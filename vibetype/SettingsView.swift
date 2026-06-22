//
//  SettingsView.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import SwiftUI

struct SettingsView: View {
    @State private var selectedItem: SettingsNavigationItem? = .general
    @State private var microphonePermissionStatus: MicrophonePermissionStatus
    @State private var accessibilityPermissionStatus: AccessibilityPermissionStatus
    @State private var inputMonitoringPermissionStatus: InputMonitoringPermissionStatus
    @State private var appSettings: AppSettings
    @State private var apiKeyInput = ""
    @State private var apiKeyStatus: APIKeySettingsStatus = .unknown
    @State private var hotkeyRegistrationStatus: GlobalHotkeyRegistrationStatus

    private let microphonePermissionService: MicrophonePermissionService
    private let accessibilityPermissionService: AccessibilityPermissionService
    private let inputMonitoringPermissionService: InputMonitoringPermissionService
    private let apiKeyStorage: APIKeyStorage
    private let appSettingsStore: AppSettingsStore
    private let preferredHotkeyConfiguration: GlobalHotkeyConfiguration
    private let hotkeyStatusProvider: () -> GlobalHotkeyRegistrationStatus

    init(
        microphonePermissionService: MicrophonePermissionService = MicrophonePermissionService(),
        accessibilityPermissionService: AccessibilityPermissionService = AccessibilityPermissionService(),
        inputMonitoringPermissionService: InputMonitoringPermissionService = InputMonitoringPermissionService(),
        apiKeyStorage: APIKeyStorage = KeychainService(),
        appSettingsStore: AppSettingsStore = AppSettingsStore(),
        preferredHotkeyConfiguration: GlobalHotkeyConfiguration = .defaultDictation,
        hotkeyStatusProvider: @escaping () -> GlobalHotkeyRegistrationStatus = { .notRegistered }
    ) {
        self.microphonePermissionService = microphonePermissionService
        self.accessibilityPermissionService = accessibilityPermissionService
        self.inputMonitoringPermissionService = inputMonitoringPermissionService
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
        _inputMonitoringPermissionStatus = State(
            initialValue: inputMonitoringPermissionService.currentStatus()
        )
        _hotkeyRegistrationStatus = State(initialValue: hotkeyStatusProvider())
    }

    var body: some View {
        NavigationSplitView {
            SettingsSidebarView(selection: $selectedItem)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            SettingsDetailView(
                item: selectedItem ?? .general,
                apiKeyInput: $apiKeyInput,
                apiKeyStatus: apiKeyStatus,
                settings: appSettingsBinding,
                hotkeyRegistrationStatus: hotkeyRegistrationStatus,
                preferredHotkeyConfiguration: preferredHotkeyConfiguration,
                microphonePermissionStatus: microphonePermissionStatus,
                accessibilityPermissionStatus: accessibilityPermissionStatus,
                inputMonitoringPermissionStatus: inputMonitoringPermissionStatus,
                onSaveAPIKey: saveAPIKey,
                onRemoveAPIKey: removeAPIKey,
                onMicrophonePermissionAction: handleMicrophonePermissionAction,
                onOpenAccessibilitySettings: handleAccessibilityPermissionAction,
                onInputMonitoringPermissionAction: handleInputMonitoringPermissionAction
            )
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            selectedItem = selectedItem ?? .general
            reloadAppSettings()
            refreshMicrophonePermissionStatus()
            refreshAccessibilityPermissionStatus()
            refreshInputMonitoringPermissionStatus()
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

    private func refreshInputMonitoringPermissionStatus() {
        inputMonitoringPermissionStatus = inputMonitoringPermissionService.currentStatus()
    }

    private func handleInputMonitoringPermissionAction() {
        switch inputMonitoringPermissionStatus {
        case .allowed:
            refreshInputMonitoringPermissionStatus()
        case .denied:
            inputMonitoringPermissionService.openInputMonitoringSettings()
            refreshInputMonitoringPermissionStatus()
        case .notDetermined:
            inputMonitoringPermissionStatus = inputMonitoringPermissionService.requestPermission()
        }
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
