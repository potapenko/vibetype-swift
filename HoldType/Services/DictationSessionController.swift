//
//  DictationSessionController.swift
//  HoldType
//
//  Created by Codex on 6/22/26.
//

import Foundation
import HoldTypeDomain
import HoldTypeOpenAI

protocol TranscriptOutputDelivering {
    func deliver(_ request: OutputDeliveryRequest) async throws -> TextInsertionResult
}

extension TextInsertionService: TranscriptOutputDelivering {}

enum FailedTranscriptionRetryOutputMode: Equatable {
    case saveOnly
    case followAutomaticInsertion
}

private struct PendingFailedTranscriptionRetry {
    let id: FailedTranscriptionAttempt.ID
    let credential: OpenAICredential?
    let outputMode: FailedTranscriptionRetryOutputMode
}

private enum DeferredRecordingTerminalOutcome {
    case automatic(
        Result<AudioRecorderAutomaticCompletion, AudioRecorderServiceError>
    )
    case maximumDurationAwaitingArtifact
}

protocol RecordingStopTailSleeping {
    func sleep(seconds: TimeInterval) async throws
}

struct TaskRecordingStopTailSleeper: RecordingStopTailSleeping {
    func sleep(seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

@MainActor
final class DictationSessionController {
    static let savedRecordingActionsUnavailableMessage =
        "Finish the current dictation before using a saved recording."
    private static let maximumDurationClassificationTolerance: TimeInterval = 0.5
    private static let recordingLimitSavingStatusText =
        "Recording limit reached. Saving recording..."
    private static let recordingLimitTranscribingStatusText =
        "Recording limit reached. Recording saved to History; transcribing..."
    private static let recordingLimitSaveFailedStatusText =
        "Text was accepted, but the recording that reached the limit could not be marked as saved."
    private static let acceptedHistorySaveFailedStatusText =
        "Text was accepted, but History could not save it. The recording remains in Saved Recordings."

    private let recorder: any AudioRecorderService
    private let transcriptionService: any OpenAITranscriptionServing
    private let transcriptPipeline: DictationTranscriptPipeline
    private let settingsProvider: () -> AppSettings
    private let transcriptOutput: any TranscriptOutputDelivering
    private let cuePlayer: any DictationCuePlaying
    private let historyAudioPlaybackStopper: any TranscriptHistoryAudioPlaybackStopping
    private let recordingDurationMonitor: any RecordingDurationMonitoring
    private let privateAudioOutputRouteProvider: any PrivateAudioOutputRouteProviding
    private let transcriptHistory: any TranscriptRecoveryHistoryRecording
    private let transcriptionFailureRecovery: any TranscriptionFailureRecoveryRecording
    private let activeTextContextReader: any ActiveTextContextReading
    private let transcriptionUsageRecorder: any TranscriptionUsageRecording
    private let transcriptionIDGenerator: () -> UUID
    private let recordingCache: any RecordingCacheLifecycleHandling
    private let recordingCaptureJournal: any RecordingCaptureJournaling
    private let recordingStopTailSleeper: any RecordingStopTailSleeping
    private let eventLogger: any DictationEventLogging
    private let credentialResolverForUngatedActions: (any OpenAICredentialResolving)?

    private var isPerformingAction = false
    private var nextSessionID = 0
    private var activeSessionID: Int?
    private var activeOutputIntent: DictationOutputIntent?
    private var activeCredential: OpenAICredential?
    private var activeRecordingStopTailTask: Task<Void, Error>?
    private var pendingFailedTranscriptionRetry: PendingFailedTranscriptionRetry?
    private var deferredRecordingTerminalOutcome: DeferredRecordingTerminalOutcome?
    private var activeRecoveryCheckpointID: FailedTranscriptionAttempt.ID?
    private var activeProviderDispatchCheckpointID: FailedTranscriptionAttempt.ID?
    private var activeRecordingDurationLimit: RecordingDurationLimit?
    private var activeRecordingCaptureLease: RecordingCaptureLease?
    private var activeRecordingSettings: AppSettings?
    private var terminationRequested = false
    private var loggedTerminalAttemptIDs: Set<UUID> = []

    private(set) var recordingCountdown: VoiceSessionCountdown? {
        didSet {
            guard oldValue != recordingCountdown else {
                return
            }
            recordingCountdownDidChange?(recordingCountdown)
        }
    }

    var statusDidChange: (@MainActor (DictationStatus) -> Void)?
    var lastTranscriptTextDidChange: (@MainActor (String?) -> Void)?
    var outputStatusTextDidChange: (@MainActor (String?) -> Void)?
    var failurePresentationDidChange: (@MainActor (DictationFailurePresentation?) -> Void)?
    var recordingCountdownDidChange: (@MainActor (VoiceSessionCountdown?) -> Void)?

    private(set) var status: DictationStatus {
        didSet {
            statusDidChange?(status)
        }
    }
    private(set) var lastTranscriptText: String? {
        didSet {
            lastTranscriptTextDidChange?(lastTranscriptText)
        }
    }
    private(set) var outputStatusText: String? {
        didSet {
            outputStatusTextDidChange?(outputStatusText)
        }
    }
    private(set) var failurePresentation: DictationFailurePresentation? {
        didSet {
            failurePresentationDidChange?(failurePresentation)
        }
    }

    init(
        recorder: any AudioRecorderService = AVFoundationAudioRecorderService(),
        transcriptionService: any OpenAITranscriptionServing = OpenAITranscriptionService(),
        textCorrectionService: any TextCorrectionServing = TranscriptTextCorrectionService(),
        translationService: any TranscriptTranslationServing = TranscriptTranslationService(),
        settingsProvider: @escaping () -> AppSettings = { AppSettingsStore().load() },
        transcriptOutput: any TranscriptOutputDelivering = TextInsertionService(),
        cuePlayer: any DictationCuePlaying = NativeDictationCuePlayer.shared,
        historyAudioPlaybackStopper: any TranscriptHistoryAudioPlaybackStopping =
            TranscriptHistoryAudioPlayer.shared,
        recordingDurationMonitor: (any RecordingDurationMonitoring)? = nil,
        privateAudioOutputRouteProvider: any PrivateAudioOutputRouteProviding =
            CoreAudioPrivateOutputRouteProvider(),
        transcriptHistory: (any TranscriptRecoveryHistoryRecording)? = nil,
        transcriptionFailureRecovery: (any TranscriptionFailureRecoveryRecording)? = nil,
        activeTextContextReader: (any ActiveTextContextReading)? = nil,
        transcriptionUsageRecorder: (any TranscriptionUsageRecording)? = nil,
        transcriptionIDGenerator: @escaping () -> UUID = UUID.init,
        recordingCache: any RecordingCacheLifecycleHandling = RecordingCacheService.shared,
        recordingCaptureJournal: any RecordingCaptureJournaling = RecordingCaptureJournal.shared,
        recordingStopTailSleeper: any RecordingStopTailSleeping = TaskRecordingStopTailSleeper(),
        eventLogger: any DictationEventLogging = OSLogDictationEventLogger(),
        credentialResolverForUngatedActions: (any OpenAICredentialResolving)? = nil,
        initialStatus: DictationStatus = .idle,
        lastTranscriptText: String? = nil,
        outputStatusText: String? = nil
    ) {
        self.recorder = recorder
        self.transcriptionService = transcriptionService
        self.transcriptPipeline = DictationTranscriptPipeline(
            textCorrectionService: textCorrectionService,
            translationService: translationService
        )
        self.settingsProvider = settingsProvider
        self.transcriptOutput = transcriptOutput
        self.cuePlayer = cuePlayer
        self.historyAudioPlaybackStopper = historyAudioPlaybackStopper
        self.recordingDurationMonitor = recordingDurationMonitor
            ?? ContinuousRecordingDurationMonitor()
        self.privateAudioOutputRouteProvider = privateAudioOutputRouteProvider
        self.transcriptHistory = transcriptHistory ?? TranscriptRecoveryHistoryStore.shared
        self.transcriptionFailureRecovery = transcriptionFailureRecovery
            ?? TranscriptionFailureRecoveryStore.shared
        self.activeTextContextReader = activeTextContextReader ?? ActiveTextContextService()
        self.transcriptionUsageRecorder = transcriptionUsageRecorder ?? OpenAIUsageStore.shared
        self.transcriptionIDGenerator = transcriptionIDGenerator
        self.recordingCache = recordingCache
        self.recordingCaptureJournal = recordingCaptureJournal
        self.recordingStopTailSleeper = recordingStopTailSleeper
        self.eventLogger = eventLogger
        self.credentialResolverForUngatedActions = credentialResolverForUngatedActions
        self.status = initialStatus
        self.lastTranscriptText = lastTranscriptText.flatMap {
            AcceptedTranscript.nonEmptyNormalizedText(from: $0)
        }
            ?? initialStatus.lastTranscriptText
        self.outputStatusText = outputStatusText
        self.failurePresentation = nil
        self.recordingCountdown = nil

        recorder.setAutomaticStopHandler { [weak self] result in
            self?.handleAutomaticRecorderStop(result)
        }
    }

    func performRecordingAction(
        intent: DictationOutputIntent = .standard,
        credential: OpenAICredential? = nil
    ) async {
        guard !terminationRequested else {
            return
        }
        guard beginExclusiveAction() else {
            return
        }

        defer { completeExclusiveAction() }

        switch status.voiceWorkPhase {
        case .inactive:
            await startRecording(intent: intent, credential: credential)
        case .listening:
            await stopRecordingAndTranscribe(intent: intent, credential: credential)
        case .arming, .ready, .finalizing, .processing:
            return
        }
    }

    func cancelRecording() {
        switch status.voiceWorkPhase {
        case .listening:
            guard !isPerformingAction || activeRecordingStopTailTask != nil else {
                return
            }

            activeRecordingStopTailTask?.cancel()
            activeRecordingStopTailTask = nil
            let captureLease = activeRecordingCaptureLease
            recorder.cancelRecording()
            if let captureLease {
                let durability: RecordingDurabilityOutcome
                do {
                    try recordingCaptureJournal.discardCapture(captureLease)
                    durability = .explicitlyDiscarded
                } catch {
                    durability = .discardFailed
                }
                recordRecordingTerminal(
                    cause: .explicitUserDiscard,
                    attemptID: captureLease.id,
                    durability: durability,
                    providerAuthorized: false
                )
            }
            activeRecordingCaptureLease = nil
            activeRecordingSettings = nil
            stopRecordingDurationMonitoring()
            deferredRecordingTerminalOutcome = nil
            cancelActiveSession()
            activeCredential = nil
            outputStatusText = nil
            failurePresentation = nil

            switch recorder.currentStatus {
            case .failed(let message):
                status = .failure(message: message)
            default:
                status = .idle
            }
        case .processing:
            markActiveRecoveryCheckpointInterrupted()
            transcriptionService.cancelActiveTranscription()
            transcriptPipeline.cancelActivePostProcessing()
            cancelActiveSession()
            outputStatusText = nil
            failurePresentation = nil
            status = .idle
        case .inactive, .arming, .ready, .finalizing:
            return
        }
    }

    func dismissFailurePresentation() {
        failurePresentation = nil
        if case .failure = status {
            status = .idle
        }
    }

    func retryFailedTranscription(
        id: FailedTranscriptionAttempt.ID,
        credential: OpenAICredential? = nil,
        outputMode: FailedTranscriptionRetryOutputMode = .saveOnly
    ) async {
        guard status.voiceWorkPhase != .listening else {
            outputStatusText = Self.savedRecordingActionsUnavailableMessage
            return
        }

        let retry = PendingFailedTranscriptionRetry(
            id: id,
            credential: credential,
            outputMode: outputMode
        )

        guard beginExclusiveAction() else {
            pendingFailedTranscriptionRetry = retry
            return
        }

        defer { completeExclusiveAction() }

        await performFailedTranscriptionRetry(retry)
    }

    private func performFailedTranscriptionRetry(_ retry: PendingFailedTranscriptionRetry) async {
        guard let attempt = transcriptionFailureRecovery.failedAttempts.first(where: { $0.id == retry.id }) else {
            outputStatusText = TranscriptionFailureRecoveryError.attemptUnavailable.localizedDescription
            return
        }
        guard attempt.canRetry else {
            outputStatusText = attempt.state == .saved
                ? "This saved recording is already transcribed."
                : "This saved recording is not available for retry."
            return
        }

        outputStatusText = nil
        failurePresentation = nil
        var sessionID: Int?

        do {
            let credential = try resolvedCredential(providedCredential: retry.credential)
            sessionID = beginSession(intent: .standard)
            activeCredential = credential
            status = .transcribing
            let settings = settingsProvider()
            let transcriptionID = transcriptionIDGenerator()
            let transcriptionRequest = try transcriptPipeline.makeAudioTranscriptionRequest(
                audioFileURL: attempt.audioFileURL,
                settings: settings,
                context: nil
            )
            activeRecoveryCheckpointID = attempt.id
            try transcriptionFailureRecovery.sealProviderDispatch(id: attempt.id)
            activeProviderDispatchCheckpointID = attempt.id
            eventLogger.record(.transcriptionStarted)
            let rawTranscript = try await transcriptionService.transcribe(
                transcriptionRequest,
                credential: credential
            )
            eventLogger.record(.transcriptionSucceeded)
            guard let sessionID, isCurrentSession(sessionID) else {
                return
            }

            let transcribedTranscript = try Self.acceptedTranscript(from: rawTranscript)
            transcriptionFailureRecovery.recordProviderAccepted(
                id: attempt.id,
                acceptedTranscriptText: transcribedTranscript.text
            )
            if activeProviderDispatchCheckpointID == attempt.id {
                activeProviderDispatchCheckpointID = nil
            }
            recordSuccessfulTranscriptionUsage(
                transcriptionID: transcriptionID,
                model: transcriptionRequest.model,
                audioDuration: attempt.audioDuration
            )
            let correctedTranscriptText = await transcriptPipeline.correctedTranscriptText(
                from: transcribedTranscript,
                settings: settings,
                credential: credential
            )
            guard isCurrentSession(sessionID) else {
                return
            }

            let acceptedTranscript = try Self.acceptedTranscript(from: correctedTranscriptText)
            let retainsMaximumDurationRecording =
                attempt.completionKind == .maximumDuration
            var savedRecordingUpdateFailed = false
            var acceptedHistoryCommitted = true
            if retainsMaximumDurationRecording {
                do {
                    try transcriptionFailureRecovery.markSaved(
                        id: retry.id,
                        acceptedTranscriptText: acceptedTranscript.text
                    )
                } catch {
                    savedRecordingUpdateFailed = true
                }
            }

            lastTranscriptText = acceptedTranscript.text
            status = .success(transcript: acceptedTranscript.text)
            failurePresentation = nil

            if !retainsMaximumDurationRecording {
                acceptedHistoryCommitted = recordRecoveryHistory(
                    acceptedTranscript,
                    settings: settings,
                    audioDuration: attempt.audioDuration,
                    cachedAudioFileURL: nil
                )
                if acceptedHistoryCommitted {
                    do {
                        _ = try transcriptionFailureRecovery.removeFailedAttempt(id: retry.id)
                    } catch {
                        outputStatusText = TranscriptionFailureRecoveryError.deleteFailed.localizedDescription
                    }
                } else {
                    transcriptionFailureRecovery.markAcceptedHistoryCommitFailed(
                        id: retry.id
                    )
                    savedRecordingUpdateFailed = true
                }
            }
            if activeRecoveryCheckpointID == attempt.id {
                activeRecoveryCheckpointID = nil
            }

            let deliveryRequest = OutputDeliveryRequest(
                acceptedTranscript: acceptedTranscript,
                preferences: outputDeliveryPreferences(
                    from: settings,
                    retryOutputMode: retry.outputMode
                )
            )
            do {
                let deliveryStatusText = try await transcriptOutput.deliver(deliveryRequest).statusText
                if !acceptedHistoryCommitted {
                    outputStatusText = Self.acceptedHistorySaveFailedStatusText
                } else if savedRecordingUpdateFailed {
                    outputStatusText = Self.recordingLimitSaveFailedStatusText
                } else {
                    outputStatusText = deliveryStatusText
                }
            } catch {
                guard isCurrentSession(sessionID) else {
                    return
                }

                recordFailure(error, at: .outputDelivery)
                outputStatusText = Self.userFacingMessage(for: error)
            }

            finishSession(sessionID)
        } catch {
            if let sessionID, !isCurrentSession(sessionID) {
                return
            }

            recordProviderFailure(id: retry.id, error: error)
            if activeRecoveryCheckpointID == attempt.id {
                activeRecoveryCheckpointID = nil
            }
            if let sessionID {
                finishSession(sessionID)
            }
            recordFailure(error, at: .transcription)
            let message = Self.userFacingMessage(for: error)
            status = .failure(message: message)
            failurePresentation = failurePresentation(
                message: message,
                error: error,
                failedAttempt: transcriptionFailureRecovery.failedAttempts.first { $0.id == retry.id },
                showsRecoveryPrompt: true
            )
        }
    }

    private func beginExclusiveAction() -> Bool {
        guard !isPerformingAction else {
            return false
        }

        isPerformingAction = true
        return true
    }

    private func completeExclusiveAction() {
        isPerformingAction = false
        if runDeferredRecordingTerminalOutcomeIfNeeded() {
            return
        }
        runPendingFailedTranscriptionRetryIfNeeded()
    }

    private func runDeferredRecordingTerminalOutcomeIfNeeded() -> Bool {
        guard !isPerformingAction,
              activeSessionID != nil,
              status.voiceWorkPhase == .listening,
              let outcome = deferredRecordingTerminalOutcome else {
            if activeSessionID == nil {
                deferredRecordingTerminalOutcome = nil
            }
            return false
        }

        deferredRecordingTerminalOutcome = nil
        switch outcome {
        case .automatic(let result):
            handleAutomaticRecorderStop(result)
        case .maximumDurationAwaitingArtifact:
            handleRecordingMaximumDurationWatchdog()
        }
        return true
    }

    private func runPendingFailedTranscriptionRetryIfNeeded() {
        guard !isPerformingAction,
              let retry = pendingFailedTranscriptionRetry else {
            return
        }

        pendingFailedTranscriptionRetry = nil
        guard status.voiceWorkPhase != .listening else {
            outputStatusText = Self.savedRecordingActionsUnavailableMessage
            return
        }

        Task { @MainActor in
            await retryFailedTranscription(
                id: retry.id,
                credential: retry.credential,
                outputMode: retry.outputMode
            )
        }
    }

    private func outputDeliveryPreferences(
        from settings: AppSettings,
        retryOutputMode: FailedTranscriptionRetryOutputMode
    ) -> OutputDeliveryPreferences {
        switch retryOutputMode {
        case .saveOnly:
            var preferences = settings.outputDeliveryPreferences
            preferences.automaticInsertionPreferenceEnabled = false
            return preferences
        case .followAutomaticInsertion:
            return settings.outputDeliveryPreferences
        }
    }

    private func beginSession(intent: DictationOutputIntent) -> Int {
        nextSessionID += 1
        activeSessionID = nextSessionID
        activeOutputIntent = intent
        activeProviderDispatchCheckpointID = nil
        return nextSessionID
    }

    private func currentOrNewSessionID(intent: DictationOutputIntent) -> Int {
        if let activeSessionID {
            return activeSessionID
        }

        return beginSession(intent: intent)
    }

    private func currentOutputIntent(fallback: DictationOutputIntent) -> DictationOutputIntent {
        let outputIntent = (activeOutputIntent ?? .standard).merged(with: fallback)
        activeOutputIntent = outputIntent
        return outputIntent
    }

    private func isCurrentSession(_ sessionID: Int) -> Bool {
        activeSessionID == sessionID
    }

    private func finishSession(_ sessionID: Int) {
        guard activeSessionID == sessionID else {
            return
        }

        activeSessionID = nil
        activeOutputIntent = nil
        activeCredential = nil
        deferredRecordingTerminalOutcome = nil
        activeRecordingDurationLimit = nil
        activeProviderDispatchCheckpointID = nil
    }

    private func cancelActiveSession() {
        activeSessionID = nil
        activeOutputIntent = nil
        activeCredential = nil
        deferredRecordingTerminalOutcome = nil
        activeRecordingDurationLimit = nil
        activeProviderDispatchCheckpointID = nil
    }

    private func startRecording(intent: DictationOutputIntent, credential: OpenAICredential?) async {
        outputStatusText = nil
        failurePresentation = nil
        let settings = settingsProvider()
        if intent == .translate,
           let translationIssue = settings.translationConfigurationIssue {
            let message = Self.userFacingMessage(for: translationIssue)
            failurePresentation = failurePresentation(
                message: message,
                error: translationIssue,
                failedAttempt: nil
            )
            status = .failure(message: message)
            return
        }

        do {
            activeCredential = try resolvedCredential(providedCredential: credential)
        } catch {
            let message = Self.userFacingMessage(for: error)
            failurePresentation = failurePresentation(message: message, error: error, failedAttempt: nil)
            status = .failure(message: message)
            return
        }

        let sessionID = beginSession(intent: intent)
        let recordingDurationLimit = settings.recordingDurationLimit
        activeRecordingDurationLimit = recordingDurationLimit
        activeRecordingSettings = settings
        deferredRecordingTerminalOutcome = nil
        eventLogger.record(.recordingStartRequested)

        do {
            let captureLease: RecordingCaptureLease?
            if recorder.acceptsPreparedRecordingFileURL {
                captureLease = try recordingCaptureJournal.prepareCapture(
                    settings: settings,
                    maximumDuration: recordingDurationLimit.duration
                )
            } else {
                captureLease = nil
            }
            activeRecordingCaptureLease = captureLease
            historyAudioPlaybackStopper.stopPlayback()
            try await recorder.startRecording(
                maximumDuration: recordingDurationLimit.duration,
                outputFileURL: captureLease?.audioFileURL
            )
            guard isCurrentSession(sessionID) else {
                return
            }

            status = .recording
            eventLogger.record(.recordingStarted)
            playCue(.startRecording, settings: settings)
            startRecordingDurationMonitoring(sessionID: sessionID, settings: settings)
        } catch {
            let recoveredAttempt = preserveInterruptedCapture(
                completionKind: .standard,
                terminalCause: .platformInterrupted
            )
            stopRecordingDurationMonitoring()
            finishSession(sessionID)
            eventLogger.record(.recordingStartFailed(category: Self.operatorLogCategory(for: error)))
            let message = Self.userFacingMessage(for: error)
            if recoveredAttempt != nil {
                outputStatusText = "Recording interrupted — saved to History."
            }
            status = .failure(message: message)
            failurePresentation = failurePresentation(
                message: message,
                error: error,
                failedAttempt: recoveredAttempt,
                showsRecoveryPrompt: recoveredAttempt != nil
            )
        }
    }

    private func stopRecordingAndTranscribe(
        intent: DictationOutputIntent,
        credential: OpenAICredential?,
        automaticCompletion: AudioRecorderAutomaticCompletion? = nil,
        automaticReasonAwaitingArtifact: AudioRecorderAutomaticCompletionReason? = nil
    ) async {
        outputStatusText = nil
        failurePresentation = nil
        let userFinishOwnedAuthority = automaticCompletion == nil
            && automaticReasonAwaitingArtifact == nil
        let sessionID = currentOrNewSessionID(intent: intent)
        let outputIntent = currentOutputIntent(fallback: intent)
        var stage: VoiceAttemptStage = .recordingFinalization
        var completedArtifact: AudioRecordingArtifact?
        var completedRecordingSettings: AppSettings?
        var recoveryCheckpoint: FailedTranscriptionAttempt?
        var checkpointAttempted = false
        var allowsRecordingCacheHandling = true
        var resolvedAutomaticCompletion = automaticCompletion
        defer {
            if allowsRecordingCacheHandling {
                updateCompletedRecordingCacheIfNeeded(
                    artifact: completedArtifact,
                    settings: completedRecordingSettings
                )
            }
        }

        do {
            let settings = activeRecordingSettings ?? settingsProvider()
            completedRecordingSettings = settings
            let recordingDurationLimit = activeRecordingDurationLimit
                ?? settings.recordingDurationLimit
            var artifact: AudioRecordingArtifact
            if let automaticCompletion = resolvedAutomaticCompletion {
                artifact = automaticCompletion.artifact
                switch automaticCompletion.reason {
                case .maximumDuration:
                    outputStatusText = Self.recordingLimitSavingStatusText
                case .unexpected:
                    outputStatusText = "Recording ended unexpectedly. Saving recording..."
                }
            } else if let automaticReasonAwaitingArtifact {
                switch automaticReasonAwaitingArtifact {
                case .maximumDuration:
                    outputStatusText = Self.recordingLimitSavingStatusText
                case .unexpected:
                    outputStatusText = "Recording ended unexpectedly. Saving recording..."
                }
                artifact = try await recorder.stopRecording()
                resolvedAutomaticCompletion = AudioRecorderAutomaticCompletion(
                    artifact: artifact,
                    reason: automaticReasonAwaitingArtifact
                )
            } else {
                eventLogger.record(.recordingStopRequested)
                try await waitForRecordingStopTail(settings: settings)
                let stopOutcome = try await recorder.stopRecordingOutcome()
                artifact = stopOutcome.artifact
                resolvedAutomaticCompletion = stopOutcome.automaticCompletion
            }
            if let deferredOutcome = takeDeferredRecordingTerminalOutcome() {
                switch deferredOutcome {
                case .maximumDurationAwaitingArtifact:
                    resolvedAutomaticCompletion = AudioRecorderAutomaticCompletion(
                        artifact: artifact,
                        reason: .maximumDuration
                    )
                case .automatic(.success(let completion)):
                    let deferredUnexpectedMayOwnAuthority =
                        !userFinishOwnedAuthority || resolvedAutomaticCompletion != nil
                    if resolvedAutomaticCompletion?.reason != .maximumDuration,
                       completion.reason == .maximumDuration
                        || deferredUnexpectedMayOwnAuthority {
                        resolvedAutomaticCompletion = AudioRecorderAutomaticCompletion(
                            artifact: artifact,
                            reason: completion.reason,
                            recorderReportedSuccess: completion.recorderReportedSuccess
                        )
                    }
                case .automatic(.failure(let error)):
                    // A joined stop that produced a non-empty artifact is more
                    // authoritative than a racing delegate failure. Keep the
                    // anomaly in diagnostics without discarding the artifact.
                    recordFailure(error, at: .recordingFinalization)
                }
            }
            if let automaticCompletion = resolvedAutomaticCompletion,
               automaticCompletion.reason != .maximumDuration,
               recorder.lastFinalizationReachedMaximumDuration
                || Self.finalizedArtifactReachedMaximumDuration(
                    artifact,
                    limit: recordingDurationLimit
                ) {
                let recorderReportedSuccess: Bool?
                switch automaticCompletion.reason {
                case .maximumDuration:
                    recorderReportedSuccess = automaticCompletion.recorderReportedSuccess
                case .unexpected(let reportedSuccess):
                    recorderReportedSuccess = reportedSuccess
                }
                resolvedAutomaticCompletion = AudioRecorderAutomaticCompletion(
                    artifact: artifact,
                    reason: .maximumDuration,
                    recorderReportedSuccess: recorderReportedSuccess
                )
                outputStatusText = Self.recordingLimitSavingStatusText
            }
            if resolvedAutomaticCompletion == nil,
               recorder.lastFinalizationReachedMaximumDuration {
                resolvedAutomaticCompletion = AudioRecorderAutomaticCompletion(
                    artifact: artifact,
                    reason: .maximumDuration
                )
                outputStatusText = Self.recordingLimitSavingStatusText
            }
            if resolvedAutomaticCompletion == nil,
               automaticReasonAwaitingArtifact == nil,
               Self.finalizedArtifactReachedMaximumDuration(
                   artifact,
                   limit: recordingDurationLimit
               ) {
                // Key-up may win the exact-once boundary just before the
                // recorder delegate or controller watchdog. Preserve the
                // product-level maximum reason from the finalized artifact so
                // that scheduling order cannot change retention semantics.
                resolvedAutomaticCompletion = AudioRecorderAutomaticCompletion(
                    artifact: artifact,
                    reason: .maximumDuration
                )
                outputStatusText = Self.recordingLimitSavingStatusText
            }
            let recordingLimitWasLoggedBeforeFinalization =
                automaticCompletion?.reason == .maximumDuration
                || automaticReasonAwaitingArtifact == .maximumDuration
            if resolvedAutomaticCompletion?.reason == .maximumDuration,
               !recordingLimitWasLoggedBeforeFinalization {
                eventLogger.record(.recordingLimitReached)
            }
            completedArtifact = artifact
            stopRecordingDurationMonitoring()
            eventLogger.record(
                .recordingStopped(duration: artifact.duration, byteCount: artifact.byteCount)
            )

            guard isCurrentSession(sessionID) else {
                return
            }

            // An automatic recorder boundary owns its feedback immediately,
            // before persistence, configuration, credentials, or provider
            // work can fail.
            if resolvedAutomaticCompletion?.reason == .maximumDuration {
                playCue(.recordingLimitReached, settings: settings)
            } else if resolvedAutomaticCompletion != nil {
                playCue(.stopRecording, settings: settings)
            }

            let transcriptionSettings = transcriptPipeline.transcriptionSettings(
                for: outputIntent,
                settings: settings
            )
            completedRecordingSettings = transcriptionSettings
            // From this boundary onward a finalized, non-empty artifact owns
            // a recoverable transcription attempt, even if the durable copy
            // itself fails and we must expose the emergency original.
            stage = .transcription
            allowsRecordingCacheHandling = false
            checkpointAttempted = true
            recoveryCheckpoint = try transcriptionFailureRecovery.recordProcessingCheckpoint(
                audioFileURL: artifact.fileURL,
                settings: transcriptionSettings,
                audioDuration: artifact.duration,
                completionKind: resolvedAutomaticCompletion?.reason == .maximumDuration
                    ? .maximumDuration
                    : .standard
            )
            activeRecoveryCheckpointID = recoveryCheckpoint?.id
            if let captureLease = activeRecordingCaptureLease,
               let recoveryCheckpoint {
                artifact = try recordingCaptureJournal.releaseCapture(
                    captureLease,
                    artifact: artifact,
                    recoveryAttemptID: recoveryCheckpoint.id
                )
                completedArtifact = artifact
                activeRecordingCaptureLease = nil
            }
            activeRecordingSettings = nil
            allowsRecordingCacheHandling = true
            let terminalCause = Self.recordingTerminalCause(
                automaticCompletion: resolvedAutomaticCompletion,
                userFinishOwnedAuthority: userFinishOwnedAuthority
            )
            let providerAuthorized = terminalCause == .userFinished
                || terminalCause == .configuredLimit
            if let recoveryCheckpoint {
                recordRecordingTerminal(
                    cause: terminalCause,
                    attemptID: recoveryCheckpoint.id,
                    durability: .historyCheckpoint,
                    providerAuthorized: providerAuthorized
                )
            }
            if terminationRequested, let recoveryCheckpoint {
                try? transcriptionFailureRecovery.updateFailedAttempt(
                    id: recoveryCheckpoint.id,
                    reason: .processingInterrupted
                )
                if activeRecoveryCheckpointID == recoveryCheckpoint.id {
                    activeRecoveryCheckpointID = nil
                }
                outputStatusText = "Recording interrupted — saved to History."
                finishSession(sessionID)
                status = .idle
                return
            }
            if terminalCause == .platformInterrupted,
               let recoveryCheckpoint {
                try? transcriptionFailureRecovery.updateFailedAttempt(
                    id: recoveryCheckpoint.id,
                    reason: .processingInterrupted
                )
                if activeRecoveryCheckpointID == recoveryCheckpoint.id {
                    activeRecoveryCheckpointID = nil
                }
                let message = "Recording ended unexpectedly."
                outputStatusText = "Recording interrupted — saved to History."
                finishSession(sessionID)
                status = .failure(message: message)
                failurePresentation = failurePresentation(
                    message: message,
                    error: AudioRecorderServiceError.stopFailed,
                    failedAttempt: transcriptionFailureRecovery.failedAttempts.first {
                        $0.id == recoveryCheckpoint.id
                    } ?? recoveryCheckpoint,
                    showsRecoveryPrompt: true
                )
                return
            }
            if resolvedAutomaticCompletion?.reason == .maximumDuration {
                outputStatusText = Self.recordingLimitTranscribingStatusText
            }

            if outputIntent == .translate,
               let translationIssue = settings.translationConfigurationIssue {
                stage = .postProcessing
                throw translationIssue
            }

            if resolvedAutomaticCompletion == nil {
                playCue(.stopRecording, settings: settings)
            }
            status = .transcribing

            let credential = try resolvedCredential(providedCredential: credential)
            activeCredential = credential
            let context = activeTextContextReader.currentContext(settings: transcriptionSettings)
            let transcriptionID = transcriptionIDGenerator()
            let transcriptionRequest = try transcriptPipeline.makeAudioTranscriptionRequest(
                audioFileURL: recoveryCheckpoint?.audioFileURL ?? artifact.fileURL,
                settings: transcriptionSettings,
                context: context
            )
            if let recoveryCheckpoint {
                try transcriptionFailureRecovery.sealProviderDispatch(
                    id: recoveryCheckpoint.id
                )
                activeProviderDispatchCheckpointID = recoveryCheckpoint.id
            }
            eventLogger.record(.transcriptionStarted)
            let rawTranscript = try await transcriptionService.transcribe(
                transcriptionRequest,
                credential: credential
            )
            eventLogger.record(.transcriptionSucceeded)
            guard isCurrentSession(sessionID) else {
                return
            }

            let transcribedTranscript = try Self.acceptedTranscript(from: rawTranscript)
            if let recoveryCheckpoint {
                transcriptionFailureRecovery.recordProviderAccepted(
                    id: recoveryCheckpoint.id,
                    acceptedTranscriptText: transcribedTranscript.text
                )
                if activeProviderDispatchCheckpointID == recoveryCheckpoint.id {
                    activeProviderDispatchCheckpointID = nil
                }
            }
            recordSuccessfulTranscriptionUsage(
                transcriptionID: transcriptionID,
                model: transcriptionRequest.model,
                audioDuration: artifact.duration
            )
            stage = .postProcessing
            let correctedTranscriptText = await transcriptPipeline.correctedTranscriptText(
                from: transcribedTranscript,
                settings: settings,
                credential: credential
            )
            guard isCurrentSession(sessionID) else {
                return
            }

            let outputText = try await transcriptPipeline.postActionTranscriptText(
                from: correctedTranscriptText,
                intent: outputIntent,
                settings: settings,
                credential: credential
            )
            guard isCurrentSession(sessionID) else {
                return
            }

            let acceptedTranscript = try Self.acceptedTranscript(from: outputText)
            let retainsMaximumDurationRecording =
                resolvedAutomaticCompletion?.reason == .maximumDuration
            var savedRecordingUpdateFailed = false
            if retainsMaximumDurationRecording, let recoveryCheckpoint {
                do {
                    try transcriptionFailureRecovery.markSaved(
                        id: recoveryCheckpoint.id,
                        acceptedTranscriptText: acceptedTranscript.text
                    )
                } catch {
                    savedRecordingUpdateFailed = true
                }
            }

            lastTranscriptText = acceptedTranscript.text
            status = .success(transcript: acceptedTranscript.text)
            failurePresentation = nil
            var acceptedHistoryCommitted = true
            if !retainsMaximumDurationRecording {
                acceptedHistoryCommitted = recordRecoveryHistory(
                    acceptedTranscript,
                    settings: settings,
                    audioDuration: artifact.duration,
                    cachedAudioFileURL: artifact.fileURL
                )
                if !acceptedHistoryCommitted {
                    savedRecordingUpdateFailed = true
                }
            }
            if let recoveryCheckpoint {
                if !retainsMaximumDurationRecording, acceptedHistoryCommitted {
                    do {
                        _ = try transcriptionFailureRecovery.removeFailedAttempt(id: recoveryCheckpoint.id)
                    } catch {
                        outputStatusText = TranscriptionFailureRecoveryError.deleteFailed.localizedDescription
                    }
                } else if !retainsMaximumDurationRecording {
                    transcriptionFailureRecovery.markAcceptedHistoryCommitFailed(
                        id: recoveryCheckpoint.id
                    )
                }
                if activeRecoveryCheckpointID == recoveryCheckpoint.id {
                    activeRecoveryCheckpointID = nil
                }
            }

            stage = .outputDelivery
            let deliveryRequest = OutputDeliveryRequest(
                acceptedTranscript: acceptedTranscript,
                preferences: settings.outputDeliveryPreferences
            )
            do {
                let deliveryStatusText = try await transcriptOutput.deliver(deliveryRequest).statusText
                if !acceptedHistoryCommitted {
                    outputStatusText = Self.acceptedHistorySaveFailedStatusText
                } else if savedRecordingUpdateFailed {
                    outputStatusText = Self.recordingLimitSaveFailedStatusText
                } else {
                    outputStatusText = deliveryStatusText
                }
            } catch {
                guard isCurrentSession(sessionID) else {
                    return
                }

                recordFailure(error, at: stage)
                outputStatusText = Self.userFacingMessage(for: error)
            }

            finishSession(sessionID)
        } catch is CancellationError {
            var interruptedAttempt: FailedTranscriptionAttempt?
            if let recoveryCheckpoint {
                markRecoveryCheckpointInterrupted(id: recoveryCheckpoint.id)
                interruptedAttempt = transcriptionFailureRecovery.failedAttempts.first {
                    $0.id == recoveryCheckpoint.id
                }
            } else {
                interruptedAttempt = preserveInterruptedCapture(
                    completionKind: resolvedAutomaticCompletion?.reason == .maximumDuration
                        ? .maximumDuration
                        : .standard,
                    terminalCause: .ownerTeardown
                )
            }
            guard isCurrentSession(sessionID) else {
                return
            }

            allowsRecordingCacheHandling = activeRecordingCaptureLease == nil
            stopRecordingDurationMonitoring()
            finishSession(sessionID)
            activeCredential = nil
            if interruptedAttempt != nil {
                outputStatusText = "Recording interrupted — saved to History."
                status = .failure(message: "Recording processing was interrupted.")
                failurePresentation = failurePresentation(
                    message: "Recording processing was interrupted.",
                    error: CancellationError(),
                    failedAttempt: interruptedAttempt,
                    showsRecoveryPrompt: true
                )
            } else {
                outputStatusText = nil
                failurePresentation = nil
                status = .idle
            }
        } catch {
            guard isCurrentSession(sessionID) else {
                return
            }

            let recoveryResult: (
                attempt: FailedTranscriptionAttempt?,
                allowsRecordingCacheHandling: Bool
            )
            let recoveredInterruptedCapture = activeRecordingCaptureLease != nil
                && recoveryCheckpoint == nil
            if recoveredInterruptedCapture {
                recoveryResult = (
                    preserveInterruptedCapture(
                        completionKind: resolvedAutomaticCompletion?.reason == .maximumDuration
                            ? .maximumDuration
                            : .standard,
                        reuseCheckpointFallback: checkpointAttempted,
                        terminalCause: .internalFailure,
                        providerAuthorized: resolvedAutomaticCompletion?.reason == .maximumDuration
                            || userFinishOwnedAuthority
                    ),
                    false
                )
            } else if let recoveryCheckpoint {
                recordProviderFailure(id: recoveryCheckpoint.id, error: error)
                if activeRecoveryCheckpointID == recoveryCheckpoint.id {
                    activeRecoveryCheckpointID = nil
                }
                let hadProtectedCapture = activeRecordingCaptureLease != nil
                if let captureLease = activeRecordingCaptureLease {
                    try? recordingCaptureJournal.retireCaptureAfterRecovery(
                        captureLease,
                        recoveryAttemptID: recoveryCheckpoint.id
                    )
                    activeRecordingCaptureLease = nil
                    activeRecordingSettings = nil
                }
                recoveryResult = (
                    transcriptionFailureRecovery.failedAttempts.first {
                        $0.id == recoveryCheckpoint.id
                    },
                    !hadProtectedCapture
                )
            } else if checkpointAttempted,
                      let completedArtifact,
                      let completedRecordingSettings {
                recoveryResult = (
                    transcriptionFailureRecovery.retainEmergencyFallback(
                        audioFileURL: completedArtifact.fileURL,
                        settings: completedRecordingSettings,
                        audioDuration: completedArtifact.duration,
                        reason: .other,
                        completionKind: resolvedAutomaticCompletion?.reason == .maximumDuration
                            ? .maximumDuration
                            : .standard
                    ),
                    false
                )
            } else {
                recoveryResult = recordFailedTranscriptionAttempt(
                    error,
                    at: stage,
                    artifact: completedArtifact,
                    settings: completedRecordingSettings
                )
            }
            allowsRecordingCacheHandling = recoveryResult.allowsRecordingCacheHandling
            stopRecordingDurationMonitoring()
            finishSession(sessionID)
            recordFailure(error, at: stage)
            let message = Self.userFacingMessage(for: error)
            if checkpointAttempted, recoveryCheckpoint == nil {
                outputStatusText = message
            }
            if recoveredInterruptedCapture, recoveryResult.attempt != nil {
                outputStatusText = "Recording interrupted — saved to History."
            }
            status = .failure(message: message)
            failurePresentation = failurePresentation(
                message: message,
                error: error,
                failedAttempt: recoveryResult.attempt,
                showsRecoveryPrompt: recoveryResult.attempt != nil
            )
        }
    }

    private func markActiveRecoveryCheckpointInterrupted() {
        guard let activeRecoveryCheckpointID else {
            return
        }

        markRecoveryCheckpointInterrupted(id: activeRecoveryCheckpointID)
    }

    private func markRecoveryCheckpointInterrupted(
        id: FailedTranscriptionAttempt.ID
    ) {
        if activeProviderDispatchCheckpointID == id {
            transcriptionFailureRecovery.markProviderOutcomeUncertain(id: id)
            activeProviderDispatchCheckpointID = nil
        } else {
            try? transcriptionFailureRecovery.updateFailedAttempt(
                id: id,
                reason: .processingInterrupted
            )
        }
        if activeRecoveryCheckpointID == id {
            activeRecoveryCheckpointID = nil
        }
    }

    private func recordProviderFailure(
        id: FailedTranscriptionAttempt.ID,
        error: Error
    ) {
        guard activeProviderDispatchCheckpointID == id else {
            try? transcriptionFailureRecovery.updateFailedAttempt(
                id: id,
                reason: FailedTranscriptionReason(error: error)
            )
            return
        }

        activeProviderDispatchCheckpointID = nil
        guard Self.providerOutcomeIsDefinitive(for: error) else {
            // A transport failure after dispatch may arrive after the provider
            // accepted the audio. Keep the lifetime dispatch seal and require
            // an explicit duplicate-submission flow instead of ordinary Retry.
            transcriptionFailureRecovery.markProviderOutcomeUncertain(id: id)
            return
        }

        try? transcriptionFailureRecovery.updateFailedAttempt(
            id: id,
            reason: FailedTranscriptionReason(error: error)
        )
    }

    private static func providerOutcomeIsDefinitive(for error: Error) -> Bool {
        guard !(error is CancellationError),
              let error = error as? OpenAITranscriptionServiceError else {
            return false
        }

        switch error {
        case .timedOut,
             .networkUnavailable,
             .networkFailure,
             .cancelled:
            return false
        case .missingAPIKey,
             .apiKeyUnavailable,
             .invalidRecording,
             .invalidRequest,
             .multipartMetadataTooLarge,
             .invalidAPIKey,
             .rateLimited,
             .providerUnavailable,
             .badRequest,
             .providerRejected,
             .invalidResponse,
             .emptyTranscript,
             .dictionaryEcho,
             .contextEcho:
            return true
        }
    }

    private static func recordingTerminalCause(
        automaticCompletion: AudioRecorderAutomaticCompletion?,
        userFinishOwnedAuthority: Bool
    ) -> RecordingTerminalCause {
        if let automaticCompletion {
            switch automaticCompletion.reason {
            case .maximumDuration:
                return .configuredLimit
            case .unexpected:
                return .platformInterrupted
            }
        }
        if userFinishOwnedAuthority {
            return .userFinished
        }
        return .platformInterrupted
    }

    private func recordRecordingTerminal(
        cause: RecordingTerminalCause,
        attemptID: UUID,
        durability: RecordingDurabilityOutcome,
        providerAuthorized: Bool
    ) {
        guard loggedTerminalAttemptIDs.insert(attemptID).inserted else {
            return
        }
        eventLogger.record(
            .recordingTerminal(
                cause: cause,
                attemptID: attemptID,
                durability: durability,
                providerAuthorized: providerAuthorized
            )
        )
    }

    func repairInterruptedRecordings() {
        let recoveredCount = recordingCaptureJournal.repairInterruptedCaptures(
            into: transcriptionFailureRecovery,
            onRepair: { [weak self] attemptID, durability in
                self?.recordRecordingTerminal(
                    cause: .ownerTeardown,
                    attemptID: attemptID,
                    durability: durability,
                    providerAuthorized: false
                )
            }
        )
        guard recoveredCount > 0 else {
            return
        }

        outputStatusText = recoveredCount == 1
            ? "An interrupted recording was recovered to History."
            : "\(recoveredCount) interrupted recordings were recovered to History."
    }

    func prepareForTermination() async {
        terminationRequested = true
        activeRecordingStopTailTask?.cancel()
        stopRecordingDurationMonitoring()

        if status.voiceWorkPhase == .processing {
            markActiveRecoveryCheckpointInterrupted()
            transcriptionService.cancelActiveTranscription()
            transcriptPipeline.cancelActivePostProcessing()
            cancelActiveSession()
            status = .idle
            return
        }

        guard status.voiceWorkPhase == .listening,
              !isPerformingAction,
              let sessionID = activeSessionID else {
            // The start/stop action already in flight still owns the recorder.
            // Its start-time journal is the bounded termination fallback.
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }
        let settings = activeRecordingSettings ?? settingsProvider()
        let completionKind = completionKindForDeferredTerminalOutcome()
        deferredRecordingTerminalOutcome = nil

        do {
            let artifact = try await recorder.stopRecording()
            let checkpoint = try transcriptionFailureRecovery.recordProcessingCheckpoint(
                audioFileURL: artifact.fileURL,
                settings: settings,
                audioDuration: artifact.duration,
                completionKind: completionKind
            )
            try? transcriptionFailureRecovery.updateFailedAttempt(
                id: checkpoint.id,
                reason: .processingInterrupted
            )
            if let captureLease = activeRecordingCaptureLease {
                try? recordingCaptureJournal.retireCaptureAfterRecovery(
                    captureLease,
                    recoveryAttemptID: checkpoint.id
                )
            } else {
                try? recordingCache.handleCompletedRecording(
                    artifact,
                    policy: .deleteImmediately
                )
            }
            activeRecordingCaptureLease = nil
            activeRecordingSettings = nil
            recordRecordingTerminal(
                cause: .ownerTeardown,
                attemptID: checkpoint.id,
                durability: .historyCheckpoint,
                providerAuthorized: false
            )
        } catch {
            _ = preserveInterruptedCapture(
                completionKind: completionKind,
                terminalCause: .ownerTeardown
            )
        }

        finishSession(sessionID)
        status = .idle
    }

    private func deferRecordingTerminalOutcome(
        _ outcome: DeferredRecordingTerminalOutcome
    ) {
        guard let existing = deferredRecordingTerminalOutcome else {
            deferredRecordingTerminalOutcome = outcome
            return
        }

        switch (existing, outcome) {
        case (.maximumDurationAwaitingArtifact, _):
            return
        case (_, .maximumDurationAwaitingArtifact):
            deferredRecordingTerminalOutcome = outcome
        case (.automatic(.success(let completion)), _)
            where completion.reason == .maximumDuration:
            return
        case (_, .automatic(.success(let completion)))
            where completion.reason == .maximumDuration:
            deferredRecordingTerminalOutcome = outcome
        case (.automatic(.success(_)), .automatic(.failure(_))):
            return
        default:
            deferredRecordingTerminalOutcome = outcome
        }
    }

    private func takeDeferredRecordingTerminalOutcome() -> DeferredRecordingTerminalOutcome? {
        defer { deferredRecordingTerminalOutcome = nil }
        return deferredRecordingTerminalOutcome
    }

    private func completionKindForDeferredTerminalOutcome() -> TranscriptionRecoveryCompletionKind {
        switch deferredRecordingTerminalOutcome {
        case .maximumDurationAwaitingArtifact:
            return .maximumDuration
        case .automatic(.success(let completion)) where completion.reason == .maximumDuration:
            return .maximumDuration
        case .automatic(_), nil:
            return .standard
        }
    }

    private func preserveInterruptedCapture(
        completionKind: TranscriptionRecoveryCompletionKind,
        reuseCheckpointFallback: Bool = false,
        terminalCause: RecordingTerminalCause?,
        providerAuthorized: Bool = false
    ) -> FailedTranscriptionAttempt? {
        guard let captureLease = activeRecordingCaptureLease else {
            return nil
        }
        let settings = activeRecordingSettings ?? settingsProvider()
        var terminalAttemptID = captureLease.id
        var terminalDurability = RecordingDurabilityOutcome.protectedCapture
        defer {
            if let terminalCause {
                recordRecordingTerminal(
                    cause: terminalCause,
                    attemptID: terminalAttemptID,
                    durability: terminalDurability,
                    providerAuthorized: providerAuthorized
                )
            }
            activeRecordingCaptureLease = nil
            activeRecordingSettings = nil
        }

        switch recordingCaptureJournal.inspectCapture(
            captureLease,
            fallbackDuration: 0
        ) {
        case .nonempty(let artifact):
            if reuseCheckpointFallback {
                let fallback = transcriptionFailureRecovery.retainEmergencyFallback(
                    audioFileURL: artifact.fileURL,
                    settings: settings,
                    audioDuration: artifact.duration > 0 ? artifact.duration : nil,
                    reason: .recoveryOwnershipPersistenceFailed,
                    completionKind: completionKind
                )
                if let fallback,
                   fallback.audioFileURL.standardizedFileURL
                    != artifact.fileURL.standardizedFileURL {
                    try? recordingCaptureJournal.retireCaptureAfterRecovery(
                        captureLease,
                        recoveryAttemptID: fallback.id
                    )
                }
                if let fallback {
                    terminalAttemptID = fallback.id
                    terminalDurability = .emergencyFallback
                }
                // When fallback ownership is the capture itself, its marker
                // remains the durable launch-repair owner. The controller
                // still releases this lease so a later recording cannot
                // accidentally overwrite its in-memory identity.
                return fallback
            }
            do {
                let checkpoint = try transcriptionFailureRecovery.recordProcessingCheckpoint(
                    audioFileURL: artifact.fileURL,
                    settings: settings,
                    audioDuration: artifact.duration > 0 ? artifact.duration : nil,
                    completionKind: completionKind
                )
                try? transcriptionFailureRecovery.updateFailedAttempt(
                    id: checkpoint.id,
                    reason: .processingInterrupted
                )
                try? recordingCaptureJournal.retireCaptureAfterRecovery(
                    captureLease,
                    recoveryAttemptID: checkpoint.id
                )
                terminalAttemptID = checkpoint.id
                terminalDurability = .historyCheckpoint
                return transcriptionFailureRecovery.failedAttempts.first {
                    $0.id == checkpoint.id
                } ?? checkpoint
            } catch {
                let fallback = transcriptionFailureRecovery.retainEmergencyFallback(
                    audioFileURL: artifact.fileURL,
                    settings: settings,
                    audioDuration: artifact.duration > 0 ? artifact.duration : nil,
                    reason: .recoveryOwnershipPersistenceFailed,
                    completionKind: completionKind
                )
                if let fallback,
                   fallback.audioFileURL.standardizedFileURL
                    != artifact.fileURL.standardizedFileURL {
                    try? recordingCaptureJournal.retireCaptureAfterRecovery(
                        captureLease,
                        recoveryAttemptID: fallback.id
                    )
                }
                if let fallback {
                    terminalAttemptID = fallback.id
                    terminalDurability = .emergencyFallback
                }
                return fallback
            }
        case .empty, .missing:
            try? recordingCaptureJournal.discardCapture(captureLease)
            terminalDurability = .emptyOrMissingDiscarded
            return nil
        case .unavailable:
            // Keep the durable marker and reserved path for launch repair.
            return nil
        }
    }

    private func handleRecordingFinalizationFailure(
        _ error: AudioRecorderServiceError,
        sessionID: Int,
        completionKind: TranscriptionRecoveryCompletionKind
    ) {
        let recoveredAttempt = preserveInterruptedCapture(
            completionKind: completionKind,
            terminalCause: .platformInterrupted
        )
        stopRecordingDurationMonitoring()
        finishSession(sessionID)
        recordFailure(error, at: .recordingFinalization)
        let message = Self.userFacingMessage(for: error)
        if recoveredAttempt != nil {
            outputStatusText = "Recording interrupted — saved to History."
        }
        status = .failure(message: message)
        failurePresentation = failurePresentation(
            message: message,
            error: error,
            failedAttempt: recoveredAttempt,
            showsRecoveryPrompt: recoveredAttempt != nil
        )
    }

    private func handleAutomaticRecorderStop(
        _ result: Result<AudioRecorderAutomaticCompletion, AudioRecorderServiceError>
    ) {
        guard status.voiceWorkPhase == .listening else {
            return
        }
        if case .success(let completion) = result {
            let recorderReportedSuccess: Bool?
            switch completion.reason {
            case .maximumDuration:
                recorderReportedSuccess = completion.recorderReportedSuccess
            case .unexpected(let reportedSuccess):
                recorderReportedSuccess = reportedSuccess
            }
            if recorderReportedSuccess == false {
                eventLogger.record(
                    .recordingEndedUnexpectedly(
                        recorderReportedSuccess: false
                    )
                )
            }
        }
        guard !isPerformingAction else {
            deferRecordingTerminalOutcome(.automatic(result))
            return
        }
        guard status.voiceWorkPhase == .listening,
              beginExclusiveAction() else {
            return
        }

        deferredRecordingTerminalOutcome = nil
        stopRecordingDurationMonitoring()
        let intent = activeOutputIntent ?? .standard
        let credential = activeCredential

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            defer { self.completeExclusiveAction() }

            switch result {
            case .success(let completion):
                switch completion.reason {
                case .maximumDuration:
                    self.eventLogger.record(.recordingLimitReached)
                case .unexpected(let recorderReportedSuccess):
                    if recorderReportedSuccess {
                        self.eventLogger.record(
                            .recordingEndedUnexpectedly(
                                recorderReportedSuccess: true
                            )
                        )
                    }
                }
                await self.stopRecordingAndTranscribe(
                    intent: intent,
                    credential: credential,
                    automaticCompletion: completion
                )
            case .failure(let error):
                guard let sessionID = self.activeSessionID else {
                    return
                }

                self.handleRecordingFinalizationFailure(
                    error,
                    sessionID: sessionID,
                    completionKind: self.completionKindForDeferredTerminalOutcome()
                )
            }
        }
    }

    private func handleRecordingMaximumDurationWatchdog() {
        guard status.voiceWorkPhase == .listening else {
            return
        }
        guard beginExclusiveAction() else {
            deferRecordingTerminalOutcome(.maximumDurationAwaitingArtifact)
            return
        }

        deferredRecordingTerminalOutcome = nil
        recordingCountdown = nil
        let intent = activeOutputIntent ?? .standard
        let credential = activeCredential
        eventLogger.record(.recordingLimitReached)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            defer { self.completeExclusiveAction() }
            await self.stopRecordingAndTranscribe(
                intent: intent,
                credential: credential,
                automaticReasonAwaitingArtifact: .maximumDuration
            )
        }
    }

