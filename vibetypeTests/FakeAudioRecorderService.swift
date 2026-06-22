//
//  FakeAudioRecorderService.swift
//  vibetypeTests
//
//  Created by Codex on 6/20/26.
//

import Foundation
@testable import vibetype

final class FakeAudioRecorderService: AudioRecorderService {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    private(set) var currentStatus: AudioRecorderStatus

    var startResult: Result<Void, AudioRecorderServiceError>
    var stopResult: Result<AudioRecordingArtifact, AudioRecorderServiceError>
    var cancelStatus: AudioRecorderStatus

    init(
        currentStatus: AudioRecorderStatus = .idle,
        startResult: Result<Void, AudioRecorderServiceError> = .success(()),
        stopResult: Result<AudioRecordingArtifact, AudioRecorderServiceError> = .success(
            AudioRecordingArtifact(
                fileURL: URL(fileURLWithPath: "/tmp/vibetype-fake-recording.m4a"),
                duration: 1.2,
                byteCount: 1024
            )
        ),
        cancelStatus: AudioRecorderStatus = .cancelled
    ) {
        self.currentStatus = currentStatus
        self.startResult = startResult
        self.stopResult = stopResult
        self.cancelStatus = cancelStatus
    }

    func startRecording() async throws {
        startCount += 1

        do {
            try startResult.get()
            currentStatus = .recording
        } catch let error as AudioRecorderServiceError {
            currentStatus = .failed(message: error.errorDescription ?? error.localizedDescription)
            throw error
        }
    }

    func stopRecording() async throws -> AudioRecordingArtifact {
        stopCount += 1

        do {
            let artifact = try stopResult.get()
            currentStatus = .finished(artifact: artifact)
            return artifact
        } catch let error as AudioRecorderServiceError {
            currentStatus = .failed(message: error.errorDescription ?? error.localizedDescription)
            throw error
        }
    }

    func cancelRecording() {
        cancelCount += 1
        currentStatus = cancelStatus
    }
}
