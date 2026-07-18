//
//  TranscriptHistoryWindowPresenter.swift
//  HoldType
//
//  Created by Codex on 7/7/26.
//

import AppKit
import SwiftUI

@MainActor
final class TranscriptHistoryWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = TranscriptHistoryWindowPresenter()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func showAfterMenuDismissal() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            show()
        }
    }

    func show() {
        AppWindowActivation.showRegularApp()
        let historyWindow = window ?? makeWindow()
        window = historyWindow
        historyWindow.makeKeyAndOrderFront(nil)
        historyWindow.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        AppWindowActivation.restoreAccessoryIfNoVisibleAppWindows(
            excluding: notification.object as? NSWindow
        )
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: TranscriptHistoryView())
        let historyWindow = NSWindow(contentViewController: hostingController)
        historyWindow.title = HoldTypeWindowTitle.history
        historyWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        historyWindow.minSize = NSSize(width: 620, height: 420)
        historyWindow.setContentSize(NSSize(width: 760, height: 560))
        historyWindow.center()
        historyWindow.isReleasedWhenClosed = false
        historyWindow.delegate = self
        return historyWindow
    }
}
