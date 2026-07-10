import Foundation
import Testing
@testable import HoldTypeDomain

struct AudioTranscriptionRequestTests {
    @Test func preservesURLResolvedProviderFieldsAndPromptComposition() throws {
        let composition = promptComposition("Provider prompt")
        let request = try AudioTranscriptionRequest(
            audioFileURL: URL(fileURLWithPath: "/tmp/holdtype-request.m4a"),
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "  custom-transcribe  ",
                language: .custom,
                customLanguageCode: " RU ",
                freeformPrompt: "must not be retained separately"
            ),
            promptComposition: composition
        )

        #expect(request.audioFileURL.path == "/tmp/holdtype-request.m4a")
        #expect(request.model == "custom-transcribe")
        #expect(request.languageCode == "ru")
        #expect(request.promptComposition == composition)
    }

    @Test func blankModelAndAutomaticLanguageResolveToCurrentFallbacks() throws {
        let request = try AudioTranscriptionRequest(
            audioFileURL: URL(fileURLWithPath: "/tmp/automatic.wav"),
            transcriptionConfiguration: TranscriptionConfiguration(
                model: " \n ",
                language: .automatic
            ),
            promptComposition: promptComposition()
        )

        #expect(request.model == TranscriptionConfiguration.defaultModel)
        #expect(request.languageCode == nil)
    }

    @Test func blankCustomLanguageStillFallsBackToAutomatic() throws {
        let request = try AudioTranscriptionRequest(
            audioFileURL: URL(fileURLWithPath: "/tmp/custom.wav"),
            transcriptionConfiguration: TranscriptionConfiguration(
                language: .custom,
                customLanguageCode: " \n "
            ),
            promptComposition: promptComposition()
        )

        #expect(request.languageCode == nil)
    }

    @Test func invalidCustomLanguageFailsWithItsUnmodifiedValue() {
        #expect(throws: AudioTranscriptionRequest.ValidationError.invalidCustomLanguageCode(" en-US ")) {
            _ = try AudioTranscriptionRequest(
                audioFileURL: URL(fileURLWithPath: "/tmp/invalid.wav"),
                transcriptionConfiguration: TranscriptionConfiguration(
                    language: .custom,
                    customLanguageCode: " en-US "
                ),
                promptComposition: promptComposition()
            )
        }
    }

    @Test func equalityIncludesEveryRuntimeInput() throws {
        let first = try AudioTranscriptionRequest(
            audioFileURL: URL(fileURLWithPath: "/tmp/first.m4a"),
            transcriptionConfiguration: TranscriptionConfiguration(language: .english),
            promptComposition: promptComposition("Prompt")
        )
        let differentURL = try AudioTranscriptionRequest(
            audioFileURL: URL(fileURLWithPath: "/tmp/second.m4a"),
            transcriptionConfiguration: TranscriptionConfiguration(language: .english),
            promptComposition: promptComposition("Prompt")
        )
        let differentModel = try AudioTranscriptionRequest(
            audioFileURL: first.audioFileURL,
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "different-model",
                language: .english
            ),
            promptComposition: promptComposition("Prompt")
        )
        let differentLanguage = try AudioTranscriptionRequest(
            audioFileURL: first.audioFileURL,
            transcriptionConfiguration: TranscriptionConfiguration(language: .spanish),
            promptComposition: promptComposition("Prompt")
        )
        let differentPrompt = try AudioTranscriptionRequest(
            audioFileURL: first.audioFileURL,
            transcriptionConfiguration: TranscriptionConfiguration(language: .english),
            promptComposition: promptComposition("Different")
        )

        #expect(first == first)
        #expect(first != differentURL)
        #expect(first != differentModel)
        #expect(first != differentLanguage)
        #expect(first != differentPrompt)
    }

    @Test func publicValueIsSendableButNotATransportContract() throws {
        requireSendable(AudioTranscriptionRequest.self)
        let request = try AudioTranscriptionRequest(
            audioFileURL: URL(fileURLWithPath: "/tmp/request.m4a"),
            transcriptionConfiguration: .defaults,
            promptComposition: promptComposition()
        )

        #expect(((request as Any) is any Encodable) == false)
        #expect(((request as Any) is any Decodable) == false)
    }

    private func promptComposition(_ freeformPrompt: String? = nil) -> TranscriptionPromptComposition {
        TranscriptionPromptComposition(
            resolvedFreeformPrompt: freeformPrompt,
            context: nil,
            emojiCommandsConfiguration: EmojiCommandsConfiguration(isEnabled: false),
            customDictionary: .empty
        )
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
