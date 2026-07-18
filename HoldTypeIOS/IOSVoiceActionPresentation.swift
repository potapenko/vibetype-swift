import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
import HoldTypePersistence
enum IOSVoiceActionProminence: Equatable, Sendable {
    case primary
    case secondary
    case destructive
}

struct IOSVoiceActionPresentation: Equatable, Sendable {
    let title: String
    let systemImage: String
    let prominence: IOSVoiceActionProminence
    let requiresConfirmation: Bool
    let accessibilityIdentifier: String

    static func resolve(
        _ action: IOSForegroundVoiceAction
    ) -> IOSVoiceActionPresentation {
        switch action {
        case .startStandard:
            makeAction(
                action,
                title: "Start Dictation",
                image: "mic.fill",
                prominence: .primary
            )
        case .startTranslation:
            makeAction(
                action,
                title: "Translate",
                image: "character.bubble",
                prominence: .secondary
            )
        case .startCorrection:
            makeAction(
                action,
                title: "Correction",
                image: "wand.and.stars",
                prominence: .secondary
            )
        case .checkAgain:
            makeAction(
                action,
                title: "Check Again",
                image: "arrow.clockwise",
                prominence: .primary
            )
        case .cancelStart:
            makeAction(
                action,
                title: "Cancel Start",
                image: "xmark",
                prominence: .secondary
            )
        case .finishUtterance:
            makeAction(
                action,
                title: "Done",
                image: "checkmark",
                prominence: .primary
            )
        case .cancelUtterance:
            makeAction(
                action,
                title: "Cancel Utterance",
                image: "xmark",
                prominence: .secondary
            )
        case .cancelProcessing:
            makeAction(
                action,
                title: "Cancel Processing",
                image: "xmark",
                prominence: .secondary
            )
        case .recoverRecording:
            makeAction(
                action,
                title: "Recover Recording",
                image: "arrow.clockwise",
                prominence: .primary
            )
        case .retryPending:
            makeAction(
                action,
                title: "Retry Transcription",
                image: "arrow.clockwise",
                prominence: .primary
            )
        case .discard:
            makeAction(
                action,
                title: "Discard Recording",
                image: "trash",
                prominence: .destructive,
                requiresConfirmation: true
            )
        }
    }

    private static func makeAction(
        _ action: IOSForegroundVoiceAction,
        title: String,
        image: String,
        prominence: IOSVoiceActionProminence,
        requiresConfirmation: Bool = false
    ) -> IOSVoiceActionPresentation {
        IOSVoiceActionPresentation(
            title: title,
            systemImage: image,
            prominence: prominence,
            requiresConfirmation: requiresConfirmation,
            accessibilityIdentifier:
                "ios.voice.action.\(accessibilityName(for: action))"
        )
    }

    private static func accessibilityName(
        for action: IOSForegroundVoiceAction
    ) -> String {
        switch action {
        case .startStandard: "start-standard"
        case .startTranslation: "start-translation"
        case .startCorrection: "start-correction"
        case .checkAgain: "check-again"
        case .cancelStart: "cancel-start"
        case .finishUtterance: "finish-utterance"
        case .cancelUtterance: "cancel-utterance"
        case .cancelProcessing: "cancel-processing"
        case .recoverRecording: "recover-recording"
        case .retryPending: "retry-pending"
        case .discard: "discard"
        }
    }
}
enum IOSVoiceHomeActionPlacement {
    static func isCancellation(
        _ action: IOSForegroundVoiceAction
    ) -> Bool {
        switch action {
        case .cancelStart, .cancelUtterance, .cancelProcessing:
            true
        default:
            false
        }
    }

    static func isVisibleStatusAction(
        _ action: IOSForegroundVoiceAction
    ) -> Bool {
        switch action {
        case .startStandard, .startTranslation, .startCorrection,
             .finishUtterance, .cancelStart, .cancelUtterance,
             .cancelProcessing:
            false
        case .checkAgain, .recoverRecording, .retryPending, .discard:
            true
        }
    }
}
