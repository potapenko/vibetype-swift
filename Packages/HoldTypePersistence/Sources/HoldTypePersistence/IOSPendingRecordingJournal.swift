import CoreFoundation
import Darwin
import Foundation
import HoldTypeDomain

protocol IOSPendingRecordingJournalStoring: Sendable {
    func load() throws -> IOSPendingRecording?
    func create(_ recording: IOSPendingRecording) throws
    func replace(
        _ recording: IOSPendingRecording,
        expected: IOSPendingRecording
    ) throws
    func remove(expected: IOSPendingRecording) throws -> Bool
}

/// Canonicalizes runtime dates to the journal's UTC millisecond precision.
enum IOSPendingRecordingTimestampCodec {
    private static let millisecondsPerSecond = 1_000.0

    static func canonicalDate(from date: Date) throws -> Date {
        let seconds = date.timeIntervalSince1970
        let scaled = seconds * millisecondsPerSecond
        guard seconds.isFinite,
              scaled.isFinite,
              scaled >= Double(Int64.min),
              scaled <= Double(Int64.max) else {
            throw IOSPendingRecordingError.invalidJournal
        }

        let milliseconds = Int64(
            scaled.rounded(.toNearestOrAwayFromZero)
        )
        let canonical = Date(
            timeIntervalSince1970: Double(milliseconds) / millisecondsPerSecond
        )
        guard canonical.timeIntervalSinceReferenceDate.isFinite else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return canonical
    }

    static func string(from date: Date) throws -> String {
        let canonical = try canonicalDate(from: date)
        let formatter = makeFormatter()
        let value = formatter.string(from: canonical)
        guard value.utf8.count == 24,
              value.hasSuffix("Z"),
              formatter.date(from: value) == canonical else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return value
    }

    static func date(from value: String) throws -> Date {
        guard value.utf8.count == 24,
              value.hasSuffix("Z") else {
            throw IOSPendingRecordingError.invalidJournal
        }
        let formatter = makeFormatter()
        guard let parsed = formatter.date(from: value),
              formatter.string(from: parsed) == value,
              try canonicalDate(from: parsed) == parsed else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return parsed
    }

    private static func makeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

enum IOSPendingRecordingJournalFileSystemError: Error, Equatable, Sendable {
    case invalidLocation
    case sourceTooLarge
    case missing
    case destinationConflict
    case staleRevision
    case protectedDataUnavailable
    case invalidFile
    case readFailed
    case writeFailed
    case synchronizationFailed
    case commitUncertain
    case removeFailed
}

struct IOSPendingRecordingJournalFileRevision: Equatable, Sendable {
    fileprivate let snapshot: IOSPendingRecordingJournalFileSnapshot?
    private let testingToken: UInt64?

    fileprivate init(snapshot: IOSPendingRecordingJournalFileSnapshot) {
        self.snapshot = snapshot
        testingToken = nil
    }

    /// Narrow seam for repository tests; live commits always use a stat snapshot.
    init(testingToken: UInt64) {
        snapshot = nil
        self.testingToken = testingToken
    }
}

struct IOSPendingRecordingJournalFile: Equatable, Sendable {
    let data: Data
    let revision: IOSPendingRecordingJournalFileRevision
}

protocol IOSPendingRecordingJournalFileSystem: Sendable {
    func readFileIfPresent() throws -> IOSPendingRecordingJournalFile?
    func createFile(with data: Data) throws -> IOSPendingRecordingJournalFileRevision
    func replaceFile(
        with data: Data,
        expected: IOSPendingRecordingJournalFileRevision
    ) throws -> IOSPendingRecordingJournalFileRevision
    func removeFile(
        expected: IOSPendingRecordingJournalFileRevision
    ) throws
}

/// Strict journal repository. All compare-and-swap decisions are made from the
/// same bounded read whose descriptor revision is supplied to the file commit.
struct FoundationIOSPendingRecordingJournalRepository:
    IOSPendingRecordingJournalStoring,
    Sendable {
    static let maximumJournalByteCount = 64 * 1_024

    private let fileSystem: any IOSPendingRecordingJournalFileSystem

    init(applicationSupportDirectoryURL: URL) {
        fileSystem = FoundationIOSPendingRecordingJournalFileSystem(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
    }

    init(fileSystem: any IOSPendingRecordingJournalFileSystem) {
        self.fileSystem = fileSystem
    }

    func load() throws -> IOSPendingRecording? {
        guard let file = try readFile() else {
            return nil
        }
        return try IOSPendingRecordingJournalWireCodec.decode(file.data)
    }

    func create(_ recording: IOSPendingRecording) throws {
        let data = try IOSPendingRecordingJournalWireCodec.encode(recording)
        do {
            _ = try fileSystem.createFile(with: data)
        } catch let error as IOSPendingRecordingJournalFileSystemError {
            throw mapCreateError(error)
        } catch {
            throw IOSPendingRecordingError.journalWriteFailed
        }
    }

    func replace(
        _ recording: IOSPendingRecording,
        expected: IOSPendingRecording
    ) throws {
        guard let currentFile = try readFile() else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        let current = try IOSPendingRecordingJournalWireCodec.decode(
            currentFile.data
        )
        guard current == expected else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }

        let data = try IOSPendingRecordingJournalWireCodec.encode(recording)
        do {
            _ = try fileSystem.replaceFile(
                with: data,
                expected: currentFile.revision
            )
        } catch IOSPendingRecordingJournalFileSystemError.staleRevision,
                IOSPendingRecordingJournalFileSystemError.missing {
            throw IOSPendingRecordingError.compareAndSwapFailed
        } catch IOSPendingRecordingJournalFileSystemError.protectedDataUnavailable {
            throw IOSPendingRecordingError.dataProtectionUnavailable
        } catch IOSPendingRecordingJournalFileSystemError.commitUncertain {
            throw IOSPendingRecordingError.journalCommitUncertain
        } catch {
            throw IOSPendingRecordingError.journalWriteFailed
        }
    }

    func remove(
        expected: IOSPendingRecording
    ) throws -> Bool {
        guard let currentFile = try readFile() else {
            return false
        }
        let current = try IOSPendingRecordingJournalWireCodec.decode(
            currentFile.data
        )
        guard current == expected else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }

        do {
            try fileSystem.removeFile(expected: currentFile.revision)
            return true
        } catch IOSPendingRecordingJournalFileSystemError.staleRevision,
                IOSPendingRecordingJournalFileSystemError.missing {
            throw IOSPendingRecordingError.compareAndSwapFailed
        } catch IOSPendingRecordingJournalFileSystemError.protectedDataUnavailable {
            throw IOSPendingRecordingError.dataProtectionUnavailable
        } catch {
            throw IOSPendingRecordingError.journalRemoveFailed
        }
    }

