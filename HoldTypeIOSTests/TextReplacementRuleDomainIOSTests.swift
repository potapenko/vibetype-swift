import Foundation
import HoldTypeDomain
import Testing

struct TextReplacementRuleDomainIOSTests {
    @Test func packagePreservesLegacyReplacementRulesOnIOS() throws {
        let fixture = Data(
            #"""
            [
              {
                "id": "01234567-89AB-CDEF-0123-456789ABCDEF",
                "search": "—",
                "replacement": "-",
                "isEnabled": true
              }
            ]
            """#.utf8
        )

        let rules = try JSONDecoder().decode([TextReplacementRule].self, from: fixture)
        let rule = try #require(rules.first)

        #expect(rule.id == UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF"))
        #expect(rule.search == "—")
        #expect(rule.replacement == "-")
        #expect(rule.isEnabled)
        #expect(rule.hasSearchText)
        #expect(
            try JSONDecoder().decode(
                [TextReplacementRule].self,
                from: JSONEncoder().encode(rules)
            ) == rules
        )
    }
}
