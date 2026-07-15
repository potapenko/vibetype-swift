import HoldTypeDomain
import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSAppSettingsEditorSupportTests {
    @Test func routeInventoryContainsOnlyGeneralSettingsV1Editors() {
        #expect(
            IOSGeneralSettingsDestination.allCases == [
                .transcription,
                .writingCorrection,
                .translation,
                .voiceRecording,
            ]
        )
        #expect(
            IOSGeneralSettingsDestination.allCases.map(\.title) == [
                "Transcription",
                "Writing & Correction",
                "Translation",
                "Voice & Recording",
            ]
        )
        #expect(
            IOSGeneralSettingsDestination.translation.systemImage
                == "character.bubble"
        )
        #expect(
            Set(
                IOSGeneralSettingsDestination.allCases.map(
                    \.rowAccessibilityIdentifier
                )
            ).count == 4
        )
    }

    @Test func sessionKeepsFailedDraftAndAdoptsCanonicalRetry() {
        var session = IOSSettingsEditorSession(value: "durable")

        session.set("draft", at: \String.self)
        #expect(session.isDirty)
        #expect(session.beginSave() == "draft")
        #expect(session.phase == .saving)

        session.commitFailed(restoring: "new durable")
        #expect(session.baseline == "new durable")
        #expect(session.draft == "draft")
        #expect(session.isDirty)
        #expect(session.phase == .saveFailed)

        #expect(session.beginSave() == "draft")
        session.commitSucceeded(
            returnedDurableValue: "canonical",
            latestDurableValue: "canonical"
        )
        #expect(session.baseline == "canonical")
        #expect(session.draft == "canonical")
        #expect(!session.isDirty)
        #expect(session.phase == .saved)
    }

    @Test func cleanAndDirtySessionsHandleExternalDurableChanges() {
        var clean = IOSSettingsEditorSession(value: "first")
        clean.observeDurableValue("second")
        #expect(clean.baseline == "second")
        #expect(clean.draft == "second")
        #expect(clean.phase == .idle)

        var dirty = IOSSettingsEditorSession(value: "first")
        dirty.set("local", at: \String.self)
        dirty.observeDurableValue("external")
        #expect(dirty.baseline == "external")
        #expect(dirty.draft == "local")
        #expect(dirty.phase == .changedElsewhere)
        #expect(dirty.isDirty)

        dirty.observeDurableValue("local")
        #expect(dirty.baseline == "local")
        #expect(dirty.draft == "local")
        #expect(dirty.phase == .idle)
        #expect(!dirty.isDirty)
    }

    @Test func discardReturnsToLatestObservedDurableValue() {
        var session = IOSSettingsEditorSession(value: "first")
        session.set("draft", at: \String.self)
        session.observeDurableValue("external")

        session.discard()

        #expect(session.baseline == "external")
        #expect(session.draft == "external")
        #expect(session.phase == .idle)
        #expect(!session.isDirty)
    }

    @Test func externalPublicationCannotEndAnInFlightSave() {
        var session = IOSSettingsEditorSession(value: "first")
        session.set("local", at: \String.self)
        #expect(session.beginSave() == "local")

        session.observeDurableValue("external")

        #expect(session.baseline == "external")
        #expect(session.draft == "local")
        #expect(session.phase == .saving)
        #expect(session.isSaving)

        session.set("second local", at: \String.self)
        #expect(session.draft == "local")
        session.commitSucceeded(
            returnedDurableValue: "local",
            latestDurableValue: "local"
        )
        #expect(session.phase == .saved)
        #expect(!session.isDirty)
    }

    @Test func newerSameGroupCommitWinsBeforeOlderCallerResumes() {
        var session = IOSSettingsEditorSession(value: "first")
        session.set("older save", at: \String.self)
        #expect(session.beginSave() == "older save")
        session.observeDurableValue("newer save")

        session.commitSucceeded(
            returnedDurableValue: "older save",
            latestDurableValue: "newer save"
        )

        #expect(session.baseline == "newer save")
        #expect(session.draft == "older save")
        #expect(session.phase == .changedElsewhere)
        #expect(session.isDirty)
    }

    @Test func firstAppearanceAdoptsStateAdvancedAfterConstruction() {
        var session = IOSSettingsEditorSession(value: "navigation snapshot")

        session.observeDurableValue("latest owner value")

        #expect(session.baseline == "latest owner value")
        #expect(session.draft == "latest owner value")
        #expect(session.phase == .idle)
        #expect(!session.isDirty)
    }

    @Test func matchingTheLatestBaselineClearsStaleWarnings() {
        var changed = IOSSettingsEditorSession(value: "first")
        changed.set("local", at: \String.self)
        changed.observeDurableValue("external")
        #expect(changed.phase == .changedElsewhere)

        changed.set("external", at: \String.self)
        #expect(changed.phase == .idle)
        #expect(!changed.isDirty)

        var failed = IOSSettingsEditorSession(value: "first")
        failed.set("local", at: \String.self)
        _ = failed.beginSave()
        failed.commitFailed(restoring: "external")
        #expect(failed.phase == .saveFailed)

        failed.set("external", at: \String.self)
        #expect(failed.phase == .idle)
        #expect(!failed.isDirty)
    }

    @Test func validationAllowsFallbacksAndBlocksMalformedCodes() {
        #expect(IOSCustomLanguageCodeInputState.resolve("") == .empty)
        #expect(IOSCustomLanguageCodeInputState.resolve(" RU ") == .valid)
        #expect(
            IOSCustomLanguageCodeInputState.resolve("russian") == .invalid
        )
        #expect(
            IOSAppSettingsEditorValidation.canSaveTranscription(
                .defaults
            )
        )
        #expect(
            IOSAppSettingsEditorValidation.canSaveTranscription(
                TranscriptionConfiguration(
                    language: .custom,
                    customLanguageCode: ""
                )
            )
        )
        #expect(
            !IOSAppSettingsEditorValidation.canSaveTranscription(
                TranscriptionConfiguration(
                    language: .custom,
                    customLanguageCode: "english"
                )
            )
        )
        #expect(
            IOSAppSettingsEditorValidation.canSaveTranscription(
                TranscriptionConfiguration(
                    language: .custom,
                    customLanguageCode: " RU "
                )
            )
        )

        #expect(
            IOSAppSettingsEditorValidation.canSaveTranslation(.defaults)
        )
        #expect(
            IOSAppSettingsEditorValidation.canSaveTranslation(
                TranslationConfiguration(
                    sourceMode: .override,
                    sourceLanguage: .custom,
                    customSourceLanguageCode: "",
                    targetLanguage: .custom,
                    customTargetLanguageCode: ""
                )
            )
        )
        #expect(
            !IOSAppSettingsEditorValidation.canSaveTranslation(
                TranslationConfiguration(
                    sourceMode: .override,
                    sourceLanguage: .custom,
                    customSourceLanguageCode: "spanish",
                    targetLanguage: .english
                )
            )
        )
        #expect(
            !IOSAppSettingsEditorValidation.canSaveTranslation(
                TranslationConfiguration(
                    targetLanguage: .custom,
                    customTargetLanguageCode: "1a"
                )
            )
        )
    }

    @Test func validityAnnouncementsOnlyReportRecovery() {
        #expect(
            IOSCustomLanguageCodeInputState.shouldAnnounceValidityRecovery(
                from: .invalid,
                to: .valid
            )
        )
        #expect(
            !IOSCustomLanguageCodeInputState.shouldAnnounceValidityRecovery(
                from: .empty,
                to: .invalid
            )
        )
        #expect(
            !IOSCustomLanguageCodeInputState.shouldAnnounceValidityRecovery(
                from: .invalid,
                to: .empty
            )
        )
        #expect(
            !IOSCustomLanguageCodeInputState.shouldAnnounceValidityRecovery(
                from: nil,
                to: .valid
            )
        )
        #expect(
            !IOSCustomLanguageCodeInputState.shouldAnnounceValidityRecovery(
                from: .valid,
                to: .invalid
            )
        )
    }

    @Test func semanticMutationsPreserveEveryUnrelatedSetting() {
        let base = settingsFixture()

        let transcription = TranscriptionConfiguration(
            model: "new-transcription",
            language: .french,
            freeformPrompt: "new prompt"
        )
        var transcriptionResult = base
        IOSAppSettingsEditorMutation.applyTranscription(
            transcription,
            to: &transcriptionResult
        )
        var expected = base
        expected.transcriptionConfiguration = transcription
        #expect(transcriptionResult == expected)

        let writing = IOSWritingCorrectionSettingsDraft(
            configuration: TextCorrectionConfiguration(
                isEnabled: false,
                modelPreset: .fast,
                prompt: "new correction"
            ),
            localTextCleanupEnabled: true
        )
        var writingResult = base
        IOSAppSettingsEditorMutation.applyWritingAndCorrection(
            writing,
            to: &writingResult
        )
        expected = base
        expected.textCorrectionConfiguration = writing.configuration
        expected.localTextCleanupEnabled = true
        #expect(writingResult == expected)

        let translation = TranslationConfiguration(
            actionPreferenceEnabled: false,
            targetLanguage: .german
        )
        var translationResult = base
        IOSAppSettingsEditorMutation.applyTranslation(
            translation,
            to: &translationResult
        )
        expected = base
        expected.translationConfiguration = translation
        #expect(translationResult == expected)

        let voice = VoiceSessionPreferences(
            audioCuesEnabled: true,
            recordingStopTailDuration: .seconds2
        )
        let voiceDraft = IOSVoiceRecordingSettingsDraft(
            preferences: voice,
            recordingCachePolicy: .keepLast(25)
        )
        var voiceResult = base
        IOSAppSettingsEditorMutation.applyVoiceAndRecording(
            voiceDraft,
            to: &voiceResult
        )
        expected = base
        expected.voiceSessionPreferences = voice
        expected.recordingCachePolicy = .keepLast(25)
        #expect(voiceResult == expected)
    }

    @Test func presentationNamesCoverEveryPortableChoice() {
        #expect(
            TranscriptionLanguage.allCases.allSatisfy {
                !$0.iosSettingsDisplayName.isEmpty
            }
        )
        #expect(
            !TranscriptionLanguage.iosTranslationCases.contains(.automatic)
        )
        #expect(
            TranscriptionLanguage.iosTranslationCases.contains(.custom)
        )
        #expect(
            TextCorrectionModelPreset.allCases.allSatisfy {
                !$0.iosSettingsDisplayName.isEmpty
                    && !$0.iosSettingsDetail.isEmpty
            }
        )
        #expect(
            RecordingStopTailDuration.allCases.allSatisfy {
                !$0.iosSettingsDisplayName.isEmpty
            }
        )
        #expect(
            IOSRecordingCacheRetentionMode.allCases == [.keepLast, .unlimited]
        )
        #expect(
            RecordingCachePolicy.deleteImmediately.iosSettingsSummary
                == "Cache off"
        )
        #expect(
            RecordingCachePolicy.keepLast(25).iosSettingsSummary
                == "Cache last 25"
        )
        #expect(
            RecordingCachePolicy.unlimited.iosSettingsSummary
                == "Cache unlimited"
        )
        #expect(
            RecordingCachePolicy.deleteImmediately.iosSettingsRetentionMode
                == .keepLast
        )
        #expect(
            RecordingCachePolicy.unlimited.iosSettingsRetentionMode
                == .unlimited
        )
    }

    @Test func recordingCacheEditorUsesExplicitOffLastTwentyAndUnlimitedPolicies() {
        #expect(
            IOSRecordingCachePolicyEditor.policyAfterSettingEnabled(false)
                == .deleteImmediately
        )
        #expect(
            IOSRecordingCachePolicyEditor.policyAfterSettingEnabled(true)
                == .keepLast(20)
        )
        #expect(
            IOSRecordingCachePolicyEditor.policyAfterSelectingRetention(
                .unlimited,
                currentPolicy: .keepLast(25)
            ) == .unlimited
        )
        #expect(
            IOSRecordingCachePolicyEditor.policyAfterSelectingRetention(
                .keepLast,
                currentPolicy: .unlimited
            ) == .keepLast(20)
        )
        #expect(
            IOSRecordingCachePolicyEditor.policyAfterSelectingRetention(
                .keepLast,
                currentPolicy: .keepLast(25)
            ) == .keepLast(25)
        )
    }

    @Test func languageSelectionSearchFindsNamesCodesAndCustom() {
        #expect(
            IOSLanguageSelectionPresentation.matches(
                .automatic,
                automaticTitle: "Auto",
                query: "auto"
            )
        )
        #expect(
            IOSLanguageSelectionPresentation.matches(
                .german,
                automaticTitle: "Auto",
                query: "de"
            )
        )
        #expect(
            IOSLanguageSelectionPresentation.matches(
                .portuguese,
                automaticTitle: "Auto",
                query: "portu"
            )
        )
        #expect(
            IOSLanguageSelectionPresentation.matches(
                .custom,
                automaticTitle: "Auto",
                query: "custom"
            )
        )
        #expect(
            !IOSLanguageSelectionPresentation.matches(
                .japanese,
                automaticTitle: "Auto",
                query: "russian"
            )
        )
    }

    @Test func modelSummariesNeverEchoModelIdentifiers() {
        let sentinel = "PRIVATE-CUSTOM-MODEL-IDENTIFIER"
        let customSummary = IOSSettingsModelPresentation.summary(
            rawModel: sentinel,
            defaultModel: "default"
        )
        let defaultSummary = IOSSettingsModelPresentation.summary(
            rawModel: "default",
            defaultModel: "default"
        )
        let blankSummary = IOSSettingsModelPresentation.summary(
            rawModel: "  ",
            defaultModel: "default"
        )

        #expect(customSummary == "Custom model")
        #expect(defaultSummary == "Default model")
        #expect(blankSummary == "Default model")
        #expect(!customSummary.contains(sentinel))
    }

    @Test func promptResetUsesExactSharedDefaultsWithoutSaving() {
        var correction = TextCorrectionConfiguration(
            isEnabled: false,
            prompt: "custom correction"
        )
        var translation = TranslationConfiguration(
            actionPreferenceEnabled: false,
            prompt: "custom translation"
        )

        correction.resetPrompt()
        translation.resetPrompt()

        #expect(correction.prompt == TextCorrectionConfiguration.defaultPrompt)
        #expect(correction.isPromptDefault)
        #expect(translation.prompt == TranslationConfiguration.defaultPrompt)
        #expect(translation.isPromptDefault)
        #expect(!correction.isEnabled)
        #expect(!translation.actionPreferenceEnabled)
    }

    @Test func standardProviderInstructionsStayHiddenUntilCustomized() {
        let defaultPrompt = "internal standard prompt"

        #expect(
            IOSProviderInstructionsPresentation.displayedValue(
                storedValue: defaultPrompt,
                defaultValue: defaultPrompt
            ).isEmpty
        )
        #expect(
            IOSProviderInstructionsPresentation.displayedValue(
                storedValue: "  ",
                defaultValue: defaultPrompt
            ).isEmpty
        )
        #expect(
            IOSProviderInstructionsPresentation.displayedValue(
                storedValue: "Keep names unchanged",
                defaultValue: defaultPrompt
            ) == "Keep names unchanged"
        )
        #expect(
            IOSProviderInstructionsPresentation.storedValue(
                from: "  ",
                defaultValue: defaultPrompt
            ) == defaultPrompt
        )
        #expect(
            IOSProviderInstructionsPresentation.storedValue(
                from: "Keep names unchanged",
                defaultValue: defaultPrompt
            ) == "Keep names unchanged"
        )
    }

    @Test func privatePromptsStayOutOfDraftAndViewReflection() {
        let sentinel = "PRIVATE-PROMPT-MUST-NOT-BE-REFLECTED"
        let configuration = TranscriptionConfiguration(
            model: sentinel,
            freeformPrompt: sentinel
        )
        let session = IOSSettingsEditorSession(value: configuration)
        let writing = IOSWritingCorrectionSettingsDraft(
            configuration: TextCorrectionConfiguration(prompt: sentinel),
            localTextCleanupEnabled: true
        )
        let view = IOSTranscriptionSettingsView(
            configuration: configuration
        )
        let writingView = IOSWritingCorrectionSettingsView(
            configuration: TextCorrectionConfiguration(
                modelPreset: .custom,
                customModel: sentinel,
                prompt: sentinel
            ),
            localTextCleanupEnabled: true
        )
        let translationView = IOSTranslationSettingsView(
            configuration: TranslationConfiguration(
                model: sentinel,
                prompt: sentinel
            )
        )
        var output = ""

        dump(session, to: &output)
        dump(writing, to: &output)
        dump(view, to: &output)
        dump(writingView, to: &output)
        dump(translationView, to: &output)

        #expect(!output.contains(sentinel))
        #expect(output.contains("redacted"))
    }

    private func settingsFixture() -> IOSAppSettings {
        IOSAppSettings(
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "old-transcription",
                language: .russian,
                freeformPrompt: "old prompt"
            ),
            textCorrectionConfiguration: TextCorrectionConfiguration(
                isEnabled: true,
                modelPreset: .balanced,
                prompt: "old correction"
            ),
            localTextCleanupEnabled: false,
            translationConfiguration: TranslationConfiguration(
                actionPreferenceEnabled: true,
                targetLanguage: .english
            ),
            voiceSessionPreferences: VoiceSessionPreferences(
                audioCuesEnabled: false,
                recordingStopTailDuration: .seconds1
            ),
            recordingCachePolicy: .keepLast(3)
        )
    }
}
