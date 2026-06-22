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
        #expect(
            DictationStatus.recording.detailText
                == "Recording placeholder active. Microphone input is not captured in this build."
        )
    }

    @Test func exposesOnlyNormalizedSuccessTranscript() {
        let status = DictationStatus.success(transcript: "  Typed text\n")

        #expect(status.lastTranscriptText == "Typed text")
        #expect(status.lastTranscriptMenuText == "Typed text")
        #expect(status.detailText == "Typed text")
    }

    @Test func longTranscriptUsesCompactMenuPreviewWithoutChangingSavedText() {
        let transcript = String(repeating: "a", count: 160)
        let status = DictationStatus.success(transcript: transcript)

        #expect(status.lastTranscriptText == transcript)
        #expect(status.lastTranscriptMenuText == "\(String(repeating: "a", count: 140))...")
        #expect(status.canSaveLastTranscript)
    }

    @Test func onlyNonEmptyNormalizedSuccessTranscriptCanBeSaved() {
        #expect(DictationStatus.idle.canSaveLastTranscript == false)
        #expect(DictationStatus.success(transcript: "").canSaveLastTranscript == false)
        #expect(DictationStatus.success(transcript: "  \n\t  ").canSaveLastTranscript == false)
        #expect(DictationStatus.success(transcript: "Typed text").canSaveLastTranscript == true)
    }

    @Test func whitespaceOnlySuccessTranscriptShowsEmptyState() {
        let status = DictationStatus.success(transcript: "  \n\t  ")

        #expect(status.lastTranscriptText == nil)
        #expect(status.lastTranscriptMenuText == "No transcript yet.")
        #expect(status.detailText == "No transcript available.")
    }

    @Test func placeholderRecordingActionTogglesOnlyStartAndStopStates() {
        #expect(DictationStatus.idle.placeholderRecordingActionResult == .recording)
        #expect(DictationStatus.recording.placeholderRecordingActionResult == .idle)
        #expect(DictationStatus.transcribing.placeholderRecordingActionResult == .transcribing)
        #expect(DictationStatus.success(transcript: "Typed text").placeholderRecordingActionResult == .recording)
        #expect(DictationStatus.failure(message: "Missing permission").placeholderRecordingActionResult == .recording)
    }
}
