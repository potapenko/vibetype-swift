import HoldTypeDomain
import SwiftUI

private enum IOSTextFixEditorPreviewError: Error {
    case unavailable
}

struct IOSTextFixEditorView: View {
    @State private var model: IOSTextFixEditorModel
    @State private var pendingDeleteIdentifier: String?
    @State private var showsDeleteConfirmation = false
    @State private var showsRestoreConfirmation = false
    @State private var newActionIdentifier =
        IOSTextFixEditorDraft.newIdentifier()

    init(model: IOSTextFixEditorModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if let catalog = model.catalog {
                catalogList(catalog)
            } else if model.phase == .loading {
                ProgressView("Loading Fixes")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                IOSTextFixEditorLoadFailureView(
                    failure: model.failure,
                    isRetrying: model.isBlockingOperation,
                    retry: {
                        Task {
                            await model.load()
                        }
                    }
                )
            }
        }
        .navigationTitle("Fixes")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isBlockingOperation)
        .searchable(
            text: searchBinding,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Search Fixes")
        )
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.catalog?.customActions.count ?? 0 > 1,
                   model.normalizedSearchText.isEmpty,
                   model.activeDraft == nil
                {
                    EditButton()
                }
                NavigationLink(
                    value: IOSTextFixEditorRoute.newCustom(
                        newActionIdentifier
                    )
                ) {
                    Label("Add Fix", systemImage: "plus")
                }
                .disabled(!model.canAddCustomAction)
                .accessibilityIdentifier("ios.fixes.add")
            }
        }
        .navigationDestination(for: IOSTextFixEditorRoute.self) { route in
            destination(for: route)
        }
        .confirmationDialog(
            "Delete Fix?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Fix", role: .destructive) {
                guard let pendingDeleteIdentifier else { return }
                self.pendingDeleteIdentifier = nil
                Task {
                    await model.deleteCustomAction(
                        id: pendingDeleteIdentifier
                    )
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteIdentifier = nil
            }
        } message: {
            Text("This removes one saved custom Fix.")
        }
        .confirmationDialog(
            "Restore Default Fixes?",
            isPresented: $showsRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults") {
                Task {
                    await model.restoreDefaults()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Missing default custom Fixes will be added. "
                    + "Your other Fixes will not change."
            )
        }
        .task {
            await model.load()
        }
        .onChange(of: model.catalog) { _, catalog in
            guard catalog?.action(id: newActionIdentifier) != nil else {
                return
            }
            newActionIdentifier =
                IOSTextFixEditorDraft.newIdentifier()
        }
        .accessibilityIdentifier("ios.fixes.editor.screen")
    }

    private func catalogList(
        _ catalog: TextFixCatalog
    ) -> some View {
        List {
            if let failure = model.failure {
                IOSTextFixEditorFailureSection(
                    failure: failure,
                    dismiss: model.clearFailure
                )
            }

            if let activeDraft = model.activeDraft,
               model.hasUnsavedChanges
            {
                Section("Unsaved Draft") {
                    NavigationLink(
                        value: resumeRoute(
                            draft: activeDraft,
                            isNew: model.activeDraftIsNew
                        )
                    ) {
                        Label(
                            activeDraft.title.isEmpty
                                ? "Untitled Fix"
                                : activeDraft.title,
                            systemImage: "square.and.pencil"
                        )
                    }
                    Button("Discard Draft", role: .destructive) {
                        model.discardActiveDraft()
                    }
                    .disabled(model.isBlockingOperation)
                }
            }

            if !model.filteredBuiltInActions.isEmpty {
                Section("Built-in") {
                    ForEach(model.filteredBuiltInActions) { action in
                        IOSTextFixEditorBuiltInRow(action: action)
                    }
                }
            }

            Section("Custom Fixes") {
                if catalog.customActions.isEmpty {
                    ContentUnavailableView {
                        Label("No Custom Fixes", systemImage: "sparkles")
                    } description: {
                        Text("Tap Add to create a reusable prompt.")
                    }
                } else if model.filteredCustomActions.isEmpty {
                    ContentUnavailableView {
                        Label(
                            "No Matching Fixes",
                            systemImage: "magnifyingglass"
                        )
                    } description: {
                        Text("Clear search to show your custom Fixes.")
                    }
                } else {
                    let actions = model.filteredCustomActions
                    ForEach(actions) { action in
                        let position = actions.firstIndex {
                            $0.id == action.id
                        } ?? 0
                        IOSTextFixEditorCustomRow(
                            action: action,
                            position: position,
                            totalCount: actions.count,
                            isDisabled: model.isBlockingOperation
                                || model.activeDraft != nil,
                            onSetEnabled: { isEnabled in
                                Task {
                                    await model.setCustomActionEnabled(
                                        id: action.id,
                                        isEnabled: isEnabled
                                    )
                                }
                            },
                            onRequestDelete: {
                                pendingDeleteIdentifier = action.id
                                showsDeleteConfirmation = true
                            }
                        )
                    }
                    .onMove { source, destination in
                        Task {
                            await model.moveCustomActions(
                                fromOffsets: source,
                                toOffset: destination
                            )
                        }
                    }
                    .moveDisabled(
                        !model.normalizedSearchText.isEmpty
                            || model.isBlockingOperation
                    )
                }
            }

            Section {
                Button("Restore Defaults") {
                    showsRestoreConfirmation = true
                }
                .disabled(
                    model.isBlockingOperation || model.activeDraft != nil
                )

                Text(
                    "Restore Defaults adds missing default custom Fixes "
                        + "without deleting or changing your other Fixes."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .disabled(model.phase == .loading)
    }

    @ViewBuilder
    private func destination(
        for route: IOSTextFixEditorRoute
    ) -> some View {
        switch route {
        case .builtIn(let id):
            if let action = model.catalog?.action(id: id),
               action.kind != .customPrompt
            {
                IOSTextFixEditorBuiltInDetailView(action: action)
            } else {
                ContentUnavailableView(
                    "Fix Unavailable",
                    systemImage: "exclamationmark.triangle"
                )
            }
        case .custom, .newCustom:
            IOSTextFixEditorDetailView(model: model, route: route)
        }
    }

    private func resumeRoute(
        draft: IOSTextFixEditorDraft,
        isNew: Bool
    ) -> IOSTextFixEditorRoute {
        isNew ? .newCustom(draft.id) : .custom(draft.id)
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { model.searchText },
            set: { model.searchText = $0 }
        )
    }
}

extension IOSTextFixEditorView: CustomReflectable {
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

#Preview("Fixes catalog") {
    let model = IOSTextFixEditorModel(
        client: IOSTextFixEditorClient(
            load: { TextFixCatalog.defaults },
            save: { $0 }
        )
    )
    NavigationStack {
        IOSTextFixEditorView(model: model)
    }
}

#Preview("Fixes load failure") {
    let model = IOSTextFixEditorModel(
        client: IOSTextFixEditorClient(
            load: { throw IOSTextFixEditorPreviewError.unavailable },
            save: { $0 }
        )
    )
    NavigationStack {
        IOSTextFixEditorView(model: model)
    }
}
