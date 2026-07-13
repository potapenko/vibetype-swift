import Foundation
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
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["HOLDTYPE_AUTOMATION"] == "1",
           environment["HOLDTYPE_AUTOMATION_LAYOUT"] == "split" {
            return .split
        }
        #endif
        return Self(interfaceIdiom: UIDevice.current.userInterfaceIdiom)
    }
}

enum IOSContainingAppDestinationSelectionDecision: Equatable, Sendable {
    case unchanged
    case apply(IOSContainingAppDestination)
    case confirmDiscard(IOSContainingAppDestination)
    case blockedByEditorOperation

    static func resolve(
        current: IOSContainingAppDestination,
        requested: IOSContainingAppDestination,
        hasUnsavedEditor: Bool,
        hasBlockingEditorOperation: Bool = false
    ) -> Self {
        guard requested != current else { return .unchanged }
        guard !hasBlockingEditorOperation else {
            return .blockedByEditorOperation
        }
        return hasUnsavedEditor
            ? .confirmDiscard(requested)
            : .apply(requested)
    }
}

enum IOSSettingsRoute: Hashable {
    case openAI
    case general(IOSGeneralSettingsDestination)
    case privacyAndPermissions
}

enum IOSLibraryRoute: Hashable {
    case dictionary
    case emojiCommands
    case emojiSetSelection
    case builtInEmojiCommand(IOSBuiltInEmojiCommandReference)
    case newCustomEmojiCommand(UUID)
    case customEmojiCommand(UUID)
    case replacementRules
    case newReplacementRule(UUID)
    case replacementRule(UUID)
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
        hasLibraryStateOwner: Bool,
        hasOpenAISettingsStateOwner: Bool
    ) -> Self {
        hasSettingsStateOwner
            && hasLibraryStateOwner
            && hasOpenAISettingsStateOwner
            ? .shell
            : .storageUnavailable
    }
}
