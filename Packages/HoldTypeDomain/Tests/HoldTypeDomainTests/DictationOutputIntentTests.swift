import Foundation
import Testing
@testable import HoldTypeDomain

struct DictationOutputIntentTests {
    @Test func casesPreserveStableRawAndCodableValues() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let expected: [(DictationOutputIntent, String)] = [
            (.standard, "standard"),
            (.translate, "translate"),
        ]

        for (intent, rawValue) in expected {
            #expect(intent.rawValue == rawValue)
            #expect(DictationOutputIntent(rawValue: rawValue) == intent)

            let encoded = try encoder.encode(intent)
            #expect(String(decoding: encoded, as: UTF8.self) == "\"\(rawValue)\"")
            #expect(try decoder.decode(DictationOutputIntent.self, from: encoded) == intent)
        }
    }

    @Test func unknownValuesFailClosed() {
        #expect(DictationOutputIntent(rawValue: "unknown") == nil)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                DictationOutputIntent.self,
                from: Data("\"unknown\"".utf8)
            )
        }
    }

    @Test func publicValueIsSendable() {
        requireSendable(DictationOutputIntent.self)
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
