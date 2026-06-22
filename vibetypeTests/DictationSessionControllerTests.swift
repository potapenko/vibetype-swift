//
//  DictationSessionControllerTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/22/26.
//

import Foundation
import Testing
@testable import vibetype

@MainActor
struct DictationSessionControllerTests {

    @Test func recordingActionStartsThroughInjectedRecorderOnly() async {
        let recorder = FakeAudioRecorderService()
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput
        )

        await controller.performRecordingAction()

        #expect(controller.status == .recording)
        #expect(controller.outputStatusText == nil)
        #expect(recorder.startCount == 1)
        #expect(recorder.stopCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func recordingActionStopsTranscribesAndDeliversAcceptedTranscript() async {
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/vibetype-controller-success.m4a"),
            duration: 1.3,
            byteCount: 2048
        )
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .success(artifact)
        )
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success("  Shared controller transcript \n")
        )
        let transcriptOutput = FakeTranscriptOutput(
            result: .success(.skipped(reason: .outputDisabled))
        )
        let settings = makeSettings(copyToClipboard: false)
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(controller.status == .success(transcript: "Shared controller transcript"))
        #expect(controller.lastTranscriptText == "Shared controller transcript")
        #expect(controller.status.lastTranscriptText == "Shared controller transcript")
        #expect(controller.outputStatusText == "Transcript output is disabled.")
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls == [TranscriptionCall(audioFileURL: artifact.fileURL, settings: settings)])
        #expect(transcriptOutput.calls == [TranscriptOutputCall(transcript: "Shared controller transcript", settings: settings)])
    }

    @Test func transcribingStateIgnoresRecordingAction() async {
        let recorder = FakeAudioRecorderService()
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .transcribing
        )

        await controller.performRecordingAction()

        #expect(controller.status == .transcribing)
        #expect(recorder.startCount == 0)
        #expect(recorder.stopCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func cancelRecordingReturnsToIdleAndSkipsTranscription() {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording,
            outputStatusText: "Previous output status"
        )

        controller.cancelRecording()

        #expect(controller.status == .idle)
        #expect(controller.outputStatusText == nil)
        #expect(recorder.cancelCount == 1)
        #expect(recorder.stopCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func cancelRecordingSurfacesRecorderCleanupFailure() {
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            cancelStatus: .failed(message: "Could not remove the canceled recording.")
        )
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording
        )

        controller.cancelRecording()

        #expect(controller.status == .failure(message: "Could not remove the canceled recording."))
        #expect(recorder.cancelCount == 1)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func cancelRecordingIsIgnoredOutsideActiveRecording() {
        let recorder = FakeAudioRecorderService()
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .success(transcript: "previous")
        )

        controller.cancelRecording()

        #expect(controller.status == .success(transcript: "previous"))
        #expect(recorder.cancelCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func startFailureBecomesUserVisibleFailureWithoutExternalWork() async {
        let recorder = FakeAudioRecorderService(startResult: .failure(.recordingUnavailable))
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput
        )

        await controller.performRecordingAction()

        #expect(controller.status == .failure(message: "Recording is unavailable on this Mac."))
        #expect(recorder.startCount == 1)
        #expect(recorder.stopCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func recordingTimeoutBecomesUserVisibleFailureWithoutTranscription() async {
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .failure(.recordingTimedOut(duration: 300, maximumDuration: 300))
        )
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording,
            lastTranscriptText: "previous transcript"
        )

        await controller.performRecordingAction()

        #expect(
            controller.status == .failure(
                message: "Recording reached the maximum length. Try again with a shorter dictation."
            )
        )
        #expect(controller.lastTranscriptText == "previous transcript")
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func transcriptionFailureDoesNotDeliverOutputOrOverwriteSuccess() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(result: .failure(.networkUnavailable))
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording,
            lastTranscriptText: "previous transcript",
            outputStatusText: "Previous output status"
        )

        await controller.performRecordingAction()

        #expect(controller.status == .failure(message: "The network is unavailable. Try again when you are connected."))
        #expect(controller.lastTranscriptText == "previous transcript")
        #expect(controller.outputStatusText == nil)
        #expect(transcriptionService.calls.count == 1)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func emptyTranscriptionKeepsPreviousTranscriptAndSkipsOutput() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(result: .success("  \n\t  "))
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording,
            lastTranscriptText: "previous accepted transcript"
        )

        await controller.performRecordingAction()

        #expect(controller.status == .failure(message: "No speech text was detected."))
        #expect(controller.lastTranscriptText == "previous accepted transcript")
        #expect(controller.outputStatusText == nil)
        #expect(transcriptionService.calls.count == 1)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func outputFailureKeepsAcceptedTranscriptRecoverable() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(result: .success("  Delivered text\n"))
        let transcriptOutput = FakeTranscriptOutput(result: .failure(TextInsertionServiceError.pasteTimedOut))
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(controller.status == .success(transcript: "Delivered text"))
        #expect(controller.lastTranscriptText == "Delivered text")
        #expect(controller.outputStatusText == "Paste into the active app timed out.")
        #expect(transcriptOutput.calls == [TranscriptOutputCall(transcript: "Delivered text", settings: .defaults)])
    }

    private func makeController(
        recorder: FakeAudioRecorderService,
        transcriptionService: FakeControllerTranscriptionService,
        settings: AppSettings = .defaults,
        transcriptOutput: FakeTranscriptOutput,
        initialStatus: DictationStatus = .idle,
        lastTranscriptText: String? = nil,
        outputStatusText: String? = nil
    ) -> DictationSessionController {
        DictationSessionController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settingsProvider: { settings },
            transcriptOutput: transcriptOutput,
            initialStatus: initialStatus,
            lastTranscriptText: lastTranscriptText,
            outputStatusText: outputStatusText
        )
    }

    private func makeSettings(copyToClipboard: Bool = true) -> AppSettings {
        var settings = AppSettings.defaults
        settings.copyToClipboard = copyToClipboard
        return settings
    }
}

private struct TranscriptionCall: Equatable {
    let audioFileURL: URL
    let settings: AppSettings
}

private struct TranscriptOutputCall: Equatable {
    let transcript: String
    let settings: AppSettings
}

private final class FakeControllerTranscriptionService: OpenAITranscriptionServing {
    private let result: Result<String, OpenAITranscriptionServiceError>
    private(set) var calls: [TranscriptionCall] = []

    init(result: Result<String, OpenAITranscriptionServiceError> = .success("Controller transcript")) {
        self.result = result
    }

    func transcribe(audioFileURL: URL, settings: AppSettings) async throws -> String {
        calls.append(TranscriptionCall(audioFileURL: audioFileURL, settings: settings))
        return try result.get()
    }
}

private final class FakeTranscriptOutput: TranscriptOutputDelivering {
    private let result: Result<TextInsertionResult, Error>
    private(set) var calls: [TranscriptOutputCall] = []

    init(result: Result<TextInsertionResult, Error> = .success(.skipped(reason: .outputDisabled))) {
        self.result = result
    }

    func deliver(_ transcript: String, settings: AppSettings) async throws -> TextInsertionResult {
        calls.append(TranscriptOutputCall(transcript: transcript, settings: settings))
        return try result.get()
    }
}
