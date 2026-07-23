//
//  MenuBarPresentation.swift
//  HoldType
//
//  Created by Codex on 6/22/26.
//

import Foundation
import HoldTypeDomain

enum HoldTypeMenuBarIdentity {
    static let title = "HoldType"
    static let iconAssetName = "HoldTypeMenuBarIcon"
    static let helpText = "HoldType Dictation"
}

enum HoldTypeWindowTitle {
    static let history = titled("History")

    static func titled(_ title: String) -> String {
        "\(HoldTypeMenuBarIdentity.title): \(title)"
    }
}

struct MenuBarPresentation: Equatable {
    static let projectTitle = "View Project on GitHub"
    static let projectURLString = "https://github.com/holdtype/holdtype-swift"
    static let translationActionTitle = "Transcribe & Translate"
    static let pasteLastResultTitle = "Paste Last Result"
    static let translationShortcutHint = GlobalHotkeyShortcut.translationDictation.menuHoldText
    static let pasteLastResultShortcutHint = GlobalHotkeyShortcut.appClipboardPaste.menuKeyEquivalentText
    static let fixesTitle = "Fixes…"
    static let fixesShortcutHint = GlobalHotkeyShortcut.fixesPalette.menuKeyEquivalentText
    static let editFixesTitle = "Edit Fixes…"
    static let historyTitle = "Transcript History"
    static let settingsTitle = "Settings\u{2026}"
    static let checkForUpdatesTitle = "Check for Updates..."
    static let quitTitle = "Quit HoldType"

    static func fixesShortcutHint(
        for status: FixesHotkeyRegistrationStatus
    ) -> String {
        if case .unavailable = status {
            return "Shortcut unavailable"
        }
        return fixesShortcutHint
    }

    let appTitle: String
    let statusText: String
    let recordingActionTitle: String
    let recordingActionShortcutHint: String?
    let isRecordingActionEnabled: Bool
    let translationActionTitle: String
    let translationActionShortcutHint: String
    let isTranslationActionEnabled: Bool
    let pasteLastResultTitle: String
    let pasteLastResultActionShortcutHint: String
    let isPasteLastResultEnabled: Bool
    let showsFailureRecoveryActions: Bool

    init(
        dictationStatus: DictationStatus,
        failurePresentation: DictationFailurePresentation? = nil,
        outputStatusText: String? = nil,
        recordingCountdown: VoiceSessionCountdown? = nil,
        settings: AppSettings = .defaults,
        isLastResultPasteAvailable: Bool = false
    ) {
        appTitle = HoldTypeMenuBarIdentity.title
        statusText = Self.statusText(
            for: dictationStatus,
            failurePresentation: failurePresentation,
            outputStatusText: outputStatusText,
            recordingCountdown: recordingCountdown
        )
        recordingActionTitle = dictationStatus.recordingActionTitle
        recordingActionShortcutHint = dictationStatus.recordingActionShortcutHint
        isRecordingActionEnabled = dictationStatus.isRecordingActionEnabled
        translationActionTitle = Self.translationActionTitle
        translationActionShortcutHint = Self.translationShortcutHint
        isTranslationActionEnabled = Self.canStartNewRecording(from: dictationStatus)
            && settings.translationShortcutEnabled
        pasteLastResultTitle = Self.pasteLastResultTitle
        pasteLastResultActionShortcutHint = Self.pasteLastResultShortcutHint
        isPasteLastResultEnabled = settings.saveTranscriptsToAppClipboard
            && isLastResultPasteAvailable
        showsFailureRecoveryActions = Self.isFailure(dictationStatus)
            || failurePresentation != nil
    }

    private static func statusText(
        for dictationStatus: DictationStatus,
        failurePresentation: DictationFailurePresentation?,
        outputStatusText: String?,
        recordingCountdown: VoiceSessionCountdown?
    ) -> String {
        if dictationStatus.voiceWorkPhase == .listening,
           let recordingCountdown {
            return "Recording — \(recordingCountdown.remainingWholeSeconds)s remaining"
        }

        if case .failure = dictationStatus,
           let failurePresentation {
            return DictationStatus.compactFailureStatusText(
                for: failurePresentation.title
            )
        }

        let trimmedOutputStatusText = outputStatusText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedOutputStatusText,
           !trimmedOutputStatusText.isEmpty {
            return trimmedOutputStatusText
        }

        return dictationStatus.menuStatusText
    }

    private static func isFailure(_ dictationStatus: DictationStatus) -> Bool {
        if case .failure = dictationStatus {
            return true
        }

        return false
    }

    private static func canStartNewRecording(from dictationStatus: DictationStatus) -> Bool {
        dictationStatus.voiceWorkPhase == .inactive
    }
}
