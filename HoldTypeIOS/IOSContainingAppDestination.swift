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
    case keyboardSetup
    case privacyAndPermissions
    case usageEstimate
    case voiceRecovery(IOSVoiceSettingsRecovery)
}

enum IOSVoiceSettingsRecovery: String, Hashable, Sendable {
    case openAI
    case transcription
    case translation
    case keyboard
    case fullAccess
    case privacyReview
    case microphonePermission

    var title: String {
        switch self {
        case .openAI:
            "OpenAI key required for Voice"
        case .transcription:
            "Transcription setup required"
        case .translation:
            "Translation setup required"
        case .keyboard:
            "Keyboard setup required"
        case .fullAccess:
            "Full Access required for keyboard voice"
        case .privacyReview:
            "Privacy review required"
        case .microphonePermission:
            "Microphone access is off"
        }
    }

    var detail: String {
        switch self {
        case .openAI:
            "Add or repair the API key below. HoldType cannot transcribe Voice recordings without it."
        case .transcription:
            "Choose a valid transcription language and model below."
        case .translation:
            "Choose a valid translation target before using Translate."
        case .keyboard:
            "Complete keyboard setup below, then verify it in the practice field."
        case .fullAccess:
            "Enable Allow Full Access for keyboard-controlled dictation, then return to HoldType."
        case .privacyReview:
            "Review microphone access and OpenAI processing consent below."
        case .microphonePermission:
            "Allow microphone access below, then return to Voice and start dictation again."
        }
    }

    var systemImage: String {
        switch self {
        case .openAI:
            "key.fill"
        case .transcription:
            "waveform.and.mic"
        case .translation:
            "character.bubble"
        case .keyboard, .fullAccess:
            "keyboard.badge.ellipsis"
        case .privacyReview:
            "hand.raised.fill"
        case .microphonePermission:
            "mic.slash.fill"
        }
    }

    var destination: IOSSettingsRoute {
        switch self {
        case .openAI:
            .openAI
        case .transcription:
            .general(.transcription)
        case .translation:
            .general(.translation)
        case .keyboard, .fullAccess:
            .keyboardSetup
        case .privacyReview, .microphonePermission:
            .privacyAndPermissions
        }
    }
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
        hasOpenAISettingsStateOwner: Bool,
        hasUsageEstimateStateOwner: Bool,
        hasAcceptedTextHistoryStateOwner: Bool
    ) -> Self {
        hasSettingsStateOwner
            && hasLibraryStateOwner
            && hasOpenAISettingsStateOwner
            && hasUsageEstimateStateOwner
            && hasAcceptedTextHistoryStateOwner
            ? .shell
            : .storageUnavailable
    }
}
