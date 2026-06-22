//
//  PermissionsService.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import AppKit
import ApplicationServices
import AVFoundation
import IOKit.hid

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

    var settingsStatusText: String {
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

    var settingsDescription: String {
        switch self {
        case .allowed:
            return "Recording can start after you choose a dictation action."
        case .denied:
            return "Recording is blocked until microphone access is allowed in System Settings."
        case .notDetermined:
            return "Request microphone access before starting dictation."
        case .unavailable:
            return "Recording is blocked because no microphone input is available."
        }
    }

    var settingsSystemImage: String {
        switch self {
        case .allowed:
            return "checkmark.circle"
        case .denied, .unavailable:
            return "xmark.octagon"
        case .notDetermined:
            return "exclamationmark.triangle"
        }
    }

    var settingsActionTitle: String? {
        switch self {
        case .allowed, .unavailable:
            return nil
        case .denied:
            return "Open Microphone Settings"
        case .notDetermined:
            return "Request Microphone Access"
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

    var canInsertTextIntoActiveApp: Bool {
        self == .trusted
    }

    var canPasteIntoActiveApp: Bool {
        canInsertTextIntoActiveApp
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
            return "Automatic insertion and VibeType Clipboard paste can insert text into the active app."
        case .notTrusted:
            return "Automatic insertion and VibeType Clipboard paste need Accessibility permission. Transcription can still save recovery text."
        }
    }

    var settingsStatusText: String {
        switch self {
        case .trusted:
            return "Accessibility: Allowed"
        case .notTrusted:
            return "Accessibility: Not Allowed"
        }
    }

    var settingsSystemImage: String {
        canInsertTextIntoActiveApp ? "checkmark.circle" : "exclamationmark.triangle"
    }

    var menuDetailText: String? {
        switch self {
        case .trusted:
            return nil
        case .notTrusted:
            return "Text insertion is unavailable until Accessibility is allowed."
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

enum InputMonitoringAuthorizationStatus: Equatable {
    case allowed
    case denied
    case notDetermined
}

enum InputMonitoringPermissionStatus: Equatable {
    case allowed
    case denied
    case notDetermined

    var settingsStatusText: String {
        switch self {
        case .allowed:
            return "Input Monitoring: Allowed"
        case .denied:
            return "Input Monitoring: Not Allowed"
        case .notDetermined:
            return "Input Monitoring: Permission Needed"
        }
    }

    var settingsDescription: String {
        switch self {
        case .allowed:
            return "Global dictation shortcuts can listen for key presses outside VibeType."
        case .denied:
            return "Global dictation shortcuts may be blocked until Input Monitoring is allowed in System Settings."
        case .notDetermined:
            return "Allow Input Monitoring when prompted if global dictation shortcuts need it."
        }
    }

    var settingsSystemImage: String {
        switch self {
        case .allowed:
            return "checkmark.circle"
        case .denied:
            return "xmark.octagon"
        case .notDetermined:
            return "exclamationmark.triangle"
        }
    }

    var settingsActionTitle: String? {
        switch self {
        case .allowed:
            return nil
        case .denied:
            return "Open Input Monitoring Settings"
        case .notDetermined:
            return "Request Input Monitoring Access"
        }
    }
}

protocol InputMonitoringPermissionClient {
    func authorizationStatus() -> InputMonitoringAuthorizationStatus
    func requestAccess() -> Bool
    func openInputMonitoringSettings() -> Bool
}

struct IOHIDInputMonitoringPermissionClient: InputMonitoringPermissionClient {
    func authorizationStatus() -> InputMonitoringAuthorizationStatus {
        let accessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)

        if accessType == kIOHIDAccessTypeGranted {
            return .allowed
        }

        if accessType == kIOHIDAccessTypeDenied {
            return .denied
        }

        return .notDetermined
    }

    func requestAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    func openInputMonitoringSettings() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else {
            return false
        }

        return NSWorkspace.shared.open(url)
    }
}

struct InputMonitoringPermissionService {
    private let client: InputMonitoringPermissionClient

    init(client: InputMonitoringPermissionClient = IOHIDInputMonitoringPermissionClient()) {
        self.client = client
    }

    func currentStatus() -> InputMonitoringPermissionStatus {
        switch client.authorizationStatus() {
        case .allowed:
            return .allowed
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        }
    }

    func requestPermission() -> InputMonitoringPermissionStatus {
        client.requestAccess() ? .allowed : currentStatus()
    }

    @discardableResult
    func openInputMonitoringSettings() -> Bool {
        client.openInputMonitoringSettings()
    }
}
