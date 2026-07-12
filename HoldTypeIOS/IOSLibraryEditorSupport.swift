import Foundation
import HoldTypeDomain
import HoldTypePersistence

enum IOSLibraryDestination: String, CaseIterable, Hashable {
    case dictionary
    case emojiCommands = "emoji-commands"
    case replacementRules = "replacement-rules"

    var title: String {
        switch self {
        case .dictionary: "Dictionary"
        case .emojiCommands: "Voice Emoji Commands"
        case .replacementRules: "Replacement Rules"
        }
    }

    var systemImage: String {
        switch self {
        case .dictionary: "text.book.closed"
        case .emojiCommands: "face.smiling"
        case .replacementRules: "arrow.left.arrow.right"
        }
    }

    var rowAccessibilityIdentifier: String {
        "ios.library.\(rawValue).row"
    }
}

struct IOSDictionaryAddDraft: Equatable {
    var rawInput = ""

    var hasMeaningfulInput: Bool {
        !rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct IOSLibrarySearchQuery: Equatable {
    var text = ""
}

enum IOSLibraryEditorNotice: Equatable {
    case added(addedCount: Int, duplicateCount: Int)
    case duplicate(duplicateCount: Int)
    case deleted
    case changedElsewhere
    case invalid
    case notSaved
}

nonisolated enum IOSLibraryMutationDisposition: Equatable, Sendable {
    case committed
    case unchanged
    case duplicate
    case targetMissing
    case conflict
    case invalid
}

nonisolated struct IOSLibraryMutationReceipt: Equatable, Sendable {
    let disposition: IOSLibraryMutationDisposition
    let addedCount: Int
    let duplicateCount: Int

    init(
        disposition: IOSLibraryMutationDisposition,
        addedCount: Int = 0,
        duplicateCount: Int = 0
    ) {
        self.disposition = disposition
        self.addedCount = addedCount
        self.duplicateCount = duplicateCount
    }
}

struct IOSLibraryMutationCompletion: Equatable, Sendable {
    let state: IOSLibraryState
    let receipt: IOSLibraryMutationReceipt
}

nonisolated struct IOSDictionaryEntryReference: Equatable, Hashable, Sendable {
    let expectedValue: String
    fileprivate let semanticKey: String

    init?(_ value: String) {
        let normalized = Self.normalizedValue(value)
        guard !normalized.isEmpty else { return nil }
        expectedValue = normalized
        semanticKey = Self.key(forNormalizedValue: normalized)
    }

    func matches(_ value: String) -> Bool {
        let normalized = Self.normalizedValue(value)
        return !normalized.isEmpty
            && Self.key(forNormalizedValue: normalized) == semanticKey
    }

    private static func normalizedValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func key(forNormalizedValue value: String) -> String {
        value.lowercased()
    }
}

nonisolated enum IOSBuiltInEmojiSetSelection: Equatable, Sendable {
    case custom
    case builtIn(String)

    init?(storedIdentifiers: [String]) {
        switch storedIdentifiers.count {
        case 0:
            self = .custom
        case 1:
            let identifier = storedIdentifiers[0]
            guard Self.supportedIdentifiers.contains(identifier) else {
                return nil
            }
            self = .builtIn(identifier)
        default:
            return nil
        }
    }

    var storedIdentifiers: [String]? {
        switch self {
        case .custom:
            []
        case .builtIn(let identifier):
            Self.supportedIdentifiers.contains(identifier)
                ? [identifier]
                : nil
        }
    }

    private static let supportedIdentifiers = Set(
        EmojiCommandSet.builtIn.map(\.id)
    )
}

nonisolated enum IOSDictionaryMutation: Equatable, Sendable {
    case add(rawInput: String)
    case remove(IOSDictionaryEntryReference)
}

nonisolated enum IOSEmojiCommandsMutation: Equatable, Sendable {
    case setEnabled(expected: Bool, requested: Bool)
    case selectBuiltInSet(
        expected: IOSBuiltInEmojiSetSelection,
        requested: IOSBuiltInEmojiSetSelection
    )
    case add(CustomEmojiCommand)
    case update(
        expected: CustomEmojiCommand,
        requested: CustomEmojiCommand
    )
    case setCommandEnabled(
        id: UUID,
        expected: Bool,
        requested: Bool
    )
    case remove(expected: CustomEmojiCommand)
}

nonisolated enum IOSReplacementRulesMutation: Equatable, Sendable {
    case add(TextReplacementRule)
    case update(
        expected: TextReplacementRule,
        requested: TextReplacementRule
    )
    case setEnabled(
        id: UUID,
        expected: Bool,
        requested: Bool
    )
    case remove(expected: TextReplacementRule)
    case reorder(expected: [UUID], requested: [UUID])
}

nonisolated enum IOSLibraryMutation: Equatable, Sendable {
    case dictionary(IOSDictionaryMutation)
    case emojiCommands(IOSEmojiCommandsMutation)
    case replacementRules(IOSReplacementRulesMutation)

    func apply(
        to content: inout IOSLibraryContent
    ) -> IOSLibraryMutationReceipt {
        switch self {
        case .dictionary(let mutation):
            applyDictionary(mutation, to: &content)
        case .emojiCommands(let mutation):
            applyEmojiCommands(mutation, to: &content)
        case .replacementRules(let mutation):
            applyReplacementRules(mutation, to: &content)
        }
    }

    private func applyDictionary(
        _ mutation: IOSDictionaryMutation,
        to content: inout IOSLibraryContent
    ) -> IOSLibraryMutationReceipt {
        switch mutation {
        case .add(let rawInput):
            let parsed = CustomDictionary.parseEntries(from: rawInput)
            guard !parsed.isEmpty else {
                return IOSLibraryMutationReceipt(disposition: .invalid)
            }

            var existingKeys = Set(
                content.customDictionary.entries.compactMap(
                    IOSDictionaryEntryReference.init
                ).map(\.semanticKey)
            )
            var additions: [String] = []
            var duplicateCount = 0

            for candidate in parsed {
                guard let reference = IOSDictionaryEntryReference(candidate)
                else { continue }
                guard existingKeys.insert(reference.semanticKey).inserted else {
                    duplicateCount += 1
                    continue
                }
                additions.append(reference.expectedValue)
            }

            guard !additions.isEmpty else {
                return IOSLibraryMutationReceipt(
                    disposition: .duplicate,
                    duplicateCount: duplicateCount
                )
            }
            content.customDictionary = CustomDictionary(
                entries: content.customDictionary.entries + additions
            )
            return IOSLibraryMutationReceipt(
                disposition: .committed,
                addedCount: additions.count,
                duplicateCount: duplicateCount
            )

        case .remove(let reference):
            guard let index = content.customDictionary.entries.firstIndex(
                where: reference.matches
            ) else {
                return IOSLibraryMutationReceipt(
                    disposition: .targetMissing
                )
            }
            guard content.customDictionary.entries[index]
                    == reference.expectedValue else {
                return IOSLibraryMutationReceipt(disposition: .conflict)
            }
            var entries = content.customDictionary.entries
            entries.remove(at: index)
            content.customDictionary = CustomDictionary(entries: entries)
            return IOSLibraryMutationReceipt(disposition: .committed)
        }
    }

    private func applyEmojiCommands(
        _ mutation: IOSEmojiCommandsMutation,
        to content: inout IOSLibraryContent
    ) -> IOSLibraryMutationReceipt {
        var configuration = content.emojiCommandsConfiguration

        switch mutation {
        case .setEnabled(let expected, let requested):
            guard configuration.isEnabled == expected else {
                return IOSLibraryMutationReceipt(disposition: .conflict)
            }
            guard requested != expected else {
                return IOSLibraryMutationReceipt(disposition: .unchanged)
            }
            configuration.isEnabled = requested

        case .selectBuiltInSet(let expected, let requested):
            guard let current = IOSBuiltInEmojiSetSelection(
                storedIdentifiers: configuration.enabledBuiltInSetIDs
            ), current == expected else {
                return IOSLibraryMutationReceipt(disposition: .conflict)
            }
            guard let requestedIdentifiers = requested.storedIdentifiers else {
                return IOSLibraryMutationReceipt(disposition: .invalid)
            }
            guard current != requested else {
                return IOSLibraryMutationReceipt(disposition: .unchanged)
            }
            configuration.enabledBuiltInSetIDs = requestedIdentifiers

        case .add(let requested):
            guard hasRequiredCustomCommandFields(requested) else {
                return IOSLibraryMutationReceipt(disposition: .invalid)
            }
            let normalized = requested.normalizedForStorage
            guard normalized.hasUsableCommand else {
                return IOSLibraryMutationReceipt(disposition: .invalid)
            }
            if let existing = configuration.customCommands.first(
                where: { $0.id == normalized.id }
            ) {
                return IOSLibraryMutationReceipt(
                    disposition: existing.normalizedForStorage == normalized
                        ? .unchanged
                        : .conflict
                )
            }
            guard !hasCustomCommandCollision(
                normalized,
                excluding: nil,
                in: configuration.customCommands
            ) else {
                return IOSLibraryMutationReceipt(disposition: .invalid)
            }
            configuration.customCommands.append(normalized)

        case .update(let expected, let requested):
            guard expected.id == requested.id else {
                return IOSLibraryMutationReceipt(disposition: .invalid)
            }
            guard let index = configuration.customCommands.firstIndex(
                where: { $0.id == expected.id }
            ) else {
                return IOSLibraryMutationReceipt(
                    disposition: .targetMissing
                )
            }
            guard configuration.customCommands[index] == expected else {
                return IOSLibraryMutationReceipt(disposition: .conflict)
            }
            guard hasRequiredCustomCommandFields(requested) else {
                return IOSLibraryMutationReceipt(disposition: .invalid)
            }
            let normalized = requested.normalizedForStorage
            guard normalized.hasUsableCommand else {
                return IOSLibraryMutationReceipt(disposition: .invalid)
            }
            guard !hasCustomCommandCollision(
                normalized,
                excluding: normalized.id,
                in: configuration.customCommands
            ) else {
                return IOSLibraryMutationReceipt(disposition: .invalid)
            }
            guard configuration.customCommands[index] != normalized else {
                return IOSLibraryMutationReceipt(disposition: .unchanged)
            }
            configuration.customCommands[index] = normalized

        case .setCommandEnabled(let id, let expected, let requested):
            guard let index = configuration.customCommands.firstIndex(
                where: { $0.id == id }
            ) else {
                return IOSLibraryMutationReceipt(
                    disposition: .targetMissing
                )
            }
            guard configuration.customCommands[index].isEnabled == expected
            else {
                return IOSLibraryMutationReceipt(disposition: .conflict)
            }
            guard requested != expected else {
                return IOSLibraryMutationReceipt(disposition: .unchanged)
            }
            configuration.customCommands[index].isEnabled = requested

        case .remove(let expected):
            guard let index = configuration.customCommands.firstIndex(
                where: { $0.id == expected.id }
            ) else {
                return IOSLibraryMutationReceipt(
                    disposition: .targetMissing
                )
            }
            guard configuration.customCommands[index] == expected else {
                return IOSLibraryMutationReceipt(disposition: .conflict)
            }
            configuration.customCommands.remove(at: index)
        }

        content.emojiCommandsConfiguration = configuration
        return IOSLibraryMutationReceipt(disposition: .committed)
    }

    private func hasRequiredCustomCommandFields(
        _ command: CustomEmojiCommand
    ) -> Bool {
        !command.normalizedEmoji.isEmpty
            && !EmojiCommand.normalizedSpokenPhrase(command.command).isEmpty
    }

    private func applyReplacementRules(
        _ mutation: IOSReplacementRulesMutation,
        to content: inout IOSLibraryContent
    ) -> IOSLibraryMutationReceipt {
        switch mutation {
        case .add(let requested):
            guard requested.hasSearchText else {
                return IOSLibraryMutationReceipt(disposition: .invalid)
            }
            if let existing = content.replacementRules.first(
                where: { $0.id == requested.id }
            ) {
                return IOSLibraryMutationReceipt(
                    disposition: existing == requested
                        ? .unchanged
                        : .conflict
                )
            }
            content.replacementRules.append(requested)

        case .update(let expected, let requested):
            guard expected.id == requested.id else {
                return IOSLibraryMutationReceipt(disposition: .invalid)
            }
            guard let index = content.replacementRules.firstIndex(
                where: { $0.id == expected.id }
            ) else {
                return IOSLibraryMutationReceipt(
                    disposition: .targetMissing
                )
            }
            guard content.replacementRules[index] == expected else {
                return IOSLibraryMutationReceipt(disposition: .conflict)
            }
            guard content.replacementRules[index] != requested else {
                return IOSLibraryMutationReceipt(disposition: .unchanged)
            }
            content.replacementRules[index] = requested

        case .setEnabled(let id, let expected, let requested):
            guard let index = content.replacementRules.firstIndex(
                where: { $0.id == id }
            ) else {
                return IOSLibraryMutationReceipt(
                    disposition: .targetMissing
                )
            }
            guard content.replacementRules[index].isEnabled == expected else {
                return IOSLibraryMutationReceipt(disposition: .conflict)
            }
            guard requested != expected else {
                return IOSLibraryMutationReceipt(disposition: .unchanged)
            }
            content.replacementRules[index].isEnabled = requested

        case .remove(let expected):
            guard let index = content.replacementRules.firstIndex(
                where: { $0.id == expected.id }
            ) else {
                return IOSLibraryMutationReceipt(
                    disposition: .targetMissing
                )
            }
            guard content.replacementRules[index] == expected else {
                return IOSLibraryMutationReceipt(disposition: .conflict)
            }
            content.replacementRules.remove(at: index)

        case .reorder(let expected, let requested):
            let current = content.replacementRules.map(\.id)
            guard Set(current).count == current.count,
                  current == expected else {
                return IOSLibraryMutationReceipt(disposition: .conflict)
            }
            guard Set(requested).count == requested.count,
                  Set(requested) == Set(expected) else {
                return IOSLibraryMutationReceipt(disposition: .invalid)
            }
            guard requested != expected else {
                return IOSLibraryMutationReceipt(disposition: .unchanged)
            }
            let rulesByID = Dictionary(
                uniqueKeysWithValues: content.replacementRules.map {
                    ($0.id, $0)
                }
            )
            content.replacementRules = requested.compactMap { rulesByID[$0] }
        }

        return IOSLibraryMutationReceipt(disposition: .committed)
    }

    private func hasCustomCommandCollision(
        _ candidate: CustomEmojiCommand,
        excluding excludedID: UUID?,
        in commands: [CustomEmojiCommand]
    ) -> Bool {
        let semanticKey = customCommandSemanticKey(candidate)
        let phraseKeys = Set(
            candidate.normalizedSpokenPhrases.compactMap(
                EmojiCommandReplacementService.normalizedSpokenPhraseKey
            )
        )

        return commands.contains { command in
            guard command.id != excludedID else { return false }
            if customCommandSemanticKey(command) == semanticKey {
                return true
            }
            let existingPhraseKeys = Set(
                command.normalizedSpokenPhrases.compactMap(
                    EmojiCommandReplacementService.normalizedSpokenPhraseKey
                )
            )
            return !phraseKeys.isDisjoint(with: existingPhraseKeys)
        }
    }

    private func customCommandSemanticKey(
        _ command: CustomEmojiCommand
    ) -> String {
        "\(command.normalizedEmoji)|\(command.displayCommand)".folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
    }
}

extension IOSLibraryState {
    var durableValue: IOSLibraryContent? {
        switch self {
        case .ready(let value), .saveFailed(let value):
            value
        case .notLoaded, .loadFailed:
            nil
        }
    }
}

extension IOSLibraryMutationDisposition: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSLibraryMutationDisposition(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSLibraryMutationReceipt: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSLibraryMutationReceipt(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSLibraryMutationCompletion: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSLibraryMutationCompletion(redacted)"
    }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSDictionaryEntryReference: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSDictionaryEntryReference(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSBuiltInEmojiSetSelection: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSBuiltInEmojiSetSelection(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSDictionaryMutation: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSDictionaryMutation(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSEmojiCommandsMutation: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSEmojiCommandsMutation(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSReplacementRulesMutation: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSReplacementRulesMutation(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSLibraryMutation: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSLibraryMutation(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSDictionaryAddDraft: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSDictionaryAddDraft(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSLibrarySearchQuery: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSLibrarySearchQuery(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSLibraryEditorNotice: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSLibraryEditorNotice(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
