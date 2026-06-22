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

    @Test func mapsRecordingStateToVisibleIndicator() {
        let recording = FloatingIndicatorPresentation.presentation(
            for: .recording,
            settings: .defaults
        )

        #expect(recording?.phase == .recording)
        #expect(recording?.title == "Recording")
    }

    @Test func hidesNonRecordingStates() {
        #expect(FloatingIndicatorPresentation.presentation(for: .transcribing, settings: .defaults) == nil)
        #expect(FloatingIndicatorPresentation.presentation(for: .success(transcript: "Done"), settings: .defaults) == nil)
        #expect(FloatingIndicatorPresentation.presentation(for: .failure(message: "Error"), settings: .defaults) == nil)
    }

    @Test func disabledSettingSuppressesRecordingIndicator() {
        var settings = AppSettings.defaults
        settings.showFloatingIndicator = false

        #expect(FloatingIndicatorPresentation.presentation(for: .recording, settings: settings) == nil)
    }
}
