import CoreFoundation
import Foundation

nonisolated enum KeyboardDictationBridgeConfiguration {
    static let commandFilename = "keyboard-dictation-command-v1.json"
    static let stateFilename = "keyboard-dictation-state-v1.json"
    static let maximumRecordBytes = 4 * 1_024
    static let commandLifetime: TimeInterval = 5
    static let sessionLifetime: TimeInterval = 60
    static let resultMaximumUTF8Bytes = 3 * 1_024
    static let commandNotification =
        "app.holdtype.keyboard-dictation.command.v1"
    static let stateNotification =
        "app.holdtype.keyboard-dictation.state.v1"
}

nonisolated enum KeyboardDictationCommandKind: String, Codable, Sendable {
    case start
    case finish
    case cancel
}

nonisolated struct KeyboardDictationCommandRecord:
    Codable,
    Equatable,
    Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let requestID: UUID
    let kind: KeyboardDictationCommandKind
    let issuedAt: Date
    let expiresAt: Date

    init?(
        requestID: UUID,
        kind: KeyboardDictationCommandKind,
        issuedAt: Date,
        expiresAt: Date
    ) {
        guard issuedAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt > issuedAt,
              expiresAt.timeIntervalSince(issuedAt)
                <= KeyboardDictationBridgeConfiguration.commandLifetime else {
            return nil
        }
        schemaVersion = Self.schemaVersion
        self.requestID = requestID
        self.kind = kind
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    func isValid(at date: Date) -> Bool {
        schemaVersion == Self.schemaVersion
            && issuedAt.timeIntervalSinceReferenceDate.isFinite
            && expiresAt.timeIntervalSinceReferenceDate.isFinite
            && expiresAt > date
            && expiresAt > issuedAt
            && expiresAt.timeIntervalSince(issuedAt)
                <= KeyboardDictationBridgeConfiguration.commandLifetime
    }
}

nonisolated enum KeyboardDictationStatePhase: String, Codable, Sendable {
    case ready
    case listening
    case processing
    case resultReady
    case unavailable
    case failed
}

nonisolated struct KeyboardDictationStateRecord:
    Codable,
    Equatable,
    Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let requestID: UUID
    let phase: KeyboardDictationStatePhase
    let result: String?
    let publishedAt: Date
    let expiresAt: Date

    init?(
        requestID: UUID,
        phase: KeyboardDictationStatePhase,
        result: String? = nil,
        publishedAt: Date,
        expiresAt: Date
    ) {
        let hasValidResult = result.map {
            !$0.isEmpty
                && $0.utf8.count
                    <= KeyboardDictationBridgeConfiguration
                        .resultMaximumUTF8Bytes
        } ?? false
        guard publishedAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt > publishedAt,
              expiresAt.timeIntervalSince(publishedAt)
                <= KeyboardDictationBridgeConfiguration.sessionLifetime,
              (phase == .resultReady) == hasValidResult else {
            return nil
        }
        schemaVersion = Self.schemaVersion
        self.requestID = requestID
        self.phase = phase
        self.result = result
        self.publishedAt = publishedAt
        self.expiresAt = expiresAt
    }

    func isValid(at date: Date) -> Bool {
        guard schemaVersion == Self.schemaVersion,
              publishedAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt > date,
              expiresAt > publishedAt,
              expiresAt.timeIntervalSince(publishedAt)
                <= KeyboardDictationBridgeConfiguration.sessionLifetime else {
            return false
        }
        let hasValidResult = result.map {
            !$0.isEmpty
                && $0.utf8.count
                    <= KeyboardDictationBridgeConfiguration
                        .resultMaximumUTF8Bytes
        } ?? false
        return (phase == .resultReady) == hasValidResult
    }
}

nonisolated enum KeyboardDictationBridgeStoreError: Error, Equatable {
    case appGroupContainerUnavailable
    case readFailed
    case decodeFailed
    case encodeFailed
    case writeFailed
    case recordTooLarge
}

