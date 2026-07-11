import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSFailedHistoryAudioCleanupCoordinatorTests {
    @Test func lifecycleCleansOnlyOneCanonicalHeadPerCall() async throws {
        let fixture = try AudioCleanupCoordinatorFixture()
        let tombstones = try (401...402).map {
            try failedHistoryTestAudioCleanup(index: $0)
        }
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 7,
                entries: [],
                audioCleanup: tombstones
            )
        )

        #expect(
            try await fixture.coordinator.recoverFailedHistoryAudioCleanup()
                == .cleaned
        )
        let afterFirst = try #require(try fixture.envelope())
        #expect(afterFirst.revision == 8)
        #expect(afterFirst.audioCleanup == [tombstones[1]])
        #expect(fixture.audioFileSystem.cleanedTombstones == [tombstones[0]])

        #expect(
            try await fixture.coordinator.recoverFailedHistoryAudioCleanup()
                == .cleaned
        )
        let afterSecond = try #require(try fixture.envelope())
        #expect(afterSecond.revision == 9)
        #expect(afterSecond.audioCleanup.isEmpty)
        #expect(fixture.audioFileSystem.cleanedTombstones == tombstones)

        #expect(
            try await fixture.coordinator.recoverFailedHistoryAudioCleanup()
                == .noWork
        )
        #expect(fixture.audioFileSystem.genericRemoveCallCount == 0)
        #expect(fixture.audioFileSystem.publishCallCount == 0)
    }

    @Test func explicitDeleteUsesFreshLeaseAndCleansOnlyItsNonHeadTombstone()
        async throws {
        let fixture = try AudioCleanupCoordinatorFixture()
        let older = try failedHistoryTestAudioCleanup(index: 411)
        let selected = try failedHistoryTestEntry(index: 412)
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 3,
                entries: [selected],
                audioCleanup: [older]
            )
        )

        let receipt = try await fixture.coordinator.deleteFailedHistoryEntry(
            attemptID: selected.attemptID
        )

        let final = try #require(try fixture.envelope())
        #expect(final.revision == 5)
        #expect(final.entries.isEmpty)
        #expect(final.audioCleanup == [older])
        #expect(receipt.tombstone.attemptID == selected.attemptID)
        #expect(
            fixture.audioFileSystem.cleanedTombstones == [receipt.tombstone]
        )
        #expect(fixture.audioFileSystem.explicitDeleteUsedFreshLease == true)
        #expect(fixture.audioFileSystem.genericRemoveCallCount == 0)
        #expect(fixture.audioFileSystem.publishCallCount == 0)
        #expect(await fixture.cleanupState.current() == nil)
        #expect(!fixture.mutationInterlock.isBlocked)
    }

    @Test func postBoundaryDeleteReturnsSuccessAndLeavesExactRetryableCleanup()
        async throws {
        let fixture = try AudioCleanupCoordinatorFixture()
        let selected = try failedHistoryTestEntry(index: 421)
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [selected],
                audioCleanup: []
            )
        )
        fixture.audioFileSystem.enqueue(.removeThenFail)

        let receipt = try await fixture.coordinator.deleteFailedHistoryEntry(
            attemptID: selected.attemptID
        )

        let pending = try #require(try fixture.envelope())
        #expect(pending.revision == 2)
        #expect(pending.entries.isEmpty)
        #expect(pending.audioCleanup == [receipt.tombstone])
        #expect(await fixture.cleanupState.current() != nil)
        #expect(fixture.mutationInterlock.isBlocked)
        #expect(fixture.audioFileSystem.cleanupCallCount == 1)

        #expect(
            try await fixture.coordinator.recoverFailedHistoryAudioCleanup()
                == .cleaned
        )
        let recovered = try #require(try fixture.envelope())
        #expect(recovered.revision == 3)
        #expect(recovered.entries.isEmpty)
        #expect(recovered.audioCleanup.isEmpty)
        #expect(fixture.audioFileSystem.cleanupCallCount == 2)
        #expect(await fixture.cleanupState.current() == nil)
        #expect(!fixture.mutationInterlock.isBlocked)
        #expect(fixture.audioFileSystem.genericRemoveCallCount == 0)
    }

    @Test func journalRetirementUncertaintyReconcilesSourceAndOutcomeVisible()
        async throws {
        for outcomeVisible in [false, true] {
            let fixture = try AudioCleanupCoordinatorFixture()
            let tombstone = try failedHistoryTestAudioCleanup(
                index: outcomeVisible ? 432 : 431
            )
            try fixture.install(
                IOSFailedHistoryEnvelope(
                    revision: 11,
                    entries: [],
                    audioCleanup: [tombstone]
                )
            )
            fixture.failedFileSystem.replaceFailure = .init(
                error: .commitUncertain,
                commitBeforeThrowing: outcomeVisible
            )

            #expect(
                try await fixture.coordinator
                    .recoverFailedHistoryAudioCleanup() == .cleaned
            )

            let final = try #require(try fixture.envelope())
            #expect(final.revision == 12)
            #expect(final.audioCleanup.isEmpty)
            #expect(
                fixture.audioFileSystem.cleanupCallCount
                    == (outcomeVisible ? 1 : 2)
            )
            #expect(await fixture.cleanupState.current() == nil)
            #expect(!fixture.mutationInterlock.isBlocked)
            #expect(fixture.audioFileSystem.genericRemoveCallCount == 0)
        }
    }

    @Test func definitiveCommitCompletesAfterTransientOutcomeReadFailure()
        async throws {
        let fixture = try AudioCleanupCoordinatorFixture()
        let tombstone = try failedHistoryTestAudioCleanup(index: 439)
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 20,
                entries: [],
                audioCleanup: [tombstone]
            )
        )
        fixture.failedFileSystem.readErrorAfterNextReplace =
            .protectedDataUnavailable

        await #expect(
            throws: IOSFailedHistoryError.dataProtectionUnavailable
        ) {
            _ = try await fixture.coordinator
                .recoverFailedHistoryAudioCleanup()
        }

        let committed = try #require(try fixture.envelope())
        #expect(committed.revision == 21)
        #expect(committed.audioCleanup.isEmpty)
        #expect(await fixture.cleanupState.current() != nil)
        #expect(fixture.mutationInterlock.isBlocked)
        #expect(fixture.audioFileSystem.cleanupCallCount == 1)

        fixture.failedFileSystem.readError = nil
        #expect(
            try await fixture.coordinator.recoverFailedHistoryAudioCleanup()
                == .cleaned
        )
        #expect(await fixture.cleanupState.current() == nil)
        #expect(!fixture.mutationInterlock.isBlocked)
        #expect(fixture.audioFileSystem.cleanupCallCount == 1)
        #expect(fixture.audioFileSystem.genericRemoveCallCount == 0)
    }

    @Test func relaunchRecoversAlreadyAbsentAudioWithoutGenericRemoval()
        async throws {
        let root = try AudioCleanupCoordinatorTestRoot()
        let failedFileSystem = FailedHistoryFakeFileSystem()
        let durableAudio = AudioCleanupDurableAudioState()
        let first = try AudioCleanupCoordinatorFixture(
            root: root,
            failedFileSystem: failedFileSystem,
            durableAudio: durableAudio
        )
        let tombstone = try failedHistoryTestAudioCleanup(index: 441)
        try first.install(
            IOSFailedHistoryEnvelope(
                revision: 5,
                entries: [],
                audioCleanup: [tombstone]
            )
        )
        first.audioFileSystem.enqueue(.removeThenFail)

        await #expect(throws: IOSPendingRecordingError.audioRemoveFailed) {
            _ = try await first.coordinator
                .recoverFailedHistoryAudioCleanup()
        }
        #expect(durableAudio.isAbsent(tombstone.audioRelativeIdentifier))
        #expect(await first.cleanupState.current() != nil)

        let relaunched = try AudioCleanupCoordinatorFixture(
            root: root,
            failedFileSystem: failedFileSystem,
            durableAudio: durableAudio
        )
        #expect(await relaunched.cleanupState.current() == nil)
        #expect(!relaunched.mutationInterlock.isBlocked)

        #expect(
            try await relaunched.coordinator
                .recoverFailedHistoryAudioCleanup() == .cleaned
        )
        let final = try #require(try relaunched.envelope())
        #expect(final.revision == 6)
        #expect(final.audioCleanup.isEmpty)
        #expect(relaunched.audioFileSystem.cleanupCallCount == 1)
        #expect(
            relaunched.audioFileSystem.alreadyAbsentReceiptCount == 1
        )
        #expect(relaunched.audioFileSystem.genericRemoveCallCount == 0)
        #expect(relaunched.audioFileSystem.publishCallCount == 0)
    }

    @Test func retainedCleanupBlocksDeleteAndFailedTransferWithoutMisclassification()
        async throws {
        let fixture = try AudioCleanupCoordinatorFixture()
        let tombstone = try failedHistoryTestAudioCleanup(index: 451)
        let retainedRow = try failedHistoryTestEntry(index: 452)
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 2,
                entries: [retainedRow],
                audioCleanup: [tombstone]
            )
        )
        fixture.audioFileSystem.enqueue(.removeThenFail)

        await #expect(throws: IOSPendingRecordingError.audioRemoveFailed) {
            _ = try await fixture.coordinator
                .recoverFailedHistoryAudioCleanup()
        }
        let retainedBytes = fixture.failedFileSystem.file?.data

        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        ) {
            _ = try await fixture.coordinator.deleteFailedHistoryEntry(
                attemptID: retainedRow.attemptID
            )
        }
        let pending = try audioCleanupPendingRecording(index: 453)
        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        ) {
            _ = try await fixture.coordinator.transferPendingRecordingFailure(
                expected: IOSPendingRecordingCASExpectation(recording: pending),
                failure: IOSFailedHistoryTransferFailure(
                    category: .networkFailure,
                    pipelineStage: .transcription
                )
            )
        }

        #expect(fixture.failedFileSystem.file?.data == retainedBytes)
        #expect(await fixture.cleanupState.current() != nil)
        #expect(fixture.mutationInterlock.isBlocked)
        #expect(fixture.audioFileSystem.cleanupCallCount == 1)
        #expect(fixture.audioFileSystem.acquireValidatedCallCount == 0)
        #expect(fixture.audioFileSystem.genericRemoveCallCount == 0)
        #expect(fixture.audioFileSystem.publishCallCount == 0)
    }

    @Test func policyNoOpPreservesCurrentRowThenDisableCleansWithoutNPlusTwo()
        async throws {
        let fixture = try AudioCleanupCoordinatorFixture()
        #expect(
            try await fixture.coordinator.recoverHistoryPolicyCleanup()
                == .complete
        )
        let current = try failedHistoryTestEntry(index: 461)
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [current],
                audioCleanup: []
            )
        )

        #expect(
            try await fixture.coordinator.setHistoryEnabled(true) == .complete
        )
        #expect(try fixture.envelope()?.entries == [current])
        #expect(try await fixture.filteredEntries() == [current])

        #expect(
            try await fixture.coordinator.setHistoryEnabled(false)
                == .pendingLocalRecovery
        )
        let tombstoned = try #require(try fixture.envelope())
        #expect(tombstoned.revision == 2)
        #expect(tombstoned.entries.isEmpty)
        #expect(tombstoned.audioCleanup.count == 1)
        #expect(try await fixture.filteredEntries().isEmpty)
        let disabled = try #require(try await fixture.context.policyStore.load())
        #expect(disabled.revision == 2)
        #expect(disabled.policyGeneration == 2)
        #expect(disabled.historyEnabled == false)

        #expect(
            try await fixture.coordinator.recoverHistoryPolicyCleanup()
                == .pendingLocalRecovery
        )
        let cleaned = try #require(try fixture.envelope())
        #expect(cleaned.revision == 3)
        #expect(cleaned.entries.isEmpty)
        #expect(cleaned.audioCleanup.isEmpty)
        #expect(
            try await fixture.coordinator.recoverHistoryPolicyCleanup()
                == .complete
        )
        #expect(try await fixture.context.policyStore.load() == disabled)
    }

    @Test func policyCutoverCleansExistingHeadBeforeInvalidatingOldestRow()
        async throws {
        let fixture = try AudioCleanupCoordinatorFixture()
        #expect(
            try await fixture.coordinator.recoverHistoryPolicyCleanup()
                == .complete
        )
        let stale = try failedHistoryTestEntry(index: 471)
        let existingHead = try failedHistoryTestAudioCleanup(index: 472)
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 4,
                entries: [stale],
                audioCleanup: [existingHead]
            )
        )

        #expect(
            try await fixture.coordinator.setHistoryEnabled(false)
                == .pendingLocalRecovery
        )
        let afterHead = try #require(try fixture.envelope())
        #expect(afterHead.revision == 5)
        #expect(afterHead.entries == [stale])
        #expect(afterHead.audioCleanup.isEmpty)
        #expect(fixture.audioFileSystem.cleanedTombstones == [existingHead])

        #expect(
            try await fixture.coordinator.recoverHistoryPolicyCleanup()
                == .pendingLocalRecovery
        )
        let invalidated = try #require(try fixture.envelope())
        let staleTombstone = try #require(invalidated.audioCleanup.first)
        #expect(invalidated.revision == 6)
        #expect(invalidated.entries.isEmpty)
        #expect(staleTombstone.attemptID == stale.attemptID)
        #expect(fixture.audioFileSystem.cleanedTombstones == [existingHead])

        #expect(
            try await fixture.coordinator.recoverHistoryPolicyCleanup()
                == .pendingLocalRecovery
        )
        #expect(try fixture.envelope()?.revision == 7)
        #expect(try fixture.envelope()?.audioCleanup.isEmpty == true)
        #expect(
            fixture.audioFileSystem.cleanedTombstones
                == [existingHead, staleTombstone]
        )
    }

    @Test func processLostRetryCancelsLocallyButAcceptingOutputFailsClosed()
        async throws {
        let cancellable = try AudioCleanupCoordinatorFixture()
        #expect(
            try await cancellable.coordinator.recoverHistoryPolicyCleanup()
                == .complete
        )
        let retry = try failedHistoryTestRetryOperation(index: 481)
        let retryingRow = try failedHistoryTestEntry(
            index: 481,
            retryCount: 1,
            retryOperation: retry
        )
        try cancellable.install(
            IOSFailedHistoryEnvelope(
                revision: 8,
                entries: [retryingRow],
                audioCleanup: []
            )
        )

        #expect(
            try await cancellable.coordinator.setHistoryEnabled(false)
                == .pendingLocalRecovery
        )
        let cancelled = try #require(try cancellable.envelope())
        let cancelledRow = try #require(cancelled.entries.first)
        #expect(cancelled.revision == 9)
        #expect(cancelled.entries.count == 1)
        #expect(cancelledRow.retryOperation == nil)
        #expect(cancelledRow.retryCount == retryingRow.retryCount)
        #expect(cancelledRow.updatedAt == retryingRow.updatedAt)
        #expect(cancelled.audioCleanup.isEmpty)
        #expect(cancellable.audioFileSystem.cleanupCallCount == 0)
        #expect(cancellable.audioFileSystem.publishCallCount == 0)

        let blocked = try AudioCleanupCoordinatorFixture()
        #expect(
            try await blocked.coordinator.recoverHistoryPolicyCleanup()
                == .complete
        )
        let accepting = try failedHistoryTestRetryOperation(
            index: 482,
            state: .acceptingOutput
        )
        let acceptingRow = try failedHistoryTestEntry(
            index: 482,
            retryCount: 1,
            retryOperation: accepting
        )
        try blocked.install(
            IOSFailedHistoryEnvelope(
                revision: 10,
                entries: [acceptingRow],
                audioCleanup: []
            )
        )

        #expect(
            try await blocked.coordinator.setHistoryEnabled(false)
                == .pendingLocalRecovery
        )
        let retainedBytes = blocked.failedFileSystem.file?.data
        let disabled = try #require(try await blocked.context.policyStore.load())
        #expect(disabled.policyGeneration == 2)
        #expect(
            try await blocked.coordinator.recoverHistoryPolicyCleanup()
                == .pendingLocalRecovery
        )
        #expect(blocked.failedFileSystem.file?.data == retainedBytes)
        #expect(try blocked.envelope()?.entries == [acceptingRow])
        #expect(try await blocked.context.policyStore.load() == disabled)
        #expect(blocked.audioFileSystem.cleanupCallCount == 0)
        #expect(blocked.audioFileSystem.publishCallCount == 0)
    }

    @Test func policyRetryCancellationReconcilesSourceAndOutcomeWithoutNewGeneration()
        async throws {
        for outcomeVisible in [false, true] {
            let fixture = try AudioCleanupCoordinatorFixture()
            #expect(
                try await fixture.coordinator.recoverHistoryPolicyCleanup()
                    == .complete
            )
            let retry = try failedHistoryTestRetryOperation(
                index: outcomeVisible ? 492 : 491,
                state: .reserved
            )
            let row = try failedHistoryTestEntry(
                index: outcomeVisible ? 492 : 491,
                retryCount: 1,
                retryOperation: retry
            )
            try fixture.install(
                IOSFailedHistoryEnvelope(
                    revision: 30,
                    entries: [row],
                    audioCleanup: []
                )
            )
            fixture.failedFileSystem.replaceFailure = .init(
                error: .commitUncertain,
                commitBeforeThrowing: outcomeVisible
            )

            #expect(
                try await fixture.coordinator.setHistoryEnabled(false)
                    == .pendingLocalRecovery
            )
            let committedPolicy = try #require(
                try await fixture.context.policyStore.load()
            )
            #expect(committedPolicy.revision == 2)
            #expect(committedPolicy.policyGeneration == 2)
            #expect(committedPolicy.historyEnabled == false)
            #expect(fixture.mutationInterlock.isBlocked)

            for _ in 0..<3 where fixture.mutationInterlock.isBlocked {
                #expect(
                    try await fixture.coordinator
                        .recoverHistoryPolicyCleanup()
                        == .pendingLocalRecovery
                )
                #expect(
                    try await fixture.context.policyStore.load()
                        == committedPolicy
                )
            }

            let recovered = try #require(try fixture.envelope())
            let retained = try #require(recovered.entries.first)
            #expect(recovered.revision == 31)
            #expect(recovered.entries.count == 1)
            #expect(retained.attemptID == row.attemptID)
            #expect(retained.retryOperation == nil)
            #expect(retained.retryCount == row.retryCount)
            #expect(retained.updatedAt == row.updatedAt)
            #expect(recovered.audioCleanup.isEmpty)
            #expect(!fixture.mutationInterlock.isBlocked)
            #expect(
                try await fixture.context.policyStore.load() == committedPolicy
            )
            #expect(fixture.audioFileSystem.cleanupCallCount == 0)
            #expect(fixture.audioFileSystem.publishCallCount == 0)
        }
    }

    @Test func failedCleanupFinishesBeforeAcceptedC3Handoff()
        async throws {
        let fixture = try AudioCleanupCoordinatorFixture()
        #expect(
            try await fixture.coordinator.recoverHistoryPolicyCleanup()
                == .complete
        )
        let preparation = try await failedPolicyAcceptedPreparation(
            using: fixture.coordinator
        )
        #expect(
            try await fixture.coordinator.accept(preparation).resolution
                == .committed
        )
        let acceptedBefore = try #require(
            try await fixture.context.acceptedHistoryStore.load()
        )
        #expect(acceptedBefore.entries.count == 1)

        let stale = try failedHistoryTestEntry(index: 501)
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [stale],
                audioCleanup: []
            )
        )

        #expect(
            try await fixture.coordinator.setHistoryEnabled(false)
                == .pendingLocalRecovery
        )
        let committedPolicy = try #require(
            try await fixture.context.policyStore.load()
        )
        let invalidated = try #require(try fixture.envelope())
        #expect(invalidated.revision == 2)
        #expect(invalidated.entries.isEmpty)
        #expect(invalidated.audioCleanup.count == 1)
        #expect(
            try await fixture.context.acceptedHistoryStore.load()
                == acceptedBefore
        )
        #expect(fixture.audioFileSystem.cleanupCallCount == 0)

        #expect(
            try await fixture.coordinator.recoverHistoryPolicyCleanup()
                == .pendingLocalRecovery
        )
        let failedComplete = try #require(try fixture.envelope())
        #expect(failedComplete.revision == 3)
        #expect(failedComplete.entries.isEmpty)
        #expect(failedComplete.audioCleanup.isEmpty)
        #expect(
            try await fixture.context.acceptedHistoryStore.load()
                == acceptedBefore
        )
        #expect(fixture.audioFileSystem.cleanupCallCount == 1)
        #expect(
            try await fixture.context.policyStore.load() == committedPolicy
        )

        #expect(
            try await fixture.coordinator.recoverHistoryPolicyCleanup()
                == .complete
        )
        let acceptedAfter = try #require(
            try await fixture.context.acceptedHistoryStore.load()
        )
        #expect(acceptedAfter.entries.isEmpty)
        #expect(
            try await fixture.context.policyStore.load() == committedPolicy
        )
    }

    @Test func providerDispatchedCancellationPrecedesQueuedTombstoneCleanup()
        async throws {
        let fixture = try AudioCleanupCoordinatorFixture()
        #expect(
            try await fixture.coordinator.recoverHistoryPolicyCleanup()
                == .complete
        )
        let retry = try failedHistoryTestRetryOperation(
            index: 511,
            state: .providerDispatched
        )
        let retryingRow = try failedHistoryTestEntry(
            index: 511,
            retryCount: 1,
            retryOperation: retry
        )
        let existingHead = try failedHistoryTestAudioCleanup(index: 512)
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 40,
                entries: [retryingRow],
                audioCleanup: [existingHead]
            )
        )

        #expect(
            try await fixture.coordinator.setHistoryEnabled(false)
                == .pendingLocalRecovery
        )
        let committedPolicy = try #require(
            try await fixture.context.policyStore.load()
        )
        let cancelled = try #require(try fixture.envelope())
        let retained = try #require(cancelled.entries.first)
        #expect(cancelled.revision == 41)
        #expect(retained.attemptID == retryingRow.attemptID)
        #expect(retained.retryOperation == nil)
        #expect(cancelled.audioCleanup == [existingHead])
        #expect(fixture.audioFileSystem.cleanupCallCount == 0)
        #expect(fixture.audioFileSystem.publishCallCount == 0)

        #expect(
            try await fixture.coordinator.recoverHistoryPolicyCleanup()
                == .pendingLocalRecovery
        )
        let afterHead = try #require(try fixture.envelope())
        #expect(afterHead.revision == 42)
        #expect(afterHead.entries == [retained])
        #expect(afterHead.audioCleanup.isEmpty)
        #expect(fixture.audioFileSystem.cleanedTombstones == [existingHead])
        #expect(
            try await fixture.context.policyStore.load() == committedPolicy
        )
        #expect(fixture.audioFileSystem.publishCallCount == 0)
    }

    @Test func currentRetryLiveOwnerExpiresAndDoesNotWedgePolicyCutover()
        async throws {
        let fixture = try AudioCleanupCoordinatorFixture()
        #expect(
            try await fixture.coordinator.recoverHistoryPolicyCleanup()
                == .complete
        )
        let retry = try failedHistoryTestRetryOperation(
            index: 531,
            state: .reserved
        )
        let currentRow = try failedHistoryTestEntry(
            index: 531,
            policyGeneration: 1,
            retryCount: 1,
            retryOperation: retry
        )
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 50,
                entries: [currentRow],
                audioCleanup: []
            )
        )
        let retryState = fixture.context.failedHistoryRetryState
        let currentPolicy = try #require(
            try await fixture.context.policyStore.load()
        )
        #expect(currentPolicy.policyGeneration == currentRow.policyGeneration)
        let inspectionPolicy = try await failedPolicyReceipt(
            ownerIdentity: fixture.context.ownerIdentity,
            generation: currentPolicy.policyGeneration + 1
        )
        let token = try await fixture.context.operationGate.perform { lease in
            let directive = try await fixture.failedHistoryStore
                .preparePolicyCutoverDirective(
                    using: inspectionPolicy,
                    operationLeaseAuthorization: lease
                )
            guard case .inspectProcessLostRetry(let inspection) = directive
            else {
                Issue.record("Store must mint the exact Retry owner token")
                throw IOSFailedHistoryError.invalidTransition
            }
            let token = inspection.liveOwnerToken
            #expect(
                token.row.policyGeneration == currentPolicy.policyGeneration
            )
            #expect(await retryState.retainLiveOwner(token))
            #expect(await retryState.hasLiveOwner())
            return token
        }
        #expect(!token.operationLeaseAuthorization.provesActiveLease())

        #expect(
            try await fixture.coordinator.setHistoryEnabled(false)
                == .pendingLocalRecovery
        )
        let committedPolicy = try #require(
            try await fixture.context.policyStore.load()
        )
        #expect(committedPolicy.revision == 2)
        #expect(committedPolicy.policyGeneration == 2)
        #expect(committedPolicy.historyEnabled == false)
        let cancelled = try #require(try fixture.envelope())
        let retained = try #require(cancelled.entries.first)
        #expect(cancelled.revision == 51)
        #expect(retained.retryOperation == nil)
        #expect(retained.retryCount == currentRow.retryCount)
        #expect(await retryState.hasLiveOwner() == false)
        #expect(await retryState.hasCancellationReservation() == false)
        #expect(fixture.audioFileSystem.cleanupCallCount == 0)
        #expect(fixture.audioFileSystem.publishCallCount == 0)
    }
}

