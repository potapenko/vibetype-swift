import HoldTypePersistence
import SwiftUI
import UIKit

@MainActor
struct IOSHistoryRowActions {
    private let copyText: (String) -> Void

    init(copyText: @escaping (String) -> Void) {
        self.copyText = copyText
    }

    func copy(_ text: String) {
        copyText(text)
    }

}

struct IOSHistoryHomeView: View {
    @Environment(IOSAcceptedTextHistoryStateOwner.self)
    private var stateOwner
    @State private var pendingClearToken:
        IOSAcceptedTextHistorySnapshotToken?
    @State private var pendingDisableToken:
        IOSAcceptedTextHistorySnapshotToken?
    @State private var playableResultIDs = Set<UUID>()
    @State private var showsPlaybackFailure = false

    private let rowActions: IOSHistoryRowActions
    private let playbackActions: IOSHistoryPlaybackActions?

    init(playbackActions: IOSHistoryPlaybackActions? = nil) {
        rowActions = IOSHistoryRowActions(
            copyText: { UIPasteboard.general.string = $0 }
        )
        self.playbackActions = playbackActions
    }

    init(
        rowActions: IOSHistoryRowActions,
        playbackActions: IOSHistoryPlaybackActions? = nil
    ) {
        self.rowActions = rowActions
        self.playbackActions = playbackActions
    }

