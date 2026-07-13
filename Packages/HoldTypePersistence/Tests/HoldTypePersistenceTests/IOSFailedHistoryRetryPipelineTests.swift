import Foundation
import HoldTypeDomain
import Testing
@_spi(HoldTypeIOSCore) @testable import HoldTypePersistence

struct IOSFailedHistoryRetryPipelineTests {
    @Test func runtimeFailureMappingIsTotalAndPayloadFree() {
        #expect(IOSFailedHistoryRetryRuntimeFailure.allCases.count == 21)

        for failure in IOSFailedHistoryRetryRuntimeFailure.allCases {
            #expect(
                failure.durableCategory(at: .transcription)
                    == expectedCategory(for: failure, at: .transcription)
            )
            #expect(
                String(describing: failure)
                    == "IOSFailedHistoryRetryRuntimeFailure(redacted)"
            )
            #expect(failure.customMirror.children.isEmpty)
        }
        #expect(
            IOSFailedHistoryRetryRuntimeFailure.dictionaryEcho
                .durableCategory(at: .translation) == nil
        )
        #expect(
            IOSFailedHistoryRetryRuntimeFailure.contextEcho
                .durableCategory(at: .translation) == nil
        )
    }

    @Test func standardPipelineUsesFrozenInputsAndOrderedSinglePass()
        async throws {
        let audio = retryPipelineAudio()
        let transcriptionID = try #require(
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )
        let prompt = retryPipelinePrompt("frozen prompt canary")
        let transcription = TranscriptionConfiguration(
            model: " retry-model ",
            language: .russian,
            freeformPrompt: "ignored after composition"
        )
        let correction = TextCorrectionConfiguration(
            isEnabled: true,
            modelPreset: .fast,
            prompt: "minimal correction canary"
        )
        let postProcessing = TranscriptPostProcessingConfiguration(
            localTextCleanupEnabled: true,
            textReplacementRules: [
                TextReplacementRule(
                    id: try #require(
                        UUID(
                            uuidString:
                                "22222222-2222-2222-2222-222222222222"
                        )
                    ),
                    search: "cat",
                    replacement: "dog"
                ),
            ]
        )
        let setup = try retryPipelineSetup(
            transcription: transcription,
            prompt: prompt,
            correction: correction,
            postProcessing: postProcessing,
            keepLatestResult: false
        )
        let events = RetryPipelineEventLog()
        let provider = RetryPipelineProviderFake(
            expectedAudio: audio,
            transcription: .success("cat — raw"),
            correction: .success("cat — corrected"),
            translation: .failure(.unknown),
            events: events
        )
        let usage = RetryPipelineUsageRecorderFake(events: events)
        let pipeline = IOSFailedHistoryRetryPipeline(
            provider: provider,
            usageRecorder: usage
        )
        let invocation = IOSFailedHistoryRetryProviderInvocation(
            audio: audio,
            setup: setup,
            transcriptionID: transcriptionID,
            outputIntent: .standard
        )

        let terminal = try await pipeline.run(invocation)

        guard case .accepted(let accepted) = terminal else {
            Issue.record("The standard pipeline must accept its final text.")
            return
        }
        #expect(accepted.text == "dog - corrected")
        #expect(
            await events.values() == [
                "provider.transcription",
                "usage.record",
                "provider.correction",
            ]
        )
        let transcriptionRequest = try #require(
            await provider.transcriptionSnapshot()
        )
        #expect(transcriptionRequest.transcriptionID == transcriptionID)
        #expect(transcriptionRequest.audioMatches)
        #expect(transcriptionRequest.audioBytes == Data([0x41, 0x42, 0x43]))
        #expect(transcriptionRequest.resolvedModel == "retry-model")
        #expect(transcriptionRequest.resolvedLanguageCode == "ru")
        #expect(transcriptionRequest.promptComposition == prompt)
        #expect(transcriptionRequest.timeout == .seconds(60))

        let correctionRequest = try #require(
            await provider.correctionSnapshot()
        )
        #expect(correctionRequest.transcript.text == "cat — raw")
        #expect(correctionRequest.configuration == correction)
        #expect(correctionRequest.timeout == .seconds(20))
        #expect(await provider.translationCallCount() == 0)

        let recordedUsage = try #require(await usage.recordedUsage())
        #expect(recordedUsage.transcriptionID == transcriptionID)
        #expect(recordedUsage.model == "retry-model")
        #expect(recordedUsage.audioDuration == 1.25)

        #expect(
            String(describing: invocation)
                == "IOSFailedHistoryRetryProviderInvocation(redacted)"
        )
        #expect(
            String(describing: terminal)
                == "IOSFailedHistoryRetryPipelineTerminal(redacted)"
        )
        #expect(terminal.customMirror.children.isEmpty)
    }

    @Test func pipelineAndDescriptorReflectionAreRedacted() {
        let audio = retryPipelineAudio()
        let providerSecret = "sk-provider-secret-canary"
        let usagePath = "/private/usage-secret-path-canary.json"
        let pipeline = IOSFailedHistoryRetryPipeline(
            provider: RetryPipelineProviderFake(
                expectedAudio: audio,
                transcription: .success(providerSecret),
                correction: .failure(.unknown),
                translation: .failure(.unknown)
            ),
            usageRecorder: RetryPipelineSecretUsageRecorder(
                pathCanary: usagePath
            )
        )

        let rendered = [
            String(describing: pipeline),
            String(reflecting: pipeline),
            String(describing: audio),
            String(reflecting: audio),
        ].joined(separator: "|")
        #expect(
            String(describing: pipeline)
                == "IOSFailedHistoryRetryPipeline(redacted)"
        )
        #expect(pipeline.customMirror.children.isEmpty)
        #expect(!rendered.contains(providerSecret))
        #expect(!rendered.contains(usagePath))
        #expect(!rendered.contains("retry-pipeline-"))
        #expect(
            audio.customMirror.children.allSatisfy { child in
                String(describing: child.value) == "redacted"
            }
        )
    }

    @Test func translationConsumesProcessedTextAndOnlyRepeatsTypography()
        async throws {
        let audio = retryPipelineAudio()
        let translation = TranslationConfiguration(
            sourceMode: .sameAsTranscription,
            targetLanguage: .english
        )
        let postProcessing = TranscriptPostProcessingConfiguration(
            localTextCleanupEnabled: true,
            textReplacementRules: [
                TextReplacementRule(search: "cat", replacement: "dog"),
            ]
        )
        let setup = try retryPipelineSetup(
            transcription: TranscriptionConfiguration(language: .russian),
            correction: TextCorrectionConfiguration(isEnabled: true),
            postProcessing: postProcessing,
            translation: translation
        )
        let events = RetryPipelineEventLog()
        let provider = RetryPipelineProviderFake(
            expectedAudio: audio,
            transcription: .success("cat — raw"),
            correction: .success("cat — corrected"),
            translation: .success("cat — translated"),
            events: events
        )
        let usage = RetryPipelineUsageRecorderFake(events: events)
        let pipeline = IOSFailedHistoryRetryPipeline(
            provider: provider,
            usageRecorder: usage
        )

        let terminal = try await pipeline.run(
            IOSFailedHistoryRetryProviderInvocation(
                audio: audio,
                setup: setup,
                transcriptionID: UUID(),
                outputIntent: .translate
            )
        )

        guard case .accepted(let accepted) = terminal else {
            Issue.record("Translation must return the translated final text.")
            return
        }
        #expect(accepted.text == "cat - translated")
        let translationRequest = try #require(
            await provider.translationSnapshot()
        )
        #expect(
            translationRequest.translationRequest.acceptedTranscript.text
                == "dog - corrected"
        )
        #expect(
            translationRequest.translationRequest.translationConfiguration
                == translation
        )
        #expect(
            translationRequest.translationRequest
                .resolvedSourceLanguageCode == "ru"
        )
        #expect(
            await events.values() == [
                "provider.transcription",
                "usage.record",
                "provider.correction",
                "provider.translation",
            ]
        )
    }

    @Test func correctionProviderOutcomesAreFailOpen() async throws {
        let original = "This original transcript is definitely long enough."
        let outcomes: [IOSFailedHistoryRetryProviderTextOutcome] = [
            .failure(.networkFailure),
            .failure(.credentialRejected),
            .failure(.authorizationUnavailable),
            .failure(.cancelled),
            .success("   \n"),
            .success("x"),
            .success(String(repeating: "expanded ", count: 40)),
        ]

        for correctionOutcome in outcomes {
            let audio = retryPipelineAudio()
            let provider = RetryPipelineProviderFake(
                expectedAudio: audio,
                transcription: .success(original),
                correction: correctionOutcome,
                translation: .failure(.unknown)
            )
            let pipeline = IOSFailedHistoryRetryPipeline(
                provider: provider,
                usageRecorder: RetryPipelineUsageRecorderFake()
            )
            let terminal = try await pipeline.run(
                IOSFailedHistoryRetryProviderInvocation(
                    audio: audio,
                    setup: try retryPipelineSetup(
                        correction: TextCorrectionConfiguration(
                            isEnabled: true
                        ),
                        postProcessing:
                            TranscriptPostProcessingConfiguration(
                                localTextCleanupEnabled: false
                            )
                    ),
                    transcriptionID: UUID(),
                    outputIntent: .standard
                )
            )

            guard case .accepted(let accepted) = terminal else {
                Issue.record("A correction outcome must fail open.")
                continue
            }
            #expect(accepted.text == original)
            #expect(await provider.correctionCallCount() == 1)
        }
    }

    @Test func authorizationLossIsDistinctForRequiredProviderStages()
        async throws {
        do {
            let audio = retryPipelineAudio()
            let pipeline = IOSFailedHistoryRetryPipeline(
                provider: RetryPipelineProviderFake(
                    expectedAudio: audio,
                    transcription: .failure(.authorizationUnavailable),
                    correction: .success("unused"),
                    translation: .success("unused")
                ),
                usageRecorder: RetryPipelineUsageRecorderFake()
            )

            #expect(
                try await pipeline.run(
                    IOSFailedHistoryRetryProviderInvocation(
                        audio: audio,
                        setup: try retryPipelineSetup(),
                        transcriptionID: UUID(),
                        outputIntent: .standard
                    )
                ) == .authorizationUnavailable
            )
        }

        do {
            let audio = retryPipelineAudio()
            let pipeline = IOSFailedHistoryRetryPipeline(
                provider: RetryPipelineProviderFake(
                    expectedAudio: audio,
                    transcription: .success("authorized transcription"),
                    correction: .failure(.authorizationUnavailable),
                    translation: .failure(.authorizationUnavailable)
                ),
                usageRecorder: RetryPipelineUsageRecorderFake()
            )

            #expect(
                try await pipeline.run(
                    IOSFailedHistoryRetryProviderInvocation(
                        audio: audio,
                        setup: try retryPipelineSetup(
                            correction: TextCorrectionConfiguration(
                                isEnabled: true
                            ),
                            translation: TranslationConfiguration(
                                targetLanguage: .english
                            )
                        ),
                        transcriptionID: UUID(),
                        outputIntent: .translate
                    )
                ) == .authorizationUnavailable
            )
        }
    }

    @Test func emptyLocalProcessingKeepsSuccessfulCorrection()
        async throws {
        let audio = retryPipelineAudio()
        let provider = RetryPipelineProviderFake(
            expectedAudio: audio,
            transcription: .success("raw transcription"),
            correction: .success("corrected transcription"),
            translation: .failure(.unknown)
        )
        let postProcessing = TranscriptPostProcessingConfiguration(
            localTextCleanupEnabled: false,
            textReplacementRules: [
                TextReplacementRule(
                    search: "corrected transcription",
                    replacement: ""
                ),
            ]
        )
        let pipeline = IOSFailedHistoryRetryPipeline(
            provider: provider,
            usageRecorder: RetryPipelineUsageRecorderFake()
        )

        let terminal = try await pipeline.run(
            IOSFailedHistoryRetryProviderInvocation(
                audio: audio,
                setup: try retryPipelineSetup(
                    correction: TextCorrectionConfiguration(isEnabled: true),
                    postProcessing: postProcessing
                ),
                transcriptionID: UUID(),
                outputIntent: .standard
            )
        )

        guard case .accepted(let accepted) = terminal else {
            Issue.record("Empty local processing must keep corrected text.")
            return
        }
        #expect(accepted.text == "corrected transcription")
    }

    @Test func disabledCorrectionMakesNoCorrectionProviderCall()
        async throws {
        let audio = retryPipelineAudio()
        let provider = RetryPipelineProviderFake(
            expectedAudio: audio,
            transcription: .success("raw transcript"),
            correction: .success("must not be used"),
            translation: .failure(.unknown)
        )
        let pipeline = IOSFailedHistoryRetryPipeline(
            provider: provider,
            usageRecorder: RetryPipelineUsageRecorderFake()
        )

        let terminal = try await pipeline.run(
            IOSFailedHistoryRetryProviderInvocation(
                audio: audio,
                setup: try retryPipelineSetup(),
                transcriptionID: UUID(),
                outputIntent: .standard
            )
        )

        guard case .accepted(let accepted) = terminal else {
            Issue.record("A standard transcript must be accepted.")
            return
        }
        #expect(accepted.text == "raw transcript")
        #expect(await provider.correctionCallCount() == 0)
        #expect(await provider.translationCallCount() == 0)
    }

    @Test func usageFailureIsNonAuthoritativeAndPrecedesCorrection()
        async throws {
        let audio = retryPipelineAudio()
        let events = RetryPipelineEventLog()
        let provider = RetryPipelineProviderFake(
            expectedAudio: audio,
            transcription: .success("raw transcript"),
            correction: .success("corrected transcript"),
            translation: .failure(.unknown),
            events: events
        )
        let usage = RetryPipelineUsageRecorderFake(
            events: events,
            shouldFail: true
        )
        let pipeline = IOSFailedHistoryRetryPipeline(
            provider: provider,
            usageRecorder: usage
        )

        let terminal = try await pipeline.run(
            IOSFailedHistoryRetryProviderInvocation(
                audio: audio,
                setup: try retryPipelineSetup(
                    correction: TextCorrectionConfiguration(isEnabled: true)
                ),
                transcriptionID: UUID(),
                outputIntent: .standard
            )
        )

        guard case .accepted(let accepted) = terminal else {
            Issue.record("Usage persistence must not reject provider text.")
            return
        }
        #expect(accepted.text == "corrected transcript")
        #expect(
            await events.values() == [
                "provider.transcription",
                "usage.record",
                "provider.correction",
            ]
        )
    }

    @Test func terminalFailuresCarryOnlyMappedStageAndCategory()
        async throws {
        do {
            let audio = retryPipelineAudio()
            let pipeline = IOSFailedHistoryRetryPipeline(
                provider: RetryPipelineProviderFake(
                    expectedAudio: audio,
                    transcription: .failure(.rateLimited),
                    correction: .success("unused"),
                    translation: .success("unused")
                ),
                usageRecorder: RetryPipelineUsageRecorderFake()
            )
            let terminal = try await pipeline.run(
                IOSFailedHistoryRetryProviderInvocation(
                    audio: audio,
                    setup: try retryPipelineSetup(),
                    transcriptionID: UUID(),
                    outputIntent: .standard
                )
            )
            assertFailure(
                terminal,
                runtimeFailure: .rateLimited,
                durableCategory: .rateLimited,
                stage: .transcription
            )
        }

        do {
            let audio = retryPipelineAudio()
            let pipeline = IOSFailedHistoryRetryPipeline(
                provider: RetryPipelineProviderFake(
                    expectedAudio: audio,
                    transcription: .success("transient text"),
                    correction: .failure(.unknown),
                    translation: .failure(.providerRejected)
                ),
                usageRecorder: RetryPipelineUsageRecorderFake()
            )
            let terminal = try await pipeline.run(
                IOSFailedHistoryRetryProviderInvocation(
                    audio: audio,
                    setup: try retryPipelineSetup(
                        translation: TranslationConfiguration(
                            targetLanguage: .english
                        )
                    ),
                    transcriptionID: UUID(),
                    outputIntent: .translate
                )
            )
            assertFailure(
                terminal,
                runtimeFailure: .providerRejected,
                durableCategory: .providerRejected,
                stage: .translation
            )
        }

        do {
            let audio = retryPipelineAudio()
            let pipeline = IOSFailedHistoryRetryPipeline(
                provider: RetryPipelineProviderFake(
                    expectedAudio: audio,
                    transcription: .success("transient text"),
                    correction: .failure(.unknown),
                    translation: .failure(.dictionaryEcho)
                ),
                usageRecorder: RetryPipelineUsageRecorderFake()
            )
            let terminal = try await pipeline.run(
                IOSFailedHistoryRetryProviderInvocation(
                    audio: audio,
                    setup: try retryPipelineSetup(
                        translation: TranslationConfiguration(
                            targetLanguage: .english
                        )
                    ),
                    transcriptionID: UUID(),
                    outputIntent: .translate
                )
            )
            assertFailure(
                terminal,
                runtimeFailure: .dictionaryEcho,
                durableCategory: nil,
                stage: .translation
            )
        }

        do {
            let audio = retryPipelineAudio()
            let pipeline = IOSFailedHistoryRetryPipeline(
                provider: RetryPipelineProviderFake(
                    expectedAudio: audio,
                    transcription: .failure(.invalidRecording),
                    correction: .success("unused"),
                    translation: .success("unused")
                ),
                usageRecorder: RetryPipelineUsageRecorderFake()
            )
            let terminal = try await pipeline.run(
                IOSFailedHistoryRetryProviderInvocation(
                    audio: audio,
                    setup: try retryPipelineSetup(),
                    transcriptionID: UUID(),
                    outputIntent: .standard
                )
            )
            assertFailure(
                terminal,
                runtimeFailure: .invalidRecording,
                durableCategory: nil,
                stage: .transcription
            )
        }
    }

    @Test func emptyTerminalProviderTextMapsAtItsActiveStage()
        async throws {
        do {
            let audio = retryPipelineAudio()
            let pipeline = IOSFailedHistoryRetryPipeline(
                provider: RetryPipelineProviderFake(
                    expectedAudio: audio,
                    transcription: .success(" \n "),
                    correction: .success("unused"),
                    translation: .success("unused")
                ),
                usageRecorder: RetryPipelineUsageRecorderFake()
            )
            let terminal = try await pipeline.run(
                IOSFailedHistoryRetryProviderInvocation(
                    audio: audio,
                    setup: try retryPipelineSetup(),
                    transcriptionID: UUID(),
                    outputIntent: .standard
                )
            )
            assertFailure(
                terminal,
                runtimeFailure: .emptyResult,
                durableCategory: .emptyResult,
                stage: .transcription
            )
        }

        do {
            let audio = retryPipelineAudio()
            let pipeline = IOSFailedHistoryRetryPipeline(
                provider: RetryPipelineProviderFake(
                    expectedAudio: audio,
                    transcription: .success("transient text"),
                    correction: .failure(.unknown),
                    translation: .success(" \t ")
                ),
                usageRecorder: RetryPipelineUsageRecorderFake()
            )
            let terminal = try await pipeline.run(
                IOSFailedHistoryRetryProviderInvocation(
                    audio: audio,
                    setup: try retryPipelineSetup(
                        translation: TranslationConfiguration(
                            targetLanguage: .english
                        )
                    ),
                    transcriptionID: UUID(),
                    outputIntent: .translate
                )
            )
            assertFailure(
                terminal,
                runtimeFailure: .emptyResult,
                durableCategory: .emptyResult,
                stage: .translation
            )
        }
    }

    @Test func transcriptionTimeoutCancelsAdapterAndIgnoresLateText()
        async throws {
        let timeouts = try retryPipelineTimeouts()
        let audio = retryPipelineAudio()
        let provider = BlockingRetryPipelineProvider(
            blockedStage: .transcription,
            expectedAudio: audio,
            lateOutcome: .success("late secret transcript")
        )
        let usage = RetryPipelineUsageRecorderFake()
        let pipeline = IOSFailedHistoryRetryPipeline(
            provider: provider,
            usageRecorder: usage,
            timeouts: timeouts,
            timeoutSleeper: SelectiveRetryPipelineSleeper(
                immediateDuration: timeouts.transcription
            )
        )

        let terminal = try await pipeline.run(
            IOSFailedHistoryRetryProviderInvocation(
                audio: audio,
                setup: try retryPipelineSetup(),
                transcriptionID: UUID(),
                outputIntent: .standard
            )
        )

        assertFailure(
            terminal,
            runtimeFailure: .timedOut,
            durableCategory: .timedOut,
            stage: .transcription
        )
        #expect(await usage.callCount() == 0)
        await provider.waitUntilFinished()
        #expect(await provider.observedCancellation())
        #expect(await provider.lowerLayerHasFinished() == false)
        await provider.releaseBlockedStage()
        await provider.waitUntilLowerLayerFinished()
    }

    @Test func correctionTimeoutIsFailOpenAndIgnoresLateText()
        async throws {
        let timeouts = try retryPipelineTimeouts()
        let audio = retryPipelineAudio()
        let provider = BlockingRetryPipelineProvider(
            blockedStage: .correction,
            expectedAudio: audio,
            lateOutcome: .success("late correction must not win")
        )
        let pipeline = IOSFailedHistoryRetryPipeline(
            provider: provider,
            usageRecorder: RetryPipelineUsageRecorderFake(),
            timeouts: timeouts,
            timeoutSleeper: SelectiveRetryPipelineSleeper(
                immediateDuration: timeouts.correction
            )
        )

        let terminal = try await pipeline.run(
            IOSFailedHistoryRetryProviderInvocation(
                audio: audio,
                setup: try retryPipelineSetup(
                    correction: TextCorrectionConfiguration(isEnabled: true),
                    postProcessing:
                        TranscriptPostProcessingConfiguration(
                            localTextCleanupEnabled: false
                        )
                ),
                transcriptionID: UUID(),
                outputIntent: .standard
            )
        )

        guard case .accepted(let accepted) = terminal else {
            Issue.record("A correction timeout must fail open.")
            return
        }
        #expect(accepted.text == "blocking raw transcript")
        await provider.waitUntilFinished()
        #expect(await provider.observedCancellation())
        #expect(await provider.lowerLayerHasFinished() == false)
        await provider.releaseBlockedStage()
        await provider.waitUntilLowerLayerFinished()
    }

    @Test func translationTimeoutMapsAtTranslationAndIgnoresLateText()
        async throws {
        let timeouts = try retryPipelineTimeouts()
        let audio = retryPipelineAudio()
        let provider = BlockingRetryPipelineProvider(
            blockedStage: .translation,
            expectedAudio: audio,
            lateOutcome: .success("late translated secret")
        )
        let pipeline = IOSFailedHistoryRetryPipeline(
            provider: provider,
            usageRecorder: RetryPipelineUsageRecorderFake(),
            timeouts: timeouts,
            timeoutSleeper: SelectiveRetryPipelineSleeper(
                immediateDuration: timeouts.translation
            )
        )

        let terminal = try await pipeline.run(
            IOSFailedHistoryRetryProviderInvocation(
                audio: audio,
                setup: try retryPipelineSetup(
                    translation: TranslationConfiguration(
                        targetLanguage: .english
                    )
                ),
                transcriptionID: UUID(),
                outputIntent: .translate
            )
        )

        assertFailure(
            terminal,
            runtimeFailure: .timedOut,
            durableCategory: .timedOut,
            stage: .translation
        )
        await provider.waitUntilFinished()
        #expect(await provider.observedCancellation())
        #expect(await provider.lowerLayerHasFinished() == false)
        await provider.releaseBlockedStage()
        await provider.waitUntilLowerLayerFinished()
    }

    @Test func outerTaskCancellationCancelsTheWholeRetry() async throws {
        let audio = retryPipelineAudio()
        let provider = BlockingRetryPipelineProvider(
            blockedStage: .transcription,
            expectedAudio: audio,
            lateOutcome: .success("late text")
        )
        let usage = RetryPipelineUsageRecorderFake()
        let pipeline = IOSFailedHistoryRetryPipeline(
            provider: provider,
            usageRecorder: usage
        )
        let invocation = IOSFailedHistoryRetryProviderInvocation(
            audio: audio,
            setup: try retryPipelineSetup(),
            transcriptionID: UUID(),
            outputIntent: .standard
        )
        let task = Task {
            try await pipeline.run(invocation)
        }
        await provider.waitUntilStarted()

        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await usage.callCount() == 0)
        await provider.waitUntilFinished()
        #expect(await provider.observedCancellation())
        #expect(await provider.lowerLayerHasFinished() == false)
        await provider.releaseBlockedStage()
        await provider.waitUntilLowerLayerFinished()
    }
}

