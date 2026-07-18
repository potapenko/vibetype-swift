import SwiftUI

struct IOSSettingsWarningLabel: View {
    let title: String
    let color: Color

    init(_ title: String, color: Color) {
        self.title = title
        self.color = color
    }

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(color)
        }
        .font(.footnote)
    }
}

#Preview("Settings warning") {
    IOSSettingsWarningLabel(
        "Review this value before continuing.",
        color: .orange
    )
    .padding()
}
