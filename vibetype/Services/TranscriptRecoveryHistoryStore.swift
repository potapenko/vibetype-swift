//
//  TranscriptRecoveryHistoryStore.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import Combine
import Foundation

@MainActor
protocol TranscriptRecoveryHistoryRecording: AnyObject {
    var entries: [TranscriptHistoryEntry] { get }

    func recordAcceptedTranscript(
        _ transcript: String,
        settings: AppSettings,
        audioDuration: TimeInterval?
    ) throws
    func clear()
}

enum TranscriptRecoveryHistoryError: Error, Equatable, LocalizedError {
    case emptyTranscript
    case invalidEntry

    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return "Empty transcripts are not saved to recovery history."
        case .invalidEntry:
            return "The transcript could not be prepared for recovery history."
        }
    }
}

@MainActor
final class TranscriptRecoveryHistoryStore: ObservableObject, TranscriptRecoveryHistoryRecording {
    static let shared = TranscriptRecoveryHistoryStore()
    nonisolated static let defaultRetentionLimit = 20

    @Published private(set) var entries: [TranscriptHistoryEntry] = []

    private let retentionLimit: Int

    init(retentionLimit: Int = TranscriptRecoveryHistoryStore.defaultRetentionLimit) {
        self.retentionLimit = max(1, retentionLimit)
    }

    func recordAcceptedTranscript(
        _ transcript: String,
        settings: AppSettings,
        audioDuration: TimeInterval? = nil
    ) throws {
        guard settings.saveTranscriptHistory else {
            return
        }

        let entry: TranscriptHistoryEntry
        do {
            entry = try TranscriptHistoryEntry(
                transcriptText: transcript,
                transcriptionModel: settings.resolvedTranscriptionModel,
                languageCode: settings.resolvedLanguageCode,
                audioDuration: audioDuration
            )
        } catch TranscriptHistoryEntry.ValidationError.emptyTranscriptText {
            throw TranscriptRecoveryHistoryError.emptyTranscript
        } catch {
            throw TranscriptRecoveryHistoryError.invalidEntry
        }

        entries = retainedEntries([entry] + entries)
    }

    func clear() {
        entries = []
    }

    private func retainedEntries(_ entries: [TranscriptHistoryEntry]) -> [TranscriptHistoryEntry] {
        let newestFirstEntries = entries.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }

        return Array(newestFirstEntries.prefix(retentionLimit))
    }
}
