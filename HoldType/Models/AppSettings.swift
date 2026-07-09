//
//  AppSettings.swift
//  HoldType
//
//  Created by Codex on 6/20/26.
//

import Foundation
import HoldTypeDomain

enum TranslationSourceMode: String, CaseIterable, Codable, Equatable {
    case sameAsTranscription
    case override

    var displayName: String {
        switch self {
        case .sameAsTranscription:
            return "Same as Transcription"
        case .override:
            return "Override source language"
        }
    }
}

enum TranslationConfigurationIssue: Error, Equatable, LocalizedError {
    case invalidSourceLanguage
    case missingTargetLanguage

    var errorDescription: String? {
        switch self {
        case .invalidSourceLanguage:
            return "Choose a valid source language override in Translation settings."
        case .missingTargetLanguage:
            return "Choose a target language in Translation settings."
        }
    }

    var title: String {
        "Translation settings need attention"
    }
}

enum TextCorrectionModelPreset: String, CaseIterable, Codable, Equatable {
    case quality
    case balanced
    case fast
    case custom

    var displayName: String {
        switch self {
        case .quality:
            return "Quality"
        case .balanced:
            return "Balanced"
        case .fast:
            return "Fast"
        case .custom:
            return "Custom"
        }
    }

    var modelName: String? {
        switch self {
        case .quality:
            return "gpt-5.5"
        case .balanced:
            return "gpt-5.4"
        case .fast:
            return "gpt-5.4-mini"
        case .custom:
            return nil
        }
    }

    var detail: String {
        switch self {
        case .quality:
            return "Highest quality correction"
        case .balanced:
            return "Lower cost than Quality"
        case .fast:
            return "Lower latency and cost"
        case .custom:
            return "Use a model ID you enter"
        }
    }
}

enum RecordingCachePolicy: Equatable {
    static let defaultRetainedRecordingLimit = 10
    static let maximumRetainedRecordingLimit = 999

    case deleteImmediately
    case keepLast(Int)
    case unlimited

    var keepsRecordings: Bool {
        self != .deleteImmediately
    }

    var retainedRecordingLimit: Int {
        switch normalized {
        case .keepLast(let count):
            return count
        case .deleteImmediately, .unlimited:
            return Self.defaultRetainedRecordingLimit
        }
    }

    var normalized: RecordingCachePolicy {
        switch self {
        case .keepLast(let count):
            return .keepLast(Self.normalizedRetainedRecordingLimit(count))
        case .deleteImmediately, .unlimited:
            return self
        }
    }

    static func normalizedRetainedRecordingLimit(_ count: Int) -> Int {
        min(max(1, count), maximumRetainedRecordingLimit)
    }
}

enum RecordingStopTailDuration: String, CaseIterable, Codable, Equatable {
    case off
    case milliseconds500
    case seconds1
    case seconds1_5
    case seconds2

    var duration: TimeInterval {
        switch self {
        case .off:
            return 0
        case .milliseconds500:
            return 0.5
        case .seconds1:
            return 1
        case .seconds1_5:
            return 1.5
        case .seconds2:
            return 2
        }
    }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .milliseconds500:
            return "0.5 seconds"
        case .seconds1:
            return "1.0 second"
        case .seconds1_5:
            return "1.5 seconds"
        case .seconds2:
            return "2.0 seconds"
        }
    }
}

struct AppSettings: Equatable {
    static let defaultTranscriptionModel = TranscriptionConfiguration.defaultModel
    static let defaultTextCorrectionModel = "gpt-5.5"
    static let defaultTranslationModel = "gpt-5.4-mini"
    static let customDictionaryPromptPrefix =
        "Custom Dictionary (use these exact spellings when they appear in the text): "
    static let emojiCommandsPromptPrefix =
        "Emoji command vocabulary (transcribe these spoken phrases exactly when spoken): "
    static let defaultEnabledEmojiCommandSetIDs = ["en"]
    static let defaultTextCorrectionPrompt =
        """
        You are correcting a speech transcript.
        Return only the corrected text.

        Make the smallest possible edits.
        Fix only obvious transcription errors, spacing, capitalization, and punctuation.
        Preserve the original language, wording, order, tone, meaning, and line breaks when possible.
        Do not rewrite for style.
        Do not summarize, expand, translate, add facts, remove facts, or make the text more formal.
        If a change is uncertain, leave the text unchanged.
        """
    static let defaultTranslationPrompt =
        """
        Translate the user's dictation transcript into the target language.
        Return only the translated text.

        Preserve meaning, names, numbers, paragraph breaks, and list structure when practical.
        Do not add explanations, markdown, alternatives, diagnostics, or source text.
        """