private func expectedCategory(
    for failure: IOSFailedHistoryRetryRuntimeFailure,
    at stage: IOSFailedHistoryPipelineStage
) -> IOSFailedHistoryFailureCategory? {
    switch failure {
    case .credentialMissing, .credentialUnavailable, .credentialRejected:
        .credentialRejected
    case .networkUnavailable:
        .networkUnavailable
    case .networkFailure:
        .networkFailure
    case .timedOut:
        .timedOut
    case .rateLimited:
        .rateLimited
    case .providerUnavailable:
        .providerUnavailable
    case .badRequest, .providerRejected:
        .providerRejected
    case .invalidResponse:
        .invalidResponse
    case .emptyResult:
        .emptyResult
    case .dictionaryEcho, .contextEcho:
        stage == .transcription ? .echoRejected : nil
    case .invalidRecording, .invalidRequest, .multipartMetadataTooLarge,
            .invalidTranslationRoute, .authorizationUnavailable, .cancelled,
            .unknown:
        nil
    }
}

private func assertFailure(
    _ terminal: IOSFailedHistoryRetryPipelineTerminal,
    runtimeFailure: IOSFailedHistoryRetryRuntimeFailure,
    durableCategory: IOSFailedHistoryFailureCategory?,
    stage: IOSFailedHistoryPipelineStage
) {
    guard case .failed(let failure) = terminal else {
        Issue.record("The pipeline must return a failed terminal outcome.")
        return
    }
    #expect(failure.runtimeFailure == runtimeFailure)
    #expect(failure.durableCategory == durableCategory)
    #expect(failure.stage == stage)
    #expect(
        String(describing: failure)
            == "IOSFailedHistoryRetryPipelineFailure(redacted)"
    )
    #expect(failure.customMirror.children.isEmpty)
}

