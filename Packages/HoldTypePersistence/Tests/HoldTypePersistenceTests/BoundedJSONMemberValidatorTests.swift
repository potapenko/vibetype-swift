import Foundation
import Testing
@testable import HoldTypePersistence

struct BoundedJSONMemberValidatorTests {
    @Test func acceptsTheCompleteJSONGrammar() throws {
        let validDocuments = [
            "null",
            "true",
            "false",
            #""text\"\\\/\b\f\n\r\t\u0061\uD83D\uDE00""#,
            "0",
            "-0",
            "12",
            "-12.5",
            "1e10",
            "1E+10",
            "1e-10",
            "[]",
            "{}",
            #" { "array" : [null, true, false, -12.5e+2], "object" : {"key":"value"} } "#,
        ]

        for document in validDocuments {
            try validate(document)
        }
    }

    @Test func rejectsDuplicateMembersAtEveryObjectDepth() {
        let documents = [
            #"{"key":1,"key":2}"#,
            #"{"outer":{"key":1,"key":2}}"#,
            #"{"array":[{"key":1,"key":2}]}"#,
            #"[{"outer":{"key":1,"key":2}}]"#,
        ]

        for document in documents {
            #expect(throws: BoundedJSONMemberValidationError.duplicateObjectMember) {
                try validate(document)
            }
        }
    }

    @Test func detectsEverySupportedEscapedEquivalentMemberName() {
        let documents = [
            #"{"a":1,"\u0061":2}"#,
            #"{"schemaVersion":1,"schema\u0056ersion":2}"#,
            #"{"/":1,"\/":2}"#,
            #"{"\\":1,"\u005C":2}"#,
            #"{"\b":1,"\u0008":2}"#,
            #"{"\f":1,"\u000C":2}"#,
            #"{"\n":1,"\u000A":2}"#,
            #"{"\r":1,"\u000D":2}"#,
            #"{"\t":1,"\u0009":2}"#,
            #"{"é":1,"\u00E9":2}"#,
            #"{"😀":1,"\uD83D\uDE00":2}"#,
            #"{"\"":1,"\u0022":2}"#,
        ]

        for document in documents {
            #expect(throws: BoundedJSONMemberValidationError.duplicateObjectMember) {
                try validate(document)
            }
        }
    }

    @Test func scopesIdentityPerObjectWithoutCaseOrCompatibilityFolding() throws {
        try validate(#"{"left":{"a":1},"right":{"\u0061":2}}"#)
        try validate(#"{"A":1,"a":2}"#)
        try validate(#"{"1":1,"①":2}"#)
        try validate(#"{"key":"key","other":"\u006bey"}"#)
    }

    @Test func rejectsCanonicallyEquivalentMemberNamesBeforeSwiftDictionaryCollapse() {
        let documents = [
            #"{"é":1,"e\u0301":2}"#,
            #"{"Å":1,"A\u030A":2}"#,
            #"{"가":1,"\u1100\u1161":2}"#,
        ]

        for document in documents {
            #expect(throws: BoundedJSONMemberValidationError.duplicateObjectMember) {
                try validate(document)
            }
        }
    }

    @Test func rejectsMalformedStringsUnicodeAndRawUTF8() {
        let malformedDocuments = [
            #""\uD800""#,
            #""\uDC00""#,
            #""\uD800\u0041""#,
            #""\uD800x""#,
            #""\uZZZZ""#,
            #""\x20""#,
            #""unterminated"#,
        ]

        for document in malformedDocuments {
            #expect(throws: BoundedJSONMemberValidationError.malformedJSON) {
                try validate(document)
            }
        }

        let invalidByteDocuments = [
            Data([0x22, 0xC0, 0xAF, 0x22]),
            Data([0x22, 0xED, 0xA0, 0x80, 0x22]),
            Data([0x22, 0xF4, 0x90, 0x80, 0x80, 0x22]),
            Data([0x22, 0x1F, 0x22]),
        ]
        for data in invalidByteDocuments {
            #expect(throws: BoundedJSONMemberValidationError.malformedJSON) {
                try BoundedJSONMemberValidator.validate(
                    data,
                    limits: .metadataFile(maximumInputByteCount: data.count)
                )
            }
        }
    }

    @Test func rejectsMalformedStructuralAndNumberGrammar() {
        let malformedDocuments = [
            "",
            " ",
            "+1",
            "01",
            "-",
            "1.",
            ".1",
            "1e",
            "1e+",
            "true false",
            "[1,]",
            "{\"a\":1,}",
            "{\"a\" 1}",
            "{\"a\":1 \"b\":2}",
            "//comment\n0",
            "/*comment*/0",
            "[",
            "{",
        ]

        for document in malformedDocuments {
            #expect(throws: BoundedJSONMemberValidationError.malformedJSON) {
                try validate(document)
            }
        }
    }

    @Test func validatesLargeRawAndEscapeHeavyValuesWithoutDecodedCopies() throws {
        let rawValue = String(repeating: "abcdefgh", count: 32_768)
        try validate(
            "{\"\":\"\(rawValue)\"}",
            limits: limits(maximumDecodedKeyByteCount: 0)
        )

        let escapeUnit = #"\u0061\n\t\/\\"#
        let escapeHeavyValue = String(repeating: escapeUnit, count: 16_384)
        try validate(
            "{\"\":\"\(escapeHeavyValue)\"}",
            limits: limits(maximumDecodedKeyByteCount: 0)
        )
    }

    @Test func enforcesDecodedValueStringBytesAtExactRawAndEscapedBoundaries() throws {
        let rawValue = #""a😀""#
        try validate(
            rawValue,
            limits: limits(maximumDecodedValueStringByteCount: 5)
        )
        #expect(throws: BoundedJSONMemberValidationError.resourceLimitExceeded) {
            try validate(
                rawValue,
                limits: limits(maximumDecodedValueStringByteCount: 4)
            )
        }

        let escapedValue = #""\u0061\uD83D\uDE00""#
        try validate(
            escapedValue,
            limits: limits(maximumDecodedValueStringByteCount: 5)
        )
        #expect(throws: BoundedJSONMemberValidationError.resourceLimitExceeded) {
            try validate(
                escapedValue,
                limits: limits(maximumDecodedValueStringByteCount: 4)
            )
        }

        try validate(
            #"{"four":""}"#,
            limits: limits(maximumDecodedValueStringByteCount: 0)
        )
        #expect(throws: BoundedJSONMemberValidationError.resourceLimitExceeded) {
            try validate(
                #"{"four":"\u0061"}"#,
                limits: limits(maximumDecodedValueStringByteCount: 0)
            )
        }
    }

    @Test func truncatedAndDeterministicallyMutatedInputsNeverTrap() {
        let source = Data(
            #"{"outer":[{"é":"\uD83D\uDE00"},-12.5e+2,true,null]}"#.utf8
        )

        for endIndex in 0...source.count {
            validateWithoutRequiringSuccess(Data(source.prefix(endIndex)))
        }

        var generator = DeterministicGenerator(seed: 0xBAD5EED)
        for _ in 0..<512 {
            var mutation = source
            let index = generator.index(upperBound: mutation.count)
            mutation[index] = UInt8(truncatingIfNeeded: generator.next())
            validateWithoutRequiringSuccess(mutation)
        }
    }

    @Test func enforcesInputAndNestingLimitsAtTheExactBoundary() throws {
        let scalar = Data("0".utf8)
        try BoundedJSONMemberValidator.validate(
            scalar,
            limits: .metadataFile(maximumInputByteCount: scalar.count)
        )
        #expect(throws: BoundedJSONMemberValidationError.inputTooLarge) {
            try BoundedJSONMemberValidator.validate(
                scalar,
                limits: .metadataFile(maximumInputByteCount: scalar.count - 1)
            )
        }

        let depthThree = "[[[0]]]"
        try validate(
            depthThree,
            limits: limits(maximumNestingDepth: 3)
        )
        #expect(throws: BoundedJSONMemberValidationError.resourceLimitExceeded) {
            try validate(
                depthThree,
                limits: limits(maximumNestingDepth: 2)
            )
        }
    }

    @Test func enforcesObjectMemberAndArrayElementLimitsExactly() throws {
        let twoMemberObject = #"{"a":0,"b":1}"#
        try validate(
            twoMemberObject,
            limits: limits(
                maximumMembersPerObject: 2,
                maximumTotalObjectMembers: 2
            )
        )
        #expect(throws: BoundedJSONMemberValidationError.resourceLimitExceeded) {
            try validate(
                twoMemberObject,
                limits: limits(maximumMembersPerObject: 1)
            )
        }

        let membersAcrossObjects = #"[{"a":0},{"b":1}]"#
        try validate(
            membersAcrossObjects,
            limits: limits(maximumTotalObjectMembers: 2)
        )
        #expect(throws: BoundedJSONMemberValidationError.resourceLimitExceeded) {
            try validate(
                membersAcrossObjects,
                limits: limits(maximumTotalObjectMembers: 1)
            )
        }

        let twoElementArray = "[0,1]"
        try validate(
            twoElementArray,
            limits: limits(maximumElementsPerArray: 2)
        )
        #expect(throws: BoundedJSONMemberValidationError.resourceLimitExceeded) {
            try validate(
                twoElementArray,
                limits: limits(maximumElementsPerArray: 1)
            )
        }
    }

    @Test func enforcesTotalValueKeyAndNumberLimitsExactly() throws {
        let rootPlusTwoValues = "[0,1]"
        try validate(
            rootPlusTwoValues,
            limits: limits(maximumTotalValues: 3)
        )
        #expect(throws: BoundedJSONMemberValidationError.resourceLimitExceeded) {
            try validate(
                rootPlusTwoValues,
                limits: limits(maximumTotalValues: 2)
            )
        }

        let fourByteKey = #"{"four":0}"#
        try validate(
            fourByteKey,
            limits: limits(maximumDecodedKeyByteCount: 4)
        )
        #expect(throws: BoundedJSONMemberValidationError.resourceLimitExceeded) {
            try validate(
                fourByteKey,
                limits: limits(maximumDecodedKeyByteCount: 3)
            )
        }

        let escapedOneByteKey = #"{"\u0061":0}"#
        try validate(
            escapedOneByteKey,
            limits: limits(maximumDecodedKeyByteCount: 1)
        )
        #expect(throws: BoundedJSONMemberValidationError.resourceLimitExceeded) {
            try validate(
                escapedOneByteKey,
                limits: limits(maximumDecodedKeyByteCount: 0)
            )
        }

        try validate("123", limits: limits(maximumNumberTokenByteCount: 3))
        #expect(throws: BoundedJSONMemberValidationError.resourceLimitExceeded) {
            try validate("123", limits: limits(maximumNumberTokenByteCount: 2))
        }
        #expect(throws: BoundedJSONMemberValidationError.resourceLimitExceeded) {
            try validate("0", limits: limits(maximumNumberTokenByteCount: 0))
        }
        try validate("true", limits: limits(maximumNumberTokenByteCount: 0))
    }

    @Test func invalidLimitConfigurationFailsWithoutATrap() {
        let invalidLimits = [
            BoundedJSONMemberValidationLimits(maximumInputByteCount: -1),
            BoundedJSONMemberValidationLimits(
                maximumInputByteCount: 1,
                maximumNestingDepth: 65
            ),
            BoundedJSONMemberValidationLimits(
                maximumInputByteCount: 1,
                maximumDecodedValueStringByteCount: -1
            ),
        ]
        for limits in invalidLimits {
            #expect(throws: BoundedJSONMemberValidationError.resourceLimitExceeded) {
                try BoundedJSONMemberValidator.validate(
                    Data("0".utf8),
                    limits: limits
                )
            }
        }
    }

    @Test func resourceAndSyntaxPrecedenceRemainBoundedAndDeterministic() throws {
        let duplicate = Data(#"{"a":0,"a":1}"#.utf8)
        #expect(throws: BoundedJSONMemberValidationError.inputTooLarge) {
            try BoundedJSONMemberValidator.validate(
                duplicate,
                limits: .metadataFile(
                    maximumInputByteCount: duplicate.count - 1
                )
            )
        }

        #expect(throws: BoundedJSONMemberValidationError.resourceLimitExceeded) {
            try validate(
                #"{"a":0,"a":1}"#,
                limits: limits(maximumMembersPerObject: 1)
            )
        }

        #expect(throws: BoundedJSONMemberValidationError.duplicateObjectMember) {
            try validate(#"{"a":0,"a":"#)
        }
    }

    @Test func deterministicRenderedKeysMatchDecodedStringIdentity() throws {
        var generator = DeterministicGenerator(seed: 0xC0DEC0DE)

        for iteration in 0..<128 {
            let keys = (0..<8).map { index in
                "key-\(iteration)-\(index)-\(generator.next() % 10_000)"
            }
            let uniqueMembers = keys.enumerated().map { index, key in
                let encodedKey = renderASCIIKey(
                    key,
                    escapingBits: generator.next()
                )
                return "\"\(encodedKey)\":\(index)"
            }
            try validate("{\(uniqueMembers.joined(separator: ","))}")

            let duplicatedKey = keys[generator.index(upperBound: keys.count)]
            let firstRepresentation = renderASCIIKey(
                duplicatedKey,
                escapingBits: 0
            )
            let secondRepresentation = renderASCIIKey(
                duplicatedKey,
                escapingBits: UInt64.max
            )
            let duplicateDocument = "{\"\(firstRepresentation)\":0,\"\(secondRepresentation)\":1}"
            #expect(throws: BoundedJSONMemberValidationError.duplicateObjectMember) {
                try validate(duplicateDocument)
            }
        }
    }

    @Test func errorsNeverEchoMemberNamesOrSourceContent() {
        let sentinel = "secret-member-sentinel"
        let document = "{\"\(sentinel)\":0,\"\(sentinel)\":1}"

        do {
            try validate(document)
            Issue.record("Expected duplicate member rejection")
        } catch {
            #expect(String(describing: error).contains(sentinel) == false)
            #expect(String(reflecting: error).contains(sentinel) == false)
        }
    }

    private func validate(
        _ document: String,
        limits: BoundedJSONMemberValidationLimits? = nil
    ) throws {
        let data = Data(document.utf8)
        try BoundedJSONMemberValidator.validate(
            data,
            limits: limits ?? .metadataFile(maximumInputByteCount: data.count)
        )
    }

    private func limits(
        maximumNestingDepth: Int = 64,
        maximumMembersPerObject: Int = 1_024,
        maximumTotalObjectMembers: Int = 262_144,
        maximumElementsPerArray: Int = 65_536,
        maximumTotalValues: Int = 524_288,
        maximumDecodedKeyByteCount: Int = 4_096,
        maximumDecodedValueStringByteCount: Int = Int.max,
        maximumNumberTokenByteCount: Int = 256
    ) -> BoundedJSONMemberValidationLimits {
        BoundedJSONMemberValidationLimits(
            maximumInputByteCount: 1_024 * 1_024,
            maximumNestingDepth: maximumNestingDepth,
            maximumMembersPerObject: maximumMembersPerObject,
            maximumTotalObjectMembers: maximumTotalObjectMembers,
            maximumElementsPerArray: maximumElementsPerArray,
            maximumTotalValues: maximumTotalValues,
            maximumDecodedKeyByteCount: maximumDecodedKeyByteCount,
            maximumDecodedValueStringByteCount:
                maximumDecodedValueStringByteCount,
            maximumNumberTokenByteCount: maximumNumberTokenByteCount
        )
    }

    private func validateWithoutRequiringSuccess(_ data: Data) {
        do {
            try BoundedJSONMemberValidator.validate(
                data,
                limits: .metadataFile(maximumInputByteCount: data.count)
            )
        } catch {
            // Rejection is expected for most prefixes and mutations. The
            // invariant under test is that every bounded input returns or
            // throws instead of trapping.
        }
    }

    private func renderASCIIKey(
        _ key: String,
        escapingBits: UInt64
    ) -> String {
        key.utf8.enumerated().map { index, byte in
            let shouldEscape = (escapingBits >> UInt64(index % 64)) & 1 == 1
            if shouldEscape {
                return String(format: "\\u%04X", UInt32(byte))
            }
            return String(decoding: [byte], as: UTF8.self)
        }.joined()
    }
}

private struct DeterministicGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }

    mutating func index(upperBound: Int) -> Int {
        Int(next() % UInt64(upperBound))
    }
}
