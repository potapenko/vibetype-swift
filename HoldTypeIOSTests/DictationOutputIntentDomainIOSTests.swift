import Foundation
import HoldTypeDomain
import Testing

struct DictationOutputIntentDomainIOSTests {
    @Test func publicOutputIntentContractWorksThroughANormalIOSImport() throws {
        #expect(DictationOutputIntent.standard.rawValue == "standard")
        #expect(DictationOutputIntent.translate.rawValue == "translate")

        let encoded = try JSONEncoder().encode(DictationOutputIntent.translate)
        #expect(String(decoding: encoded, as: UTF8.self) == "\"translate\"")
        #expect(try JSONDecoder().decode(DictationOutputIntent.self, from: encoded) == .translate)
        #expect(DictationOutputIntent(rawValue: "unknown") == nil)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                DictationOutputIntent.self,
                from: Data("\"unknown\"".utf8)
            )
        }
        requireSendable(DictationOutputIntent.self)
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
