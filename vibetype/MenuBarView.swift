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
    @State private var lastClipboardSnapshot: ClipboardSnapshot?
    @State private var clipboardStatusText: String?
    @State private var microphonePermissionStatus: MicrophonePermissionStatus
    @State private var accessibilityPermissionStatus: AccessibilityPermissionStatus
    @State private var floatingIndicatorPanel = FloatingIndicatorPanelController()

    private let clipboardService: ClipboardService
    private let microphonePermissionService: MicrophonePermissionService
    private let accessibilityPermissionService: AccessibilityPermissionService
    private let appSettingsStore: AppSettingsStore

    init(
        clipboardService: ClipboardService = ClipboardService(),
        microphonePermissionService: MicrophonePermissionService = MicrophonePermissionService(),
        accessibilityPermissionService: AccessibilityPermissionService = AccessibilityPermissionService(),
        appSettingsStore: AppSettingsStore = AppSettingsStore()
    ) {
        self.clipboardService = clipboardService
        self.microphonePermissionService = microphonePermissionService
        self.accessibilityPermissionService = accessibilityPermissionService
        self.appSettingsStore = appSettingsStore
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
            Text("VibeType")
                .font(.headline)

            Text(dictationStatus.menuStatusText)
                .foregroundStyle(.secondary)

            Text(microphonePermissionStatus.menuStatusText)
                .foregroundStyle(.secondary)

            if let microphoneDetailText = microphonePermissionStatus.menuDetailText {
                Text(microphoneDetailText)
                    .foregroundStyle(.secondary)
            }

            if microphonePermissionStatus == .denied {
                Button("Open Microphone Settings") {
                    microphonePermissionService.openMicrophoneSettings()
                    refreshMicrophonePermissionStatus()
                }
            }

            Text(accessibilityPermissionStatus.menuStatusText)
                .foregroundStyle(.secondary)

            if let accessibilityDetailText = accessibilityPermissionStatus.menuDetailText {
                Text(accessibilityDetailText)
                    .foregroundStyle(.secondary)
            }

            if !accessibilityPermissionStatus.canPasteIntoActiveApp {
                Button("Open Accessibility Settings") {
                    accessibilityPermissionService.openAccessibilitySettings()
                    refreshAccessibilityPermissionStatus()
                }
            }

            Divider()

            Button(recordingActionTitle) {
                performRecordingAction()
            }
            .disabled(!isRecordingActionEnabled)

            if let detailText = dictationStatus.detailText {
                Text(detailText)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Last Transcript")
                .font(.subheadline)

            Text(dictationStatus.lastTranscriptMenuText)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Button("Copy Last Transcript") {
                copyLastTranscript()
            }
            .disabled(!dictationStatus.canCopyLastTranscript)

            if let clipboardStatusText {
                Text(clipboardStatusText)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Settings") {
                openWindow(id: VibeTypeWindow.settings)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit VibeType") {
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
    }

    private func copyLastTranscript() {
        guard let transcript = dictationStatus.lastTranscriptText else {
            clipboardStatusText = ClipboardServiceError.emptyText.localizedDescription
            return
        }

        do {
            lastClipboardSnapshot = try clipboardService.copyPlainText(transcript)
            clipboardStatusText = "Last transcript copied."
        } catch {
            clipboardStatusText = error.localizedDescription
        }
    }

    private var recordingActionTitle: String {
        switch microphonePermissionStatus {
        case .notDetermined:
            return "Request Microphone Access"
        case .allowed, .denied, .unavailable:
            return dictationStatus.recordingActionTitle
        }
    }

    private var isRecordingActionEnabled: Bool {
        dictationStatus.isRecordingActionEnabled && microphonePermissionStatus.canUseRecordingAction
    }

    private func performRecordingAction() {
        switch microphonePermissionStatus {
        case .allowed:
            dictationStatus = dictationStatus.placeholderRecordingActionResult
        case .notDetermined:
            requestMicrophonePermission()
        case .denied, .unavailable:
            if let microphoneDetailText = microphonePermissionStatus.menuDetailText {
                dictationStatus = .failure(message: microphoneDetailText)
            }
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
