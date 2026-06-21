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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VibeTypeSetupStatusView(surface: .macOSSettings, showsDetailSections: false)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
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

                Label("Configurable settings are not enabled in this build.", systemImage: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 460, minHeight: 380, alignment: .topLeading)
        .onAppear(perform: refreshAccessibilityPermissionStatus)
    }

    private func refreshAccessibilityPermissionStatus() {
        accessibilityPermissionStatus = accessibilityPermissionService.currentStatus()
    }
}

#Preview {
    SettingsView()
}
