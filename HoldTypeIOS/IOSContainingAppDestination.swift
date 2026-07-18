import Foundation
import UIKit

enum IOSContainingAppDestination: String, CaseIterable, Identifiable,
    Hashable, Sendable {
    case voice
    case library
    case history
    case usage
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice:
            "Voice"
        case .library:
            "Rules"
        case .history:
            "History"
        case .usage:
            "Usage"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .voice:
            "mic.fill"
        case .library:
            "checklist"
        case .history:
            "clock.arrow.circlepath"
        case .usage:
            "chart.bar.xaxis"
        case .settings:
            "gearshape.fill"
        }
    }

    var accessibilityIdentifier: String {
        "ios.destination.\(rawValue)"
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
    case diagnostics
    case attention(IOSSettingsAttention)
}

enum IOSSettingsField: String, Hashable, Sendable {
    case openAIKey
    case transcriptionModel
    case transcriptionLanguage
    case transcriptionCustomLanguage
    case transcriptionInstructions
    case correctionLocalCleanup
    case correctionEnabled
    case correctionModel
    case correctionCustomModel
    case correctionInstructions
    case translationSourceMode
    case translationSourceLanguage
    case translationCustomSource
    case translationTargetLanguage
    case translationCustomTarget
    case translationModel
    case translationInstructions
    case voiceAudioCues
    case voiceFinishBuffer
    case voiceRecordingDurationLimit
    case voiceRecordingCache
    case voiceRecordingRetention
    case voiceRecordingLimit
    case keyboardSystemSettings
    case keyboardPractice
    case privacyMicrophone
    case privacyProviderConsent
}

enum IOSSettingsAttention: String, Hashable, Sendable {
    case openAI
    case transcription
    case translation
    case keyboard
    case fullAccess
    case privacyReview
    case microphonePermission

    static let launchScheme = "holdtype"
    static let launchHost = "settings"

    init?(launchURL: URL) {
        guard launchURL.scheme == Self.launchScheme,
              launchURL.host == Self.launchHost else {
            return nil
        }
        let component = launchURL.pathComponents
            .filter { $0 != "/" }
            .first
        guard let component, let value = Self(rawValue: component) else {
            return nil
        }
        self = value
    }

    var launchURL: URL? {
        var components = URLComponents()
        components.scheme = Self.launchScheme
        components.host = Self.launchHost
        components.path = "/\(rawValue)"
        return components.url
    }

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
        .attention(self)
    }

    var defaultField: IOSSettingsField {
        switch self {
        case .openAI:
            .openAIKey
        case .transcription:
            .transcriptionLanguage
        case .translation:
            .translationTargetLanguage
        case .keyboard:
            .keyboardPractice
        case .fullAccess:
            .keyboardSystemSettings
        case .privacyReview:
            .privacyProviderConsent
        case .microphonePermission:
            .privacyMicrophone
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
