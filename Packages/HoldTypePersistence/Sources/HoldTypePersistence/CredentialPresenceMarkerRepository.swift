import Foundation

public enum CredentialPresenceMarkerRepositoryError: Error, Equatable, Sendable {
    case readFailed
    case corruptData
    case unsupportedSchemaVersion(Int)
    case unexpectedFields([String])
    case invalidState(String)
    case invalidMutationKind(String)
    case invalidMutationCombination
    case encodingFailed
    case writeFailed
}

/// Persists the app-private credential-presence marker without touching Keychain.
public struct CredentialPresenceMarkerRepository {
    private static let replacementOptions = CredentialPresenceMarkerReplacementOptions(
        fileProtection: .complete,
        excludesFromBackup: true
    )

    private let fileURL: URL
    private let fileSystem: any CredentialPresenceMarkerFileSystem

    public init(fileURL: URL) {
        self.init(
            fileURL: fileURL,
            fileSystem: FoundationCredentialPresenceMarkerFileSystem()
        )
    }

    init(
        fileURL: URL,
        fileSystem: any CredentialPresenceMarkerFileSystem
    ) {
        self.fileURL = fileURL
        self.fileSystem = fileSystem
    }

    public func load() throws -> CredentialPresenceMarker? {
        let data: Data?

        do {
            data = try fileSystem.readFileIfPresent(at: fileURL)
        } catch {
            throw CredentialPresenceMarkerRepositoryError.readFailed
        }

        guard let data else {
            return nil
        }

        return try CredentialPresenceMarkerWireCodec.decode(data)
    }

    public func save(_ marker: CredentialPresenceMarker) throws {
        let data: Data

        do {
            data = try CredentialPresenceMarkerWireCodec.encode(marker)
        } catch let error as CredentialPresenceMarkerRepositoryError {
            throw error
        } catch {
            throw CredentialPresenceMarkerRepositoryError.encodingFailed
        }

        do {
            try fileSystem.replaceFileAtomically(
                at: fileURL,
                with: data,
                options: Self.replacementOptions
            )
        } catch {
            throw CredentialPresenceMarkerRepositoryError.writeFailed
        }
    }
}

private enum CredentialPresenceMarkerWireCodec {
    private static let supportedSchemaVersion = 1
    private static let requiredFields: Set<String> = [
        "schemaVersion",
        "state",
        "updatedAt",
    ]
    private static let allowedFields = requiredFields.union(["mutationKind"])

    static func encode(_ marker: CredentialPresenceMarker) throws -> Data {
        let wireValue = CredentialPresenceMarkerWireV1(
            schemaVersion: supportedSchemaVersion,
            state: marker.state.wireValue,
            updatedAt: DateCodec.string(from: marker.updatedAt),
            mutationKind: marker.mutationKind?.wireValue
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            return try encoder.encode(wireValue)
        } catch {
            throw CredentialPresenceMarkerRepositoryError.encodingFailed
        }
    }

    static func decode(_ data: Data) throws -> CredentialPresenceMarker {
        let version = try decodeSchemaVersion(from: data)
        guard version == supportedSchemaVersion else {
            throw CredentialPresenceMarkerRepositoryError.unsupportedSchemaVersion(version)
        }

        let keys = try topLevelKeys(in: data)
        let unexpectedFields = keys.subtracting(allowedFields).sorted()
        guard unexpectedFields.isEmpty else {
            throw CredentialPresenceMarkerRepositoryError.unexpectedFields(unexpectedFields)
        }
        guard requiredFields.isSubset(of: keys) else {
            throw CredentialPresenceMarkerRepositoryError.corruptData
        }

        let wireValue: CredentialPresenceMarkerWireV1
        do {
            wireValue = try JSONDecoder().decode(CredentialPresenceMarkerWireV1.self, from: data)
        } catch {
            throw CredentialPresenceMarkerRepositoryError.corruptData
        }

        let state = try CredentialPresenceMarker.State(wireValue: wireValue.state)
        let mutationKind = try wireValue.mutationKind.map(CredentialPresenceMarker.MutationKind.init(wireValue:))
        if state != .mutationInProgress, keys.contains("mutationKind") {
            throw CredentialPresenceMarkerRepositoryError.invalidMutationCombination
        }

        guard let updatedAt = DateCodec.date(from: wireValue.updatedAt) else {
            throw CredentialPresenceMarkerRepositoryError.corruptData
        }

        do {
            return try CredentialPresenceMarker(
                state: state,
                updatedAt: updatedAt,
                mutationKind: mutationKind
            )
        } catch CredentialPresenceMarker.ValidationError.invalidMutationCombination {
            throw CredentialPresenceMarkerRepositoryError.invalidMutationCombination
        }
    }

    private static func decodeSchemaVersion(from data: Data) throws -> Int {
        do {
            return try JSONDecoder().decode(SchemaVersionEnvelope.self, from: data).schemaVersion
        } catch {
            throw CredentialPresenceMarkerRepositoryError.corruptData
        }
    }

    private static func topLevelKeys(in data: Data) throws -> Set<String> {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CredentialPresenceMarkerRepositoryError.corruptData
        }

        guard let object = value as? [String: Any] else {
            throw CredentialPresenceMarkerRepositoryError.corruptData
        }

        return Set(object.keys)
    }
}

private struct SchemaVersionEnvelope: Decodable {
    let schemaVersion: Int
}

private struct CredentialPresenceMarkerWireV1: Codable {
    let schemaVersion: Int
    let state: String
    let updatedAt: String
    let mutationKind: String?
}

private enum DateCodec {
    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }

    private static var formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

private extension CredentialPresenceMarker.State {
    init(wireValue: String) throws {
        switch wireValue {
        case "present":
            self = .present
        case "absent":
            self = .absent
        case "unknown":
            self = .unknown
        case "mutationInProgress":
            self = .mutationInProgress
        default:
            throw CredentialPresenceMarkerRepositoryError.invalidState(wireValue)
        }
    }

    var wireValue: String {
        switch self {
        case .present:
            "present"
        case .absent:
            "absent"
        case .unknown:
            "unknown"
        case .mutationInProgress:
            "mutationInProgress"
        }
    }
}

private extension CredentialPresenceMarker.MutationKind {
    init(wireValue: String) throws {
        switch wireValue {
        case "saveOrReplace":
            self = .saveOrReplace
        case "remove":
            self = .remove
        default:
            throw CredentialPresenceMarkerRepositoryError.invalidMutationKind(wireValue)
        }
    }

    var wireValue: String {
        switch self {
        case .saveOrReplace:
            "saveOrReplace"
        case .remove:
            "remove"
        }
    }
}
