//
//  TranscriptRecoveryHistoryStore.swift
//  HoldType
//
//  Created by Codex on 6/22/26.
//

import Combine
import Foundation
import HoldTypeDomain

@MainActor
protocol TranscriptRecoveryHistoryRecording: AnyObject {
    var entries: [TranscriptHistoryEntry] { get }

    func recordAcceptedTranscript(_ request: AcceptedTranscriptHistoryRequest) throws
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
    nonisolated static let defaultRetentionLimit =
        RetentionConfiguration.acceptedHistoryEntryLimit

    @Published private(set) var entries: [TranscriptHistoryEntry] = []

    private let retentionLimit: Int

    init(retentionLimit: Int = TranscriptRecoveryHistoryStore.defaultRetentionLimit) {
        self.retentionLimit = max(1, retentionLimit)
    }

    func recordAcceptedTranscript(_ request: AcceptedTranscriptHistoryRequest) throws {
        guard request.historyEnabled else {
            return
        }

        let entry: TranscriptHistoryEntry
        do {
            entry = try TranscriptHistoryEntry(
                transcriptText: request.acceptedTranscript.text,
                transcriptionModel: request.transcriptionModel,
                languageCode: request.languageCode,
                audioDuration: request.audioDuration,
                cachedAudioFileURL: request.cachedAudioFileURL
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

    @discardableResult
    func deleteEntry(id: TranscriptHistoryEntry.ID) -> Bool {
        let originalCount = entries.count
        entries.removeAll { entry in
            entry.id == id
        }
        return entries.count != originalCount
    }

    private func retainedEntries(_ entries: [TranscriptHistoryEntry]) -> [TranscriptHistoryEntry] {
        let newestFirstEntries = entries.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }

        return Array(newestFirstEntries.prefix(retentionLimit))
    }
}
