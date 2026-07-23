import AppKit
import HoldTypeDomain
import Testing
@testable import HoldType

@MainActor
struct FixesPalettePanelControllerTests {
    @Test func panelUsesInteractiveNonActivatingUtilityInvariants() {
        let monitor = FakeFixesPaletteOutsideClickMonitor()
        let controller = makeController(monitor: monitor)
        let model = makeModel()

        controller.show(
            model: model,
            accessibilityAnchorRect: CGRect(x: 400, y: 200, width: 1, height: 18)
        )
        defer { controller.hide() }

        let panel = controller.presentedPanel
        #expect(panel != nil)
        #expect(panel?.styleMask.contains(.borderless) == true)
        #expect(panel?.styleMask.contains(.nonactivatingPanel) == true)
        #expect(panel?.canBecomeKey == true)
        #expect(panel?.canBecomeMain == false)
        #expect(panel?.level == .popUpMenu)
        #expect(panel?.isOpaque == false)
        #expect(panel?.hidesOnDeactivate == false)
        #expect(panel?.isReleasedWhenClosed == false)
        #expect(monitor.isMonitoring)
    }

    @Test func arrowAndReturnCommandsDriveTheHostedModel() {
        var activatedIDs: [String] = []
        let controller = makeController()
        let model = makeModel { activatedIDs.append($0) }
        controller.show(model: model, accessibilityAnchorRect: nil)
        defer { controller.hide() }

        #expect(controller.handleKeyboardCommand(.moveDown))
        #expect(model.selectedActionID == TextFixAction.fixIdentifier)

        #expect(controller.handleKeyboardCommand(.activate))
        #expect(activatedIDs == [TextFixAction.fixIdentifier])
        #expect(model.status == .processing(actionID: TextFixAction.fixIdentifier))
    }

    @Test func escapeDismissesOnceAndCleansPanelAndMonitors() {
        let monitor = FakeFixesPaletteOutsideClickMonitor()
        var dismissCount = 0
        let controller = makeController(monitor: monitor)
        let model = makeModel(onDismiss: { dismissCount += 1 })
        controller.show(model: model, accessibilityAnchorRect: nil)

        #expect(controller.handleKeyboardCommand(.dismiss))
        #expect(controller.handleKeyboardCommand(.dismiss) == false)
        #expect(controller.presentedPanel == nil)
        #expect(controller.isVisible == false)
        #expect(monitor.isMonitoring == false)
        #expect(dismissCount == 1)
    }

    @Test func outsideClickDismissesAndRunsDeterministicCleanup() {
        let monitor = FakeFixesPaletteOutsideClickMonitor()
        var dismissCount = 0
        let controller = makeController(monitor: monitor)
        let model = makeModel(onDismiss: { dismissCount += 1 })
        controller.show(model: model, accessibilityAnchorRect: nil)

        monitor.fireOutsideClick()

        #expect(controller.presentedPanel == nil)
        #expect(monitor.isMonitoring == false)
        #expect(monitor.stopCount == 2)
        #expect(dismissCount == 1)
    }

    @Test func programmaticHideDoesNotReportUserDismissal() {
        let monitor = FakeFixesPaletteOutsideClickMonitor()
        var dismissCount = 0
        let controller = makeController(monitor: monitor)
        let model = makeModel(onDismiss: { dismissCount += 1 })
        controller.show(model: model, accessibilityAnchorRect: nil)

        controller.hide()

        #expect(controller.presentedPanel == nil)
        #expect(monitor.isMonitoring == false)
        #expect(dismissCount == 0)
    }

    @Test func keyboardEventMappingHandlesArrowsReturnAndEscape() throws {
        #expect(try command(for: 126) == .moveUp)
        #expect(try command(for: 125) == .moveDown)
        #expect(try command(for: 36) == .activate)
        #expect(try command(for: 76) == .activate)
        #expect(try command(for: 53) == .dismiss)
        #expect(try command(for: 0) == nil)
        #expect(try command(for: 125, modifiers: [.option]) == nil)
    }

    private func makeController() -> FixesPalettePanelController {
        makeController(monitor: FakeFixesPaletteOutsideClickMonitor())
    }

    private func makeController(
        monitor: FakeFixesPaletteOutsideClickMonitor
    ) -> FixesPalettePanelController {
        FixesPalettePanelController(
            panelSize: CGSize(width: 360, height: 392),
            outsideClickMonitor: monitor,
            screenGeometryProvider: {
                [
                    FixesPaletteScreenGeometry(
                        frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                        visibleFrame: CGRect(x: 0, y: 24, width: 1_000, height: 752),
                        isPrimary: true
                    )
                ]
            },
            mouseLocationProvider: {
                CGPoint(x: 500, y: 500)
            }
        )
    }

    private func makeModel(
        onActivate: @escaping FixesPaletteModel.ActionHandler = { _ in },
        onDismiss: @escaping FixesPaletteModel.DismissHandler = {}
    ) -> FixesPaletteModel {
        FixesPaletteModel(
            catalog: .defaults,
            onActivate: onActivate,
            onDismiss: onDismiss
        )
    }

    private func command(
        for keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> FixesPaletteKeyboardCommand? {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
        return FixesPaletteKeyboardCommand(event: try #require(event))
    }
}

@MainActor
private final class FakeFixesPaletteOutsideClickMonitor:
    FixesPaletteOutsideClickMonitoring {
    private(set) var isMonitoring = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onOutsideClick: (@MainActor () -> Void)?

    func start(
        panel: NSPanel,
        onOutsideClick: @escaping @MainActor () -> Void
    ) {
        _ = panel
        isMonitoring = true
        startCount += 1
        self.onOutsideClick = onOutsideClick
    }

    func stop() {
        isMonitoring = false
        stopCount += 1
        onOutsideClick = nil
    }

    func fireOutsideClick() {
        onOutsideClick?()
    }
}
