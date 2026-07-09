import HoldTypeDomain
import Testing

struct EmojiCommandReplacementServiceDomainIOSTests {
    @Test func packageReplacesEmojiCommandsOnIOS() {
        let english = EmojiCommandSet.builtIn.first { $0.id == "en" }!
        let service = EmojiCommandReplacementService()

        #expect(
            service.process(
                "emoji rocket, emoji smile!",
                commandSets: [english],
                customCommands: [
                    CustomEmojiCommand(emoji: "🚀", command: "emoji rocket")
                ]
            ) == "🚀, 🙂!"
        )
    }
}