    private func readFile() throws -> IOSPendingRecordingJournalFile? {
        do {
            return try fileSystem.readFileIfPresent()
        } catch IOSPendingRecordingJournalFileSystemError.sourceTooLarge {
            throw IOSPendingRecordingError.journalTooLarge
        } catch IOSPendingRecordingJournalFileSystemError.protectedDataUnavailable {
            throw IOSPendingRecordingError.dataProtectionUnavailable
        } catch {
            throw IOSPendingRecordingError.journalUnreadable
        }
    }

    private func mapCreateError(
        _ error: IOSPendingRecordingJournalFileSystemError
    ) -> IOSPendingRecordingError {
        switch error {
        case .destinationConflict:
            .pendingSlotOccupied
        case .sourceTooLarge:
            .journalTooLarge
        case .protectedDataUnavailable:
            .dataProtectionUnavailable
        case .commitUncertain:
            .journalCommitUncertain
        default:
            .journalWriteFailed
        }
    }

}

typealias IOSPendingRecordingJournalRepository =
    FoundationIOSPendingRecordingJournalRepository

enum IOSPendingRecordingJournalWireCodec {
    static let supportedSchemaVersion = 1
    static let fields: Set<String> = [
        "schemaVersion",
        "attemptID",
        "audioRelativeIdentifier",
        "createdAt",
        "updatedAt",
        "phase",
        "outputIntent",
        "transcriptionID",
        "transcriptionModel",
        "transcriptionLanguageCode",
        "durationMilliseconds",
        "byteCount",
    ]

    static func encode(_ recording: IOSPendingRecording) throws -> Data {
        let wire = try IOSPendingRecordingJournalWireV1(recording: recording)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let data: Data
        do {
            data = try encoder.encode(wire)
        } catch {
            throw IOSPendingRecordingError.invalidJournal
        }
        guard data.count <= FoundationIOSPendingRecordingJournalRepository
            .maximumJournalByteCount else {
            throw IOSPendingRecordingError.journalTooLarge
        }
        return data
    }

    static func decode(_ data: Data) throws -> IOSPendingRecording {
        do {
            try BoundedJSONMemberValidator.validate(
                data,
                limits: .metadataFile(
                    maximumInputByteCount:
                        FoundationIOSPendingRecordingJournalRepository
                            .maximumJournalByteCount
                )
            )
        } catch BoundedJSONMemberValidationError.inputTooLarge {
            throw IOSPendingRecordingError.journalTooLarge
        } catch {
            throw IOSPendingRecordingError.journalMalformed
        }

        let rootValue: Any
        do {
            rootValue = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw IOSPendingRecordingError.journalMalformed
        }
        guard let object = rootValue as? [String: Any] else {
            throw IOSPendingRecordingError.invalidJournal
        }

        let reader = IOSPendingRecordingJournalObjectReader(object: object)
        let schemaVersion = try reader.integer64("schemaVersion")
        guard schemaVersion == Int64(supportedSchemaVersion) else {
            throw IOSPendingRecordingError.unsupportedJournalVersion
        }
        guard Set(object.keys) == fields else {
            throw IOSPendingRecordingError.invalidJournal
        }

        let attemptID = try canonicalUUID(
            from: reader.string("attemptID")
        )
        let transcriptionIDValue = try reader.nullableString(
            "transcriptionID"
        )
        let transcriptionID = try transcriptionIDValue.map {
            try canonicalUUID(from: $0)
        }
        let phase = try decodePhase(reader.string("phase"))
        let outputIntent = try decodeOutputIntent(
            reader.string("outputIntent")
        )

        do {
            return try IOSPendingRecording(
                attemptID: attemptID,
                audioRelativeIdentifier: reader.string(
                    "audioRelativeIdentifier"
                ),
                createdAt: IOSPendingRecordingTimestampCodec.date(
                    from: reader.string("createdAt")
                ),
                updatedAt: IOSPendingRecordingTimestampCodec.date(
                    from: reader.string("updatedAt")
                ),
                phase: phase,
                outputIntent: outputIntent,
                transcriptionID: transcriptionID,
                transcriptionModel: reader.string("transcriptionModel"),
                transcriptionLanguageCode: reader.nullableString(
                    "transcriptionLanguageCode"
                ),
                durationMilliseconds: reader.integer64(
                    "durationMilliseconds"
                ),
                byteCount: reader.integer64("byteCount")
            )
        } catch {
            throw IOSPendingRecordingError.invalidJournal
        }
    }

    private static func canonicalUUID(from value: String) throws -> UUID {
        guard let identifier = UUID(uuidString: value),
              value == identifier.uuidString.lowercased() else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return identifier
    }

    private static func decodePhase(
        _ value: String
    ) throws -> IOSPendingRecordingPhase {
        switch value {
        case "readyForTranscription": .readyForTranscription
        case "awaitingRecovery": .awaitingRecovery
        case "transcribing": .transcribing
        case "postProcessing": .postProcessing
        case "outputDelivery": .outputDelivery
        default: throw IOSPendingRecordingError.invalidJournal
        }
    }

