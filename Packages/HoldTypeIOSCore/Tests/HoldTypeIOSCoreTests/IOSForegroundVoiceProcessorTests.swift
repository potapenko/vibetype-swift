import Foundation
import HoldTypeDomain
import HoldTypeOpenAI
@_spi(HoldTypeIOSCore) import HoldTypePersistence
import Testing
@_spi(HoldTypeIOSCore) @testable import HoldTypeIOSCore

@MainActor
@Suite(.serialized)
struct IOSForegroundVoiceProcessorTests {
    @Test func standardFlowTransformsTextAndCommitsLatest() async throws {
        var settings = IOSAppSettings.defaults
        settings.localTextCleanupEnabled = true
        let fixture = try await ProcessorFixture(
            settings: settings,
            library: IOSLibraryContent(
                replacementRules: [
                    TextReplacementRule(
                        search: "voice",
                        replacement: "world"
                    ),
                ]
            )
        )
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let usage = ProcessorUsageCapture()
        let progress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            provider: provider(
                transcribe: { request, _ in
                    calls.record("transcription")
                    #expect(request.model == fixture.pending.transcriptionModel)
                    return "“Hello”—voice…"
                }
            ),
            usageCapture: usage
        )

        let result = await processor.process(
            fixture.request(),
            progress: { progress.record($0) }
        )
        let record = try result.requireReady()

