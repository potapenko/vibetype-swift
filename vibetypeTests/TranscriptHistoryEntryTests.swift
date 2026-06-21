//
//  TranscriptHistoryEntryTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/20/26.
//

import Foundation
import Testing
@testable import vibetype

struct TranscriptHistoryEntryTests {

    @Test func createsEntryFromAcceptedTranscriptMetadata() throws {
        let id = try #require(UUID(uuidString: "8D91F716-A597-479A-9724-6F8EF0EC5D3A"))
        let createdAt = Date(timeIntervalSince1970: 1_781_983_983)

        let entry = try TranscriptHistoryEntry(
            id: id,
            createdAt: createdAt,
            transcriptText: "  Ship the Swift slice.  \n",
            transcriptionModel: "  gpt-4o-transcribe  ",
            languageCode: " en ",
            audioDuration: 2.5
        )

        #expect(entry.id == id)
        #expect(entry.createdAt == createdAt)
        #expect(entry.transcriptText == "Ship the Swift slice.")
        #expect(entry.transcriptionModel == "gpt-4o-transcribe")
        #expect(entry.languageCode == "en")
        #expect(entry.audioDuration == 2.5)
    }

    @Test func rejectsWhitespaceOnlyTranscriptText() {
        #expect(throws: TranscriptHistoryEntry.ValidationError.emptyTranscriptText) {
            _ = try TranscriptHistoryEntry(
                transcriptText: "  \n\t  ",
                transcriptionModel: "gpt-4o-transcribe",
                languageCode: nil
            )
        }
    }

    @Test func encodesAndDecodesOnlyAllowedHistoryFields() throws {
        let entry = try TranscriptHistoryEntry(
            id: try #require(UUID(uuidString: "DAE9E50F-F317-4595-9D99-144C0D0BB828")),
            createdAt: Date(timeIntervalSince1970: 1_781_983_983),
            transcriptText: "Accepted transcript",
            transcriptionModel: "gpt-4o-transcribe",
            languageCode: "en",
            audioDuration: 2.5
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(TranscriptHistoryEntry.self, from: data)

        #expect(decoded == entry)

        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let encodedKeys = Set(object.keys)

        #expect(
            encodedKeys == [
                "id",
                "createdAt",
                "transcriptText",
                "transcriptionModel",
                "languageCode",
                "audioDuration",
            ]
        )
        #expect(encodedKeys.contains("prompt") == false)
        #expect(encodedKeys.contains("audioFileURL") == false)
        #expect(encodedKeys.contains("apiKey") == false)
        #expect(encodedKeys.contains("providerPayload") == false)
        #expect(encodedKeys.contains("authorizationHeader") == false)
    }

    @Test func normalizesBlankLanguageCodeToAutomatic() throws {
        let entry = try TranscriptHistoryEntry(
            transcriptText: "Accepted transcript",
            transcriptionModel: "gpt-4o-transcribe",
            languageCode: "  "
        )

        #expect(entry.languageCode == nil)
    }
}
