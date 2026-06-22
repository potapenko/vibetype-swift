//
//  TranscriptHistoryStoreTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/22/26.
//

import Foundation
import Testing
@testable import vibetype

struct TranscriptHistoryStoreTests {

    @Test func appendsAndLoadsAcceptedEntriesFromUserDefaults() throws {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let id = try #require(UUID(uuidString: "21E44D7E-65E7-42E8-A589-EB8DDB933573"))
        let createdAt = Date(timeIntervalSince1970: 1_782_123_456)
        let store = TranscriptHistoryStore(userDefaults: defaults)

        let history = try store.appendTranscript(
            text: "  Keep this accepted transcript.  ",
            transcriptionModel: "  gpt-4o-transcribe  ",
            languageCode: " en ",
            audioDuration: 4.2,
            id: id,
            createdAt: createdAt
        )

        let expectedEntry = try TranscriptHistoryEntry(
            id: id,
            createdAt: createdAt,
            transcriptText: "Keep this accepted transcript.",
            transcriptionModel: "gpt-4o-transcribe",
            languageCode: "en",
            audioDuration: 4.2
        )

        #expect(history == [expectedEntry])
        #expect(try TranscriptHistoryStore(userDefaults: defaults).load() == [expectedEntry])
    }

    @Test func appendingTwentyFirstEntryDropsOldestEntry() throws {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TranscriptHistoryStore(userDefaults: defaults)

        for offset in 0..<21 {
            let entry = try TranscriptHistoryEntry(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: TimeInterval(offset)),
                transcriptText: "Transcript \(offset)",
                transcriptionModel: AppSettings.defaultTranscriptionModel,
                languageCode: nil
            )

            try store.append(entry)
        }

        let history = try store.load()

        #expect(history.count == TranscriptHistoryStore.defaultRetentionLimit)
        #expect(history.first?.transcriptText == "Transcript 20")
        #expect(history.last?.transcriptText == "Transcript 1")
        #expect(history.contains { $0.transcriptText == "Transcript 0" } == false)
    }

    @Test func clearRemovesOnlyTranscriptHistoryEntries() throws {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let unrelatedKey = AppSettingsStore.keyPrefix + "transcriptionModel"
        defaults.set("kept-model", forKey: unrelatedKey)

        let store = TranscriptHistoryStore(userDefaults: defaults)
        try store.appendTranscript(
            text: "History row",
            transcriptionModel: AppSettings.defaultTranscriptionModel,
            languageCode: nil
        )

        try store.clear()

        #expect(try store.load().isEmpty)
        #expect(defaults.string(forKey: unrelatedKey) == "kept-model")
    }

    @Test func rejectsWhitespaceOnlyTranscriptWithoutWritingHistory() throws {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TranscriptHistoryStore(userDefaults: defaults)

        #expect(throws: TranscriptHistoryStoreError.emptyTranscript) {
            try store.appendTranscript(
                text: " \n\t ",
                transcriptionModel: AppSettings.defaultTranscriptionModel,
                languageCode: nil
            )
        }
        #expect(try store.load().isEmpty)
    }

    @Test func unreadablePersistedHistoryIsRecoverableStoreError() {
        let persistence = FakeTranscriptHistoryPersistence(
            storedData: Data("not-json".utf8)
        )
        let store = TranscriptHistoryStore(persistence: persistence)

        #expect(throws: TranscriptHistoryStoreError.unreadableHistory) {
            try store.load()
        }
    }

    @Test func persistenceFailuresAreSurfacedAsRecoverableStoreErrors() {
        #expect(throws: TranscriptHistoryStoreError.loadFailed) {
            try TranscriptHistoryStore(
                persistence: FakeTranscriptHistoryPersistence(loadError: FakePersistenceError.failed)
            ).load()
        }

        #expect(throws: TranscriptHistoryStoreError.saveFailed) {
            try TranscriptHistoryStore(
                persistence: FakeTranscriptHistoryPersistence(saveError: FakePersistenceError.failed)
            ).appendTranscript(
                text: "Accepted transcript",
                transcriptionModel: AppSettings.defaultTranscriptionModel,
                languageCode: nil
            )
        }

        #expect(throws: TranscriptHistoryStoreError.clearFailed) {
            try TranscriptHistoryStore(
                persistence: FakeTranscriptHistoryPersistence(removeError: FakePersistenceError.failed)
            ).clear()
        }
    }

    private func makeIsolatedUserDefaults() -> (UserDefaults, String) {
        let suiteName = "vibetype.TranscriptHistoryStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated UserDefaults suite")
            return (.standard, suiteName)
        }

        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

private enum FakePersistenceError: Error {
    case failed
}

private final class FakeTranscriptHistoryPersistence: TranscriptHistoryPersistence {
    private var storedData: Data?
    private let loadError: Error?
    private let saveError: Error?
    private let removeError: Error?

    init(
        storedData: Data? = nil,
        loadError: Error? = nil,
        saveError: Error? = nil,
        removeError: Error? = nil
    ) {
        self.storedData = storedData
        self.loadError = loadError
        self.saveError = saveError
        self.removeError = removeError
    }

    func loadData(forKey key: String) throws -> Data? {
        if let loadError {
            throw loadError
        }

        return storedData
    }

    func saveData(_ data: Data, forKey key: String) throws {
        if let saveError {
            throw saveError
        }

        storedData = data
    }

    func removeData(forKey key: String) throws {
        if let removeError {
            throw removeError
        }

        storedData = nil
    }
}
