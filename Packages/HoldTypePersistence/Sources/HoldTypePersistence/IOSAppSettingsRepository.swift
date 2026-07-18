import Foundation

public enum IOSAppSettingsRepositoryError: Error, Equatable, Sendable {
    case readFailed
    case sourceTooLarge
    case malformedData
    case topLevelNotObject
    case missingSchemaVersion
    case invalidValueType(path: String)
    case unsupportedSchemaVersion
    case unexpectedFields(path: String)
    case unknownEnumValue(path: String)
    case encodingFailed
    case encodedDataTooLarge
    case writeFailed
}

/// Serializes access to the containing app's canonical, app-private settings file.
public actor IOSAppSettingsRepository {
    private static let filePolicy = ProtectedAtomicMetadataFilePolicy(
        maximumByteCount: 1_024 * 1_024,
        fileProtection: .complete,
        excludesFromBackup: false
    )

    private let fileURL: URL
    private let fileSystem: any ProtectedAtomicMetadataFileSystem

    public init(applicationSupportDirectoryURL: URL) {
        fileURL = IOSAppSettingsStorageLocation.fileURL(
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

    public func load() throws -> IOSAppSettings {
        let data: Data?

        do {
            data = try fileSystem.readFileIfPresent(
                at: fileURL,
                policy: Self.filePolicy
            )
        } catch ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded {
            throw IOSAppSettingsRepositoryError.sourceTooLarge
        } catch {
            throw IOSAppSettingsRepositoryError.readFailed
        }

        guard let data else {
            return .defaults
        }

        return try IOSAppSettingsWireCodec.decode(
            data,
            maximumInputByteCount: Self.filePolicy.maximumByteCount
        )
    }

    public func save(_ settings: IOSAppSettings) throws {
        let data = try IOSAppSettingsWireCodec.encode(settings)
        guard data.count <= Self.filePolicy.maximumByteCount else {
            throw IOSAppSettingsRepositoryError.encodedDataTooLarge
        }

        do {
            try fileSystem.replaceFileAtomically(
                at: fileURL,
                with: data,
                policy: Self.filePolicy
            )
        } catch ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded {
            throw IOSAppSettingsRepositoryError.encodedDataTooLarge
        } catch {
            throw IOSAppSettingsRepositoryError.writeFailed
        }
    }
}
