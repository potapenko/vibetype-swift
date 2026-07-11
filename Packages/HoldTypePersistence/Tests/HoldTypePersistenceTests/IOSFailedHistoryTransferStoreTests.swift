import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSFailedHistoryTransferStoreTests {
    @Test func pendingStoreBindingIsOneTimeAndRedacted() throws {
        let fixture = try FailedTransferStoreFixture()
        #expect(
            fixture.store.bindExpectedPendingStoreIdentity(
                fixture.pendingStoreIdentity
            )
        )
        #expect(
            !fixture.store.bindExpectedPendingStoreIdentity(
                IOSPendingRecordingStoreIdentity()
            )
        )
        #expect(
            String(describing: fixture.pendingStoreIdentity)
                == "IOSPendingRecordingStoreIdentity(redacted)"
        )
    }

    @Test func appendThenReadyChangesOnlyOwnershipAndRootRevision()
        async throws {
        let fixture = try FailedTransferStoreFixture()
        let values = try await fixture.makeValues(index: 1)
        let audioLease = FailedTransferAudioLease(recording: values.recording)

        try await fixture.gate.perform { lease in
            let preparation = try #require(
                IOSPendingFailedHistoryTransferPreparation(
                    mint: IOSPendingFailedHistoryTransferPreparationMint(
                        testingToken: ()
                    ),
                    pendingSnapshot: values.pendingSnapshot,
                    intendedRow: values.row,
                    audioLease: audioLease,
                    pendingStoreIdentity: fixture.pendingStoreIdentity,
                    failedStoreIdentity: fixture.store.storeIdentity,
                    ownerIdentity: fixture.ownerIdentity,
                    repositoryBinding: fixture.repositoryBinding,
                    operationLeaseAuthorization: lease,
                    policyReceipt: values.policyReceipt
                )
            )
            let authority = try await fixture.store
                .commitPendingJournalRetirement(preparation)
            #expect(authority.origin == .committed(values.pendingSnapshot))
            #expect(String(describing: authority).contains("redacted"))
            #expect(authority.customMirror.children.isEmpty)

            let receipt = try fixture.removePendingMetadata(
                authority: authority,
                source: values.pendingSnapshot
            )
            try await fixture.store.commitReady(using: receipt)
        }

        let envelope = try #require(try await fixture.store.load())
        let ready = try #require(envelope.entries.first)
        #expect(envelope.revision == 2)
        #expect(ready.ownershipState == .ready)
        #expect(ready.updatedAt == values.row.updatedAt)
        #expect(ready.createdAt == values.row.createdAt)
        #expect(ready.policyGeneration == values.row.policyGeneration)
        #expect(ready.failureCategory == values.row.failureCategory)
        #expect(ready.pipelineStage == values.row.pipelineStage)
        #expect(ready.retryCount == values.row.retryCount)
        #expect(ready.outputIntent == values.row.outputIntent)
        #expect(ready.transcriptionModel == values.row.transcriptionModel)
        #expect(
            ready.transcriptionLanguageCode
                == values.row.transcriptionLanguageCode
        )
        #expect(
            ready.audioRelativeIdentifier
                == values.row.audioRelativeIdentifier
        )
        #expect(ready.durationMilliseconds == values.row.durationMilliseconds)
        #expect(ready.byteCount == values.row.byteCount)
        #expect(ready.retryOperation == nil)
        #expect(audioLease.revalidationCount == 1)
        #expect(audioLease.readCount == 0)
    }

    @Test func appendRejectsCapacityExistingTransferAndCollisions()
        async throws {
        for scenario in FailedTransferRejectionScenario.allCases {
            let fixture = try FailedTransferStoreFixture()
            let values = try await fixture.makeValues(index: 20)
            try fixture.installFailedEnvelope(
                scenario.envelope(for: values)
            )
            fixture.failedFileSystem.resetEvents()

            await #expect(throws: scenario.expectedError) {
                try await fixture.gate.perform { lease in
                    let preparation = try #require(
                        fixture.preparation(
                            values: values,
                            lease: lease
                        )
                    )
                    return try await fixture.store
                        .commitPendingJournalRetirement(preparation)
                }
            }
            #expect(!fixture.failedFileSystem.events.contains("create"))
            #expect(!fixture.failedFileSystem.events.contains("replace"))
        }
    }

    @Test func appendRejectsPolicyStoreRootAndLeaseBeforeMutationIO()
        async throws {
        let fixture = try FailedTransferStoreFixture()
        let values = try await fixture.makeValues(index: 30)

        let disabledPolicy = try await failedTransferPolicyReceipt(
            generation: values.row.policyGeneration,
            enabled: false,
            ownerIdentity: fixture.ownerIdentity
        )
        try await fixture.gate.perform { lease in
            #expect(
                fixture.preparation(
                    values: values,
                    lease: lease,
                    policyReceipt: disabledPolicy
                ) == nil
            )
        }
        let stalePolicy = try await failedTransferPolicyReceipt(
            generation: values.row.policyGeneration + 1,
            enabled: true,
            ownerIdentity: fixture.ownerIdentity
        )
        try await fixture.gate.perform { lease in
            #expect(
                fixture.preparation(
                    values: values,
                    lease: lease,
                    policyReceipt: stalePolicy
                ) == nil
            )
        }

        let foreignStore = try FailedTransferStoreFixture(
            operationGate: fixture.gate,
            ownerIdentity: fixture.ownerIdentity,
            repositoryContext: fixture.context
        )
        let preparation = try await fixture.gate.perform { lease in
            try #require(fixture.preparation(values: values, lease: lease))
        }
        fixture.failedFileSystem.resetEvents()
        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            try await fixture.gate.perform { lease in
                let foreignFailedPreparation = try #require(
                    fixture.preparation(
                        values: values,
                        lease: lease,
                        failedStoreIdentity: foreignStore.store.storeIdentity
                    )
                )
                return try await fixture.store
                    .commitPendingJournalRetirement(
                        foreignFailedPreparation
                    )
            }
        }
        #expect(fixture.failedFileSystem.events.isEmpty)

        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try await fixture.store
                .commitPendingJournalRetirement(preparation)
        }
        #expect(fixture.failedFileSystem.events.isEmpty)

        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            try await fixture.gate.perform { lease in
                let foreignPreparation = try #require(
                    foreignStore.preparation(
                        values: values,
                        lease: lease,
                        failedStoreIdentity: fixture.store.storeIdentity
                    )
                )
                return try await fixture.store
                    .commitPendingJournalRetirement(foreignPreparation)
            }
        }

        let unrootedFileSystem = FailedHistoryFakeFileSystem()
        let unrootedStore = IOSFailedHistoryStore(
            journal: FoundationIOSFailedHistoryJournalRepository(
                fileSystem: unrootedFileSystem
            ),
            capabilityOwnerIdentity: fixture.ownerIdentity,
            expectedPendingStoreIdentity: fixture.pendingStoreIdentity
        )
        #expect(unrootedStore.bindOperationGateIdentity(fixture.gate.identity))
        await #expect(throws: IOSFailedHistoryError.repositoryIdentityConflict) {
            try await fixture.gate.perform { lease in
                let rootlessPreparation = try #require(
                    fixture.preparation(
                        values: values,
                        lease: lease,
                        failedStoreIdentity: unrootedStore.storeIdentity
                    )
                )
                return try await unrootedStore
                    .commitPendingJournalRetirement(rootlessPreparation)
            }
        }
        #expect(unrootedFileSystem.events.isEmpty)
    }

    @Test func relaunchAuthorityComesOnlyFromExactPendingRetirementRow()
        async throws {
        let fixture = try FailedTransferStoreFixture()
        let values = try await fixture.makeValues(index: 40)
        try fixture.installFailedEnvelope(
            IOSFailedHistoryEnvelope(
                revision: 7,
                entries: [values.row],
                audioCleanup: []
            )
        )

        try await fixture.gate.perform { lease in
            let authority = try #require(
                try await fixture.store
                    .makeRelaunchedPendingMetadataRetirementAuthority(
                        operationLeaseAuthorization: lease
                    )
            )
            #expect(authority.origin == .relaunched)
            #expect(authority.row == values.row)
            #expect(authority.failedSource.envelope.revision == 7)
        }

        try fixture.installFailedEnvelope(
            IOSFailedHistoryEnvelope(
                revision: 8,
                entries: [try readyVersion(of: values.row)],
                audioCleanup: []
            )
        )
        try await fixture.gate.perform { lease in
            let authority = try await fixture.store
                .makeRelaunchedPendingMetadataRetirementAuthority(
                    operationLeaseAuthorization: lease
                )
            #expect(authority == nil)
        }
    }

    @Test func appendUncertaintyReconcilesVisibleAndInvisibleOnFreshLease()
        async throws {
        for commitWasVisible in [false, true] {
            let fixture = try FailedTransferStoreFixture()
            let values = try await fixture.makeValues(
                index: commitWasVisible ? 51 : 50
            )
            fixture.failedFileSystem.createFailure =
                FailedHistoryFakeFileSystem.Failure(
                    error: .commitUncertain,
                    commitBeforeThrowing: commitWasVisible
                )

            let preparation = try await fixture.gate.perform { lease in
                let preparation = try #require(
                    fixture.preparation(values: values, lease: lease)
                )
                do {
                    _ = try await fixture.store
                        .commitPendingJournalRetirement(preparation)
                    Issue.record("Expected uncertain failed-row commit")
                } catch let error as IOSFailedHistoryError {
                    #expect(error == .commitUncertain)
                }
                return preparation
            }
            #expect(fixture.mutationInterlock.isBlocked)

            let authority = try await fixture.gate.perform { lease in
                #expect(
                    preparation.refresh(
                        mint: IOSPendingFailedHistoryTransferPreparationMint(
                            testingToken: ()
                        ),
                        repositoryBinding: fixture.repositoryBinding,
                        operationLeaseAuthorization: lease,
                        policyReceipt: values.policyReceipt
                    )
                )
                return try await fixture.store
                    .reconcilePendingJournalRetirementCommit(
                        operationLeaseAuthorization: lease
                    )
            }
            #expect(authority.row == values.row)
            #expect(!fixture.mutationInterlock.isBlocked)
            let envelope = try #require(try await fixture.store.load())
            #expect(envelope.revision == 1)
            #expect(envelope.entries == [values.row])
        }
    }

    @Test func definitiveAppendAbsenceProofRequiresFreshLeaseAndNoOwner()
        async throws {
        let fixture = try FailedTransferStoreFixture()
        let values = try await fixture.makeValues(index: 55)
        fixture.failedFileSystem.createFailure =
            FailedHistoryFakeFileSystem.Failure(
                error: .writeFailed,
                commitBeforeThrowing: false
            )
        let preparation = try await fixture.gate.perform { lease in
            let preparation = try #require(
                fixture.preparation(values: values, lease: lease)
            )
            do {
                _ = try await fixture.store
                    .commitPendingJournalRetirement(preparation)
                Issue.record("Expected definitive append failure")
            } catch let error as IOSFailedHistoryError {
                #expect(error == .writeFailed)
            }
            await #expect(throws: IOSFailedHistoryError.commitUncertain) {
                _ = try await fixture.store
                    .provePendingJournalRetirementAppendAbsent(
                        for: preparation,
                        operationLeaseAuthorization: lease
                    )
            }
            return preparation
        }

        try await fixture.gate.perform { lease in
            let proof = try await fixture.store
                .provePendingJournalRetirementAppendAbsent(
                    for: preparation,
                    operationLeaseAuthorization: lease
                )
            #expect(proof.preparation === preparation)
            #expect(String(describing: proof).contains("redacted"))
            #expect(proof.customMirror.children.isEmpty)
        }

        try fixture.installFailedEnvelope(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [values.row],
                audioCleanup: []
            )
        )
        await #expect(throws: IOSFailedHistoryError.collision) {
            try await fixture.gate.perform { lease in
                try await fixture.store
                    .provePendingJournalRetirementAppendAbsent(
                        for: preparation,
                        operationLeaseAuthorization: lease
                    )
            }
        }
    }

    @Test func readyUncertaintyReprovesAbsenceAndConfirmsVisibleOutcome()
        async throws {
        for commitWasVisible in [false, true] {
            let fixture = try FailedTransferStoreFixture()
            let values = try await fixture.makeValues(
                index: commitWasVisible ? 61 : 60
            )

            try await fixture.gate.perform { lease in
                let preparation = try #require(
                    fixture.preparation(values: values, lease: lease)
                )
                let authority = try await fixture.store
                    .commitPendingJournalRetirement(preparation)
                let receipt = try fixture.removePendingMetadata(
                    authority: authority,
                    source: values.pendingSnapshot
                )
                fixture.failedFileSystem.replaceFailure =
                    FailedHistoryFakeFileSystem.Failure(
                        error: .commitUncertain,
                        commitBeforeThrowing: commitWasVisible
                    )
                await #expect(throws: IOSFailedHistoryError.commitUncertain) {
                    try await fixture.store.commitReady(using: receipt)
                }
            }
            #expect(fixture.mutationInterlock.isBlocked)

            try await fixture.gate.perform { lease in
                let classification = try await fixture.store
                    .classifyReadyCommitUncertainty(
                        operationLeaseAuthorization: lease
                    )
                if commitWasVisible {
                    guard case .readyOutcomeConfirmation = classification else {
                        Issue.record("Expected visible ready outcome")
                        return
                    }
                } else {
                    guard case .retryReadyCommit = classification else {
                        Issue.record("Expected retryable ready source")
                        return
                    }
                }
                #expect(
                    classification.authority.origin
                        == .readyOutcomeConfirmation
                )
                #expect(
                    String(describing: classification)
                        == "IOSFailedHistoryReadyCommitUncertainty(redacted)"
                )
                let receipt = try fixture.provePendingMetadataAbsent(
                    authority: classification.authority
                )
                try await fixture.store.commitReady(using: receipt)
            }

            #expect(!fixture.mutationInterlock.isBlocked)
            let envelope = try #require(try await fixture.store.load())
            let row = try #require(envelope.entries.first)
            #expect(envelope.revision == 2)
            #expect(row.ownershipState == .ready)
            #expect(row.updatedAt == values.row.updatedAt)
        }
    }

    @Test func ownershipProbeFailsClosedForRowsTombstonesAndUncertainty()
        async throws {
        let fixture = try FailedTransferStoreFixture()
        let values = try await fixture.makeValues(index: 70)
        let differentKey = IOSFailedHistoryPendingOwnershipKey(
            recording: try failedTransferPendingRecording(index: 71)
        )

        try await fixture.gate.perform { lease in
            let proof = try await fixture.store.provePendingOwnershipAbsent(
                for: differentKey,
                expectedPendingStoreIdentity: fixture.pendingStoreIdentity,
                operationLeaseAuthorization: lease
            )
            #expect(proof.pendingKey == differentKey)
            #expect(String(describing: proof).contains("redacted"))
        }

        for envelope in [
            try IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [values.row],
                audioCleanup: []
            ),
            try IOSFailedHistoryEnvelope(
                revision: 2,
                entries: [try readyVersion(of: values.row)],
                audioCleanup: []
            ),
            try IOSFailedHistoryEnvelope(
                revision: 3,
                entries: [],
                audioCleanup: [
                    try IOSFailedHistoryAudioCleanup(
                        attemptID: values.row.attemptID,
                        policyGeneration: values.row.policyGeneration,
                        queuedAt: values.row.updatedAt,
                        audioRelativeIdentifier:
                            values.row.audioRelativeIdentifier,
                        byteCount: values.row.byteCount
                    ),
                ]
            ),
        ] {
            try fixture.installFailedEnvelope(envelope)
            await #expect(throws: IOSFailedHistoryError.collision) {
                try await fixture.gate.perform { lease in
                    try await fixture.store.provePendingOwnershipAbsent(
                        for: IOSFailedHistoryPendingOwnershipKey(
                            recording: values.recording
                        ),
                        expectedPendingStoreIdentity:
                            fixture.pendingStoreIdentity,
                        operationLeaseAuthorization: lease
                    )
                }
            }
        }

        let uncertain = try FailedTransferStoreFixture()
        let uncertainValues = try await uncertain.makeValues(index: 72)
        uncertain.failedFileSystem.createFailure =
            FailedHistoryFakeFileSystem.Failure(
                error: .commitUncertain,
                commitBeforeThrowing: false
            )
        await #expect(throws: IOSFailedHistoryError.commitUncertain) {
            try await uncertain.gate.perform { lease in
                let preparation = try #require(
                    uncertain.preparation(
                        values: uncertainValues,
                        lease: lease
                    )
                )
                return try await uncertain.store
                    .commitPendingJournalRetirement(preparation)
            }
        }
        await #expect(throws: IOSFailedHistoryError.commitUncertain) {
            try await uncertain.gate.perform { lease in
                try await uncertain.store.provePendingOwnershipAbsent(
                    for: differentKey,
                    expectedPendingStoreIdentity:
                        uncertain.pendingStoreIdentity,
                    operationLeaseAuthorization: lease
                )
            }
        }
    }
}

