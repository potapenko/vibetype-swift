import Foundation
import HoldTypeDomain
import Testing
@testable import HoldType

@MainActor
struct FixesPaletteModelTests {
    @Test func startsWithEnabledCatalogOrderAndFirstActionSelected() throws {
        let disabledID = TextFixCatalog.defaults.customActions[0].id
        let catalog = try TextFixCatalog.defaults.settingCustomActionEnabled(
            id: disabledID,
            isEnabled: false
        )
        let model = makeModel(catalog: catalog)

        #expect(model.actions.map(\.id) == catalog.enabledActions.map(\.id))
        #expect(model.actions.contains(where: { $0.id == disabledID }) == false)
        #expect(model.selectedActionID == TextFixAction.translateIdentifier)
    }

    @Test func searchIsCaseAndDiacriticInsensitive() throws {
        let resume = try TextFixAction(
            id: "custom.resume",
            kind: .customPrompt,
            title: "Résumé",
            icon: .custom,
            prompt: "Improve this résumé.",
            isEnabled: true
        )
        let catalog = try TextFixCatalog.defaults.addingCustomAction(resume)
        let model = makeModel(catalog: catalog)

        model.setSearchText("RESUME")

        #expect(model.visibleActions.map(\.id) == [resume.id])
        #expect(model.selectedActionID == resume.id)
    }

    @Test func clearingSearchRestoresFullListAndKeepsVisibleSelection() {
        let model = makeModel()
        model.setSearchText("Fix")
        let selectedID = model.selectedActionID

        model.setSearchText("")

        #expect(model.visibleActions.count == TextFixCatalog.defaults.enabledActions.count)
        #expect(model.selectedActionID == selectedID)
    }

    @Test func unmatchedSearchClearsSelection() {
        let model = makeModel()

        model.setSearchText("No result with this title")

        #expect(model.visibleActions.isEmpty)
        #expect(model.selectedActionID == nil)
        #expect(model.canActivateSelection == false)
    }

    @Test func arrowMovementClampsAtListEdges() {
        let model = makeModel()

        model.moveSelection(.up)
        #expect(model.selectedActionID == model.visibleActions.first?.id)

        for _ in 0..<(model.visibleActions.count + 2) {
            model.moveSelection(.down)
        }
        #expect(model.selectedActionID == model.visibleActions.last?.id)

        for _ in 0..<(model.visibleActions.count + 2) {
            model.moveSelection(.up)
        }
        #expect(model.selectedActionID == model.visibleActions.first?.id)
    }

    @Test func activationImmediatelyEntersProcessingAndPreventsDuplicateAction() {
        var activatedIDs: [String] = []
        let model = makeModel { activatedIDs.append($0) }

        model.activateSelection()
        model.activateSelection()

        #expect(activatedIDs == [TextFixAction.translateIdentifier])
        #expect(
            model.status
                == .processing(actionID: TextFixAction.translateIdentifier)
        )
        #expect(model.canActivateSelection == false)
    }

    @Test func retryableFailureAllowsAnotherActivation() {
        var activatedIDs: [String] = []
        let model = makeModel { activatedIDs.append($0) }
        model.updateStatus(
            .failure(message: "The service is temporarily unavailable.", allowsRetry: true)
        )
        model.moveSelection(.down)

        model.activateSelection()

        #expect(activatedIDs == [TextFixAction.fixIdentifier])
        #expect(model.status == .processing(actionID: TextFixAction.fixIdentifier))
    }

    @Test func unavailableAndStaleStatesBlockActivation() {
        var activationCount = 0
        let model = makeModel { _ in activationCount += 1 }

        model.updateStatus(.unavailable(message: "Select some text."))
        model.activateSelection()
        model.updateStatus(.staleTarget(message: "The text changed."))
        model.activateSelection()

        #expect(activationCount == 0)
    }

    @Test func dismissalIsIdempotentAndStopsFurtherInteraction() {
        var dismissCount = 0
        var activationCount = 0
        let model = FixesPaletteModel(
            catalog: .defaults,
            onActivate: { _ in activationCount += 1 },
            onDismiss: { dismissCount += 1 }
        )

        model.requestDismissal()
        model.requestDismissal()
        model.activateSelection()
        model.setSearchText("Fix")

        #expect(dismissCount == 1)
        #expect(activationCount == 0)
        #expect(model.searchText.isEmpty)
    }

    private func makeModel(
        catalog: TextFixCatalog = .defaults,
        onActivate: @escaping FixesPaletteModel.ActionHandler = { _ in }
    ) -> FixesPaletteModel {
        FixesPaletteModel(
            catalog: catalog,
            onActivate: onActivate,
            onDismiss: {}
        )
    }
}
