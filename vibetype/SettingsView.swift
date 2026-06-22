//
//  SettingsView.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import SwiftUI

struct SettingsView: View {
    @State private var microphonePermissionStatus: MicrophonePermissionStatus
    @State private var accessibilityPermissionStatus: AccessibilityPermissionStatus
    @State private var appSettings: AppSettings
    @State private var apiKeyInput = ""
    @State private var apiKeyStatus: APIKeySettingsStatus = .unknown
    @State private var hotkeyRegistrationStatus: GlobalHotkeyRegistrationStatus

    private let microphonePermissionService: MicrophonePermissionService
    private let accessibilityPermissionService: AccessibilityPermissionService
    private let apiKeyStorage: APIKeyStorage
    private let appSettingsStore: AppSettingsStore
    private let preferredHotkeyConfiguration: GlobalHotkeyConfiguration
    private let hotkeyStatusProvider: () -> GlobalHotkeyRegistrationStatus

    init(
        microphonePermissionService: MicrophonePermissionService = MicrophonePermissionService(),
        accessibilityPermissionService: AccessibilityPermissionService = AccessibilityPermissionService(),
        apiKeyStorage: APIKeyStorage = KeychainService(),
        appSettingsStore: AppSettingsStore = AppSettingsStore(),
        preferredHotkeyConfiguration: GlobalHotkeyConfiguration = .defaultDictation,
        hotkeyStatusProvider: @escaping () -> GlobalHotkeyRegistrationStatus = { .notRegistered }
    ) {
        self.microphonePermissionService = microphonePermissionService
        self.accessibilityPermissionService = accessibilityPermissionService
        self.apiKeyStorage = apiKeyStorage
        self.appSettingsStore = appSettingsStore
        self.preferredHotkeyConfiguration = preferredHotkeyConfiguration
        self.hotkeyStatusProvider = hotkeyStatusProvider
        _appSettings = State(initialValue: appSettingsStore.load())
        _microphonePermissionStatus = State(
            initialValue: microphonePermissionService.currentStatus()
        )
        _accessibilityPermissionStatus = State(
            initialValue: accessibilityPermissionService.currentStatus()
        )
        _hotkeyRegistrationStatus = State(initialValue: hotkeyStatusProvider())
    }

    var body: some View {
        Form {
            SettingsSetupStatusSection()

            OpenAISettingsSection(
                apiKeyInput: $apiKeyInput,
                apiKeyStatus: apiKeyStatus,
                onSaveAPIKey: saveAPIKey,
                onRemoveAPIKey: removeAPIKey
            )

            TranscriptionSettingsSection(settings: appSettingsBinding)

            KeyboardShortcutSettingsSection(
                status: hotkeyRegistrationStatus,
                preferredConfiguration: preferredHotkeyConfiguration
            )

            BehaviorSettingsSection(settings: appSettingsBinding)

            PrivacyPermissionsSettingsSection(
                microphonePermissionStatus: microphonePermissionStatus,
                accessibilityPermissionStatus: accessibilityPermissionStatus,
                onMicrophonePermissionAction: handleMicrophonePermissionAction,
                onOpenAccessibilitySettings: handleAccessibilityPermissionAction
            )
        }
        .formStyle(.grouped)
        .scenePadding()
        .frame(minWidth: 460, minHeight: 400, alignment: .topLeading)
        .onAppear {
            reloadAppSettings()
            refreshMicrophonePermissionStatus()
            refreshAccessibilityPermissionStatus()
            refreshHotkeyRegistrationStatus()
            refreshAPIKeyStatus()
        }
    }

    private var appSettingsBinding: Binding<AppSettings> {
        Binding(
            get: {
                appSettings
            },
            set: { newValue in
                appSettings = newValue
                appSettingsStore.save(newValue)
            }
        )
    }

    private func reloadAppSettings() {
        appSettings = appSettingsStore.load()
    }

    private func refreshMicrophonePermissionStatus() {
        microphonePermissionStatus = microphonePermissionService.currentStatus()
    }

    private func handleMicrophonePermissionAction() {
        switch microphonePermissionStatus {
        case .allowed, .unavailable:
            refreshMicrophonePermissionStatus()
        case .denied:
            microphonePermissionService.openMicrophoneSettings()
            refreshMicrophonePermissionStatus()
        case .notDetermined:
            microphonePermissionService.requestPermission { newStatus in
                Task { @MainActor in
                    microphonePermissionStatus = newStatus
                }
            }
        }
    }

    private func refreshAccessibilityPermissionStatus() {
        accessibilityPermissionStatus = accessibilityPermissionService.currentStatus()
    }

    private func handleAccessibilityPermissionAction() {
        accessibilityPermissionService.openAccessibilitySettings()
        refreshAccessibilityPermissionStatus()
    }

    private func refreshHotkeyRegistrationStatus() {
        hotkeyRegistrationStatus = hotkeyStatusProvider()
    }

    private func refreshAPIKeyStatus() {
        do {
            apiKeyStatus = try apiKeyStorage.loadAPIKey() == nil ? .missing : .saved
        } catch {
            apiKeyStatus = .failure(error.localizedDescription)
        }
    }

    private func saveAPIKey() {
        do {
            try apiKeyStorage.saveAPIKey(apiKeyInput)
            apiKeyInput = ""
            apiKeyStatus = .saved
        } catch {
            apiKeyStatus = .failure(error.localizedDescription)
        }
    }

    private func removeAPIKey() {
        do {
            try apiKeyStorage.deleteAPIKey()
            apiKeyInput = ""
            apiKeyStatus = .missing
        } catch {
            apiKeyStatus = .failure(error.localizedDescription)
        }
    }
}

#Preview {
    SettingsView(apiKeyStorage: PreviewAPIKeyStorage())
}

private final class PreviewAPIKeyStorage: APIKeyStorage {
    private var apiKey: String?

    func saveAPIKey(_ apiKey: String) throws {
        self.apiKey = apiKey
    }

    func loadAPIKey() throws -> String? {
        apiKey
    }

    func deleteAPIKey() throws {
        apiKey = nil
    }
}
