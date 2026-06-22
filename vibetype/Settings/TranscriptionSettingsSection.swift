//
//  TranscriptionSettingsSection.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import SwiftUI

struct TranscriptionSettingsSection: View {
    @Binding var settings: AppSettings
    @State private var newDictionaryEntry = ""

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

        Section("Dictionary") {
            HStack {
                TextField("Add word or phrase", text: $newDictionaryEntry)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addDictionaryEntries)

                Button(action: addDictionaryEntries) {
                    Label("Add", systemImage: "plus")
                }
                .disabled(!canAddDictionaryEntry)
            }

            if dictionaryEntries.isEmpty {
                Label("No custom words yet", systemImage: "book.closed")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dictionaryEntries, id: \.self) { entry in
                    HStack {
                        Text(entry)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()

                        Button {
                            removeDictionaryEntry(entry)
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Remove \(entry)")
                    }
                }
            }
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

    private var dictionaryEntries: [String] {
        settings.resolvedCustomDictionaryEntries
    }

    private var canAddDictionaryEntry: Bool {
        !AppSettings.parseCustomDictionaryEntries(from: newDictionaryEntry).isEmpty
    }

    private func addDictionaryEntries() {
        let currentEntries = settings.resolvedCustomDictionaryEntries
        let updatedEntries = AppSettings.appendingCustomDictionaryEntries(
            from: newDictionaryEntry,
            to: currentEntries
        )

        guard updatedEntries != currentEntries else {
            return
        }

        settings.customDictionary = updatedEntries
        newDictionaryEntry = ""
    }

    private func removeDictionaryEntry(_ entry: String) {
        settings.customDictionary = settings.resolvedCustomDictionaryEntries.filter { $0 != entry }
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
