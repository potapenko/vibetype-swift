//
//  SettingsView.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import SwiftUI

struct SettingsView: View {
    @State private var accessibilityPermissionStatus: AccessibilityPermissionStatus

    private let accessibilityPermissionService: AccessibilityPermissionService

    init(accessibilityPermissionService: AccessibilityPermissionService = AccessibilityPermissionService()) {
        self.accessibilityPermissionService = accessibilityPermissionService
        _accessibilityPermissionStatus = State(
            initialValue: accessibilityPermissionService.currentStatus()
        )
    }

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

            VStack(alignment: .leading, spacing: 8) {
                Text("Permissions")
                    .font(.headline)

                Label(
                    accessibilityPermissionStatus.settingsDescription,
                    systemImage: accessibilityPermissionStatus.canPasteIntoActiveApp
                        ? "checkmark.circle"
                        : "exclamationmark.triangle"
                )
                .foregroundStyle(.secondary)

                if !accessibilityPermissionStatus.canPasteIntoActiveApp {
                    Button("Open Accessibility Settings") {
                        accessibilityPermissionService.openAccessibilitySettings()
                        refreshAccessibilityPermissionStatus()
                    }
                }
            }

            Divider()

            Label("No configurable settings yet.", systemImage: "gearshape")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 300, alignment: .topLeading)
        .onAppear(perform: refreshAccessibilityPermissionStatus)
    }

    private func refreshAccessibilityPermissionStatus() {
        accessibilityPermissionStatus = accessibilityPermissionService.currentStatus()
    }
}

#Preview {
    SettingsView()
}
