//
//  DictationSessionControllerTests.swift
//  HoldTypeTests
//
//  Created by Codex on 6/22/26.
//

import Foundation
import HoldTypeDomain
import Testing
@testable import HoldType

@MainActor
struct DictationSessionControllerTests {

    @Test func recordingActionStartsThroughInjectedRecorderOnly() async {
        let recorder = FakeAudioRecorderService()
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let cuePlayer = FakeDictationCuePlayer()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            cuePlayer: cuePlayer
        )

        await controller.performRecordingAction()

        #expect(controller.status == .recording)
        #expect(controller.outputStatusText == nil)
        #expect(recorder.startCount == 1)
        #expect(recorder.stopCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(cuePlayer.playedCues == [.startRecording])
    }

    @Test func unavailableCredentialDoesNotStartRecordingOrReportInvalidAPIKey() async {
        let recorder = FakeAudioRecorderService()
        let transcriptionService = FakeControllerTranscriptionService()
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: failureRecovery,
            credentialResolverForUngatedActions: FakeControllerCredentialResolver(
                result: .failure(.apiKeyUnavailable(KeychainService.inaccessibleAPIKeyMessage))
            )
        )

        await controller.performRecordingAction()

        #expect(
            controller.status == .failure(
                message: "The OpenAI API key could not be read."
            )
        )
        #expect(controller.failurePresentation?.settingsTarget == .openAI)
        #expect(controller.failurePresentation?.failedAttemptID == nil)
        #expect(controller.failurePresentation?.canRetry == false)
        #expect(recorder.startCount == 0)
        #expect(recorder.stopCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(failureRecovery.failedAttempts.isEmpty)
    }

    @Test func unavailableCredentialDuringStopDoesNotUploadOrReportInvalidAPIKey() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(result: .failure(.invalidAPIKey))
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: failureRecovery,
            credentialResolverForUngatedActions: FakeControllerCredentialResolver(
                result: .failure(.apiKeyUnavailable(KeychainService.inaccessibleAPIKeyMessage))
            ),
            initialStatus: .recording,
            lastTranscriptText: "previous transcript"
        )

        await controller.performRecordingAction()

        #expect(
            controller.status == .failure(
                message: "The OpenAI API key could not be read."
            )
        )
        #expect(controller.lastTranscriptText == "previous transcript")
        #expect(controller.failurePresentation?.settingsTarget == .openAI)
        #expect(controller.failurePresentation?.failedAttemptID == nil)
        #expect(controller.failurePresentation?.canRetry == false)
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls.isEmpty)
        #expect(failureRecovery.failedAttempts.isEmpty)
    }

    @Test func recordingActionStopsTranscribesAndDeliversAcceptedTranscript() async {
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-controller-success.m4a"),
            duration: 1.3,
            byteCount: 2048
        )
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .success(artifact)
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("  Shared controller transcript \n")
        )
        let transcriptOutput = FakeTranscriptOutput(
            result: .success(.skipped(reason: .appClipboardDisabled))
        )
        let cuePlayer = FakeDictationCuePlayer()
        let eventLogger = FakeDictationEventLogger()
        let settings = makeSettings(saveTranscriptsToAppClipboard: false)
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            cuePlayer: cuePlayer,
            eventLogger: eventLogger,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(controller.status == .success(transcript: "Shared controller transcript"))
        #expect(controller.lastTranscriptText == "Shared controller transcript")
        #expect(controller.status.lastTranscriptText == "Shared controller transcript")
        #expect(controller.outputStatusText == "Paste Last Result is disabled.")
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls == [TranscriptionCall(audioFileURL: artifact.fileURL, settings: settings)])
        #expect(transcriptOutput.calls == [TranscriptOutputCall(transcript: "Shared controller transcript", settings: settings)])
        #expect(cuePlayer.playedCues == [.stopRecording])
        #expect(
            eventLogger.events == [
                .recordingStopRequested,
                .recordingStopped(duration: 1.3, byteCount: 2048),
                .transcriptionStarted,
                .transcriptionSucceeded,
                .recordingCacheHandled(policy: .deleteImmediately),
            ]
        )
    }

    @Test func configuredRecordingStopTailRunsBeforeRecorderStop() async {
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-controller-tail.m4a"),
            duration: 1.3,
            byteCount: 2048
        )
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .success(artifact)
        )
        let stopTailSleeper = FakeRecordingStopTailSleeper()
        let eventLogger = FakeDictationEventLogger()
        var settings = AppSettings.defaults
        settings.recordingStopTailDuration = .seconds1_5
        let controller = makeController(
            recorder: recorder,
            transcriptionService: FakeControllerTranscriptionService(result: .success("Tail transcript")),
            settings: settings,
            transcriptOutput: FakeTranscriptOutput(),
            recordingStopTailSleeper: stopTailSleeper,
            eventLogger: eventLogger,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(stopTailSleeper.sleepCalls == [1.5])
        #expect(recorder.stopCount == 1)
        #expect(
            Array(eventLogger.events.prefix(4)) == [
                .recordingStopRequested,
                .recordingStopTailStarted(duration: 1.5),
                .recordingStopTailFinished(duration: 1.5),
                .recordingStopped(duration: 1.3, byteCount: 2048),
            ]
        )
    }

    @Test func offRecordingStopTailStopsRecorderImmediately() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let stopTailSleeper = FakeRecordingStopTailSleeper()
        var settings = AppSettings.defaults
        settings.recordingStopTailDuration = .off
        let controller = makeController(
            recorder: recorder,
            transcriptionService: FakeControllerTranscriptionService(result: .success("No tail transcript")),
            settings: settings,
            transcriptOutput: FakeTranscriptOutput(),
            recordingStopTailSleeper: stopTailSleeper,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(stopTailSleeper.sleepCalls.isEmpty)
        #expect(recorder.stopCount == 1)
    }

    @Test func cancelDuringRecordingStopTailSkipsStopTranscriptionAndOutput() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let stopTailSleeper = FakeRecordingStopTailSleeper(mode: .sleepUntilCancelled)
        let transcriptionService = FakeControllerTranscriptionService(result: .success("Unexpected transcript"))
        let transcriptOutput = FakeTranscriptOutput()
        var settings = AppSettings.defaults
        settings.recordingStopTailDuration = .seconds2
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            recordingStopTailSleeper: stopTailSleeper,
            initialStatus: .recording,
            lastTranscriptText: "previous transcript"
        )

        let stopTask = Task { @MainActor in
            await controller.performRecordingAction()
        }
        await yieldUntil {
            stopTailSleeper.sleepCalls == [2]
        }

        controller.cancelRecording()
        await stopTask.value

        #expect(controller.status == .idle)
        #expect(controller.lastTranscriptText == "previous transcript")
        #expect(recorder.cancelCount == 1)
        #expect(recorder.stopCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func recordingActionPassesActiveTextContextToTranscription() async throws {
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-controller-context.m4a"),
            duration: 1.3,
            byteCount: 2048
        )
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .success(artifact)
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("  continued transcript \n")
        )
        var settings = AppSettings.defaults
        settings.useActiveTextContext = true
        let context = try #require(TranscriptionPromptContext("Existing text near the cursor."))
        let contextReader = FakeActiveTextContextReader(context: context)
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: FakeTranscriptOutput(),
            activeTextContextReader: contextReader,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(contextReader.settingsCalls == [settings])
        #expect(
            transcriptionService.calls == [
                TranscriptionCall(
                    audioFileURL: artifact.fileURL,
                    settings: settings,
                    context: context
                )
            ]
        )
    }

    @Test func successfulTranscriptionRecordsOpenAIUsageEstimate() async throws {
        let transcriptionID = try #require(
            UUID(uuidString: "88753EA8-4A6A-4D90-9DB6-846D554DB730")
        )
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-controller-usage.m4a"),
            duration: 42,
            byteCount: 2048
        )
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .success(artifact)
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Usage transcript")
        )
        var settings = AppSettings.defaults
        settings.transcriptionModel = "gpt-4o-mini-transcribe"
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionUsageRecorder: usageRecorder,
            transcriptionIDGenerator: { transcriptionID },
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(
            usageRecorder.calls == [
                try SuccessfulTranscriptionUsage(
                    transcriptionID: transcriptionID,
                    model: "gpt-4o-mini-transcribe",
                    audioDuration: 42
                )
            ]
        )
    }

    @Test func successfulTranscriptionAppliesRecordingCachePolicy() async {
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-controller-cache-success.m4a"),
            duration: 2,
            byteCount: 1024
        )
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .success(artifact)
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Cached transcript")
        )
        var settings = AppSettings.defaults
        settings.recordingCachePolicy = .keepLast(10)
        let recordingCache = FakeRecordingCache()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: FakeTranscriptOutput(),
            recordingCache: recordingCache,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(
            recordingCache.completedRecordingCalls == [
                RecordingCachePolicyCall(artifact: artifact, policy: .keepLast(10))
            ]
        )
    }

    @Test func successfulTranscriptionLinksAcceptedHistoryToCachedRecordingWhenCacheIsEnabled() async {
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-controller-history-cache.m4a"),
            duration: 2,
            byteCount: 1024
        )
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .success(artifact)
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("History cache transcript")
        )
        var settings = AppSettings.defaults
        settings.recordingCachePolicy = .keepLast(10)
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptHistory: transcriptHistory,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(transcriptHistory.calls.first?.cachedAudioFileURL == artifact.fileURL)
        #expect(transcriptHistory.entries.first?.cachedAudioFileURL == artifact.fileURL)
    }

    @Test func transcriptionFailureStillAppliesRecordingCachePolicy() async {
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-controller-cache-failure.m4a"),
            duration: 2,
            byteCount: 1024
        )
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .success(artifact)
        )
        let transcriptionService = FakeControllerTranscriptionService(result: .failure(.networkUnavailable))
        var lifecycleEvents: [String] = []
        let failureRecovery = FakeTranscriptionFailureRecovery(
            onRecordFailedAttempt: { lifecycleEvents.append("recovery") }
        )
        let recordingCache = FakeRecordingCache(
            onHandleCompletedRecording: { lifecycleEvents.append("cache") }
        )
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: failureRecovery,
            recordingCache: recordingCache,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(controller.status == .failure(message: "The network is unavailable. Try again when you are connected."))
        #expect(
            recordingCache.completedRecordingCalls == [
                RecordingCachePolicyCall(artifact: artifact, policy: .deleteImmediately)
            ]
        )
        #expect(lifecycleEvents == ["recovery", "cache"])
    }

    @Test func failedRecoveryHandoffPreservesTheOnlyCompletedArtifact() async {
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-controller-recovery-save-failure.m4a"),
            duration: 2,
            byteCount: 1024
        )
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .success(artifact)
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .failure(.networkUnavailable)
        )
        let failureRecovery = FakeTranscriptionFailureRecovery(
            recordFailedAttemptError: TranscriptionFailureRecoveryError.saveFailed
        )
        let recordingCache = FakeRecordingCache()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: failureRecovery,
            recordingCache: recordingCache,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(
            controller.status == .failure(
                message: "The network is unavailable. Try again when you are connected."
            )
        )
        #expect(controller.outputStatusText == "The failed recording could not be saved for retry.")
        #expect(controller.failurePresentation?.failedAttemptID == nil)
        #expect(recordingCache.completedRecordingCalls.isEmpty)
    }

    @Test func textCorrectionRunsBeforeOutputAndHistory() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("  raw transcript \n")
        )
        let textCorrectionService = FakeTextCorrectionService(result: .success("corrected transcript"))
        let transcriptOutput = FakeTranscriptOutput()
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            textCorrectionService: textCorrectionService,
            transcriptOutput: transcriptOutput,
            transcriptHistory: transcriptHistory,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(controller.status == .success(transcript: "corrected transcript"))
        #expect(controller.lastTranscriptText == "corrected transcript")
        #expect(textCorrectionService.calls == [TextCorrectionCall(transcript: "raw transcript", settings: .defaults)])
        #expect(transcriptOutput.calls == [TranscriptOutputCall(transcript: "corrected transcript", settings: .defaults)])
        #expect(transcriptHistory.entries.map(\.transcriptText) == ["corrected transcript"])
    }

    @Test func textCorrectionFailureFallsBackToTranscriptionText() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("  raw transcript \n")
        )
        let textCorrectionService = FakeTextCorrectionService(result: .failure(.timedOut))
        let transcriptOutput = FakeTranscriptOutput()
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            textCorrectionService: textCorrectionService,
            transcriptOutput: transcriptOutput,
            transcriptionUsageRecorder: usageRecorder,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(controller.status == .success(transcript: "raw transcript"))
        #expect(controller.lastTranscriptText == "raw transcript")
        #expect(transcriptOutput.calls == [TranscriptOutputCall(transcript: "raw transcript", settings: .defaults)])
        #expect(usageRecorder.calls.map(\.model) == ["gpt-4o-transcribe"])
        #expect(usageRecorder.calls.map(\.audioDuration) == [1.2])
    }

    @Test func historyFailureDoesNotRemoveOrDuplicateSuccessfulTranscriptionUsage() async {
        let transcriptHistory = FakeTranscriptRecoveryHistory(
            recordError: TranscriptHistoryStoreError.saveFailed
        )
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .recording),
            transcriptionService: FakeControllerTranscriptionService(result: .success(" accepted text ")),
            transcriptOutput: transcriptOutput,
            transcriptHistory: transcriptHistory,
            transcriptionUsageRecorder: usageRecorder,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(controller.status == .success(transcript: "accepted text"))
        #expect(transcriptHistory.calls.count == 1)
        #expect(transcriptHistory.entries.isEmpty)
        #expect(transcriptOutput.calls.map(\.transcript) == ["accepted text"])
        #expect(usageRecorder.calls.count == 1)
        #expect(usageRecorder.calls.map(\.model) == ["gpt-4o-transcribe"])
        #expect(usageRecorder.calls.map(\.audioDuration) == [1.2])
    }

    @Test func translationIntentRunsAfterTextCorrectionBeforeOutputAndHistory() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("  texto español sin corregir \n")
        )
        let textCorrectionService = FakeTextCorrectionService(result: .success("texto español corregido"))
        let translationService = FakeTranslationService(result: .success("Corrected English text"))
        let transcriptOutput = FakeTranscriptOutput()
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        var settings = AppSettings.defaults
        settings.language = .spanish
        settings.translationShortcutEnabled = true
        settings.translationTargetLanguage = .english
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            textCorrectionService: textCorrectionService,
            translationService: translationService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            transcriptHistory: transcriptHistory,
            initialStatus: .recording
        )

        await controller.performRecordingAction(intent: .translate)

        #expect(controller.status == .success(transcript: "Corrected English text"))
        #expect(controller.lastTranscriptText == "Corrected English text")
        #expect(transcriptionService.calls.map(\.settings.language) == [.spanish])
        #expect(
            textCorrectionService.calls == [
                TextCorrectionCall(transcript: "texto español sin corregir", settings: settings)
            ]
        )
        #expect(
            translationService.calls == [
                TranslationCall(transcript: "texto español corregido", settings: settings)
            ]
        )
        #expect(transcriptOutput.calls == [TranscriptOutputCall(transcript: "Corrected English text", settings: settings)])
        #expect(transcriptHistory.entries.map(\.transcriptText) == ["Corrected English text"])
    }

    @Test func translationIntentCleansFinalTypographyWithoutReplacementRules() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("  texto español sin corregir \n")
        )
        let textCorrectionService = FakeTextCorrectionService(result: .success("texto español corregido"))
        let translationService = FakeTranslationService(result: .success("“Corrected”—English… emoji smile"))
        let transcriptOutput = FakeTranscriptOutput()
        var settings = AppSettings.defaults
        settings.language = .spanish
        settings.translationShortcutEnabled = true
        settings.translationTargetLanguage = .english
        settings.localTextCleanupEnabled = true
        settings.enabledEmojiCommandSetIDs = ["en"]
        settings.textReplacementRules = [
            TextReplacementRule(search: "Corrected", replacement: "Rewritten")
        ]
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            textCorrectionService: textCorrectionService,
            translationService: translationService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording
        )

        await controller.performRecordingAction(intent: .translate)

        #expect(controller.status == .success(transcript: "\"Corrected\" - English... emoji smile"))
        #expect(
            translationService.calls == [
                TranslationCall(transcript: "texto español corregido", settings: settings)
            ]
        )
        #expect(
            transcriptOutput.calls == [
                TranscriptOutputCall(
                    transcript: "\"Corrected\" - English... emoji smile",
                    settings: settings
                )
            ]
        )
    }

    @Test func translationSourceOverrideChangesTranscriptionLanguage() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("  texto español \n")
        )
        let translationService = FakeTranslationService(result: .success("English text"))
        let transcriptOutput = FakeTranscriptOutput()
        var settings = AppSettings.defaults
        settings.language = .automatic
        settings.translationShortcutEnabled = true
        settings.translationSourceMode = .override
        settings.translationSourceLanguage = .spanish
        settings.translationTargetLanguage = .english
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            translationService: translationService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording
        )

        await controller.performRecordingAction(intent: .translate)

        #expect(controller.status == .success(transcript: "English text"))
        #expect(transcriptionService.calls.map(\.settings.language) == [.spanish])
        #expect(translationService.calls == [TranslationCall(transcript: "texto español", settings: settings)])
        #expect(transcriptOutput.calls == [TranscriptOutputCall(transcript: "English text", settings: settings)])
    }

    @Test func stopIntentCanPromoteActiveSessionToTranslation() async {
        let recorder = FakeAudioRecorderService()
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("  русский текст \n")
        )
        let translationService = FakeTranslationService(result: .success("English text"))
        let transcriptOutput = FakeTranscriptOutput()
        var settings = AppSettings.defaults
        settings.language = .russian
        settings.translationShortcutEnabled = true
        settings.translationTargetLanguage = .english
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            translationService: translationService,
            settings: settings,
            transcriptOutput: transcriptOutput
        )

        await controller.performRecordingAction(intent: .standard)
        await controller.performRecordingAction(intent: .translate)

        #expect(recorder.startCount == 1)
        #expect(recorder.stopCount == 1)
        #expect(controller.status == .success(transcript: "English text"))
        #expect(translationService.calls == [TranslationCall(transcript: "русский текст", settings: settings)])
        #expect(transcriptOutput.calls == [TranscriptOutputCall(transcript: "English text", settings: settings)])
    }

    @Test func translationIntentFailsBeforeTranscriptionWhenTargetLanguageIsMissing() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("  normal transcript \n")
        )
        let translationService = FakeTranslationService(result: .success("Unexpected translation"))
        let transcriptOutput = FakeTranscriptOutput()
        let usageRecorder = FakeTranscriptionUsageRecorder()
        var settings = AppSettings.defaults
        settings.language = .automatic
        settings.translationShortcutEnabled = true
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            translationService: translationService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            transcriptionUsageRecorder: usageRecorder,
            initialStatus: .recording
        )

        await controller.performRecordingAction(intent: .translate)

        #expect(recorder.stopCount == 1)
        #expect(controller.status == .failure(message: "Choose a target language in Translation settings."))
        #expect(controller.failurePresentation?.title == "Translation settings need attention")
        #expect(controller.failurePresentation?.settingsTarget == .translation)
        #expect(controller.lastTranscriptText == nil)
        #expect(transcriptionService.calls.isEmpty)
        #expect(translationService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(usageRecorder.calls.isEmpty)
    }

    @Test func translationIntentFallsBackToNormalOutputWhenShortcutSettingIsDisabled() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("  русский текст \n")
        )
        let translationService = FakeTranslationService(result: .success("Unexpected translation"))
        let transcriptOutput = FakeTranscriptOutput()
        var settings = AppSettings.defaults
        settings.language = .spanish
        settings.translationShortcutEnabled = false
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            translationService: translationService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording
        )

        await controller.performRecordingAction(intent: .translate)

        #expect(controller.status == .success(transcript: "русский текст"))
        #expect(translationService.calls.isEmpty)
        #expect(transcriptOutput.calls == [TranscriptOutputCall(transcript: "русский текст", settings: settings)])
    }

    @Test func translationFailurePreservesSuccessfulTranscriptionUsageWithoutDeliveringOutput() async throws {
        let transcriptionID = try #require(
            UUID(uuidString: "D148D919-F2F7-4D9E-A4B8-D5B11A8CDB25")
        )
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("  русский текст \n")
        )
        let translationService = FakeTranslationService(result: .failure(.timedOut))
        let transcriptOutput = FakeTranscriptOutput()
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        let usageRecorder = FakeTranscriptionUsageRecorder()
        var settings = AppSettings.defaults
        settings.language = .russian
        settings.translationShortcutEnabled = true
        settings.translationTargetLanguage = .english
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            translationService: translationService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            transcriptHistory: transcriptHistory,
            transcriptionUsageRecorder: usageRecorder,
            transcriptionIDGenerator: { transcriptionID },
            initialStatus: .recording,
            lastTranscriptText: "previous transcript",
            outputStatusText: "Previous output status"
        )

        await controller.performRecordingAction(intent: .translate)

        #expect(controller.status == .failure(message: "Translation timed out."))
        #expect(controller.lastTranscriptText == "previous transcript")
        #expect(controller.outputStatusText == nil)
        #expect(
            translationService.calls == [
                TranslationCall(transcript: "русский текст", settings: settings)
            ]
        )
        #expect(transcriptOutput.calls.isEmpty)
        #expect(transcriptHistory.entries.isEmpty)
        #expect(
            usageRecorder.calls == [
                try SuccessfulTranscriptionUsage(
                    transcriptionID: transcriptionID,
                    model: "gpt-4o-transcribe",
                    audioDuration: 1.2
                )
            ]
        )
    }

    @Test func transcribingStateIgnoresRecordingAction() async {
        let recorder = FakeAudioRecorderService()
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .transcribing
        )

        await controller.performRecordingAction()

        #expect(controller.status == .transcribing)
        #expect(recorder.startCount == 0)
        #expect(recorder.stopCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func cancelRecordingReturnsToIdleAndSkipsTranscription() {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording,
            lastTranscriptText: "previous transcript",
            outputStatusText: "Previous output status"
        )

        controller.cancelRecording()

        #expect(controller.status == .idle)
        #expect(controller.lastTranscriptText == "previous transcript")
        #expect(controller.outputStatusText == nil)
        #expect(recorder.cancelCount == 1)
        #expect(recorder.stopCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func cancelRecordingSurfacesRecorderCleanupFailure() {
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            cancelStatus: .failed(message: "Could not remove the canceled recording.")
        )
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording
        )

        controller.cancelRecording()

        #expect(controller.status == .failure(message: "Could not remove the canceled recording."))
        #expect(recorder.cancelCount == 1)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func cancelRecordingIsIgnoredOutsideActiveRecording() {
        let recorder = FakeAudioRecorderService()
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .success(transcript: "previous")
        )

        controller.cancelRecording()

        #expect(controller.status == .success(transcript: "previous"))
        #expect(recorder.cancelCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func cancelDuringTranscriptionDiscardsLateTranscript() async {
        let gate = ControllerAsyncGate()
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success(" late transcript "),
            beforeResult: {
                await gate.wait()
            }
        )
        let transcriptOutput = FakeTranscriptOutput()
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptionUsageRecorder: usageRecorder,
            initialStatus: .recording,
            lastTranscriptText: "previous accepted transcript",
            outputStatusText: "Previous output status"
        )

        let stopTask = Task { @MainActor in
            await controller.performRecordingAction()
        }
        await yieldUntil {
            controller.status == .transcribing && transcriptionService.calls.count == 1
        }

        controller.cancelRecording()

        #expect(controller.status == .idle)
        #expect(controller.lastTranscriptText == "previous accepted transcript")
        #expect(controller.outputStatusText == nil)
        #expect(transcriptionService.cancelCount == 1)

        await gate.open()
        await stopTask.value

        #expect(controller.status == .idle)
        #expect(controller.lastTranscriptText == "previous accepted transcript")
        #expect(controller.outputStatusText == nil)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(usageRecorder.calls.isEmpty)
    }

    @Test func cancelDuringCorrectionKeepsAlreadyAcceptedTranscriptionUsage() async {
        let gate = ControllerAsyncGate()
        let textCorrectionService = FakeTextCorrectionService(
            result: .success("late correction"),
            beforeResult: {
                await gate.wait()
            }
        )
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let transcriptOutput = FakeTranscriptOutput()
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .recording),
            transcriptionService: FakeControllerTranscriptionService(result: .success(" accepted transcript ")),
            textCorrectionService: textCorrectionService,
            transcriptOutput: transcriptOutput,
            transcriptHistory: transcriptHistory,
            transcriptionUsageRecorder: usageRecorder,
            initialStatus: .recording
        )

        let stopTask = Task { @MainActor in
            await controller.performRecordingAction()
        }
        await yieldUntil {
            usageRecorder.calls.count == 1 && textCorrectionService.calls.count == 1
        }

        controller.cancelRecording()

        #expect(controller.status == .idle)
        #expect(usageRecorder.calls.count == 1)
        #expect(textCorrectionService.cancelCount == 1)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(transcriptHistory.entries.isEmpty)

        await gate.open()
        await stopTask.value

        #expect(controller.status == .idle)
        #expect(usageRecorder.calls.count == 1)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(transcriptHistory.entries.isEmpty)
    }

    @Test func startFailureBecomesUserVisibleFailureWithoutExternalWork() async {
        let recorder = FakeAudioRecorderService(startResult: .failure(.recordingUnavailable))
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let cuePlayer = FakeDictationCuePlayer()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            cuePlayer: cuePlayer
        )

        await controller.performRecordingAction()

        #expect(controller.status == .failure(message: "Recording is unavailable on this Mac."))
        #expect(recorder.startCount == 1)
        #expect(recorder.stopCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(cuePlayer.playedCues.isEmpty)
    }

    @Test func disabledSoundSettingSuppressesRecordingCues() async {
        let recorder = FakeAudioRecorderService()
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let cuePlayer = FakeDictationCuePlayer()
        var settings = AppSettings.defaults
        settings.soundEnabled = false
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            cuePlayer: cuePlayer
        )

        await controller.performRecordingAction()

        #expect(controller.status == .recording)
        #expect(cuePlayer.playedCues.isEmpty)
    }

    @Test func recordingTimeoutBecomesUserVisibleFailureWithoutTranscription() async {
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .failure(.recordingTimedOut(duration: 300, maximumDuration: 300))
        )
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording,
            lastTranscriptText: "previous transcript"
        )

        await controller.performRecordingAction()

        #expect(
            controller.status == .failure(
                message: "Recording reached the maximum length. Try again with a shorter dictation."
            )
        )
        #expect(controller.lastTranscriptText == "previous transcript")
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func stopFailureBecomesUserVisibleFailureWithoutTranscription() async {
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .failure(.stopFailed)
        )
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording,
            lastTranscriptText: "previous transcript",
            outputStatusText: "Previous output status"
        )

        await controller.performRecordingAction()

        #expect(controller.status == .failure(message: "Could not finish the current recording."))
        #expect(controller.lastTranscriptText == "previous transcript")
        #expect(controller.outputStatusText == nil)
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func transcriptionFailureDoesNotDeliverOutputOrOverwriteSuccess() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(result: .failure(.networkUnavailable))
        let transcriptOutput = FakeTranscriptOutput()
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptionFailureRecovery: failureRecovery,
            transcriptionUsageRecorder: usageRecorder,
            initialStatus: .recording,
            lastTranscriptText: "previous transcript",
            outputStatusText: "Previous output status"
        )

        await controller.performRecordingAction()

        #expect(controller.status == .failure(message: "The network is unavailable. Try again when you are connected."))
        #expect(controller.lastTranscriptText == "previous transcript")
        #expect(controller.outputStatusText == nil)
        #expect(transcriptionService.calls.count == 1)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(usageRecorder.calls.isEmpty)
        #expect(failureRecovery.failedAttempts.map(\.reason) == [.networkUnavailable])
        #expect(controller.failurePresentation?.settingsTarget == nil)
        #expect(controller.failurePresentation?.failedAttemptID == failureRecovery.failedAttempts.first?.id)
        #expect(controller.failurePresentation?.canRetry == true)
    }

    @Test func dismissFailurePresentationKeepsRecoverableAttempt() async {
        let transcriptionService = FakeControllerTranscriptionService(result: .failure(.networkUnavailable))
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .recording),
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: failureRecovery,
            initialStatus: .recording
        )

        await controller.performRecordingAction()
        controller.dismissFailurePresentation()

        #expect(controller.status == .idle)
        #expect(controller.failurePresentation == nil)
        #expect(failureRecovery.failedAttempts.map(\.reason) == [.networkUnavailable])
    }

    @Test func invalidAPIKeyFailureRecordsAttemptAndPresentsOpenAISettingsRecovery() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(result: .failure(.invalidAPIKey))
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: failureRecovery,
            initialStatus: .recording,
            lastTranscriptText: "previous transcript"
        )

        await controller.performRecordingAction()

        #expect(
            controller.status == .failure(
                message: "OpenAI rejected the saved API key."
            )
        )
        #expect(controller.lastTranscriptText == "previous transcript")
        #expect(failureRecovery.failedAttempts.map(\.reason) == [.invalidAPIKey])
        #expect(controller.failurePresentation?.settingsTarget == .openAI)
        #expect(controller.failurePresentation?.failedAttemptID == failureRecovery.failedAttempts.first?.id)
        #expect(controller.failurePresentation?.canRetry == true)
    }

    @Test func retryFailedTranscriptionDefaultsToSavingRecoveredTranscriptWithoutAutomaticInsertion() async throws {
        let attemptID = try #require(UUID(uuidString: "A1C9C18D-B97D-4E04-9E23-9E08C51E9A8D"))
        let transcriptionID = try #require(
            UUID(uuidString: "A16CBE9A-1C9C-4344-8508-B61D47D195C1")
        )
        let attempt = FailedTranscriptionAttempt(
            id: attemptID,
            audioFileURL: URL(fileURLWithPath: "/tmp/holdtype-failed-retry.m4a"),
            audioDuration: 12,
            transcriptionModel: "gpt-4o-transcribe",
            languageCode: "en",
            reason: .networkUnavailable
        )
        let failureRecovery = FakeTranscriptionFailureRecovery(initialAttempts: [attempt])
        let transcriptionService = FakeControllerTranscriptionService(result: .success(" recovered text "))
        let transcriptOutput = FakeTranscriptOutput(result: .success(.savedToAppClipboard))
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .idle),
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptHistory: transcriptHistory,
            transcriptionFailureRecovery: failureRecovery,
            transcriptionUsageRecorder: usageRecorder,
            transcriptionIDGenerator: { transcriptionID }
        )

        await controller.retryFailedTranscription(id: attemptID)

        #expect(controller.status == .success(transcript: "recovered text"))
        #expect(controller.lastTranscriptText == "recovered text")
        #expect(failureRecovery.failedAttempts.isEmpty)
        #expect(transcriptionService.calls.map(\.audioFileURL) == [attempt.audioFileURL])
        #expect(transcriptHistory.entries.map(\.transcriptText) == ["recovered text"])
        #expect(
            usageRecorder.calls == [
                try SuccessfulTranscriptionUsage(
                    transcriptionID: transcriptionID,
                    model: "gpt-4o-transcribe",
                    audioDuration: 12
                )
            ]
        )
        #expect(transcriptOutput.calls.map(\.transcript) == ["recovered text"])
        #expect(transcriptOutput.calls.first?.settings.automaticallyInsertTranscripts == false)
        #expect(controller.outputStatusText == "Saved as Last Result. Press Control+Command+V to insert.")
    }

    @Test func retryFailedTranscriptionCanFollowAutomaticInsertionForRecoveryPrompt() async throws {
        let attemptID = try #require(UUID(uuidString: "F3C53B46-5566-4445-BB97-2F59CE1527C4"))
        let attempt = FailedTranscriptionAttempt(
            id: attemptID,
            audioFileURL: URL(fileURLWithPath: "/tmp/holdtype-failed-prompt-retry.m4a"),
            audioDuration: 10,
            transcriptionModel: "gpt-4o-transcribe",
            languageCode: "en",
            reason: .networkUnavailable
        )
        let failureRecovery = FakeTranscriptionFailureRecovery(initialAttempts: [attempt])
        let transcriptionService = FakeControllerTranscriptionService(result: .success(" inserted retry "))
        let transcriptOutput = FakeTranscriptOutput(result: .success(.insertedAndSavedToAppClipboard))
        var settings = AppSettings.defaults
        settings.automaticallyInsertTranscripts = true
        settings.saveTranscriptsToAppClipboard = true
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .idle),
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            transcriptionFailureRecovery: failureRecovery
        )

        await controller.retryFailedTranscription(
            id: attemptID,
            outputMode: .followAutomaticInsertion
        )

        #expect(controller.status == .success(transcript: "inserted retry"))
        #expect(failureRecovery.failedAttempts.isEmpty)
        #expect(transcriptOutput.calls.map(\.transcript) == ["inserted retry"])
        #expect(transcriptOutput.calls.first?.settings.automaticallyInsertTranscripts == true)
        #expect(controller.outputStatusText == "Inserted transcript into the active app. Paste Last Result is ready.")
    }

    @Test func successfulRetriesWithInvalidLegacyDurationsSkipUsageWithoutLosingText() async {
        let invalidDurations: [TimeInterval?] = [nil, 0, -1]

        for (index, duration) in invalidDurations.enumerated() {
            let attemptID = UUID()
            let attempt = FailedTranscriptionAttempt(
                id: attemptID,
                audioFileURL: URL(
                    fileURLWithPath: "/tmp/holdtype-failed-retry-invalid-duration-\(index).m4a"
                ),
                audioDuration: duration,
                transcriptionModel: "gpt-4o-transcribe",
                languageCode: "en",
                reason: .networkUnavailable
            )
            let failureRecovery = FakeTranscriptionFailureRecovery(initialAttempts: [attempt])
            let usageRecorder = FakeTranscriptionUsageRecorder()
            let controller = makeController(
                recorder: FakeAudioRecorderService(currentStatus: .idle),
                transcriptionService: FakeControllerTranscriptionService(result: .success(" recovered text ")),
                transcriptOutput: FakeTranscriptOutput(result: .success(.savedToAppClipboard)),
                transcriptionFailureRecovery: failureRecovery,
                transcriptionUsageRecorder: usageRecorder
            )

            await controller.retryFailedTranscription(id: attemptID)

            #expect(controller.status == .success(transcript: "recovered text"))
            #expect(controller.lastTranscriptText == "recovered text")
            #expect(failureRecovery.failedAttempts.isEmpty)
            #expect(usageRecorder.calls.isEmpty)
        }
    }

    @Test func cancelDuringFailedAttemptRetryKeepsAttemptAndRecordsNoUsage() async throws {
        let attemptID = try #require(
            UUID(uuidString: "A58D268D-2C6B-474F-A694-1ED27D0AF9CE")
        )
        let attempt = FailedTranscriptionAttempt(
            id: attemptID,
            audioFileURL: URL(fileURLWithPath: "/tmp/holdtype-cancelled-failed-retry.m4a"),
            audioDuration: 12,
            transcriptionModel: "gpt-4o-transcribe",
            languageCode: "en",
            reason: .networkUnavailable
        )
        let gate = ControllerAsyncGate()
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success(" late retry text "),
            beforeResult: {
                await gate.wait()
            }
        )
        let failureRecovery = FakeTranscriptionFailureRecovery(initialAttempts: [attempt])
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .idle),
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: failureRecovery,
            transcriptionUsageRecorder: usageRecorder
        )

        let retryTask = Task { @MainActor in
            await controller.retryFailedTranscription(id: attemptID)
        }
        await yieldUntil {
            controller.status == .transcribing && transcriptionService.calls.count == 1
        }

        controller.cancelRecording()

        #expect(controller.status == .idle)
        #expect(transcriptionService.cancelCount == 1)
        #expect(usageRecorder.calls.isEmpty)
        #expect(failureRecovery.failedAttempts.map(\.id) == [attemptID])

        await gate.open()
        await retryTask.value

        #expect(controller.status == .idle)
        #expect(usageRecorder.calls.isEmpty)
        #expect(failureRecovery.failedAttempts.map(\.id) == [attemptID])
    }

    @Test func retryRequestedDuringCurrentActionRunsAfterActionCompletes() async throws {
        let attemptID = try #require(UUID(uuidString: "41DB7FBA-4D70-4CFD-9E27-727F2A3309E6"))
        let retryAttempt = FailedTranscriptionAttempt(
            id: attemptID,
            audioFileURL: URL(fileURLWithPath: "/tmp/holdtype-deferred-retry.m4a"),
            audioDuration: 9,
            transcriptionModel: "gpt-4o-transcribe",
            languageCode: "en",
            reason: .networkUnavailable
        )
        let activeArtifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-active-action.m4a"),
            duration: 1.4,
            byteCount: 2048
        )
        let retryRequestOnce = ControllerOneShot()
        let failureRecovery = FakeTranscriptionFailureRecovery(initialAttempts: [retryAttempt])
        let transcriptOutput = FakeTranscriptOutput(result: .success(.inserted))
        let usageRecorder = FakeTranscriptionUsageRecorder()
        var controller: DictationSessionController!
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success(" deferred retry text "),
            beforeResult: {
                if await retryRequestOnce.take() {
                    await controller.retryFailedTranscription(
                        id: attemptID,
                        outputMode: .followAutomaticInsertion
                    )
                }
            }
        )
        controller = makeController(
            recorder: FakeAudioRecorderService(
                currentStatus: .recording,
                stopResult: .success(activeArtifact)
            ),
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptionFailureRecovery: failureRecovery,
            transcriptionUsageRecorder: usageRecorder,
            initialStatus: .recording
        )

        await controller.performRecordingAction()
        await yieldUntil {
            transcriptionService.calls.count == 2 && transcriptOutput.calls.count == 2
        }

        #expect(transcriptionService.calls.map(\.audioFileURL) == [
            activeArtifact.fileURL,
            retryAttempt.audioFileURL,
        ])
        #expect(transcriptOutput.calls.map(\.transcript) == [
            "deferred retry text",
            "deferred retry text",
        ])
        #expect(transcriptOutput.calls.last?.settings.automaticallyInsertTranscripts == true)
        #expect(failureRecovery.failedAttempts.isEmpty)
        #expect(controller.status == .success(transcript: "deferred retry text"))
        #expect(usageRecorder.calls.count == 2)
        #expect(Set(usageRecorder.calls.map(\.transcriptionID)).count == 2)
    }

    @Test func retryFailureKeepsAttemptAndUpdatesReasonWithoutOverwritingPreviousTranscript() async throws {
        let attemptID = try #require(UUID(uuidString: "0916733D-E4C8-472F-93F9-82E4AB6504D3"))
        let attempt = FailedTranscriptionAttempt(
            id: attemptID,
            audioFileURL: URL(fileURLWithPath: "/tmp/holdtype-failed-retry-timeout.m4a"),
            audioDuration: 8,
            transcriptionModel: "gpt-4o-transcribe",
            languageCode: nil,
            reason: .networkUnavailable
        )
        let failureRecovery = FakeTranscriptionFailureRecovery(initialAttempts: [attempt])
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .idle),
            transcriptionService: FakeControllerTranscriptionService(result: .failure(.timedOut)),
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: failureRecovery,
            transcriptionUsageRecorder: usageRecorder,
            initialStatus: .success(transcript: "previous transcript"),
            lastTranscriptText: "previous transcript"
        )

        await controller.retryFailedTranscription(id: attemptID)

        #expect(controller.status == .failure(message: "Transcription timed out."))
        #expect(controller.lastTranscriptText == "previous transcript")
        #expect(failureRecovery.failedAttempts.map(\.reason) == [.timedOut])
        #expect(failureRecovery.failedAttempts.map(\.retryCount) == [1])
        #expect(controller.failurePresentation?.settingsTarget == nil)
        #expect(controller.failurePresentation?.failedAttemptID == attemptID)
        #expect(controller.failurePresentation?.canRetry == true)
        #expect(usageRecorder.calls.isEmpty)
    }

    @Test func emptyTranscriptionKeepsPreviousTranscriptAndSkipsOutput() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(result: .success("  \n\t  "))
        let transcriptOutput = FakeTranscriptOutput()
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptionUsageRecorder: usageRecorder,
            initialStatus: .recording,
            lastTranscriptText: "previous accepted transcript"
        )

        await controller.performRecordingAction()

        #expect(controller.status == .failure(message: "No speech text was detected."))
        #expect(controller.lastTranscriptText == "previous accepted transcript")
        #expect(controller.outputStatusText == nil)
        #expect(transcriptionService.calls.count == 1)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(usageRecorder.calls.isEmpty)
    }

    @Test func outputFailureKeepsAcceptedTranscriptRecoverable() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(result: .success("  Delivered text\n"))
        let transcriptOutput = FakeTranscriptOutput(
            result: .failure(TextInsertionServiceError.textInsertionTimedOut)
        )
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptHistory: transcriptHistory,
            transcriptionUsageRecorder: usageRecorder,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(controller.status == .success(transcript: "Delivered text"))
        #expect(controller.lastTranscriptText == "Delivered text")
        #expect(controller.outputStatusText == "Inserting text into the active app timed out.")
        #expect(transcriptOutput.calls == [TranscriptOutputCall(transcript: "Delivered text", settings: .defaults)])
        #expect(transcriptHistory.entries.map(\.transcriptText) == ["Delivered text"])
        #expect(usageRecorder.calls.map(\.model) == ["gpt-4o-transcribe"])
        #expect(usageRecorder.calls.map(\.audioDuration) == [1.2])
        #expect(transcriptHistory.calls.first?.audioDuration == 1.2)
    }

    @Test func disabledRecoveryHistoryDoesNotWriteAcceptedTranscript() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(result: .success("  Private text\n"))
        let transcriptOutput = FakeTranscriptOutput()
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        var settings = AppSettings.defaults
        settings.saveTranscriptHistory = false
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            transcriptHistory: transcriptHistory,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(controller.status == .success(transcript: "Private text"))
        #expect(transcriptHistory.entries.isEmpty)
    }

    private func makeController(
        recorder: FakeAudioRecorderService,
        transcriptionService: FakeControllerTranscriptionService,
        textCorrectionService: FakeTextCorrectionService? = nil,
        translationService: FakeTranslationService? = nil,
        settings: AppSettings = .defaults,
        transcriptOutput: FakeTranscriptOutput,
        cuePlayer: FakeDictationCuePlayer? = nil,
        transcriptHistory: FakeTranscriptRecoveryHistory? = nil,
        transcriptionFailureRecovery: FakeTranscriptionFailureRecovery? = nil,
        activeTextContextReader: FakeActiveTextContextReader? = nil,
        transcriptionUsageRecorder: FakeTranscriptionUsageRecorder? = nil,
        transcriptionIDGenerator: @escaping () -> UUID = UUID.init,
        recordingCache: FakeRecordingCache? = nil,
        recordingStopTailSleeper: FakeRecordingStopTailSleeper? = nil,
        eventLogger: FakeDictationEventLogger? = nil,
        credentialResolverForUngatedActions: (any OpenAICredentialResolving)? = FakeControllerCredentialResolver(),
        initialStatus: DictationStatus = .idle,
        lastTranscriptText: String? = nil,
        outputStatusText: String? = nil
    ) -> DictationSessionController {
        let cuePlayer = cuePlayer ?? FakeDictationCuePlayer()
        let transcriptHistory = transcriptHistory ?? FakeTranscriptRecoveryHistory()

        return DictationSessionController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            textCorrectionService: textCorrectionService ?? FakeTextCorrectionService(),
            translationService: translationService ?? FakeTranslationService(),
            settingsProvider: { settings },
            transcriptOutput: transcriptOutput,
            cuePlayer: cuePlayer,
            transcriptHistory: transcriptHistory,
            transcriptionFailureRecovery: transcriptionFailureRecovery ?? FakeTranscriptionFailureRecovery(),
            activeTextContextReader: activeTextContextReader ?? FakeActiveTextContextReader(),
            transcriptionUsageRecorder: transcriptionUsageRecorder ?? FakeTranscriptionUsageRecorder(),
            transcriptionIDGenerator: transcriptionIDGenerator,
            recordingCache: recordingCache ?? FakeRecordingCache(),
            recordingStopTailSleeper: recordingStopTailSleeper ?? FakeRecordingStopTailSleeper(),
            eventLogger: eventLogger ?? FakeDictationEventLogger(),
            credentialResolverForUngatedActions: credentialResolverForUngatedActions,
            initialStatus: initialStatus,
            lastTranscriptText: lastTranscriptText,
            outputStatusText: outputStatusText
        )
    }

    private func makeSettings(saveTranscriptsToAppClipboard: Bool = true) -> AppSettings {
        var settings = AppSettings.defaults
        settings.saveTranscriptsToAppClipboard = saveTranscriptsToAppClipboard
        return settings
    }

    private func yieldUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<20 {
            if condition() {
                return
            }

            await Task.yield()
        }
    }
}

