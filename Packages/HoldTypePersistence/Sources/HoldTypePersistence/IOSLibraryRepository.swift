import CoreFoundation
import Foundation
import HoldTypeDomain

public enum IOSLibraryRepositoryError: Error, Equatable, Sendable {
    case readFailed
    case sourceTooLarge
    case malformedData
    case topLevelNotObject
    case missingSchemaVersion
    case invalidValueType(path: String)
    case missingRequiredValue(path: String)
    case invalidValue(path: String)
    case unsupportedSchemaVersion
    case unexpectedFields(path: String)
    case invalidIdentifier(path: String)
    case duplicateIdentifier(path: String)
    case unknownBuiltInSetIdentifier(path: String)
    case invalidBuiltInSetSelection(path: String)
    case encodingFailed
    case encodedDataTooLarge
    case writeFailed
}

/// Serializes access to the containing app's canonical app-private Library file.
public actor IOSLibraryRepository {
    private static let filePolicy = ProtectedAtomicMetadataFilePolicy(
        maximumByteCount: 1_024 * 1_024,
        fileProtection: .complete,
        excludesFromBackup: false
    )

    private let fileURL: URL
    private let fileSystem: any ProtectedAtomicMetadataFileSystem

    public init(applicationSupportDirectoryURL: URL) {
        fileURL = IOSLibraryStorageLocation.fileURL(
            in: applicationSupportDirectoryURL
        )
        fileSystem = FoundationProtectedAtomicMetadataFileSystem()
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        fileSystem = FoundationProtectedAtomicMetadataFileSystem()
    }

    init(
        fileURL: URL,
        fileSystem: any ProtectedAtomicMetadataFileSystem
    ) {
        self.fileURL = fileURL
        self.fileSystem = fileSystem
    }

    public func load() throws -> IOSLibraryContent {
        let data: Data?

        do {
            data = try fileSystem.readFileIfPresent(
                at: fileURL,
                policy: Self.filePolicy
            )
        } catch ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded {
            throw IOSLibraryRepositoryError.sourceTooLarge
        } catch {
            throw IOSLibraryRepositoryError.readFailed
        }

        guard let data else {
            return .defaults
        }

        return try IOSLibraryWireCodec.decode(data)
    }

    public func save(_ content: IOSLibraryContent) throws {
        let data = try IOSLibraryWireCodec.encode(content)
        guard data.count <= Self.filePolicy.maximumByteCount else {
            throw IOSLibraryRepositoryError.encodedDataTooLarge
        }

        do {
            try fileSystem.replaceFileAtomically(
                at: fileURL,
                with: data,
                policy: Self.filePolicy
            )
        } catch ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded {
            throw IOSLibraryRepositoryError.encodedDataTooLarge
        } catch {
            throw IOSLibraryRepositoryError.writeFailed
        }
    }
}

private enum IOSLibraryWireCodec {
    private static let supportedSchemaVersion = 1
    private static let supportedBuiltInSetIdentifiers: Set<String> = [
        "en", "ru", "es", "de", "fr", "pt",
    ]
    private static let rootFields: Set<String> = [
        "schemaVersion", "dictionary", "emojiCommands", "replacementRules",
    ]
    private static let dictionaryFields: Set<String> = ["entries"]
    private static let emojiCommandsFields: Set<String> = [
        "isEnabled", "enabledBuiltInSetIDs", "customCommands",
    ]
    private static let customCommandFields: Set<String> = [
        "id", "emoji", "command", "aliases", "isEnabled",
    ]
    private static let replacementRuleFields: Set<String> = [
        "id", "search", "replacement", "isEnabled",
    ]

