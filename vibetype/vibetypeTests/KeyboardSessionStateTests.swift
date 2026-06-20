//
//  KeyboardSessionStateTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/21/26.
//

import Foundation
import Testing
@testable import vibetype

struct KeyboardSessionStateTests {

    @Test func startsReadySessionThroughContainingAppLaunch() {
        var model = KeyboardSessionModel(availability: .ready)

        #expect(model.state == .idle(acceptedTranscript: nil))
        #expect(model.start() == .requestContainingAppVoiceSession)
        #expect(model.state == .launchingSession)

        model.sessionDidBeginListening()

        #expect(model.state == .listening)
    }

    @Test func cancelReturnsToIdleWithoutDroppingAcceptedTranscript() throws {
        let transcript = try KeyboardAcceptedTranscript(
            id: try #require(UUID(uuidString: "7B7C7E1A-7F33-4A1C-9D19-98B57D6E7B58")),
            text: "Already accepted",
            createdAt: Date(timeIntervalSince1970: 1_781_983_983)
        )
        var model = KeyboardSessionModel(acceptedTranscript: transcript)

        _ = model.start()
        model.cancel()

        #expect(model.acceptedTranscript == transcript)
        #expect(model.state == .idle(acceptedTranscript: transcript))
    }

    @Test func acceptsConfirmedTranscriptAndReturnsInsertDecision() throws {
        var model = FakeKeyboardSessionDriver().model

        try model.completeSuccessfulSession(text: "  Insert this text.  ")

        let decision = try model.accept()

        #expect(decision == .insertAcceptedTranscript("Insert this text."))
        #expect(model.acceptedTranscript?.text == "Insert this text.")

        if case .acceptedTranscript(let accepted) = model.state {
            #expect(accepted.text == "Insert this text.")
        } else {
            Issue.record("Expected accepted transcript state")
        }
    }

    @Test func recordsErrorWithoutClearingPreviousAcceptedTranscript() throws {
        let transcript = try KeyboardAcceptedTranscript(text: "Previous text")
        var model = KeyboardSessionModel(acceptedTranscript: transcript)

        _ = model.start()
        model.sessionDidBeginListening()
        model.fail(.transcriptionFailed)

        #expect(model.acceptedTranscript == transcript)
        #expect(model.state == .error(.transcriptionFailed, acceptedTranscript: transcript))
    }

    @Test func opensAndClosesCompactSettings() {
        var model = KeyboardSessionModel()

        model.openInlineSettings()

        #expect(model.state == .compactSettings(KeyboardInlineSettingsState(canOpenContainingApp: true)))
        #expect(model.openContainingApp() == .openContainingApp)

        model.closeInlineSettings()

        #expect(model.state == .idle(acceptedTranscript: nil))
    }

    @Test func unavailableStartStaysInSetupNeededState() {
        var model = KeyboardSessionModel(
            availability: .setupNeeded(.openAccessRequired)
        )

        #expect(model.state == .setupNeeded(.openAccessRequired))
        #expect(model.start() == .unavailable(.openAccessRequired))
        #expect(model.state == .setupNeeded(.openAccessRequired))
        #expect(model.openContainingApp() == .openContainingApp)
    }

    @Test func emptyTranscriptionBecomesErrorWithoutAcceptedText() {
        var model = FakeKeyboardSessionDriver().model

        model.startTranscribing()
        model.finishTranscription(text: "   ")

        #expect(model.acceptedTranscript == nil)
        #expect(model.state == .error(.emptyTranscript, acceptedTranscript: nil))
    }
}

private struct FakeKeyboardSessionDriver {
    var model = KeyboardSessionModel()
}

private extension KeyboardSessionModel {
    mutating func startTranscribing() {
        _ = start()
        sessionDidBeginListening()
        beginTranscribing()
    }

    mutating func completeSuccessfulSession(text: String) throws {
        startTranscribing()
        finishTranscription(text: text)

        let draft = try #require(
            {
                if case .confirming(let draft) = state {
                    return draft
                }

                return nil
            }()
        )

        #expect(draft.text == text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
