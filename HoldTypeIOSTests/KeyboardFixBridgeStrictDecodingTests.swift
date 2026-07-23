import Foundation
import Testing

struct KeyboardFixBridgeStrictDecodingTests {
    @Test func metadataRejectsUnknownTopLevelAndActionMembers() throws {
        let fixture = try KeyboardFixBridgeTestFixture()
        defer { fixture.remove() }
        try fixture.store.publishMetadata(try makeKeyboardFixMetadataSnapshot())
        let url = fixture.url(
            for: KeyboardFixBridgeConfiguration.metadataFilename
        )
        let pristineData = try Data(contentsOf: url)

        try mutateJSONObject(at: url) { object in
            object["apiKey"] = "PRIVATE-KEY"
        }
        #expect(throws: KeyboardFixBridgeStoreError.decodeFailed) {
            try fixture.store.loadMetadata()
        }

        try pristineData.write(to: url, options: .atomic)
        try mutateJSONObject(at: url) { object in
            var actions = object["actions"] as? [[String: Any]] ?? []
            actions[2]["prompt"] = "PRIVATE-PROMPT"
            object["actions"] = actions
        }
        #expect(throws: KeyboardFixBridgeStoreError.decodeFailed) {
            try fixture.store.loadMetadata()
        }
    }

    @Test func requestRejectsUnknownMembersAndUnsupportedSourceKinds() throws {
        let fixture = try KeyboardFixBridgeTestFixture()
        defer { fixture.remove() }
        let request = try makeKeyboardFixRequest()
        let url = fixture.url(for: KeyboardFixBridgeConfiguration.requestFilename)
        try fixture.store.publishRequest(request)

        try mutateJSONObject(at: url) { object in
            object["surroundingText"] = "PRIVATE-CONTEXT"
        }
        #expect(throws: KeyboardFixBridgeStoreError.decodeFailed) {
            try fixture.store.consumeRequest(at: request.issuedAt)
        }
        #expect(try fixture.store.consumeRequest(at: request.issuedAt) == nil)

        try fixture.store.publishRequest(request)
        try mutateJSONObject(at: url) { object in
            object["sourceKind"] = "complete_field"
        }
        #expect(throws: KeyboardFixBridgeStoreError.decodeFailed) {
            try fixture.store.consumeRequest(at: request.issuedAt)
        }
        #expect(try fixture.store.consumeRequest(at: request.issuedAt) == nil)
    }

    @Test func resultRejectsUnknownMembersAndOpenErrorStringsWithoutReplay() throws {
        let fixture = try KeyboardFixBridgeTestFixture()
        defer { fixture.remove() }
        let request = try makeKeyboardFixRequest()
        let result = try makeKeyboardFixResult(
            request: request,
            phase: .failed,
            failureCode: .providerFailed
        )
        let url = fixture.url(for: KeyboardFixBridgeConfiguration.resultFilename)
        try fixture.store.publishResult(result)

        try mutateJSONObject(at: url) { object in
            object["providerBody"] = "PRIVATE-BODY"
        }
        #expect(throws: KeyboardFixBridgeStoreError.decodeFailed) {
            try fixture.store.consumeTerminalResult(
                matching: request.identity,
                at: result.publishedAt
            )
        }
        #expect(
            try fixture.store.consumeTerminalResult(
                matching: request.identity,
                at: result.publishedAt
            ) == nil
        )

        try fixture.store.publishResult(result)
        try mutateJSONObject(at: url) { object in
            object["failureCode"] = "server said PRIVATE-BODY"
        }
        #expect(throws: KeyboardFixBridgeStoreError.decodeFailed) {
            try fixture.store.consumeTerminalResult(
                matching: request.identity,
                at: result.publishedAt
            )
        }
    }

    @Test func oversizedFilesFailBeforeJSONDecode() throws {
        let fixture = try KeyboardFixBridgeTestFixture()
        defer { fixture.remove() }
        let oversized = Data(
            repeating: 0x20,
            count: KeyboardFixBridgeConfiguration.maximumMetadataBytes + 1
        )
        try oversized.write(
            to: fixture.url(
                for: KeyboardFixBridgeConfiguration.metadataFilename
            )
        )

        #expect(
            throws: KeyboardFixBridgeStoreError.recordTooLarge(
                maximumBytes: KeyboardFixBridgeConfiguration.maximumMetadataBytes,
                actualBytes: oversized.count
            )
        ) {
            try fixture.store.loadMetadata()
        }
    }

    private func mutateJSONObject(
        at url: URL,
        mutation: (inout [String: Any]) -> Void
    ) throws {
        var object = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: url)
            ) as? [String: Any]
        )
        mutation(&object)
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        ).write(to: url, options: .atomic)
    }
}
