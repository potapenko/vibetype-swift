import Foundation
import HoldTypeDomain
import SwiftUI
import Testing
import UIKit
@testable import HoldTypeIOS

@MainActor
struct IOSReplacementRuleEditorSupportTests {
    @Test func presentationStatusesAndRoutesUseDurableContentFreeIdentity() {
        let active = TextReplacementRule(
            id: UUID(),
            search: "PRIVATE-SEARCH",
            replacement: "PRIVATE-REPLACEMENT"
        )
        let off = TextReplacementRule(
            id: UUID(),
            search: "other",
            replacement: "value",
            isEnabled: false
        )
        let inactive = TextReplacementRule(
            id: UUID(),
            search: " \n ",
            replacement: "value",
            isEnabled: true
        )

        #expect(
            IOSReplacementRulesPresentation.summary([])
                == "0 custom rules"
        )
        #expect(
            IOSReplacementRulesPresentation.summary([active, off, inactive])
                == "3 custom rules · 1 active"
        )
        #expect(
            IOSReplacementRulesPresentation.summary([active])
                == "1 custom rule · 1 active"
        )
        #expect(IOSReplacementRuleRuntimeStatus(rule: active) == .active)
        #expect(IOSReplacementRuleRuntimeStatus(rule: off) == .off)
        #expect(
            IOSReplacementRuleRuntimeStatus(rule: inactive)
                == .inactiveEmptySearch
        )

        let routes: [IOSLibraryRoute] = [
            .replacementRules,
            .newReplacementRule(active.id),
            .replacementRule(active.id),
        ]
        for route in routes {
            #expect(!String(describing: route).contains("PRIVATE"))
            #expect(!String(reflecting: route).contains("PRIVATE"))
        }
    }

    @Test func automaticCleanupPresentationCoversEveryRuntimeCategory() {
        #expect(
            IOSAutomaticCleanupPresentation.transformationDescriptions == [
                "Typographic quotes and apostrophes become plain quotes",
                "Long dashes and minus signs become a plain hyphen",
                "A single-character ellipsis becomes three periods",
                "Special spaces become regular spaces",
                "Word joiners are removed",
                "Repeated spaces and extra blank lines are compacted",
            ]
        )
    }

    @Test func draftAndValidationPreserveEveryRawString() {
        let id = UUID()
        var draft = IOSReplacementRuleEditorDraft(id: id)
        draft.search = "  First\nSecond  "
        draft.replacement = ""

        let candidate = draft.candidate(isEnabled: false)
        #expect(candidate.id == id)
        #expect(candidate.search == "  First\nSecond  ")
        #expect(candidate.replacement.isEmpty)
        #expect(!candidate.isEnabled)
        #expect(
            IOSReplacementRuleDraftValidation.resolve(
                mode: .add(id),
                draft: draft
            ) == .valid
        )

        draft.search = " \n\t "
        draft.replacement = " whitespace stays "
        #expect(
            IOSReplacementRuleDraftValidation.resolve(
                mode: .add(id),
                draft: draft
            ) == .missingSearch
        )
        #expect(
            IOSReplacementRuleDraftValidation.resolve(
                mode: .edit(id),
                draft: draft
            ) == .valid
        )
        #expect(draft.candidate(isEnabled: true).search == " \n\t ")
        #expect(
            draft.candidate(isEnabled: true).replacement
                == " whitespace stays "
        )
    }

    @Test func exactMultilineInputDisablesAutomaticTextRewriters() {
        let textView = UITextView()

        IOSExactMultilineTextInput.configure(
            textView,
            accessibilityLabel: "Search text"
        )

        #expect(textView.autocapitalizationType == .none)
        #expect(textView.autocorrectionType == .no)
        #expect(textView.spellCheckingType == .no)
        #expect(textView.smartQuotesType == .no)
        #expect(textView.smartDashesType == .no)
        #expect(textView.smartInsertDeleteType == .no)
        #expect(textView.textContentType == nil)
        #expect(textView.adjustsFontForContentSizeCategory)
        #expect(textView.accessibilityLabel == "Search text")
        #expect(textView.inlinePredictionType == .no)
        if #available(iOS 18.0, *) {
            #expect(textView.mathExpressionCompletionType == .no)
            #expect(textView.writingToolsBehavior == .none)
        }

        IOSExactMultilineTextInput.setInteraction(
            textView,
            isEnabled: false
        )
        #expect(!textView.isEditable)
        #expect(!textView.isSelectable)
        #expect(!textView.isUserInteractionEnabled)
        #expect(textView.accessibilityTraits.contains(.notEnabled))

        IOSExactMultilineTextInput.setInteraction(
            textView,
            isEnabled: true
        )
        #expect(textView.isEditable)
        #expect(textView.isSelectable)
        #expect(textView.isUserInteractionEnabled)
        #expect(!textView.accessibilityTraits.contains(.notEnabled))
    }

    @Test func newSessionRetainsUUIDAndRawDraftAcrossFailureAndRetry() throws {
        let id = UUID()
        var session = IOSReplacementRuleEditorSession(newRuleID: id)
        session.set("  exact search  ", at: \.search)
        session.set("", at: \.replacement)

        let firstResult = session.beginSave()
        let first = try #require(firstResult)
        assertAddMutation(first.mutation, id: id)

        session.commitFailed(currentRule: nil)
        #expect(session.phase == .saveFailed)
        #expect(session.isDirty)
        #expect(session.draft.id == id)
        #expect(session.draft.search == "  exact search  ")

        let retryResult = session.beginSave()
        let retry = try #require(retryResult)
        #expect(retry.ruleID == id)
        assertAddMutation(retry.mutation, id: id)
    }

    @Test func newSessionUUIDCollisionFailsClosedWithoutBrokenRecovery() {
        let id = UUID()
        var session = IOSReplacementRuleEditorSession(newRuleID: id)
        session.set("local draft", at: \.search)
        let collidingRule = TextReplacementRule(
            id: id,
            search: "existing",
            replacement: "durable"
        )

        session.observeDurableRule(collidingRule)

        #expect(session.phase == .changedElsewhere)
        #expect(session.isDirty)
        #expect(session.draft.search == "local draft")
        #expect(!session.canReloadLatest)
        #expect(!session.canReplaceLatest)
        #expect(session.beginSave() == nil)
        #expect(session.beginSave(replacingLatest: true) == nil)
    }

    @Test func cleanEditorAdoptsAndDirtyEditorRequiresReloadOrReplace() throws {
        let original = TextReplacementRule(
            id: UUID(),
            search: "old",
            replacement: "value",
            isEnabled: true
        )
        var session = IOSReplacementRuleEditorSession(rule: original)
        var changed = original
        changed.search = "latest"

        session.observeDurableRule(changed)
        #expect(session.phase == .idle)
        #expect(session.draft.search == "latest")
        #expect(!session.isDirty)

        session.set("local draft", at: \.search)
        var changedAgain = changed
        changedAgain.replacement = "new durable replacement"
        changedAgain.isEnabled = false
        session.observeDurableRule(changedAgain)

        #expect(session.phase == .changedElsewhere)
        #expect(session.baseline == changedAgain)
        #expect(session.latest == changedAgain)
        #expect(session.draft.search == "local draft")
        #expect(session.canReloadLatest)
        #expect(session.canReplaceLatest)
        session.observeDurableRule(changedAgain)
        #expect(session.phase == .changedElsewhere)
        #expect(session.beginSave() == nil)

        let replaceResult = session.beginSave(replacingLatest: true)
        let replace = try #require(replaceResult)
        guard case .replacementRules(
            .update(let expected, let requested)
        ) = replace.mutation else {
            Issue.record("Expected replacement rule update")
            return
        }
        #expect(expected == changedAgain)
        #expect(requested.search == "local draft")
        #expect(requested.replacement == "value")
        #expect(!requested.isEnabled)
    }

    @Test func reloadDeletionAndRepeatedReplaceRaceFailClosed() throws {
        let original = TextReplacementRule(
            id: UUID(),
            search: "old",
            replacement: "value"
        )
        var session = IOSReplacementRuleEditorSession(rule: original)
        session.set("local", at: \.search)

        var latest = original
        latest.replacement = "latest"
        session.observeDurableRule(latest)
        #expect(session.phase == .changedElsewhere)

        session.reloadLatest()
        #expect(session.phase == .idle)
        #expect(session.draft.replacement == "latest")
        #expect(!session.isDirty)

        session.set("local again", at: \.search)
        var secondLatest = latest
        secondLatest.search = "second latest"
        session.observeDurableRule(secondLatest)
        let replaceResult = session.beginSave(replacingLatest: true)
        _ = try #require(replaceResult)

        var thirdLatest = secondLatest
        thirdLatest.replacement = "third latest"
        session.completeWithoutCommit(
            disposition: .conflict,
            returnedRule: thirdLatest,
            currentRule: thirdLatest
        )
        #expect(session.phase == .changedElsewhere)
        #expect(session.baseline == thirdLatest)
        #expect(session.draft.search == "local again")

        let retryResult = session.beginSave(replacingLatest: true)
        let retry = try #require(retryResult)
        guard case .replacementRules(.update(let expected, _)) = retry.mutation
        else {
            Issue.record("Expected replacement retry update")
            return
        }
        #expect(expected == thirdLatest)

        session.completeWithoutCommit(
            disposition: .targetMissing,
            returnedRule: nil,
            currentRule: nil
        )
        #expect(session.phase == .deletedElsewhere)
        #expect(session.beginSave(replacingLatest: true) == nil)
    }

    @Test func completionUsesCurrentFieldsButMergesEnabledOnlyPublication() throws {
        let original = TextReplacementRule(
            id: UUID(),
            search: "old",
            replacement: "value",
            isEnabled: true
        )

        var merged = IOSReplacementRuleEditorSession(rule: original)
        merged.set("  saved search  ", at: \.search)
        let mergedRequest = merged.beginSave()
        _ = try #require(mergedRequest)
        var returned = original
        returned.search = "  saved search  "
        var enabledOnly = returned
        enabledOnly.isEnabled = false
        merged.commitSucceeded(
            returnedRule: returned,
            currentRule: enabledOnly
        )
        #expect(merged.phase == .saved)
        #expect(merged.baseline == enabledOnly)
        #expect(!merged.isDirty)

        var conflicted = IOSReplacementRuleEditorSession(rule: original)
        conflicted.set("saved search", at: \.search)
        let conflictedRequest = conflicted.beginSave()
        _ = try #require(conflictedRequest)
        returned.search = "saved search"
        var newerFields = returned
        newerFields.replacement = "newer publication"
        conflicted.commitSucceeded(
            returnedRule: returned,
            currentRule: newerFields
        )
        #expect(conflicted.phase == .changedElsewhere)
        #expect(conflicted.baseline == newerFields)
        #expect(conflicted.latest == newerFields)
        #expect(conflicted.draft.replacement == "value")
        #expect(conflicted.isDirty)
    }

    @Test func failedCleanDeleteKeepsVisibleNotSavedState() {
        let rule = TextReplacementRule(
            id: UUID(),
            search: "old",
            replacement: "value"
        )
        var session = IOSReplacementRuleEditorSession(rule: rule)

        session.commitFailed(currentRule: rule, forceNotSaved: true)

        #expect(session.phase == .saveFailed)
        #expect(!session.isDirty)
        #expect(session.baseline == rule)
    }

    @Test func orderRequestsAlwaysDescribeTheCompleteUUIDSequence() throws {
        let ids = [UUID(), UUID(), UUID(), UUID()]
        let multiResult = IOSReplacementRulesOrderRequest(
            expected: ids,
            moving: IndexSet([1, 2]),
            to: 4
        )
        let multi = try #require(multiResult)
        #expect(multi.expected == ids)
        #expect(multi.requested == [ids[0], ids[3], ids[1], ids[2]])
        #expect(Set(multi.requested) == Set(ids))

        let upResult = IOSReplacementRulesOrderRequest(
            expected: ids,
            moving: ids[2],
            direction: .up
        )
        let up = try #require(upResult)
        #expect(up.requested == [ids[0], ids[2], ids[1], ids[3]])

        let downResult = IOSReplacementRulesOrderRequest(
            expected: ids,
            moving: ids[1],
            direction: .down
        )
        let down = try #require(downResult)
        #expect(down.requested == [ids[0], ids[2], ids[1], ids[3]])

        #expect(
            IOSReplacementRulesOrderRequest(
                expected: ids,
                moving: IndexSet(integer: 9),
                to: 0
            ) == nil
        )
        #expect(
            IOSReplacementRulesOrderRequest(
                expected: ids,
                moving: ids[0],
                direction: .up
            ) == nil
        )
    }

    @Test func pendingOrderUsesLatestFieldsAndRejectsSequenceChanges() throws {
        let first = TextReplacementRule(
            id: UUID(),
            search: "one",
            replacement: "1"
        )
        let second = TextReplacementRule(
            id: UUID(),
            search: "two",
            replacement: "2"
        )
        let requestResult = IOSReplacementRulesOrderRequest(
            expected: [first.id, second.id],
            moving: second.id,
            direction: .up
        )
        let request = try #require(requestResult)
        let pending = IOSReplacementRulesPendingOrder(request: request)

        var latestFirst = first
        latestFirst.replacement = "latest field"
        let orderedResult = pending.orderedRules(
            from: [latestFirst, second]
        )
        let ordered = try #require(orderedResult)
        #expect(ordered.map(\.id) == [second.id, first.id])
        #expect(ordered[1].replacement == "latest field")
        #expect(
            pending.orderedRules(
                from: [latestFirst, second, TextReplacementRule(
                    search: "three",
                    replacement: "3"
                )]
            ) == nil
        )
    }

    @Test func editorAndListSupportSurfacesAreRedacted() throws {
        let canary = "REPLACEMENT-RULE-PRIVATE-CANARY"
        let rule = TextReplacementRule(
            id: UUID(),
            search: canary,
            replacement: canary
        )
        var session = IOSReplacementRuleEditorSession(rule: rule)
        session.set(canary + "-draft", at: \.search)
        let requestResult = session.beginSave()
        let request = try #require(requestResult)
        let orderResult = IOSReplacementRulesOrderRequest(
            expected: [rule.id, UUID()],
            moving: IndexSet(integer: 0),
            to: 2
        )
        let order = try #require(orderResult)
        let values: [Any] = [
            IOSReplacementRuleReference(expected: rule),
            IOSReplacementRuleEditorDraft(rule: rule),
            session,
            request,
            order,
            IOSReplacementRulesPendingOrder(request: order),
            IOSReplacementRuleRuntimeStatus.active,
            IOSReplacementRulesNotice.notSaved,
            IOSReplacementRuleRowModel(
                rule: rule,
                position: 0,
                totalCount: 1
            ),
            IOSReplacementRulesView(),
            IOSReplacementRuleEditorView(
                mode: .edit(rule.id),
                hasUnsavedSceneEditor: .constant(false)
            ),
        ]

        for value in values {
            #expect(!String(describing: value).contains(canary))
            #expect(!String(reflecting: value).contains(canary))
            #expect(Mirror(reflecting: value).children.isEmpty)
        }
    }

    private func assertAddMutation(
        _ mutation: IOSLibraryMutation,
        id: UUID,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard case .replacementRules(.add(let rule)) = mutation else {
            Issue.record(
                "Expected replacement rule add",
                sourceLocation: sourceLocation
            )
            return
        }
        #expect(rule.id == id, sourceLocation: sourceLocation)
        #expect(rule.search == "  exact search  ", sourceLocation: sourceLocation)
        #expect(rule.replacement.isEmpty, sourceLocation: sourceLocation)
        #expect(rule.isEnabled, sourceLocation: sourceLocation)
    }
}