        #expect(record.acceptedText == "\"Hello\" - world...")
        #expect(record.sourceAttemptID == fixture.pending.attemptID)
        #expect(calls.events == ["transcription"])
        #expect(usage.values.count == 1)
        #expect(
            usage.values.first?.transcriptionID
                != fixture.pending.transcriptionID
        )
        #expect(try await fixture.persistenceOwner.load() == nil)
        guard case .resultReady(let latest) =
            try await fixture.persistenceOwner.loadLatestResult() else {
            Issue.record("Expected Latest Result after acceptance.")
            return
        }
        #expect(latest.resultID == record.resultID)
        #expect(latest.sourceAttemptID == record.sourceAttemptID)
        #expect(latest.acceptedText == record.acceptedText)
        let history = try await IOSAcceptedTextHistoryRepository(
            applicationSupportDirectoryURL: fixture.root
        ).load()
        #expect(history.entries.count == 1)
        #expect(history.entries.first?.resultID == record.resultID)
        #expect(history.entries.first?.text == record.acceptedText)
        #expect(
            progress.stages
                == [.transcription, .postProcessing, .outputDelivery]
        )
    }

    @Test func definitiveProviderFailureAllowsOnlyExplicitRetry()
        async throws {
        let fixture = try await ProcessorFixture()
        defer { fixture.removeFiles() }
        let providerSequence = ProcessorTranscriptionSequence(
            outcomes: [
                .failure(.rateLimited),
                .success("Explicit retry result"),
            ]
        )
        let processor = fixture.makeProcessor(
            provider: provider(
                transcribe: { request, _ in
                    try providerSequence.next(model: request.model)
                }
            )
        )

        guard case .retryAvailable(
            let failed,
            failure: .providerUnavailable,
            stage: .transcription
        ) = await processor.process(fixture.request()) else {
            Issue.record("Expected one durable failed Pending.")
            return
        }
        #expect(failed.phase == .failed)
        #expect(failed.transcriptionID == nil)
        #expect(providerSequence.callCount == 1)

        // Constructing another processor and observing durable state performs
        // no provider work. Only the explicit request below is allowed to run.
        _ = fixture.makeProcessor(
            provider: provider(
                transcribe: { request, _ in
                    try providerSequence.next(model: request.model)
                }
            )
        )
        #expect(try await fixture.persistenceOwner.load()?.recording == failed)
        #expect(providerSequence.callCount == 1)

        var retrySettings = fixture.settings
        retrySettings.transcriptionConfiguration =
            TranscriptionConfiguration(
                model: "current-retry-model",
                language: .russian
            )
        let record = try await processor.process(
            fixture.request(
                pendingRecording: failed,
                mode: .retry,
                settings: retrySettings
            )
        ).requireReady()

        #expect(record.acceptedText == "Explicit retry result")
        #expect(providerSequence.callCount == 2)
        #expect(
            providerSequence.models
                == [fixture.pending.transcriptionModel, "current-retry-model"]
        )
    }

    @Test
    func ambiguousDispatchedFailuresBlockTranscriptionReplayAcrossRelaunch()
        async throws {
        let cases: [(
            OpenAITranscriptionServiceError,
            IOSForegroundVoiceProcessingFailure
        )] = [
            (.networkUnavailable, .networkUnavailable),
            (.timedOut, .timedOut),
            (.networkFailure, .networkFailure),
            (.cancelled, .cancelled),
        ]

        for (providerError, expectedFailure) in cases {
            let fixture = try await ProcessorFixture()
            defer { fixture.removeFiles() }
            let calls = ProcessorCallLog()
            let processor = fixture.makeProcessor(
                provider: provider(
                    transcribe: { _, _ in
                        calls.record("transcription")
                        throw providerError
                    }
                )
            )

            guard case .retryAvailable(
                let failed,
                failure: let failure,
                stage: .transcription
            ) = await processor.process(fixture.request()) else {
                Issue.record("Expected durable ambiguous failure.")
                continue
            }
            #expect(failure == expectedFailure)
            #expect(failed.phase == .failed)
            #expect(failed.transcriptionReplayBlocked)
            #expect(calls.events == ["transcription"])

            #expect(
                await fixture.persistenceOwner.recoverContainingAppLifecycle(
                    .processLaunch
                ) == .complete
            )
            let relaunched = try #require(
                try await fixture.persistenceOwner.load()?.recording
            )
            #expect(relaunched.transcriptionReplayBlocked)
            await #expect(
                throws: IOSV1ForegroundVoicePersistenceError
                    .invalidTransition
            ) {
                _ = try await fixture.persistenceOwner.retryTranscription(
                    expected: IOSV1PendingRecordingExpectation(
                        recording: relaunched
                    ),
                    transcriptionID: UUID(),
                    transcriptionConfiguration: .defaults
                )
            }
            #expect(calls.events == ["transcription"])
        }
    }

    @Test
    func explicitCancelAfterDispatchRejectsHostileSuccessAndBlocksReplay()
        async throws {
        let fixture = try await ProcessorFixture()
        defer { fixture.removeFiles() }
        let cancellationAuthority =
            IOSForegroundVoiceProcessingCancellationAuthority()
        let hostileProvider = ProcessorCancellationHostileProvider()
        let processor = fixture.makeProcessor(
            provider: provider(
                transcribe: { _, _ in
                    await hostileProvider.transcribe()
                }
            )
        )
        let task = Task {
            await processor.process(
                fixture.request(
                    cancellationAuthority: cancellationAuthority
                )
            )
        }

        await hostileProvider.waitUntilLaunched()
        cancellationAuthority.cancelExplicitly()
        task.cancel()
        hostileProvider.returnSuccess()

        guard case .retryAvailable(
            let failed,
            failure: .cancelled,
            stage: .transcription
        ) = await task.value else {
            Issue.record("Expected one outcome-uncertain Pending.")
            return
        }
        #expect(failed.phase == .failed)
        #expect(failed.transcriptionReplayBlocked)
        #expect(try await fixture.persistenceOwner.load()?.recording == failed)
        #expect(
            try await fixture.persistenceOwner.loadLatestResult()
                == .absent
        )
        let history = try await IOSAcceptedTextHistoryRepository(
            applicationSupportDirectoryURL: fixture.root
        ).load()
        #expect(history.entries.isEmpty)
        await #expect(
            throws: IOSV1ForegroundVoicePersistenceError.invalidTransition
        ) {
            _ = try await fixture.persistenceOwner.retryTranscription(
                expected: IOSV1PendingRecordingExpectation(recording: failed),
                transcriptionID: UUID(),
                transcriptionConfiguration: .defaults
            )
        }
    }

    @Test func correctionFailureIsFailOpenAndCredentialRejectionIsRecorded()
        async throws {
        var settings = IOSAppSettings.defaults
        settings.textCorrectionConfiguration.isEnabled = true
        let fixture = try await ProcessorFixture(settings: settings)
        defer { fixture.removeFiles() }
        let rejected = ProcessorGenerationCapture()
        let processor = fixture.makeProcessor(
            provider: provider(
                transcribe: { _, _ in "Original transcript" },
                correct: { _, _, _ in
                    throw OpenAITextCorrectionServiceError.invalidAPIKey
                }
            ),
            rejectionCapture: rejected
        )

        let record = try await processor.process(
            fixture.request()
        ).requireReady()

        #expect(record.acceptedText == "Original transcript")
        #expect(rejected.values == [fixture.credential.generation])
    }

    @Test func oneShotImprovementForcesCorrectionWithoutChangingSettings()
        async throws {
        let fixture = try await ProcessorFixture()
        defer { fixture.removeFiles() }
        #expect(!fixture.settings.textCorrectionConfiguration.isEnabled)
        let processor = fixture.makeProcessor(
            provider: provider(
                transcribe: { _, _ in "original transcript" },
                correct: { _, _, _ in "Improved transcript" }
            )
        )

        let record = try await processor.process(
            fixture.request(forcesTextCorrection: true)
        ).requireReady()

        #expect(record.acceptedText == "Improved transcript")
        #expect(!fixture.settings.textCorrectionConfiguration.isEnabled)
    }

    @Test func translationRetryUsesRetainedIntermediateWithoutCorrectionReplay()
        async throws {
        var settings = IOSAppSettings.defaults
        settings.textCorrectionConfiguration.isEnabled = true
        settings.translationConfiguration = TranslationConfiguration(
            actionPreferenceEnabled: true,
            targetLanguage: .french
        )
        let fixture = try await ProcessorFixture(
            outputIntent: .translate,
            settings: settings
        )
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let usage = ProcessorUsageCapture()
        let translations = ProcessorTranslationSequence(
            outcomes: [
                .failure(.timedOut),
                .success("Texte traduit"),
            ]
        )
        let processor = fixture.makeProcessor(
            provider: provider(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Translate me"
                },
                correct: { _, _, _ in
                    calls.record("correction")
                    return "Corrected intermediate"
                },
                translate: { _, _ in
                    calls.record("translation")
                    return try translations.next()
                }
            ),
            usageCapture: usage
        )

        guard case .retryAvailable(
            let failed,
            failure: .timedOut,
            stage: .postProcessing
        ) = await processor.process(fixture.request()) else {
            Issue.record("Expected failed Pending after Translation failure.")
            return
        }
        #expect(failed.phase == .failed)
        #expect(failed.textCheckpointStage == .translationReady)
        #expect(failed.textCheckpointText == "Corrected intermediate")
        #expect(try await fixture.persistenceOwner.load()?.recording == failed)
        #expect(
            try await fixture.persistenceOwner.loadLatestResult() == .absent
        )

        let recreated = fixture.makeProcessor(
            provider: provider(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "unexpected transcription"
                },
                correct: { _, _, _ in
                    calls.record("correction")
                    return "unexpected correction"
                },
                translate: { _, _ in
                    calls.record("translation")
                    return try translations.next()
                }
            ),
            usageCapture: usage
        )
        let accepted = try await recreated.process(
            fixture.request(
                pendingRecording: failed,
                mode: .retry,
                settings: settings
            )
        ).requireReady()

        #expect(accepted.acceptedText == "Texte traduit")
        #expect(
            calls.events
                == [
                    "transcription", "correction", "translation",
                    "translation",
                ]
        )
        #expect(translations.callCount == 2)
        #expect(usage.values.count == 1)
    }

    @Test func fiveMinuteOutputCheckpointRetriesLocallyWithoutProviderAuthority()
        async throws {
        var settings = IOSAppSettings.defaults
        settings.textCorrectionConfiguration.isEnabled = true
        settings.translationConfiguration = TranslationConfiguration(
            actionPreferenceEnabled: true,
            targetLanguage: .french
        )
        let fixture = try await ProcessorFixture(
            outputIntent: .translate,
            settings: settings,
            audioDurationSeconds: 300
        )
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let usage = ProcessorUsageCapture()
        let persistence = CommitThenThrowPersistence(
            base: fixture.persistenceOwner,
            failureMode: .outputTransitionBeforeCommit
        )
        let initial = fixture.makeProcessor(
            persistence: persistence,
            provider: provider(
                transcribe: { request, _ in
                    calls.record("transcription")
                    #expect(request.durationMilliseconds >= 299_500)
                    #expect(request.durationMilliseconds <= 302_000)
                    return "Five minute source"
                },
                correct: { _, _, _ in
                    calls.record("correction")
                    return "Corrected five minute source"
                },
                translate: { _, _ in
                    calls.record("translation")
                    return "Résultat final conservé"
                }
            ),
            usageCapture: usage
        )

        guard case .retryAvailable(
            let failed,
            failure: .localPersistence,
            stage: .postProcessing
        ) = await initial.process(fixture.request()) else {
            Issue.record("Expected retained final-output checkpoint.")
            return
        }
        #expect(failed.phase == .failed)
        #expect(failed.textCheckpointStage == .outputReady)
        #expect(failed.textCheckpointText == "Résultat final conservé")
        #expect(failed.acceptedAudioRetention == .savedFiveMinute)
        #expect(failed.durationMilliseconds >= 299_500)
        #expect(failed.durationMilliseconds <= 302_000)
        #expect(
            calls.events == ["transcription", "correction", "translation"]
        )
        #expect(usage.values.count == 1)
        #expect(
            usage.values.first?.audioDuration
                == TimeInterval(failed.durationMilliseconds) / 1_000
        )

        let withdrawn = try await fixture.consentCoordinator.withdraw(
            using: fixture.acceptedConsent,
            decisionAt: Date(timeIntervalSince1970: 1_800_000_001)
        )
        var invalidProviderSettings = settings
        invalidProviderSettings.transcriptionConfiguration =
            TranscriptionConfiguration(
                language: .custom,
                customLanguageCode: "invalid-code"
            )
        let progress = ProcessorProgressCapture()
        let recreated = fixture.makeProcessor(
            provider: provider(
                transcribe: { _, _ in
                    calls.record("unexpected-transcription")
                    return "unexpected"
                },
                correct: { _, _, _ in
                    calls.record("unexpected-correction")
                    return "unexpected"
                },
                translate: { _, _ in
                    calls.record("unexpected-translation")
                    return "unexpected"
                }
            ),
            usageCapture: usage
        )
        let accepted = try await recreated.process(
            fixture.request(
                pendingRecording: failed,
                mode: .retry,
                settings: invalidProviderSettings,
                consentObservation: withdrawn
            ),
            progress: { progress.record($0) }
        ).requireReady()

        #expect(accepted.acceptedText == "Résultat final conservé")
        #expect(
            calls.events == ["transcription", "correction", "translation"]
        )
        #expect(usage.values.count == 1)
        #expect(progress.stages == [.postProcessing, .outputDelivery])
        let saved = try await IOSAcceptedAudioCache(
            applicationSupportDirectoryURL: fixture.root
        ).savedRecordings()
        #expect(saved.count == 1)
    }

    @Test func lostTranslationResultIsSealedAndNeverReplayed() async throws {
        var settings = IOSAppSettings.defaults
        settings.translationConfiguration = TranslationConfiguration(
            actionPreferenceEnabled: true,
            targetLanguage: .french
        )
        let fixture = try await ProcessorFixture(
            outputIntent: .translate,
            settings: settings
        )
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let usage = ProcessorUsageCapture()
        let persistence = CommitThenThrowPersistence(
            base: fixture.persistenceOwner,
            failureMode: .outputCheckpointBeforeCommit
        )
        let initial = fixture.makeProcessor(
            persistence: persistence,
            provider: provider(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Translate once"
                },
                translate: { _, _ in
                    calls.record("translation")
                    return "Traduction perdue"
                }
            ),
            usageCapture: usage
        )

        guard case .retryAvailable(
            let failed,
            failure: .localPersistence,
            stage: .postProcessing
        ) = await initial.process(fixture.request()) else {
            Issue.record("Expected sealed unknown Translation result.")
            return
        }
        #expect(failed.textCheckpointStage == .translationInFlight)
        #expect(failed.textCheckpointText == "Translate once")
        #expect(calls.events == ["transcription", "translation"])
        #expect(usage.values.count == 1)

        let recreated = fixture.makeProcessor(
            provider: provider(
                transcribe: { _, _ in
                    calls.record("unexpected-transcription")
                    return "unexpected"
                },
                translate: { _, _ in
                    calls.record("unexpected-translation")
                    return "unexpected"
                }
            ),
            usageCapture: usage
        )
        #expect(
            await recreated.process(
                fixture.request(
                    pendingRecording: failed,
                    mode: .retry,
                    settings: settings
                )
            ) == .notStarted(.localPersistence)
        )
        #expect(calls.events == ["transcription", "translation"])
        #expect(usage.values.count == 1)
    }

    @Test func acceptedTranscriptCheckpointFailureNeverReopensAudioDispatch()
        async throws {
        let fixture = try await ProcessorFixture()
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let usage = ProcessorUsageCapture()
        let persistence = CommitThenThrowPersistence(
            base: fixture.persistenceOwner,
            failureMode: .acceptedCheckpointBeforeCommit
        )
        let initial = fixture.makeProcessor(
            persistence: persistence,
            provider: provider(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Accepted but checkpoint unavailable"
                }
            ),
            usageCapture: usage
        )

        #expect(
            await initial.process(fixture.request())
                == .notStarted(.localPersistence)
        )
        let liveLost = try #require(
            try await fixture.persistenceOwner.load()?.recording
        )
        #expect(liveLost.phase == .transcribing)
        #expect(liveLost.acceptedTranscript == nil)
        #expect(calls.events == ["transcription"])
        #expect(usage.values.count == 1)

        let sameProcess = fixture.makeProcessor(
            provider: provider(
                transcribe: { _, _ in
                    calls.record("unexpected-transcription")
                    return "unexpected"
                }
            ),
            usageCapture: usage
        )
        #expect(
            await sameProcess.process(
                fixture.request(
                    pendingRecording: liveLost,
                    mode: .retry
                )
            ) == .notStarted(.invalidConfiguration)
        )

        #expect(
            await fixture.persistenceOwner.recoverContainingAppLifecycle(
                .processLaunch
            ) == .complete
        )
        let replayBlocked = try #require(
            try await fixture.persistenceOwner.load()?.recording
        )
        #expect(replayBlocked.phase == .failed)
        #expect(replayBlocked.transcriptionReplayBlocked)
        guard case .retryAvailable(
            let observed,
            failure: .localPersistence,
            stage: .transcription
        ) = await fixture.makeProcessor(
            provider: provider(
                transcribe: { _, _ in
                    calls.record("unexpected-transcription")
                    return "unexpected"
                }
            ),
            usageCapture: usage
        ).process(
            fixture.request(
                pendingRecording: replayBlocked,
                mode: .retry
            )
        ) else {
            Issue.record("Expected replay-blocked durable recovery.")
            return
        }
        #expect(observed == replayBlocked)
        #expect(calls.events == ["transcription"])
        #expect(usage.values.count == 1)
    }

    @Test func acceptanceCommitUncertaintyReconcilesWithoutProviderReplay()
        async throws {
        let fixture = try await ProcessorFixture()
        defer { fixture.removeFiles() }
        let persistence = CommitThenThrowPersistence(
            base: fixture.persistenceOwner
        )
        let calls = ProcessorCallLog()
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: provider(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Committed once"
                }
            )
        )

        let record = try await processor.process(
            fixture.request()
        ).requireReady()

        #expect(record.acceptedText == "Committed once")
        #expect(calls.events == ["transcription"])
        #expect(persistence.acceptCallCount == 1)
        #expect(persistence.reconcileCallCount == 1)
        #expect(try await fixture.persistenceOwner.load() == nil)
    }

    @Test func invalidInitialConfigurationNeverStartsProvider() async throws {
        let fixture = try await ProcessorFixture()
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let processor = fixture.makeProcessor(
            provider: provider(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "unexpected"
                }
            )
        )

        var mismatchingSettings = fixture.settings
        mismatchingSettings.transcriptionConfiguration =
            TranscriptionConfiguration(model: "mismatching-model")
        #expect(
            await processor.process(
                fixture.request(settings: mismatchingSettings)
            ) == .notStarted(.invalidConfiguration)
        )
        #expect(calls.events.isEmpty)
        #expect(
            try await fixture.persistenceOwner.load()?.recording
                == fixture.pending
        )
    }

    @Test func draftCorrectionSkipsRecordingTranscriptionAndDurableVoiceState()
        async throws {
        let fixture = try await ProcessorFixture()
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let processor = fixture.makeProcessor(
            provider: provider(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "unexpected"
                },
                correct: { transcript, configuration, _ in
                    calls.record("correction")
                    #expect(configuration.isEnabled)
                    #expect(transcript.text == "Original Draft")
                    return "Improved Draft"
                }
            )
        )

        let result = await processor.processDraftText(
            fixture.draftRequest(
                action: .correct,
                text: "Original Draft"
            )
        )

        #expect(result == .success("Improved Draft"))
        #expect(calls.events == ["correction"])
        #expect(
            try await fixture.persistenceOwner.load()?.recording
                == fixture.pending
        )
        #expect(
            try await fixture.persistenceOwner.loadLatestResult() == .absent
        )
    }

    @Test func draftTranslationUsesSavedRouteAndMapsBoundedFailure()
        async throws {
        var settings = IOSAppSettings.defaults
        settings.translationConfiguration = TranslationConfiguration(
            actionPreferenceEnabled: true,
            targetLanguage: .french
        )
        let fixture = try await ProcessorFixture(settings: settings)
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let processor = fixture.makeProcessor(
            provider: provider(
                translate: { request, _ in
                    calls.record("translation")
                    #expect(
                        request.translationConfiguration.targetLanguage
                            == .french
                    )
                    throw OpenAITextTranslationServiceError.timedOut
                }
            )
        )

        let result = await processor.processDraftText(
            fixture.draftRequest(
                action: .translate,
                text: "Translate this"
            )
        )

        #expect(result == .failure(.timedOut))
        #expect(calls.events == ["translation"])
        #expect(
            try await fixture.persistenceOwner.load()?.recording
                == fixture.pending
        )
    }

    @Test func diagnosticsRedactTextCredentialAndPaths() async throws {
        let fixture = try await ProcessorFixture()
        defer { fixture.removeFiles() }
        let request = fixture.request()
        let draftRequest = fixture.draftRequest(
            action: .correct,
            text: "private draft canary"
        )
        let processor = fixture.makeProcessor(provider: provider())
        var dumpText = ""
        dump((request, draftRequest, processor), to: &dumpText)
        let diagnostics = [
            dumpText,
            String(describing: request),
            String(reflecting: request),
            String(describing: draftRequest),
            String(reflecting: draftRequest),
            String(describing: processor),
            String(reflecting: processor),
        ].joined(separator: "\n")

        #expect(
            diagnostics.contains(
                "IOSForegroundVoiceProcessingRequest(redacted)"
            )
        )
        #expect(
            diagnostics.contains(
                "IOSVoiceDraftTextActionRequest(redacted)"
            )
        )
        #expect(diagnostics.contains("IOSForegroundVoiceProcessor(redacted)"))
        for canary in [
            "sk-processor-test",
            "private draft canary",
            fixture.root.path,
        ] {
            #expect(!diagnostics.contains(canary))
        }
    }
}