private let defaultControllerCredentialAPIKey = "sk-controller-test"

private struct TranscriptionCall: Equatable {
    let audioFileURL: URL
    let settings: AppSettings
    let context: TranscriptionPromptContext?
    let credentialAPIKey: String

    init(
        audioFileURL: URL,
        settings: AppSettings,
        context: TranscriptionPromptContext? = nil,
        credentialAPIKey: String = defaultControllerCredentialAPIKey
    ) {
        self.audioFileURL = audioFileURL
        self.settings = settings
        self.context = context
        self.credentialAPIKey = credentialAPIKey
    }
}

private struct TranscriptOutputCall: Equatable {
    let transcript: String
    let settings: AppSettings
}

private struct TextCorrectionCall: Equatable {
    let transcript: String
    let settings: AppSettings
    let credentialAPIKey: String

    init(
        transcript: String,
        settings: AppSettings,
        credentialAPIKey: String = defaultControllerCredentialAPIKey
    ) {
        self.transcript = transcript
        self.settings = settings
        self.credentialAPIKey = credentialAPIKey
    }
}

private struct TranslationCall: Equatable {
    let transcript: String
    let settings: AppSettings
    let credentialAPIKey: String

    init(
        transcript: String,
        settings: AppSettings,
        credentialAPIKey: String = defaultControllerCredentialAPIKey
    ) {
        self.transcript = transcript
        self.settings = settings
        self.credentialAPIKey = credentialAPIKey
    }
}

