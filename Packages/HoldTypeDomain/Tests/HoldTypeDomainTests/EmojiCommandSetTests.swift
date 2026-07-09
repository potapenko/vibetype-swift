import Foundation
import Testing
@testable import HoldTypeDomain

struct EmojiCommandSetTests {
    @Test func builtInCatalogPreservesLanguageOrderAndCommandCounts() {
        #expect(EmojiCommandSet.builtIn.map(\.id) == ["en", "ru", "es", "de", "fr", "pt"])
        #expect(EmojiCommandSet.builtIn.allSatisfy { $0.commands.count == 21 })
        #expect(EmojiCommandSet.builtInIDs == Set(["en", "ru", "es", "de", "fr", "pt"]))

        let english = EmojiCommandSet.builtIn[0]
        let russian = EmojiCommandSet.builtIn[1]
        let portuguese = EmojiCommandSet.builtIn[5]
        #expect(english.commands.first?.aliases == ["emoji heart", "emoji red heart"])
        #expect(russian.commands.first?.aliases == ["эмодзи сердце", "эмодзи сердечко"])
        #expect(portuguese.commands.last?.emoji == "💔")
    }

    @Test func spokenPhraseNormalizationPreservesFirstSpellingAndOrder() {
        let phrases = EmojiCommand.normalizedSpokenPhrases([
            "  Emoji   Smile  ",
            "emoji smile",
            "ÉMOJI LÄCHELN",
            "emoji lacheln",
            " \n ",
        ])

        #expect(phrases == ["Emoji Smile", "ÉMOJI LÄCHELN"])
    }

    @Test func builtInSelectionUsesOnlyTheFirstKnownTrimmedID() {
        #expect(EmojiCommandSet.normalizedBuiltInIDs(["missing", " ru ", "en"]) == ["ru"])
        #expect(EmojiCommandSet.normalizedBuiltInIDs(["missing"]) == [])
    }

    @Test func customCommandNormalizesStorageWithoutChangingIdentityOrEnabledState() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000321")!
        let command = CustomEmojiCommand(
            id: id,
            emoji: " 🚀 \n",
            command: "  Emoji   Rocket ",
            aliases: ["Launch Emoji", "launch emoji", " \n"],
            isEnabled: false
        )

        #expect(command.normalizedEmoji == "🚀")
        #expect(command.displayCommand == "Emoji Rocket")
        #expect(command.promptHints == ["Emoji Rocket", "Launch Emoji"])
        #expect(command.hasUsableCommand)
        #expect(
            command.normalizedForStorage == CustomEmojiCommand(
                id: id,
                emoji: "🚀",
                command: "Emoji Rocket",
                aliases: ["Launch Emoji"],
                isEnabled: false
            )
        )
    }

    @Test func frozenCustomCommandPayloadPreservesLegacyCodableFields() throws {
        let fixture = Data(
            #"""
            {
              "id": "00000000-0000-0000-0000-000000000321",
              "emoji": "🚀",
              "command": "emoji rocket",
              "aliases": ["launch emoji"],
              "isEnabled": false
            }
            """#.utf8
        )
        let command = try JSONDecoder().decode(CustomEmojiCommand.self, from: fixture)

        #expect(command.id == UUID(uuidString: "00000000-0000-0000-0000-000000000321"))
        #expect(command.emoji == "🚀")
        #expect(command.command == "emoji rocket")
        #expect(command.aliases == ["launch emoji"])
        #expect(command.isEnabled == false)

        let encoded = try JSONEncoder().encode(command)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(
            Set(object.keys) == Set(["id", "emoji", "command", "aliases", "isEnabled"])
        )
        #expect(try JSONDecoder().decode(CustomEmojiCommand.self, from: encoded) == command)
    }
}
