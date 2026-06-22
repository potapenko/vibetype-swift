//
//  TranscriptHistoryStore.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import Foundation

protocol TranscriptHistoryPersistence {
    func loadData(forKey key: String) throws -> Data?
    func saveData(_ data: Data, forKey key: String) throws
    func removeData(forKey key: String) throws
}

extension UserDefaults: TranscriptHistoryPersistence {
    func loadData(forKey key: String) throws -> Data? {
        data(forKey: key)
    }

    func saveData(_ data: Data, forKey key: String) throws {
        set(data, forKey: key)
    }

    func removeData(forKey key: String) throws {
        removeObject(forKey: key)
    }
}

struct TranscriptHistoryStore {
    static let defaultStorageKey = "vibetype.transcriptHistory.entries"
    static let defaultRetentionLimit = 20

    private let persistence: any TranscriptHistoryPersistence
    private let storageKey: String
    private let retentionLimit: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = Self.defaultStorageKey,
        retentionLimit: Int = Self.defaultRetentionLimit,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.init(
            persistence: userDefaults,
            storageKey: storageKey,
            retentionLimit: retentionLimit,
            encoder: encoder,
            decoder: decoder
        )
    }

    init(
        persistence: any TranscriptHistoryPersistence,
        storageKey: String = Self.defaultStorageKey,
        retentionLimit: Int = Self.defaultRetentionLimit,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.persistence = persistence
        self.storageKey = storageKey
        self.retentionLimit = max(1, retentionLimit)
        self.encoder = encoder
        self.decoder = decoder
    }

    func load() throws -> [TranscriptHistoryEntry] {
        let data: Data?

        do {
            data = try persistence.loadData(forKey: storageKey)
        } catch {
            throw TranscriptHistoryStoreError.loadFailed
        }

        guard let data else {
            return []
        }

        do {
            return retainedEntries(try decoder.decode([TranscriptHistoryEntry].self, from: data))
        } catch {
            throw TranscriptHistoryStoreError.unreadableHistory
        }
    }

    @discardableResult
    func append(_ entry: TranscriptHistoryEntry) throws -> [TranscriptHistoryEntry] {
        let updatedEntries = retainedEntries([entry] + (try load()))
        try save(updatedEntries)
        return updatedEntries
    }

    @discardableResult
    func appendTranscript(
        text: String,
        transcriptionModel: String,
        languageCode: String?,
        audioDuration: TimeInterval? = nil,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) throws -> [TranscriptHistoryEntry] {
        let entry: TranscriptHistoryEntry

        do {
            entry = try TranscriptHistoryEntry(
                id: id,
                createdAt: createdAt,
                transcriptText: text,
                transcriptionModel: transcriptionModel,
                languageCode: languageCode,
                audioDuration: audioDuration
            )
        } catch TranscriptHistoryEntry.ValidationError.emptyTranscriptText {
            throw TranscriptHistoryStoreError.emptyTranscript
        } catch {
            throw TranscriptHistoryStoreError.invalidEntry
        }

        return try append(entry)
    }

    func clear() throws {
        do {
            try persistence.removeData(forKey: storageKey)
        } catch {
            throw TranscriptHistoryStoreError.clearFailed
        }
    }

    private func save(_ entries: [TranscriptHistoryEntry]) throws {
        do {
            try persistence.saveData(try encoder.encode(entries), forKey: storageKey)
        } catch {
            throw TranscriptHistoryStoreError.saveFailed
        }
    }

    private func retainedEntries(_ entries: [TranscriptHistoryEntry]) -> [TranscriptHistoryEntry] {
        let newestFirstEntries = entries.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }

        return Array(newestFirstEntries.prefix(retentionLimit))
    }
}

enum TranscriptHistoryStoreError: Error, Equatable, LocalizedError {
    case emptyTranscript
    case invalidEntry
    case loadFailed
    case unreadableHistory
    case saveFailed
    case clearFailed

    var errorDescription: String? {
        userFacingMessage
    }

    var userFacingMessage: String {
        switch self {
        case .emptyTranscript:
            return "Empty transcripts are not saved to history."
        case .invalidEntry:
            return "The transcript could not be prepared for history."
        case .loadFailed:
            return "Transcript history could not be loaded."
        case .unreadableHistory:
            return "Saved transcript history could not be read."
        case .saveFailed:
            return "Transcript history could not be saved."
        case .clearFailed:
            return "Transcript history could not be cleared."
        }
    }
}