    static let defaults = AppSettings(
        transcriptionModel: defaultTranscriptionModel,
        language: .automatic,
        customLanguageCode: "",
        prompt: "",
        customDictionary: [],
        emojiCommandsEnabled: true,
        enabledEmojiCommandSetIDs: defaultEnabledEmojiCommandSetIDs,
        customEmojiCommands: [],
        useActiveTextContext: false,
        textCorrectionEnabled: false,
        textCorrectionModelPreset: .quality,
        customTextCorrectionModel: "",
        textCorrectionPrompt: defaultTextCorrectionPrompt,
        localTextCleanupEnabled: true,
        textReplacementRules: [],
        translationShortcutEnabled: true,
        translationSourceMode: .sameAsTranscription,
        translationSourceLanguage: .automatic,
        customTranslationSourceLanguageCode: "",
        translationTargetLanguage: .automatic,
        customTranslationTargetLanguageCode: "",
        translationModel: defaultTranslationModel,
        translationPrompt: defaultTranslationPrompt,
        automaticallyInsertTranscripts: true,
        saveTranscriptsToAppClipboard: true,
        soundEnabled: true,
        showFloatingIndicator: true,
        recordingStopTailDuration: .off,
        saveTranscriptHistory: true,
        recordingCachePolicy: .deleteImmediately
    )

    var transcriptionModel: String
    var language: TranscriptionLanguage
    var customLanguageCode: String
    var prompt: String
    var customDictionary: [String] = []
    var emojiCommandsEnabled: Bool = true
    var enabledEmojiCommandSetIDs: [String] = Self.defaultEnabledEmojiCommandSetIDs
    var customEmojiCommands: [CustomEmojiCommand] = []
    var useActiveTextContext: Bool = false
    var textCorrectionEnabled: Bool = false
    var textCorrectionModelPreset: TextCorrectionModelPreset = .quality
    var customTextCorrectionModel: String = ""
    var textCorrectionPrompt: String = ""
    var localTextCleanupEnabled: Bool = true
    var textReplacementRules: [TextReplacementRule] = []
    var translationShortcutEnabled: Bool = true
    var translationSourceMode: TranslationSourceMode = .sameAsTranscription
    var translationSourceLanguage: TranscriptionLanguage = .automatic
    var customTranslationSourceLanguageCode: String = ""
    var translationTargetLanguage: TranscriptionLanguage = .automatic
    var customTranslationTargetLanguageCode: String = ""
    var translationModel: String = Self.defaultTranslationModel
    var translationPrompt: String = Self.defaultTranslationPrompt
    var automaticallyInsertTranscripts: Bool
    var saveTranscriptsToAppClipboard: Bool
    var soundEnabled: Bool
    var showFloatingIndicator: Bool
    var recordingStopTailDuration: RecordingStopTailDuration = .off
    var saveTranscriptHistory: Bool
    var recordingCachePolicy: RecordingCachePolicy = .deleteImmediately

    var transcriptionConfiguration: TranscriptionConfiguration {
        TranscriptionConfiguration(
            model: transcriptionModel,
            language: language,
            customLanguageCode: customLanguageCode,
            freeformPrompt: prompt
        )
    }

    var resolvedTranscriptionModel: String {
        transcriptionConfiguration.resolvedModel
    }

    var resolvedTextCorrectionModel: String {
        if let modelName = textCorrectionModelPreset.modelName {
            return modelName
        }

        let trimmedModel = customTextCorrectionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedModel.isEmpty ? Self.defaultTextCorrectionModel : trimmedModel
    }

    var resolvedTextCorrectionPrompt: String {
        let trimmedPrompt = textCorrectionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPrompt.isEmpty ? Self.defaultTextCorrectionPrompt : trimmedPrompt
    }

    var isTextCorrectionPromptDefault: Bool {
        textCorrectionPrompt == Self.defaultTextCorrectionPrompt
    }

