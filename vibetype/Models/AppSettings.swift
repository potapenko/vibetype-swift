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
    static let customDictionaryPromptPrefix =
        "Custom Dictionary (use these exact spellings when they appear in the text): "

    static let defaults = AppSettings(
        transcriptionModel: defaultTranscriptionModel,
        language: .automatic,
        customLanguageCode: "",
        prompt: "",
        customDictionary: [],
        saveTranscriptsToAppClipboard: true,
        soundEnabled: true,
        showFloatingIndicator: true,
        saveTranscriptHistory: false
    )

    var transcriptionModel: String
    var language: TranscriptionLanguage
    var customLanguageCode: String
    var prompt: String
    var customDictionary: [String] = []
    var saveTranscriptsToAppClipboard: Bool
    var soundEnabled: Bool
    var showFloatingIndicator: Bool
    var saveTranscriptHistory: Bool

    var resolvedTranscriptionModel: String {
        let trimmedModel = transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedModel.isEmpty ? Self.defaultTranscriptionModel : trimmedModel
    }

    var resolvedPrompt: String? {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var promptParts: [String] = []

        if !trimmedPrompt.isEmpty {
            promptParts.append(trimmedPrompt)
        }

        if let customDictionaryPrompt = resolvedCustomDictionaryPrompt {
            promptParts.append(Self.customDictionaryPromptPrefix + customDictionaryPrompt)
        }

        let resolvedPrompt = promptParts.joined(separator: "\n\n")
        return resolvedPrompt.isEmpty ? nil : resolvedPrompt
    }

    var resolvedCustomDictionaryEntries: [String] {
        Self.normalizedCustomDictionary(customDictionary)
    }

    var resolvedCustomDictionaryPrompt: String? {
        let entries = resolvedCustomDictionaryEntries
        guard !entries.isEmpty else {
            return nil
        }

        return entries.joined(separator: ", ")
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

    static func parseCustomDictionaryEntries(from text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func normalizedCustomDictionary(_ entries: [String]) -> [String] {
        var normalizedEntries: [String] = []
        var seenEntryKeys = Set<String>()

        for entry in entries {
            let trimmedEntry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedEntry.isEmpty else {
                continue
            }

            let entryKey = trimmedEntry.lowercased()
            guard !seenEntryKeys.contains(entryKey) else {
                continue
            }

            seenEntryKeys.insert(entryKey)
            normalizedEntries.append(trimmedEntry)
        }

        return normalizedEntries
    }

    static func appendingCustomDictionaryEntries(from text: String, to entries: [String]) -> [String] {
        normalizedCustomDictionary(entries + parseCustomDictionaryEntries(from: text))
    }
}

struct AppSettingsStore {
    static let keyPrefix = "vibetype.settings."

    static let persistedKeys: Set<String> = [
        Key.transcriptionModel,
        Key.language,
        Key.customLanguageCode,
        Key.prompt,
        Key.customDictionary,
        Key.saveTranscriptsToAppClipboard,
        Key.soundEnabled,
        Key.showFloatingIndicator,
        Key.saveTranscriptHistory,
    ]

    private enum Key {
        static let transcriptionModel = keyPrefix + "transcriptionModel"
        static let language = keyPrefix + "language"
        static let customLanguageCode = keyPrefix + "customLanguageCode"
        static let prompt = keyPrefix + "prompt"
        static let customDictionary = keyPrefix + "customDictionary"
        static let saveTranscriptsToAppClipboard = keyPrefix + "saveTranscriptsToAppClipboard"
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
            customDictionary: AppSettings.normalizedCustomDictionary(
                userDefaults.stringArray(forKey: Key.customDictionary)
                    ?? defaultSettings.customDictionary
            ),
            saveTranscriptsToAppClipboard: optionalBool(forKey: Key.saveTranscriptsToAppClipboard)
                ?? defaultSettings.saveTranscriptsToAppClipboard,
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
        userDefaults.set(
            AppSettings.normalizedCustomDictionary(settings.customDictionary),
            forKey: Key.customDictionary
        )
        userDefaults.set(
            settings.saveTranscriptsToAppClipboard,
            forKey: Key.saveTranscriptsToAppClipboard
        )
        userDefaults.set(settings.soundEnabled, forKey: Key.soundEnabled)
        userDefaults.set(settings.showFloatingIndicator, forKey: Key.showFloatingIndicator)
        userDefaults.set(settings.saveTranscriptHistory, forKey: Key.saveTranscriptHistory)

        NotificationCenter.default.post(name: .appSettingsDidChange, object: nil)
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

extension Notification.Name {
    static let appSettingsDidChange = Notification.Name("vibetype.appSettingsDidChange")
}
