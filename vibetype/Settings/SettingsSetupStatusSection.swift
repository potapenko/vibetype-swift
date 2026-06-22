//
//  SettingsSetupStatusSection.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import SwiftUI

struct SettingsSetupStatusSection: View {
    var body: some View {
        Section {
            VibeTypeSetupStatusView(surface: .macOSSettings, showsDetailSections: false)
        }
    }
}

#Preview {
    Form {
        SettingsSetupStatusSection()
    }
    .formStyle(.grouped)
    .padding()
}
