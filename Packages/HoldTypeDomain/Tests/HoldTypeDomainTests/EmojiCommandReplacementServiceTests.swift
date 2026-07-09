import Testing
@testable import HoldTypeDomain

struct EmojiCommandReplacementServiceTests {
    private let service = EmojiCommandReplacementService()

    @Test func replacesOnlyAliasesFromTheSelectedBuiltInSet() {
        let english = EmojiCommandSet.builtIn.first { $0.id == "en" }!

        #expect(
            service.process(
                "Nice emoji smile. emoji angry. эмодзи огонь!",
                commandSets: [english]
            ) == "Nice 🙂. 😠. эмодзи огонь!"
        )
    }

    @Test func matchesCaseAndDiacriticInsensitivelyAcrossPunctuation() {
        let german = EmojiCommandSet.builtIn.first { $0.id == "de" }!

        #expect(
            service.process(
                "Emoji, LaCheln and emoji. herz.",
                commandSets: [german]
            ) == "🙂 and ❤️."
        )
    }

    @Test func requiresKnownCompleteWordPhrases() {
        let english = EmojiCommandSet.builtIn.first { $0.id == "en" }!

        #expect(
            service.process(
                "I like your smile. emoji unknown. preemoji smile.",
                commandSets: [english]
            ) == "I like your smile. emoji unknown. preemoji smile."
        )
    }

    @Test func customCommandsOverrideBuiltInsAndDisabledRowsAreIgnored() {
        let english = EmojiCommandSet.builtIn.first { $0.id == "en" }!
        let customCommands = [
            CustomEmojiCommand(emoji: "😎", command: "emoji smile"),
            CustomEmojiCommand(
                emoji: "🚀",
                command: "emoji rocket",
                aliases: ["launch emoji"]
            ),
            CustomEmojiCommand(
                emoji: "🛑",
                command: "emoji fire",
                isEnabled: false
            ),
        ]

        #expect(
            service.process(
                "emoji smile launch emoji emoji fire",
                commandSets: [english],
                customCommands: customCommands
            ) == "😎 🚀 🔥"
        )
    }

    @Test func longestAliasWinsBeforeItsShorterPrefix() {
        let english = EmojiCommandSet.builtIn.first { $0.id == "en" }!
        let customCommand = CustomEmojiCommand(
            emoji: "🚀",
            command: "emoji smile now"
        )

        #expect(
            service.process(
                "emoji smile now. emoji smile.",
                commandSets: [english],
                customCommands: [customCommand]
            ) == "🚀. 🙂."
        )
    }

    @Test func preservesSeparatorsAndRepeatedCommands() {
        let russian = EmojiCommandSet.builtIn.first { $0.id == "ru" }!

        #expect(
            service.process(
                "Проба: эмодзи смайл.эмодзи улыбка!",
                commandSets: [russian]
            ) == "Проба: 🙂.🙂!"
        )
    }

    @Test func noUsableAliasesReturnsInputExactly() {
        let input = "  Keep\nall spacing — unchanged.  "

        #expect(service.process(input, commandSets: []) == input)
        #expect(
            service.process(
                input,
                commandSets: [],
                customCommands: [CustomEmojiCommand(emoji: "", command: "ignored")]
            ) == input
        )
    }
}
