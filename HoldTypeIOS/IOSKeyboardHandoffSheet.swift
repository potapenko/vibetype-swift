import SwiftUI

enum IOSKeyboardHandoffSheetPhase: Equatable, Sendable {
    case starting
    case listening
    case processing
    case blocked
}

struct IOSKeyboardHandoffSheetPresentation: Equatable, Sendable {
    let phase: IOSKeyboardHandoffSheetPhase
    let issue: IOSKeyboardHandoffPreflightIssue?

    init(phase: IOSKeyboardHandoffSheetPhase) {
        self.phase = phase
        issue = nil
    }

    init(issue: IOSKeyboardHandoffPreflightIssue) {
        phase = .blocked
        self.issue = issue
    }

    var title: String {
        switch phase {
        case .starting:
            "Starting dictation…"
        case .listening:
            "HoldType is listening"
        case .processing:
            "Processing dictation…"
        case .blocked:
            issue?.title ?? "Keyboard dictation is unavailable"
        }
    }

    var detail: String {
        switch phase {
        case .starting:
            "Getting your microphone ready."
        case .listening:
            "Return to the app where you were typing."
        case .processing:
            "HoldType is preparing the result for the keyboard."
        case .blocked:
            issue?.detail ?? "Close this sheet and try again."
        }
    }

    var instructionTitle: String {
        "Swipe right to return"
    }

    var instructionDetail: String {
        switch phase {
        case .starting:
            "This gesture is ready as soon as HoldType starts listening."
        case .listening:
            "Recording will continue after you return."
        case .processing, .blocked:
            ""
        }
    }

    var activityPhase: IOSVoiceActivityPhase? {
        switch phase {
        case .starting:
            .ready
        case .listening:
            .listening
        case .processing:
            .recognizing
        case .blocked:
            nil
        }
    }

    var returnInstructionIsActive: Bool {
        phase == .listening
    }

    var showsReturnInstruction: Bool {
        phase == .starting || phase == .listening
    }

    var accessibilityStatus: String {
        [title, detail, showsReturnInstruction ? instructionTitle : nil,
         showsReturnInstruction ? instructionDetail : nil]
            .compactMap { $0 }
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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    closeRow

                    VStack(spacing: 22) {
                        activityVisual

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
                    }
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 160)
                }
                .frame(maxWidth: .infinity)
            }
            .overlay(alignment: .bottom) {
                if presentation.showsReturnInstruction {
                    IOSKeyboardHandoffBottomReturnGuide(
                        title: presentation.instructionTitle,
                        detail: presentation.instructionDetail,
                        isActive: presentation.returnInstructionIsActive
                    )
                    .offset(y: geometry.safeAreaInsets.bottom)
                }
            }
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

    @ViewBuilder
    private var activityVisual: some View {
        if let activityPhase = presentation.activityPhase {
            IOSVoiceActivityIndicator(phase: activityPhase)
                .id(activityPhase)
                .frame(width: 184, height: 184)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 132, height: 132)
                .background(.orange.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
        }
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
                "Stops this keyboard request and closes this sheet."
            )
            .accessibilityIdentifier("ios.keyboard-handoff.cancel")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

private struct IOSKeyboardHandoffBottomReturnGuide: View {
    let title: String
    let detail: String
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            swipeTrack
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        colors: [.clear, .black, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .opacity(isActive ? 1 : 0.64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(title) across the bottom edge. \(detail)"
        )
        .accessibilityIdentifier("ios.keyboard-handoff.swipe-guide")
    }

    private var swipeTrack: some View {
        chevrons
            .frame(maxWidth: 320)
            .frame(height: 48)
            .background {
                Capsule()
                    .fill(
                        isActive
                            ? Color.accentColor.opacity(0.13)
                            : Color.secondary.opacity(0.08)
                    )
            }
            .overlay {
                Capsule()
                    .stroke(
                        isActive
                            ? Color.accentColor.opacity(0.32)
                            : Color.secondary.opacity(0.14),
                        lineWidth: 1
                    )
            }
            .contentShape(Capsule())
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var chevrons: some View {
        if !IOSKeyboardHandoffMotionPolicy.animatesReturnCue(
            isActive: isActive,
            reduceMotion: reduceMotion
        ) {
            chevronRow(activeIndex: isActive ? 2 : nil)
        } else {
            PhaseAnimator([0, 1, 2]) { activeIndex in
                chevronRow(activeIndex: activeIndex)
            } animation: { _ in
                .easeInOut(duration: 0.34)
            }
        }
    }

    private func chevronRow(activeIndex: Int?) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(
                        index == activeIndex
                            ? Color.accentColor
                            : Color.secondary.opacity(0.34)
                    )
                    .scaleEffect(index == activeIndex ? 1.12 : 0.92)
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