/// Exactly two bounded atomic projections: extension-written command and
/// containing-app-written state/result. This store has no history or queue.
nonisolated struct KeyboardDictationBridgeStore {
    private let directoryURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    static func appGroup(
        fileManager: FileManager = .default
    ) throws -> KeyboardDictationBridgeStore {
        guard let directoryURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier:
                KeyboardBridgeConfiguration.appGroupIdentifier
        ) else {
            throw KeyboardDictationBridgeStoreError
                .appGroupContainerUnavailable
        }
        return KeyboardDictationBridgeStore(
            directoryURL: directoryURL,
            fileManager: fileManager
        )
    }

    func loadCommand(at date: Date = Date()) throws
        -> KeyboardDictationCommandRecord? {
        guard let record: KeyboardDictationCommandRecord = try load(
            filename: KeyboardDictationBridgeConfiguration.commandFilename
        ) else {
            return nil
        }
        return record.isValid(at: date) ? record : nil
    }

    func loadState(at date: Date = Date()) throws
        -> KeyboardDictationStateRecord? {
        guard let record: KeyboardDictationStateRecord = try load(
            filename: KeyboardDictationBridgeConfiguration.stateFilename
        ) else {
            return nil
        }
        return record.isValid(at: date) ? record : nil
    }

    func saveCommand(_ record: KeyboardDictationCommandRecord) throws {
        try save(
            record,
            filename: KeyboardDictationBridgeConfiguration.commandFilename
        )
    }

    func saveState(_ record: KeyboardDictationStateRecord) throws {
        try save(
            record,
            filename: KeyboardDictationBridgeConfiguration.stateFilename
        )
    }

    private func load<Record: Decodable>(filename: String) throws -> Record? {
        let url = directoryURL.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: url.path
        ),
        let size = attributes[.size] as? NSNumber,
        size.intValue <= KeyboardDictationBridgeConfiguration.maximumRecordBytes
        else {
            throw KeyboardDictationBridgeStoreError.recordTooLarge
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw KeyboardDictationBridgeStoreError.readFailed
        }
        do {
            return try decoder.decode(Record.self, from: data)
        } catch {
            throw KeyboardDictationBridgeStoreError.decodeFailed
        }
    }

    private func save<Record: Encodable>(
        _ record: Record,
        filename: String
    ) throws {
        let data: Data
        do {
            data = try encoder.encode(record)
        } catch {
            throw KeyboardDictationBridgeStoreError.encodeFailed
        }
        guard data.count
            <= KeyboardDictationBridgeConfiguration.maximumRecordBytes else {
            throw KeyboardDictationBridgeStoreError.recordTooLarge
        }
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try data.write(
                to: directoryURL.appendingPathComponent(filename),
                options: [
                    .atomic,
                    .completeFileProtectionUntilFirstUserAuthentication,
                ]
            )
        } catch {
            throw KeyboardDictationBridgeStoreError.writeFailed
        }
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

nonisolated enum KeyboardDictationBridgeSignal {
    static func postCommandChanged() {
        post(KeyboardDictationBridgeConfiguration.commandNotification)
    }

    static func postStateChanged() {
        post(KeyboardDictationBridgeConfiguration.stateNotification)
    }

    private static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }
}

@MainActor
final class KeyboardDictationBridgeObserver {
    private let name: String
    private let action: @MainActor () -> Void

    init(name: String, action: @escaping @MainActor () -> Void) {
        self.name = name
        self.action = action
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            keyboardDictationDarwinCallback,
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(name as CFString),
            nil
        )
    }

    fileprivate func receive() {
        action()
    }
}

private let keyboardDictationDarwinCallback: CFNotificationCallback = {
    _, observer, _, _, _ in
    guard let observer else { return }
    let owner = Unmanaged<KeyboardDictationBridgeObserver>
        .fromOpaque(observer)
        .takeUnretainedValue()
    Task { @MainActor in
        owner.receive()
    }
}