private final class ProcessorFixture: @unchecked Sendable {
    let root: URL
    let persistenceOwner: IOSV1ForegroundVoicePersistenceOwner
    let consentCoordinator: IOSV1ProviderConsentCoordinator
    let acceptedConsent: IOSV1ProviderConsentObservation
    let pending: IOSV1PendingRecording
    let settings: IOSAppSettings
    let library: IOSLibraryContent
    let credential: IOSResolvedOpenAICredential

    init(
        outputIntent: DictationOutputIntent = .standard,
        settings: IOSAppSettings = .defaults,
        library: IOSLibraryContent = .defaults,
        audioDurationSeconds: Int = 3
    ) async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ios-v1-foreground-processor-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        self.settings = settings
        self.library = library
        persistenceOwner = IOSV1ForegroundVoicePersistenceOwner(
            applicationSupportDirectoryURL: root
        )

        let attemptID = UUID()
        let audio = try makeForegroundVoiceTestM4A(
            durationSeconds: audioDurationSeconds
        )
        let lease = try await persistenceOwner.createCapture(
            attemptID: attemptID,
            outputIntent: outputIntent
        )
        try lease.withTransientRecordingURL { url in
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: audio)
            try handle.close()
        }
        try lease.revalidateRecorderCheckpoint()
        try await lease.beginFinalizing()
        guard case .completed(let completed) =
            try await lease.completeAfterRecorderClose(
                fallbackDurationMilliseconds:
                    Int64(audioDurationSeconds) * 1_000
            ) else {
            throw ProcessorFixtureError.invalidCapture
        }
        _ = try await persistenceOwner.prepareCompletedCapture(
            completed,
            transcriptionConfiguration: settings.transcriptionConfiguration
        )
        guard let prepared = try await persistenceOwner.load()?.recording else {
            throw ProcessorFixtureError.invalidCapture
        }
        pending = prepared

        consentCoordinator = IOSV1ProviderConsentCoordinator(
            applicationSupportDirectoryURL: root
        )
        acceptedConsent = try await consentCoordinator.accept(
            using: await consentCoordinator.observe(),
            decisionAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        credential = IOSResolvedOpenAICredential(
            credential: try OpenAICredential(apiKey: "sk-processor-test"),
            generation: IOSOpenAICredentialGeneration(rawValue: UUID())
        )
    }

    func request(
        pendingRecording: IOSV1PendingRecording? = nil,
        mode: IOSForegroundVoiceProcessingMode = .initial,
        settings: IOSAppSettings? = nil,
        forcesTextCorrection: Bool = false,
        consentObservation: IOSV1ProviderConsentObservation? = nil,
        cancellationAuthority:
            IOSForegroundVoiceProcessingCancellationAuthority = .init()
    ) -> IOSForegroundVoiceProcessingRequest {
        IOSForegroundVoiceProcessingRequest(
            sessionID: UUID(),
            pendingRecording: pendingRecording ?? pending,
            mode: mode,
            settings: settings ?? self.settings,
            library: library,
            credential: credential,
            consentObservation: consentObservation ?? acceptedConsent,
            forcesTextCorrection: forcesTextCorrection,
            cancellationAuthority: cancellationAuthority
        )
    }

    func draftRequest(
        action: IOSVoiceDraftTextAction,
        text: String,
        settings: IOSAppSettings? = nil
    ) -> IOSVoiceDraftTextActionRequest {
        IOSVoiceDraftTextActionRequest(
            action: action,
            text: text,
            settings: settings ?? self.settings,
            credential: credential,
            consentObservation: acceptedConsent
        )
    }

    func makeProcessor(
        persistence: (any IOSForegroundVoicePersisting)? = nil,
        provider: IOSForegroundVoiceOpenAIProviderOperations,
        usageCapture: ProcessorUsageCapture? = nil,
        rejectionCapture: ProcessorGenerationCapture? = nil
    ) -> IOSForegroundVoiceProcessor {
        let identifiers = ProcessorUUIDSequence()
        return IOSForegroundVoiceProcessor(
            persistenceOwner: persistence ?? persistenceOwner,
            consentCoordinator: consentCoordinator,
            provider: provider,
            recordUsage: { usage in usageCapture?.record(usage) },
            recordProviderRejection: { generation in
                rejectionCapture?.record(generation)
            },
            makeUUID: { identifiers.next() }
        )
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class CommitThenThrowPersistence:
    IOSForegroundVoicePersisting,
    @unchecked Sendable {
    enum FailureMode: Equatable {
        case acceptAfterCommit
        case acceptedCheckpointBeforeCommit
        case outputTransitionBeforeCommit
        case outputCheckpointBeforeCommit
    }

    private let base: IOSV1ForegroundVoicePersistenceOwner
    private let failureMode: FailureMode
    private let lock = NSLock()
    private var storedAcceptCallCount = 0
    private var storedReconcileCallCount = 0
    private var injectedFailure = false

    init(
        base: IOSV1ForegroundVoicePersistenceOwner,
        failureMode: FailureMode = .acceptAfterCommit
    ) {
        self.base = base
        self.failureMode = failureMode
    }

    var acceptCallCount: Int { lock.withLock { storedAcceptCallCount } }
    var reconcileCallCount: Int { lock.withLock { storedReconcileCallCount } }

    func load() async throws -> IOSV1PendingRecordingObservation? {
        try await base.load()
    }

    func beginTranscription(
        expected: IOSV1PendingRecordingExpectation,
        transcriptionID: UUID
    ) async throws -> IOSV1ForegroundVoiceTranscriptionDispatch {
        try await base.beginTranscription(
            expected: expected,
            transcriptionID: transcriptionID
        )
    }

    func retryTranscription(
        expected: IOSV1PendingRecordingExpectation,
        transcriptionID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSV1ForegroundVoiceTranscriptionDispatch {
        try await base.retryTranscription(
            expected: expected,
            transcriptionID: transcriptionID,
            transcriptionConfiguration: transcriptionConfiguration
        )
    }

    func checkpointTranscription(
        expected: IOSV1PendingRecordingExpectation,
        acceptedTranscript: String
    ) async throws -> IOSV1PendingRecording {
        if takeFailure(.acceptedCheckpointBeforeCommit) {
            throw ProcessorFixtureError.injectedFailure
        }
        return try await base.checkpointTranscription(
            expected: expected,
            acceptedTranscript: acceptedTranscript
        )
    }

    func checkpointPostProcessing(
        expected: IOSV1PendingRecordingExpectation,
        stage: IOSV1PendingTextCheckpointStage,
        text: String
    ) async throws -> IOSV1PendingRecording {
        if stage == .outputReady,
           takeFailure(.outputCheckpointBeforeCommit) {
            throw ProcessorFixtureError.injectedFailure
        }
        return try await base.checkpointPostProcessing(
            expected: expected,
            stage: stage,
            text: text
        )
    }

    func retryPostProcessing(
        expected: IOSV1PendingRecordingExpectation,
        operationID: UUID
    ) async throws -> IOSV1PendingRecording {
        try await base.retryPostProcessing(
            expected: expected,
            operationID: operationID
        )
    }

    func markOutputDelivery(
        expected: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1PendingRecording {
        if takeFailure(.outputTransitionBeforeCommit) {
            throw ProcessorFixtureError.injectedFailure
        }
        return try await base.markOutputDelivery(expected: expected)
    }

    func markFailed(
        expected: IOSV1PendingRecordingExpectation,
        transcriptionReplayBlocked: Bool
    ) async throws -> IOSV1PendingRecording {
        try await base.markFailed(
            expected: expected,
            transcriptionReplayBlocked: transcriptionReplayBlocked
        )
    }

    func accept(
        _ preparation: IOSV1ForegroundVoiceAcceptedOutputPreparation,
        expectedPending: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1ForegroundVoiceAcceptanceResult {
        lock.withLock { storedAcceptCallCount += 1 }
        let result = try await base.accept(
            preparation,
            expectedPending: expectedPending
        )
        if failureMode == .acceptAfterCommit {
            throw ProcessorFixtureError.injectedFailure
        }
        return result
    }

    func reconcileAcceptance(
        matching preparation: IOSV1ForegroundVoiceAcceptedOutputPreparation
    ) async throws -> IOSV1ForegroundVoiceAcceptanceResult? {
        lock.withLock { storedReconcileCallCount += 1 }
        return try await base.reconcileAcceptance(matching: preparation)
    }

    private func takeFailure(_ mode: FailureMode) -> Bool {
        lock.withLock {
            guard failureMode == mode, !injectedFailure else { return false }
            injectedFailure = true
            return true
        }
    }
}

private final class ProcessorCancellationHostileProvider:
    @unchecked Sendable {
    private let lock = NSLock()
    private var launched = false
    private var continuation: CheckedContinuation<String, Never>?

    func transcribe() async -> String {
        await withCheckedContinuation { continuation in
            lock.withLock {
                launched = true
                self.continuation = continuation
            }
        }
    }

    func waitUntilLaunched() async {
        while !lock.withLock({ launched }) {
            await Task.yield()
        }
    }

    func returnSuccess() {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: "Late cancelled success")
    }
}

private func provider(
    transcribe: @escaping IOSForegroundVoiceOpenAIProviderOperations.Transcribe = {
        _, _ in "Transcript"
    },
    correct: @escaping IOSForegroundVoiceOpenAIProviderOperations.Correct = {
        transcript, _, _ in transcript.text
    },
    translate: @escaping IOSForegroundVoiceOpenAIProviderOperations.Translate = {
        _, _ in "Translated"
    }
) -> IOSForegroundVoiceOpenAIProviderOperations {
    IOSForegroundVoiceOpenAIProviderOperations(
        transcribe: transcribe,
        correct: correct,
        translate: translate
    )
}

private final class ProcessorCallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [String] = []

    var events: [String] { lock.withLock { storedEvents } }
    func record(_ event: String) {
        lock.withLock { storedEvents.append(event) }
    }
}

private final class ProcessorUsageCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [SuccessfulTranscriptionUsage] = []

    var values: [SuccessfulTranscriptionUsage] {
        lock.withLock { storedValues }
    }
    func record(_ value: SuccessfulTranscriptionUsage) {
        lock.withLock { storedValues.append(value) }
    }
}

private final class ProcessorGenerationCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [IOSOpenAICredentialGeneration] = []

    var values: [IOSOpenAICredentialGeneration] {
        lock.withLock { storedValues }
    }
    func record(_ value: IOSOpenAICredentialGeneration) {
        lock.withLock { storedValues.append(value) }
    }
}