    mutating func resetTextCorrectionPrompt() {
        textCorrectionPrompt = Self.defaultTextCorrectionPrompt
    }

    var resolvedTranslationModel: String {
        let trimmedModel = translationModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedModel.isEmpty ? Self.defaultTranslationModel : trimmedModel
    }

    var resolvedTranslationPrompt: String {
        let trimmedPrompt = translationPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPrompt.isEmpty ? Self.defaultTranslationPrompt : trimmedPrompt
    }

    var isTranslationPromptDefault: Bool {
        translationPrompt == Self.defaultTranslationPrompt
    }

    mutating func resetTranslationPrompt() {
        translationPrompt = Self.defaultTranslationPrompt
    }

    var resolvedTranslationSourceLanguageCode: String? {
        switch translationSourceMode {
        case .sameAsTranscription:
            return resolvedLanguageCode
        case .override:
            return Self.resolvedLanguageCode(
                for: translationSourceLanguage,
                customCode: customTranslationSourceLanguageCode
            )
        }
    }

    var resolvedTranslationTargetLanguageCode: String? {
        Self.resolvedLanguageCode(
            for: translationTargetLanguage,
            customCode: customTranslationTargetLanguageCode
        )
    }

    var canRunTranslation: Bool {
        translationShortcutEnabled
            && translationConfigurationIssue == nil
    }

    var translationConfigurationIssue: TranslationConfigurationIssue? {
        guard translationShortcutEnabled else {
            return nil
        }

        guard isTranslationSourceConfigurationValid else {
            return .invalidSourceLanguage
        }

        guard resolvedTranslationTargetLanguageCode != nil else {
            return .missingTargetLanguage
        }

        return nil
    }

    var isTranslationSourceConfigurationValid: Bool {
        switch translationSourceMode {
        case .sameAsTranscription:
            return true
        case .override:
            return resolvedTranslationSourceLanguageCode != nil
        }
    }

    var enabledTextReplacementRules: [TextReplacementRule] {
        textReplacementRules.filter { $0.isEnabled && $0.hasSearchText }
    }

    var resolvedPrompt: String? {
        resolvedPrompt(context: nil)
    }

    func resolvedPrompt(context: TranscriptionPromptContext?) -> String? {
        var promptParts: [String] = []

        if let freeformPrompt = transcriptionConfiguration.resolvedFreeformPrompt {
            promptParts.append(freeformPrompt)
        }

        if useActiveTextContext, let activeTextPrompt = context?.promptText {
            promptParts.append(activeTextPrompt)
        }

        if let emojiCommandsPrompt = resolvedEmojiCommandsPrompt {
            promptParts.append(Self.emojiCommandsPromptPrefix + emojiCommandsPrompt)
        }

        if let customDictionaryPrompt = resolvedCustomDictionaryPrompt {
            promptParts.append(Self.customDictionaryPromptPrefix + customDictionaryPrompt)
        }

        let resolvedPrompt = promptParts.joined(separator: "\n\n")
        return resolvedPrompt.isEmpty ? nil : resolvedPrompt
    }

    var resolvedCustomDictionaryEntries: [String] {
        resolvedCustomDictionary.entries
    }

    var resolvedCustomDictionary: CustomDictionary {
        CustomDictionary(entries: customDictionary)
    }

    var resolvedCustomDictionaryPrompt: String? {
        resolvedCustomDictionary.promptText
    }

    var enabledEmojiCommandSets: [EmojiCommandSet] {
        guard emojiCommandsEnabled else {
            return []
        }

        let enabledIDs = Set(Self.normalizedEmojiCommandSetIDs(enabledEmojiCommandSetIDs))
        return EmojiCommandSet.builtIn.filter { enabledIDs.contains($0.id) }
    }

    var enabledCustomEmojiCommands: [CustomEmojiCommand] {
        guard emojiCommandsEnabled else {
            return []
        }

        return Self.normalizedCustomEmojiCommands(customEmojiCommands)
            .filter { $0.isEnabled && $0.hasUsableCommand }
    }

    var resolvedEmojiCommandsPrompt: String? {
        let hints = enabledEmojiCommandSets.flatMap(\.promptHints)
            + enabledCustomEmojiCommands.flatMap(\.promptHints)
        guard !hints.isEmpty else {
            return nil
        }

        return hints.joined(separator: ", ")
    }

