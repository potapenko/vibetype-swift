import Foundation
import HoldTypeDomain
import HoldTypeOpenAI
@_spi(HoldTypeIOSCore) import HoldTypePersistence
import Testing
@_spi(HoldTypeIOSCore) @testable import HoldTypeIOSCore

@MainActor
struct IOSForegroundVoiceProcessorTests {
    @Test func standardFlowUsesLocalLibraryRecordsUsageAndAcceptsP4Result()
        async throws {
        var settings = IOSAppSettings.defaults
        settings.localTextCleanupEnabled = true
        let library = IOSLibraryContent(
            replacementRules: [
                TextReplacementRule(
                    search: "voice",
                    replacement: "world"
                ),
            ]
        )
        let fixture = try await ProcessorFixture(
            outputIntent: .standard,
            settings: settings,
            library: library
        )
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let usageCapture = ProcessorUsageCapture()
        let progress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Hello voice"
                },
                correct: { _, _, _ in
                    calls.record("correction")
                    return "unexpected"
                },
                translate: { _, _ in
                    calls.record("translation")
                    return "unexpected"
                }
            ),
            calls: calls,
            usageCapture: usageCapture
        )

        #expect(fixture.request().historyMode == .appOnly)

        let resolution = await processor.process(
            fixture.request(),
            progress: { progress.record($0) }
        )
        let record = try resolution.requireReady()

        #expect(record.acceptedText == "Hello world")
        #expect(record.outputIntent == .standard)
        #expect(record.historyWrite == nil)
        #expect(calls.events == ["transcription", "usage"])
        #expect(usageCapture.values.count == 1)
        #expect(usageCapture.values.first?.transcriptionID == record.transcriptID)
        #expect(
            usageCapture.values.first?.model
                == fixture.pending.transcriptionModel
        )
        #expect(usageCapture.values.first?.audioDuration == 1)
        #expect(try await fixture.persistenceOwner.load() == nil)
        #expect(await processor.hasLocalRecoveryPending() == false)
        #expect(
            progress.stages
                == [.transcription, .postProcessing, .outputDelivery]
        )
    }

    @Test func capturedHistoryModeSurvivesProviderFreeAcceptanceRetry()
        async throws {
        let fixture = try await ProcessorFixture(
            outputIntent: .standard,
            usesHistoryDisclosureV2: true
        )
        defer { fixture.removeFiles() }
        let historyMode = try await fixture.capturedHistoryMode()
        let persistence = CapturingHistoryModeForegroundPersistence(
            base: fixture.persistenceOwner
        )
        let calls = ProcessorCallLog()
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Captured foreground result"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )
        let request = fixture.request(historyMode: historyMode)

        #expect(request.historyMode == historyMode)
        #expect(request.customMirror.children.isEmpty)
        #expect(
            String(describing: request)
                == "IOSForegroundVoiceProcessingRequest(redacted)"
        )
        #expect(
            await processor.process(request)
                == .localRecoveryPending(
                    failure: .localPersistence,
                    stage: .outputDelivery,
                    disposition: .savingResult,
                    requirement: .providerFree
                )
        )
        #expect(persistence.acceptedHistoryModes == [historyMode])
        #expect(calls.events == ["transcription", "usage"])

        _ = try await fixture.consentCoordinator.withdraw(
            using: fixture.acceptedConsent,
            decisionAt: Date(timeIntervalSince1970: 1_800_000_100)
        )

        #expect(
            await processor.retryLocalRecovery()
                == .localRecoveryPending(
                    failure: .localPersistence,
                    stage: .outputDelivery,
                    disposition: .savingResult,
                    requirement: .providerFree
                )
        )
        #expect(
            persistence.acceptedHistoryModes == [historyMode, historyMode]
        )
        #expect(calls.events == ["transcription", "usage"])
    }

    @Test func capturedHistoryModeRequiresDisclosureTwoBeforePendingDispatch()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        let historyMode = try await fixture.capturedHistoryMode()
        let persistence = CapturingHistoryModeForegroundPersistence(
            base: fixture.persistenceOwner
        )
        let calls = ProcessorCallLog()
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "must not dispatch"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "must not dispatch" }
            ),
            calls: calls
        )

        #expect(
            await processor.process(
                fixture.request(historyMode: historyMode)
            ) == .notStarted(.providerConsentUnavailable)
        )
        #expect(calls.events.isEmpty)
        #expect(persistence.acceptedHistoryModes.isEmpty)
        #expect(
            try await fixture.persistenceOwner.load()?.recording
                == fixture.pending
        )
        #expect(fixture.pending.phase == .readyForTranscription)
        #expect(await processor.hasLocalRecoveryPending() == false)
    }

    @Test func correctionFailureIsFailOpenAfterConsentConsumption()
        async throws {
        var settings = IOSAppSettings.defaults
        settings.textCorrectionConfiguration.isEnabled = true
        let fixture = try await ProcessorFixture(
            outputIntent: .standard,
            settings: settings
        )
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let rejectionCapture = ProcessorCredentialGenerationCapture()
        let progress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Original transcript"
                },
                correct: { _, _, _ in
                    calls.record("correction")
                    throw OpenAITextCorrectionServiceError.invalidAPIKey
                },
                translate: { _, _ in
                    calls.record("translation")
                    return "unexpected"
                }
            ),
            calls: calls,
            rejectionCapture: rejectionCapture
        )

        let record = try await processor.process(
            fixture.request(),
            progress: { progress.record($0) }
        ).requireReady()

        #expect(record.acceptedText == "Original transcript")
        #expect(
            calls.events
                == [
                    "transcription",
                    "usage",
                    "correction",
                    "credential-rejected",
                ]
        )
        #expect(rejectionCapture.values == [fixture.credential.generation])
        #expect(
            progress.stages
                == [.transcription, .postProcessing, .outputDelivery]
        )
    }

    @Test func translationWithdrawalRejectsLateTextAndDurablyRecovers()
        async throws {
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
        let rejectionCapture = ProcessorCredentialGenerationCapture()
        let translation = ControlledTextProvider(value: "Texte tardif")
        let processor = fixture.makeProcessor(
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Source text"
                },
                correct: { transcript, _, _ in
                    transcript.text
                },
                translate: { _, _ in
                    calls.record("translation")
                    return await translation.execute()
                }
            ),
            calls: calls,
            rejectionCapture: rejectionCapture
        )

        let processing = Task {
            await processor.process(fixture.request())
        }
        await translation.waitUntilStarted()
        _ = try await fixture.consentCoordinator.withdraw(
            using: fixture.acceptedConsent
        )
        await translation.release()
        let resolution = await processing.value

        guard case .awaitingRecovery(
            let recovered,
            failure: .providerConsentUnavailable,
            stage: .postProcessing
        ) = resolution else {
            Issue.record("Expected strict Translation recovery.")
            return
        }
        #expect(recovered.phase == .awaitingRecovery)
        #expect(recovered.transcriptionID == nil)
        #expect(calls.events == ["transcription", "usage", "translation"])
        #expect(rejectionCapture.values.isEmpty)
        #expect(try await fixture.persistenceOwner.load()?.recording == recovered)
        #expect(
            try await fixture.persistenceOwner.loadLatestResult()
                == .absent
        )
    }

    @Test func failedPostProcessingCommitRetriesLocallyWithoutProviderReplay()
        async throws {
        var settings = IOSAppSettings.defaults
        settings.textCorrectionConfiguration.isEnabled = true
        let fixture = try await ProcessorFixture(
            outputIntent: .standard,
            settings: settings
        )
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let persistence = FailingOnceForegroundPersistence(
            base: fixture.persistenceOwner,
            failure: .postProcessing
        )
        let initialProgress = ProcessorProgressCapture()
        let retryProgress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Retained provider text"
                },
                correct: { transcript, _, _ in
                    calls.record("correction")
                    return transcript.text
                },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )

        let first = await processor.process(
            fixture.request(),
            progress: { initialProgress.record($0) }
        )
        #expect(
            first == .localRecoveryPending(
                failure: .localPersistence,
                stage: .transcription,
                disposition: .processingCheckpoint,
                requirement: .providerFree
            )
        )
        #expect(await processor.hasLocalRecoveryPending())
        #expect(calls.events == ["transcription", "usage"])
        #expect(initialProgress.stages == [.transcription])

        _ = try await fixture.consentCoordinator.withdraw(
            using: fixture.acceptedConsent,
            decisionAt: Date(timeIntervalSince1970: 1_800_000_100)
        )

        let record = try await processor.retryLocalRecovery(
            progress: { retryProgress.record($0) }
        ).requireReady()
        #expect(record.acceptedText == "Retained provider text")
        #expect(calls.events == ["transcription", "usage"])
        #expect(persistence.postProcessingCallCount == 2)
        #expect(await processor.hasLocalRecoveryPending() == false)
        #expect(
            retryProgress.stages
                == [.transcription, .postProcessing, .outputDelivery]
        )
    }

    @Test func translationCredentialRejectionIsGenerationBoundAndStrict()
        async throws {
        var settings = IOSAppSettings.defaults
        settings.translationConfiguration = TranslationConfiguration(
            actionPreferenceEnabled: true,
            targetLanguage: .german
        )
        let fixture = try await ProcessorFixture(
            outputIntent: .translate,
            settings: settings
        )
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let rejectionCapture = ProcessorCredentialGenerationCapture()
        let progress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Translate me"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in
                    calls.record("translation")
                    throw OpenAITextTranslationServiceError.invalidAPIKey
                }
            ),
            calls: calls,
            rejectionCapture: rejectionCapture
        )

        guard case .awaitingRecovery(
            let recovered,
            failure: .credentialRejected,
            stage: .postProcessing
        ) = await processor.process(
            fixture.request(),
            progress: { progress.record($0) }
        ) else {
            Issue.record("Expected strict Translation credential recovery.")
            return
        }
        #expect(recovered.phase == .awaitingRecovery)
        #expect(rejectionCapture.values == [fixture.credential.generation])
        #expect(
            calls.events
                == [
                    "transcription",
                    "usage",
                    "translation",
                    "credential-rejected",
                ]
        )
        #expect(progress.stages == [.transcription, .postProcessing])
    }

    @Test func invalidTranslateConfigurationStopsBeforeProviderAndMutation()
        async throws {
        let fixture = try await ProcessorFixture(
            outputIntent: .translate,
            settings: .defaults
        )
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let rejectionCapture = ProcessorCredentialGenerationCapture()
        let progress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "unexpected"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls,
            rejectionCapture: rejectionCapture
        )

        #expect(
            await processor.process(
                fixture.request(),
                progress: { progress.record($0) }
            )
                == .notStarted(.invalidConfiguration)
        )
        #expect(calls.events.isEmpty)
        #expect(rejectionCapture.values.isEmpty)
        #expect(progress.stages.isEmpty)
        #expect(
            try await fixture.persistenceOwner.load()?.recording
                == fixture.pending
        )
    }

    @Test func explicitRetryUsesFreshSettingsPromptAndTranscriptionIdentity()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        let priorDispatch = try await fixture.persistenceOwner
            .beginTranscription(
                expected: IOSPendingRecordingCASExpectation(
                    recording: fixture.pending
                ),
                transcriptionID: UUID()
            )
        let recovery = try await fixture.persistenceOwner.markAwaitingRecovery(
            expected: priorDispatch.expectation
        )
        var retrySettings = fixture.settings
        retrySettings.transcriptionConfiguration =
            TranscriptionConfiguration(
                model: "fresh-retry-model",
                language: .russian,
                freeformPrompt: "fresh retry prompt"
            )
        let retryLibrary = IOSLibraryContent(
            customDictionary: CustomDictionary(entries: ["FreshName"])
        )
        let capture = ProcessorTranscriptionCapture()
        let usageCapture = ProcessorUsageCapture()
        let calls = ProcessorCallLog()
        let progress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { request, _ in
                    calls.record("transcription")
                    capture.record(request)
                    return "Fresh retry result"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls,
            usageCapture: usageCapture
        )

        let record = try await processor.process(
            fixture.request(
                pendingRecording: recovery,
                mode: .retry,
                settings: retrySettings,
                library: retryLibrary
            ),
            progress: { progress.record($0) }
        ).requireReady()

        #expect(record.attemptID == fixture.pending.attemptID)
        #expect(record.transcriptID != priorDispatch.recording.transcriptionID)
        #expect(capture.model == "fresh-retry-model")
        #expect(capture.languageCode == "ru")
        #expect(
            capture.prompt?.contains("fresh retry prompt") == true
        )
        #expect(capture.prompt?.contains("FreshName") == true)
        #expect(calls.events == ["transcription", "usage"])
        #expect(usageCapture.values.count == 1)
        #expect(usageCapture.values.first?.transcriptionID == record.transcriptID)
        #expect(usageCapture.values.first?.model == "fresh-retry-model")
        #expect(usageCapture.values.first?.audioDuration == 1)
        #expect(
            progress.stages
                == [.transcription, .postProcessing, .outputDelivery]
        )
    }

    @Test func explicitRetryCanStartFromReadyUsingCurrentSettings()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        var settings = fixture.settings
        settings.transcriptionConfiguration = TranscriptionConfiguration(
            model: "ready-retry-model",
            language: .german
        )
        let capture = ProcessorTranscriptionCapture()
        let calls = ProcessorCallLog()
        let processor = fixture.makeProcessor(
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { request, _ in
                    calls.record("transcription")
                    capture.record(request)
                    return "Ready retry"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )

        let record = try await processor.process(
            fixture.request(mode: .retry, settings: settings)
        ).requireReady()

        #expect(record.attemptID == fixture.pending.attemptID)
        #expect(capture.model == "ready-retry-model")
        #expect(capture.languageCode == "de")
        #expect(calls.events == ["transcription", "usage"])
    }

    @Test func readyRetryRejectsInvalidCurrentConfigurationWithoutMutation()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        var settings = fixture.settings
        settings.transcriptionConfiguration = TranscriptionConfiguration(
            language: .custom,
            customLanguageCode: "invalid-language"
        )
        let calls = ProcessorCallLog()
        let progress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "must not launch"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )

        #expect(
            await processor.process(
                fixture.request(mode: .retry, settings: settings),
                progress: { progress.record($0) }
            ) == .notStarted(.invalidConfiguration)
        )
        #expect(calls.events.isEmpty)
        #expect(progress.stages.isEmpty)
        #expect(
            try await fixture.persistenceOwner.load()?.recording
                == fixture.pending
        )
    }

    @Test func initialProcessingKeepsThePreparedCompactConfiguration()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        var settings = fixture.settings
        settings.transcriptionConfiguration = TranscriptionConfiguration(
            model: "changed-after-prepare",
            language: .japanese
        )
        let calls = ProcessorCallLog()
        let progress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "must not launch"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )

        #expect(
            await processor.process(
                fixture.request(settings: settings),
                progress: { progress.record($0) }
            ) == .notStarted(.invalidConfiguration)
        )
        #expect(calls.events.isEmpty)
        #expect(progress.stages.isEmpty)
        #expect(
            try await fixture.persistenceOwner.load()?.recording
                == fixture.pending
        )
    }

    @Test func consumedCredentialRejectionIsRecordedThenMadeRecoverable()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let rejectionCapture = ProcessorCredentialGenerationCapture()
        let processor = fixture.makeProcessor(
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    throw OpenAITranscriptionServiceError.invalidAPIKey
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls,
            rejectionCapture: rejectionCapture
        )

        let resolution = await processor.process(fixture.request())

        guard case .awaitingRecovery(
            let recovered,
            failure: .credentialRejected,
            stage: .transcription
        ) = resolution else {
            Issue.record("Expected credential-rejected recovery.")
            return
        }
        #expect(recovered.phase == .awaitingRecovery)
        #expect(
            calls.events
                == ["transcription", "credential-rejected"]
        )
        #expect(rejectionCapture.values == [fixture.credential.generation])
    }

    @Test func wholeSessionCancellationOverridesCorrectionFailOpen()
        async throws {
        var settings = IOSAppSettings.defaults
        settings.textCorrectionConfiguration.isEnabled = true
        let fixture = try await ProcessorFixture(
            outputIntent: .standard,
            settings: settings
        )
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let correction = ControlledTextProvider(value: "Late correction")
        let processor = fixture.makeProcessor(
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Original result"
                },
                correct: { _, _, _ in
                    calls.record("correction")
                    return await correction.execute()
                },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )
        let processing = Task {
            await processor.process(fixture.request())
        }
        await correction.waitUntilStarted()

        processing.cancel()
        await correction.release()
        let resolution = await processing.value

        guard case .awaitingRecovery(
            let recovered,
            failure: .cancelled,
            stage: .postProcessing
        ) = resolution else {
            Issue.record("Expected whole-session cancellation recovery.")
            return
        }
        #expect(recovered.phase == .awaitingRecovery)
        #expect(calls.events == ["transcription", "usage", "correction"])
        #expect(
            try await fixture.persistenceOwner.loadLatestResult()
                == .absent
        )
    }

    @Test func translatedTextIsNeverAcceptedByProviderFreeLocalRetry()
        async throws {
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
        let persistence = FailingOnceForegroundPersistence(
            base: fixture.persistenceOwner,
            failure: .postProcessing
        )
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Untranslated source"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in
                    calls.record("translation")
                    return "Texte traduit"
                }
            ),
            calls: calls
        )

        #expect(
            await processor.process(fixture.request())
                == .localRecoveryPending(
                    failure: .localPersistence,
                    stage: .transcription,
                    disposition: .processingCheckpoint,
                    requirement: .providerFree
                )
        )
        guard case .awaitingRecovery(
            let recovered,
            failure: .localPersistence,
            stage: .postProcessing
        ) = await processor.retryLocalRecovery() else {
            Issue.record("Expected provider-free Translation recovery.")
            return
        }
        #expect(recovered.phase == .awaitingRecovery)
        #expect(calls.events == ["transcription", "usage"])
        #expect(try await fixture.persistenceOwner.loadLatestResult() == .absent)
    }

    @Test func outputDeliveryFailureRetriesOnlyTheLocalCheckpoint()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let persistence = FailingOnceForegroundPersistence(
            base: fixture.persistenceOwner,
            failure: .outputDelivery
        )
        let initialProgress = ProcessorProgressCapture()
        let retryProgress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Local output retry"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )

        #expect(
            await processor.process(
                fixture.request(),
                progress: { initialProgress.record($0) }
            )
                == .localRecoveryPending(
                    failure: .localPersistence,
                    stage: .postProcessing,
                    disposition: .savingResult,
                    requirement: .providerFree
                )
        )
        _ = try await fixture.consentCoordinator.withdraw(
            using: fixture.acceptedConsent,
            decisionAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let record = try await processor.retryLocalRecovery(
            progress: { retryProgress.record($0) }
        ).requireReady()
        #expect(record.acceptedText == "Local output retry")
        #expect(calls.events == ["transcription", "usage"])
        #expect(persistence.outputDeliveryCallCount == 2)
        #expect(persistence.acceptanceCallCount == 1)
        #expect(initialProgress.stages == [.transcription, .postProcessing])
        #expect(retryProgress.stages == [.postProcessing, .outputDelivery])
    }

    @Test func cancellingFinalTextRetryKeepsSavingResultCheckpoint()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let persistence = FailingOnceForegroundPersistence(
            base: fixture.persistenceOwner,
            failure: .outputDelivery
        )
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Retained accepted output"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )

        #expect(
            await processor.process(fixture.request())
                == .localRecoveryPending(
                    failure: .localPersistence,
                    stage: .postProcessing,
                    disposition: .savingResult,
                    requirement: .providerFree
                )
        )
        #expect(calls.events == ["transcription", "usage"])
        #expect(persistence.outputDeliveryCallCount == 1)

        let cancelledProgress = ProcessorProgressCapture(
            cancellingAt: .postProcessing
        )
        let cancelledRetry = Task {
            await processor.retryLocalRecovery(
                progress: { cancelledProgress.record($0) }
            )
        }
        #expect(
            await cancelledRetry.value == .localRecoveryPending(
                failure: .cancelled,
                stage: .postProcessing,
                disposition: .savingResult,
                requirement: .providerFree
            )
        )
        #expect(cancelledProgress.stages == [.postProcessing])
        #expect(calls.events == ["transcription", "usage"])
        #expect(persistence.outputDeliveryCallCount == 1)

        let retryProgress = ProcessorProgressCapture()
        let record = try await processor.retryLocalRecovery(
            progress: { retryProgress.record($0) }
        ).requireReady()
        #expect(record.acceptedText == "Retained accepted output")
        #expect(retryProgress.stages == [.postProcessing, .outputDelivery])
        #expect(calls.events == ["transcription", "usage"])
        #expect(persistence.outputDeliveryCallCount == 2)
        #expect(persistence.acceptanceCallCount == 1)
    }

    @Test func acceptanceFailureRetriesOnlyTheLocalCheckpoint()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let persistence = FailingOnceForegroundPersistence(
            base: fixture.persistenceOwner,
            failure: .acceptance
        )
        let initialProgress = ProcessorProgressCapture()
        let retryProgress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Local acceptance retry"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )

        #expect(
            await processor.process(
                fixture.request(),
                progress: { initialProgress.record($0) }
            )
                == .localRecoveryPending(
                    failure: .localPersistence,
                    stage: .outputDelivery,
                    disposition: .savingResult,
                    requirement: .providerFree
                )
        )
        let record = try await processor.retryLocalRecovery(
            progress: { retryProgress.record($0) }
        ).requireReady()
        #expect(record.acceptedText == "Local acceptance retry")
        #expect(calls.events == ["transcription", "usage"])
        #expect(persistence.acceptanceCallCount == 2)
        #expect(
            initialProgress.stages
                == [.transcription, .postProcessing, .outputDelivery]
        )
        #expect(retryProgress.stages == [.outputDelivery])
    }

    @Test func recoveryFailureRetriesWithoutProviderReplay()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let persistence = FailingOnceForegroundPersistence(
            base: fixture.persistenceOwner,
            failure: .awaitingRecovery
        )
        let initialProgress = ProcessorProgressCapture()
        let retryProgress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    throw OpenAITranscriptionServiceError.networkFailure
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )

        #expect(
            await processor.process(
                fixture.request(),
                progress: { initialProgress.record($0) }
            )
                == .localRecoveryPending(
                    failure: .localPersistence,
                    stage: .transcription,
                    disposition: .processingCheckpoint,
                    requirement: .providerFree
                )
        )
        guard case .awaitingRecovery(
            let recovered,
            failure: .networkFailure,
            stage: .transcription
        ) = await processor.retryLocalRecovery(
            progress: { retryProgress.record($0) }
        ) else {
            Issue.record("Expected exact recovery retry.")
            return
        }
        #expect(recovered.phase == .awaitingRecovery)
        #expect(calls.events == ["transcription"])
        #expect(persistence.awaitingRecoveryCallCount == 2)
        #expect(initialProgress.stages == [.transcription])
        #expect(retryProgress.stages == [.transcription])
    }

    @Test func committedLocalTransitionsAreAdoptedAfterThrownResults()
        async throws {
        for failure in [
            FailingOnceForegroundPersistence.Failure
                .postProcessingAfterCommit,
            .outputDeliveryAfterCommit,
            .acceptanceAfterCommit,
        ] {
            var settings = IOSAppSettings.defaults
            settings.textCorrectionConfiguration.isEnabled = true
            let fixture = try await ProcessorFixture(
                outputIntent: .standard,
                settings: settings
            )
            defer { fixture.removeFiles() }
            let calls = ProcessorCallLog()
            let progress = ProcessorProgressCapture()
            let persistence = FailingOnceForegroundPersistence(
                base: fixture.persistenceOwner,
                failure: failure
            )
            let processor = fixture.makeProcessor(
                persistence: persistence,
                provider: IOSForegroundVoiceOpenAIProviderOperations(
                    transcribe: { _, _ in
                        calls.record("transcription")
                        return "Committed local result"
                    },
                    correct: { transcript, _, _ in
                        calls.record("correction")
                        return transcript.text
                    },
                    translate: { _, _ in "unexpected" }
                ),
                calls: calls
            )

            let record = try await processor.process(
                fixture.request(),
                progress: { progress.record($0) }
            ).requireReady()
            #expect(record.acceptedText == "Committed local result")
            if failure == .postProcessingAfterCommit {
                #expect(calls.events == ["transcription", "usage"])
            } else {
                #expect(
                    calls.events
                        == ["transcription", "usage", "correction"]
                )
            }
            #expect(await processor.hasLocalRecoveryPending() == false)
            #expect(
                progress.stages
                    == [.transcription, .postProcessing, .outputDelivery]
            )
        }
    }

    @Test func committedRecoveryIsAdoptedAfterThrownResult()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let persistence = FailingOnceForegroundPersistence(
            base: fixture.persistenceOwner,
            failure: .awaitingRecoveryAfterCommit
        )
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    throw OpenAITranscriptionServiceError.timedOut
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )

        guard case .awaitingRecovery(
            let recovered,
            failure: .timedOut,
            stage: .transcription
        ) = await processor.process(fixture.request()) else {
            Issue.record("Expected committed recovery adoption.")
            return
        }
        #expect(recovered.phase == .awaitingRecovery)
        #expect(persistence.awaitingRecoveryCallCount == 2)
        #expect(calls.events == ["transcription"])
    }

    @Test func lostCommittedBeginNeverLaunchesProviderAndBecomesRecovery()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let persistence = FailingOnceForegroundPersistence(
            base: fixture.persistenceOwner,
            failure: .beginAfterCommit
        )
        let progress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "must not launch"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )

        guard case .awaitingRecovery(
            let recovered,
            failure: .localPersistence,
            stage: .transcription
        ) = await processor.process(
            fixture.request(),
            progress: { progress.record($0) }
        ) else {
            Issue.record("Expected lost-handoff recovery.")
            return
        }
        #expect(recovered.phase == .awaitingRecovery)
        #expect(persistence.beginCallCount == 1)
        #expect(calls.events.isEmpty)
        #expect(progress.stages.isEmpty)
    }

    @Test func retainedBeginningRequiresFreshAuthorityAndUsesOnlyReplacementCredential()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let persistence = FailingOnceForegroundPersistence(
            base: fixture.persistenceOwner,
            failure: .beginBeforeCommit
        )
        let firstProgress = ProcessorProgressCapture()
        let retryProgress = ProcessorProgressCapture()
        let credentialCapture = ProcessorOpenAICredentialCapture()
        let replacementCredential = IOSResolvedOpenAICredential(
            credential: try OpenAICredential(apiKey: "sk-processor-replacement"),
            generation: IOSOpenAICredentialGeneration(rawValue: UUID())
        )
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, credential in
                    calls.record("transcription")
                    credentialCapture.record(credential)
                    return "Retained beginning"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )

        #expect(
            await processor.process(
                fixture.request(),
                progress: { firstProgress.record($0) }
            ) == .localRecoveryPending(
                failure: .localPersistence,
                stage: .transcription,
                disposition: .processingCheckpoint,
                requirement: .currentProviderAuthority
            )
        )
        #expect(firstProgress.stages.isEmpty)
        #expect(calls.events.isEmpty)
        #expect(persistence.beginCallCount == 1)

        #expect(
            await processor.retryLocalRecovery()
                == .localRecoveryPending(
                    failure: .providerConsentUnavailable,
                    stage: .transcription,
                    disposition: .processingCheckpoint,
                    requirement: .currentProviderAuthority
                )
        )
        #expect(calls.events.isEmpty)
        #expect(persistence.beginCallCount == 1)

        let record = try await processor.retryLocalRecovery(
            authorization: fixture.retryAuthorization(
                credential: replacementCredential
            ),
            progress: { retryProgress.record($0) }
        ).requireReady()
        #expect(record.acceptedText == "Retained beginning")
        #expect(
            retryProgress.stages
                == [.transcription, .postProcessing, .outputDelivery]
        )
        #expect(calls.events == ["transcription", "usage"])
        #expect(
            credentialCapture.values
                == [replacementCredential.credential]
        )
        #expect(persistence.beginCallCount == 2)
    }

    @Test func capturedRetainedBeginningRequiresDisclosureTwo()
        async throws {
        let versionOne = try await ProcessorFixture(outputIntent: .standard)
        defer { versionOne.removeFiles() }
        let versionOneMode = try await versionOne.capturedHistoryMode()
        let versionOneCalls = ProcessorCallLog()
        let versionOneProcessor = versionOne.makeProcessor(
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    versionOneCalls.record("transcription")
                    return "must not dispatch"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "must not dispatch" }
            ),
            calls: versionOneCalls,
            retainedWork: .beginning(
                versionOne.providerContext(
                    transcriptionID: UUID(),
                    deliveryID: UUID(),
                    historyMode: versionOneMode
                )
            )
        )

        #expect(
            await versionOneProcessor.retryLocalRecovery(
                authorization: versionOne.retryAuthorization()
            ) == .localRecoveryPending(
                failure: .providerConsentUnavailable,
                stage: .transcription,
                disposition: .processingCheckpoint,
                requirement: .currentProviderAuthority
            )
        )
        #expect(versionOneCalls.events.isEmpty)
        #expect(
            try await versionOne.persistenceOwner.load()?.recording
                == versionOne.pending
        )

        let versionTwo = try await ProcessorFixture(
            outputIntent: .standard,
            usesHistoryDisclosureV2: true
        )
        defer { versionTwo.removeFiles() }
        let versionTwoMode = try await versionTwo.capturedHistoryMode()
        let versionTwoCalls = ProcessorCallLog()
        let persistence = CapturingHistoryModeForegroundPersistence(
            base: versionTwo.persistenceOwner
        )
        let versionTwoProcessor = versionTwo.makeProcessor(
            persistence: persistence,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    versionTwoCalls.record("transcription")
                    return "captured retained beginning"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: versionTwoCalls,
            retainedWork: .beginning(
                versionTwo.providerContext(
                    transcriptionID: UUID(),
                    deliveryID: UUID(),
                    historyMode: versionTwoMode
                )
            )
        )

        #expect(
            await versionTwoProcessor.retryLocalRecovery(
                authorization: versionTwo.retryAuthorization()
            ) == .localRecoveryPending(
                failure: .localPersistence,
                stage: .outputDelivery,
                disposition: .savingResult,
                requirement: .providerFree
            )
        )
        #expect(versionTwoCalls.events == ["transcription", "usage"])
        #expect(persistence.acceptedHistoryModes == [versionTwoMode])
    }

    @Test func retainedBeginningRejectsConsentObservationFromBeforeReacceptance()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let staleRetryProgress = ProcessorProgressCapture()
        let persistence = FailingOnceForegroundPersistence(
            base: fixture.persistenceOwner,
            failure: .beginBeforeCommit
        )
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Fresh consent"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )

        guard case .localRecoveryPending(
            failure: _,
            stage: _,
            disposition: _,
            requirement: .currentProviderAuthority
        ) = await processor.process(fixture.request()) else {
            Issue.record("Expected provider-authorized retained beginning.")
            return
        }
        let withdrawn = try await fixture.consentCoordinator.withdraw(
            using: fixture.acceptedConsent,
            decisionAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let reaccepted = try await fixture.consentCoordinator.accept(
            using: withdrawn,
            decisionAt: Date(timeIntervalSince1970: 1_800_000_200)
        )

        #expect(
            await processor.retryLocalRecovery(
                authorization: fixture.retryAuthorization(
                    consentObservation: fixture.acceptedConsent
                ),
                progress: { staleRetryProgress.record($0) }
            ) == .localRecoveryPending(
                failure: .providerConsentUnavailable,
                stage: .transcription,
                disposition: .processingCheckpoint,
                requirement: .currentProviderAuthority
            )
        )
        #expect(calls.events.isEmpty)
        #expect(persistence.beginCallCount == 1)
        #expect(staleRetryProgress.stages.isEmpty)

        _ = try await processor.retryLocalRecovery(
            authorization: fixture.retryAuthorization(
                consentObservation: reaccepted
            )
        ).requireReady()
        #expect(calls.events == ["transcription", "usage"])
        #expect(persistence.beginCallCount == 2)
    }

    @Test func retainedPostProcessingRebindsFreshCredentialBeforeCorrection()
        async throws {
        var settings = IOSAppSettings.defaults
        settings.textCorrectionConfiguration.isEnabled = true
        let fixture = try await ProcessorFixture(
            outputIntent: .standard,
            settings: settings
        )
        defer { fixture.removeFiles() }
        let transcriptionID = UUID()
        let dispatch = try await fixture.persistenceOwner.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(
                recording: fixture.pending
            ),
            transcriptionID: transcriptionID
        )
        let oldContext = fixture.providerContext(
            transcriptionID: transcriptionID,
            deliveryID: UUID()
        )
        guard let oldAuthorization = fixture.consentCoordinator
            .makeAuthorization(from: fixture.acceptedConsent) else {
            Issue.record("Expected fixture provider authorization.")
            return
        }
        let admissionExecutor = IOSForegroundVoiceTranscriptionExecutor(
            authorization: oldAuthorization,
            stageExecutor: IOSProviderConsentStageExecutor(
                consentCoordinator: fixture.consentCoordinator
            ),
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in "Consumed before retained checkpoint" },
                correct: { transcript, _, _ in transcript.text },
                translate: { request, _ in request.acceptedTranscript.text }
            ),
            credential: fixture.credential.credential,
            promptComposition: oldContext.promptComposition
        )
        _ = try await dispatch.execute(using: admissionExecutor)
        let postProcessing = try await fixture.persistenceOwner
            .markPostProcessing(expected: dispatch.expectation)
        let replacementCredential = IOSResolvedOpenAICredential(
            credential: try OpenAICredential(apiKey: "sk-post-processing-fresh"),
            generation: IOSOpenAICredentialGeneration(rawValue: UUID())
        )
        let credentialCapture = ProcessorOpenAICredentialCapture()
        let calls = ProcessorCallLog()
        let processor = IOSForegroundVoiceProcessor(
            persistenceOwner: fixture.persistenceOwner,
            consentCoordinator: fixture.consentCoordinator,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "must not replay"
                },
                correct: { transcript, _, credential in
                    calls.record("correction")
                    credentialCapture.record(credential)
                    return "Corrected fresh authority"
                },
                translate: { _, _ in "unexpected" }
            ),
            retainedWork: .postProcessing(
                oldContext,
                postProcessing,
                try AcceptedTranscript(rawText: "Original retained text"),
                usageAttempted: true
            )
        )

        guard case .localRecoveryPending(
            failure: _,
            stage: _,
            disposition: _,
            requirement: .currentProviderAuthority
        ) = await processor.process(fixture.request()) else {
            Issue.record("Expected provider-authorized post-processing retry.")
            return
        }
        let record = try await processor.retryLocalRecovery(
            authorization: fixture.retryAuthorization(
                credential: replacementCredential
            )
        ).requireReady()

        #expect(record.acceptedText == "Corrected fresh authority")
        #expect(calls.events == ["correction"])
        #expect(
            credentialCapture.values
                == [replacementCredential.credential]
        )
    }

    @Test func cancelledDurableAdmissionEmitsNoProgressOrProviderCall()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let suspension = ProcessorAdmissionSuspension()
        let persistence = FailingOnceForegroundPersistence(
            base: fixture.persistenceOwner,
            failure: .suspendBeginAfterCommit,
            suspension: suspension
        )
        let progress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "must not launch"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )
        let processing = Task {
            await processor.process(
                fixture.request(),
                progress: { progress.record($0) }
            )
        }
        await suspension.waitUntilSuspended()

        processing.cancel()
        await suspension.release()

        guard case .awaitingRecovery(
            let recovered,
            failure: .cancelled,
            stage: .transcription
        ) = await processing.value else {
            Issue.record("Expected cancelled durable admission recovery.")
            return
        }
        #expect(recovered.phase == .awaitingRecovery)
        #expect(progress.stages.isEmpty)
        #expect(calls.events.isEmpty)
        #expect(try await fixture.persistenceOwner.load()?.recording == recovered)
    }

    @Test func activeProcessorReportsBusyWithoutClaimingLocalRecovery()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let transcription = ControlledTextProvider(value: "Single result")
        let activeProgress = ProcessorProgressCapture()
        let busyProcessProgress = ProcessorProgressCapture()
        let busyRetryProgress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return await transcription.execute()
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )
        let processing = Task {
            await processor.process(
                fixture.request(),
                progress: { activeProgress.record($0) }
            )
        }
        await transcription.waitUntilStarted()

        #expect(await processor.hasLocalRecoveryPending() == false)
        #expect(
            await processor.process(
                fixture.request(),
                progress: { busyProcessProgress.record($0) }
            ) == .busy
        )
        #expect(
            await processor.retryLocalRecovery(
                progress: { busyRetryProgress.record($0) }
            ) == .busy
        )
        await transcription.release()
        _ = try await processing.value.requireReady()
        #expect(calls.events == ["transcription", "usage"])
        #expect(
            activeProgress.stages
                == [.transcription, .postProcessing, .outputDelivery]
        )
        #expect(busyProcessProgress.stages.isEmpty)
        #expect(busyRetryProgress.stages.isEmpty)
    }

    @Test func processorDiagnosticsNeverExposeRuntimePayloads()
        async throws {
        var settings = IOSAppSettings.defaults
        settings.transcriptionConfiguration = TranscriptionConfiguration(
            freeformPrompt: "PROMPT-CANARY-4931"
        )
        let library = IOSLibraryContent(
            customDictionary: CustomDictionary(
                entries: ["DICTIONARY-CANARY-7824"]
            )
        )
        let fixture = try await ProcessorFixture(
            outputIntent: .standard,
            settings: settings,
            library: library
        )
        defer { fixture.removeFiles() }
        let progressCanary = "PROGRESS-CANARY-4382"
        let calls = ProcessorCallLog()
        let persistence = FailingOnceForegroundPersistence(
            base: fixture.persistenceOwner,
            failure: .outputDelivery
        )
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in "TRANSCRIPT-CANARY-1596" },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            calls: calls
        )
        let request = fixture.request()
        let resolution = await processor.process(
            request,
            progress: { _ in _ = progressCanary }
        )
        let diagnostics = [
            diagnosticDump(request),
            diagnosticDump(fixture.retryAuthorization()),
            diagnosticDump(resolution),
            diagnosticDump(
                IOSForegroundVoiceLocalRecoveryDisposition.savingResult
            ),
            diagnosticDump(
                IOSForegroundVoiceLocalRecoveryRequirement
                    .currentProviderAuthority
            ),
            diagnosticDump(processor),
            String(describing: processor),
            String(reflecting: processor),
        ].joined(separator: "\n")

        for canary in [
            "sk-processor-test",
            "PROMPT-CANARY-4931",
            "DICTIONARY-CANARY-7824",
            "TRANSCRIPT-CANARY-1596",
            progressCanary,
            fixture.root.path,
        ] {
            #expect(!diagnostics.contains(canary))
        }
    }

    @Test func cancellationAfterConsumedTranscriptionKeepsUsageAndRecovery()
        async throws {
        let fixture = try await ProcessorFixture(outputIntent: .standard)
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let usage = ControlledUsageRecorder()
        let identifiers = ProcessorUUIDSequence()
        let processor = IOSForegroundVoiceProcessor(
            persistenceOwner: fixture.persistenceOwner,
            consentCoordinator: fixture.consentCoordinator,
            provider: IOSForegroundVoiceOpenAIProviderOperations(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Consumed before cancellation"
                },
                correct: { transcript, _, _ in transcript.text },
                translate: { _, _ in "unexpected" }
            ),
            recordUsage: { value in
                await usage.record(value)
            },
            makeUUID: { identifiers.next() }
        )
        let processing = Task {
            await processor.process(fixture.request())
        }
        await usage.waitUntilStarted()

        processing.cancel()
        await usage.release()
        guard case .awaitingRecovery(
            let recovered,
            failure: .cancelled,
            stage: .transcription
        ) = await processing.value else {
            Issue.record("Expected post-consumption cancellation recovery.")
            return
        }
        let usages = await usage.recordedValues()
        #expect(recovered.phase == .awaitingRecovery)
        #expect(usages.count == 1)
        #expect(usages.first?.model == fixture.pending.transcriptionModel)
        #expect(usages.first?.audioDuration == 1)
        #expect(calls.events == ["transcription"])
        #expect(try await fixture.persistenceOwner.load()?.recording == recovered)
        #expect(try await fixture.persistenceOwner.loadLatestResult() == .absent)
    }

    @Test func progressCancellationIsObservedBeforeTheNextStage()
        async throws {
        for cancellationStage in [
            VoiceAttemptStage.transcription,
            .postProcessing,
            .outputDelivery,
        ] {
            let fixture = try await ProcessorFixture(outputIntent: .standard)
            defer { fixture.removeFiles() }
            let calls = ProcessorCallLog()
            let progress = ProcessorProgressCapture(
                cancellingAt: cancellationStage
            )
            let processor = fixture.makeProcessor(
                provider: IOSForegroundVoiceOpenAIProviderOperations(
                    transcribe: { _, _ in
                        calls.record("transcription")
                        return "Progress cancellation"
                    },
                    correct: { transcript, _, _ in transcript.text },
                    translate: { _, _ in "unexpected" }
                ),
                calls: calls
            )

            let processing = Task {
                await processor.process(
                    fixture.request(),
                    progress: { progress.record($0) }
                )
            }
            let resolution = await processing.value

            switch cancellationStage {
            case .transcription:
                guard case .awaitingRecovery(
                    _,
                    failure: .cancelled,
                    stage: .transcription
                ) = resolution else {
                    Issue.record("Expected Transcription cancellation.")
                    continue
                }
                #expect(progress.stages == [.transcription])
                #expect(calls.events.isEmpty)
            case .postProcessing:
                guard case .awaitingRecovery(
                    _,
                    failure: .cancelled,
                    stage: .postProcessing
                ) = resolution else {
                    Issue.record("Expected Post Processing cancellation.")
                    continue
                }
                #expect(progress.stages == [.transcription, .postProcessing])
                #expect(calls.events == ["transcription", "usage"])
            case .outputDelivery:
                #expect(
                    resolution == .localRecoveryPending(
                        failure: .cancelled,
                        stage: .outputDelivery,
                        disposition: .savingResult,
                        requirement: .providerFree
                    )
                )
                #expect(
                    progress.stages
                        == [.transcription, .postProcessing, .outputDelivery]
                )
                #expect(calls.events == ["transcription", "usage"])
                let retryProgress = ProcessorProgressCapture()
                _ = try await processor.retryLocalRecovery(
                    progress: { retryProgress.record($0) }
                ).requireReady()
                #expect(retryProgress.stages == [.outputDelivery])
                #expect(calls.events == ["transcription", "usage"])
            case .recordingFinalization:
                Issue.record("Recording Finalization is not processor progress.")
            }
        }
    }
}

