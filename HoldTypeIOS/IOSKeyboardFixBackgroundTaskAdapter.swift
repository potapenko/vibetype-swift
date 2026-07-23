import UIKit

/// Main-actor registry that pairs every processor attempt with one finite iOS
/// background task and ends it exactly once, including expiration.
@MainActor
final class IOSKeyboardFixBackgroundTaskRegistry {
    typealias BeginSystemTask = (
        _ expirationHandler: @escaping @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier
    typealias EndSystemTask = (UIBackgroundTaskIdentifier) -> Void

    private let beginSystemTask: BeginSystemTask
    private let endSystemTask: EndSystemTask
    private var identifiers:
        [IOSKeyboardFixBackgroundTaskToken: UIBackgroundTaskIdentifier] = [:]

    init(
        beginSystemTask: @escaping BeginSystemTask,
        endSystemTask: @escaping EndSystemTask
    ) {
        self.beginSystemTask = beginSystemTask
        self.endSystemTask = endSystemTask
    }

    static func production() -> IOSKeyboardFixBackgroundTaskRegistry {
        IOSKeyboardFixBackgroundTaskRegistry(
            beginSystemTask: { expirationHandler in
                UIApplication.shared.beginBackgroundTask(
                    withName: "HoldType Keyboard Fix",
                    expirationHandler: expirationHandler
                )
            },
            endSystemTask: {
                UIApplication.shared.endBackgroundTask($0)
            }
        )
    }

    var client: IOSKeyboardFixBackgroundTaskClient {
        IOSKeyboardFixBackgroundTaskClient(
            begin: { [weak self] expirationHandler in
                guard let self else {
                    return IOSKeyboardFixBackgroundTaskToken()
                }
                return await self.begin(expirationHandler)
            },
            end: { [weak self] token in
                await self?.end(token)
            }
        )
    }

    func endAll() {
        let active = identifiers.values
        identifiers.removeAll()
        for identifier in active where identifier != .invalid {
            endSystemTask(identifier)
        }
    }

    private func begin(
        _ expirationHandler: @escaping @Sendable () -> Void
    ) -> IOSKeyboardFixBackgroundTaskToken {
        let token = IOSKeyboardFixBackgroundTaskToken()
        let identifier = beginSystemTask { [weak self] in
            expirationHandler()
            Task { @MainActor [weak self] in
                self?.end(token)
            }
        }
        if identifier != .invalid {
            identifiers[token] = identifier
        }
        return token
    }

    private func end(_ token: IOSKeyboardFixBackgroundTaskToken) {
        guard let identifier = identifiers.removeValue(forKey: token),
              identifier != .invalid
        else {
            return
        }
        endSystemTask(identifier)
    }

    deinit {
        for identifier in identifiers.values where identifier != .invalid {
            endSystemTask(identifier)
        }
    }
}
