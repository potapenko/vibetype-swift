import Foundation
import HoldTypeDomain
import Testing

struct AudioTranscriptionRequestDomainIOSTests {
    @Test func publicRuntimeRequestWorksThroughANormalIOSImport() throws {
        let composition = TranscriptionPromptComposition(
            resolvedFreeformPrompt: "Provider prompt",
            context: nil,
            emojiCommandsConfiguration: EmojiCommandsConfiguration(isEnabled: false),
            customDictionary: CustomDictionary(entries: ["HoldType"])
        )
        let request = try AudioTranscriptionRequest(
            audioFileURL: URL(fileURLWithPath: "/tmp/ios-request.m4a"),
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "  ios-transcribe  ",
                language: .custom,
                customLanguageCode: " PT ",
                freeformPrompt: "not retained outside composition"
            ),
            promptComposition: composition
        )

        #expect(request.audioFileURL.path == "/tmp/ios-request.m4a")
        #expect(request.model == "ios-transcribe")
        #expect(request.languageCode == "pt")
        #expect(request.promptComposition == composition)
        requireSendable(AudioTranscriptionRequest.self)
        #expect(((request as Any) is any Encodable) == false)
        #expect(((request as Any) is any Decodable) == false)
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
