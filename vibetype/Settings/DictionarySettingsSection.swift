//
//  DictionarySettingsSection.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import SwiftUI

struct DictionarySettingsSection: View {
    @Binding var settings: AppSettings
    @State private var newDictionaryEntry = ""

    var body: some View {
        Section("Dictionary") {
            HStack {
                TextField("Add word or phrase", text: $newDictionaryEntry, axis: .vertical)
                    .lineLimit(1...3)
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
        DictionarySettingsSection(
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
