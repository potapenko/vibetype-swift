import Testing
@testable import HoldTypeDomain

struct AcceptedTranscriptTests {
    @Test func trimsSurroundingWhitespaceAndNewlines() throws {
        let transcript = try AcceptedTranscript(
            rawText: "  Ship  the portable slice.\nKeep this line.  \n"
        )

        #expect(transcript.text == "Ship  the portable slice.\nKeep this line.")
    }

    @Test func rejectsWhitespaceOnlyText() {
        #expect(throws: AcceptedTranscript.ValidationError.emptyText) {
            _ = try AcceptedTranscript(rawText: " \n\t ")
        }
    }

    @Test func returnsNilOnlyForEmptyNormalizedText() {
        #expect(AcceptedTranscript.nonEmptyNormalizedText(from: "  Accepted  ") == "Accepted")
        #expect(AcceptedTranscript.nonEmptyNormalizedText(from: "\n\t") == nil)
    }
}