private enum FailedTransferRejectionScenario: CaseIterable {
    case entryCapacity
    case cleanupCapacity
    case existingPendingRetirement
    case rowCollision
    case cleanupCollision

    var expectedError: IOSFailedHistoryError {
        switch self {
        case .entryCapacity, .cleanupCapacity: .capacityExceeded
        case .existingPendingRetirement: .slotOccupied
        case .rowCollision, .cleanupCollision: .collision
        }
    }

    func envelope(
        for values: FailedTransferStoreFixture.Values
    ) throws -> IOSFailedHistoryEnvelope {
        switch self {
        case .entryCapacity:
            let entries = try (1...5).map {
                try failedHistoryTestEntry(index: 100 + $0)
            }
            return try IOSFailedHistoryEnvelope(
                revision: 9,
                entries: IOSFailedHistoryValidation.sortedEntries(entries),
                audioCleanup: []
            )
        case .cleanupCapacity:
            return try IOSFailedHistoryEnvelope(
                revision: 9,
                entries: [],
                audioCleanup: (1...5).map {
                    try failedHistoryTestAudioCleanup(index: 100 + $0)
                }
            )
        case .existingPendingRetirement:
            return try IOSFailedHistoryEnvelope(
                revision: 9,
                entries: [
                    try failedHistoryTestEntry(
                        index: 100,
                        ownershipState: .pendingJournalRetirement
                    ),
                ],
                audioCleanup: []
            )
        case .rowCollision:
            return try IOSFailedHistoryEnvelope(
                revision: 9,
                entries: [try readyVersion(of: values.row)],
                audioCleanup: []
            )
        case .cleanupCollision:
            return try IOSFailedHistoryEnvelope(
                revision: 9,
                entries: [],
                audioCleanup: [
                    try IOSFailedHistoryAudioCleanup(
                        attemptID: values.row.attemptID,
                        policyGeneration: values.row.policyGeneration,
                        queuedAt: values.row.updatedAt,
                        audioRelativeIdentifier:
                            values.row.audioRelativeIdentifier,
                        byteCount: values.row.byteCount
                    ),
                ]
            )
        }
    }
}