    static func encode(_ content: IOSLibraryContent) throws -> Data {
        let canonicalContent = try canonicalized(content)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            return try encoder.encode(IOSLibraryWireV1(content: canonicalContent))
        } catch {
            throw IOSLibraryRepositoryError.encodingFailed
        }
    }

    static func decode(_ data: Data) throws -> IOSLibraryContent {
        let rootValue: Any

        do {
            rootValue = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw IOSLibraryRepositoryError.malformedData
        }

        guard let rootObject = rootValue as? [String: Any] else {
            throw IOSLibraryRepositoryError.topLevelNotObject
        }

        let root = IOSLibraryWireObjectReader(object: rootObject, path: "$")
        guard rootObject.keys.contains("schemaVersion") else {
            throw IOSLibraryRepositoryError.missingSchemaVersion
        }
        let schemaVersion = try root.requiredInteger("schemaVersion")
        guard schemaVersion == supportedSchemaVersion else {
            throw IOSLibraryRepositoryError.unsupportedSchemaVersion
        }
        try root.rejectUnexpectedFields(allowing: rootFields)

        let decoded = IOSLibraryContent(
            customDictionary: try decodeDictionary(from: root),
            emojiCommandsConfiguration: try decodeEmojiCommands(from: root),
            replacementRules: try decodeReplacementRules(from: root)
        )
        return try canonicalized(decoded)
    }

    private static func decodeDictionary(
        from root: IOSLibraryWireObjectReader
    ) throws -> CustomDictionary {
        guard let reader = try root.object("dictionary") else {
            return .empty
        }
        try reader.rejectUnexpectedFields(allowing: dictionaryFields)
        return CustomDictionary(
            entries: try reader.stringArray("entries", defaultValue: [])
        )
    }

    private static func decodeEmojiCommands(
        from root: IOSLibraryWireObjectReader
    ) throws -> EmojiCommandsConfiguration {
        let defaults = EmojiCommandsConfiguration.defaults
        guard let reader = try root.object("emojiCommands") else {
            return defaults
        }
        try reader.rejectUnexpectedFields(allowing: emojiCommandsFields)

        let customCommandObjects = try reader.objectArray(
            "customCommands",
            defaultValue: []
        )
        let customCommands = try customCommandObjects.map { object in
            try decodeCustomCommand(
                from: IOSLibraryWireObjectReader(
                    object: object,
                    path: "emojiCommands.customCommands[]"
                )
            )
        }

        return EmojiCommandsConfiguration(
            isEnabled: try reader.boolean(
                "isEnabled",
                defaultValue: defaults.isEnabled
            ),
            enabledBuiltInSetIDs: try reader.stringArray(
                "enabledBuiltInSetIDs",
                defaultValue: defaults.enabledBuiltInSetIDs
            ),
            customCommands: customCommands
        )
    }

    private static func decodeCustomCommand(
        from reader: IOSLibraryWireObjectReader
    ) throws -> CustomEmojiCommand {
        try reader.rejectUnexpectedFields(allowing: customCommandFields)
        return CustomEmojiCommand(
            id: try reader.requiredUUID("id"),
            emoji: try reader.requiredString("emoji"),
            command: try reader.requiredString("command"),
            aliases: try reader.requiredStringArray("aliases"),
            isEnabled: try reader.requiredBoolean("isEnabled")
        )
    }

    private static func decodeReplacementRules(
        from root: IOSLibraryWireObjectReader
    ) throws -> [TextReplacementRule] {
        let objects = try root.objectArray("replacementRules", defaultValue: [])
        return try objects.map { object in
            let reader = IOSLibraryWireObjectReader(
                object: object,
                path: "replacementRules[]"
            )
            try reader.rejectUnexpectedFields(allowing: replacementRuleFields)
            return TextReplacementRule(
                id: try reader.requiredUUID("id"),
                search: try reader.requiredString("search"),
                replacement: try reader.requiredString("replacement"),
                isEnabled: try reader.requiredBoolean("isEnabled")
            )
        }
    }

    private static func canonicalized(
        _ content: IOSLibraryContent
    ) throws -> IOSLibraryContent {
        let emojiConfiguration = content.emojiCommandsConfiguration
        try validateBuiltInSetIdentifiers(emojiConfiguration.enabledBuiltInSetIDs)
        try validateUniqueIdentifiers(
            emojiConfiguration.customCommands.map(\.id),
            path: "emojiCommands.customCommands[].id"
        )
        try validateCustomCommands(emojiConfiguration.customCommands)
        try validateUniqueIdentifiers(
            content.replacementRules.map(\.id),
            path: "replacementRules[].id"
        )

        return IOSLibraryContent(
            customDictionary: CustomDictionary(
                entries: content.customDictionary.entries
            ),
            emojiCommandsConfiguration: EmojiCommandsConfiguration(
                isEnabled: emojiConfiguration.isEnabled,
                enabledBuiltInSetIDs: emojiConfiguration.enabledBuiltInSetIDs,
                customCommands: EmojiCommandsConfiguration.normalizedCustomCommands(
                    emojiConfiguration.customCommands
                )
            ),
            replacementRules: content.replacementRules
        )
    }

    private static func validateBuiltInSetIdentifiers(
        _ identifiers: [String]
    ) throws {
        let path = "emojiCommands.enabledBuiltInSetIDs"
        guard identifiers.allSatisfy(supportedBuiltInSetIdentifiers.contains) else {
            throw IOSLibraryRepositoryError.unknownBuiltInSetIdentifier(path: path)
        }
        guard identifiers.count <= 1 else {
            throw IOSLibraryRepositoryError.invalidBuiltInSetSelection(path: path)
        }
    }

    private static func validateUniqueIdentifiers(
        _ identifiers: [UUID],
        path: String
    ) throws {
        var seenIdentifiers = Set<UUID>()
        guard identifiers.allSatisfy({ seenIdentifiers.insert($0).inserted }) else {
            throw IOSLibraryRepositoryError.duplicateIdentifier(path: path)
        }
    }

    private static func validateCustomCommands(
        _ commands: [CustomEmojiCommand]
    ) throws {
        for command in commands {
            guard !command.normalizedEmoji.isEmpty else {
                throw IOSLibraryRepositoryError.invalidValue(
                    path: "emojiCommands.customCommands[].emoji"
                )
            }
            guard !command.normalizedSpokenPhrases.isEmpty else {
                throw IOSLibraryRepositoryError.invalidValue(
                    path: "emojiCommands.customCommands[].command"
                )
            }
        }
    }
}

