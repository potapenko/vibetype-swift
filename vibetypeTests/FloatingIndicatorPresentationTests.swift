//
//  FloatingIndicatorPresentationTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/21/26.
//

import Testing
@testable import vibetype

struct FloatingIndicatorPresentationTests {

    @Test func hidesIdleStatus() {
        let presentation = FloatingIndicatorPresentation.presentation(
            for: .idle,
            settings: .defaults
        )

        #expect(presentation == nil)
    }

    @Test func mapsWorkingStatesToVisibleIndicator() {
        let recording = FloatingIndicatorPresentation.presentation(
            for: .recording,
            settings: .defaults
        )
        let transcribing = FloatingIndicatorPresentation.presentation(
            for: .transcribing,
            settings: .defaults
        )

        #expect(recording?.phase == .recording)
        #expect(recording?.title == "Recording")
        #expect(recording?.dismissalDelay == nil)
        #expect(transcribing?.phase == .transcribing)
        #expect(transcribing?.title == "Transcribing")
        #expect(transcribing?.dismissalDelay == nil)
    }

    @Test func mapsCompletionStatesToBriefIndicator() {
        let success = FloatingIndicatorPresentation.presentation(
            for: .success(transcript: "Typed text"),
            settings: .defaults
        )
        let failure = FloatingIndicatorPresentation.presentation(
            for: .failure(message: "Missing microphone permission"),
            settings: .defaults
        )

        #expect(success?.phase == .success)
        #expect(success?.title == "Done")
        #expect(success?.dismissalDelay == FloatingIndicatorPresentation.successDismissalDelay)
        #expect(failure?.phase == .failure)
        #expect(failure?.title == "Missing microphone permission")
        #expect(failure?.dismissalDelay == FloatingIndicatorPresentation.failureDismissalDelay)
    }

    @Test func disabledSettingSuppressesEveryVisibleState() {
        var settings = AppSettings.defaults
        settings.showFloatingIndicator = false

        #expect(FloatingIndicatorPresentation.presentation(for: .recording, settings: settings) == nil)
        #expect(FloatingIndicatorPresentation.presentation(for: .transcribing, settings: settings) == nil)
        #expect(FloatingIndicatorPresentation.presentation(for: .success(transcript: "Done"), settings: settings) == nil)
        #expect(FloatingIndicatorPresentation.presentation(for: .failure(message: "Error"), settings: settings) == nil)
    }

    @Test func failureTitleFallsBackAndTruncatesLongMessages() {
        let blankFailure = FloatingIndicatorPresentation.presentation(
            for: .failure(message: "   "),
            settings: .defaults
        )
        let longFailure = FloatingIndicatorPresentation.presentation(
            for: .failure(message: String(repeating: "a", count: 80)),
            settings: .defaults
        )

        #expect(blankFailure?.title == "Error")
        #expect(longFailure?.title.count == 75)
        #expect(longFailure?.title.hasSuffix("...") == true)
    }
}
