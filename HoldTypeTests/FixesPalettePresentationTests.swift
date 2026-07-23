import HoldTypeDomain
import Testing
@testable import HoldType

@MainActor
struct FixesPalettePresentationTests {
    @Test func everySupportedIconMapsToAnSFSymbolName() {
        let mappings = Dictionary(
            uniqueKeysWithValues: TextFixIcon.allCases.map {
                ($0, $0.fixesPaletteSystemImageName)
            }
        )

        #expect(mappings.count == TextFixIcon.allCases.count)
        #expect(mappings[.translate] == "character.bubble")
        #expect(mappings[.fix] == "checkmark.seal")
        #expect(mappings[.improveWriting] == "wand.and.stars")
        #expect(mappings[.makeShorter] == "text.alignleft")
        #expect(mappings[.summarize] == "doc.text")
        #expect(mappings[.bulletPoints] == "list.bullet")
        #expect(mappings[.casual] == "face.smiling")
        #expect(mappings[.markdown] == "chevron.left.forwardslash.chevron.right")
        #expect(mappings[.formal] == "briefcase")
        #expect(mappings[.expand] == "arrow.up.left.and.arrow.down.right")
        #expect(mappings[.rewrite] == "arrow.triangle.2.circlepath")
        #expect(mappings[.custom] == "sparkles")
        #expect(mappings.values.allSatisfy { !$0.isEmpty })
    }

    @Test func actionPresentationContainsOnlyDisplayMetadata() {
        let action = TextFixCatalog.defaults.customActions[0]
        let presentation = FixesPaletteActionPresentation(action: action)

        #expect(presentation.id == action.id)
        #expect(presentation.title == action.title)
        #expect(presentation.systemImageName == "wand.and.stars")
        #expect(String(reflecting: presentation).contains(action.prompt ?? "") == false)
    }

    @Test func readyStatusHasNoBannerAndAllowsActivation() {
        #expect(FixesPaletteStatus.ready.presentation(actionTitle: nil) == nil)
        #expect(FixesPaletteStatus.ready.allowsActionActivation)
    }

    @Test func progressUsesSelectedActionTitle() {
        let status = FixesPaletteStatus.processing(actionID: "default.make-shorter")

        #expect(
            status.presentation(actionTitle: "Make Shorter")
                == FixesPaletteStatusPresentation(
                    title: "Applying Make Shorter…",
                    message: nil,
                    systemImageName: nil,
                    tone: .neutral,
                    showsProgress: true
                )
        )
        #expect(status.allowsActionActivation == false)
    }

    @Test func unavailableFailureAndStaleHaveProductLanguagePresentation() {
        let unavailable = FixesPaletteStatus.unavailable(message: "Select some text.")
        let failure = FixesPaletteStatus.failure(
            message: "The request timed out.",
            allowsRetry: true
        )
        let stale = FixesPaletteStatus.staleTarget(message: "The original text changed.")

        #expect(unavailable.presentation(actionTitle: nil)?.title == "Fixes Unavailable")
        #expect(unavailable.presentation(actionTitle: nil)?.tone == .warning)
        #expect(failure.presentation(actionTitle: nil)?.title == "Fix Failed")
        #expect(failure.presentation(actionTitle: nil)?.tone == .error)
        #expect(failure.allowsActionActivation)
        #expect(stale.presentation(actionTitle: nil)?.title == "Text Changed")
        #expect(stale.presentation(actionTitle: nil)?.tone == .warning)
        #expect(stale.allowsActionActivation == false)
    }
}
