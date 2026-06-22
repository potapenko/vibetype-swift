//
//  PrivacyPermissionsSettingsSection.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import SwiftUI

struct PrivacyPermissionsSettingsSection: View {
    let microphonePermissionStatus: MicrophonePermissionStatus
    let accessibilityPermissionStatus: AccessibilityPermissionStatus
    let onMicrophonePermissionAction: () -> Void
    let onOpenAccessibilitySettings: () -> Void

    var body: some View {
        Section("Privacy And Permissions") {
            PermissionStatusRow(
                title: microphonePermissionStatus.settingsStatusText,
                description: microphonePermissionStatus.settingsDescription,
                systemImage: microphonePermissionStatus.settingsSystemImage
            )

            if let microphoneActionTitle = microphonePermissionStatus.settingsActionTitle {
                Button(microphoneActionTitle, action: onMicrophonePermissionAction)
            }

            PermissionStatusRow(
                title: accessibilityPermissionStatus.settingsStatusText,
                description: accessibilityPermissionStatus.settingsDescription,
                systemImage: accessibilityPermissionStatus.settingsSystemImage
            )

            if !accessibilityPermissionStatus.canPasteIntoActiveApp {
                Button("Open Accessibility Settings", action: onOpenAccessibilitySettings)
            }

            Label(
                "Audio is sent to OpenAI for transcription. VibeType does not retain raw audio by default.",
                systemImage: "lock.shield"
            )
            .foregroundStyle(.secondary)
        }
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let description: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)

            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    Form {
        PrivacyPermissionsSettingsSection(
            microphonePermissionStatus: .notDetermined,
            accessibilityPermissionStatus: .notTrusted,
            onMicrophonePermissionAction: {},
            onOpenAccessibilitySettings: {}
        )
    }
    .formStyle(.grouped)
    .padding()
}
