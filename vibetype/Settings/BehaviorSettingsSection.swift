//
//  BehaviorSettingsSection.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import SwiftUI

struct BehaviorSettingsSection: View {
    @Binding var settings: AppSettings
    let transcriptHistoryCount: Int
    let onClearTranscriptHistory: () -> Void

    var body: some View {
        Section("Behavior") {
            Toggle(
                "Insert transcripts automatically",
                isOn: $settings.automaticallyInsertTranscripts
            )

            Text("After transcription, insert accepted text into the active app at the cursor.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(
                "Keep last transcript in VibeType Clipboard",
                isOn: $settings.saveTranscriptsToAppClipboard
            )

            Text("Use Control+Command+V to recover the saved text in the active app.")
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

            Toggle(
                "Keep transcript recovery history",
                isOn: $settings.saveTranscriptHistory
            )

            Text("Keeps recent accepted transcripts in memory until you clear history or quit VibeType.")
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
            transcriptHistoryCount: 0,
            onClearTranscriptHistory: {}
        )
    }
    .formStyle(.grouped)
    .padding()
}
