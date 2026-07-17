//
//  FloatingIndicatorPanelController.swift
//  HoldType
//
//  Created by Codex on 6/21/26.
//

import AppKit
import Combine
import SwiftUI

@MainActor
protocol FloatingIndicatorPresenting: AnyObject {
    func update(with presentation: FloatingIndicatorPresentation?)
    func hide()
}

@MainActor
final class FloatingIndicatorPanelController: FloatingIndicatorPresenting {
    private let panelSize = CGSize(width: 72, height: 72)
    private let screenMargin: CGFloat = 18

    private var panel: NSPanel?
    private var hostingModel: FloatingIndicatorHostingModel?
    private var hostingView: NSView?
    private var isVisible = false

    var hostingViewIdentity: ObjectIdentifier? {
        hostingView.map(ObjectIdentifier.init)
    }

    func update(with presentation: FloatingIndicatorPresentation?) {
        guard let presentation else {
            hide()
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        updateHostedContent(
            with: presentation,
            in: panel,
            restartsAnimation: !isVisible
        )
        position(panel)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

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
        panel.setContentSize(panelSize)
        return panel
    }

    private func updateHostedContent(
        with presentation: FloatingIndicatorPresentation,
        in panel: NSPanel,
        restartsAnimation: Bool
    ) {
        if let hostingModel {
            hostingModel.update(
                with: presentation,
                restartsAnimation: restartsAnimation
            )
            return
        }

        let hostingModel = FloatingIndicatorHostingModel(presentation: presentation)
        let hostingView = NSHostingView(
            rootView: FloatingIndicatorHostView(model: hostingModel)
        )
        self.hostingModel = hostingModel
        self.hostingView = hostingView
        panel.contentView = hostingView
    }

    private func position(_ panel: NSPanel) {
        let screen = screenForIndicator()
        let visibleFrame = screen.visibleFrame
        let origin = CGPoint(
            x: visibleFrame.maxX - panelSize.width - screenMargin,
            y: visibleFrame.minY + screenMargin
        )
        panel.setFrame(CGRect(origin: origin, size: panelSize), display: true)
    }

    private func screenForIndicator() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

@MainActor
final class FloatingIndicatorHostingModel: ObservableObject {
    struct State: Equatable {
        let presentation: FloatingIndicatorPresentation
        let animationIdentity: Int
    }

    @Published private(set) var state: State

    init(presentation: FloatingIndicatorPresentation) {
        state = State(
            presentation: presentation,
            animationIdentity: 0
        )
    }

    func update(
        with presentation: FloatingIndicatorPresentation,
        restartsAnimation: Bool
    ) {
        let phaseChanged = presentation.phase != state.presentation.phase
        let animationIdentity = restartsAnimation || phaseChanged
            ? state.animationIdentity + 1
            : state.animationIdentity
        let nextState = State(
            presentation: presentation,
            animationIdentity: animationIdentity
        )
        guard nextState != state else {
            return
        }

        state = nextState
    }
}

private struct FloatingIndicatorHostView: View {
    @ObservedObject var model: FloatingIndicatorHostingModel

    var body: some View {
        FloatingIndicatorView(presentation: model.state.presentation)
            .id(model.state.animationIdentity)
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
