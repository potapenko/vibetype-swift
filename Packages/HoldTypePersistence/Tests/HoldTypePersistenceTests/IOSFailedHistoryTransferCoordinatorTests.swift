import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSFailedHistoryTransferCoordinatorTests {
    @Test func happyPathRetiresOnlyPendingMetadataAndPreservesExactAudio()
        async throws {
        let fixture = try FailedTransferCoordinatorFixture()
        let coordinator = fixture.makeCoordinator()
        try await fixture.establishEnabledPolicy(using: coordinator)
        let recording = try await fixture.prepareAwaitingRecoveryRecording()
        let audioIdentityBefore = try fixture.audioIdentity(for: recording)

        let result = try await coordinator.transferPendingRecordingFailure(
            expected: IOSPendingRecordingCASExpectation(recording: recording),
            failure: .recoverableNetworkFailure
        )

        #expect(result == .transferred)
        let envelope = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        let row = try #require(envelope.entries.first)
        #expect(envelope.revision == 2)
        #expect(envelope.entries.count == 1)
        #expect(row.attemptID == recording.attemptID)
        #expect(row.ownershipState == .ready)
        #expect(row.audioRelativeIdentifier == recording.audioRelativeIdentifier)
        #expect(row.byteCount == recording.byteCount)
        #expect(try fixture.rawPendingRecording() == nil)
        #expect(try fixture.audioIdentity(for: recording) == audioIdentityBefore)
    }

    @Test func relaunchReconcilesDurablePendingRetirementWithoutProviderWork()
        async throws {
        let fixture = try FailedTransferCoordinatorFixture()
        let coordinator = fixture.makeCoordinator()
        try await fixture.establishEnabledPolicy(using: coordinator)
        let recording = try await fixture.prepareAwaitingRecoveryRecording()
        let audioIdentityBefore = try fixture.audioIdentity(for: recording)

        try await fixture.stagePendingJournalRetirement(for: recording)

        let stagedEnvelope = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        #expect(stagedEnvelope.revision == 1)
        #expect(stagedEnvelope.entries.first?.ownershipState == .pendingJournalRetirement)
        #expect(try fixture.rawPendingRecording() == recording)
        await #expect(throws: IOSPendingRecordingError.localRecoveryPending) {
            _ = try await fixture.context.pendingRecordingStore.load()
        }
        await #expect(throws: IOSPendingRecordingError.localRecoveryPending) {
            _ = try await fixture.context.pendingRecordingStore.discard(
                expected: IOSPendingRecordingCASExpectation(
                    recording: recording
                )
            )
        }
        #expect(try fixture.rawPendingRecording() == recording)
        #expect(try fixture.audioIdentity(for: recording) == audioIdentityBefore)
        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        ) {
            _ = try await coordinator.capture(
                transcriptionModel: "gpt-4o-mini-transcribe",
                transcriptionLanguageCode: "en",
                durationMilliseconds: 1_000
            )
        }
        #expect(
            try await coordinator.recoverAcceptedHistory()
                == .pendingLocalRecovery
        )
        #expect(
            try await coordinator.recoverAcceptedHistoryOutbox()
                == .pendingLocalRecovery
        )
        #expect(
            try await coordinator.recoverHistoryPolicyCleanup()
                == .pendingLocalRecovery
        )
        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        ) {
            _ = try await coordinator.setHistoryEnabled(false)
        }

        let relaunchedRegistry =
            IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let relaunchedContext = relaunchedRegistry.context(
            for: fixture.applicationSupportDirectoryURL
        )
        let relaunchedCoordinator = fixture.makeCoordinator(
            context: relaunchedContext,
            registry: relaunchedRegistry
        )

        #expect(
            try await relaunchedCoordinator.reconcileFailedHistoryTransfer()
                == .reconciled
        )
        let recoveredEnvelope = try #require(
            try await relaunchedContext.failedHistoryStore.load()
        )
        #expect(recoveredEnvelope.revision == 2)
        #expect(recoveredEnvelope.entries.count == 1)
        #expect(recoveredEnvelope.entries.first?.ownershipState == .ready)
        #expect(try fixture.rawPendingRecording() == nil)
        #expect(try fixture.audioIdentity(for: recording) == audioIdentityBefore)
    }

    @Test func readyTerminalRequiresPendingAbsenceAndPreservesRecreatedConflict()
        async throws {
        let absent = try FailedTransferCoordinatorFixture()
        let absentCoordinator = absent.makeCoordinator()
        try await absent.establishEnabledPolicy(using: absentCoordinator)
        let absentRecording = try await absent
            .prepareAwaitingRecoveryRecording()
        #expect(
            try await absentCoordinator.transferPendingRecordingFailure(
                expected: IOSPendingRecordingCASExpectation(
                    recording: absentRecording
                ),
                failure: .recoverableNetworkFailure
            ) == .transferred
        )
        #expect(
            try await absent.makeCoordinator()
                .reconcileFailedHistoryTransfer() == .noWork
        )

        let present = try FailedTransferCoordinatorFixture()
        let presentCoordinator = present.makeCoordinator()
        try await present.establishEnabledPolicy(using: presentCoordinator)
        let presentRecording = try await present
            .prepareAwaitingRecoveryRecording()
        #expect(
            try await presentCoordinator.transferPendingRecordingFailure(
                expected: IOSPendingRecordingCASExpectation(
                    recording: presentRecording
                ),
                failure: .recoverableNetworkFailure
            ) == .transferred
        )
        try present.recreatePendingMetadata(presentRecording)
        let failedBytesBefore = try Data(
            contentsOf: IOSFailedHistoryStorageLocation.fileURL(
                in: present.applicationSupportDirectoryURL
            )
        )
        let pendingBytesBefore = try Data(
            contentsOf: IOSPendingRecordingStorageLocation.journalFileURL(
                in: present.applicationSupportDirectoryURL
            )
        )
        let audioIdentityBefore = try present.audioIdentity(
            for: presentRecording
        )

        await #expect(throws: IOSPendingRecordingError.localRecoveryPending) {
            _ = try await present.context.pendingRecordingStore.load()
        }
        await #expect(throws: IOSPendingRecordingError.localRecoveryPending) {
            _ = try await present.context.pendingRecordingStore.discard(
                expected: IOSPendingRecordingCASExpectation(
                    recording: presentRecording
                )
            )
        }

        await #expect(throws: IOSPendingRecordingError.localRecoveryPending) {
            _ = try await present.makeCoordinator()
                .reconcileFailedHistoryTransfer()
        }

        #expect(
            try Data(
                contentsOf: IOSFailedHistoryStorageLocation.fileURL(
                    in: present.applicationSupportDirectoryURL
                )
            ) == failedBytesBefore
        )
        #expect(
            try Data(
                contentsOf: IOSPendingRecordingStorageLocation.journalFileURL(
                    in: present.applicationSupportDirectoryURL
                )
            ) == pendingBytesBefore
        )
        #expect(
            try present.audioIdentity(for: presentRecording)
                == audioIdentityBefore
        )
    }

    @Test func sixthFailureEvictsOnlyCanonicalOldestAndPreservesItsAudio()
        async throws {
        let fixture = try FailedTransferCoordinatorFixture()
        let coordinator = fixture.makeCoordinator()
        try await fixture.establishEnabledPolicy(using: coordinator)
        var recordings: [IOSPendingRecording] = []

        for _ in 0..<5 {
            let recording = try await fixture
                .prepareAwaitingRecoveryRecording()
            recordings.append(recording)
            #expect(
                try await coordinator.transferPendingRecordingFailure(
                    expected: IOSPendingRecordingCASExpectation(
                        recording: recording
                    ),
                    failure: .recoverableNetworkFailure
                ) == .transferred
            )
        }

        let before = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        let canonicalOldest = try #require(before.entries.last)
        let oldestRecording = try #require(recordings.first(where: {
            $0.attemptID == canonicalOldest.attemptID
        }))
        let oldestAudioIdentity = try fixture.audioIdentity(
            for: oldestRecording
        )
        let sixth = try await fixture.prepareAwaitingRecoveryRecording()

        #expect(
            try await coordinator.transferPendingRecordingFailure(
                expected: IOSPendingRecordingCASExpectation(
                    recording: sixth
                ),
                failure: .recoverableNetworkFailure
            ) == .transferred
        )

        let after = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        #expect(after.revision == before.revision + 2)
        #expect(after.entries.count == 5)
        #expect(!after.entries.contains(canonicalOldest))
        #expect(after.entries.contains(where: {
            $0.attemptID == sixth.attemptID
                && $0.ownershipState == .ready
        }))
        #expect(after.audioCleanup.count == 1)
        #expect(after.audioCleanup.first?.attemptID == canonicalOldest.attemptID)
        #expect(try fixture.rawPendingRecording() == nil)
        #expect(
            try fixture.audioIdentity(for: oldestRecording)
                == oldestAudioIdentity
        )
    }

    @Test func individualDeleteQueuesOnlySelectedTombstoneAndPreservesAudio()
        async throws {
        let fixture = try FailedTransferCoordinatorFixture()
        let coordinator = fixture.makeCoordinator()
        try await fixture.establishEnabledPolicy(using: coordinator)
        let selected = try await fixture.prepareAwaitingRecoveryRecording()
        #expect(
            try await coordinator.transferPendingRecordingFailure(
                expected: IOSPendingRecordingCASExpectation(
                    recording: selected
                ),
                failure: .recoverableNetworkFailure
            ) == .transferred
        )
        let retained = try await fixture.prepareAwaitingRecoveryRecording()
        #expect(
            try await coordinator.transferPendingRecordingFailure(
                expected: IOSPendingRecordingCASExpectation(
                    recording: retained
                ),
                failure: .recoverableNetworkFailure
            ) == .transferred
        )
        let audioIdentity = try fixture.audioIdentity(for: selected)
        let before = try #require(
            try await fixture.context.failedHistoryStore.load()
        )

        let receipt = try await coordinator.deleteFailedHistoryEntry(
            attemptID: selected.attemptID
        )

        let after = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        #expect(after.revision == before.revision + 1)
        #expect(!after.entries.contains(where: {
            $0.attemptID == selected.attemptID
        }))
        #expect(after.entries.contains(where: {
            $0.attemptID == retained.attemptID
        }))
        #expect(after.audioCleanup.count == 1)
        #expect(after.audioCleanup.first == receipt.tombstone)
        #expect(receipt.tombstone.attemptID == selected.attemptID)
        #expect(try fixture.audioIdentity(for: selected) == audioIdentity)
    }

    @Test func retentionUncertaintyReconcilesBothVisibleStatesAcrossCalls()
        async throws {
        for outcomeVisible in [false, true] {
            let fixture = try FailedTransferCoordinatorFixture(
                controllableFailedHistory: true
            )
            let coordinator = fixture.makeCoordinator()
            try await fixture.establishEnabledPolicy(using: coordinator)
            var recordings: [IOSPendingRecording] = []

            for _ in 0..<5 {
                let recording = try await fixture
                    .prepareAwaitingRecoveryRecording()
                recordings.append(recording)
                #expect(
                    try await coordinator.transferPendingRecordingFailure(
                        expected: IOSPendingRecordingCASExpectation(
                            recording: recording
                        ),
                        failure: .recoverableNetworkFailure
                    ) == .transferred
                )
            }

            let before = try #require(
                try await fixture.failedHistoryStore.load()
            )
            let canonicalOldest = try #require(before.entries.last)
            let sixth = try await fixture.prepareAwaitingRecoveryRecording()
            recordings.append(sixth)
            let audioIdentities = try fixture.audioIdentities(
                for: recordings
            )
            let failedHistoryFileSystem = try #require(
                fixture.failedHistoryFileSystem
            )
            failedHistoryFileSystem.replaceFailure = .init(
                error: .commitUncertain,
                commitBeforeThrowing: outcomeVisible
            )

            await #expect(throws: IOSFailedHistoryError.commitUncertain) {
                _ = try await coordinator.transferPendingRecordingFailure(
                    expected: IOSPendingRecordingCASExpectation(
                        recording: sixth
                    ),
                    failure: .recoverableNetworkFailure
                )
            }

            #expect(fixture.context.failedHistoryMutationInterlock.isBlocked)
            #expect(try fixture.rawPendingRecording() == sixth)
            #expect(
                try fixture.audioIdentities(for: recordings)
                    == audioIdentities
            )
            let uncertainState = try #require(
                try fixture.rawControllableFailedHistory()
            )
            if outcomeVisible {
                #expect(uncertainState.revision == before.revision + 1)
                #expect(uncertainState.entries.count == 5)
                #expect(uncertainState.entries.contains(where: {
                    $0.attemptID == sixth.attemptID
                        && $0.ownershipState == .pendingJournalRetirement
                }))
                #expect(
                    uncertainState.audioCleanup.map(\.attemptID)
                        == [canonicalOldest.attemptID]
                )
            } else {
                #expect(uncertainState == before)
            }

            #expect(
                try await coordinator.reconcileFailedHistoryTransfer()
                    == .reconciled
            )

            let final = try #require(
                try await fixture.failedHistoryStore.load()
            )
            let sixthReady = try #require(final.entries.first(where: {
                $0.attemptID == sixth.attemptID
            }))
            #expect(sixthReady.ownershipState == .ready)
            #expect(final.revision == before.revision + 2)
            #expect(
                final.entries
                    == IOSFailedHistoryValidation.sortedEntries(
                        Array(before.entries.dropLast()) + [sixthReady]
                    )
            )
            let expectedTombstone = try IOSFailedHistoryAudioCleanup(
                attemptID: canonicalOldest.attemptID,
                policyGeneration: canonicalOldest.policyGeneration,
                queuedAt: sixthReady.updatedAt,
                audioRelativeIdentifier:
                    canonicalOldest.audioRelativeIdentifier,
                byteCount: canonicalOldest.byteCount
            )
            #expect(final.audioCleanup == [expectedTombstone])
            #expect(try fixture.rawPendingRecording() == nil)
            #expect(!fixture.context.failedHistoryMutationInterlock.isBlocked)
            #expect(
                try fixture.audioIdentities(for: recordings)
                    == audioIdentities
            )
        }
    }

    @Test func deleteImmediatelyReconcilesBothVisibleStatesAndPreservesAudio()
        async throws {
        for outcomeVisible in [false, true] {
            let fixture = try FailedTransferCoordinatorFixture(
                controllableFailedHistory: true
            )
            let coordinator = fixture.makeCoordinator()
            try await fixture.establishEnabledPolicy(using: coordinator)
            let selected = try await fixture
                .prepareAwaitingRecoveryRecording()
            #expect(
                try await coordinator.transferPendingRecordingFailure(
                    expected: IOSPendingRecordingCASExpectation(
                        recording: selected
                    ),
                    failure: .recoverableNetworkFailure
                ) == .transferred
            )
            let retained = try await fixture
                .prepareAwaitingRecoveryRecording()
            #expect(
                try await coordinator.transferPendingRecordingFailure(
                    expected: IOSPendingRecordingCASExpectation(
                        recording: retained
                    ),
                    failure: .recoverableNetworkFailure
                ) == .transferred
            )
            let recordings = [selected, retained]
            let audioIdentities = try fixture.audioIdentities(
                for: recordings
            )
            let before = try #require(
                try await fixture.failedHistoryStore.load()
            )
            let selectedRow = try #require(before.entries.first(where: {
                $0.attemptID == selected.attemptID
            }))
            let expectedRows = before.entries.filter {
                $0.attemptID != selected.attemptID
            }
            let failedHistoryFileSystem = try #require(
                fixture.failedHistoryFileSystem
            )
            failedHistoryFileSystem.replaceFailure = .init(
                error: .commitUncertain,
                commitBeforeThrowing: outcomeVisible
            )

            let receipt = try await coordinator.deleteFailedHistoryEntry(
                attemptID: selected.attemptID
            )

            #expect(failedHistoryFileSystem.replaceFailure == nil)
            let final = try #require(
                try await fixture.failedHistoryStore.load()
            )
            #expect(final.revision == before.revision + 1)
            #expect(final.entries == expectedRows)
            #expect(final.audioCleanup == [receipt.tombstone])
            #expect(receipt.tombstone.attemptID == selectedRow.attemptID)
            #expect(
                receipt.tombstone.policyGeneration
                    == selectedRow.policyGeneration
            )
            #expect(
                receipt.tombstone.audioRelativeIdentifier
                    == selectedRow.audioRelativeIdentifier
            )
            #expect(receipt.tombstone.byteCount == selectedRow.byteCount)
            #expect(!fixture.context.failedHistoryMutationInterlock.isBlocked)
            #expect(try fixture.rawPendingRecording() == nil)
            #expect(
                try fixture.audioIdentities(for: recordings)
                    == audioIdentities
            )
        }
    }
}

