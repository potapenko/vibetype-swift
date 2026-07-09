//
//  BehaviorSettingsSection.swift
//  HoldType
//
//  Created by Codex on 6/22/26.
//

import HoldTypeDomain
import SwiftUI

struct BehaviorSettingsSection: View {
    @Binding var settings: AppSettings
    let launchAtLoginStatus: LaunchAtLoginStatus
    let transcriptHistoryCount: Int
    let onSetLaunchAtLogin: (Bool) -> Void
    let onOpenLoginItemsSettings: () -> Void
    let onClearTranscriptHistory: () -> Void

    var body: some View {
        Section("Behavior") {
            LaunchAtLoginSettingsRows(
                status: launchAtLoginStatus,
                onSetEnabled: onSetLaunchAtLogin,
                onOpenLoginItemsSettings: onOpenLoginItemsSettings
            )

            Toggle(
                "Insert transcripts automatically",
                isOn: $settings.automaticallyInsertTranscripts
            )

            Text("After transcription, insert accepted text into the active app at the cursor.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(
                "Keep last result for quick paste",
                isOn: $settings.saveTranscriptsToAppClipboard
            )

            Text("Use Control+Command+V or Paste Last Result to insert the saved text in the active app.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(
                "Play recording start and stop sounds",
                isOn: $settings.soundEnabled
            )

            Toggle(
                "Show floating recording indicator",
                isOn: $settings.showFloatingIndicator
            )

            Picker(
                "Recording tail after release",
                selection: $settings.recordingStopTailDuration
            ) {
                ForEach(RecordingStopTailDuration.allCases, id: \.self) { duration in
                    Text(duration.displayName).tag(duration)
                }
            }
            .pickerStyle(.menu)

            Text("Keeps recording briefly after stop so final words are less likely to be cut off.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(
                "Keep transcript recovery history",
                isOn: $settings.saveTranscriptHistory
            )

            Text("Keeps recent accepted transcripts and retryable failed attempts until you clear history or quit HoldType.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Clear Transcript History", role: .destructive, action: onClearTranscriptHistory)
                .disabled(transcriptHistoryCount == 0)
        }
    }
}

#Preview {
    Form {
        BehaviorSettingsSection(
            settings: .constant(.defaults),
            launchAtLoginStatus: .disabled,
            transcriptHistoryCount: 0,
            onSetLaunchAtLogin: { _ in },
            onOpenLoginItemsSettings: {},
            onClearTranscriptHistory: {}
        )
    }
    .formStyle(.grouped)
    .padding()
}
