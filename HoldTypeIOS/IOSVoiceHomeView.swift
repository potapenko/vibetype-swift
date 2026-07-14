import Foundation
import HoldTypeDomain
import SwiftUI
import UIKit

struct IOSVoiceHomeView: View {
    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(IOSForegroundVoiceSceneHostOwner.self)
    private var sceneOwner
    @Environment(IOSForegroundVoiceLatestResultOwner.self)
    private var latestResultOwner
    @Environment(IOSVoiceDraftOwner.self)
    private var draftOwner
    @Environment(IOSProviderConsentPresentationOwner.self)
    private var consentOwner
    @Environment(IOSKeyboardDictationSessionCoordinator.self)
    private var keyboardSession

    @Binding var practiceText: String
    @State private var listeningStartedAt: Date?
    @State private var pendingVoiceCommand:
        IOSForegroundVoiceActionCommand?
    @State private var pendingLatestClearCommand:
        IOSForegroundVoiceLatestResultClearCommand?
    @State private var shareItem: IOSVoiceShareItem?
    @State private var latestActionNotice: String?
    @State private var draftActionNotice: String?
    @State private var showsKeyboardTools = false
    @State private var accessibilityAnnouncementTask: Task<Void, Never>?
    @State private var accessibilityAnnouncementCandidate:
        IOSAccessibilityAnnouncementCandidate?
    @State private var draftEditSaveTask: Task<Void, Never>?
    @State private var automaticallyOpenedSetup: RecoveryDestination?
    @FocusState private var practiceFieldIsFocused: Bool
    @FocusState private var draftEditorIsFocused: Bool