    private static func decodeOutputIntent(
        _ value: String
    ) throws -> DictationOutputIntent {
        guard let intent = DictationOutputIntent(rawValue: value) else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return intent
    }
}

private struct IOSPendingRecordingJournalObjectReader {
    let object: [String: Any]

    func string(_ key: String) throws -> String {
        guard let value = object[key] as? String else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return value
    }

    func nullableString(_ key: String) throws -> String? {
        guard let value = object[key] else {
            throw IOSPendingRecordingError.invalidJournal
        }
        if value is NSNull {
            return nil
        }
        guard let string = value as? String else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return string
    }

    func integer64(_ key: String) throws -> Int64 {
        guard let value = object[key],
              let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !Self.isFloatingPoint(number),
              let integer = Int64(number.stringValue) else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return integer
    }

    private static func isFloatingPoint(_ number: NSNumber) -> Bool {
        let type = String(cString: number.objCType)
        return type == "f" || type == "d"
    }
}

private struct IOSPendingRecordingJournalWireV1: Encodable {
    let schemaVersion = 1
    let attemptID: String
    let audioRelativeIdentifier: String
    let createdAt: String
    let updatedAt: String
    let phase: String
    let outputIntent: String
    let transcriptionID: String?
    let transcriptionModel: String
    let transcriptionLanguageCode: String?
    let durationMilliseconds: Int64
    let byteCount: Int64

    init(recording: IOSPendingRecording) throws {
        attemptID = recording.attemptID.uuidString.lowercased()
        audioRelativeIdentifier = recording.audioRelativeIdentifier
        createdAt = try IOSPendingRecordingTimestampCodec.string(
            from: recording.createdAt
        )
        updatedAt = try IOSPendingRecordingTimestampCodec.string(
            from: recording.updatedAt
        )
        phase = Self.phaseValue(recording.phase)
        outputIntent = recording.outputIntent.rawValue
        transcriptionID = recording.transcriptionID?.uuidString.lowercased()
        transcriptionModel = recording.transcriptionModel
        transcriptionLanguageCode = recording.transcriptionLanguageCode
        durationMilliseconds = recording.durationMilliseconds
        byteCount = recording.byteCount
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(attemptID, forKey: .attemptID)
        try container.encode(
            audioRelativeIdentifier,
            forKey: .audioRelativeIdentifier
        )
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(phase, forKey: .phase)
        try container.encode(outputIntent, forKey: .outputIntent)
        if let transcriptionID {
            try container.encode(transcriptionID, forKey: .transcriptionID)
        } else {
            try container.encodeNil(forKey: .transcriptionID)
        }
        try container.encode(
            transcriptionModel,
            forKey: .transcriptionModel
        )
        if let transcriptionLanguageCode {
            try container.encode(
                transcriptionLanguageCode,
                forKey: .transcriptionLanguageCode
            )
        } else {
            try container.encodeNil(forKey: .transcriptionLanguageCode)
        }
        try container.encode(
            durationMilliseconds,
            forKey: .durationMilliseconds
        )
        try container.encode(byteCount, forKey: .byteCount)
    }

    private static func phaseValue(
        _ phase: IOSPendingRecordingPhase
    ) -> String {
        switch phase {
        case .readyForTranscription: "readyForTranscription"
        case .awaitingRecovery: "awaitingRecovery"
        case .transcribing: "transcribing"
        case .postProcessing: "postProcessing"
        case .outputDelivery: "outputDelivery"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case attemptID
        case audioRelativeIdentifier
        case createdAt
        case updatedAt
        case phase
        case outputIntent
        case transcriptionID
        case transcriptionModel
        case transcriptionLanguageCode
        case durationMilliseconds
        case byteCount
    }
}

private struct IOSPendingRecordingJournalFileSnapshot: Equatable, Sendable {
    let device: dev_t
    let inode: ino_t
    let byteCount: off_t
    let modificationSeconds: time_t
    let modificationNanoseconds: Int
    let statusChangeSeconds: time_t
    let statusChangeNanoseconds: Int

