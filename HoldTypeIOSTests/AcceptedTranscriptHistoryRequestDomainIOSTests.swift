import Foundation
import HoldTypeDomain
import Testing

struct AcceptedTranscriptHistoryRequestDomainIOSTests {
    @Test func publicRuntimeRequestWorksThroughANormalIOSImport() throws {
        let cachedAudioFileURL = URL(fileURLWithPath: "/tmp/ios-accepted-history.m4a")
        let request = AcceptedTranscriptHistoryRequest(
            acceptedTranscript: try AcceptedTranscript(rawText: "  Accepted on iOS.\n"),
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "  ios-transcribe  ",
                language: .custom,
                customLanguageCode: " PT ",
                freeformPrompt: "not retained by the request"
            ),
            retentionConfiguration: RetentionConfiguration(
                historyEnabled: false,
                recordingCachePolicy: .keepLast(10)
            ),
            audioDuration: -7.25,
            cachedAudioFileURL: cachedAudioFileURL
        )

        #expect(request.acceptedTranscript.text == "Accepted on iOS.")
        #expect(request.transcriptionModel == "ios-transcribe")
        #expect(request.languageCode == "pt")
        #expect(request.audioDuration == -7.25)
        #expect(request.cachedAudioFileURL == cachedAudioFileURL)
        #expect(request.historyEnabled == false)
        requireSendable(AcceptedTranscriptHistoryRequest.self)
        #expect(((request as Any) is any Encodable) == false)
        #expect(((request as Any) is any Decodable) == false)
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
