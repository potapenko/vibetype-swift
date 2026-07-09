//
//  KeyboardBridgeIOSTests.swift
//  HoldTypeIOSTests
//
//  Created by Codex on 7/9/26.
//

import Foundation
import Testing

struct KeyboardBridgeIOSTests {

    @Test func transcriptNormalizesWhitespaceAndRejectsEmptyText() throws {
        let transcript = try KeyboardBridgeTranscript(text: "  Bridge sample  \n")

        #expect(transcript.text == "Bridge sample")
        #expect(throws: KeyboardBridgeTranscript.ValidationError.emptyText) {
            try KeyboardBridgeTranscript(text: " \n ")
        }
    }

    @Test func storeRoundTripsAnInsertableSnapshot() throws {
        let fixture = try BridgeStoreFixture()
        defer { fixture.remove() }

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let transcript = try KeyboardBridgeTranscript(
            id: UUID(uuidString: "3E64CDEA-589B-4C69-B0EA-F9CFD19C988B")!,
            text: "Keyboard bridge works",
            createdAt: now
        )
        let snapshot = KeyboardBridgeSnapshot(
            revision: 42,
            sessionID: UUID(uuidString: "4EFA555B-43FE-43B6-9DA9-1525D043025D"),
            phase: .transcriptReady,
            updatedAt: now,
            expiresAt: now.addingTimeInterval(600),
            acceptedTranscript: transcript
        )

        try fixture.store.save(snapshot)
        let loaded = try fixture.store.load(at: now)

        #expect(loaded == snapshot)
        #expect(loaded?.transcriptForInsertion(at: now) == transcript)
    }

    @Test func expiredAndIncompatibleSnapshotsAreUnavailable() throws {
        let fixture = try BridgeStoreFixture()
        defer { fixture.remove() }

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let expired = KeyboardBridgeSnapshot(
            revision: 1,
            phase: .idle,
            updatedAt: now.addingTimeInterval(-20),
            expiresAt: now.addingTimeInterval(-10)
        )
        try fixture.store.save(expired)
        #expect(try fixture.store.load(at: now) == nil)

        let incompatible = KeyboardBridgeSnapshot(
            schemaVersion: 99,
            revision: 2,
            phase: .idle,
            updatedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
        try fixture.store.save(incompatible)
        #expect(try fixture.store.load(at: now) == nil)
    }

    @Test func corruptSnapshotReportsAReadFailure() throws {
        let fixture = try BridgeStoreFixture()
        defer { fixture.remove() }

        try FileManager.default.createDirectory(
            at: fixture.directoryURL,
            withIntermediateDirectories: true
        )
        let snapshotURL = fixture.directoryURL.appendingPathComponent(
            KeyboardBridgeConfiguration.snapshotFilename
        )
        try Data("not-json".utf8).write(to: snapshotURL)

        var didThrow = false
        do {
            _ = try fixture.store.load()
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }

    @Test func decodedTranscriptStillRequiresNonEmptyText() throws {
        let validTranscript = try KeyboardBridgeTranscript(text: "Valid")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let validData = try encoder.encode(validTranscript)

        var object = try #require(
            JSONSerialization.jsonObject(with: validData) as? [String: Any]
        )
        object["text"] = "  \n "
        let invalidData = try JSONSerialization.data(withJSONObject: object)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        #expect(throws: DecodingError.self) {
            try decoder.decode(KeyboardBridgeTranscript.self, from: invalidData)
        }
    }

    @Test func storeIssuesStrictlyIncreasingRevisions() throws {
        let fixture = try BridgeStoreFixture()
        defer { fixture.remove() }

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        #expect(try fixture.store.nextRevision() == 1)

        let first = KeyboardBridgeSnapshot(
            revision: 1,
            phase: .idle,
            updatedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
        try fixture.store.save(first)

        #expect(try fixture.store.nextRevision() == 2)
        #expect(
            throws: KeyboardBridgeStoreError.nonIncreasingRevision(
                current: 1,
                proposed: 1
            )
        ) {
            try fixture.store.save(first)
        }
    }
}

private struct BridgeStoreFixture {
    let directoryURL: URL
    let store: KeyboardBridgeStore

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = KeyboardBridgeStore(
            directoryURL: directoryURL,
            writingOptions: .atomic
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