private struct RecoveryHistoryCall: Equatable {
    let transcript: String
    let settings: AppSettings
    let audioDuration: TimeInterval?
    let cachedAudioFileURL: URL?
}

private struct RecordingCachePolicyCall: Equatable {
    let artifact: AudioRecordingArtifact
    let policy: RecordingCachePolicy
}

private final class FakeRecordingCache: RecordingCacheLifecycleHandling {
    private(set) var completedRecordingCalls: [RecordingCachePolicyCall] = []
    private let onHandleCompletedRecording: () -> Void

    init(onHandleCompletedRecording: @escaping () -> Void = {}) {
        self.onHandleCompletedRecording = onHandleCompletedRecording
    }

    func handleCompletedRecording(
        _ artifact: AudioRecordingArtifact,
        policy: RecordingCachePolicy
    ) throws {
        onHandleCompletedRecording()
        completedRecordingCalls.append(
            RecordingCachePolicyCall(artifact: artifact, policy: policy)
        )
    }
}

private final class FakeDictationEventLogger: DictationEventLogging {
    private(set) var events: [DictationLogEvent] = []

    func record(_ event: DictationLogEvent) {
        events.append(event)
    }
}

private final class FakeRecordingStopTailSleeper: RecordingStopTailSleeping {
    enum Mode {
        case immediate
        case sleepUntilCancelled
    }

