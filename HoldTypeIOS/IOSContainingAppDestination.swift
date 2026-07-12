import UIKit

enum IOSContainingAppDestination: String, CaseIterable, Identifiable,
    Hashable, Sendable {
    case voice
    case library
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice:
            "Voice"
        case .library:
            "Library"
        case .history:
            "History"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .voice:
            "mic.fill"
        case .library:
            "books.vertical.fill"
        case .history:
            "clock.arrow.circlepath"
        case .settings:
            "gearshape.fill"
        }
    }

    var accessibilityIdentifier: String {
        "ios.destination.\(rawValue)"
    }

    static func resolve(storedRawValue: String) -> Self {
        Self(rawValue: storedRawValue) ?? .voice
    }
}

enum IOSContainingAppShellLayout: Equatable, Sendable {
    case tabs
    case split

    init(interfaceIdiom: UIUserInterfaceIdiom) {
        self = interfaceIdiom == .pad ? .split : .tabs
    }

    static var current: Self {
        Self(interfaceIdiom: UIDevice.current.userInterfaceIdiom)
    }
}

enum IOSSecureProviderAvailability: Equatable, Sendable {
    case available
    case unavailable

    static func resolve(
        compositionAvailability: IOSContainingAppCompositionAvailability
    ) -> Self {
        compositionAvailability == .ready ? .available : .unavailable
    }
}

enum IOSContainingAppRootPresentation: Equatable, Sendable {
    case shell
    case storageUnavailable

    static func resolve(
        hasSettingsStateOwner: Bool,
        hasLibraryStateOwner: Bool
    ) -> Self {
        hasSettingsStateOwner && hasLibraryStateOwner
            ? .shell
            : .storageUnavailable
    }
}
