import Foundation

nonisolated enum KeyboardHandoffIntentConfiguration {
    static let filename = "keyboard-handoff-intent-v1.json"
    static let maximumRecordBytes = 4 * 1_024
    static let lifetime: TimeInterval = 10
}

nonisolated enum KeyboardHandoffIntentDisposition: String, Codable, Sendable {
    case pending
    case consumed
}

/// One short-lived keyboard-to-app launch request. It contains only opaque
/// routing identity and the selected action, never host text or provider data.
nonisolated struct KeyboardHandoffIntentRecord:
    Codable,
    Equatable,
    Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let requestID: UUID
    let sourceDocumentID: UUID?
    let action: KeyboardVoiceAction
    let issuedAt: Date
    let expiresAt: Date
    let disposition: KeyboardHandoffIntentDisposition
    let consumedAt: Date?

    init?(
        requestID: UUID,
        sourceDocumentID: UUID?,
        action: KeyboardVoiceAction,
        issuedAt: Date,
        expiresAt: Date
    ) {
        guard Self.hasValidLifetime(
            issuedAt: issuedAt,
            expiresAt: expiresAt
        ) else {
            return nil
        }
        schemaVersion = Self.schemaVersion
        self.requestID = requestID
        self.sourceDocumentID = sourceDocumentID
        self.action = action
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        disposition = .pending
        consumedAt = nil
    }

    func isPending(at date: Date) -> Bool {
        isWellFormed
            && disposition == .pending
            && consumedAt == nil
            && issuedAt <= date
            && expiresAt > date
    }

    func consuming(at date: Date) -> Self? {
        guard isPending(at: date) else { return nil }
        return Self(
            schemaVersion: schemaVersion,
            requestID: requestID,
            sourceDocumentID: sourceDocumentID,
            action: action,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            disposition: .consumed,
            consumedAt: date
        )
    }

    var isWellFormed: Bool {
        guard schemaVersion == Self.schemaVersion,
              Self.hasValidLifetime(
                issuedAt: issuedAt,
                expiresAt: expiresAt
              ) else {
            return false
        }
        switch disposition {
        case .pending:
            return consumedAt == nil
        case .consumed:
            guard let consumedAt else { return false }
            return consumedAt >= issuedAt && consumedAt < expiresAt
        }
    }

    private init(
        schemaVersion: Int,
        requestID: UUID,
        sourceDocumentID: UUID?,
        action: KeyboardVoiceAction,
        issuedAt: Date,
        expiresAt: Date,
        disposition: KeyboardHandoffIntentDisposition,
        consumedAt: Date?
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.sourceDocumentID = sourceDocumentID
        self.action = action
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.disposition = disposition
        self.consumedAt = consumedAt
    }

    private static func hasValidLifetime(
        issuedAt: Date,
        expiresAt: Date
    ) -> Bool {
        issuedAt.timeIntervalSinceReferenceDate.isFinite
            && expiresAt.timeIntervalSinceReferenceDate.isFinite
            && expiresAt > issuedAt
            && expiresAt.timeIntervalSince(issuedAt)
                <= KeyboardHandoffIntentConfiguration.lifetime
    }
}

nonisolated struct KeyboardHandoffLaunchRoute: Equatable, Sendable {
    static let scheme = "holdtype"
    static let host = "keyboard-handoff"

    let requestID: UUID

    init(requestID: UUID) {
        self.requestID = requestID
    }

    init?(url: URL) {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        components.scheme == Self.scheme,
        components.host == Self.host,
        components.user == nil,
        components.password == nil,
        components.port == nil,
        components.queryItems == nil,
        components.fragment == nil else {
            return nil
        }
        let path = components.path.split(separator: "/")
        guard path.count == 1,
              let requestID = UUID(uuidString: String(path[0])) else {
            return nil
        }
        self.requestID = requestID
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.path = "/\(requestID.uuidString.lowercased())"
        return components.url
    }
}

nonisolated enum KeyboardHandoffIntentStoreError: Error, Equatable {
    case appGroupContainerUnavailable
    case readFailed
    case decodeFailed
    case encodeFailed
    case writeFailed
    case recordTooLarge
    case invalidRecord
}

/// One atomic, expiring intent projection. A newer save supersedes the previous
/// request and a successful consume persists before returning the intent.
nonisolated struct KeyboardHandoffIntentStore {
    private let directoryURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    static func appGroup(
        fileManager: FileManager = .default
    ) throws -> Self {
        guard let directoryURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier:
                KeyboardBridgeConfiguration.appGroupIdentifier
        ) else {
            throw KeyboardHandoffIntentStoreError.appGroupContainerUnavailable
        }
        return Self(directoryURL: directoryURL, fileManager: fileManager)
    }

    func save(_ record: KeyboardHandoffIntentRecord) throws {
        guard record.isWellFormed else {
            throw KeyboardHandoffIntentStoreError.invalidRecord
        }
        let data: Data
        do {
            data = try encoder.encode(record)
        } catch {
            throw KeyboardHandoffIntentStoreError.encodeFailed
        }
        guard data.count <= KeyboardHandoffIntentConfiguration.maximumRecordBytes
        else {
            throw KeyboardHandoffIntentStoreError.recordTooLarge
        }
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try data.write(
                to: intentURL,
                options: [
                    .atomic,
                    .completeFileProtectionUntilFirstUserAuthentication,
                ]
            )
        } catch {
            throw KeyboardHandoffIntentStoreError.writeFailed
        }
    }

    func loadPending(at date: Date = Date()) throws
        -> KeyboardHandoffIntentRecord? {
        guard let record = try loadRecord(), record.isPending(at: date) else {
            return nil
        }
        return record
    }

    /// Returns the one admitted handoff retained for extension reconnection.
    ///
    /// The launch deadline applies only while the record is pending. Once the
    /// app has consumed it, the matching bounded dictation state owns expiry.
    /// A newer keyboard tap atomically supersedes this record.
    func loadConsumed() throws -> KeyboardHandoffIntentRecord? {
        guard let record = try loadRecord(),
              record.disposition == .consumed else {
            return nil
        }
        return record
    }

    func consume(
        requestID: UUID,
        at date: Date = Date()
    ) throws -> KeyboardHandoffIntentRecord? {
        guard let record = try loadRecord(),
              record.requestID == requestID,
              let consumed = record.consuming(at: date) else {
            return nil
        }
        try save(consumed)
        return record
    }

    private func loadRecord() throws -> KeyboardHandoffIntentRecord? {
        guard fileManager.fileExists(atPath: intentURL.path) else { return nil }
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: intentURL.path
        ),
        let size = attributes[.size] as? NSNumber,
        size.intValue <= KeyboardHandoffIntentConfiguration.maximumRecordBytes
        else {
            throw KeyboardHandoffIntentStoreError.recordTooLarge
        }
        let data: Data
        do {
            data = try Data(contentsOf: intentURL)
        } catch {
            throw KeyboardHandoffIntentStoreError.readFailed
        }
        let record: KeyboardHandoffIntentRecord
        do {
            record = try decoder.decode(
                KeyboardHandoffIntentRecord.self,
                from: data
            )
        } catch {
            throw KeyboardHandoffIntentStoreError.decodeFailed
        }
        guard record.isWellFormed else {
            throw KeyboardHandoffIntentStoreError.invalidRecord
        }
        return record
    }

    private var intentURL: URL {
        directoryURL.appendingPathComponent(
            KeyboardHandoffIntentConfiguration.filename
        )
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