    var body: some View {
        Group {
            switch IOSAcceptedTextHistoryHomePresentation.resolve(
                stateOwner.state
            ) {
            case .loading:
                IOSDestinationLoadingView(title: "Loading History")
            case .unavailable:
                unavailableContent
            case .history(let record, let content, let isStale):
                historyList(
                    record,
                    content: content,
                    isStale: isStale
                )
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                historyManagementMenu
            }
        }
        .task {
            await stateOwner.refresh()
        }
        .task(id: playbackRefreshToken) {
            await refreshPlaybackAvailability()
        }
        .onDisappear {
            guard let playbackActions else { return }
            Task { await playbackActions.stop() }
        }
        .alert(
            "Recording Unavailable",
            isPresented: $showsPlaybackFailure
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("HoldType couldn’t play this cached recording.")
        }
        .confirmationDialog(
            "Clear All History?",
            isPresented: Binding(
                get: { pendingClearToken != nil },
                set: { if !$0 { pendingClearToken = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Clear All History", role: .destructive) {
                guard let token = pendingClearToken else { return }
                pendingClearToken = nil
                Task { await stateOwner.clearAll(ifCurrent: token) }
            }
            .disabled(stateOwner.isBusy)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every saved History entry on this device.")
        }
        .confirmationDialog(
            "Turn Off Save History?",
            isPresented: Binding(
                get: { pendingDisableToken != nil },
                set: { if !$0 { pendingDisableToken = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Turn Off and Delete History", role: .destructive) {
                guard let token = pendingDisableToken else { return }
                pendingDisableToken = nil
                Task {
                    await stateOwner.setEnabled(
                        false,
                        ifCurrent: token
                    )
                }
            }
            .disabled(stateOwner.isBusy)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "HoldType will stop saving successful texts and permanently "
                    + "delete the current History on this device."
            )
        }
        .accessibilityIdentifier(
            IOSContainingAppDestination.history.accessibilityIdentifier
        )
    }

    private var unavailableContent: some View {
        IOSDestinationLoadFailureView(
            title: "History Unavailable",
            description:
                "HoldType couldn't read device-local History. Stored data was "
                    + "preserved and was not replaced with an empty list.",
            isRetrying: stateOwner.isBusy,
            retry: { Task { await stateOwner.refresh() } }
        )
    }

    private var historyManagementMenu: some View {
        Menu {
            Button {
                Task { await stateOwner.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier("ios.history.refresh")

            if let record = stateOwner.confirmedRecord {
                Divider()

                Toggle(
                    "Save History",
                    isOn: saveHistoryBinding(record)
                )
                .accessibilityIdentifier("ios.history.save-history")

                Button("Clear All History", role: .destructive) {
                    pendingClearToken = IOSAcceptedTextHistorySnapshotToken(
                        record: record
                    )
                }
                .disabled(record.entries.isEmpty)
                .accessibilityIdentifier("ios.history.clear-all")
            }
        } label: {
            Label("History Options", systemImage: "ellipsis.circle")
        }
        .disabled(stateOwner.isBusy)
        .accessibilityIdentifier("ios.history.menu")
    }

    private func saveHistoryBinding(
        _ record: IOSAcceptedTextHistoryRecord
    ) -> Binding<Bool> {
        Binding(
            get: { record.isEnabled },
            set: { requestedValue in
                guard requestedValue != record.isEnabled else { return }

                let token = IOSAcceptedTextHistorySnapshotToken(
                    record: record
                )
                if requestedValue {
                    Task {
                        await stateOwner.setEnabled(
                            true,
                            ifCurrent: token
                        )
                    }
                } else {
                    pendingDisableToken = token
                }
            }
        )
    }

    private func historyList(
        _ record: IOSAcceptedTextHistoryRecord,
        content: IOSAcceptedTextHistoryHomePresentation.Content,
        isStale: Bool
    ) -> some View {
        List {
            if let notice = stateOwner.notice {
                Section {
                    Label {
                        Text(notice.message)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Button("Dismiss") {
                        stateOwner.dismissNotice()
                    }
                }
                .accessibilityIdentifier("ios.history.warning")
            }

            if isStale {
                Section {
                    Label(
                        "History couldn't be refreshed. The last confirmed list remains visible.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            switch content {
            case .disabled:
                Section {
                    ContentUnavailableView {
                        Label("History Is Off", systemImage: "clock.badge.xmark")
                    } description: {
                        Text("Turn on Save History to keep future successful texts on this device.")
                    }
                }
                .accessibilityIdentifier("ios.history.disabled")
            case .empty:
                Section {
                    ContentUnavailableView {
                        Label("No History Yet", systemImage: "clock")
                    } description: {
                        Text("Successful texts will appear here after you finish a dictation.")
                    }
                }
                .accessibilityIdentifier("ios.history.empty")
            case .entries:
                ForEach(record.entries) { entry in
                    historyRow(entry)
                }
            }
        }
        .refreshable {
            guard !stateOwner.isBusy else { return }
            await stateOwner.refresh()
            await refreshPlaybackAvailability()
        }
    }

    private func historyRow(
        _ entry: IOSAcceptedTextHistoryEntry
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                if playableResultIDs.contains(entry.resultID) {
                    historyActionButton(
                        title: "Play Recording",
                        systemImage: "play.fill"
                    ) {
                        beginPlayback(resultID: entry.resultID)
                    }
                    .accessibilityIdentifier(
                        "ios.history.play.\(entry.resultID.uuidString)"
                    )
                }

                historyActionButton(
                    title: "Copy Text",
                    systemImage: "doc.on.doc"
                ) {
                    rowActions.copy(entry.text)
                }
                .accessibilityHint("Copies this text to the clipboard")
                .accessibilityIdentifier(
                    "ios.history.copy.\(entry.resultID.uuidString)"
                )
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", role: .destructive) {
                Task { await stateOwner.delete(resultID: entry.resultID) }
            }
            .disabled(stateOwner.isBusy)
        }
    }

    private func historyActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var playbackRefreshToken: String {
        stateOwner.confirmedRecord?.entries
            .map(\.resultID.uuidString)
            .joined(separator: "|") ?? ""
    }

    private func refreshPlaybackAvailability() async {
        guard let playbackActions,
              let record = stateOwner.confirmedRecord else {
            playableResultIDs = []
            return
        }
        let resolved = await playbackActions.playableResultIDs(
            record.entries.map(\.resultID)
        )
        guard !Task.isCancelled else { return }
        playableResultIDs = resolved
    }

    private func beginPlayback(resultID: UUID) {
        guard let playbackActions else { return }

        Task {
            switch await playbackActions.play(resultID: resultID) {
            case .played:
                break
            case .unavailable:
                playableResultIDs.remove(resultID)
            case .failed:
                playableResultIDs.remove(resultID)
                showsPlaybackFailure = true
            }
        }
    }
}
