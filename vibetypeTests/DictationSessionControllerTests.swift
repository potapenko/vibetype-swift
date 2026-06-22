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
        let cuePlayer = FakeDictationCuePlayer()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            cuePlayer: cuePlayer
        )

        await controller.performRecordingAction()

        #expect(controller.status == .recording)
        #expect(controller.outputStatusText == nil)
        #expect(recorder.startCount == 1)
        #expect(recorder.stopCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(cuePlayer.playedCues == [.startRecording])
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
            result: .success(.skipped(reason: .appClipboardDisabled))
        )
        let cuePlayer = FakeDictationCuePlayer()
        let settings = makeSettings(saveTranscriptsToAppClipboard: false)
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            cuePlayer: cuePlayer,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(controller.status == .success(transcript: "Shared controller transcript"))
        #expect(controller.lastTranscriptText == "Shared controller transcript")
        #expect(controller.status.lastTranscriptText == "Shared controller transcript")
        #expect(controller.outputStatusText == "VibeType Clipboard is disabled.")
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls == [TranscriptionCall(audioFileURL: artifact.fileURL, settings: settings)])
        #expect(transcriptOutput.calls == [TranscriptOutputCall(transcript: "Shared controller transcript", settings: settings)])
        #expect(cuePlayer.playedCues == [.stopRecording])
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
            lastTranscriptText: "previous transcript",
            outputStatusText: "Previous output status"
        )

        controller.cancelRecording()

        #expect(controller.status == .idle)
        #expect(controller.lastTranscriptText == "previous transcript")
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

    @Test func cancelDuringTranscriptionDiscardsLateTranscript() async {
        let gate = ControllerAsyncGate()
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(
            result: .success(" late transcript "),
            beforeResult: {
                await gate.wait()
            }
        )
        let transcriptOutput = FakeTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording,
            lastTranscriptText: "previous accepted transcript",
            outputStatusText: "Previous output status"
        )

        let stopTask = Task { @MainActor in
            await controller.performRecordingAction()
        }
        await yieldUntil {
            controller.status == .transcribing && transcriptionService.calls.count == 1
        }

        controller.cancelRecording()

        #expect(controller.status == .idle)
        #expect(controller.lastTranscriptText == "previous accepted transcript")
        #expect(controller.outputStatusText == nil)
        #expect(transcriptionService.cancelCount == 1)

        await gate.open()
        await stopTask.value

        #expect(controller.status == .idle)
        #expect(controller.lastTranscriptText == "previous accepted transcript")
        #expect(controller.outputStatusText == nil)
        #expect(transcriptOutput.calls.isEmpty)
    }

    @Test func startFailureBecomesUserVisibleFailureWithoutExternalWork() async {
        let recorder = FakeAudioRecorderService(startResult: .failure(.recordingUnavailable))
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let cuePlayer = FakeDictationCuePlayer()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            cuePlayer: cuePlayer
        )

        await controller.performRecordingAction()

        #expect(controller.status == .failure(message: "Recording is unavailable on this Mac."))
        #expect(recorder.startCount == 1)
        #expect(recorder.stopCount == 0)
        #expect(transcriptionService.calls.isEmpty)
        #expect(transcriptOutput.calls.isEmpty)
        #expect(cuePlayer.playedCues.isEmpty)
    }

    @Test func disabledSoundSettingSuppressesRecordingCues() async {
        let recorder = FakeAudioRecorderService()
        let transcriptionService = FakeControllerTranscriptionService()
        let transcriptOutput = FakeTranscriptOutput()
        let cuePlayer = FakeDictationCuePlayer()
        var settings = AppSettings.defaults
        settings.soundEnabled = false
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            cuePlayer: cuePlayer
        )

        await controller.performRecordingAction()

        #expect(controller.status == .recording)
        #expect(cuePlayer.playedCues.isEmpty)
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

    @Test func stopFailureBecomesUserVisibleFailureWithoutTranscription() async {
        let recorder = FakeAudioRecorderService(
            currentStatus: .recording,
            stopResult: .failure(.stopFailed)
        )
        let transcriptionService = FakeControllerTranscriptionService()
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

        #expect(controller.status == .failure(message: "Could not finish the current recording."))
        #expect(controller.lastTranscriptText == "previous transcript")
        #expect(controller.outputStatusText == nil)
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
        let transcriptOutput = FakeTranscriptOutput(
            result: .failure(TextInsertionServiceError.textInsertionTimedOut)
        )
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            transcriptHistory: transcriptHistory,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(controller.status == .success(transcript: "Delivered text"))
        #expect(controller.lastTranscriptText == "Delivered text")
        #expect(controller.outputStatusText == "Inserting text into the active app timed out.")
        #expect(transcriptOutput.calls == [TranscriptOutputCall(transcript: "Delivered text", settings: .defaults)])
        #expect(transcriptHistory.entries.map(\.transcriptText) == ["Delivered text"])
        #expect(transcriptHistory.calls.first?.audioDuration == 1.2)
    }

    @Test func disabledRecoveryHistoryDoesNotWriteAcceptedTranscript() async {
        let recorder = FakeAudioRecorderService(currentStatus: .recording)
        let transcriptionService = FakeControllerTranscriptionService(result: .success("  Private text\n"))
        let transcriptOutput = FakeTranscriptOutput()
        let transcriptHistory = FakeTranscriptRecoveryHistory()
        var settings = AppSettings.defaults
        settings.saveTranscriptHistory = false
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settings: settings,
            transcriptOutput: transcriptOutput,
            transcriptHistory: transcriptHistory,
            initialStatus: .recording
        )

        await controller.performRecordingAction()

        #expect(controller.status == .success(transcript: "Private text"))
        #expect(transcriptHistory.entries.isEmpty)
    }

    private func makeController(
        recorder: FakeAudioRecorderService,
        transcriptionService: FakeControllerTranscriptionService,
        settings: AppSettings = .defaults,
        transcriptOutput: FakeTranscriptOutput,
        cuePlayer: FakeDictationCuePlayer? = nil,
        transcriptHistory: FakeTranscriptRecoveryHistory? = nil,
        initialStatus: DictationStatus = .idle,
        lastTranscriptText: String? = nil,
        outputStatusText: String? = nil
    ) -> DictationSessionController {
        let cuePlayer = cuePlayer ?? FakeDictationCuePlayer()
        let transcriptHistory = transcriptHistory ?? FakeTranscriptRecoveryHistory()

        return DictationSessionController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settingsProvider: { settings },
            transcriptOutput: transcriptOutput,
            cuePlayer: cuePlayer,
            transcriptHistory: transcriptHistory,
            initialStatus: initialStatus,
            lastTranscriptText: lastTranscriptText,
            outputStatusText: outputStatusText
        )
    }

    private func makeSettings(saveTranscriptsToAppClipboard: Bool = true) -> AppSettings {
        var settings = AppSettings.defaults
        settings.saveTranscriptsToAppClipboard = saveTranscriptsToAppClipboard
        return settings
    }

    private func yieldUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<20 {
            if condition() {
                return
            }

            await Task.yield()
        }
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