private final class FailedTransferStoreFixture: @unchecked Sendable {
    struct Values {
        let recording: IOSPendingRecording
        let pendingSnapshot: IOSPendingRecordingJournalMetadataSnapshot
        let row: IOSFailedHistoryEntry
        let policyReceipt: IOSHistoryPolicyReceipt
    }

    let applicationSupportDirectoryURL: URL
    let context: IOSAcceptedHistoryCoordinatorProcessContext
    let gate: IOSPersistenceOperationGate
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let pendingStoreIdentity: IOSPendingRecordingStoreIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let mutationInterlock = IOSFailedHistoryMutationInterlock()
    let failedFileSystem = FailedHistoryFakeFileSystem()
    let store: IOSFailedHistoryStore
    private let pendingJournalFileSystem:
        FoundationIOSPendingRecordingJournalFileSystem
    private let pendingJournalRepository:
        FoundationIOSPendingRecordingJournalRepository

    init(
        operationGate: IOSPersistenceOperationGate? = nil,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity? = nil,
        repositoryContext: IOSAcceptedHistoryCoordinatorProcessContext? = nil
    ) throws {
        if let repositoryContext {
            context = repositoryContext
            applicationSupportDirectoryURL =
                repositoryContext.applicationSupportDirectoryURL
        } else {
            applicationSupportDirectoryURL = FileManager.default
                .temporaryDirectory
                .appendingPathComponent(
                    "failed-transfer-\(UUID().uuidString)",
                    isDirectory: true
                )
            try FileManager.default.createDirectory(
                at: applicationSupportDirectoryURL,
                withIntermediateDirectories: false
            )
            context = IOSAcceptedHistoryCoordinatorProcessContextRegistry
                .shared.context(for: applicationSupportDirectoryURL)
        }
        gate = operationGate ?? context.operationGate
        self.ownerIdentity = ownerIdentity ?? context.ownerIdentity
        pendingStoreIdentity = IOSPendingRecordingStoreIdentity()
        repositoryBinding = context.repositoryBinding
        let repository = FoundationIOSFailedHistoryJournalRepository(
            fileSystem: failedFileSystem
        )
        store = IOSFailedHistoryStore(
            journal: repository,
            capabilityOwnerIdentity: self.ownerIdentity,
            operationGateIdentity: gate.identity,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryGuard: context.repositoryGuard,
            mutationInterlock: mutationInterlock,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        pendingJournalFileSystem =
            FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL:
                    applicationSupportDirectoryURL,
                expectedRepositoryRoot:
                    repositoryBinding.physicalRootIdentity
            )
        pendingJournalRepository =
            FoundationIOSPendingRecordingJournalRepository(
                fileSystem: pendingJournalFileSystem
            )
    }

