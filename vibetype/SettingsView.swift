//
//  SettingsView.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import SwiftUI

struct SettingsView: View {
    @State private var accessibilityPermissionStatus: AccessibilityPermissionStatus
    @State private var apiKeyInput = ""
    @State private var apiKeyStatus: APIKeySettingsStatus = .unknown

    private let accessibilityPermissionService: AccessibilityPermissionService
    private let apiKeyStorage: APIKeyStorage

    init(
        accessibilityPermissionService: AccessibilityPermissionService = AccessibilityPermissionService(),
        apiKeyStorage: APIKeyStorage = KeychainService()
    ) {
        self.accessibilityPermissionService = accessibilityPermissionService
        self.apiKeyStorage = apiKeyStorage
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
            refreshAccessibilityPermissionStatus()
            refreshAPIKeyStatus()
        }
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
