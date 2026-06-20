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

@main
struct VibeTypeApp: App {
    var body: some Scene {
        MenuBarExtra("VibeType", systemImage: "mic.fill") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)

        Window("VibeType Settings", id: VibeTypeWindow.settings) {
            SettingsView()
        }
        .defaultSize(width: 420, height: 320)
    }
}
