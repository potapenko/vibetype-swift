//
//  TranscriptRecoveryHistoryStoreTests.swift
//  HoldTypeTests
//
//  Created by Codex on 6/22/26.
//

import Foundation
import HoldTypeDomain
import Testing
@testable import HoldType

@MainActor
struct TranscriptRecoveryHistoryStoreTests {

    @Test func recordsAcceptedTranscriptsNewestFirstInMemory() throws {
        let store = TranscriptRecoveryHistoryStore()

        try store.recordAcceptedTranscript(
            try makeRequest(
                "  First transcript  ",
                transcriptionModel: "gpt-4o-mini-transcribe",
                language: .english,
                audioDuration: 1.5
            )
        )
        try store.recordAcceptedTranscript(
            try makeRequest(
                "Second transcript",
                transcriptionModel: "gpt-4o-mini-transcribe",
                language: .english,
                audioDuration: 2.5
            )
        )

        #expect(store.entries.map(\.transcriptText) == ["Second transcript", "First transcript"])
        #expect(store.entries.first?.transcriptionModel == "gpt-4o-mini-transcribe")
        #expect(store.entries.first?.languageCode == "en")
        #expect(store.entries.first?.audioDuration == 2.5)
    }

    @Test func disabledSettingDoesNotRecordTranscript() throws {
        let store = TranscriptRecoveryHistoryStore()

        try store.recordAcceptedTranscript(
            try makeRequest(
                "Private transcript",
                historyEnabled: false
            )
        )

        #expect(store.entries.isEmpty)
    }

    @Test func recordsCachedAudioFileURLWhenRecordingCacheKeepsRecordings() throws {
        let store = TranscriptRecoveryHistoryStore()
        let cachedAudioFileURL = URL(fileURLWithPath: "/tmp/HoldType-cache-enabled.m4a")

        try store.recordAcceptedTranscript(
            try makeRequest(
                "Cached transcript",
                recordingCachePolicy: .keepLast(10),
                audioDuration: 3.5,
                cachedAudioFileURL: cachedAudioFileURL
            )
        )

        #expect(store.entries.first?.cachedAudioFileURL == cachedAudioFileURL)
    }

    @Test func dropsCachedAudioFileURLWhenRecordingCacheDeletesImmediately() throws {
        let store = TranscriptRecoveryHistoryStore()
        let cachedAudioFileURL = URL(fileURLWithPath: "/tmp/HoldType-cache-disabled.m4a")

        try store.recordAcceptedTranscript(
            try makeRequest(
                "Uncached transcript",
                recordingCachePolicy: .deleteImmediately,
                audioDuration: 3.5,
                cachedAudioFileURL: cachedAudioFileURL
            )
        )

        #expect(store.entries.first?.cachedAudioFileURL == nil)
    }

    @Test func retainsOnlyMostRecentTwentyEntries() throws {
        let store = TranscriptRecoveryHistoryStore()

        for offset in 0..<21 {
            try store.recordAcceptedTranscript(
                try makeRequest("Transcript \(offset)")
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
            try makeRequest("Recoverable transcript")
        )

        store.clear()

        #expect(store.entries.isEmpty)
    }

    @Test func deleteEntryRemovesOnlyMatchingRecoveryEntry() throws {
        let store = TranscriptRecoveryHistoryStore()

        try store.recordAcceptedTranscript(
            try makeRequest("Keep this transcript")
        )
        try store.recordAcceptedTranscript(
            try makeRequest("Delete this transcript")
        )

        let entryToDelete = try #require(store.entries.first)

        #expect(store.deleteEntry(id: entryToDelete.id))
        #expect(store.entries.map(\.transcriptText) == ["Keep this transcript"])
        #expect(store.deleteEntry(id: UUID()) == false)
    }

    private func makeRequest(
        _ rawText: String,
        transcriptionModel: String = TranscriptionConfiguration.defaultModel,
        language: TranscriptionLanguage = .automatic,
        customLanguageCode: String = "",
        historyEnabled: Bool = true,
        recordingCachePolicy: RecordingCachePolicy = .deleteImmediately,
        audioDuration: TimeInterval? = nil,
        cachedAudioFileURL: URL? = nil
    ) throws -> AcceptedTranscriptHistoryRequest {
        try AcceptedTranscriptHistoryRequest(
            acceptedTranscript: AcceptedTranscript(rawText: rawText),
            transcriptionConfiguration: TranscriptionConfiguration(
                model: transcriptionModel,
                language: language,
                customLanguageCode: customLanguageCode
            ),
            retentionConfiguration: RetentionConfiguration(
                historyEnabled: historyEnabled,
                recordingCachePolicy: recordingCachePolicy
            ),
            audioDuration: audioDuration,
            cachedAudioFileURL: cachedAudioFileURL
        )
    }
}
