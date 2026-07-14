import Foundation
import Testing

struct KeyboardDictationBridgeTests {
    @Test func twoCurrentRecordsRoundTripAndExpire() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KeyboardDictationBridgeStore(directoryURL: directory)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let requestID = UUID()
        let command = try #require(
            KeyboardDictationCommandRecord(
                requestID: requestID,
                kind: .start,
                issuedAt: now,
                expiresAt: now.addingTimeInterval(5)
            )
        )
        let state = try #require(
            KeyboardDictationStateRecord(
                requestID: requestID,
                phase: .listening,
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            )
        )

        try store.saveCommand(command)
        try store.saveState(state)

        #expect(try store.loadCommand(at: now) == command)
        #expect(try store.loadState(at: now) == state)
        #expect(
            try store.loadCommand(at: now.addingTimeInterval(5)) == nil
        )
        #expect(
            try store.loadState(at: now.addingTimeInterval(60)) == nil
        )
        #expect(
            try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent).sorted() == [
                KeyboardDictationBridgeConfiguration.commandFilename,
                KeyboardDictationBridgeConfiguration.stateFilename,
            ].sorted()
        )
    }

    @Test func resultIsBoundedAndOnlyAllowedForResultReady() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let requestID = UUID()

        #expect(
            KeyboardDictationStateRecord(
                requestID: requestID,
                phase: .ready,
                result: "unexpected",
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            ) == nil
        )
        #expect(
            KeyboardDictationStateRecord(
                requestID: requestID,
                phase: .resultReady,
                result: nil,
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            ) == nil
        )
        #expect(
            KeyboardDictationStateRecord(
                requestID: requestID,
                phase: .resultReady,
                result: String(repeating: "x", count: 3_073),
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            ) == nil
        )
        #expect(
            KeyboardDictationStateRecord(
                requestID: requestID,
                phase: .resultReady,
                result: "Processed keyboard text",
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            ) != nil
        )
    }
}