    init(_ status: stat) {
        device = status.st_dev
        inode = status.st_ino
        byteCount = status.st_size
        modificationSeconds = status.st_mtimespec.tv_sec
        modificationNanoseconds = status.st_mtimespec.tv_nsec
        statusChangeSeconds = status.st_ctimespec.tv_sec
        statusChangeNanoseconds = status.st_ctimespec.tv_nsec
    }
}

/// Descriptor-relative live boundary for the single protected journal file.
/// The destination is never opened through a followed path component.
struct FoundationIOSPendingRecordingJournalFileSystem:
    IOSPendingRecordingJournalFileSystem,
    Sendable {
    private static let processMutationLock = NSLock()
    private static let transferChunkByteCount = 64 * 1_024
    private static let maximumInterruptedRetryCount = 8
    private static let completeProtectionClass: Int32 = 1
    private static let backupExclusionAttributeName =
        "com.apple.metadata:com_apple_backup_excludeItem"
    private static let backupExclusionAttributeValue: [UInt8] = [
        0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30,
        0x5F, 0x10, 0x11, 0x63, 0x6F, 0x6D, 0x2E, 0x61,
        0x70, 0x70, 0x6C, 0x65, 0x2E, 0x62, 0x61, 0x63,
        0x6B, 0x75, 0x70, 0x64, 0x08, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x1C,
    ]

    typealias ReplaceOperation = @Sendable (
        _ directoryDescriptor: Int32,
        _ temporaryName: String,
        _ destinationName: String
    ) -> IOSPendingRecordingPOSIXResult<Void>
    typealias DirectorySynchronizationOperation = @Sendable (
        _ directoryDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void>

    private let applicationSupportDirectoryURL: URL
    private let adapter: any IOSPendingRecordingPOSIXAdapter
    private let replaceOperation: ReplaceOperation
    private let directorySynchronizationOperation:
        DirectorySynchronizationOperation?

    init(
        applicationSupportDirectoryURL: URL,
        adapter: any IOSPendingRecordingPOSIXAdapter =
            DarwinIOSPendingRecordingPOSIXAdapter(),
        replaceOperation: @escaping ReplaceOperation = {
            directoryDescriptor,
            temporaryName,
            destinationName in
            liveIOSPendingRecordingJournalReplace(
                directoryDescriptor: directoryDescriptor,
                temporaryName: temporaryName,
                destinationName: destinationName
            )
        },
        directorySynchronizationOperation:
            DirectorySynchronizationOperation? = nil
    ) {
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
        self.adapter = adapter
        self.replaceOperation = replaceOperation
        self.directorySynchronizationOperation =
            directorySynchronizationOperation
    }

    func readFileIfPresent() throws -> IOSPendingRecordingJournalFile? {
        guard let directory = try openJournalDirectory(createIfMissing: false) else {
            return nil
        }
        defer { close(directory) }
        try validateDirectoryIdentity(directory)

        guard let pathStatus = try statusIfPresent(
            named: IOSPendingRecordingStorageLocation.journalFileName,
            directory: directory,
            failure: .readFailed
        ) else {
            return nil
        }
        try validateJournalStatus(
            pathStatus,
            effectiveUserID: directory.effectiveUserID
        )
        guard pathStatus.st_size >= 0,
              pathStatus.st_size <= off_t(
                  FoundationIOSPendingRecordingJournalRepository
                      .maximumJournalByteCount
              ) else {
            throw IOSPendingRecordingJournalFileSystemError.sourceTooLarge
        }

        let descriptor = try openJournalForReading(directory: directory)
        defer { adapter.closeFile(descriptor) }
        let openedStatus = try status(
            descriptor: descriptor,
            failure: .readFailed
        )
        try validateJournalStatus(
            openedStatus,
            effectiveUserID: directory.effectiveUserID
        )
        guard IOSPendingRecordingJournalFileSnapshot(pathStatus)
                == IOSPendingRecordingJournalFileSnapshot(openedStatus) else {
            throw IOSPendingRecordingJournalFileSystemError.readFailed
        }
        try validateExactConfiguration(descriptor: descriptor)

        let data = try readBoundedData(from: descriptor)
        let finalStatus = try status(
            descriptor: descriptor,
            failure: .readFailed
        )
        try validateJournalStatus(
            finalStatus,
            effectiveUserID: directory.effectiveUserID
        )
        let snapshot = IOSPendingRecordingJournalFileSnapshot(finalStatus)
        guard snapshot == IOSPendingRecordingJournalFileSnapshot(openedStatus),
              finalStatus.st_size == off_t(data.count) else {
            throw IOSPendingRecordingJournalFileSystemError.readFailed
        }
        try validatePathIdentity(
            named: IOSPendingRecordingStorageLocation.journalFileName,
            descriptorStatus: finalStatus,
            directory: directory,
            failure: .readFailed
        )
        try validateDirectoryIdentity(directory)

        return IOSPendingRecordingJournalFile(
            data: data,
            revision: IOSPendingRecordingJournalFileRevision(
                snapshot: snapshot
            )
        )
    }

    func createFile(
        with data: Data
    ) throws -> IOSPendingRecordingJournalFileRevision {
        try validateWriteData(data)
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        guard let directory = try openJournalDirectory(createIfMissing: true) else {
            throw IOSPendingRecordingJournalFileSystemError.writeFailed
        }
        defer { close(directory) }
        try validateDirectoryIdentity(directory)
        try lockDirectoryForMutation(directory)
        try validateDirectoryIdentity(directory)

        if try statusIfPresent(
            named: IOSPendingRecordingStorageLocation.journalFileName,
            directory: directory,
            failure: .writeFailed
        ) != nil {
            throw IOSPendingRecordingJournalFileSystemError.destinationConflict
        }

        return try commitTemporaryFile(
            data: data,
            directory: directory,
            expected: nil,
            createOnly: true
        )
    }

    func replaceFile(
        with data: Data,
        expected: IOSPendingRecordingJournalFileRevision
    ) throws -> IOSPendingRecordingJournalFileRevision {
        try validateWriteData(data)
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        guard let directory = try openJournalDirectory(createIfMissing: false) else {
            throw IOSPendingRecordingJournalFileSystemError.missing
        }
        defer { close(directory) }
        try validateDirectoryIdentity(directory)
        try lockDirectoryForMutation(directory)
        try validateDirectoryIdentity(directory)
        try validateCurrentFile(directory: directory, expected: expected)

        return try commitTemporaryFile(
            data: data,
            directory: directory,
            expected: expected,
            createOnly: false
        )
    }

    func removeFile(
        expected: IOSPendingRecordingJournalFileRevision
    ) throws {
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        guard let directory = try openJournalDirectory(createIfMissing: false) else {
            throw IOSPendingRecordingJournalFileSystemError.missing
        }
        defer { close(directory) }
        try validateDirectoryIdentity(directory)
        try lockDirectoryForMutation(directory)
        try validateDirectoryIdentity(directory)
        try validateCurrentFile(directory: directory, expected: expected)
        try validateDirectoryIdentity(directory)

        let result = retryInterrupted {
            adapter.unlinkAt(
                directoryDescriptor: directory.descriptor,
                name: IOSPendingRecordingStorageLocation.journalFileName
            )
        }
        switch result {
        case .success:
            break
        case .failure(ENOENT):
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.removeFailed
        }

        try synchronizeDirectory(directory.descriptor)
    }
}

private extension FoundationIOSPendingRecordingJournalFileSystem {
    struct DirectoryHandle {
        let parentDescriptor: Int32
        let descriptor: Int32
        let identity: FileIdentity
        let effectiveUserID: uid_t
    }

    struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t

        init(_ status: stat) {
            device = status.st_dev
            inode = status.st_ino
        }
    }

    struct TemporaryFile {
        let name: String
        let descriptor: Int32
        let identity: FileIdentity
    }

    func openJournalDirectory(
        createIfMissing: Bool
    ) throws -> DirectoryHandle? {
        guard applicationSupportDirectoryURL.isFileURL,
              !applicationSupportDirectoryURL.path.isEmpty,
              !applicationSupportDirectoryURL.path.utf8.contains(0) else {
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }

        let effectiveUserID: uid_t
        switch retryInterrupted({ adapter.effectiveUserID() }) {
        case .success(let value):
            effectiveUserID = value
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }

        let parentResult = retryInterrupted {
            adapter.openPath(
                applicationSupportDirectoryURL.path,
                flags: O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW,
                mode: nil
            )
        }
        let parentDescriptor: Int32
        switch parentResult {
        case .success(let value):
            parentDescriptor = value
        case .failure(ENOENT) where !createIfMissing:
            return nil
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }

        var shouldCloseParent = true
        defer {
            if shouldCloseParent {
                adapter.closeFile(parentDescriptor)
            }
        }
        let parentStatus = try status(
            descriptor: parentDescriptor,
            failure: .invalidLocation
        )
        guard isDirectory(parentStatus),
              parentStatus.st_uid == effectiveUserID else {
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }

        let rootName = IOSPendingRecordingStorageLocation.rootDirectoryName
        var createdDirectory = false
        var rootStatus = try directoryStatusIfPresent(
            named: rootName,
            parentDescriptor: parentDescriptor,
            failure: .invalidLocation
        )
        if rootStatus == nil {
            guard createIfMissing else { return nil }
            switch retryInterrupted({
                adapter.makeDirectoryAt(
                    directoryDescriptor: parentDescriptor,
                    name: rootName,
                    mode: 0o700
                )
            }) {
            case .success:
                createdDirectory = true
            case .failure(EEXIST):
                break
            case .failure(let code) where isProtectedDataError(code):
                throw IOSPendingRecordingJournalFileSystemError
                    .protectedDataUnavailable
            case .failure:
                throw IOSPendingRecordingJournalFileSystemError.writeFailed
            }
            rootStatus = try directoryStatusIfPresent(
                named: rootName,
                parentDescriptor: parentDescriptor,
                failure: .invalidLocation
            )
        }

        guard let rootStatus,
              isDirectory(rootStatus),
              rootStatus.st_uid == effectiveUserID else {
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }

        let rootResult = retryInterrupted {
            adapter.openAt(
                directoryDescriptor: parentDescriptor,
                name: rootName,
                flags: O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW,
                mode: nil
            )
        }
        let rootDescriptor: Int32
        switch rootResult {
        case .success(let value):
            rootDescriptor = value
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }
        var shouldCloseRoot = true
        defer {
            if shouldCloseRoot {
                adapter.closeFile(rootDescriptor)
            }
        }

        if createdDirectory {
            try requireSuccess(
                retryInterrupted {
                    adapter.changeMode(
                        fileDescriptor: rootDescriptor,
                        mode: 0o700
                    )
                },
                failure: .writeFailed
            )
        }

        let openedStatus = try status(
            descriptor: rootDescriptor,
            failure: .invalidLocation
        )
        guard isDirectory(openedStatus),
              openedStatus.st_uid == effectiveUserID,
              FileIdentity(openedStatus) == FileIdentity(rootStatus) else {
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }

        if createdDirectory {
            try synchronizeDirectory(rootDescriptor)
            try synchronizeDirectory(parentDescriptor)
        }

        shouldCloseParent = false
        shouldCloseRoot = false
        return DirectoryHandle(
            parentDescriptor: parentDescriptor,
            descriptor: rootDescriptor,
            identity: FileIdentity(openedStatus),
            effectiveUserID: effectiveUserID
        )
    }

    func close(_ directory: DirectoryHandle) {
        adapter.closeFile(directory.descriptor)
        adapter.closeFile(directory.parentDescriptor)
    }

    func lockDirectoryForMutation(_ directory: DirectoryHandle) throws {
        switch retryInterrupted({
            adapter.lock(
                fileDescriptor: directory.descriptor,
                operation: LOCK_EX | LOCK_NB
            )
        }) {
        case .success:
            return
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        }
    }

    func validateDirectoryIdentity(_ directory: DirectoryHandle) throws {
        let descriptorStatus = try status(
            descriptor: directory.descriptor,
            failure: .invalidLocation
        )
        guard isDirectory(descriptorStatus),
              descriptorStatus.st_uid == directory.effectiveUserID,
              FileIdentity(descriptorStatus) == directory.identity,
              let pathStatus = try directoryStatusIfPresent(
                  named: IOSPendingRecordingStorageLocation.rootDirectoryName,
                  parentDescriptor: directory.parentDescriptor,
                  failure: .invalidLocation
              ),
              isDirectory(pathStatus),
              pathStatus.st_uid == directory.effectiveUserID,
              FileIdentity(pathStatus) == directory.identity else {
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }
    }

    func commitTemporaryFile(
        data: Data,
        directory: DirectoryHandle,
        expected: IOSPendingRecordingJournalFileRevision?,
        createOnly: Bool
    ) throws -> IOSPendingRecordingJournalFileRevision {
        let temporary = try createTemporaryFile(directory: directory)
        var shouldRemoveTemporary = true
        defer {
            adapter.closeFile(temporary.descriptor)
            if shouldRemoveTemporary {
                removeTemporaryIfOwned(temporary, directory: directory)
            }
        }

        try validateDirectoryIdentity(directory)
        try configureTemporaryFile(
            temporary,
            directory: directory
        )
        try write(data, to: temporary.descriptor)
        try synchronizeFile(temporary.descriptor)
        try validateOwnedTemporaryFile(
            temporary,
            directory: directory,
            expectedByteCount: data.count
        )
        try validateExactConfiguration(descriptor: temporary.descriptor)
        try validateDirectoryIdentity(directory)

        if let expected {
            try validateCurrentFile(directory: directory, expected: expected)
        } else if try statusIfPresent(
            named: IOSPendingRecordingStorageLocation.journalFileName,
            directory: directory,
            failure: .writeFailed
        ) != nil {
            throw IOSPendingRecordingJournalFileSystemError.destinationConflict
        }

        let prepublishStatus = try status(
            descriptor: temporary.descriptor,
            failure: .writeFailed
        )
        try validateJournalStatus(
            prepublishStatus,
            effectiveUserID: directory.effectiveUserID
        )
        guard prepublishStatus.st_size == off_t(data.count),
              FileIdentity(prepublishStatus) == temporary.identity else {
            throw IOSPendingRecordingJournalFileSystemError.writeFailed
        }

        let publishResult: IOSPendingRecordingPOSIXResult<Void>
        if createOnly {
            publishResult = retryInterrupted {
                adapter.publishExclusively(
                    directoryDescriptor: directory.descriptor,
                    temporaryName: temporary.name,
                    finalName: IOSPendingRecordingStorageLocation.journalFileName
                )
            }
        } else {
            publishResult = retryInterrupted {
                replaceOperation(
                    directory.descriptor,
                    temporary.name,
                    IOSPendingRecordingStorageLocation.journalFileName
                )
            }
        }
        switch publishResult {
        case .success:
            shouldRemoveTemporary = false
        case .failure(EEXIST) where createOnly:
            if finalPathMayReferenceTemporary(
                temporary,
                directory: directory
            ) != false {
                throw IOSPendingRecordingJournalFileSystemError.commitUncertain
            }
            throw IOSPendingRecordingJournalFileSystemError.destinationConflict
        case .failure(ENOENT) where !createOnly:
            if finalPathMayReferenceTemporary(
                temporary,
                directory: directory
            ) != false {
                throw IOSPendingRecordingJournalFileSystemError.commitUncertain
            }
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        case .failure where finalPathMayReferenceTemporary(
            temporary,
            directory: directory
        ) != false:
            throw IOSPendingRecordingJournalFileSystemError.commitUncertain
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.writeFailed
        }

        // Rename makes the new bytes visible. It is not a confirmed durable
        // commit until descriptor/path policy and the containing directory are
        // revalidated and the directory entry is synchronized. Never roll back
        // or clean the visible journal if one of these post-commit steps fails.
        var publishedStatus: stat?
        var postCommitFailed = false
        do {
            let status = try status(
                descriptor: temporary.descriptor,
                failure: .writeFailed
            )
            try validateJournalStatus(
                status,
                effectiveUserID: directory.effectiveUserID
            )
            guard status.st_size == off_t(data.count),
                  FileIdentity(status) == temporary.identity else {
                throw IOSPendingRecordingJournalFileSystemError.writeFailed
            }
            try validatePathIdentity(
                named: IOSPendingRecordingStorageLocation.journalFileName,
                descriptorStatus: status,
                directory: directory,
                failure: .writeFailed
            )
            try validateExactConfiguration(descriptor: temporary.descriptor)
            try validateDirectoryIdentity(directory)
            publishedStatus = status
        } catch {
            postCommitFailed = true
        }

        // Attempt the durability barrier even when an earlier post-rename
        // policy check failed; both outcomes remain commit-uncertain.
        do {
            try synchronizeDirectory(directory.descriptor)
        } catch {
            postCommitFailed = true
        }

        guard !postCommitFailed, let publishedStatus else {
            throw IOSPendingRecordingJournalFileSystemError.commitUncertain
        }
        return IOSPendingRecordingJournalFileRevision(
            snapshot: IOSPendingRecordingJournalFileSnapshot(publishedStatus)
        )
    }

    func finalPathMayReferenceTemporary(
        _ temporary: TemporaryFile,
        directory: DirectoryHandle
    ) -> Bool? {
        do {
            guard let finalStatus = try statusIfPresent(
                named: IOSPendingRecordingStorageLocation.journalFileName,
                directory: directory,
                failure: .writeFailed
            ) else {
                return false
            }
            return FileIdentity(finalStatus) == temporary.identity
        } catch {
            return nil
        }
    }

    func createTemporaryFile(
        directory: DirectoryHandle
    ) throws -> TemporaryFile {
        let name = ".\(IOSPendingRecordingStorageLocation.journalFileName)."
            + UUID().uuidString.lowercased()
            + ".tmp"
        let result = retryInterrupted {
            adapter.openAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode: 0o600
            )
        }
        let descriptor: Int32
        switch result {
        case .success(let value):
            descriptor = value
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.writeFailed
        }

        let initialStatus: stat
        do {
            initialStatus = try status(
                descriptor: descriptor,
                failure: .writeFailed
            )
            guard isRegularFile(initialStatus),
                  initialStatus.st_uid == directory.effectiveUserID,
                  initialStatus.st_nlink == 1,
                  initialStatus.st_size == 0 else {
                throw IOSPendingRecordingJournalFileSystemError.writeFailed
            }
        } catch {
            adapter.closeFile(descriptor)
            throw error
        }

        let temporary = TemporaryFile(
            name: name,
            descriptor: descriptor,
            identity: FileIdentity(initialStatus)
        )
        do {
            try requireSuccess(
                retryInterrupted {
                    adapter.changeMode(
                        fileDescriptor: descriptor,
                        mode: 0o600
                    )
                },
                failure: .writeFailed
            )
            let status = try status(
                descriptor: descriptor,
                failure: .writeFailed
            )
            try validateJournalStatus(
                status,
                effectiveUserID: directory.effectiveUserID
            )
            guard status.st_size == 0 else {
                throw IOSPendingRecordingJournalFileSystemError.writeFailed
            }
            guard FileIdentity(status) == temporary.identity else {
                throw IOSPendingRecordingJournalFileSystemError.writeFailed
            }
            return temporary
        } catch {
            adapter.closeFile(descriptor)
            removeTemporaryIfOwned(temporary, directory: directory)
            throw error
        }
    }