private func retryPipelineSetup(
    transcription: TranscriptionConfiguration = .defaults,
    prompt: TranscriptionPromptComposition = retryPipelinePrompt(
        "retry prompt"
    ),
    correction: TextCorrectionConfiguration = .defaults,
    postProcessing: TranscriptPostProcessingConfiguration = .defaults,
    translation: TranslationConfiguration? = nil,
    keepLatestResult: Bool = true
) throws -> IOSFailedHistoryRetrySetupSnapshot {
    try IOSFailedHistoryRetrySetupSnapshot(
        credentialEligibility: .available,
        transcriptionConfiguration: transcription,
        transcriptionPromptComposition: prompt,
        textCorrectionConfiguration: correction,
        postProcessingConfiguration: postProcessing,
        translationConfiguration: translation,
        keepLatestResult: keepLatestResult
    )
}

private func retryPipelinePrompt(
    _ freeformPrompt: String
) -> TranscriptionPromptComposition {
    TranscriptionPromptComposition(
        resolvedFreeformPrompt: freeformPrompt,
        context: nil,
        emojiCommandsConfiguration: .defaults,
        customDictionary: .empty
    )
}

private func retryPipelineTimeouts() throws
    -> IOSFailedHistoryRetryProviderTimeouts {
    try IOSFailedHistoryRetryProviderTimeouts(
        transcription: .seconds(101),
        correction: .seconds(102),
        translation: .seconds(103)
    )
}

