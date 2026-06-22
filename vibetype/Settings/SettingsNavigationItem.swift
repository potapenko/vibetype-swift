//
//  SettingsNavigationItem.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import Foundation

enum SettingsNavigationItem: String, CaseIterable, Identifiable, Hashable {
    case general
    case openAI
    case transcription
    case dictionary
    case shortcut
    case behavior
    case privacy

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .openAI:
            return "OpenAI"
        case .transcription:
            return "Transcription"
        case .dictionary:
            return "Dictionary"
        case .shortcut:
            return "Shortcut"
        case .behavior:
            return "Behavior"
        case .privacy:
            return "Privacy"
        }
    }

    var detail: String? {
        switch self {
        case .general:
            return "Setup status"
        case .openAI:
            return "API key"
        case .transcription:
            return "Model and language"
        case .dictionary:
            return "Custom words"
        case .shortcut:
            return "Global hotkey"
        case .behavior:
            return "Output and indicator"
        case .privacy:
            return "Permissions"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .openAI:
            return "key"
        case .transcription:
            return "waveform"
        case .dictionary:
            return "book.closed"
        case .shortcut:
            return "keyboard"
        case .behavior:
            return "slider.horizontal.3"
        case .privacy:
            return "lock.shield"
        }
    }
}
