//
//  KeyboardSessionStateIOSTests.swift
//  vibetypeIOSTests
//
//  Created by Codex on 6/21/26.
//

import Testing

struct KeyboardSessionStateIOSTests {

    @Test func readyKeyboardSessionCanReachConfirmationState() throws {
        var model = KeyboardSessionModel(availability: .ready)

        #expect(model.start() == .requestContainingAppVoiceSession)

        model.sessionDidBeginListening()
        model.beginTranscribing()
        model.finishTranscription(text: " Keyboard transcript ")

        #expect(model.state == .confirming(try #require(KeyboardTranscriptDraft("Keyboard transcript"))))
    }

    @Test func acceptDecisionCarriesOnlyAcceptedTranscriptText() throws {
        var model = KeyboardSessionModel()

        _ = model.start()
        model.sessionDidBeginListening()
        model.beginTranscribing()
        model.finishTranscription(text: "Accepted on iOS")

        #expect(try model.accept() == .insertAcceptedTranscript("Accepted on iOS"))
        #expect(model.acceptedTranscript?.text == "Accepted on iOS")
    }

    @Test func setupNeededPathDoesNotLaunchVoiceSession() {
        var model = KeyboardSessionModel(
            availability: .setupNeeded(.containingAppSetupRequired)
        )

        #expect(model.start() == .unavailable(.containingAppSetupRequired))
        #expect(model.state == .setupNeeded(.containingAppSetupRequired))
    }
}
