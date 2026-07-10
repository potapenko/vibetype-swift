import HoldTypeOpenAI
import Testing

struct OpenAIProviderServicesIOSTests {
    @Test func publicBoundaryConstructsAllProviderServicesWithoutStartingNetworkWork() {
        let transcription: any OpenAITranscriptionServing = OpenAITranscriptionService()
        let correction: any OpenAITextCorrectionServing = OpenAITextCorrectionService()
        let translation: any OpenAITextTranslationServing = OpenAITextTranslationService()

        transcription.cancelActiveTranscription()
        correction.cancelActiveCorrection()
        translation.cancelActiveTranslation()

        #expect(OpenAITranscriptionServiceError.timedOut.errorDescription != nil)
        #expect(OpenAITextCorrectionServiceError.timedOut.errorDescription != nil)
        #expect(OpenAITextTranslationServiceError.timedOut.errorDescription != nil)
        #expect(
            OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable.errorDescription
                != nil
        )
    }

    @Test func publicConcreteServicesAreSendable() {
        requireSendable(OpenAITranscriptionService.self)
        requireSendable(OpenAITextCorrectionService.self)
        requireSendable(OpenAITextTranslationService.self)
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
