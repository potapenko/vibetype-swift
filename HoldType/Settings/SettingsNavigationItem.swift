//
//  SettingsNavigationItem.swift
//  HoldType
//
//  Created by Codex on 6/22/26.
//

import Foundation

enum SettingsNavigationItem: String, CaseIterable, Identifiable, Hashable {
    case permissions
    case openAI
    case billing
    case transcription
    case textCorrection
    case translation
    case dictionary
    case shortcut
    case behavior
    case cache
    case updates
    case diagnostics

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .permissions:
            return "Permissions"
        case .openAI:
            return "API key"
        case .billing:
            return "Billing"
        case .transcription:
            return "Transcription"
        case .textCorrection:
            return "Text Correction"
        case .translation:
            return "Translation"
        case .dictionary:
            return "Dictionary"
        case .shortcut:
            return "Shortcut"
        case .behavior:
            return "Behavior"
        case .cache:
            return "Recording Cache"
        case .updates:
            return "Updates"
        case .diagnostics:
            return "Diagnostics"
        }
    }

    var detail: String? {
        switch self {
        case .permissions:
            return "System access"
        case .openAI:
            return "OpenAI"
        case .billing:
            return "Usage estimate"
        case .transcription:
            return "Model and language"
        case .textCorrection:
            return "Post-processing"
        case .translation:
            return "OpenAI translate"
        case .dictionary:
            return "Words and emoji"
        case .shortcut:
            return "Global hotkey"
        case .behavior:
            return "Output and indicator"
        case .cache:
            return "Audio files"
        case .updates:
            return "App releases"
        case .diagnostics:
            return "Crash reports"
        }
    }

    var systemImage: String {
        switch self {
        case .permissions:
            return "lock.shield"
        case .openAI:
            return "key"
        case .billing:
            return "chart.bar.xaxis"
        case .transcription:
            return "waveform"
        case .textCorrection:
            return "text.badge.checkmark"
        case .translation:
            return "character.bubble"
        case .dictionary:
            return "book.closed"
        case .shortcut:
            return "keyboard"
        case .behavior:
            return "slider.horizontal.3"
        case .cache:
            return "externaldrive"
        case .updates:
            return "arrow.down.circle"
        case .diagnostics:
            return "wrench.and.screwdriver"
        }
    }
}
