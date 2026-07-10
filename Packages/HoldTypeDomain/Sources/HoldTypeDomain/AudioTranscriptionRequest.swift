import Foundation

public struct AudioTranscriptionRequest: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case invalidCustomLanguageCode(String)
    }

    public let audioFileURL: URL
    public let model: String
    public let languageCode: String?
    public let promptComposition: TranscriptionPromptComposition

    public init(
        audioFileURL: URL,
        transcriptionConfiguration: TranscriptionConfiguration,
        promptComposition: TranscriptionPromptComposition
    ) throws {
        switch transcriptionConfiguration.customLanguageCodeValidation {
        case .invalid:
            throw ValidationError.invalidCustomLanguageCode(
                transcriptionConfiguration.customLanguageCode
            )
        case .notRequired, .emptyFallsBackToAutomatic, .valid:
            break
        }

        self.audioFileURL = audioFileURL
        model = transcriptionConfiguration.resolvedModel
        languageCode = transcriptionConfiguration.resolvedLanguageCode
        self.promptComposition = promptComposition
    }
}
