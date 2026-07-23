import AppKit

@MainActor
protocol FixesPaletteOutsideClickMonitoring: AnyObject {
    var isMonitoring: Bool { get }

    func start(
        panel: NSPanel,
        onOutsideClick: @escaping @MainActor () -> Void
    )
    func stop()
}

@MainActor
final class FixesPaletteOutsideClickMonitor: FixesPaletteOutsideClickMonitoring {
    private static let mouseEventMask: NSEvent.EventTypeMask = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
    ]

    private var localMonitor: Any?
    private var globalMonitor: Any?

    var isMonitoring: Bool {
        localMonitor != nil || globalMonitor != nil
    }

    func start(
        panel: NSPanel,
        onOutsideClick: @escaping @MainActor () -> Void
    ) {
        stop()

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: Self.mouseEventMask
        ) { [weak panel] event in
            guard event.window !== panel else {
                return event
            }

            onOutsideClick()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: Self.mouseEventMask
        ) { _ in
            Task { @MainActor in
                onOutsideClick()
            }
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
    }
}
