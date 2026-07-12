import Foundation
import Testing
@testable import HoldTypePersistence

struct IOSProviderConsentWireCodecTests {
    @Test func canonicalV1EncodingIsExactAndRoundTrips() throws {
        let record = IOSProviderConsentRecord(
            epochID: UUID(uuidString: "01234567-89AB-CDEF-8123-456789ABCDEF")!,
            revision: 7,
            disclosureVersion: 1,
            state: .accepted,
            decisionAt: try fixtureDate("2026-07-12T16:05:04.321Z")
        )

        let data = try IOSProviderConsentWireCodec.encode(record)

        #expect(
            String(decoding: data, as: UTF8.self) ==
                #"{"decisionAt":"2026-07-12T16:05:04.321Z","disclosureVersion":1,"epochID":"01234567-89ab-cdef-8123-456789abcdef","revision":7,"schemaVersion":1,"state":"accepted"}"#
        )
        #expect(try IOSProviderConsentWireCodec.decode(data) == record)
        #expect(data.count < IOSProviderConsentStoragePolicy.maximumByteCount)
    }

    @Test func withdrawnIsTheOnlyOtherSupportedState() throws {
        let accepted = canonicalJSON()
        let withdrawn = accepted.replacingOccurrences(
            of: #""state":"accepted""#,
            with: #""state":"withdrawn""#
        )

        #expect(
            try IOSProviderConsentWireCodec.decode(Data(withdrawn.utf8)).state
                == .withdrawn
        )
    }

    @Test func exactFieldSetAndSupportedSchemaAreRequired() {
        let fixtures = [
            #"{}"#,
            canonicalJSON().replacingOccurrences(
                of: #", "state":"accepted""#.replacingOccurrences(
                    of: " ",
                    with: ""
                ),
                with: ""
            ),
            canonicalJSON().dropLast().description + #", "future":true}"#,
            canonicalJSON().replacingOccurrences(
                of: #""schemaVersion":1"#,
                with: #""schemaVersion":2"#
            ),
            canonicalJSON().replacingOccurrences(
                of: #""schemaVersion":1"#,
                with: #""schemaVersion":true"#
            ),
            canonicalJSON().replacingOccurrences(
                of: #""schemaVersion":1"#,
                with: #""schemaVersion":1.0"#
            ),
            canonicalJSON().replacingOccurrences(
                of: #""schemaVersion":1"#,
                with: #""schemaVersion":1e0"#
            ),
        ]

        for fixture in fixtures {
            expectDecodeFailure(Data(fixture.utf8))
        }
    }

    @Test func numericRangesAndTypesAreStrict() {
        let replacements: [(String, String)] = [
            (#""revision":7"#, #""revision":0"#),
            (#""revision":7"#, #""revision":-1"#),
            (#""revision":7"#, #""revision":7.0"#),
            (#""revision":7"#, #""revision":true"#),
            (#""revision":7"#, #""revision":9223372036854775808"#),
            (#""disclosureVersion":1"#, #""disclosureVersion":0"#),
            (#""disclosureVersion":1"#, #""disclosureVersion":1.0"#),
            (#""disclosureVersion":1"#, #""disclosureVersion":"1"#),
        ]

        for (source, replacement) in replacements {
            expectDecodeFailure(
                Data(
                    canonicalJSON()
                        .replacingOccurrences(of: source, with: replacement)
                        .utf8
                )
            )
        }
    }

    @Test func UUIDStateAndTimestampMustBeCanonical() {
        let replacements: [(String, String)] = [
            (
                "01234567-89ab-cdef-8123-456789abcdef",
                "01234567-89AB-CDEF-8123-456789ABCDEF"
            ),
            (
                "01234567-89ab-cdef-8123-456789abcdef",
                "{01234567-89ab-cdef-8123-456789abcdef}"
            ),
            (#""state":"accepted""#, #""state":"pending""#),
            ("2026-07-12T16:05:04.321Z", "2026-07-12T16:05:04Z"),
            ("2026-07-12T16:05:04.321Z", "2026-07-12T16:05:04.321+00:00"),
            ("2026-07-12T16:05:04.321Z", "2026-02-30T16:05:04.321Z"),
            ("2026-07-12T16:05:04.321Z", "2026-07-12T16:05:60.000Z"),
        ]

        for (source, replacement) in replacements {
            expectDecodeFailure(
                Data(
                    canonicalJSON()
                        .replacingOccurrences(of: source, with: replacement)
                        .utf8
                )
            )
        }
    }

    @Test func malformedUTF8BOMDuplicatesAndCanonicalKeyAliasesFailClosed() {
        let duplicate = canonicalJSON().replacingOccurrences(
            of: #""schemaVersion":1"#,
            with: #""schemaVersion":1,"schema\u0056ersion":1"#
        )
        let canonicalAlias = canonicalJSON().dropLast().description
            + #", "é":1,"e\u0301":2}"#
        let fixtures = [
            Data([0xFF, 0xFE, 0x00]),
            Data(("\u{FEFF}" + canonicalJSON()).utf8),
            Data(duplicate.utf8),
            Data(canonicalAlias.utf8),
            Data("[]".utf8),
            Data("null".utf8),
            Data(#""record""#.utf8),
        ]

        for fixture in fixtures {
            expectDecodeFailure(fixture)
        }
    }

    @Test func byteLimitFailsBeforeSemanticInterpretation() {
        let oversized = Data(
            repeating: UInt8(ascii: " "),
            count: IOSProviderConsentStoragePolicy.maximumByteCount + 1
        )

        #expect(throws: IOSProviderConsentWireCodecError.sourceTooLarge) {
            try IOSProviderConsentWireCodec.decode(oversized)
        }
    }

    @Test func canonicalDateRoundsToThePersistedMillisecond() throws {
        let source = Date(timeIntervalSince1970: 1_752_336_304.321_987)
        let canonical = try IOSProviderConsentWireCodec.canonicalDate(source)
        let record = IOSProviderConsentRecord(
            epochID: UUID(),
            revision: 1,
            disclosureVersion: 1,
            state: .accepted,
            decisionAt: canonical
        )

        #expect(try IOSProviderConsentWireCodec.decode(
            IOSProviderConsentWireCodec.encode(record)
        ) == record)
        #expect(canonical != source)
    }

    @Test func storageLocationAndPolicyMatchTheAppPrivateContract() {
        let support = URL(
            fileURLWithPath: "/private/app/Library/Application Support",
            isDirectory: true
        )

        #expect(
            IOSProviderConsentStorageLocation.fileURL(in: support).path ==
                "/private/app/Library/Application Support/HoldType/ios-openai-provider-consent.json"
        )
        #expect(IOSProviderConsentStoragePolicy.maximumByteCount == 4_096)
        #expect(!IOSProviderConsentStoragePolicy.excludesFromBackup)
        #expect(IOSStrictProtectedRecordConfiguration.providerConsent.maximumByteCount == 4_096)
        #expect(
            IOSStrictProtectedRecordConfiguration.providerConsent.marker?.name ==
                "com.holdtype.ios.provider-consent"
        )
    }

    @Test func runtimeValuesAndErrorsAreRedacted() throws {
        let canary = "PRIVATE-CONSENT-CANARY"
        let record = IOSProviderConsentRecord(
            epochID: UUID(),
            revision: 1,
            disclosureVersion: 1,
            state: .accepted,
            decisionAt: try fixtureDate("2026-07-12T16:05:04.321Z")
        )
        let values: [Any] = [
            record,
            IOSProviderConsentWireCodecError.invalidRecord,
            IOSProviderConsentError.commitUncertain,
            IOSProviderConsentStatus.reviewRequired,
            IOSProviderConsentProviderStage.transcription,
        ]

        for value in values {
            var rendered = canary
            dump(value, to: &rendered)
            #expect(!String(describing: value).contains(canary))
            #expect(!String(reflecting: value).contains(canary))
            #expect(rendered.filter { $0 == "\n" }.count <= 1)
        }
    }

    private func canonicalJSON() -> String {
        #"{"decisionAt":"2026-07-12T16:05:04.321Z","disclosureVersion":1,"epochID":"01234567-89ab-cdef-8123-456789abcdef","revision":7,"schemaVersion":1,"state":"accepted"}"#
    }

    private func fixtureDate(_ value: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return try #require(formatter.date(from: value))
    }

    private func expectDecodeFailure(_ data: Data) {
        do {
            _ = try IOSProviderConsentWireCodec.decode(data)
            Issue.record("Expected strict provider-consent decoding to fail")
        } catch is IOSProviderConsentWireCodecError {
            // Expected typed, content-free failure.
        } catch {
            Issue.record("Expected the typed provider-consent codec error")
        }
    }
}
