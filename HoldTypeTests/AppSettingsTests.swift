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
        #expect(settings.resolvedCustomDictionary.promptText == nil)
        #expect(settings.emojiCommandsEnabled)
        #expect(settings.enabledEmojiCommandSetIDs == ["en"])
        #expect(settings.emojiCommandsConfiguration == .defaults)
        #expect(settings.emojiCommandsConfiguration.enabledBuiltInSets.map(\.id) == ["en"])
        #expect(EmojiCommandSet.builtIn.map(\.id) == ["en", "ru", "es", "de", "fr", "pt"])
        #expect(EmojiCommandSet.builtIn.allSatisfy { $0.commands.count == 21 })
        #expect(settings.customEmojiCommands.isEmpty)
        #expect(settings.emojiCommandsConfiguration.enabledCustomCommands.isEmpty)
        #expect(settings.emojiCommandsConfiguration.promptText?.contains("emoji smile") == true)
        #expect(settings.resolvedPrompt?.contains("Emoji command vocabulary") == true)
        #expect(settings.useActiveTextContext == false)
        #expect(settings.textCorrectionEnabled == false)
        #expect(settings.textCorrectionModelPreset == .quality)
        #expect(settings.customTextCorrectionModel.isEmpty)
        #expect(settings.textCorrectionConfiguration == .defaults)
        #expect(settings.resolvedTextCorrectionModel == "gpt-5.5")
        #expect(settings.textCorrectionPrompt == AppSettings.defaultTextCorrectionPrompt)
        #expect(
            settings.textCorrectionConfiguration.resolvedPrompt
                == AppSettings.defaultTextCorrectionPrompt
        )
        #expect(settings.isTextCorrectionPromptDefault)
        #expect(settings.localTextCleanupEnabled)
        #expect(settings.textReplacementRules.isEmpty)
        #expect(settings.enabledTextReplacementRules.isEmpty)
        #expect(settings.transcriptPostProcessingConfiguration == .defaults)
        #expect(settings.translationShortcutEnabled)
        #expect(settings.translationSourceMode == .sameAsTranscription)
        #expect(settings.translationSourceLanguage == .automatic)
        #expect(settings.translationConfiguration == .defaults)
        #expect(settings.resolvedTranslationSourceLanguageCode == nil)
        #expect(settings.isTranslationSourceConfigurationValid)
        #expect(settings.translationTargetLanguage == .automatic)
        #expect(settings.resolvedTranslationTargetLanguageCode == nil)
        #expect(settings.translationModel == AppSettings.defaultTranslationModel)
        #expect(settings.translationConfiguration.resolvedModel == "gpt-5.4-mini")
        #expect(settings.translationPrompt == AppSettings.defaultTranslationPrompt)
        #expect(
            settings.translationConfiguration.resolvedPrompt
                == AppSettings.defaultTranslationPrompt
        )
        #expect(settings.isTranslationPromptDefault)
        #expect(settings.translationConfigurationIssue == .missingTargetLanguage)
        #expect(settings.canRunTranslation == false)
        #expect(settings.automaticallyInsertTranscripts)
        #expect(settings.saveTranscriptsToAppClipboard)
        #expect(settings.outputDeliveryPreferences == .defaults)
        #expect(settings.soundEnabled)
        #expect(settings.voiceSessionPreferences == .defaults)
        #expect(settings.showFloatingIndicator)
        #expect(settings.recordingStopTailDuration == .off)
        #expect(settings.recordingStopTailDuration.duration == 0)
        #expect(settings.recordingDurationLimit == .default)
        #expect(settings.recordingDurationLimit.minutes == 5)
        #expect(settings.saveTranscriptHistory)
        #expect(settings.recordingCachePolicy == .deleteImmediately)
        #expect(settings.recordingCachePolicy.keepsRecordings == false)
        #expect(settings.retentionConfiguration == .defaults)
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
        #expect(settings.resolvedCustomDictionary.promptText == "OpenWhispr, Synty")
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

            \(AppSettings.emojiCommandsPromptPrefix)\(
                settings.emojiCommandsConfiguration.promptText ?? ""
            )
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
        #expect(
            disabledSettings.transcriptionPromptComposition(context: context)
                .contextEchoGuardText == nil
        )

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
        let composition = enabledSettings.transcriptionPromptComposition(context: context)
        #expect(composition.providerPrompt == enabledSettings.resolvedPrompt(context: context))
        #expect(
            composition.contextEchoGuardText ==
                "The user is already writing about macOS Accessibility."
        )
        #expect(composition.dictionaryEchoGuardText == "HoldType")
    }

    @Test func projectsOneFrozenAudioTranscriptionRequest() throws {
        var settings = AppSettings.defaults
        settings.transcriptionModel = "  custom-transcribe  "
        settings.language = .custom
        settings.customLanguageCode = " PT "
        settings.prompt = "Prefer product vocabulary."
        settings.useActiveTextContext = true
        settings.customDictionary = ["HoldType"]
        let audioFileURL = URL(fileURLWithPath: "/tmp/frozen-request.m4a")
        let context = try #require(TranscriptionPromptContext("Existing sentence."))

        let request = try settings.audioTranscriptionRequest(
            audioFileURL: audioFileURL,
            context: context
        )

        #expect(request.audioFileURL == audioFileURL)
        #expect(request.model == "custom-transcribe")
        #expect(request.languageCode == "pt")
        #expect(
            request.promptComposition ==
                settings.transcriptionPromptComposition(context: context)
        )
    }

    @Test func rejectsInvalidCustomLanguageBeforeProducingAnAudioRequest() {
        var settings = AppSettings.defaults
        settings.language = .custom
        settings.customLanguageCode = "en-US"

        #expect(
            throws: AudioTranscriptionRequest.ValidationError.invalidCustomLanguageCode("en-US")
        ) {
            _ = try settings.audioTranscriptionRequest(
                audioFileURL: URL(fileURLWithPath: "/tmp/invalid-request.m4a"),
                context: nil
            )
        }
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
        #expect(settings.textCorrectionConfiguration.resolvedPrompt == "Fix only punctuation.")
        #expect(settings.enabledTextReplacementRules.count == 1)
        #expect(settings.enabledTextReplacementRules.first?.replacement == "plain")
        #expect(
            settings.transcriptPostProcessingConfiguration.textReplacementRules ==
                settings.textReplacementRules
        )

        settings.customTextCorrectionModel = "  "
        settings.textCorrectionPrompt = "  "

        #expect(settings.resolvedTextCorrectionModel == AppSettings.defaultTextCorrectionModel)
        #expect(
            settings.textCorrectionConfiguration.resolvedPrompt
                == AppSettings.defaultTextCorrectionPrompt
        )
    }

    @Test func projectsRawTextCorrectionConfigurationWithoutOwningPersistence() {
        var settings = AppSettings.defaults
        settings.textCorrectionEnabled = true
        settings.textCorrectionModelPreset = .custom
        settings.customTextCorrectionModel = "  custom-correction-model  "
        settings.textCorrectionPrompt = "  Correct names only.  "

        let configuration = settings.textCorrectionConfiguration

        #expect(configuration.isEnabled)
        #expect(configuration.modelPreset == .custom)
        #expect(configuration.customModel == "  custom-correction-model  ")
        #expect(configuration.prompt == "  Correct names only.  ")
        #expect(settings.resolvedTextCorrectionModel == configuration.resolvedModel)
        #expect(settings.textCorrectionConfiguration.resolvedPrompt == configuration.resolvedPrompt)
        #expect(settings.isTextCorrectionPromptDefault == configuration.isPromptDefault)
    }

    @Test func resolvesEmojiCommandPromptFromActiveSet() {
        var settings = AppSettings.defaults

        #expect(settings.emojiCommandsConfiguration.enabledBuiltInSets.map(\.id) == ["en"])
        #expect(settings.emojiCommandsConfiguration.promptText?.contains("emoji smile") == true)
        #expect(
            settings.emojiCommandsConfiguration.promptText?
                .contains("эмодзи улыбка") == false
        )

        settings.enabledEmojiCommandSetIDs = ["ru", "missing", "en", "ru", "de"]
        settings.customEmojiCommands = [
            CustomEmojiCommand(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000321")!,
                emoji: "🚀",
                command: "emoji rocket",
                aliases: ["launch emoji"]
            )
        ]

        #expect(settings.emojiCommandsConfiguration.enabledBuiltInSets.map(\.id) == ["ru"])
        #expect(
            settings.emojiCommandsConfiguration.enabledCustomCommands
                .map(\.displayCommand) == ["emoji rocket"]
        )
        #expect(settings.emojiCommandsConfiguration.promptText?.contains("emoji smile") == false)
        #expect(
            settings.emojiCommandsConfiguration.promptText?
                .contains("эмодзи улыбка") == true
        )
        #expect(
            settings.emojiCommandsConfiguration.promptText?
                .contains("эмодзи смех") == true
        )
        #expect(settings.emojiCommandsConfiguration.promptText?.contains("эмоции") == false)
        #expect(settings.emojiCommandsConfiguration.promptText?.contains("эмоджи") == false)
        #expect(settings.emojiCommandsConfiguration.promptText?.contains("emoji lächeln") == false)
        #expect(settings.emojiCommandsConfiguration.promptText?.contains("emoji rocket") == true)
        #expect(settings.emojiCommandsConfiguration.promptText?.contains("launch emoji") == true)

        settings.emojiCommandsEnabled = false

        #expect(settings.emojiCommandsConfiguration.enabledBuiltInSets.isEmpty)
        #expect(settings.emojiCommandsConfiguration.enabledCustomCommands.isEmpty)
        #expect(settings.emojiCommandsConfiguration.promptText == nil)
    }

    @Test func projectsRawEmojiConfigurationAndDelegatesResolvedValues() {
        var settings = AppSettings.defaults
        settings.emojiCommandsEnabled = true
        settings.enabledEmojiCommandSetIDs = ["missing", " ru ", "en"]
        settings.customEmojiCommands = [
            CustomEmojiCommand(emoji: " 🚀 ", command: " Emoji   Rocket ")
        ]

        let configuration = settings.emojiCommandsConfiguration

        #expect(configuration.isEnabled)
        #expect(configuration.enabledBuiltInSetIDs == ["missing", " ru ", "en"])
        #expect(configuration.customCommands == settings.customEmojiCommands)
        #expect(
            settings.emojiCommandsConfiguration.enabledBuiltInSets
                == configuration.enabledBuiltInSets
        )
        #expect(
            settings.emojiCommandsConfiguration.enabledCustomCommands
                == configuration.enabledCustomCommands
        )
        #expect(settings.emojiCommandsConfiguration.promptText == configuration.promptText)
        #expect(
            AppSettings.normalizedEmojiCommandSetIDs(settings.enabledEmojiCommandSetIDs) ==
                configuration.normalizedEnabledBuiltInSetIDs
        )
        #expect(
            AppSettings.normalizedCustomEmojiCommands(settings.customEmojiCommands) ==
                configuration.normalizedCustomCommands
        )
    }

    @Test func keepsExactFourPartTranscriptionPromptOrder() throws {
        var settings = AppSettings.defaults
        settings.prompt = "Prefer product vocabulary."
        settings.useActiveTextContext = true
        settings.enabledEmojiCommandSetIDs = []
        settings.customEmojiCommands = [
            CustomEmojiCommand(emoji: "🚀", command: "emoji rocket")
        ]
        settings.customDictionary = ["HoldType"]
        let context = try #require(TranscriptionPromptContext("Existing sentence."))

        #expect(
            settings.resolvedPrompt(context: context) ==
                """
                Prefer product vocabulary.

                Current writing context near the cursor. Use this only for continuity; transcribe only the new speech:
                Existing sentence.

                Emoji command vocabulary (transcribe these spoken phrases exactly when spoken): emoji rocket

                Custom Dictionary (use these exact spellings when they appear in the text): HoldType
                """
        )
        let composition = settings.transcriptionPromptComposition(context: context)
        #expect(composition.providerPrompt == settings.resolvedPrompt(context: context))
        #expect(composition.contextEchoGuardText == "Existing sentence.")
        #expect(composition.dictionaryEchoGuardText == "HoldType")
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
        #expect(settings.translationConfiguration.resolvedModel == "custom-translation-model")
        #expect(
            settings.translationConfiguration.resolvedPrompt
                == "Translate for product UI labels."
        )
        #expect(settings.canRunTranslation)
        #expect(settings.isTranslationPromptDefault == false)

        settings.translationModel = "  "
        settings.translationPrompt = "  "

        #expect(
            settings.translationConfiguration.resolvedModel
                == AppSettings.defaultTranslationModel
        )
        #expect(
            settings.translationConfiguration.resolvedPrompt
                == AppSettings.defaultTranslationPrompt
        )

        settings.resetTranslationPrompt()

        #expect(settings.translationPrompt == AppSettings.defaultTranslationPrompt)
        #expect(settings.isTranslationPromptDefault)
    }

    @Test func projectsRawTranslationConfigurationAndDelegatesResolvedValues() {
        var settings = AppSettings.defaults
        settings.translationShortcutEnabled = false
        settings.translationSourceMode = .override
        settings.translationSourceLanguage = .custom
        settings.customTranslationSourceLanguageCode = "  ES  "
        settings.translationTargetLanguage = .custom
        settings.customTranslationTargetLanguageCode = "  ENG  "
        settings.translationModel = "  custom-translation-model  "
        settings.translationPrompt = "  Translate names only.  "

        let configuration = settings.translationConfiguration

        #expect(configuration.actionPreferenceEnabled == false)
        #expect(configuration.sourceMode == .override)
        #expect(configuration.sourceLanguage == .custom)
        #expect(configuration.customSourceLanguageCode == "  ES  ")
        #expect(configuration.targetLanguage == .custom)
        #expect(configuration.customTargetLanguageCode == "  ENG  ")
        #expect(configuration.model == "  custom-translation-model  ")
        #expect(configuration.prompt == "  Translate names only.  ")
        #expect(
            settings.resolvedTranslationSourceLanguageCode ==
                configuration.resolvedSourceLanguageCode(
                    transcriptionConfiguration: settings.transcriptionConfiguration
                )
        )
        #expect(
            settings.resolvedTranslationTargetLanguageCode ==
                configuration.resolvedTargetLanguageCode
        )
        #expect(settings.translationConfiguration.resolvedModel == configuration.resolvedModel)
        #expect(settings.translationConfiguration.resolvedPrompt == configuration.resolvedPrompt)
        #expect(settings.isTranslationPromptDefault == configuration.isPromptDefault)
        #expect(settings.translationConfigurationIssue == configuration.configurationIssue)
        #expect(settings.canRunTranslation == configuration.canRunAction)
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
        #expect(
            settings.textCorrectionConfiguration.resolvedPrompt
                == "Correct obvious names only."
        )

        settings.resetTextCorrectionPrompt()

        #expect(settings.textCorrectionPrompt == AppSettings.defaultTextCorrectionPrompt)
        #expect(
            settings.textCorrectionConfiguration.resolvedPrompt
                == AppSettings.defaultTextCorrectionPrompt
        )
        #expect(settings.isTextCorrectionPromptDefault)
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
        #expect(settings.resolvedCustomDictionary.promptText == "ACME, Inc., Line\nBreak")

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
            recordingDurationLimit: RecordingDurationLimit(minutes: 12),
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

    @Test func projectsRawRetentionConfigurationWithoutOwningPersistence() {
        var settings = AppSettings.defaults
        settings.saveTranscriptHistory = false
        settings.recordingCachePolicy = .keepLast(0)

        let configuration = settings.retentionConfiguration

        #expect(configuration.historyEnabled == false)
        #expect(configuration.recordingCachePolicy == .keepLast(0))
        #expect(configuration.recordingCachePolicy.normalized == .keepLast(1))
    }

    @Test func recordingCachePolicyPersistenceKeepsTheLegacyTwoKeySchema() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let modeKey = AppSettingsStore.keyPrefix + "recordingCachePolicyMode"
        let countKey = AppSettingsStore.keyPrefix + "recordingCacheRetainedRecordingLimit"
        let store = AppSettingsStore(userDefaults: defaults)

        defaults.set(42, forKey: countKey)
        #expect(store.load().recordingCachePolicy == .deleteImmediately)
        #expect(defaults.integer(forKey: countKey) == 42)

        defaults.set("unknown-mode", forKey: modeKey)
        #expect(store.load().recordingCachePolicy == .deleteImmediately)
        #expect(defaults.string(forKey: modeKey) == "unknown-mode")
        #expect(defaults.integer(forKey: countKey) == 42)

        defaults.set("keepLast", forKey: modeKey)
        defaults.set("not-an-int", forKey: countKey)
        #expect(
            store.load().recordingCachePolicy ==
                .keepLast(RecordingCachePolicy.defaultRetainedRecordingLimit)
        )
        #expect(defaults.string(forKey: countKey) == "not-an-int")

        defaults.set(Int.min, forKey: countKey)
        #expect(store.load().recordingCachePolicy == .keepLast(1))
        #expect(defaults.object(forKey: countKey) as? Int == Int.min)

        defaults.set(Int.max, forKey: countKey)
        #expect(store.load().recordingCachePolicy == .keepLast(999))
        #expect(defaults.object(forKey: countKey) as? Int == Int.max)

        var settings = AppSettings.defaults
        settings.recordingCachePolicy = .keepLast(1_000)
        store.save(settings)
        #expect(defaults.string(forKey: modeKey) == "keepLast")
        #expect(defaults.integer(forKey: countKey) == 999)

        settings.recordingCachePolicy = .unlimited
        store.save(settings)
        #expect(defaults.string(forKey: modeKey) == "unlimited")
        #expect(defaults.object(forKey: countKey) == nil)

        defaults.set(77, forKey: countKey)
        settings.recordingCachePolicy = .deleteImmediately
        store.save(settings)
        #expect(defaults.string(forKey: modeKey) == "deleteImmediately")
        #expect(defaults.object(forKey: countKey) == nil)
    }

    @Test func transcriptHistoryDefaultMigrationPreservesEveryLegacyState() {
        let historyKey = AppSettingsStore.keyPrefix + "saveTranscriptHistory"
        let markerKey = "holdtype.migrations.transcriptHistoryDefaultEnabled"

        func makeStore(savedValue: Bool?, markerValue: Bool?) -> (
            UserDefaults,
            String,
            AppSettingsStore
        ) {
            let (defaults, suiteName) = makeIsolatedUserDefaults()
            if let savedValue {
                defaults.set(savedValue, forKey: historyKey)
            }
            if let markerValue {
                defaults.set(markerValue, forKey: markerKey)
            }
            return (defaults, suiteName, AppSettingsStore(userDefaults: defaults))
        }

        var fixtures: [(UserDefaults, String)] = []
        defer {
            for (defaults, suiteName) in fixtures {
                defaults.removePersistentDomain(forName: suiteName)
            }
        }

        let missing = makeStore(savedValue: nil, markerValue: nil)
        fixtures.append((missing.0, missing.1))
        #expect(missing.2.load().saveTranscriptHistory)
        #expect(missing.0.bool(forKey: markerKey))
        #expect(missing.0.object(forKey: historyKey) == nil)

        let enabled = makeStore(savedValue: true, markerValue: nil)
        fixtures.append((enabled.0, enabled.1))
        #expect(enabled.2.load().saveTranscriptHistory)
        #expect(enabled.0.bool(forKey: markerKey))
        #expect(enabled.0.bool(forKey: historyKey))

        let legacyDisabled = makeStore(savedValue: false, markerValue: nil)
        fixtures.append((legacyDisabled.0, legacyDisabled.1))
        #expect(legacyDisabled.2.load().saveTranscriptHistory)
        #expect(legacyDisabled.0.bool(forKey: markerKey))
        #expect(legacyDisabled.0.bool(forKey: historyKey))

        let explicitDisabled = makeStore(savedValue: false, markerValue: true)
        fixtures.append((explicitDisabled.0, explicitDisabled.1))
        #expect(explicitDisabled.2.load().saveTranscriptHistory == false)
        #expect(explicitDisabled.0.bool(forKey: markerKey))
        #expect(explicitDisabled.0.bool(forKey: historyKey) == false)

        let migratedMissing = makeStore(savedValue: nil, markerValue: true)
        fixtures.append((migratedMissing.0, migratedMissing.1))
        #expect(migratedMissing.2.load().saveTranscriptHistory)
        #expect(migratedMissing.0.object(forKey: historyKey) == nil)
    }

    @Test func projectsVoiceSessionPreferencesWithoutIncludingMacOnlyIndicatorState() {
        var settings = AppSettings.defaults
        settings.soundEnabled = false
        settings.recordingStopTailDuration = .seconds1_5
        settings.recordingDurationLimit = RecordingDurationLimit(minutes: 12)
        settings.showFloatingIndicator = false

        #expect(settings.voiceSessionPreferences == VoiceSessionPreferences(
            audioCuesEnabled: false,
            recordingStopTailDuration: .seconds1_5,
            recordingDurationLimit: RecordingDurationLimit(minutes: 12)
        ))
        #expect(RecordingStopTailDuration.allCases.map(\.displayName) == [
            "Off",
            "0.5 seconds",
            "1.0 second",
            "1.5 seconds",
            "2.0 seconds",
        ])
        #expect(RecordingDurationLimit.allValues.map(\.displayName).first == "1 minute")
        #expect(RecordingDurationLimit.allValues.map(\.displayName).last == "15 minutes")
    }

    @Test func projectsOutputDeliveryPreferencesWithoutClaimingRuntimeEligibility() {
        var settings = AppSettings.defaults
        settings.automaticallyInsertTranscripts = false
        settings.saveTranscriptsToAppClipboard = true

        #expect(settings.outputDeliveryPreferences == OutputDeliveryPreferences(
            automaticInsertionPreferenceEnabled: false,
            keepLatestResult: true
        ))
    }

    @Test func outputDeliveryPreferencePersistenceKeepsTheLegacyBoolKeys() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(userDefaults: defaults)
        let insertionKey = AppSettingsStore.keyPrefix + "automaticallyInsertTranscripts"
        let latestResultKey = AppSettingsStore.keyPrefix + "saveTranscriptsToAppClipboard"
        let combinations = [
            OutputDeliveryPreferences(
                automaticInsertionPreferenceEnabled: false,
                keepLatestResult: false
            ),
            OutputDeliveryPreferences(
                automaticInsertionPreferenceEnabled: false,
                keepLatestResult: true
            ),
            OutputDeliveryPreferences(
                automaticInsertionPreferenceEnabled: true,
                keepLatestResult: false
            ),
            .defaults,
        ]

        for preferences in combinations {
            var settings = AppSettings.defaults
            settings.automaticallyInsertTranscripts =
                preferences.automaticInsertionPreferenceEnabled
            settings.saveTranscriptsToAppClipboard = preferences.keepLatestResult
            store.save(settings)

            #expect(
                defaults.bool(forKey: insertionKey) ==
                    preferences.automaticInsertionPreferenceEnabled
            )
            #expect(defaults.bool(forKey: latestResultKey) == preferences.keepLatestResult)
            #expect(store.load().outputDeliveryPreferences == preferences)
        }

        defaults.set("not-a-bool", forKey: insertionKey)
        defaults.set(Data([0x01]), forKey: latestResultKey)
        #expect(store.load().outputDeliveryPreferences == .defaults)
        #expect(defaults.string(forKey: insertionKey) == "not-a-bool")
        #expect(defaults.data(forKey: latestResultKey) == Data([0x01]))

        defaults.removeObject(forKey: insertionKey)
        defaults.removeObject(forKey: latestResultKey)
        #expect(store.load().outputDeliveryPreferences == .defaults)
        #expect(defaults.object(forKey: insertionKey) == nil)
        #expect(defaults.object(forKey: latestResultKey) == nil)
    }

    @Test func voiceSessionPreferencePersistenceKeepsLegacyKeysAndRawValues() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(userDefaults: defaults)
        var settings = AppSettings.defaults
        let soundKey = AppSettingsStore.keyPrefix + "soundEnabled"
        let tailKey = AppSettingsStore.keyPrefix + "recordingStopTailDuration"
        let durationLimitKey = AppSettingsStore.keyPrefix
            + "recordingDurationLimitMinutes"

        settings.soundEnabled = false
        settings.recordingDurationLimit = RecordingDurationLimit(minutes: 12)
        for tail in RecordingStopTailDuration.allCases {
            settings.recordingStopTailDuration = tail
            store.save(settings)
            #expect(defaults.bool(forKey: soundKey) == false)
            #expect(defaults.string(forKey: tailKey) == tail.rawValue)
            #expect(store.load().voiceSessionPreferences == VoiceSessionPreferences(
                audioCuesEnabled: false,
                recordingStopTailDuration: tail,
                recordingDurationLimit: RecordingDurationLimit(minutes: 12)
            ))
        }
        #expect(defaults.integer(forKey: durationLimitKey) == 12)

        defaults.set("legacyUnknownTail", forKey: tailKey)
        #expect(store.load().recordingStopTailDuration == .off)
        #expect(defaults.string(forKey: tailKey) == "legacyUnknownTail")

        defaults.set("not-a-bool", forKey: soundKey)
        defaults.set(Data([0x01]), forKey: tailKey)
        defaults.set(Data([0x02]), forKey: durationLimitKey)
        #expect(store.load().voiceSessionPreferences == .defaults)
        #expect(defaults.string(forKey: soundKey) == "not-a-bool")
        #expect(defaults.data(forKey: tailKey) == Data([0x01]))
        #expect(defaults.data(forKey: durationLimitKey) == Data([0x02]))

        defaults.removeObject(forKey: soundKey)
        defaults.removeObject(forKey: tailKey)
        defaults.removeObject(forKey: durationLimitKey)
        #expect(store.load().voiceSessionPreferences == .defaults)
        #expect(defaults.object(forKey: soundKey) == nil)
        #expect(defaults.object(forKey: tailKey) == nil)
    }

    @Test func recordingDurationLimitPersistenceDefaultsClampsAndRejectsWrongTypes() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(userDefaults: defaults)
        let key = AppSettingsStore.keyPrefix + "recordingDurationLimitMinutes"

        #expect(store.load().recordingDurationLimit == .default)

        for minutes in [1, 5, 15] {
            var settings = AppSettings.defaults
            settings.recordingDurationLimit = RecordingDurationLimit(minutes: minutes)
            store.save(settings)

            #expect(defaults.integer(forKey: key) == minutes)
            #expect(store.load().recordingDurationLimit.minutes == minutes)
        }

        defaults.set(-100, forKey: key)
        #expect(
            store.load().recordingDurationLimit.minutes
                == RecordingDurationLimit.minimumMinutes
        )

        defaults.set(100, forKey: key)
        #expect(
            store.load().recordingDurationLimit.minutes
                == RecordingDurationLimit.maximumMinutes
        )

        defaults.set("not-an-integer", forKey: key)
        #expect(store.load().recordingDurationLimit == .default)
        #expect(defaults.string(forKey: key) == "not-an-integer")

        defaults.set(Data([0x01]), forKey: key)
        #expect(store.load().recordingDurationLimit == .default)
        #expect(defaults.data(forKey: key) == Data([0x01]))

        defaults.set(true, forKey: key)
        #expect(store.load().recordingDurationLimit == .default)
        #expect(defaults.bool(forKey: key))

        defaults.set(12.0, forKey: key)
        #expect(store.load().recordingDurationLimit == .default)
        #expect(defaults.double(forKey: key) == 12)
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

    @Test func explicitDisabledTranslationPreferenceKeepsLegacyRouteUntilSave() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let enabledKey = AppSettingsStore.keyPrefix + "translationShortcutEnabled"
        let legacyKey = AppSettingsStore.keyPrefix + "translateRussianToEnglishShortcutEnabled"
        let modeKey = AppSettingsStore.keyPrefix + "translationSourceMode"
        let sourceKey = AppSettingsStore.keyPrefix + "translationSourceLanguage"
        let targetKey = AppSettingsStore.keyPrefix + "translationTargetLanguage"
        defaults.set(false, forKey: enabledKey)
        defaults.set(true, forKey: legacyKey)
        let store = AppSettingsStore(userDefaults: defaults)

        let settings = store.load()

        #expect(settings.translationShortcutEnabled == false)
        #expect(settings.translationSourceMode == .override)
        #expect(settings.translationSourceLanguage == .russian)
        #expect(settings.translationTargetLanguage == .english)
        #expect(settings.translationConfigurationIssue == nil)
        #expect(settings.canRunTranslation == false)
        #expect(defaults.object(forKey: modeKey) == nil)
        #expect(defaults.object(forKey: sourceKey) == nil)
        #expect(defaults.object(forKey: targetKey) == nil)

        store.save(settings)

        #expect(defaults.bool(forKey: enabledKey) == false)
        #expect(defaults.string(forKey: modeKey) == "override")
        #expect(defaults.string(forKey: sourceKey) == "russian")
        #expect(defaults.string(forKey: targetKey) == "english")
        #expect(defaults.object(forKey: legacyKey) == nil)
    }

    @Test func translationPersistenceKeepsRawValuesAndFallbacksWithoutLoadRewrite() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let enabledKey = AppSettingsStore.keyPrefix + "translationShortcutEnabled"
        let legacyKey = AppSettingsStore.keyPrefix + "translateRussianToEnglishShortcutEnabled"
        let modeKey = AppSettingsStore.keyPrefix + "translationSourceMode"
        let sourceKey = AppSettingsStore.keyPrefix + "translationSourceLanguage"
        let customSourceKey = AppSettingsStore.keyPrefix + "customTranslationSourceLanguageCode"
        let targetKey = AppSettingsStore.keyPrefix + "translationTargetLanguage"
        let customTargetKey = AppSettingsStore.keyPrefix + "customTranslationTargetLanguageCode"
        let modelKey = AppSettingsStore.keyPrefix + "translationModel"
        let promptKey = AppSettingsStore.keyPrefix + "translationPrompt"
        defaults.set(false, forKey: enabledKey)
        defaults.set(true, forKey: legacyKey)
        defaults.set("unknown-mode", forKey: modeKey)
        defaults.set("unknown-source", forKey: sourceKey)
        defaults.set("  ES  ", forKey: customSourceKey)
        defaults.set("unknown-target", forKey: targetKey)
        defaults.set("  ENG  ", forKey: customTargetKey)
        defaults.set("  custom-translation-model  ", forKey: modelKey)
        defaults.set("  Keep raw translation prompt.  ", forKey: promptKey)
        let store = AppSettingsStore(userDefaults: defaults)

        var settings = store.load()

        #expect(settings.translationShortcutEnabled == false)
        #expect(settings.translationSourceMode == .sameAsTranscription)
        #expect(settings.translationSourceLanguage == .automatic)
        #expect(settings.translationTargetLanguage == .automatic)
        #expect(settings.customTranslationSourceLanguageCode == "  ES  ")
        #expect(settings.customTranslationTargetLanguageCode == "  ENG  ")
        #expect(settings.translationModel == "  custom-translation-model  ")
        #expect(settings.translationPrompt == "  Keep raw translation prompt.  ")
        #expect(defaults.string(forKey: modeKey) == "unknown-mode")
        #expect(defaults.string(forKey: sourceKey) == "unknown-source")
        #expect(defaults.string(forKey: targetKey) == "unknown-target")

        settings.translationShortcutEnabled = true
        settings.translationSourceMode = .override
        settings.translationSourceLanguage = .custom
        settings.translationTargetLanguage = .custom
        store.save(settings)

        #expect(defaults.bool(forKey: enabledKey))
        #expect(defaults.string(forKey: modeKey) == "override")
        #expect(defaults.string(forKey: sourceKey) == "custom")
        #expect(defaults.string(forKey: customSourceKey) == "  ES  ")
        #expect(defaults.string(forKey: targetKey) == "custom")
        #expect(defaults.string(forKey: customTargetKey) == "  ENG  ")
        #expect(defaults.string(forKey: modelKey) == "  custom-translation-model  ")
        #expect(defaults.string(forKey: promptKey) == "  Keep raw translation prompt.  ")
        #expect(defaults.object(forKey: legacyKey) == nil)
        #expect(store.load().translationConfiguration == settings.translationConfiguration)
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

    @Test func textCorrectionPersistenceKeepsLegacyRawValuesAndLoadFallbacks() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let enabledKey = AppSettingsStore.keyPrefix + "textCorrectionEnabled"
        let presetKey = AppSettingsStore.keyPrefix + "textCorrectionModelPreset"
        let customModelKey = AppSettingsStore.keyPrefix + "customTextCorrectionModel"
        let promptKey = AppSettingsStore.keyPrefix + "textCorrectionPrompt"
        defaults.set("legacy-unknown-preset", forKey: presetKey)
        defaults.set("  raw-custom-model  ", forKey: customModelKey)
        defaults.set("   ", forKey: promptKey)
        let store = AppSettingsStore(userDefaults: defaults)

        var settings = store.load()

        #expect(settings.textCorrectionModelPreset == .quality)
        #expect(settings.customTextCorrectionModel == "  raw-custom-model  ")
        #expect(settings.textCorrectionPrompt == AppSettings.defaultTextCorrectionPrompt)
        #expect(defaults.string(forKey: presetKey) == "legacy-unknown-preset")
        #expect(defaults.string(forKey: promptKey) == "   ")

        settings.textCorrectionEnabled = true
        settings.textCorrectionModelPreset = .fast
        settings.customTextCorrectionModel = "  saved-custom-model  "
        settings.textCorrectionPrompt = "  Keep raw prompt spacing.  "
        store.save(settings)

        #expect(defaults.bool(forKey: enabledKey))
        #expect(defaults.string(forKey: presetKey) == "fast")
        #expect(defaults.string(forKey: customModelKey) == "  saved-custom-model  ")
        #expect(defaults.string(forKey: promptKey) == "  Keep raw prompt spacing.  ")
        #expect(store.load().textCorrectionConfiguration == settings.textCorrectionConfiguration)
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
