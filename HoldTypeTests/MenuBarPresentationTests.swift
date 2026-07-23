//
//  MenuBarPresentationTests.swift
//  HoldTypeTests
//
//  Created by Codex on 6/22/26.
//

import Foundation
import HoldTypeDomain
import Testing
@testable import HoldType

struct MenuBarPresentationTests {

    @Test func idleMenuExposesMVPItems() {
        let presentation = MenuBarPresentation(
            dictationStatus: .idle,
            isLastResultPasteAvailable: true
        )

        #expect(presentation.appTitle == "HoldType")
        #expect(HoldTypeMenuBarIdentity.iconAssetName == "HoldTypeMenuBarIcon")
        #expect(HoldTypeMenuBarIdentity.helpText == "HoldType Dictation")
        #expect(presentation.statusText == "Ready")
        #expect(presentation.recordingActionTitle == "Transcribe")
        #expect(presentation.recordingActionShortcutHint == "Hold Right ⌘")
        #expect(presentation.isRecordingActionEnabled)
        #expect(presentation.translationActionTitle == "Transcribe & Translate")
        #expect(presentation.translationActionShortcutHint == "Hold Right ⌘ + Right ⌥")
        #expect(presentation.isTranslationActionEnabled)
        #expect(MenuBarPresentation.translationShortcutHint == "Hold Right ⌘ + Right ⌥")
        #expect(presentation.pasteLastResultTitle == "Paste Last Result")
        #expect(presentation.pasteLastResultActionShortcutHint == "⌃⌘V")
        #expect(presentation.isPasteLastResultEnabled)
        #expect(MenuBarPresentation.pasteLastResultShortcutHint == "⌃⌘V")
        #expect(MenuBarPresentation.fixesTitle == "Fixes…")
        #expect(MenuBarPresentation.fixesShortcutHint == "⌥J")
        #expect(
            MenuBarPresentation.fixesShortcutHint(
                for: .unavailable(message: "Already in use")
            ) == "Shortcut unavailable"
        )
        #expect(MenuBarPresentation.editFixesTitle == "Edit Fixes…")
        #expect(MenuBarPresentation.historyTitle == "Transcript History")
        #expect(HoldTypeWindowTitle.history == "HoldType: History")
        #expect(MenuBarPresentation.settingsTitle == "Settings…")
        #expect(MenuBarPresentation.quitTitle == "Quit HoldType")
        #expect(presentation.showsFailureRecoveryActions == false)
    }

    @Test func recordingStateSwitchesPrimaryActionToStop() {
        let presentation = MenuBarPresentation(
            dictationStatus: .recording
        )

        #expect(presentation.statusText == "Recording…")
        #expect(presentation.recordingActionTitle == "Stop Recording")
        #expect(presentation.recordingActionShortcutHint == nil)
        #expect(presentation.isRecordingActionEnabled)
        #expect(presentation.isTranslationActionEnabled == false)
    }

    @Test func recordingCountdownRemainsVisibleInMenuStatus() {
        let presentation = MenuBarPresentation(
            dictationStatus: .recording,
            recordingCountdown: VoiceSessionCountdown(
                remainingWholeSeconds: 10,
                urgency: .red
            )
        )

        #expect(presentation.statusText == "Recording — 10s remaining")
    }

    @Test func transcribingStateDisablesRecordingAction() {
        let presentation = MenuBarPresentation(
            dictationStatus: .transcribing
        )

        #expect(presentation.statusText == "Transcribing…")
        #expect(presentation.recordingActionTitle == "Transcribe")
        #expect(presentation.isRecordingActionEnabled == false)
        #expect(presentation.isTranslationActionEnabled == false)
    }

    @Test func durableRecordingNoticeOverridesGenericProcessingStatus() {
        let presentation = MenuBarPresentation(
            dictationStatus: .transcribing,
            outputStatusText: "Recording interrupted — saved to History."
        )

        #expect(
            presentation.statusText
                == "Recording interrupted — saved to History."
        )
    }

    @Test func failureTitleOverridesPriorOutputNotice() {
        let presentation = MenuBarPresentation(
            dictationStatus: .failure(message: "Could not finish recording."),
            failurePresentation: DictationFailurePresentation(
                title: "Recording saved",
                message: "Open History to recover the recording."
            ),
            outputStatusText: "Recording interrupted — saved to History."
        )

        #expect(presentation.statusText == "Error: Recording saved")
    }

    @Test func translationActionFollowsShortcutToggleRatherThanCompletedLanguageConfiguration() {
        var settings = AppSettings.defaults
        settings.translationShortcutEnabled = true

        let missingTargetPresentation = MenuBarPresentation(
            dictationStatus: .idle,
            settings: settings
        )

        #expect(settings.canRunTranslation == false)
        #expect(missingTargetPresentation.isTranslationActionEnabled)

        settings.translationShortcutEnabled = false
        let disabledShortcutPresentation = MenuBarPresentation(
            dictationStatus: .idle,
            settings: settings
        )

        #expect(disabledShortcutPresentation.isTranslationActionEnabled == false)
    }

    @Test func pasteLastResultFollowsSettingAndAvailability() {
        var settings = AppSettings.defaults
        settings.saveTranscriptsToAppClipboard = false

        let presentation = MenuBarPresentation(
            dictationStatus: .idle,
            settings: settings,
            isLastResultPasteAvailable: true
        )

        #expect(presentation.isPasteLastResultEnabled == false)
    }

    @Test func successTranscriptDoesNotCreateMenuDetailRows() {
        let presentation = MenuBarPresentation(
            dictationStatus: .success(transcript: "Typed text")
        )

        #expect(presentation.statusText == "Ready")
        #expect(presentation.recordingActionTitle == "Transcribe")
    }

    @Test func failureStateShowsErrorStatusWithoutDetailRows() {
        let presentation = MenuBarPresentation(
            dictationStatus: .failure(message: "Recording was too short. Try speaking for a little longer.")
        )

        #expect(presentation.statusText == "Error: Recording too short")
        #expect(presentation.showsFailureRecoveryActions)
    }

    @Test func failurePresentationTitleDrivesCompactStatus() {
        let presentation = MenuBarPresentation(
            dictationStatus: .failure(message: "The network is unavailable. Try again when you are connected."),
            failurePresentation: DictationFailurePresentation(
                title: "Network unavailable",
                message: "The network is unavailable. You can retry when connected.",
                failedAttemptID: UUID(),
                canRetry: true
            )
        )

        #expect(presentation.statusText == "Error: Network unavailable")
        #expect(presentation.showsFailureRecoveryActions)
    }
}
