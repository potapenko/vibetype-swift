//
//  AudioRecorderServiceTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/20/26.
//

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
}

private struct RecorderConsumer {
    let recorder: any AudioRecorderService

    func recordOnce() async throws -> URL {
        try await recorder.startRecording()
        return try await recorder.stopRecording()
    }
}
