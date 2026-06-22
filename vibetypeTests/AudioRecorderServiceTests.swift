//
//  AudioRecorderServiceTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/20/26.
//

import AVFoundation
import Foundation
import Testing
@testable import vibetype

struct AudioRecorderServiceTests {

    @Test func statusExposesRecordingState() {
        #expect(AudioRecorderStatus.idle.isRecording == false)
        #expect(AudioRecorderStatus.recording.isRecording)
        #expect(
            AudioRecorderStatus.finished(
                audioFileURL: URL(fileURLWithPath: "/tmp/vibetype-test.m4a")
            ).isRecording == false
        )
        #expect(AudioRecorderStatus.cancelled.isRecording == false)
    }

    @Test func fakeRecorderTracksSuccessfulLifecycle() async throws {
        let audioFileURL = URL(fileURLWithPath: "/tmp/vibetype-success.m4a")
        let recorder = FakeAudioRecorderService(stopResult: .success(audioFileURL))

        #expect(recorder.currentStatus == .idle)

        try await recorder.startRecording()
        #expect(recorder.currentStatus == .recording)

        let stoppedFileURL = try await recorder.stopRecording()

        #expect(stoppedFileURL == audioFileURL)
        #expect(recorder.currentStatus == .finished(audioFileURL: audioFileURL))
        #expect(recorder.startCount == 1)
        #expect(recorder.stopCount == 1)
        #expect(recorder.cancelCount == 0)
    }

    @Test func fakeRecorderCanSimulateStartFailure() async {
        let recorder = FakeAudioRecorderService(
            startResult: .failure(.recordingUnavailable)
        )

        do {
            try await recorder.startRecording()
            Issue.record("Expected startRecording to throw")
        } catch let error as AudioRecorderServiceError {
            #expect(error == .recordingUnavailable)
        } catch {
            Issue.record("Expected AudioRecorderServiceError, got \(error)")
        }

        #expect(
            recorder.currentStatus == .failed(
                message: AudioRecorderServiceError.recordingUnavailable.errorDescription ?? ""
            )
        )
        #expect(recorder.startCount == 1)
        #expect(recorder.stopCount == 0)
    }

    @Test func fakeRecorderCanSimulateStopFailure() async throws {
        let recorder = FakeAudioRecorderService(stopResult: .failure(.stopFailed))

        try await recorder.startRecording()

        do {
            _ = try await recorder.stopRecording()
            Issue.record("Expected stopRecording to throw")
        } catch let error as AudioRecorderServiceError {
            #expect(error == .stopFailed)
        } catch {
            Issue.record("Expected AudioRecorderServiceError, got \(error)")
        }

        #expect(
            recorder.currentStatus == .failed(
                message: AudioRecorderServiceError.stopFailed.errorDescription ?? ""
            )
        )
        #expect(recorder.startCount == 1)
        #expect(recorder.stopCount == 1)
    }

    @Test func fakeRecorderCanCancelCurrentRecording() async throws {
        let recorder = FakeAudioRecorderService()

        try await recorder.startRecording()
        recorder.cancelRecording()

        #expect(recorder.currentStatus == .cancelled)
        #expect(recorder.cancelCount == 1)
    }

    @Test func appCodeCanDependOnRecorderProtocol() async throws {
        let audioFileURL = URL(fileURLWithPath: "/tmp/vibetype-protocol.m4a")
        let recorder = FakeAudioRecorderService(stopResult: .success(audioFileURL))
        let consumer = RecorderConsumer(recorder: recorder)

        let result = try await consumer.recordOnce()

        #expect(result == audioFileURL)
        #expect(recorder.currentStatus == .finished(audioFileURL: audioFileURL))
    }

    @Test func avFoundationRecorderRejectsStartWhenMicrophoneIsNotAllowed() async {
        let factory = CapturingAudioRecorderEngineFactory()
        let recorder = AVFoundationAudioRecorderService(
            permissionStatusProvider: { .denied },
            recorderFactory: factory,
            makeRecordingFileURL: { URL(fileURLWithPath: "/tmp/vibetype-denied.m4a") }
        )

        do {
            try await recorder.startRecording()
            Issue.record("Expected startRecording to throw")
        } catch let error as AudioRecorderServiceError {
            #expect(error == .microphonePermissionDenied)
        } catch {
            Issue.record("Expected AudioRecorderServiceError, got \(error)")
        }

        #expect(factory.makeRecorderCallCount == 0)
        #expect(
            recorder.currentStatus == .failed(
                message: AudioRecorderServiceError.microphonePermissionDenied.errorDescription ?? ""
            )
        )
    }

    @Test func avFoundationRecorderPreparesTemporaryM4ARecordingPath() async throws {
        let outputFileURL = URL(fileURLWithPath: "/tmp/vibetype-recording-\(UUID().uuidString).m4a")
        let engine = FakeAudioRecorderEngine()
        let factory = CapturingAudioRecorderEngineFactory(engine: engine)
        let recorder = AVFoundationAudioRecorderService(
            permissionStatusProvider: { .allowed },
            recorderFactory: factory,
            makeRecordingFileURL: { outputFileURL }
        )

        try await recorder.startRecording()

        #expect(recorder.currentStatus == .recording)
        #expect(factory.makeRecorderCallCount == 1)
        #expect(factory.outputFileURL == outputFileURL)
        #expect(factory.settings?[AVFormatIDKey] as? Int == Int(kAudioFormatMPEG4AAC))
        #expect(factory.settings?[AVNumberOfChannelsKey] as? Int == 1)
        #expect(engine.recordCallCount == 1)
        #expect(engine.isRecording)

        let stoppedURL = try await recorder.stopRecording()

        #expect(stoppedURL == outputFileURL)
        #expect(recorder.currentStatus == .finished(audioFileURL: outputFileURL))
        #expect(engine.stopCallCount == 1)
    }

    @Test func avFoundationRecorderRejectsParallelStartWithoutLosingRecordingState() async throws {
        let outputFileURL = URL(fileURLWithPath: "/tmp/vibetype-parallel.m4a")
        let factory = CapturingAudioRecorderEngineFactory()
        let recorder = AVFoundationAudioRecorderService(
            permissionStatusProvider: { .allowed },
            recorderFactory: factory,
            makeRecordingFileURL: { outputFileURL }
        )

        try await recorder.startRecording()

        do {
            try await recorder.startRecording()
            Issue.record("Expected second startRecording to throw")
        } catch let error as AudioRecorderServiceError {
            #expect(error == .alreadyRecording)
        } catch {
            Issue.record("Expected AudioRecorderServiceError, got \(error)")
        }

        #expect(factory.makeRecorderCallCount == 1)
        #expect(recorder.currentStatus == .recording)
    }

    @Test func avFoundationRecorderDeletesPreparedFileWhenEngineCannotStart() async {
        let engine = FakeAudioRecorderEngine(recordResult: false)
        let factory = CapturingAudioRecorderEngineFactory(engine: engine)
        let recorder = AVFoundationAudioRecorderService(
            permissionStatusProvider: { .allowed },
            recorderFactory: factory,
            makeRecordingFileURL: { URL(fileURLWithPath: "/tmp/vibetype-start-failure.m4a") }
        )

        do {
            try await recorder.startRecording()
            Issue.record("Expected startRecording to throw")
        } catch let error as AudioRecorderServiceError {
            #expect(error == .startFailed)
        } catch {
            Issue.record("Expected AudioRecorderServiceError, got \(error)")
        }

        #expect(factory.makeRecorderCallCount == 1)
        #expect(engine.recordCallCount == 1)
        #expect(engine.deleteCallCount == 1)
        #expect(
            recorder.currentStatus == .failed(
                message: AudioRecorderServiceError.startFailed.errorDescription ?? ""
            )
        )
    }
}

