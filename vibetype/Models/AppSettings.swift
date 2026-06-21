//
//  AppSettings.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import Foundation

enum TranscriptionLanguage: String, CaseIterable, Codable, Equatable {
    case automatic = "auto"
    case english
    case russian
    case custom

    var displayName: String {
        switch self {
        case .automatic:
            return "Auto"
        case .english:
            return "English"
        case .russian:
            return "Russian"
        case .custom:
            return "Custom"
        }
    }

    func apiLanguageCode(customCode: String) -> String? {
        switch self {
        case .automatic:
            return nil
        case .english:
            return "en"
        case .russian:
            return "ru"
        case .custom:
            let trimmedCode = customCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard AppSettings.isSupportedCustomLanguageCode(trimmedCode) else {
                return nil
            }
            return trimmedCode.lowercased()
        }
    }
}

enum CustomLanguageCodeValidation: Equatable {
    case notRequired
    case emptyFallsBackToAutomatic
    case valid(normalizedCode: String)
    case invalid

    var isInvalid: Bool {
        self == .invalid
    }

    var resolvedLanguageCode: String? {
        switch self {
        case .valid(let normalizedCode):
            return normalizedCode
        case .notRequired, .emptyFallsBackToAutomatic, .invalid:
            return nil
        }
    }
}

struct AppSettings: Equatable {
    static let defaultTranscriptionModel = "gpt-4o-transcribe"

    static let defaults = AppSettings(
        transcriptionModel: defaultTranscriptionModel,
        language: .automatic,
        customLanguageCode: "",
        prompt: "",
        autoPaste: true,
        copyToClipboard: true,
        restoreClipboard: true,
        soundEnabled: true,
        showFloatingIndicator: true,
        saveTranscriptHistory: false
    )

    var transcriptionModel: String
    var language: TranscriptionLanguage
    var customLanguageCode: String
    var prompt: String
    var autoPaste: Bool
    var copyToClipboard: Bool
    var restoreClipboard: Bool
    var soundEnabled: Bool
    var showFloatingIndicator: Bool
    var saveTranscriptHistory: Bool

    var resolvedTranscriptionModel: String {
        let trimmedModel = transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedModel.isEmpty ? Self.defaultTranscriptionModel : trimmedModel
    }

    var resolvedPrompt: String? {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPrompt.isEmpty ? nil : trimmedPrompt
    }

    var resolvedLanguageCode: String? {
        switch language {
        case .automatic:
            return nil
        case .english:
            return "en"
        case .russian:
            return "ru"
        case .custom:
            return customLanguageCodeValidation.resolvedLanguageCode
        }
    }

    var customLanguageCodeValidation: CustomLanguageCodeValidation {
        guard language == .custom else {
            return .notRequired
        }

        let trimmedCode = customLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            return .emptyFallsBackToAutomatic
        }

        guard Self.isSupportedCustomLanguageCode(trimmedCode) else {
            return .invalid
        }

        return .valid(normalizedCode: trimmedCode.lowercased())
    }

    static func isSupportedCustomLanguageCode(_ code: String) -> Bool {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count == 2 || trimmedCode.count == 3 else {
            return false
        }

        return trimmedCode.unicodeScalars.allSatisfy { scalar in
            (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
        }
    }
}

struct AppSettingsStore {
    static let keyPrefix = "vibetype.settings."

    static let persistedKeys: Set<String> = [
        Key.transcriptionModel,
        Key.language,
        Key.customLanguageCode,
        Key.prompt,
        Key.autoPaste,
        Key.copyToClipboard,
        Key.restoreClipboard,
        Key.soundEnabled,
        Key.showFloatingIndicator,
        Key.saveTranscriptHistory,
    ]

    private enum Key {
        static let transcriptionModel = keyPrefix + "transcriptionModel"
        static let language = keyPrefix + "language"
        static let customLanguageCode = keyPrefix + "customLanguageCode"
        static let prompt = keyPrefix + "prompt"
        static let autoPaste = keyPrefix + "autoPaste"
        static let copyToClipboard = keyPrefix + "copyToClipboard"
        static let restoreClipboard = keyPrefix + "restoreClipboard"
        static let soundEnabled = keyPrefix + "soundEnabled"
        static let showFloatingIndicator = keyPrefix + "showFloatingIndicator"
        static let saveTranscriptHistory = keyPrefix + "saveTranscriptHistory"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> AppSettings {
        let defaultSettings = AppSettings.defaults

        return AppSettings(
            transcriptionModel: userDefaults.string(forKey: Key.transcriptionModel)
                ?? defaultSettings.transcriptionModel,
            language: loadLanguage(defaultValue: defaultSettings.language),
            customLanguageCode: userDefaults.string(forKey: Key.customLanguageCode)
                ?? defaultSettings.customLanguageCode,
            prompt: userDefaults.string(forKey: Key.prompt) ?? defaultSettings.prompt,
            autoPaste: optionalBool(forKey: Key.autoPaste) ?? defaultSettings.autoPaste,
            copyToClipboard: optionalBool(forKey: Key.copyToClipboard)
                ?? defaultSettings.copyToClipboard,
            restoreClipboard: optionalBool(forKey: Key.restoreClipboard)
                ?? defaultSettings.restoreClipboard,
            soundEnabled: optionalBool(forKey: Key.soundEnabled) ?? defaultSettings.soundEnabled,
            showFloatingIndicator: optionalBool(forKey: Key.showFloatingIndicator)
                ?? defaultSettings.showFloatingIndicator,
            saveTranscriptHistory: optionalBool(forKey: Key.saveTranscriptHistory)
                ?? defaultSettings.saveTranscriptHistory
        )
    }

    func save(_ settings: AppSettings) {
        userDefaults.set(settings.transcriptionModel, forKey: Key.transcriptionModel)
        userDefaults.set(settings.language.rawValue, forKey: Key.language)
        userDefaults.set(settings.customLanguageCode, forKey: Key.customLanguageCode)
        userDefaults.set(settings.prompt, forKey: Key.prompt)
        userDefaults.set(settings.autoPaste, forKey: Key.autoPaste)
        userDefaults.set(settings.copyToClipboard, forKey: Key.copyToClipboard)
        userDefaults.set(settings.restoreClipboard, forKey: Key.restoreClipboard)
        userDefaults.set(settings.soundEnabled, forKey: Key.soundEnabled)
        userDefaults.set(settings.showFloatingIndicator, forKey: Key.showFloatingIndicator)
        userDefaults.set(settings.saveTranscriptHistory, forKey: Key.saveTranscriptHistory)
    }

    private func loadLanguage(defaultValue: TranscriptionLanguage) -> TranscriptionLanguage {
        guard let rawLanguage = userDefaults.string(forKey: Key.language) else {
            return defaultValue
        }

        return TranscriptionLanguage(rawValue: rawLanguage) ?? defaultValue
    }

    private func optionalBool(forKey key: String) -> Bool? {
        userDefaults.object(forKey: key) as? Bool
    }
}
