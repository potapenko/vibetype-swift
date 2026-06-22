//
//  MenuBarView.swift
//  vibetype
//
//  Created by Eugene Potapenko on 6/20/26.
//

import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    @State private var dictationStatus = DictationStatus.idle
    @State private var appSettings: AppSettings
    @State private var clipboardStatusText: String?
    @State private var microphonePermissionStatus: MicrophonePermissionStatus
    @State private var accessibilityPermissionStatus: AccessibilityPermissionStatus
    @State private var floatingIndicatorPanel = FloatingIndicatorPanelController()

    private let transcriptClipboardStore: any TranscriptClipboardStoring
    private let microphonePermissionService: MicrophonePermissionService
    private let accessibilityPermissionService: AccessibilityPermissionService
    private let appSettingsStore: AppSettingsStore
    private let cuePlayer: any DictationCuePlaying

    init(
        transcriptClipboardStore: any TranscriptClipboardStoring = AppTranscriptClipboardStore.shared,
        microphonePermissionService: MicrophonePermissionService = MicrophonePermissionService(),
        accessibilityPermissionService: AccessibilityPermissionService = AccessibilityPermissionService(),
        appSettingsStore: AppSettingsStore = AppSettingsStore(),
        cuePlayer: any DictationCuePlaying = NativeDictationCuePlayer.shared
    ) {
        self.transcriptClipboardStore = transcriptClipboardStore
        self.microphonePermissionService = microphonePermissionService
        self.accessibilityPermissionService = accessibilityPermissionService
        self.appSettingsStore = appSettingsStore
        self.cuePlayer = cuePlayer
        _appSettings = State(initialValue: appSettingsStore.load())
        _microphonePermissionStatus = State(
            initialValue: microphonePermissionService.currentStatus()
        )
        _accessibilityPermissionStatus = State(
            initialValue: accessibilityPermissionService.currentStatus()
        )
    }

    var body: some View {
        Group {
            Text(presentation.appTitle)
                .font(.headline)

            Text(presentation.statusText)
                .foregroundStyle(.secondary)

            Text(presentation.microphoneStatusText)
                .foregroundStyle(.secondary)

            if let microphoneDetailText = presentation.microphoneDetailText {
                Text(microphoneDetailText)
                    .foregroundStyle(.secondary)
            }

            if let microphoneSettingsActionTitle = presentation.microphoneSettingsActionTitle {
                Button(microphoneSettingsActionTitle) {
                    microphonePermissionService.openMicrophoneSettings()
                    refreshMicrophonePermissionStatus()
                }
            }

            Text(presentation.accessibilityStatusText)
                .foregroundStyle(.secondary)

            if let accessibilityDetailText = presentation.accessibilityDetailText {
                Text(accessibilityDetailText)
                    .foregroundStyle(.secondary)
            }

            if let accessibilitySettingsActionTitle = presentation.accessibilitySettingsActionTitle {
                Button(accessibilitySettingsActionTitle) {
                    accessibilityPermissionService.openAccessibilitySettings()
                    refreshAccessibilityPermissionStatus()
                }
            }

            Divider()

            Button(presentation.recordingActionTitle) {
                performRecordingAction()
            }
            .disabled(!presentation.isRecordingActionEnabled)

            if let detailText = presentation.dictationDetailText {
                Text(detailText)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text(MenuBarPresentation.lastTranscriptTitle)
                .font(.subheadline)

            Text(presentation.lastTranscriptText)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Button(MenuBarPresentation.saveLastTranscriptTitle) {
                saveLastTranscriptToAppClipboard()
            }
            .disabled(!presentation.canSaveLastTranscript)

            if let clipboardStatusText = presentation.clipboardStatusText {
                Text(clipboardStatusText)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button(MenuBarPresentation.settingsTitle) {
                openWindow(id: VibeTypeWindow.settings)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",")

            Divider()

            Button(MenuBarPresentation.quitTitle) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .onAppear {
            reloadAppSettings()
            refreshMicrophonePermissionStatus()
            refreshAccessibilityPermissionStatus()
            updateFloatingIndicator()
        }
        .onChange(of: dictationStatus) { _ in
            updateFloatingIndicator()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appSettingsDidChange)) { _ in
            reloadAppSettings()
            updateFloatingIndicator()
        }
    }

    private func saveLastTranscriptToAppClipboard() {
        guard appSettings.saveTranscriptsToAppClipboard else {
            clipboardStatusText = TextInsertionSkipReason.appClipboardDisabled.statusText
            return
        }

        guard let transcript = dictationStatus.lastTranscriptText else {
            clipboardStatusText = TextInsertionServiceError.emptyAppClipboardText.localizedDescription
            return
        }

        Task {
            do {
                try await transcriptClipboardStore.save(transcript)
                await MainActor.run {
                    clipboardStatusText = "Saved to VibeType Clipboard."
                }
            } catch {
                await MainActor.run {
                    clipboardStatusText = error.localizedDescription
                }
            }
        }
    }

    private var presentation: MenuBarPresentation {
        MenuBarPresentation(
            dictationStatus: dictationStatus,
            microphonePermissionStatus: microphonePermissionStatus,
            accessibilityPermissionStatus: accessibilityPermissionStatus,
            appClipboardEnabled: appSettings.saveTranscriptsToAppClipboard,
            clipboardStatusText: clipboardStatusText
        )
    }

    private func performRecordingAction() {
        switch microphonePermissionStatus {
        case .allowed:
            let previousStatus = dictationStatus
            let newStatus = dictationStatus.placeholderRecordingActionResult
            dictationStatus = newStatus
            playRecordingCue(from: previousStatus, to: newStatus)
        case .notDetermined:
            requestMicrophonePermission()
        case .denied, .unavailable:
            if let microphoneDetailText = microphonePermissionStatus.menuDetailText {
                dictationStatus = .failure(message: microphoneDetailText)
            }
        }
    }

    private func playRecordingCue(from previousStatus: DictationStatus, to newStatus: DictationStatus) {
        guard appSettings.soundEnabled else {
            return
        }

        if previousStatus != .recording, newStatus == .recording {
            cuePlayer.play(.startRecording)
        } else if previousStatus == .recording, newStatus != .recording {
            cuePlayer.play(.stopRecording)
        }
    }

    private func requestMicrophonePermission() {
        microphonePermissionService.requestPermission { newStatus in
            DispatchQueue.main.async {
                microphonePermissionStatus = newStatus

                if newStatus.canRecord {
                    dictationStatus = .idle
                } else if let microphoneDetailText = newStatus.menuDetailText {
                    dictationStatus = .failure(message: microphoneDetailText)
                }
            }
        }
    }

    private func refreshMicrophonePermissionStatus() {
        microphonePermissionStatus = microphonePermissionService.currentStatus()
    }

    private func refreshAccessibilityPermissionStatus() {
        accessibilityPermissionStatus = accessibilityPermissionService.currentStatus()
    }

    private func reloadAppSettings() {
        appSettings = appSettingsStore.load()
    }

    @MainActor
    private func updateFloatingIndicator() {
        floatingIndicatorPanel.update(
            with: FloatingIndicatorPresentation.presentation(
                for: dictationStatus,
                settings: appSettings
            )
        )
    }
}

#Preview {
    MenuBarView()
}