    func configureTemporaryFile(
        _ temporary: TemporaryFile,
        directory: DirectoryHandle
    ) throws {
        try validateOwnedTemporaryFile(
            temporary,
            directory: directory,
            expectedByteCount: 0
        )
        try requireConfigurationSuccess(
            retryInterrupted {
                adapter.setProtectionClass(
                    fileDescriptor: temporary.descriptor,
                    protectionClass: Self.completeProtectionClass
                )
            }
        )
        try requireConfigurationSuccess(
            retryInterrupted {
                adapter.setExtendedAttribute(
                    fileDescriptor: temporary.descriptor,
                    name: Self.backupExclusionAttributeName,
                    value: Self.backupExclusionAttributeValue,
                    flags: 0
                )
            }
        )
        try validateExactConfiguration(descriptor: temporary.descriptor)
        try validateOwnedTemporaryFile(
            temporary,
            directory: directory,
            expectedByteCount: 0
        )
    }

    func validateExactConfiguration(descriptor: Int32) throws {
        let protectionResult = retryInterrupted {
            adapter.protectionClass(fileDescriptor: descriptor)
        }
        switch protectionResult {
        case .success(Self.completeProtectionClass):
            break
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        default:
            throw IOSPendingRecordingJournalFileSystemError.invalidFile
        }

        let backupResult = retryInterrupted {
            adapter.extendedAttribute(
                fileDescriptor: descriptor,
                name: Self.backupExclusionAttributeName,
                maximumByteCount: Self.backupExclusionAttributeValue.count + 1
            )
        }
        switch backupResult {
        case .success(Self.backupExclusionAttributeValue):
            break
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        default:
            throw IOSPendingRecordingJournalFileSystemError.invalidFile
        }
    }

