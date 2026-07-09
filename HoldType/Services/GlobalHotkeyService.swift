//
//  GlobalHotkeyService.swift
//  HoldType
//
//  Created by Codex on 6/20/26.
//

import Foundation
import HoldTypeDomain

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

    var menuSymbol: String {
        switch self {
        case .control:
            return "\u{2303}"
        case .option:
            return "\u{2325}"
        case .shift:
            return "\u{21e7}"
        case .command:
            return "\u{2318}"
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

    static let translationDictation = GlobalHotkeyShortcut(
        modifiers: [.option],
        key: "Right Command"
    )

    static let appClipboardPaste = GlobalHotkeyShortcut(
        modifiers: [.control, .command],
        key: "V"
    )

    var modifiers: [GlobalHotkeyModifier]
    var key: String

    var displayText: String {
        (modifiers.map(\.displayName) + [key]).joined(separator: "+")
    }

    var menuKeyEquivalentText: String {
        modifiers.map(\.menuSymbol).joined() + key
    }

    var menuHoldText: String {
        let holdParts = [Self.menuKeyText(for: key)] + modifiers.map(Self.menuHoldModifierText)
        return "Hold " + holdParts.joined(separator: " + ")
    }

    private static func menuKeyText(for key: String) -> String {
        switch key {
        case "Right Command":
            return "Right \u{2318}"
        case "Left Command":
            return "Left \u{2318}"
        case "Right Option":
            return "Right \u{2325}"
        case "Left Option":
            return "Left \u{2325}"
        default:
            return key
        }
    }

    private static func menuHoldModifierText(for modifier: GlobalHotkeyModifier) -> String {
        switch modifier {
        case .option:
            return "Right \u{2325}"
        case .command:
            return "Right \u{2318}"
        case .control:
            return "Control"
        case .shift:
            return "Shift"
        }
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
    case outputIntentChanged
}

struct GlobalHotkeyEvent: Equatable {
    let action: GlobalHotkeyAction
    let outputIntent: DictationOutputIntent

    static func keyDown(outputIntent: DictationOutputIntent = .standard) -> GlobalHotkeyEvent {
        GlobalHotkeyEvent(action: .keyDown, outputIntent: outputIntent)
    }

    static func keyUp(outputIntent: DictationOutputIntent = .standard) -> GlobalHotkeyEvent {
        GlobalHotkeyEvent(action: .keyUp, outputIntent: outputIntent)
    }

    static func outputIntentChanged(to outputIntent: DictationOutputIntent) -> GlobalHotkeyEvent {
        GlobalHotkeyEvent(action: .outputIntentChanged, outputIntent: outputIntent)
    }
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

typealias GlobalHotkeyActionHandler = (GlobalHotkeyEvent) -> Void

protocol GlobalHotkeyService {
    var preferredConfiguration: GlobalHotkeyConfiguration { get }
    var currentRegistrationStatus: GlobalHotkeyRegistrationStatus { get }

    func startListening(actionHandler: @escaping GlobalHotkeyActionHandler) throws
    func stopListening()
}
