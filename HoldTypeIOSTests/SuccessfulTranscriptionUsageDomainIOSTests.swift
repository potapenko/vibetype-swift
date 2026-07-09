import Foundation
import HoldTypeDomain
import Testing

@MainActor
struct SuccessfulTranscriptionUsageDomainIOSTests {
    @Test func publicUsageHandoffWorksThroughANormalIOSImport() throws {
        let transcriptionID = try #require(
            UUID(uuidString: "F75485B4-C1BA-47C2-BDE5-F74A56D0A5CE")
        )
        let usage = try SuccessfulTranscriptionUsage(
            transcriptionID: transcriptionID,
            model: " GPT-4O-Transcribe ",
            audioDuration: 18
        )
        let spy = IOSSuccessfulTranscriptionUsageRecorderSpy()
        let recorder: any TranscriptionUsageRecording = spy

        recorder.recordSuccessfulTranscriptionUsage(usage)

        #expect(usage.transcriptionID == transcriptionID)
        #expect(usage.model == "gpt-4o-transcribe")
        #expect(usage.audioDuration == 18)
        #expect(spy.calls == [usage])
        requireSendable(SuccessfulTranscriptionUsage.self)
        #expect(((usage as Any) is any Encodable) == false)
        #expect(((usage as Any) is any Decodable) == false)
    }

    @Test func invalidDurationFailsThroughThePublicIOSContract() {
        #expect(throws: SuccessfulTranscriptionUsage.ValidationError.invalidAudioDuration) {
            _ = try SuccessfulTranscriptionUsage(
                transcriptionID: UUID(),
                model: "gpt-4o-transcribe",
                audioDuration: .nan
            )
        }
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}

@MainActor
private final class IOSSuccessfulTranscriptionUsageRecorderSpy: TranscriptionUsageRecording {
    private(set) var calls: [SuccessfulTranscriptionUsage] = []

    func recordSuccessfulTranscriptionUsage(_ usage: SuccessfulTranscriptionUsage) {
        calls.append(usage)
    }
}