    func validateCurrentFile(
        directory: DirectoryHandle,
        expected: IOSPendingRecordingJournalFileRevision
    ) throws {
        guard let pathStatus = try statusIfPresent(
            named: IOSPendingRecordingStorageLocation.journalFileName,
            directory: directory,
            failure: .writeFailed
        ) else {
            throw IOSPendingRecordingJournalFileSystemError.missing
        }
        try validateJournalStatus(
            pathStatus,
            effectiveUserID: directory.effectiveUserID
        )
        guard let expectedSnapshot = expected.snapshot,
              IOSPendingRecordingJournalFileSnapshot(pathStatus)
                == expectedSnapshot else {
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        }

        let descriptor = try openJournalForReading(directory: directory)
        defer { adapter.closeFile(descriptor) }
        let descriptorStatus = try status(
            descriptor: descriptor,
            failure: .writeFailed
        )
        try validateJournalStatus(
            descriptorStatus,
            effectiveUserID: directory.effectiveUserID
        )
        guard IOSPendingRecordingJournalFileSnapshot(descriptorStatus)
                == expectedSnapshot else {
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        }
        try validateExactConfiguration(descriptor: descriptor)
        try validatePathIdentity(
            named: IOSPendingRecordingStorageLocation.journalFileName,
            descriptorStatus: descriptorStatus,
            directory: directory,
            failure: .writeFailed
        )
    }

