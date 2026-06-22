//
//  TranscriptionSettingsSection.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import SwiftUI

struct TranscriptionSettingsSection: View {
    @Binding var settings: AppSettings

    var body: some View {
        Section("Transcription") {
            TextField("Model", text: $settings.transcriptionModel)
                .textFieldStyle(.roundedBorder)

            if isUsingDefaultTranscriptionModelFallback {
                Label(
                    "Empty model uses \(AppSettings.defaultTranscriptionModel).",
                    systemImage: "info.circle"
                )
                .foregroundStyle(.secondary)
            }

            Picker("Language", selection: $settings.language) {
                ForEach(TranscriptionLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }

            if settings.language == .custom {
                TextField("Custom language code", text: $settings.customLanguageCode)
                    .textFieldStyle(.roundedBorder)

                Label(
                    customLanguageCodeStatusMessage,
                    systemImage: customLanguageCodeStatusImage
                )
                .foregroundStyle(customLanguageCodeStatusTint)
            }

            TextField("Prompt", text: $settings.prompt, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var isUsingDefaultTranscriptionModelFallback: Bool {
        settings.transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var customLanguageCodeStatusMessage: String {
        switch settings.customLanguageCodeValidation {
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
        settings.customLanguageCodeValidation.isInvalid ? "exclamationmark.triangle" : "info.circle"
    }

    private var customLanguageCodeStatusTint: Color {
        settings.customLanguageCodeValidation.isInvalid ? .red : .secondary
    }
}

#Preview {
    Form {
        TranscriptionSettingsSection(
            settings: .constant(
                AppSettings(
                    transcriptionModel: "",
                    language: .custom,
                    customLanguageCode: "ru",
                    prompt: "Prefer product vocabulary.",
                    customDictionary: ["OpenWhispr", "Synty", "The word is VibeType"],
                    automaticallyInsertTranscripts: true,
                    saveTranscriptsToAppClipboard: true,
                    soundEnabled: true,
                    showFloatingIndicator: true,
                    saveTranscriptHistory: false
                )
            )
        )
    }
    .formStyle(.grouped)
    .padding()
}
