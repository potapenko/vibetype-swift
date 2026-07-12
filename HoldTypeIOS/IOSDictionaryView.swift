import HoldTypeDomain
import HoldTypePersistence
import SwiftUI

struct IOSDictionaryView: View {
    @Environment(IOSLibraryStateOwner.self) private var stateOwner
    @Environment(\.dismiss) private var dismiss

    @State private var addDraft = IOSDictionaryAddDraft()
    @State private var searchQuery = IOSLibrarySearchQuery()
    @State private var notice: IOSLibraryEditorNotice?
    @State private var pendingDelete: IOSDictionaryEntryReference?
    @State private var showsDeleteConfirmation = false
    @State private var showsDiscardConfirmation = false
    @State private var operationInFlight = false
    @State private var isLoading = false
    @Binding private var hasUnsavedSceneEditor: Bool

    init(hasUnsavedSceneEditor: Binding<Bool>) {
        _hasUnsavedSceneEditor = hasUnsavedSceneEditor
    }

    var body: some View {
        Group {
            switch stateOwner.state {
            case .notLoaded:
                IOSDestinationLoadingView(title: "Loading Dictionary")
            case .loadFailed:
                IOSDestinationLoadFailureView(
                    title: "Dictionary Unavailable",
                    description:
                        "HoldType couldn’t read your Library. No empty "
                        + "replacement was created.",
                    isRetrying: isLoading,
                    retry: retryLoad
                )
            case .ready(let content):
                dictionaryList(
                    entries: content.customDictionary.entries,
                    showsSharedSaveFailure: false
                )
            case .saveFailed(let lastDurableValue):
                dictionaryList(
                    entries: lastDurableValue.customDictionary.entries,
                    showsSharedSaveFailure: true
                )
            }
        }
        .navigationTitle("Dictionary")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(addDraft.hasMeaningfulInput)
        .toolbar {
            if addDraft.hasMeaningfulInput {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showsDiscardConfirmation = true
                    }
                    .disabled(operationInFlight)
                }
            }
        }
        .confirmationDialog(
            "Discard Added Words?",
            isPresented: $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                addDraft = IOSDictionaryAddDraft()
                hasUnsavedSceneEditor = false
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Words that have not been added will be lost.")
        }
        .confirmationDialog(
            "Delete Dictionary Entry?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Entry", role: .destructive) {
                guard let pendingDelete else { return }
                self.pendingDelete = nil
                beginDelete(pendingDelete)
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("This removes one custom Dictionary entry.")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if notice == .notSaved {
                IOSLibraryPersistentFailureStatus()
            }
        }
        .onChange(
            of: addDraft.hasMeaningfulInput,
            initial: true
        ) { _, isDirty in
            hasUnsavedSceneEditor = isDirty
        }
        .accessibilityIdentifier("ios.library.dictionary.screen")
    }

    private func dictionaryList(
        entries: [String],
        showsSharedSaveFailure: Bool
    ) -> some View {
        let rows = entries.compactMap(IOSDictionaryRow.init)
        let visibleRows = filteredRows(rows)

        return List {
            if showsSharedSaveFailure, notice != .notSaved {
                IOSSaveFailureSection(subject: "Library")
            }

            if let notice {
                IOSLibraryEditorNoticeSection(notice: notice)
            }

            Section("Add Words") {
                TextField(
                    "Word or phrase",
                    text: $addDraft.rawInput,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(beginAdd)
                .accessibilityHint(
                    "Separate multiple entries with commas or new lines."
                )

                Button(action: beginAdd) {
                    if operationInFlight {
                        ProgressView()
                            .accessibilityLabel("Adding Dictionary Entries")
                    } else {
                        Label("Add to Dictionary", systemImage: "plus")
                    }
                }
                .disabled(!addDraft.hasMeaningfulInput || operationInFlight)

                Text(
                    "Use commas or new lines to add several words or phrases. "
                        + "Duplicates are ignored."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Saved Entries") {
                if rows.isEmpty {
                    ContentUnavailableView {
                        Label("No Dictionary Entries", systemImage: "book.closed")
                    } description: {
                        Text(
                            "Add names, product terms, or phrases that should "
                                + "appear in transcription hints."
                        )
                    }
                } else if visibleRows.isEmpty {
                    ContentUnavailableView {
                        Label("No Matching Entries", systemImage: "magnifyingglass")
                    } description: {
                        Text("Clear search to show saved entries.")
                    }
                } else {
                    ForEach(visibleRows) { row in
                        Text(row.value)
                            .fixedSize(horizontal: false, vertical: true)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    requestDelete(row.reference)
                                }
                            }
                            .contextMenu {
                                Button("Delete Entry", role: .destructive) {
                                    requestDelete(row.reference)
                                }
                            }
                            .accessibilityAction(named: "Delete Entry") {
                                requestDelete(row.reference)
                            }
                    }
                }
            }

            Section {
                Text(
                    "Dictionary entries stay in HoldType’s private Library. "
                        + "They are not copied into the keyboard extension."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .searchable(
            text: $searchQuery.text,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search Dictionary"
        )
        .scrollDismissesKeyboard(.interactively)
        .disabled(operationInFlight)
    }

    private func filteredRows(
        _ rows: [IOSDictionaryRow]
    ) -> [IOSDictionaryRow] {
        let query = searchQuery.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.value.localizedStandardContains(query) }
    }

    private func beginAdd() {
        guard addDraft.hasMeaningfulInput, !operationInFlight else { return }
        let mutation = IOSLibraryMutation.dictionary(
            .add(rawInput: addDraft.rawInput)
        )
        operationInFlight = true
        Task {
            defer { operationInFlight = false }
            do {
                let completion = try await stateOwner.apply(mutation)
                handleAdd(completion.receipt)
            } catch {
                notice = .notSaved
                iosAnnounceSettingsStatus(
                    "Library was not saved. Added words remain in the draft."
                )
            }
        }
    }

    private func handleAdd(_ receipt: IOSLibraryMutationReceipt) {
        switch receipt.disposition {
        case .committed:
            notice = .added(
                addedCount: receipt.addedCount,
                duplicateCount: receipt.duplicateCount
            )
            addDraft = IOSDictionaryAddDraft()
            iosAnnounceSettingsStatus(
                "Dictionary updated. \(receipt.addedCount) entries added."
            )
        case .duplicate, .unchanged:
            notice = .duplicate(duplicateCount: receipt.duplicateCount)
            addDraft = IOSDictionaryAddDraft()
            iosAnnounceSettingsStatus("Dictionary is already up to date.")
        case .invalid:
            notice = .invalid
            iosAnnounceSettingsStatus(
                "Enter at least one word or phrase to add."
            )
        case .targetMissing, .conflict:
            notice = .changedElsewhere
            iosAnnounceSettingsStatus("Library changed elsewhere.")
        }
    }

    private func requestDelete(_ reference: IOSDictionaryEntryReference) {
        guard !operationInFlight else { return }
        pendingDelete = reference
        showsDeleteConfirmation = true
    }

    private func beginDelete(_ reference: IOSDictionaryEntryReference) {
        guard !operationInFlight else { return }
        operationInFlight = true
        Task {
            defer { operationInFlight = false }
            do {
                let completion = try await stateOwner.apply(
                    .dictionary(.remove(reference))
                )
                switch completion.receipt.disposition {
                case .committed:
                    notice = .deleted
                    iosAnnounceSettingsStatus("Dictionary entry deleted.")
                case .targetMissing, .conflict:
                    notice = .changedElsewhere
                    iosAnnounceSettingsStatus("Library changed elsewhere.")
                case .unchanged, .duplicate, .invalid:
                    notice = .changedElsewhere
                }
            } catch {
                notice = .notSaved
                iosAnnounceSettingsStatus(
                    "Library was not saved. The entry remains saved."
                )
            }
        }
    }

    private func retryLoad() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            _ = try? await stateOwner.load()
        }
    }
}

