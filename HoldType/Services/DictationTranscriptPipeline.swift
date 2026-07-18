import Foundation
import HoldTypeDomain
import HoldTypeOpenAI

@MainActor
struct DictationTranscriptPipeline {
    private let textCorrectionService: any TextCorrectionServing
    private let translationService: any TranscriptTranslationServing

    init(
        textCorrectionService: any TextCorrectionServing,
        translationService: any TranscriptTranslationServing
    ) {
        self.textCorrectionService = textCorrectionService
        self.translationService = translationService
    }

    func cancelActivePostProcessing() {
        textCorrectionService.cancelActiveCorrection()
        translationService.cancelActiveTranslation()
    }

    func correctedTranscriptText(
        from transcript: AcceptedTranscript,
        settings: AppSettings,
        credential: OpenAICredential
    ) async -> String {
        let request = TextCorrectionRequest(
            acceptedTranscript: transcript,
            correctionConfiguration: settings.textCorrectionConfiguration,
            postProcessingConfiguration: settings.transcriptPostProcessingConfiguration
        )
        do {
            return try await textCorrectionService.correct(
                request,
                credential: credential
            )
        } catch {
            return transcript.text
        }
    }

    func transcriptionSettings(
        for intent: DictationOutputIntent,
        settings: AppSettings
    ) -> AppSettings {
        guard intent == .translate,
              settings.translationShortcutEnabled,
              settings.translationSourceMode == .override,
              settings.isTranslationSourceConfigurationValid else {
            return settings
        }

        var transcriptionSettings = settings
        transcriptionSettings.language = settings.translationSourceLanguage
        transcriptionSettings.customLanguageCode = settings.customTranslationSourceLanguageCode
        return transcriptionSettings
    }

    func makeAudioTranscriptionRequest(
        audioFileURL: URL,
        settings: AppSettings,
        context: TranscriptionPromptContext?
    ) throws -> AudioTranscriptionRequest {
        do {
            return try settings.audioTranscriptionRequest(
                audioFileURL: audioFileURL,
                context: context
            )
        } catch AudioTranscriptionRequest.ValidationError.invalidCustomLanguageCode(let code) {
            throw OpenAITranscriptionServiceError.invalidRecording(
                .invalidCustomLanguageCode(code)
            )
        }
    }

    func postActionTranscriptText(
        from transcript: String,
        intent: DictationOutputIntent,
        settings: AppSettings,
        credential: OpenAICredential
    ) async throws -> String {
        guard intent == .translate, settings.translationShortcutEnabled else {
            return transcript
        }

        guard settings.canRunTranslation else {
            throw OpenAITextTranslationServiceError.invalidLanguageConfiguration
        }

        let acceptedTranscript: AcceptedTranscript
        do {
            acceptedTranscript = try AcceptedTranscript(rawText: transcript)
        } catch {
            throw OpenAITextTranslationServiceError.emptyTranslation
        }
        let request = TextTranslationRequest(
            acceptedTranscript: acceptedTranscript,
            translationConfiguration: settings.translationConfiguration,
            transcriptionConfiguration: settings.transcriptionConfiguration
        )
        let translatedTranscript = try await translationService.translate(
            request,
            credential: credential
        )
        guard let acceptedTranslation = AcceptedTranscript.nonEmptyNormalizedText(
            from: translatedTranscript
        ) else {
            throw OpenAITextTranslationServiceError.emptyTranslation
        }

        return finalTranslatedTranscriptText(acceptedTranslation, settings: settings)
    }

    private func finalTranslatedTranscriptText(
        _ transcript: String,
        settings: AppSettings
    ) -> String {
        guard settings.localTextCleanupEnabled else {
            return transcript
        }

        return TranscriptTextPostProcessor.normalizedInformalTypography(from: transcript)
    }
}
