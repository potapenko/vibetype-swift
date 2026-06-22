//
//  vibetypeApp.swift
//  vibetype
//
//  Created by Eugene Potapenko on 6/20/26.
//

import AppKit
import SwiftUI

enum VibeTypeWindow {
    static let settings = "settings"
}

@main
struct VibeTypeApp: App {
    @NSApplicationDelegateAdaptor(VibeTypeAppDelegate.self) private var appDelegate

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
        .defaultSize(width: 760, height: 520)
    }
}

@MainActor
final class VibeTypeAppDelegate: NSObject, NSApplicationDelegate {
    private let specialClipboardHotkeyCoordinator = SpecialClipboardHotkeyCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        specialClipboardHotkeyCoordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        specialClipboardHotkeyCoordinator.stop()
    }
}