private final class ProcessorFixture: @unchecked Sendable {
    let root: URL
    let sourceURL: URL
    let historyCoordinator: IOSAcceptedHistoryCoordinator
    let persistenceOwner: IOSForegroundVoicePersistenceOwner
    let consentCoordinator: IOSProviderConsentCoordinator
    let acceptedConsent: IOSProviderConsentObservation
    let pending: IOSPendingRecording
    let settings: IOSAppSettings
    let library: IOSLibraryContent
    let credential: IOSResolvedOpenAICredential

    init(
        outputIntent: DictationOutputIntent,
        settings: IOSAppSettings = .defaults,
        library: IOSLibraryContent = .defaults,
        usesHistoryDisclosureV2: Bool = false
    ) async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ios-foreground-processor-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        sourceURL = root.appendingPathComponent(
            "source-\(UUID().uuidString).wav",
            isDirectory: false
        )
        let audio = makeOneSecondProcessorWAV()
        try audio.write(to: sourceURL, options: .withoutOverwriting)

        self.settings = settings
        self.library = library
        historyCoordinator = IOSAcceptedHistoryCoordinator(
            applicationSupportDirectoryURL: root
        )
        guard await historyCoordinator.recoverContainingAppLifecycle(
            .processLaunch
        ) == .complete else {
            throw ProcessorFixtureError.injectedFailure
        }
        persistenceOwner = IOSForegroundVoicePersistenceOwner(
            applicationSupportDirectoryURL: root
        )
        do {
            pending = try await persistenceOwner.prepare(
                IOSPendingRecordingPreparation(
                    attemptID: UUID(),
                    sourceArtifact: AudioRecordingArtifact(
                        fileURL: sourceURL,
                        duration: 1,
                        byteCount: Int64(audio.count)
                    ),
                    initialState: .readyForTranscription,
                    outputIntent: outputIntent,
                    transcriptionConfiguration:
                        settings.transcriptionConfiguration
                )
            )
        } catch let error as IOSPendingRecordingError {
            Issue.record(
                "Fixture Pending prepare failed: \(processorErrorName(error))"
            )
            throw error
        }
        if usesHistoryDisclosureV2 {
            consentCoordinator = IOSProviderConsentProcessingQualificationFixture
                .foregroundHistoryCoordinator(
                    applicationSupportDirectoryURL: root
                )
        } else {
            consentCoordinator = IOSProviderConsentCoordinator(
                applicationSupportDirectoryURL: root
            )
        }
        let observation = await consentCoordinator.observe()
        acceptedConsent = try await consentCoordinator.accept(
            using: observation,
            decisionAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        credential = IOSResolvedOpenAICredential(
            credential: try OpenAICredential(apiKey: "sk-processor-test"),
            generation: IOSOpenAICredentialGeneration(rawValue: UUID())
        )
    }

