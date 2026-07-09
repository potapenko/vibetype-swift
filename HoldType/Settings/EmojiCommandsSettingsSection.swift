//
//  EmojiCommandsSettingsSection.swift
//  HoldType
//
//  Created by Codex on 7/7/26.
//

import HoldTypeDomain
import SwiftUI

struct EmojiCommandsSettingsSection: View {
    private static let customTabID = "custom"

    @Binding var settings: AppSettings
    @State private var selectedTabID = AppSettings.defaultEnabledEmojiCommandSetIDs.first ?? "en"
    @State private var customEmoji = ""
    @State private var customCommand = ""
    @State private var customAliases = ""
    @FocusState private var isCustomCommandFocused: Bool

    var body: some View {
        Section("Emoji commands") {
            Toggle("Replace spoken emoji commands", isOn: $settings.emojiCommandsEnabled)

            commandSetPicker

            Text("Choose the active set for transcription and replacement, or select Custom to create your own commands.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if selectedTabID == Self.customTabID {
                customCommandsEditor
            } else if let commandSet = selectedCommandSet {
                builtInCommandSetEditor(commandSet)
            }
        }
        .onAppear(perform: syncSelectedTabFromSettings)
        .onChange(of: selectedTabID) { _, newValue in
            activateSelectedTab(newValue)
        }
    }

    private var commandSetPicker: some View {
        Picker("Set", selection: $selectedTabID) {
            ForEach(EmojiCommandSet.builtIn) { commandSet in
                Text(commandSet.displayName).tag(commandSet.id)
            }

            Text("Custom").tag(Self.customTabID)
        }
        .pickerStyle(.segmented)
    }

    private var selectedCommandSet: EmojiCommandSet? {
        EmojiCommandSet.builtIn.first { $0.id == selectedTabID }
    }

    private func builtInCommandSetEditor(_ commandSet: EmojiCommandSet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(commandSet.commands) { command in
                    EmojiCommandRow(command: command)

                    if command.id != commandSet.commands.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var customCommandsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if settings.customEmojiCommands.isEmpty {
                Label("No custom emoji commands", systemImage: "face.smiling")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach($settings.customEmojiCommands) { $command in
                        CustomEmojiCommandRow(
                            command: $command,
                            remove: { removeCustomCommand(command.id) }
                        )

                        if command.id != settings.customEmojiCommands.last?.id {
                            Divider()
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Emoji", text: $customEmoji)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 70)

                    TextField("Spoken command", text: $customCommand)
                        .textFieldStyle(.roundedBorder)
                        .environment(\.layoutDirection, .leftToRight)
                        .focused($isCustomCommandFocused)
                        .onSubmit(addCustomCommand)

                    Button(action: addCustomCommand) {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(!canAddCustomCommand)
                }

                TextField("Aliases, comma-separated", text: $customAliases)
                    .textFieldStyle(.roundedBorder)
                    .environment(\.layoutDirection, .leftToRight)
                    .onSubmit(addCustomCommand)
            }
            .disabled(!settings.emojiCommandsEnabled)
        }
    }

    private var canAddCustomCommand: Bool {
        draftCustomCommand?.hasUsableCommand == true
    }

    private var draftCustomCommand: CustomEmojiCommand? {
        let command = CustomEmojiCommand(
            emoji: customEmoji,
            command: customCommand,
            aliases: parsedCustomAliases
        ).normalizedForStorage

        return command.hasUsableCommand ? command : nil
    }

    private var parsedCustomAliases: [String] {
        customAliases
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func addCustomCommand() {
        guard let command = draftCustomCommand else {
            return
        }

        settings.customEmojiCommands = AppSettings.normalizedCustomEmojiCommands(
            settings.customEmojiCommands + [command]
        )
        customEmoji = ""
        customCommand = ""
        customAliases = ""
        isCustomCommandFocused = true
    }

    private func removeCustomCommand(_ id: UUID) {
        settings.customEmojiCommands.removeAll { $0.id == id }
    }

    private func syncSelectedTabFromSettings() {
        if let activeSetID = AppSettings.normalizedEmojiCommandSetIDs(
            settings.enabledEmojiCommandSetIDs
        ).first {
            selectedTabID = activeSetID
        } else {
            selectedTabID = Self.customTabID
        }
    }

    private func activateSelectedTab(_ tabID: String) {
        guard tabID != Self.customTabID else {
            settings.enabledEmojiCommandSetIDs = []
            return
        }

        settings.enabledEmojiCommandSetIDs = AppSettings.normalizedEmojiCommandSetIDs([tabID])
    }
}

private struct EmojiCommandRow: View {
    let command: EmojiCommand

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(command.emoji)
                .font(.title2)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(command.primarySpokenPhrase)
                    .font(.body)

                if !command.secondarySpokenPhrases.isEmpty {
                    Text(command.secondarySpokenPhrases.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
    }
}

private struct CustomEmojiCommandRow: View {
    @Binding var command: CustomEmojiCommand
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: $command.isEnabled)
                .labelsHidden()

            Text(command.normalizedEmoji)
                .font(.title2)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(command.displayCommand)

                let aliases = Array(command.normalizedSpokenPhrases.dropFirst())
                if !aliases.isEmpty {
                    Text(aliases.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: remove) {
                Label("Remove", systemImage: "minus.circle")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Remove \(command.displayCommand)")
        }
        .padding(.vertical, 5)
    }
}

#Preview {
    Form {
        EmojiCommandsSettingsSection(settings: .constant(.defaults))
    }
    .formStyle(.grouped)
    .padding()
}
