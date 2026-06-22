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
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/vibetype-test.m4a"),
            duration: 1.2,
            byteCount: 512
        )

        #expect(AudioRecorderStatus.idle.isRecording == false)
        #expect(AudioRecorderStatus.recording.isRecording)
        #expect(AudioRecorderStatus.finished(artifact: artifact).isRecording == false)
        #expect(AudioRecorderStatus.cancelled.isRecording == false)
    }

    @Test func fakeRecorderTracksSuccessfulLifecycle() async throws {
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/vibetype-success.m4a"),
            duration: 1.4,
            byteCount: 2048
        )
        let recorder = FakeAudioRecorderService(stopResult: .success(artifact))

        #expect(recorder.currentStatus == .idle)

        try await recorder.startRecording()
        #expect(recorder.currentStatus == .recording)

        let stoppedArtifact = try await recorder.stopRecording()

        #expect(stoppedArtifact == artifact)
        #expect(recorder.currentStatus == .finished(artifact: artifact))
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
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/vibetype-protocol.m4a"),
            duration: 0.8,
            byteCount: 300
        )
        let recorder = FakeAudioRecorderService(stopResult: .success(artifact))
        let consumer = RecorderConsumer(recorder: recorder)

        let result = try await consumer.recordOnce()

        #expect(result == artifact)
        #expect(recorder.currentStatus == .finished(artifact: artifact))
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

    @Test func avFoundationRecorderReturnsCompletedArtifactMetadata() async throws {
        let outputFileURL = makeTemporaryRecordingFileURL()
        let fileContents = Data([0x01, 0x02, 0x03, 0x04])
        let engine = FakeAudioRecorderEngine(currentTime: 1.7)
        let factory = CapturingAudioRecorderEngineFactory(engine: engine)
        let recorder = AVFoundationAudioRecorderService(
            permissionStatusProvider: { .allowed },
            recorderFactory: factory,
            makeRecordingFileURL: { outputFileURL }
        )
        defer { try? FileManager.default.removeItem(at: outputFileURL) }

        try await recorder.startRecording()

        #expect(recorder.currentStatus == .recording)
        #expect(factory.makeRecorderCallCount == 1)
        #expect(factory.outputFileURL == outputFileURL)
        #expect(factory.settings?[AVFormatIDKey] as? Int == Int(kAudioFormatMPEG4AAC))
        #expect(factory.settings?[AVNumberOfChannelsKey] as? Int == 1)
        #expect(engine.recordCallCount == 1)
        #expect(engine.isRecording)

        try fileContents.write(to: outputFileURL)

        let artifact = try await recorder.stopRecording()

        #expect(artifact.fileURL == outputFileURL)
        #expect(artifact.duration == 1.7)
        #expect(artifact.byteCount == Int64(fileContents.count))
        #expect(recorder.currentStatus == .finished(artifact: artifact))
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

    @Test func avFoundationRecorderRejectsMissingCompletedFile() async throws {
        let outputFileURL = makeTemporaryRecordingFileURL()
        let engine = FakeAudioRecorderEngine(currentTime: 1.0)
        let factory = CapturingAudioRecorderEngineFactory(engine: engine)
        let recorder = AVFoundationAudioRecorderService(
            permissionStatusProvider: { .allowed },
            recorderFactory: factory,
            makeRecordingFileURL: { outputFileURL }
        )

        try await recorder.startRecording()

        do {
            _ = try await recorder.stopRecording()
            Issue.record("Expected stopRecording to throw")
        } catch let error as AudioRecorderServiceError {
            #expect(error == .missingRecordingFile)
        } catch {
            Issue.record("Expected AudioRecorderServiceError, got \(error)")
        }

        #expect(engine.stopCallCount == 1)
        #expect(engine.deleteCallCount == 1)
        #expect(
            recorder.currentStatus == .failed(
                message: AudioRecorderServiceError.missingRecordingFile.errorDescription ?? ""
            )
        )
    }

    @Test func avFoundationRecorderRejectsEmptyCompletedFile() async throws {
        let outputFileURL = makeTemporaryRecordingFileURL()
        let engine = FakeAudioRecorderEngine(currentTime: 1.0)
        let factory = CapturingAudioRecorderEngineFactory(engine: engine)
        let recorder = AVFoundationAudioRecorderService(
            permissionStatusProvider: { .allowed },
            recorderFactory: factory,
            makeRecordingFileURL: { outputFileURL }
        )
        defer { try? FileManager.default.removeItem(at: outputFileURL) }

        try await recorder.startRecording()
        try Data().write(to: outputFileURL)

        do {
            _ = try await recorder.stopRecording()
            Issue.record("Expected stopRecording to throw")
        } catch let error as AudioRecorderServiceError {
            #expect(error == .emptyRecording)
        } catch {
            Issue.record("Expected AudioRecorderServiceError, got \(error)")
        }

        #expect(engine.stopCallCount == 1)
        #expect(engine.deleteCallCount == 1)
        #expect(
            recorder.currentStatus == .failed(
                message: AudioRecorderServiceError.emptyRecording.errorDescription ?? ""
            )
        )
    }

    @Test func avFoundationRecorderRejectsTooShortCompletedFile() async throws {
        let outputFileURL = makeTemporaryRecordingFileURL()
        let engine = FakeAudioRecorderEngine(currentTime: 0.1)
        let factory = CapturingAudioRecorderEngineFactory(engine: engine)
        let recorder = AVFoundationAudioRecorderService(
            permissionStatusProvider: { .allowed },
            recorderFactory: factory,
            minimumRecordingDuration: 0.5,
            makeRecordingFileURL: { outputFileURL }
        )
        defer { try? FileManager.default.removeItem(at: outputFileURL) }

        try await recorder.startRecording()
        try Data([0x01]).write(to: outputFileURL)

        do {
            _ = try await recorder.stopRecording()
            Issue.record("Expected stopRecording to throw")
        } catch let error as AudioRecorderServiceError {
            #expect(error == .recordingTooShort(duration: 0.1, minimumDuration: 0.5))
        } catch {
            Issue.record("Expected AudioRecorderServiceError, got \(error)")
        }

        #expect(engine.stopCallCount == 1)
        #expect(engine.deleteCallCount == 1)
        #expect(
            recorder.currentStatus == .failed(
                message: AudioRecorderServiceError.recordingTooShort(
                    duration: 0.1,
                    minimumDuration: 0.5
                ).errorDescription ?? ""
            )
        )
    }
}

private struct RecorderConsumer {
    let recorder: any AudioRecorderService

    func recordOnce() async throws -> AudioRecordingArtifact {
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
    let currentTime: TimeInterval
    private(set) var recordCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var deleteCallCount = 0

    init(recordResult: Bool = true, currentTime: TimeInterval = 1.0) {
        self.recordResult = recordResult
        self.currentTime = currentTime
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

private func makeTemporaryRecordingFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("vibetype-test-recording-\(UUID().uuidString)")
        .appendingPathExtension("m4a")
}