    private let mode: Mode
    private(set) var sleepCalls: [TimeInterval] = []

    init(mode: Mode = .immediate) {
        self.mode = mode
    }

    func sleep(seconds: TimeInterval) async throws {
        sleepCalls.append(seconds)

        switch mode {
        case .immediate:
            return
        case .sleepUntilCancelled:
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
    }
}

private struct FakeControllerCredentialResolver: OpenAICredentialResolving {
    let result: Result<String, OpenAICredentialResolutionError>

    init(result: Result<String, OpenAICredentialResolutionError> = .success(defaultControllerCredentialAPIKey)) {
        self.result = result
    }

    func resolveOpenAICredential() throws -> OpenAICredential {
        try OpenAICredential(apiKey: result.get())
    }
}

private final class FakeControllerTranscriptionService: OpenAITranscriptionServing {
    private let result: Result<String, OpenAITranscriptionServiceError>
    private let beforeResult: (() async -> Void)?
    private(set) var calls: [TranscriptionCall] = []
    private(set) var cancelCount = 0

    init(
        result: Result<String, OpenAITranscriptionServiceError> = .success("Controller transcript"),
        beforeResult: (() async -> Void)? = nil
    ) {
        self.result = result
        self.beforeResult = beforeResult
    }

    func transcribe(
        audioFileURL: URL,
        settings: AppSettings,
        context: TranscriptionPromptContext?,
        credential: OpenAICredential
    ) async throws -> String {
        calls.append(
            TranscriptionCall(
                audioFileURL: audioFileURL,
                settings: settings,
                context: context,
                credentialAPIKey: credential.apiKey
            )
        )
        await beforeResult?()
        return try result.get()
    }

