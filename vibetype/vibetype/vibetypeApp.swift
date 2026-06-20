//
//  vibetypeApp.swift
//  vibetype
//
//  Created by Eugene Potapenko on 6/20/26.
//

import SwiftUI

enum VibeTypeWindow {
    static let settings = "settings"
}

private enum VibeTypeMenuBarIdentity {
    static let title = "VibeType"
    static let systemImage = "mic.fill"
    static let helpText = "VibeType Dictation"
}

@main
struct VibeTypeApp: App {
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Label(
                VibeTypeMenuBarIdentity.title,
                systemImage: VibeTypeMenuBarIdentity.systemImage
            )
            .accessibilityLabel(VibeTypeMenuBarIdentity.title)
            .help(VibeTypeMenuBarIdentity.helpText)
        }
        .menuBarExtraStyle(.menu)

        Window("\(VibeTypeMenuBarIdentity.title) Settings", id: VibeTypeWindow.settings) {
            SettingsView()
        }
        .defaultSize(width: 420, height: 320)
    }
}