    private func waitForRecordingStopTail(settings: AppSettings) async throws {
        let duration = settings.recordingStopTailDuration.duration
        guard duration > 0 else {
            return
        }

        eventLogger.record(.recordingStopTailStarted(duration: duration))
        let tailTask = Task { @MainActor in
            try await recordingStopTailSleeper.sleep(seconds: duration)
        }
        activeRecordingStopTailTask = tailTask
        defer {
            activeRecordingStopTailTask = nil
        }

        try await tailTask.value
        eventLogger.record(.recordingStopTailFinished(duration: duration))
    }

    private func playCue(_ cue: DictationCue, settings: AppSettings) {
        guard settings.soundEnabled else {
            return
        }

        cuePlayer.play(cue)
    }

    private func startRecordingDurationMonitoring(
        sessionID: Int,
        settings: AppSettings
    ) {
        recordingCountdown = nil
        let schedule = VoiceSessionWarningSchedule(
            limit: settings.recordingDurationLimit
        )
        recordingDurationMonitor.start(
            maximumDurationWholeSeconds: schedule.maximumDurationWholeSeconds
        ) { [weak self] elapsedWholeSecond in
            guard let self,
                  self.isCurrentSession(sessionID),
                  self.status.voiceWorkPhase == .listening else {
                return
            }

            if elapsedWholeSecond >= schedule.maximumDurationWholeSeconds {
                self.handleRecordingMaximumDurationWatchdog()
                return
            }

            self.recordingCountdown = schedule.countdown(
                atElapsedWholeSecond: elapsedWholeSecond
            )
            guard let warning = schedule.warning(
                atElapsedWholeSecond: elapsedWholeSecond
            ),
                settings.soundEnabled,
                self.privateAudioOutputRouteProvider.isPrivateAudioOutputRoute()
            else {
                return
            }

            self.cuePlayer.play(.recordingLimitWarning(warning.urgency))
        }
    }