    func request(
        pendingRecording: IOSPendingRecording? = nil,
        mode: IOSForegroundVoiceProcessingMode = .initial,
        settings: IOSAppSettings? = nil,
        library: IOSLibraryContent? = nil,
        historyMode: IOSForegroundVoiceHistoryMode? = nil
    ) -> IOSForegroundVoiceProcessingRequest {
        if let historyMode {
            return IOSForegroundVoiceProcessingRequest(
                sessionID: UUID(),
                pendingRecording: pendingRecording ?? pending,
                mode: mode,
                settings: settings ?? self.settings,
                library: library ?? self.library,
                credential: credential,
                consentObservation: acceptedConsent,
                historyMode: historyMode
            )
        }
        return IOSForegroundVoiceProcessingRequest(
            sessionID: UUID(),
            pendingRecording: pendingRecording ?? pending,
            mode: mode,
            settings: settings ?? self.settings,
            library: library ?? self.library,
            credential: credential,
            consentObservation: acceptedConsent
        )
    }

    func capturedHistoryMode() async throws
        -> IOSForegroundVoiceHistoryMode {
        _ = try await historyCoordinator.setHistoryEnabled(true)
        return .captured(
            try await historyCoordinator.capture(
                transcriptionModel: pending.transcriptionModel,
                transcriptionLanguageCode:
                    pending.transcriptionLanguageCode,
                durationMilliseconds: pending.durationMilliseconds
            )
        )
    }