private final class FailedTransferCoordinatorFixture: @unchecked Sendable {
    struct AudioIdentity: Equatable {
        let fileNumber: UInt64
        let byteCount: UInt64
    }

    let parentDirectoryURL: URL
    let applicationSupportDirectoryURL: URL
    let registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry
    let context: IOSAcceptedHistoryCoordinatorProcessContext
    let failedHistoryFileSystem: FailedHistoryFakeFileSystem?
    let failedHistoryStore: IOSFailedHistoryStore
    let pendingRecordingStore: IOSPendingRecordingStore

    init(controllableFailedHistory: Bool = false) throws {
        parentDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "failed-transfer-coordinator-\(UUID().uuidString)",
                isDirectory: true
            )
        applicationSupportDirectoryURL = parentDirectoryURL
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
        try FileManager.default.createDirectory(
            at: applicationSupportDirectoryURL,
            withIntermediateDirectories: true
        )
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        self.registry = registry
        context = registry.context(for: applicationSupportDirectoryURL)
        if controllableFailedHistory {
            let fileSystem = FailedHistoryFakeFileSystem()
            let failedHistoryStore = IOSFailedHistoryStore(
                journal: FoundationIOSFailedHistoryJournalRepository(
                    fileSystem: fileSystem
                ),
                capabilityOwnerIdentity: context.ownerIdentity,
                operationGateIdentity: context.operationGate.identity,
                expectedPendingStoreIdentity:
                    context.pendingRecordingStoreIdentity,
                repositoryGuard: context.repositoryGuard,
                mutationInterlock: context.failedHistoryMutationInterlock
            )
            failedHistoryFileSystem = fileSystem
            self.failedHistoryStore = failedHistoryStore
            pendingRecordingStore = IOSPendingRecordingStore(
                applicationSupportDirectoryURL:
                    applicationSupportDirectoryURL,
                capabilityOwnerIdentity: context.ownerIdentity,
                storeIdentity: context.pendingRecordingStoreIdentity,
                operationGate: context.operationGate,
                liveOwnerRegistry:
                    context.pendingRecordingLiveOwnerRegistry,
                mediaValidationWorkerGate:
                    context.pendingRecordingMediaValidationWorkerGate,
                repositoryGuard: context.repositoryGuard,
                failedHistoryMutationInterlock:
                    context.failedHistoryMutationInterlock,
                failedOwnershipInspector: failedHistoryStore
            )
        } else {
            failedHistoryFileSystem = nil
            failedHistoryStore = context.failedHistoryStore
            pendingRecordingStore = context.pendingRecordingStore
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: parentDirectoryURL)
    }

    func makeCoordinator(
        context: IOSAcceptedHistoryCoordinatorProcessContext? = nil,
        registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry? = nil
    ) -> IOSAcceptedHistoryCoordinator {
        let context = context ?? self.context
        let registry = registry ?? self.registry
        let failedHistoryStore = failedHistoryFileSystem == nil
            ? context.failedHistoryStore
            : self.failedHistoryStore
        let pendingRecordingStore = failedHistoryFileSystem == nil
            ? context.pendingRecordingStore
            : self.pendingRecordingStore
        return IOSAcceptedHistoryCoordinator(
            policyStore: context.policyStore,
            acceptedHistoryStore: context.acceptedHistoryStore,
            failedHistoryStore: failedHistoryStore,
            pendingRecordingStore: pendingRecordingStore,
            outboxStore: context.outboxStore,
            deliveryStore: context.deliveryStore,
            operationGate: context.operationGate,
            baselineRecoveryState: context.baselineRecoveryState,
            acceptanceState: context.acceptanceState,
            pendingReplacementState: context.pendingReplacementState,
            outboxWorkerState: context.outboxWorkerState,
            policyCutoverState: context.policyCutoverState,
            failedHistoryTransferState: context.failedHistoryTransferState,
            ownerIdentity: context.ownerIdentity,
            repositoryIdentityState: context.repositoryIdentityState,
            repositoryRegistration:
                IOSAcceptedHistoryCoordinatorRepositoryRegistration(
                    registry: registry,
                    context: context,
                    applicationSupportDirectoryURL:
                        applicationSupportDirectoryURL
                )
        )
    }

    func establishEnabledPolicy(
        using coordinator: IOSAcceptedHistoryCoordinator
    ) async throws {
        let capture = try await coordinator.capture(
            transcriptionModel: "gpt-4o-mini-transcribe",
            transcriptionLanguageCode: "en",
            durationMilliseconds: 1_000
        )
        #expect(capture.historyWrite?.policyGeneration == 1)
    }

    func prepareAwaitingRecoveryRecording() async throws
        -> IOSPendingRecording {
        let attemptID = UUID()
        let sourceURL = parentDirectoryURL.appendingPathComponent(
            "source-\(attemptID.uuidString.lowercased()).wav",
            isDirectory: false
        )
        let data = makeFailedTransferOneSecondWAV()
        try data.write(to: sourceURL, options: .atomic)
        let preparation = try IOSPendingRecordingPreparation(
            attemptID: attemptID,
            sourceArtifact: AudioRecordingArtifact(
                fileURL: sourceURL,
                duration: 1,
                byteCount: Int64(data.count)
            ),
            initialState: .awaitingRecovery,
            outputIntent: .standard,
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "gpt-4o-mini-transcribe",
                language: .english
            )
        )
        return try await pendingRecordingStore.prepare(preparation)
    }

    func stagePendingJournalRetirement(
        for recording: IOSPendingRecording
    ) async throws {
        let context = context
        try await context.operationGate.perform { lease in
            let source = try await self.pendingRecordingStore
                .prepareFailedHistoryTransferSource(
                    expected: IOSPendingRecordingCASExpectation(
                        recording: recording
                    ),
                    failedStoreIdentity:
                        self.failedHistoryStore.storeIdentity,
                    operationLeaseAuthorization: lease
                )
            defer { source.releaseAudioLease() }
            let policy = try #require(try await context.policyStore.load())
            let policyReceipt = try await context.policyStore.confirm(
                expected: IOSHistoryPolicyExpectation(state: policy)
            )
            let preparation = try await self.pendingRecordingStore
                .sealFailedHistoryTransfer(
                    source,
                    failure: .recoverableNetworkFailure,
                    transferDate: recording.updatedAt.addingTimeInterval(1),
                    policyReceipt: policyReceipt,
                    operationLeaseAuthorization: lease
                )
            defer { preparation.releaseAudioLease() }
            _ = try await self.failedHistoryStore
                .commitPendingJournalRetirement(preparation)
        }
    }

    func rawPendingRecording() throws -> IOSPendingRecording? {
        try FoundationIOSPendingRecordingJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            repositoryGuard: context.repositoryGuard
        ).load()
    }

    func rawControllableFailedHistory() throws
        -> IOSFailedHistoryEnvelope? {
        guard let data = failedHistoryFileSystem?.file?.data else {
            return nil
        }
        return try IOSFailedHistoryWireCodec.decode(data)
    }

    func recreatePendingMetadata(_ recording: IOSPendingRecording) throws {
        try FoundationIOSPendingRecordingJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            repositoryGuard: context.repositoryGuard
        ).create(
            recording,
            expectedRepositoryRoot:
                context.repositoryBinding.physicalRootIdentity
        )
    }

    func audioIdentity(
        for recording: IOSPendingRecording
    ) throws -> AudioIdentity {
        let url = try #require(
            IOSPendingRecordingStorageLocation.audioFileURL(
                forRelativeIdentifier: recording.audioRelativeIdentifier,
                in: applicationSupportDirectoryURL
            )
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        return AudioIdentity(
            fileNumber: try #require(
                (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
            ),
            byteCount: try #require(
                (attributes[.size] as? NSNumber)?.uint64Value
            )
        )
    }

    func audioIdentities(
        for recordings: [IOSPendingRecording]
    ) throws -> [UUID: AudioIdentity] {
        try Dictionary(uniqueKeysWithValues: recordings.map {
            ($0.attemptID, try audioIdentity(for: $0))
        })
    }
}

