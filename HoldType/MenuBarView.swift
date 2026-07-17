//
//  MenuBarView.swift
//  HoldType
//
//  Created by Eugene Potapenko on 6/20/26.
//

import AppKit
import HoldTypeDomain
import SwiftUI

struct MenuBarView: View {
    private static let menuWidth: CGFloat = 420

    @Environment(\.dismiss) private var dismiss
    @StateObject private var dictationRuntime: DictationRuntime

    init(
        dictationRuntime: DictationRuntime? = nil
    ) {
        _dictationRuntime = StateObject(wrappedValue: dictationRuntime ?? .shared)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(presentation.appTitle)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            Text(presentation.statusText)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            if presentation.showsFailureRecoveryActions {
                failureRecoverySection(dictationRuntime.failurePresentation)
            }

            Divider()

            MenuBarActionButton(
                title: presentation.recordingActionTitle,
                shortcutHint: presentation.recordingActionShortcutHint,
                isEnabled: presentation.isRecordingActionEnabled
            ) {
                performRecordingAction()
            }

            MenuBarActionButton(
                title: presentation.translationActionTitle,
                shortcutHint: presentation.translationActionShortcutHint,
                isEnabled: presentation.isTranslationActionEnabled
            ) {
                performTranslationRecordingAction()
            }

            MenuBarActionButton(
                title: presentation.pasteLastResultTitle,
                shortcutHint: presentation.pasteLastResultActionShortcutHint,
                isEnabled: presentation.isPasteLastResultEnabled
            ) {
                pasteLastResult()
            }
            .keyboardShortcut("v", modifiers: [.control, .command])

            Divider()

            MenuBarActionButton(title: MenuBarPresentation.historyTitle) {
                dismiss()
                TranscriptHistoryWindowPresenter.shared.showAfterMenuDismissal()
            }

            MenuBarActionButton(title: MenuBarPresentation.settingsTitle) {
                dismiss()
                SettingsWindowPresenter.shared.showAfterMenuDismissal()
            }

            Divider()

            MenuBarActionButton(title: MenuBarPresentation.quitTitle) {
                MenuBarQuitRequest.requestAfterMenuDismissal {
                    dismiss()
                }
            }
        }
        .frame(width: Self.menuWidth)
        .padding(.vertical, 8)
    }

    private var presentation: MenuBarPresentation {
        MenuBarPresentation(
            dictationStatus: dictationRuntime.status,
            failurePresentation: dictationRuntime.failurePresentation,
            outputStatusText: dictationRuntime.outputStatusText,
            recordingCountdown: dictationRuntime.recordingCountdown,
            settings: dictationRuntime.appSettings,
            isLastResultPasteAvailable: dictationRuntime.isLastResultPasteAvailable
        )
    }

    private func performRecordingAction() {
        dismiss()
        Task {
            await dictationRuntime.performRecordingAction()
        }
    }

    private func performTranslationRecordingAction() {
        dismiss()
        Task {
            await dictationRuntime.performRecordingAction(intent: .translate)
        }
    }

    private func pasteLastResult() {
        dismiss()
        Task {
            await dictationRuntime.pasteLastResult()
        }
    }

    @ViewBuilder
    private func failureRecoverySection(_ failurePresentation: DictationFailurePresentation?) -> some View {
        Divider()

        if let failedAttemptID = failurePresentation?.failedAttemptID,
           failurePresentation?.canRetry == true {
            MenuBarActionButton(title: "Try Again") {
                retryFailedTranscription(id: failedAttemptID)
            }
        }

        if let settingsTarget = failurePresentation?.settingsTarget {
            MenuBarActionButton(title: settingsActionTitle(for: settingsTarget)) {
                dismiss()
                SettingsWindowPresenter.shared.showAfterMenuDismissal(focusing: settingsTarget)
            }
        }

        MenuBarActionButton(title: "Dismiss") {
            dismiss()
            dictationRuntime.dismissFailurePresentation()
        }
    }

    private func retryFailedTranscription(id: FailedTranscriptionAttempt.ID) {
        dismiss()
        Task {
            await dictationRuntime.retryFailedTranscription(
                id: id,
                outputMode: .followAutomaticInsertion
            )
        }
    }

    private func settingsActionTitle(for item: SettingsNavigationItem) -> String {
        switch item {
        case .openAI:
            return "Open OpenAI Settings"
        case .transcription:
            return "Open Transcription Settings"
        case .translation:
            return "Open Translation Settings"
        default:
            return "Open Settings"
        }
    }
}

@MainActor
enum MenuBarQuitRequest {
    static let delayAfterMenuDismissal: Duration = .milliseconds(100)

    static func requestAfterMenuDismissal(dismissMenu: () -> Void) {
        requestAfterMenuDismissal(
            dismissMenu: dismissMenu,
            scheduleTermination: scheduleTerminationAfterMenuDismissal,
            terminate: {
                NSApplication.shared.terminate(nil)
            }
        )
    }

    static func requestAfterMenuDismissal(
        dismissMenu: () -> Void,
        scheduleTermination: (@escaping @MainActor () -> Void) -> Void,
        terminate: @escaping @MainActor () -> Void
    ) {
        dismissMenu()
        scheduleTermination(terminate)
    }

    private static func scheduleTerminationAfterMenuDismissal(
        _ terminate: @escaping @MainActor () -> Void
    ) {
        Task { @MainActor in
            try? await Task.sleep(for: delayAfterMenuDismissal)
            terminate()
        }
    }
}

private struct MenuBarActionButton: View {
    let title: String
    var shortcutHint: String?
    var isEnabled = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 24)

                if let shortcutHint {
                    Text(shortcutHint)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(rowBackground)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isHovered && isEnabled {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.opacity(0.16))
                .padding(.horizontal, 8)
        }
    }
}

#Preview {
    MenuBarView()
}
