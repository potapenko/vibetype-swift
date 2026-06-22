//
//  AudioRecorderService.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import AVFoundation
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
    case microphonePermissionDenied
    case recordingUnavailable
    case temporaryFileUnavailable
    case startFailed
    case stopFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Recording is already in progress."
        case .notRecording:
            return "There is no active recording to stop."
        case .microphonePermissionDenied:
            return "Microphone access is required before recording can start."
        case .recordingUnavailable:
            return "Recording is unavailable on this Mac."
        case .temporaryFileUnavailable:
            return "Could not prepare a temporary recording file."
        case .startFailed:
            return "Could not start microphone recording."
        case .stopFailed:
            return "Could not finish the current recording."
        }
    }
}

protocol AudioRecorderEngine: AnyObject {
    var isRecording: Bool { get }

    func record() -> Bool
    func stop()
    @discardableResult func deleteRecording() -> Bool
}

extension AVAudioRecorder: AudioRecorderEngine {}

protocol AudioRecorderEngineFactory {
    func makeRecorder(
        outputFileURL: URL,
        settings: [String: Any]
    ) throws -> any AudioRecorderEngine
}

struct AVFoundationAudioRecorderEngineFactory: AudioRecorderEngineFactory {
    func makeRecorder(
        outputFileURL: URL,
        settings: [String: Any]
    ) throws -> any AudioRecorderEngine {
        let recorder = try AVAudioRecorder(url: outputFileURL, settings: settings)

        guard recorder.prepareToRecord() else {
            throw AudioRecorderServiceError.temporaryFileUnavailable
        }

        return recorder
    }
}

final class AVFoundationAudioRecorderService: AudioRecorderService {
    private static let temporaryDirectoryName = "vibetype-recordings"

    private let permissionStatusProvider: () -> MicrophonePermissionStatus
    private let recorderFactory: any AudioRecorderEngineFactory
    private let makeRecordingFileURL: () throws -> URL

    private var activeRecorder: (any AudioRecorderEngine)?
    private var activeFileURL: URL?

    private(set) var currentStatus: AudioRecorderStatus = .idle

    init(
        permissionStatusProvider: @escaping () -> MicrophonePermissionStatus = {
            MicrophonePermissionService().currentStatus()
        },
        recorderFactory: any AudioRecorderEngineFactory = AVFoundationAudioRecorderEngineFactory(),
        makeRecordingFileURL: @escaping () throws -> URL = {
            try AVFoundationAudioRecorderService.makeDefaultRecordingFileURL()
        }
    ) {
        self.permissionStatusProvider = permissionStatusProvider
        self.recorderFactory = recorderFactory
        self.makeRecordingFileURL = makeRecordingFileURL
    }

    func startRecording() async throws {
        let permissionStatus = permissionStatusProvider()
        guard permissionStatus.canRecord else {
            let error = startError(for: permissionStatus)
            fail(with: error)
            throw error
        }

        guard activeRecorder == nil else {
            throw AudioRecorderServiceError.alreadyRecording
        }

        do {
            let outputFileURL = try makeRecordingFileURL()
            let recorder = try recorderFactory.makeRecorder(
                outputFileURL: outputFileURL,
                settings: Self.recordingSettings
            )

            guard recorder.record() else {
                recorder.deleteRecording()
                let error = AudioRecorderServiceError.startFailed
                fail(with: error)
                throw error
            }

            activeRecorder = recorder
            activeFileURL = outputFileURL
            currentStatus = .recording
        } catch let error as AudioRecorderServiceError {
            fail(with: error)
            throw error
        } catch {
            let serviceError = AudioRecorderServiceError.recordingUnavailable
            fail(with: serviceError)
            throw serviceError
        }
    }

    func stopRecording() async throws -> URL {
        guard let recorder = activeRecorder, let outputFileURL = activeFileURL else {
            throw AudioRecorderServiceError.notRecording
        }

        recorder.stop()
        activeRecorder = nil
        activeFileURL = nil
        currentStatus = .finished(audioFileURL: outputFileURL)
        return outputFileURL
    }

    func cancelRecording() {
        activeRecorder?.stop()
        activeRecorder?.deleteRecording()
        activeRecorder = nil
        activeFileURL = nil
        currentStatus = .cancelled
    }

    private func startError(for permissionStatus: MicrophonePermissionStatus) -> AudioRecorderServiceError {
        switch permissionStatus {
        case .allowed:
            return .startFailed
        case .denied, .notDetermined:
            return .microphonePermissionDenied
        case .unavailable:
            return .recordingUnavailable
        }
    }

    private func fail(with error: AudioRecorderServiceError) {
        currentStatus = .failed(message: error.errorDescription ?? error.localizedDescription)
    }

    private static var recordingSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }

    private static func makeDefaultRecordingFileURL(
        fileManager: FileManager = .default,
        uuid: UUID = UUID()
    ) throws -> URL {
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(temporaryDirectoryName, isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw AudioRecorderServiceError.temporaryFileUnavailable
        }

        return directoryURL
            .appendingPathComponent("recording-\(uuid.uuidString)")
            .appendingPathExtension("m4a")
    }
}
