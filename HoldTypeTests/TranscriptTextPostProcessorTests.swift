//
//  TranscriptTextPostProcessorTests.swift
//  HoldTypeTests
//
//  Created by Codex on 7/5/26.
//

import HoldTypeDomain
import Testing
@testable import HoldType

struct TranscriptTextPostProcessorTests {

    @Test func localCleanupNormalizesInformalTypography() {
        let input = """
        “Hello”—world…\u{00A0}5 – 7
        — bullet


        Done
        """

        let output = TranscriptTextPostProcessor.normalizeInformalTypography(input)

        #expect(
            output ==
                """
                "Hello" - world... 5-7
                - bullet

                Done
                """
        )
    }

    @Test func replacementRulesRunInOrderAfterLocalCleanup() {
        var settings = AppSettings.defaults
        settings.localTextCleanupEnabled = true
        settings.textReplacementRules = [
            TextReplacementRule(search: "AI-looking", replacement: "plain"),
            TextReplacementRule(search: "plain", replacement: "human"),
        ]

        let output = TranscriptTextPostProcessor().process(
            "“AI-looking”—text",
            settings: settings
        )

        #expect(output == "\"human\" - text")
    }

    @Test func replacementRulesIgnoreSourceTextCase() {
        var settings = AppSettings.defaults
        settings.localTextCleanupEnabled = false
        settings.textReplacementRules = [
            TextReplacementRule(search: "openai", replacement: "OpenAI"),
            TextReplacementRule(search: "hello", replacement: "hi"),
        ]

        let output = TranscriptTextPostProcessor().process(
            "OPENAI and OpenAi say HELLO.",
            settings: settings
        )

        #expect(output == "OpenAI and OpenAI say hi.")
    }

    @Test func emojiCommandsReplaceActiveEnglishAliases() {
        var settings = AppSettings.defaults
        settings.localTextCleanupEnabled = false
        settings.enabledEmojiCommandSetIDs = ["en"]

        let output = TranscriptTextPostProcessor().process(
            "Nice emoji smile. emoji angry. эмодзи огонь!",
            settings: settings
        )

        #expect(output == "Nice 🙂. 😠. эмодзи огонь!")
    }

    @Test func emojiCommandsReplaceInlineRussianVariantsWithPunctuation() {
        var settings = AppSettings.defaults
        settings.localTextCleanupEnabled = false
        settings.enabledEmojiCommandSetIDs = ["ru"]

        let output = TranscriptTextPostProcessor().process(
            "Проба ввода с эмодзи. Эмодзи смайл.эмодзи улыбка.",
            settings: settings
        )

        #expect(output == "Проба ввода с эмодзи. 🙂.🙂.")
    }

    @Test func emojiCommandsRequireCanonicalRussianPrefix() {
        var settings = AppSettings.defaults
        settings.localTextCleanupEnabled = false
        settings.enabledEmojiCommandSetIDs = ["ru"]

        let output = TranscriptTextPostProcessor().process(
            "эмодзи сердце. эмоции сердце. эмоджи сердце. смайлик.",
            settings: settings
        )

        #expect(output == "❤️. эмоции сердце. эмоджи сердце. смайлик.")
    }

    @Test func emojiCommandsReplaceActiveRussianAliasesOnly() {
        var settings = AppSettings.defaults
        settings.localTextCleanupEnabled = false
        settings.enabledEmojiCommandSetIDs = ["ru"]

        let output = TranscriptTextPostProcessor().process(
            "эмодзи смех. эмодзи злой. emoji fire.",
            settings: settings
        )

        #expect(output == "😂. 😠. emoji fire.")
    }

    @Test func emojiCommandsAllowPunctuationBetweenCommandWords() {
        var settings = AppSettings.defaults
        settings.localTextCleanupEnabled = false

        let output = TranscriptTextPostProcessor().process(
            "Ship it: emoji, smile and emoji. fire.",
            settings: settings
        )

        #expect(output == "Ship it: 🙂 and 🔥.")
    }

    @Test func emojiCommandsIgnoreCommandCasing() {
        var englishSettings = AppSettings.defaults
        englishSettings.localTextCleanupEnabled = false
        englishSettings.enabledEmojiCommandSetIDs = ["en"]

        var russianSettings = englishSettings
        russianSettings.enabledEmojiCommandSetIDs = ["ru"]

        var germanSettings = englishSettings
        germanSettings.enabledEmojiCommandSetIDs = ["de"]

        var customSettings = englishSettings
        customSettings.enabledEmojiCommandSetIDs = []
        customSettings.customEmojiCommands = [
            CustomEmojiCommand(emoji: "🚀", command: "Emoji Rocket", aliases: ["Launch Emoji"])
        ]

        let processor = TranscriptTextPostProcessor()

        #expect(processor.process("EMOJI SMILE.", settings: englishSettings) == "🙂.")
        #expect(processor.process("ЭМОДЗИ СМАЙЛ.", settings: russianSettings) == "🙂.")
        #expect(processor.process("Emoji LäCheLn.", settings: germanSettings) == "🙂.")
        #expect(processor.process("launch emoji.", settings: customSettings) == "🚀.")
    }

    @Test func emojiCommandsUseOnlyTheFirstActiveLanguageSet() {
        var settings = AppSettings.defaults
        settings.localTextCleanupEnabled = false
        settings.enabledEmojiCommandSetIDs = ["es", "de"]

        let output = TranscriptTextPostProcessor().process(
            "emoji sonrisa emoji herz",
            settings: settings
        )

        #expect(output == "🙂 emoji herz")
    }

    @Test func emojiCommandsReplaceSelectedLanguageSet() {
        var settings = AppSettings.defaults
        settings.localTextCleanupEnabled = false
        settings.enabledEmojiCommandSetIDs = ["de"]

        let output = TranscriptTextPostProcessor().process(
            "emoji sonrisa emoji herz",
            settings: settings
        )

        #expect(output == "emoji sonrisa ❤️")
    }

    @Test func emojiCommandsReplaceCustomCommandsAndPreferThemOverBuiltIns() {
        var settings = AppSettings.defaults
        settings.localTextCleanupEnabled = false
        settings.customEmojiCommands = [
            CustomEmojiCommand(emoji: "🚀", command: "emoji rocket", aliases: ["эмодзи ракета"]),
            CustomEmojiCommand(emoji: "😎", command: "emoji smile"),
        ]

        let output = TranscriptTextPostProcessor().process(
            "emoji rocket эмодзи ракета emoji smile",
            settings: settings
        )

        #expect(output == "🚀 🚀 😎")
    }

    @Test func emojiCommandsRequireKnownPrefixedPhrases() {
        var settings = AppSettings.defaults
        settings.localTextCleanupEnabled = false

        let output = TranscriptTextPostProcessor().process(
            "I like your smile. emoji unknown.",
            settings: settings
        )

        #expect(output == "I like your smile. emoji unknown.")
    }

    @Test func emojiCommandsCanBeDisabled() {
        var settings = AppSettings.defaults
        settings.localTextCleanupEnabled = false
        settings.emojiCommandsEnabled = false

        let output = TranscriptTextPostProcessor().process(
            "emoji smile",
            settings: settings
        )

        #expect(output == "emoji smile")
    }

    @Test func emojiCommandsPreserveRepeatedCommandsAndUserReplacementOrder() {
        var settings = AppSettings.defaults
        settings.localTextCleanupEnabled = false
        settings.textReplacementRules = [
            TextReplacementRule(search: "🙂", replacement: ":smile:")
        ]

        let output = TranscriptTextPostProcessor().process(
            "emoji smile emoji smile",
            settings: settings
        )

        #expect(output == ":smile: :smile:")
    }

    @Test func disabledCleanupAndRulesAreSkipped() {
        var settings = AppSettings.defaults
        settings.localTextCleanupEnabled = false
        settings.textReplacementRules = [
            TextReplacementRule(search: "AI-looking", replacement: "plain", isEnabled: false)
        ]

        let output = TranscriptTextPostProcessor().process(
            "“AI-looking”—text",
            settings: settings
        )

        #expect(output == "“AI-looking”—text")
    }

    @Test func emptyReplacementResultFallsBackToOriginalText() {
        var settings = AppSettings.defaults
        settings.localTextCleanupEnabled = false
        settings.textReplacementRules = [
            TextReplacementRule(search: "transcript", replacement: "")
        ]

        let output = TranscriptTextPostProcessor().process(
            "transcript",
            settings: settings,
            fallback: "original transcript"
        )

        #expect(output == "original transcript")
    }
}
