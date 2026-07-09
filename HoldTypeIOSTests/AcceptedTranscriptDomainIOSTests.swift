import HoldTypeDomain
import Testing

struct AcceptedTranscriptDomainIOSTests {
    @Test func packageNormalizesAcceptedTextOnIOS() throws {
        let transcript = try AcceptedTranscript(rawText: "  Accepted on iOS.  \n")

        #expect(transcript.text == "Accepted on iOS.")
    }

    @Test func packageRejectsEmptyAcceptedTextOnIOS() {
        #expect(throws: AcceptedTranscript.ValidationError.emptyText) {
            _ = try AcceptedTranscript(rawText: " \n\t ")
        }
    }
}