    var resolvedLanguageCode: String? {
        transcriptionConfiguration.resolvedLanguageCode
    }

    var customLanguageCodeValidation: CustomLanguageCodeValidation {
        transcriptionConfiguration.customLanguageCodeValidation
    }

    static func isSupportedCustomLanguageCode(_ code: String) -> Bool {
        TranscriptionLanguage.isWellFormedCustomLanguageCode(code)
    }

    static func resolvedLanguageCode(for language: TranscriptionLanguage, customCode: String) -> String? {
        language.apiLanguageCode(customCode: customCode)
    }

    static func parseCustomDictionaryEntries(from text: String) -> [String] {
        CustomDictionary.parseEntries(from: text)
    }

    static func normalizedCustomDictionary(_ entries: [String]) -> [String] {
        CustomDictionary(entries: entries).entries
    }

    static func normalizedEmojiCommandSetIDs(_ ids: [String]) -> [String] {
        EmojiCommandSet.normalizedBuiltInIDs(ids)
    }

    static func normalizedCustomEmojiCommands(_ commands: [CustomEmojiCommand]) -> [CustomEmojiCommand] {
        var normalizedCommands: [CustomEmojiCommand] = []
        var seenKeys = Set<String>()

        for command in commands {
            let normalizedCommand = command.normalizedForStorage
            guard normalizedCommand.hasUsableCommand else {
                continue
            }

            let commandKey = "\(normalizedCommand.normalizedEmoji)|\(normalizedCommand.displayCommand)"
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            guard !seenKeys.contains(commandKey) else {
                continue
            }

            seenKeys.insert(commandKey)
            normalizedCommands.append(normalizedCommand)
        }

        return normalizedCommands
    }

    static func appendingCustomDictionaryEntries(from text: String, to entries: [String]) -> [String] {
        CustomDictionary(entries: entries).appendingEntries(from: text).entries
    }
}

struct AppSettingsStore {
    static let keyPrefix = "holdtype.settings."
    private static let migrationKeyPrefix = "holdtype.migrations."

    static let persistedKeys: Set<String> = [
        Key.transcriptionModel,
        Key.language,
        Key.customLanguageCode,
        Key.prompt,
        Key.customDictionary,
        Key.emojiCommandsEnabled,
        Key.enabledEmojiCommandSetIDs,
        Key.customEmojiCommands,
        Key.useActiveTextContext,
        Key.textCorrectionEnabled,
        Key.textCorrectionModelPreset,
        Key.customTextCorrectionModel,
        Key.textCorrectionPrompt,
        Key.localTextCleanupEnabled,
        Key.textReplacementRules,
        Key.translationShortcutEnabled,
        Key.translationSourceMode,
        Key.translationSourceLanguage,
        Key.customTranslationSourceLanguageCode,
        Key.translationTargetLanguage,
        Key.customTranslationTargetLanguageCode,
        Key.translationModel,
        Key.translationPrompt,
        Key.automaticallyInsertTranscripts,
        Key.saveTranscriptsToAppClipboard,
        Key.soundEnabled,
        Key.showFloatingIndicator,
        Key.recordingStopTailDuration,
        Key.saveTranscriptHistory,
        Key.recordingCachePolicyMode,
        Key.recordingCacheRetainedRecordingLimit,
    ]

