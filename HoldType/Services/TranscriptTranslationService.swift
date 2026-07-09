//
//  TranscriptTranslationService.swift
//  HoldType
//
//  Created by Codex on 7/5/26.
//

import Foundation
import HoldTypeDomain

protocol TranscriptTranslationServing {
    func translate(
        _ transcript: String,
        settings: AppSettings,
        credential: OpenAICredential
    ) async throws -> String
    func cancelActiveTranslation()
}

extension TranscriptTranslationServing {
    func cancelActiveTranslation() {}
}

struct TranscriptTranslationService: TranscriptTranslationServing {
    private let openAITextTranslationService: any OpenAITextTranslationServing

    init(
        openAITextTranslationService: any OpenAITextTranslationServing = OpenAITextTranslationService()
    ) {
        self.openAITextTranslationService = openAITextTranslationService
    }

    func translate(
        _ transcript: String,
        settings: AppSettings,
        credential: OpenAICredential
    ) async throws -> String {
        let normalizedTranscript = AcceptedTranscript.nonEmptyNormalizedText(from: transcript) ?? transcript
        return try await openAITextTranslationService.translate(
            normalizedTranscript,
            settings: settings,
            credential: credential
        )
    }

    func cancelActiveTranslation() {
        openAITextTranslationService.cancelActiveTranslation()
    }
}