private extension IOSFailedHistoryTransferFailure {
    static let recoverableNetworkFailure = Self(
        category: .networkUnavailable,
        pipelineStage: .transcription
    )
}

private func makeFailedTransferOneSecondWAV() -> Data {
    let sampleRate: UInt32 = 8_000
    let channelCount: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let dataByteCount = sampleRate * UInt32(bitsPerSample / 8)
    let byteRate = sampleRate * UInt32(channelCount)
        * UInt32(bitsPerSample / 8)
    let blockAlign = channelCount * (bitsPerSample / 8)

    var data = Data()
    data.append(contentsOf: "RIFF".utf8)
    data.appendFailedTransferLittleEndian(UInt32(36) + dataByteCount)
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    data.appendFailedTransferLittleEndian(UInt32(16))
    data.appendFailedTransferLittleEndian(UInt16(1))
    data.appendFailedTransferLittleEndian(channelCount)
    data.appendFailedTransferLittleEndian(sampleRate)
    data.appendFailedTransferLittleEndian(byteRate)
    data.appendFailedTransferLittleEndian(blockAlign)
    data.appendFailedTransferLittleEndian(bitsPerSample)
    data.append(contentsOf: "data".utf8)
    data.appendFailedTransferLittleEndian(dataByteCount)
    data.append(Data(repeating: 0, count: Int(dataByteCount)))
    return data
}

private extension Data {
    mutating func appendFailedTransferLittleEndian<T: FixedWidthInteger>(
        _ value: T
    ) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) {
            append(contentsOf: $0)
        }
    }
}