    func retryAuthorization(
        credential: IOSResolvedOpenAICredential? = nil,
        consentObservation: IOSProviderConsentObservation? = nil
    ) -> IOSForegroundVoiceProviderRetryAuthorization {
        IOSForegroundVoiceProviderRetryAuthorization(
            credential: credential ?? self.credential,
            consentObservation: consentObservation ?? acceptedConsent
        )
    }

    func providerContext(
        transcriptionID: UUID,
        deliveryID: UUID,
        historyMode: IOSForegroundVoiceHistoryMode = .appOnly
    ) -> IOSForegroundVoiceProviderContext {
        let transcription = settings.transcriptionConfiguration
        return IOSForegroundVoiceProviderContext(
            sessionID: UUID(),
            pendingRecording: pending,
            mode: .initial,
            transcriptionConfiguration: transcription,
            correctionConfiguration:
                settings.textCorrectionConfiguration,
            translationConfiguration:
                pending.outputIntent == .translate
                    ? settings.translationConfiguration
                    : nil,
            postProcessingConfiguration:
                TranscriptPostProcessingConfiguration(
                    localTextCleanupEnabled:
                        settings.localTextCleanupEnabled,
                    emojiCommands:
                        library.emojiCommandsConfiguration,
                    textReplacementRules: library.replacementRules
                ),
            promptComposition: TranscriptionPromptComposition(
                resolvedFreeformPrompt:
                    transcription.resolvedFreeformPrompt,
                context: nil,
                emojiCommandsConfiguration:
                    library.emojiCommandsConfiguration,
                customDictionary: library.customDictionary
            ),
            keepLatestResult: settings.keepLatestResult,
            historyMode: historyMode,
            credential: credential,
            consentObservation: acceptedConsent,
            transcriptionID: transcriptionID,
            deliveryID: deliveryID
        )
    }

