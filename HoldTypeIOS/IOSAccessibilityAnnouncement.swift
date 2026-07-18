import UIKit

nonisolated struct IOSAccessibilityAnnouncementCandidate:
    Equatable,
    Sendable {
    nonisolated enum Priority: Int, Sendable {
        case passive = 0
        case status = 1
        case content = 2
    }

    let message: String
    let priority: Priority

    static func preferred(
        current: Self?,
        incoming: Self
    ) -> Self {
        guard let current,
              current.priority.rawValue > incoming.priority.rawValue else {
            return incoming
        }
        return current
    }
}

enum IOSAccessibilityAnnouncement {
    static func message(title: String, detail: String) -> String {
        guard !detail.isEmpty else { return title }
        return "\(title). \(detail)"
    }

    static func transitionMessage(
        oldTitle: String,
        oldDetail: String,
        newTitle: String,
        newDetail: String
    ) -> String? {
        guard oldTitle != newTitle || oldDetail != newDetail else {
            return nil
        }
        return message(title: newTitle, detail: newDetail)
    }

    static func spokenElapsedTime(totalSeconds: Int) -> String {
        let safeSeconds = max(0, totalSeconds)
        let minutes = safeSeconds / 60
        let seconds = safeSeconds % 60
        let minutePart = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        let secondPart = seconds == 1 ? "1 second" : "\(seconds) seconds"

        if minutes == 0 { return secondPart }
        if seconds == 0 { return minutePart }
        return "\(minutePart), \(secondPart)"
    }

    @MainActor
    static func post(_ message: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: message
        )
    }
}
