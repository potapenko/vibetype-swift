//
//  MenuBarPresentation.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

enum VibeTypeMenuBarIdentity {
    static let title = "VibeType"
    static let systemImage = "mic.fill"
    static let helpText = "VibeType Dictation"
}

struct MenuBarPresentation: Equatable {
    static let lastTranscriptTitle = "Last Transcript"
    static let copyLastTranscriptTitle = "Copy Last Transcript"
    static let settingsTitle = "Settings"
    static let quitTitle = "Quit VibeType"

    let appTitle: String
    let statusText: String
    let microphoneStatusText: String
    let microphoneDetailText: String?
    let microphoneSettingsActionTitle: String?
    let accessibilityStatusText: String
    let accessibilityDetailText: String?
    let accessibilitySettingsActionTitle: String?
    let recordingActionTitle: String
    let isRecordingActionEnabled: Bool
    let dictationDetailText: String?
    let lastTranscriptText: String
    let canCopyLastTranscript: Bool
    let clipboardStatusText: String?

    init(
        dictationStatus: DictationStatus,
        microphonePermissionStatus: MicrophonePermissionStatus,
        accessibilityPermissionStatus: AccessibilityPermissionStatus,
        clipboardStatusText: String? = nil
    ) {
        appTitle = VibeTypeMenuBarIdentity.title
        statusText = dictationStatus.menuStatusText
        microphoneStatusText = microphonePermissionStatus.menuStatusText
        microphoneDetailText = microphonePermissionStatus.menuDetailText
        microphoneSettingsActionTitle = microphonePermissionStatus == .denied
            ? "Open Microphone Settings"
            : nil
        accessibilityStatusText = accessibilityPermissionStatus.menuStatusText
        accessibilityDetailText = accessibilityPermissionStatus.menuDetailText
        accessibilitySettingsActionTitle = accessibilityPermissionStatus.canPasteIntoActiveApp
            ? nil
            : "Open Accessibility Settings"
        recordingActionTitle = Self.recordingActionTitle(
            dictationStatus: dictationStatus,
            microphonePermissionStatus: microphonePermissionStatus
        )
        isRecordingActionEnabled = dictationStatus.isRecordingActionEnabled
            && microphonePermissionStatus.canUseRecordingAction
        dictationDetailText = dictationStatus.detailText
        lastTranscriptText = dictationStatus.lastTranscriptMenuText
        canCopyLastTranscript = dictationStatus.canCopyLastTranscript
        self.clipboardStatusText = clipboardStatusText
    }

    private static func recordingActionTitle(
        dictationStatus: DictationStatus,
        microphonePermissionStatus: MicrophonePermissionStatus
    ) -> String {
        switch microphonePermissionStatus {
        case .notDetermined:
            return "Request Microphone Access"
        case .allowed, .denied, .unavailable:
            return dictationStatus.recordingActionTitle
        }
    }
}
