//
//  APIKeySettingsStateTests.swift
//  HoldTypeTests
//
//  Created by Codex on 7/5/26.
//

import Testing
@testable import HoldType

struct APIKeySettingsStateTests {

    @Test func savedAPIKeyAvailabilityDoesNotPopulateInput() {
        var state = APIKeySettingsState()

        state.applyAvailability(.saved)

        #expect(state.input.isEmpty)
        #expect(state.status == .saved)
        #expect(state.apiKeyAvailability == .saved)
        #expect(state.shouldAutosaveInput == false)
    }

    @Test func savedStatusUsesMaskedInputDisplayWhenReplacementInputIsEmpty() {
        #expect(
            APIKeySettingsStatus.saved.inputMask(isInputEmpty: true)
                == APIKeySettingsStatus.savedAPIKeyInputMask
        )
        #expect(APIKeySettingsStatus.saved.inputMask(isInputEmpty: false) == nil)
        #expect(APIKeySettingsStatus.missing.inputMask(isInputEmpty: true) == nil)
    }

    @Test func missingAPIKeyAvailabilityClearsInput() {
        var state = APIKeySettingsState(input: "sk-draft")

        state.applyAvailability(.missing)

        #expect(state.input.isEmpty)
        #expect(state.status == .missing)
        #expect(state.shouldAutosaveInput == false)
    }

    @Test func changedNonEmptyInputNeedsAutosave() {
        var state = APIKeySettingsState()
        state.applyAvailability(.saved)

        state.input = " sk-new "

        #expect(state.normalizedInput == "sk-new")
        #expect(state.shouldAutosaveInput)
    }

    @Test func successfulAutosaveClearsSecretInputAndShowsSavedStatus() {
        var state = APIKeySettingsState()
        state.input = " sk-new\n"

        state.applySavedInput()

        #expect(state.input.isEmpty)
        #expect(state.status == .saved)
        #expect(state.shouldAutosaveInput == false)
    }

    @Test func deleteClearsInputAndShowsMissingStatus() {
        var state = APIKeySettingsState()
        state.applyAvailability(.saved)

        state.applyDeletedAPIKey()

        #expect(state.input.isEmpty)
        #expect(state.status == .missing)
    }

    @Test func failurePreservesCurrentInput() {
        var state = APIKeySettingsState(input: "sk-draft")

        state.applyFailure("Keychain is unavailable.")

        #expect(state.input == "sk-draft")
        #expect(state.status == .failure("Keychain is unavailable."))
    }

    @Test func unavailableAvailabilityReportsFailureWithoutClearingDraft() {
        var state = APIKeySettingsState(input: "sk-draft")

        state.applyAvailability(.unavailable("Keychain is locked."))

        #expect(state.input == "sk-draft")
        #expect(state.status == .failure("Keychain is locked."))
        #expect(state.apiKeyAvailability == .unavailable("Keychain is locked."))
    }

}
