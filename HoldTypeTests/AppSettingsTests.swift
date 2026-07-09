//
//  AppSettingsTests.swift
//  HoldTypeTests
//
//  Created by Codex on 6/20/26.
//

import Foundation
import HoldTypeDomain
import Testing
@testable import HoldType

struct AppSettingsTests {

    @Test func defaultsMatchMVPContracts() {
        let settings = AppSettings.defaults

        #expect(settings.transcriptionModel == "gpt-4o-transcribe")
        #expect(settings.transcriptionConfiguration == .defaults)
        #expect(settings.resolvedTranscriptionModel == "gpt-4o-transcribe")
        #expect(settings.language == .automatic)
        #expect(settings.resolvedLanguageCode == nil)
        #expect(settings.customLanguageCode.isEmpty)
        #expect(settings.customDictionary.isEmpty)
        #expect(settings.resolvedCustomDictionary == .empty)
        #expect(settings.resolvedCustomDictionaryEntries.isEmpty)
        #expect(settings.resolvedCustomDictionaryPrompt == nil)
        #expect(settings.emojiCommandsEnabled)
        #expect(settings.enabledEmojiCommandSetIDs == ["en"])
        #expect(settings.enabledEmojiCommandSets.map(\.id) == ["en"])
        #expect(EmojiCommandSet.builtIn.map(\.id) == ["en", "ru", "es", "de", "fr", "pt"])
        #expect(EmojiCommandSet.builtIn.allSatisfy { $0.commands.count == 21 })
        #expect(settings.customEmojiCommands.isEmpty)
        #expect(settings.enabledCustomEmojiCommands.isEmpty)
        #expect(settings.resolvedEmojiCommandsPrompt?.contains("emoji smile") == true)
        #expect(settings.resolvedPrompt?.contains("Emoji command vocabulary") == true)
        #expect(settings.useActiveTextContext == false)
        #expect(settings.textCorrectionEnabled == false)
        #expect(settings.textCorrectionModelPreset == .quality)
        #expect(settings.customTextCorrectionModel.isEmpty)
        #expect(settings.resolvedTextCorrectionModel == "gpt-5.5")
        #expect(settings.textCorrectionPrompt == AppSettings.defaultTextCorrectionPrompt)
        #expect(settings.resolvedTextCorrectionPrompt == AppSettings.defaultTextCorrectionPrompt)
        #expect(settings.isTextCorrectionPromptDefault)
        #expect(settings.localTextCleanupEnabled)
        #expect(settings.textReplacementRules.isEmpty)
        #expect(settings.enabledTextReplacementRules.isEmpty)
        #expect(settings.translationShortcutEnabled)
        #expect(settings.translationSourceMode == .sameAsTranscription)
        #expect(settings.translationSourceLanguage == .automatic)
        #expect(settings.resolvedTranslationSourceLanguageCode == nil)
        #expect(settings.isTranslationSourceConfigurationValid)
        #expect(settings.translationTargetLanguage == .automatic)
        #expect(settings.resolvedTranslationTargetLanguageCode == nil)
        #expect(settings.translationModel == AppSettings.defaultTranslationModel)
        #expect(settings.resolvedTranslationModel == "gpt-5.4-mini")
        #expect(settings.translationPrompt == AppSettings.defaultTranslationPrompt)
        #expect(settings.resolvedTranslationPrompt == AppSettings.defaultTranslationPrompt)
        #expect(settings.isTranslationPromptDefault)
        #expect(settings.translationConfigurationIssue == .missingTargetLanguage)
        #expect(settings.canRunTranslation == false)
        #expect(settings.automaticallyInsertTranscripts)
        #expect(settings.saveTranscriptsToAppClipboard)
        #expect(settings.soundEnabled)
        #expect(settings.showFloatingIndicator)
        #expect(settings.recordingStopTailDuration == .off)
        #expect(settings.recordingStopTailDuration.duration == 0)
        #expect(settings.saveTranscriptHistory)
        #expect(settings.recordingCachePolicy == .deleteImmediately)
        #expect(settings.recordingCachePolicy.keepsRecordings == false)
    }

