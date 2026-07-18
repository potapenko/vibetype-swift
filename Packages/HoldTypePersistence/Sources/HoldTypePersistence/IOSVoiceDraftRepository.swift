import CoreFoundation
import Foundation

public enum IOSVoiceDraftRepositoryError: Error, Equatable, Sendable {
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
    case identifierCollision
    case encodingFailed
    case encodedDataTooLarge
    case writeFailed
}

/// Owns the one bounded, protected, app-private composed Voice Draft record.
public actor IOSVoiceDraftRepository {
    public static let maximumByteCount = 4 * 1_024 * 1_024

    private static let filePolicy = ProtectedAtomicMetadataFilePolicy(
        maximumByteCount: maximumByteCount,
        fileProtection: .complete,
        excludesFromBackup: true
    )

    private let fileURL: URL
    private let fileSystem: any ProtectedAtomicMetadataFileSystem

    public init(applicationSupportDirectoryURL: URL) {
        fileURL = IOSVoiceDraftStorageLocation.fileURL(
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

    public func load() throws -> IOSVoiceDraftRecord {
        let data: Data?
        do {
            data = try fileSystem.readFileIfPresent(
                at: fileURL,
                policy: Self.filePolicy
            )
        } catch ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded {
            throw IOSVoiceDraftRepositoryError.sourceTooLarge
        } catch {
            throw IOSVoiceDraftRepositoryError.readFailed
        }

        guard let data else { return .empty }
        return try IOSVoiceDraftWireCodec.decode(
            data,
            maximumInputByteCount: Self.filePolicy.maximumByteCount
        )
    }

    public func append(
        _ segment: IOSVoiceDraftSegment
    ) throws -> IOSVoiceDraftAppendResult {
        try accept(segment, mode: .append)
    }

    public func accept(
        _ segment: IOSVoiceDraftSegment,
        mode: IOSVoiceDraftInsertionMode
    ) throws -> IOSVoiceDraftAppendResult {
        let record = try load()
        if let existing = record.segments.first(where: {
            $0.resultID == segment.resultID
        }) {
            guard existing == segment else {
                throw IOSVoiceDraftRepositoryError.identifierCollision
            }
            return .duplicate(record)
        }
        let updated: IOSVoiceDraftRecord
        switch mode {
        case .replace:
            updated = IOSVoiceDraftRecord(
                text: segment.text,
                segments: [segment]
            )
        case .append:
            guard !record.isFull else { return .full(record) }
            let appendedText = record.text.isEmpty
                ? segment.text
                : record.text + "\n\n" + segment.text
            updated = IOSVoiceDraftRecord(
                text: appendedText,
                segments: record.segments + [segment]
            )
        }
        try replace(updated)
        return .inserted(updated)
    }

    public func replace(
        _ updated: IOSVoiceDraftRecord,
        ifCurrent expected: IOSVoiceDraftSnapshotToken
    ) throws -> IOSVoiceDraftMutationResult {
        let current = try load()
        guard IOSVoiceDraftSnapshotToken(record: current) == expected else {
            return .stale(current)
        }
        guard current != updated else { return .confirmed(current) }
        try replace(updated)
        return .confirmed(updated)
    }

    private func replace(_ record: IOSVoiceDraftRecord) throws {
        let data = try IOSVoiceDraftWireCodec.encode(record)
        guard data.count <= Self.filePolicy.maximumByteCount else {
            throw IOSVoiceDraftRepositoryError.encodedDataTooLarge
        }
        do {
            try BoundedJSONMemberValidator.validate(
                data,
                limits: .metadataFile(
                    maximumInputByteCount: Self.filePolicy.maximumByteCount
                )
            )
        } catch BoundedJSONMemberValidationError.inputTooLarge {
            throw IOSVoiceDraftRepositoryError.encodedDataTooLarge
        } catch {
            throw IOSVoiceDraftRepositoryError.encodingFailed
        }

        do {
            try fileSystem.replaceFileAtomically(
                at: fileURL,
                with: data,
                policy: Self.filePolicy
            )
        } catch ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded {
            throw IOSVoiceDraftRepositoryError.encodedDataTooLarge
        } catch {
            throw IOSVoiceDraftRepositoryError.writeFailed
        }
    }
}

private enum IOSVoiceDraftWireCodec {
    private static let supportedSchemaVersion = 2
    private static let v1RootFields: Set<String> = [
        "schemaVersion",
        "segments",
    ]
    private static let v2RootFields: Set<String> = [
        "schemaVersion",
        "text",
        "acceptedSegments",
    ]
    private static let segmentFields: Set<String> = [
        "resultID",
        "text",
    ]

    private struct RecordWireV2: Codable {
        let schemaVersion: Int
        let text: String
        let acceptedSegments: [SegmentWireV1]
    }

    private struct SegmentWireV1: Codable {
        let resultID: String
        let text: String
    }

    static func encode(_ record: IOSVoiceDraftRecord) throws -> Data {
        guard record.segments.count <= IOSVoiceDraftRecord.maximumSegmentCount,
              IOSVoiceDraftRecord.isValidEditableText(record.text),
              !record.text.isEmpty || record.segments.isEmpty else {
            throw IOSVoiceDraftRepositoryError.encodingFailed
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(
                RecordWireV2(
                    schemaVersion: supportedSchemaVersion,
                    text: record.text,
                    acceptedSegments: record.segments.map {
                        SegmentWireV1(
                            resultID: $0.resultID.uuidString,
                            text: $0.text
                        )
                    }
                )
            )
        } catch {
            throw IOSVoiceDraftRepositoryError.encodingFailed
        }
    }

    static func decode(
        _ data: Data,
        maximumInputByteCount: Int
    ) throws -> IOSVoiceDraftRecord {
        guard data.count <= maximumInputByteCount else {
            throw IOSVoiceDraftRepositoryError.sourceTooLarge
        }
        do {
            try BoundedJSONMemberValidator.validate(
                data,
                limits: .metadataFile(
                    maximumInputByteCount: maximumInputByteCount
                )
            )
        } catch BoundedJSONMemberValidationError.inputTooLarge {
            throw IOSVoiceDraftRepositoryError.sourceTooLarge
        } catch {
            throw IOSVoiceDraftRepositoryError.malformedData
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw IOSVoiceDraftRepositoryError.malformedData
        }
        guard let root = object as? [String: Any] else {
            throw IOSVoiceDraftRepositoryError.topLevelNotObject
        }
        let version = try requireInteger(root["schemaVersion"], path: "schemaVersion")
        switch version {
        case 1:
            try requireExactFields(root, expected: v1RootFields, path: "$")
            return try decodeV1(root)
        case supportedSchemaVersion:
            try requireExactFields(root, expected: v2RootFields, path: "$")
            return try decodeV2(root)
        default:
            throw IOSVoiceDraftRepositoryError.unsupportedSchemaVersion
        }
    }

    private static func decodeV1(
        _ root: [String: Any]
    ) throws -> IOSVoiceDraftRecord {
        let segments = try decodeSegments(root["segments"], path: "segments")
        return IOSVoiceDraftRecord(segments: segments)
    }

    private static func decodeV2(
        _ root: [String: Any]
    ) throws -> IOSVoiceDraftRecord {
        let text = try requireString(root["text"], path: "text")
        guard IOSVoiceDraftRecord.isValidEditableText(text) else {
            throw IOSVoiceDraftRepositoryError.invalidValue(path: "text")
        }
        let segments = try decodeSegments(
            root["acceptedSegments"],
            path: "acceptedSegments"
        )
        guard !text.isEmpty || segments.isEmpty else {
            throw IOSVoiceDraftRepositoryError.invalidValue(path: "text")
        }
        return IOSVoiceDraftRecord(text: text, segments: segments)
    }

    private static func decodeSegments(
        _ value: Any?,
        path rootPath: String
    ) throws -> [IOSVoiceDraftSegment] {
        guard let rawSegments = value as? [Any] else {
            throw IOSVoiceDraftRepositoryError.invalidValueType(
                path: rootPath
            )
        }
        guard rawSegments.count <= IOSVoiceDraftRecord.maximumSegmentCount else {
            throw IOSVoiceDraftRepositoryError.invalidValue(path: rootPath)
        }

        var seen = Set<UUID>()
        var segments: [IOSVoiceDraftSegment] = []
        segments.reserveCapacity(rawSegments.count)
        for (index, rawSegment) in rawSegments.enumerated() {
            let path = "\(rootPath)[\(index)]"
            guard let object = rawSegment as? [String: Any] else {
                throw IOSVoiceDraftRepositoryError.invalidValueType(path: path)
            }
            try requireExactFields(object, expected: segmentFields, path: path)
            let identifierText = try requireString(
                object["resultID"],
                path: "\(path).resultID"
            )
            guard let resultID = UUID(uuidString: identifierText) else {
                throw IOSVoiceDraftRepositoryError.invalidValue(
                    path: "\(path).resultID"
                )
            }
            guard seen.insert(resultID).inserted else {
                throw IOSVoiceDraftRepositoryError.duplicateIdentifier
            }
            let text = try requireString(
                object["text"],
                path: "\(path).text"
            )
            do {
                segments.append(
                    try IOSVoiceDraftSegment(resultID: resultID, text: text)
                )
            } catch {
                throw IOSVoiceDraftRepositoryError.invalidValue(
                    path: "\(path).text"
                )
            }
        }
        return segments
    }

    private static func requireExactFields(
        _ object: [String: Any],
        expected: Set<String>,
        path: String
    ) throws {
        let actual = Set(object.keys)
        guard expected.isSubset(of: actual) else {
            let missing = expected.subtracting(actual).sorted().first ?? path
            throw IOSVoiceDraftRepositoryError.missingRequiredValue(
                path: path == "$" ? missing : "\(path).\(missing)"
            )
        }
        guard actual == expected else {
            throw IOSVoiceDraftRepositoryError.unexpectedFields(path: path)
        }
    }

    private static func requireInteger(
        _ value: Any?,
        path: String
    ) throws -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.rounded(.towardZero) == number.doubleValue
        else {
            throw IOSVoiceDraftRepositoryError.invalidValueType(path: path)
        }
        return number.intValue
    }

    private static func requireString(
        _ value: Any?,
        path: String
    ) throws -> String {
        guard let value = value as? String else {
            throw IOSVoiceDraftRepositoryError.invalidValueType(path: path)
        }
        return value
    }
}
