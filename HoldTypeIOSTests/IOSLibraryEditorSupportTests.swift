import Foundation
import HoldTypeDomain
import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSLibraryEditorSupportTests {
    @Test func libraryDestinationsAndDraftsHaveStableContentFreePresentation() {
        #expect(
            IOSLibraryDestination.allCases == [
                .dictionary,
                .emojiCommands,
                .replacementRules,
            ]
        )
        #expect(
            IOSLibraryDestination.allCases.map(\.title) == [
                "Dictionary",
                "Voice Emoji Commands",
                "Replacement Rules",
            ]
        )
        #expect(
            Set(
                IOSLibraryDestination.allCases.map(
                    \.rowAccessibilityIdentifier
                )
            ).count == 3
        )

        var draft = IOSDictionaryAddDraft()
        #expect(!draft.hasMeaningfulInput)
        draft.rawInput = "  HoldType  "
        #expect(draft.hasMeaningfulInput)

        let canary = "LIBRARY-PRESENTATION-PRIVATE-CANARY"
        let values: [Any] = [
            draft,
            IOSLibrarySearchQuery(text: canary),
            IOSLibraryEditorNotice.added(
                addedCount: 1,
                duplicateCount: 2
            ),
        ]
        for value in values {
            #expect(!String(describing: value).contains(canary))
            #expect(!String(reflecting: value).contains(canary))
            #expect(Mirror(reflecting: value).children.isEmpty)
        }
    }

    @Test func dictionaryBatchUsesSemanticIdentityAndReportsCounts() {
        var content = IOSLibraryContent(
            customDictionary: CustomDictionary(entries: ["Alpha", "Beta"])
        )

        let receipt = IOSLibraryMutation.dictionary(
            .add(rawInput: " beta, Gamma\nDELTA\ngamma ")
        ).apply(to: &content)

        #expect(receipt.disposition == .committed)
        #expect(receipt.addedCount == 2)
        #expect(receipt.duplicateCount == 2)
        #expect(
            content.customDictionary.entries
                == ["Alpha", "Beta", "Gamma", "DELTA"]
        )

        let duplicate = IOSLibraryMutation.dictionary(
            .add(rawInput: "ALPHA, beta")
        ).apply(to: &content)
        #expect(duplicate.disposition == .duplicate)
        #expect(duplicate.addedCount == 0)
        #expect(duplicate.duplicateCount == 2)

        let beforeInvalid = content
        let invalid = IOSLibraryMutation.dictionary(
            .add(rawInput: " , \n ")
        ).apply(to: &content)
        #expect(invalid.disposition == .invalid)
        #expect(content == beforeInvalid)
    }

    @Test func dictionaryRemovalNeverUsesAVisibleIndex() throws {
        let reference = try #require(IOSDictionaryEntryReference("Beta"))
        var shifted = IOSLibraryContent(
            customDictionary: CustomDictionary(
                entries: ["Inserted Elsewhere", "Alpha", "Beta", "Gamma"]
            )
        )

        let removed = IOSLibraryMutation.dictionary(
            .remove(reference)
        ).apply(to: &shifted)

        #expect(removed.disposition == .committed)
        #expect(
            shifted.customDictionary.entries
                == ["Inserted Elsewhere", "Alpha", "Gamma"]
        )

        var changedSpelling = IOSLibraryContent(
            customDictionary: CustomDictionary(entries: ["BETA"])
        )
        let conflict = IOSLibraryMutation.dictionary(
            .remove(reference)
        ).apply(to: &changedSpelling)
        #expect(conflict.disposition == .conflict)
        #expect(changedSpelling.customDictionary.entries == ["BETA"])

        var missing = IOSLibraryContent.defaults
        let targetMissing = IOSLibraryMutation.dictionary(
            .remove(reference)
        ).apply(to: &missing)
        #expect(targetMissing.disposition == .targetMissing)
    }

    @Test func emojiFieldMutationsPreserveConcurrentRowsAndFields() throws {
        let commandID = UUID()
        let command = CustomEmojiCommand(
            id: commandID,
            emoji: "🚀",
            command: "emoji launch",
            aliases: ["launch now"],
            isEnabled: true
        )
        var content = IOSLibraryContent(
            emojiCommandsConfiguration: EmojiCommandsConfiguration(
                isEnabled: true,
                enabledBuiltInSetIDs: ["en"],
                customCommands: [command]
            )
        )

        let selection = IOSLibraryMutation.emojiCommands(
            .selectBuiltInSet(
                expected: .builtIn("en"),
                requested: .custom
            )
        ).apply(to: &content)
        #expect(selection.disposition == .committed)
        #expect(
            content.emojiCommandsConfiguration.enabledBuiltInSetIDs.isEmpty
        )
        #expect(
            content.emojiCommandsConfiguration.customCommands == [command]
        )

        content.emojiCommandsConfiguration.customCommands[0].aliases = [
            "changed elsewhere",
        ]
        let toggle = IOSLibraryMutation.emojiCommands(
            .setCommandEnabled(
                id: commandID,
                expected: true,
                requested: false
            )
        ).apply(to: &content)
        #expect(toggle.disposition == .committed)
        #expect(
            content.emojiCommandsConfiguration.customCommands[0].aliases
                == ["changed elsewhere"]
        )
        #expect(
            !content.emojiCommandsConfiguration.customCommands[0].isEnabled
        )

        let staleToggle = IOSLibraryMutation.emojiCommands(
            .setCommandEnabled(
                id: commandID,
                expected: true,
                requested: false
            )
        ).apply(to: &content)
        #expect(staleToggle.disposition == .conflict)
    }

    @Test func emojiCRUDUsesUUIDFullRowCASAndRejectsPhraseAmbiguity() {
        let first = CustomEmojiCommand(
            id: UUID(),
            emoji: "🙂",
            command: "ÉMOJI smile",
            aliases: ["happy face"]
        ).normalizedForStorage
        var content = IOSLibraryContent(
            emojiCommandsConfiguration: EmojiCommandsConfiguration(
                customCommands: [first]
            )
        )

        let colliding = CustomEmojiCommand(
            id: UUID(),
            emoji: "🔥",
            command: "emoji, smíle"
        )
        let collision = IOSLibraryMutation.emojiCommands(
            .add(colliding)
        ).apply(to: &content)
        #expect(collision.disposition == .invalid)
        #expect(
            content.emojiCommandsConfiguration.customCommands == [first]
        )

        let aliasOnly = CustomEmojiCommand(
            id: UUID(),
            emoji: "🚫",
            command: "  ",
            aliases: ["alias cannot become primary"]
        )
        let missingPrimary = IOSLibraryMutation.emojiCommands(
            .add(aliasOnly)
        ).apply(to: &content)
        #expect(missingPrimary.disposition == .invalid)
        #expect(
            content.emojiCommandsConfiguration.customCommands == [first]
        )

        let second = CustomEmojiCommand(
            id: UUID(),
            emoji: "🚀",
            command: "launch now"
        )
        let added = IOSLibraryMutation.emojiCommands(
            .add(second)
        ).apply(to: &content)
        #expect(added.disposition == .committed)

        var externallyChanged = second.normalizedForStorage
        externallyChanged.aliases = ["external alias"]
        content.emojiCommandsConfiguration.customCommands[1] =
            externallyChanged
        var staleDraft = second
        staleDraft.command = "new local command"
        let conflict = IOSLibraryMutation.emojiCommands(
            .update(expected: second.normalizedForStorage, requested: staleDraft)
        ).apply(to: &content)
        #expect(conflict.disposition == .conflict)
        #expect(
            content.emojiCommandsConfiguration.customCommands[1]
                == externallyChanged
        )

        var aliasOnlyUpdate = externallyChanged
        aliasOnlyUpdate.command = "\n"
        aliasOnlyUpdate.aliases = ["alias cannot become primary"]
        let missingUpdatedPrimary = IOSLibraryMutation.emojiCommands(
            .update(
                expected: externallyChanged,
                requested: aliasOnlyUpdate
            )
        ).apply(to: &content)
        #expect(missingUpdatedPrimary.disposition == .invalid)
        #expect(
            content.emojiCommandsConfiguration.customCommands[1]
                == externallyChanged
        )

        let missing = CustomEmojiCommand(
            id: UUID(),
            emoji: "✅",
            command: "missing"
        )
        let missingRemoval = IOSLibraryMutation.emojiCommands(
            .remove(expected: missing)
        ).apply(to: &content)
        #expect(missingRemoval.disposition == .targetMissing)
    }

    @Test func replacementRulesPreserveRawValuesAndUseStrictOrderCAS() {
        let first = TextReplacementRule(
            id: UUID(),
            search: "  A\nB  ",
            replacement: " keep ",
            isEnabled: true
        )
        let second = TextReplacementRule(
            id: UUID(),
            search: "b",
            replacement: "c",
            isEnabled: false
        )
        var content = IOSLibraryContent(replacementRules: [first, second])

        let reordered = IOSLibraryMutation.replacementRules(
            .reorder(
                expected: [first.id, second.id],
                requested: [second.id, first.id]
            )
        ).apply(to: &content)
        #expect(reordered.disposition == .committed)
        #expect(content.replacementRules == [second, first])
        #expect(content.replacementRules[1].search == "  A\nB  ")
        #expect(content.replacementRules[1].replacement == " keep ")

        content.replacementRules.append(
            TextReplacementRule(search: "new", replacement: "row")
        )
        let staleOrder = IOSLibraryMutation.replacementRules(
            .reorder(
                expected: [second.id, first.id],
                requested: [first.id, second.id]
            )
        ).apply(to: &content)
        #expect(staleOrder.disposition == .conflict)

        var existingBlank = first
        existingBlank.search = ""
        let blankUpdate = IOSLibraryMutation.replacementRules(
            .update(expected: first, requested: existingBlank)
        )
        var updateContent = IOSLibraryContent(replacementRules: [first])
        #expect(blankUpdate.apply(to: &updateContent).disposition == .committed)
        #expect(updateContent.replacementRules[0].search.isEmpty)

        var addContent = IOSLibraryContent.defaults
        let blankAdd = IOSLibraryMutation.replacementRules(
            .add(TextReplacementRule(search: " ", replacement: "x"))
        ).apply(to: &addContent)
        #expect(blankAdd.disposition == .invalid)
        #expect(addContent.replacementRules.isEmpty)
    }

    @Test func replacementToggleMergesAnIndependentFieldEdit() {
        let ruleID = UUID()
        let original = TextReplacementRule(
            id: ruleID,
            search: "old",
            replacement: "new",
            isEnabled: true
        )
        var externallyChanged = original
        externallyChanged.replacement = "newer"
        var content = IOSLibraryContent(
            replacementRules: [externallyChanged]
        )

        let receipt = IOSLibraryMutation.replacementRules(
            .setEnabled(
                id: ruleID,
                expected: true,
                requested: false
            )
        ).apply(to: &content)

        #expect(receipt.disposition == .committed)
        #expect(content.replacementRules[0].replacement == "newer")
        #expect(!content.replacementRules[0].isEnabled)
    }

    @Test func ownerSkipsRepositoryWritesForClosedNonCommitDispositions()
        async throws {
        let repository = IOSLibraryMutationRepository()
        let owner = IOSLibraryStateOwner(
            load: { try await repository.load() },
            commit: { try await repository.commit($0) }
        )

        let invalid = try await owner.apply(
            .dictionary(.add(rawInput: " , "))
        )
        #expect(invalid.receipt.disposition == .invalid)
        #expect(invalid.state == .ready(.defaults))
        #expect(await repository.commitCount() == 0)

        let committed = try await owner.apply(
            .dictionary(.add(rawInput: "HoldType"))
        )
        #expect(committed.receipt.disposition == .committed)
        #expect(await repository.commitCount() == 1)

        let duplicate = try await owner.apply(
            .dictionary(.add(rawInput: "holdtype"))
        )
        #expect(duplicate.receipt.disposition == .duplicate)
        #expect(await repository.commitCount() == 1)

        let staleReference = try #require(
            IOSDictionaryEntryReference("HOLDTYPE")
        )
        let conflict = try await owner.apply(
            .dictionary(.remove(staleReference))
        )
        #expect(conflict.receipt.disposition == .conflict)
        #expect(await repository.commitCount() == 1)
    }

    @Test func twoScenesMutateTheLatestDurableLibraryWithoutLostUpdates()
        async throws {
        let repository = IOSLibraryMutationRepository()
        let owner = IOSLibraryStateOwner(
            load: { try await repository.load() },
            commit: { try await repository.commit($0) }
        )

        async let first = owner.apply(
            .dictionary(.add(rawInput: "First Scene"))
        )
        async let second = owner.apply(
            .dictionary(.add(rawInput: "Second Scene"))
        )
        let completions = try await [first, second]

        #expect(
            completions.allSatisfy {
                $0.receipt.disposition == .committed
            }
        )
        let durable = try #require(owner.state.durableValue)
        #expect(
            Set(durable.customDictionary.entries)
                == ["First Scene", "Second Scene"]
        )
        #expect(await repository.commitCount() == 2)
    }

    @Test func failedTypedCommitKeepsDurableTruthUntilRetry() async throws {
        let repository = IOSLibraryMutationRepository(commitFailures: [true])
        let owner = IOSLibraryStateOwner(
            load: { try await repository.load() },
            commit: { try await repository.commit($0) }
        )

        await #expect(throws: IOSContainingAppStateOwnerError.saveFailed) {
            _ = try await owner.apply(
                .dictionary(.add(rawInput: "Retry Me"))
            )
        }
        #expect(owner.state == .saveFailed(lastDurableValue: .defaults))

        let invalid = try await owner.apply(
            .dictionary(.add(rawInput: ""))
        )
        #expect(invalid.receipt.disposition == .invalid)
        #expect(invalid.state == .saveFailed(lastDurableValue: .defaults))
        #expect(await repository.commitCount() == 1)

        let recovered = try await owner.apply(
            .dictionary(.add(rawInput: "Retry Me"))
        )
        #expect(recovered.receipt.disposition == .committed)
        #expect(recovered.state.durableValue?.customDictionary.entries == ["Retry Me"])
        #expect(await repository.commitCount() == 2)
    }

    @Test func mutationAndCompletionDebugSurfacesAreRedacted() throws {
        let canary = "LIBRARY-EDITOR-PRIVATE-CANARY"
        let command = CustomEmojiCommand(
            emoji: canary,
            command: canary,
            aliases: [canary]
        )
        let mutation = IOSLibraryMutation.emojiCommands(.add(command))
        let reference = try #require(
            IOSDictionaryEntryReference(canary)
        )
        let completion = IOSLibraryMutationCompletion(
            state: .ready(
                IOSLibraryContent(
                    customDictionary: CustomDictionary(entries: [canary])
                )
            ),
            receipt: IOSLibraryMutationReceipt(
                disposition: .committed,
                addedCount: 1
            )
        )
        let values: [Any] = [
            mutation,
            command,
            reference,
            completion,
            completion.receipt,
        ]

        for value in values where !(value is CustomEmojiCommand) {
            #expect(!String(describing: value).contains(canary))
            #expect(!String(reflecting: value).contains(canary))
            #expect(Mirror(reflecting: value).children.isEmpty)
        }
    }
}

