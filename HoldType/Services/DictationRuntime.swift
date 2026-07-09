//
//  DictationRuntime.swift
//  HoldType
//
//  Created by Codex on 7/6/26.
//

import Combine
import Foundation
import HoldTypeDomain

@MainActor
final class DictationRuntime: ObservableObject {
    static let shared = DictationRuntime()

    @Published private(set) var status: DictationStatus
    @Published private(set) var lastTranscriptText: String?
    @Published private(set) var outputStatusText: String?
    @Published private(set) var failurePresentation: DictationFailurePresentation?
    @Published private(set) var hotkeyRegistrationStatus: GlobalHotkeyRegistrationStatus
    @Published private(set) var appSettings: AppSettings
    @Published private(set) var isLastResultPasteAvailable: Bool

    let preferredHotkeyConfiguration: GlobalHotkeyConfiguration

    private let controller: DictationSessionController
    private let appSettingsStore: AppSettingsStore
    private let recordingSetupPreflight: RecordingSetupPreflight
    private let credentialResolver: any OpenAICredentialResolving
    private let settingsPresenter: any SetupSettingsPresenting
    private let hotkeyService: any GlobalHotkeyService
    private let pasteLastResultService: SpecialClipboardPasteService
    private let transcriptClipboardStore: any TranscriptClipboardStoring

    private var hotkeyCoordinator: DictationHotkeyCoordinator?
    private var settingsObserver: NSObjectProtocol?

    init(
        controller: DictationSessionController? = nil,
        appSettingsStore: AppSettingsStore? = nil,
        recordingSetupPreflight: RecordingSetupPreflight? = nil,
        credentialResolver: (any OpenAICredentialResolving)? = nil,
        settingsPresenter: (any SetupSettingsPresenting)? = nil,
        hotkeyService: (any GlobalHotkeyService)? = nil,
        pasteLastResultService: SpecialClipboardPasteService? = nil,
        transcriptClipboardStore: (any TranscriptClipboardStoring)? = nil
    ) {
        let resolvedController = controller ?? DictationSessionController()
        let resolvedHotkeyService = hotkeyService ?? CGEventGlobalHotkeyService()
        let resolvedAppSettingsStore = appSettingsStore ?? AppSettingsStore()
        let resolvedTranscriptClipboardStore = transcriptClipboardStore ?? AppTranscriptClipboardStore.shared

        self.controller = resolvedController
        self.appSettingsStore = resolvedAppSettingsStore
        self.recordingSetupPreflight = recordingSetupPreflight ?? RecordingSetupPreflight()
        self.credentialResolver = credentialResolver ?? OpenAICredentialResolver()
        self.settingsPresenter = settingsPresenter ?? SettingsWindowPresenter.shared
        self.hotkeyService = resolvedHotkeyService
        self.transcriptClipboardStore = resolvedTranscriptClipboardStore
        self.pasteLastResultService = pasteLastResultService
            ?? SpecialClipboardPasteService(transcriptClipboardStore: resolvedTranscriptClipboardStore)
        self.preferredHotkeyConfiguration = resolvedHotkeyService.preferredConfiguration
        self.hotkeyRegistrationStatus = resolvedHotkeyService.currentRegistrationStatus
        self.status = resolvedController.status
        self.lastTranscriptText = resolvedController.lastTranscriptText
        self.outputStatusText = resolvedController.outputStatusText
        self.failurePresentation = resolvedController.failurePresentation
        self.appSettings = resolvedAppSettingsStore.load()
        self.isLastResultPasteAvailable = false

        resolvedController.statusDidChange = { [weak self] status in
            self?.status = status
        }
        resolvedController.lastTranscriptTextDidChange = { [weak self] lastTranscriptText in
            self?.lastTranscriptText = lastTranscriptText
            Task { @MainActor in
                await self?.refreshLastResultPasteAvailability()
            }
        }
        resolvedController.outputStatusTextDidChange = { [weak self] outputStatusText in
            self?.outputStatusText = outputStatusText
        }
        resolvedController.failurePresentationDidChange = { [weak self] failurePresentation in
            self?.failurePresentation = failurePresentation
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .appSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.reloadAppSettings()
            }
        }

