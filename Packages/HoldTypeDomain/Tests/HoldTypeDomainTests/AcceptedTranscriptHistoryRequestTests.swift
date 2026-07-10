import Foundation
import Testing
@testable import HoldTypeDomain

struct AcceptedTranscriptHistoryRequestTests {
    @Test func preservesEveryAcceptedHistoryFieldAndSupportsValueEquality() throws {
        let acceptedTranscript = try AcceptedTranscript(rawText: "  Accepted text\n")
        let cachedAudioFileURL = URL(fileURLWithPath: "/tmp/accepted-history.m4a")
        let request = AcceptedTranscriptHistoryRequest(
            acceptedTranscript: acceptedTranscript,
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "  gpt-4o-mini-transcribe  ",
                language: .custom,
                customLanguageCode: " PT ",
                freeformPrompt: "Must not be retained"
            ),
            retentionConfiguration: RetentionConfiguration(
                historyEnabled: false,
                recordingCachePolicy: .keepLast(10)
            ),
            audioDuration: -2.5,
            cachedAudioFileURL: cachedAudioFileURL
        )

        #expect(request.acceptedTranscript.text == "Accepted text")
        #expect(request.transcriptionModel == "gpt-4o-mini-transcribe")
        #expect(request.languageCode == "pt")
        #expect(request.audioDuration == -2.5)
        #expect(request.cachedAudioFileURL == cachedAudioFileURL)
        #expect(request.historyEnabled == false)
        #expect(
            request == AcceptedTranscriptHistoryRequest(
                acceptedTranscript: acceptedTranscript,
                transcriptionConfiguration: TranscriptionConfiguration(
                    model: "gpt-4o-mini-transcribe",
                    language: .custom,
                    customLanguageCode: "pt"
                ),
                retentionConfiguration: RetentionConfiguration(
                    historyEnabled: false,
                    recordingCachePolicy: .unlimited
                ),
                audioDuration: -2.5,
                cachedAudioFileURL: cachedAudioFileURL
            )
        )
    }

    @Test func blankModelFallsBackAndEveryLanguageModeResolvesNormally() throws {
        let acceptedTranscript = try AcceptedTranscript(rawText: "Accepted")

        let automatic = makeRequest(
            acceptedTranscript: acceptedTranscript,
            transcriptionConfiguration: TranscriptionConfiguration(
                model: " \n ",
                language: .automatic
            )
        )
        let fixed = makeRequest(
            acceptedTranscript: acceptedTranscript,
            transcriptionConfiguration: TranscriptionConfiguration(language: .german)
        )
        let custom = makeRequest(
            acceptedTranscript: acceptedTranscript,
            transcriptionConfiguration: TranscriptionConfiguration(
                language: .custom,
                customLanguageCode: " UKR "
            )
        )

        #expect(automatic.transcriptionModel == TranscriptionConfiguration.defaultModel)
        #expect(automatic.languageCode == nil)
        #expect(fixed.languageCode == "de")
        #expect(custom.languageCode == "ukr")
    }

    @Test func cachePolicyAloneControlsWhetherTheTransientURLIsKept() throws {
        let acceptedTranscript = try AcceptedTranscript(rawText: "Accepted")
        let cachedAudioFileURL = URL(fileURLWithPath: "/tmp/cache-policy.m4a")

        let deleted = makeRequest(
            acceptedTranscript: acceptedTranscript,
            retentionConfiguration: RetentionConfiguration(
                historyEnabled: true,
                recordingCachePolicy: .deleteImmediately
            ),
            cachedAudioFileURL: cachedAudioFileURL
        )
        let bounded = makeRequest(
            acceptedTranscript: acceptedTranscript,
            retentionConfiguration: RetentionConfiguration(
                historyEnabled: false,
                recordingCachePolicy: .keepLast(10)
            ),
            cachedAudioFileURL: cachedAudioFileURL
        )
        let unlimited = makeRequest(
            acceptedTranscript: acceptedTranscript,
            retentionConfiguration: RetentionConfiguration(
                historyEnabled: true,
                recordingCachePolicy: .unlimited
            ),
            cachedAudioFileURL: cachedAudioFileURL
        )

        #expect(deleted.cachedAudioFileURL == nil)
        #expect(bounded.cachedAudioFileURL == cachedAudioFileURL)
        #expect(bounded.historyEnabled == false)
        #expect(unlimited.cachedAudioFileURL == cachedAudioFileURL)
    }

    @Test func optionalDurationIsPreservedWithoutNewValidation() throws {
        let acceptedTranscript = try AcceptedTranscript(rawText: "Accepted")
        let absent = makeRequest(
            acceptedTranscript: acceptedTranscript,
            audioDuration: nil
        )
        let nonFinite = makeRequest(
            acceptedTranscript: acceptedTranscript,
            audioDuration: .infinity
        )

        #expect(absent.audioDuration == nil)
        #expect(nonFinite.audioDuration == .infinity)
    }

    @Test func publicValueIsSendableButNotATransportContract() throws {
        let request = makeRequest(
            acceptedTranscript: try AcceptedTranscript(rawText: "Accepted")
        )

        requireSendable(AcceptedTranscriptHistoryRequest.self)
        #expect(((request as Any) is any Encodable) == false)
        #expect(((request as Any) is any Decodable) == false)
    }

    private func makeRequest(
        acceptedTranscript: AcceptedTranscript,
        transcriptionConfiguration: TranscriptionConfiguration = .defaults,
        retentionConfiguration: RetentionConfiguration = .defaults,
        audioDuration: TimeInterval? = 1.5,
        cachedAudioFileURL: URL? = nil
    ) -> AcceptedTranscriptHistoryRequest {
        AcceptedTranscriptHistoryRequest(
            acceptedTranscript: acceptedTranscript,
            transcriptionConfiguration: transcriptionConfiguration,
            retentionConfiguration: retentionConfiguration,
            audioDuration: audioDuration,
            cachedAudioFileURL: cachedAudioFileURL
        )
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