    deinit {
        // A shared-context fixture can be owned by another fixture.
        guard context.applicationSupportDirectoryURL
                == applicationSupportDirectoryURL else { return }
        try? FileManager.default.removeItem(
            at: applicationSupportDirectoryURL
        )
    }

    func makeValues(index: Int) async throws -> Values {
        let recording = try failedTransferPendingRecording(index: index)
        try pendingJournalRepository.create(
            recording,
            expectedRepositoryRoot: repositoryBinding.physicalRootIdentity
        )
        let pendingSnapshot = try #require(
            try pendingJournalRepository.loadMetadataSnapshot(
                authorization:
                    IOSPendingRecordingMetadataRetirementAuthorization(
                        testingToken: UInt64(index)
                    )
            )
        )
        let policyGeneration = Int64(index + 1)
        let policyReceipt = try await failedTransferPolicyReceipt(
            generation: policyGeneration,
            enabled: true,
            ownerIdentity: ownerIdentity
        )
        let row = try IOSFailedHistoryEntry(
            attemptID: recording.attemptID,
            createdAt: recording.createdAt,
            updatedAt: try failedHistoryTestDate(
                offsetMilliseconds: Int64(index * 100 + 70)
            ),
            policyGeneration: policyGeneration,
            failureCategory: .networkFailure,
            pipelineStage: .transcription,
            retryCount: 0,
            outputIntent: recording.outputIntent,
            transcriptionModel: recording.transcriptionModel,
            transcriptionLanguageCode:
                recording.transcriptionLanguageCode,
            durationMilliseconds: recording.durationMilliseconds,
            byteCount: recording.byteCount,
            audioRelativeIdentifier: recording.audioRelativeIdentifier,
            ownershipState: .pendingJournalRetirement,
            retryOperation: nil
        )
        return Values(
            recording: recording,
            pendingSnapshot: pendingSnapshot,
            row: row,
            policyReceipt: policyReceipt
        )
    }

    func preparation(
        values: Values,
        lease: IOSPersistenceOperationLeaseAuthorization,
        policyReceipt: IOSHistoryPolicyReceipt? = nil,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity? = nil
    ) -> IOSPendingFailedHistoryTransferPreparation? {
        IOSPendingFailedHistoryTransferPreparation(
            mint: IOSPendingFailedHistoryTransferPreparationMint(
                testingToken: ()
            ),
            pendingSnapshot: values.pendingSnapshot,
            intendedRow: values.row,
            audioLease: FailedTransferAudioLease(
                recording: values.recording
            ),
            pendingStoreIdentity: pendingStoreIdentity,
            failedStoreIdentity: failedStoreIdentity ?? store.storeIdentity,
            ownerIdentity: ownerIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: lease,
            policyReceipt: policyReceipt ?? values.policyReceipt
        )
    }

    func removePendingMetadata(
        authority: IOSFailedHistoryPendingMetadataRetirementAuthority,
        source: IOSPendingRecordingJournalMetadataSnapshot
    ) throws -> IOSPendingRecordingMetadataAbsenceReceipt {
        let evidence = try pendingJournalRepository.removeMetadata(
            expected: source,
            expectedRepositoryRoot: repositoryBinding.physicalRootIdentity,
            authorization: IOSPendingRecordingMetadataRetirementAuthorization(
                testingToken: 10_001
            )
        )
        return try #require(
            IOSPendingRecordingMetadataAbsenceReceipt(
                mint: IOSPendingRecordingMetadataAbsenceReceiptMint(
                    testingToken: ()
                ),
                issuerStoreIdentity: pendingStoreIdentity,
                authority: authority,
                outcome: .removed(source: source, evidence: evidence)
            )
        )
    }

    func provePendingMetadataAbsent(
        authority: IOSFailedHistoryPendingMetadataRetirementAuthority
    ) throws -> IOSPendingRecordingMetadataAbsenceReceipt {
        let evidence = try pendingJournalRepository.proveMetadataAbsent(
            expectedRepositoryRoot: repositoryBinding.physicalRootIdentity,
            authorization: IOSPendingRecordingMetadataRetirementAuthorization(
                testingToken: 10_002
            )
        )
        return try #require(
            IOSPendingRecordingMetadataAbsenceReceipt(
                mint: IOSPendingRecordingMetadataAbsenceReceiptMint(
                    testingToken: ()
                ),
                issuerStoreIdentity: pendingStoreIdentity,
                authority: authority,
                outcome: .alreadyAbsent(evidence: evidence)
            )
        )
    }

    func installFailedEnvelope(_ envelope: IOSFailedHistoryEnvelope) throws {
        failedFileSystem.install(try IOSFailedHistoryWireCodec.encode(envelope))
        failedFileSystem.resetEvents()
    }
}

