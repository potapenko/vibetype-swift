import SwiftUI

struct TranscriptHistoryEmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

#if DEBUG
#Preview("No history yet") {
    TranscriptHistoryEmptyStateView(
        systemImage: "text.bubble",
        title: "No transcripts yet",
        message: "Accepted dictations and saved recordings will appear here."
    )
    .frame(width: 620, height: 420)
}

#Preview("History disabled") {
    TranscriptHistoryEmptyStateView(
        systemImage: "clock.badge.xmark",
        title: "Transcript history is off",
        message: "Accepted transcripts are not retained. Recordings saved for processing or retry will still appear here."
    )
    .frame(width: 620, height: 420)
}
#endif
