import Foundation
import Testing

struct KeyboardFixBridgeStoreTests {
    @Test func newerRequestAtomicallySupersedesAndConsumesExactlyOnce() throws {
        let fixture = try KeyboardFixBridgeTestFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let first = try makeKeyboardFixRequest(
            revision: 1,
            requestID: UUID(),
            sourceText: "First",
            issuedAt: now
        )
        let second = try makeKeyboardFixRequest(
            revision: 2,
            requestID: UUID(),
            sourceText: "Second",
            issuedAt: now
        )

        try fixture.store.publishRequest(first)
        try fixture.store.publishRequest(second)

        #expect(
            try fixture.store.consumeRequest(
                at: now.addingTimeInterval(1)
            ) == second
        )
        #expect(
            try fixture.store.consumeRequest(
                at: now.addingTimeInterval(2)
            ) == nil
        )
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.url(
                    for: KeyboardFixBridgeConfiguration.requestFilename
                ).path
            ) == false
        )
    }

    @Test func expiredRequestIsRemovedInsteadOfReplayed() throws {
        let fixture = try KeyboardFixBridgeTestFixture()
        defer { fixture.remove() }
        let request = try makeKeyboardFixRequest()
        try fixture.store.publishRequest(request)

        #expect(
            try fixture.store.consumeRequest(at: request.expiresAt) == nil
        )
        #expect(
            try fixture.store.consumeRequest(
                at: request.expiresAt.addingTimeInterval(1)
            ) == nil
        )
    }

    @Test func processingCanBeObservedButOnlyTerminalResultIsConsumed() throws {
        let fixture = try KeyboardFixBridgeTestFixture()
        defer { fixture.remove() }
        let request = try makeKeyboardFixRequest()
        let processing = try makeKeyboardFixResult(
            request: request,
            phase: .processing,
            outputText: nil
        )
        let success = try makeKeyboardFixResult(request: request)

        try fixture.store.publishResult(processing)
        #expect(
            try fixture.store.loadResult(
                matching: request.identity,
                at: processing.publishedAt
            ) == processing
        )
        try fixture.store.publishResult(success)
        #expect(
            try fixture.store.consumeTerminalResult(
                matching: request.identity,
                at: success.publishedAt
            ) == success
        )
        #expect(
            try fixture.store.consumeTerminalResult(
                matching: request.identity,
                at: success.publishedAt
            ) == nil
        )
    }

    @Test func mismatchedOrExpiredTerminalResultFailsClosedAndIsRetired() throws {
        let fixture = try KeyboardFixBridgeTestFixture()
        defer { fixture.remove() }
        let request = try makeKeyboardFixRequest()
        let result = try makeKeyboardFixResult(request: request)
        var mismatch = request.identity
        mismatch = KeyboardFixRequestIdentity(
            revision: mismatch.revision,
            requestID: UUID(),
            actionIdentifier: mismatch.actionIdentifier,
            sourceKind: mismatch.sourceKind,
            documentIdentifier: mismatch.documentIdentifier,
            sourceFingerprint: mismatch.sourceFingerprint
        )

        try fixture.store.publishResult(result)
        #expect(
            try fixture.store.consumeTerminalResult(
                matching: mismatch,
                at: result.publishedAt
            ) == nil
        )
        #expect(
            try fixture.store.loadResult(
                matching: request.identity,
                at: result.publishedAt
            ) == nil
        )

        try fixture.store.publishResult(result)
        #expect(
            try fixture.store.consumeTerminalResult(
                matching: request.identity,
                at: result.expiresAt
            ) == nil
        )
        #expect(
            try fixture.store.loadResult(
                matching: request.identity,
                at: result.publishedAt
            ) == nil
        )
    }

    @Test func publishingNewRequestRetiresEarlierResultAndCancelIsScoped() throws {
        let fixture = try KeyboardFixBridgeTestFixture()
        defer { fixture.remove() }
        let first = try makeKeyboardFixRequest(requestID: UUID())
        let second = try makeKeyboardFixRequest(requestID: UUID())
        try fixture.store.publishResult(try makeKeyboardFixResult(request: first))

        try fixture.store.publishRequest(second)

        #expect(
            try fixture.store.loadResult(
                matching: first.identity,
                at: first.issuedAt.addingTimeInterval(2)
            ) == nil
        )
        try fixture.store.cancelRequest(requestID: first.requestID)
        #expect(
            try fixture.store.consumeRequest(
                at: second.issuedAt.addingTimeInterval(1)
            ) == second
        )

        try fixture.store.publishRequest(second)
        try fixture.store.publishResult(try makeKeyboardFixResult(request: second))
        try fixture.store.cancelRequest(requestID: second.requestID)
        #expect(try fixture.store.consumeRequest(at: second.issuedAt) == nil)
        #expect(
            try fixture.store.loadResult(
                matching: second.identity,
                at: second.issuedAt.addingTimeInterval(2)
            ) == nil
        )
    }

    @Test func encodedRequestAndResultBoundsFailWithoutTruncation() throws {
        let fixture = try KeyboardFixBridgeTestFixture()
        defer { fixture.remove() }
        let escapedSource = String(
            repeating: "\"",
            count: KeyboardFixBridgeConfiguration.maximumSourceUTF8Bytes
        )
        let request = try makeKeyboardFixRequest(sourceText: escapedSource)

        #expect(
            throws: KeyboardFixBridgeStoreError.recordTooLarge(
                maximumBytes: KeyboardFixBridgeConfiguration.maximumRequestBytes,
                actualBytes: encodedSize(
                    request,
                    dateEncodingStrategy: .millisecondsSince1970
                )
            )
        ) {
            try fixture.store.publishRequest(request)
        }

        let ordinaryRequest = try makeKeyboardFixRequest()
        let escapedOutput = String(
            repeating: "\"",
            count: KeyboardFixBridgeConfiguration.maximumOutputUTF8Bytes
        )
        let result = try #require(
            KeyboardFixResultRecord(
                identity: ordinaryRequest.identity,
                phase: .succeeded,
                outputText: escapedOutput,
                requestIssuedAt: ordinaryRequest.issuedAt,
                publishedAt: ordinaryRequest.issuedAt.addingTimeInterval(1),
                expiresAt: ordinaryRequest.expiresAt
            )
        )
        #expect(
            throws: KeyboardFixBridgeStoreError.recordTooLarge(
                maximumBytes: KeyboardFixBridgeConfiguration.maximumResultBytes,
                actualBytes: encodedSize(
                    result,
                    dateEncodingStrategy: .millisecondsSince1970
                )
            )
        ) {
            try fixture.store.publishResult(result)
        }
    }

    @Test func explicitTransientCleanupLeavesMetadataUntouched() throws {
        let fixture = try KeyboardFixBridgeTestFixture()
        defer { fixture.remove() }
        let metadata = try makeKeyboardFixMetadataSnapshot()
        let request = try makeKeyboardFixRequest()
        try fixture.store.publishMetadata(metadata)
        try fixture.store.publishRequest(request)
        try fixture.store.publishResult(try makeKeyboardFixResult(request: request))

        try fixture.store.removeAllTransientRecords()

        #expect(try fixture.store.loadMetadata() == metadata)
        #expect(try fixture.store.consumeRequest(at: request.issuedAt) == nil)
        #expect(
            try fixture.store.loadResult(
                matching: request.identity,
                at: request.issuedAt.addingTimeInterval(1)
            ) == nil
        )
    }

    private func encodedSize<Value: Encodable>(
        _ value: Value,
        dateEncodingStrategy: JSONEncoder.DateEncodingStrategy
    ) -> Int {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = dateEncodingStrategy
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value).count) ?? -1
    }
}