    func openJournalForReading(
        directory: DirectoryHandle
    ) throws -> Int32 {
        let result = retryInterrupted {
            adapter.openAt(
                directoryDescriptor: directory.descriptor,
                name: IOSPendingRecordingStorageLocation.journalFileName,
                flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
                mode: nil
            )
        }
        switch result {
        case .success(let descriptor):
            return descriptor
        case .failure(ENOENT):
            throw IOSPendingRecordingJournalFileSystemError.missing
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.readFailed
        }
    }

    func validateOwnedTemporaryFile(
        _ temporary: TemporaryFile,
        directory: DirectoryHandle,
        expectedByteCount: Int
    ) throws {
        let descriptorStatus = try status(
            descriptor: temporary.descriptor,
            failure: .writeFailed
        )
        try validateJournalStatus(
            descriptorStatus,
            effectiveUserID: directory.effectiveUserID
        )
        guard FileIdentity(descriptorStatus) == temporary.identity,
              descriptorStatus.st_size == off_t(expectedByteCount) else {
            throw IOSPendingRecordingJournalFileSystemError.writeFailed
        }
        try validatePathIdentity(
            named: temporary.name,
            descriptorStatus: descriptorStatus,
            directory: directory,
            failure: .writeFailed
        )
    }

    func validatePathIdentity(
        named name: String,
        descriptorStatus: stat,
        directory: DirectoryHandle,
        failure: IOSPendingRecordingJournalFileSystemError
    ) throws {
        guard let pathStatus = try statusIfPresent(
            named: name,
            directory: directory,
            failure: failure
        ) else {
            throw failure
        }
        try validateJournalStatus(
            pathStatus,
            effectiveUserID: directory.effectiveUserID
        )
        guard IOSPendingRecordingJournalFileSnapshot(pathStatus)
                == IOSPendingRecordingJournalFileSnapshot(descriptorStatus) else {
            throw failure
        }
    }

    func validateJournalStatus(
        _ status: stat,
        effectiveUserID: uid_t
    ) throws {
        guard isRegularFile(status),
              status.st_uid == effectiveUserID,
              status.st_nlink == 1,
              status.st_mode & mode_t(0o7777) == mode_t(0o600) else {
            throw IOSPendingRecordingJournalFileSystemError.invalidFile
        }
    }

