//
//  AppSettingsTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/20/26.
//

import Foundation
import Testing
@testable import vibetype

struct AppSettingsTests {

    @Test func defaultsMatchMVPContracts() {
        let settings = AppSettings.defaults

        #expect(settings.transcriptionModel == "gpt-4o-transcribe")
        #expect(settings.resolvedTranscriptionModel == "gpt-4o-transcribe")
        #expect(settings.language == .automatic)
        #expect(settings.resolvedLanguageCode == nil)
        #expect(settings.customLanguageCode.isEmpty)
        #expect(settings.resolvedPrompt == nil)
        #expect(settings.saveTranscriptsToAppClipboard)
        #expect(settings.soundEnabled)
        #expect(settings.showFloatingIndicator)
        #expect(settings.saveTranscriptHistory == false)
    }

    @Test func resolvesBlankModelAndPromptWithoutMutatingStoredValues() {
        var settings = AppSettings.defaults
        settings.transcriptionModel = "  "
        settings.prompt = "  release names, Swift symbols  "

        #expect(settings.transcriptionModel == "  ")
        #expect(settings.resolvedTranscriptionModel == AppSettings.defaultTranscriptionModel)
        #expect(settings.resolvedPrompt == "release names, Swift symbols")
    }

    @Test func mapsLanguageModesToTranscriptionCodes() {
        #expect(TranscriptionLanguage.automatic.apiLanguageCode(customCode: "de") == nil)
        #expect(TranscriptionLanguage.english.apiLanguageCode(customCode: "") == "en")
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
    }

    @Test func loadsDefaultsFromEmptyUserDefaults() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(userDefaults: defaults)

        #expect(store.load() == .defaults)
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
            saveTranscriptsToAppClipboard: false,
            soundEnabled: false,
            showFloatingIndicator: true,
            saveTranscriptHistory: true
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

    @Test func invalidPersistedLanguageFallsBackToAutomatic() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("unsupported-language", forKey: AppSettingsStore.keyPrefix + "language")

        let settings = AppSettingsStore(userDefaults: defaults).load()

        #expect(settings.language == .automatic)
    }

    private func makeIsolatedUserDefaults() -> (UserDefaults, String) {
        let suiteName = "vibetype.AppSettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated UserDefaults suite")
            return (.standard, suiteName)
        }

        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
