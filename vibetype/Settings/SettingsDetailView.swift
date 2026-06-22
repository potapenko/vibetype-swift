//
//  SettingsDetailView.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import SwiftUI

struct SettingsDetailView: View {
    let item: SettingsNavigationItem

    @Binding var apiKeyInput: String
    let apiKeyStatus: APIKeySettingsStatus
    @Binding var settings: AppSettings
    let hotkeyRegistrationStatus: GlobalHotkeyRegistrationStatus
    let preferredHotkeyConfiguration: GlobalHotkeyConfiguration
    let microphonePermissionStatus: MicrophonePermissionStatus
    let accessibilityPermissionStatus: AccessibilityPermissionStatus
    let inputMonitoringPermissionStatus: InputMonitoringPermissionStatus
    let transcriptHistoryCount: Int
    let onSaveAPIKey: () -> Void
    let onRemoveAPIKey: () -> Void
    let onMicrophonePermissionAction: () -> Void
    let onOpenAccessibilitySettings: () -> Void
    let onInputMonitoringPermissionAction: () -> Void
    let onClearTranscriptHistory: () -> Void

    var body: some View {
        Form {
            switch item {
            case .general:
                SettingsSetupStatusSection()
            case .openAI:
                OpenAISettingsSection(
                    apiKeyInput: $apiKeyInput,
                    apiKeyStatus: apiKeyStatus,
                    onSaveAPIKey: onSaveAPIKey,
                    onRemoveAPIKey: onRemoveAPIKey
                )
            case .transcription:
                TranscriptionSettingsSection(settings: $settings)
            case .dictionary:
                DictionarySettingsSection(settings: $settings)
            case .shortcut:
                KeyboardShortcutSettingsSection(
                    status: hotkeyRegistrationStatus,
                    preferredConfiguration: preferredHotkeyConfiguration
                )
            case .behavior:
                BehaviorSettingsSection(
                    settings: $settings,
                    transcriptHistoryCount: transcriptHistoryCount,
                    onClearTranscriptHistory: onClearTranscriptHistory
                )
            case .privacy:
                PrivacyPermissionsSettingsSection(
                    microphonePermissionStatus: microphonePermissionStatus,
                    accessibilityPermissionStatus: accessibilityPermissionStatus,
                    inputMonitoringPermissionStatus: inputMonitoringPermissionStatus,
                    onMicrophonePermissionAction: onMicrophonePermissionAction,
                    onOpenAccessibilitySettings: onOpenAccessibilitySettings,
                    onInputMonitoringPermissionAction: onInputMonitoringPermissionAction
                )
            }
        }
        .formStyle(.grouped)
        .scenePadding()
        .navigationTitle(item.title)
    }
}

#Preview("Privacy") {
    SettingsDetailView(
        item: .privacy,
        apiKeyInput: .constant(""),
        apiKeyStatus: .missing,
        settings: .constant(.defaults),
        hotkeyRegistrationStatus: .registered(.defaultDictation),
        preferredHotkeyConfiguration: .defaultDictation,
        microphonePermissionStatus: .notDetermined,
        accessibilityPermissionStatus: .notTrusted,
        inputMonitoringPermissionStatus: .notDetermined,
        transcriptHistoryCount: 0,
        onSaveAPIKey: {},
        onRemoveAPIKey: {},
        onMicrophonePermissionAction: {},
        onOpenAccessibilitySettings: {},
        onInputMonitoringPermissionAction: {},
        onClearTranscriptHistory: {}
    )
    .frame(width: 520, height: 420)
}
