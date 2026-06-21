//
//  AudioRecorderService.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import Foundation

enum AudioRecorderStatus: Equatable {
    case idle
    case recording
    case finished(audioFileURL: URL)
    case cancelled
    case failed(message: String)

    var isRecording: Bool {
        self == .recording
    }
}

protocol AudioRecorderService {
    var currentStatus: AudioRecorderStatus { get }

    func startRecording() async throws
    func stopRecording() async throws -> URL
    func cancelRecording()
}

enum AudioRecorderServiceError: Error, Equatable, LocalizedError {
    case alreadyRecording
    case notRecording
    case recordingUnavailable
    case stopFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Recording is already in progress."
        case .notRecording:
            return "There is no active recording to stop."
        case .recordingUnavailable:
            return "Recording is unavailable on this Mac."
        case .stopFailed:
            return "Could not finish the current recording."
        }
    }
}
