//
//  BehaviorSettingsSection.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import SwiftUI

struct BehaviorSettingsSection: View {
    @Binding var settings: AppSettings

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
        }
    }
}

#Preview {
    Form {
        BehaviorSettingsSection(settings: .constant(.defaults))
    }
    .formStyle(.grouped)
    .padding()
}
