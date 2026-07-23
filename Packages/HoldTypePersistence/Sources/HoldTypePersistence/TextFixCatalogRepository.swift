import Foundation
import HoldTypeDomain

public enum TextFixCatalogRepositoryError: Error, Equatable, Sendable {
    case readFailed
    case sourceTooLarge
    case malformedData
    case topLevelNotObject
    case missingRequiredValue(path: String)
    case invalidValueType(path: String)
    case invalidValue(path: String)
    case unsupportedSchemaVersion
    case unexpectedFields(path: String)
    case invalidCatalog
    case encodingFailed
    case encodedDataTooLarge
    case encodedStructureTooComplex
    case writeFailed
}

/// Serializes access to one canonical, platform-local Fixes catalog.
public actor TextFixCatalogRepository {
    public static let maximumByteCount = 1_024 * 1_024

    private static let filePolicy = ProtectedAtomicMetadataFilePolicy(
        maximumByteCount: maximumByteCount,
        fileProtection: .complete,
        excludesFromBackup: false
    )

    private let fileURL: URL
    private let fileSystem: any ProtectedAtomicMetadataFileSystem

    /// Compatibility initializer for the containing iOS app's private catalog.
    public init(applicationSupportDirectoryURL: URL) {
        fileURL = IOSTextFixCatalogStorageLocation.fileURL(
            in: applicationSupportDirectoryURL
        )
        fileSystem = FoundationProtectedAtomicMetadataFileSystem()
    }

    /// Creates the macOS repository at its stable local Application Support path.
    public init(macOSApplicationSupportDirectoryURL: URL) {
        fileURL = MacOSTextFixCatalogStorageLocation.fileURL(
            in: macOSApplicationSupportDirectoryURL
        )
        fileSystem = FoundationProtectedAtomicMetadataFileSystem()
    }

    init(
        fileURL: URL,
        fileSystem: any ProtectedAtomicMetadataFileSystem
    ) {
        self.fileURL = fileURL
        self.fileSystem = fileSystem
    }

    public func load() throws -> TextFixCatalog {
        let data: Data?
        do {
            data = try fileSystem.readFileIfPresent(
                at: fileURL,
                policy: Self.filePolicy
            )
        } catch ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded {
            throw TextFixCatalogRepositoryError.sourceTooLarge
        } catch {
            throw TextFixCatalogRepositoryError.readFailed
        }

        guard let data else {
            return .defaults
        }
        return try IOSTextFixCatalogWireCodec.decode(
            data,
            maximumInputByteCount: Self.filePolicy.maximumByteCount
        )
    }

    @discardableResult
    public func save(_ catalog: TextFixCatalog) throws -> TextFixCatalog {
        let encoding = try IOSTextFixCatalogWireCodec.encode(catalog)
        guard encoding.data.count <= Self.filePolicy.maximumByteCount else {
            throw TextFixCatalogRepositoryError.encodedDataTooLarge
        }
        do {
            try BoundedJSONMemberValidator.validate(
                encoding.data,
                limits: .metadataFile(
                    maximumInputByteCount: Self.filePolicy.maximumByteCount
                )
            )
        } catch BoundedJSONMemberValidationError.inputTooLarge {
            throw TextFixCatalogRepositoryError.encodedDataTooLarge
        } catch BoundedJSONMemberValidationError.resourceLimitExceeded {
            throw TextFixCatalogRepositoryError.encodedStructureTooComplex
        } catch {
            throw TextFixCatalogRepositoryError.encodingFailed
        }

        do {
            try fileSystem.replaceFileAtomically(
                at: fileURL,
                with: encoding.data,
                policy: Self.filePolicy
            )
        } catch ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded {
            throw TextFixCatalogRepositoryError.encodedDataTooLarge
        } catch {
            throw TextFixCatalogRepositoryError.writeFailed
        }
        return encoding.catalog
    }
}

extension TextFixCatalogRepository: CustomStringConvertible,
    CustomDebugStringConvertible {
    public nonisolated var description: String {
        "TextFixCatalogRepository(redacted)"
    }

    public nonisolated var debugDescription: String { description }
}

/// Source-compatible iOS name retained while both platforms share one facade.
public typealias IOSTextFixCatalogRepository = TextFixCatalogRepository
/// Source-compatible iOS error name retained for existing callers.
public typealias IOSTextFixCatalogRepositoryError =
    TextFixCatalogRepositoryError