    func cancelActiveTranscription() {
        cancelCount += 1
    }
}

private final class FakeTranscriptOutput: TranscriptOutputDelivering {
    private let result: Result<TextInsertionResult, Error>
    private(set) var calls: [TranscriptOutputCall] = []

    init(result: Result<TextInsertionResult, Error> = .success(.skipped(reason: .appClipboardDisabled))) {
        self.result = result
    }

    func deliver(_ transcript: String, settings: AppSettings) async throws -> TextInsertionResult {
        calls.append(TranscriptOutputCall(transcript: transcript, settings: settings))
        return try result.get()
    }
}

private final class FakeTextCorrectionService: TextCorrectionServing {
    private let result: Result<String, OpenAITextCorrectionServiceError>
    private let beforeResult: (() async -> Void)?
    private(set) var calls: [TextCorrectionCall] = []
    private(set) var cancelCount = 0

    init(
        result: Result<String, OpenAITextCorrectionServiceError>? = nil,
        beforeResult: (() async -> Void)? = nil
    ) {
        self.result = result ?? .success("")
        self.beforeResult = beforeResult
    }

    func correct(
        _ transcript: String,
        settings: AppSettings,
        credential: OpenAICredential
    ) async throws -> String {
        calls.append(
            TextCorrectionCall(
                transcript: transcript,
                settings: settings,
                credentialAPIKey: credential.apiKey
            )
        )
        await beforeResult?()

        switch result {
        case .success(let correctedTranscript):
            return correctedTranscript.isEmpty ? transcript : correctedTranscript
        case .failure(let error):
            throw error
        }
    }