private struct IOSLibraryWireObjectReader {
    let object: [String: Any]
    let path: String

    func rejectUnexpectedFields(allowing allowedFields: Set<String>) throws {
        guard Set(object.keys).isSubset(of: allowedFields) else {
            throw IOSLibraryRepositoryError.unexpectedFields(path: path)
        }
    }

    func object(_ key: String) throws -> IOSLibraryWireObjectReader? {
        guard object.keys.contains(key) else {
            return nil
        }
        guard let nestedObject = object[key] as? [String: Any] else {
            throw IOSLibraryRepositoryError.invalidValueType(path: valuePath(key))
        }
        return IOSLibraryWireObjectReader(
            object: nestedObject,
            path: valuePath(key)
        )
    }

    func stringArray(_ key: String, defaultValue: [String]) throws -> [String] {
        guard object.keys.contains(key) else {
            return defaultValue
        }
        return try requiredStringArray(key)
    }

    func objectArray(
        _ key: String,
        defaultValue: [[String: Any]]
    ) throws -> [[String: Any]] {
        guard object.keys.contains(key) else {
            return defaultValue
        }
        guard let values = object[key] as? [Any],
              values.allSatisfy({ $0 is [String: Any] }) else {
            throw IOSLibraryRepositoryError.invalidValueType(path: valuePath(key))
        }
        return values.compactMap { $0 as? [String: Any] }
    }

    func boolean(_ key: String, defaultValue: Bool) throws -> Bool {
        guard object.keys.contains(key) else {
            return defaultValue
        }
        return try requiredBoolean(key)
    }