    private enum Key {
        static let transcriptionModel = keyPrefix + "transcriptionModel"
        static let language = keyPrefix + "language"
        static let customLanguageCode = keyPrefix + "customLanguageCode"
        static let prompt = keyPrefix + "prompt"
        static let customDictionary = keyPrefix + "customDictionary"
        static let emojiCommandsEnabled = keyPrefix + "emojiCommandsEnabled"
        static let enabledEmojiCommandSetIDs = keyPrefix + "enabledEmojiCommandSetIDs"
        static let customEmojiCommands = keyPrefix + "customEmojiCommands"
        static let useActiveTextContext = keyPrefix + "useActiveTextContext"
        static let textCorrectionEnabled = keyPrefix + "textCorrectionEnabled"
        static let textCorrectionModelPreset = keyPrefix + "textCorrectionModelPreset"
        static let customTextCorrectionModel = keyPrefix + "customTextCorrectionModel"
        static let textCorrectionPrompt = keyPrefix + "textCorrectionPrompt"
        static let localTextCleanupEnabled = keyPrefix + "localTextCleanupEnabled"
        static let textReplacementRules = keyPrefix + "textReplacementRules"
        static let translationShortcutEnabled = keyPrefix + "translationShortcutEnabled"
        static let translationSourceMode = keyPrefix + "translationSourceMode"
        static let translationSourceLanguage = keyPrefix + "translationSourceLanguage"
        static let customTranslationSourceLanguageCode =
            keyPrefix + "customTranslationSourceLanguageCode"
        static let translationTargetLanguage = keyPrefix + "translationTargetLanguage"
        static let customTranslationTargetLanguageCode =
            keyPrefix + "customTranslationTargetLanguageCode"
        static let translationModel = keyPrefix + "translationModel"
        static let translationPrompt = keyPrefix + "translationPrompt"
        static let legacyTranslateRussianToEnglishShortcutEnabled =
            keyPrefix + "translateRussianToEnglishShortcutEnabled"
        static let automaticallyInsertTranscripts = keyPrefix + "automaticallyInsertTranscripts"
        static let saveTranscriptsToAppClipboard = keyPrefix + "saveTranscriptsToAppClipboard"
        static let soundEnabled = keyPrefix + "soundEnabled"
        static let showFloatingIndicator = keyPrefix + "showFloatingIndicator"
        static let recordingStopTailDuration = keyPrefix + "recordingStopTailDuration"
        static let saveTranscriptHistory = keyPrefix + "saveTranscriptHistory"
        static let recordingCachePolicyMode = keyPrefix + "recordingCachePolicyMode"
        static let recordingCacheRetainedRecordingLimit =
            keyPrefix + "recordingCacheRetainedRecordingLimit"
    }

    private enum RecordingCachePolicyMode {
        static let deleteImmediately = "deleteImmediately"
        static let keepLast = "keepLast"
        static let unlimited = "unlimited"
    }