    func cancelActiveCorrection() {
        cancelCount += 1
    }
}

private final class FakeTranslationService: TranscriptTranslationServing {
    private let result: Result<String, OpenAITextTranslationServiceError>
    private(set) var calls: [TranslationCall] = []
    private(set) var cancelCount = 0

    init(result: Result<String, OpenAITextTranslationServiceError>? = nil) {
        self.result = result ?? .success("")
    }

    func translate(
        _ transcript: String,
        settings: AppSettings,
        credential: OpenAICredential
    ) async throws -> String {
        calls.append(
            TranslationCall(
                transcript: transcript,
                settings: settings,
                credentialAPIKey: credential.apiKey
            )
        )

        switch result {
        case .success(let translatedTranscript):
            return translatedTranscript.isEmpty ? transcript : translatedTranscript
        case .failure(let error):
            throw error
        }
    }

    func cancelActiveTranslation() {
        cancelCount += 1
    }
}

@MainActor
private final class FakeTranscriptionUsageRecorder: TranscriptionUsageRecording {
    private(set) var calls: [SuccessfulTranscriptionUsage] = []

    func recordSuccessfulTranscriptionUsage(_ usage: SuccessfulTranscriptionUsage) {
        calls.append(usage)
    }
}

@MainActor
private final class FakeTranscriptRecoveryHistory: TranscriptRecoveryHistoryRecording {
    private(set) var entries: [TranscriptHistoryEntry] = []
    private(set) var calls: [RecoveryHistoryCall] = []
    private let recordError: (any Error)?

