import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSFailedHistoryRetentionStoreTests {
    @Test func retentionSelectsAbsoluteOldestTieAndCommitsOneRevision()
        async throws {
        let fixture = try RetentionStoreFixture()
        let oldestDate = try failedHistoryTestDate(offsetMilliseconds: 10)
        let firstTie = try failedHistoryTestEntry(
            index: 1,
            createdAt: oldestDate
        )
        let lastTie = try failedHistoryTestEntry(
            index: 2,
            createdAt: oldestDate
        )
        let rows = try [
            failedHistoryTestEntry(index: 5),
            failedHistoryTestEntry(index: 4),
            failedHistoryTestEntry(index: 3),
            firstTie,
            lastTie,
        ]
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 8,
                entries: IOSFailedHistoryValidation.sortedEntries(rows),
                audioCleanup: []
            )
        )

        try await fixture.gate.perform { lease in
            let preparation = try await fixture.preparation(
                index: 50,
                lease: lease
            )
            let authorization = try #require(
                try await fixture.store.prepareRetention(for: preparation)
            )
            #expect(authorization.candidate == lastTie)
            #expect(
                authorization.tombstone.queuedAt
                    == preparation.intendedRow.updatedAt
            )
            let proof = try fixture.validatedAudio(for: authorization)
            _ = try await fixture.store.commitPendingJournalRetirement(
                preparation,
                validatedEviction: proof
            )
        }

        let outcome = try #require(try await fixture.store.load())
        #expect(outcome.revision == 9)
        #expect(outcome.entries.count == 5)
        #expect(!outcome.entries.contains(lastTie))
        #expect(outcome.entries.contains(where: {
            $0.ownershipState == .pendingJournalRetirement
        }))
        #expect(outcome.audioCleanup.map(\.attemptID) == [lastTie.attemptID])
        #expect(fixture.failedFileSystem.events.filter {
            $0 == "replace"
        }.count == 1)
    }

    @Test func retentionNeverSkipsUnsafeOldestAndRequiresTombstoneCapacity()
        async throws {
        let fixture = try RetentionStoreFixture()
        let retryDate = try failedHistoryTestDate(offsetMilliseconds: 12)
        let retry = try failedHistoryTestRetryOperation(
            index: 8,
            createdAt: retryDate
        )
        let unsafeOldest = try failedHistoryTestEntry(
            index: 1,
            createdAt: try failedHistoryTestDate(offsetMilliseconds: 10),
            updatedAt: retryDate,
            retryCount: 1,
            retryOperation: retry
        )
        let rows = try (2...5).map { try failedHistoryTestEntry(index: $0) }
            + [unsafeOldest]
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 2,
                entries: IOSFailedHistoryValidation.sortedEntries(rows),
                audioCleanup: []
            )
        )
        await #expect(throws: IOSFailedHistoryError.invalidTransition) {
            try await fixture.gate.perform { lease in
                let preparation = try await fixture.preparation(
                    index: 51,
                    lease: lease
                )
                _ = try await fixture.store.prepareRetention(
                    for: preparation
                )
            }
        }

        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 3,
                entries: IOSFailedHistoryValidation.sortedEntries(
                    try (1...5).map {
                        try failedHistoryTestEntry(index: $0)
                    }
                ),
                audioCleanup: try (20...24).map {
                    try failedHistoryTestAudioCleanup(index: $0)
                }
            )
        )
        await #expect(throws: IOSFailedHistoryError.capacityExceeded) {
            try await fixture.gate.perform { lease in
                let preparation = try await fixture.preparation(
                    index: 52,
                    lease: lease
                )
                _ = try await fixture.store.prepareRetention(
                    for: preparation
                )
            }
        }
    }

    @Test func deleteRequiresValidatedAudioAndAtomicallyQueuesTombstone()
        async throws {
        let fixture = try RetentionStoreFixture()
        let row = try failedHistoryTestEntry(index: 6)
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 4,
                entries: [row],
                audioCleanup: []
            )
        )

        try await fixture.gate.perform { lease in
            let authorization = try await fixture.store.prepareDelete(
                attemptID: row.attemptID,
                operationLeaseAuthorization: lease
            )
            #expect(authorization.candidate == row)
            #expect(authorization.purpose == .delete)
            #expect(
                authorization.tombstone.queuedAt == fixture.now
            )
            let invalidLease = RetentionAudioLease(
                row: try failedHistoryTestEntry(index: 99)
            )
            #expect(
                IOSFailedHistoryValidatedRowAudio(
                    testingAuthorization: authorization,
                    audioLease: invalidLease
                ) == nil
            )
            let receipt = try await fixture.store.commitDelete(
                using: fixture.validatedAudio(for: authorization)
            )
            #expect(receipt.tombstone == authorization.tombstone)
            #expect(String(describing: receipt).contains("redacted"))
        }

        let outcome = try #require(try await fixture.store.load())
        #expect(outcome.revision == 5)
        #expect(outcome.entries.isEmpty)
        #expect(outcome.audioCleanup.count == 1)
    }

    @Test func deleteUncertaintyRequiresFreshAudioOnlyWhenSourceVisible()
        async throws {
        for outcomeVisible in [false, true] {
            let fixture = try RetentionStoreFixture()
            let row = try failedHistoryTestEntry(
                index: outcomeVisible ? 71 : 70
            )
            try fixture.install(
                IOSFailedHistoryEnvelope(
                    revision: 10,
                    entries: [row],
                    audioCleanup: []
                )
            )
            fixture.failedFileSystem.replaceFailure = .init(
                error: .commitUncertain,
                commitBeforeThrowing: outcomeVisible
            )
            await #expect(throws: IOSFailedHistoryError.commitUncertain) {
                try await fixture.gate.perform { lease in
                    let authorization = try await fixture.store.prepareDelete(
                        attemptID: row.attemptID,
                        operationLeaseAuthorization: lease
                    )
                    _ = try await fixture.store.commitDelete(
                        using: fixture.validatedAudio(for: authorization)
                    )
                }
            }
            #expect(fixture.mutationInterlock.isBlocked)

            try await fixture.gate.perform { lease in
                await #expect(throws: IOSFailedHistoryError.commitUncertain) {
                    _ = try await fixture.store
                        .refreshRetainedDeleteValidationAuthorization(
                            attemptID: UUID(),
                            operationLeaseAuthorization: lease
                        )
                }
                if outcomeVisible {
                    let refreshed = try await fixture.store
                        .refreshRetainedDeleteValidationAuthorization(
                            attemptID: row.attemptID,
                            operationLeaseAuthorization: lease
                        )
                    #expect(refreshed == nil)
                    _ = try await fixture.store.reconcileDeleteCommit(
                        validatedAudio: nil,
                        operationLeaseAuthorization: lease
                    )
                } else {
                    await #expect(
                        throws: IOSFailedHistoryError.invalidTransition
                    ) {
                        _ = try await fixture.store.reconcileDeleteCommit(
                            validatedAudio: nil,
                            operationLeaseAuthorization: lease
                        )
                    }
                    let refreshed = try await fixture.store
                        .refreshRetainedDeleteValidationAuthorization(
                            attemptID: row.attemptID,
                            operationLeaseAuthorization: lease
                        )
                    _ = try await fixture.store.reconcileDeleteCommit(
                        validatedAudio: fixture.validatedAudio(
                            for: try #require(refreshed)
                        ),
                        operationLeaseAuthorization: lease
                    )
                }
            }
            #expect(!fixture.mutationInterlock.isBlocked)
        }
    }
}