    private func stopRecordingDurationMonitoring() {
        recordingDurationMonitor.stop()
        recordingCountdown = nil
    }

    private static func finalizedArtifactReachedMaximumDuration(
        _ artifact: AudioRecordingArtifact,
        limit: RecordingDurationLimit
    ) -> Bool {
        let threshold = limit.duration
            - maximumDurationClassificationTolerance
        return artifact.duration.isFinite && artifact.duration >= threshold
    }

    @discardableResult
    private func recordRecoveryHistory(
        _ acceptedTranscript: AcceptedTranscript,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        cachedAudioFileURL: URL?
    ) -> Bool {
        let request = settings.acceptedTranscriptHistoryRequest(
            acceptedTranscript: acceptedTranscript,
            audioDuration: audioDuration,
            cachedAudioFileURL: cachedAudioFileURL
        )

        do {
            try transcriptHistory.recordAcceptedTranscript(request)
            return true
        } catch {
            outputStatusText = Self.userFacingMessage(for: error)
            return false
        }
    }

    private func recordFailedTranscriptionAttempt(
        _ error: Error,
        at stage: VoiceAttemptStage,
        artifact: AudioRecordingArtifact?,
        settings: AppSettings?
    ) -> (attempt: FailedTranscriptionAttempt?, allowsRecordingCacheHandling: Bool) {
        guard stage == .transcription,
              let artifact,
              let settings else {
            return (nil, true)
        }

        let reason = FailedTranscriptionReason(error: error)
        guard reason.shouldRecordFailedAttempt else {
            return (nil, true)
        }

        do {
            return (
                try transcriptionFailureRecovery.recordFailedAttempt(
                    audioFileURL: artifact.fileURL,
                    settings: settings,
                    audioDuration: artifact.duration,
                    reason: reason
                ),
                true
            )
        } catch {
            outputStatusText = Self.userFacingMessage(for: error)
            return (nil, false)
        }
    }

