import Foundation
import Testing
@testable import HoldTypeDomain

struct TextReplacementRuleTests {
    private static let firstID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private static let secondID = UUID(uuidString: "FEDCBA98-7654-3210-FEDC-BA9876543210")!

    @Test func initializerPreservesRawValuesAndDefaultsToEnabled() {
        let rule = TextReplacementRule(
            id: Self.firstID,
            search: "  OpenAI  ",
            replacement: ""
        )

        #expect(rule.id == Self.firstID)
        #expect(rule.search == "  OpenAI  ")
        #expect(rule.replacement.isEmpty)
        #expect(rule.isEnabled)
        #expect(rule.hasSearchText)
    }

    @Test func searchValidationDoesNotMutateRawText() {
        let emptyRule = TextReplacementRule(search: "", replacement: "ignored")
        let whitespaceRule = TextReplacementRule(search: " \n\t ", replacement: "ignored")

        #expect(emptyRule.hasSearchText == false)
        #expect(whitespaceRule.hasSearchText == false)
        #expect(whitespaceRule.search == " \n\t ")
    }

    @Test func frozenLegacyPayloadDecodesAndRoundTripsInOrder() throws {
        let rules = try JSONDecoder().decode(
            [TextReplacementRule].self,
            from: Self.legacyFixture
        )

        #expect(
            rules == [
                TextReplacementRule(
                    id: Self.firstID,
                    search: "—",
                    replacement: "-"
                ),
                TextReplacementRule(
                    id: Self.secondID,
                    search: "  ",
                    replacement: "",
                    isEnabled: false
                ),
            ]
        )

        let encoded = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode([TextReplacementRule].self, from: encoded)
        #expect(decoded == rules)

        let objects = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [[String: Any]]
        )
        let expectedKeys = Set(["id", "search", "replacement", "isEnabled"])
        #expect(objects.allSatisfy { Set($0.keys) == expectedKeys })
    }

    @Test func legacyPayloadStillRequiresEveryField() {
        let missingEnabled = Data(
            #"{"id":"01234567-89AB-CDEF-0123-456789ABCDEF","search":"x","replacement":"y"}"#.utf8
        )

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(TextReplacementRule.self, from: missingEnabled)
        }
    }

    private static let legacyFixture = Data(
        #"""
        [
          {
            "id": "01234567-89AB-CDEF-0123-456789ABCDEF",
            "search": "—",
            "replacement": "-",
            "isEnabled": true
          },
          {
            "id": "FEDCBA98-7654-3210-FEDC-BA9876543210",
            "search": "  ",
            "replacement": "",
            "isEnabled": false
          }
        ]
        """#.utf8
    )
}
