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
    var stopResult: Result<URL, AudioRecorderServiceError>

    init(
        currentStatus: AudioRecorderStatus = .idle,
        startResult: Result<Void, AudioRecorderServiceError> = .success(()),
        stopResult: Result<URL, AudioRecorderServiceError> = .success(
            URL(fileURLWithPath: "/tmp/vibetype-fake-recording.m4a")
        )
    ) {
        self.currentStatus = currentStatus
        self.startResult = startResult
        self.stopResult = stopResult
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

    func stopRecording() async throws -> URL {
        stopCount += 1

        do {
            let audioFileURL = try stopResult.get()
            currentStatus = .finished(audioFileURL: audioFileURL)
            return audioFileURL
        } catch let error as AudioRecorderServiceError {
            currentStatus = .failed(message: error.errorDescription ?? error.localizedDescription)
            throw error
        }
    }

    func cancelRecording() {
        cancelCount += 1
        currentStatus = .cancelled
    }
}
