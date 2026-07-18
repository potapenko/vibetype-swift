//
//  TranscriptHistoryView.swift
//  HoldType
//
//  Created by Codex on 6/22/26.
//

import HoldTypeDomain
import SwiftUI

struct TranscriptHistoryView: View {
    @ObservedObject private var historyStore: TranscriptRecoveryHistoryStore
    @ObservedObject private var failureRecoveryStore: TranscriptionFailureRecoveryStore
    @ObservedObject private var dictationRuntime: DictationRuntime
    @State private var appSettings: AppSettings
    @State private var actionStatusText: String?
    @State private var recordingCacheRevision = 0

    private let appSettingsStore: AppSettingsStore
    private let copyHistoryEntryAction: TranscriptHistoryClipboardCopyAction
    private let playHistoryAudioAction: TranscriptHistoryAudioPlaybackAction
    private let retryFailedTranscription: @MainActor (FailedTranscriptionAttempt.ID) async -> Void
    private let openSettings: @MainActor (SettingsNavigationItem) -> Void
    private let calendar: Calendar

    @MainActor
    init(
        historyStore: TranscriptRecoveryHistoryStore? = nil,
        failureRecoveryStore: TranscriptionFailureRecoveryStore? = nil,
        dictationRuntime: DictationRuntime? = nil,
        appSettingsStore: AppSettingsStore = AppSettingsStore(),
        systemClipboardWriter: any SystemClipboardWriting = SystemClipboardWriter(),
        audioPlayer: any TranscriptHistoryAudioPlaying = TranscriptHistoryAudioPlayer.shared,
        retryFailedTranscription: @escaping @MainActor (FailedTranscriptionAttempt.ID) async -> Void = { id in
            await DictationRuntime.shared.retryFailedTranscription(id: id)
        },
        openSettings: @escaping @MainActor (SettingsNavigationItem) -> Void = { item in
            SettingsWindowPresenter.shared.show(focusing: item)
        },
        calendar: Calendar = .current
    ) {
        self.historyStore = historyStore ?? TranscriptRecoveryHistoryStore.shared
        self.failureRecoveryStore = failureRecoveryStore ?? TranscriptionFailureRecoveryStore.shared
        self.dictationRuntime = dictationRuntime ?? .shared
        self.appSettingsStore = appSettingsStore
        copyHistoryEntryAction = TranscriptHistoryClipboardCopyAction(
            systemClipboardWriter: systemClipboardWriter
        )
        playHistoryAudioAction = TranscriptHistoryAudioPlaybackAction(audioPlayer: audioPlayer)
        self.retryFailedTranscription = retryFailedTranscription
        self.openSettings = openSettings
        self.calendar = calendar
        _appSettings = State(initialValue: appSettingsStore.load())
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content

            if let actionStatusText {
                Divider()

                Text(actionStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .onAppear(perform: reloadAppSettings)
        .onReceive(NotificationCenter.default.publisher(for: .appSettingsDidChange)) { _ in
            reloadAppSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingCacheDidChange)) { _ in
            recordingCacheRevision += 1
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Transcript History")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(headerSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Clear Accepted History", role: .destructive) {
                clearHistory()
            }
            .disabled(historyStore.entries.isEmpty)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if historyRows.isEmpty {
            TranscriptHistoryEmptyStateView(
                systemImage: appSettings.saveTranscriptHistory ? "text.bubble" : "clock.badge.xmark",
                title: appSettings.saveTranscriptHistory ? "No transcripts yet" : "Transcript history is off",
                message: appSettings.saveTranscriptHistory
                    ? "Accepted dictations and saved recordings will appear here."
                    : "Accepted transcripts are not retained. Recordings saved for processing or retry will still appear here."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(groupedRows) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            VStack(spacing: 8) {
                                ForEach(group.rows) { row in
                                    switch row {
                                    case .transcript(let entry):
                                        TranscriptHistoryRowView(
                                            entry: entry,
                                            canPlayAudio: canPlayAudio(for: entry),
                                            onPlayAudio: {
                                                playCachedAudio(for: entry)
                                            },
                                            onCopy: {
                                                copyToSystemClipboard(entry)
                                            },
                                            onDelete: {
                                                deleteEntry(entry)
                                            }
                                        )
                                    case .failed(let attempt):
                                        FailedTranscriptionHistoryRowView(
                                            attempt: attempt,
                                            canPlayAudio: canPlayAudio(for: attempt),
                                            savedRecordingActionsEnabled:
                                                savedRecordingActionsEnabled,
                                            onPlayAudio: {
                                                playCachedAudio(for: attempt)
                                            },
                                            onRetry: {
                                                retryAttempt(attempt)
                                            },
                                            onRetrySave: {
                                                retrySavingAttempt(attempt)
                                            },
                                            onOpenSettings: { item in
                                                openSettings(item)
                                            },
                                            onDelete: {
                                                deleteFailedAttempt(attempt)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private var headerSubtitle: String {
        let count = historyRows.count
        if !appSettings.saveTranscriptHistory {
            let savedCount = failureRecoveryStore.failedAttempts.count
            guard savedCount > 0 else {
                return "Accepted transcript history is disabled"
            }
            return "Accepted history off · \(savedCount) saved \(savedCount == 1 ? "recording" : "recordings")"
        }

        return "\(count) session \(count == 1 ? "entry" : "entries")"
    }

    private var historyRows: [TranscriptHistoryRow] {
        let transcriptRows = historyStore.entries.map(TranscriptHistoryRow.transcript)
        let failedRows = failureRecoveryStore.failedAttempts.map(TranscriptHistoryRow.failed)

        return (transcriptRows + failedRows).sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }

    private var groupedRows: [TranscriptHistoryGroup] {
        let grouped = Dictionary(grouping: historyRows) { row in
            calendar.startOfDay(for: row.createdAt)
        }

        return grouped.keys.sorted(by: >).map { day in
            TranscriptHistoryGroup(
                day: day,
                title: title(for: day),
                rows: (grouped[day] ?? []).sorted { lhs, rhs in
                    lhs.createdAt > rhs.createdAt
                }
            )
        }
    }

    private func reloadAppSettings() {
        appSettings = appSettingsStore.load()

        if !appSettings.saveTranscriptHistory {
            historyStore.clear()
        }
    }

    private func clearHistory() {
        historyStore.clear()
        actionStatusText = "Accepted transcript history cleared. Saved recordings were kept."
    }

    private func copyToSystemClipboard(_ entry: TranscriptHistoryEntry) {
        actionStatusText = copyHistoryEntryAction.copy(entry).statusText
    }

    private func canPlayAudio(for entry: TranscriptHistoryEntry) -> Bool {
        _ = recordingCacheRevision
        return playHistoryAudioAction.canPlay(entry, settings: appSettings)
    }

    private func playCachedAudio(for entry: TranscriptHistoryEntry) {
        actionStatusText = playHistoryAudioAction.play(entry, settings: appSettings).statusText
    }

    private func canPlayAudio(for attempt: FailedTranscriptionAttempt) -> Bool {
        _ = recordingCacheRevision
        return playHistoryAudioAction.canPlay(attempt)
    }

    private func playCachedAudio(for attempt: FailedTranscriptionAttempt) {
        guard savedRecordingActionsEnabled else {
            actionStatusText =
                DictationSessionController.savedRecordingActionsUnavailableMessage
            return
        }
        actionStatusText = playHistoryAudioAction.play(attempt).statusText
    }

    private func deleteEntry(_ entry: TranscriptHistoryEntry) {
        let didDelete = historyStore.deleteEntry(id: entry.id)
        actionStatusText = didDelete
            ? "Deleted history row."
            : "History row was already gone."
    }

    private func retryAttempt(_ attempt: FailedTranscriptionAttempt) {
        guard savedRecordingActionsEnabled else {
            actionStatusText =
                DictationSessionController.savedRecordingActionsUnavailableMessage
            return
        }

        guard attempt.canRetry else {
            if attempt.state == .processing {
                actionStatusText = "Transcription is already in progress."
                return
            }
            if attempt.state == .saved {
                actionStatusText = "This saved recording is already transcribed."
                return
            }
            actionStatusText = attempt.reason.message
            return
        }

        actionStatusText = "Retrying failed transcription..."
        Task {
            await retryFailedTranscription(attempt.id)
            await MainActor.run {
                actionStatusText = "Retry finished. Check the latest status in the menu."
            }
        }
    }

    private func deleteFailedAttempt(_ attempt: FailedTranscriptionAttempt) {
        guard savedRecordingActionsEnabled, attempt.canDelete else {
            actionStatusText = attempt.state == .processing
                ? "This saved recording is still being processed."
                : DictationSessionController.savedRecordingActionsUnavailableMessage
            return
        }
        do {
            let didDelete = try failureRecoveryStore.removeFailedAttempt(id: attempt.id)
            actionStatusText = didDelete
                ? "Deleted saved recording."
                : "Saved recording was already gone."
        } catch {
            actionStatusText = TranscriptionFailureRecoveryError.deleteFailed.localizedDescription
        }
    }

    private func retrySavingAttempt(_ attempt: FailedTranscriptionAttempt) {
        guard savedRecordingActionsEnabled else {
            actionStatusText = DictationSessionController.savedRecordingActionsUnavailableMessage
            return
        }
        do {
            switch attempt.reason {
            case .savedStatePersistenceFailed:
                guard let acceptedTranscriptText = attempt.acceptedTranscriptText else {
                    throw TranscriptionFailureRecoveryError.attemptUnavailable
                }
                try failureRecoveryStore.markSaved(
                    id: attempt.id,
                    acceptedTranscriptText: acceptedTranscriptText
                )
                actionStatusText = "Saved recording updated."
            case .recoveryOwnershipPersistenceFailed:
                try failureRecoveryStore.repairLocalRecovery(id: attempt.id)
                actionStatusText = "Recording saved locally. Transcription can now be retried."
            case .providerDispatchPersistenceFailed:
                try failureRecoveryStore.repairLocalRecovery(id: attempt.id)
                actionStatusText = "Retry preparation updated. Transcription can now be retried."
            case .postProcessingFailedAfterProviderAcceptance:
                guard let acceptedTranscriptText = attempt.acceptedTranscriptText else {
                    throw TranscriptionFailureRecoveryError.attemptUnavailable
                }
                try failureRecoveryStore.markSaved(
                    id: attempt.id,
                    acceptedTranscriptText: acceptedTranscriptText
                )
                actionStatusText = "Raw transcription saved."
            default:
                throw TranscriptionFailureRecoveryError.attemptUnavailable
            }
        } catch {
            actionStatusText = "The saved recording still could not be updated."
        }
    }

    private var savedRecordingActionsEnabled: Bool {
        dictationRuntime.status.voiceWorkPhase == .inactive
    }

    private func title(for day: Date) -> String {
        if calendar.isDateInToday(day) {
            return "Today"
        }

        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }

        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct TranscriptHistoryGroup: Identifiable {
    let day: Date
    let title: String
    let rows: [TranscriptHistoryRow]

    var id: Date {
        day
    }
}

private enum TranscriptHistoryRow: Identifiable {
    case transcript(TranscriptHistoryEntry)
    case failed(FailedTranscriptionAttempt)

    var id: String {
        switch self {
        case .transcript(let entry):
            return "transcript-\(entry.id.uuidString)"
        case .failed(let attempt):
            return "failed-\(attempt.id.uuidString)"
        }
    }

    var createdAt: Date {
        switch self {
        case .transcript(let entry):
            return entry.createdAt
        case .failed(let attempt):
            return attempt.updatedAt
        }
    }
}

#Preview {
    TranscriptHistoryView(historyStore: TranscriptRecoveryHistoryStore())
}
