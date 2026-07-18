import Foundation
import HoldTypeDomain

nonisolated struct IOSBuiltInEmojiCommandReference: Equatable, Hashable,
    Sendable {
    let setID: String
    let commandID: String

    init?(setID: String, commandID: String) {
        guard let commandSet = EmojiCommandSet.builtIn.first(
            where: { $0.id == setID }
        ), commandSet.commands.contains(where: { $0.id == commandID }) else {
            return nil
        }
        self.setID = setID
        self.commandID = commandID
    }

    var commandSet: EmojiCommandSet? {
        EmojiCommandSet.builtIn.first { $0.id == setID }
    }

    var command: EmojiCommand? {
        commandSet?.commands.first { $0.id == commandID }
    }
}

nonisolated struct IOSCustomEmojiCommandReference: Equatable, Sendable {
    let expected: CustomEmojiCommand
}

extension IOSBuiltInEmojiSetSelection {
    static var iosOptions: [Self] {
        EmojiCommandSet.builtIn.map { .builtIn($0.id) } + [.custom]
    }

    var iosDisplayName: String {
        switch self {
        case .custom:
            "Custom"
        case .builtIn(let identifier):
            switch identifier {
            case "en": "English"
            case "ru": "Russian"
            case "es": "Spanish"
            case "de": "German"
            case "fr": "French"
            case "pt": "Portuguese"
            default: "Unknown"
            }
        }
    }

    var commandSet: EmojiCommandSet? {
        guard case .builtIn(let identifier) = self else { return nil }
        return EmojiCommandSet.builtIn.first { $0.id == identifier }
    }
}

nonisolated enum IOSEmojiCommandDraftValidation: Equatable, Sendable {
    case valid
    case missingOutput
    case missingPrimaryPhrase
    case customPhraseCollision

    static func resolve(
        candidate: CustomEmojiCommand,
        excluding excludedID: UUID?,
        customCommands: [CustomEmojiCommand]
    ) -> Self {
        guard !candidate.normalizedEmoji.isEmpty else {
            return .missingOutput
        }
        guard !EmojiCommand.normalizedSpokenPhrase(candidate.command).isEmpty
        else {
            return .missingPrimaryPhrase
        }

        let normalized = candidate.normalizedForStorage
        let phraseKeys = Set(
            normalized.normalizedSpokenPhrases.compactMap(
                EmojiCommandReplacementService.normalizedSpokenPhraseKey
            )
        )
        let semanticKey = customCommandSemanticKey(normalized)

        let collides = customCommands.contains { command in
            guard command.id != excludedID else { return false }
            if customCommandSemanticKey(command) == semanticKey {
                return true
            }
            let existingKeys = Set(
                command.normalizedSpokenPhrases.compactMap(
                    EmojiCommandReplacementService.normalizedSpokenPhraseKey
                )
            )
            return !phraseKeys.isDisjoint(with: existingKeys)
        }
        return collides ? .customPhraseCollision : .valid
    }

    private static func customCommandSemanticKey(
        _ command: CustomEmojiCommand
    ) -> String {
        "\(command.normalizedEmoji)|\(command.displayCommand)".folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
    }
}

struct IOSEmojiCommandEditorDraft: Equatable, Sendable {
    let id: UUID
    var output: String
    var primaryPhrase: String
    var aliasesText: String

    init(id: UUID) {
        self.id = id
        output = ""
        primaryPhrase = ""
        aliasesText = ""
    }

    init(command: CustomEmojiCommand) {
        id = command.id
        output = command.emoji
        primaryPhrase = command.command
        aliasesText = command.aliases.joined(separator: "\n")
    }

    func candidate(isEnabled: Bool) -> CustomEmojiCommand {
        CustomEmojiCommand(
            id: id,
            emoji: output,
            command: primaryPhrase,
            aliases: parsedAliases,
            isEnabled: isEnabled
        )
    }