    private enum MigrationKey {
        static let transcriptHistoryDefaultEnabled =
            migrationKeyPrefix + "transcriptHistoryDefaultEnabled"
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
            emojiCommandsEnabled: optionalBool(forKey: Key.emojiCommandsEnabled)
                ?? defaultSettings.emojiCommandsEnabled,
            enabledEmojiCommandSetIDs: loadEmojiCommandSetIDs(
                defaultValue: defaultSettings.enabledEmojiCommandSetIDs
            ),
            customEmojiCommands: loadCustomEmojiCommands(
                defaultValue: defaultSettings.customEmojiCommands
            ),
            useActiveTextContext: optionalBool(forKey: Key.useActiveTextContext)
                ?? defaultSettings.useActiveTextContext,
            textCorrectionEnabled: optionalBool(forKey: Key.textCorrectionEnabled)
                ?? defaultSettings.textCorrectionEnabled,
            textCorrectionModelPreset: loadTextCorrectionModelPreset(
                defaultValue: defaultSettings.textCorrectionModelPreset
            ),
            customTextCorrectionModel: userDefaults.string(forKey: Key.customTextCorrectionModel)
                ?? defaultSettings.customTextCorrectionModel,
            textCorrectionPrompt: loadTextCorrectionPrompt(defaultValue: defaultSettings.textCorrectionPrompt),
            localTextCleanupEnabled: optionalBool(forKey: Key.localTextCleanupEnabled)
                ?? defaultSettings.localTextCleanupEnabled,
            textReplacementRules: loadTextReplacementRules(
                defaultValue: defaultSettings.textReplacementRules
            ),
            translationShortcutEnabled: loadTranslationShortcutEnabled(
                defaultValue: defaultSettings.translationShortcutEnabled
            ),
            translationSourceMode: loadTranslationSourceMode(
                defaultValue: defaultSettings.translationSourceMode
            ),
            translationSourceLanguage: loadTranslationSourceLanguage(
                defaultValue: defaultSettings.translationSourceLanguage
            ),
            customTranslationSourceLanguageCode: userDefaults.string(
                forKey: Key.customTranslationSourceLanguageCode
            )
                ?? defaultSettings.customTranslationSourceLanguageCode,
            translationTargetLanguage: loadTranslationTargetLanguage(
                defaultValue: defaultSettings.translationTargetLanguage
            ),
            customTranslationTargetLanguageCode: userDefaults.string(
                forKey: Key.customTranslationTargetLanguageCode
            )
                ?? defaultSettings.customTranslationTargetLanguageCode,
            translationModel: userDefaults.string(forKey: Key.translationModel)
                ?? defaultSettings.translationModel,
            translationPrompt: loadTranslationPrompt(defaultValue: defaultSettings.translationPrompt),
            automaticallyInsertTranscripts: optionalBool(forKey: Key.automaticallyInsertTranscripts)
                ?? defaultSettings.automaticallyInsertTranscripts,
            saveTranscriptsToAppClipboard: optionalBool(forKey: Key.saveTranscriptsToAppClipboard)
                ?? defaultSettings.saveTranscriptsToAppClipboard,
            soundEnabled: optionalBool(forKey: Key.soundEnabled) ?? defaultSettings.soundEnabled,
            showFloatingIndicator: optionalBool(forKey: Key.showFloatingIndicator)
                ?? defaultSettings.showFloatingIndicator,
            recordingStopTailDuration: loadRecordingStopTailDuration(
                defaultValue: defaultSettings.recordingStopTailDuration
            ),
            saveTranscriptHistory: loadSaveTranscriptHistory(
                defaultValue: defaultSettings.saveTranscriptHistory
            ),
            recordingCachePolicy: loadRecordingCachePolicy(
                defaultValue: defaultSettings.recordingCachePolicy
            )
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
        userDefaults.set(settings.emojiCommandsEnabled, forKey: Key.emojiCommandsEnabled)
        userDefaults.set(
            AppSettings.normalizedEmojiCommandSetIDs(settings.enabledEmojiCommandSetIDs),
            forKey: Key.enabledEmojiCommandSetIDs
        )
        saveCustomEmojiCommands(settings.customEmojiCommands)
        userDefaults.set(settings.useActiveTextContext, forKey: Key.useActiveTextContext)
        userDefaults.set(settings.textCorrectionEnabled, forKey: Key.textCorrectionEnabled)
        userDefaults.set(settings.textCorrectionModelPreset.rawValue, forKey: Key.textCorrectionModelPreset)
        userDefaults.set(settings.customTextCorrectionModel, forKey: Key.customTextCorrectionModel)
        userDefaults.set(settings.textCorrectionPrompt, forKey: Key.textCorrectionPrompt)
        userDefaults.set(settings.localTextCleanupEnabled, forKey: Key.localTextCleanupEnabled)
        saveTextReplacementRules(settings.textReplacementRules)
        userDefaults.set(settings.translationShortcutEnabled, forKey: Key.translationShortcutEnabled)
        userDefaults.removeObject(forKey: Key.legacyTranslateRussianToEnglishShortcutEnabled)
        userDefaults.set(settings.translationSourceMode.rawValue, forKey: Key.translationSourceMode)
        userDefaults.set(settings.translationSourceLanguage.rawValue, forKey: Key.translationSourceLanguage)
        userDefaults.set(
            settings.customTranslationSourceLanguageCode,
            forKey: Key.customTranslationSourceLanguageCode
        )
        userDefaults.set(settings.translationTargetLanguage.rawValue, forKey: Key.translationTargetLanguage)
        userDefaults.set(
            settings.customTranslationTargetLanguageCode,
            forKey: Key.customTranslationTargetLanguageCode
        )
        userDefaults.set(settings.translationModel, forKey: Key.translationModel)
        userDefaults.set(settings.translationPrompt, forKey: Key.translationPrompt)
        userDefaults.set(
            settings.automaticallyInsertTranscripts,
            forKey: Key.automaticallyInsertTranscripts
        )
        userDefaults.set(
            settings.saveTranscriptsToAppClipboard,
            forKey: Key.saveTranscriptsToAppClipboard
        )
        userDefaults.set(settings.soundEnabled, forKey: Key.soundEnabled)
        userDefaults.set(settings.showFloatingIndicator, forKey: Key.showFloatingIndicator)
        userDefaults.set(
            settings.recordingStopTailDuration.rawValue,
            forKey: Key.recordingStopTailDuration
        )
        userDefaults.set(settings.saveTranscriptHistory, forKey: Key.saveTranscriptHistory)
        saveRecordingCachePolicy(settings.recordingCachePolicy)
        userDefaults.set(true, forKey: MigrationKey.transcriptHistoryDefaultEnabled)

