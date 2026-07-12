import SwiftUI

struct IOSContainingAppShell: View {
    @SceneStorage("ios.containing-app.selected-destination")
    private var selectedDestinationRawValue =
        IOSContainingAppDestination.voice.rawValue

    @State private var settingsNavigationPath = NavigationPath()
    @State private var libraryNavigationPath = NavigationPath()
    @State private var preferredCompactColumn:
        NavigationSplitViewColumn = .detail
    @State private var openAIEditorDraft =
        IOSOpenAICredentialEditorDraft()
    @State private var hasUnsavedEditor = false
    @State private var pendingDestination:
        IOSContainingAppDestination?
    @State private var showsEditorDiscardConfirmation = false

    let secureProviderAvailability: IOSSecureProviderAvailability
    let layout: IOSContainingAppShellLayout

    init(
        secureProviderAvailability: IOSSecureProviderAvailability,
        layout: IOSContainingAppShellLayout = .current
    ) {
        self.secureProviderAvailability = secureProviderAvailability
        self.layout = layout
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
            }
        } message: {
            Text(
                "Your unsaved edits on the current screen will be lost."
            )
        }
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
            IOSVoiceHomeView(
                secureProviderAvailability: secureProviderAvailability
            )
        case .library:
            IOSLibraryHomeView(
                hasUnsavedLibraryEditor: $hasUnsavedEditor
            )
        case .history:
            IOSHistoryHomeView()
        case .settings:
            IOSSettingsHomeView(
                openAIEditorDraft: $openAIEditorDraft,
                hasUnsavedGeneralSettings:
                    $hasUnsavedEditor
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
        switch IOSContainingAppDestinationSelectionDecision.resolve(
            current: selectedDestination,
            requested: destination,
            hasUnsavedEditor: hasUnsavedEditor
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
            showsEditorDiscardConfirmation = true
        }
    }

    private func applyPendingDestination() {
        guard let pendingDestination else { return }
        hasUnsavedEditor = false
        clearActiveEditorPath()
        self.pendingDestination = nil
        applyDestination(pendingDestination)
    }

    private func clearActiveEditorPath() {
        switch selectedDestination {
        case .settings:
            settingsNavigationPath = NavigationPath()
        case .library:
            libraryNavigationPath = NavigationPath()
        case .voice, .history:
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
                    + "Your settings and Library were not replaced with "
                    + "defaults. Close and reopen HoldType to try again."
                )
            }
            .navigationTitle("HoldType")
        }
        .accessibilityIdentifier("ios.storage-unavailable")
    }
}
