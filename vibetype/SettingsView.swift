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
            Section {
                VibeTypeSetupStatusView(surface: .macOSSettings, showsDetailSections: false)
            }

            Section("OpenAI") {
                SecureField("OpenAI API key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .privacySensitive()

                Label(apiKeyStatus.message, systemImage: apiKeyStatus.systemImage)
                    .foregroundStyle(apiKeyStatus.tintColor)

                HStack {
                    Button("Save API Key", action: saveAPIKey)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Remove Saved Key", role: .destructive, action: removeAPIKey)
                        .disabled(!apiKeyStatus.hasSavedKey)
                }
            }

            Section("Transcription") {
                TextField("Model", text: settingBinding(\.transcriptionModel))
                    .textFieldStyle(.roundedBorder)

                if isUsingDefaultTranscriptionModelFallback {
                    Label(
                        "Empty model uses \(AppSettings.defaultTranscriptionModel).",
                        systemImage: "info.circle"
                    )
                    .foregroundStyle(.secondary)
                }

                Picker("Language", selection: languageBinding) {
                    ForEach(TranscriptionLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                if appSettings.language == .custom {
                    TextField("Custom language code", text: settingBinding(\.customLanguageCode))
                        .textFieldStyle(.roundedBorder)

                    Label(
                        customLanguageCodeStatusMessage,
                        systemImage: customLanguageCodeStatusImage
                    )
                    .foregroundStyle(customLanguageCodeStatusTint)
                }

                TextField("Prompt or vocabulary hint", text: settingBinding(\.prompt), axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Keyboard Shortcut") {
                HotkeySettingsRow(presentation: hotkeyPresentation)
            }

            Section("Behavior") {
                Toggle(
                    "Paste transcript into active app",
                    isOn: settingBinding(\.autoPaste)
                )

                Toggle(
                    "Copy transcript to clipboard",
                    isOn: settingBinding(\.copyToClipboard)
                )

                Toggle(
                    "Restore previous clipboard after paste",
                    isOn: settingBinding(\.restoreClipboard)
                )

                Toggle(
                    "Play sound on start and stop",
                    isOn: settingBinding(\.soundEnabled)
                )

                Toggle(
                    "Show floating recording indicator",
                    isOn: settingBinding(\.showFloatingIndicator)
                )
            }

            Section("Privacy And Permissions") {
                PermissionStatusRow(
                    title: microphonePermissionStatus.settingsStatusText,
                    description: microphonePermissionStatus.settingsDescription,
                    systemImage: microphonePermissionStatus.settingsSystemImage
                )

                if let microphoneActionTitle = microphonePermissionStatus.settingsActionTitle {
                    Button(microphoneActionTitle, action: handleMicrophonePermissionAction)
                }

                PermissionStatusRow(
                    title: accessibilityPermissionStatus.settingsStatusText,
                    description: accessibilityPermissionStatus.settingsDescription,
                    systemImage: accessibilityPermissionStatus.settingsSystemImage
                )

                if !accessibilityPermissionStatus.canPasteIntoActiveApp {
                    Button("Open Accessibility Settings") {
                        accessibilityPermissionService.openAccessibilitySettings()
                        refreshAccessibilityPermissionStatus()
                    }
                }

                Label(
                    "Audio is sent to OpenAI for transcription. VibeType does not retain raw audio by default.",
                    systemImage: "lock.shield"
                )
                .foregroundStyle(.secondary)
            }
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

    private func settingBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: {
                appSettings[keyPath: keyPath]
            },
            set: { newValue in
                appSettings[keyPath: keyPath] = newValue
                appSettingsStore.save(appSettings)
            }
        )
    }

    private func settingBinding(_ keyPath: WritableKeyPath<AppSettings, String>) -> Binding<String> {
        Binding(
            get: {
                appSettings[keyPath: keyPath]
            },
            set: { newValue in
                appSettings[keyPath: keyPath] = newValue
                appSettingsStore.save(appSettings)
            }
        )
    }

    private var languageBinding: Binding<TranscriptionLanguage> {
        Binding(
            get: {
                appSettings.language
            },
            set: { newValue in
                appSettings.language = newValue
                appSettingsStore.save(appSettings)
            }
        )
    }

    private var isUsingDefaultTranscriptionModelFallback: Bool {
        appSettings.transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var customLanguageCodeStatusMessage: String {
        switch appSettings.customLanguageCodeValidation {
        case .notRequired:
            return ""
        case .emptyFallsBackToAutomatic:
            return "Empty custom language uses Auto."
        case .valid(let normalizedCode):
            return "Language code: \(normalizedCode)"
        case .invalid:
            return "Use a two- or three-letter code, such as en or ru."
        }
    }

    private var customLanguageCodeStatusImage: String {
        appSettings.customLanguageCodeValidation.isInvalid ? "exclamationmark.triangle" : "info.circle"
    }

    private var customLanguageCodeStatusTint: Color {
        appSettings.customLanguageCodeValidation.isInvalid ? .red : .secondary
    }

    private var hotkeyPresentation: HotkeySettingsPresentation {
        HotkeySettingsPresentation(
            status: hotkeyRegistrationStatus,
            preferredConfiguration: preferredHotkeyConfiguration
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

private struct HotkeySettingsRow: View {
    let presentation: HotkeySettingsPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(presentation.shortcutText, systemImage: presentation.systemImage)

            Text(presentation.statusText)
                .font(.footnote)
                .foregroundStyle(presentation.statusTint)

            Text(presentation.detailText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HotkeySettingsPresentation {
    let shortcutText: String
    let statusText: String
    let detailText: String
    let systemImage: String
    let statusTint: Color

    init(
        status: GlobalHotkeyRegistrationStatus,
        preferredConfiguration: GlobalHotkeyConfiguration
    ) {
        switch status {
        case .registered(let configuration):
            shortcutText = configuration.displayText
            statusText = "Global hotkey active."
            detailText = Self.activeDetailText(for: configuration)
            systemImage = "keyboard"
            statusTint = .secondary
        case .fallbackRegistered(let configuration):
            shortcutText = configuration.displayText
            statusText = "Fallback hotkey active."
            detailText = "The default shortcut was unavailable. This shortcut records from any app."
            systemImage = "keyboard.badge.ellipsis"
            statusTint = .secondary
        case .notRegistered:
            shortcutText = preferredConfiguration.displayText
            statusText = "Global hotkey not active."
            detailText = "Use Start Recording in the menu until a shortcut is available."
            systemImage = "keyboard"
            statusTint = .secondary
        case .unavailable(let message):
            shortcutText = preferredConfiguration.displayText
            statusText = "Global hotkey unavailable."
            detailText = "\(message) Use Start Recording in the menu."
            systemImage = "keyboard.badge.exclamationmark"
            statusTint = .red
        }
    }

    private static func activeDetailText(for configuration: GlobalHotkeyConfiguration) -> String {
        switch configuration.activationMode {
        case .holdToRecord:
            return "Hold the shortcut to record from any app."
        case .toggle:
            return "Press the shortcut once to start recording and again to stop."
        }
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let description: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)

            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private enum APIKeySettingsStatus: Equatable {
    case unknown
    case missing
    case saved
    case failure(String)

    var hasSavedKey: Bool {
        self == .saved
    }

    var message: String {
        switch self {
        case .unknown:
            return "Checking saved API key..."
        case .missing:
            return "No API key saved."
        case .saved:
            return "API key saved in Keychain."
        case .failure(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .unknown:
            return "key"
        case .missing:
            return "exclamationmark.triangle"
        case .saved:
            return "checkmark.circle"
        case .failure:
            return "xmark.octagon"
        }
    }

    var tintColor: Color {
        switch self {
        case .unknown, .missing:
            return .secondary
        case .saved:
            return .green
        case .failure:
            return .red
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