        NotificationCenter.default.post(name: .appSettingsDidChange, object: nil)
    }

    private func loadLanguage(defaultValue: TranscriptionLanguage) -> TranscriptionLanguage {
        loadLanguage(forKey: Key.language, defaultValue: defaultValue)
    }

    private func loadEmojiCommandSetIDs(defaultValue: [String]) -> [String] {
        guard let ids = userDefaults.stringArray(forKey: Key.enabledEmojiCommandSetIDs) else {
            return defaultValue
        }

        return AppSettings.normalizedEmojiCommandSetIDs(ids)
    }

    private func loadCustomEmojiCommands(defaultValue: [CustomEmojiCommand]) -> [CustomEmojiCommand] {
        guard let data = userDefaults.data(forKey: Key.customEmojiCommands) else {
            return defaultValue
        }

        do {
            let commands = try JSONDecoder().decode([CustomEmojiCommand].self, from: data)
            return AppSettings.normalizedCustomEmojiCommands(commands)
        } catch {
            return defaultValue
        }
    }

    private func loadLanguage(forKey key: String, defaultValue: TranscriptionLanguage) -> TranscriptionLanguage {
        guard let rawLanguage = userDefaults.string(forKey: key) else {
            return defaultValue
        }

        return TranscriptionLanguage(rawValue: rawLanguage) ?? defaultValue
    }

