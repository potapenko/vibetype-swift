//
//  TranscriptTextCorrectionService.swift
//  HoldType
//
//  Created by Codex on 7/5/26.
//

import Foundation
import HoldTypeDomain

protocol TextCorrectionServing {
    func correct(
        _ transcript: String,
        settings: AppSettings,
        credential: OpenAICredential
    ) async throws -> String
    func cancelActiveCorrection()
}

extension TextCorrectionServing {
    func cancelActiveCorrection() {}
}

struct TranscriptTextCorrectionService: TextCorrectionServing {
    private let openAITextCorrectionService: any OpenAITextCorrectionServing
    private let localPostProcessor: TranscriptTextPostProcessor

    init(
        openAITextCorrectionService: any OpenAITextCorrectionServing = OpenAITextCorrectionService(),
        localPostProcessor: TranscriptTextPostProcessor = TranscriptTextPostProcessor()
    ) {
        self.openAITextCorrectionService = openAITextCorrectionService
        self.localPostProcessor = localPostProcessor
    }

    func correct(
        _ transcript: String,
        settings: AppSettings,
        credential: OpenAICredential
    ) async throws -> String {
        let normalizedTranscript = AcceptedTranscript.nonEmptyNormalizedText(from: transcript) ?? transcript
        var correctedText = normalizedTranscript

        if settings.textCorrectionEnabled {
            do {
                let openAIText = try await openAITextCorrectionService.correct(
                    normalizedTranscript,
                    settings: settings,
                    credential: credential
                )

                if Self.isSafeCorrection(original: normalizedTranscript, corrected: openAIText) {
                    correctedText = openAIText
                }
            } catch {
                correctedText = normalizedTranscript
            }
        }

        return localPostProcessor.process(correctedText, settings: settings, fallback: normalizedTranscript)
    }

    func cancelActiveCorrection() {
        openAITextCorrectionService.cancelActiveCorrection()
    }

    private static func isSafeCorrection(original: String, corrected: String) -> Bool {
        guard let normalizedCorrection = AcceptedTranscript.nonEmptyNormalizedText(from: corrected) else {
            return false
        }

        let originalCount = original.count
        let correctedCount = normalizedCorrection.count
        guard originalCount >= 20 else {
            return true
        }

        return correctedCount >= max(1, originalCount / 3) && correctedCount <= originalCount * 3
    }
}

struct TranscriptTextPostProcessor {
    private static let quoteTranslations: [Character: String] = [
        "«": "\"",
        "»": "\"",
        "“": "\"",
        "”": "\"",
        "„": "\"",
        "‟": "\"",
        "‘": "'",
        "’": "'",
        "‚": "'",
        "‛": "'",
        "`": "'",
        "´": "'",
        "…": "...",
        "\u{00A0}": " ",
        "\u{202F}": " ",
        "\u{2009}": " ",
        "\u{2060}": "",
    ]

    private static let dashCharacters = "\u{2012}\u{2013}\u{2014}\u{2015}\u{2212}\u{2011}"
    private let emojiCommandReplacementService: EmojiCommandReplacementService

    init(emojiCommandReplacementService: EmojiCommandReplacementService = EmojiCommandReplacementService()) {
        self.emojiCommandReplacementService = emojiCommandReplacementService
    }

    func process(_ text: String, settings: AppSettings, fallback: String? = nil) -> String {
        let originalText = fallback ?? text
        var processedText = text

        if settings.localTextCleanupEnabled {
            processedText = Self.normalizeInformalTypography(processedText)
        }

        processedText = emojiCommandReplacementService.process(
            processedText,
            commandSets: settings.enabledEmojiCommandSets,
            customCommands: settings.enabledCustomEmojiCommands
        )

        for rule in settings.enabledTextReplacementRules {
            processedText = processedText.replacingOccurrences(
                of: rule.search,
                with: rule.replacement,
                options: [.caseInsensitive]
            )
        }

        return AcceptedTranscript.nonEmptyNormalizedText(from: processedText)
            ?? AcceptedTranscript.nonEmptyNormalizedText(from: originalText)
            ?? originalText
    }

    static func normalizeInformalTypography(_ text: String) -> String {
        let translatedText = translateCharacters(in: text)
        let dashNormalizedText = normalizeDashes(in: translatedText)
        return normalizeSpacing(in: dashNormalizedText)
    }

    static func normalizedInformalTypography(from text: String, fallback: String? = nil) -> String {
        let originalText = fallback ?? text
        return AcceptedTranscript.nonEmptyNormalizedText(from: normalizeInformalTypography(text))
            ?? AcceptedTranscript.nonEmptyNormalizedText(from: originalText)
            ?? originalText
    }

    private static func translateCharacters(in text: String) -> String {
        var translatedText = ""

        for character in text {
            translatedText.append(quoteTranslations[character] ?? String(character))
        }

        return translatedText
    }

    private static func normalizeDashes(in text: String) -> String {
        var normalizedText = text
        normalizedText = replacingMatches(
            in: normalizedText,
            pattern: "(?<=\\d)\\s*[\(dashCharacters)]\\s*(?=\\d)",
            with: "-"
        )
        normalizedText = replacingMatches(
            in: normalizedText,
            pattern: "(?m)^\\s*[\(dashCharacters)]\\s*",
            with: "- "
        )
        normalizedText = replacingMatches(
            in: normalizedText,
            pattern: "(?<=\\S)\\s*[\(dashCharacters)]\\s*(?=\\S)",
            with: " - "
        )
        return replacingMatches(in: normalizedText, pattern: "[\(dashCharacters)]", with: "-")
    }

    private static func normalizeSpacing(in text: String) -> String {
        var normalizedText = replacingMatches(in: text, pattern: "[ \\t]+", with: " ")
        normalizedText = replacingMatches(in: normalizedText, pattern: " *\\n", with: "\n")
        return replacingMatches(in: normalizedText, pattern: "\\n{3,}", with: "\n\n")
    }

    private static func replacingMatches(in text: String, pattern: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: replacement
        )
    }
}
