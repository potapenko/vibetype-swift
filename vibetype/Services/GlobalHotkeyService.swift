//
//  GlobalHotkeyService.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import Foundation

enum GlobalHotkeyModifier: String, CaseIterable, Equatable {
    case control
    case option
    case shift
    case command

    var displayName: String {
        switch self {
        case .control:
            return "Control"
        case .option:
            return "Option"
        case .shift:
            return "Shift"
        case .command:
            return "Command"
        }
    }
}

struct GlobalHotkeyShortcut: Equatable {
    static let defaultDictation = GlobalHotkeyShortcut(
        modifiers: [],
        key: "Right Command"
    )

    static let fallbackDictation = GlobalHotkeyShortcut(
        modifiers: [],
        key: "Globe/Fn"
    )

    var modifiers: [GlobalHotkeyModifier]
    var key: String

    var displayText: String {
        (modifiers.map(\.displayName) + [key]).joined(separator: "+")
    }
}

enum GlobalHotkeyActivationMode: Equatable {
    case holdToRecord
    case toggle

    var stopsRecordingOnKeyUp: Bool {
        self == .holdToRecord
    }

    var displayName: String {
        switch self {
        case .holdToRecord:
            return "Hold to record"
        case .toggle:
            return "Toggle"
        }
    }

    func recordingCommand(
        for action: GlobalHotkeyAction,
        isRecording: Bool,
        isShortcutPressed: Bool
    ) -> GlobalHotkeyRecordingCommand? {
        switch self {
        case .holdToRecord:
            switch action {
            case .keyDown where !isShortcutPressed && !isRecording:
                return .startRecording
            case .keyUp where isShortcutPressed && isRecording:
                return .stopRecording
            default:
                return nil
            }
        case .toggle:
            switch action {
            case .keyDown where !isShortcutPressed && isRecording:
                return .stopRecording
            case .keyDown where !isShortcutPressed:
                return .startRecording
            case .keyUp:
                return nil
            default:
                return nil
            }
        }
    }
}

struct GlobalHotkeyConfiguration: Equatable {
    static let defaultDictation = GlobalHotkeyConfiguration(
        shortcut: .defaultDictation,
        activationMode: .holdToRecord
    )

    static let fallbackDictation = GlobalHotkeyConfiguration(
        shortcut: .fallbackDictation,
        activationMode: .holdToRecord
    )

    var shortcut: GlobalHotkeyShortcut
    var activationMode: GlobalHotkeyActivationMode

    var displayText: String {
        "\(shortcut.displayText) - \(activationMode.displayName)"
    }

    var stopsRecordingOnKeyUp: Bool {
        activationMode.stopsRecordingOnKeyUp
    }

    func recordingCommand(
        for action: GlobalHotkeyAction,
        isRecording: Bool,
        isShortcutPressed: Bool
    ) -> GlobalHotkeyRecordingCommand? {
        activationMode.recordingCommand(
            for: action,
            isRecording: isRecording,
            isShortcutPressed: isShortcutPressed
        )
    }
}

enum GlobalHotkeyAction: Equatable {
    case keyDown
    case keyUp
}

enum GlobalHotkeyRecordingCommand: Equatable {
    case startRecording
    case stopRecording
}

enum GlobalHotkeyRegistrationStatus: Equatable {
    case notRegistered
    case registered(GlobalHotkeyConfiguration)
    case fallbackRegistered(GlobalHotkeyConfiguration)
    case unavailable(message: String)

    var activeConfiguration: GlobalHotkeyConfiguration? {
        switch self {
        case .registered(let configuration), .fallbackRegistered(let configuration):
            return configuration
        case .notRegistered, .unavailable:
            return nil
        }
    }

    var isRegistered: Bool {
        activeConfiguration != nil
    }

    var displayText: String {
        switch self {
        case .registered(let configuration):
            return configuration.displayText
        case .fallbackRegistered(let configuration):
            return "\(configuration.displayText) fallback"
        case .notRegistered:
            return "No global hotkey registered"
        case .unavailable:
            return "Global hotkey unavailable"
        }
    }
}

enum GlobalHotkeyServiceError: Error, Equatable, LocalizedError {
    case registrationUnavailable(message: String)

    var errorDescription: String? {
        switch self {
        case .registrationUnavailable(let message):
            return message
        }
    }
}

typealias GlobalHotkeyActionHandler = (GlobalHotkeyAction) -> Void

protocol GlobalHotkeyService {
    var preferredConfiguration: GlobalHotkeyConfiguration { get }
    var currentRegistrationStatus: GlobalHotkeyRegistrationStatus { get }

    func startListening(actionHandler: @escaping GlobalHotkeyActionHandler) throws
    func stopListening()
}
