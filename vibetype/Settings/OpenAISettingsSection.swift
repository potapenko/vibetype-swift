//
//  OpenAISettingsSection.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import SwiftUI

struct OpenAISettingsSection: View {
    @Binding var apiKeyInput: String

    let apiKeyStatus: APIKeySettingsStatus
    let onSaveAPIKey: () -> Void
    let onRemoveAPIKey: () -> Void

    var body: some View {
        Section("OpenAI") {
            SecureField("OpenAI API key", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .privacySensitive()

            Label(apiKeyStatus.message, systemImage: apiKeyStatus.systemImage)
                .foregroundStyle(apiKeyStatus.tintColor)

            HStack {
                Button("Save API Key", action: onSaveAPIKey)
                    .disabled(isAPIKeyInputEmpty)

                Button("Remove Saved Key", role: .destructive, action: onRemoveAPIKey)
                    .disabled(!apiKeyStatus.hasSavedKey)
            }
        }
    }

    private var isAPIKeyInputEmpty: Bool {
        apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum APIKeySettingsStatus: Equatable {
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
    Form {
        OpenAISettingsSection(
            apiKeyInput: .constant(""),
            apiKeyStatus: .missing,
            onSaveAPIKey: {},
            onRemoveAPIKey: {}
        )
    }
    .formStyle(.grouped)
    .padding()
}
