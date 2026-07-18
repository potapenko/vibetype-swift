import Foundation
import HoldTypeDomain
import SwiftUI

struct IOSVoiceStatusRow: View {
    let status: IOSVoiceStatusPresentation
    let listeningStartedAt: Date?
    let recordingDurationLimit: RecordingDurationLimit?

    var body: some View {
        if let listeningStartedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let totalSeconds = elapsedSeconds(
                    from: listeningStartedAt,
                    at: context.date
                )
                let countdown = VoiceSessionWarningSchedule(
                    limit: recordingDurationLimit ?? .default
                ).countdown(atElapsedWholeSecond: totalSeconds)
                statusContent(
                    timeText: countdown.map(countdownText)
                        ?? elapsedText(totalSeconds),
                    countdownUrgency: countdown?.urgency
                )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(status.title)
                    .accessibilityValue(
                        IOSAccessibilityAnnouncement.message(
                            title: status.detail,
                            detail: countdown.map(accessibilityCountdownText)
                                ?? "Elapsed time "
                                    + IOSAccessibilityAnnouncement
                                    .spokenElapsedTime(
                                        totalSeconds: totalSeconds
                                    )
                        )
                    )
            }
        } else {
            statusContent(timeText: nil, countdownUrgency: nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(status.title)
                .accessibilityValue(status.detail)
        }
    }

    private func statusContent(
        timeText: String?,
        countdownUrgency: VoiceSessionWarningUrgency?
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(status.title)
                    Spacer(minLength: 8)
                    if let timeText {
                        Text(timeText)
                            .font(
                                countdownUrgency == nil
                                    ? .subheadline.monospacedDigit()
                                    : .subheadline.monospacedDigit().bold()
                            )
                            .foregroundStyle(
                                countdownColor(countdownUrgency)
                            )
                    }
                }
                Text(status.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            if status.showsProgress {
                ProgressView()
            } else {
                Image(systemName: status.systemImage)
                    .foregroundStyle(status.color)
            }
        }
    }

    private func elapsedSeconds(from start: Date, at now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(start)))
    }

    private func elapsedText(_ totalSeconds: Int) -> String {
        String(
            format: "%d:%02d",
            totalSeconds / 60,
            totalSeconds % 60
        )
    }

    private func countdownText(_ countdown: VoiceSessionCountdown) -> String {
        "\(countdown.remainingWholeSeconds)s"
    }

    private func accessibilityCountdownText(
        _ countdown: VoiceSessionCountdown
    ) -> String {
        "Recording limit in \(countdown.remainingWholeSeconds) seconds"
    }

    private func countdownColor(
        _ urgency: VoiceSessionWarningUrgency?
    ) -> Color {
        switch urgency {
        case .amber:
            return .orange
        case .red:
            return .red
        case nil:
            return .secondary
        }
    }
}

extension IOSVoiceStatusPresentation {
    var color: Color {
        tone.color
    }
}

private extension IOSVoiceStatusTone {
    var color: Color {
        switch self {
        case .neutral:
            .secondary
        case .active:
            .accentColor
        case .success:
            .green
        case .warning:
            .orange
        case .failure:
            .red
        }
    }
}

#Preview("Ready") {
    IOSVoiceStatusRow(
        status: IOSVoiceStatusPresentation(
            title: "Ready to dictate",
            detail: "Record in HoldType and keep the result under your control.",
            systemImage: "mic.fill",
            tone: .neutral,
            showsProgress: false,
            setupDestination: nil
        ),
        listeningStartedAt: nil,
        recordingDurationLimit: nil
    )
    .padding()
}

#Preview("Needs attention") {
    IOSVoiceStatusRow(
        status: IOSVoiceStatusPresentation(
            title: "Microphone access is off",
            detail: "Open Privacy & Permissions to allow recording, then return to Voice.",
            systemImage: "mic.slash",
            tone: .warning,
            showsProgress: false,
            setupDestination: nil
        ),
        listeningStartedAt: nil,
        recordingDurationLimit: nil
    )
    .padding()
}