    func requiredString(_ key: String) throws -> String {
        try requireField(key)
        guard let value = object[key] as? String else {
            throw IOSLibraryRepositoryError.invalidValueType(path: valuePath(key))
        }
        return value
    }

    func requiredStringArray(_ key: String) throws -> [String] {
        try requireField(key)
        guard let values = object[key] as? [Any],
              values.allSatisfy({ $0 is String }) else {
            throw IOSLibraryRepositoryError.invalidValueType(path: valuePath(key))
        }
        return values.compactMap { $0 as? String }
    }

    func requiredBoolean(_ key: String) throws -> Bool {
        try requireField(key)
        guard let number = object[key] as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw IOSLibraryRepositoryError.invalidValueType(path: valuePath(key))
        }
        return number.boolValue
    }

    func requiredInteger(_ key: String) throws -> Int {
        try requireField(key)
        guard let number = object[key] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !Self.isFloatingPointNumber(number),
              let integer = Int(number.stringValue) else {
            throw IOSLibraryRepositoryError.invalidValueType(path: valuePath(key))
        }
        return integer
    }

    func requiredUUID(_ key: String) throws -> UUID {
        let rawValue = try requiredString(key)
        guard let identifier = UUID(uuidString: rawValue) else {
            throw IOSLibraryRepositoryError.invalidIdentifier(path: valuePath(key))
        }
        return identifier
    }

    private func requireField(_ key: String) throws {
        guard object.keys.contains(key) else {
            throw IOSLibraryRepositoryError.missingRequiredValue(path: valuePath(key))
        }
    }

    private func valuePath(_ key: String) -> String {
        path == "$" ? key : "\(path).\(key)"
    }

    private static func isFloatingPointNumber(_ number: NSNumber) -> Bool {
        let typeEncoding = String(cString: number.objCType)
        return typeEncoding == "f" || typeEncoding == "d"
    }
}

private struct IOSLibraryWireV1: Encodable {
    let schemaVersion = 1
    let dictionary: IOSLibraryDictionaryWireV1
    let emojiCommands: IOSLibraryEmojiCommandsWireV1
    let replacementRules: [IOSLibraryReplacementRuleWireV1]

    init(content: IOSLibraryContent) {
        dictionary = IOSLibraryDictionaryWireV1(
            entries: content.customDictionary.entries
        )
        emojiCommands = IOSLibraryEmojiCommandsWireV1(
            isEnabled: content.emojiCommandsConfiguration.isEnabled,
            enabledBuiltInSetIDs:
                content.emojiCommandsConfiguration.enabledBuiltInSetIDs,
            customCommands: content.emojiCommandsConfiguration.customCommands.map {
                IOSLibraryCustomCommandWireV1(command: $0)
            }
        )
        replacementRules = content.replacementRules.map {
            IOSLibraryReplacementRuleWireV1(rule: $0)
        }
    }
}

private struct IOSLibraryDictionaryWireV1: Encodable {
    let entries: [String]
}

private struct IOSLibraryEmojiCommandsWireV1: Encodable {
    let isEnabled: Bool
    let enabledBuiltInSetIDs: [String]
    let customCommands: [IOSLibraryCustomCommandWireV1]
}

private struct IOSLibraryCustomCommandWireV1: Encodable {
    let id: String
    let emoji: String
    let command: String
    let aliases: [String]
    let isEnabled: Bool

    init(command: CustomEmojiCommand) {
        id = command.id.uuidString
        emoji = command.emoji
        self.command = command.command
        aliases = command.aliases
        isEnabled = command.isEnabled
    }
}

private struct IOSLibraryReplacementRuleWireV1: Encodable {
    let id: String
    let search: String
    let replacement: String
    let isEnabled: Bool

    init(rule: TextReplacementRule) {
        id = rule.id.uuidString
        search = rule.search
        replacement = rule.replacement
        isEnabled = rule.isEnabled
    }
}
