import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
import SwiftUI
import UIKit

struct IOSVoiceHomeView: View {
    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(IOSForegroundVoiceSceneHostOwner.self)
    private var sceneOwner
    @Environment(IOSForegroundVoiceLatestResultOwner.self)
    private var latestResultOwner
    @Environment(IOSVoiceDraftOwner.self)
    private var draftOwner
    @Environment(IOSVoiceDraftTextActionOwner.self)
    private var draftTextActionOwner
    @Environment(IOSProviderConsentPresentationOwner.self)
    private var consentOwner
    @Environment(IOSKeyboardDictationSessionCoordinator.self)
    private var keyboardSession

    @Binding var practiceText: String
    @State private var listeningStartedAt: Date?
    @State private var pendingVoiceCommand:
        IOSForegroundVoiceActionCommand?
    @State private var revealedCancellationCommand:
        IOSForegroundVoiceActionCommand?
    @State private var pendingLatestClearCommand:
        IOSForegroundVoiceLatestResultClearCommand?
    @State private var shareItem: IOSVoiceShareItem?
    @State private var latestActionNotice: String?
    @State private var draftActionNotice: IOSVoiceDraftActionNotice?
    @State private var showsKeyboardTools = false
    @State private var showsVoiceSessionModeMenu = false
    @State private var accessibilityAnnouncementTask: Task<Void, Never>?
    @State private var accessibilityAnnouncementCandidate:
        IOSAccessibilityAnnouncementCandidate?
    @State private var draftEditSaveTask: Task<Void, Never>?
    @State private var showsDraftJumpToLatest = false
    @State private var draftScrollToLatestRequest = 0
    @State private var automaticallyOpenedSetup: RecoveryDestination?
    @State private var sessionModes = IOSVoiceSessionModes()
    @FocusState private var practiceFieldIsFocused: Bool
    @FocusState private var draftEditorIsFocused: Bool

