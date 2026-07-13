//
//  KeyboardBridgeIOSTests.swift
//  HoldTypeIOSTests
//
//  Created by Codex on 7/9/26.
//

import Foundation
import Testing

struct KeyboardBridgeIOSTests {

    @Test func itemPreservesExactTextAndRejectsUnsafePayloads() throws {
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let exactText = "  First line\n\tSecond line 😀  "
        let item = try KeyboardBridgeItem.latest(
            resultID: UUID(),
            text: exactText,
            createdAt: createdAt
        )

        #expect(item.text == exactText)
        #expect(
            item.expiresAt == createdAt.addingTimeInterval(
                KeyboardBridgeConfiguration.latestLifetime
            )
        )
        #expect(throws: KeyboardBridgeItem.ValidationError.emptyText) {
            try KeyboardBridgeItem.latest(
                resultID: UUID(),
                text: " \n\t ",
                createdAt: createdAt
            )
        }
        #expect(
            throws: KeyboardBridgeItem.ValidationError.textTooLarge(
                maximumUTF8Bytes: KeyboardBridgeConfiguration.maximumTextUTF8Bytes
            )
        ) {
            try KeyboardBridgeItem.latest(
                resultID: UUID(),
                text: String(
                    repeating: "a",
                    count: KeyboardBridgeConfiguration.maximumTextUTF8Bytes + 1
                ),
                createdAt: createdAt
            )
        }
        #expect(throws: KeyboardBridgeItem.ValidationError.unsafeControlScalar(0)) {
            try KeyboardBridgeItem.latest(
                resultID: UUID(),
                text: "unsafe\u{0000}text",
                createdAt: createdAt
            )
        }
    }

    @Test func storeRoundTripsProjectionAndExpiryBoundariesAreExclusive() throws {
        let fixture = try BridgeStoreFixture()
        defer { fixture.remove() }

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let latest = try KeyboardBridgeItem.latest(
            resultID: UUID(),
            text: "Latest exact text",
            createdAt: now
        )
        let snapshot = try KeyboardBridgeSnapshot(
            revision: 42,
            publishedAt: now,
            latest: latest
        )

        try fixture.store.save(snapshot)
        let loaded = try #require(try fixture.store.load())

        #expect(loaded == snapshot)
        #expect(
            loaded.latestForInsertion(
                at: latest.expiresAt.addingTimeInterval(-0.001)
            ) == latest
        )
        #expect(loaded.latestForInsertion(at: latest.expiresAt) == nil)

        let object = try #require(
            JSONSerialization.jsonObject(with: fixture.data()) as? [String: Any]
        )
        #expect(object["schemaVersion"] as? Int == 3)
        #expect(object["historyEnabled"] == nil)
        #expect(object["recentResults"] == nil)
    }

    @Test func snapshotRejectsInvalidRevisionAndExtendedLatestLifetime() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let extendedLatest = try KeyboardBridgeItem(
            resultID: UUID(),
            text: "Latest",
            createdAt: now,
            expiresAt: now.addingTimeInterval(
                KeyboardBridgeConfiguration.latestLifetime + 1
            )
        )

        #expect(throws: KeyboardBridgeSnapshot.ValidationError.invalidLatestLifetime) {
            try KeyboardBridgeSnapshot(
                revision: 1,
                latest: extendedLatest
            )
        }
        #expect(throws: KeyboardBridgeSnapshot.ValidationError.invalidRevision) {
            try KeyboardBridgeSnapshot(
                revision: 0,
                latest: nil
            )
        }
    }

    @Test func missingCorruptOversizedLegacyAndFutureFilesStayDistinct() throws {
        let fixture = try BridgeStoreFixture()
        defer { fixture.remove() }

        #expect(try fixture.store.load() == nil)

        try fixture.write(Data("not-json".utf8))
        #expect(throws: KeyboardBridgeStoreError.snapshotDecodeFailed) {
            try fixture.store.load()
        }

        try fixture.write(
            Data(
                repeating: 0x20,
                count: KeyboardBridgeConfiguration.maximumSnapshotBytes + 1
            )
        )
        #expect(
            throws: KeyboardBridgeStoreError.snapshotTooLarge(
                maximumBytes: KeyboardBridgeConfiguration.maximumSnapshotBytes,
                actualBytes: KeyboardBridgeConfiguration.maximumSnapshotBytes + 1
            )
        ) {
            try fixture.store.load()
        }

        for schemaVersion in [1, 2, 99] {
            try fixture.write(
                Data(
                    "{\"revision\":3,\"schemaVersion\":\(schemaVersion)}".utf8
                )
            )
            #expect(
                throws: KeyboardBridgeStoreError.incompatibleSchemaVersion(
                    found: schemaVersion,
                    supported: KeyboardBridgeSnapshot.currentSchemaVersion
                )
            ) {
                try fixture.store.load()
            }
        }
    }

    @Test func v3SaveAtomicallyReplacesLegacySchemasAndRevisionsIncreaseStrictly()
        throws {
        let fixture = try BridgeStoreFixture()
        defer { fixture.remove() }

        try fixture.write(Data("{\"revision\":41,\"schemaVersion\":1}".utf8))
        #expect(try fixture.store.nextRevision() == 42)

        let firstSnapshot = try KeyboardBridgeSnapshot(
            revision: 42,
            publishedAt: Date(timeIntervalSince1970: 1_750_000_000),
            latest: nil
        )
        try fixture.store.save(firstSnapshot)

        #expect(try fixture.store.load() == firstSnapshot)
        #expect(try fixture.store.nextRevision() == 43)

        try fixture.write(
            Data(
                """
                {
                  "schemaVersion": 2,
                  "revision": 73,
                  "historyEnabled": true,
                  "recentResults": [{"text": "must disappear"}]
                }
                """.utf8
            )
        )
        #expect(try fixture.store.nextRevision() == 74)

        let replacement = try KeyboardBridgeSnapshot(
            revision: 74,
            publishedAt: Date(timeIntervalSince1970: 1_750_000_001),
            latest: nil
        )
        try fixture.store.save(replacement)
        #expect(try fixture.store.load() == replacement)

        let storedData = try fixture.data()
        #expect(
            throws: KeyboardBridgeStoreError.nonIncreasingRevision(
                current: 74,
                proposed: 74
            )
        ) {
            try fixture.store.save(replacement)
        }
        #expect(try fixture.data() == storedData)

        let object = try #require(
            JSONSerialization.jsonObject(with: storedData) as? [String: Any]
        )
        #expect(object["schemaVersion"] as? Int == 3)
        #expect(object["historyEnabled"] == nil)
        #expect(object["recentResults"] == nil)
    }

    @Test func canonicalWriterRepairsCorruptCacheButNotFutureSchema()
        throws {
        let fixture = try BridgeStoreFixture()
        defer { fixture.remove() }
        let replacement = try KeyboardBridgeSnapshot(
            revision: 1,
            publishedAt: Date(timeIntervalSince1970: 1_750_000_000),
            latest: nil
        )

        try fixture.write(Data("not-json".utf8))
        #expect(try fixture.store.nextRevision() == 1)
        try fixture.store.save(replacement)
        #expect(try fixture.store.load() == replacement)

        try fixture.write(
            Data(
                repeating: 0x20,
                count: KeyboardBridgeConfiguration.maximumSnapshotBytes + 1
            )
        )
        #expect(try fixture.store.nextRevision() == 1)
        try fixture.store.save(replacement)
        #expect(try fixture.store.load() == replacement)

        try fixture.write(Data("{\"revision\":3,\"schemaVersion\":99}".utf8))
        #expect(
            throws: KeyboardBridgeStoreError.incompatibleSchemaVersion(
                found: 99,
                supported: KeyboardBridgeSnapshot.currentSchemaVersion
            )
        ) {
            try fixture.store.save(replacement)
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

    func write(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try data.write(to: snapshotURL, options: .atomic)
    }

    func data() throws -> Data {
        try Data(contentsOf: snapshotURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private var snapshotURL: URL {
        directoryURL.appendingPathComponent(
            KeyboardBridgeConfiguration.snapshotFilename,
            isDirectory: false
        )
    }
}