private func retryPipelineAudio() -> IOSPendingTranscriptionAudio {
    let data = Data([0x41, 0x42, 0x43, 0x44, 0x45])
    let artifact = AudioRecordingArtifact(
        fileURL: URL(
            fileURLWithPath:
                "/private/tmp/retry-pipeline-\(UUID().uuidString).m4a"
        ),
        duration: 1.25,
        byteCount: Int64(data.count)
    )
    return IOSPendingTranscriptionAudio(
        lease: RetryPipelineAudioLease(
            artifact: artifact,
            data: data
        )
    )
}

private actor RetryPipelineEventLog {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func values() -> [String] {
        events
    }
}

private struct RetryPipelineTranscriptionSnapshot: Equatable, Sendable {
    let transcriptionID: UUID
    let audioMatches: Bool
    let audioBytes: Data?
    let resolvedModel: String
    let resolvedLanguageCode: String?
    let promptComposition: TranscriptionPromptComposition
    let timeout: Duration
}

private actor RetryPipelineProviderFake:
    IOSFailedHistoryRetryProviderExecuting {
    private let expectedAudio: IOSPendingTranscriptionAudio
    private let transcriptionOutcome:
        IOSFailedHistoryRetryProviderTextOutcome
    private let correctionOutcome: IOSFailedHistoryRetryProviderTextOutcome
    private let translationOutcome: IOSFailedHistoryRetryProviderTextOutcome
    private let events: RetryPipelineEventLog?

    private var storedTranscriptionSnapshot:
        RetryPipelineTranscriptionSnapshot?
    private var storedCorrectionSnapshot:
        IOSFailedHistoryRetryCorrectionRequest?
    private var storedTranslationSnapshot:
        IOSFailedHistoryRetryTranslationRequest?
    private var storedCorrectionCallCount = 0
    private var storedTranslationCallCount = 0

    init(
        expectedAudio: IOSPendingTranscriptionAudio,
        transcription: IOSFailedHistoryRetryProviderTextOutcome,
        correction: IOSFailedHistoryRetryProviderTextOutcome,
        translation: IOSFailedHistoryRetryProviderTextOutcome,
        events: RetryPipelineEventLog? = nil
    ) {
        self.expectedAudio = expectedAudio
        transcriptionOutcome = transcription
        correctionOutcome = correction
        translationOutcome = translation
        self.events = events
    }

    func transcribe(
        _ request: IOSFailedHistoryRetryTranscriptionRequest
    ) async -> IOSFailedHistoryRetryProviderTextOutcome {
        await events?.append("provider.transcription")
        let bytes = try? await request.audio.read(
            atOffset: 0,
            maximumByteCount: 3
        )
        storedTranscriptionSnapshot = RetryPipelineTranscriptionSnapshot(
            transcriptionID: request.transcriptionID,
            audioMatches: request.audio === expectedAudio,
            audioBytes: bytes,
            resolvedModel: request.resolvedModel,
            resolvedLanguageCode: request.resolvedLanguageCode,
            promptComposition: request.promptComposition,
            timeout: request.timeout
        )
        return transcriptionOutcome
    }

    func correct(
        _ request: IOSFailedHistoryRetryCorrectionRequest
    ) async -> IOSFailedHistoryRetryProviderTextOutcome {
        await events?.append("provider.correction")
        storedCorrectionCallCount += 1
        storedCorrectionSnapshot = request
        return correctionOutcome
    }

    func translate(
        _ request: IOSFailedHistoryRetryTranslationRequest
    ) async -> IOSFailedHistoryRetryProviderTextOutcome {
        await events?.append("provider.translation")
        storedTranslationCallCount += 1
        storedTranslationSnapshot = request
        return translationOutcome
    }

    func transcriptionSnapshot()
        -> RetryPipelineTranscriptionSnapshot? {
        storedTranscriptionSnapshot
    }

    func correctionSnapshot()
        -> IOSFailedHistoryRetryCorrectionRequest? {
        storedCorrectionSnapshot
    }

    func translationSnapshot()
        -> IOSFailedHistoryRetryTranslationRequest? {
        storedTranslationSnapshot
    }

    func correctionCallCount() -> Int {
        storedCorrectionCallCount
    }

    func translationCallCount() -> Int {
        storedTranslationCallCount
    }
}

