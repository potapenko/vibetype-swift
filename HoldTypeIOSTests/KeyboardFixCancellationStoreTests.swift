import Foundation
import Testing
@testable import HoldTypeIOS

struct KeyboardFixCancellationStoreTests {
    @Test func requestSurvivesAppReadUntilAcknowledgementIsConsumed()
        throws {
        let fixture = try KeyboardFixCancellationStoreFixture()
        defer { fixture.remove() }
        let request = try fixture.makeRequest()
        let cancellation = try fixture.makeCancellation(
            requestID: request.requestID
        )
        try fixture.store.publishRequest(request)

        try fixture.store.publishCancellationRequest(cancellation)

        #expect(
            try fixture.store.consumeRequest(
                at: fixture.now.addingTimeInterval(1)
            ) == nil
        )
        #expect(
            try fixture.store.consumeCancellationRequest(
                at: fixture.now.addingTimeInterval(1)
            ) == cancellation
        )
        // A new app process can repeat the read after process loss.
        #expect(
            try fixture.store.consumeCancellationRequest(
                at: fixture.now.addingTimeInterval(1)
            ) == cancellation
        )

        let acknowledgement = try #require(
            cancellation.acknowledging(
                at: fixture.now.addingTimeInterval(2)
            )
        )
        #expect(
            try fixture.store.publishCancellationAcknowledgement(
                acknowledgement
            )
        )
        #expect(
            try fixture.store.consumeCancellationRequest(
                at: fixture.now.addingTimeInterval(2)
            ) == nil
        )
        #expect(
            try fixture.store.consumeCancellationAcknowledgement(
                matching: request.requestID,
                at: fixture.now.addingTimeInterval(2)
            ) == acknowledgement
        )
        #expect(
            try fixture.store.consumeCancellationAcknowledgement(
                matching: request.requestID,
                at: fixture.now.addingTimeInterval(2)
            ) == nil
        )
    }

    @Test func pendingCancellationBlocksRapidReplacementRequest() throws {
        let fixture = try KeyboardFixCancellationStoreFixture()
        defer { fixture.remove() }
        let first = try fixture.makeRequest()
        let cancellation = try fixture.makeCancellation(
            requestID: first.requestID
        )
        try fixture.store.publishRequest(first)
        try fixture.store.publishCancellationRequest(cancellation)
        let second = try fixture.makeRequest(
            issuedAt: fixture.now.addingTimeInterval(1)
        )

        #expect(throws: KeyboardFixBridgeStoreError.cancellationPending) {
            try fixture.store.publishRequest(second)
        }

        let acknowledgement = try #require(
            cancellation.acknowledging(
                at: fixture.now.addingTimeInterval(2)
            )
        )
        #expect(
            try fixture.store.publishCancellationAcknowledgement(
                acknowledgement
            )
        )
        _ = try fixture.store.consumeCancellationAcknowledgement(
            matching: first.requestID,
            at: fixture.now.addingTimeInterval(2)
        )
        try fixture.store.publishRequest(second)
        #expect(
            try fixture.store.consumeRequest(
                at: fixture.now.addingTimeInterval(2)
            ) == second
        )
    }

    @Test func staleCancellationIdentityDoesNotRetireNewerRequest() throws {
        let fixture = try KeyboardFixCancellationStoreFixture()
        defer { fixture.remove() }
        let staleRequestID = UUID()
        let current = try fixture.makeRequest()
        try fixture.store.publishRequest(current)
        try fixture.store.publishCancellationRequest(
            fixture.makeCancellation(requestID: staleRequestID)
        )

        #expect(
            try fixture.store.consumeRequest(
                at: fixture.now.addingTimeInterval(1)
            ) == current
        )
    }
}

private final class KeyboardFixCancellationStoreFixture {
    let directoryURL: URL
    let store: KeyboardFixBridgeStore
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        store = KeyboardFixBridgeStore(directoryURL: directoryURL)
    }

    func makeRequest(
        issuedAt: Date? = nil
    ) throws -> KeyboardFixRequestRecord {
        let issuedAt = issuedAt ?? now
        return try #require(
            KeyboardFixRequestRecord(
                revision: 1,
                requestID: UUID(),
                actionIdentifier: "builtin.fix",
                sourceText: "Selected source",
                documentIdentifier: "document",
                sourceFingerprint: "fingerprint",
                issuedAt: issuedAt,
                expiresAt: issuedAt.addingTimeInterval(60)
            )
        )
    }

    func makeCancellation(
        requestID: UUID
    ) throws -> KeyboardFixCancellationRecord {
        try #require(
            KeyboardFixCancellationRecord(
                requestID: requestID,
                issuedAt: now,
                expiresAt: now.addingTimeInterval(60)
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