private final class FailedTransferAudioLease:
    IOSPendingRecordingPublishedAudioLease,
    @unchecked Sendable {
    let relativeIdentifier: String
    let audioArtifact: AudioRecordingArtifact
    let durationMilliseconds: Int64
    private let lock = NSLock()
    private var storedRevalidationCount = 0
    private var storedReadCount = 0

    init(recording: IOSPendingRecording) {
        relativeIdentifier = recording.audioRelativeIdentifier
        audioArtifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/failed-transfer.m4a"),
            duration: Double(recording.durationMilliseconds) / 1_000,
            byteCount: recording.byteCount
        )
        durationMilliseconds = recording.durationMilliseconds
    }

    var revalidationCount: Int {
        lock.withLock { storedRevalidationCount }
    }
    var readCount: Int { lock.withLock { storedReadCount } }

    func revalidate() async throws -> AudioRecordingArtifact {
        lock.withLock { storedRevalidationCount += 1 }
        return audioArtifact
    }

    func read(
        atOffset offset: Int64,
        maximumByteCount: Int
    ) async throws -> Data {
        lock.withLock { storedReadCount += 1 }
        return Data()
    }

    func release() {}
}

private final class FailedTransferPolicyJournal:
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

private func failedTransferPolicyReceipt(
    generation: Int64,
    enabled: Bool,
    ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
) async throws -> IOSHistoryPolicyReceipt {
    let state = try IOSHistoryPolicyState(
        revision: generation,
        historyEnabled: enabled,
        policyGeneration: generation
    )
    return try await IOSHistoryPolicyStore(
        journal: FailedTransferPolicyJournal(state: state),
        capabilityOwnerIdentity: ownerIdentity
    ).confirm(expected: IOSHistoryPolicyExpectation(state: state))
}

