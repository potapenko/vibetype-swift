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
                "Save transcripts to VibeType Clipboard",
                isOn: $settings.saveTranscriptsToAppClipboard
            )

            Text("Use Control+Command+V to insert the saved VibeType Clipboard text into the active app.")
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
