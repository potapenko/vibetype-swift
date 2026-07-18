import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
import HoldTypePersistence
struct IOSVoiceDraftTextActionPresentation: Equatable, Sendable {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let processingStatus: IOSVoiceStatusPresentation

    static func resolve(
        _ action: IOSVoiceDraftTextAction
    ) -> IOSVoiceDraftTextActionPresentation {
        switch action {
        case .translate:
            IOSVoiceDraftTextActionPresentation(
                title: "Translate",
                systemImage: "character.bubble",
                accessibilityIdentifier: "ios.voice.draft.translate",
                processingStatus: IOSVoiceStatusPresentation(
                    title: "Translating…",
                    detail: "Applying the saved Translation settings to the current Draft.",
                    systemImage: "character.bubble",
                    tone: .active,
                    showsProgress: true,
                    setupDestination: nil
                )
            )
        case .correct:
            IOSVoiceDraftTextActionPresentation(
                title: "Correction",
                systemImage: "wand.and.stars",
                accessibilityIdentifier: "ios.voice.draft.correct",
                processingStatus: IOSVoiceStatusPresentation(
                    title: "Improving…",
                    detail: "Applying the saved Writing & Correction settings to the current Draft.",
                    systemImage: "wand.and.stars",
                    tone: .active,
                    showsProgress: true,
                    setupDestination: nil
                )
            )
        }
    }
}
struct IOSVoiceDraftClearPresentation: Equatable, Sendable {
    let isVisible: Bool
    let isEnabled: Bool

    static func resolve(
        visibleText: String,
        voicePhase: VoiceWorkPhase,
        draftIsBusy: Bool
    ) -> IOSVoiceDraftClearPresentation {
        let isVisible = !visibleText.isEmpty
        let voiceAllowsMutation = switch voicePhase {
        case .inactive, .ready:
            true
        case .arming, .listening, .finalizing, .processing:
            false
        }
        return IOSVoiceDraftClearPresentation(
            isVisible: isVisible,
            isEnabled: isVisible
                && voiceAllowsMutation
                && !draftIsBusy
        )
    }
}

struct IOSVoiceDraftPendingResultPresentation: Equatable, Sendable {
    let title: String
    let detail: String
    let systemImage: String
    let hidesConfirmedText: Bool

    var accessibilityAnnouncement: String {
        "\(title) \(detail)"
    }

    static func resolve(
        _ presentation: IOSForegroundVoicePresentation
    ) -> IOSVoiceDraftPendingResultPresentation? {
        guard let insertionMode = presentation.activeDraftInsertionMode else {
            return nil
        }
        switch presentation.phase {
        case .arming, .listening, .finalizing, .processing:
            break
        case .inactive, .ready:
            return nil
        }

        let voiceStatus = IOSVoiceHomePresentation.resolve(presentation)
        let detail = switch (insertionMode, presentation.phase) {
        case (.replace, .arming), (.replace, .listening):
            "New text will appear here when you finish."
        case (.replace, .finalizing), (.replace, .processing):
            "Your result will appear here."
        case (.append, .arming), (.append, .listening):
            "New text will be added below when you finish."
        case (.append, .finalizing), (.append, .processing):
            "Your result will be added below."
        case (_, .inactive), (_, .ready):
            preconditionFailure("Inactive Voice cannot await a Draft result.")
        }
        return IOSVoiceDraftPendingResultPresentation(
            title: voiceStatus.title,
            detail: detail,
            systemImage: voiceStatus.systemImage,
            hidesConfirmedText: insertionMode == .replace
        )
    }
}

enum IOSVoiceDraftAccessibilityFeedback {
    static let copyAnnouncement = "Current Draft copied"
    static let clearAnnouncement = "Draft cleared. Undo is available."
}
