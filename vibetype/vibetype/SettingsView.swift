//
//  SettingsView.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("VibeType Settings")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Settings are not configurable in this build.")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Label("No configurable settings yet.", systemImage: "gearshape")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 220, alignment: .topLeading)
    }
}

#Preview {
    SettingsView()
}
