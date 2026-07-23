import Foundation

nonisolated enum IOSKeyboardFixCoordinationSignal: Sendable {
    case requestChanged
    case cancellationChanged
}

nonisolated struct IOSKeyboardFixRequestObservationClient: Sendable {
    let start: @Sendable (
        @escaping @Sendable (IOSKeyboardFixCoordinationSignal) -> Void
    ) -> Void
    let stop: @Sendable () -> Void

    init(
        start: @escaping @Sendable (
            @escaping @Sendable (IOSKeyboardFixCoordinationSignal) -> Void
        ) -> Void,
        stop: @escaping @Sendable () -> Void
    ) {
        self.start = start
        self.stop = stop
    }

    static func production() -> IOSKeyboardFixRequestObservationClient {
        let observer = IOSKeyboardFixDarwinRequestObserver()
        return IOSKeyboardFixRequestObservationClient(
            start: { observer.start(handler: $0) },
            stop: { observer.stop() }
        )
    }
}

private nonisolated final class IOSKeyboardFixDarwinRequestObserver:
    @unchecked Sendable {
    private let lock = NSLock()
    private var handler:
        (@Sendable (IOSKeyboardFixCoordinationSignal) -> Void)?
    private var isObserving = false

    func start(
        handler: @escaping @Sendable (
            IOSKeyboardFixCoordinationSignal
        ) -> Void
    ) {
        let shouldRegister = lock.withLock {
            self.handler = handler
            guard !isObserving else { return false }
            isObserving = true
            return true
        }
        guard shouldRegister else { return }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            iosKeyboardFixRequestNotificationCallback,
            KeyboardFixBridgeConfiguration.requestNotification as CFString,
            nil,
            .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            iosKeyboardFixRequestNotificationCallback,
            KeyboardFixBridgeConfiguration
                .cancellationNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    func stop() {
        let shouldRemove = lock.withLock {
            handler = nil
            guard isObserving else { return false }
            isObserving = false
            return true
        }
        guard shouldRemove else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(
                KeyboardFixBridgeConfiguration.requestNotification as CFString
            ),
            nil
        )
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(
                KeyboardFixBridgeConfiguration
                    .cancellationNotification as CFString
            ),
            nil
        )
    }

    func receiveSignal(_ signal: IOSKeyboardFixCoordinationSignal) {
        let handler: (
            @Sendable (IOSKeyboardFixCoordinationSignal) -> Void
        )? = lock.withLock {
            self.handler
        }
        handler?(signal)
    }

    deinit {
        stop()
    }
}

nonisolated private func iosKeyboardFixRequestNotificationCallback(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard let observer, let name else { return }
    let signal: IOSKeyboardFixCoordinationSignal
    switch name.rawValue as String {
    case KeyboardFixBridgeConfiguration.requestNotification:
        signal = .requestChanged
    case KeyboardFixBridgeConfiguration.cancellationNotification:
        signal = .cancellationChanged
    default:
        return
    }
    Unmanaged<IOSKeyboardFixDarwinRequestObserver>
        .fromOpaque(observer)
        .takeUnretainedValue()
        .receiveSignal(signal)
}
