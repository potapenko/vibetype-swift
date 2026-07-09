//
//  DictationHotkeyCoordinator.swift
//  HoldType
//
//  Created by Codex on 6/22/26.
//

import Foundation
import HoldTypeDomain

@MainActor
final class DictationHotkeyCoordinator {
    typealias StatusProvider = @MainActor () -> DictationStatus
    typealias RecordingAction = @MainActor (DictationOutputIntent) async -> Void

    private let hotkeyService: any GlobalHotkeyService
    private let statusProvider: StatusProvider
    private let performRecordingAction: RecordingAction
    private let eventLogger: any DictationEventLogging

    private var isShortcutPressed = false
    private var isHotkeyRecordingActive = false
    private var isPerformingRecordingAction = false
    private var shouldStopAfterCurrentAction = false
    private var activeOutputIntent: DictationOutputIntent = .standard

    private(set) var registrationStatus: GlobalHotkeyRegistrationStatus

    init(
        hotkeyService: any GlobalHotkeyService,
        statusProvider: @escaping StatusProvider,
        performRecordingAction: @escaping RecordingAction,
        eventLogger: any DictationEventLogging = OSLogDictationEventLogger()
    ) {
        self.hotkeyService = hotkeyService
        self.statusProvider = statusProvider
        self.performRecordingAction = performRecordingAction
        self.eventLogger = eventLogger
        self.registrationStatus = hotkeyService.currentRegistrationStatus
    }

    func start() throws {
        do {
            try hotkeyService.startListening { [weak self] event in
                Task { @MainActor [weak self] in
                    await self?.handle(event)
                }
            }
            registrationStatus = hotkeyService.currentRegistrationStatus
        } catch {
            registrationStatus = hotkeyService.currentRegistrationStatus
            throw error
        }
    }

    func stop() {
        hotkeyService.stopListening()
        registrationStatus = hotkeyService.currentRegistrationStatus
        isShortcutPressed = false
        isHotkeyRecordingActive = false
        isPerformingRecordingAction = false
        shouldStopAfterCurrentAction = false
        activeOutputIntent = .standard
    }

    func handle(_ event: GlobalHotkeyEvent) async {
        eventLogger.record(.hotkeyEvent(action: event.action, intent: event.outputIntent))

        let action = event.action
        let wasShortcutPressed = isShortcutPressed

        if action == .keyUp {
            isShortcutPressed = false
        }

        guard let configuration = registrationStatus.activeConfiguration else {
            return
        }

        if action == .outputIntentChanged {
            promoteActiveOutputIntentIfNeeded(to: event.outputIntent)
            return
        }

        if isPerformingRecordingAction {
            rememberStopIfNeeded(
                action: action,
                configuration: configuration,
                wasShortcutPressed: wasShortcutPressed
            )
            return
        }

        let status = statusProvider()
        guard status != .transcribing else {
            return
        }

        let isRecording = status == .recording
        guard !isRecording || isHotkeyRecordingActive else {
            return
        }

        guard let command = configuration.recordingCommand(
            for: action,
            isRecording: isRecording,
            isShortcutPressed: wasShortcutPressed
        ) else {
            return
        }

        switch command {
        case .startRecording:
            isShortcutPressed = true
            isHotkeyRecordingActive = true
            shouldStopAfterCurrentAction = false
            activeOutputIntent = event.outputIntent
        case .stopRecording:
            isHotkeyRecordingActive = false
            shouldStopAfterCurrentAction = false
        }

        let outputIntent = command == .stopRecording ? activeOutputIntent : event.outputIntent
        await runRecordingAction(intent: outputIntent)

        if command == .startRecording, statusProvider() != .recording {
            isHotkeyRecordingActive = false
            shouldStopAfterCurrentAction = false
            activeOutputIntent = .standard
        } else if command == .startRecording, shouldStopAfterCurrentAction {
            await replayDeferredStop()
        } else if command == .stopRecording {
            activeOutputIntent = .standard
        }
    }

    private func rememberStopIfNeeded(
        action: GlobalHotkeyAction,
        configuration: GlobalHotkeyConfiguration,
        wasShortcutPressed: Bool
    ) {
        guard action == .keyUp,
              configuration.stopsRecordingOnKeyUp,
              wasShortcutPressed,
              isHotkeyRecordingActive else {
            return
        }

        shouldStopAfterCurrentAction = true
        eventLogger.record(.hotkeyStopDeferred)
    }

    private func promoteActiveOutputIntentIfNeeded(to outputIntent: DictationOutputIntent) {
        guard outputIntent == .translate,
              isShortcutPressed || isHotkeyRecordingActive else {
            return
        }

        activeOutputIntent = activeOutputIntent.merged(with: outputIntent)
    }

    private func replayDeferredStop() async {
        shouldStopAfterCurrentAction = false

        guard statusProvider() == .recording, isHotkeyRecordingActive else {
            isHotkeyRecordingActive = false
            activeOutputIntent = .standard
            return
        }

        let outputIntent = activeOutputIntent
        isHotkeyRecordingActive = false
        eventLogger.record(.hotkeyStopReplayed)
        await runRecordingAction(intent: outputIntent)
        activeOutputIntent = .standard
    }

    private func runRecordingAction(intent: DictationOutputIntent) async {
        isPerformingRecordingAction = true
        await performRecordingAction(intent)
        isPerformingRecordingAction = false
    }
}
