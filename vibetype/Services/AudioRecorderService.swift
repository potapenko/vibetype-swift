//
//  AudioRecorderService.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import AVFoundation
import Foundation

struct AudioRecordingArtifact: Equatable {
    let fileURL: URL
    let duration: TimeInterval
    let byteCount: Int64
}

enum AudioRecorderStatus: Equatable {
    case idle
    case recording
    case finished(artifact: AudioRecordingArtifact)
    case cancelled
    case failed(message: String)

    var isRecording: Bool {
        self == .recording
    }
}

protocol AudioRecorderService {
    var currentStatus: AudioRecorderStatus { get }

    func startRecording() async throws
    func stopRecording() async throws -> AudioRecordingArtifact
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
    case cancelCleanupFailed
    case missingRecordingFile
    case emptyRecording
    case recordingTooShort(duration: TimeInterval, minimumDuration: TimeInterval)
    case recordingTimedOut(duration: TimeInterval, maximumDuration: TimeInterval)

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
        case .cancelCleanupFailed:
            return "Could not remove the canceled recording."
        case .missingRecordingFile:
            return "The completed recording file is missing."
        case .emptyRecording:
            return "No audio was captured. Try recording again."
        case .recordingTooShort:
            return "Recording was too short. Try speaking for a little longer."
        case .recordingTimedOut:
            return "Recording reached the maximum length. Try again with a shorter dictation."
        }
    }
}

protocol AudioRecorderEngine: AnyObject {
    var isRecording: Bool { get }
    var currentTime: TimeInterval { get }

    func record() -> Bool
    func record(forDuration duration: TimeInterval) -> Bool
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
    static let defaultMaximumRecordingDuration: TimeInterval = 300

    private let permissionStatusProvider: () -> MicrophonePermissionStatus
    private let recorderFactory: any AudioRecorderEngineFactory
    private let makeRecordingFileURL: () throws -> URL
    private let fileManager: FileManager
    private let minimumRecordingDuration: TimeInterval
    private let maximumRecordingDuration: TimeInterval

    private var activeRecorder: (any AudioRecorderEngine)?
    private var activeFileURL: URL?

    private(set) var currentStatus: AudioRecorderStatus = .idle

    init(
        permissionStatusProvider: @escaping () -> MicrophonePermissionStatus = {
            MicrophonePermissionService().currentStatus()
        },
        recorderFactory: any AudioRecorderEngineFactory = AVFoundationAudioRecorderEngineFactory(),
        fileManager: FileManager = .default,
        minimumRecordingDuration: TimeInterval = 0.3,
        maximumRecordingDuration: TimeInterval = AVFoundationAudioRecorderService.defaultMaximumRecordingDuration,
        makeRecordingFileURL: @escaping () throws -> URL = {
            try AVFoundationAudioRecorderService.makeDefaultRecordingFileURL()
        }
    ) {
        self.permissionStatusProvider = permissionStatusProvider
        self.recorderFactory = recorderFactory
        self.fileManager = fileManager
        self.minimumRecordingDuration = minimumRecordingDuration
        self.maximumRecordingDuration = maximumRecordingDuration > 0
            ? maximumRecordingDuration
            : Self.defaultMaximumRecordingDuration
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

            guard recorder.record(forDuration: maximumRecordingDuration) else {
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

    func stopRecording() async throws -> AudioRecordingArtifact {
        guard let recorder = activeRecorder, let outputFileURL = activeFileURL else {
            throw AudioRecorderServiceError.notRecording
        }

        let duration = max(0, recorder.currentTime)
        recorder.stop()
        activeRecorder = nil
        activeFileURL = nil

        do {
            let artifact = try recordingArtifact(at: outputFileURL, duration: duration)
            currentStatus = .finished(artifact: artifact)
            return artifact
        } catch let error as AudioRecorderServiceError {
            recorder.deleteRecording()
            fail(with: error)
            throw error
        } catch {
            let serviceError = AudioRecorderServiceError.stopFailed
            recorder.deleteRecording()
            fail(with: serviceError)
            throw serviceError
        }
    }

    func cancelRecording() {
        let recorder = activeRecorder
        let outputFileURL = activeFileURL

        recorder?.stop()
        recorder?.deleteRecording()
        activeRecorder = nil
        activeFileURL = nil

        do {
            try removeRecordingFileIfPresent(at: outputFileURL)
        } catch {
            fail(with: .cancelCleanupFailed)
            return
        }

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

    private func recordingArtifact(at outputFileURL: URL, duration: TimeInterval) throws -> AudioRecordingArtifact {
        let path = outputFileURL.path
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw AudioRecorderServiceError.missingRecordingFile
        }

        let attributes = try fileManager.attributesOfItem(atPath: path)
        guard let fileSize = attributes[.size] as? NSNumber else {
            throw AudioRecorderServiceError.stopFailed
        }

        let byteCount = fileSize.int64Value
        guard byteCount > 0 else {
            throw AudioRecorderServiceError.emptyRecording
        }

        guard duration >= minimumRecordingDuration else {
            throw AudioRecorderServiceError.recordingTooShort(
                duration: duration,
                minimumDuration: minimumRecordingDuration
            )
        }

        guard duration < maximumRecordingDuration else {
            throw AudioRecorderServiceError.recordingTimedOut(
                duration: duration,
                maximumDuration: maximumRecordingDuration
            )
        }

        return AudioRecordingArtifact(
            fileURL: outputFileURL,
            duration: duration,
            byteCount: byteCount
        )
    }

    private func removeRecordingFileIfPresent(at outputFileURL: URL?) throws {
        guard let outputFileURL else {
            return
        }

        let path = outputFileURL.path
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return
        }

        guard !isDirectory.boolValue else {
            throw AudioRecorderServiceError.cancelCleanupFailed
        }

        try fileManager.removeItem(at: outputFileURL)
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
