//
//  PermissionsService.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import AVFoundation

enum MicrophonePermissionStatus: Equatable {
    case allowed
    case denied
    case notDetermined
    case unavailable

    var canRecord: Bool {
        self == .allowed
    }
}

enum MicrophoneAuthorizationStatus: Equatable {
    case allowed
    case denied
    case notDetermined
}

protocol MicrophonePermissionClient {
    var hasAvailableAudioInput: Bool { get }

    func authorizationStatus() -> MicrophoneAuthorizationStatus
    func requestAccess(completion: @escaping (Bool) -> Void)
}

struct AVFoundationMicrophonePermissionClient: MicrophonePermissionClient {
    var hasAvailableAudioInput: Bool {
        AVCaptureDevice.default(for: .audio) != nil
    }

    func authorizationStatus() -> MicrophoneAuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .allowed
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }
}

struct MicrophonePermissionService {
    private let client: MicrophonePermissionClient

    init(client: MicrophonePermissionClient = AVFoundationMicrophonePermissionClient()) {
        self.client = client
    }

    func currentStatus() -> MicrophonePermissionStatus {
        guard client.hasAvailableAudioInput else {
            return .unavailable
        }

        return status(for: client.authorizationStatus())
    }

    func requestPermission(completion: @escaping (MicrophonePermissionStatus) -> Void) {
        guard client.hasAvailableAudioInput else {
            completion(.unavailable)
            return
        }

        switch client.authorizationStatus() {
        case .allowed:
            completion(.allowed)
        case .denied:
            completion(.denied)
        case .notDetermined:
            client.requestAccess { isAllowed in
                completion(isAllowed ? .allowed : .denied)
            }
        }
    }

    private func status(for authorizationStatus: MicrophoneAuthorizationStatus) -> MicrophonePermissionStatus {
        switch authorizationStatus {
        case .allowed:
            return .allowed
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        }
    }
}
