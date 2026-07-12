import SwiftUI

struct IOSContainingAppShell: View {
    @SceneStorage("ios.containing-app.selected-destination")
    private var selectedDestinationRawValue =
        IOSContainingAppDestination.voice.rawValue

    @State private var splitSelection: IOSContainingAppDestination?
    @State private var didRestoreSplitSelection = false

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
        .onChange(of: splitSelection) { _, destination in
            guard let destination else { return }
            selectedDestinationRawValue = destination.rawValue
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
            set: { selectedDestinationRawValue = $0.rawValue }
        )
    }

    private var tabShell: some View {
        TabView(selection: destinationSelection) {
            ForEach(IOSContainingAppDestination.allCases) { destination in
                NavigationStack {
                    destinationRoot(destination)
                }
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
        NavigationSplitView {
            List(
                IOSContainingAppDestination.allCases,
                selection: $splitSelection
            ) { destination in
                NavigationLink(value: destination) {
                    Label(
                        destination.title,
                        systemImage: destination.systemImage
                    )
                }
                .accessibilityIdentifier(
                    "\(destination.accessibilityIdentifier).sidebar"
                )
            }
            .navigationTitle("HoldType")
            .accessibilityIdentifier("ios.containing-app.sidebar")
        } detail: {
            NavigationStack {
                destinationRoot(selectedDestination)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("ios.containing-app.split")
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
            IOSLibraryHomeView()
        case .history:
            IOSHistoryHomeView()
        case .settings:
            IOSSettingsHomeView()
        }
    }

    private func restoreSelectionIfNeeded() {
        if IOSContainingAppDestination(
            rawValue: selectedDestinationRawValue
        ) == nil {
            selectedDestinationRawValue =
                IOSContainingAppDestination.voice.rawValue
        }

        guard layout == .split, !didRestoreSplitSelection else { return }
        splitSelection = selectedDestination
        didRestoreSplitSelection = true
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