    init(recordError: (any Error)? = nil) {
        self.recordError = recordError
    }

    func recordAcceptedTranscript(
        _ transcript: String,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        cachedAudioFileURL: URL?
    ) throws {
        calls.append(
            RecoveryHistoryCall(
                transcript: transcript,
                settings: settings,
                audioDuration: audioDuration,
                cachedAudioFileURL: cachedAudioFileURL
            )
        )

        if let recordError {
            throw recordError
        }

        guard settings.saveTranscriptHistory else {
            return
        }

        entries = try [
            TranscriptHistoryEntry(
                transcriptText: transcript,
                transcriptionModel: settings.resolvedTranscriptionModel,
                languageCode: settings.resolvedLanguageCode,
                audioDuration: audioDuration,
                cachedAudioFileURL: settings.recordingCachePolicy.keepsRecordings
                    ? cachedAudioFileURL
                    : nil
            )
        ] + entries
    }

    func clear() {
        entries = []
    }
}

@MainActor
private final class FakeTranscriptionFailureRecovery: TranscriptionFailureRecoveryRecording {
    private(set) var failedAttempts: [FailedTranscriptionAttempt]
    private let recordFailedAttemptError: (any Error)?
    private let onRecordFailedAttempt: () -> Void

    init(
        initialAttempts: [FailedTranscriptionAttempt] = [],
        recordFailedAttemptError: (any Error)? = nil,
        onRecordFailedAttempt: @escaping () -> Void = {}
    ) {
        failedAttempts = initialAttempts
        self.recordFailedAttemptError = recordFailedAttemptError
        self.onRecordFailedAttempt = onRecordFailedAttempt
    }

