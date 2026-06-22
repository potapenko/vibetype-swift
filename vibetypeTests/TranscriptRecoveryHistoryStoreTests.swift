//
//  TranscriptRecoveryHistoryStoreTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/22/26.
//

import Foundation
import Testing
@testable import vibetype

@MainActor
struct TranscriptRecoveryHistoryStoreTests {

    @Test func recordsAcceptedTranscriptsNewestFirstInMemory() throws {
        let store = TranscriptRecoveryHistoryStore()
        var settings = AppSettings.defaults
        settings.transcriptionModel = "gpt-4o-mini-transcribe"
        settings.language = .english

        try store.recordAcceptedTranscript(
            "  First transcript  ",
            settings: settings,
            audioDuration: 1.5
        )
        try store.recordAcceptedTranscript(
            "Second transcript",
            settings: settings,
            audioDuration: 2.5
        )

        #expect(store.entries.map(\.transcriptText) == ["Second transcript", "First transcript"])
        #expect(store.entries.first?.transcriptionModel == "gpt-4o-mini-transcribe")
        #expect(store.entries.first?.languageCode == "en")
        #expect(store.entries.first?.audioDuration == 2.5)
    }

    @Test func disabledSettingDoesNotRecordTranscript() throws {
        let store = TranscriptRecoveryHistoryStore()
        var settings = AppSettings.defaults
        settings.saveTranscriptHistory = false

        try store.recordAcceptedTranscript(
            "Private transcript",
            settings: settings,
            audioDuration: nil
        )

        #expect(store.entries.isEmpty)
    }

    @Test func retainsOnlyMostRecentTwentyEntries() throws {
        let store = TranscriptRecoveryHistoryStore()

        for offset in 0..<21 {
            try store.recordAcceptedTranscript(
                "Transcript \(offset)",
                settings: .defaults,
                audioDuration: nil
            )
        }

        #expect(store.entries.count == TranscriptRecoveryHistoryStore.defaultRetentionLimit)
        #expect(store.entries.first?.transcriptText == "Transcript 20")
        #expect(store.entries.last?.transcriptText == "Transcript 1")
        #expect(store.entries.contains { $0.transcriptText == "Transcript 0" } == false)
    }

    @Test func clearRemovesOnlyCurrentRecoveryEntries() throws {
        let store = TranscriptRecoveryHistoryStore()

        try store.recordAcceptedTranscript(
            "Recoverable transcript",
            settings: .defaults,
            audioDuration: nil
        )

        store.clear()

        #expect(store.entries.isEmpty)
    }

    @Test func rejectsWhitespaceOnlyTranscript() {
        let store = TranscriptRecoveryHistoryStore()

        #expect(throws: TranscriptRecoveryHistoryError.emptyTranscript) {
            try store.recordAcceptedTranscript(
                " \n\t ",
                settings: .defaults,
                audioDuration: nil
            )
        }
        #expect(store.entries.isEmpty)
    }
}
