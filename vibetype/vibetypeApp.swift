//
//  vibetypeApp.swift
//  vibetype
//
//  Created by Eugene Potapenko on 6/20/26.
//

import AppKit
import SwiftUI

enum VibeTypeWindow {
    static let history = "history"
    static let settings = "settings"
}

@main
struct VibeTypeApp: App {
    @NSApplicationDelegateAdaptor(VibeTypeAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(VibeTypeMenuBarIdentity.iconAssetName)
                .renderingMode(.template)
                .accessibilityLabel(VibeTypeMenuBarIdentity.title)
                .help(VibeTypeMenuBarIdentity.helpText)
        }
        .menuBarExtraStyle(.menu)

        Window("\(VibeTypeMenuBarIdentity.title) Settings", id: VibeTypeWindow.settings) {
            SettingsView()
        }
        .defaultSize(width: 760, height: 520)

        Window("Transcript History", id: VibeTypeWindow.history) {
            TranscriptHistoryView()
        }
        .defaultSize(width: 760, height: 560)
    }
}

@MainActor
final class VibeTypeAppDelegate: NSObject, NSApplicationDelegate {
    private let specialClipboardHotkeyCoordinator = SpecialClipboardHotkeyCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        specialClipboardHotkeyCoordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        TranscriptRecoveryHistoryStore.shared.clear()
        specialClipboardHotkeyCoordinator.stop()
    }
}