    func recordFailedAttempt(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        reason: FailedTranscriptionReason
    ) throws -> FailedTranscriptionAttempt? {
        guard settings.saveTranscriptHistory, reason.shouldRecordFailedAttempt else {
            return nil
        }

        onRecordFailedAttempt()
        if let recordFailedAttemptError {
            throw recordFailedAttemptError
        }

        let attempt = FailedTranscriptionAttempt(
            audioFileURL: audioFileURL,
            audioDuration: audioDuration,
            transcriptionModel: settings.resolvedTranscriptionModel,
            languageCode: settings.resolvedLanguageCode,
            reason: reason
        )
        failedAttempts = [attempt] + failedAttempts
        return attempt
    }

    func updateFailedAttempt(id: FailedTranscriptionAttempt.ID, reason: FailedTranscriptionReason) throws {
        guard let index = failedAttempts.firstIndex(where: { $0.id == id }) else {
            throw TranscriptionFailureRecoveryError.attemptUnavailable
        }

        failedAttempts[index].reason = reason
        failedAttempts[index].retryCount += 1
        failedAttempts[index].updatedAt = Date()
    }

    func removeFailedAttempt(id: FailedTranscriptionAttempt.ID) {
        failedAttempts.removeAll { $0.id == id }
    }

    func clear() {
        failedAttempts = []
    }
}

@MainActor
private final class FakeActiveTextContextReader: ActiveTextContextReading {
    private let context: TranscriptionPromptContext?
    private(set) var settingsCalls: [AppSettings] = []

    init(context: TranscriptionPromptContext? = nil) {
        self.context = context
    }

    func currentContext(settings: AppSettings) -> TranscriptionPromptContext? {
        settingsCalls.append(settings)
        return context
    }
}

@MainActor
private final class FakeDictationCuePlayer: DictationCuePlaying {
    private(set) var playedCues: [DictationCue] = []

    func play(_ cue: DictationCue) {
        playedCues.append(cue)
    }
}

private actor ControllerAsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen {
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let waitingContinuations = continuations
        continuations.removeAll()

        for continuation in waitingContinuations {
            continuation.resume()
        }
    }
}

private actor ControllerOneShot {
    private var hasRun = false

    func take() -> Bool {
        guard !hasRun else {
            return false
        }

        hasRun = true
        return true
    }
}
