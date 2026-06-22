//
//  TranscriptHistoryView.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import SwiftUI

struct TranscriptHistoryView: View {
    @ObservedObject private var historyStore: TranscriptRecoveryHistoryStore
    @State private var appSettings: AppSettings
    @State private var actionStatusText: String?

    private let appSettingsStore: AppSettingsStore
    private let transcriptClipboardStore: any TranscriptClipboardStoring
    private let textInsertionService: TextInsertionService
    private let calendar: Calendar

    @MainActor
    init(
        historyStore: TranscriptRecoveryHistoryStore? = nil,
        appSettingsStore: AppSettingsStore = AppSettingsStore(),
        transcriptClipboardStore: any TranscriptClipboardStoring = AppTranscriptClipboardStore.shared,
        textInsertionService: TextInsertionService = TextInsertionService(),
        calendar: Calendar = .current
    ) {
        self.historyStore = historyStore ?? TranscriptRecoveryHistoryStore.shared
        self.appSettingsStore = appSettingsStore
        self.transcriptClipboardStore = transcriptClipboardStore
        self.textInsertionService = textInsertionService
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

            Button("Clear History", role: .destructive) {
                clearHistory()
            }
            .disabled(historyStore.entries.isEmpty)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if !appSettings.saveTranscriptHistory {
            TranscriptHistoryEmptyStateView(
                systemImage: "clock.badge.xmark",
                title: "Transcript history is off",
                message: "Enable recovery history in Settings to keep recent accepted transcripts until you quit."
            )
        } else if historyStore.entries.isEmpty {
            TranscriptHistoryEmptyStateView(
                systemImage: "text.bubble",
                title: "No transcripts yet",
                message: "Accepted dictations will appear here until you clear history or quit VibeType."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(groupedEntries) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            VStack(spacing: 8) {
                                ForEach(group.entries) { entry in
                                    TranscriptHistoryRowView(
                                        entry: entry,
                                        onSave: {
                                            saveToAppClipboard(entry)
                                        },
                                        onInsert: {
                                            insertIntoActiveApp(entry)
                                        }
                                    )
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
        if appSettings.saveTranscriptHistory {
            return "\(historyStore.entries.count) of \(TranscriptRecoveryHistoryStore.defaultRetentionLimit) session entries"
        }

        return "Session recovery is disabled"
    }

    private var groupedEntries: [TranscriptHistoryGroup] {
        let grouped = Dictionary(grouping: historyStore.entries) { entry in
            calendar.startOfDay(for: entry.createdAt)
        }

        return grouped.keys.sorted(by: >).map { day in
            TranscriptHistoryGroup(
                day: day,
                title: title(for: day),
                entries: (grouped[day] ?? []).sorted { lhs, rhs in
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
        actionStatusText = "Transcript history cleared."
    }

    private func saveToAppClipboard(_ entry: TranscriptHistoryEntry) {
        guard appSettings.saveTranscriptsToAppClipboard else {
            actionStatusText = TextInsertionSkipReason.appClipboardDisabled.statusText
            return
        }

        Task {
            do {
                try await transcriptClipboardStore.save(entry.transcriptText)
                await MainActor.run {
                    actionStatusText = "Saved history row to VibeType Clipboard."
                }
            } catch {
                await MainActor.run {
                    actionStatusText = error.localizedDescription
                }
            }
        }
    }

    private func insertIntoActiveApp(_ entry: TranscriptHistoryEntry) {
        Task {
            do {
                let result = try await textInsertionService.insertRecoveredTranscript(
                    entry.transcriptText,
                    settings: appSettings
                )
                await MainActor.run {
                    actionStatusText = result.statusText
                }
            } catch {
                await MainActor.run {
                    actionStatusText = error.localizedDescription
                }
            }
        }
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
    let entries: [TranscriptHistoryEntry]

    var id: Date {
        day
    }
}

private struct TranscriptHistoryRowView: View {
    let entry: TranscriptHistoryEntry
    let onSave: () -> Void
    let onInsert: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 58, alignment: .leading)

            Text(entry.transcriptText)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Button(action: onSave) {
                    Label("Save", systemImage: "tray.and.arrow.down")
                }
                .help("Save to VibeType Clipboard")

                Button(action: onInsert) {
                    Label("Insert", systemImage: "text.cursor")
                }
                .help("Insert into Active App")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TranscriptHistoryEmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

#Preview {
    TranscriptHistoryView(historyStore: TranscriptRecoveryHistoryStore())
}
