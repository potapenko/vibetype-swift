import CoreFoundation
import Foundation

public enum IOSAcceptedTextHistoryRepositoryError: Error, Equatable, Sendable {
    case readFailed
    case sourceTooLarge
    case malformedData
    case topLevelNotObject
    case missingRequiredValue(path: String)
    case invalidValueType(path: String)
    case invalidValue(path: String)
    case unsupportedSchemaVersion
    case unexpectedFields(path: String)
    case duplicateIdentifier
    case invalidOrdering
    case identifierCollision
    case encodingFailed
    case encodedDataTooLarge
    case writeFailed
}

/// Owns the one compact, app-private successful-text History record.
public actor IOSAcceptedTextHistoryRepository {
    public static let maximumByteCount = 4 * 1_024 * 1_024

    private static let filePolicy = ProtectedAtomicMetadataFilePolicy(
        maximumByteCount: maximumByteCount,
        fileProtection: .complete,
        excludesFromBackup: true
    )

    private let fileURL: URL
    private let fileSystem: any ProtectedAtomicMetadataFileSystem

    public init(applicationSupportDirectoryURL: URL) {
        fileURL = IOSAcceptedTextHistoryStorageLocation.fileURL(
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

    public func load() throws -> IOSAcceptedTextHistoryRecord {
        let data: Data?
        do {
            data = try fileSystem.readFileIfPresent(
                at: fileURL,
                policy: Self.filePolicy
            )
        } catch ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded {
            throw IOSAcceptedTextHistoryRepositoryError.sourceTooLarge
        } catch {
            throw IOSAcceptedTextHistoryRepositoryError.readFailed
        }

        guard let data else {
            return .enabledEmpty
        }
        return try IOSAcceptedTextHistoryWireCodec.decode(
            data,
            maximumInputByteCount: Self.filePolicy.maximumByteCount
        )
    }

    @discardableResult
    public func append(
        _ entry: IOSAcceptedTextHistoryEntry
    ) throws -> IOSAcceptedTextHistoryAppendResult {
        let record = try load()
        guard record.isEnabled else {
            return .disabled
        }

        if let existing = record.entries.first(where: {
            $0.resultID == entry.resultID
        }) {
            guard existing == entry else {
                throw IOSAcceptedTextHistoryRepositoryError.identifierCollision
            }
            return .duplicate
        }

        let retainedEntries = Array(
            (record.entries + [entry])
                .sorted(by: Self.isOrderedBefore)
                .prefix(IOSAcceptedTextHistoryRecord.maximumEntryCount)
        )
        guard retainedEntries.contains(where: {
            $0.resultID == entry.resultID
        }) else {
            return .outsideRetentionWindow
        }

        try replace(
            IOSAcceptedTextHistoryRecord(
                isEnabled: true,
                entries: retainedEntries
            )
        )
        return .inserted
    }

    @discardableResult
    public func delete(
        resultID: UUID
    ) throws -> IOSAcceptedTextHistoryRecord {
        let record = try load()
        let retainedEntries = record.entries.filter {
            $0.resultID != resultID
        }
        guard retainedEntries.count != record.entries.count else {
            return record
        }

        let updated = IOSAcceptedTextHistoryRecord(
            isEnabled: record.isEnabled,
            entries: retainedEntries
        )
        try replace(updated)
        return updated
    }

    @discardableResult
    public func clearAll(
        ifCurrent expected: IOSAcceptedTextHistorySnapshotToken
    ) throws -> IOSAcceptedTextHistoryMutationResult {
        let record = try load()
        guard IOSAcceptedTextHistorySnapshotToken(record: record) == expected
        else {
            return .stale(record)
        }
        guard !record.entries.isEmpty else {
            return .confirmed(record)
        }

        let updated = IOSAcceptedTextHistoryRecord(
            isEnabled: record.isEnabled,
            entries: []
        )
        try replace(updated)
        return .confirmed(updated)
    }

    @discardableResult
    public func setEnabled(
        _ isEnabled: Bool,
        ifCurrent expected: IOSAcceptedTextHistorySnapshotToken
    ) throws -> IOSAcceptedTextHistoryMutationResult {
        let record = try load()
        guard IOSAcceptedTextHistorySnapshotToken(record: record) == expected
        else {
            return .stale(record)
        }
        let targetEntries = isEnabled ? record.entries : []
        guard record.isEnabled != isEnabled
                || record.entries != targetEntries else {
            return .confirmed(record)
        }

        let updated = IOSAcceptedTextHistoryRecord(
            isEnabled: isEnabled,
            entries: targetEntries
        )
        try replace(updated)
        return .confirmed(updated)
    }

    private func replace(_ record: IOSAcceptedTextHistoryRecord) throws {
        let data = try IOSAcceptedTextHistoryWireCodec.encode(record)
        guard data.count <= Self.filePolicy.maximumByteCount else {
            throw IOSAcceptedTextHistoryRepositoryError.encodedDataTooLarge
        }

        do {
            try BoundedJSONMemberValidator.validate(
                data,
                limits: .metadataFile(
                    maximumInputByteCount: Self.filePolicy.maximumByteCount
                )
            )
        } catch BoundedJSONMemberValidationError.inputTooLarge {
            throw IOSAcceptedTextHistoryRepositoryError.encodedDataTooLarge
        } catch {
            throw IOSAcceptedTextHistoryRepositoryError.encodingFailed
        }

        do {
            try fileSystem.replaceFileAtomically(
                at: fileURL,
                with: data,
                policy: Self.filePolicy
            )
        } catch ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded {
            throw IOSAcceptedTextHistoryRepositoryError.encodedDataTooLarge
        } catch {
            throw IOSAcceptedTextHistoryRepositoryError.writeFailed
        }
    }

    fileprivate static func isOrderedBefore(
        _ lhs: IOSAcceptedTextHistoryEntry,
        _ rhs: IOSAcceptedTextHistoryEntry
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.resultID.uuidString < rhs.resultID.uuidString
    }
}

private enum IOSAcceptedTextHistoryWireCodec {
    private static let supportedSchemaVersion = 1
    private static let rootFields: Set<String> = [
        "schemaVersion",
        "enabled",
        "entries",
    ]
    private static let entryFields: Set<String> = [
        "resultID",
        "text",
        "createdAtMilliseconds",
    ]

    static func encode(_ record: IOSAcceptedTextHistoryRecord) throws -> Data {
        let entries: [EntryWireV1]
        do {
            entries = try record.entries.map { entry in
                EntryWireV1(
                    resultID: entry.resultID.uuidString,
                    text: entry.text,
                    createdAtMilliseconds:
                        try IOSAcceptedTextHistoryTimestampCodec
                            .milliseconds(from: entry.createdAt)
                )
            }
        } catch {
            throw IOSAcceptedTextHistoryRepositoryError.encodingFailed
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(
                RecordWireV1(
                    schemaVersion: supportedSchemaVersion,
                    enabled: record.isEnabled,
                    entries: entries
                )
            )
        } catch {
            throw IOSAcceptedTextHistoryRepositoryError.encodingFailed
        }
    }

    static func decode(
        _ data: Data,
        maximumInputByteCount: Int
    ) throws -> IOSAcceptedTextHistoryRecord {
        do {
            try BoundedJSONMemberValidator.validate(
                data,
                limits: .metadataFile(
                    maximumInputByteCount: maximumInputByteCount
                )
            )
        } catch BoundedJSONMemberValidationError.inputTooLarge {
            throw IOSAcceptedTextHistoryRepositoryError.sourceTooLarge
        } catch {
            throw IOSAcceptedTextHistoryRepositoryError.malformedData
        }

        let value: Any
        do {
            value = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw IOSAcceptedTextHistoryRepositoryError.malformedData
        }

        guard let object = value as? [String: Any] else {
            throw IOSAcceptedTextHistoryRepositoryError.topLevelNotObject
        }
        try rejectUnexpectedFields(
            in: object,
            allowing: rootFields,
            path: "$"
        )

        let schemaVersion = try integer(
            "schemaVersion",
            in: object,
            path: "$"
        )
        guard schemaVersion == supportedSchemaVersion else {
            throw IOSAcceptedTextHistoryRepositoryError
                .unsupportedSchemaVersion
        }
        let enabled = try boolean("enabled", in: object, path: "$")
        guard let rawEntries = object["entries"] else {
            throw IOSAcceptedTextHistoryRepositoryError
                .missingRequiredValue(path: "entries")
        }
        guard let entryObjects = rawEntries as? [Any] else {
            throw IOSAcceptedTextHistoryRepositoryError
                .invalidValueType(path: "entries")
        }
        guard entryObjects.count <= IOSAcceptedTextHistoryRecord.maximumEntryCount else {
            throw IOSAcceptedTextHistoryRepositoryError
                .invalidValue(path: "entries")
        }

        var entries: [IOSAcceptedTextHistoryEntry] = []
        entries.reserveCapacity(entryObjects.count)
        var identifiers = Set<UUID>()
        for (index, rawEntry) in entryObjects.enumerated() {
            let path = "entries[\(index)]"
            guard let entryObject = rawEntry as? [String: Any] else {
                throw IOSAcceptedTextHistoryRepositoryError
                    .invalidValueType(path: path)
            }
            try rejectUnexpectedFields(
                in: entryObject,
                allowing: entryFields,
                path: path
            )

            let identifierString = try string(
                "resultID",
                in: entryObject,
                path: path
            )
            guard let identifier = UUID(uuidString: identifierString),
                  identifier.uuidString == identifierString else {
                throw IOSAcceptedTextHistoryRepositoryError
                    .invalidValue(path: "\(path).resultID")
            }
            guard identifiers.insert(identifier).inserted else {
                throw IOSAcceptedTextHistoryRepositoryError
                    .duplicateIdentifier
            }

            let text = try string("text", in: entryObject, path: path)
            guard IOSAcceptedTextHistoryValidation.isStoredText(text) else {
                throw IOSAcceptedTextHistoryRepositoryError
                    .invalidValue(path: "\(path).text")
            }
            let milliseconds = try integer(
                "createdAtMilliseconds",
                in: entryObject,
                path: path
            )
            let date = Date(
                timeIntervalSince1970: Double(milliseconds) / 1_000
            )
            guard (try? IOSAcceptedTextHistoryTimestampCodec
                .milliseconds(from: date)) == milliseconds else {
                throw IOSAcceptedTextHistoryRepositoryError
                    .invalidValue(path: "\(path).createdAtMilliseconds")
            }

            do {
                entries.append(
                    try IOSAcceptedTextHistoryEntry(
                        resultID: identifier,
                        text: text,
                        createdAt: date
                    )
                )
            } catch {
                throw IOSAcceptedTextHistoryRepositoryError
                    .invalidValue(path: path)
            }
        }

        guard enabled || entries.isEmpty else {
            throw IOSAcceptedTextHistoryRepositoryError
                .invalidValue(path: "entries")
        }
        guard entries.elementsEqual(
            entries.sorted(by: IOSAcceptedTextHistoryRepository.isOrderedBefore)
        ) else {
            throw IOSAcceptedTextHistoryRepositoryError.invalidOrdering
        }

        return IOSAcceptedTextHistoryRecord(
            isEnabled: enabled,
            entries: entries
        )
    }

    private static func rejectUnexpectedFields(
        in object: [String: Any],
        allowing allowedFields: Set<String>,
        path: String
    ) throws {
        guard Set(object.keys) == allowedFields else {
            let missingFields = allowedFields.subtracting(object.keys)
            if let missingField = missingFields.sorted().first {
                let valuePath = path == "$"
                    ? missingField
                    : "\(path).\(missingField)"
                throw IOSAcceptedTextHistoryRepositoryError
                    .missingRequiredValue(path: valuePath)
            }
            throw IOSAcceptedTextHistoryRepositoryError
                .unexpectedFields(path: path)
        }
    }

    private static func string(
        _ key: String,
        in object: [String: Any],
        path: String
    ) throws -> String {
        guard let value = object[key] else {
            throw IOSAcceptedTextHistoryRepositoryError
                .missingRequiredValue(path: valuePath(path, key))
        }
        guard let string = value as? String else {
            throw IOSAcceptedTextHistoryRepositoryError
                .invalidValueType(path: valuePath(path, key))
        }
        return string
    }

    private static func boolean(
        _ key: String,
        in object: [String: Any],
        path: String
    ) throws -> Bool {
        guard let value = object[key] else {
            throw IOSAcceptedTextHistoryRepositoryError
                .missingRequiredValue(path: valuePath(path, key))
        }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw IOSAcceptedTextHistoryRepositoryError
                .invalidValueType(path: valuePath(path, key))
        }
        return number.boolValue
    }

    private static func integer(
        _ key: String,
        in object: [String: Any],
        path: String
    ) throws -> Int64 {
        guard let value = object[key] else {
            throw IOSAcceptedTextHistoryRepositoryError
                .missingRequiredValue(path: valuePath(path, key))
        }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !isFloatingPointNumber(number),
              let integer = Int64(number.stringValue) else {
            throw IOSAcceptedTextHistoryRepositoryError
                .invalidValueType(path: valuePath(path, key))
        }
        return integer
    }

    private static func valuePath(_ path: String, _ key: String) -> String {
        path == "$" ? key : "\(path).\(key)"
    }

    private static func isFloatingPointNumber(_ number: NSNumber) -> Bool {
        let typeEncoding = String(cString: number.objCType)
        return typeEncoding == "f" || typeEncoding == "d"
    }
}

private struct RecordWireV1: Encodable {
    let schemaVersion: Int
    let enabled: Bool
    let entries: [EntryWireV1]
}

private struct EntryWireV1: Encodable {
    let resultID: String
    let text: String
    let createdAtMilliseconds: Int64
}
