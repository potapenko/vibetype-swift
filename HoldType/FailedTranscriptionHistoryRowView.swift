import Foundation
import SwiftUI

struct FailedTranscriptionHistoryRowView: View {
    let attempt: FailedTranscriptionAttempt
    let canPlayAudio: Bool
    let savedRecordingActionsEnabled: Bool
    let onPlayAudio: () -> Void
    let onRetry: () -> Void
    let onRetrySave: () -> Void
    let onOpenSettings: (SettingsNavigationItem) -> Void
    let onDelete: () -> Void

    private var presentation: TranscriptionRecoveryHistoryRowPresentation {
        TranscriptionRecoveryHistoryRowPresentation(attempt: attempt)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(attempt.updatedAt.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if presentation.showsProgress {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: presentation.systemImage)
                            .foregroundStyle(
                                attempt.state == .saved ? Color.green : Color.orange
                            )
                    }

                    Text(presentation.title)
                        .font(.body)
                        .fontWeight(.semibold)
                }

                Text(presentation.message)
                    .font(.body)
                    .foregroundStyle(attempt.state == .saved ? .primary : .secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(metadataText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if canPlayAudio {
                    Button(action: onPlayAudio) {
                        Label("Play", systemImage: "play.circle")
                    }
                    .help("Play Saved Recording")
                    .accessibilityLabel("Play Saved Recording")
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(!savedRecordingActionsEnabled)
                }

                if presentation.showsSettings,
                   let settingsTarget = attempt.reason.settingsTarget {
                    Button {
                        onOpenSettings(settingsTarget)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Open Settings")
                    .controlSize(.small)
                }

                if presentation.showsRetry {
                    Button(action: onRetry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .help("Retry Transcription")
                    .controlSize(.small)
                    .disabled(!savedRecordingActionsEnabled)
                }

                if presentation.showsSaveRetry {
                    Button(action: onRetrySave) {
                        Label(
                            presentation.saveRetryTitle,
                            systemImage: "externaldrive.badge.checkmark"
                        )
                    }
                    .help(presentation.saveRetryTitle)
                    .controlSize(.small)
                    .disabled(!savedRecordingActionsEnabled)
                }

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete Saved Recording")
                .accessibilityLabel("Delete Saved Recording")
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(
                    !savedRecordingActionsEnabled
                        || !attempt.canDelete
                )
            }
        }
        .padding(12)
        .background(
            backgroundColor,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var backgroundColor: Color {
        switch attempt.state {
        case .processing:
            return Color.accentColor.opacity(0.08)
        case .failed:
            return Color.orange.opacity(0.10)
        case .saved:
            return Color.green.opacity(0.08)
        }
    }

    private var metadataText: String {
        var parts: [String] = []

        if attempt.state == .failed {
            parts.append(attempt.reason.title)
        } else if attempt.state == .saved {
            parts.append("Saved")
        }

        if !attempt.transcriptionModel.isEmpty {
            parts.append(attempt.transcriptionModel)
        }

        parts.append(attempt.languageCode ?? "Auto")

        if let audioDuration = attempt.audioDuration {
            parts.append(Self.durationFormatter.string(from: audioDuration) ?? "\(Int(audioDuration.rounded()))s")
        }

        if attempt.retryCount > 0 {
            parts.append("Retries: \(attempt.retryCount)")
        }

        return parts.joined(separator: " · ")
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

#if DEBUG
private enum FailedTranscriptionHistoryRowPreview {
    static func attempt(
        state: TranscriptionRecoveryState,
        reason: FailedTranscriptionReason,
        acceptedTranscriptText: String? = nil
    ) -> FailedTranscriptionAttempt {
        FailedTranscriptionAttempt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            createdAt: Date(timeIntervalSince1970: 1_725_192_000),
            audioFileURL: URL(fileURLWithPath: "/preview/recovery.m4a"),
            audioDuration: 73,
            transcriptionModel: "gpt-4o-transcribe",
            languageCode: "en",
            state: state,
            reason: reason,
            retryCount: 1,
            acceptedTranscriptText: acceptedTranscriptText
        )
    }
}

#Preview("Processing recording") {
    FailedTranscriptionHistoryRowView(
        attempt: FailedTranscriptionHistoryRowPreview.attempt(
            state: .processing,
            reason: .other
        ),
        canPlayAudio: true,
        savedRecordingActionsEnabled: false,
        onPlayAudio: {},
        onRetry: {},
        onRetrySave: {},
        onOpenSettings: { _ in },
        onDelete: {}
    )
    .frame(width: 720)
    .padding()
}

#Preview("Retryable failure") {
    FailedTranscriptionHistoryRowView(
        attempt: FailedTranscriptionHistoryRowPreview.attempt(
            state: .failed,
            reason: .networkFailure
        ),
        canPlayAudio: true,
        savedRecordingActionsEnabled: true,
        onPlayAudio: {},
        onRetry: {},
        onRetrySave: {},
        onOpenSettings: { _ in },
        onDelete: {}
    )
    .frame(width: 720)
    .padding()
}

#Preview("Saved transcription") {
    FailedTranscriptionHistoryRowView(
        attempt: FailedTranscriptionHistoryRowPreview.attempt(
            state: .saved,
            reason: .other,
            acceptedTranscriptText: "A fixed recovered transcription."
        ),
        canPlayAudio: true,
        savedRecordingActionsEnabled: true,
        onPlayAudio: {},
        onRetry: {},
        onRetrySave: {},
        onOpenSettings: { _ in },
        onDelete: {}
    )
    .frame(width: 720)
    .padding()
}
#endif