    private var parsedAliases: [String] {
        aliasesText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

nonisolated enum IOSEmojiCommandEditorMode: Equatable, Sendable {
    case add(UUID)
    case edit(UUID)

    var id: UUID {
        switch self {
        case .add(let id), .edit(let id): id
        }
    }

    var isNew: Bool {
        if case .add = self { return true }
        return false
    }
}

enum IOSEmojiCommandEditorPhase: Equatable {
    case idle
    case saving
    case saved
    case saveFailed
    case changedElsewhere
    case deletedElsewhere
    case invalid
}

nonisolated struct IOSEmojiCommandSaveRequest: Equatable, Sendable {
    let mutation: IOSLibraryMutation
    let commandID: UUID
}

struct IOSEmojiCommandEditorSession: Equatable {
    let mode: IOSEmojiCommandEditorMode
    private(set) var baseline: CustomEmojiCommand?
    private(set) var latest: CustomEmojiCommand?
    private(set) var draft: IOSEmojiCommandEditorDraft
    private(set) var phase = IOSEmojiCommandEditorPhase.idle

    init(newCommandID: UUID) {
        mode = .add(newCommandID)
        baseline = nil
        latest = nil
        draft = IOSEmojiCommandEditorDraft(id: newCommandID)
    }

    init(command: CustomEmojiCommand) {
        mode = .edit(command.id)
        baseline = command
        latest = command
        draft = IOSEmojiCommandEditorDraft(command: command)
    }

    var isDirty: Bool {
        draft != baselineDraft
    }

    var isSaving: Bool { phase == .saving }

    var canReloadLatest: Bool {
        phase == .changedElsewhere && latest != nil
    }

    var canReplaceLatest: Bool {
        canReloadLatest && isDirty
    }

    mutating func set(
        _ value: String,
        at keyPath: WritableKeyPath<IOSEmojiCommandEditorDraft, String>
    ) {
        guard !isSaving, draft[keyPath: keyPath] != value else { return }
        draft[keyPath: keyPath] = value
        if !isDirty {
            phase = .idle
        } else {
            switch phase {
            case .saved, .invalid:
                phase = .idle
            case .idle, .saving, .saveFailed, .changedElsewhere,
                    .deletedElsewhere:
                break
            }
        }
    }

    func validation(
        in customCommands: [CustomEmojiCommand]
    ) -> IOSEmojiCommandDraftValidation {
        IOSEmojiCommandDraftValidation.resolve(
            candidate: draft.candidate(
                isEnabled: latest?.isEnabled ?? baseline?.isEnabled ?? true
            ),
            excluding: mode.isNew ? nil : mode.id,
            customCommands: customCommands
        )
    }

    mutating func beginSave(
        customCommands: [CustomEmojiCommand],
        replacingLatest: Bool = false
    ) -> IOSEmojiCommandSaveRequest? {
        guard isDirty, !isSaving,
              phase != .deletedElsewhere,
              validation(in: customCommands) == .valid else {
            return nil
        }

        let mutation: IOSLibraryMutation
        switch mode {
        case .add:
            guard phase != .changedElsewhere else { return nil }
            mutation = .emojiCommands(
                .add(draft.candidate(isEnabled: true))
            )
        case .edit:
            if phase == .changedElsewhere, !replacingLatest {
                return nil
            }
            let expected = replacingLatest ? latest : baseline
            guard let expected else { return nil }
            mutation = .emojiCommands(
                .update(
                    expected: expected,
                    requested: draft.candidate(
                        isEnabled: expected.isEnabled
                    )
                )
            )
        }

        phase = .saving
        return IOSEmojiCommandSaveRequest(
            mutation: mutation,
            commandID: mode.id
        )
    }

    mutating func observeDurableCommand(
        _ command: CustomEmojiCommand?
    ) {
        latest = command
        guard !isSaving else { return }

        switch mode {
        case .add:
            guard let command else { return }
            if IOSEmojiCommandEditorDraft(command: command) == draft {
                adopt(command, phase: .saved)
            } else {
                phase = .changedElsewhere
            }
        case .edit:
            guard let command else {
                phase = .deletedElsewhere
                return
            }
            guard command != baseline else {
                if phase == .deletedElsewhere, isDirty {
                    phase = .changedElsewhere
                } else if !isDirty,
                          phase == .changedElsewhere
                            || phase == .deletedElsewhere {
                    phase = .idle
                }
                return
            }
            let incomingDraft = IOSEmojiCommandEditorDraft(command: command)
            if !isDirty {
                adopt(command, phase: .idle)
            } else if incomingDraft == draft {
                adopt(command, phase: .saved)
            } else {
                markChangedElsewhere(command)
            }
        }
    }

    mutating func reloadLatest() {
        guard let latest else { return }
        adopt(latest, phase: .idle)
    }

    mutating func commitSucceeded(
        returnedCommand: CustomEmojiCommand?,
        currentCommand: CustomEmojiCommand?
    ) {
        latest = currentCommand
        guard let currentCommand else {
            latest = nil
            phase = .deletedElsewhere
            return
        }
        guard let returnedCommand else {
            markChangedElsewhere(currentCommand)
            return
        }

        let currentDraft = IOSEmojiCommandEditorDraft(
            command: currentCommand
        )
        let returnedDraft = IOSEmojiCommandEditorDraft(
            command: returnedCommand
        )
        let draftOwnedFieldsMatch = currentDraft == returnedDraft
        guard currentCommand == returnedCommand || draftOwnedFieldsMatch else {
            markChangedElsewhere(currentCommand)
            return
        }
        adopt(currentCommand, phase: .saved)
    }

    mutating func commitFailed(
        currentCommand: CustomEmojiCommand?,
        forceNotSaved: Bool = false
    ) {
        let previousBaseline = baseline
        latest = currentCommand
        switch mode {
        case .add:
            if let currentCommand {
                markChangedElsewhere(currentCommand)
                return
            }
        case .edit:
            guard let currentCommand else {
                phase = .deletedElsewhere
                return
            }
            if currentCommand != previousBaseline {
                markChangedElsewhere(currentCommand)
                return
            }
            baseline = currentCommand
        }
        phase = isDirty || forceNotSaved ? .saveFailed : .idle
    }

    mutating func completeWithoutCommit(
        disposition: IOSLibraryMutationDisposition,
        returnedCommand: CustomEmojiCommand?,
        currentCommand: CustomEmojiCommand?
    ) {
        latest = currentCommand
        switch disposition {
        case .unchanged:
            commitSucceeded(
                returnedCommand: returnedCommand,
                currentCommand: currentCommand
            )
        case .targetMissing:
            if let currentCommand {
                markChangedElsewhere(currentCommand)
            } else {
                phase = .deletedElsewhere
            }
        case .conflict:
            if let currentCommand {
                markChangedElsewhere(currentCommand)
            } else {
                phase = .deletedElsewhere
            }
        case .duplicate, .invalid:
            if let currentCommand,
               mode.isNew || currentCommand != baseline {
                markChangedElsewhere(currentCommand)
            } else {
                phase = .invalid
            }
        case .committed:
            commitSucceeded(
                returnedCommand: returnedCommand,
                currentCommand: currentCommand
            )
        }
    }

    mutating func discard() {
        draft = baselineDraft
        phase = .idle
    }

    private var baselineDraft: IOSEmojiCommandEditorDraft {
        if let baseline {
            return IOSEmojiCommandEditorDraft(command: baseline)
        }
        return IOSEmojiCommandEditorDraft(id: mode.id)
    }

    private mutating func adopt(
        _ command: CustomEmojiCommand,
        phase: IOSEmojiCommandEditorPhase
    ) {
        baseline = command
        latest = command
        draft = IOSEmojiCommandEditorDraft(command: command)
        self.phase = phase
    }

    private mutating func markChangedElsewhere(
        _ command: CustomEmojiCommand
    ) {
        latest = command
        if case .edit = mode {
            baseline = command
        }
        phase = .changedElsewhere
    }
}

enum IOSEmojiCommandsNotice: Equatable {
    case saved
    case deleted
    case changedElsewhere
    case invalid
    case notSaved
}

enum IOSEmojiCommandsPresentation {
    static func summary(
        _ configuration: EmojiCommandsConfiguration
    ) -> String {
        let enabled = configuration.isEnabled ? "On" : "Off"
        let selection = IOSBuiltInEmojiSetSelection(
            storedIdentifiers: configuration.enabledBuiltInSetIDs
        )?.iosDisplayName ?? "Custom"
        return "\(enabled) · \(selection) · "
            + "\(configuration.customCommands.count) custom"
    }
}

extension IOSBuiltInEmojiCommandReference: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String {
        "IOSBuiltInEmojiCommandReference(app-owned)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSCustomEmojiCommandReference: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSCustomEmojiCommandReference(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSEmojiCommandDraftValidation: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSEmojiCommandDraftValidation(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSEmojiCommandEditorDraft: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSEmojiCommandEditorDraft(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSEmojiCommandEditorMode: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSEmojiCommandEditorMode(content-free)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSEmojiCommandEditorPhase: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSEmojiCommandEditorPhase(content-free)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSEmojiCommandSaveRequest: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSEmojiCommandSaveRequest(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSEmojiCommandEditorSession: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSEmojiCommandEditorSession(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSEmojiCommandsNotice: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSEmojiCommandsNotice(content-free)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
