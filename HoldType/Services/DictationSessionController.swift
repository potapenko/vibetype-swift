//
//  DictationSessionController.swift
//  HoldType
//
//  Created by Codex on 6/22/26.
//

import Foundation
import HoldTypeDomain

protocol TranscriptOutputDelivering {
    func deliver(_ transcript: String, settings: AppSettings) async throws -> TextInsertionResult
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
    private let recorder: any AudioRecorderService
    private let transcriptionService: any OpenAITranscriptionServing
    private let textCorrectionService: any TextCorrectionServing
    private let translationService: any TranscriptTranslationServing
    private let settingsProvider: () -> AppSettings
    private let transcriptOutput: any TranscriptOutputDelivering
    private let cuePlayer: any DictationCuePlaying
    private let transcriptHistory: any TranscriptRecoveryHistoryRecording
    private let transcriptionFailureRecovery: any TranscriptionFailureRecoveryRecording
    private let activeTextContextReader: any ActiveTextContextReading
    private let transcriptionUsageRecorder: any TranscriptionUsageRecording
    private let transcriptionIDGenerator: () -> UUID
    private let recordingCache: any RecordingCacheLifecycleHandling
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

    var statusDidChange: (@MainActor (DictationStatus) -> Void)?
    var lastTranscriptTextDidChange: (@MainActor (String?) -> Void)?
    var outputStatusTextDidChange: (@MainActor (String?) -> Void)?
    var failurePresentationDidChange: (@MainActor (DictationFailurePresentation?) -> Void)?

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
        transcriptHistory: (any TranscriptRecoveryHistoryRecording)? = nil,
        transcriptionFailureRecovery: (any TranscriptionFailureRecoveryRecording)? = nil,
        activeTextContextReader: (any ActiveTextContextReading)? = nil,
        transcriptionUsageRecorder: (any TranscriptionUsageRecording)? = nil,
        transcriptionIDGenerator: @escaping () -> UUID = UUID.init,
        recordingCache: any RecordingCacheLifecycleHandling = RecordingCacheService.shared,
        recordingStopTailSleeper: any RecordingStopTailSleeping = TaskRecordingStopTailSleeper(),
        eventLogger: any DictationEventLogging = OSLogDictationEventLogger(),
        credentialResolverForUngatedActions: (any OpenAICredentialResolving)? = nil,
        initialStatus: DictationStatus = .idle,
        lastTranscriptText: String? = nil,
        outputStatusText: String? = nil
    ) {
        self.recorder = recorder
        self.transcriptionService = transcriptionService
        self.textCorrectionService = textCorrectionService
        self.translationService = translationService
        self.settingsProvider = settingsProvider
        self.transcriptOutput = transcriptOutput
        self.cuePlayer = cuePlayer
        self.transcriptHistory = transcriptHistory ?? TranscriptRecoveryHistoryStore.shared
        self.transcriptionFailureRecovery = transcriptionFailureRecovery
            ?? TranscriptionFailureRecoveryStore.shared
        self.activeTextContextReader = activeTextContextReader ?? ActiveTextContextService()
        self.transcriptionUsageRecorder = transcriptionUsageRecorder ?? OpenAIUsageStore.shared
        self.transcriptionIDGenerator = transcriptionIDGenerator
        self.recordingCache = recordingCache
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
    }

    func performRecordingAction(
        intent: DictationOutputIntent = .standard,
        credential: OpenAICredential? = nil
    ) async {
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
            recorder.cancelRecording()
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
            transcriptionService.cancelActiveTranscription()
            textCorrectionService.cancelActiveCorrection()
            translationService.cancelActiveTranslation()
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

        outputStatusText = nil
        failurePresentation = nil
        var sessionID: Int?

        do {
            let credential = try resolvedCredential(providedCredential: retry.credential)
            sessionID = beginSession(intent: .standard)
            activeCredential = credential
            status = .transcribing
            let settings = settingsProvider()
            eventLogger.record(.transcriptionStarted)
            let transcriptionID = transcriptionIDGenerator()
            let rawTranscript = try await transcriptionService.transcribe(
                audioFileURL: attempt.audioFileURL,
                settings: settings,
                context: nil,
                credential: credential
            )
            eventLogger.record(.transcriptionSucceeded)
            guard let sessionID, isCurrentSession(sessionID) else {
                return
            }

            let transcribedTranscript = try Self.acceptedTranscript(from: rawTranscript)
            recordSuccessfulTranscriptionUsage(
                transcriptionID: transcriptionID,
                model: settings.resolvedTranscriptionModel,
                audioDuration: attempt.audioDuration
            )
            let correctedTranscriptText = await correctedTranscriptText(
                from: transcribedTranscript.text,
                settings: settings,
                credential: credential
            )
            guard isCurrentSession(sessionID) else {
                return
            }

            let acceptedTranscript = try Self.acceptedTranscript(from: correctedTranscriptText)
            lastTranscriptText = acceptedTranscript.text
            status = .success(transcript: acceptedTranscript.text)
            failurePresentation = nil

            recordRecoveryHistory(
                acceptedTranscript.text,
                settings: settings,
                audioDuration: attempt.audioDuration,
                cachedAudioFileURL: nil
            )
            transcriptionFailureRecovery.removeFailedAttempt(id: retry.id)

            let recoveryOutputSettings = outputSettings(
                from: settings,
                retryOutputMode: retry.outputMode
            )
            do {
                outputStatusText = try await transcriptOutput.deliver(
                    acceptedTranscript.text,
                    settings: recoveryOutputSettings
                ).statusText
            } catch {
                guard isCurrentSession(sessionID) else {
                    return
                }

                eventLogger.record(.outputDeliveryFailed(category: Self.operatorLogCategory(for: error)))
                outputStatusText = Self.userFacingMessage(for: error)
            }

            finishSession(sessionID)
        } catch {
            if let sessionID, !isCurrentSession(sessionID) {
                return
            }

            let reason = FailedTranscriptionReason(error: error)
            try? transcriptionFailureRecovery.updateFailedAttempt(id: retry.id, reason: reason)
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
        runPendingFailedTranscriptionRetryIfNeeded()
    }

    private func runPendingFailedTranscriptionRetryIfNeeded() {
        guard !isPerformingAction,
              let retry = pendingFailedTranscriptionRetry else {
            return
        }

        pendingFailedTranscriptionRetry = nil
        Task { @MainActor in
            await retryFailedTranscription(
                id: retry.id,
                credential: retry.credential,
                outputMode: retry.outputMode
            )
        }
    }

    private func outputSettings(
        from settings: AppSettings,
        retryOutputMode: FailedTranscriptionRetryOutputMode
    ) -> AppSettings {
        switch retryOutputMode {
        case .saveOnly:
            var recoveryOutputSettings = settings
            recoveryOutputSettings.automaticallyInsertTranscripts = false
            return recoveryOutputSettings
        case .followAutomaticInsertion:
            return settings
        }
    }

    private func beginSession(intent: DictationOutputIntent) -> Int {
        nextSessionID += 1
        activeSessionID = nextSessionID
        activeOutputIntent = intent
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
    }

    private func cancelActiveSession() {
        activeSessionID = nil
        activeOutputIntent = nil
        activeCredential = nil
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
        eventLogger.record(.recordingStartRequested)

        do {
            try await recorder.startRecording()
            guard isCurrentSession(sessionID) else {
                return
            }

            status = .recording
            eventLogger.record(.recordingStarted)
            playCue(.startRecording, settings: settings)
        } catch {
            finishSession(sessionID)
            eventLogger.record(.recordingStartFailed(category: Self.operatorLogCategory(for: error)))
            status = .failure(message: Self.userFacingMessage(for: error))
        }
    }

    private func stopRecordingAndTranscribe(intent: DictationOutputIntent, credential: OpenAICredential?) async {
        outputStatusText = nil
        failurePresentation = nil
        let sessionID = currentOrNewSessionID(intent: intent)
        let outputIntent = currentOutputIntent(fallback: intent)
        var stage: DictationSessionStage = .recordingStop
        var completedArtifact: AudioRecordingArtifact?
        var completedRecordingSettings: AppSettings?
        var allowsRecordingCacheHandling = true
        defer {
            if allowsRecordingCacheHandling {
                updateCompletedRecordingCacheIfNeeded(
                    artifact: completedArtifact,
                    settings: completedRecordingSettings
                )
            }
        }

        do {
            eventLogger.record(.recordingStopRequested)
            let settings = settingsProvider()
            try await waitForRecordingStopTail(settings: settings)
            let artifact = try await recorder.stopRecording()
            completedArtifact = artifact
            eventLogger.record(
                .recordingStopped(duration: artifact.duration, byteCount: artifact.byteCount)
            )

            completedRecordingSettings = settings

            guard isCurrentSession(sessionID) else {
                return
            }

            if outputIntent == .translate,
               let translationIssue = settings.translationConfigurationIssue {
                stage = .postProcessing
                throw translationIssue
            }

            playCue(.stopRecording, settings: settings)
            status = .transcribing

            let credential = try resolvedCredential(providedCredential: credential)
            activeCredential = credential
            stage = .transcription
            let transcriptionSettings = transcriptionSettings(for: outputIntent, settings: settings)
            completedRecordingSettings = transcriptionSettings
            let context = activeTextContextReader.currentContext(settings: transcriptionSettings)
            eventLogger.record(.transcriptionStarted)
            let transcriptionID = transcriptionIDGenerator()
            let rawTranscript = try await transcriptionService.transcribe(
                audioFileURL: artifact.fileURL,
                settings: transcriptionSettings,
                context: context,
                credential: credential
            )
            eventLogger.record(.transcriptionSucceeded)
            guard isCurrentSession(sessionID) else {
                return
            }

            let transcribedTranscript = try Self.acceptedTranscript(from: rawTranscript)
            recordSuccessfulTranscriptionUsage(
                transcriptionID: transcriptionID,
                model: transcriptionSettings.resolvedTranscriptionModel,
                audioDuration: artifact.duration
            )
            stage = .postProcessing
            let correctedTranscriptText = await correctedTranscriptText(
                from: transcribedTranscript.text,
                settings: settings,
                credential: credential
            )
            guard isCurrentSession(sessionID) else {
                return
            }

            let outputText = try await postActionTranscriptText(
                from: correctedTranscriptText,
                intent: outputIntent,
                settings: settings,
                credential: credential
            )
            guard isCurrentSession(sessionID) else {
                return
            }

            let acceptedTranscript = try Self.acceptedTranscript(from: outputText)
            lastTranscriptText = acceptedTranscript.text
            status = .success(transcript: acceptedTranscript.text)
            failurePresentation = nil
            recordRecoveryHistory(
                acceptedTranscript.text,
                settings: settings,
                audioDuration: artifact.duration,
                cachedAudioFileURL: artifact.fileURL
            )

            stage = .outputDelivery
            do {
                outputStatusText = try await transcriptOutput.deliver(
                    acceptedTranscript.text,
                    settings: settings
                ).statusText
            } catch {
                guard isCurrentSession(sessionID) else {
                    return
                }

                eventLogger.record(.outputDeliveryFailed(category: Self.operatorLogCategory(for: error)))
                outputStatusText = Self.userFacingMessage(for: error)
            }

            finishSession(sessionID)
        } catch is CancellationError {
            guard isCurrentSession(sessionID) else {
                return
            }

            recorder.cancelRecording()
            finishSession(sessionID)
            activeCredential = nil
            outputStatusText = nil
            failurePresentation = nil
            status = .idle
        } catch {
            guard isCurrentSession(sessionID) else {
                return
            }

            let recoveryResult = recordFailedTranscriptionAttempt(
                error,
                at: stage,
                artifact: completedArtifact,
                settings: completedRecordingSettings
            )
            allowsRecordingCacheHandling = recoveryResult.allowsRecordingCacheHandling
            finishSession(sessionID)
            recordFailure(error, at: stage)
            let message = Self.userFacingMessage(for: error)
            status = .failure(message: message)
            failurePresentation = failurePresentation(
                message: message,
                error: error,
                failedAttempt: recoveryResult.attempt,
                showsRecoveryPrompt: stage == .transcription
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

    private func recordRecoveryHistory(
        _ transcript: String,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        cachedAudioFileURL: URL?
    ) {
        do {
            try transcriptHistory.recordAcceptedTranscript(
                transcript,
                settings: settings,
                audioDuration: audioDuration,
                cachedAudioFileURL: cachedAudioFileURL
            )
        } catch {
            outputStatusText = Self.userFacingMessage(for: error)
        }
    }

    private func recordFailedTranscriptionAttempt(
        _ error: Error,
        at stage: DictationSessionStage,
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

    private func correctedTranscriptText(
        from transcript: String,
        settings: AppSettings,
        credential: OpenAICredential
    ) async -> String {
        do {
            return try await textCorrectionService.correct(
                transcript,
                settings: settings,
                credential: credential
            )
        } catch {
            return transcript
        }
    }

    private func transcriptionSettings(for intent: DictationOutputIntent, settings: AppSettings) -> AppSettings {
        guard intent == .translate,
              settings.translationShortcutEnabled,
              settings.translationSourceMode == .override,
              settings.isTranslationSourceConfigurationValid else {
            return settings
        }

        var transcriptionSettings = settings
        transcriptionSettings.language = settings.translationSourceLanguage
        transcriptionSettings.customLanguageCode = settings.customTranslationSourceLanguageCode
        return transcriptionSettings
    }

    private func postActionTranscriptText(
        from transcript: String,
        intent: DictationOutputIntent,
        settings: AppSettings,
        credential: OpenAICredential
    ) async throws -> String {
        guard intent == .translate else {
            return transcript
        }

        guard settings.translationShortcutEnabled else {
            return transcript
        }

        guard settings.canRunTranslation else {
            throw OpenAITextTranslationServiceError.invalidLanguageConfiguration
        }

        let translatedTranscript = try await translationService.translate(
            transcript,
            settings: settings,
            credential: credential
        )
        return finalTranslatedTranscriptText(translatedTranscript, settings: settings)
    }

    private func finalTranslatedTranscriptText(_ transcript: String, settings: AppSettings) -> String {
        guard settings.localTextCleanupEnabled else {
            return transcript
        }

        return TranscriptTextPostProcessor.normalizedInformalTypography(from: transcript)
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

    private func recordFailure(_ error: Error, at stage: DictationSessionStage) {
        let category = Self.operatorLogCategory(for: error)

        switch stage {
        case .recordingStop:
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
        if let error = error as? AudioRecorderServiceError {
            return error.operatorLogCategory
        }

        if let error = error as? OpenAITranscriptionServiceError {
            return error.operatorLogCategory
        }

        if let error = error as? OpenAITextCorrectionServiceError {
            return error.operatorLogCategory
        }

        if let error = error as? OpenAITextTranslationServiceError {
            return error.operatorLogCategory
        }

        if let error = error as? TextInsertionServiceError {
            return error.operatorLogCategory
        }

        if let error = error as? RecordingCacheServiceError {
            return error.operatorLogCategory
        }

        if let error = error as? TranslationConfigurationIssue {
            return error.operatorLogCategory
        }

        return "unknown"
    }
}

private enum DictationSessionStage {
    case recordingStop
    case transcription
    case postProcessing
    case outputDelivery
}

private extension AudioRecorderServiceError {
    var operatorLogCategory: String {
        switch self {
        case .alreadyRecording:
            return "already_recording"
        case .notRecording:
            return "not_recording"
        case .microphonePermissionDenied:
            return "microphone_permission_denied"
        case .recordingUnavailable:
            return "recording_unavailable"
        case .temporaryFileUnavailable:
            return "temporary_file_unavailable"
        case .startFailed:
            return "start_failed"
        case .stopFailed:
            return "stop_failed"
        case .cancelCleanupFailed:
            return "cancel_cleanup_failed"
        case .missingRecordingFile:
            return "missing_recording_file"
        case .emptyRecording:
            return "empty_recording"
        case .recordingTooShort:
            return "recording_too_short"
        case .recordingTimedOut:
            return "recording_timed_out"
        }
    }
}

private extension OpenAITextCorrectionServiceError {
    var operatorLogCategory: String {
        switch self {
        case .missingAPIKey:
            return "missing_api_key"
        case .apiKeyUnavailable:
            return "api_key_unavailable"
        case .invalidRequest:
            return "invalid_request"
        case .timedOut:
            return "timeout"
        case .networkUnavailable:
            return "network_unavailable"
        case .networkFailure:
            return "network_failure"
        case .cancelled:
            return "cancelled"
        case .invalidAPIKey:
            return "invalid_api_key"
        case .rateLimited:
            return "rate_limited"
        case .providerUnavailable:
            return "provider_unavailable"
        case .badRequest:
            return "bad_request"
        case .providerRejected(let statusCode):
            return "provider_rejected_\(statusCode)"
        case .invalidResponse:
            return "invalid_response"
        case .emptyCorrection:
            return "empty_correction"
        }
    }
}

private extension OpenAITextTranslationServiceError {
    var operatorLogCategory: String {
        switch self {
        case .missingAPIKey:
            return "missing_api_key"
        case .apiKeyUnavailable:
            return "api_key_unavailable"
        case .invalidRequest:
            return "invalid_request"
        case .timedOut:
            return "timeout"
        case .networkUnavailable:
            return "network_unavailable"
        case .networkFailure:
            return "network_failure"
        case .cancelled:
            return "cancelled"
        case .invalidAPIKey:
            return "invalid_api_key"
        case .rateLimited:
            return "rate_limited"
        case .providerUnavailable:
            return "provider_unavailable"
        case .badRequest:
            return "bad_request"
        case .invalidLanguageConfiguration:
            return "invalid_language_configuration"
        case .providerRejected(let statusCode):
            return "provider_rejected_\(statusCode)"
        case .invalidResponse:
            return "invalid_response"
        case .emptyTranslation:
            return "empty_translation"
        }
    }
}

private extension TranslationConfigurationIssue {
    var operatorLogCategory: String {
        switch self {
        case .invalidSourceLanguage:
            return "invalid_translation_source_language"
        case .missingTargetLanguage:
            return "missing_translation_target_language"
        }
    }
}

private extension TextInsertionServiceError {
    var operatorLogCategory: String {
        switch self {
        case .emptyAppClipboardText:
            return "empty_app_clipboard_text"
        case .textEventUnavailable:
            return "text_event_unavailable"
        case .textInsertionFailed:
            return "text_insertion_failed"
        case .textInsertionTimedOut:
            return "text_insertion_timed_out"
        }
    }
}

private extension RecordingCacheServiceError {
    var operatorLogCategory: String {
        switch self {
        case .directoryUnavailable:
            return "directory_unavailable"
        case .listingFailed:
            return "listing_failed"
        case .unsupportedRecordingURL:
            return "unsupported_recording_url"
        case .deleteFailed:
            return "delete_failed"
        case .clearFailed:
            return "clear_failed"
        }
    }
}