private enum RetryPipelineUsageError: Error {
    case unavailable
}

private actor RetryPipelineUsageRecorderFake:
    IOSFailedHistoryRetryUsageRecording {
    private let events: RetryPipelineEventLog?
    private let shouldFail: Bool
    private var calls: [SuccessfulTranscriptionUsage] = []

    init(
        events: RetryPipelineEventLog? = nil,
        shouldFail: Bool = false
    ) {
        self.events = events
        self.shouldFail = shouldFail
    }

    func recordRetryUsage(
        _ usage: SuccessfulTranscriptionUsage
    ) async throws {
        await events?.append("usage.record")
        calls.append(usage)
        if shouldFail {
            throw RetryPipelineUsageError.unavailable
        }
    }

    func recordedUsage() -> SuccessfulTranscriptionUsage? {
        calls.first
    }

    func callCount() -> Int {
        calls.count
    }
}

private actor RetryPipelineSecretUsageRecorder:
    IOSFailedHistoryRetryUsageRecording {
    private let pathCanary: String

    init(pathCanary: String) {
        self.pathCanary = pathCanary
    }

    func recordRetryUsage(
        _ usage: SuccessfulTranscriptionUsage
    ) async throws {
        _ = usage
        _ = pathCanary
    }
}

private struct SelectiveRetryPipelineSleeper:
    IOSFailedHistoryRetryTimeoutSleeping {
    let immediateDuration: Duration

    func sleep(for duration: Duration) async throws {
        guard duration == immediateDuration else {
            try await Task<Never, Never>.sleep(for: .seconds(3_600))
            return
        }
    }
}

