import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSFailedHistoryRetryCoordinatorTests {
    @Test func dispatchRegistersBeforeGateReleaseAndExecutesOnlyOnce()
        async throws {
        let fixture = try RetryCoordinatorFixture()
        let row = try await fixture.prepareReadyFailure()
        let handoff = try await fixture.coordinator
            .prepareFailedHistoryRetry(
                attemptID: row.attemptID,
                setup: try retryCoordinatorSetup(
                    transcriptionConfiguration: TranscriptionConfiguration(
                        model: "retry-model",
                        language: .french,
                        freeformPrompt: "secret-retry-prompt-canary"
                    )
                )
            )

        let dispatched = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        let dispatchedRow = try #require(dispatched.entries.first)
        #expect(dispatchedRow.retryCount == 1)
        #expect(dispatchedRow.retryOperation?.state == .providerDispatched)
        #expect(dispatchedRow.transcriptionModel == "retry-model")
        #expect(dispatchedRow.transcriptionLanguageCode == "fr")
        #expect(await fixture.context.failedHistoryRetryState.hasLiveOwner())

        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        ) {
            _ = try await fixture.coordinator.prepareFailedHistoryRetry(
                attemptID: row.attemptID,
                setup: try retryCoordinatorSetup()
            )
        }

        let completion = try await handoff.execute { audio, setup in
            let gateReleased = (try? await fixture.context.operationGate
                .perform { _ in true }) == true
            let bytes = try? await audio.read(
                atOffset: 0,
                maximumByteCount: 64
            )
            return gateReleased && bytes?.isEmpty == false
                && setup.keepLatestResult
                ? "secret-provider-result-canary"
                : "failed"
        }
        #expect(completion.outcome == "secret-provider-result-canary")
        #expect(
            completion.dispatchReceipt.retryOperation.state
                == .providerDispatched
        )
        #expect(
            String(describing: completion)
                == "IOSFailedHistoryRetryProviderCompletion(redacted)"
        )
        #expect(
            !String(describing: completion).contains(
                "secret-provider-result-canary"
            )
        )
        #expect(completion.customMirror.children.isEmpty)
        await #expect(throws: IOSPendingRecordingError.dispatchAlreadyCommitted) {
            _ = try await handoff.execute { _, _ in false }
        }
        #expect(await fixture.context.failedHistoryRetryState.hasLiveOwner())
    }

    @Test func setupIsFrozenAndRejectedBeforeDurableReservation()
        async throws {
        #expect(throws: IOSFailedHistoryError.invalidTransition) {
            _ = try IOSFailedHistoryRetrySetupSnapshot(
                credentialEligibility: .unavailable,
                transcriptionConfiguration: .defaults,
                transcriptionPromptComposition: retryPromptComposition(),
                textCorrectionConfiguration: .defaults,
                postProcessingConfiguration: .defaults,
                translationConfiguration: nil,
                keepLatestResult: true
            )
        }
        let nearbyContext = try #require(
            TranscriptionPromptContext("secret-nearby-text-canary")
        )
        #expect(throws: IOSFailedHistoryError.invalidTransition) {
            _ = try IOSFailedHistoryRetrySetupSnapshot(
                credentialEligibility: .available,
                transcriptionConfiguration: .defaults,
                transcriptionPromptComposition:
                    TranscriptionPromptComposition(
                        resolvedFreeformPrompt: nil,
                        context: nearbyContext,
                        emojiCommandsConfiguration: .defaults,
                        customDictionary: .empty
                    ),
                textCorrectionConfiguration: .defaults,
                postProcessingConfiguration: .defaults,
                translationConfiguration: nil,
                keepLatestResult: true
            )
        }
        let dormantInvalidCorrection = TextCorrectionConfiguration(
            isEnabled: false,
            modelPreset: .custom,
            customModel: String(repeating: "x", count: 300)
        )
        _ = try IOSFailedHistoryRetrySetupSnapshot(
            credentialEligibility: .available,
            transcriptionConfiguration: .defaults,
            transcriptionPromptComposition: retryPromptComposition(),
            textCorrectionConfiguration: dormantInvalidCorrection,
            postProcessingConfiguration: .defaults,
            translationConfiguration: nil,
            keepLatestResult: true
        )
        var enabledInvalidCorrection = dormantInvalidCorrection
        enabledInvalidCorrection.isEnabled = true
        #expect(throws: IOSFailedHistoryError.invalidTransition) {
            _ = try IOSFailedHistoryRetrySetupSnapshot(
                credentialEligibility: .available,
                transcriptionConfiguration: .defaults,
                transcriptionPromptComposition: retryPromptComposition(),
                textCorrectionConfiguration: enabledInvalidCorrection,
                postProcessingConfiguration: .defaults,
                translationConfiguration: nil,
                keepLatestResult: true
            )
        }

        let fixture = try RetryCoordinatorFixture()
        let row = try await fixture.prepareReadyFailure()
        let incompatible = try IOSFailedHistoryRetrySetupSnapshot(
            credentialEligibility: .available,
            transcriptionConfiguration: .defaults,
            transcriptionPromptComposition: retryPromptComposition(),
            textCorrectionConfiguration: .defaults,
            postProcessingConfiguration: .defaults,
            translationConfiguration: TranslationConfiguration(
                targetLanguage: .english
            ),
            keepLatestResult: false
        )
        #expect(
            String(describing: incompatible)
                == "IOSFailedHistoryRetrySetupSnapshot(redacted)"
        )
        await #expect(throws: IOSFailedHistoryError.invalidTransition) {
            _ = try await fixture.coordinator.prepareFailedHistoryRetry(
                attemptID: row.attemptID,
                setup: incompatible
            )
        }
        let unchanged = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        #expect(unchanged.entries.first?.retryOperation == nil)
        #expect(unchanged.entries.first?.retryCount == 0)
        #expect(
            await fixture.context.failedHistoryRetryState.hasLiveOwner()
                == false
        )
    }

    @Test func pendingAndFailedProviderOwnersExcludeEachOtherAtRoot()
        async throws {
        do {
            let fixture = try RetryCoordinatorFixture()
            let failedRow = try await fixture.prepareReadyFailure()
            let pending = try await fixture.prepareReadyPending()
            let pendingHandoff = try await fixture.context
                .pendingRecordingStore.beginTranscription(
                    expected: IOSPendingRecordingCASExpectation(
                        recording: pending
                    ),
                    transcriptionID: UUID()
                )
            await #expect(throws: IOSPendingRecordingError.localRecoveryPending) {
                _ = try await fixture.coordinator.prepareFailedHistoryRetry(
                    attemptID: failedRow.attemptID,
                    setup: try retryCoordinatorSetup()
                )
            }
            let unchanged = try #require(
                try await fixture.context.failedHistoryStore.load()
            )
            #expect(unchanged.entries.first?.retryOperation == nil)
            #expect(unchanged.entries.first?.retryCount == 0)
            _ = pendingHandoff
        }

        do {
            let fixture = try RetryCoordinatorFixture()
            let failedRow = try await fixture.prepareReadyFailure()
            let retryHandoff = try await fixture.coordinator
                .prepareFailedHistoryRetry(
                    attemptID: failedRow.attemptID,
                    setup: try retryCoordinatorSetup()
                )
            do {
                _ = try await fixture.prepareReadyPending()
                Issue.record("A live failed Retry must exclude Pending work.")
            } catch is IOSPendingRecordingError {
                // The exact Pending surface remains typed and no Pending
                // journal is published while Retry owns the descriptor/root.
            }
            #expect(try fixture.rawPendingRecording() == nil)
            try await retryHandoff.cancel()
        }
    }

    @Test func durableOutboxHeadBlocksRetryBeforeReservation() async throws {
        let fixture = try RetryCoordinatorFixture()
        let original = try await fixture.prepareReadyFailure()
        try await fixture.prepareOutboxHead()

        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        ) {
            _ = try await fixture.coordinator.prepareFailedHistoryRetry(
                attemptID: original.attemptID,
                setup: try retryCoordinatorSetup()
            )
        }

        let retained = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        #expect(retained.entries == [original])
        #expect(retained.entries.first?.retryOperation == nil)
        #expect(
            await fixture.context.failedHistoryRetryState.hasLiveOwner()
                == false
        )
    }

    @Test func exactCancellationMakesTheSameRowRetryableAgain()
        async throws {
        let fixture = try RetryCoordinatorFixture()
        let row = try await fixture.prepareReadyFailure()
        let first = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: row.attemptID,
            setup: try retryCoordinatorSetup()
        )

        try await first.cancel()
        try await first.cancel()
        var cancelled = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        var cancelledRow = try #require(cancelled.entries.first)
        #expect(cancelledRow.retryOperation == nil)
        #expect(cancelledRow.retryCount == 1)
        #expect(cancelledRow.failureCategory == row.failureCategory)
        #expect(cancelledRow.pipelineStage == row.pipelineStage)
        #expect(fixture.audioExists(for: cancelledRow))
        #expect(
            await fixture.context.failedHistoryRetryState.hasLiveOwner()
                == false
        )

        let second = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: row.attemptID,
            setup: try retryCoordinatorSetup(
                transcriptionConfiguration: TranscriptionConfiguration(
                    model: "second-model",
                    language: .german
                )
            )
        )
        try await second.cancel()
        cancelled = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        cancelledRow = try #require(cancelled.entries.first)
        #expect(cancelledRow.retryOperation == nil)
        #expect(cancelledRow.retryCount == 2)
        #expect(cancelledRow.transcriptionModel == "second-model")
        #expect(cancelledRow.transcriptionLanguageCode == "de")
    }

    @Test func cancellationDrainsNoncooperativeLateResultBeforeRowClears()
        async throws {
        let fixture = try RetryCoordinatorFixture()
        let row = try await fixture.prepareReadyFailure()
        let handoff = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: row.attemptID,
            setup: try retryCoordinatorSetup()
        )
        let started = RetryCoordinatorLatch()
        let release = RetryCoordinatorLatch()
        let execution = Task {
            try await handoff.execute { _, _ in
                await started.open()
                await release.wait()
                return "late-success"
            }
        }
        await started.wait()

        let cancellation = Task {
            try await handoff.cancel()
        }
        await Task.yield()
        let stillDispatched = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        #expect(
            stillDispatched.entries.first?.retryOperation?.state
                == .providerDispatched
        )
        #expect(await fixture.context.failedHistoryRetryState.hasLiveOwner())

        await release.open()
        try await cancellation.value
        await #expect(throws: CancellationError.self) {
            _ = try await execution.value
        }
        let cancelled = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        #expect(cancelled.entries.first?.retryOperation == nil)
        #expect(
            await fixture.context.failedHistoryRetryState.hasLiveOwner()
                == false
        )
    }

    @Test func callerCancellationUsesFreshCleanupTaskAndClearsExactRetry()
        async throws {
        let fixture = try RetryCoordinatorFixture()
        let row = try await fixture.prepareReadyFailure()
        let handoff = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: row.attemptID,
            setup: try retryCoordinatorSetup()
        )
        let started = RetryCoordinatorLatch()
        let execution = Task {
            try await handoff.execute { _, _ in
                await started.open()
                while !Task.isCancelled {
                    await Task.yield()
                }
                return "cancelled"
            }
        }
        await started.wait()

        execution.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await execution.value
        }
        try await retryCoordinatorEventually {
            let envelope = try await fixture.context.failedHistoryStore.load()
            let hasLiveOwner = await fixture.context
                .failedHistoryRetryState.hasLiveOwner()
            return envelope?.entries.first?.retryOperation == nil
                && !hasLiveOwner
        }
    }

    @Test func providerSelfCancellationDoesNotWaitForItsOwnDrain()
        async throws {
        let fixture = try RetryCoordinatorFixture()
        let row = try await fixture.prepareReadyFailure()
        let handoff = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: row.attemptID,
            setup: try retryCoordinatorSetup()
        )

        await #expect(throws: CancellationError.self) {
            _ = try await handoff.execute { _, _ in
                try? await handoff.cancel()
                return "late-self-result"
            }
        }
        try await retryCoordinatorEventually {
            let envelope = try await fixture.context.failedHistoryStore.load()
            let hasLiveOwner = await fixture.context
                .failedHistoryRetryState.hasLiveOwner()
            return envelope?.entries.first?.retryOperation == nil
                && !hasLiveOwner
        }
    }

    @Test func coordinatorReconcilesEveryLocalCommitUncertainty()
        async throws {
        for boundary in RetryCoordinatorUncertaintyBoundary.allCases {
            for outcomeVisible in [false, true] {
                let fixture = try RetryCoordinatorUncertaintyFixture()
                let row = try await fixture.prepareReadyFailure()
                let failure = FailedHistoryFakeFileSystem.Failure(
                    error: .commitUncertain,
                    commitBeforeThrowing: outcomeVisible
                )
                switch boundary {
                case .reservation:
                    fixture.failedFileSystem.replaceFailure = failure
                case .dispatch:
                    fixture.failedFileSystem
                        .replaceFailureAfterSuccessfulReplaces = (
                            remaining: 1,
                            failure: failure
                        )
                case .cancellation:
                    break
                }

                let handoff = try await fixture.coordinator
                    .prepareFailedHistoryRetry(
                        attemptID: row.attemptID,
                        setup: try retryCoordinatorSetup()
                    )
                let dispatched = try #require(
                    try await fixture.failedHistoryStore.load()
                )
                #expect(dispatched.entries.first?.retryCount == 1)
                #expect(
                    dispatched.entries.first?.retryOperation?.state
                        == .providerDispatched
                )
                #expect(await fixture.retryState.hasLiveOwner())

                if boundary == .cancellation {
                    fixture.failedFileSystem.replaceFailure = failure
                }
                try await handoff.cancel()
                let cancelled = try #require(
                    try await fixture.failedHistoryStore.load()
                )
                #expect(cancelled.entries.first?.retryOperation == nil)
                #expect(cancelled.entries.first?.retryCount == 1)
                #expect(await fixture.retryState.hasLiveOwner() == false)
                #expect(!fixture.mutationInterlock.isBlocked)
            }
        }
    }

    @Test func retryEntrypointResumesRetainedCleanupAfterDeinitExhaustion()
        async throws {
        let fixture = try RetryCoordinatorUncertaintyFixture()
        let row = try await fixture.prepareReadyFailure()
        var handoff: IOSFailedHistoryRetryHandoff? = try await fixture
            .coordinator.prepareFailedHistoryRetry(
                attemptID: row.attemptID,
                setup: try retryCoordinatorSetup()
            )
        fixture.failedFileSystem.persistentReplaceFailure = .init(
            error: .commitUncertain,
            commitBeforeThrowing: false
        )

        handoff = nil
        #expect(handoff == nil)
        #expect(await fixture.retryState.hasLiveOwner())
        try await retryCoordinatorEventually {
            fixture.mutationInterlock.isBlocked
        }

        fixture.failedFileSystem.persistentReplaceFailure = nil
        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        ) {
            _ = try await fixture.coordinator.prepareFailedHistoryRetry(
                attemptID: row.attemptID,
                setup: try retryCoordinatorSetup()
            )
        }
        try await retryCoordinatorEventually {
            guard !fixture.mutationInterlock.isBlocked,
                  let envelope = try? await fixture.failedHistoryStore.load()
            else {
                return false
            }
            let hasLiveOwner = await fixture.retryState.hasLiveOwner()
            return envelope.entries.first?.retryOperation == nil
                && !hasLiveOwner
        }
        #expect(!fixture.mutationInterlock.isBlocked)

        let resumed = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: row.attemptID,
            setup: try retryCoordinatorSetup()
        )
        let retried = try #require(
            try await fixture.failedHistoryStore.load()
        )
        #expect(retried.entries.first?.retryCount == 2)
        try await resumed.cancel()
    }

    @Test func unconsumedHandoffDeinitUsesExactDurableCancellation()
        async throws {
        let fixture = try RetryCoordinatorFixture()
        let row = try await fixture.prepareReadyFailure()
        var handoff: IOSFailedHistoryRetryHandoff? = try await fixture
            .coordinator.prepareFailedHistoryRetry(
                attemptID: row.attemptID,
                setup: try retryCoordinatorSetup()
            )
        #expect(handoff != nil)
        #expect(await fixture.context.failedHistoryRetryState.hasLiveOwner())

        handoff = nil
        try await retryCoordinatorEventually {
            let envelope = try await fixture.context.failedHistoryStore.load()
            let hasLiveOwner = await fixture.context
                .failedHistoryRetryState.hasLiveOwner()
            return envelope?.entries.first?.retryOperation == nil
                && !hasLiveOwner
        }
        let cancelled = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        #expect(cancelled.entries.first?.retryCount == 1)
        #expect(fixture.audioExists(for: try #require(cancelled.entries.first)))
    }

    @Test func pipelineFailureCommitsMappedThenPreservedOutcome()
        async throws {
        let fixture = try RetryCoordinatorFixture()
        let original = try await fixture.prepareReadyFailure()
        let first = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: original.attemptID,
            setup: try retryCoordinatorSetup()
        )
        let firstResult = try await first.executePipeline(
            IOSFailedHistoryRetryPipeline(
                provider: RetryCoordinatorPipelineProvider(
                    transcription: .failure(.rateLimited)
                ),
                usageRecorder: RetryCoordinatorUsageRecorder()
            )
        )
        guard case .failed = firstResult else {
            Issue.record("A mapped provider failure must remain failed.")
            return
        }
        #expect(
            String(describing: firstResult)
                == "IOSFailedHistoryRetryPipelineExecutionResult(redacted)"
        )

        let retainedEnvelope = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        var retained = try #require(retainedEnvelope.entries.first)
        #expect(retained.retryOperation == nil)
        #expect(retained.retryCount == 1)
        #expect(retained.failureCategory == .rateLimited)
        #expect(retained.pipelineStage == .transcription)
        #expect(retained.updatedAt > original.updatedAt)
        #expect(fixture.audioExists(for: retained))
        #expect(
            await fixture.context.failedHistoryRetryState.hasLiveOwner()
                == false
        )

        let second = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: original.attemptID,
            setup: try retryCoordinatorSetup()
        )
        let secondResult = try await second.executePipeline(
            IOSFailedHistoryRetryPipeline(
                provider: RetryCoordinatorPipelineProvider(
                    transcription: .failure(.invalidRecording)
                ),
                usageRecorder: RetryCoordinatorUsageRecorder()
            )
        )
        guard case .failed = secondResult else {
            Issue.record("An unmappable provider failure must remain failed.")
            return
        }

        let secondEnvelope = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        let secondRetained = try #require(secondEnvelope.entries.first)
        #expect(secondRetained.retryOperation == nil)
        #expect(secondRetained.retryCount == 2)
        #expect(secondRetained.failureCategory == retained.failureCategory)
        #expect(secondRetained.pipelineStage == retained.pipelineStage)
        #expect(secondRetained.updatedAt > retained.updatedAt)
        retained = secondRetained
        #expect(fixture.audioExists(for: retained))
    }

    @Test func translationFailureUsesItsActualStageAfterUsage()
        async throws {
        let fixture = try RetryCoordinatorFixture()
        let original = try await fixture.prepareReadyFailure(
            outputIntent: .translate
        )
        let handoff = try await fixture.coordinator
            .prepareFailedHistoryRetry(
                attemptID: original.attemptID,
                setup: try retryCoordinatorSetup(
                    translationConfiguration: TranslationConfiguration(
                        targetLanguage: .english
                    )
                )
            )
        let usage = RetryCoordinatorUsageRecorder()
        let result = try await handoff.executePipeline(
            IOSFailedHistoryRetryPipeline(
                provider: RetryCoordinatorPipelineProvider(
                    transcription: .success("transient transcript"),
                    translation: .failure(.providerUnavailable)
                ),
                usageRecorder: usage
            )
        )

        guard case .failed = result else {
            Issue.record("Strict Translation failure must remain failed.")
            return
        }
        let retainedEnvelope = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        let retained = try #require(retainedEnvelope.entries.first)
        #expect(retained.retryCount == 1)
        #expect(retained.failureCategory == .providerUnavailable)
        #expect(retained.pipelineStage == .translation)
        #expect(retained.retryOperation == nil)
        #expect(await usage.callCount() == 1)
        #expect(
            await fixture.context.failedHistoryRetryState.hasLiveOwner()
                == false
        )
    }

    @Test func droppedAcceptedProviderOutputReturnsRowToRetryableState()
        async throws {
        let fixture = try RetryCoordinatorFixture()
        let original = try await fixture.prepareReadyFailure()
        let handoff = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: original.attemptID,
            setup: try retryCoordinatorSetup()
        )
        let usage = RetryCoordinatorUsageRecorder()
        var acceptedOutput:
            IOSFailedHistoryRetryAcceptedProviderOutput?
        var result: IOSFailedHistoryRetryPipelineExecutionResult? =
            try await handoff.executePipeline(
            IOSFailedHistoryRetryPipeline(
                provider: RetryCoordinatorPipelineProvider(
                    transcription: .success("secret accepted result")
                ),
                usageRecorder: usage
            )
        )
        switch try #require(result) {
        case .accepted(let output):
            acceptedOutput = output
        case .failed:
            Issue.record("A valid provider result must be accepted.")
            return
        }
        #expect(acceptedOutput?.transcript.text == "secret accepted result")
        #expect(
            String(describing: acceptedOutput)
                == "Optional(IOSFailedHistoryRetryAcceptedProviderOutput(redacted))"
        )
        #expect(await usage.callCount() == 1)
        #expect(await fixture.context.failedHistoryRetryState.hasLiveOwner())

        result = nil
        acceptedOutput = nil
        try await retryCoordinatorEventually {
            let envelope = try await fixture.context.failedHistoryStore.load()
            let hasLiveOwner = await fixture.context
                .failedHistoryRetryState.hasLiveOwner()
            return envelope?.entries.first?.retryOperation == nil
                && !hasLiveOwner
        }

        let retainedEnvelope = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        let retained = try #require(retainedEnvelope.entries.first)
        #expect(retained.retryCount == 1)
        #expect(retained.failureCategory == original.failureCategory)
        #expect(retained.pipelineStage == original.pipelineStage)
        #expect(retained.updatedAt > original.updatedAt)
        #expect(fixture.audioExists(for: retained))
    }

    @Test func acceptedProviderOutputCommitsExactDeliveryHistoryAndCleanup()
        async throws {
        let fixture = try RetryCoordinatorFixture()
        let original = try await fixture.prepareReadyFailure()
        let handoff = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: original.attemptID,
            setup: try retryCoordinatorSetup()
        )
        let provider = RetryCoordinatorPipelineProvider(
            transcription: .success("secret accepted retry result")
        )
        let usage = RetryCoordinatorUsageRecorder()
        var output: IOSFailedHistoryRetryAcceptedProviderOutput?
        do {
            let execution = try await handoff.executePipeline(
                IOSFailedHistoryRetryPipeline(
                    provider: provider,
                    usageRecorder: usage
                )
            )
            guard case .accepted(let accepted) = execution else {
                Issue.record("A valid provider result must be accepted.")
                return
            }
            output = accepted
        }

        let retryOperation: IOSFailedHistoryRetryOperation
        do {
            let accepted = try #require(output)
            retryOperation = accepted.dispatchReceipt.retryOperation
            let firstResolution = try await accepted.accept()
            if firstResolution != .committed {
                let phase = await fixture.context.acceptanceState.current()?
                    .phase
                let phaseName = switch phase {
                case .deliveryAccepted: "deliveryAccepted"
                case .deliveryAuthorized: "deliveryAuthorized"
                case .policyConfirmed: "policyConfirmed"
                case .rowDecided: "rowDecided"
                case .policyRevalidated: "policyRevalidated"
                case .invalidationConfirmed: "invalidationConfirmed"
                case .abandoningExpired: "abandoningExpired"
                case .confirmingExpired: "confirmingExpired"
                case .removingExpired: "removingExpired"
                case nil: "none"
                }
                Issue.record("Retry acceptance stopped at \(phaseName).")
            }
            #expect(firstResolution == .committed)
            #expect(try await accepted.accept() == .committed)
        }

        guard case .active(let delivery)? = try await fixture.context
            .deliveryStore.load() else {
            Issue.record("Retry success must commit one active delivery.")
            return
        }
        #expect(delivery.deliveryID == retryOperation.deliveryID)
        #expect(delivery.sessionID == retryOperation.sessionID)
        #expect(delivery.attemptID == original.attemptID)
        #expect(delivery.transcriptID == retryOperation.transcriptID)
        #expect(delivery.acceptedText == "secret accepted retry result")
        #expect(delivery.outputIntent == .standard)
        #expect(!delivery.automaticInsertionPreferenceEnabled)
        #expect(delivery.keepLatestResult)
        #expect(delivery.publicationGeneration == 0)
        #expect(delivery.historyWrite?.state == .committed)

        let history = try #require(
            try await fixture.context.acceptedHistoryStore.load()
        )
        #expect(history.entries.count == 1)
        #expect(history.entries.first?.deliveryID == retryOperation.deliveryID)
        #expect(history.entries.first?.transcriptID == retryOperation.transcriptID)
        #expect(
            history.entries.first?.acceptedText
                == "secret accepted retry result"
        )

        let failed = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        let tombstone = try #require(failed.audioCleanup.first)
        #expect(failed.entries.isEmpty)
        #expect(failed.audioCleanup.count == 1)
        #expect(tombstone.attemptID == original.attemptID)
        #expect(tombstone.policyGeneration == original.policyGeneration)
        #expect(
            tombstone.audioRelativeIdentifier
                == original.audioRelativeIdentifier
        )
        #expect(tombstone.byteCount == original.byteCount)
        #expect(fixture.audioExists(for: original))
        #expect(await provider.transcriptionCallCount() == 1)
        #expect(await usage.callCount() == 1)
        #expect(
            await fixture.context.failedHistoryRetryState.hasLiveOwner()
                == false
        )

        output = nil
        try await Task.sleep(for: .milliseconds(50))
        let afterDeinit = try #require(
            try await fixture.context.failedHistoryStore.load()
        )
        #expect(afterDeinit == failed)
        #expect(await provider.transcriptionCallCount() == 1)
    }

    @Test func acceptedProviderOutputPreservesDisabledKeepLatest()
        async throws {
        let fixture = try RetryCoordinatorFixture()
        let original = try await fixture.prepareReadyFailure()
        let handoff = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: original.attemptID,
            setup: try retryCoordinatorSetup(keepLatestResult: false)
        )
        let provider = RetryCoordinatorPipelineProvider(
            transcription: .success("accepted without latest result")
        )
        let execution = try await handoff.executePipeline(
            IOSFailedHistoryRetryPipeline(
                provider: provider,
                usageRecorder: RetryCoordinatorUsageRecorder()
            )
        )
        guard case .accepted(let output) = execution else {
            Issue.record("A valid provider result must be accepted.")
            return
        }

        #expect(try await output.accept() == .committed)
        guard case .active(let delivery)? = try await fixture.context
            .deliveryStore.load() else {
            Issue.record("Retry success must commit one active delivery.")
            return
        }
        #expect(!delivery.keepLatestResult)
        #expect(!delivery.automaticInsertionPreferenceEnabled)
        #expect(delivery.historyWrite?.state == .committed)
        #expect(await provider.transcriptionCallCount() == 1)
        #expect(
            try await fixture.context.failedHistoryStore.load()?
                .audioCleanup.count == 1
        )
    }

    @Test func acceptedRetryTransfersTheExactPendingPredecessor()
        async throws {
        let fixture = try RetryCoordinatorFixture()
        let original = try await fixture.prepareReadyFailure()
        let predecessor = try await fixture.preparePendingDeliveryPredecessor()
        let handoff = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: original.attemptID,
            setup: try retryCoordinatorSetup()
        )
        let provider = RetryCoordinatorPipelineProvider(
            transcription: .success("accepted after predecessor transfer")
        )
        let execution = try await handoff.executePipeline(
            IOSFailedHistoryRetryPipeline(
                provider: provider,
                usageRecorder: RetryCoordinatorUsageRecorder()
            )
        )
        guard case .accepted(let output) = execution else {
            Issue.record("A valid provider result must be accepted.")
            return
        }

        #expect(try await output.accept() == .committed)
        let outbox = try #require(
            try await fixture.context.outboxStore.load()
        )
        #expect(outbox.entries.count == 1)
        #expect(outbox.entries.first?.deliveryID == predecessor.deliveryID)
        guard case .active(let current)? = try await fixture.context
            .deliveryStore.load() else {
            Issue.record("Retry replacement must remain active.")
            return
        }
        #expect(current.deliveryID == output.dispatchReceipt.retryOperation.deliveryID)
        #expect(current.historyWrite?.state == .committed)
        #expect(
            try await fixture.context.failedHistoryStore.load()?
                .audioCleanup.count == 1
        )
        #expect(await provider.transcriptionCallCount() == 1)
    }

    @Test func concurrentAcceptedProviderOutputWaitersShareOneSuccess()
        async throws {
        let fixture = try RetryCoordinatorFixture()
        let original = try await fixture.prepareReadyFailure()
        let handoff = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: original.attemptID,
            setup: try retryCoordinatorSetup()
        )
        let provider = RetryCoordinatorPipelineProvider(
            transcription: .success("one shared accepted result")
        )
        let execution = try await handoff.executePipeline(
            IOSFailedHistoryRetryPipeline(
                provider: provider,
                usageRecorder: RetryCoordinatorUsageRecorder()
            )
        )
        guard case .accepted(let output) = execution else {
            Issue.record("A valid provider result must be accepted.")
            return
        }

        async let first = output.accept()
        async let second = output.accept()
        let firstResolution = try await first
        let secondResolution = try await second

        #expect(firstResolution == .committed)
        #expect(secondResolution == .committed)
        #expect(await provider.transcriptionCallCount() == 1)
        #expect(
            try await fixture.context.failedHistoryStore.load()?
                .audioCleanup.count == 1
        )
    }

    @Test func retainedFrozenProofResumesPersistentAcceptingUncertainty()
        async throws {
        let fixture = try RetryCoordinatorUncertaintyFixture()
        let original = try await fixture.prepareReadyFailure()
        let handoff = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: original.attemptID,
            setup: try retryCoordinatorSetup()
        )
        let provider = RetryCoordinatorPipelineProvider(
            transcription: .success("accepted after accepting uncertainty")
        )
        let execution = try await handoff.executePipeline(
            IOSFailedHistoryRetryPipeline(
                provider: provider,
                usageRecorder: RetryCoordinatorUsageRecorder()
            )
        )
        guard case .accepted(let output) = execution else {
            Issue.record("A valid provider result must be accepted.")
            return
        }
        fixture.failedFileSystem.persistentReplaceFailure = .init(
            error: .commitUncertain,
            commitBeforeThrowing: false
        )

        await #expect(throws: IOSFailedHistoryError.commitUncertain) {
            _ = try await output.accept()
        }
        #expect(fixture.mutationInterlock.hasRetryDeliveryRelation)
        #expect(await fixture.retryState.hasLiveOwner())

        fixture.failedFileSystem.persistentReplaceFailure = nil
        #expect(try await output.accept() == .committed)
        #expect(await provider.transcriptionCallCount() == 1)
        #expect(
            try await fixture.failedHistoryStore.load()?
                .audioCleanup.count == 1
        )
        #expect(!fixture.mutationInterlock.hasRetryDeliveryRelation)
        #expect(await fixture.retryState.hasLiveOwner() == false)
    }

    @Test func retainedSuccessPhaseResumesPersistentCommitUncertainty()
        async throws {
        let fixture = try RetryCoordinatorUncertaintyFixture()
        let original = try await fixture.prepareReadyFailure()
        let handoff = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: original.attemptID,
            setup: try retryCoordinatorSetup()
        )
        let provider = RetryCoordinatorPipelineProvider(
            transcription: .success("accepted after success uncertainty")
        )
        let execution = try await handoff.executePipeline(
            IOSFailedHistoryRetryPipeline(
                provider: provider,
                usageRecorder: RetryCoordinatorUsageRecorder()
            )
        )
        guard case .accepted(let output) = execution else {
            Issue.record("A valid provider result must be accepted.")
            return
        }
        fixture.failedFileSystem
            .persistentReplaceFailureAfterSuccessfulReplaces = (
                remaining: 1,
                failure: .init(
                    error: .commitUncertain,
                    commitBeforeThrowing: false
                )
            )

        let firstResolution: IOSAcceptedHistoryAcceptanceResolution
        do {
            firstResolution = try await output.accept()
        } catch {
            Issue.record("Initial retained-success acceptance threw.")
            throw error
        }
        #expect(firstResolution == .pendingLocalRecovery)
        #expect(fixture.mutationInterlock.hasRetryDeliveryRelation)
        #expect(await fixture.retryState.hasLiveOwner())

        fixture.failedFileSystem.persistentReplaceFailure = nil
        fixture.failedFileSystem
            .persistentReplaceFailureAfterSuccessfulReplaces = nil
        let recoveredResolution: IOSAcceptedHistoryAcceptanceResolution
        do {
            recoveredResolution = try await output.accept()
        } catch {
            Issue.record("Retained success recovery threw.")
            throw error
        }
        #expect(recoveredResolution == .committed)
        #expect(await provider.transcriptionCallCount() == 1)
        #expect(
            try await fixture.failedHistoryStore.load()?
                .audioCleanup.count == 1
        )
        #expect(!fixture.mutationInterlock.hasRetryDeliveryRelation)
        #expect(await fixture.retryState.hasLiveOwner() == false)
    }

    @Test func definiteAcceptingFailureDropsOnlyTheFrozenCheckpoint()
        async throws {
        let fixture = try RetryCoordinatorUncertaintyFixture()
        let original = try await fixture.prepareReadyFailure()
        let handoff = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: original.attemptID,
            setup: try retryCoordinatorSetup()
        )
        let provider = RetryCoordinatorPipelineProvider(
            transcription: .success("accepted after protected-data retry")
        )
        let execution = try await handoff.executePipeline(
            IOSFailedHistoryRetryPipeline(
                provider: provider,
                usageRecorder: RetryCoordinatorUsageRecorder()
            )
        )
        guard case .accepted(let output) = execution else {
            Issue.record("A valid provider result must be accepted.")
            return
        }
        fixture.failedFileSystem.replaceFailure = .init(
            error: .protectedDataUnavailable,
            commitBeforeThrowing: false
        )

        await #expect(throws: IOSFailedHistoryError.dataProtectionUnavailable) {
            _ = try await output.accept()
        }
        #expect(!fixture.mutationInterlock.hasRetryDeliveryRelation)
        #expect(await fixture.retryState.hasLiveOwner())

        #expect(try await output.accept() == .committed)
        #expect(await provider.transcriptionCallCount() == 1)
        #expect(!fixture.mutationInterlock.hasRetryDeliveryRelation)
        #expect(await fixture.retryState.hasLiveOwner() == false)
    }

    @Test func retryEntrypointResumesRetainedProviderFailure()
        async throws {
        let fixture = try RetryCoordinatorUncertaintyFixture()
        let row = try await fixture.prepareReadyFailure()
        let handoff = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: row.attemptID,
            setup: try retryCoordinatorSetup()
        )
        fixture.failedFileSystem.persistentReplaceFailure = .init(
            error: .commitUncertain,
            commitBeforeThrowing: false
        )

        await #expect(throws: IOSFailedHistoryError.commitUncertain) {
            _ = try await handoff.executePipeline(
                IOSFailedHistoryRetryPipeline(
                    provider: RetryCoordinatorPipelineProvider(
                        transcription: .failure(.networkFailure)
                    ),
                    usageRecorder: RetryCoordinatorUsageRecorder()
                )
            )
        }
        #expect(await fixture.retryState.hasLiveOwner())
        #expect(fixture.mutationInterlock.isBlocked)

        fixture.failedFileSystem.persistentReplaceFailure = nil
        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        ) {
            _ = try await fixture.coordinator.prepareFailedHistoryRetry(
                attemptID: row.attemptID,
                setup: try retryCoordinatorSetup()
            )
        }
        try await retryCoordinatorEventually {
            guard !fixture.mutationInterlock.isBlocked,
                  let retained = try? await fixture.failedHistoryStore
                    .load()?.entries.first else {
                return false
            }
            let hasLiveOwner = await fixture.retryState.hasLiveOwner()
            return retained.retryOperation == nil
                && retained.failureCategory == .networkFailure
                && !hasLiveOwner
        }

        let resumed = try await fixture.coordinator.prepareFailedHistoryRetry(
            attemptID: row.attemptID,
            setup: try retryCoordinatorSetup()
        )
        let retried = try #require(
            try await fixture.failedHistoryStore.load()?.entries.first
        )
        #expect(retried.retryCount == 2)
        try await resumed.cancel()
    }
}

