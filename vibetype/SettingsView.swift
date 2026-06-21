//
//  SettingsView.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import SwiftUI

struct SettingsView: View {
    @State private var accessibilityPermissionStatus: AccessibilityPermissionStatus
    @State private var appSettings: AppSettings
    @State private var apiKeyInput = ""
    @State private var apiKeyStatus: APIKeySettingsStatus = .unknown

    private let accessibilityPermissionService: AccessibilityPermissionService
    private let apiKeyStorage: APIKeyStorage
    private let appSettingsStore: AppSettingsStore

    init(
        accessibilityPermissionService: AccessibilityPermissionService = AccessibilityPermissionService(),
        apiKeyStorage: APIKeyStorage = KeychainService(),
        appSettingsStore: AppSettingsStore = AppSettingsStore()
    ) {
        self.accessibilityPermissionService = accessibilityPermissionService
        self.apiKeyStorage = apiKeyStorage
        self.appSettingsStore = appSettingsStore
        _appSettings = State(initialValue: appSettingsStore.load())
        _accessibilityPermissionStatus = State(
            initialValue: accessibilityPermissionService.currentStatus()
        )
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

            Section("Permissions") {
                Label(
                    accessibilityPermissionStatus.settingsDescription,
                    systemImage: accessibilityPermissionStatus.canPasteIntoActiveApp
                        ? "checkmark.circle"
                        : "exclamationmark.triangle"
                )
                .foregroundStyle(.secondary)

                if !accessibilityPermissionStatus.canPasteIntoActiveApp {
                    Button("Open Accessibility Settings") {
                        accessibilityPermissionService.openAccessibilitySettings()
                        refreshAccessibilityPermissionStatus()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scenePadding()
        .frame(minWidth: 460, minHeight: 400, alignment: .topLeading)
        .onAppear {
            reloadAppSettings()
            refreshAccessibilityPermissionStatus()
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

    private func reloadAppSettings() {
        appSettings = appSettingsStore.load()
    }

    private func refreshAccessibilityPermissionStatus() {
        accessibilityPermissionStatus = accessibilityPermissionService.currentStatus()
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
