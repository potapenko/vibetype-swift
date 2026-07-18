import SwiftUI

struct IOSMissingCustomEmojiCommandView: View {
    var body: some View {
        ContentUnavailableView {
            Label(
                "Command Unavailable",
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text("This custom command is no longer saved.")
        }
    }
}

#Preview("Custom emoji command unavailable") {
    NavigationStack {
        IOSMissingCustomEmojiCommandView()
            .navigationTitle("Custom Command")
    }
}
