//
//  DictationSessionControllerTests.swift
//  HoldTypeTests
//
//  Created by Codex on 6/22/26.
//

import Foundation
import HoldTypeDomain
import HoldTypeOpenAI
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
        let eventLogger = FakeDictationEventLogger()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: failureRecovery,
            eventLogger: eventLogger,
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
        #expect(attemptStageFailureEvents(in: eventLogger.events).isEmpty)
    }

    @Test func unavailableCredentialDuringStopDoesNotUploadOrReportInvalidAPIKey() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(result: .failure(.invalidAPIKey))
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let eventLogger = FakeDictationEventLogger()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: failureRecovery,
            eventLogger: eventLogger,
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
        #expect(controller.failurePresentation?.failedAttemptID != nil)
        #expect(controller.failurePresentation?.canRetry == true)
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls.isEmpty)
        #expect(failureRecovery.failedAttempts.count == 1)
        #expect(failureRecovery.failedAttempts.first?.reason == .apiKeyUnavailable)
        #expect(
            attemptStageFailureEvents(in: eventLogger.events) == [
                .transcriptionFailed(category: "api_key_unavailable")
            ]
        )
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
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let settings = makeSettings(saveTranscriptsToAppClipboard: false)
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            cuePlayer: cuePlayer,
            transcriptHistory: transcriptHistory,
            transcriptionFailureRecovery: failureRecovery,
            eventLogger: eventLogger,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(controller.status == .success(transcript: "Shared controller transcript"))
        #expect(controller.voiceAttemptOutcome == .resultReady)
        #expect(controller.lastTranscriptText == "Shared controller transcript")
        #expect(controller.status.lastTranscriptText == "Shared controller transcript")
        #expect(controller.outputStatusText == "Paste Last Result is disabled.")
        #expect(recorder.stopCount == 1)
        #expect(
            transcriptionService.calls == [
                TranscriptionCall(
                    audioFileURL: artifact.fileURL,
                    model: settings.resolvedTranscriptionModel,
                    languageCode: settings.resolvedLanguageCode,
                    promptComposition: settings.transcriptionPromptComposition(context: nil)
                )
            ]
        )
        #expect(
            transcriptOutput.calls == [
                TranscriptOutputCall(
                    transcript: "Shared controller transcript",
                    preferences: settings.outputDeliveryPreferences
                )
            ]
        )
        #expect(cuePlayer.playedCues == [.stopRecording])
        #expect(transcriptHistory.calls.count == 1)
        #expect(transcriptHistory.entries.map(\.transcriptText) == ["Shared controller transcript"])
        #expect(failureRecovery.failedAttempts.isEmpty)
        let nonTerminalEvents = eventLogger.events.filter { event in
            if case .recordingTerminal = event {
                return false
            }
            return true
        }
        #expect(
            nonTerminalEvents == [
                .recordingStopRequested,
                .recordingStopped(duration: 1.3, byteCount: 2048),
                .transcriptionStarted,
                .transcriptionSucceeded,
                .recordingCacheHandled(policy: .deleteImmediately),
            ]
        )
        let terminalEvents = eventLogger.events.filter { event in
            if case .recordingTerminal = event {
                return true
            }
            return false
        }
        #expect(terminalEvents.count == 1)
        guard let terminalEvent = terminalEvents.first else {
            Issue.record("Expected one user-finished terminal event")
            return
        }
        guard case .recordingTerminal(
            cause: .userFinished,
            attemptID: _,
            durability: .historyCheckpoint,
            providerAuthorized: true
        ) = terminalEvent else {
            Issue.record("Expected one user-finished terminal event")
            return
        }
    }

    @Test func automaticFiveMinuteStopTranscribesExactlyOnceWhenKeyUpRaces() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("holdtype-controller-max-saved-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("Cache", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let originalURL = cacheURL.appendingPathComponent("HoldType-max.m4a")
        try Data("maximum recording".utf8).write(to: originalURL)
        let artifact = AudioRecordingArtifact(
            fileURL: originalURL,
            duration: 300.4,
            byteCount: 2_400_000
        )
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Automatic limit transcript")
        )
        let cuePlayer = FakeDictationCuePlayer()
        let eventLogger = FakeDictationEventLogger()
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        let failureRecovery = TranscriptionFailureRecoveryStore(directoryURL: recoveryURL)
        let recordingCache = RecordingCacheService(
            directoryURL: cacheURL,
            legacyDirectoryURL: nil
        )
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            cuePlayer: cuePlayer,
            transcriptHistory: transcriptHistory,
            transcriptionFailureRecovery: failureRecovery,
            recordingCache: recordingCache,
            eventLogger: eventLogger,
            initialStatus: .recording
        )
        recorder.simulateAutomaticStop(
            .success(
                AudioRecorderAutomaticCompletion(
                    artifact: artifact,
                    reason: .maximumDuration
                )
            )
        )
        await controller.performRecordingAction()
        await yieldUntil { controller.status.voiceWorkPhase == .inactive }

        #expect(controller.status == .success(transcript: "Automatic limit transcript"))
        #expect(recorder.stopCount == 0)
        #expect(transcriptionService.calls.count == 1)
        let savedAttempt = failureRecovery.failedAttempts.first
        #expect(savedAttempt?.state == .saved)
        #expect(savedAttempt?.completionKind == .maximumDuration)
        #expect(savedAttempt?.acceptedTranscriptText == "Automatic limit transcript")
        #expect(savedAttempt?.canRetry == false)
        #expect(savedAttempt?.audioFileURL != artifact.fileURL)
        #expect(transcriptionService.calls.first?.audioFileURL == savedAttempt?.audioFileURL)
        #expect(transcriptHistory.calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: artifact.fileURL.path) == false)
        if let savedAudioURL = savedAttempt?.audioFileURL {
            #expect(FileManager.default.fileExists(atPath: savedAudioURL.path))
        }
        #expect(cuePlayer.playedCues == [.recordingLimitReached])
        #expect(eventLogger.events.filter { $0 == .recordingLimitReached }.count == 1)
        #expect(
            eventLogger.events.filter {
                if case .recordingStopped = $0 { return true }
                return false
            }.count == 1
        )
    }

    @Test func manualKeyUpWinningAtMaximumBoundaryStillRetainsPlayableAudio() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("holdtype-controller-manual-max-race-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("Cache", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let originalURL = cacheURL.appendingPathComponent("HoldType-manual-max-race.m4a")
        try Data("near-boundary recording".utf8).write(to: originalURL)
        let artifact = AudioRecordingArtifact(
            fileURL: originalURL,
            duration: 300,
            byteCount: 2_300_000
        )
        let stopGate = ControllerAsyncGate()
        let recorder = FakeAudioRecorderService(
            stopResult: .success(artifact),
            beforeStop: { await stopGate.wait() }
        )
        let monitor = FakeRecordingDurationMonitor()
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Boundary transcript")
        )
        let failureRecovery = TranscriptionFailureRecoveryStore(directoryURL: recoveryURL)
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        let eventLogger = FakeDictationEventLogger()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            recordingDurationMonitor: monitor,
            transcriptHistory: transcriptHistory,
            transcriptionFailureRecovery: failureRecovery,
            recordingCache: RecordingCacheService(
                directoryURL: cacheURL,
                legacyDirectoryURL: nil
            ),
            eventLogger: eventLogger
        )

        await controller.performRecordingAction()
        let manualStopTask = Task { @MainActor in
            await controller.performRecordingAction()
        }
        await yieldUntil { recorder.stopCount == 1 }

        // Both automatic boundaries arrive while key-up owns finalization and
        // therefore lose the exact-once race.
        monitor.emit(elapsedWholeSecond: 300)
        recorder.simulateAutomaticStop(
            .success(
                AudioRecorderAutomaticCompletion(
                    artifact: artifact,
                    reason: .maximumDuration
                )
            )
        )
        await stopGate.open()
        await manualStopTask.value

        #expect(controller.status == .success(transcript: "Boundary transcript"))
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls.count == 1)
        #expect(eventLogger.events.filter { $0 == .recordingLimitReached }.count == 1)
        #expect(transcriptHistory.calls.isEmpty)
        let savedAttempt = try #require(failureRecovery.failedAttempts.first)
        #expect(savedAttempt.state == .saved)
        #expect(savedAttempt.acceptedTranscriptText == "Boundary transcript")
        #expect(savedAttempt.canRetry == false)
        #expect(FileManager.default.fileExists(atPath: savedAttempt.audioFileURL.path))
        #expect(
            TranscriptHistoryAudioPlaybackAction().canPlay(savedAttempt)
        )
        #expect(FileManager.default.fileExists(atPath: originalURL.path) == false)
    }

    @Test func manualWinnerConsumesMaximumCallbackWhenFinalizedDurationFallsBackToZero() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("holdtype-controller-zero-duration-max-race-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("Cache", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let originalURL = cacheURL.appendingPathComponent("HoldType-zero-duration-race.m4a")
        try Data("positive audio with unavailable duration".utf8).write(to: originalURL)
        let artifact = AudioRecordingArtifact(
            fileURL: originalURL,
            duration: 0,
            byteCount: 2_300_000
        )
        let stopGate = ControllerAsyncGate()
        let recorder = FakeAudioRecorderService(
            stopResult: .success(artifact),
            beforeStop: { await stopGate.wait() },
            stopFinalizationReachedMaximumDuration: true
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Callback preserved transcript")
        )
        let failureRecovery = TranscriptionFailureRecoveryStore(directoryURL: recoveryURL)
        let eventLogger = FakeDictationEventLogger()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: failureRecovery,
            recordingCache: RecordingCacheService(
                directoryURL: cacheURL,
                legacyDirectoryURL: nil
            ),
            eventLogger: eventLogger
        )

        await controller.performRecordingAction()
        let manualStopTask = Task { @MainActor in
            await controller.performRecordingAction()
        }
        await yieldUntil { recorder.stopCount == 1 }
        await stopGate.open()
        await manualStopTask.value

        // The service-level joined result was consumed before the delegate
        // notification arrived. This late callback must be a no-op.
        recorder.simulateAutomaticStop(
            .success(
                AudioRecorderAutomaticCompletion(
                    artifact: artifact,
                    reason: .maximumDuration
                )
            )
        )

        #expect(controller.status == .success(transcript: "Callback preserved transcript"))
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls.count == 1)
        #expect(eventLogger.events.filter { $0 == .recordingLimitReached }.count == 1)
        let savedAttempt = try #require(failureRecovery.failedAttempts.first)
        #expect(savedAttempt.state == .saved)
        #expect(savedAttempt.completionKind == .maximumDuration)
        #expect(savedAttempt.acceptedTranscriptText == "Callback preserved transcript")
        #expect(FileManager.default.fileExists(atPath: savedAttempt.audioFileURL.path))
        #expect(TranscriptHistoryAudioPlaybackAction().canPlay(savedAttempt))
        #expect(FileManager.default.fileExists(atPath: originalURL.path) == false)
    }

    @Test func maximumDurationSaveStateFailureKeepsRecoverableAudioWithoutRepeatingProvider() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("holdtype-controller-max-save-failure-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("Cache", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let originalURL = cacheURL.appendingPathComponent("HoldType-max-save-failure.m4a")
        try Data("maximum recording".utf8).write(to: originalURL)
        let metadataURL = recoveryURL.appendingPathComponent("Recovery.json")
        let artifact = AudioRecordingArtifact(
            fileURL: originalURL,
            duration: 300,
            byteCount: 2_400_000
        )
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Accepted despite save failure"),
            beforeResult: {
                try? FileManager.default.removeItem(at: metadataURL)
                try? FileManager.default.createDirectory(
                    at: metadataURL,
                    withIntermediateDirectories: false
                )
            }
        )
        let failureRecovery = TranscriptionFailureRecoveryStore(directoryURL: recoveryURL)
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptHistory: transcriptHistory,
            transcriptionFailureRecovery: failureRecovery,
            recordingCache: RecordingCacheService(
                directoryURL: cacheURL,
                legacyDirectoryURL: nil
            ),
            initialStatus: .recording
        )

        recorder.simulateAutomaticStop(
            .success(
                AudioRecorderAutomaticCompletion(
                    artifact: artifact,
                    reason: .maximumDuration
                )
            )
        )
        await yieldUntil { controller.status.voiceWorkPhase == .inactive }

        #expect(controller.status == .success(transcript: "Accepted despite save failure"))
        #expect(
            controller.outputStatusText
                == "Text was accepted, but the recording that reached the limit could not be marked as saved."
        )
        #expect(transcriptionService.calls.count == 1)
        #expect(transcriptOutput.calls.count == 1)
        #expect(transcriptHistory.calls.isEmpty)
        let retainedAttempt = try #require(failureRecovery.failedAttempts.first)
        #expect(retainedAttempt.state == .failed)
        #expect(retainedAttempt.reason == .savedStatePersistenceFailed)
        #expect(retainedAttempt.canRetry == false)
        #expect(retainedAttempt.acceptedTranscriptText == "Accepted despite save failure")
        #expect(FileManager.default.fileExists(atPath: retainedAttempt.audioFileURL.path))
        #expect(FileManager.default.fileExists(atPath: originalURL.path) == false)

        await controller.retryFailedTranscription(id: retainedAttempt.id)
        #expect(transcriptionService.calls.count == 1)
        #expect(failureRecovery.failedAttempts.first?.state == .failed)
        #expect(
            controller.outputStatusText
                == "This saved recording is not available for retry."
        )

        let restoredRecoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let restoredAttempt = try #require(restoredRecoveryStore.failedAttempts.first)
        #expect(restoredAttempt.id == retainedAttempt.id)
        #expect(restoredAttempt.state == .failed)
        #expect(restoredAttempt.reason == .savedStatePersistenceFailed)
        #expect(restoredAttempt.completionKind == .maximumDuration)
        #expect(restoredAttempt.canRetry == false)
        #expect(restoredAttempt.acceptedTranscriptText == "Accepted despite save failure")
        #expect(FileManager.default.fileExists(atPath: restoredAttempt.audioFileURL.path))
        let restoredPresentation = TranscriptionRecoveryHistoryRowPresentation(
            attempt: restoredAttempt
        )
        #expect(restoredPresentation.showsRetry == false)
        #expect(restoredPresentation.showsSaveRetry)

        let relaunchedProvider = FakeControllerTranscriptionService(
            result: .success("Must never be requested")
        )
        let relaunchedController = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: relaunchedProvider,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: restoredRecoveryStore
        )
        await relaunchedController.retryFailedTranscription(id: restoredAttempt.id)
        #expect(relaunchedProvider.calls.isEmpty)
        #expect(
            relaunchedController.outputStatusText
                == "This saved recording is not available for retry."
        )

        try FileManager.default.removeItem(at: metadataURL)
        try restoredRecoveryStore.markSaved(
            id: restoredAttempt.id,
            acceptedTranscriptText: try #require(restoredAttempt.acceptedTranscriptText)
        )
        let locallyRepairedAttempt = try #require(
            restoredRecoveryStore.failedAttempts.first
        )
        #expect(locallyRepairedAttempt.state == .saved)
        #expect(
            locallyRepairedAttempt.acceptedTranscriptText
                == "Accepted despite save failure"
        )
        #expect(FileManager.default.fileExists(atPath: locallyRepairedAttempt.audioFileURL.path))
        #expect(relaunchedProvider.calls.isEmpty)
    }

    @Test func maximumCheckpointFailureThenRetrySuccessFailsClosedWithoutSecondProviderCall() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-controller-max-checkpoint-emergency-\(UUID().uuidString)",
                isDirectory: true
            )
        let cacheURL = rootURL.appendingPathComponent("Cache", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: recoveryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let metadataURL = recoveryURL.appendingPathComponent("Recovery.json")
        try FileManager.default.createDirectory(
            at: metadataURL,
            withIntermediateDirectories: false
        )
        let originalURL = cacheURL.appendingPathComponent("checkpoint-emergency.m4a")
        try Data("checkpoint emergency recording".utf8).write(to: originalURL)
        let artifact = AudioRecordingArtifact(
            fileURL: originalURL,
            duration: 300,
            byteCount: 2_400_000
        )
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Accepted on emergency retry")
        )
        let recoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore,
            recordingCache: RecordingCacheService(
                directoryURL: cacheURL,
                legacyDirectoryURL: nil
            ),
            initialStatus: .recording
        )

        recorder.simulateAutomaticStop(
            .success(
                AudioRecorderAutomaticCompletion(
                    artifact: artifact,
                    reason: .maximumDuration
                )
            )
        )
        await yieldUntil { controller.status.voiceWorkPhase == .inactive }

        #expect(transcriptionService.calls.isEmpty)
        let emergencyAttempt = try #require(recoveryStore.failedAttempts.first)
        #expect(emergencyAttempt.state == .failed)
        #expect(emergencyAttempt.completionKind == .maximumDuration)
        #expect(emergencyAttempt.canRetry)
        #expect(emergencyAttempt.audioFileURL != originalURL)
        #expect(FileManager.default.fileExists(atPath: emergencyAttempt.audioFileURL.path))
        #expect(FileManager.default.fileExists(atPath: originalURL.path))

        await controller.retryFailedTranscription(id: emergencyAttempt.id)
        #expect(transcriptionService.calls.count == 1)
        let failClosedAttempt = try #require(recoveryStore.failedAttempts.first)
        #expect(failClosedAttempt.id == emergencyAttempt.id)
        #expect(failClosedAttempt.state == .failed)
        #expect(failClosedAttempt.reason == .savedStatePersistenceFailed)
        #expect(failClosedAttempt.canRetry == false)
        #expect(failClosedAttempt.acceptedTranscriptText == "Accepted on emergency retry")
        #expect(FileManager.default.fileExists(atPath: failClosedAttempt.audioFileURL.path))
        let presentation = TranscriptionRecoveryHistoryRowPresentation(
            attempt: failClosedAttempt
        )
        #expect(presentation.showsRetry == false)
        #expect(presentation.showsSaveRetry)

        await controller.retryFailedTranscription(id: emergencyAttempt.id)
        #expect(transcriptionService.calls.count == 1)
        #expect(recoveryStore.failedAttempts.first?.canRetry == false)
    }

    @Test func unownedEmergencyRequiresLocalSaveBeforeProviderAndThenSurvivesRelaunch() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-controller-unowned-emergency-\(UUID().uuidString)",
                isDirectory: true
            )
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let originalURL = rootURL.appendingPathComponent("unowned-emergency.m4a")
        try Data("unowned emergency recording".utf8).write(to: originalURL)
        let recoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let emergencyAttempt = try #require(
            recoveryStore.retainEmergencyFallback(
                audioFileURL: originalURL,
                settings: .defaults,
                audioDuration: 300,
                reason: .other,
                completionKind: .maximumDuration
            )
        )
        #expect(emergencyAttempt.reason == .recoveryOwnershipPersistenceFailed)
        #expect(emergencyAttempt.canRetry == false)
        #expect(TranscriptHistoryAudioPlaybackAction().canPlay(emergencyAttempt))
        let emergencyPresentation = TranscriptionRecoveryHistoryRowPresentation(
            attempt: emergencyAttempt
        )
        #expect(emergencyPresentation.showsRetry == false)
        #expect(emergencyPresentation.showsSaveRetry)

        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Accepted only after local save")
        )
        let controller = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore
        )
        await controller.retryFailedTranscription(id: emergencyAttempt.id)
        #expect(transcriptionService.calls.isEmpty)

        try recoveryStore.repairLocalRecovery(id: emergencyAttempt.id)
        let locallySavedAttempt = try #require(recoveryStore.failedAttempts.first)
        #expect(locallySavedAttempt.id == emergencyAttempt.id)
        #expect(locallySavedAttempt.reason == .processingInterrupted)
        #expect(locallySavedAttempt.completionKind == .maximumDuration)
        #expect(locallySavedAttempt.canRetry)
        #expect(locallySavedAttempt.audioFileURL != originalURL)
        #expect(FileManager.default.fileExists(atPath: locallySavedAttempt.audioFileURL.path))

        await controller.retryFailedTranscription(id: locallySavedAttempt.id)
        #expect(transcriptionService.calls.count == 1)
        let savedAttempt = try #require(recoveryStore.failedAttempts.first)
        #expect(savedAttempt.state == .saved)
        #expect(savedAttempt.acceptedTranscriptText == "Accepted only after local save")
        #expect(savedAttempt.canRetry == false)
        #expect(TranscriptHistoryAudioPlaybackAction().canPlay(savedAttempt))

        let relaunchedStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let relaunchedAttempt = try #require(relaunchedStore.failedAttempts.first)
        #expect(relaunchedAttempt.state == .saved)
        #expect(relaunchedAttempt.acceptedTranscriptText == "Accepted only after local save")
        let duplicateProvider = FakeControllerTranscriptionService(
            result: .success("Must not run")
        )
        let relaunchedController = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: duplicateProvider,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: relaunchedStore
        )
        await relaunchedController.retryFailedTranscription(id: relaunchedAttempt.id)
        #expect(duplicateProvider.calls.isEmpty)
    }

    @Test func unownedEmergencyWithContinuedCopyFailureNeverCallsProvider() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-controller-unowned-copy-failure-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let originalURL = rootURL.appendingPathComponent("still-unowned.m4a")
        try Data("still unowned recording".utf8).write(to: originalURL)
        let unusableRecoveryURL = rootURL.appendingPathComponent("Recovery")
        try Data("not a directory".utf8).write(to: unusableRecoveryURL)
        let recoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: unusableRecoveryURL
        )
        let emergencyAttempt = try #require(
            recoveryStore.retainEmergencyFallback(
                audioFileURL: originalURL,
                settings: .defaults,
                audioDuration: 300,
                reason: .other,
                completionKind: .maximumDuration
            )
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Must not run")
        )
        let controller = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore
        )

        await controller.retryFailedTranscription(id: emergencyAttempt.id)
        #expect(transcriptionService.calls.isEmpty)
        #expect(throws: TranscriptionFailureRecoveryError.directoryUnavailable) {
            try recoveryStore.repairLocalRecovery(id: emergencyAttempt.id)
        }
        await controller.retryFailedTranscription(id: emergencyAttempt.id)
        #expect(transcriptionService.calls.isEmpty)
        #expect(recoveryStore.failedAttempts.first?.canRetry == false)
        #expect(FileManager.default.fileExists(atPath: originalURL.path))
        #expect(TranscriptHistoryAudioPlaybackAction().canPlay(emergencyAttempt))
    }

    @Test func unownedEmergencyWithDualOwnershipWriteFailureStaysFailClosed() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-controller-unowned-dual-write-failure-\(UUID().uuidString)",
                isDirectory: true
            )
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: recoveryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let attemptID = UUID(uuidString: "D9C6D531-C23C-4D7C-A0C0-976A9E289ED2")!
        let originalURL = rootURL.appendingPathComponent("dual-write-emergency.m4a")
        try Data("dual write emergency recording".utf8).write(to: originalURL)
        let recoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL,
            uuidProvider: { attemptID }
        )
        let emergencyAttempt = try #require(
            recoveryStore.retainEmergencyFallback(
                audioFileURL: originalURL,
                settings: .defaults,
                audioDuration: 300,
                reason: .other,
                completionKind: .maximumDuration
            )
        )
        let metadataURL = recoveryURL.appendingPathComponent("Recovery.json")
        let markerURL = recoveryURL.appendingPathComponent(
            "ProcessingCheckpoint-\(attemptID.uuidString.lowercased()).json"
        )
        try FileManager.default.createDirectory(
            at: metadataURL,
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: markerURL,
            withIntermediateDirectories: false
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Must not run")
        )
        let controller = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore
        )

        #expect(throws: TranscriptionFailureRecoveryError.saveFailed) {
            try recoveryStore.repairLocalRecovery(id: emergencyAttempt.id)
        }
        let blockedAttempt = try #require(recoveryStore.failedAttempts.first)
        #expect(blockedAttempt.id == emergencyAttempt.id)
        #expect(blockedAttempt.audioFileURL == originalURL)
        #expect(blockedAttempt.reason == .recoveryOwnershipPersistenceFailed)
        #expect(blockedAttempt.canRetry == false)
        #expect(FileManager.default.fileExists(atPath: originalURL.path))
        let retainedCopies = try FileManager.default.contentsOfDirectory(
            at: recoveryURL,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "m4a" }
        #expect(retainedCopies.count == 1)
        #expect(FileManager.default.fileExists(atPath: retainedCopies[0].path))

        await controller.retryFailedTranscription(id: emergencyAttempt.id)
        #expect(transcriptionService.calls.isEmpty)

        try FileManager.default.removeItem(at: metadataURL)
        try FileManager.default.removeItem(at: markerURL)
        let relaunchedStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let relaunchedAttempt = try #require(relaunchedStore.failedAttempts.first)
        #expect(relaunchedAttempt.id == attemptID)
        #expect(relaunchedAttempt.completionKind == .maximumDuration)
        #expect(FileManager.default.fileExists(atPath: relaunchedAttempt.audioFileURL.path))
        #expect(TranscriptHistoryAudioPlaybackAction().canPlay(relaunchedAttempt))
        #expect(FileManager.default.fileExists(atPath: metadataURL.path))
        #expect(transcriptionService.calls.isEmpty)
    }

    @Test func providerDispatchSealFailureBlocksUploadUntilLocalRepair() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-controller-dispatch-seal-failure-\(UUID().uuidString)",
                isDirectory: true
            )
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = rootURL.appendingPathComponent("dispatch-seal.m4a")
        try Data("dispatch seal recording".utf8).write(to: sourceURL)
        let recoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let checkpoint = try recoveryStore.recordProcessingCheckpoint(
            audioFileURL: sourceURL,
            settings: .defaults,
            audioDuration: 300,
            completionKind: .maximumDuration
        )
        try recoveryStore.updateFailedAttempt(
            id: checkpoint.id,
            reason: .networkUnavailable
        )
        let dispatchMarkerURL = recoveryURL.appendingPathComponent(
            "ProviderDispatch-\(checkpoint.id.uuidString.lowercased()).json"
        )
        try FileManager.default.createDirectory(
            at: dispatchMarkerURL,
            withIntermediateDirectories: false
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Accepted after dispatch repair")
        )
        let controller = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore
        )

        await controller.retryFailedTranscription(id: checkpoint.id)
        #expect(transcriptionService.calls.isEmpty)
        let blockedAttempt = try #require(recoveryStore.failedAttempts.first)
        #expect(blockedAttempt.reason == .providerDispatchPersistenceFailed)
        #expect(blockedAttempt.canRetry == false)
        let blockedPresentation = TranscriptionRecoveryHistoryRowPresentation(
            attempt: blockedAttempt
        )
        #expect(blockedPresentation.showsRetry == false)
        #expect(blockedPresentation.showsSaveRetry)

        try FileManager.default.removeItem(at: dispatchMarkerURL)
        try recoveryStore.repairLocalRecovery(id: checkpoint.id)
        #expect(recoveryStore.failedAttempts.first?.canRetry == true)
        await controller.retryFailedTranscription(id: checkpoint.id)
        #expect(transcriptionService.calls.count == 1)
        #expect(recoveryStore.failedAttempts.first?.state == .saved)
        #expect(
            recoveryStore.failedAttempts.first?.acceptedTranscriptText
                == "Accepted after dispatch repair"
        )
    }

    @Test func providerSuccessWithDualMetadataFailureRelaunchesAsOutcomeUncertain() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-controller-provider-dual-write-failure-\(UUID().uuidString)",
                isDirectory: true
            )
        let cacheURL = rootURL.appendingPathComponent("Cache", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let attemptID = UUID(uuidString: "D9C6D531-C23C-4D7C-A0C0-976A9E289ED2")!
        let metadataURL = recoveryURL.appendingPathComponent("Recovery.json")
        let repairMarkerURL = recoveryURL.appendingPathComponent(
            "SavedStateRepair-\(attemptID.uuidString.lowercased()).json"
        )
        let originalURL = cacheURL.appendingPathComponent("dual-write.m4a")
        try Data("dual write recording".utf8).write(to: originalURL)
        let artifact = AudioRecordingArtifact(
            fileURL: originalURL,
            duration: 300,
            byteCount: 2_400_000
        )
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Accepted but metadata unavailable"),
            beforeResult: {
                try? FileManager.default.removeItem(at: metadataURL)
                try? FileManager.default.createDirectory(
                    at: metadataURL,
                    withIntermediateDirectories: false
                )
                try? FileManager.default.createDirectory(
                    at: repairMarkerURL,
                    withIntermediateDirectories: false
                )
            }
        )
        let recoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL,
            uuidProvider: { attemptID }
        )
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore,
            recordingCache: RecordingCacheService(
                directoryURL: cacheURL,
                legacyDirectoryURL: nil
            ),
            initialStatus: .recording
        )

        recorder.simulateAutomaticStop(
            .success(
                AudioRecorderAutomaticCompletion(
                    artifact: artifact,
                    reason: .maximumDuration
                )
            )
        )
        await yieldUntil { controller.status.voiceWorkPhase == .inactive }

        #expect(transcriptionService.calls.count == 1)
        let inMemoryAttempt = try #require(recoveryStore.failedAttempts.first)
        #expect(inMemoryAttempt.reason == .savedStatePersistenceFailed)
        #expect(inMemoryAttempt.acceptedTranscriptText == "Accepted but metadata unavailable")
        #expect(inMemoryAttempt.canRetry == false)

        let relaunchedStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let uncertainAttempt = try #require(relaunchedStore.failedAttempts.first)
        #expect(uncertainAttempt.id == attemptID)
        #expect(uncertainAttempt.reason == .providerOutcomeUncertain)
        #expect(uncertainAttempt.completionKind == .maximumDuration)
        #expect(uncertainAttempt.acceptedTranscriptText == nil)
        #expect(uncertainAttempt.canRetry == false)
        #expect(TranscriptHistoryAudioPlaybackAction().canPlay(uncertainAttempt))
        let uncertainPresentation = TranscriptionRecoveryHistoryRowPresentation(
            attempt: uncertainAttempt
        )
        #expect(uncertainPresentation.showsRetry == false)
        #expect(uncertainPresentation.showsSaveRetry == false)
        let duplicateProvider = FakeControllerTranscriptionService(
            result: .success("Must not repeat")
        )
        let relaunchedController = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: duplicateProvider,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: relaunchedStore
        )
        await relaunchedController.retryFailedTranscription(id: uncertainAttempt.id)
        #expect(duplicateProvider.calls.isEmpty)
    }

    @Test func maximumTranslationFailurePreservesRawAcceptedTextWithoutProviderRetry() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-controller-max-translation-failure-\(UUID().uuidString)",
                isDirectory: true
            )
        let cacheURL = rootURL.appendingPathComponent("Cache", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let originalURL = cacheURL.appendingPathComponent("translation-failure.m4a")
        try Data("maximum translation failure".utf8).write(to: originalURL)
        let artifact = AudioRecordingArtifact(
            fileURL: originalURL,
            duration: 300,
            byteCount: 2_400_000
        )
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .success(artifact),
            stopFinalizationReachedMaximumDuration: true
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("  русский текст \n")
        )
        let translationService = FakeTranslationService(
            result: .failure(.timedOut)
        )
        var settings = AppSettings.defaults
        settings.language = .russian
        settings.translationShortcutEnabled = true
        settings.translationTargetLanguage = .english
        let recoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            translationService: translationService,
            settings: settings,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore,
            recordingCache: RecordingCacheService(
                directoryURL: cacheURL,
                legacyDirectoryURL: nil
            ),
            initialStatus: .recording
        )

        await controller.performRecordingAction(intent: .translate)

        #expect(controller.status == .failure(message: "Translation timed out."))
        #expect(transcriptionService.calls.count == 1)
        #expect(translationService.calls.count == 1)
        let failClosedAttempt = try #require(recoveryStore.failedAttempts.first)
        #expect(failClosedAttempt.state == .failed)
        #expect(
            failClosedAttempt.reason
                == .postProcessingFailedAfterProviderAcceptance
        )
        #expect(failClosedAttempt.acceptedTranscriptText == "русский текст")
        #expect(failClosedAttempt.canRetry == false)
        #expect(TranscriptHistoryAudioPlaybackAction().canPlay(failClosedAttempt))
        let presentation = TranscriptionRecoveryHistoryRowPresentation(
            attempt: failClosedAttempt
        )
        #expect(
            presentation.title
                == "Raw transcription recovered — post-processing failed"
        )
        #expect(presentation.showsRetry == false)
        #expect(presentation.showsSaveRetry)
        #expect(presentation.saveRetryTitle == "Save Raw Transcription")

        await controller.retryFailedTranscription(id: failClosedAttempt.id)
        #expect(transcriptionService.calls.count == 1)

        let relaunchedStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let relaunchedAttempt = try #require(relaunchedStore.failedAttempts.first)
        #expect(
            relaunchedAttempt.reason
                == .postProcessingFailedAfterProviderAcceptance
        )
        #expect(relaunchedAttempt.acceptedTranscriptText == "русский текст")
        #expect(relaunchedAttempt.canRetry == false)
        try relaunchedStore.markSaved(
            id: relaunchedAttempt.id,
            acceptedTranscriptText: "русский текст"
        )
        let rawSavedAttempt = try #require(relaunchedStore.failedAttempts.first)
        #expect(rawSavedAttempt.state == .saved)
        #expect(
            rawSavedAttempt.reason
                == .postProcessingFailedAfterProviderAcceptance
        )
        let rawSavedPresentation = TranscriptionRecoveryHistoryRowPresentation(
            attempt: rawSavedAttempt
        )
        #expect(
            rawSavedPresentation.title
                == "Raw transcription saved — post-processing failed"
        )
        let duplicateProvider = FakeControllerTranscriptionService(
            result: .success("Must not repeat")
        )
        let relaunchedController = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: duplicateProvider,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: relaunchedStore
        )
        await relaunchedController.retryFailedTranscription(id: rawSavedAttempt.id)
        #expect(duplicateProvider.calls.isEmpty)
    }

    @Test func standardTranslationFailurePreservesRawAcceptedTextWithoutProviderRetry() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-controller-standard-translation-failure-\(UUID().uuidString)",
                isDirectory: true
            )
        let cacheURL = rootURL.appendingPathComponent("Cache", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let originalURL = cacheURL.appendingPathComponent("translation-failure.m4a")
        try Data("standard translation failure".utf8).write(to: originalURL)
        let artifact = AudioRecordingArtifact(
            fileURL: originalURL,
            duration: 19,
            byteCount: 152_000
        )
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .success(artifact)
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("  обычный сырой текст \n")
        )
        let translationService = FakeTranslationService(
            result: .failure(.timedOut)
        )
        var settings = AppSettings.defaults
        settings.language = .russian
        settings.translationShortcutEnabled = true
        settings.translationTargetLanguage = .english
        let recoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            translationService: translationService,
            settings: settings,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore,
            recordingCache: RecordingCacheService(
                directoryURL: cacheURL,
                legacyDirectoryURL: nil
            ),
            initialStatus: .recording
        )

        await controller.performRecordingAction(intent: .translate)

        #expect(controller.status == .failure(message: "Translation timed out."))
        #expect(transcriptionService.calls.count == 1)
        #expect(translationService.calls.count == 1)
        let failClosedAttempt = try #require(recoveryStore.failedAttempts.first)
        #expect(failClosedAttempt.completionKind == .standard)
        #expect(
            failClosedAttempt.reason
                == .postProcessingFailedAfterProviderAcceptance
        )
        #expect(failClosedAttempt.acceptedTranscriptText == "обычный сырой текст")
        #expect(failClosedAttempt.canRetry == false)
        #expect(TranscriptHistoryAudioPlaybackAction().canPlay(failClosedAttempt))

        await controller.retryFailedTranscription(id: failClosedAttempt.id)
        #expect(transcriptionService.calls.count == 1)

        let relaunchedStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let relaunchedAttempt = try #require(relaunchedStore.failedAttempts.first)
        #expect(relaunchedAttempt.completionKind == .standard)
        #expect(
            relaunchedAttempt.reason
                == .postProcessingFailedAfterProviderAcceptance
        )
        #expect(relaunchedAttempt.acceptedTranscriptText == "обычный сырой текст")
        #expect(relaunchedAttempt.canRetry == false)
        try relaunchedStore.markSaved(
            id: relaunchedAttempt.id,
            acceptedTranscriptText: "обычный сырой текст"
        )
        let rawSavedAttempt = try #require(relaunchedStore.failedAttempts.first)
        #expect(rawSavedAttempt.state == .saved)
        #expect(
            rawSavedAttempt.reason
                == .postProcessingFailedAfterProviderAcceptance
        )
        let duplicateProvider = FakeControllerTranscriptionService(
            result: .success("Must not repeat")
        )
        let relaunchedController = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: duplicateProvider,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: relaunchedStore
        )
        await relaunchedController.retryFailedTranscription(id: rawSavedAttempt.id)
        #expect(duplicateProvider.calls.isEmpty)
    }

    @Test func standardRetryPostProcessingFailureDoesNotReuploadProviderAudio() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-controller-standard-retry-postprocess-\(UUID().uuidString)",
                isDirectory: true
            )
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = rootURL.appendingPathComponent("retry-source.m4a")
        try Data("standard retry recording".utf8).write(to: sourceURL)
        let recoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let failedAttempt = try #require(
            try recoveryStore.recordFailedAttempt(
                audioFileURL: sourceURL,
                settings: .defaults,
                audioDuration: 24,
                reason: .networkUnavailable
            )
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Raw retry transcript")
        )
        let textCorrectionService = FakeTextCorrectionService(
            result: .success(" \n ")
        )
        let controller = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: transcriptionService,
            textCorrectionService: textCorrectionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore
        )

        await controller.retryFailedTranscription(id: failedAttempt.id)

        #expect(transcriptionService.calls.count == 1)
        let failClosedAttempt = try #require(recoveryStore.failedAttempts.first)
        #expect(failClosedAttempt.completionKind == .standard)
        #expect(
            failClosedAttempt.reason
                == .postProcessingFailedAfterProviderAcceptance
        )
        #expect(failClosedAttempt.acceptedTranscriptText == "Raw retry transcript")
        #expect(failClosedAttempt.canRetry == false)

        await controller.retryFailedTranscription(id: failClosedAttempt.id)
        #expect(transcriptionService.calls.count == 1)

        let relaunchedStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let relaunchedAttempt = try #require(relaunchedStore.failedAttempts.first)
        #expect(relaunchedAttempt.completionKind == .standard)
        #expect(
            relaunchedAttempt.reason
                == .postProcessingFailedAfterProviderAcceptance
        )
        #expect(relaunchedAttempt.acceptedTranscriptText == "Raw retry transcript")
        #expect(relaunchedAttempt.canRetry == false)
        let duplicateProvider = FakeControllerTranscriptionService(
            result: .success("Must not repeat")
        )
        let relaunchedController = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: duplicateProvider,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: relaunchedStore
        )
        await relaunchedController.retryFailedTranscription(id: relaunchedAttempt.id)
        #expect(duplicateProvider.calls.isEmpty)
    }

    @Test func standardSuccessfulTranscriptionRemovesRecoveryAudioAndMarkers() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-controller-standard-success-cleanup-\(UUID().uuidString)",
                isDirectory: true
            )
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = rootURL.appendingPathComponent("standard-success.m4a")
        try Data("standard successful recording".utf8).write(to: sourceURL)
        let artifact = AudioRecordingArtifact(
            fileURL: sourceURL,
            duration: 21,
            byteCount: 168_000
        )
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .success(artifact)
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Completed standard transcript")
        )
        let recoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(
            controller.status
                == .success(transcript: "Completed standard transcript")
        )
        #expect(transcriptionService.calls.count == 1)
        #expect(recoveryStore.failedAttempts.isEmpty)
        let remainingNames = try FileManager.default.contentsOfDirectory(
            atPath: recoveryURL.path
        )
        #expect(remainingNames.allSatisfy { $0 == "Recovery.json" })
        let relaunchedStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        #expect(relaunchedStore.failedAttempts.isEmpty)
    }

    @Test func localRequestValidationFailureRemainsRetryableAcrossRelaunch() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-controller-local-validation-relaunch-\(UUID().uuidString)",
                isDirectory: true
            )
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = rootURL.appendingPathComponent("invalid-request.m4a")
        try Data("locally invalid request recording".utf8).write(to: sourceURL)
        let artifact = AudioRecordingArtifact(
            fileURL: sourceURL,
            duration: 17,
            byteCount: 136_000
        )
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .success(artifact)
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Must not be called")
        )
        var settings = AppSettings.defaults
        settings.language = .custom
        settings.customLanguageCode = "en-US"
        let recoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(transcriptionService.calls.isEmpty)
        let localFailure = try #require(recoveryStore.failedAttempts.first)
        #expect(localFailure.completionKind == .standard)
        #expect(localFailure.reason == .invalidRequest)
        #expect(localFailure.canRetry)
        let relaunchedStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let relaunchedAttempt = try #require(relaunchedStore.failedAttempts.first)
        #expect(relaunchedAttempt.id == localFailure.id)
        #expect(relaunchedAttempt.reason == .invalidRequest)
        #expect(relaunchedAttempt.canRetry)
    }

    @Test func maximumFilenameSurvivesCheckpointAndMarkerFailureThenRetryRetainsAudio() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-controller-max-checkpoint-relaunch-\(UUID().uuidString)",
                isDirectory: true
            )
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: recoveryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let metadataURL = recoveryURL.appendingPathComponent("Recovery.json")
        try FileManager.default.createDirectory(
            at: metadataURL,
            withIntermediateDirectories: false
        )
        let sourceURL = rootURL.appendingPathComponent("checkpoint-relaunch-source.m4a")
        try Data("checkpoint relaunch recording".utf8).write(to: sourceURL)
        let attemptID = UUID(uuidString: "D9C6D531-C23C-4D7C-A0C0-976A9E289ED2")!
        try FileManager.default.createDirectory(
            at: recoveryURL.appendingPathComponent(
                "ProcessingCheckpoint-\(attemptID.uuidString.lowercased()).json"
            ),
            withIntermediateDirectories: false
        )
        let firstStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL,
            uuidProvider: { attemptID }
        )
        #expect(throws: TranscriptionFailureRecoveryError.saveFailed) {
            try firstStore.recordProcessingCheckpoint(
                audioFileURL: sourceURL,
                settings: .defaults,
                audioDuration: 300,
                completionKind: .maximumDuration
            )
        }

        let restoredStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let restoredAttempt = try #require(restoredStore.failedAttempts.first)
        #expect(restoredAttempt.id == attemptID)
        #expect(restoredAttempt.state == .failed)
        #expect(restoredAttempt.reason == .processingInterrupted)
        #expect(restoredAttempt.completionKind == .maximumDuration)
        #expect(restoredAttempt.canRetry)
        #expect(FileManager.default.fileExists(atPath: restoredAttempt.audioFileURL.path))

        try FileManager.default.removeItem(at: metadataURL)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Recovered max checkpoint")
        )
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        let retryController = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptHistory: transcriptHistory,
            transcriptionFailureRecovery: restoredStore
        )

        await retryController.retryFailedTranscription(id: restoredAttempt.id)

        #expect(transcriptionService.calls.count == 1)
        #expect(transcriptHistory.calls.isEmpty)
        let savedAttempt = try #require(restoredStore.failedAttempts.first)
        #expect(savedAttempt.id == restoredAttempt.id)
        #expect(savedAttempt.state == .saved)
        #expect(savedAttempt.completionKind == .maximumDuration)
        #expect(savedAttempt.acceptedTranscriptText == "Recovered max checkpoint")
        #expect(savedAttempt.canRetry == false)
        #expect(FileManager.default.fileExists(atPath: savedAttempt.audioFileURL.path))
        #expect(TranscriptHistoryAudioPlaybackAction().canPlay(savedAttempt))

        await retryController.retryFailedTranscription(id: restoredAttempt.id)
        #expect(transcriptionService.calls.count == 1)
    }

    @Test func failedMaximumAttemptSurvivesRelaunchAndRetrySuccessRemainsSaved() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("holdtype-controller-max-retry-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("Cache", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let originalURL = cacheURL.appendingPathComponent("HoldType-max-retry.m4a")
        try Data("maximum retry recording".utf8).write(to: originalURL)
        let artifact = AudioRecordingArtifact(
            fileURL: originalURL,
            duration: 300,
            byteCount: 2_400_000
        )
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let firstTranscriptionService = FakeControllerTranscriptionService(
            result: .failure(.providerUnavailable)
        )
        let firstRecoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let firstController = makeController(
            recorder: recorder,
            transcriptionService: firstTranscriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: firstRecoveryStore,
            recordingCache: RecordingCacheService(
                directoryURL: cacheURL,
                legacyDirectoryURL: nil
            ),
            initialStatus: .recording
        )

        recorder.simulateAutomaticStop(
            .success(
                AudioRecorderAutomaticCompletion(
                    artifact: artifact,
                    reason: .maximumDuration
                )
            )
        )
        await yieldUntil { firstController.status.voiceWorkPhase == .inactive }

        #expect(firstTranscriptionService.calls.count == 1)
        let failedAttempt = try #require(firstRecoveryStore.failedAttempts.first)
        #expect(failedAttempt.state == .failed)
        #expect(failedAttempt.reason == .providerUnavailable)
        #expect(failedAttempt.completionKind == .maximumDuration)
        #expect(FileManager.default.fileExists(atPath: failedAttempt.audioFileURL.path))
        #expect(FileManager.default.fileExists(atPath: originalURL.path) == false)

        let restoredRecoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let restoredAttempt = try #require(restoredRecoveryStore.failedAttempts.first)
        #expect(restoredAttempt.id == failedAttempt.id)
        #expect(restoredAttempt.completionKind == .maximumDuration)
        #expect(restoredAttempt.state == .failed)
        let retryTranscriptionService = FakeControllerTranscriptionService(
            result: .success("Recovered after relaunch")
        )
        let retryHistory = FakeTranscriptRecoveryHistory()
        let retryController = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: retryTranscriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptHistory: retryHistory,
            transcriptionFailureRecovery: restoredRecoveryStore
        )

        await retryController.retryFailedTranscription(id: restoredAttempt.id)

        #expect(retryController.status == .success(transcript: "Recovered after relaunch"))
        #expect(retryTranscriptionService.calls.count == 1)
        #expect(retryHistory.calls.isEmpty)
        let savedAttempt = try #require(restoredRecoveryStore.failedAttempts.first)
        #expect(savedAttempt.id == restoredAttempt.id)
        #expect(savedAttempt.state == .saved)
        #expect(savedAttempt.completionKind == .maximumDuration)
        #expect(savedAttempt.acceptedTranscriptText == "Recovered after relaunch")
        #expect(savedAttempt.canRetry == false)
        #expect(FileManager.default.fileExists(atPath: savedAttempt.audioFileURL.path))
        #expect(TranscriptHistoryAudioPlaybackAction().canPlay(savedAttempt))
    }

    @Test func unexpectedRecorderCompletionSavesWithoutProviderDispatch() async throws {
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-controller-unexpected-stop.m4a"),
            duration: 28,
            byteCount: 220_000
        )
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Unexpected completion transcript")
        )
        let cuePlayer = FakeDictationCuePlayer()
        let eventLogger = FakeDictationEventLogger()
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            cuePlayer: cuePlayer,
            transcriptionFailureRecovery: failureRecovery,
            eventLogger: eventLogger,
            initialStatus: .recording
        )
        var outputStatusChanges: [String?] = []
        controller.outputStatusTextDidChange = { outputStatusChanges.append($0) }

        recorder.simulateAutomaticStop(
            .success(
                AudioRecorderAutomaticCompletion(
                    artifact: artifact,
                    reason: .unexpected(recorderReportedSuccess: false)
                )
            )
        )
        await yieldUntil { controller.status.voiceWorkPhase == .inactive }

        #expect(controller.status == .failure(message: "Recording ended unexpectedly."))
        #expect(recorder.stopCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(cuePlayer.playedCues == [.stopRecording])
        #expect(
            eventLogger.events.filter {
                $0 == .recordingEndedUnexpectedly(recorderReportedSuccess: false)
            }.count == 1
        )
        #expect(eventLogger.events.contains(.recordingLimitReached) == false)
        let retainedAttempt = try #require(failureRecovery.failedAttempts.first)
        #expect(retainedAttempt.reason == .processingInterrupted)
        #expect(retainedAttempt.canRetry)
        #expect(
            eventLogger.events.contains(
                .recordingTerminal(
                    cause: .platformInterrupted,
                    attemptID: retainedAttempt.id,
                    durability: .historyCheckpoint,
                    providerAuthorized: false
                )
            )
        )
        let savingStatusIndex = outputStatusChanges.firstIndex(
            of: "Recording ended unexpectedly. Saving recording..."
        )
        let savedStatusIndex = outputStatusChanges.firstIndex(
            of: "Recording interrupted — saved to History."
        )
        #expect(savingStatusIndex != nil)
        #expect(savedStatusIndex != nil)
        if let savingStatusIndex, let savedStatusIndex {
            #expect(savingStatusIndex < savedStatusIndex)
        }
    }

    @Test func userFinishAuthoritySurvivesRacingUnexpectedRecorderCallback() async throws {
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-user-finish-unexpected-race.m4a"),
            duration: 12,
            byteCount: 96_000
        )
        let stopGate = ControllerAsyncGate()
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .success(artifact),
            beforeStop: { await stopGate.wait() }
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("User-owned finish transcript")
        )
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let eventLogger = FakeDictationEventLogger()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: failureRecovery,
            eventLogger: eventLogger,
            initialStatus: .recording
        )

        let finishTask = Task { @MainActor in
            await controller.performRecordingAction()
        }
        await yieldUntil { recorder.stopCount == 1 }
        recorder.simulateAutomaticStop(
            .success(
                AudioRecorderAutomaticCompletion(
                    artifact: artifact,
                    reason: .unexpected(recorderReportedSuccess: false)
                )
            )
        )
        await stopGate.open()
        await finishTask.value

        #expect(controller.status == .success(transcript: "User-owned finish transcript"))
        #expect(transcriptionService.calls.count == 1)
        #expect(failureRecovery.failedAttempts.isEmpty)
        let terminalEvents = eventLogger.events.compactMap { event -> DictationLogEvent? in
            if case .recordingTerminal = event { return event }
            return nil
        }
        #expect(terminalEvents.count == 1)
        let terminalEvent = try #require(terminalEvents.first)
        guard case .recordingTerminal(
            cause: .userFinished,
            attemptID: _,
            durability: .historyCheckpoint,
            providerAuthorized: true
        ) = terminalEvent else {
            Issue.record("Expected one user-finished terminal event")
            return
        }
    }

    @Test func automaticServiceBoundaryWinningBeforeKeyUpRemainsProviderFree() async throws {
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-joined-unexpected-stop.m4a"),
            duration: 18,
            byteCount: 144_000
        )
        let completion = AudioRecorderAutomaticCompletion(
            artifact: artifact,
            reason: .unexpected(recorderReportedSuccess: false),
            recorderReportedSuccess: false
        )
        let recorder = JoinedAutomaticStopRecorder(completion: completion)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Must not be dispatched")
        )
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let eventLogger = FakeDictationEventLogger()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: failureRecovery,
            eventLogger: eventLogger,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(controller.status == .failure(message: "Recording ended unexpectedly."))
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls.isEmpty)
        let retainedAttempt = try #require(failureRecovery.failedAttempts.first)
        #expect(retainedAttempt.reason == .processingInterrupted)
        #expect(
            eventLogger.events.contains(
                .recordingTerminal(
                    cause: .platformInterrupted,
                    attemptID: retainedAttempt.id,
                    durability: .historyCheckpoint,
                    providerAuthorized: false
                )
            )
        )
    }

    @Test func unsuccessfulRecorderCallbackAtLimitStillRetainsSavedPlayableRecording() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-controller-false-callback-at-limit-\(UUID().uuidString)",
                isDirectory: true
            )
        let cacheURL = rootURL.appendingPathComponent("Cache", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let originalURL = cacheURL.appendingPathComponent("false-at-limit.m4a")
        try Data("five minute callback anomaly".utf8).write(to: originalURL)
        let artifact = AudioRecordingArtifact(
            fileURL: originalURL,
            duration: 300,
            byteCount: 2_400_000
        )
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Maximum transcript despite false callback")
        )
        let cuePlayer = FakeDictationCuePlayer()
        let eventLogger = FakeDictationEventLogger()
        let recoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            cuePlayer: cuePlayer,
            transcriptHistory: transcriptHistory,
            transcriptionFailureRecovery: recoveryStore,
            recordingCache: RecordingCacheService(
                directoryURL: cacheURL,
                legacyDirectoryURL: nil
            ),
            eventLogger: eventLogger,
            initialStatus: .recording
        )

        recorder.simulateAutomaticStop(
            .success(
                AudioRecorderAutomaticCompletion(
                    artifact: artifact,
                    reason: .unexpected(recorderReportedSuccess: false)
                )
            )
        )
        await yieldUntil { controller.status.voiceWorkPhase == .inactive }

        #expect(
            controller.status == .success(
                transcript: "Maximum transcript despite false callback"
            )
        )
        #expect(transcriptionService.calls.count == 1)
        #expect(cuePlayer.playedCues == [.recordingLimitReached])
        #expect(
            eventLogger.events.contains(
                .recordingEndedUnexpectedly(recorderReportedSuccess: false)
            )
        )
        #expect(eventLogger.events.contains(.recordingLimitReached))
        #expect(transcriptHistory.calls.isEmpty)
        let savedAttempt = try #require(recoveryStore.failedAttempts.first)
        #expect(savedAttempt.state == .saved)
        #expect(savedAttempt.completionKind == .maximumDuration)
        #expect(
            savedAttempt.acceptedTranscriptText
                == "Maximum transcript despite false callback"
        )
        #expect(savedAttempt.canRetry == false)
        #expect(FileManager.default.fileExists(atPath: savedAttempt.audioFileURL.path))
        #expect(TranscriptHistoryAudioPlaybackAction().canPlay(savedAttempt))
        #expect(FileManager.default.fileExists(atPath: originalURL.path) == false)
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
                    model: settings.resolvedTranscriptionModel,
                    languageCode: settings.resolvedLanguageCode,
                    promptComposition: settings.transcriptionPromptComposition(context: context)
                )
            ]
        )
    }

    @Test func invalidCustomLanguageRequestUsesExistingInvalidRecordingFailure() async {
        let transcriptionService = FakeControllerTranscriptionService()
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let eventLogger = FakeDictationEventLogger()
        var settings = AppSettings.defaults
        settings.language = .custom
        settings.customLanguageCode = "en-US"
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .recording),
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: failureRecovery,
            eventLogger: eventLogger,
            initialStatus: .recording,
            lastTranscriptText: "previous transcript"
        )

        await controller.performRecordingAction()

        #expect(
            controller.status == .failure(
                message: "Use a two- or three-letter custom language code."
            )
        )
        #expect(controller.lastTranscriptText == "previous transcript")
        #expect(controller.failurePresentation?.settingsTarget == .transcription)
        #expect(controller.failurePresentation?.canRetry == true)
        #expect(transcriptionService.calls.isEmpty)
        #expect(failureRecovery.failedAttempts.count == 1)
        #expect(failureRecovery.failedAttempts.first?.reason == .invalidRequest)
        #expect(
            attemptStageFailureEvents(in: eventLogger.events) == [
                .transcriptionFailed(category: "invalid_language_code")
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
        settings.transcriptionModel = " history-model "
        settings.language = .custom
        settings.customLanguageCode = " EN "
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

        let historyRequest = transcriptHistory.calls.first
        #expect(historyRequest?.acceptedTranscript.text == "History cache transcript")
        #expect(historyRequest?.transcriptionModel == "history-model")
        #expect(historyRequest?.languageCode == "en")
        #expect(historyRequest?.audioDuration == 2)
        #expect(historyRequest?.cachedAudioFileURL == artifact.fileURL)
        #expect(historyRequest?.historyEnabled == true)
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
                message: "The failed recording could not be saved for retry."
            )
        )
        #expect(controller.outputStatusText == "The failed recording could not be saved for retry.")
        #expect(controller.failurePresentation?.failedAttemptID != nil)
        #expect(controller.voiceAttemptOutcome == .recoverableFailure)
        #expect(failureRecovery.failedAttempts.count == 1)
        #expect(failureRecovery.failedAttempts.first?.audioFileURL == artifact.fileURL)
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
        #expect(
            textCorrectionService.calls == [
                TextCorrectionCall(
                    transcript: "raw transcript",
                    correctionConfiguration: AppSettings.defaults.textCorrectionConfiguration,
                    postProcessingConfiguration: AppSettings.defaults.transcriptPostProcessingConfiguration
                )
            ]
        )
        #expect(
            transcriptOutput.calls == [
                TranscriptOutputCall(
                    transcript: "corrected transcript",
                    preferences: AppSettings.defaults.outputDeliveryPreferences
                )
            ]
        )
        #expect(transcriptHistory.entries.map(\.transcriptText) == ["corrected transcript"])
        #expect(transcriptHistory.calls.map(\.acceptedTranscript.text) == ["corrected transcript"])
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
        #expect(
            transcriptOutput.calls == [
                TranscriptOutputCall(
                    transcript: "raw transcript",
                    preferences: AppSettings.defaults.outputDeliveryPreferences
                )
            ]
        )
        #expect(usageRecorder.calls.map(\.model) == ["gpt-4o-transcribe"])
        #expect(usageRecorder.calls.map(\.audioDuration) == [1.2])
    }

    @Test func historyFailurePreservesRecoveryOwnerWithoutDuplicatingProviderUsage() async throws {
        let rootURL = try makeTemporaryControllerDirectory(prefix: "history-append-failure")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let sourceURL = rootURL.appendingPathComponent("accepted-source.m4a")
        try Data("accepted audio remains recoverable".utf8).write(to: sourceURL)
        let artifact = AudioRecordingArtifact(
            fileURL: sourceURL,
            duration: 1.2,
            byteCount: 34
        )
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        let failureRecovery = TranscriptionFailureRecoveryStore(directoryURL: recoveryURL)
        let transcriptHistory = FakeTranscriptRecoveryHistory(
            recordError: FakeTranscriptRecoveryHistoryError.saveFailed
        )
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: FakeAudioRecorderService(
                currentStatus: .recording,
                stopResult: .success(artifact)
            ),
            transcriptionService: FakeControllerTranscriptionService(result: .success(" accepted text ")),
            transcriptOutput: transcriptOutput,
            transcriptHistory: transcriptHistory,
            transcriptionFailureRecovery: failureRecovery,
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
        #expect(
            controller.outputStatusText
                == "Text was accepted, but History could not save it. The recording remains in Saved Recordings."
        )
        let retainedAttempt = try #require(failureRecovery.failedAttempts.first)
        #expect(retainedAttempt.state == .failed)
        #expect(retainedAttempt.reason == .savedStatePersistenceFailed)
        #expect(retainedAttempt.acceptedTranscriptText == "accepted text")
        #expect(retainedAttempt.canRetry == false)
        #expect(retainedAttempt.canDelete)
        #expect(FileManager.default.fileExists(atPath: retainedAttempt.audioFileURL.path))

        let reloadedRecovery = TranscriptionFailureRecoveryStore(directoryURL: recoveryURL)
        let reloadedAttempt = try #require(reloadedRecovery.failedAttempts.first)
        #expect(reloadedAttempt.id == retainedAttempt.id)
        #expect(reloadedAttempt.acceptedTranscriptText == "accepted text")
        #expect(FileManager.default.fileExists(atPath: reloadedAttempt.audioFileURL.path))
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
        #expect(transcriptionService.calls.map(\.languageCode) == ["es"])
        #expect(
            textCorrectionService.calls == [
                TextCorrectionCall(
                    transcript: "texto español sin corregir",
                    correctionConfiguration: settings.textCorrectionConfiguration,
                    postProcessingConfiguration: settings.transcriptPostProcessingConfiguration
                )
            ]
        )
        #expect(
            translationService.calls == [
                TranslationCall(
                    transcript: "texto español corregido",
                    translationConfiguration: settings.translationConfiguration,
                    resolvedSourceLanguageCode: "es"
                )
            ]
        )
        #expect(
            transcriptOutput.calls == [
                TranscriptOutputCall(
                    transcript: "Corrected English text",
                    preferences: settings.outputDeliveryPreferences
                )
            ]
        )
        #expect(transcriptHistory.entries.map(\.transcriptText) == ["Corrected English text"])
        #expect(transcriptHistory.calls.map(\.acceptedTranscript.text) == ["Corrected English text"])
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
                TranslationCall(
                    transcript: "texto español corregido",
                    translationConfiguration: settings.translationConfiguration,
                    resolvedSourceLanguageCode: "es"
                )
            ]
        )
        #expect(
            transcriptOutput.calls == [
                TranscriptOutputCall(
                    transcript: "\"Corrected\" - English... emoji smile",
                    preferences: settings.outputDeliveryPreferences
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
        #expect(transcriptionService.calls.map(\.languageCode) == ["es"])
        #expect(
            translationService.calls == [
                TranslationCall(
                    transcript: "texto español",
                    translationConfiguration: settings.translationConfiguration,
                    resolvedSourceLanguageCode: "es"
                )
            ]
        )
        #expect(
            transcriptOutput.calls == [
                TranscriptOutputCall(
                    transcript: "English text",
                    preferences: settings.outputDeliveryPreferences
                )
            ]
        )
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
        #expect(
            translationService.calls == [
                TranslationCall(
                    transcript: "русский текст",
                    translationConfiguration: settings.translationConfiguration,
                    resolvedSourceLanguageCode: "ru"
                )
            ]
        )
        #expect(
            transcriptOutput.calls == [
                TranscriptOutputCall(
                    transcript: "English text",
                    preferences: settings.outputDeliveryPreferences
                )
            ]
        )
    }

    @Test func translationIntentFailsBeforeTranscriptionWhenTargetLanguageIsMissing() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("  normal transcript \n")
        )
        let translationService = FakeTranslationService(result: .success("Unexpected translation"))
        let transcriptOutput = FakeTranscriptOutput()
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let eventLogger = FakeDictationEventLogger()
        var settings = AppSettings.defaults
        settings.language = .automatic
        settings.translationShortcutEnabled = true
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            translationService: translationService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            transcriptionFailureRecovery: failureRecovery,
            transcriptionUsageRecorder: usageRecorder,
            eventLogger: eventLogger,
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
        #expect(failureRecovery.failedAttempts.count == 1)
        #expect(failureRecovery.failedAttempts.first?.reason == .other)
        #expect(
            attemptStageFailureEvents(in: eventLogger.events) == [
                .postProcessingFailed(category: "missing_translation_target_language")
            ]
        )
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
        #expect(
            transcriptOutput.calls == [
                TranscriptOutputCall(
                    transcript: "русский текст",
                    preferences: settings.outputDeliveryPreferences
                )
            ]
        )
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
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let eventLogger = FakeDictationEventLogger()
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
            transcriptionFailureRecovery: failureRecovery,
            transcriptionUsageRecorder: usageRecorder,
            transcriptionIDGenerator: { transcriptionID },
            eventLogger: eventLogger,
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
                TranslationCall(
                    transcript: "русский текст",
                    translationConfiguration: settings.translationConfiguration,
                    resolvedSourceLanguageCode: "ru"
                )
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
        #expect(failureRecovery.failedAttempts.count == 1)
        #expect(failureRecovery.failedAttempts.first?.reason == .other)
        #expect(
            attemptStageFailureEvents(in: eventLogger.events) == [
                .postProcessingFailed(category: "timeout")
            ]
        )
    }

    @Test func emptyTranslationFailsWithoutPublishingUntranslatedText() async {
        let translationService = FakeTranslationService(result: .success(" \n "))
        let transcriptOutput = FakeTranscriptOutput()
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        let usageRecorder = FakeTranscriptionUsageRecorder()
        var settings = AppSettings.defaults
        settings.language = .russian
        settings.translationTargetLanguage = .english
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .recording),
            transcriptionService: FakeControllerTranscriptionService(
                result: .success(" исходный текст ")
            ),
            translationService: translationService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            transcriptHistory: transcriptHistory,
            transcriptionUsageRecorder: usageRecorder,
            initialStatus: .recording,
            lastTranscriptText: "previous accepted transcript"
        )

        await controller.performRecordingAction(intent: .translate)

        #expect(controller.status == .failure(message: "Translation returned no usable text."))
        #expect(controller.lastTranscriptText == "previous accepted transcript")
        #expect(translationService.calls.count == 1)
        #expect(usageRecorder.calls.count == 1)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(transcriptHistory.entries.isEmpty)
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
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let eventLogger = FakeDictationEventLogger()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptionFailureRecovery: failureRecovery,
            eventLogger: eventLogger,
            initialStatus: .recording,
            lastTranscriptText: "previous transcript",
            outputStatusText: "Previous output status"
        )

        controller.cancelRecording()

        #expect(controller.status == .idle)
        #expect(controller.voiceAttemptOutcome == nil)
        #expect(controller.lastTranscriptText == "previous transcript")
        #expect(controller.outputStatusText == nil)
        #expect(recorder.cancelCount == 1)
        #expect(recorder.stopCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(failureRecovery.failedAttempts.isEmpty)
        #expect(attemptStageFailureEvents(in: eventLogger.events).isEmpty)
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
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let eventLogger = FakeDictationEventLogger()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptionFailureRecovery: failureRecovery,
            transcriptionUsageRecorder: usageRecorder,
            eventLogger: eventLogger,
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
        #expect(controller.voiceAttemptOutcome == nil)

        controller.cancelRecording()

        #expect(controller.status == .idle)
        #expect(controller.voiceAttemptOutcome == nil)
        #expect(controller.lastTranscriptText == "previous accepted transcript")
        #expect(controller.outputStatusText == nil)
        #expect(transcriptionService.cancelCount == 1)

        await gate.open()
        await stopTask.value

        #expect(controller.status == .idle)
        #expect(controller.voiceAttemptOutcome == nil)
        #expect(controller.lastTranscriptText == "previous accepted transcript")
        #expect(controller.outputStatusText == nil)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(usageRecorder.calls.isEmpty)
        #expect(failureRecovery.failedAttempts.count == 1)
        #expect(
            failureRecovery.failedAttempts.first?.reason
                == .providerOutcomeUncertain
        )
        #expect(attemptStageFailureEvents(in: eventLogger.events).isEmpty)
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

    @Test func cancelDuringTranslationKeepsUsageAndDiscardsLateResult() async {
        let gate = ControllerAsyncGate()
        let translationService = FakeTranslationService(
            result: .success("late translation"),
            beforeResult: {
                await gate.wait()
            }
        )
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let transcriptOutput = FakeTranscriptOutput()
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        var settings = AppSettings.defaults
        settings.language = .russian
        settings.translationTargetLanguage = .english
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .recording),
            transcriptionService: FakeControllerTranscriptionService(
                result: .success(" исходный текст ")
            ),
            translationService: translationService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            transcriptHistory: transcriptHistory,
            transcriptionUsageRecorder: usageRecorder,
            initialStatus: .recording,
            lastTranscriptText: "previous accepted transcript"
        )

        let stopTask = Task { @MainActor in
            await controller.performRecordingAction(intent: .translate)
        }
        await yieldUntil {
            usageRecorder.calls.count == 1 && translationService.calls.count == 1
        }

        controller.cancelRecording()

        #expect(controller.status == .idle)
        #expect(controller.lastTranscriptText == "previous accepted transcript")
        #expect(usageRecorder.calls.count == 1)
        #expect(translationService.cancelCount == 1)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(transcriptHistory.entries.isEmpty)

        await gate.open()
        await stopTask.value

        #expect(controller.status == .idle)
        #expect(controller.lastTranscriptText == "previous accepted transcript")
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

    @Test func startFailureAfterPositiveWriteIsRecoveredWithoutProviderWork() async throws {
        let rootURL = try makeTemporaryControllerDirectory(prefix: "start-salvage")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let activeURL = rootURL.appendingPathComponent("Active", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("Cache", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        let contents = Data("microphone wrote before start failed".utf8)
        let recorder = PreparedCaptureRecorder(
            contents: contents,
            startErrorAfterWrite: .startFailed
        )
        let recoveryStore = TranscriptionFailureRecoveryStore(directoryURL: recoveryURL)
        let transcriptionService = FakeControllerTranscriptionService()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore,
            recordingCaptureJournal: RecordingCaptureJournal(
                directoryURL: activeURL,
                releasedDirectoryURL: cacheURL
            )
        )

        await controller.performRecordingAction()

        #expect(controller.status == .failure(message: "Could not start microphone recording."))
        #expect(controller.outputStatusText == "Recording interrupted — saved to History.")
        #expect(transcriptionService.calls.isEmpty)
        let attempt = try #require(recoveryStore.failedAttempts.first)
        #expect(attempt.state == .failed)
        #expect(attempt.reason == .processingInterrupted)
        #expect(try Data(contentsOf: attempt.audioFileURL) == contents)
        #expect(try protectedCaptureURLs(in: activeURL).isEmpty)
    }

    @Test func stopFailureAfterPositiveWriteIsRecoveredWithoutProviderWork() async throws {
        let rootURL = try makeTemporaryControllerDirectory(prefix: "stop-salvage")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let activeURL = rootURL.appendingPathComponent("Active", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("Cache", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        let contents = Data("finalization failed after useful audio".utf8)
        let recorder = PreparedCaptureRecorder(
            contents: contents,
            stopError: .stopFailed
        )
        let recoveryStore = TranscriptionFailureRecoveryStore(directoryURL: recoveryURL)
        let transcriptionService = FakeControllerTranscriptionService()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore,
            recordingCaptureJournal: RecordingCaptureJournal(
                directoryURL: activeURL,
                releasedDirectoryURL: cacheURL
            )
        )

        await controller.performRecordingAction()
        await controller.performRecordingAction()

        #expect(controller.status == .failure(message: "Could not finish the current recording."))
        #expect(controller.outputStatusText == "Recording interrupted — saved to History.")
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls.isEmpty)
        let attempt = try #require(recoveryStore.failedAttempts.first)
        #expect(attempt.reason == .processingInterrupted)
        #expect(try Data(contentsOf: attempt.audioFileURL) == contents)
        #expect(try protectedCaptureURLs(in: activeURL).isEmpty)
    }

    @Test func checkpointWriteFailureConsumesOwnedFallbackAndRetiresCapture() async throws {
        let rootURL = try makeTemporaryControllerDirectory(prefix: "checkpoint-salvage")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let activeURL = rootURL.appendingPathComponent("Active", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("Cache", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        let contents = Data("checkpoint persistence failure audio".utf8)
        let recorder = PreparedCaptureRecorder(contents: contents)
        let recoveryStore = CheckpointPersistenceFailureRecovery(
            directoryURL: recoveryURL
        )
        let transcriptionService = FakeControllerTranscriptionService()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore,
            recordingCaptureJournal: RecordingCaptureJournal(
                directoryURL: activeURL,
                releasedDirectoryURL: cacheURL
            )
        )

        await controller.performRecordingAction()
        await controller.performRecordingAction()

        #expect(controller.outputStatusText == "Recording interrupted — saved to History.")
        #expect(transcriptionService.calls.isEmpty)
        #expect(recoveryStore.checkpointCallCount == 1)
        #expect(recoveryStore.fallbackCallCount == 1)
        let attempt = try #require(recoveryStore.failedAttempts.first)
        #expect(attempt.reason == .recoveryOwnershipPersistenceFailed)
        #expect(try Data(contentsOf: attempt.audioFileURL) == contents)
        #expect(try protectedCaptureURLs(in: activeURL).isEmpty)
    }

    @Test func startFailureCheckpointWriteFailureRetiresFallbackOwnedCapture() async throws {
        let rootURL = try makeTemporaryControllerDirectory(prefix: "start-checkpoint-salvage")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let activeURL = rootURL.appendingPathComponent("Active", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("Cache", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        let contents = Data("start failure checkpoint fallback audio".utf8)
        let recorder = PreparedCaptureRecorder(
            contents: contents,
            startErrorAfterWrite: .startFailed
        )
        let recoveryStore = CheckpointPersistenceFailureRecovery(
            directoryURL: recoveryURL
        )
        let transcriptionService = FakeControllerTranscriptionService()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore,
            recordingCaptureJournal: RecordingCaptureJournal(
                directoryURL: activeURL,
                releasedDirectoryURL: cacheURL
            )
        )

        await controller.performRecordingAction()

        #expect(controller.status == .failure(message: "Could not start microphone recording."))
        #expect(controller.outputStatusText == "Recording interrupted — saved to History.")
        #expect(transcriptionService.calls.isEmpty)
        #expect(recoveryStore.checkpointCallCount == 1)
        #expect(recoveryStore.fallbackCallCount == 1)
        let attempt = try #require(recoveryStore.failedAttempts.first)
        #expect(attempt.reason == .recoveryOwnershipPersistenceFailed)
        #expect(try Data(contentsOf: attempt.audioFileURL) == contents)
        #expect(try protectedCaptureURLs(in: activeURL).isEmpty)
    }

    @Test func terminationWhileListeningFinalizesProviderFreeHistoryOwner() async throws {
        let rootURL = try makeTemporaryControllerDirectory(prefix: "termination-salvage")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let activeURL = rootURL.appendingPathComponent("Active", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("Cache", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        let contents = Data("quit while recording".utf8)
        let recorder = PreparedCaptureRecorder(contents: contents)
        let recoveryStore = TranscriptionFailureRecoveryStore(directoryURL: recoveryURL)
        let transcriptionService = FakeControllerTranscriptionService()
        let eventLogger = FakeDictationEventLogger()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore,
            recordingCaptureJournal: RecordingCaptureJournal(
                directoryURL: activeURL,
                releasedDirectoryURL: cacheURL
            ),
            eventLogger: eventLogger
        )

        await controller.performRecordingAction()
        await controller.prepareForTermination()

        #expect(controller.status == .idle)
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls.isEmpty)
        let attempt = try #require(recoveryStore.failedAttempts.first)
        #expect(attempt.state == .failed)
        #expect(attempt.reason == .processingInterrupted)
        #expect(try Data(contentsOf: attempt.audioFileURL) == contents)
        #expect(try protectedCaptureURLs(in: activeURL).isEmpty)
        #expect(
            eventLogger.events.contains(
                .recordingTerminal(
                    cause: .ownerTeardown,
                    attemptID: attempt.id,
                    durability: .historyCheckpoint,
                    providerAuthorized: false
                )
            )
        )
    }

    @Test func launchRepairLogsProviderFreeDurabilityWithoutPathsOrText() async throws {
        let rootURL = try makeTemporaryControllerDirectory(prefix: "launch-repair-log")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let activeURL = rootURL.appendingPathComponent("Active", isDirectory: true)
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        let journal = RecordingCaptureJournal(directoryURL: activeURL)
        let lease = try journal.prepareCapture(
            settings: .defaults,
            maximumDuration: 300
        )
        try Data("launch repair audio".utf8).write(to: lease.audioFileURL)
        let recoveryStore = TranscriptionFailureRecoveryStore(directoryURL: recoveryURL)
        let eventLogger = FakeDictationEventLogger()
        let controller = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: FakeControllerTranscriptionService(),
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore,
            recordingCaptureJournal: journal,
            eventLogger: eventLogger
        )

        controller.repairInterruptedRecordings()

        let attempt = try #require(recoveryStore.failedAttempts.first)
        #expect(controller.outputStatusText == "An interrupted recording was recovered to History.")
        #expect(
            eventLogger.events.contains(
                .recordingTerminal(
                    cause: .ownerTeardown,
                    attemptID: attempt.id,
                    durability: .historyCheckpoint,
                    providerAuthorized: false
                )
            )
        )
    }

    @Test func terminationAfterProviderDispatchIsUncertainAndNeverRetryable() async throws {
        let rootURL = try makeTemporaryControllerDirectory(prefix: "termination-dispatch")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let sourceURL = rootURL.appendingPathComponent("dispatched.m4a")
        let contents = Data("already dispatched audio".utf8)
        try contents.write(to: sourceURL)
        let artifact = AudioRecordingArtifact(
            fileURL: sourceURL,
            duration: 4,
            byteCount: Int64(contents.count)
        )
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        let recoveryStore = TranscriptionFailureRecoveryStore(directoryURL: recoveryURL)
        let gate = ControllerAsyncGate()
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("late provider result"),
            beforeResult: {
                await gate.wait()
            }
        )
        let controller = makeController(
            recorder: FakeAudioRecorderService(
                currentStatus: .recording,
                stopResult: .success(artifact)
            ),
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore,
            initialStatus: .recording
        )
        let stopTask = Task { @MainActor in
            await controller.performRecordingAction()
        }
        await yieldUntil {
            controller.status == .transcribing
                && transcriptionService.calls.count == 1
        }

        await controller.prepareForTermination()

        #expect(controller.status == .idle)
        #expect(transcriptionService.cancelCount == 1)
        let retained = try #require(recoveryStore.failedAttempts.first)
        #expect(retained.state == .failed)
        #expect(retained.reason == .providerOutcomeUncertain)
        #expect(retained.canRetry == false)
        #expect(try Data(contentsOf: retained.audioFileURL) == contents)
        let relaunched = TranscriptionFailureRecoveryStore(directoryURL: recoveryURL)
        let restored = try #require(relaunched.failedAttempts.first)
        #expect(restored.id == retained.id)
        #expect(restored.reason == .providerOutcomeUncertain)
        #expect(restored.canRetry == false)

        await gate.open()
        await stopTask.value
        #expect(transcriptionService.calls.count == 1)
        #expect(controller.status == .idle)
    }

    @Test func transportFailureAfterProviderDispatchStaysUncertainAcrossRelaunch() async throws {
        let rootURL = try makeTemporaryControllerDirectory(prefix: "transport-uncertain")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let sourceURL = rootURL.appendingPathComponent("transport-failure.m4a")
        let contents = Data("ambiguous transport response".utf8)
        try contents.write(to: sourceURL)
        let artifact = AudioRecordingArtifact(
            fileURL: sourceURL,
            duration: 7,
            byteCount: Int64(contents.count)
        )
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        let recoveryStore = TranscriptionFailureRecoveryStore(directoryURL: recoveryURL)
        let controller = makeController(
            recorder: FakeAudioRecorderService(
                currentStatus: .recording,
                stopResult: .success(artifact)
            ),
            transcriptionService: FakeControllerTranscriptionService(
                result: .failure(.networkFailure)
            ),
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: recoveryStore,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        let uncertainAttempt = try #require(recoveryStore.failedAttempts.first)
        #expect(uncertainAttempt.reason == .providerOutcomeUncertain)
        #expect(!uncertainAttempt.canRetry)
        let dispatchMarkerURL = recoveryURL.appendingPathComponent(
            "ProviderDispatch-\(uncertainAttempt.id.uuidString.lowercased()).json"
        )
        #expect(FileManager.default.fileExists(atPath: dispatchMarkerURL.path))

        let relaunchedStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let relaunchedAttempt = try #require(relaunchedStore.failedAttempts.first)
        #expect(relaunchedAttempt.id == uncertainAttempt.id)
        #expect(relaunchedAttempt.reason == .providerOutcomeUncertain)
        #expect(!relaunchedAttempt.canRetry)
        let duplicateProvider = FakeControllerTranscriptionService(
            result: .success("Must not be uploaded twice")
        )
        let relaunchedController = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: duplicateProvider,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: relaunchedStore
        )

        await relaunchedController.retryFailedTranscription(id: relaunchedAttempt.id)

        #expect(duplicateProvider.calls.isEmpty)
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

    @Test func finalFifteenSecondCountdownKeepsEarlierPrivateRouteWarnings() async {
        let recorder = FakeAudioRecorderService()
        let monitor = FakeRecordingDurationMonitor()
        let cuePlayer = FakeDictationCuePlayer()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: FakeControllerTranscriptionService(),
            transcriptOutput: FakeTranscriptOutput(),
            cuePlayer: cuePlayer,
            recordingDurationMonitor: monitor,
            privateAudioOutputRouteProvider: FakePrivateAudioOutputRouteProvider(
                isPrivate: true
            )
        )

        await controller.performRecordingAction()
        #expect(recorder.requestedMaximumDurations == [300])
        #expect(monitor.requestedMaximumDurations == [300])
        monitor.emit(elapsedWholeSecond: 240)

        #expect(controller.recordingCountdown == nil)
        #expect(cuePlayer.playedCues == [
            .startRecording,
            .recordingLimitWarning(.amber),
        ])

        monitor.emit(elapsedWholeSecond: 285)
        #expect(controller.recordingCountdown == VoiceSessionCountdown(
            remainingWholeSeconds: 15,
            urgency: .amber
        ))
        #expect(cuePlayer.playedCues == [
            .startRecording,
            .recordingLimitWarning(.amber),
        ])

        monitor.emit(elapsedWholeSecond: 290)
        #expect(controller.recordingCountdown == VoiceSessionCountdown(
            remainingWholeSeconds: 10,
            urgency: .red
        ))
        #expect(cuePlayer.playedCues.last == .recordingLimitWarning(.red))

        controller.cancelRecording()
        #expect(controller.recordingCountdown == nil)
        #expect(monitor.stopCount == 1)
    }

    @Test func recordingCountdownPublishesOnlyChangedValues() async {
        let monitor = FakeRecordingDurationMonitor()
        let controller = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: FakeControllerTranscriptionService(),
            transcriptOutput: FakeTranscriptOutput(),
            recordingDurationMonitor: monitor
        )
        var publishedCountdowns: [VoiceSessionCountdown?] = []
        controller.recordingCountdownDidChange = { countdown in
            publishedCountdowns.append(countdown)
        }

        await controller.performRecordingAction()
        monitor.emit(elapsedWholeSecond: 1)
        monitor.emit(elapsedWholeSecond: 239)
        monitor.emit(elapsedWholeSecond: 284)

        #expect(publishedCountdowns.isEmpty)

        monitor.emit(elapsedWholeSecond: 285)
        monitor.emit(elapsedWholeSecond: 285)
        monitor.emit(elapsedWholeSecond: 286)

        #expect(publishedCountdowns == [
            VoiceSessionCountdown(
                remainingWholeSeconds: 15,
                urgency: .amber
            ),
            VoiceSessionCountdown(
                remainingWholeSeconds: 14,
                urgency: .amber
            ),
        ])

        controller.cancelRecording()
        controller.cancelRecording()

        #expect(publishedCountdowns == [
            VoiceSessionCountdown(
                remainingWholeSeconds: 15,
                urgency: .amber
            ),
            VoiceSessionCountdown(
                remainingWholeSeconds: 14,
                urgency: .amber
            ),
            nil,
        ])
    }

    @Test func selectedLimitIsFrozenForCurrentRecordingAndReloadedForNextRecording() async {
        var settings = AppSettings.defaults
        settings.recordingDurationLimit = RecordingDurationLimit(minutes: 1)
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-one-minute-limit.m4a"),
            duration: 59.7,
            byteCount: 480_000
        )
        let recorder = FakeAudioRecorderService(stopResult: .success(artifact))
        let monitor = FakeRecordingDurationMonitor()
        let cuePlayer = FakeDictationCuePlayer()
        let eventLogger = FakeDictationEventLogger()
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: FakeControllerTranscriptionService(
                result: .success("One-minute transcript")
            ),
            settingsProvider: { settings },
            transcriptOutput: FakeTranscriptOutput(),
            cuePlayer: cuePlayer,
            recordingDurationMonitor: monitor,
            privateAudioOutputRouteProvider: FakePrivateAudioOutputRouteProvider(
                isPrivate: true
            ),
            transcriptionFailureRecovery: failureRecovery,
            eventLogger: eventLogger
        )

        await controller.performRecordingAction()
        #expect(recorder.requestedMaximumDurations == [60])
        #expect(monitor.requestedMaximumDurations == [60])

        monitor.emit(elapsedWholeSecond: 30)
        #expect(controller.recordingCountdown == nil)
        #expect(cuePlayer.playedCues.last == .recordingLimitWarning(.amber))

        monitor.emit(elapsedWholeSecond: 45)
        #expect(controller.recordingCountdown == VoiceSessionCountdown(
            remainingWholeSeconds: 15,
            urgency: .amber
        ))
        #expect(cuePlayer.playedCues.last == .recordingLimitWarning(.amber))

        monitor.emit(elapsedWholeSecond: 50)
        #expect(controller.recordingCountdown == VoiceSessionCountdown(
            remainingWholeSeconds: 10,
            urgency: .red
        ))
        #expect(cuePlayer.playedCues.last == .recordingLimitWarning(.red))

        settings.recordingDurationLimit = RecordingDurationLimit(minutes: 15)
        recorder.simulateAutomaticStop(
            .success(
                AudioRecorderAutomaticCompletion(
                    artifact: artifact,
                    reason: .unexpected(recorderReportedSuccess: false)
                )
            )
        )
        await yieldUntil { controller.status.voiceWorkPhase == .inactive }

        #expect(controller.status == .success(transcript: "One-minute transcript"))
        #expect(failureRecovery.failedAttempts.first?.completionKind == .maximumDuration)
        #expect(cuePlayer.playedCues.last == .recordingLimitReached)
        #expect(eventLogger.events.filter { $0 == .recordingLimitReached }.count == 1)

        await controller.performRecordingAction()
        #expect(recorder.requestedMaximumDurations == [60, 900])
        #expect(monitor.requestedMaximumDurations == [60, 900])
        controller.cancelRecording()
    }

    @Test func oneMinuteWatchdogFinishesExactlyOnce() async {
        var settings = AppSettings.defaults
        settings.recordingDurationLimit = RecordingDurationLimit(minutes: 1)
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-one-minute-watchdog.m4a"),
            duration: 60,
            byteCount: 500_000
        )
        let recorder = FakeAudioRecorderService(stopResult: .success(artifact))
        let monitor = FakeRecordingDurationMonitor()
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("One-minute watchdog transcript")
        )
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: FakeTranscriptOutput(),
            recordingDurationMonitor: monitor
        )

        await controller.performRecordingAction()
        monitor.emit(elapsedWholeSecond: 60)
        monitor.emit(elapsedWholeSecond: 60)
        await yieldUntil { controller.status.voiceWorkPhase == .inactive }

        #expect(controller.status == .success(
            transcript: "One-minute watchdog transcript"
        ))
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls.count == 1)
    }

    @Test func speakerRouteShowsCountdownWithoutInjectingWarningCue() async {
        let monitor = FakeRecordingDurationMonitor()
        let cuePlayer = FakeDictationCuePlayer()
        let controller = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: FakeControllerTranscriptionService(),
            transcriptOutput: FakeTranscriptOutput(),
            cuePlayer: cuePlayer,
            recordingDurationMonitor: monitor
        )

        await controller.performRecordingAction()
        monitor.emit(elapsedWholeSecond: 299)

        #expect(controller.recordingCountdown?.remainingWholeSeconds == 1)
        #expect(cuePlayer.playedCues == [.startRecording])
    }

    @Test func maximumDurationWatchdogFinishesWhenRecorderDelegateIsMissing() async {
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-watchdog-limit.m4a"),
            duration: 300,
            byteCount: 2_100_000
        )
        let recorder = FakeAudioRecorderService(stopResult: .success(artifact))
        let monitor = FakeRecordingDurationMonitor()
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Watchdog transcript")
        )
        let cuePlayer = FakeDictationCuePlayer()
        let eventLogger = FakeDictationEventLogger()
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            cuePlayer: cuePlayer,
            recordingDurationMonitor: monitor,
            transcriptionFailureRecovery: failureRecovery,
            eventLogger: eventLogger
        )

        await controller.performRecordingAction()
        monitor.emit(elapsedWholeSecond: 300)
        await yieldUntil { controller.status.voiceWorkPhase == .inactive }

        #expect(controller.status == .success(transcript: "Watchdog transcript"))
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls.count == 1)
        #expect(transcriptionService.calls.first?.audioFileURL == artifact.fileURL)
        #expect(failureRecovery.failedAttempts.first?.state == .saved)
        #expect(failureRecovery.failedAttempts.first?.acceptedTranscriptText == "Watchdog transcript")
        #expect(cuePlayer.playedCues == [.startRecording, .recordingLimitReached])
        #expect(eventLogger.events.filter { $0 == .recordingLimitReached }.count == 1)
        #expect(
            eventLogger.events.filter {
                if case .recordingStopped = $0 { return true }
                return false
            }.count == 1
        )
        #expect(monitor.stopCount == 1)
    }

    @Test func stopFailureBecomesUserVisibleFailureWithoutTranscription() async {
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .failure(.stopFailed)
        )
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let eventLogger = FakeDictationEventLogger()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptionFailureRecovery: failureRecovery,
            eventLogger: eventLogger,
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
        #expect(failureRecovery.failedAttempts.isEmpty)
        #expect(
            attemptStageFailureEvents(in: eventLogger.events) == [
                .recordingStopFailed(category: "stop_failed")
            ]
        )
    }

    @Test func transcriptionFailureDoesNotDeliverOutputOrOverwriteSuccess() async throws {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(result: .failure(.networkUnavailable))
        let transcriptOutput = FakeTranscriptOutput()
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let eventLogger = FakeDictationEventLogger()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptionFailureRecovery: failureRecovery,
            transcriptionUsageRecorder: usageRecorder,
            eventLogger: eventLogger,
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
        #expect(failureRecovery.failedAttempts.map(\.reason) == [.providerOutcomeUncertain])
        #expect(controller.failurePresentation?.settingsTarget == nil)
        #expect(controller.failurePresentation?.failedAttemptID == failureRecovery.failedAttempts.first?.id)
        #expect(controller.failurePresentation?.canRetry == false)
        #expect(controller.voiceAttemptOutcome == .recoverableFailure)
        #expect(
            attemptStageFailureEvents(in: eventLogger.events) == [
                .transcriptionFailed(category: "network_unavailable")
            ]
        )

        let retainedAttemptID = try #require(controller.failurePresentation?.failedAttemptID)
        try failureRecovery.removeFailedAttempt(id: retainedAttemptID)

        #expect(controller.failurePresentation?.failedAttemptID == retainedAttemptID)
        #expect(controller.voiceAttemptOutcome == nil)
    }

    @Test func ambiguousTransportFailuresAfterDispatchAreNonRetryable() async throws {
        let errors: [OpenAITranscriptionServiceError] = [
            .timedOut,
            .networkUnavailable,
            .networkFailure,
            .cancelled,
        ]

        for error in errors {
            let failureRecovery = FakeTranscriptionFailureRecovery()
            let controller = makeController(
                recorder: FakeAudioRecorderService(currentStatus: .recording),
                transcriptionService: FakeControllerTranscriptionService(
                    result: .failure(error)
                ),
                transcriptOutput: FakeTranscriptOutput(),
                transcriptionFailureRecovery: failureRecovery,
                initialStatus: .recording
            )

            await controller.performRecordingAction()

            let attempt = try #require(failureRecovery.failedAttempts.first)
            #expect(attempt.reason == .providerOutcomeUncertain)
            #expect(!attempt.canRetry)
            #expect(controller.failurePresentation?.failedAttemptID == attempt.id)
            #expect(controller.failurePresentation?.canRetry == false)
        }
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
        #expect(failureRecovery.failedAttempts.map(\.reason) == [.providerOutcomeUncertain])
        #expect(controller.voiceAttemptOutcome == nil)
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

    @Test func retryCredentialFailureKeepsAttemptAndUsesTranscriptionAttribution() async throws {
        let attemptID = try #require(
            UUID(uuidString: "FE38D9D4-00FA-41F8-BE6E-EF490875C815")
        )
        let attempt = FailedTranscriptionAttempt(
            id: attemptID,
            audioFileURL: URL(fileURLWithPath: "/tmp/holdtype-failed-retry-credential.m4a"),
            audioDuration: 12,
            transcriptionModel: "gpt-4o-transcribe",
            languageCode: "en",
            reason: .networkUnavailable
        )
        let failureRecovery = FakeTranscriptionFailureRecovery(initialAttempts: [attempt])
        let transcriptionService = FakeControllerTranscriptionService(result: .success("unexpected transcript"))
        let transcriptOutput = FakeTranscriptOutput()
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let eventLogger = FakeDictationEventLogger()
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .idle),
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptionFailureRecovery: failureRecovery,
            transcriptionUsageRecorder: usageRecorder,
            eventLogger: eventLogger,
            credentialResolverForUngatedActions: FakeControllerCredentialResolver(
                result: .failure(.apiKeyUnavailable(KeychainService.inaccessibleAPIKeyMessage))
            )
        )

        await controller.retryFailedTranscription(id: attemptID)

        #expect(controller.status == .failure(message: "The OpenAI API key could not be read."))
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(usageRecorder.calls.isEmpty)
        #expect(failureRecovery.failedAttempts.map(\.id) == [attemptID])
        #expect(failureRecovery.failedAttempts.map(\.reason) == [.apiKeyUnavailable])
        #expect(controller.failurePresentation?.settingsTarget == .openAI)
        #expect(controller.failurePresentation?.failedAttemptID == attemptID)
        #expect(controller.failurePresentation?.canRetry == true)
        #expect(
            attemptStageFailureEvents(in: eventLogger.events) == [
                .transcriptionFailed(category: "api_key_unavailable")
            ]
        )
    }

    @Test func savedMaximumDurationRecordingCannotBeRetried() async {
        let savedAttempt = FailedTranscriptionAttempt(
            audioFileURL: URL(fileURLWithPath: "/tmp/holdtype-saved-max-recording.m4a"),
            audioDuration: 300,
            transcriptionModel: "gpt-4o-transcribe",
            languageCode: nil,
            completionKind: .maximumDuration,
            state: .saved,
            reason: .other,
            acceptedTranscriptText: "Already transcribed"
        )
        let failureRecovery = FakeTranscriptionFailureRecovery(
            initialAttempts: [savedAttempt]
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Duplicate transcript")
        )
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: FakeAudioRecorderService(),
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptionFailureRecovery: failureRecovery
        )

        await controller.retryFailedTranscription(id: savedAttempt.id)

        #expect(controller.outputStatusText == "This saved recording is already transcribed.")
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(failureRecovery.failedAttempts == [savedAttempt])
    }

    @Test func retryWhileRecordingLeavesTheLiveCaptureAndSavedAttemptUntouched() async {
        let attemptID = UUID()
        let attempt = FailedTranscriptionAttempt(
            id: attemptID,
            audioFileURL: URL(
                fileURLWithPath: "/tmp/holdtype-retry-blocked-during-recording.m4a"
            ),
            audioDuration: 12,
            transcriptionModel: "gpt-4o-transcribe",
            languageCode: "en",
            reason: .networkUnavailable
        )
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("must not run")
        )
        let failureRecovery = FakeTranscriptionFailureRecovery(
            initialAttempts: [attempt]
        )
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: failureRecovery,
            initialStatus: .recording
        )

        await controller.retryFailedTranscription(id: attemptID)

        #expect(controller.status == .recording)
        #expect(
            controller.outputStatusText
                == DictationSessionController.savedRecordingActionsUnavailableMessage
        )
        #expect(recorder.currentStatus == .recording)
        #expect(recorder.stopCount == 0)
        #expect(recorder.cancelCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(failureRecovery.failedAttempts.map(\.id) == [attemptID])
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
        let textCorrectionService = FakeTextCorrectionService()
        var settings = AppSettings.defaults
        settings.textCorrectionEnabled = true
        settings.textCorrectionModelPreset = .fast
        settings.localTextCleanupEnabled = false
        settings.transcriptionModel = " current-retry-model "
        settings.useActiveTextContext = true
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .idle),
            transcriptionService: transcriptionService,
            textCorrectionService: textCorrectionService,
            settings: settings,
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
        #expect(
            transcriptionService.calls == [
                TranscriptionCall(
                    audioFileURL: attempt.audioFileURL,
                    model: "current-retry-model",
                    languageCode: nil,
                    promptComposition: settings.transcriptionPromptComposition(context: nil)
                )
            ]
        )
        #expect(transcriptHistory.entries.map(\.transcriptText) == ["recovered text"])
        let historyRequest = transcriptHistory.calls.first
        #expect(historyRequest?.acceptedTranscript.text == "recovered text")
        #expect(historyRequest?.transcriptionModel == "current-retry-model")
        #expect(historyRequest?.languageCode == nil)
        #expect(historyRequest?.audioDuration == 12)
        #expect(historyRequest?.cachedAudioFileURL == nil)
        #expect(historyRequest?.historyEnabled == true)
        #expect(
            textCorrectionService.calls == [
                TextCorrectionCall(
                    transcript: "recovered text",
                    correctionConfiguration: settings.textCorrectionConfiguration,
                    postProcessingConfiguration: settings.transcriptPostProcessingConfiguration
                )
            ]
        )
        #expect(
            usageRecorder.calls == [
                try SuccessfulTranscriptionUsage(
                    transcriptionID: transcriptionID,
                    model: "current-retry-model",
                    audioDuration: 12
                )
            ]
        )
        #expect(transcriptOutput.calls.map(\.transcript) == ["recovered text"])
        #expect(
            transcriptOutput.calls.map(\.preferences) == [
                OutputDeliveryPreferences(
                    automaticInsertionPreferenceEnabled: false,
                    keepLatestResult: true
                )
            ]
        )
        #expect(controller.outputStatusText == "Saved as Last Result. Press Control+Command+V to insert.")
    }

    @Test func retrySaveOnlyPreservesDisabledLatestResultPreference() async throws {
        let attemptID = try #require(
            UUID(uuidString: "F692D966-294B-4C23-B333-E4287E2BD245")
        )
        let attempt = FailedTranscriptionAttempt(
            id: attemptID,
            audioFileURL: URL(fileURLWithPath: "/tmp/holdtype-failed-retry-save-only.m4a"),
            audioDuration: 6,
            transcriptionModel: "gpt-4o-transcribe",
            languageCode: "en",
            reason: .networkUnavailable
        )
        let failureRecovery = FakeTranscriptionFailureRecovery(initialAttempts: [attempt])
        let transcriptOutput = FakeTranscriptOutput(result: .success(.skipped(reason: .outputDisabled)))
        var settings = AppSettings.defaults
        settings.automaticallyInsertTranscripts = true
        settings.saveTranscriptsToAppClipboard = false
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .idle),
            transcriptionService: FakeControllerTranscriptionService(result: .success(" save-only result ")),
            settings: settings,
            transcriptOutput: transcriptOutput,
            transcriptionFailureRecovery: failureRecovery
        )

        await controller.retryFailedTranscription(id: attemptID)

        #expect(controller.status == .success(transcript: "save-only result"))
        #expect(failureRecovery.failedAttempts.isEmpty)
        #expect(transcriptOutput.calls.map(\.transcript) == ["save-only result"])
        #expect(
            transcriptOutput.calls.map(\.preferences) == [
                OutputDeliveryPreferences(
                    automaticInsertionPreferenceEnabled: false,
                    keepLatestResult: false
                )
            ]
        )
        #expect(controller.outputStatusText == "Automatic insertion and Paste Last Result are disabled.")
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
        let transcriptOutput = FakeTranscriptOutput(result: .success(.inserted))
        var settings = AppSettings.defaults
        settings.automaticallyInsertTranscripts = true
        settings.saveTranscriptsToAppClipboard = false
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
        #expect(
            transcriptOutput.calls.map(\.preferences) == [
                OutputDeliveryPreferences(
                    automaticInsertionPreferenceEnabled: true,
                    keepLatestResult: false
                )
            ]
        )
        #expect(controller.outputStatusText == "Inserted transcript into the active app.")
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
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .idle),
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptionFailureRecovery: failureRecovery,
            transcriptionUsageRecorder: usageRecorder
        )

        let retryTask = Task { @MainActor in
            await controller.retryFailedTranscription(id: attemptID)
        }
        await yieldUntil {
            controller.status == .transcribing && transcriptionService.calls.count == 1
        }
        #expect(controller.voiceAttemptOutcome == nil)

        controller.cancelRecording()

        #expect(controller.status == .idle)
        #expect(controller.voiceAttemptOutcome == nil)
        #expect(transcriptionService.cancelCount == 1)
        #expect(usageRecorder.calls.isEmpty)
        #expect(failureRecovery.failedAttempts.map(\.id) == [attemptID])

        await gate.open()
        await retryTask.value

        #expect(controller.status == .idle)
        #expect(controller.voiceAttemptOutcome == nil)
        #expect(usageRecorder.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(failureRecovery.failedAttempts.map(\.id) == [attemptID])
    }

    @Test func cancelDuringFailedAttemptRetryRemainsUncertainAcrossRelaunch() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-controller-cancelled-retry-relaunch-\(UUID().uuidString)",
                isDirectory: true
            )
        let recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = rootURL.appendingPathComponent("cancelled-retry.m4a")
        try Data("cancelled retry recording".utf8).write(to: sourceURL)
        let recoveryStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let attempt = try #require(
            try recoveryStore.recordFailedAttempt(
                audioFileURL: sourceURL,
                settings: .defaults,
                audioDuration: 12,
                reason: .networkUnavailable
            )
        )
        let gate = ControllerAsyncGate()
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("Must be discarded after cancellation"),
            beforeResult: {
                await gate.wait()
            }
        )
        let usageRecorder = FakeTranscriptionUsageRecorder()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .idle),
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptionFailureRecovery: recoveryStore,
            transcriptionUsageRecorder: usageRecorder
        )

        let retryTask = Task { @MainActor in
            await controller.retryFailedTranscription(id: attempt.id)
        }
        await yieldUntil {
            controller.status == .transcribing
                && transcriptionService.calls.count == 1
        }

        controller.cancelRecording()

        #expect(controller.status == .idle)
        let interruptedAttempt = try #require(recoveryStore.failedAttempts.first)
        #expect(interruptedAttempt.id == attempt.id)
        #expect(interruptedAttempt.reason == .providerOutcomeUncertain)
        #expect(interruptedAttempt.acceptedTranscriptText == nil)
        #expect(!interruptedAttempt.canRetry)
        #expect(usageRecorder.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
        let dispatchMarkerURL = recoveryURL.appendingPathComponent(
            "ProviderDispatch-\(attempt.id.uuidString.lowercased()).json"
        )
        #expect(FileManager.default.fileExists(atPath: dispatchMarkerURL.path))

        await gate.open()
        await retryTask.value

        #expect(usageRecorder.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)

        let relaunchedStore = TranscriptionFailureRecoveryStore(
            directoryURL: recoveryURL
        )
        let relaunchedAttempt = try #require(relaunchedStore.failedAttempts.first)
        #expect(relaunchedAttempt.id == attempt.id)
        #expect(relaunchedAttempt.reason == .providerOutcomeUncertain)
        #expect(relaunchedAttempt.acceptedTranscriptText == nil)
        #expect(!relaunchedAttempt.canRetry)

        let relaunchedProvider = FakeControllerTranscriptionService(
            result: .success("Recovered after cancellation")
        )
        let relaunchedController = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .idle),
            transcriptionService: relaunchedProvider,
            transcriptOutput: FakeTranscriptOutput(),
            transcriptionFailureRecovery: relaunchedStore
        )
        await relaunchedController.retryFailedTranscription(id: relaunchedAttempt.id)

        #expect(relaunchedProvider.calls.isEmpty)
        #expect(relaunchedStore.failedAttempts.map(\.id) == [attempt.id])
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
        #expect(
            transcriptOutput.calls.map(\.preferences) == [
                AppSettings.defaults.outputDeliveryPreferences,
                AppSettings.defaults.outputDeliveryPreferences,
            ]
        )
        #expect(failureRecovery.failedAttempts.isEmpty)
        #expect(controller.status == .success(transcript: "deferred retry text"))
        #expect(usageRecorder.calls.count == 2)
        #expect(Set(usageRecorder.calls.map(\.transcriptionID)).count == 2)
    }

    @Test func retryTransportFailureKeepsAttemptUncertainWithoutOverwritingPreviousTranscript() async throws {
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
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: FakeAudioRecorderService(currentStatus: .idle),
            transcriptionService: FakeControllerTranscriptionService(result: .failure(.timedOut)),
            transcriptOutput: transcriptOutput,
            transcriptionFailureRecovery: failureRecovery,
            transcriptionUsageRecorder: usageRecorder,
            initialStatus: .success(transcript: "previous transcript"),
            lastTranscriptText: "previous transcript"
        )

        await controller.retryFailedTranscription(id: attemptID)

        #expect(controller.status == .failure(message: "Transcription timed out."))
        #expect(controller.lastTranscriptText == "previous transcript")
        #expect(failureRecovery.failedAttempts.map(\.reason) == [.providerOutcomeUncertain])
        #expect(failureRecovery.failedAttempts.map(\.retryCount) == [0])
        #expect(controller.failurePresentation?.settingsTarget == nil)
        #expect(controller.failurePresentation?.failedAttemptID == attemptID)
        #expect(controller.failurePresentation?.canRetry == false)
        #expect(usageRecorder.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
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
        let failureRecovery = FakeTranscriptionFailureRecovery()
        let eventLogger = FakeDictationEventLogger()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptHistory: transcriptHistory,
            transcriptionFailureRecovery: failureRecovery,
            transcriptionUsageRecorder: usageRecorder,
            eventLogger: eventLogger,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(controller.status == .success(transcript: "Delivered text"))
        #expect(controller.voiceAttemptOutcome == .resultReady)
        #expect(controller.lastTranscriptText == "Delivered text")
        #expect(controller.outputStatusText == "Inserting text into the active app timed out.")
        #expect(
            transcriptOutput.calls == [
                TranscriptOutputCall(
                    transcript: "Delivered text",
                    preferences: AppSettings.defaults.outputDeliveryPreferences
                )
            ]
        )
        #expect(transcriptHistory.entries.map(\.transcriptText) == ["Delivered text"])
        #expect(usageRecorder.calls.map(\.model) == ["gpt-4o-transcribe"])
        #expect(usageRecorder.calls.map(\.audioDuration) == [1.2])
        #expect(transcriptHistory.calls.first?.audioDuration == 1.2)
        #expect(failureRecovery.failedAttempts.isEmpty)
        #expect(
            attemptStageFailureEvents(in: eventLogger.events) == [
                .outputDeliveryFailed(category: "text_insertion_timed_out")
            ]
        )
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
        #expect(transcriptHistory.calls.count == 1)
        #expect(transcriptHistory.calls.first?.historyEnabled == false)
        #expect(transcriptHistory.entries.isEmpty)
    }

    private func makeController(
        recorder: any AudioRecorderService,
        transcriptionService: FakeControllerTranscriptionService,
        textCorrectionService: FakeTextCorrectionService? = nil,
        translationService: FakeTranslationService? = nil,
        settings: AppSettings = .defaults,
        settingsProvider: (() -> AppSettings)? = nil,
        transcriptOutput: FakeTranscriptOutput,
        cuePlayer: FakeDictationCuePlayer? = nil,
        recordingDurationMonitor: FakeRecordingDurationMonitor? = nil,
        privateAudioOutputRouteProvider: FakePrivateAudioOutputRouteProvider =
            FakePrivateAudioOutputRouteProvider(isPrivate: false),
        transcriptHistory: FakeTranscriptRecoveryHistory? = nil,
        transcriptionFailureRecovery: (any TranscriptionFailureRecoveryRecording)? = nil,
        activeTextContextReader: FakeActiveTextContextReader? = nil,
        transcriptionUsageRecorder: FakeTranscriptionUsageRecorder? = nil,
        transcriptionIDGenerator: @escaping () -> UUID = UUID.init,
        recordingCache: (any RecordingCacheLifecycleHandling)? = nil,
        recordingCaptureJournal: (any RecordingCaptureJournaling)? = nil,
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
            settingsProvider: settingsProvider ?? { settings },
            transcriptOutput: transcriptOutput,
            cuePlayer: cuePlayer,
            recordingDurationMonitor: recordingDurationMonitor,
            privateAudioOutputRouteProvider: privateAudioOutputRouteProvider,
            transcriptHistory: transcriptHistory,
            transcriptionFailureRecovery: transcriptionFailureRecovery ?? FakeTranscriptionFailureRecovery(),
            activeTextContextReader: activeTextContextReader ?? FakeActiveTextContextReader(),
            transcriptionUsageRecorder: transcriptionUsageRecorder ?? FakeTranscriptionUsageRecorder(),
            transcriptionIDGenerator: transcriptionIDGenerator,
            recordingCache: recordingCache ?? FakeRecordingCache(),
            recordingCaptureJournal: recordingCaptureJournal
                ?? RecordingCaptureJournal.shared,
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

    private func makeTemporaryControllerDirectory(prefix: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-controller-\(prefix)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL
    }

    private func protectedCaptureURLs(in directoryURL: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { url in
            url.lastPathComponent.contains("HoldType-Capture-")
        }
    }

    private func attemptStageFailureEvents(
        in events: [DictationLogEvent]
    ) -> [DictationLogEvent] {
        events.filter { event in
            switch event {
            case .recordingStopFailed,
                 .transcriptionFailed,
                 .postProcessingFailed,
                 .outputDeliveryFailed:
                return true
            default:
                return false
            }
        }
    }

    private func yieldUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private let defaultControllerCredentialAPIKey = "sk-controller-test"

private struct TranscriptionCall: Equatable {
    let audioFileURL: URL
    let model: String
    let languageCode: String?
    let promptComposition: TranscriptionPromptComposition
    let credentialAPIKey: String

    init(
        audioFileURL: URL,
        model: String,
        languageCode: String?,
        promptComposition: TranscriptionPromptComposition,
        credentialAPIKey: String = defaultControllerCredentialAPIKey
    ) {
        self.audioFileURL = audioFileURL
        self.model = model
        self.languageCode = languageCode
        self.promptComposition = promptComposition
        self.credentialAPIKey = credentialAPIKey
    }

    init(
        request: AudioTranscriptionRequest,
        credentialAPIKey: String = defaultControllerCredentialAPIKey
    ) {
        self.init(
            audioFileURL: request.audioFileURL,
            model: request.model,
            languageCode: request.languageCode,
            promptComposition: request.promptComposition,
            credentialAPIKey: credentialAPIKey
        )
    }
}

private struct TranscriptOutputCall: Equatable {
    let transcript: String
    let preferences: OutputDeliveryPreferences

    init(request: OutputDeliveryRequest) {
        transcript = request.acceptedTranscript.text
        preferences = request.preferences
    }

    init(transcript: String, preferences: OutputDeliveryPreferences) {
        self.transcript = transcript
        self.preferences = preferences
    }
}

private struct TextCorrectionCall: Equatable {
    let transcript: String
    let correctionConfiguration: TextCorrectionConfiguration
    let postProcessingConfiguration: TranscriptPostProcessingConfiguration
    let credentialAPIKey: String

    init(
        transcript: String,
        correctionConfiguration: TextCorrectionConfiguration,
        postProcessingConfiguration: TranscriptPostProcessingConfiguration,
        credentialAPIKey: String = defaultControllerCredentialAPIKey
    ) {
        self.transcript = transcript
        self.correctionConfiguration = correctionConfiguration
        self.postProcessingConfiguration = postProcessingConfiguration
        self.credentialAPIKey = credentialAPIKey
    }
}

private struct TranslationCall: Equatable {
    let transcript: String
    let translationConfiguration: TranslationConfiguration
    let resolvedSourceLanguageCode: String?
    let credentialAPIKey: String

    init(
        transcript: String,
        translationConfiguration: TranslationConfiguration,
        resolvedSourceLanguageCode: String?,
        credentialAPIKey: String = defaultControllerCredentialAPIKey
    ) {
        self.transcript = transcript
        self.translationConfiguration = translationConfiguration
        self.resolvedSourceLanguageCode = resolvedSourceLanguageCode
        self.credentialAPIKey = credentialAPIKey
    }
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

@MainActor
private final class FakeRecordingDurationMonitor: RecordingDurationMonitoring {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var requestedMaximumDurations: [Int] = []
    private var onElapsedWholeSecond: (@MainActor (Int) -> Void)?

    func start(
        maximumDurationWholeSeconds: Int,
        onElapsedWholeSecond: @escaping @MainActor (Int) -> Void
    ) {
        startCount += 1
        requestedMaximumDurations.append(maximumDurationWholeSeconds)
        self.onElapsedWholeSecond = onElapsedWholeSecond
    }

    func stop() {
        stopCount += 1
        onElapsedWholeSecond = nil
    }

    func emit(elapsedWholeSecond: Int) {
        onElapsedWholeSecond?(elapsedWholeSecond)
    }
}

private struct FakePrivateAudioOutputRouteProvider: PrivateAudioOutputRouteProviding {
    let isPrivate: Bool

    func isPrivateAudioOutputRoute() -> Bool {
        isPrivate
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
        _ request: AudioTranscriptionRequest,
        credential: OpenAICredential
    ) async throws -> String {
        calls.append(
            TranscriptionCall(
                request: request,
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

    func deliver(_ request: OutputDeliveryRequest) async throws -> TextInsertionResult {
        calls.append(TranscriptOutputCall(request: request))
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
        _ request: TextCorrectionRequest,
        credential: OpenAICredential
    ) async throws -> String {
        calls.append(
            TextCorrectionCall(
                transcript: request.acceptedTranscript.text,
                correctionConfiguration: request.correctionConfiguration,
                postProcessingConfiguration: request.postProcessingConfiguration,
                credentialAPIKey: credential.apiKey
            )
        )
        await beforeResult?()

        switch result {
        case .success(let correctedTranscript):
            return correctedTranscript.isEmpty
                ? request.acceptedTranscript.text
                : correctedTranscript
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
    private let beforeResult: (() async -> Void)?
    private(set) var calls: [TranslationCall] = []
    private(set) var cancelCount = 0

    init(
        result: Result<String, OpenAITextTranslationServiceError>? = nil,
        beforeResult: (() async -> Void)? = nil
    ) {
        self.result = result ?? .success("")
        self.beforeResult = beforeResult
    }

    func translate(
        _ request: TextTranslationRequest,
        credential: OpenAICredential
    ) async throws -> String {
        calls.append(
            TranslationCall(
                transcript: request.acceptedTranscript.text,
                translationConfiguration: request.translationConfiguration,
                resolvedSourceLanguageCode: request.resolvedSourceLanguageCode,
                credentialAPIKey: credential.apiKey
            )
        )
        await beforeResult?()

        switch result {
        case .success(let translatedTranscript):
            return translatedTranscript
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

private enum FakeTranscriptRecoveryHistoryError: Error {
    case saveFailed
}

@MainActor
private final class FakeTranscriptRecoveryHistory: TranscriptRecoveryHistoryRecording {
    private(set) var entries: [TranscriptHistoryEntry] = []
    private(set) var calls: [AcceptedTranscriptHistoryRequest] = []
    private let recordError: (any Error)?

    init(recordError: (any Error)? = nil) {
        self.recordError = recordError
    }

    func recordAcceptedTranscript(_ request: AcceptedTranscriptHistoryRequest) throws {
        calls.append(request)

        if let recordError {
            throw recordError
        }

        guard request.historyEnabled else {
            return
        }

        entries = try [
            TranscriptHistoryEntry(
                transcriptText: request.acceptedTranscript.text,
                transcriptionModel: request.transcriptionModel,
                languageCode: request.languageCode,
                audioDuration: request.audioDuration,
                cachedAudioFileURL: request.cachedAudioFileURL
            )
        ] + entries
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

private final class JoinedAutomaticStopRecorder: AudioRecorderService {
    private let completion: AudioRecorderAutomaticCompletion

    private(set) var currentStatus: AudioRecorderStatus = .recording
    private(set) var stopCount = 0

    init(completion: AudioRecorderAutomaticCompletion) {
        self.completion = completion
    }

    func startRecording(maximumDuration: TimeInterval) async throws {
        currentStatus = .recording
    }

    func stopRecording() async throws -> AudioRecordingArtifact {
        try await stopRecordingOutcome().artifact
    }

    func stopRecordingOutcome() async throws -> AudioRecorderStopOutcome {
        stopCount += 1
        currentStatus = .finished(artifact: completion.artifact)
        return AudioRecorderStopOutcome(
            artifact: completion.artifact,
            automaticCompletion: completion
        )
    }

    func cancelRecording() {
        currentStatus = .cancelled
    }
}

private final class PreparedCaptureRecorder: AudioRecorderService {
    private let contents: Data
    private let startErrorAfterWrite: AudioRecorderServiceError?
    private let stopError: AudioRecorderServiceError?
    private var activeFileURL: URL?

    private(set) var currentStatus: AudioRecorderStatus = .idle
    private(set) var stopCount = 0
    let lastFinalizationReachedMaximumDuration = false
    let acceptsPreparedRecordingFileURL = true

    init(
        contents: Data,
        startErrorAfterWrite: AudioRecorderServiceError? = nil,
        stopError: AudioRecorderServiceError? = nil
    ) {
        self.contents = contents
        self.startErrorAfterWrite = startErrorAfterWrite
        self.stopError = stopError
    }

    func startRecording(maximumDuration: TimeInterval) async throws {
        try await startRecording(maximumDuration: maximumDuration, outputFileURL: nil)
    }

    func startRecording(
        maximumDuration: TimeInterval,
        outputFileURL: URL?
    ) async throws {
        guard let outputFileURL else {
            throw AudioRecorderServiceError.temporaryFileUnavailable
        }
        try FileManager.default.createDirectory(
            at: outputFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: outputFileURL)
        activeFileURL = outputFileURL
        if let startErrorAfterWrite {
            currentStatus = .failed(
                message: startErrorAfterWrite.errorDescription ?? ""
            )
            throw startErrorAfterWrite
        }
        currentStatus = .recording
    }

    func stopRecording() async throws -> AudioRecordingArtifact {
        stopCount += 1
        if let stopError {
            currentStatus = .failed(message: stopError.errorDescription ?? "")
            throw stopError
        }
        guard let activeFileURL else {
            throw AudioRecorderServiceError.missingRecordingFile
        }
        let byteCount = Int64(
            (try FileManager.default.attributesOfItem(atPath: activeFileURL.path)[.size]
                as? NSNumber)?.int64Value ?? 0
        )
        let artifact = AudioRecordingArtifact(
            fileURL: activeFileURL,
            duration: 3.25,
            byteCount: byteCount
        )
        currentStatus = .finished(artifact: artifact)
        return artifact
    }

    func cancelRecording() {
        currentStatus = .cancelled
    }

}

@MainActor
private final class CheckpointPersistenceFailureRecovery:
    TranscriptionFailureRecoveryRecording {
    private let directoryURL: URL
    private var pendingAttempt: FailedTranscriptionAttempt?

    private(set) var failedAttempts: [FailedTranscriptionAttempt] = []
    private(set) var checkpointCallCount = 0
    private(set) var fallbackCallCount = 0

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func recordProcessingCheckpoint(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        completionKind: TranscriptionRecoveryCompletionKind
    ) throws -> FailedTranscriptionAttempt {
        checkpointCallCount += 1
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let ownedURL = directoryURL.appendingPathComponent(
            "owned-\(UUID().uuidString).m4a"
        )
        try FileManager.default.copyItem(at: audioFileURL, to: ownedURL)
        pendingAttempt = FailedTranscriptionAttempt(
            audioFileURL: ownedURL,
            audioDuration: audioDuration,
            transcriptionModel: settings.resolvedTranscriptionModel,
            languageCode: settings.resolvedLanguageCode,
            completionKind: completionKind,
            state: .processing,
            reason: .other
        )
        throw TranscriptionFailureRecoveryError.saveFailed
    }

    func recordFailedAttempt(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        reason: FailedTranscriptionReason
    ) throws -> FailedTranscriptionAttempt? {
        throw TranscriptionFailureRecoveryError.saveFailed
    }

    func retainEmergencyFallback(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        reason: FailedTranscriptionReason,
        completionKind: TranscriptionRecoveryCompletionKind
    ) -> FailedTranscriptionAttempt? {
        fallbackCallCount += 1
        guard var attempt = pendingAttempt else {
            return nil
        }
        pendingAttempt = nil
        attempt.state = .failed
        attempt.reason = reason
        attempt.updatedAt = Date()
        failedAttempts = [attempt]
        return attempt
    }

    func updateFailedAttempt(
        id: FailedTranscriptionAttempt.ID,
        reason: FailedTranscriptionReason
    ) throws {
        guard let index = failedAttempts.firstIndex(where: { $0.id == id }) else {
            throw TranscriptionFailureRecoveryError.attemptUnavailable
        }
        failedAttempts[index].state = .failed
        failedAttempts[index].reason = reason
    }

    @discardableResult
    func removeFailedAttempt(id: FailedTranscriptionAttempt.ID) throws -> Bool {
        let oldCount = failedAttempts.count
        failedAttempts.removeAll { $0.id == id }
        return failedAttempts.count != oldCount
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
