import SwiftUI

enum IOSKeyboardHandoffSheetPhase: Equatable, Sendable {
    case starting
    case listening
    case processing
    case savedRecording
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
        case .savedRecording:
            "Recording Saved"
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
        case .savedRecording:
            "Your audio is safe on this device."
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
        case .processing, .savedRecording, .blocked:
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
        case .savedRecording, .blocked:
            nil
        }
    }

    var returnInstructionIsActive: Bool {
        phase == .listening
    }

    var showsReturnInstruction: Bool {
        phase == .starting || phase == .listening
    }

}

struct IOSKeyboardHandoffSavedRecordingContent: Equatable, Sendable {
    let title: String
    let detail: String
    let durationText: String?
    let showsPlay: Bool
    let primaryActionTitle: String?
    let allowsDelete: Bool

    init(card: IOSPendingRecordingHistoryCard) {
        durationText = card.durationText
        showsPlay = card.isPlayable
        primaryActionTitle = switch card.primaryAction {
        case .transcribe:
            "Transcribe"
        case .retry:
            "Retry"
        case nil:
            nil
        }
        allowsDelete = !card.status.isProcessing

        switch card.status {
        case .ready:
            title = "Ready to Transcribe"
            detail = "Your audio is safe on this device and ready to transcribe."
        case .processing(.transcribing):
            title = "Transcribing Saved Recording"
            detail = "Your audio stays saved until transcription finishes."
        case .processing(.postProcessing):
            title = "Finishing Saved Recording"
            detail = "Your audio stays saved while HoldType prepares the text."
        case .processing(.savingResult):
            title = "Saving Dictation Result"
            detail = "Your audio stays saved until the result is secure."
        case .failed:
            title = "Recording Saved"
            detail = "Transcription didn’t finish. Your audio is still saved."
        case .blocked:
            title = "Recording Saved"
            detail = switch card.blockedReason {
            case .providerResultUnrecoverable:
                "HoldType couldn't safely recover the processing result. "
                    + "You can play or delete the saved audio."
            case .durationLimitExceeded:
                "This recording exceeds the supported transcription limit. "
                    + "You can play or delete the saved audio."
            case .audioUnavailable, nil:
                "Your audio is preserved, but it isn't currently available "
                    + "for transcription."
            }
        }
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
    let pendingRecordingOwner: IOSPendingRecordingHistoryStateOwner?
    let cancel: () -> Void
    let savedRecordingResolved: () -> Void

    @State private var pendingDiscardToken:
        IOSPendingRecordingHistorySnapshotToken?

    init(
        presentation: IOSKeyboardHandoffSheetPresentation,
        pendingRecordingOwner: IOSPendingRecordingHistoryStateOwner? = nil,
        cancel: @escaping () -> Void,
        savedRecordingResolved: @escaping () -> Void = {}
    ) {
        self.presentation = presentation
        self.pendingRecordingOwner = pendingRecordingOwner
        self.cancel = cancel
        self.savedRecordingResolved = savedRecordingResolved
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    closeRow

                    VStack(spacing: 22) {
                        activityVisual

                        VStack(spacing: 8) {
                            Text(displayTitle)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)

                            Text(displayDetail)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .accessibilityElement(children: .combine)

                        if presentation.phase == .savedRecording {
                            savedRecordingControls
                        }
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
        .task(id: presentation.phase) {
            guard presentation.phase == .savedRecording,
                  let pendingRecordingOwner else {
                return
            }
            let confirmed = await pendingRecordingOwner.refresh()
            if confirmed {
                finishSavedRecordingPresentationIfResolved()
            }
        }
        .task(id: savedRecordingPollingToken) {
            guard presentation.phase == .savedRecording,
                  let pendingRecordingOwner,
                  pendingRecordingOwner.card?.status.isProcessing == true else {
                return
            }
            while !Task.isCancelled,
                  pendingRecordingOwner.card?.status.isProcessing == true {
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
                _ = await pendingRecordingOwner.refresh()
            }
            finishSavedRecordingPresentationIfResolved()
        }
        .onDisappear {
            guard presentation.phase == .savedRecording,
                  let pendingRecordingOwner else {
                return
            }
            Task { await pendingRecordingOwner.stopPlayback() }
        }
        .confirmationDialog(
            "Delete Saved Recording?",
            isPresented: Binding(
                get: { pendingDiscardToken != nil },
                set: { if !$0 { pendingDiscardToken = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Recording", role: .destructive) {
                guard let token = pendingDiscardToken,
                      let pendingRecordingOwner else {
                    return
                }
                pendingDiscardToken = nil
                Task {
                    await pendingRecordingOwner.discard(ifCurrent: token)
                    finishSavedRecordingPresentationIfResolved()
                }
            }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("This permanently removes this saved audio from this device.")
        }
    }

    private var savedRecordingCard: IOSPendingRecordingHistoryCard? {
        guard presentation.phase == .savedRecording else { return nil }
        return pendingRecordingOwner?.card
    }

    private var savedRecordingContent:
        IOSKeyboardHandoffSavedRecordingContent? {
        guard let savedRecordingCard else { return nil }
        return IOSKeyboardHandoffSavedRecordingContent(
            card: savedRecordingCard
        )
    }

    private var displayTitle: String {
        if savedRecordingLoadNeedsRefresh {
            return "Saved Recording Needs Attention"
        }
        return savedRecordingContent?.title ?? presentation.title
    }

    private var displayDetail: String {
        if savedRecordingLoadNeedsRefresh {
            return "HoldType couldn't confirm the saved audio. Nothing was "
                + "removed. Retry Refresh before starting another dictation."
        }
        return savedRecordingContent?.detail ?? presentation.detail
    }

    private var savedRecordingLoadNeedsRefresh: Bool {
        presentation.phase == .savedRecording
            && pendingRecordingOwner?.state.isStale == true
            && pendingRecordingOwner?.card == nil
    }

    @ViewBuilder
    private var savedRecordingControls: some View {
        if let pendingRecordingOwner,
           let card = savedRecordingCard,
           let content = savedRecordingContent {
            VStack(spacing: 14) {
                if let durationText = content.durationText {
                    Label(durationText, systemImage: "clock")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Recording duration \(durationText)")
                }

                HStack(spacing: 12) {
                    if content.showsPlay {
                        Button("Play", systemImage: "play.fill") {
                            Task {
                                await pendingRecordingOwner.play(
                                    ifCurrent: card.token
                                )
                            }
                        }
                        .accessibilityIdentifier(
                            "ios.keyboard-handoff.saved-recording.play"
                        )
                    }

                    if let primaryActionTitle = content.primaryActionTitle {
                        Button(primaryActionTitle) {
                            Task {
                                await pendingRecordingOwner.retry(
                                    ifCurrent: card.token
                                )
                                finishSavedRecordingPresentationIfResolved()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(
                            "ios.keyboard-handoff.saved-recording.primary"
                        )
                    }

                    if content.allowsDelete {
                        Button("Delete", role: .destructive) {
                            pendingDiscardToken = card.token
                        }
                        .accessibilityIdentifier(
                            "ios.keyboard-handoff.saved-recording.delete"
                        )
                    }
                }
                .buttonStyle(.bordered)
                .disabled(pendingRecordingOwner.isBusy)

                if pendingRecordingOwner.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Working with saved recording")
                }

                if let notice = pendingRecordingOwner.notice {
                    VStack(spacing: 8) {
                        Label(
                            notice.message,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)

                        Button("Dismiss") {
                            pendingRecordingOwner.dismissNotice()
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
            }
            .accessibilityIdentifier(
                "ios.keyboard-handoff.saved-recording"
            )
        } else if let pendingRecordingOwner,
                  savedRecordingLoadNeedsRefresh {
            VStack(spacing: 14) {
                Label(
                    "Saved recording status couldn't be refreshed.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)

                Button("Retry Refresh", systemImage: "arrow.clockwise") {
                    Task {
                        _ = await pendingRecordingOwner.refresh()
                        finishSavedRecordingPresentationIfResolved()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(pendingRecordingOwner.isBusy)
                .accessibilityIdentifier(
                    "ios.keyboard-handoff.saved-recording.refresh"
                )
            }
            .accessibilityIdentifier(
                "ios.keyboard-handoff.saved-recording.blocked"
            )
        } else {
            ProgressView("Loading saved recording…")
                .accessibilityIdentifier(
                    "ios.keyboard-handoff.saved-recording.loading"
                )
        }
    }

    private var savedRecordingPollingToken: String {
        guard presentation.phase == .savedRecording else { return "inactive" }
        guard let card = pendingRecordingOwner?.card else { return "absent" }
        return "\(card.id.uuidString)|\(String(describing: card.status))"
    }

    private func finishSavedRecordingPresentationIfResolved() {
        guard presentation.phase == .savedRecording,
              pendingRecordingOwner?.isConfirmedAbsent == true else {
            return
        }
        savedRecordingResolved()
    }

    @ViewBuilder
    private var activityVisual: some View {
        if savedRecordingLoadNeedsRefresh {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 132, height: 132)
                .background(.orange.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
        } else if presentation.phase == .savedRecording {
            Image(systemName: "waveform.badge.checkmark")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 132, height: 132)
                .background(.blue.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
        } else if let activityPhase = presentation.activityPhase {
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
            .accessibilityLabel(closeAccessibilityLabel)
            .accessibilityHint(closeAccessibilityHint)
            .accessibilityIdentifier("ios.keyboard-handoff.cancel")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var closeAccessibilityLabel: String {
        presentation.phase == .savedRecording
            ? "Close saved recording"
            : "Cancel keyboard dictation"
    }

    private var closeAccessibilityHint: String {
        presentation.phase == .savedRecording
            ? "Closes this sheet and keeps the recording saved."
            : "Stops this keyboard request and closes this sheet."
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
