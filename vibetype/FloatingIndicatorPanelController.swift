//
//  FloatingIndicatorPanelController.swift
//  vibetype
//
//  Created by Codex on 6/21/26.
//

import AppKit
import SwiftUI

final class FloatingIndicatorPanelController {
    private let panelSize = CGSize(width: 72, height: 72)
    private let screenMargin: CGFloat = 18

    private var panel: NSPanel?

    @MainActor
    func update(with presentation: FloatingIndicatorPresentation?) {
        guard let presentation else {
            hide()
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(
            rootView: FloatingIndicatorView(presentation: presentation)
        )
        panel.setContentSize(panelSize)
        position(panel)
        panel.orderFrontRegardless()
    }

    @MainActor
    func hide() {
        panel?.orderOut(nil)
    }

    @MainActor
    private func makePanel() -> NSPanel {
        let panel = NonActivatingIndicatorPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    @MainActor
    private func position(_ panel: NSPanel) {
        let screen = screenForIndicator()
        let visibleFrame = screen.visibleFrame
        let origin = CGPoint(
            x: visibleFrame.maxX - panelSize.width - screenMargin,
            y: visibleFrame.minY + screenMargin
        )
        panel.setFrame(CGRect(origin: origin, size: panelSize), display: true)
    }

    @MainActor
    private func screenForIndicator() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

private final class NonActivatingIndicatorPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
