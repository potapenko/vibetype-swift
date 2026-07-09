//
//  AppSettings.swift
//  HoldType
//
//  Created by Codex on 6/20/26.
//

import Foundation
import HoldTypeDomain

struct AppSettings: Equatable {
    static let defaultTranscriptionModel = TranscriptionConfiguration.defaultModel
    static let defaultTextCorrectionModel = TextCorrectionConfiguration.defaultModel
    static let defaultTranslationModel = TranslationConfiguration.defaultModel
    static let customDictionaryPromptPrefix =
        "Custom Dictionary (use these exact spellings when they appear in the text): "
    static let emojiCommandsPromptPrefix =
        "Emoji command vocabulary (transcribe these spoken phrases exactly when spoken): "
    static let defaultEnabledEmojiCommandSetIDs =
        EmojiCommandsConfiguration.defaultEnabledBuiltInSetIDs
    static let defaultTextCorrectionPrompt = TextCorrectionConfiguration.defaultPrompt
    static let defaultTranslationPrompt = TranslationConfiguration.defaultPrompt

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
        soundEnabled: VoiceSessionPreferences.defaults.audioCuesEnabled,
        showFloatingIndicator: true,
        recordingStopTailDuration:
            VoiceSessionPreferences.defaults.recordingStopTailDuration,
        saveTranscriptHistory: RetentionConfiguration.defaults.historyEnabled,
        recordingCachePolicy: RetentionConfiguration.defaults.recordingCachePolicy
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

    var textCorrectionConfiguration: TextCorrectionConfiguration {
        TextCorrectionConfiguration(
            isEnabled: textCorrectionEnabled,
            modelPreset: textCorrectionModelPreset,
            customModel: customTextCorrectionModel,
            prompt: textCorrectionPrompt
        )
    }

    var resolvedTextCorrectionModel: String {
        textCorrectionConfiguration.resolvedModel
    }

    var resolvedTextCorrectionPrompt: String {
        textCorrectionConfiguration.resolvedPrompt
    }

    var isTextCorrectionPromptDefault: Bool {
        textCorrectionConfiguration.isPromptDefault
    }

    mutating func resetTextCorrectionPrompt() {
        textCorrectionPrompt = Self.defaultTextCorrectionPrompt
    }

    var translationConfiguration: TranslationConfiguration {
        TranslationConfiguration(
            actionPreferenceEnabled: translationShortcutEnabled,
            sourceMode: translationSourceMode,
            sourceLanguage: translationSourceLanguage,
            customSourceLanguageCode: customTranslationSourceLanguageCode,
            targetLanguage: translationTargetLanguage,
            customTargetLanguageCode: customTranslationTargetLanguageCode,
            model: translationModel,
            prompt: translationPrompt
        )
    }

    var resolvedTranslationModel: String {
        translationConfiguration.resolvedModel
    }

    var resolvedTranslationPrompt: String {
        translationConfiguration.resolvedPrompt
    }

    var isTranslationPromptDefault: Bool {
        translationConfiguration.isPromptDefault
    }

    mutating func resetTranslationPrompt() {
        translationPrompt = Self.defaultTranslationPrompt
    }

    var resolvedTranslationSourceLanguageCode: String? {
        translationConfiguration.resolvedSourceLanguageCode(
            transcriptionConfiguration: transcriptionConfiguration
        )
    }

    var resolvedTranslationTargetLanguageCode: String? {
        translationConfiguration.resolvedTargetLanguageCode
    }

    var canRunTranslation: Bool {
        translationConfiguration.canRunAction
    }

    var translationConfigurationIssue: TranslationConfigurationIssue? {
        translationConfiguration.configurationIssue
    }

    var isTranslationSourceConfigurationValid: Bool {
        translationConfiguration.isSourceConfigurationValid
    }

    var retentionConfiguration: RetentionConfiguration {
        RetentionConfiguration(
            historyEnabled: saveTranscriptHistory,
            recordingCachePolicy: recordingCachePolicy
        )
    }

    var voiceSessionPreferences: VoiceSessionPreferences {
        VoiceSessionPreferences(
            audioCuesEnabled: soundEnabled,
            recordingStopTailDuration: recordingStopTailDuration
        )
    }

    var enabledTextReplacementRules: [TextReplacementRule] {
        transcriptPostProcessingConfiguration.enabledTextReplacementRules
    }

    var transcriptPostProcessingConfiguration: TranscriptPostProcessingConfiguration {
        TranscriptPostProcessingConfiguration(
            localTextCleanupEnabled: localTextCleanupEnabled,
            emojiCommands: emojiCommandsConfiguration,
            textReplacementRules: textReplacementRules
        )
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

    var emojiCommandsConfiguration: EmojiCommandsConfiguration {
        EmojiCommandsConfiguration(
            isEnabled: emojiCommandsEnabled,
            enabledBuiltInSetIDs: enabledEmojiCommandSetIDs,
            customCommands: customEmojiCommands
        )
    }

    var enabledEmojiCommandSets: [EmojiCommandSet] {
        emojiCommandsConfiguration.enabledBuiltInSets
    }

    var enabledCustomEmojiCommands: [CustomEmojiCommand] {
        emojiCommandsConfiguration.enabledCustomCommands
    }

    var resolvedEmojiCommandsPrompt: String? {
        emojiCommandsConfiguration.promptText
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
        EmojiCommandsConfiguration(enabledBuiltInSetIDs: ids)
            .normalizedEnabledBuiltInSetIDs
    }

    static func normalizedCustomEmojiCommands(_ commands: [CustomEmojiCommand]) -> [CustomEmojiCommand] {
        EmojiCommandsConfiguration.normalizedCustomCommands(commands)
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
