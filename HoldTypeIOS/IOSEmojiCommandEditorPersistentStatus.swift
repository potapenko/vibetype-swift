import SwiftUI

struct IOSEmojiCommandEditorPersistentStatus: View {
    let phase: IOSEmojiCommandEditorPhase

    @ViewBuilder
    var body: some View {
        switch phase {
        case .saveFailed:
            status(
                "Not Saved — saved command unchanged",
                systemImage: "exclamationmark.triangle.fill",
                color: .red
            )
        case .changedElsewhere:
            status(
                "Changed Elsewhere — draft not saved",
                systemImage: "arrow.triangle.2.circlepath",
                color: .orange
            )
        case .deletedElsewhere:
            status(
                "Deleted Elsewhere — Save unavailable",
                systemImage: "trash",
                color: .orange
            )
        case .idle, .saving, .saved, .invalid:
            EmptyView()
        }
    }

    private func status(
        _ title: String,
        systemImage: String,
        color: Color
    ) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
        .font(.footnote.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .accessibilityIdentifier(
            "ios.library.emoji-commands.editor.persistent-status"
        )
    }
}

#Preview("Custom emoji command — persistent status") {
    VStack {
        Spacer()
        IOSEmojiCommandEditorPersistentStatus(phase: .saveFailed)
    }
}
