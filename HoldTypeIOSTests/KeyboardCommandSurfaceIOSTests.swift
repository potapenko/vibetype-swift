//
//  KeyboardCommandSurfaceIOSTests.swift
//  HoldTypeIOSTests
//
//  Created by Codex on 7/13/26.
//

import Testing

struct KeyboardCommandSurfaceIOSTests {

    @Test func voiceStatusUsesOnlyShortProductLabels() {
        #expect(KeyboardVoiceStatus.allCases.map(\.rawValue) == [
            "Ready",
            "Full Access required",
            "Opening HoldType…",
            "Couldn’t open HoldType",
            "Starting…",
            "Listening…",
            "Processing…",
            "Session not running",
            "Allow Microphone",
            "No Network",
            "Dictation failed",
        ])
        #expect(KeyboardVoiceStatus.ready.accessibilityAnnouncement == nil)
        #expect(
            KeyboardVoiceStatus.sessionNotRunning.accessibilityAnnouncement
                == "Session not running"
        )
    }

    @Test func recoveryCopyIsCompactAndContainsNoManualNavigation() {
        #expect(KeyboardVoiceRecovery.startSession.title == "Ready to dictate")
        #expect(
            KeyboardVoiceRecovery.startSession.instruction
                == "Tap the microphone to start."
        )
        #expect(
            KeyboardVoiceRecovery.enableFullAccess.instruction
                == "Full Access is required for keyboard voice controls."
        )
        #expect(
            KeyboardVoiceRecovery.enableFullAccess.followUpInstruction == nil
        )
        #expect(
            KeyboardVoiceRecovery.enableFullAccess.shortcutInstruction == nil
        )
        #expect(
            KeyboardVoiceRecovery.requestFailed.instruction
                == "Tap the microphone to try again."
        )
        let allInstructions = [
            KeyboardVoiceRecovery.startSession.instruction,
            KeyboardVoiceRecovery.enableFullAccess.instruction,
            KeyboardVoiceRecovery.requestFailed.instruction,
        ]
        #expect(allInstructions.allSatisfy { !$0.contains("Open HoldType") })
    }

    @Test func cursorDragAccumulatesThresholdsAndReportsDirection() {
        var accumulator = KeyboardCursorDragAccumulator(maximumCharactersPerUpdate: 3)

        let belowForwardThreshold = accumulator.consume(horizontalDelta: 11)
        let forward = accumulator.consume(horizontalDelta: 1)
        let belowBackwardThreshold = accumulator.consume(horizontalDelta: -7)
        let backward = accumulator.consume(horizontalDelta: -5)

        #expect(belowForwardThreshold == nil)
        #expect(forward == KeyboardCursorMovement(direction: .forward, characterCount: 1))
        #expect(forward?.characterOffset == 1)
        #expect(belowBackwardThreshold == nil)
        #expect(backward == KeyboardCursorMovement(direction: .backward, characterCount: 1))
        #expect(backward?.characterOffset == -1)
    }

    @Test func cursorDragBoundsLargeUpdatesAndResetDropsRemainder() {
        var accumulator = KeyboardCursorDragAccumulator(maximumCharactersPerUpdate: 3)

        let bounded = accumulator.consume(horizontalDelta: 120)
        let droppedOverflow = accumulator.consume(horizontalDelta: 0)

        #expect(bounded == KeyboardCursorMovement(direction: .forward, characterCount: 3))
        #expect(droppedOverflow == nil)

        let belowThreshold = accumulator.consume(horizontalDelta: 11)
        #expect(belowThreshold == nil)
        accumulator.reset()
        let afterReset = accumulator.consume(horizontalDelta: 1)
        #expect(afterReset == nil)
        #expect(accumulator.accumulatedPoints == 1)
    }

    @Test func deleteRepeatAcceleratesOnlyInsideItsBounds() {
        let profile = KeyboardDeleteRepeatProfile()

        #expect(profile.initialDelay == 0.42)
        #expect(profile.interval(afterCompletedRepeats: -1) == 0.085)
        #expect(abs(profile.interval(afterCompletedRepeats: 10) - 0.065) < 0.000_001)
        #expect(abs(profile.interval(afterCompletedRepeats: 20) - 0.045) < 0.000_001)
        #expect(profile.interval(afterCompletedRepeats: 1_000) == 0.045)
    }

    @Test func returnPresentationUsesHostSemanticMeaning() {
        let expected: [KeyboardReturnKeySemantic: KeyboardReturnKeyPresentation] = [
            .lineBreak: .returnSymbol,
            .go: .title("Go"),
            .join: .title("Join"),
            .next: .title("Next"),
            .route: .title("Route"),
            .search: .title("Search"),
            .send: .title("Send"),
            .done: .title("Done"),
            .emergencyCall: .title("Emergency Call"),
            .continueAction: .title("Continue"),
        ]

        for semantic in KeyboardReturnKeySemantic.allCases {
            let presentation = KeyboardReturnKeyPresentation(semantic: semantic)
            #expect(presentation == expected[semantic])
        }
        #expect(KeyboardReturnKeyPresentation.returnSymbol.accessibilityLabel == "Return")
        #expect(KeyboardReturnKeyPresentation.title("Send").accessibilityLabel == "Send")
    }

    @Test func insertionGateSuppressesOnlyTheActiveEvent() {
        var gate = KeyboardInsertionEventGate()

        let firstBegin = gate.beginEvent()
        let reentrantBegin = gate.beginEvent()

        #expect(firstBegin)
        #expect(!reentrantBegin)
        #expect(gate.isHandlingEvent)

        gate.endEvent()

        #expect(!gate.isHandlingEvent)
        let laterBegin = gate.beginEvent()
        #expect(laterBegin)
    }
}