private func failedPolicyAcceptedPreparation(
    using coordinator: IOSAcceptedHistoryCoordinator
) async throws -> IOSAcceptedOutputDeliveryPreparation {
    let capture = try await coordinator.capture(
        transcriptionModel: "whisper-1",
        transcriptionLanguageCode: "en",
        durationMilliseconds: 1_250
    )
    return try IOSAcceptedOutputDeliveryPreparation(
        deliveryID: UUID(),
        sessionID: UUID(),
        attemptID: UUID(),
        transcriptID: UUID(),
        rawAcceptedText: "accepted before failed cleanup",
        outputIntent: .standard,
        automaticInsertionPreferenceEnabled: true,
        keepLatestResult: true,
        historyCapture: capture
    )
}

private func failedPolicyReceipt(
    ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
    generation: Int64
) async throws -> IOSHistoryPolicyReceipt {
    let state = try IOSHistoryPolicyState(
        revision: generation,
        historyEnabled: true,
        policyGeneration: generation
    )
    let store = IOSHistoryPolicyStore(
        journal: AudioCleanupPolicyJournal(state: state),
        capabilityOwnerIdentity: ownerIdentity
    )
    return try await store.confirm(
        expected: IOSHistoryPolicyExpectation(state: state)
    )
}

private final class AudioCleanupPolicyJournal:
    IOSHistoryPolicyJournalStoring,
    @unchecked Sendable {
    private var snapshot: IOSHistoryPolicyJournalSnapshot
    private var nextToken: UInt64 = 2

    init(state: IOSHistoryPolicyState) {
        snapshot = IOSHistoryPolicyJournalSnapshot(
            state: state,
            fileRevision: IOSStrictProtectedRecordFileRevision(
                testingToken: 1
            )
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

private final class AudioCleanupCoordinatorTestRoot: @unchecked Sendable {
    let parentDirectoryURL: URL
    let applicationSupportDirectoryURL: URL

    init() throws {
        parentDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "failed-audio-cleanup-coordinator-\(UUID().uuidString)",
                isDirectory: true
            )
        applicationSupportDirectoryURL = parentDirectoryURL
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
        try FileManager.default.createDirectory(
            at: applicationSupportDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: parentDirectoryURL)
    }
}

private final class AudioCleanupCoordinatorFixture: @unchecked Sendable {
    let root: AudioCleanupCoordinatorTestRoot
    let registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry
    let context: IOSAcceptedHistoryCoordinatorProcessContext
    let failedFileSystem: FailedHistoryFakeFileSystem
    let failedHistoryStore: IOSFailedHistoryStore
    let pendingRecordingStore: IOSPendingRecordingStore
    let audioFileSystem: CoordinatorCleanupAudioFileSystem
    let coordinator: IOSAcceptedHistoryCoordinator

    var cleanupState: IOSFailedHistoryAudioCleanupOperationState {
        context.failedHistoryAudioCleanupState
    }

    var mutationInterlock: IOSFailedHistoryMutationInterlock {
        context.failedHistoryMutationInterlock
    }

    convenience init() throws {
        try self.init(
            root: AudioCleanupCoordinatorTestRoot(),
            failedFileSystem: FailedHistoryFakeFileSystem(),
            durableAudio: AudioCleanupDurableAudioState()
        )
    }

    init(
        root: AudioCleanupCoordinatorTestRoot,
        failedFileSystem: FailedHistoryFakeFileSystem,
        durableAudio: AudioCleanupDurableAudioState
    ) throws {
        self.root = root
        self.failedFileSystem = failedFileSystem
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        self.registry = registry
        let context = registry.context(
            for: root.applicationSupportDirectoryURL
        )
        self.context = context
        let now = try failedHistoryTestDate(
            offsetMilliseconds: 10_000_000
        )
        let failedHistoryStore = IOSFailedHistoryStore(
            journal: FoundationIOSFailedHistoryJournalRepository(
                fileSystem: failedFileSystem
            ),
            capabilityOwnerIdentity: context.ownerIdentity,
            operationGateIdentity: context.operationGate.identity,
            expectedPendingStoreIdentity:
                context.pendingRecordingStoreIdentity,
            retryLiveOwnerState: context.failedHistoryRetryState,
            repositoryGuard: context.repositoryGuard,
            mutationInterlock: context.failedHistoryMutationInterlock,
            now: { now }
        )
        self.failedHistoryStore = failedHistoryStore
        let audioFileSystem = CoordinatorCleanupAudioFileSystem(
            durableAudio: durableAudio
        )
        self.audioFileSystem = audioFileSystem
        let pendingRecordingStore = IOSPendingRecordingStore(
            journal: FoundationIOSPendingRecordingJournalRepository(
                applicationSupportDirectoryURL:
                    root.applicationSupportDirectoryURL,
                repositoryGuard: context.repositoryGuard
            ),
            audioFileSystem: audioFileSystem,
            operationGate: context.operationGate,
            liveOwnerRegistry: context.pendingRecordingLiveOwnerRegistry,
            capabilityOwnerIdentity: context.ownerIdentity,
            storeIdentity: context.pendingRecordingStoreIdentity,
            repositoryGuard: context.repositoryGuard,
            failedHistoryMutationInterlock:
                context.failedHistoryMutationInterlock,
            failedOwnershipInspector: failedHistoryStore
        )
        self.pendingRecordingStore = pendingRecordingStore
        coordinator = IOSAcceptedHistoryCoordinator(
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
            failedHistoryAudioCleanupState:
                context.failedHistoryAudioCleanupState,
            failedHistoryRetryState: context.failedHistoryRetryState,
            ownerIdentity: context.ownerIdentity,
            repositoryIdentityState: context.repositoryIdentityState,
            repositoryRegistration:
                IOSAcceptedHistoryCoordinatorRepositoryRegistration(
                    registry: registry,
                    context: context,
                    applicationSupportDirectoryURL:
                        root.applicationSupportDirectoryURL
                )
        )
    }

    func install(_ envelope: IOSFailedHistoryEnvelope) throws {
        failedFileSystem.install(
            try IOSFailedHistoryWireCodec.encode(envelope)
        )
    }

    func envelope() throws -> IOSFailedHistoryEnvelope? {
        guard let data = failedFileSystem.file?.data else { return nil }
        return try IOSFailedHistoryWireCodec.decode(data)
    }

    func filteredEntries() async throws -> [IOSFailedHistoryEntry] {
        let context = context
        let failedHistoryStore = failedHistoryStore
        return try await context.operationGate.perform { lease in
            let state = try #require(try await context.policyStore.load())
            let receipt = try await context.policyStore.confirm(
                expected: IOSHistoryPolicyExpectation(state: state)
            )
            return try await failedHistoryStore.loadPolicyFilteredEntries(
                using: receipt,
                operationLeaseAuthorization: lease
            )
        }
    }
}

private final class AudioCleanupDurableAudioState: @unchecked Sendable {
    private let lock = NSLock()
    private var absentIdentifiers: Set<String> = []

    func markAbsent(_ relativeIdentifier: String) {
        _ = lock.withLock {
            absentIdentifiers.insert(relativeIdentifier)
        }
    }

    func isAbsent(_ relativeIdentifier: String) -> Bool {
        lock.withLock { absentIdentifiers.contains(relativeIdentifier) }
    }
}

private final class CoordinatorCleanupAudioFileSystem:
    IOSPendingRecordingAudioFileSystem,
    @unchecked Sendable {
    enum Step: Equatable, Sendable {
        case removeThenFail
    }

    private struct Values {
        var steps: [Step] = []
        var cleanupAuthorizations:
            [IOSFailedHistoryAudioCleanupAuthorization] = []
        var alreadyAbsentReceiptCount = 0
        var genericRemoveCallCount = 0
        var publishCallCount = 0
        var acquireValidatedCallCount = 0
        var explicitDeleteUsedFreshLease: Bool?
    }

    private let lock = NSLock()
    private let durableAudio: AudioCleanupDurableAudioState
    private var values = Values()

    init(durableAudio: AudioCleanupDurableAudioState) {
        self.durableAudio = durableAudio
    }

    var cleanupCallCount: Int {
        lock.withLock { values.cleanupAuthorizations.count }
    }

    var cleanedTombstones: [IOSFailedHistoryAudioCleanup] {
        lock.withLock { values.cleanupAuthorizations.map(\.tombstone) }
    }

    var alreadyAbsentReceiptCount: Int {
        lock.withLock { values.alreadyAbsentReceiptCount }
    }

    var genericRemoveCallCount: Int {
        lock.withLock { values.genericRemoveCallCount }
    }

    var publishCallCount: Int {
        lock.withLock { values.publishCallCount }
    }

    var acquireValidatedCallCount: Int {
        lock.withLock { values.acquireValidatedCallCount }
    }

    var explicitDeleteUsedFreshLease: Bool? {
        lock.withLock { values.explicitDeleteUsedFreshLease }
    }

    func enqueue(_ step: Step) {
        lock.withLock { values.steps.append(step) }
    }

    #if DEBUG
    func requireEmptyNamespace() async throws {}
    #endif

    func validateProtectedAudioNamespace(
        _ inventory: IOSProtectedAudioNamespaceInventory
    ) async throws {
        _ = inventory
    }

    func reconcileProtectedAudioCleanup(
        using authorization:
            IOSPendingRecordingProtectedAudioCleanupAuthorization
    ) async throws -> IOSPendingRecordingProtectedAudioCleanupEvidence {
        let cleanup = authorization.cleanupAuthorization
        let step = lock.withLock { () -> Step? in
            values.cleanupAuthorizations.append(cleanup)
            if case .explicitDelete(let receipt) = cleanup.purpose {
                values.explicitDeleteUsedFreshLease =
                    !receipt.operationLeaseAuthorization.provesActiveLease()
                    && cleanup.operationLeaseAuthorization.provesActiveLease()
                    && !receipt.operationLeaseAuthorization
                        .provesSameActiveLease(
                            as: cleanup.operationLeaseAuthorization
                        )
            }
            return values.steps.isEmpty ? nil : values.steps.removeFirst()
        }

        if step == .removeThenFail {
            durableAudio.markAbsent(
                cleanup.tombstone.audioRelativeIdentifier
            )
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        if durableAudio.isAbsent(
            cleanup.tombstone.audioRelativeIdentifier
        ) {
            lock.withLock { values.alreadyAbsentReceiptCount += 1 }
            return IOSPendingRecordingProtectedAudioCleanupEvidence(
                testingAlreadyAbsent: cleanup
            )
        }
        durableAudio.markAbsent(cleanup.tombstone.audioRelativeIdentifier)
        return IOSPendingRecordingProtectedAudioCleanupEvidence(
            testingRemoved: cleanup
        )
    }

    #if DEBUG
    func publishProtectedCopy(
        from source: AudioRecordingArtifact,
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat,
        durationMilliseconds: Int64
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        _ = source
        _ = attemptID
        _ = format
        _ = durationMilliseconds
        lock.withLock { values.publishCallCount += 1 }
        throw IOSPendingRecordingAudioFileSystemError.writeFailed
    }
    #endif

    func publishProtectedCopy(
        from source: AudioRecordingArtifact,
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat,
        durationMilliseconds: Int64,
        inventory: IOSProtectedAudioNamespaceInventory
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        _ = source
        _ = attemptID
        _ = format
        _ = durationMilliseconds
        _ = inventory
        lock.withLock { values.publishCallCount += 1 }
        throw IOSPendingRecordingAudioFileSystemError.writeFailed
    }

    func validatePublishedAudio(
        relativeIdentifier: String,
        attemptID: UUID,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) async throws -> AudioRecordingArtifact {
        _ = attemptID
        return audioArtifact(
            relativeIdentifier: relativeIdentifier,
            durationMilliseconds: durationMilliseconds,
            byteCount: byteCount
        )
    }

    func acquireValidatedPublishedAudio(
        relativeIdentifier: String,
        attemptID: UUID,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        _ = attemptID
        lock.withLock { values.acquireValidatedCallCount += 1 }
        return CoordinatorCleanupAudioLease(
            relativeIdentifier: relativeIdentifier,
            audioArtifact: audioArtifact(
                relativeIdentifier: relativeIdentifier,
                durationMilliseconds: durationMilliseconds,
                byteCount: byteCount
            ),
            durationMilliseconds: durationMilliseconds
        )
    }

    func removePublishedAudioIfPresent(
        relativeIdentifier: String,
        attemptID: UUID,
        expectedByteCount: Int64
    ) async throws -> Bool {
        _ = relativeIdentifier
        _ = attemptID
        _ = expectedByteCount
        lock.withLock { values.genericRemoveCallCount += 1 }
        return false
    }

    private func audioArtifact(
        relativeIdentifier: String,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) -> AudioRecordingArtifact {
        AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(
                    relativeIdentifier.replacingOccurrences(
                        of: "/",
                        with: "_"
                    )
                ),
            duration: TimeInterval(durationMilliseconds) / 1_000,
            byteCount: byteCount
        )
    }
}

private final class CoordinatorCleanupAudioLease:
    IOSPendingRecordingPublishedAudioLease,
    @unchecked Sendable {
    let relativeIdentifier: String
    let audioArtifact: AudioRecordingArtifact
    let durationMilliseconds: Int64

    init(
        relativeIdentifier: String,
        audioArtifact: AudioRecordingArtifact,
        durationMilliseconds: Int64
    ) {
        self.relativeIdentifier = relativeIdentifier
        self.audioArtifact = audioArtifact
        self.durationMilliseconds = durationMilliseconds
    }

    func revalidate() async throws -> AudioRecordingArtifact { audioArtifact }

    func read(
        atOffset offset: Int64,
        maximumByteCount: Int
    ) async throws -> Data {
        _ = offset
        _ = maximumByteCount
        return Data()
    }

    func release() {}
}

private func audioCleanupPendingRecording(
    index: Int
) throws -> IOSPendingRecording {
    let attemptID = failedHistoryTestUUID(namespace: 0x79, index: index)
    return try IOSPendingRecording(
        attemptID: attemptID,
        audioRelativeIdentifier: IOSPendingRecordingStorageLocation
            .relativeAudioIdentifier(for: attemptID, format: .m4a),
        createdAt: failedHistoryTestDate(
            offsetMilliseconds: Int64(index * 100)
        ),
        updatedAt: failedHistoryTestDate(
            offsetMilliseconds: Int64(index * 100 + 1)
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