private enum RetryCoordinatorUncertaintyBoundary: CaseIterable {
    case reservation
    case dispatch
    case cancellation
}

private final class RetryCoordinatorFixture: @unchecked Sendable {
    let parentDirectoryURL: URL
    let applicationSupportDirectoryURL: URL
    let registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry
    let context: IOSAcceptedHistoryCoordinatorProcessContext
    let coordinator: IOSAcceptedHistoryCoordinator

    init() throws {
        parentDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "failed-retry-coordinator-\(UUID().uuidString)",
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
        let context = registry.context(for: applicationSupportDirectoryURL)
        self.context = context
        coordinator = IOSAcceptedHistoryCoordinator(
            policyStore: context.policyStore,
            acceptedHistoryStore: context.acceptedHistoryStore,
            failedHistoryStore: context.failedHistoryStore,
            pendingRecordingStore: context.pendingRecordingStore,
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
                        applicationSupportDirectoryURL
                )
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: parentDirectoryURL)
    }

    func prepareReadyFailure(
        outputIntent: DictationOutputIntent = .standard
    ) async throws -> IOSFailedHistoryEntry {
        _ = try await coordinator.capture(
            transcriptionModel: "gpt-4o-mini-transcribe",
            transcriptionLanguageCode: "en",
            durationMilliseconds: 1_000
        )
        let attemptID = UUID()
        let sourceURL = parentDirectoryURL.appendingPathComponent(
            "source-\(attemptID.uuidString.lowercased()).wav",
            isDirectory: false
        )
        let audio = makeRetryCoordinatorWAV()
        try audio.write(to: sourceURL, options: .atomic)
        let pending = try await context.pendingRecordingStore.prepare(
            IOSPendingRecordingPreparation(
                attemptID: attemptID,
                sourceArtifact: AudioRecordingArtifact(
                    fileURL: sourceURL,
                    duration: 1,
                    byteCount: Int64(audio.count)
                ),
                initialState: .awaitingRecovery,
                outputIntent: outputIntent,
                transcriptionConfiguration: TranscriptionConfiguration(
                    model: "gpt-4o-mini-transcribe",
                    language: .english
                )
            )
        )
        _ = try await coordinator.transferPendingRecordingFailure(
            expected: IOSPendingRecordingCASExpectation(recording: pending),
            failure: IOSFailedHistoryTransferFailure(
                category: .networkUnavailable,
                pipelineStage: .transcription
            )
        )
        let envelope = try #require(
            try await context.failedHistoryStore.load()
        )
        return try #require(envelope.entries.first)
    }

    func prepareOutboxHead() async throws {
        let capture = try await coordinator.capture(
            transcriptionModel: "outbox-model",
            transcriptionLanguageCode: "en",
            durationMilliseconds: 500
        )
        let preparation = try IOSAcceptedOutputDeliveryPreparation(
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: UUID(),
            transcriptID: UUID(),
            rawAcceptedText: "retained predecessor",
            outputIntent: .standard,
            automaticInsertionPreferenceEnabled: false,
            keepLatestResult: true,
            historyCapture: capture
        )
        let record = try await context.deliveryStore.accept(preparation)
        let authorization = try await context.deliveryStore
            .authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: record
                )
            )
        _ = try await context.outboxStore.transferForTesting(
            delivery: authorization,
            policy: capture.policyReceipt
        )
    }

    func preparePendingDeliveryPredecessor()
        async throws -> IOSAcceptedOutputDeliveryRecord {
        let capture = try await coordinator.capture(
            transcriptionModel: "predecessor-model",
            transcriptionLanguageCode: "en",
            durationMilliseconds: 750
        )
        return try await context.deliveryStore.accept(
            IOSAcceptedOutputDeliveryPreparation(
                deliveryID: UUID(),
                sessionID: UUID(),
                attemptID: UUID(),
                transcriptID: UUID(),
                rawAcceptedText: "pending predecessor",
                outputIntent: .standard,
                automaticInsertionPreferenceEnabled: false,
                keepLatestResult: true,
                historyCapture: capture
            )
        )
    }

    func prepareReadyPending() async throws -> IOSPendingRecording {
        let attemptID = UUID()
        let sourceURL = parentDirectoryURL.appendingPathComponent(
            "pending-source-\(attemptID.uuidString.lowercased()).wav",
            isDirectory: false
        )
        let audio = makeRetryCoordinatorWAV()
        try audio.write(to: sourceURL, options: .atomic)
        return try await context.pendingRecordingStore.prepare(
            IOSPendingRecordingPreparation(
                attemptID: attemptID,
                sourceArtifact: AudioRecordingArtifact(
                    fileURL: sourceURL,
                    duration: 1,
                    byteCount: Int64(audio.count)
                ),
                initialState: .readyForTranscription,
                outputIntent: .standard,
                transcriptionConfiguration: .defaults
            )
        )
    }

    func audioExists(for row: IOSFailedHistoryEntry) -> Bool {
        guard let url = IOSPendingRecordingStorageLocation.audioFileURL(
            forRelativeIdentifier: row.audioRelativeIdentifier,
            in: applicationSupportDirectoryURL
        ) else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func rawPendingRecording() throws -> IOSPendingRecording? {
        try FoundationIOSPendingRecordingJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            repositoryGuard: context.repositoryGuard
        ).load()
    }
}