    private func recordSuccessfulTranscriptionUsage(
        transcriptionID: UUID,
        model: String,
        audioDuration: TimeInterval?
    ) {
        guard let audioDuration,
              let usage = try? SuccessfulTranscriptionUsage(
                  transcriptionID: transcriptionID,
                  model: model,
                  audioDuration: audioDuration
              ) else {
            return
        }

        transcriptionUsageRecorder.recordSuccessfulTranscriptionUsage(usage)
    }

    private func updateCompletedRecordingCacheIfNeeded(
        artifact: AudioRecordingArtifact?,
        settings: AppSettings?
    ) {
        guard let artifact, let settings else {
            return
        }

        updateRecordingCache(for: artifact, settings: settings)
    }

    private func updateRecordingCache(for artifact: AudioRecordingArtifact, settings: AppSettings) {
        do {
            try recordingCache.handleCompletedRecording(
                artifact,
                policy: settings.recordingCachePolicy
            )
            eventLogger.record(.recordingCacheHandled(policy: settings.recordingCachePolicy))
        } catch {
            eventLogger.record(.recordingCacheFailed(category: Self.operatorLogCategory(for: error)))
            guard outputStatusText == nil else {
                return
            }

            outputStatusText = Self.userFacingMessage(for: error)
        }
    }