private struct RecoveryHistoryCall: Equatable {
    let transcript: String
    let settings: AppSettings
    let audioDuration: TimeInterval?
}

private final class FakeControllerTranscriptionService: OpenAITranscriptionServing {
    private let result: Result<String, OpenAITranscriptionServiceError>
    private let beforeResult: (() async -> Void)?
    private(set) var calls: [TranscriptionCall] = []
    private(set) var cancelCount = 0

    init(
        result: Result<String, OpenAITranscriptionServiceError> = .success("Controller transcript"),
        beforeResult: (() async -> Void)? = nil
    ) {
        self.result = result
        self.beforeResult = beforeResult
    }

    func transcribe(audioFileURL: URL, settings: AppSettings) async throws -> String {
        calls.append(TranscriptionCall(audioFileURL: audioFileURL, settings: settings))
        await beforeResult?()
        return try result.get()
    }

    func cancelActiveTranscription() {
        cancelCount += 1
    }
}

private final class FakeTranscriptOutput: TranscriptOutputDelivering {
    private let result: Result<TextInsertionResult, Error>
    private(set) var calls: [TranscriptOutputCall] = []

    init(result: Result<TextInsertionResult, Error> = .success(.skipped(reason: .appClipboardDisabled))) {
        self.result = result
    }

    func deliver(_ transcript: String, settings: AppSettings) async throws -> TextInsertionResult {
        calls.append(TranscriptOutputCall(transcript: transcript, settings: settings))
        return try result.get()
    }
}

@MainActor
private final class FakeTranscriptRecoveryHistory: TranscriptRecoveryHistoryRecording {
    private(set) var entries: [TranscriptHistoryEntry] = []
    private(set) var calls: [RecoveryHistoryCall] = []

    func recordAcceptedTranscript(
        _ transcript: String,
        settings: AppSettings,
        audioDuration: TimeInterval?
    ) throws {
        calls.append(
            RecoveryHistoryCall(
                transcript: transcript,
                settings: settings,
                audioDuration: audioDuration
            )
        )

        guard settings.saveTranscriptHistory else {
            return
        }

        entries = try [
            TranscriptHistoryEntry(
                transcriptText: transcript,
                transcriptionModel: settings.resolvedTranscriptionModel,
                languageCode: settings.resolvedLanguageCode,
                audioDuration: audioDuration
            )
        ] + entries
    }

    func clear() {
        entries = []
    }
}

@MainActor
private final class FakeDictationCuePlayer: DictationCuePlaying {
    private(set) var playedCues: [DictationCue] = []

    func play(_ cue: DictationCue) {
        playedCues.append(cue)
    }
}

private actor ControllerAsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen {
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let waitingContinuations = continuations
        continuations.removeAll()

        for continuation in waitingContinuations {
            continuation.resume()
        }
    }
}
