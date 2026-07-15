import SwiftUI
import UIKit

enum IOSKeyboardHandoffSceneDecision: Equatable, Sendable {
    case waitForActiveScene
    case start

    static func resolve(_ activity: IOSVoiceSceneActivity) -> Self {
        activity == .active ? .start : .waitForActiveScene
    }
}

struct IOSContainingAppShell: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedDestinationRawValue =
        IOSContainingAppDestination.voice.rawValue

    @State private var settingsNavigationPath = NavigationPath()
    @State private var libraryNavigationPath = NavigationPath()
    @State private var preferredCompactColumn:
        NavigationSplitViewColumn = .detail
    @State private var openAIEditorDraft =
        IOSOpenAICredentialEditorDraft()
    @State private var sceneDraft = IOSContainingAppSceneDraft()
    @State private var hasUnsavedEditor = false
    @State private var hasBlockingEditorOperation = false
    @State private var pendingDestination:
        IOSContainingAppDestination?
    @State private var pendingSettingsRoute: IOSSettingsRoute?
    @State private var acceptedKeyboardHandoffIntent:
        KeyboardHandoffIntentRecord?
    @State private var activeKeyboardHandoffRequestID: UUID?
    @State private var startingKeyboardHandoffRequestID: UUID?
    @State private var showsEditorDiscardConfirmation = false
    @State private var showsEditorOperationAlert = false

    let secureProviderAvailability: IOSSecureProviderAvailability
    let foregroundVoiceRuntimeAvailable: Bool
    let historyPlaybackActions: IOSHistoryPlaybackActions?
    let recordingCacheLifecycleActions:
        IOSRecordingCacheLifecycleActions?
    let layout: IOSContainingAppShellLayout
    let launchRouter: IOSKeyboardHandoffLaunchRouter
    let keyboardHandoffPresentationOwner:
        IOSKeyboardHandoffPresentationOwner?
    let keyboardHandoffNow: @Sendable () -> Date

    init(
        secureProviderAvailability: IOSSecureProviderAvailability,
        foregroundVoiceRuntimeAvailable: Bool = false,
        historyPlaybackActions: IOSHistoryPlaybackActions? = nil,
        recordingCacheLifecycleActions:
            IOSRecordingCacheLifecycleActions? = nil,
        layout: IOSContainingAppShellLayout = .current,
        launchRouter: IOSKeyboardHandoffLaunchRouter = .live,
        keyboardHandoffPresentationOwner:
            IOSKeyboardHandoffPresentationOwner? = nil,
        keyboardHandoffNow: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.secureProviderAvailability = secureProviderAvailability
        self.foregroundVoiceRuntimeAvailable =
            foregroundVoiceRuntimeAvailable
        self.historyPlaybackActions = historyPlaybackActions
        self.recordingCacheLifecycleActions =
            recordingCacheLifecycleActions
        self.layout = layout
        self.launchRouter = launchRouter
        self.keyboardHandoffPresentationOwner =
            keyboardHandoffPresentationOwner
        self.keyboardHandoffNow = keyboardHandoffNow
    }

    var body: some View {
        Group {
            switch layout {
            case .tabs:
                tabShell
            case .split:
                splitShell
            }
        }
        .onAppear(perform: restoreSelectionIfNeeded)
        .onChange(of: scenePhase) { _, _ in
            startAcceptedKeyboardHandoffIfPossible()
        }
        .confirmationDialog(
            "Discard Unsaved Changes?",
            isPresented: $showsEditorDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes and Continue", role: .destructive) {
                applyPendingDestination()
            }
            Button("Keep Editing", role: .cancel) {
                pendingDestination = nil
                pendingSettingsRoute = nil
            }
        } message: {
            Text(
                "Your unsaved edits on the current screen will be lost."
            )
        }
        .onOpenURL { url in
            switch launchRouter.resolve(url) {
            case .ignore:
                break
            case .settings(let attention):
                openSettings(.attention(attention))
            case .keyboardHandoff(let intent):
                acceptKeyboardHandoff(intent)
            }
        }
        .alert(
            "Finishing Dictation Rule Change",
            isPresented: $showsEditorOperationAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "Wait for the current Save or Delete operation to finish "
                    + "before changing destinations."
            )
        }
        .sheet(isPresented: keyboardHandoffSheetIsPresented) {
            if let keyboardHandoffPresentationOwner,
               let presentation =
                   keyboardHandoffPresentationOwner.presentation {
                IOSKeyboardHandoffSheet(
                    presentation: presentation,
                    cancel: {
                        keyboardHandoffPresentationOwner.cancelFromSheet()
                    }
                )
            }
        }
    }

    private func acceptKeyboardHandoff(
        _ intent: KeyboardHandoffIntentRecord
    ) {
        acceptedKeyboardHandoffIntent = intent
        activeKeyboardHandoffRequestID = intent.requestID
        requestDestination(.voice)
        startAcceptedKeyboardHandoffIfPossible()
    }

    private func startAcceptedKeyboardHandoffIfPossible() {
        guard let intent = acceptedKeyboardHandoffIntent,
              activeKeyboardHandoffRequestID == intent.requestID else {
            return
        }
        guard IOSKeyboardHandoffSceneDecision.resolve(
            IOSVoiceSceneActivity(scenePhase)
        ) == .start else {
            return
        }
        guard startingKeyboardHandoffRequestID != intent.requestID else {
            return
        }
        guard let keyboardHandoffPresentationOwner else {
            clearAcceptedKeyboardHandoff(intent.requestID)
            return
        }
        guard intent.expiresAt > keyboardHandoffNow() else {
            clearAcceptedKeyboardHandoff(intent.requestID)
            return
        }
        startingKeyboardHandoffRequestID = intent.requestID
        Task { @MainActor in
            guard activeKeyboardHandoffRequestID == intent.requestID else {
                return
            }
            clearAcceptedKeyboardHandoff(intent.requestID)
            guard intent.expiresAt > keyboardHandoffNow() else { return }
            await keyboardHandoffPresentationOwner.start(intent)
        }
    }

    private func clearAcceptedKeyboardHandoff(_ requestID: UUID) {
        guard activeKeyboardHandoffRequestID == requestID else { return }
        acceptedKeyboardHandoffIntent = nil
        activeKeyboardHandoffRequestID = nil
        if startingKeyboardHandoffRequestID == requestID {
            startingKeyboardHandoffRequestID = nil
        }
    }

    private var keyboardHandoffSheetIsPresented: Binding<Bool> {
        Binding(
            get: {
                keyboardHandoffPresentationOwner?.presentation != nil
            },
            set: { isPresented in
                guard !isPresented else { return }
                keyboardHandoffPresentationOwner?.cancelFromSheet()
            }
        )
    }

    private var selectedDestination: IOSContainingAppDestination {
        IOSContainingAppDestination.resolve(
            storedRawValue: selectedDestinationRawValue
        )
    }

    private var destinationSelection:
        Binding<IOSContainingAppDestination> {
        Binding(
            get: { selectedDestination },
            set: { requestDestination($0) }
        )
    }

    private var tabShell: some View {
        TabView(selection: destinationSelection) {
            ForEach(IOSContainingAppDestination.allCases) { destination in
                destinationStack(destination)
                .tabItem {
                    Label(destination.title, systemImage: destination.systemImage)
                }
                .tag(destination)
                .accessibilityIdentifier(
                    "\(destination.accessibilityIdentifier).tab"
                )
            }
        }
        .accessibilityIdentifier("ios.containing-app.tabs")
    }

    private var splitShell: some View {
        NavigationSplitView(
            preferredCompactColumn: $preferredCompactColumn
        ) {
            List(IOSContainingAppDestination.allCases) { destination in
                Button {
                    requestDestination(destination)
                } label: {
                    Label(
                        destination.title,
                        systemImage: destination.systemImage
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    selectedDestination == destination
                        ? Color.accentColor.opacity(0.14)
                        : Color.clear
                )
                .accessibilityAddTraits(
                    selectedDestination == destination
                        ? .isSelected
                        : []
                )
                .accessibilityIdentifier(
                    "\(destination.accessibilityIdentifier).sidebar"
                )
            }
            .navigationTitle("HoldType")
            .accessibilityIdentifier("ios.containing-app.sidebar")
        } detail: {
            destinationStack(selectedDestination)
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("ios.containing-app.split")
    }

    @ViewBuilder
    private func destinationStack(
        _ destination: IOSContainingAppDestination
    ) -> some View {
        if destination == .settings {
            NavigationStack(path: $settingsNavigationPath) {
                destinationRoot(destination)
            }
        } else if destination == .library {
            NavigationStack(path: $libraryNavigationPath) {
                destinationRoot(destination)
            }
        } else {
            NavigationStack {
                destinationRoot(destination)
            }
        }
    }

    @ViewBuilder
    private func destinationRoot(
        _ destination: IOSContainingAppDestination
    ) -> some View {
        switch destination {
        case .voice:
            if foregroundVoiceRuntimeAvailable {
                IOSVoiceHomeView(
                    practiceText: $sceneDraft.practiceText,
                    secureProviderAvailability:
                        secureProviderAvailability,
                    openSettings: openSettings
                )
            } else {
                IOSVoiceRuntimeUnavailableView()
            }
        case .library:
            IOSLibraryHomeView(
                hasUnsavedLibraryEditor: $hasUnsavedEditor,
                hasBlockingLibraryOperation: $hasBlockingEditorOperation
            )
        case .history:
            IOSHistoryHomeView(
                playbackActions: historyPlaybackActions
            )
        case .usage:
            IOSUsageEstimateView()
        case .settings:
            IOSSettingsHomeView(
                openAIEditorDraft: $openAIEditorDraft,
                practiceText: $sceneDraft.practiceText,
                foregroundVoiceRuntimeAvailable:
                    foregroundVoiceRuntimeAvailable,
                reconcileRecordingCache: { policy in
                    guard let recordingCacheLifecycleActions else {
                        return true
                    }
                    return await recordingCacheLifecycleActions.reconcile(
                        policy: policy
                    )
                }
            )
        }
    }

    private func restoreSelectionIfNeeded() {
        if IOSContainingAppDestination(
            rawValue: selectedDestinationRawValue
        ) == nil {
            selectedDestinationRawValue =
                IOSContainingAppDestination.voice.rawValue
        }

    }

    private func requestDestination(
        _ destination: IOSContainingAppDestination
    ) {
        pendingSettingsRoute = nil
        switch IOSContainingAppDestinationSelectionDecision.resolve(
            current: selectedDestination,
            requested: destination,
            hasUnsavedEditor: hasUnsavedEditor,
            hasBlockingEditorOperation: hasBlockingEditorOperation
        ) {
        case .unchanged:
            if layout == .split {
                preferredCompactColumn = .detail
            }
            return
        case .apply(let destination):
            applyDestination(destination)
        case .confirmDiscard(let destination):
            pendingDestination = destination
            dismissActiveTextInput()
            Task { @MainActor in
                await Task.yield()
                guard pendingDestination == destination else { return }
                showsEditorDiscardConfirmation = true
            }
        case .blockedByEditorOperation:
            pendingDestination = nil
            dismissActiveTextInput()
            Task { @MainActor in
                await Task.yield()
                showsEditorOperationAlert = true
            }
        }
    }

    private func dismissActiveTextInput() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func applyPendingDestination() {
        guard let pendingDestination else { return }
        let settingsRoute = pendingSettingsRoute
        hasUnsavedEditor = false
        clearActiveEditorPath()
        self.pendingDestination = nil
        pendingSettingsRoute = nil
        if pendingDestination == .settings, let settingsRoute {
            settingsNavigationPath = NavigationPath([settingsRoute])
        }
        applyDestination(pendingDestination)
    }

    private func clearActiveEditorPath() {
        switch selectedDestination {
        case .settings:
            settingsNavigationPath = NavigationPath()
        case .library:
            libraryNavigationPath = NavigationPath()
        case .voice, .history, .usage:
            break
        }
    }

    private func applyDestination(
        _ destination: IOSContainingAppDestination
    ) {
        selectedDestinationRawValue = destination.rawValue
        if layout == .split {
            preferredCompactColumn = .detail
        }
    }

    private func openSettings(_ route: IOSSettingsRoute) {
        switch IOSContainingAppDestinationSelectionDecision.resolve(
            current: selectedDestination,
            requested: .settings,
            hasUnsavedEditor: hasUnsavedEditor,
            hasBlockingEditorOperation: hasBlockingEditorOperation
        ) {
        case .unchanged:
            guard !hasBlockingEditorOperation else {
                dismissActiveTextInput()
                Task { @MainActor in
                    await Task.yield()
                    showsEditorOperationAlert = true
                }
                return
            }
            guard !hasUnsavedEditor else {
                pendingDestination = .settings
                pendingSettingsRoute = route
                dismissActiveTextInput()
                Task { @MainActor in
                    await Task.yield()
                    showsEditorDiscardConfirmation = true
                }
                return
            }
            settingsNavigationPath = NavigationPath([route])
        case .apply:
            settingsNavigationPath = NavigationPath([route])
            applyDestination(.settings)
        case .confirmDiscard:
            pendingDestination = .settings
            pendingSettingsRoute = route
            dismissActiveTextInput()
            Task { @MainActor in
                await Task.yield()
                showsEditorDiscardConfirmation = true
            }
        case .blockedByEditorOperation:
            pendingDestination = nil
            pendingSettingsRoute = nil
            dismissActiveTextInput()
            Task { @MainActor in
                await Task.yield()
                showsEditorOperationAlert = true
            }
        }
    }
}

struct IOSContainingAppSceneDraft: Equatable {
    var practiceText = ""
}

struct IOSContainingAppStorageUnavailableView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(
                    "Local Storage Unavailable",
                    systemImage: "externaldrive.badge.exclamationmark"
                )
            } description: {
                Text(
                    "HoldType couldn’t open its private local storage. "
                    + "Your settings and dictation rules were not replaced with "
                    + "defaults. Close and reopen HoldType to try again."
                )
            }
            .navigationTitle("HoldType")
        }
        .accessibilityIdentifier("ios.storage-unavailable")
    }
}
