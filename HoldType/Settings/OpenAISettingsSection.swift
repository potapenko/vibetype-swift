//
//  OpenAISettingsSection.swift
//  HoldType
//
//  Created by Codex on 6/22/26.
//

import SwiftUI

struct OpenAISettingsSection: View {
    @Binding var apiKeyInput: String

    let apiKeyStatus: APIKeySettingsStatus
    let onAPIKeyInputChange: () -> Void
    let onPasteAPIKeyFromClipboard: () -> Void
    let onRemoveAPIKey: () -> Void

    var body: some View {
        Section("OpenAI") {
            OpenAISetupGuideView()

            SavedAPIKeySecureField(
                title: apiKeyStatus.inputTitle,
                text: $apiKeyInput,
                mask: apiKeyStatus.inputMask(isInputEmpty: apiKeyInput.isEmpty),
                onPasteFromClipboard: onPasteAPIKeyFromClipboard
            )
                .onChange(of: apiKeyInput) { _, _ in
                    onAPIKeyInputChange()
                }

            Label(apiKeyStatus.message, systemImage: apiKeyStatus.systemImage)
                .foregroundStyle(apiKeyStatus.tintColor)

            Button("Remove Saved Key", role: .destructive, action: onRemoveAPIKey)
                .disabled(!apiKeyStatus.hasSavedKey)
        }
    }
}

private struct SavedAPIKeySecureField: View {
    let title: String
    @Binding var text: String
    let mask: String?
    let onPasteFromClipboard: () -> Void

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    SettingsTechnicalSecureFieldInput(text: $text)
                        .privacySensitive()
                        .accessibilityValue(accessibilityValue)

                    if let mask {
                        Text(mask)
                            .font(.body.monospaced())
                            .multilineTextAlignment(.leading)
                            .environment(\.layoutDirection, .leftToRight)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onPasteFromClipboard) {
                    Image(systemName: "doc.on.clipboard")
                        .imageScale(.medium)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Paste API key from Clipboard")
                .accessibilityLabel("Paste API key from Clipboard")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var accessibilityValue: Text {
        if mask != nil {
            Text("Saved API key present")
        } else {
            Text("")
        }
    }
}

private struct OpenAISetupGuideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Connect OpenAI", systemImage: "sparkles")
                .font(.headline)

            Text(
                "HoldType uses OpenAI to turn recordings into text. An API key lets this app send recordings through your OpenAI Platform account. HoldType saves the key in macOS Keychain automatically."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                OpenAISetupStepRow(
                    number: 1,
                    text: "Sign in or create an OpenAI account."
                )

                OpenAISetupStepRow(
                    number: 2,
                    text: "Open Billing and add API credits. API billing is separate from ChatGPT Plus, and OpenAI currently starts prepaid credits at $5."
                )

                OpenAISetupStepRow(
                    number: 3,
                    text: "Create a new API key, copy it once, then paste it below."
                )
            }

            HStack(spacing: 12) {
                OpenAISetupLink(
                    title: "Open API Keys",
                    systemImage: "key",
                    urlString: "https://platform.openai.com/api-keys"
                )

                OpenAISetupLink(
                    title: "Open Billing",
                    systemImage: "creditcard",
                    urlString: "https://platform.openai.com/account/billing/overview"
                )

                OpenAISetupLink(
                    title: "Key Safety",
                    systemImage: "lock.shield",
                    urlString: "https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety"
                )
            }
        }
    }
}

private struct OpenAISetupStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.secondary.opacity(0.14)))

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OpenAISetupLink: View {
    let title: String
    let systemImage: String
    let urlString: String

    var body: some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                Label(title, systemImage: systemImage)
            }
        }
    }
}

enum APIKeySettingsStatus: Equatable {
    static let savedAPIKeyInputMask = "••••••••••••"

    case unknown
    case missing
    case saved
    case failure(String)

    var hasSavedKey: Bool {
        switch self {
        case .saved:
            return true
        case .unknown, .missing, .failure:
            return false
        }
    }

    var message: String {
        switch self {
        case .unknown:
            return "API key will be checked when dictation starts."
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

    var inputTitle: String {
        hasSavedKey ? "Replace OpenAI API key" : "OpenAI API key"
    }

    func inputMask(isInputEmpty: Bool) -> String? {
        hasSavedKey && isInputEmpty ? Self.savedAPIKeyInputMask : nil
    }

    var apiKeyAvailability: APIKeyAvailability {
        switch self {
        case .unknown:
            return .unknown
        case .missing:
            return .missing
        case .saved:
            return .saved
        case .failure(let message):
            return .unavailable(message)
        }
    }
}

struct APIKeySettingsState: Equatable {
    var input: String
    var status: APIKeySettingsStatus

    init(
        input: String = "",
        status: APIKeySettingsStatus = .unknown
    ) {
        self.input = input
        self.status = status
    }

    var normalizedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var shouldAutosaveInput: Bool {
        !normalizedInput.isEmpty
    }

    var apiKeyAvailability: APIKeyAvailability {
        status.apiKeyAvailability
    }

    mutating func applyAvailability(_ availability: APIKeyAvailability) {
        switch availability {
        case .unknown:
            status = .unknown
        case .saved:
            input = ""
            status = .saved
        case .missing:
            input = ""
            status = .missing
        case .unavailable(let message):
            status = .failure(message)
        }
    }

    mutating func applySavedInput() {
        guard !normalizedInput.isEmpty else {
            return
        }

        input = ""
        status = .saved
    }

    mutating func applyDeletedAPIKey() {
        input = ""
        status = .missing
    }

    mutating func applyFailure(_ message: String) {
        status = .failure(message)
    }
}

#Preview {
    Form {
        OpenAISettingsSection(
            apiKeyInput: .constant(""),
            apiKeyStatus: .missing,
            onAPIKeyInputChange: {},
            onPasteAPIKeyFromClipboard: {},
            onRemoveAPIKey: {}
        )
    }
    .formStyle(.grouped)
    .padding()
}