    func makeProcessor(
        persistence: (any IOSForegroundVoicePersisting)? = nil,
        provider: IOSForegroundVoiceOpenAIProviderOperations,
        calls: ProcessorCallLog,
        usageCapture: ProcessorUsageCapture? = nil,
        rejectionCapture: ProcessorCredentialGenerationCapture? = nil,
        retainedWork: IOSForegroundVoiceRetainedWork? = nil
    ) -> IOSForegroundVoiceProcessor {
        let identifiers = ProcessorUUIDSequence()
        return IOSForegroundVoiceProcessor(
            persistenceOwner: persistence ?? persistenceOwner,
            consentCoordinator: consentCoordinator,
            provider: provider,
            recordUsage: { usage in
                usageCapture?.record(usage)
                calls.record("usage")
            },
            recordProviderRejection: { generation in
                rejectionCapture?.record(generation)
                calls.record("credential-rejected")
            },
            makeUUID: { identifiers.next() },
            retainedWork: retainedWork
        )
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor ProcessorAdmissionSuspension {
    private var isSuspended = false
    private var suspendedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        isSuspended = true
        let waiters = suspendedWaiters
        suspendedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilSuspended() async {
        if isSuspended { return }
        await withCheckedContinuation { continuation in
            suspendedWaiters.append(continuation)
        }
    }

    func release() {
        let continuation = releaseContinuation
        releaseContinuation = nil
        continuation?.resume()
    }
}

private final class CapturingHistoryModeForegroundPersistence:
    IOSForegroundVoicePersisting,
    @unchecked Sendable {
    private let base: IOSForegroundVoicePersistenceOwner
    private let lock = NSLock()
    private var storedAcceptedHistoryModes: [IOSForegroundVoiceHistoryMode] = []

    init(base: IOSForegroundVoicePersistenceOwner) {
        self.base = base
    }

    var acceptedHistoryModes: [IOSForegroundVoiceHistoryMode] {
        lock.withLock { storedAcceptedHistoryModes }
    }

    func load() async throws -> IOSPendingRecordingObservation? {
        try await base.load()
    }

    func beginTranscription(
        expected: IOSPendingRecordingCASExpectation,
        transcriptionID: UUID
    ) async throws -> IOSForegroundVoiceTranscriptionDispatch {
        try await base.beginTranscription(
            expected: expected,
            transcriptionID: transcriptionID
        )
    }

    func retryTranscription(
        expected: IOSPendingRecordingCASExpectation,
        transcriptionID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSForegroundVoiceTranscriptionDispatch {
        try await base.retryTranscription(
            expected: expected,
            transcriptionID: transcriptionID,
            transcriptionConfiguration: transcriptionConfiguration
        )
    }

    func markPostProcessing(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await base.markPostProcessing(expected: expected)
    }

    func markOutputDelivery(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await base.markOutputDelivery(expected: expected)
    }

    func markAwaitingRecovery(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await base.markAwaitingRecovery(expected: expected)
    }

    func recoverAfterProcessLoss(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await base.recoverAfterProcessLoss(expected: expected)
    }

    func accept(
        _ preparation: IOSForegroundVoiceAcceptedOutputPreparation,
        expectedPending _: IOSPendingRecordingCASExpectation
    ) async throws -> IOSForegroundVoiceAcceptanceResult {
        lock.withLock {
            storedAcceptedHistoryModes.append(preparation.historyMode)
        }
        throw ProcessorFixtureError.injectedFailure
    }

    func reconcileAcceptance(
        matching _: IOSForegroundVoiceAcceptedOutputPreparation
    ) async throws -> IOSForegroundVoiceAcceptanceResult? {
        nil
    }
}

private final class FailingOnceForegroundPersistence:
    IOSForegroundVoicePersisting,
    @unchecked Sendable {
    enum Failure: Equatable {
        case beginBeforeCommit
        case beginAfterCommit
        case suspendBeginAfterCommit
        case postProcessing
        case postProcessingAfterCommit
        case outputDelivery
        case outputDeliveryAfterCommit
        case awaitingRecovery
        case awaitingRecoveryAfterCommit
        case acceptance
        case acceptanceAfterCommit
    }

    private let base: IOSForegroundVoicePersistenceOwner
    private let suspension: ProcessorAdmissionSuspension?
    private let lock = NSLock()
    private var remainingFailure: Failure?
    private var storedBeginCallCount = 0
    private var storedPostProcessingCallCount = 0
    private var storedOutputDeliveryCallCount = 0
    private var storedAwaitingRecoveryCallCount = 0
    private var storedAcceptanceCallCount = 0

    init(
        base: IOSForegroundVoicePersistenceOwner,
        failure: Failure,
        suspension: ProcessorAdmissionSuspension? = nil
    ) {
        self.base = base
        self.suspension = suspension
        remainingFailure = failure
    }

    var postProcessingCallCount: Int {
        lock.withLock { storedPostProcessingCallCount }
    }

    var beginCallCount: Int { lock.withLock { storedBeginCallCount } }
    var outputDeliveryCallCount: Int {
        lock.withLock { storedOutputDeliveryCallCount }
    }
    var awaitingRecoveryCallCount: Int {
        lock.withLock { storedAwaitingRecoveryCallCount }
    }
    var acceptanceCallCount: Int {
        lock.withLock { storedAcceptanceCallCount }
    }

    func load() async throws -> IOSPendingRecordingObservation? {
        try await base.load()
    }

    func beginTranscription(
        expected: IOSPendingRecordingCASExpectation,
        transcriptionID: UUID
    ) async throws -> IOSForegroundVoiceTranscriptionDispatch {
        lock.withLock { storedBeginCallCount += 1 }
        if takeFailure(.beginBeforeCommit) {
            throw ProcessorFixtureError.injectedFailure
        }
        let result = try await base.beginTranscription(
            expected: expected,
            transcriptionID: transcriptionID
        )
        if takeFailure(.beginAfterCommit) {
            throw ProcessorFixtureError.injectedFailure
        }
        if takeFailure(.suspendBeginAfterCommit) {
            await suspension?.suspend()
        }
        return result
    }

    func retryTranscription(
        expected: IOSPendingRecordingCASExpectation,
        transcriptionID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSForegroundVoiceTranscriptionDispatch {
        try await base.retryTranscription(
            expected: expected,
            transcriptionID: transcriptionID,
            transcriptionConfiguration: transcriptionConfiguration
        )
    }

    func markPostProcessing(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        lock.withLock { storedPostProcessingCallCount += 1 }
        if takeFailure(.postProcessing) {
            throw ProcessorFixtureError.injectedFailure
        }
        let result = try await base.markPostProcessing(expected: expected)
        if takeFailure(.postProcessingAfterCommit) {
            throw ProcessorFixtureError.injectedFailure
        }
        return result
    }

    private func takeFailure(_ candidate: Failure) -> Bool {
        lock.withLock {
            guard remainingFailure == candidate else { return false }
            remainingFailure = nil
            return true
        }
    }

    func markOutputDelivery(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        lock.withLock { storedOutputDeliveryCallCount += 1 }
        if takeFailure(.outputDelivery) {
            throw ProcessorFixtureError.injectedFailure
        }
        let result = try await base.markOutputDelivery(expected: expected)
        if takeFailure(.outputDeliveryAfterCommit) {
            throw ProcessorFixtureError.injectedFailure
        }
        return result
    }

    func markAwaitingRecovery(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        lock.withLock { storedAwaitingRecoveryCallCount += 1 }
        if takeFailure(.awaitingRecovery) {
            throw ProcessorFixtureError.injectedFailure
        }
        let result = try await base.markAwaitingRecovery(expected: expected)
        if takeFailure(.awaitingRecoveryAfterCommit) {
            throw ProcessorFixtureError.injectedFailure
        }
        return result
    }

    func recoverAfterProcessLoss(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await base.recoverAfterProcessLoss(expected: expected)
    }

    func accept(
        _ preparation: IOSForegroundVoiceAcceptedOutputPreparation,
        expectedPending: IOSPendingRecordingCASExpectation
    ) async throws -> IOSForegroundVoiceAcceptanceResult {
        lock.withLock { storedAcceptanceCallCount += 1 }
        if takeFailure(.acceptance) {
            throw ProcessorFixtureError.injectedFailure
        }
        let result = try await base.accept(
            preparation,
            expectedPending: expectedPending
        )
        if takeFailure(.acceptanceAfterCommit) {
            throw ProcessorFixtureError.injectedFailure
        }
        return result
    }

    func reconcileAcceptance(
        matching preparation: IOSForegroundVoiceAcceptedOutputPreparation
    ) async throws -> IOSForegroundVoiceAcceptanceResult? {
        try await base.reconcileAcceptance(matching: preparation)
    }
}

private final class ProcessorCallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [String] = []

    var events: [String] { lock.withLock { storedEvents } }

    func record(_ event: String) {
        lock.withLock { storedEvents.append(event) }
    }
}

@MainActor
private final class ProcessorProgressCapture {
    private(set) var stages: [VoiceAttemptStage] = []
    private let cancellingStage: VoiceAttemptStage?

    init(cancellingAt stage: VoiceAttemptStage? = nil) {
        cancellingStage = stage
    }

    func record(_ stage: VoiceAttemptStage) {
        stages.append(stage)
        if stage == cancellingStage {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
        }
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

private final class ProcessorCredentialGenerationCapture:
    @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [IOSOpenAICredentialGeneration] = []

    var values: [IOSOpenAICredentialGeneration] {
        lock.withLock { storedValues }
    }

    func record(_ value: IOSOpenAICredentialGeneration) {
        lock.withLock { storedValues.append(value) }
    }
}

private final class ProcessorOpenAICredentialCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [OpenAICredential] = []

    var values: [OpenAICredential] { lock.withLock { storedValues } }

    func record(_ value: OpenAICredential) {
        lock.withLock { storedValues.append(value) }
    }
}

private final class ProcessorTranscriptionCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedModel: String?
    private var storedLanguageCode: String?
    private var storedPrompt: String?

    var model: String? { lock.withLock { storedModel } }
    var languageCode: String? { lock.withLock { storedLanguageCode } }
    var prompt: String? { lock.withLock { storedPrompt } }

    func record(_ request: OpenAIReaderTranscriptionRequest) {
        lock.withLock {
            storedModel = request.model
            storedLanguageCode = request.languageCode
            storedPrompt = request.promptComposition.providerPrompt
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

private actor ControlledTextProvider {
    private let value: String
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<String, Never>?

    init(value: String) {
        self.value = value
    }

    func execute() async -> String {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            completion = continuation
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        let continuation = completion
        completion = nil
        continuation?.resume(returning: value)
    }
}

private actor ControlledUsageRecorder {
    private var values: [SuccessfulTranscriptionUsage] = []
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<Void, Never>?

    func record(_ value: SuccessfulTranscriptionUsage) async {
        values.append(value)
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            completion = continuation
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        let continuation = completion
        completion = nil
        continuation?.resume()
    }

    func recordedValues() -> [SuccessfulTranscriptionUsage] { values }
}

private enum ProcessorFixtureError: Error {
    case injectedFailure
}

private func diagnosticDump<Value>(_ value: Value) -> String {
    var output = ""
    dump(value, to: &output)
    return output
}

private func processorErrorName(_ error: IOSPendingRecordingError) -> String {
    switch error {
    case .cancelledBeforeOperation: "cancelledBeforeOperation"
    case .reentrantOperation: "reentrantOperation"
    case .repositoryIdentityConflict: "repositoryIdentityConflict"
    case .localRecoveryPending: "localRecoveryPending"
    case .pendingSlotOccupied: "pendingSlotOccupied"
    case .orphanedAudio: "orphanedAudio"
    case .journalUnreadable: "journalUnreadable"
    case .journalTooLarge: "journalTooLarge"
    case .journalMalformed: "journalMalformed"
    case .unsupportedJournalVersion: "unsupportedJournalVersion"
    case .invalidJournal: "invalidJournal"
    case .invalidSourceArtifact: "invalidSourceArtifact"
    case .invalidTranscriptionConfiguration:
        "invalidTranscriptionConfiguration"
    case .sourceUnavailable: "sourceUnavailable"
    case .sourceChanged: "sourceChanged"
    case .protectedAudioConflict: "protectedAudioConflict"
    case .audioPublicationFailed: "audioPublicationFailed"
    case .audioPublicationTimedOut: "audioPublicationTimedOut"
    case .mediaValidationFailed: "mediaValidationFailed"
    case .mediaValidationTimedOut: "mediaValidationTimedOut"
    case .dataProtectionUnavailable: "dataProtectionUnavailable"
    case .linkedAudioMissing: "linkedAudioMissing"
    case .linkedAudioInvalid: "linkedAudioInvalid"
    case .journalWriteFailed: "journalWriteFailed"
    case .journalCommitUncertain: "journalCommitUncertain"
    case .audioRemoveFailed: "audioRemoveFailed"
    case .journalRemoveFailed: "journalRemoveFailed"
    case .compareAndSwapFailed: "compareAndSwapFailed"
    case .invalidTransition: "invalidTransition"
    case .dispatchAlreadyCommitted: "dispatchAlreadyCommitted"
    case .destinationInspectionFailed: "destinationInspectionFailed"
    }
}

private extension IOSForegroundVoiceProcessingResolution {
    func requireReady() throws -> IOSAcceptedOutputDeliveryRecord {
        guard case .acceptance(.resultReady(let record, _)) = self else {
            throw ProcessorFixtureError.injectedFailure
        }
        return record
    }
}

private func makeOneSecondProcessorWAV() -> Data {
    let sampleRate: UInt32 = 8_000
    let channelCount: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let sampleCount = Int(sampleRate)
    let dataByteCount = UInt32(sampleCount * Int(bitsPerSample / 8))
    let byteRate = sampleRate * UInt32(channelCount)
        * UInt32(bitsPerSample / 8)
    let blockAlign = channelCount * (bitsPerSample / 8)

    var data = Data()
    data.append(contentsOf: "RIFF".utf8)
    data.appendProcessorLittleEndian(UInt32(36) + dataByteCount)
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    data.appendProcessorLittleEndian(UInt32(16))
    data.appendProcessorLittleEndian(UInt16(1))
    data.appendProcessorLittleEndian(channelCount)
    data.appendProcessorLittleEndian(sampleRate)
    data.appendProcessorLittleEndian(byteRate)
    data.appendProcessorLittleEndian(blockAlign)
    data.appendProcessorLittleEndian(bitsPerSample)
    data.append(contentsOf: "data".utf8)
    data.appendProcessorLittleEndian(dataByteCount)
    data.append(Data(repeating: 0, count: Int(dataByteCount)))
    return data
}

private extension Data {
    mutating func appendProcessorLittleEndian<Value: FixedWidthInteger>(
        _ value: Value
    ) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) {
            append(contentsOf: $0)
        }
    }
}