private final class RetentionStoreFixture: @unchecked Sendable {
    let now: Date
    let context: IOSAcceptedHistoryCoordinatorProcessContext
    let gate: IOSPersistenceOperationGate
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let pendingStoreIdentity = IOSPendingRecordingStoreIdentity()
    let mutationInterlock = IOSFailedHistoryMutationInterlock()
    let failedFileSystem = FailedHistoryFakeFileSystem()
    let store: IOSFailedHistoryStore
    private let rootURL: URL

    init() throws {
        now = try failedHistoryTestDate(offsetMilliseconds: 9_999)
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "failed-retention-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: false
        )
        context = IOSAcceptedHistoryCoordinatorProcessContextRegistry.shared
            .context(for: rootURL)
        gate = context.operationGate
        ownerIdentity = context.ownerIdentity
        store = IOSFailedHistoryStore(
            journal: FoundationIOSFailedHistoryJournalRepository(
                fileSystem: failedFileSystem
            ),
            capabilityOwnerIdentity: ownerIdentity,
            operationGateIdentity: gate.identity,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryGuard: context.repositoryGuard,
            mutationInterlock: mutationInterlock,
            now: { [now] in now }
        )
    }

    deinit { try? FileManager.default.removeItem(at: rootURL) }

    func install(_ envelope: IOSFailedHistoryEnvelope) throws {
        failedFileSystem.install(try IOSFailedHistoryWireCodec.encode(envelope))
        failedFileSystem.resetEvents()
    }

    func preparation(
        index: Int,
        lease: IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingFailedHistoryTransferPreparation {
        let attemptID = failedHistoryTestUUID(namespace: 0x75, index: index)
        let recording = try IOSPendingRecording(
            attemptID: attemptID,
            audioRelativeIdentifier: IOSPendingRecordingStorageLocation
                .relativeAudioIdentifier(for: attemptID, format: .m4a),
            createdAt: failedHistoryTestDate(
                offsetMilliseconds: Int64(index * 100)
            ),
            updatedAt: failedHistoryTestDate(
                offsetMilliseconds: Int64(index * 100 + 40)
            ),
            phase: .awaitingRecovery,
            outputIntent: .standard,
            transcriptionID: nil,
            transcriptionModel: "gpt-4o-mini-transcribe",
            transcriptionLanguageCode: "en",
            durationMilliseconds: 1_250,
            byteCount: 4_096
        )
        let row = try IOSFailedHistoryEntry(
            attemptID: attemptID,
            createdAt: recording.createdAt,
            updatedAt: failedHistoryTestDate(
                offsetMilliseconds: Int64(index * 100 + 70)
            ),
            policyGeneration: 1,
            failureCategory: .networkFailure,
            pipelineStage: .transcription,
            retryCount: 0,
            outputIntent: .standard,
            transcriptionModel: recording.transcriptionModel,
            transcriptionLanguageCode: recording.transcriptionLanguageCode,
            durationMilliseconds: recording.durationMilliseconds,
            byteCount: recording.byteCount,
            audioRelativeIdentifier: recording.audioRelativeIdentifier,
            ownershipState: .pendingJournalRetirement,
            retryOperation: nil
        )
        let policy = try await policyReceipt()
        return try #require(
            IOSPendingFailedHistoryTransferPreparation(
                mint: IOSPendingFailedHistoryTransferPreparationMint(
                    testingToken: ()
                ),
                pendingSnapshot: IOSPendingRecordingJournalMetadataSnapshot(
                    testingRecording: recording,
                    testingRevision: UInt64(index)
                ),
                intendedRow: row,
                audioLease: RetentionAudioLease(recording: recording),
                pendingStoreIdentity: pendingStoreIdentity,
                failedStoreIdentity: store.storeIdentity,
                ownerIdentity: ownerIdentity,
                repositoryBinding: context.repositoryBinding,
                operationLeaseAuthorization: lease,
                policyReceipt: policy
            )
        )
    }

    func validatedAudio(
        for authorization: IOSFailedHistoryRowAudioValidationAuthorization
    ) throws -> IOSFailedHistoryValidatedRowAudio {
        try #require(
            IOSFailedHistoryValidatedRowAudio(
                testingAuthorization: authorization,
                audioLease: RetentionAudioLease(row: authorization.candidate)
            )
        )
    }

    private func policyReceipt() async throws -> IOSHistoryPolicyReceipt {
        let state = try IOSHistoryPolicyState(
            revision: 1,
            historyEnabled: true,
            policyGeneration: 1
        )
        return try await IOSHistoryPolicyStore(
            journal: RetentionPolicyJournal(state: state),
            capabilityOwnerIdentity: ownerIdentity
        ).confirm(expected: IOSHistoryPolicyExpectation(state: state))
    }
}

