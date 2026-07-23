import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSTextFixEditorPresentationTests {
    @Test func draftValidationMatchesProductCharacterAndByteBounds() {
        var draft = IOSTextFixEditorDraft(
            id: "custom.validation"
        )
        #expect(draft.validation == .missingTitle)

        draft.title = String(
            repeating: "a",
            count: TextFixAction.maximumTitleCharacterCount + 1
        )
        draft.prompt = "prompt"
        #expect(
            draft.validation
                == .titleTooLong(
                    maximumCharacterCount:
                        TextFixAction.maximumTitleCharacterCount
                )
        )

        draft.title = "Valid"
        draft.prompt = " \n "
        #expect(draft.validation == .missingPrompt)

        draft.prompt = String(
            repeating: "é",
            count: (TextFixAction.maximumPromptUTF8ByteCount / 2) + 1
        )
        #expect(
            draft.validation
                == .promptTooLarge(
                    maximumUTF8ByteCount:
                        TextFixAction.maximumPromptUTF8ByteCount
                )
        )

        draft.prompt = "  Preserve exact whitespace.  "
        #expect(draft.validation == .valid)
        let action = try? draft.action()
        #expect(action?.prompt == draft.prompt)
    }

    @Test func everySupportedIconHasNativeAccessiblePresentation() {
        let titles = TextFixIcon.allCases.map {
            IOSTextFixEditorIconPresentation.title(for: $0)
        }
        let symbols = TextFixIcon.allCases.map {
            IOSTextFixEditorIconPresentation.systemImage(for: $0)
        }

        #expect(titles.count == TextFixIcon.allCases.count)
        #expect(symbols.count == TextFixIcon.allCases.count)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(symbols.allSatisfy { !$0.isEmpty })
    }

    @Test func draftAndRouteDescriptionsNeverExposePromptContent() {
        let canary = "PRIVATE-FIX-PROMPT-CANARY"
        let draft = IOSTextFixEditorDraft(
            id: "custom.redaction",
            title: canary,
            prompt: canary
        )
        let route = IOSTextFixEditorRoute.custom("custom.redaction")

        #expect(!String(describing: draft).contains(canary))
        #expect(!String(reflecting: draft).contains(canary))
        #expect(
            !Mirror(reflecting: draft).children.contains {
                String(describing: $0.value).contains(canary)
            }
        )
        #expect(!String(describing: route).contains(canary))
    }

    @Test func newIdentifiersAreStableBoundedCustomIdentifiers() {
        let identifier = IOSTextFixEditorDraft.newIdentifier(
            uuid: UUID(
                uuid: (0x42, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7)
            )
        )

        #expect(identifier.hasPrefix("custom."))
        #expect(
            identifier.utf8.count
                <= TextFixAction.maximumIdentifierUTF8ByteCount
        )
        #expect(
            IOSTextFixEditorRoute.newCustom(identifier).identifier
                == identifier
        )
    }
}
