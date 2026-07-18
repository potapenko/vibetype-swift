import SwiftUI

struct TranscriptHistoryRowView: View {
    let entry: TranscriptHistoryEntry
    let canPlayAudio: Bool
    let onPlayAudio: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 58, alignment: .leading)

            Text(entry.transcriptText)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if canPlayAudio {
                    Button(action: onPlayAudio) {
                        Label("Play", systemImage: "play.circle")
                    }
                    .help("Play Cached Recording")
                    .accessibilityLabel("Play Cached Recording")
                }

                Button(action: onCopy) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .help("Copy to Clipboard")
                .accessibilityLabel("Copy Transcript to Clipboard")

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete History Row")
                .accessibilityLabel("Delete Transcript")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

#if DEBUG
#Preview("Cached recording") {
    TranscriptHistoryRowView(
        entry: try! TranscriptHistoryEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            createdAt: Date(timeIntervalSince1970: 1_725_192_000),
            transcriptText: "A fixed transcript with a locally cached recording.",
            transcriptionModel: "gpt-4o-transcribe",
            languageCode: "en",
            audioDuration: 42,
            cachedAudioFileURL: URL(fileURLWithPath: "/preview/history.m4a")
        ),
        canPlayAudio: true,
        onPlayAudio: {},
        onCopy: {},
        onDelete: {}
    )
    .frame(width: 620)
    .padding()
}

#Preview("Text only") {
    TranscriptHistoryRowView(
        entry: try! TranscriptHistoryEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            createdAt: Date(timeIntervalSince1970: 1_725_192_000),
            transcriptText: "A fixed transcript without retained audio.",
            transcriptionModel: "gpt-4o-transcribe",
            languageCode: nil
        ),
        canPlayAudio: false,
        onPlayAudio: {},
        onCopy: {},
        onDelete: {}
    )
    .frame(width: 620)
    .padding()
}
#endif
