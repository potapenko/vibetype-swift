import HoldTypeDomain
import SwiftUI

struct IOSTextFixEditorDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let model: IOSTextFixEditorModel
    let route: IOSTextFixEditorRoute

    @State private var showsDeleteConfirmation = false
    @State private var showsDiscardConfirmation = false

    var body: some View {
        Group {
            if let draft = matchingDraft {
                editorForm(draft)
            } else if model.isBlockingOperation || !model.isLoaded {
                ProgressView("Loading Fix")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Fix Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        "The saved Fix could not be opened."
                    )
                )
            }
        }
        .navigationTitle(routeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isBlockingOperation)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        if await model.saveActiveDraft() {
                            dismiss()
                        }
                    }
                }
                .disabled(!model.canSaveActiveDraft)
            }
        }
        .confirmationDialog(
            "Delete Fix?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Fix", role: .destructive) {
                Task {
                    if await model.deleteCustomAction(
                        id: route.identifier
                    ) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved custom Fix.")
        }
        .confirmationDialog(
            "Discard Draft?",
            isPresented: $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Draft", role: .destructive) {
                model.discardActiveDraft()
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your unsaved title, prompt, and icon changes will be lost.")
        }
        .task {
            guard await model.load() else { return }
            beginEditing()
        }
        .onDisappear {
            model.discardActiveDraftIfClean(id: route.identifier)
        }
        .accessibilityIdentifier("ios.fixes.editor.detail")
    }

    private func editorForm(
        _ draft: IOSTextFixEditorDraft
    ) -> some View {
        Form {
            statusSection

            Section("Fix") {
                TextField(
                    "Title",
                    text: draftBinding(\.title)
                )
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .accessibilityIdentifier("ios.fixes.editor.title")

                IOSTextFixEditorIconPicker(
                    icon: draftBinding(\.icon)
                )

                Toggle(
                    "Enabled",
                    isOn: draftBinding(\.isEnabled)
                )
            }

            Section("Prompt") {
                IOSExactMultilineTextInput(
                    text: draftBinding(\.prompt),
                    accessibilityLabel: "Fix prompt"
                )
                .accessibilityIdentifier("ios.fixes.editor.prompt")

                Text(
                    "\(draft.prompt.utf8.count) of "
                        + "\(TextFixAction.maximumPromptUTF8ByteCount) bytes"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            validationSection(draft.validation)

            Section {
                Button("Discard Draft", role: .destructive) {
                    if model.hasUnsavedChanges {
                        showsDiscardConfirmation = true
                    } else {
                        model.discardActiveDraft()
                        dismiss()
                    }
                }
            }

            if !model.activeDraftIsNew {
                Section {
                    Button("Delete Custom Fix", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                    .disabled(model.isBlockingOperation)
                }
            }

            Section {
                Text(
                    "Prompts stay private to the HoldType app. Running this "
                        + "Fix sends only the chosen source and this "
                        + "instruction to OpenAI after provider consent."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .disabled(model.isBlockingOperation)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var statusSection: some View {
        if model.phase == .saving {
            Section {
                ProgressView("Saving…")
            }
        } else if model.failure == .saveFailed {
            Section {
                Label(
                    "Not Saved. Your draft is still here.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func validationSection(
        _ validation: IOSTextFixEditorDraftValidation
    ) -> some View {
        switch validation {
        case .valid:
            EmptyView()
        case .missingTitle:
            warning("Enter a title.")
        case .titleTooLong(let maximum):
            warning("Keep the title to \(maximum) characters.")
        case .missingPrompt:
            warning("Enter a prompt.")
        case .promptTooLarge(let maximum):
            warning("Keep the prompt to \(maximum) UTF-8 bytes.")
        }
    }

    private func warning(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private var matchingDraft: IOSTextFixEditorDraft? {
        guard model.activeDraft?.id == route.identifier else { return nil }
        return model.activeDraft
    }

    private var routeTitle: String {
        switch route {
        case .newCustom: "New Fix"
        case .custom, .builtIn: "Edit Fix"
        }
    }

    private func beginEditing() {
        switch route {
        case .custom(let id):
            model.beginEditingCustomAction(id: id)
        case .newCustom(let id):
            model.beginNewCustomAction(id: id)
        case .builtIn:
            break
        }
    }

    private func draftBinding<Value>(
        _ keyPath: WritableKeyPath<IOSTextFixEditorDraft, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                guard let draft = matchingDraft else {
                    preconditionFailure("Fix editor draft is unavailable")
                }
                return draft[keyPath: keyPath]
            },
            set: { value in
                guard var draft = matchingDraft else { return }
                draft[keyPath: keyPath] = value
                model.updateActiveDraft(draft)
            }
        )
    }
}

#Preview("Custom Fix editor") {
    let model = IOSTextFixEditorModel(
        client: IOSTextFixEditorClient(
            load: { TextFixCatalog.defaults },
            save: { $0 }
        )
    )
    NavigationStack {
        IOSTextFixEditorDetailView(
            model: model,
            route: .custom("default.improve-writing")
        )
    }
}
