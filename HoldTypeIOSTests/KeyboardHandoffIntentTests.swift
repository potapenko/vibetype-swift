import Foundation
import Testing
@testable import HoldTypeIOS

@Suite(.serialized)
struct KeyboardHandoffIntentTests {
    @Test func routeRoundTripsOnlyOneOpaqueRequestIdentifier() throws {
        let requestID = UUID()
        let route = KeyboardHandoffLaunchRoute(requestID: requestID)
        let url = try #require(route.url)

        #expect(url.absoluteString == "holdtype://keyboard-handoff/\(requestID.uuidString.lowercased())")
        #expect(KeyboardHandoffLaunchRoute(url: url) == route)

        let rejected = [
            "other://keyboard-handoff/\(requestID.uuidString)",
            "holdtype://other/\(requestID.uuidString)",
            "holdtype://keyboard-handoff/not-a-uuid",
            "holdtype://keyboard-handoff/\(requestID.uuidString)/extra",
            "holdtype://keyboard-handoff/\(requestID.uuidString)?text=secret",
            "holdtype://keyboard-handoff/\(requestID.uuidString)#fragment",
            "holdtype://user@keyboard-handoff/\(requestID.uuidString)",
        ]
        for rawURL in rejected {
            #expect(
                KeyboardHandoffLaunchRoute(
                    url: try #require(URL(string: rawURL))
                ) == nil
            )
        }
    }

    @Test func storeRoundTripsAndConsumesExactlyOnce() throws {
        let fixture = try KeyboardHandoffStoreFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let intent = try #require(
            KeyboardHandoffIntentRecord(
                requestID: UUID(),
                sourceDocumentID: UUID(),
                action: .translateAndImprove,
                issuedAt: now,
                expiresAt: now.addingTimeInterval(10)
            )
        )

        try fixture.store.save(intent)

        #expect(try fixture.store.loadPending(at: now) == intent)
        #expect(
            try fixture.store.consume(
                requestID: intent.requestID,
                at: now.addingTimeInterval(1)
            ) == intent
        )
        #expect(
            try fixture.store.consume(
                requestID: intent.requestID,
                at: now.addingTimeInterval(2)
            ) == nil
        )
        #expect(
            try fixture.store.loadPending(at: now.addingTimeInterval(2))
                == nil
        )
        let storedConsumed = try fixture.store.loadConsumed()
        let consumed = try #require(storedConsumed)
        #expect(consumed.requestID == intent.requestID)
        #expect(consumed.disposition == .consumed)
    }

    @Test func expiredAndMismatchedRequestsAreInert() throws {
        let fixture = try KeyboardHandoffStoreFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let intent = try #require(
            KeyboardHandoffIntentRecord(
                requestID: UUID(),
                sourceDocumentID: nil,
                action: .standard,
                issuedAt: now,
                expiresAt: now.addingTimeInterval(10)
            )
        )
        try fixture.store.save(intent)

        #expect(
            try fixture.store.consume(
                requestID: UUID(),
                at: now.addingTimeInterval(1)
            ) == nil
        )
        #expect(
            try fixture.store.consume(
                requestID: intent.requestID,
                at: now.addingTimeInterval(10)
            ) == nil
        )
    }

    @Test func newerIntentSupersedesThePreviousRequest() throws {
        let fixture = try KeyboardHandoffStoreFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let first = try #require(
            KeyboardHandoffIntentRecord(
                requestID: UUID(),
                sourceDocumentID: UUID(),
                action: .standard,
                issuedAt: now,
                expiresAt: now.addingTimeInterval(10)
            )
        )
        let second = try #require(
            KeyboardHandoffIntentRecord(
                requestID: UUID(),
                sourceDocumentID: UUID(),
                action: .improve,
                issuedAt: now.addingTimeInterval(1),
                expiresAt: now.addingTimeInterval(10)
            )
        )

        try fixture.store.save(first)
        try fixture.store.save(second)

        #expect(try fixture.store.loadConsumed() == nil)

        #expect(
            try fixture.store.consume(
                requestID: first.requestID,
                at: now.addingTimeInterval(2)
            ) == nil
        )
        #expect(
            try fixture.store.consume(
                requestID: second.requestID,
                at: now.addingTimeInterval(2)
            ) == second
        )
    }
}

private struct KeyboardHandoffStoreFixture {
    let directory: URL
    let store: KeyboardHandoffIntentStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-keyboard-handoff-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        store = KeyboardHandoffIntentStore(directoryURL: directory)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
