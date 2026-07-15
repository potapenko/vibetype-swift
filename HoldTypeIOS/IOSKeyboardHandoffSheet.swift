import SwiftUI

enum IOSKeyboardHandoffSheetPhase: Equatable, Sendable {
    case starting
    case listening
}

struct IOSKeyboardHandoffSheetPresentation: Equatable, Sendable {
    let phase: IOSKeyboardHandoffSheetPhase

    var title: String {
        switch phase {
        case .starting:
            "Starting dictation…"
        case .listening:
            "HoldType is listening"
        }
    }

    var detail: String {
        switch phase {
        case .starting:
            "Getting your microphone ready."
        case .listening:
            "Return to the app where you were typing."
        }
    }

    var instructionTitle: String {
        "Swipe right on the bottom bar"
    }

    var instructionDetail: String {
        switch phase {
        case .starting:
            "This gesture is ready as soon as HoldType starts listening."
        case .listening:
            "Recording will continue after you return."
        }
    }

    var activityPhase: IOSVoiceActivityPhase {
        switch phase {
        case .starting:
            .ready
        case .listening:
            .listening
        }
    }

    var returnInstructionIsActive: Bool {
        phase == .listening
    }

    var accessibilityStatus: String {
        [title, detail, instructionTitle, instructionDetail]
            .joined(separator: ". ")
    }
}

enum IOSKeyboardHandoffMotionPolicy {
    static func animatesReturnCue(
        isActive: Bool,
        reduceMotion: Bool
    ) -> Bool {
        isActive && !reduceMotion
    }
}

struct IOSKeyboardHandoffSheet: View {
    let presentation: IOSKeyboardHandoffSheetPresentation
    let cancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                closeRow

                VStack(spacing: 22) {
                    IOSVoiceActivityIndicator(
                        phase: presentation.activityPhase
                    )
                    .id(presentation.activityPhase)
                    .frame(width: 184, height: 184)

                    VStack(spacing: 8) {
                        Text(presentation.title)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)

                        Text(presentation.detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .accessibilityElement(children: .combine)

                    IOSKeyboardHandoffSwipeGuide(
                        title: presentation.instructionTitle,
                        detail: presentation.instructionDetail,
                        isActive: presentation.returnInstructionIsActive
                    )
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(36)
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .interactiveDismissDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios.keyboard-handoff.sheet")
    }

    private var closeRow: some View {
        HStack {
            Spacer()

            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle()
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel keyboard dictation")
            .accessibilityHint(
                "Stops this keyboard request and returns to Voice."
            )
            .accessibilityIdentifier("ios.keyboard-handoff.cancel")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

private struct IOSKeyboardHandoffSwipeGuide: View {
    let title: String
    let detail: String
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            gestureArtwork

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .multilineTextAlignment(.center)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    isActive
                        ? Color.accentColor.opacity(0.22)
                        : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        }
        .opacity(isActive ? 1 : 0.64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityIdentifier("ios.keyboard-handoff.swipe-guide")
    }

    private var gestureArtwork: some View {
        ZStack {
            Capsule()
                .fill(isActive ? Color.primary : Color.secondary)
                .frame(width: 112, height: 6)

            arrow
                .offset(y: -24)
        }
        .frame(height: 44)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var arrow: some View {
        if !IOSKeyboardHandoffMotionPolicy.animatesReturnCue(
            isActive: isActive,
            reduceMotion: reduceMotion
        ) {
            Image(systemName: "arrow.right")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
        } else {
            PhaseAnimator([false, true]) { advanced in
                Image(systemName: "arrow.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .offset(x: advanced ? 18 : -12)
                    .opacity(advanced ? 1 : 0.42)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
        }
    }
}

#Preview("Keyboard handoff — Listening") {
    Color(uiColor: .systemGroupedBackground)
        .sheet(isPresented: .constant(true)) {
            IOSKeyboardHandoffSheet(
                presentation: IOSKeyboardHandoffSheetPresentation(
                    phase: .listening
                ),
                cancel: {}
            )
        }
}
