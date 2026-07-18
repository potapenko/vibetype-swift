import AppKit
import HoldTypeDomain
import HoldTypeOpenAI
import Testing
@testable import HoldType
struct DictationStatusTests {

    @Test func projectsOnlyRuntimeWorkWithoutTranscriptOrErrorPayloads() {
        #expect(DictationStatus.idle.voiceWorkPhase == .inactive)
        #expect(DictationStatus.recording.voiceWorkPhase == .listening)
        #expect(DictationStatus.transcribing.voiceWorkPhase == .processing)
        #expect(DictationStatus.success(transcript: "First result").voiceWorkPhase == .inactive)
        #expect(DictationStatus.success(transcript: "Second result").voiceWorkPhase == .inactive)
        #expect(DictationStatus.failure(message: "First failure").voiceWorkPhase == .inactive)
        #expect(DictationStatus.failure(message: "Second failure").voiceWorkPhase == .inactive)
    }

    @Test func exposesMenuTextForCoreStates() {
        #expect(DictationStatus.idle.menuStatusText == "Ready")
        #expect(DictationStatus.recording.menuStatusText == "Recording…")
        #expect(DictationStatus.transcribing.menuStatusText == "Transcribing…")
        #expect(DictationStatus.success(transcript: "Hello").menuStatusText == "Ready")
        #expect(
            DictationStatus.failure(message: "Recording was too short. Try speaking for a little longer.")
                .menuStatusText == "Error: Recording too short"
        )
        #expect(
            DictationStatus.failure(message: "Transcription needs an OpenAI API key saved in Settings.")
                .menuStatusText == "API key required"
        )
    }

    @Test func exposesRecordingActionForCurrentState() {
        #expect(DictationStatus.idle.recordingActionTitle == "Transcribe")
        #expect(DictationStatus.recording.recordingActionTitle == "Stop Recording")
        #expect(DictationStatus.transcribing.recordingActionTitle == "Transcribe")
        #expect(DictationStatus.transcribing.isRecordingActionEnabled == false)
        #expect(DictationStatus.idle.recordingActionShortcutHint == "Hold Right ⌘")
        #expect(DictationStatus.recording.recordingActionShortcutHint == nil)
    }

    @Test func exposesOnlyNormalizedSuccessTranscript() {
        let status = DictationStatus.success(transcript: "  Typed text\n")

        #expect(status.lastTranscriptText == "Typed text")
    }

    @Test func longTranscriptKeepsFullLastTranscriptState() {
        let transcript = String(repeating: "a", count: 160)
        let status = DictationStatus.success(transcript: transcript)

        #expect(status.lastTranscriptText == transcript)
    }

    @Test func onlyNonEmptyNormalizedSuccessTranscriptIsRetained() {
        #expect(DictationStatus.idle.lastTranscriptText == nil)
        #expect(DictationStatus.success(transcript: "").lastTranscriptText == nil)
        #expect(DictationStatus.success(transcript: "  \n\t  ").lastTranscriptText == nil)
        #expect(DictationStatus.success(transcript: "Typed text").lastTranscriptText == "Typed text")
    }

    @Test func projectsOnlyANonEmptySuccessAsAReadyAttemptResult() {
        let statuses: [DictationStatus] = [
            .idle,
            .recording,
            .transcribing,
            .failure(message: "Failure"),
            .success(transcript: ""),
            .success(transcript: "  \n\t  "),
            .success(transcript: "  First accepted text\n"),
            .success(transcript: "Second accepted text"),
        ]
        let projectedOutcomes = statuses.compactMap(\.voiceAttemptOutcome)

        #expect(projectedOutcomes == [.resultReady, .resultReady])
        #expect(projectedOutcomes.contains(.interrupted) == false)
    }

}