    @Test func resolvesBlankModelAndPromptWithoutMutatingStoredValues() {
        var settings = AppSettings.defaults
        settings.transcriptionModel = "  "
        settings.prompt = "  release names, Swift symbols  "
        settings.customDictionary = [" OpenWhispr ", "openwhispr", "", "Synty"]
        settings.emojiCommandsEnabled = false

        #expect(settings.transcriptionModel == "  ")
        #expect(settings.resolvedTranscriptionModel == AppSettings.defaultTranscriptionModel)
        #expect(settings.resolvedCustomDictionaryEntries == ["OpenWhispr", "Synty"])
        #expect(settings.resolvedCustomDictionaryPrompt == "OpenWhispr, Synty")
        #expect(
            settings.resolvedPrompt ==
                """
                release names, Swift symbols

                Custom Dictionary (use these exact spellings when they appear in the text): OpenWhispr, Synty
                """
        )
    }

    @Test func projectsRawTranscriptionConfigurationWithoutOwningPersistence() {
        var settings = AppSettings.defaults
        settings.transcriptionModel = "  custom-transcribe  "
        settings.language = .custom
        settings.customLanguageCode = " RU "
        settings.prompt = "  Prefer HoldType.  "

        let configuration = settings.transcriptionConfiguration

        #expect(configuration.model == "  custom-transcribe  ")
        #expect(configuration.language == .custom)
        #expect(configuration.customLanguageCode == " RU ")
        #expect(configuration.freeformPrompt == "  Prefer HoldType.  ")
        #expect(settings.resolvedTranscriptionModel == configuration.resolvedModel)
        #expect(settings.resolvedLanguageCode == configuration.resolvedLanguageCode)
        #expect(
            settings.customLanguageCodeValidation ==
                configuration.customLanguageCodeValidation
        )
        #expect(settings.resolvedPrompt == configuration.resolvedFreeformPrompt.map { prompt in
            """
            \(prompt)

            \(AppSettings.emojiCommandsPromptPrefix)\(settings.resolvedEmojiCommandsPrompt ?? "")
            """
        })
    }

    @Test func includesActiveTextContextOnlyWhenEnabled() throws {
        var disabledSettings = AppSettings.defaults
        disabledSettings.prompt = "Prefer project vocabulary."
        disabledSettings.emojiCommandsEnabled = false
        disabledSettings.useActiveTextContext = false
        let context = try #require(
            TranscriptionPromptContext("The user is already writing about macOS Accessibility.")
        )

        #expect(disabledSettings.resolvedPrompt(context: context) == "Prefer project vocabulary.")

        var enabledSettings = disabledSettings
        enabledSettings.useActiveTextContext = true
        enabledSettings.customDictionary = ["HoldType"]

        #expect(
            enabledSettings.resolvedPrompt(context: context) ==
                """
                Prefer project vocabulary.

                Current writing context near the cursor. Use this only for continuity; transcribe only the new speech:
                The user is already writing about macOS Accessibility.

                Custom Dictionary (use these exact spellings when they appear in the text): HoldType
                """
        )
    }

    @Test func resolvesTextCorrectionModelAndRules() {
        var settings = AppSettings.defaults

        #expect(settings.resolvedTextCorrectionModel == "gpt-5.5")

        settings.textCorrectionModelPreset = .balanced
        #expect(settings.resolvedTextCorrectionModel == "gpt-5.4")

        settings.textCorrectionModelPreset = .fast
        #expect(settings.resolvedTextCorrectionModel == "gpt-5.4-mini")

        settings.textCorrectionModelPreset = .custom
        settings.customTextCorrectionModel = "  custom-correction-model  "
        settings.textCorrectionPrompt = "  Fix only punctuation.  "
        settings.textReplacementRules = [
            TextReplacementRule(search: "AI-looking", replacement: "plain", isEnabled: true),
            TextReplacementRule(search: "ignored", replacement: "value", isEnabled: false),
            TextReplacementRule(search: "  ", replacement: "empty search", isEnabled: true),
        ]

        #expect(settings.resolvedTextCorrectionModel == "custom-correction-model")
        #expect(settings.resolvedTextCorrectionPrompt == "Fix only punctuation.")
        #expect(settings.enabledTextReplacementRules.count == 1)
        #expect(settings.enabledTextReplacementRules.first?.replacement == "plain")

        settings.customTextCorrectionModel = "  "
        settings.textCorrectionPrompt = "  "

        #expect(settings.resolvedTextCorrectionModel == AppSettings.defaultTextCorrectionModel)
        #expect(settings.resolvedTextCorrectionPrompt == AppSettings.defaultTextCorrectionPrompt)
    }

    @Test func resolvesEmojiCommandPromptFromActiveSet() {
        var settings = AppSettings.defaults

        #expect(settings.enabledEmojiCommandSets.map(\.id) == ["en"])
        #expect(settings.resolvedEmojiCommandsPrompt?.contains("emoji smile") == true)
        #expect(settings.resolvedEmojiCommandsPrompt?.contains("эмодзи улыбка") == false)

        settings.enabledEmojiCommandSetIDs = ["ru", "missing", "en", "ru", "de"]
        settings.customEmojiCommands = [
            CustomEmojiCommand(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000321")!,
                emoji: "🚀",
                command: "emoji rocket",
                aliases: ["launch emoji"]
            )
        ]

        #expect(settings.enabledEmojiCommandSets.map(\.id) == ["ru"])
        #expect(settings.enabledCustomEmojiCommands.map(\.displayCommand) == ["emoji rocket"])
        #expect(settings.resolvedEmojiCommandsPrompt?.contains("emoji smile") == false)
        #expect(settings.resolvedEmojiCommandsPrompt?.contains("эмодзи улыбка") == true)
        #expect(settings.resolvedEmojiCommandsPrompt?.contains("эмодзи смех") == true)
        #expect(settings.resolvedEmojiCommandsPrompt?.contains("эмоции") == false)
        #expect(settings.resolvedEmojiCommandsPrompt?.contains("эмоджи") == false)
        #expect(settings.resolvedEmojiCommandsPrompt?.contains("emoji lächeln") == false)
        #expect(settings.resolvedEmojiCommandsPrompt?.contains("emoji rocket") == true)
        #expect(settings.resolvedEmojiCommandsPrompt?.contains("launch emoji") == true)

        settings.emojiCommandsEnabled = false

        #expect(settings.enabledEmojiCommandSets.isEmpty)
        #expect(settings.enabledCustomEmojiCommands.isEmpty)
        #expect(settings.resolvedEmojiCommandsPrompt == nil)
    }

    @Test func normalizesEmojiCommandSetIDsToSingleActiveSet() {
        #expect(AppSettings.normalizedEmojiCommandSetIDs(["ru", "en", "de"]) == ["ru"])
        #expect(AppSettings.normalizedEmojiCommandSetIDs(["missing", "de", "en"]) == ["de"])
        #expect(AppSettings.normalizedEmojiCommandSetIDs(["missing"]) == [])
    }

    @Test func resolvesTranslationModelPromptLanguagesAndReset() {
        var settings = AppSettings.defaults

        settings.translationShortcutEnabled = true
        settings.language = .spanish
        settings.translationTargetLanguage = .japanese
        settings.translationModel = "  custom-translation-model  "
        settings.translationPrompt = "  Translate for product UI labels.  "

        #expect(settings.resolvedTranslationSourceLanguageCode == "es")
        #expect(settings.resolvedTranslationTargetLanguageCode == "ja")
        #expect(settings.resolvedTranslationModel == "custom-translation-model")
        #expect(settings.resolvedTranslationPrompt == "Translate for product UI labels.")
        #expect(settings.canRunTranslation)
        #expect(settings.isTranslationPromptDefault == false)

        settings.translationModel = "  "
        settings.translationPrompt = "  "

        #expect(settings.resolvedTranslationModel == AppSettings.defaultTranslationModel)
        #expect(settings.resolvedTranslationPrompt == AppSettings.defaultTranslationPrompt)

        settings.resetTranslationPrompt()

        #expect(settings.translationPrompt == AppSettings.defaultTranslationPrompt)
        #expect(settings.isTranslationPromptDefault)
    }

    @Test func customTranslationLanguageCodesGateTranslation() {
        var settings = AppSettings.defaults
        settings.translationShortcutEnabled = true
        settings.translationSourceMode = .override
        settings.translationSourceLanguage = .custom
        settings.translationTargetLanguage = .custom
        settings.customTranslationSourceLanguageCode = "  ES  "
        settings.customTranslationTargetLanguageCode = "  ENG  "

        #expect(settings.resolvedTranslationSourceLanguageCode == "es")
        #expect(settings.resolvedTranslationTargetLanguageCode == "eng")
        #expect(settings.canRunTranslation)

        settings.customTranslationTargetLanguageCode = "en-US"

        #expect(settings.resolvedTranslationTargetLanguageCode == nil)
        #expect(settings.translationConfigurationIssue == .missingTargetLanguage)
        #expect(settings.canRunTranslation == false)

        settings.customTranslationTargetLanguageCode = "en"
        settings.customTranslationSourceLanguageCode = "es-MX"

        #expect(settings.translationConfigurationIssue == .invalidSourceLanguage)
        #expect(settings.canRunTranslation == false)
    }

    @Test func textCorrectionPromptResetRestoresDefaultPrompt() {
        var settings = AppSettings.defaults

        settings.textCorrectionPrompt = "Correct obvious names only."

        #expect(settings.isTextCorrectionPromptDefault == false)
        #expect(settings.resolvedTextCorrectionPrompt == "Correct obvious names only.")

        settings.resetTextCorrectionPrompt()

        #expect(settings.textCorrectionPrompt == AppSettings.defaultTextCorrectionPrompt)
        #expect(settings.resolvedTextCorrectionPrompt == AppSettings.defaultTextCorrectionPrompt)
        #expect(settings.isTextCorrectionPromptDefault)
    }

    @Test func boundsActiveTextContextPrompt() throws {
        let context = try #require(
            TranscriptionPromptContext("abcdef", maximumCharacterCount: 3)
        )

        #expect(context.text == "def")
    }

    @Test func parsesAndAppendsCustomDictionaryEntries() {
        let parsedEntries = AppSettings.parseCustomDictionaryEntries(
            from: " OpenWhispr, Synty\nThe word is HoldType,, "
        )

        #expect(parsedEntries == ["OpenWhispr", "Synty", "The word is HoldType"])
        #expect(
            AppSettings.normalizedCustomDictionary([" OpenWhispr ", "openwhispr", "Synty"]) ==
                CustomDictionary(entries: [" OpenWhispr ", "openwhispr", "Synty"]).entries
        )
        #expect(
            AppSettings.appendingCustomDictionaryEntries(
                from: "openwhispr, Sinead",
                to: ["OpenWhispr"]
            ) == ["OpenWhispr", "Sinead"]
        )
    }

    @Test func mapsLanguageModesToTranscriptionCodes() {
        #expect(TranscriptionLanguage.automatic.apiLanguageCode(customCode: "de") == nil)
        #expect(TranscriptionLanguage.english.apiLanguageCode(customCode: "") == "en")
        #expect(TranscriptionLanguage.spanish.apiLanguageCode(customCode: "") == "es")
        #expect(TranscriptionLanguage.japanese.apiLanguageCode(customCode: "") == "ja")
        #expect(TranscriptionLanguage.russian.apiLanguageCode(customCode: "") == "ru")
        #expect(TranscriptionLanguage.custom.apiLanguageCode(customCode: "  uk  ") == "uk")
        #expect(TranscriptionLanguage.custom.apiLanguageCode(customCode: "ENG") == "eng")
        #expect(TranscriptionLanguage.custom.apiLanguageCode(customCode: "   ") == nil)
        #expect(TranscriptionLanguage.custom.apiLanguageCode(customCode: "english") == nil)
        #expect(TranscriptionLanguage.custom.apiLanguageCode(customCode: "en-US") == nil)
    }

    @Test func validatesCustomLanguageCodeForSettingsAndRequests() {
        var settings = AppSettings.defaults

        #expect(settings.customLanguageCodeValidation == .notRequired)
        settings.language = .custom
        settings.customLanguageCode = "   "

        #expect(settings.customLanguageCodeValidation == .emptyFallsBackToAutomatic)
        #expect(settings.resolvedLanguageCode == nil)

        settings.customLanguageCode = " RU "

        #expect(settings.customLanguageCodeValidation == .valid(normalizedCode: "ru"))
        #expect(settings.resolvedLanguageCode == "ru")

        settings.customLanguageCode = "russian"

        #expect(settings.customLanguageCodeValidation == .invalid)
        #expect(settings.resolvedLanguageCode == nil)

        settings.language = .russian

        #expect(settings.resolvedLanguageCode == "ru")
    }

    @Test func loadsDefaultsFromEmptyUserDefaults() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(userDefaults: defaults)

        #expect(store.load() == .defaults)
    }

    @Test func explicitDisabledTranslationShortcutOverridesDefault() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: AppSettingsStore.keyPrefix + "translationShortcutEnabled")

        let settings = AppSettingsStore(userDefaults: defaults).load()

        #expect(settings.translationShortcutEnabled == false)
    }

    @Test func customDictionaryPersistenceNormalizesArraysWithoutReparsingEntries() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = AppSettingsStore.keyPrefix + "customDictionary"
        defaults.set(
            [" ACME, Inc. ", "Line\nBreak", "acme, inc.", "   "],
            forKey: key
        )
        let store = AppSettingsStore(userDefaults: defaults)

        let settings = store.load()

        #expect(settings.customDictionary == ["ACME, Inc.", "Line\nBreak"])
        #expect(settings.resolvedCustomDictionaryPrompt == "ACME, Inc., Line\nBreak")

        store.save(settings)

        #expect(defaults.stringArray(forKey: key) == ["ACME, Inc.", "Line\nBreak"])
    }

    @Test func textReplacementRulesDecodeFrozenLegacyPayloadWithoutMigration() throws {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = AppSettingsStore.keyPrefix + "textReplacementRules"
        let fixture = Data(
            #"""
            [
              {
                "id": "01234567-89AB-CDEF-0123-456789ABCDEF",
                "search": "—",
                "replacement": "-",
                "isEnabled": true
              },
              {
                "id": "FEDCBA98-7654-3210-FEDC-BA9876543210",
                "search": "  ",
                "replacement": "",
                "isEnabled": false
              }
            ]
            """#.utf8
        )
        defaults.set(fixture, forKey: key)
        let store = AppSettingsStore(userDefaults: defaults)

        let settings = store.load()

        #expect(defaults.data(forKey: key) == fixture)
        #expect(settings.textReplacementRules.map(\.search) == ["—", "  "])
        #expect(settings.textReplacementRules.map(\.replacement) == ["-", ""])
        #expect(settings.textReplacementRules.map(\.isEnabled) == [true, false])
        #expect(settings.enabledTextReplacementRules.count == 1)

        store.save(settings)

        let savedData = try #require(defaults.data(forKey: key))
        #expect(
            try JSONDecoder().decode(
                Array<HoldTypeDomain.TextReplacementRule>.self,
                from: savedData
            ) ==
                settings.textReplacementRules
        )
    }

    @Test func customEmojiCommandsDecodeFrozenLegacyPayloadWithoutMigration() throws {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = AppSettingsStore.keyPrefix + "customEmojiCommands"
        let fixture = Data(
            #"""
            [
              {
                "id": "00000000-0000-0000-0000-000000000321",
                "emoji": "🚀",
                "command": "emoji rocket",
                "aliases": ["launch emoji"],
                "isEnabled": false
              }
            ]
            """#.utf8
        )
        defaults.set(fixture, forKey: key)
        let store = AppSettingsStore(userDefaults: defaults)

        let settings = store.load()

        #expect(defaults.data(forKey: key) == fixture)
        #expect(settings.customEmojiCommands.count == 1)
        #expect(settings.customEmojiCommands.first?.emoji == "🚀")
        #expect(settings.customEmojiCommands.first?.command == "emoji rocket")
        #expect(settings.customEmojiCommands.first?.aliases == ["launch emoji"])
        #expect(settings.customEmojiCommands.first?.isEnabled == false)

        store.save(settings)

        let savedData = try #require(defaults.data(forKey: key))
        #expect(
            try JSONDecoder().decode(
                Array<HoldTypeDomain.CustomEmojiCommand>.self,
                from: savedData
            ) == settings.customEmojiCommands
        )
    }

    @Test func migratesLegacyDisabledTranscriptHistoryToEnabledDefaultOnce() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: AppSettingsStore.keyPrefix + "saveTranscriptHistory")
        let store = AppSettingsStore(userDefaults: defaults)

        #expect(store.load().saveTranscriptHistory)
        #expect(defaults.bool(forKey: AppSettingsStore.keyPrefix + "saveTranscriptHistory"))

        var settings = AppSettings.defaults
        settings.saveTranscriptHistory = false
        store.save(settings)

        #expect(store.load().saveTranscriptHistory == false)
    }

    @Test func savesAndLoadsOnlyNonSecretSettings() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(userDefaults: defaults)
        let settings = AppSettings(
            transcriptionModel: "custom-model",
            language: .custom,
            customLanguageCode: "de",
            prompt: "Product names",
            customDictionary: ["OpenWhispr", "Synty"],
            emojiCommandsEnabled: false,
            enabledEmojiCommandSetIDs: ["ru"],
            customEmojiCommands: [
                CustomEmojiCommand(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000322")!,
                    emoji: "🚀",
                    command: "emoji rocket",
                    aliases: ["launch emoji"],
                    isEnabled: false
                )
            ],
            useActiveTextContext: true,
            textCorrectionEnabled: true,
            textCorrectionModelPreset: .custom,
            customTextCorrectionModel: "custom-correction-model",
            textCorrectionPrompt: "Correct punctuation only.",
            localTextCleanupEnabled: false,
            textReplacementRules: [
                TextReplacementRule(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000167")!,
                    search: "—",
                    replacement: "-",
                    isEnabled: true
                )
            ],
            translationShortcutEnabled: true,
            translationSourceMode: .override,
            translationSourceLanguage: .custom,
            customTranslationSourceLanguageCode: "es",
            translationTargetLanguage: .japanese,
            customTranslationTargetLanguageCode: "",
            translationModel: "custom-translation-model",
            translationPrompt: "Translate for an engineering audience.",
            automaticallyInsertTranscripts: false,
            saveTranscriptsToAppClipboard: false,
            soundEnabled: false,
            showFloatingIndicator: true,
            recordingStopTailDuration: .seconds1_5,
            saveTranscriptHistory: false,
            recordingCachePolicy: .keepLast(25)
        )

        store.save(settings)

        #expect(store.load() == settings)

        let persistedKeys = Set(
            defaults.dictionaryRepresentation().keys.filter {
                $0.hasPrefix(AppSettingsStore.keyPrefix)
            }
        )
        #expect(persistedKeys == AppSettingsStore.persistedKeys)
        #expect(persistedKeys.contains { $0.localizedCaseInsensitiveContains("api") } == false)
        #expect(persistedKeys.contains { $0.localizedCaseInsensitiveContains("key") } == false)
    }

    @Test func loadsRecordingCachePolicyModesAndNormalizesCount() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(userDefaults: defaults)
        var settings = AppSettings.defaults
        settings.recordingCachePolicy = .unlimited

        store.save(settings)
        #expect(store.load().recordingCachePolicy == .unlimited)

        defaults.set("keepLast", forKey: AppSettingsStore.keyPrefix + "recordingCachePolicyMode")
        defaults.set(0, forKey: AppSettingsStore.keyPrefix + "recordingCacheRetainedRecordingLimit")

        #expect(store.load().recordingCachePolicy == .keepLast(1))
    }

    @Test func loadsRecordingStopTailDurationAndFallsBackForUnknownValues() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(userDefaults: defaults)
        var settings = AppSettings.defaults
        settings.recordingStopTailDuration = .seconds2

        store.save(settings)
        #expect(store.load().recordingStopTailDuration == .seconds2)

        defaults.set("legacyUnknownTail", forKey: AppSettingsStore.keyPrefix + "recordingStopTailDuration")
        #expect(store.load().recordingStopTailDuration == .off)
    }

    @Test func legacyRussianToEnglishShortcutSettingMigratesToTranslationShortcut() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: AppSettingsStore.keyPrefix + "translateRussianToEnglishShortcutEnabled")
        let store = AppSettingsStore(userDefaults: defaults)

        var settings = store.load()

        #expect(settings.translationShortcutEnabled)
        #expect(settings.translationSourceMode == .override)
        #expect(settings.translationSourceLanguage == .russian)
        #expect(settings.resolvedTranslationSourceLanguageCode == "ru")
        #expect(settings.translationTargetLanguage == .english)
        #expect(settings.resolvedTranslationTargetLanguageCode == "en")
        #expect(settings.canRunTranslation)

        settings.translationShortcutEnabled = false
        store.save(settings)

        #expect(defaults.object(forKey: AppSettingsStore.keyPrefix + "translateRussianToEnglishShortcutEnabled") == nil)
        #expect(defaults.bool(forKey: AppSettingsStore.keyPrefix + "translationShortcutEnabled") == false)
        #expect(
            defaults.string(forKey: AppSettingsStore.keyPrefix + "translationSourceMode")
                == TranslationSourceMode.override.rawValue
        )
    }

    @Test func enabledTranslationSettingsWithoutSourceModePreserveSourceOverride() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: AppSettingsStore.keyPrefix + "translationShortcutEnabled")
        defaults.set("spanish", forKey: AppSettingsStore.keyPrefix + "translationSourceLanguage")
        defaults.set("english", forKey: AppSettingsStore.keyPrefix + "translationTargetLanguage")

        let settings = AppSettingsStore(userDefaults: defaults).load()

        #expect(settings.translationSourceMode == .override)
        #expect(settings.translationSourceLanguage == .spanish)
        #expect(settings.resolvedTranslationSourceLanguageCode == "es")
        #expect(settings.translationTargetLanguage == .english)
        #expect(settings.canRunTranslation)
    }

    @Test func invalidPersistedLanguageFallsBackToAutomatic() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("unsupported-language", forKey: AppSettingsStore.keyPrefix + "language")

        let settings = AppSettingsStore(userDefaults: defaults).load()

        #expect(settings.language == .automatic)
    }

    @Test func languagePersistenceKeepsRawABIAndUnnormalizedCustomInput() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(userDefaults: defaults)
        var settings = AppSettings.defaults
        settings.language = .automatic
        settings.customLanguageCode = " RU "

        store.save(settings)

        #expect(defaults.string(forKey: AppSettingsStore.keyPrefix + "language") == "auto")
        #expect(
            defaults.string(forKey: AppSettingsStore.keyPrefix + "customLanguageCode") ==
                " RU "
        )
        #expect(store.load().customLanguageCode == " RU ")
    }

    @Test func blankPersistedTextCorrectionPromptLoadsDefaultPrompt() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("   ", forKey: AppSettingsStore.keyPrefix + "textCorrectionPrompt")

        let settings = AppSettingsStore(userDefaults: defaults).load()

        #expect(settings.textCorrectionPrompt == AppSettings.defaultTextCorrectionPrompt)
        #expect(settings.isTextCorrectionPromptDefault)
    }

    @Test func blankPersistedTranslationPromptLoadsDefaultPrompt() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("   ", forKey: AppSettingsStore.keyPrefix + "translationPrompt")

        let settings = AppSettingsStore(userDefaults: defaults).load()

        #expect(settings.translationPrompt == AppSettings.defaultTranslationPrompt)
        #expect(settings.isTranslationPromptDefault)
    }

    private func makeIsolatedUserDefaults() -> (UserDefaults, String) {
        let suiteName = "holdtype.AppSettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated UserDefaults suite")
            return (.standard, suiteName)
        }

        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
