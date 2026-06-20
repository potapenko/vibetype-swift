//
//  vibetypeTests.swift
//  vibetypeTests
//
//  Created by Eugene Potapenko on 6/20/26.
//

import Testing
@testable import vibetype

struct DictationStatusTests {

    @Test func exposesMenuTextForCoreStates() {
        #expect(DictationStatus.idle.menuStatusText == "Ready")
        #expect(DictationStatus.recording.menuStatusText == "Recording...")
        #expect(DictationStatus.transcribing.menuStatusText == "Transcribing...")
        #expect(DictationStatus.success(transcript: "Hello").menuStatusText == "Done")
        #expect(DictationStatus.failure(message: "Missing permission").menuStatusText == "Error")
    }

    @Test func exposesRecordingActionForCurrentState() {
        #expect(DictationStatus.idle.recordingActionTitle == "Start Recording")
        #expect(DictationStatus.recording.recordingActionTitle == "Stop Recording")
        #expect(DictationStatus.transcribing.recordingActionTitle == "Start Recording")
        #expect(DictationStatus.transcribing.isRecordingActionEnabled == false)
    }

    @Test func carriesSuccessAndFailureDetails() {
        #expect(DictationStatus.success(transcript: "Typed text").lastTranscriptText == "Typed text")
        #expect(DictationStatus.success(transcript: "Typed text").detailText == "Typed text")
        #expect(DictationStatus.failure(message: "Missing permission").detailText == "Missing permission")
    }

    @Test func onlyNonEmptySuccessTranscriptCanBeCopied() {
        #expect(DictationStatus.idle.canCopyLastTranscript == false)
        #expect(DictationStatus.success(transcript: "").canCopyLastTranscript == false)
        #expect(DictationStatus.success(transcript: "Typed text").canCopyLastTranscript == true)
    }
}
