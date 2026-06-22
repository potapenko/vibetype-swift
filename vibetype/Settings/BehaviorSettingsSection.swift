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
                "Paste transcript into active app",
                isOn: $settings.autoPaste
            )

            Toggle(
                "Copy transcript to clipboard",
                isOn: $settings.copyToClipboard
            )

            Toggle(
                "Restore previous clipboard after paste",
                isOn: $settings.restoreClipboard
            )

            Toggle(
                "Play sound on start and stop",
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
