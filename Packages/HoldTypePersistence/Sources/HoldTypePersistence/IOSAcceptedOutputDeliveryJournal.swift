import CoreFoundation
import Darwin
import Foundation
import HoldTypeDomain

struct IOSAcceptedOutputDeliveryJournalSnapshot: Equatable, Sendable {
    let record: IOSAcceptedOutputDeliveryRecord
    let fileRevision: IOSStrictProtectedRecordFileRevision
}

struct IOSAcceptedOutputDeliveryOpaqueSnapshot: Sendable {
    let fileRevision: IOSStrictProtectedRecordFileRevision
}

protocol IOSAcceptedOutputDeliveryJournalStoring: Sendable {
    func load() throws -> IOSAcceptedOutputDeliveryJournalSnapshot?
    func loadOpaque() throws -> IOSAcceptedOutputDeliveryOpaqueSnapshot?
    func create(
        _ record: IOSAcceptedOutputDeliveryRecord
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot
    func replace(
        _ record: IOSAcceptedOutputDeliveryRecord,
        expected: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot
    func remove(expected: IOSAcceptedOutputDeliveryJournalSnapshot) throws
    func removeOpaque(expected: IOSAcceptedOutputDeliveryOpaqueSnapshot) throws
    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport
}

enum IOSAcceptedOutputDeliveryJournal {
    static let maximumByteCount = 1_048_576
}

struct FoundationIOSAcceptedOutputDeliveryJournalRepository:
    IOSAcceptedOutputDeliveryJournalStoring,
    Sendable {
    private let fileSystem: any IOSStrictProtectedRecordFileSystem
    private let stagingMaintenance: @Sendable (Date) throws
        -> IOSStrictProtectedRecordMaintenanceReport

    init(
        applicationSupportDirectoryURL: URL,
        repositoryGuard:
            IOSAcceptedHistoryCoordinatorRepositoryGuard? = nil
    ) {
        let fileSystem = FoundationIOSStrictProtectedRecordFileSystem(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            configuration: .acceptedOutputDelivery,
            adapter: IOSAcceptedOutputDeliveryMarkerPOSIXAdapter(),
            expectedRepositoryRoot:
                repositoryGuard?.expectedPhysicalRootIdentity,
            onRepositoryIdentityMismatch: {
                repositoryGuard?.invalidate()
            }
        )
        self.fileSystem = fileSystem
        stagingMaintenance = { now in
            try fileSystem.removeAbandonedTemporaryFiles(now: now)
        }
    }

    init(
        fileSystem: any IOSStrictProtectedRecordFileSystem,
        stagingMaintenance: @escaping @Sendable (Date) throws
            -> IOSStrictProtectedRecordMaintenanceReport = { _ in .empty }
    ) {
        self.fileSystem = fileSystem
        self.stagingMaintenance = stagingMaintenance
    }

    func load() throws -> IOSAcceptedOutputDeliveryJournalSnapshot? {
        guard let file = try readFile() else { return nil }
        return IOSAcceptedOutputDeliveryJournalSnapshot(
            record: try IOSAcceptedOutputDeliveryWireCodec.decode(file.data),
            fileRevision: file.revision
        )
    }

    func loadOpaque() throws -> IOSAcceptedOutputDeliveryOpaqueSnapshot? {
        do {
            guard let revision = try fileSystem
                .readOpaqueFileRevisionIfPresent() else {
                return nil
            }
            return IOSAcceptedOutputDeliveryOpaqueSnapshot(
                fileRevision: revision
            )
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable {
            throw IOSAcceptedOutputDeliveryError.dataProtectionUnavailable
        } catch {
            throw IOSAcceptedOutputDeliveryError.readFailed
        }
    }

    func create(
        _ record: IOSAcceptedOutputDeliveryRecord
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        let data = try IOSAcceptedOutputDeliveryWireCodec.encode(record)
        do {
            let revision = try fileSystem.createFile(with: data)
            return IOSAcceptedOutputDeliveryJournalSnapshot(
                record: record,
                fileRevision: revision
            )
        } catch IOSStrictProtectedRecordFileSystemError.destinationConflict {
            throw IOSAcceptedOutputDeliveryError.slotOccupied
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable {
            throw IOSAcceptedOutputDeliveryError.dataProtectionUnavailable
        } catch IOSStrictProtectedRecordFileSystemError.commitUncertain {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        } catch IOSStrictProtectedRecordFileSystemError.sourceTooLarge {
            throw IOSAcceptedOutputDeliveryError.writeFailed
        } catch {
            throw IOSAcceptedOutputDeliveryError.writeFailed
        }
    }

    func replace(
        _ record: IOSAcceptedOutputDeliveryRecord,
        expected: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        let data = try IOSAcceptedOutputDeliveryWireCodec.encode(record)
        do {
            let revision = try fileSystem.replaceFile(
                with: data,
                expected: expected.fileRevision
            )
            return IOSAcceptedOutputDeliveryJournalSnapshot(
                record: record,
                fileRevision: revision
            )
        } catch IOSStrictProtectedRecordFileSystemError.staleRevision,
                IOSStrictProtectedRecordFileSystemError.missing {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable {
            throw IOSAcceptedOutputDeliveryError.dataProtectionUnavailable
        } catch IOSStrictProtectedRecordFileSystemError.commitUncertain {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        } catch {
            throw IOSAcceptedOutputDeliveryError.writeFailed
        }
    }

    func remove(expected: IOSAcceptedOutputDeliveryJournalSnapshot) throws {
        try removeFile(expected: expected.fileRevision)
    }

    func removeOpaque(
        expected: IOSAcceptedOutputDeliveryOpaqueSnapshot
    ) throws {
        do {
            try fileSystem.removeOpaqueFile(expected: expected.fileRevision)
        } catch IOSStrictProtectedRecordFileSystemError.staleRevision,
                IOSStrictProtectedRecordFileSystemError.missing {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable {
            throw IOSAcceptedOutputDeliveryError.dataProtectionUnavailable
        } catch IOSStrictProtectedRecordFileSystemError.synchronizationFailed {
            throw IOSAcceptedOutputDeliveryError.removalCommitUncertain
        } catch {
            throw IOSAcceptedOutputDeliveryError.removeFailed
        }
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        do {
            return try stagingMaintenance(now)
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable {
            throw IOSAcceptedOutputDeliveryError.dataProtectionUnavailable
        } catch IOSStrictProtectedRecordFileSystemError.synchronizationFailed {
            throw IOSAcceptedOutputDeliveryError.removalCommitUncertain
        } catch {
            throw IOSAcceptedOutputDeliveryError.removeFailed
        }
    }

    private func readFile() throws -> IOSStrictProtectedRecordFile? {
        do {
            return try fileSystem.readFileIfPresent()
        } catch IOSStrictProtectedRecordFileSystemError.sourceTooLarge {
            throw IOSAcceptedOutputDeliveryError.sourceTooLarge
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable {
            throw IOSAcceptedOutputDeliveryError.dataProtectionUnavailable
        } catch {
            throw IOSAcceptedOutputDeliveryError.readFailed
        }
    }

    private func removeFile(
        expected: IOSStrictProtectedRecordFileRevision
    ) throws {
        do {
            try fileSystem.removeFile(expected: expected)
        } catch IOSStrictProtectedRecordFileSystemError.staleRevision,
                IOSStrictProtectedRecordFileSystemError.missing {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable {
            throw IOSAcceptedOutputDeliveryError.dataProtectionUnavailable
        } catch IOSStrictProtectedRecordFileSystemError.synchronizationFailed {
            throw IOSAcceptedOutputDeliveryError.removalCommitUncertain
        } catch {
            throw IOSAcceptedOutputDeliveryError.removeFailed
        }
    }
}

enum IOSAcceptedOutputDeliveryWireCodec {
    static let supportedSchemaVersions: Set<Int64> = [1, 2]
    static let fields: Set<String> = [
        "schemaVersion",
        "revision",
        "deliveryID",
        "sessionID",
        "attemptID",
        "transcriptID",
        "acceptedText",
        "outputIntent",
        "createdAt",
        "updatedAt",
        "expiresAt",
        "deliveryState",
        "automaticInsertionPreferenceEnabled",
        "keepLatestResult",
        "publicationGeneration",
        "historyWrite",
    ]
    static let failedRetryFields = fields.union(["failedRetryID"])
    static let historyFields: Set<String> = [
        "state",
        "policyGeneration",
        "transcriptionModel",
        "transcriptionLanguageCode",
        "durationMilliseconds",
    ]

    static func encode(_ record: IOSAcceptedOutputDeliveryRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(
                IOSAcceptedOutputDeliveryWireRecord(record: record)
            )
        } catch {
            throw IOSAcceptedOutputDeliveryError.writeFailed
        }
        guard data.count <= IOSAcceptedOutputDeliveryJournal.maximumByteCount else {
            throw IOSAcceptedOutputDeliveryError.writeFailed
        }
        return data
    }

    static func decode(_ data: Data) throws -> IOSAcceptedOutputDeliveryRecord {
        do {
            try BoundedJSONMemberValidator.validate(
                data,
                limits: BoundedJSONMemberValidationLimits(
                    maximumInputByteCount:
                        IOSAcceptedOutputDeliveryJournal.maximumByteCount,
                    maximumNestingDepth: 2,
                    maximumMembersPerObject: 32,
                    maximumTotalObjectMembers: 64,
                    maximumElementsPerArray: 0,
                    maximumTotalValues: 65,
                    maximumDecodedKeyByteCount: 64,
                    maximumDecodedValueStringByteCount:
                        IOSAcceptedOutputDeliveryValidation
                            .maximumAcceptedTextByteCount,
                    maximumNumberTokenByteCount: 20
                )
            )
        } catch BoundedJSONMemberValidationError.inputTooLarge {
            throw IOSAcceptedOutputDeliveryError.sourceTooLarge
        } catch {
            throw IOSAcceptedOutputDeliveryError.malformedData
        }

        let root: Any
        do {
            root = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw IOSAcceptedOutputDeliveryError.malformedData
        }
        guard let object = root as? [String: Any] else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        let reader = IOSAcceptedOutputDeliveryObjectReader(object: object)
        let schemaVersion = try reader.integer64("schemaVersion")
        guard supportedSchemaVersions.contains(schemaVersion) else {
            throw IOSAcceptedOutputDeliveryError.unsupportedSchemaVersion
        }
        let expectedFields = schemaVersion == 1 ? fields : failedRetryFields
        guard Set(object.keys) == expectedFields else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }

        let marker: IOSAcceptedOutputHistoryWrite?
        if let markerObject = try reader.nullableObject("historyWrite") {
            guard Set(markerObject.keys) == historyFields else {
                throw IOSAcceptedOutputDeliveryError.invalidRecord
            }
            let markerReader = IOSAcceptedOutputDeliveryObjectReader(
                object: markerObject
            )
            do {
                let encodedModel = try markerReader.string(
                    "transcriptionModel"
                )
                marker = try IOSAcceptedOutputHistoryWrite(
                    state: decodeHistoryState(markerReader.string("state")),
                    policyGeneration: markerReader.integer64(
                        "policyGeneration"
                    ),
                    transcriptionModel: encodedModel,
                    transcriptionLanguageCode: markerReader.nullableString(
                        "transcriptionLanguageCode"
                    ),
                    durationMilliseconds: markerReader.nullableInteger64(
                        "durationMilliseconds"
                    )
                )
                guard marker.map({
                    IOSAcceptedOutputDeliveryValidation.bytesEqual(
                        $0.transcriptionModel,
                        encodedModel
                    )
                }) == true else {
                    throw IOSAcceptedOutputDeliveryError.invalidRecord
                }
            } catch {
                throw IOSAcceptedOutputDeliveryError.invalidRecord
            }
        } else {
            marker = nil
        }

        do {
            return try IOSAcceptedOutputDeliveryRecord(
                revision: reader.integer64("revision"),
                deliveryID: canonicalUUID(reader.string("deliveryID")),
                sessionID: canonicalUUID(reader.string("sessionID")),
                attemptID: canonicalUUID(reader.string("attemptID")),
                transcriptID: canonicalUUID(reader.string("transcriptID")),
                failedRetryID: schemaVersion == 2
                    ? canonicalUUID(reader.string("failedRetryID"))
                    : nil,
                acceptedText: reader.nullableString("acceptedText"),
                outputIntent: decodeOutputIntent(reader.string("outputIntent")),
                createdAt: IOSAcceptedOutputDeliveryTimestampCodec.date(
                    from: reader.string("createdAt")
                ),
                updatedAt: IOSAcceptedOutputDeliveryTimestampCodec.date(
                    from: reader.string("updatedAt")
                ),
                expiresAt: IOSAcceptedOutputDeliveryTimestampCodec.date(
                    from: reader.string("expiresAt")
                ),
                deliveryState: decodeDeliveryState(
                    reader.string("deliveryState")
                ),
                automaticInsertionPreferenceEnabled: reader.boolean(
                    "automaticInsertionPreferenceEnabled"
                ),
                keepLatestResult: reader.boolean("keepLatestResult"),
                publicationGeneration: reader.integer64(
                    "publicationGeneration"
                ),
                historyWrite: marker
            )
        } catch IOSAcceptedOutputDeliveryError.unsupportedSchemaVersion {
            throw IOSAcceptedOutputDeliveryError.unsupportedSchemaVersion
        } catch {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
    }

    private static func canonicalUUID(_ value: String) throws -> UUID {
        guard let identifier = UUID(uuidString: value),
              value == identifier.uuidString.lowercased() else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        return identifier
    }

    private static func decodeOutputIntent(
        _ value: String
    ) throws -> DictationOutputIntent {
        guard let intent = DictationOutputIntent(rawValue: value) else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        return intent
    }

    private static func decodeDeliveryState(
        _ value: String
    ) throws -> IOSAcceptedOutputDeliveryState {
        switch value {
        case "pending": .pending
        case "confirmedInserted": .confirmedInserted
        case "submittedUnverified": .submittedUnverified
        case "discarded": .discarded
        default: throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
    }

    private static func decodeHistoryState(
        _ value: String
    ) throws -> IOSAcceptedOutputHistoryWriteState {
        switch value {
        case "pending": .pending
        case "pendingReplacement": .pendingReplacement
        case "committed": .committed
        case "cancelled": .cancelled
        default: throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
    }
}

private struct IOSAcceptedOutputDeliveryObjectReader {
    let object: [String: Any]

    func string(_ key: String) throws -> String {
        guard let value = object[key] as? String else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        return value
    }

    func nullableString(_ key: String) throws -> String? {
        guard let value = object[key] else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        if value is NSNull { return nil }
        guard let value = value as? String else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        return value
    }

    func boolean(_ key: String) throws -> Bool {
        guard let value = object[key] as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        return value.boolValue
    }

    func integer64(_ key: String) throws -> Int64 {
        guard let value = object[key] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              !Self.isFloatingPoint(value),
              let integer = Int64(value.stringValue) else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        return integer
    }

    func nullableInteger64(_ key: String) throws -> Int64? {
        guard let value = object[key] else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        if value is NSNull { return nil }
        return try integer64(key)
    }

    func nullableObject(_ key: String) throws -> [String: Any]? {
        guard let value = object[key] else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        if value is NSNull { return nil }
        guard let value = value as? [String: Any] else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        return value
    }

    private static func isFloatingPoint(_ number: NSNumber) -> Bool {
        let type = String(cString: number.objCType)
        return type == "f" || type == "d"
    }
}

private struct IOSAcceptedOutputDeliveryWireRecord: Encodable {
    let schemaVersion: Int
    let revision: Int64
    let deliveryID: String
    let sessionID: String
    let attemptID: String
    let transcriptID: String
    let failedRetryID: String?
    let acceptedText: String?
    let outputIntent: String
    let createdAt: String
    let updatedAt: String
    let expiresAt: String
    let deliveryState: String
    let automaticInsertionPreferenceEnabled: Bool
    let keepLatestResult: Bool
    let publicationGeneration: Int64
    private let historyWrite: HistoryWrite?

    init(record: IOSAcceptedOutputDeliveryRecord) throws {
        schemaVersion = record.failedRetryID == nil ? 1 : 2
        revision = record.revision
        deliveryID = record.deliveryID.uuidString.lowercased()
        sessionID = record.sessionID.uuidString.lowercased()
        attemptID = record.attemptID.uuidString.lowercased()
        transcriptID = record.transcriptID.uuidString.lowercased()
        failedRetryID = record.failedRetryID?.uuidString.lowercased()
        acceptedText = record.acceptedText
        outputIntent = record.outputIntent.rawValue
        createdAt = try IOSAcceptedOutputDeliveryTimestampCodec.string(
            from: record.createdAt
        )
        updatedAt = try IOSAcceptedOutputDeliveryTimestampCodec.string(
            from: record.updatedAt
        )
        expiresAt = try IOSAcceptedOutputDeliveryTimestampCodec.string(
            from: record.expiresAt
        )
        deliveryState = switch record.deliveryState {
        case .pending: "pending"
        case .confirmedInserted: "confirmedInserted"
        case .submittedUnverified: "submittedUnverified"
        case .discarded: "discarded"
        }
        automaticInsertionPreferenceEnabled =
            record.automaticInsertionPreferenceEnabled
        keepLatestResult = record.keepLatestResult
        publicationGeneration = record.publicationGeneration
        historyWrite = record.historyWrite.map(HistoryWrite.init)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(revision, forKey: .revision)
        try container.encode(deliveryID, forKey: .deliveryID)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(attemptID, forKey: .attemptID)
        try container.encode(transcriptID, forKey: .transcriptID)
        if schemaVersion == 2 {
            try container.encode(
                failedRetryID,
                forKey: .failedRetryID
            )
        }
        if let acceptedText {
            try container.encode(acceptedText, forKey: .acceptedText)
        } else {
            try container.encodeNil(forKey: .acceptedText)
        }
        try container.encode(outputIntent, forKey: .outputIntent)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(deliveryState, forKey: .deliveryState)
        try container.encode(
            automaticInsertionPreferenceEnabled,
            forKey: .automaticInsertionPreferenceEnabled
        )
        try container.encode(keepLatestResult, forKey: .keepLatestResult)
        try container.encode(
            publicationGeneration,
            forKey: .publicationGeneration
        )
        if let historyWrite {
            try container.encode(
                historyWrite,
                forKey: .historyWrite
            )
        } else {
            try container.encodeNil(forKey: .historyWrite)
        }
    }

    private struct HistoryWrite: Encodable {
        let state: String
        let policyGeneration: Int64
        let transcriptionModel: String
        let transcriptionLanguageCode: String?
        let durationMilliseconds: Int64?

        init(_ marker: IOSAcceptedOutputHistoryWrite) {
            state = switch marker.state {
            case .pending: "pending"
            case .pendingReplacement: "pendingReplacement"
            case .committed: "committed"
            case .cancelled: "cancelled"
            }
            policyGeneration = marker.policyGeneration
            transcriptionModel = marker.transcriptionModel
            transcriptionLanguageCode = marker.transcriptionLanguageCode
            durationMilliseconds = marker.durationMilliseconds
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(state, forKey: .state)
            try container.encode(
                policyGeneration,
                forKey: .policyGeneration
            )
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
            if let durationMilliseconds {
                try container.encode(
                    durationMilliseconds,
                    forKey: .durationMilliseconds
                )
            } else {
                try container.encodeNil(forKey: .durationMilliseconds)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case state
            case policyGeneration
            case transcriptionModel
            case transcriptionLanguageCode
            case durationMilliseconds
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case revision
        case deliveryID
        case sessionID
        case attemptID
        case transcriptID
        case failedRetryID
        case acceptedText
        case outputIntent
        case createdAt
        case updatedAt
        case expiresAt
        case deliveryState
        case automaticInsertionPreferenceEnabled
        case keepLatestResult
        case publicationGeneration
        case historyWrite
    }
}

private struct IOSAcceptedOutputDeliveryMarkerPOSIXAdapter:
    IOSPendingRecordingPOSIXAdapter {
    private let base = DarwinIOSPendingRecordingPOSIXAdapter()

    func effectiveUserID() -> IOSPendingRecordingPOSIXResult<uid_t> {
        base.effectiveUserID()
    }

    func openPath(_ path: String, flags: Int32, mode: mode_t?)
        -> IOSPendingRecordingPOSIXResult<Int32> {
        base.openPath(path, flags: flags, mode: mode)
    }

    func openAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32,
        mode: mode_t?
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        base.openAt(
            directoryDescriptor: directoryDescriptor,
            name: name,
            flags: flags,
            mode: mode
        )
    }

    func makeDirectoryAt(
        directoryDescriptor: Int32,
        name: String,
        mode: mode_t
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.makeDirectoryAt(
            directoryDescriptor: directoryDescriptor,
            name: name,
            mode: mode
        )
    }

    func status(of fileDescriptor: Int32) -> IOSPendingRecordingPOSIXResult<stat> {
        base.status(of: fileDescriptor)
    }

    func statusAtPath(_ path: String) -> IOSPendingRecordingPOSIXResult<stat> {
        base.statusAtPath(path)
    }

    func statusAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<stat> {
        base.statusAt(
            directoryDescriptor: directoryDescriptor,
            name: name,
            flags: flags
        )
    }

    func read(
        fileDescriptor: Int32,
        buffer: UnsafeMutableRawPointer,
        byteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        base.read(
            fileDescriptor: fileDescriptor,
            buffer: buffer,
            byteCount: byteCount
        )
    }

    func write(
        fileDescriptor: Int32,
        buffer: UnsafeRawPointer,
        byteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        base.write(
            fileDescriptor: fileDescriptor,
            buffer: buffer,
            byteCount: byteCount
        )
    }

    func synchronize(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.synchronize(fileDescriptor: fileDescriptor)
    }

    func changeMode(
        fileDescriptor: Int32,
        mode: mode_t
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.changeMode(fileDescriptor: fileDescriptor, mode: mode)
    }

    func lock(
        fileDescriptor: Int32,
        operation: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.lock(fileDescriptor: fileDescriptor, operation: operation)
    }

    func setExtendedAttribute(
        fileDescriptor: Int32,
        name: String,
        value: [UInt8],
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        let markerName = IOSStrictProtectedRecordConfiguration
            .acceptedOutputDelivery.marker?.name
        return base.setExtendedAttribute(
            fileDescriptor: fileDescriptor,
            name: name,
            value: value,
            flags: name == markerName ? Int32(XATTR_CREATE) : flags
        )
    }

    func extendedAttribute(
        fileDescriptor: Int32,
        name: String,
        maximumByteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<[UInt8]> {
        base.extendedAttribute(
            fileDescriptor: fileDescriptor,
            name: name,
            maximumByteCount: maximumByteCount
        )
    }

    func setProtectionClass(
        fileDescriptor: Int32,
        protectionClass: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.setProtectionClass(
            fileDescriptor: fileDescriptor,
            protectionClass: protectionClass
        )
    }

    func protectionClass(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        base.protectionClass(fileDescriptor: fileDescriptor)
    }

    func publishExclusively(
        directoryDescriptor: Int32,
        temporaryName: String,
        finalName: String
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.publishExclusively(
            directoryDescriptor: directoryDescriptor,
            temporaryName: temporaryName,
            finalName: finalName
        )
    }

    func unlinkAt(
        directoryDescriptor: Int32,
        name: String
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.unlinkAt(directoryDescriptor: directoryDescriptor, name: name)
    }

    func openDirectoryStream(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<UnsafeMutablePointer<DIR>> {
        base.openDirectoryStream(fileDescriptor: fileDescriptor)
    }

    func nextDirectoryEntry(
        stream: UnsafeMutablePointer<DIR>
    ) -> IOSPendingRecordingPOSIXResult<IOSPendingRecordingDirectoryEntry?> {
        base.nextDirectoryEntry(stream: stream)
    }

    func closeFile(_ fileDescriptor: Int32) {
        base.closeFile(fileDescriptor)
    }

    func closeDirectoryStream(_ stream: UnsafeMutablePointer<DIR>) {
        base.closeDirectoryStream(stream)
    }
}