private struct RecorderConsumer {
    let recorder: any AudioRecorderService

    func recordOnce() async throws -> URL {
        try await recorder.startRecording()
        return try await recorder.stopRecording()
    }
}

private final class CapturingAudioRecorderEngineFactory: AudioRecorderEngineFactory {
    private let engine: FakeAudioRecorderEngine

    private(set) var makeRecorderCallCount = 0
    private(set) var outputFileURL: URL?
    private(set) var settings: [String: Any]?

    init(engine: FakeAudioRecorderEngine = FakeAudioRecorderEngine()) {
        self.engine = engine
    }

    func makeRecorder(
        outputFileURL: URL,
        settings: [String: Any]
    ) throws -> any AudioRecorderEngine {
        makeRecorderCallCount += 1
        self.outputFileURL = outputFileURL
        self.settings = settings
        return engine
    }
}

private final class FakeAudioRecorderEngine: AudioRecorderEngine {
    private let recordResult: Bool

    private(set) var isRecording = false
    private(set) var recordCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var deleteCallCount = 0

    init(recordResult: Bool = true) {
        self.recordResult = recordResult
    }

    func record() -> Bool {
        recordCallCount += 1
        isRecording = recordResult
        return recordResult
    }

    func stop() {
        stopCallCount += 1
        isRecording = false
    }

    func deleteRecording() -> Bool {
        deleteCallCount += 1
        return true
    }
}