private func failedTransferPendingRecording(
    index: Int
) throws -> IOSPendingRecording {
    let attemptID = failedHistoryTestUUID(namespace: 0x75, index: index)
    return try IOSPendingRecording(
        attemptID: attemptID,
        audioRelativeIdentifier: IOSPendingRecordingStorageLocation
            .relativeAudioIdentifier(for: attemptID, format: .m4a),
        createdAt: failedHistoryTestDate(
            offsetMilliseconds: Int64(index * 100)
        ),
        updatedAt: failedHistoryTestDate(
            offsetMilliseconds: Int64(index * 100 + 50)
        ),
        phase: .awaitingRecovery,
        outputIntent: .standard,
        transcriptionID: nil,
        transcriptionModel: "gpt-4o-mini-transcribe",
        transcriptionLanguageCode: "en",
        durationMilliseconds: 1_250,
        byteCount: 4_096
    )
}

private func readyVersion(
    of row: IOSFailedHistoryEntry
) throws -> IOSFailedHistoryEntry {
    try IOSFailedHistoryEntry(
        attemptID: row.attemptID,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        policyGeneration: row.policyGeneration,
        failureCategory: row.failureCategory,
        pipelineStage: row.pipelineStage,
        retryCount: row.retryCount,
        outputIntent: row.outputIntent,
        transcriptionModel: row.transcriptionModel,
        transcriptionLanguageCode: row.transcriptionLanguageCode,
        durationMilliseconds: row.durationMilliseconds,
        byteCount: row.byteCount,
        audioRelativeIdentifier: row.audioRelativeIdentifier,
        ownershipState: .ready,
        retryOperation: row.retryOperation
    )
}
