import Foundation

enum IOSContainingAppLaunchDecision: Equatable {
    case ignore
    case settings(IOSSettingsAttention)
    case keyboardHandoff(KeyboardHandoffIntentRecord)
}

struct IOSKeyboardHandoffLaunchRouter {
    typealias Consume = (
        UUID,
        Date
    ) throws -> KeyboardHandoffIntentRecord?

    private let now: () -> Date
    private let consume: Consume

    init(
        now: @escaping () -> Date,
        consume: @escaping Consume
    ) {
        self.now = now
        self.consume = consume
    }

    static let live = Self(
        now: { Date() },
        consume: { requestID, date in
            let store = try KeyboardHandoffIntentStore.appGroup()
            return try store.consume(requestID: requestID, at: date)
        }
    )

    func resolve(_ url: URL) -> IOSContainingAppLaunchDecision {
        if let attention = IOSSettingsAttention(launchURL: url) {
            return .settings(attention)
        }
        guard let route = KeyboardHandoffLaunchRoute(url: url),
              let intent = try? consume(route.requestID, now()) else {
            return .ignore
        }
        return .keyboardHandoff(intent)
    }
}