private enum BlockingRetryPipelineStage: Sendable {
    case transcription
    case correction
    case translation
}

private actor BlockingRetryPipelineProvider:
    IOSFailedHistoryRetryProviderExecuting {
    private let blockedStage: BlockingRetryPipelineStage
    private let expectedAudio: IOSPendingTranscriptionAudio
    private let lateOutcome: IOSFailedHistoryRetryProviderTextOutcome
    private let started = RetryPipelineLatch()
    private let release = RetryPipelineLatch()
    private let finished = RetryPipelineLatch()
    private let lowerLayerFinished = RetryPipelineLatch()
    private var storedObservedCancellation = false

    init(
        blockedStage: BlockingRetryPipelineStage,
        expectedAudio: IOSPendingTranscriptionAudio,
        lateOutcome: IOSFailedHistoryRetryProviderTextOutcome
    ) {
        self.blockedStage = blockedStage
        self.expectedAudio = expectedAudio
        self.lateOutcome = lateOutcome
    }

    func transcribe(
        _ request: IOSFailedHistoryRetryTranscriptionRequest
    ) async -> IOSFailedHistoryRetryProviderTextOutcome {
        guard request.audio === expectedAudio else {
            return .failure(.invalidRecording)
        }
        if blockedStage == .transcription {
            return await block()
        }
        return .success("blocking raw transcript")
    }

    func correct(
        _ request: IOSFailedHistoryRetryCorrectionRequest
    ) async -> IOSFailedHistoryRetryProviderTextOutcome {
        _ = request
        if blockedStage == .correction {
            return await block()
        }
        return .success("blocking corrected transcript")
    }

    func translate(
        _ request: IOSFailedHistoryRetryTranslationRequest
    ) async -> IOSFailedHistoryRetryProviderTextOutcome {
        _ = request
        if blockedStage == .translation {
            return await block()
        }
        return .success("blocking translated transcript")
    }

    func waitUntilStarted() async {
        await started.wait()
    }

    func releaseBlockedStage() async {
        await release.open()
    }

    func waitUntilFinished() async {
        await finished.wait()
    }

    func lowerLayerHasFinished() async -> Bool {
        await lowerLayerFinished.value()
    }

    func waitUntilLowerLayerFinished() async {
        await lowerLayerFinished.wait()
    }

    func observedCancellation() -> Bool {
        storedObservedCancellation
    }

    private func block() async -> IOSFailedHistoryRetryProviderTextOutcome {
        await started.open()
        let race = RetryPipelineBlockingAdapterRace()
        let release = release
        let lowerLayerFinished = lowerLayerFinished
        Task {
            await release.wait()
            await lowerLayerFinished.open()
            await race.resolve(.lowerLayer)
        }
        let resolution = await withTaskCancellationHandler {
            await race.wait()
        } onCancel: {
            Task {
                await race.resolve(.cancelled)
            }
        }
        switch resolution {
        case .lowerLayer:
            await finished.open()
            return lateOutcome
        case .cancelled:
            storedObservedCancellation = true
            await finished.open()
            return .failure(.cancelled)
        }
    }
}

