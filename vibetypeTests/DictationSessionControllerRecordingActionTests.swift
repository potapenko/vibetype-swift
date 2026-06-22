//
//  DictationSessionControllerRecordingActionTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/22/26.
//

import Foundation
import Testing
@testable import vibetype

@MainActor
struct DictationSessionControllerRecordingActionTests {
    @Test func explicitStartOnlyStartsFromIdle() async {
        let recorder = RecordingActionRecorder()
        let controller = makeController(recorder: recorder)

        await controller.startRecordingAction()
        await controller.startRecordingAction()

        #expect(controller.status == .recording)
        #expect(recorder.startCount == 1)
        #expect(recorder.stopCount == 0)

        let transcribingRecorder = RecordingActionRecorder()
        let transcribingController = makeController(
            recorder: transcribingRecorder,
            initialStatus: .transcribing
        )

        await transcribingController.startRecordingAction()

        #expect(transcribingController.status == .transcribing)
        #expect(transcribingRecorder.startCount == 0)
    }

    @Test func explicitStopOnlyStopsActiveRecording() async {
        let idleRecorder = RecordingActionRecorder()
        let idleController = makeController(recorder: idleRecorder)

        await idleController.stopRecordingAction()

        #expect(idleController.status == .idle)
        #expect(idleRecorder.stopCount == 0)

        let recordingRecorder = RecordingActionRecorder(currentStatus: .recording)
        let transcriptionService = RecordingActionTranscriptionService(result: " accepted text ")
        let transcriptOutput = RecordingActionTranscriptOutput()
        let recordingController = makeController(
            recorder: recordingRecorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording
        )

        await recordingController.stopRecordingAction()
        await recordingController.stopRecordingAction()

        #expect(recordingController.status == .success(transcript: "accepted text"))
        #expect(recordingRecorder.stopCount == 1)
        #expect(transcriptionService.calls.count == 1)
        #expect(transcriptOutput.calls == ["accepted text"])
    }

    @Test func overlappingStartRequestsUseOneRecorderStart() async {
        let gate = AsyncGate()
        let recorder = RecordingActionRecorder(
            onStart: {
                await gate.wait()
            }
        )
        let controller = makeController(recorder: recorder)

        let firstStart = Task { @MainActor in
            await controller.startRecordingAction()
        }
        await yieldUntil { recorder.startCount == 1 }

        let secondStart = Task { @MainActor in
            await controller.startRecordingAction()
        }
        await Task.yield()

        #expect(recorder.startCount == 1)

        await gate.open()
        await firstStart.value
        await secondStart.value

        #expect(controller.status == .recording)
        #expect(recorder.startCount == 1)
        #expect(recorder.stopCount == 0)
    }

    @Test func overlappingStopRequestsUseOneTranscription() async {
        let gate = AsyncGate()
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/vibetype-recording-action-stop.m4a"),
            duration: 1.1,
            byteCount: 4096
        )
        let recorder = RecordingActionRecorder(
            currentStatus: .recording,
            onStop: {
                await gate.wait()
                return artifact
            }
        )
        let transcriptionService = RecordingActionTranscriptionService(result: "One transcript")
        let transcriptOutput = RecordingActionTranscriptOutput()
        let controller = makeController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            transcriptOutput: transcriptOutput,
            initialStatus: .recording
        )

        let firstStop = Task { @MainActor in
            await controller.stopRecordingAction()
        }
        await yieldUntil { recorder.stopCount == 1 }

        let secondStop = Task { @MainActor in
            await controller.stopRecordingAction()
        }
        await Task.yield()

        #expect(recorder.stopCount == 1)

        await gate.open()
        await firstStop.value
        await secondStop.value

        #expect(controller.status == .success(transcript: "One transcript"))
        #expect(recorder.stopCount == 1)
        #expect(transcriptionService.calls == [artifact.fileURL])
        #expect(transcriptOutput.calls == ["One transcript"])
    }

    private func makeController(
        recorder: RecordingActionRecorder,
        transcriptionService: RecordingActionTranscriptionService = RecordingActionTranscriptionService(),
        transcriptOutput: RecordingActionTranscriptOutput = RecordingActionTranscriptOutput(),
        initialStatus: DictationStatus = .idle
    ) -> DictationSessionController {
        DictationSessionController(
            recorder: recorder,
            transcriptionService: transcriptionService,
            settingsProvider: { .defaults },
            transcriptOutput: transcriptOutput,
            initialStatus: initialStatus
        )
    }

    private func yieldUntil(_ condition: () -> Bool) async {
        for _ in 0..<20 {
            if condition() {
                return
            }

            await Task.yield()
        }
    }
}

private actor AsyncGate {
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

private final class RecordingActionRecorder: AudioRecorderService {
    private let artifact: AudioRecordingArtifact
    private let onStart: (() async throws -> Void)?
    private let onStop: (() async throws -> AudioRecordingArtifact)?

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    private(set) var currentStatus: AudioRecorderStatus

    init(
        currentStatus: AudioRecorderStatus = .idle,
        artifact: AudioRecordingArtifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/vibetype-recording-action.m4a"),
            duration: 1.2,
            byteCount: 1024
        ),
        onStart: (() async throws -> Void)? = nil,
        onStop: (() async throws -> AudioRecordingArtifact)? = nil
    ) {
        self.currentStatus = currentStatus
        self.artifact = artifact
        self.onStart = onStart
        self.onStop = onStop
    }

    func startRecording() async throws {
        startCount += 1
        try await onStart?()
        currentStatus = .recording
    }

    func stopRecording() async throws -> AudioRecordingArtifact {
        stopCount += 1

        if let onStop {
            let stoppedArtifact = try await onStop()
            currentStatus = .finished(artifact: stoppedArtifact)
            return stoppedArtifact
        }

        currentStatus = .finished(artifact: artifact)
        return artifact
    }

    func cancelRecording() {
        cancelCount += 1
        currentStatus = .cancelled
    }
}

private final class RecordingActionTranscriptionService: OpenAITranscriptionServing {
    private let result: String
    private(set) var calls: [URL] = []

    init(result: String = "Controller transcript") {
        self.result = result
    }

    func transcribe(audioFileURL: URL, settings: AppSettings) async throws -> String {
        calls.append(audioFileURL)
        return result
    }
}

private final class RecordingActionTranscriptOutput: TranscriptOutputDelivering {
    private(set) var calls: [String] = []

    func deliver(_ transcript: String, settings: AppSettings) async throws -> TextInsertionResult {
        calls.append(transcript)
        return .skipped(reason: .appClipboardDisabled)
    }
}