@MainActor
private final class ProcessorProgressCapture {
    private(set) var stages: [VoiceAttemptStage] = []
    func record(_ stage: VoiceAttemptStage) { stages.append(stage) }
}

private final class ProcessorTranscriptionSequence: @unchecked Sendable {
    enum Outcome {
        case success(String)
        case failure(OpenAITranscriptionServiceError)
    }

    private let lock = NSLock()
    private var outcomes: [Outcome]
    private var storedModels: [String] = []

    init(outcomes: [Outcome]) { self.outcomes = outcomes }

    var callCount: Int { lock.withLock { storedModels.count } }
    var models: [String] { lock.withLock { storedModels } }

    func next(model: String) throws -> String {
        let outcome = lock.withLock { () -> Outcome in
            storedModels.append(model)
            return outcomes.removeFirst()
        }
        switch outcome {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
}

private final class ProcessorTranslationSequence: @unchecked Sendable {
    enum Outcome {
        case success(String)
        case failure(OpenAITextTranslationServiceError)
    }

    private let lock = NSLock()
    private var outcomes: [Outcome]
    private var storedCallCount = 0

    init(outcomes: [Outcome]) { self.outcomes = outcomes }

    var callCount: Int { lock.withLock { storedCallCount } }

    func next() throws -> String {
        let outcome = lock.withLock { () -> Outcome in
            storedCallCount += 1
            return outcomes.removeFirst()
        }
        switch outcome {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
}

private final class ProcessorUUIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var counter: UInt8 = 1

    func next() -> UUID {
        lock.withLock {
            defer { counter &+= 1 }
            return UUID(
                uuid: (
                    counter, 0, 0, 0, 0, 0x40, 0x40, 0x40,
                    0x80, 0, 0, 0, 0, 0, 0, counter
                )
            )
        }
    }
}

private enum ProcessorFixtureError: Error {
    case invalidCapture
    case injectedFailure
}

private extension IOSForegroundVoiceProcessingResolution {
    func requireReady() throws -> IOSV1AcceptedOutputDeliveryRecord {
        guard case .acceptance(.resultReady(let record, _)) = self else {
            throw ProcessorFixtureError.injectedFailure
        }
        return record
    }
}