    let secureProviderAvailability: IOSSecureProviderAvailability
    let openSettings: (IOSSettingsRoute) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 14) {
                    draftSurface
                        .frame(minHeight: 250, maxHeight: 340)
                    if showsInlineVoiceStatus {
                        voiceStatusSurface
                    }
                    Spacer(minLength: 0)
                    primaryVoiceSurface
                    Spacer(minLength: 0)
                }
                .frame(
                    minHeight: max(0, geometry.size.height - 22),
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
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            draftEditorIsFocused = false
            if draftOwner.isEditing {
                finishDraftEditing()
            }
        }
        .onChange(of: sceneOwner.presentation) { old, new in
            let oldStatus = IOSVoiceHomePresentation.resolve(old)
            let newStatus = IOSVoiceHomePresentation.resolve(new)
            guard let message = IOSAccessibilityAnnouncement.transitionMessage(
                oldTitle: oldStatus.title,
                oldDetail: oldStatus.detail,
                newTitle: newStatus.title,
                newDetail: newStatus.detail
            ) else {
                return
            }
            scheduleAccessibilityAnnouncement(
                message,
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
            guard let pendingVoiceCommand,
                  !commands.contains(pendingVoiceCommand) else {
                return
            }
            self.pendingVoiceCommand = nil
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
        .onDisappear {
            draftEditSaveTask?.cancel()
            draftEditSaveTask = nil
            if draftOwner.isEditing {
                Task { await draftOwner.finishEditing() }
            }
            accessibilityAnnouncementTask?.cancel()
            accessibilityAnnouncementTask = nil
            accessibilityAnnouncementCandidate = nil
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

    private func oneShotVoiceIconButton(
        _ action: IOSForegroundVoiceAction
    ) -> some View {
        let presentation = IOSVoiceActionPresentation.resolve(action)
        let command = sceneOwner.actionCommands.first {
            $0.action == action
        }
        let isEnabled = command != nil && !draftBlocksNewDictation

        return Button {
            guard let command, isEnabled else { return }
            performVoiceCommand(command)
        } label: {
            Image(systemName: presentation.systemImage)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(presentation.title)
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }

    private var draftSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 4) {
                oneShotVoiceIconButton(.startTranslation)
                oneShotVoiceIconButton(.startCorrection)
                Spacer(minLength: 12)
                draftActionButtons
            }
            .accessibilityIdentifier("ios.voice.draft-actions")

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

            if let message = draftActionNotice ?? draftOwner.notice?.message {
                Label(message, systemImage: noticeSystemImage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ios.voice.draft.notice")
            }
        }
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .accessibilityIdentifier("ios.voice.draft")
    }

    @ViewBuilder
    private var draftTextSurface: some View {
        if draftEditorCanFocus {
            ZStack(alignment: .topLeading) {
                TextEditor(text: draftEditingBinding)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($draftEditorIsFocused)
                    .accessibilityLabel("Current Draft")
                    .accessibilityIdentifier("ios.voice.draft.editor")

                if draftOwner.visibleText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "Ready for your first dictation",
                            systemImage: "text.page"
                        )
                        .font(.headline)
                        Text("Tap here to type, paste, or add emoji.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        } else {
            ScrollView {
                if draftOwner.visibleText.isEmpty {
                    ContentUnavailableView(
                        "Ready for your first dictation",
                        systemImage: "text.page",
                        description: Text(
                            "Your accepted text will appear here."
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                } else {
                    Text(draftOwner.visibleText)
                        .font(.body)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .topLeading
                        )
                        .textSelection(.enabled)
                        .accessibilityLabel("Current Draft")
                        .accessibilityValue(draftOwner.visibleText)
                }
            }
            .scrollIndicators(.visible)
        }
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
                draftOwner.updateEditingText(text)
                scheduleDraftEditPersistence()
            }
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

    @ViewBuilder
    private var draftActionButtons: some View {
        HStack(spacing: 4) {
            Button {
                draftActionNotice = nil
                Task { await draftOwner.undo() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 36, height: 36)
            }
            .disabled(!draftOwner.canUndo)
            .accessibilityLabel("Undo Draft Change")

            Button {
                draftActionNotice = nil
                Task { await draftOwner.redo() }
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 36, height: 36)
            }
            .disabled(!draftOwner.canRedo)
            .accessibilityLabel("Redo Draft Change")

            Button {
                copyDraft()
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 36, height: 36)
            }
            .disabled(draftOwner.visibleText.isEmpty)
            .accessibilityLabel("Copy Draft")

            Button(role: .destructive) {
                clearDraft()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.red)
            }
            .disabled(draftOwner.visibleText.isEmpty || draftOwner.isBusy)
            .accessibilityLabel("Clear Draft")
        }
        .buttonStyle(.plain)
    }

    private var noticeSystemImage: String {
        draftActionNotice == "Copied"
            ? "checkmark.circle"
            : "exclamationmark.triangle"
    }

    private var voiceStatusSurface: some View {
        let status = IOSVoiceHomePresentation.resolve(
            sceneOwner.presentation
        )
        let recoveryCommands = sceneOwner.actionCommands.filter {
            !isPrimaryVoiceAction($0.action)
                && $0.action != .startTranslation
                && $0.action != .startCorrection
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
        let status = IOSVoiceHomePresentation.resolve(
            sceneOwner.presentation
        )
        let command = primaryVoiceCommand

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
            ProgressView()
                .controlSize(.large)
                .tint(.accentColor)
                .frame(width: 96, height: 96)
                .background(
                    Color.accentColor.opacity(0.08),
                    in: Circle()
                )
                .accessibilityLabel(status.title)
                .accessibilityValue(status.detail)
                .accessibilityIdentifier("ios.voice.primary-progress")
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

    private func voiceActivityButton(
        _ command: IOSForegroundVoiceActionCommand
    ) -> some View {
        let presentation = IOSVoiceActionPresentation.resolve(command.action)

        return IOSVoiceRecordButton(
            accessibilityLabel: presentation.title,
            isEnabled: true,
            workPhase: sceneOwner.presentation.phase,
            action: { performVoiceCommand(command) }
        )
        .accessibilityIdentifier("ios.voice.primary-action")
    }

    private func voiceActivityIndicator(
        _ phase: IOSVoiceActivityPhase,
        status: IOSVoiceStatusPresentation
    ) -> some View {
        IOSVoiceActivityIndicator(phase: phase)
            .id(phase)
            .frame(width: 208, height: 208)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.title)
            .accessibilityValue(status.detail)
            .accessibilityIdentifier("ios.voice.primary-activity")
    }

    private var showsInlineVoiceStatus: Bool {
        switch sceneOwner.presentation.phase {
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

        if draftOwner.isFull { return .draftFull }
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
            !isPrimaryVoiceAction($0.action)
                && $0.action != .startTranslation
                && $0.action != .startCorrection
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
        !draftOwner.isAvailableForMutation || draftOwner.isFull
    }

    private func copyDraft() {
        guard !draftOwner.visibleText.isEmpty else { return }
        IOSVoiceClipboard.copy(draftOwner.visibleText)
        draftActionNotice = "Copied"
        IOSAccessibilityAnnouncement.post("Current Draft copied")
    }

    private func clearDraft() {
        draftActionNotice = nil
        if draftOwner.isEditing {
            draftOwner.updateEditingText("")
            scheduleDraftEditPersistence()
        } else {
            Task { await draftOwner.clear() }
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
        sceneOwner.presentation.phase != .inactive
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
                    "Save History is on by default and keeps up to 20 "
                        + "successful texts locally. It never stores audio or "
                        + "failed attempts."
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
                "Normal typing and Apple Dictation stay on your system keyboard. The app shares one Latest Result with HoldType Keyboard for explicit insertion; insertion eligibility expires after 10 minutes."
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
            .voiceRecovery(
                voiceSettingsRecovery(for: destination)
            )
        )
    }

    private func voiceSettingsRecovery(
        for destination: RecoveryDestination
    ) -> IOSVoiceSettingsRecovery {
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

struct IOSVoiceRuntimeUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Voice Unavailable", systemImage: "mic.slash")
        } description: {
            Text(
                "Foreground Voice could not be composed safely. Settings, "
                    + "Library, and ordinary keyboard typing remain available."
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
            detail: "The keyboard copy couldn't be refreshed; an older item may remain until it expires.",
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
