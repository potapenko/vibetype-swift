import SwiftUI

struct IOSSettingsMultilineField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let lineLimit: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
            TextField(
                prompt,
                text: $text,
                axis: .vertical
            )
            .lineLimit(lineLimit)
            .accessibilityLabel(title)
        }
    }
}

#Preview("Settings multiline field") {
    Form {
        IOSSettingsMultilineField(
            title: "Instructions",
            prompt: "Optional instructions",
            text: .constant("Keep the result concise."),
            lineLimit: 2...5
        )
    }
}