    private func resolvedCredential(providedCredential: OpenAICredential?) throws -> OpenAICredential {
        if let providedCredential {
            return providedCredential
        }

        if let activeCredential {
            return activeCredential
        }

        guard let credentialResolverForUngatedActions else {
            throw OpenAITranscriptionServiceError.missingAPIKey
        }

        do {
            return try credentialResolverForUngatedActions.resolveOpenAICredential()
        } catch let error as OpenAICredentialResolutionError {
            throw error.transcriptionServiceError
        } catch {
            throw OpenAITranscriptionServiceError.apiKeyUnavailable
        }
    }

    private static func acceptedTranscript(from rawText: String) throws -> AcceptedTranscript {
        do {
            return try AcceptedTranscript(rawText: rawText)
        } catch AcceptedTranscript.ValidationError.emptyText {
            throw OpenAITranscriptionServiceError.emptyTranscript
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return description
        }

        return error.localizedDescription
    }

    private func failurePresentation(
        message: String,
        error: Error,
        failedAttempt: FailedTranscriptionAttempt?,
        showsRecoveryPrompt: Bool = false
    ) -> DictationFailurePresentation {
        if let translationIssue = error as? TranslationConfigurationIssue {
            return DictationFailurePresentation(
                title: translationIssue.title,
                message: message,
                settingsTarget: .translation
            )
        }

        let reason = failedAttempt?.reason ?? FailedTranscriptionReason(error: error)
        return DictationFailurePresentation(
            title: reason.title,
            message: failedAttempt == nil ? message : reason.message,
            failedAttemptID: failedAttempt?.id,
            settingsTarget: reason.settingsTarget,
            canRetry: reason.canRetry,
            showsRecoveryPrompt: showsRecoveryPrompt
        )
    }

    private func recordFailure(_ error: Error, at stage: VoiceAttemptStage) {
        let category = Self.operatorLogCategory(for: error)

        switch stage {
        case .recordingFinalization:
            eventLogger.record(.recordingStopFailed(category: category))
        case .transcription:
            eventLogger.record(.transcriptionFailed(category: category))
        case .postProcessing:
            eventLogger.record(.postProcessingFailed(category: category))
        case .outputDelivery:
            eventLogger.record(.outputDeliveryFailed(category: category))
        }
    }

    private static func operatorLogCategory(for error: Error) -> String {
        DictationFailureLogClassifier.category(for: error)
    }
}
