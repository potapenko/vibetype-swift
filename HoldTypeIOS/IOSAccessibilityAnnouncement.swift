import UIKit

enum IOSAccessibilityAnnouncement {
    static func message(title: String, detail: String) -> String {
        guard !detail.isEmpty else { return title }
        return "\(title). \(detail)"
    }

    @MainActor
    static func post(title: String, detail: String) {
        post(message(title: title, detail: detail))
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