private actor RetryPipelineBlockingAdapterRace {
    enum Resolution: Sendable {
        case lowerLayer
        case cancelled
    }

    private var resolution: Resolution?
    private var waiters: [CheckedContinuation<Resolution, Never>] = []

    func resolve(_ candidate: Resolution) {
        guard resolution == nil else { return }
        resolution = candidate
        let currentWaiters = waiters
        waiters.removeAll()
        for waiter in currentWaiters {
            waiter.resume(returning: candidate)
        }
    }

    func wait() async -> Resolution {
        if let resolution { return resolution }
        return await withCheckedContinuation { continuation in
            if let resolution {
                continuation.resume(returning: resolution)
            } else {
                waiters.append(continuation)
            }
        }
    }
}

private actor RetryPipelineLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let currentWaiters = waiters
        waiters.removeAll()
        for waiter in currentWaiters {
            waiter.resume()
        }
    }

    func value() -> Bool {
        isOpen
    }
}

private final class RetryPipelineAudioLease:
    IOSPendingRecordingPublishedAudioLease,
    @unchecked Sendable {
    let relativeIdentifier = "Recordings/Pending/retry-pipeline.m4a"
    let audioArtifact: AudioRecordingArtifact
    let durationMilliseconds: Int64

    private let data: Data

    init(
        artifact: AudioRecordingArtifact,
        data: Data
    ) {
        audioArtifact = artifact
        durationMilliseconds = 1_250
        self.data = data
    }

    func revalidate() async throws -> AudioRecordingArtifact {
        audioArtifact
    }

    func read(
        atOffset offset: Int64,
        maximumByteCount: Int
    ) async throws -> Data {
        guard offset >= 0,
              offset <= Int64(data.count),
              maximumByteCount > 0 else {
            throw IOSPendingRecordingAudioFileSystemError
                .protectedAudioInvalid
        }
        let start = Int(offset)
        let end = min(data.count, start + maximumByteCount)
        return data.subdata(in: start..<end)
    }

    func release() {}
}
