import Foundation
import HoldTypeDomain
import Testing

struct EmojiCommandSetDomainIOSTests {
    @Test func packageExposesEmojiCatalogAndLegacyCustomCommandsOnIOS() throws {
        #expect(EmojiCommandSet.builtIn.map(\.id) == ["en", "ru", "es", "de", "fr", "pt"])
        #expect(EmojiCommandSet.builtIn.allSatisfy { $0.commands.count == 21 })

        let command = CustomEmojiCommand(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000321")!,
            emoji: " 🚀 ",
            command: " Emoji   Rocket ",
            aliases: ["Launch Emoji"],
            isEnabled: false
        )
        let roundTrip = try JSONDecoder().decode(
            CustomEmojiCommand.self,
            from: JSONEncoder().encode(command)
        )

        #expect(roundTrip == command)
        #expect(command.normalizedForStorage.emoji == "🚀")
        #expect(command.normalizedForStorage.command == "Emoji Rocket")
    }
}
