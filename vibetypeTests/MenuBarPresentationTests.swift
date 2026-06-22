//
//  MenuBarPresentationTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/22/26.
//

import Testing
@testable import vibetype

struct MenuBarPresentationTests {

    @Test func idleAllowedMenuExposesMVPItems() {
        let presentation = MenuBarPresentation(
            dictationStatus: .idle,
            microphonePermissionStatus: .allowed,
            accessibilityPermissionStatus: .trusted
        )

        #expect(presentation.appTitle == "VibeType")
        #expect(VibeTypeMenuBarIdentity.systemImage == "mic.fill")
        #expect(VibeTypeMenuBarIdentity.helpText == "VibeType Dictation")
        #expect(presentation.statusText == "Ready")
        #expect(presentation.microphoneStatusText == "Microphone: Allowed")
        #expect(presentation.microphoneDetailText == nil)
        #expect(presentation.microphoneSettingsActionTitle == nil)
        #expect(presentation.accessibilityStatusText == "Accessibility: Allowed")
        #expect(presentation.accessibilityDetailText == nil)
        #expect(presentation.accessibilitySettingsActionTitle == nil)
        #expect(presentation.recordingActionTitle == "Start Recording")
        #expect(presentation.isRecordingActionEnabled)
        #expect(presentation.dictationDetailText == "Recording is not implemented in this build.")
        #expect(presentation.lastTranscriptText == "No transcript yet.")
        #expect(presentation.canCopyLastTranscript == false)
        #expect(MenuBarPresentation.lastTranscriptTitle == "Last Transcript")
        #expect(MenuBarPresentation.copyLastTranscriptTitle == "Copy Last Transcript")
        #expect(MenuBarPresentation.settingsTitle == "Settings")
        #expect(MenuBarPresentation.quitTitle == "Quit VibeType")
    }

    @Test func recordingStateSwitchesPrimaryActionToStop() {
        let presentation = MenuBarPresentation(
            dictationStatus: .recording,
            microphonePermissionStatus: .allowed,
            accessibilityPermissionStatus: .trusted
        )

        #expect(presentation.statusText == "Recording...")
        #expect(presentation.recordingActionTitle == "Stop Recording")
        #expect(presentation.isRecordingActionEnabled)
        #expect(
            presentation.dictationDetailText
                == "Recording placeholder active. Microphone input is not captured in this build."
        )
    }

    @Test func transcribingStateDisablesRecordingAction() {
        let presentation = MenuBarPresentation(
            dictationStatus: .transcribing,
            microphonePermissionStatus: .allowed,
            accessibilityPermissionStatus: .trusted
        )

        #expect(presentation.statusText == "Transcribing...")
        #expect(presentation.recordingActionTitle == "Start Recording")
        #expect(presentation.isRecordingActionEnabled == false)
        #expect(presentation.dictationDetailText == "Transcribing audio...")
    }

    @Test func microphonePermissionNeededChangesPrimaryAction() {
        let presentation = MenuBarPresentation(
            dictationStatus: .idle,
            microphonePermissionStatus: .notDetermined,
            accessibilityPermissionStatus: .trusted
        )

        #expect(presentation.microphoneStatusText == "Microphone: Permission Needed")
        #expect(presentation.microphoneDetailText?.contains("Allow microphone access") == true)
        #expect(presentation.microphoneSettingsActionTitle == nil)
        #expect(presentation.recordingActionTitle == "Request Microphone Access")
        #expect(presentation.isRecordingActionEnabled)
    }

    @Test func microphoneDeniedBlocksRecordingAndExposesRecoveryAction() {
        let presentation = MenuBarPresentation(
            dictationStatus: .idle,
            microphonePermissionStatus: .denied,
            accessibilityPermissionStatus: .trusted
        )

        #expect(presentation.microphoneStatusText == "Microphone: Not Allowed")
        #expect(presentation.microphoneDetailText?.contains("Recording is blocked") == true)
        #expect(presentation.microphoneSettingsActionTitle == "Open Microphone Settings")
        #expect(presentation.recordingActionTitle == "Start Recording")
        #expect(presentation.isRecordingActionEnabled == false)
    }

    @Test func accessibilityNotTrustedExplainsCopyFallback() {
        let presentation = MenuBarPresentation(
            dictationStatus: .idle,
            microphonePermissionStatus: .allowed,
            accessibilityPermissionStatus: .notTrusted
        )

        #expect(presentation.accessibilityStatusText == "Accessibility: Not Allowed")
        #expect(presentation.accessibilityDetailText?.contains("Auto-paste is unavailable") == true)
        #expect(presentation.accessibilityDetailText?.contains("copied") == true)
        #expect(presentation.accessibilitySettingsActionTitle == "Open Accessibility Settings")
    }

    @Test func successTranscriptNormalizesLastTranscriptAndEnablesCopy() {
        let presentation = MenuBarPresentation(
            dictationStatus: .success(transcript: "  Typed text\n"),
            microphonePermissionStatus: .allowed,
            accessibilityPermissionStatus: .notTrusted,
            clipboardStatusText: "Last transcript copied."
        )

        #expect(presentation.statusText == "Done")
        #expect(presentation.lastTranscriptText == "Typed text")
        #expect(presentation.canCopyLastTranscript)
        #expect(presentation.dictationDetailText == "Typed text")
        #expect(presentation.clipboardStatusText == "Last transcript copied.")
    }

    @Test func longTranscriptUsesCompactMenuText() {
        let transcript = String(repeating: "a", count: 160)
        let presentation = MenuBarPresentation(
            dictationStatus: .success(transcript: transcript),
            microphonePermissionStatus: .allowed,
            accessibilityPermissionStatus: .trusted
        )

        #expect(presentation.lastTranscriptText == "\(String(repeating: "a", count: 140))...")
        #expect(presentation.canCopyLastTranscript)
    }
}