private final class RetryCoordinatorUncertaintyFixture:
    @unchecked Sendable {
    let parentDirectoryURL: URL
    let applicationSupportDirectoryURL: URL
    let registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry
    let context: IOSAcceptedHistoryCoordinatorProcessContext
    let failedFileSystem = FailedHistoryFakeFileSystem()
    let retryState = IOSFailedHistoryRetryLiveOwnerState()
    let mutationInterlock: IOSFailedHistoryMutationInterlock
    let failedHistoryStore: IOSFailedHistoryStore
    let pendingRecordingStore: IOSPendingRecordingStore
    let coordinator: IOSAcceptedHistoryCoordinator

    init() throws {
        parentDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "failed-retry-uncertainty-\(UUID().uuidString)",
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
        let context = registry.context(for: applicationSupportDirectoryURL)
        self.context = context
        mutationInterlock = context.failedHistoryMutationInterlock

        let failedHistoryStore = IOSFailedHistoryStore(
            journal: FoundationIOSFailedHistoryJournalRepository(
                fileSystem: failedFileSystem
            ),
            capabilityOwnerIdentity: context.ownerIdentity,
            operationGateIdentity: context.operationGate.identity,
            expectedPendingStoreIdentity:
                context.pendingRecordingStoreIdentity,
            retryLiveOwnerState: retryState,
            repositoryGuard: context.repositoryGuard,
            mutationInterlock: mutationInterlock
        )
        self.failedHistoryStore = failedHistoryStore
        guard let physicalRootIdentity = context.repositoryBinding
                .physicalRootIdentity,
              retryState.bindProviderRegistration(
                  failedStoreIdentity: failedHistoryStore.storeIdentity,
                  ownerIdentity: context.ownerIdentity,
                  physicalRootIdentity: physicalRootIdentity
              ) else {
            throw IOSFailedHistoryError.repositoryIdentityConflict
        }

        let pendingRecordingStore = IOSPendingRecordingStore(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            capabilityOwnerIdentity: context.ownerIdentity,
            storeIdentity: context.pendingRecordingStoreIdentity,
            operationGate: context.operationGate,
            liveOwnerRegistry: context.pendingRecordingLiveOwnerRegistry,
            failedHistoryRetryState: retryState,
            mediaValidationWorkerGate:
                context.pendingRecordingMediaValidationWorkerGate,
            repositoryGuard: context.repositoryGuard,
            failedHistoryMutationInterlock: mutationInterlock,
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
            failedHistoryRetryState: retryState,
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

    deinit {
        try? FileManager.default.removeItem(at: parentDirectoryURL)
    }

    func prepareReadyFailure() async throws -> IOSFailedHistoryEntry {
        _ = try await coordinator.capture(
            transcriptionModel: "gpt-4o-mini-transcribe",
            transcriptionLanguageCode: "en",
            durationMilliseconds: 1_000
        )
        let attemptID = UUID()
        let sourceURL = parentDirectoryURL.appendingPathComponent(
            "source-\(attemptID.uuidString.lowercased()).wav",
            isDirectory: false
        )
        let audio = makeRetryCoordinatorWAV()
        try audio.write(to: sourceURL, options: .atomic)
        let pending = try await pendingRecordingStore.prepare(
            IOSPendingRecordingPreparation(
                attemptID: attemptID,
                sourceArtifact: AudioRecordingArtifact(
                    fileURL: sourceURL,
                    duration: 1,
                    byteCount: Int64(audio.count)
                ),
                initialState: .awaitingRecovery,
                outputIntent: .standard,
                transcriptionConfiguration: .defaults
            )
        )
        _ = try await coordinator.transferPendingRecordingFailure(
            expected: IOSPendingRecordingCASExpectation(recording: pending),
            failure: IOSFailedHistoryTransferFailure(
                category: .networkUnavailable,
                pipelineStage: .transcription
            )
        )
        let envelope = try #require(try await failedHistoryStore.load())
        return try #require(envelope.entries.first)
    }
}

private actor RetryCoordinatorLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor RetryCoordinatorPipelineProvider:
    IOSFailedHistoryRetryProviderExecuting {
    private let transcriptionOutcome:
        IOSFailedHistoryRetryProviderTextOutcome
    private let correctionOutcome: IOSFailedHistoryRetryProviderTextOutcome
    private let translationOutcome: IOSFailedHistoryRetryProviderTextOutcome
    private var storedTranscriptionCallCount = 0

    init(
        transcription: IOSFailedHistoryRetryProviderTextOutcome,
        correction: IOSFailedHistoryRetryProviderTextOutcome =
            .failure(.unknown),
        translation: IOSFailedHistoryRetryProviderTextOutcome =
            .failure(.unknown)
    ) {
        transcriptionOutcome = transcription
        correctionOutcome = correction
        translationOutcome = translation
    }

    func transcribe(
        _ request: IOSFailedHistoryRetryTranscriptionRequest
    ) async -> IOSFailedHistoryRetryProviderTextOutcome {
        storedTranscriptionCallCount += 1
        guard (try? await request.audio.read(
            atOffset: 0,
            maximumByteCount: 64
        ))?.isEmpty == false else {
            return .failure(.invalidRecording)
        }
        return transcriptionOutcome
    }

    func correct(
        _ request: IOSFailedHistoryRetryCorrectionRequest
    ) async -> IOSFailedHistoryRetryProviderTextOutcome {
        _ = request
        return correctionOutcome
    }

    func translate(
        _ request: IOSFailedHistoryRetryTranslationRequest
    ) async -> IOSFailedHistoryRetryProviderTextOutcome {
        _ = request
        return translationOutcome
    }

    func transcriptionCallCount() -> Int {
        storedTranscriptionCallCount
    }
}

private actor RetryCoordinatorUsageRecorder:
    IOSFailedHistoryRetryUsageRecording {
    private var storedCallCount = 0

    func recordRetryUsage(
        _ usage: SuccessfulTranscriptionUsage
    ) async throws {
        _ = usage
        storedCallCount += 1
    }

    func callCount() -> Int {
        storedCallCount
    }
}

private func retryCoordinatorSetup(
    transcriptionConfiguration: TranscriptionConfiguration = .defaults,
    textCorrectionConfiguration: TextCorrectionConfiguration = .defaults,
    postProcessingConfiguration:
        TranscriptPostProcessingConfiguration = .defaults,
    translationConfiguration: TranslationConfiguration? = nil,
    keepLatestResult: Bool = true
) throws -> IOSFailedHistoryRetrySetupSnapshot {
    try IOSFailedHistoryRetrySetupSnapshot(
        credentialEligibility: .available,
        transcriptionConfiguration: transcriptionConfiguration,
        transcriptionPromptComposition: retryPromptComposition(
            transcriptionConfiguration: transcriptionConfiguration
        ),
        textCorrectionConfiguration: textCorrectionConfiguration,
        postProcessingConfiguration: postProcessingConfiguration,
        translationConfiguration: translationConfiguration,
        keepLatestResult: keepLatestResult
    )
}

private func retryPromptComposition(
    transcriptionConfiguration: TranscriptionConfiguration = .defaults
) -> TranscriptionPromptComposition {
    TranscriptionPromptComposition(
        resolvedFreeformPrompt:
            transcriptionConfiguration.resolvedFreeformPrompt,
        context: nil,
        emojiCommandsConfiguration: .defaults,
        customDictionary: .empty
    )
}

private func retryCoordinatorEventually(
    _ predicate: @escaping @Sendable () async throws -> Bool
) async throws {
    for _ in 0..<100 {
        if try await predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for Retry cancellation.")
}

private func makeRetryCoordinatorWAV() -> Data {
    let sampleRate: UInt32 = 8_000
    let channelCount: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let dataByteCount = sampleRate * UInt32(bitsPerSample / 8)
    let byteRate = sampleRate * UInt32(channelCount)
        * UInt32(bitsPerSample / 8)
    let blockAlign = channelCount * (bitsPerSample / 8)

    var data = Data()
    data.append(contentsOf: "RIFF".utf8)
    data.appendRetryCoordinatorLittleEndian(UInt32(36) + dataByteCount)
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    data.appendRetryCoordinatorLittleEndian(UInt32(16))
    data.appendRetryCoordinatorLittleEndian(UInt16(1))
    data.appendRetryCoordinatorLittleEndian(channelCount)
    data.appendRetryCoordinatorLittleEndian(sampleRate)
    data.appendRetryCoordinatorLittleEndian(byteRate)
    data.appendRetryCoordinatorLittleEndian(blockAlign)
    data.appendRetryCoordinatorLittleEndian(bitsPerSample)
    data.append(contentsOf: "data".utf8)
    data.appendRetryCoordinatorLittleEndian(dataByteCount)
    data.append(Data(repeating: 0, count: Int(dataByteCount)))
    return data
}

private extension Data {
    mutating func appendRetryCoordinatorLittleEndian<
        Value: FixedWidthInteger
    >(_ value: Value) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) {
            append(contentsOf: $0)
        }
    }
}
