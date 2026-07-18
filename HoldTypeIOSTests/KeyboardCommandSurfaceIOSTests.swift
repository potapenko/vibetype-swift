//
//  KeyboardCommandSurfaceIOSTests.swift
//  HoldTypeIOSTests
//
//  Created by Codex on 7/13/26.
//

import Foundation
import Testing

struct KeyboardCommandSurfaceIOSTests {

    @Test func historyRouteAcceptsOnlyTheCanonicalURL() throws {
        let route = KeyboardHistoryLaunchRoute()
        let url = try #require(route.url)

        #expect(url.absoluteString == "holdtype://history")
        #expect(KeyboardHistoryLaunchRoute(url: url) != nil)

        for rawURL in [
            "holdtype://history/",
            "holdtype://history/entry",
            "holdtype://history?source=keyboard",
            "holdtype://history#recent",
            "holdtype://user@history",
            "https://history",
        ] {
            #expect(
                KeyboardHistoryLaunchRoute(
                    url: try #require(URL(string: rawURL))
                ) == nil
            )
        }
    }

    @Test func voiceStatusUsesOnlyShortProductLabels() {
        #expect(KeyboardVoiceStatus.allCases.map(\.rawValue) == [
            "Ready",
            "Full Access required",
            "Opening HoldType…",
            "Couldn’t open HoldType",
            "Starting…",
            "Listening…",
            "Processing…",
            "Allow Microphone",
            "No Network",
            "Dictation failed",
        ])
        #expect(KeyboardVoiceStatus.ready.accessibilityAnnouncement == nil)
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