    private func loadTextCorrectionPrompt(defaultValue: String) -> String {
        guard let prompt = userDefaults.string(forKey: Key.textCorrectionPrompt) else {
            return defaultValue
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPrompt.isEmpty ? defaultValue : prompt
    }

    private func loadTranslationPrompt(defaultValue: String) -> String {
        guard let prompt = userDefaults.string(forKey: Key.translationPrompt) else {
            return defaultValue
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPrompt.isEmpty ? defaultValue : prompt
    }

    private func loadTranslationShortcutEnabled(defaultValue: Bool) -> Bool {
        optionalBool(forKey: Key.translationShortcutEnabled)
            ?? optionalBool(forKey: Key.legacyTranslateRussianToEnglishShortcutEnabled)
            ?? defaultValue
    }

    private func loadTranslationSourceMode(defaultValue: TranslationSourceMode) -> TranslationSourceMode {
        if let rawMode = userDefaults.string(forKey: Key.translationSourceMode) {
            return TranslationSourceMode(rawValue: rawMode) ?? defaultValue
        }

        if optionalBool(forKey: Key.legacyTranslateRussianToEnglishShortcutEnabled) == true {
            return .override
        }

        if optionalBool(forKey: Key.translationShortcutEnabled) == true,
           userDefaults.string(forKey: Key.translationSourceLanguage) != nil {
            return .override
        }

        return defaultValue
    }

    private func loadTranslationSourceLanguage(defaultValue: TranscriptionLanguage) -> TranscriptionLanguage {
        if userDefaults.string(forKey: Key.translationSourceLanguage) != nil {
            return loadLanguage(forKey: Key.translationSourceLanguage, defaultValue: defaultValue)
        }

        if optionalBool(forKey: Key.legacyTranslateRussianToEnglishShortcutEnabled) == true {
            return .russian
        }

        return defaultValue
    }

    private func loadTranslationTargetLanguage(defaultValue: TranscriptionLanguage) -> TranscriptionLanguage {
        if userDefaults.string(forKey: Key.translationTargetLanguage) != nil {
            return loadLanguage(forKey: Key.translationTargetLanguage, defaultValue: defaultValue)
        }

        if optionalBool(forKey: Key.legacyTranslateRussianToEnglishShortcutEnabled) == true {
            return .english
        }

        return defaultValue
    }

    private func loadTextCorrectionModelPreset(
        defaultValue: TextCorrectionModelPreset
    ) -> TextCorrectionModelPreset {
        guard let rawValue = userDefaults.string(forKey: Key.textCorrectionModelPreset) else {
            return defaultValue
        }

        return TextCorrectionModelPreset(rawValue: rawValue) ?? defaultValue
    }

    private func loadRecordingStopTailDuration(
        defaultValue: RecordingStopTailDuration
    ) -> RecordingStopTailDuration {
        guard let rawValue = userDefaults.string(forKey: Key.recordingStopTailDuration) else {
            return defaultValue
        }

        return RecordingStopTailDuration(rawValue: rawValue) ?? defaultValue
    }

    private func loadTextReplacementRules(defaultValue: [TextReplacementRule]) -> [TextReplacementRule] {
        guard let data = userDefaults.data(forKey: Key.textReplacementRules) else {
            return defaultValue
        }

        do {
            return try JSONDecoder().decode([TextReplacementRule].self, from: data)
        } catch {
            return defaultValue
        }
    }

    private func loadSaveTranscriptHistory(defaultValue: Bool) -> Bool {
        let savedValue = optionalBool(forKey: Key.saveTranscriptHistory)
        guard optionalBool(forKey: MigrationKey.transcriptHistoryDefaultEnabled) != true else {
            return savedValue ?? defaultValue
        }

        userDefaults.set(true, forKey: MigrationKey.transcriptHistoryDefaultEnabled)

        guard savedValue == false else {
            return savedValue ?? defaultValue
        }

        userDefaults.set(defaultValue, forKey: Key.saveTranscriptHistory)
        return defaultValue
    }

    private func loadRecordingCachePolicy(defaultValue: RecordingCachePolicy) -> RecordingCachePolicy {
        guard let mode = userDefaults.string(forKey: Key.recordingCachePolicyMode) else {
            return defaultValue
        }

        switch mode {
        case RecordingCachePolicyMode.deleteImmediately:
            return .deleteImmediately
        case RecordingCachePolicyMode.keepLast:
            return .keepLast(loadRecordingCacheRetainedRecordingLimit())
        case RecordingCachePolicyMode.unlimited:
            return .unlimited
        default:
            return defaultValue
        }
    }

    private func loadRecordingCacheRetainedRecordingLimit() -> Int {
        guard let savedLimit = userDefaults.object(
            forKey: Key.recordingCacheRetainedRecordingLimit
        ) as? Int else {
            return RecordingCachePolicy.defaultRetainedRecordingLimit
        }

        return RecordingCachePolicy.normalizedRetainedRecordingLimit(savedLimit)
    }

    private func saveRecordingCachePolicy(_ policy: RecordingCachePolicy) {
        switch policy.normalized {
        case .deleteImmediately:
            userDefaults.set(
                RecordingCachePolicyMode.deleteImmediately,
                forKey: Key.recordingCachePolicyMode
            )
            userDefaults.removeObject(forKey: Key.recordingCacheRetainedRecordingLimit)
        case .keepLast(let count):
            userDefaults.set(RecordingCachePolicyMode.keepLast, forKey: Key.recordingCachePolicyMode)
            userDefaults.set(count, forKey: Key.recordingCacheRetainedRecordingLimit)
        case .unlimited:
            userDefaults.set(RecordingCachePolicyMode.unlimited, forKey: Key.recordingCachePolicyMode)
            userDefaults.removeObject(forKey: Key.recordingCacheRetainedRecordingLimit)
        }
    }

    private func saveTextReplacementRules(_ rules: [TextReplacementRule]) {
        do {
            let data = try JSONEncoder().encode(rules)
            userDefaults.set(data, forKey: Key.textReplacementRules)
        } catch {
            userDefaults.removeObject(forKey: Key.textReplacementRules)
        }
    }

    private func saveCustomEmojiCommands(_ commands: [CustomEmojiCommand]) {
        do {
            let normalizedCommands = AppSettings.normalizedCustomEmojiCommands(commands)
            let data = try JSONEncoder().encode(normalizedCommands)
            userDefaults.set(data, forKey: Key.customEmojiCommands)
        } catch {
            userDefaults.removeObject(forKey: Key.customEmojiCommands)
        }
    }

    private func optionalBool(forKey key: String) -> Bool? {
        userDefaults.object(forKey: key) as? Bool
    }
}

extension Notification.Name {
    static let appSettingsDidChange = Notification.Name("holdtype.appSettingsDidChange")
}
