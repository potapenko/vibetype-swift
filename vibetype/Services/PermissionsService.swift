//
//  PermissionsService.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import AppKit
import ApplicationServices
import AVFoundation

enum MicrophonePermissionStatus: Equatable {
    case allowed
    case denied
    case notDetermined
    case unavailable

    var canRecord: Bool {
        self == .allowed
    }

    var canUseRecordingAction: Bool {
        switch self {
        case .allowed, .notDetermined:
            return true
        case .denied, .unavailable:
            return false
        }
    }

    var menuStatusText: String {
        switch self {
        case .allowed:
            return "Microphone: Allowed"
        case .denied:
            return "Microphone: Not Allowed"
        case .notDetermined:
            return "Microphone: Permission Needed"
        case .unavailable:
            return "Microphone: Unavailable"
        }
    }

    var menuDetailText: String? {
        switch self {
        case .allowed:
            return nil
        case .denied:
            return "Recording is blocked until microphone access is allowed."
        case .notDetermined:
            return "Allow microphone access before starting dictation."
        case .unavailable:
            return "Recording is blocked because no microphone input is available."
        }
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

    @discardableResult
    func openMicrophoneSettings() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else {
            return false
        }

        return NSWorkspace.shared.open(url)
    }
}

enum AccessibilityPermissionStatus: Equatable {
    case trusted
    case notTrusted

    var canPasteIntoActiveApp: Bool {
        self == .trusted
    }

    var menuStatusText: String {
        switch self {
        case .trusted:
            return "Accessibility: Allowed"
        case .notTrusted:
            return "Accessibility: Not Allowed"
        }
    }

    var settingsDescription: String {
        switch self {
        case .trusted:
            return "Auto-paste can control the active app."
        case .notTrusted:
            return "Auto-paste needs Accessibility permission. Transcription and copy-only fallback can still work."
        }
    }

    var menuDetailText: String? {
        switch self {
        case .trusted:
            return nil
        case .notTrusted:
            return "Auto-paste is unavailable; transcripts can still be copied."
        }
    }
}

protocol AccessibilityPermissionClient {
    func isProcessTrusted(promptIfNeeded: Bool) -> Bool
    func openAccessibilitySettings() -> Bool
}

struct AXAccessibilityPermissionClient: AccessibilityPermissionClient {
    func isProcessTrusted(promptIfNeeded: Bool) -> Bool {
        guard promptIfNeeded else {
            return AXIsProcessTrusted()
        }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return false
        }

        return NSWorkspace.shared.open(url)
    }
}

struct AccessibilityPermissionService {
    private let client: AccessibilityPermissionClient

    init(client: AccessibilityPermissionClient = AXAccessibilityPermissionClient()) {
        self.client = client
    }

    func currentStatus() -> AccessibilityPermissionStatus {
        client.isProcessTrusted(promptIfNeeded: false) ? .trusted : .notTrusted
    }

    @discardableResult
    func openAccessibilitySettings() -> Bool {
        client.openAccessibilitySettings()
    }
}