        Task { @MainActor in
            await refreshLastResultPasteAvailability()
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    func startHotkeyListening() {
        guard hotkeyCoordinator == nil else {
            return
        }

        let coordinator = DictationHotkeyCoordinator(
            hotkeyService: hotkeyService,
            statusProvider: { [weak self] in
                self?.status ?? .idle
            },
            performRecordingAction: { [weak self] intent in
                await self?.performRecordingAction(intent: intent)
            }
        )
        hotkeyCoordinator = coordinator

        do {
            try coordinator.start()
        } catch {
            // The registration status carries the user-facing failure for Settings.
        }

        hotkeyRegistrationStatus = coordinator.registrationStatus
    }

    func stopHotkeyListening() {
        hotkeyCoordinator?.stop()
        hotkeyRegistrationStatus = hotkeyCoordinator?.registrationStatus ?? .notRegistered
        hotkeyCoordinator = nil
    }

    func refreshHotkeyRegistrationStatus() {
        hotkeyRegistrationStatus = hotkeyCoordinator?.registrationStatus
            ?? hotkeyService.currentRegistrationStatus
    }

    func performRecordingAction(intent: DictationOutputIntent = .standard) async {
        var credential: OpenAICredential?
        if shouldValidateSetupBeforeRecording {
            let settings = appSettingsStore.load()
            if intent == .translate,
               let translationIssue = settings.translationConfigurationIssue {
                let message = Self.userFacingMessage(for: translationIssue)
                failurePresentation = DictationFailurePresentation(
                    title: translationIssue.title,
                    message: message,
                    settingsTarget: .translation
                )
                status = .failure(message: message)
                settingsPresenter.showAfterMenuDismissal(focusing: .translation)
                return
            }

            if let microphoneStatus = await recordingSetupPreflight.requestMicrophonePermissionIfNeeded(),
               microphoneStatus != .allowed {
                failurePresentation = nil
                status = .failure(message: microphoneStatus.settingsDescription)
                settingsPresenter.showAfterSystemPermissionPrompt(focusing: .permissions)
                return
            }

            let preflight = recordingSetupPreflight.evaluate(settings: settings)

            switch preflight.requirement {
            case .ready(let resolvedCredential):
                credential = resolvedCredential
            case .permissions(let message):
                failurePresentation = nil
                status = .failure(message: message)
                settingsPresenter.showAfterMenuDismissal(
                    focusing: preflight.setupStatus.preferredRecordingSettingsItem
                )
                return
            case .openAIKey(let message):
                failurePresentation = nil
                status = .failure(message: message)
                settingsPresenter.showAfterMenuDismissal(focusing: .openAI)
                return
            }
        }

        await controller.performRecordingAction(intent: intent, credential: credential)
        syncFromController()
        if case .failure = status,
           intent == .translate,
           failurePresentation?.settingsTarget == .translation {
            settingsPresenter.showAfterMenuDismissal(focusing: .translation)
        }
        await refreshLastResultPasteAvailability()
    }

    func pasteLastResult() async {
        let result = await pasteLastResultService.pasteFromAppClipboard(settings: appSettingsStore.load())
        outputStatusText = result.statusText
        await refreshLastResultPasteAvailability()
    }

    func retryFailedTranscription(
        id: FailedTranscriptionAttempt.ID,
        outputMode: FailedTranscriptionRetryOutputMode = .saveOnly
    ) async {
        do {
            let credential = try credentialResolver.resolveOpenAICredential()
            await controller.retryFailedTranscription(
                id: id,
                credential: credential,
                outputMode: outputMode
            )
            syncFromController()
        } catch {
            let message = Self.userFacingCredentialMessage(for: error)
            status = .failure(message: message)
            failurePresentation = DictationFailurePresentation(
                title: FailedTranscriptionReason(error: Self.transcriptionServiceError(for: error)).title,
                message: message,
                failedAttemptID: id,
                settingsTarget: .openAI,
                canRetry: true,
                showsRecoveryPrompt: true
            )
        }
    }

    func reportFailure(message: String) {
        failurePresentation = nil
        status = .failure(message: message)
    }

    func dismissFailurePresentation() {
        controller.dismissFailurePresentation()
        failurePresentation = nil
        if case .failure = status {
            status = .idle
        }
    }

    #if DEBUG
    func presentDebugTranscriptionFailure(reason: FailedTranscriptionReason) {
        let failedAttempt = makeDebugFailedTranscriptionAttempt(reason: reason)
        status = .failure(message: reason.message)
        failurePresentation = DictationFailurePresentation(
            title: reason.title,
            message: reason.message,
            failedAttemptID: failedAttempt?.id,
            settingsTarget: reason.settingsTarget,
            canRetry: reason.canRetry,
            showsRecoveryPrompt: true
        )
    }
    #endif

    private var shouldValidateSetupBeforeRecording: Bool {
        switch status {
        case .idle, .success, .failure:
            return true
        case .recording, .transcribing:
            return false
        }
    }

    private func syncFromController() {
        status = controller.status
        lastTranscriptText = controller.lastTranscriptText
        outputStatusText = controller.outputStatusText
        failurePresentation = controller.failurePresentation
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return description
        }

        return error.localizedDescription
    }

    private func reloadAppSettings() async {
        appSettings = appSettingsStore.load()
        await refreshLastResultPasteAvailability()
    }

    private func refreshLastResultPasteAvailability() async {
        guard appSettings.saveTranscriptsToAppClipboard else {
            isLastResultPasteAvailable = false
            return
        }

        let text = await transcriptClipboardStore.currentText()
        isLastResultPasteAvailable = text?.isEmpty == false
    }

    private static func userFacingCredentialMessage(for error: Error) -> String {
        transcriptionServiceError(for: error).userFacingMessage
    }

    private static func transcriptionServiceError(for error: Error) -> OpenAITranscriptionServiceError {
        if let error = error as? OpenAICredentialResolutionError {
            return error.transcriptionServiceError
        }

        return .apiKeyUnavailable
    }

    #if DEBUG
    private func makeDebugFailedTranscriptionAttempt(
        reason: FailedTranscriptionReason
    ) -> FailedTranscriptionAttempt? {
        guard reason.shouldRecordFailedAttempt else {
            return nil
        }

        do {
            let audioFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("HoldTypeDebugFailedTranscription-\(UUID().uuidString)")
                .appendingPathExtension("m4a")
            try Data("debug transcription failure audio fixture".utf8).write(
                to: audioFileURL,
                options: .atomic
            )

            var settings = appSettingsStore.load()
            settings.saveTranscriptHistory = true

            return try TranscriptionFailureRecoveryStore.shared.recordFailedAttempt(
                audioFileURL: audioFileURL,
                settings: settings,
                audioDuration: 12,
                reason: reason
            )
        } catch {
            return nil
        }
    }
    #endif
}
