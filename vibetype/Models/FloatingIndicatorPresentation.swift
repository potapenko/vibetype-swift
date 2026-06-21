//
//  FloatingIndicatorPresentation.swift
//  vibetype
//
//  Created by Codex on 6/21/26.
//

import Foundation

struct FloatingIndicatorPresentation: Equatable {
    enum Phase: Equatable {
        case recording
        case transcribing
        case success
        case failure
    }

    static let successDismissalDelay: TimeInterval = 2
    static let failureDismissalDelay: TimeInterval = 6

    let phase: Phase
    let title: String
    let systemImage: String
    let dismissalDelay: TimeInterval?

    var accessibilityLabel: String {
        "VibeType \(title)"
    }

    static func presentation(
        for status: DictationStatus,
        settings: AppSettings
    ) -> FloatingIndicatorPresentation? {
        guard settings.showFloatingIndicator else {
            return nil
        }

        switch status {
        case .idle:
            return nil
        case .recording:
            return FloatingIndicatorPresentation(
                phase: .recording,
                title: "Recording",
                systemImage: "mic.fill",
                dismissalDelay: nil
            )
        case .transcribing:
            return FloatingIndicatorPresentation(
                phase: .transcribing,
                title: "Transcribing",
                systemImage: "waveform",
                dismissalDelay: nil
            )
        case .success:
            return FloatingIndicatorPresentation(
                phase: .success,
                title: "Done",
                systemImage: "checkmark.circle.fill",
                dismissalDelay: successDismissalDelay
            )
        case .failure(let message):
            return FloatingIndicatorPresentation(
                phase: .failure,
                title: shortFailureTitle(from: message),
                systemImage: "exclamationmark.triangle.fill",
                dismissalDelay: failureDismissalDelay
            )
        }
    }

    private static func shortFailureTitle(from message: String) -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            return "Error"
        }

        let maximumCharacterCount = 72
        guard trimmedMessage.count > maximumCharacterCount else {
            return trimmedMessage
        }

        let prefix = String(trimmedMessage.prefix(maximumCharacterCount))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)..."
    }
}