private final class RetentionAudioLease:
    IOSPendingRecordingPublishedAudioLease,
    @unchecked Sendable {
    let relativeIdentifier: String
    let audioArtifact: AudioRecordingArtifact
    let durationMilliseconds: Int64

    init(row: IOSFailedHistoryEntry) {
        relativeIdentifier = row.audioRelativeIdentifier
        durationMilliseconds = row.durationMilliseconds
        audioArtifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/retention.m4a"),
            duration: Double(row.durationMilliseconds) / 1_000,
            byteCount: row.byteCount
        )
    }

    init(recording: IOSPendingRecording) {
        relativeIdentifier = recording.audioRelativeIdentifier
        durationMilliseconds = recording.durationMilliseconds
        audioArtifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/retention.m4a"),
            duration: Double(recording.durationMilliseconds) / 1_000,
            byteCount: recording.byteCount
        )
    }

    func revalidate() async throws -> AudioRecordingArtifact { audioArtifact }
    func read(atOffset: Int64, maximumByteCount: Int) async throws -> Data {
        _ = atOffset
        _ = maximumByteCount
        return Data()
    }
    func release() {}
}

private final class RetentionPolicyJournal:
    IOSHistoryPolicyJournalStoring,
    @unchecked Sendable {
    private var snapshot: IOSHistoryPolicyJournalSnapshot
    private var nextToken: UInt64 = 2

    init(state: IOSHistoryPolicyState) {
        snapshot = IOSHistoryPolicyJournalSnapshot(
            state: state,
            fileRevision: IOSStrictProtectedRecordFileRevision(testingToken: 1)
        )
    }

    func load() throws -> IOSHistoryPolicyJournalSnapshot? { snapshot }
    func replace(
        _ state: IOSHistoryPolicyState,
        expected: IOSHistoryPolicyJournalSnapshot
    ) throws -> IOSHistoryPolicyJournalSnapshot {
        guard snapshot == expected else {
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }
        snapshot = IOSHistoryPolicyJournalSnapshot(
            state: state,
            fileRevision: IOSStrictProtectedRecordFileRevision(
                testingToken: nextToken
            )
        )
        nextToken += 1
        return snapshot
    }
    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        _ = now
        return .empty
    }
}
