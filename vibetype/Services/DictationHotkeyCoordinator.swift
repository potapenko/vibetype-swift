//
//  DictationHotkeyCoordinator.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import Foundation

@MainActor
final class DictationHotkeyCoordinator {
    typealias StatusProvider = @MainActor () -> DictationStatus
    typealias RecordingAction = @MainActor () async -> Void

    private let hotkeyService: any GlobalHotkeyService
    private let statusProvider: StatusProvider
    private let performRecordingAction: RecordingAction

    private var isShortcutPressed = false
    private var isHotkeyRecordingActive = false
    private var isPerformingRecordingAction = false

    private(set) var registrationStatus: GlobalHotkeyRegistrationStatus

    init(
        hotkeyService: any GlobalHotkeyService,
        statusProvider: @escaping StatusProvider,
        performRecordingAction: @escaping RecordingAction
    ) {
        self.hotkeyService = hotkeyService
        self.statusProvider = statusProvider
        self.performRecordingAction = performRecordingAction
        self.registrationStatus = hotkeyService.currentRegistrationStatus
    }

    func start() throws {
        do {
            try hotkeyService.startListening { [weak self] action in
                Task { @MainActor [weak self] in
                    await self?.handle(action)
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
    }

    func handle(_ action: GlobalHotkeyAction) async {
        let wasShortcutPressed = isShortcutPressed

        if action == .keyUp {
            isShortcutPressed = false
        }

        guard !isPerformingRecordingAction,
              let configuration = registrationStatus.activeConfiguration else {
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
        case .stopRecording:
            isHotkeyRecordingActive = false
        }

        isPerformingRecordingAction = true
        await performRecordingAction()
        isPerformingRecordingAction = false

        if command == .startRecording, statusProvider() != .recording {
            isHotkeyRecordingActive = false
        }
    }
}
