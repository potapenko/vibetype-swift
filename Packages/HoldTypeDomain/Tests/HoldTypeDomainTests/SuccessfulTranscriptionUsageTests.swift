import Foundation
import Testing
import HoldTypeDomain

@MainActor
struct SuccessfulTranscriptionUsageTests {
    @Test func normalizesOnlyTheApprovedModelEdgesAndCase() throws {
        let transcriptionID = try #require(
            UUID(uuidString: "CD676B1A-6FD2-4244-9A70-BF865A7D6F40")
        )
        let usage = try SuccessfulTranscriptionUsage(
            transcriptionID: transcriptionID,
            model: "  GPT-4O-Mini-Transcribe \n",
            audioDuration: 42.5
        )

        #expect(usage.transcriptionID == transcriptionID)
        #expect(usage.model == "gpt-4o-mini-transcribe")
        #expect(usage.audioDuration == 42.5)
    }

    @Test func rejectsEmptyModelsWithATypedValidationError() {
        for model in ["", " \n\t "] {
            #expect(throws: SuccessfulTranscriptionUsage.ValidationError.emptyModel) {
                _ = try SuccessfulTranscriptionUsage(
                    transcriptionID: UUID(),
                    model: model,
                    audioDuration: 1
                )
            }
        }
    }

    @Test func rejectsEveryNonPositiveOrNonFiniteDuration() {
        let invalidDurations: [TimeInterval] = [
            0,
            -1,
            .nan,
            .infinity,
            -.infinity,
        ]

        for duration in invalidDurations {
            #expect(throws: SuccessfulTranscriptionUsage.ValidationError.invalidAudioDuration) {
                _ = try SuccessfulTranscriptionUsage(
                    transcriptionID: UUID(),
                    model: "gpt-4o-transcribe",
                    audioDuration: duration
                )
            }
        }
    }

    @Test func publicValueIsSendableButNotAPersistenceContract() throws {
        requireSendable(SuccessfulTranscriptionUsage.self)
        let usage = try SuccessfulTranscriptionUsage(
            transcriptionID: UUID(),
            model: "gpt-4o-transcribe",
            audioDuration: 1
        )

        #expect(((usage as Any) is any Encodable) == false)
        #expect(((usage as Any) is any Decodable) == false)
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