    let secureProviderAvailability: IOSSecureProviderAvailability
    let openSettings: (IOSSettingsRoute) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: IOSVoiceStagePlacement.contentSpacing) {
                    draftSurface
                        .frame(
                            minHeight: IOSVoiceStagePlacement.minimumDraftHeight,
                            maxHeight: IOSVoiceStagePlacement.maximumDraftHeight
                        )
                    voiceStage
                        .frame(
                            minHeight: IOSVoiceStagePlacement.minimumHeight,
                            maxHeight: .infinity
                        )
                }
                .frame(
                    height: max(
                        IOSVoiceStagePlacement.minimumContentHeight,
                        geometry.size.height - 22
                    ),
                    alignment: .top
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("HoldType")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        showsKeyboardTools = true
                    } label: {
                        Label(
                            "Keyboard Session",
                            systemImage: "keyboard.badge.ellipsis"
                        )
                    }
                    .accessibilityIdentifier("ios.voice.keyboard-tools")
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("ios.voice.more")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    openSettings(.privacyAndPermissions)
                } label: {
                    Label(
                        "Privacy & Permissions",
                        systemImage: "info.circle"
                    )
                }
                .accessibilityIdentifier("ios.voice.privacy-info")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    draftEditorIsFocused = false
                }
                .accessibilityIdentifier("ios.voice.draft.keyboard-done")
            }
        }
        .accessibilityIdentifier(
            IOSContainingAppDestination.voice.accessibilityIdentifier
        )
        .task {
            if case .notLoaded = draftOwner.state {
                await draftOwner.refresh()
            }
            let environment = ProcessInfo.processInfo.environment
            guard environment["HOLDTYPE_AUTOMATION"] == "1",
                  environment[
                    "HOLDTYPE_AUTOMATION_FOCUS_DRAFT"
                  ] == "1" else {
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            draftEditorIsFocused = true
        }
        .task {
            let environment = ProcessInfo.processInfo.environment
            guard environment["HOLDTYPE_AUTOMATION"] == "1",
                  environment[
                    "HOLDTYPE_AUTOMATION_FOCUS_PRACTICE"
                  ] == "1" else {
                return
            }
            await Task.yield()
            practiceFieldIsFocused = true
        }
        .onChange(
            of: sceneOwner.presentation.phase,
            initial: true
        ) { _, phase in
            revealedCancellationCommand = nil
            if phase == .listening {
                listeningStartedAt = listeningStartedAt ?? Date()
            } else {
                listeningStartedAt = nil
            }
            if phase != .inactive {
                draftEditorIsFocused = false
            }
        }
        .onChange(of: draftEditorIsFocused) { _, isFocused in
            if isFocused {
                guard draftOwner.isEditing || draftOwner.beginEditing() else {
                    draftEditorIsFocused = false
                    return
                }
            } else if draftOwner.isEditing {
                finishDraftEditing()
            }
        }
        .onChange(of: draftOwner.contentChange) { _, _ in
            draftActionNotice = nil
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            revealedCancellationCommand = nil
            draftEditorIsFocused = false
            if draftOwner.isEditing {
                finishDraftEditing()
            }
        }
        .onChange(of: sceneOwner.presentation) { old, new in
            let oldStatus = IOSVoiceHomePresentation.resolve(old)
            let newStatus = IOSVoiceHomePresentation.resolve(new)
            let transitionMessage = IOSAccessibilityAnnouncement.transitionMessage(
                oldTitle: oldStatus.title,
                oldDetail: oldStatus.detail,
                newTitle: newStatus.title,
                newDetail: newStatus.detail
            )
            let oldDraftStatus =
                IOSVoiceDraftPendingResultPresentation.resolve(old)
            let newDraftStatus =
                IOSVoiceDraftPendingResultPresentation.resolve(new)

            if oldDraftStatus == nil, let newDraftStatus {
                scheduleAccessibilityAnnouncement(
                    newDraftStatus.accessibilityAnnouncement,
                    priority: .status
                )
                return
            }
            if oldDraftStatus != nil,
               newDraftStatus == nil,
               new.outcome != .resultReady {
                let message = [
                    "Previous Draft is visible again.",
                    transitionMessage,
                ].compactMap { $0 }.joined(separator: " ")
                scheduleAccessibilityAnnouncement(message, priority: .status)
                return
            }
            guard let transitionMessage else { return }
            scheduleAccessibilityAnnouncement(
                transitionMessage,
                priority: .status
            )
        }
        .onChange(
            of: sceneOwner.presentation.setup,
            initial: true
        ) { _, setup in
            routeToSetupIfNeeded(setup)
        }
        .onChange(of: sceneOwner.actionCommands) { _, commands in
            if !commands.contains(where: {
                $0.action == .startTranslation
            }) {
                sessionModes.translates = false
            }
            if let pendingVoiceCommand,
               !commands.contains(pendingVoiceCommand) {
                self.pendingVoiceCommand = nil
            }
            if let revealedCancellationCommand,
               !commands.contains(revealedCancellationCommand) {
                self.revealedCancellationCommand = nil
            }
        }
        .onChange(of: latestResultOwner.presentation) { old, new in
            latestActionNotice = nil
            let oldStatus = IOSVoiceLatestStatusPresentation.resolve(old)
            let newStatus = IOSVoiceLatestStatusPresentation.resolve(new)
            if let message = IOSAccessibilityAnnouncement.transitionMessage(
                oldTitle: oldStatus.title,
                oldDetail: oldStatus.detail,
                newTitle: newStatus.title,
                newDetail: newStatus.detail
            ) {
                scheduleAccessibilityAnnouncement(
                    message,
                    priority: old.text != nil || new.text != nil
                        ? .content
                        : .passive
                )
            } else if old.text != new.text, new.text != nil {
                scheduleAccessibilityAnnouncement(
                    "Latest Result updated",
                    priority: .content
                )
            }
            guard let pendingLatestClearCommand,
                  latestResultOwner.clearCommand
                    != pendingLatestClearCommand else {
                return
            }
            self.pendingLatestClearCommand = nil
        }
        .onChange(of: draftTextActionOwner.notice) { _, notice in
            guard let notice else { return }
            if let route = notice.settingsRoute {
                openSettings(route)
            }
            scheduleAccessibilityAnnouncement(
                notice.message,
                priority: .content
            )
        }
        .onDisappear {
            draftEditSaveTask?.cancel()
            draftEditSaveTask = nil
            if draftOwner.isEditing {
                Task { await draftOwner.finishEditing() }
            }
            accessibilityAnnouncementTask?.cancel()
            accessibilityAnnouncementTask = nil
            accessibilityAnnouncementCandidate = nil
            revealedCancellationCommand = nil
        }
        .confirmationDialog(
            "Discard Recording?",
            isPresented: Binding(
                get: { pendingVoiceCommandIsCurrent },
                set: { if !$0 { pendingVoiceCommand = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Discard Recording", role: .destructive) {
                guard let command = pendingVoiceCommand,
                      sceneOwner.actionCommands.contains(command) else {
                    pendingVoiceCommand = nil
                    return
                }
                pendingVoiceCommand = nil
                _ = sceneOwner.submit(command)
            }
            Button("Keep Recording", role: .cancel) {
                pendingVoiceCommand = nil
            }
        } message: {
            Text(
                "This removes only the exact recoverable recording shown "
                    + "here. It does not clear History or Latest Result."
            )
        }
        .confirmationDialog(
            "Clear Latest Result?",
            isPresented: Binding(
                get: { pendingLatestClearCommandIsCurrent },
                set: { if !$0 { pendingLatestClearCommand = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Clear Latest Result", role: .destructive) {
                guard let command = pendingLatestClearCommand,
                      latestResultOwner.clearCommand == command else {
                    pendingLatestClearCommand = nil
                    return
                }
                pendingLatestClearCommand = nil
                _ = latestResultOwner.clear(command)
            }
            Button("Keep Result", role: .cancel) {
                pendingLatestClearCommand = nil
            }
        } message: {
            Text(
                "This clears only the exact app-private Latest Result. "
                    + "It does not delete History, recordings, usage, "
                    + "settings, or your API key."
            )
        }
        .sheet(item: $shareItem) { item in
            IOSVoiceActivityView(items: [item.text])
        }
        .sheet(isPresented: $showsKeyboardTools) {
            NavigationStack {
                Form {
                    keyboardDictationSessionSection
                    keyboardPracticeSection
                }
                .navigationTitle("Keyboard Session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showsKeyboardTools = false
                        }
                    }
                }
            }
        }
        .sheet(
            isPresented: voiceConsentSheetBinding,
            onDismiss: dismissVisibleVoiceConsent
        ) {
            if let prompt = visibleVoiceConsentPrompt {
                IOSProviderConsentVoiceSheet(
                    promptID: prompt.id,
                    sceneOwner: sceneOwner,
                    consentOwner: consentOwner
                )
            }
        }
    }

    private func draftTextActionButton(
        _ action: IOSVoiceDraftTextAction
    ) -> some View {
        let presentation = IOSVoiceDraftTextActionPresentation.resolve(action)
        let isEnabled = sceneOwner.presentation.phase == .inactive
            && draftOwner.isAvailableForMutation
            && !draftOwner.visibleText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty

        return Button {
            guard isEnabled else { return }
            draftActionNotice = nil
            draftTextActionOwner.dismissNotice()
            _ = draftTextActionOwner.submit(action)
        } label: {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(presentation.title)
        .accessibilityHint("Processes the complete current Draft.")
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }

    private var draftSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            draftActionBar

            Divider()

            Group {
                switch draftOwner.state {
                case .notLoaded:
                    ProgressView("Loading Draft…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loadFailed(lastConfirmed: nil):
                    ContentUnavailableView {
                        Label(
                            "Draft Unavailable",
                            systemImage: "doc.badge.exclamationmark"
                        )
                    } description: {
                        Text(
                            "HoldType couldn't safely load the current Draft."
                        )
                    } actions: {
                        Button("Try Again") {
                            Task { await draftOwner.refresh() }
                        }
                    }
                case .ready, .loadFailed(lastConfirmed: .some):
                    draftTextSurface
                }
            }

            Divider()

            draftBottomActionArea

            draftNotice
        }
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .accessibilityIdentifier("ios.voice.draft")
    }

    private var draftActionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 4) {
                draftIconActions
                Spacer(minLength: 12)
                draftClearAction
            }

            HStack(alignment: .center, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        oneShotDraftActions
                    }
                    HStack(spacing: 4) {
                        draftEditingIconActions
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 12)
                draftClearAction
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityIdentifier("ios.voice.draft-actions")
    }

    @ViewBuilder
    private var draftIconActions: some View {
        HStack(spacing: 4) {
            oneShotDraftActions
            draftEditingIconActions
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var oneShotDraftActions: some View {
        draftTextActionButton(.translate)
        draftTextActionButton(.correct)
    }

    @ViewBuilder
    private var draftEditingIconActions: some View {
        Button {
            draftActionNotice = nil
            Task { await draftOwner.undo() }
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 36, height: 36)
        }
        .disabled(!draftOwner.canUndo)
        .accessibilityLabel("Undo Draft Change")

        Button {
            draftActionNotice = nil
            Task { await draftOwner.redo() }
        } label: {
            Image(systemName: "arrow.uturn.forward")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 36, height: 36)
        }
        .disabled(!draftOwner.canRedo)
        .accessibilityLabel("Redo Draft Change")
    }

    @ViewBuilder
    private var draftClearAction: some View {
        if draftClearPresentation.isVisible {
            Button {
                clearDraft()
            } label: {
                draftLabeledActionLabel(
                    "Clear",
                    systemImage: "xmark.circle"
                )
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(!draftClearPresentation.isEnabled)
            .accessibilityLabel("Clear Current Draft")
            .accessibilityHint(
                "Clears only this Draft. Undo remains available."
            )
            .accessibilityIdentifier("ios.voice.draft.clear")
        }
    }

    @ViewBuilder
    private var draftTextSurface: some View {
        let pendingResult = draftPendingResultPresentation

        ZStack(alignment: .topLeading) {
            IOSVoiceDraftTextViewport(
                text: draftEditingBinding,
                isFocused: draftEditorFocusBinding,
                showsJumpToLatest: $showsDraftJumpToLatest,
                isEditable: draftEditorCanFocus,
                contentChange: draftOwner.contentChange,
                scrollToLatestRequest: draftScrollToLatestRequest,
                usesAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
                reduceMotion: reduceMotion
            )
            .frame(
                minHeight: 120,
                maxHeight: .infinity
            )
            .opacity(pendingResult?.hidesConfirmedText == true ? 0 : 1)
            .allowsHitTesting(pendingResult?.hidesConfirmedText != true)
            .accessibilityHidden(
                pendingResult?.hidesConfirmedText == true
            )

            if let pendingResult {
                draftPendingResultStatus(pendingResult)
            } else if draftOwner.visibleText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        "Ready for your first dictation",
                        systemImage: "text.page"
                    )
                    .font(.headline)
                    Text(draftEmptyDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if pendingResult == nil,
               showsDraftJumpToLatest,
               !draftOwner.visibleText.isEmpty,
               !draftEditorIsFocused {
                Button {
                    draftScrollToLatestRequest += 1
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show Newest Draft Text")
                .accessibilityIdentifier("ios.voice.draft.jump-to-latest")
            }
        }
    }

    private var draftPendingResultPresentation:
        IOSVoiceDraftPendingResultPresentation? {
        IOSVoiceDraftPendingResultPresentation.resolve(
            sceneOwner.presentation
        )
    }

    @ViewBuilder
    private func draftPendingResultStatus(
        _ presentation: IOSVoiceDraftPendingResultPresentation
    ) -> some View {
        let keepsVisibleText = !presentation.hidesConfirmedText
            && !draftOwner.visibleText.isEmpty

        if keepsVisibleText {
            VStack {
                Spacer(minLength: 12)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: presentation.systemImage)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(presentation.title)
                            .font(.subheadline.weight(.semibold))
                        Text(presentation.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground)
                        .opacity(0.96),
                    in: RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.title)
            .accessibilityValue(presentation.detail)
            .accessibilityIdentifier("ios.voice.draft.pending-result")
        } else {
            VStack(spacing: 8) {
                Label(
                    presentation.title,
                    systemImage: presentation.systemImage
                )
                .font(.headline)
                Text(presentation.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.title)
            .accessibilityValue(presentation.detail)
            .accessibilityIdentifier("ios.voice.draft.pending-result")
        }
    }

    private var draftEmptyDetail: String {
        draftEditorCanFocus
            ? "Tap here to type, paste, or add emoji."
            : "Your accepted text will appear here."
    }

    private var draftEditorCanFocus: Bool {
        draftOwner.isEditing
            || (sceneOwner.presentation.phase == .inactive
                && draftOwner.isAvailableForMutation)
    }

    private var draftEditingBinding: Binding<String> {
        Binding(
            get: { draftOwner.visibleText },
            set: { text in
                draftActionNotice = nil
                if !draftOwner.isEditing,
                   !draftOwner.beginEditing() {
                    return
                }
                draftOwner.updateEditingText(text)
                scheduleDraftEditPersistence()
            }
        )
    }

    private var draftEditorFocusBinding: Binding<Bool> {
        Binding(
            get: { draftEditorIsFocused },
            set: { draftEditorIsFocused = $0 }
        )
    }

    private func scheduleDraftEditPersistence() {
        draftEditSaveTask?.cancel()
        draftEditSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, draftOwner.isEditing else { return }
            _ = await draftOwner.persistEditing()
        }
    }

    private func finishDraftEditing() {
        draftEditSaveTask?.cancel()
        draftEditSaveTask = Task { @MainActor in
            _ = await draftOwner.finishEditing()
            draftEditSaveTask = nil
        }
    }

    private var draftClearPresentation: IOSVoiceDraftClearPresentation {
        IOSVoiceDraftClearPresentation.resolve(
            visibleText: draftOwner.visibleText,
            voicePhase: sceneOwner.presentation.phase,
            draftIsBusy: draftOwner.isBusy
        )
    }

    @ViewBuilder
    private var draftNotice: some View {
        if let draftActionNotice {
            HStack(spacing: 12) {
                Label(
                    draftActionNotice.message,
                    systemImage: draftActionNotice.systemImage
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                if draftActionNotice == .cleared, draftOwner.canUndo {
                    Button("Undo") {
                        undoClearedDraft()
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel("Undo Clear Draft")
                    .accessibilityIdentifier("ios.voice.draft.clear-undo")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("ios.voice.draft.notice")
        } else if let notice = draftTextActionOwner.notice {
            Label(notice.message, systemImage: notice.systemImage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ios.voice.draft.notice")
        } else if let notice = draftOwner.notice {
            Label(notice.message, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ios.voice.draft.notice")
        }
    }

    private var voiceSessionModeMenu: some View {
        Button {
            showsVoiceSessionModeMenu.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                Text("Auto")

                Image(systemName: "chevron.up")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .disabled(!voiceSessionModesAreEnabled)
        .accessibilityLabel("Auto")
        .accessibilityValue(voiceSessionModeAccessibilityValue)
        .accessibilityHint("Opens automatic session modes.")
        .accessibilityIdentifier("ios.voice.session-modes")
        .popover(
            isPresented: $showsVoiceSessionModeMenu,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            voiceSessionModeMenuContent
                .presentationCompactAdaptation(.popover)
        }
    }

    private var voiceSessionModeMenuContent: some View {
        VStack(spacing: 0) {
            voiceSessionModeToggle(
                title: "Clear Draft",
                accessibilityLabel: "Auto Clear",
                detail: "When a new dictation starts",
                identifier: "clear",
                systemImage: "text.badge.xmark",
                isOn: clearSessionModeBinding
            )

            Divider()

            voiceSessionModeToggle(
                title: "Translate Result",
                accessibilityLabel: "Auto Translate",
                identifier: "translate",
                systemImage: "character.bubble",
                isOn: translateSessionModeBinding
            )

            Divider()

            voiceSessionModeToggle(
                title: "Correct Result",
                accessibilityLabel: "Auto Correct",
                identifier: "correct",
                systemImage: "wand.and.stars",
                isOn: correctSessionModeBinding
            )
        }
        .padding(.vertical, 6)
        .frame(width: 280)
    }

    private func voiceSessionModeToggle(
        title: String,
        accessibilityLabel: String,
        detail: String? = nil,
        identifier: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.body)
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 52)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(detail ?? "")
        .accessibilityIdentifier("ios.voice.mode.\(identifier)")
    }

    private var draftBottomActionArea: some View {
        HStack(alignment: .center, spacing: 8) {
            voiceSessionModeMenu
            Spacer(minLength: 12)
            draftCopyAction
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityIdentifier("ios.voice.draft-bottom-actions")
    }

    private var draftCopyAction: some View {
        Button {
            copyDraft()
        } label: {
            draftLabeledActionLabel(
                "Copy",
                systemImage: "doc.on.doc"
            )
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .disabled(
            draftOwner.visibleText.isEmpty
                || draftPendingResultPresentation?.hidesConfirmedText == true
        )
        .accessibilityLabel("Copy Draft")
        .accessibilityHint("Copies the entire current Draft.")
        .accessibilityIdentifier("ios.voice.draft.copy")
    }

    private func draftLabeledActionLabel(
        _ title: String,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
    }

    private var clearSessionModeBinding: Binding<Bool> {
        Binding(
            get: { sessionModes.clearsDraftOnStart },
            set: { sessionModes.clearsDraftOnStart = $0 }
        )
    }

    private var translateSessionModeBinding: Binding<Bool> {
        Binding(
            get: { sessionModes.translates },
            set: { isSelected in
                if !isSelected {
                    sessionModes.translates = false
                } else if translationModeIsAvailable {
                    sessionModes.translates = true
                } else {
                    showsVoiceSessionModeMenu = false
                    openSettings(.attention(.translation))
                }
            }
        )
    }

    private var correctSessionModeBinding: Binding<Bool> {
        Binding(
            get: { sessionModes.corrects },
            set: { sessionModes.corrects = $0 }
        )
    }

    private var voiceSessionModeAccessibilityValue: String {
        let enabledModes = [
            sessionModes.clearsDraftOnStart ? "Auto Clear" : nil,
            sessionModes.translates ? "Auto Translate" : nil,
            sessionModes.corrects ? "Auto Correct" : nil,
        ].compactMap { $0 }
        guard !enabledModes.isEmpty else {
            return "No automatic actions enabled"
        }
        return enabledModes.joined(separator: ", ") + " enabled"
    }

    private var voiceSessionModesAreEnabled: Bool {
        sceneOwner.presentation.phase == .inactive
            && draftOwner.isAvailableForMutation
            && !draftOwner.isEditing
    }

    private var translationModeIsAvailable: Bool {
        sceneOwner.actionCommands.contains {
            $0.action == .startTranslation
        }
    }

    private var voiceStage: some View {
        GeometryReader { geometry in
            let activityCenter = IOSVoiceStagePlacement.activityCenter(
                in: geometry.size
            )

            ZStack(alignment: .topLeading) {
                primaryVoiceSurface
                    .position(activityCenter)

                if showsInlineVoiceStatus {
                    voiceStatusSurface
                        .frame(
                            width: geometry.size.width,
                            alignment: .leading
                        )
                }

                if let command = currentRevealedCancellationCommand {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            revealedCancellationCommand = nil
                        }

                    cancellationButton(command)
                        .position(
                            IOSVoiceStagePlacement.cancellationCenter(
                                in: geometry.size
                            )
                        )
                }
            }
        }
        .accessibilityIdentifier("ios.voice.stage")
    }

    private var voiceStatusSurface: some View {
        let status = effectiveVoiceStatus
        let recoveryCommands = sceneOwner.actionCommands.filter {
            IOSVoiceHomeActionPlacement.isVisibleStatusAction($0.action)
        }

        return VStack(alignment: .leading, spacing: 10) {
            IOSVoiceStatusRow(
                status: status,
                listeningStartedAt: listeningStartedAt
            )
            .accessibilityIdentifier("ios.voice.status")

            if let destination = status.setupDestination,
               let setupAction = setupAction(for: destination) {
                Button(setupAction.title) {
                    setupAction.perform()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ios.voice.setup-action")
            }
            if !recoveryCommands.isEmpty {
                IOSVoiceActionLayout(
                    commands: recoveryCommands,
                    perform: performVoiceCommand
                )
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var primaryVoiceSurface: some View {
        let status = effectiveVoiceStatus
        let command = primaryVoiceCommand

        if draftTextActionOwner.isProcessing {
            voiceActivityIndicator(.recognizing, status: status)
        } else {
            switch sceneOwner.presentation.phase {
            case .inactive:
                if let command, primaryVoiceGate == .available {
                    voiceActivityButton(command)
                } else {
                    primaryVoiceRecoverySurface(
                        status: primaryBlockedStatus(fallback: status)
                    )
                }
            case .arming:
                voiceArmingIndicator(status: status)
            case .listening:
                if let command {
                    voiceActivityButton(command)
                } else {
                    voiceActivityIndicator(.listening, status: status)
                }
            case .finalizing, .processing:
                voiceActivityIndicator(.recognizing, status: status)
            case .ready:
                if let command, primaryVoiceGate == .available {
                    voiceActivityButton(command)
                } else {
                    primaryVoiceRecoverySurface(
                        status: primaryBlockedStatus(fallback: status)
                    )
                }
            }
        }
    }

    private var effectiveVoiceStatus: IOSVoiceStatusPresentation {
        if let action = draftTextActionOwner.activeAction {
            return IOSVoiceDraftTextActionPresentation
                .resolve(action)
                .processingStatus
        }
        return IOSVoiceHomePresentation.resolve(sceneOwner.presentation)
    }

    private func voiceActivityButton(
        _ command: IOSForegroundVoiceActionCommand
    ) -> some View {
        let presentation = IOSVoiceActionPresentation.resolve(command.action)

        return Group {
            if let cancellationCommand = hiddenCancellationCommand {
                IOSVoiceRecordButton(
                    accessibilityLabel: presentation.title,
                    isEnabled: true,
                    workPhase: sceneOwner.presentation.phase,
                    longPressAction: {
                        revealCancellation(cancellationCommand)
                    },
                    action: { performPrimaryVoiceCommand(command) }
                )
                .accessibilityHint(
                    "Tap to finish. Touch and hold to show cancellation."
                )
                .accessibilityAction(named: "Cancel Dictation") {
                    performCancellation(cancellationCommand)
                }
            } else {
                IOSVoiceRecordButton(
                    accessibilityLabel: presentation.title,
                    isEnabled: true,
                    workPhase: sceneOwner.presentation.phase,
                    action: { performPrimaryVoiceCommand(command) }
                )
            }
        }
        .accessibilityIdentifier("ios.voice.primary-action")
    }

    private func voiceArmingIndicator(
        status: IOSVoiceStatusPresentation
    ) -> some View {
        let progress = ProgressView()
            .controlSize(.large)
            .tint(.accentColor)
            .frame(width: 96, height: 96)
            .background(
                Color.accentColor.opacity(0.08),
                in: Circle()
            )
            .frame(width: 208, height: 208)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.title)
            .accessibilityValue(status.detail)
            .accessibilityIdentifier("ios.voice.primary-progress")

        return cancelableActivity(progress)
    }

    private func voiceActivityIndicator(
        _ phase: IOSVoiceActivityPhase,
        status: IOSVoiceStatusPresentation
    ) -> some View {
        let indicator = IOSVoiceActivityIndicator(phase: phase)
            .id(phase)
            .frame(width: 208, height: 208)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.title)
            .accessibilityValue(status.detail)
            .accessibilityIdentifier("ios.voice.primary-activity")

        return cancelableActivity(indicator)
    }

    private var showsInlineVoiceStatus: Bool {
        if draftTextActionOwner.isProcessing { return true }
        return switch sceneOwner.presentation.phase {
        case .inactive:
            primaryVoiceCommand != nil && primaryVoiceGate == .available
        case .ready:
            false
        case .arming, .listening, .finalizing, .processing:
            true
        }
    }

    private var primaryVoiceCommand: IOSForegroundVoiceActionCommand? {
        sceneOwner.actionCommands.first {
            isPrimaryVoiceAction($0.action)
        }
    }

    private var hiddenCancellationCommand:
        IOSForegroundVoiceActionCommand? {
        sceneOwner.actionCommands.first {
            IOSVoiceHomeActionPlacement.isCancellation($0.action)
        }
    }

    private var currentRevealedCancellationCommand:
        IOSForegroundVoiceActionCommand? {
        guard let revealedCancellationCommand,
              sceneOwner.actionCommands.contains(revealedCancellationCommand),
              IOSVoiceHomeActionPlacement.isCancellation(
                revealedCancellationCommand.action
              ) else {
            return nil
        }
        return revealedCancellationCommand
    }

    @ViewBuilder
    private func cancelableActivity<Content: View>(
        _ content: Content
    ) -> some View {
        if let command = hiddenCancellationCommand {
            content
                .onLongPressGesture(minimumDuration: 0.6) {
                    revealCancellation(command)
                }
                .accessibilityHint(
                    "Touch and hold to show cancellation."
                )
                .accessibilityAction(named: "Cancel Dictation") {
                    performCancellation(command)
                }
        } else {
            content
        }
    }

    private func cancellationButton(
        _ command: IOSForegroundVoiceActionCommand
    ) -> some View {
        Button(role: .destructive) {
            performCancellation(command)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.red, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.72), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel Dictation")
        .accessibilityHint("Stops and discards the current attempt.")
        .accessibilityIdentifier("ios.voice.cancel-action")
    }

    private func revealCancellation(
        _ command: IOSForegroundVoiceActionCommand
    ) {
        guard sceneOwner.actionCommands.contains(command),
              IOSVoiceHomeActionPlacement.isCancellation(command.action) else {
            revealedCancellationCommand = nil
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        revealedCancellationCommand = command
    }

    private func performCancellation(
        _ command: IOSForegroundVoiceActionCommand
    ) {
        guard sceneOwner.actionCommands.contains(command),
              IOSVoiceHomeActionPlacement.isCancellation(command.action) else {
            revealedCancellationCommand = nil
            return
        }
        revealedCancellationCommand = nil
        _ = sceneOwner.submit(command)
    }

    private var primaryVoiceGate: IOSVoicePrimaryGate {
        if draftOwner.isEditing { return .draftEditing }

        if draftOwner.operation == .refreshing {
            return draftOwner.isLoaded ? .draftUpdating : .draftLoading
        }
        if draftOwner.operation != .idle { return .draftUpdating }

        switch draftOwner.state {
        case .notLoaded:
            return .draftLoading
        case .loadFailed:
            return .draftUnavailable
        case .ready:
            break
        }

        if draftOwner.isFull && !sessionModes.clearsDraftOnStart {
            return .draftFull
        }
        if primaryVoiceCommand == nil { return .voiceChecking }
        return .available
    }

    private func primaryBlockedStatus(
        fallback: IOSVoiceStatusPresentation
    ) -> IOSVoiceStatusPresentation {
        if sceneOwner.presentation.setup != .ready
            || sceneOwner.presentation.recovery != .none
            || sceneOwner.presentation.failure != nil {
            return fallback
        }
        return IOSVoiceHomePresentation.primaryGateStatus(primaryVoiceGate)
            ?? fallback
    }

    private func primaryVoiceRecoverySurface(
        status: IOSVoiceStatusPresentation
    ) -> some View {
        let recoveryCommands = sceneOwner.actionCommands.filter {
            IOSVoiceHomeActionPlacement.isVisibleStatusAction($0.action)
        }

        return VStack(spacing: 14) {
            if status.showsProgress {
                ProgressView()
                    .controlSize(.large)
                    .tint(status.color)
                    .frame(width: 58, height: 58)
            } else {
                Image(systemName: status.systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(status.color)
                    .frame(width: 58, height: 58)
                    .background(status.color.opacity(0.10), in: Circle())
            }

            VStack(spacing: 5) {
                Text(status.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(status.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let destination = status.setupDestination,
               let setupAction = setupAction(for: destination) {
                Button(setupAction.title) {
                    setupAction.perform()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("ios.voice.setup-action")
            }
            if !recoveryCommands.isEmpty {
                IOSVoiceActionLayout(
                    commands: recoveryCommands,
                    perform: performVoiceCommand
                )
            } else if status.setupDestination == nil,
                      primaryVoiceGate == .draftUnavailable {
                Button("Try Loading Draft Again") {
                    Task { await draftOwner.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("ios.voice.draft-retry")
            } else if status.setupDestination == nil,
                      primaryVoiceGate == .draftFull {
                ViewThatFits(in: .horizontal) {
                    HStack { draftRecoveryButtons }
                    VStack { draftRecoveryButtons }
                }
            }
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(
            status.color.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(status.color.opacity(0.16), lineWidth: 1)
        }
        .accessibilityIdentifier("ios.voice.primary-recovery")
    }

    @ViewBuilder
    private var draftRecoveryButtons: some View {
        Button {
            copyDraft()
        } label: {
            Label("Copy Draft", systemImage: "doc.on.doc")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        Button(role: .destructive) {
            clearDraft()
        } label: {
            Label("Clear Draft", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func isPrimaryVoiceAction(
        _ action: IOSForegroundVoiceAction
    ) -> Bool {
        action == .startStandard || action == .finishUtterance
    }

    private var draftBlocksNewDictation: Bool {
        !draftOwner.isAvailableForMutation
            || (draftOwner.isFull && !sessionModes.clearsDraftOnStart)
    }

    private func copyDraft() {
        guard !draftOwner.visibleText.isEmpty else { return }
        IOSVoiceClipboard.copy(draftOwner.visibleText)
        IOSAccessibilityAnnouncement.post(
            IOSVoiceDraftCopyPresentation.accessibilityAnnouncement
        )
    }

    private func clearDraft() {
        draftActionNotice = nil
        draftEditSaveTask?.cancel()
        draftEditSaveTask = nil
        Task { @MainActor in
            if draftOwner.isEditing {
                guard await draftOwner.finishEditing() else { return }
                draftEditorIsFocused = false
            }
            guard draftClearPresentation.isEnabled,
                  await draftOwner.clear() else {
                return
            }
            let notice = IOSVoiceDraftActionNotice.cleared
            draftActionNotice = notice
            IOSAccessibilityAnnouncement.post(
                notice.accessibilityAnnouncement
            )
        }
    }

    private func undoClearedDraft() {
        draftActionNotice = nil
        Task { @MainActor in
            _ = await draftOwner.undo()
        }
    }

    private var voiceHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voice")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(
                "Record one dictation in HoldType, then copy, share, or "
                    + "practice with the result."
            )
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .listRowInsets(
            EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)
        )
        .listRowBackground(Color.clear)
    }

    private var showsGettingStarted: Bool {
        sceneOwner.presentation.setup != .ready
    }

    private var dictationHasPriority: Bool {
        draftTextActionOwner.isProcessing
            || sceneOwner.presentation.phase != .inactive
            || sceneOwner.presentation.recovery != .none
    }

    private var pendingVoiceCommandIsCurrent: Bool {
        guard let pendingVoiceCommand else { return false }
        return sceneOwner.actionCommands.contains(pendingVoiceCommand)
    }

    private var pendingLatestClearCommandIsCurrent: Bool {
        guard let pendingLatestClearCommand else { return false }
        return latestResultOwner.clearCommand == pendingLatestClearCommand
    }

    private var gettingStartedSection: some View {
        Section("Getting Started") {
            IOSVoiceSetupRow(
                number: 1,
                systemImage: "keyboard",
                title: "Add and switch keyboards",
                detail: "In Settings › General › Keyboard › Keyboards, add HoldType and enable Allow Full Access for keyboard voice. Local editing and Latest still work without Full Access. Use Globe in the practice field below."
            ) {
                practiceFieldIsFocused = true
            }
            .accessibilityIdentifier("ios.voice.setup.keyboard")

            IOSVoiceSetupRow(
                number: 2,
                systemImage: "key.fill",
                title: openAISetupTitle,
                detail: openAISetupDetail
            ) {
                openSettings(.openAI)
            }
            .accessibilityIdentifier("ios.voice.setup.openai")

            IOSVoiceSetupRow(
                number: 3,
                systemImage: "mic.fill",
                title: "Microphone access",
                detail: "We’ll ask only when you start."
            ) {
                openSettings(.privacyAndPermissions)
            }
            .accessibilityIdentifier("ios.voice.setup.microphone")

            Label {
                Text(
                    "Save History is on by default, while Recording Cache is "
                        + "off. HoldType keeps up to 20 successful texts; "
                        + "completed recordings are retained only after you "
                        + "enable the cache, starting with the 20 newest. "
                        + "Failed attempts are not added."
                )
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "clock")
                    .foregroundStyle(.tint)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ios.voice.setup.history")
        }
    }

    private var dictationSection: some View {
        let status = IOSVoiceHomePresentation.resolve(
            sceneOwner.presentation
        )
        let commands = sceneOwner.actionCommands

        return Section("Dictation") {
            IOSVoiceStatusRow(
                status: status,
                listeningStartedAt: listeningStartedAt
            )
            .accessibilityIdentifier("ios.voice.status")

            if !commands.isEmpty {
                IOSVoiceActionLayout(
                    commands: commands,
                    perform: performVoiceCommand
                )
            } else if let destination = status.setupDestination,
                      let setupAction = setupAction(for: destination) {
                Button(setupAction.title) {
                    setupAction.perform()
                }
                .accessibilityIdentifier("ios.voice.setup-action")
            }
        }
    }

    private var latestSectionIsVisible: Bool {
        IOSVoiceLatestStatusPresentation.sectionIsVisible(
            for: latestResultOwner.presentation
        )
    }

    private var latestResultSection: some View {
        let presentation = latestResultOwner.presentation
        let status = IOSVoiceLatestStatusPresentation.resolve(presentation)

        return Section("Latest Result") {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.title)
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
            .accessibilityElement(children: .combine)

            if let text = presentation.text {
                Text(text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ios.voice.latest.text")
            }

            if let command = latestResultOwner.contentCommand {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        latestContentButtons(command)
                    }
                    VStack(alignment: .leading) {
                        latestContentButtons(command)
                    }
                }
            }

            if let latestActionNotice {
                Label(latestActionNotice, systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ios.voice.latest.action-notice")
            }

            if let clearCommand = latestResultOwner.clearCommand {
                Button("Clear Latest Result", role: .destructive) {
                    pendingLatestClearCommand = clearCommand
                }
                .accessibilityIdentifier("ios.voice.latest.clear")
            }
        }
    }

    @ViewBuilder
    private func latestContentButtons(
        _ command: IOSForegroundVoiceLatestResultContentCommand
    ) -> some View {
        Button {
            guard let text = latestResultOwner.content(for: command) else {
                return
            }
            IOSVoiceClipboard.copy(text)
            latestActionNotice = "Copied"
            IOSAccessibilityAnnouncement.post("Latest Result copied")
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
        .accessibilityIdentifier("ios.voice.latest.copy")

        Button {
            guard let text = latestResultOwner.content(for: command) else {
                return
            }
            shareItem = IOSVoiceShareItem(text: text)
            latestActionNotice = nil
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
        .accessibilityIdentifier("ios.voice.latest.share")

        Button {
            guard let text = latestResultOwner.content(for: command) else {
                return
            }
            practiceText = text
            practiceFieldIsFocused = true
            latestActionNotice = "Moved to Practice"
            IOSAccessibilityAnnouncement.post(
                "Latest Result moved to Practice"
            )
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "keyboard")
                Text("Use in Practice")
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
        .accessibilityIdentifier("ios.voice.latest.use-in-practice")
    }

    private var keyboardPracticeSection: some View {
        Section("Keyboard Practice") {
            Text(
                "Normal typing and Apple Dictation stay on your system keyboard. HoldType Keyboard inserts the newest saved History entry; it remains available until History changes."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            TextField(
                "Tap here to try HoldType Keyboard",
                text: $practiceText,
                axis: .vertical
            )
            .lineLimit(4...8)
            .textInputAutocapitalization(.sentences)
            .focused($practiceFieldIsFocused)
            .accessibilityIdentifier("ios.voice.practice-field")

            LabeledContent("Characters", value: "\(practiceText.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !practiceText.isEmpty {
                Button("Clear Practice Field", role: .destructive) {
                    practiceText = ""
                }
                .accessibilityIdentifier("ios.voice.practice-clear")
            }

        }
    }

    private var keyboardDictationSessionSection: some View {
        Section("Keyboard Dictation Session") {
            Text(keyboardSession.presentation.title)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(
                    "ios.voice.keyboard-session.status"
                )

            Text(
                "This brief app-owned session lets HoldType Keyboard control one recording for up to 60 seconds. Start it immediately before returning to the field where you want to dictate. The existing Voice pipeline owns recording, processing, Latest, and History."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            switch keyboardSession.presentation {
            case .stopped, .failed:
                Button("Start Keyboard Session") {
                    Task {
                        await keyboardSession.startSession()
                    }
                }
                .accessibilityIdentifier(
                    "ios.voice.keyboard-session.start"
                )
            case .preparing:
                ProgressView()
                    .accessibilityLabel("Preparing keyboard session")
            case .ready, .listening, .processing, .resultReady:
                Button("Stop Keyboard Session", role: .destructive) {
                    keyboardSession.stopSession()
                }
                .accessibilityIdentifier(
                    "ios.voice.keyboard-session.stop"
                )
            }
        }
    }

    private func scheduleAccessibilityAnnouncement(
        _ message: String,
        priority: IOSAccessibilityAnnouncementCandidate.Priority
    ) {
        let incoming = IOSAccessibilityAnnouncementCandidate(
            message: message,
            priority: priority
        )
        let preferred = IOSAccessibilityAnnouncementCandidate.preferred(
            current: accessibilityAnnouncementCandidate,
            incoming: incoming
        )
        guard preferred != accessibilityAnnouncementCandidate else { return }

        accessibilityAnnouncementCandidate = preferred
        accessibilityAnnouncementTask?.cancel()
        accessibilityAnnouncementTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled,
                  accessibilityAnnouncementCandidate == preferred else {
                return
            }
            accessibilityAnnouncementCandidate = nil
            accessibilityAnnouncementTask = nil
            IOSAccessibilityAnnouncement.post(preferred.message)
        }
    }

    private var openAISetupTitle: String {
        switch secureProviderAvailability {
        case .available:
            "OpenAI setup"
        case .unavailable:
            "OpenAI setup unavailable"
        }
    }

    private var openAISetupDetail: String {
        switch secureProviderAvailability {
        case .available:
            "Connect your OpenAI API key."
        case .unavailable:
            "Secure provider settings are unavailable in this build."
        }
    }

    private func performVoiceCommand(
        _ command: IOSForegroundVoiceActionCommand
    ) {
        let presentation = IOSVoiceActionPresentation.resolve(command.action)
        if presentation.requiresConfirmation {
            pendingVoiceCommand = command
        } else {
            _ = sceneOwner.submit(command)
        }
    }

    private func performPrimaryVoiceCommand(
        _ command: IOSForegroundVoiceActionCommand
    ) {
        guard command.action == .startStandard else {
            performVoiceCommand(command)
            return
        }
        _ = sceneOwner.submitStart(command, modes: sessionModes)
    }

    private func setupAction(
        for destination: RecoveryDestination
    ) -> (title: String, perform: () -> Void)? {
        switch destination {
        case .openAI:
            (
                "Open OpenAI Settings",
                { openVoiceRecoverySettings(destination) }
            )
        case .transcription:
            (
                "Review Transcription Settings",
                { openVoiceRecoverySettings(destination) }
            )
        case .translation:
            (
                "Review Translation Settings",
                { openVoiceRecoverySettings(destination) }
            )
        case .microphoneAndPrivacy:
            (
                "Review Privacy & Permissions",
                { openVoiceRecoverySettings(destination) }
            )
        case .keyboard:
            (
                "Open Keyboard Setup",
                { openVoiceRecoverySettings(destination) }
            )
        case .fullAccess:
            (
                "Enable Full Access",
                { openVoiceRecoverySettings(destination) }
            )
        }
    }

    private func routeToSetupIfNeeded(
        _ setup: IOSForegroundVoiceSetup
    ) {
        guard case .needsSetup(let destination) = setup else {
            automaticallyOpenedSetup = nil
            return
        }
        guard automaticallyOpenedSetup != destination else { return }
        automaticallyOpenedSetup = destination
        openVoiceRecoverySettings(destination)
    }

    private func openVoiceRecoverySettings(
        _ destination: RecoveryDestination
    ) {
        openSettings(
            .attention(
                voiceSettingsRecovery(for: destination)
            )
        )
    }

    private func voiceSettingsRecovery(
        for destination: RecoveryDestination
    ) -> IOSSettingsAttention {
        switch destination {
        case .openAI:
            .openAI
        case .transcription:
            .transcription
        case .translation:
            .translation
        case .keyboard:
            .keyboard
        case .fullAccess:
            .fullAccess
        case .microphoneAndPrivacy:
            sceneOwner.presentation.failure == .microphonePermissionDenied
                ? .microphonePermission
                : .privacyReview
        }
    }

    private var visibleVoiceConsentPrompt:
        IOSProviderConsentVoicePromptPresentation? {
        guard let prompt = consentOwner.voicePrompt,
              consentOwner.isVoicePrompt(prompt.id, ownedBy: sceneOwner) else {
            return nil
        }
        return prompt
    }

    private var voiceConsentSheetBinding: Binding<Bool> {
        Binding(
            get: { visibleVoiceConsentPrompt != nil },
            set: { isPresented in
                guard !isPresented else { return }
                dismissVisibleVoiceConsent()
            }
        )
    }

    private func dismissVisibleVoiceConsent() {
        guard let prompt = visibleVoiceConsentPrompt else { return }
        consentOwner.dismissVoicePrompt(prompt.id, from: sceneOwner)
    }
}

struct IOSVoiceStagePlacement {
    static let minimumHeight: CGFloat = 300
    static let minimumDraftHeight: CGFloat = 250
    static let maximumDraftHeight: CGFloat = 340
    static let contentSpacing: CGFloat = 14
    static let minimumContentHeight =
        minimumDraftHeight + contentSpacing + minimumHeight

    static func activityCenter(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    static func cancellationCenter(in size: CGSize) -> CGPoint {
        let center = activityCenter(in: size)
        return CGPoint(x: center.x + 78, y: center.y + 78)
    }
}

struct IOSVoiceRuntimeUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Voice Unavailable", systemImage: "mic.slash")
        } description: {
            Text(
                "Foreground Voice could not be composed safely. Settings, "
                    + "Dictation Rules, and ordinary keyboard typing remain available."
            )
        }
        .navigationTitle("Voice")
        .accessibilityIdentifier("ios.voice.runtime-unavailable")
    }
}

private struct IOSVoiceSetupRow: View {
    let number: Int
    let systemImage: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(number). \(title)")
                            .foregroundStyle(.primary)
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct IOSVoiceStatusRow: View {
    let status: IOSVoiceStatusPresentation
    let listeningStartedAt: Date?

    var body: some View {
        if let listeningStartedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let totalSeconds = elapsedSeconds(
                    from: listeningStartedAt,
                    at: context.date
                )
                statusContent(elapsedText: elapsedText(totalSeconds))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(status.title)
                    .accessibilityValue(
                        IOSAccessibilityAnnouncement.message(
                            title: status.detail,
                            detail: "Elapsed time "
                                + IOSAccessibilityAnnouncement
                                .spokenElapsedTime(
                                    totalSeconds: totalSeconds
                                )
                        )
                    )
            }
        } else {
            statusContent(elapsedText: nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(status.title)
                .accessibilityValue(status.detail)
        }
    }

    private func statusContent(elapsedText: String?) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(status.title)
                    Spacer(minLength: 8)
                    if let elapsedText {
                        Text(elapsedText)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
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
}

private struct IOSVoiceActionLayout: View {
    let commands: [IOSForegroundVoiceActionCommand]
    let perform: (IOSForegroundVoiceActionCommand) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                actionButtons
            }
            VStack {
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        ForEach(Array(commands.enumerated()), id: \.offset) { _, command in
            actionButton(command)
        }
    }

    @ViewBuilder
    private func actionButton(
        _ command: IOSForegroundVoiceActionCommand
    ) -> some View {
        let presentation = IOSVoiceActionPresentation.resolve(command.action)
        switch presentation.prominence {
        case .primary:
            Button {
                perform(command)
            } label: {
                Label(presentation.title, systemImage: presentation.systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier(presentation.accessibilityIdentifier)
        case .secondary:
            Button {
                perform(command)
            } label: {
                Label(presentation.title, systemImage: presentation.systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier(presentation.accessibilityIdentifier)
        case .destructive:
            Button(role: .destructive) {
                perform(command)
            } label: {
                Label(presentation.title, systemImage: presentation.systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier(presentation.accessibilityIdentifier)
        }
    }
}

struct IOSVoiceLatestStatusPresentation {
    let title: String
    let detail: String
    let systemImage: String
    let tone: IOSVoiceStatusTone
    let showsProgress: Bool

    var color: Color {
        tone.color
    }

    static func sectionIsVisible(
        for presentation: IOSForegroundVoiceLatestResultPresentation
    ) -> Bool {
        switch presentation.status {
        case .notLoaded:
            false
        case .absent:
            presentation.notice != nil
                || presentation.keyboardProjectionUpdateFailed
        case .ready, .clearing, .unavailable:
            true
        }
    }

    static func resolve(
        _ presentation: IOSForegroundVoiceLatestResultPresentation
    ) -> Self {
        let base: Self = switch presentation.status {
        case .notLoaded:
            Self(
                title: "Checking Latest Result…",
                detail: "Reading the protected app-private result.",
                systemImage: "clock",
                tone: .neutral,
                showsProgress: true
            )
        case .absent:
            Self(
                title: "No Latest Result",
                detail: "A completed dictation result will appear here.",
                systemImage: "text.page",
                tone: .neutral,
                showsProgress: false
            )
        case .ready:
            Self(
                title: "Latest Result",
                detail: "Stored privately in the containing app.",
                systemImage: "checkmark.circle.fill",
                tone: .success,
                showsProgress: false
            )
        case .clearing:
            Self(
                title: "Clearing Latest Result…",
                detail: "The exact selected result is being cleared.",
                systemImage: "trash",
                tone: .neutral,
                showsProgress: true
            )
        case .unavailable:
            Self(
                title: "Latest Result Unavailable",
                detail: "HoldType could not verify the protected result safely.",
                systemImage: "exclamationmark.triangle",
                tone: .failure,
                showsProgress: false
            )
        }

        if let notice = presentation.notice {
            let noticeDetail: String = switch notice {
            case .loadFailed:
                "The protected Latest Result could not be verified."
            case .clearFailed:
                "Clear did not finish; the exact result remains available."
            case .clearStateUnknown:
                "Clear could not be reconciled, so text remains hidden."
            case .resultChanged:
                "A newer result replaced the one selected for Clear."
            }
            return Self(
                title: base.title,
                detail: noticeDetail,
                systemImage: base.systemImage,
                tone: notice == .resultChanged ? .warning : .failure,
                showsProgress: base.showsProgress
            )
        }

        guard presentation.keyboardProjectionUpdateFailed,
              presentation.status == .ready
                || presentation.status == .absent else {
            return base
        }
        return Self(
            title: base.title,
            detail: "The keyboard History copy couldn't be refreshed; Latest may remain unavailable or show an older History item until refresh succeeds.",
            systemImage: base.systemImage,
            tone: .failure,
            showsProgress: base.showsProgress
        )
    }
}

private struct IOSVoiceShareItem: Identifiable {
    let id = UUID()
    let text: String
}

private struct IOSVoiceActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

private enum IOSVoiceClipboard {
    @MainActor
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}

private extension IOSVoiceStatusPresentation {
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