private nonisolated struct IOSDictionaryRow: Identifiable, Sendable {
    let value: String
    let reference: IOSDictionaryEntryReference

    init?(_ value: String) {
        guard let reference = IOSDictionaryEntryReference(value) else {
            return nil
        }
        self.value = value
        self.reference = reference
    }

    var id: IOSDictionaryEntryReference { reference }
}

private struct IOSLibraryEditorNoticeSection: View {
    let notice: IOSLibraryEditorNotice

    var body: some View {
        Section {
            switch notice {
            case .added(let addedCount, let duplicateCount):
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dictionary Updated")
                        Text(summary(addedCount, duplicateCount))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            case .duplicate(let duplicateCount):
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Already Up to Date")
                        Text(
                            duplicateCount == 1
                                ? "1 entry already exists."
                                : "\(duplicateCount) entries already exist."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            case .deleted:
                Label("Dictionary Entry Deleted", systemImage: "trash")
            case .changedElsewhere:
                IOSSettingsWarningLabel(
                    "Library changed elsewhere. The latest saved entries are shown.",
                    color: .orange
                )
            case .invalid:
                IOSSettingsWarningLabel(
                    "Enter at least one word or phrase.",
                    color: .orange
                )
            case .notSaved:
                IOSSettingsWarningLabel(
                    "Library was not saved. The last saved entries remain active.",
                    color: .red
                )
            }
        }
    }

    private func summary(_ addedCount: Int, _ duplicateCount: Int) -> String {
        let added = addedCount == 1
            ? "1 entry added."
            : "\(addedCount) entries added."
        guard duplicateCount > 0 else { return added }
        let duplicates = duplicateCount == 1
            ? "1 duplicate ignored."
            : "\(duplicateCount) duplicates ignored."
        return added + " " + duplicates
    }
}

private struct IOSLibraryPersistentFailureStatus: View {
    var body: some View {
        Label {
            Text("Not Saved — saved Library unchanged")
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
        .font(.footnote.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .accessibilityIdentifier("ios.library.editor.persistent-save-failed")
    }
}

extension IOSDictionaryView: CustomReflectable {
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSDictionaryRow: CustomReflectable {
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