private enum IOSLibraryMutationRepositoryError: Error {
    case scriptedFailure
}

private actor IOSLibraryMutationRepository {
    private var value = IOSLibraryContent.defaults
    private var failures: [Bool]
    private var commits = 0

    init(commitFailures: [Bool] = []) {
        failures = commitFailures
    }

    func load() throws -> IOSLibraryContent { value }

    func commit(_ candidate: IOSLibraryContent) throws -> IOSLibraryContent {
        commits += 1
        if !failures.isEmpty, failures.removeFirst() {
            throw IOSLibraryMutationRepositoryError.scriptedFailure
        }
        value = IOSLibraryContent(
            customDictionary: CustomDictionary(
                entries: candidate.customDictionary.entries
            ),
            emojiCommandsConfiguration: EmojiCommandsConfiguration(
                isEnabled: candidate.emojiCommandsConfiguration.isEnabled,
                enabledBuiltInSetIDs: candidate
                    .emojiCommandsConfiguration.enabledBuiltInSetIDs,
                customCommands: EmojiCommandsConfiguration
                    .normalizedCustomCommands(
                        candidate.emojiCommandsConfiguration.customCommands
                    )
            ),
            replacementRules: candidate.replacementRules
        )
        return value
    }

    func commitCount() -> Int { commits }
}