    func readBoundedData(from descriptor: Int32) throws -> Data {
        let maximumByteCount = FoundationIOSPendingRecordingJournalRepository
            .maximumJournalByteCount
        var data = Data()
        var buffer = [UInt8](
            repeating: 0,
            count: Self.transferChunkByteCount
        )

        while true {
            let remaining = maximumByteCount - data.count
            let requestCount = min(buffer.count, remaining + 1)
            let result = buffer.withUnsafeMutableBytes { bytes in
                retryInterrupted {
                    adapter.read(
                        fileDescriptor: descriptor,
                        buffer: bytes.baseAddress!,
                        byteCount: requestCount
                    )
                }
            }
            switch result {
            case .success(0):
                return data
            case .success(let count) where count > 0 && count <= remaining:
                data.append(contentsOf: buffer.prefix(count))
            case .success:
                throw IOSPendingRecordingJournalFileSystemError.sourceTooLarge
            case .failure(let code) where isProtectedDataError(code):
                throw IOSPendingRecordingJournalFileSystemError
                    .protectedDataUnavailable
            case .failure:
                throw IOSPendingRecordingJournalFileSystemError.readFailed
            }
        }
    }

    func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = min(
                    Self.transferChunkByteCount,
                    bytes.count - offset
                )
                let pointer = bytes.baseAddress!.advanced(by: offset)
                let result = retryInterrupted {
                    adapter.write(
                        fileDescriptor: descriptor,
                        buffer: pointer,
                        byteCount: count
                    )
                }
                switch result {
                case .success(let written) where written > 0 && written <= count:
                    offset += written
                case .failure(let code) where isProtectedDataError(code):
                    throw IOSPendingRecordingJournalFileSystemError
                        .protectedDataUnavailable
                default:
                    throw IOSPendingRecordingJournalFileSystemError.writeFailed
                }
            }
        }
    }

    func validateWriteData(_ data: Data) throws {
        guard !data.isEmpty else {
            throw IOSPendingRecordingJournalFileSystemError.writeFailed
        }
        guard data.count <= FoundationIOSPendingRecordingJournalRepository
            .maximumJournalByteCount else {
            throw IOSPendingRecordingJournalFileSystemError.sourceTooLarge
        }
    }

    func synchronizeFile(_ descriptor: Int32) throws {
        let result = retryInterrupted {
            adapter.synchronize(fileDescriptor: descriptor)
        }
        switch result {
        case .success:
            return
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError
                .synchronizationFailed
        }
    }

    func synchronizeDirectory(_ descriptor: Int32) throws {
        switch retryInterrupted({
            if let directorySynchronizationOperation {
                directorySynchronizationOperation(descriptor)
            } else {
                adapter.synchronize(fileDescriptor: descriptor)
            }
        }) {
        case .success:
            return
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError
                .synchronizationFailed
        }
    }

    func status(
        descriptor: Int32,
        failure: IOSPendingRecordingJournalFileSystemError
    ) throws -> stat {
        switch retryInterrupted({ adapter.status(of: descriptor) }) {
        case .success(let value):
            return value
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw failure
        }
    }

    func statusIfPresent(
        named name: String,
        directory: DirectoryHandle,
        failure: IOSPendingRecordingJournalFileSystemError
    ) throws -> stat? {
        switch retryInterrupted({
            adapter.statusAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }) {
        case .success(let value):
            return value
        case .failure(ENOENT):
            return nil
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw failure
        }
    }

    func directoryStatusIfPresent(
        named name: String,
        parentDescriptor: Int32,
        failure: IOSPendingRecordingJournalFileSystemError
    ) throws -> stat? {
        switch retryInterrupted({
            adapter.statusAt(
                directoryDescriptor: parentDescriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }) {
        case .success(let value):
            return value
        case .failure(ENOENT):
            return nil
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw failure
        }
    }

    func removeTemporaryIfOwned(
        _ temporary: TemporaryFile,
        directory: DirectoryHandle
    ) {
        guard case .success(let pathStatus) = retryInterrupted({
            adapter.statusAt(
                directoryDescriptor: directory.descriptor,
                name: temporary.name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }),
        FileIdentity(pathStatus) == temporary.identity else {
            return
        }
        _ = retryInterrupted {
            adapter.unlinkAt(
                directoryDescriptor: directory.descriptor,
                name: temporary.name
            )
        }
    }

    func requireSuccess<Value>(
        _ result: IOSPendingRecordingPOSIXResult<Value>,
        failure: IOSPendingRecordingJournalFileSystemError
    ) throws {
        switch result {
        case .success:
            return
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw failure
        }
    }

    func requireConfigurationSuccess<Value>(
        _ result: IOSPendingRecordingPOSIXResult<Value>
    ) throws {
        switch result {
        case .success:
            return
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.invalidFile
        }
    }

    func retryInterrupted<Value>(
        _ operation: () -> IOSPendingRecordingPOSIXResult<Value>
    ) -> IOSPendingRecordingPOSIXResult<Value> {
        var interruptionCount = 0
        while true {
            let result = operation()
            guard case .failure(EINTR) = result,
                  interruptionCount < Self.maximumInterruptedRetryCount else {
                return result
            }
            interruptionCount += 1
        }
    }

    func isRegularFile(_ status: stat) -> Bool {
        status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
    }

    func isDirectory(_ status: stat) -> Bool {
        status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
    }

    func isProtectedDataError(_ code: Int32) -> Bool {
        code == EACCES || code == EPERM
    }
}

private func liveIOSPendingRecordingJournalReplace(
    directoryDescriptor: Int32,
    temporaryName: String,
    destinationName: String
) -> IOSPendingRecordingPOSIXResult<Void> {
    let result = temporaryName.withCString { temporaryName in
        destinationName.withCString { destinationName in
            Darwin.renameat(
                directoryDescriptor,
                temporaryName,
                directoryDescriptor,
                destinationName
            )
        }
    }
    return result == 0 ? .success(()) : .failure(errno)
}
