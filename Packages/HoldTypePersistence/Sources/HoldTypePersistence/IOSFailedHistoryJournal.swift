import CoreFoundation
import Foundation
import HoldTypeDomain

struct IOSFailedHistoryJournalSnapshot: Equatable, Sendable {
    let envelope: IOSFailedHistoryEnvelope
    let fileRevision: IOSStrictProtectedRecordFileRevision
}

protocol IOSFailedHistoryJournalStoring: Sendable {
    func load() throws -> IOSFailedHistoryJournalSnapshot?
    func create(
        _ envelope: IOSFailedHistoryEnvelope,
        authorization: IOSFailedHistoryJournalMutationAuthorization
    ) throws -> IOSFailedHistoryJournalSnapshot
    func replace(
        _ envelope: IOSFailedHistoryEnvelope,
        expected: IOSFailedHistoryJournalSnapshot,
        authorization: IOSFailedHistoryJournalMutationAuthorization
    ) throws -> IOSFailedHistoryJournalSnapshot
    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport
}

enum IOSFailedHistoryJournal {
    static let maximumByteCount = 1_048_576
}

struct FoundationIOSFailedHistoryJournalRepository:
    IOSFailedHistoryJournalStoring,
    Sendable {
    private let fileSystem: any IOSStrictProtectedRecordFileSystem
    private let stagingMaintenance: @Sendable (Date) throws
        -> IOSStrictProtectedRecordMaintenanceReport

    init(applicationSupportDirectoryURL: URL) {
        let fileSystem = FoundationIOSStrictProtectedRecordFileSystem(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            configuration: .failedHistory
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

    func load() throws -> IOSFailedHistoryJournalSnapshot? {
        guard let file = try readFile() else { return nil }
        return IOSFailedHistoryJournalSnapshot(
            envelope: try IOSFailedHistoryWireCodec.decode(file.data),
            fileRevision: file.revision
        )
    }

    func create(
        _ envelope: IOSFailedHistoryEnvelope,
        authorization: IOSFailedHistoryJournalMutationAuthorization
    ) throws -> IOSFailedHistoryJournalSnapshot {
        _ = authorization
        let data = try IOSFailedHistoryWireCodec.encode(envelope)
        do {
            let revision = try fileSystem.createFile(with: data)
            return IOSFailedHistoryJournalSnapshot(
                envelope: envelope,
                fileRevision: revision
            )
        } catch IOSStrictProtectedRecordFileSystemError.destinationConflict {
            throw IOSFailedHistoryError.slotOccupied
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable {
            throw IOSFailedHistoryError.dataProtectionUnavailable
        } catch IOSStrictProtectedRecordFileSystemError.commitUncertain {
            throw IOSFailedHistoryError.commitUncertain
        } catch {
            throw IOSFailedHistoryError.writeFailed
        }
    }

    func replace(
        _ envelope: IOSFailedHistoryEnvelope,
        expected: IOSFailedHistoryJournalSnapshot,
        authorization: IOSFailedHistoryJournalMutationAuthorization
    ) throws -> IOSFailedHistoryJournalSnapshot {
        _ = authorization
        let data = try IOSFailedHistoryWireCodec.encode(envelope)
        do {
            let revision = try fileSystem.replaceFile(
                with: data,
                expected: expected.fileRevision
            )
            return IOSFailedHistoryJournalSnapshot(
                envelope: envelope,
                fileRevision: revision
            )
        } catch IOSStrictProtectedRecordFileSystemError.staleRevision,
                IOSStrictProtectedRecordFileSystemError.missing {
            throw IOSFailedHistoryError.compareAndSwapFailed
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable {
            throw IOSFailedHistoryError.dataProtectionUnavailable
        } catch IOSStrictProtectedRecordFileSystemError.commitUncertain {
            throw IOSFailedHistoryError.commitUncertain
        } catch {
            throw IOSFailedHistoryError.writeFailed
        }
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        do {
            return try stagingMaintenance(now)
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable {
            throw IOSFailedHistoryError.dataProtectionUnavailable
        } catch {
            throw IOSFailedHistoryError.maintenanceFailed
        }
    }

    private func readFile() throws -> IOSStrictProtectedRecordFile? {
        do {
            return try fileSystem.readFileIfPresent()
        } catch IOSStrictProtectedRecordFileSystemError.sourceTooLarge {
            throw IOSFailedHistoryError.sourceTooLarge
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable {
            throw IOSFailedHistoryError.dataProtectionUnavailable
        } catch {
            throw IOSFailedHistoryError.readFailed
        }
    }
}

enum IOSFailedHistoryWireCodec {
    private static let supportedSchemaVersion: Int64 = 1
    private static let rootFields: Set<String> = [
        "schemaVersion",
        "revision",
        "entries",
        "audioCleanup",
    ]
    private static let entryFields: Set<String> = [
        "attemptID",
        "createdAt",
        "updatedAt",
        "policyGeneration",
        "failureCategory",
        "pipelineStage",
        "retryCount",
        "outputIntent",
        "transcriptionModel",
        "transcriptionLanguageCode",
        "durationMilliseconds",
        "byteCount",
        "audioRelativeIdentifier",
        "ownershipState",
        "retryOperation",
    ]
    private static let retryOperationFields: Set<String> = [
        "retryID",
        "createdAt",
        "transcriptionID",
        "deliveryID",
        "sessionID",
        "transcriptID",
        "state",
    ]
    private static let audioCleanupFields: Set<String> = [
        "attemptID",
        "policyGeneration",
        "queuedAt",
        "audioRelativeIdentifier",
        "byteCount",
    ]

    static func encode(_ envelope: IOSFailedHistoryEnvelope) throws -> Data {
        let data = try encodedData(envelope)
        guard data.count <= IOSFailedHistoryJournal.maximumByteCount else {
            throw IOSFailedHistoryError.writeFailed
        }
        return data
    }

    static func isWithinEncodedLimit(
        _ envelope: IOSFailedHistoryEnvelope
    ) throws -> Bool {
        try encodedData(envelope).count
            <= IOSFailedHistoryJournal.maximumByteCount
    }

    static func decode(_ data: Data) throws -> IOSFailedHistoryEnvelope {
        do {
            try BoundedJSONMemberValidator.validate(
                data,
                limits: BoundedJSONMemberValidationLimits(
                    maximumInputByteCount:
                        IOSFailedHistoryJournal.maximumByteCount,
                    maximumNestingDepth: 5,
                    maximumMembersPerObject: 32,
                    maximumTotalObjectMembers: 160,
                    maximumElementsPerArray: 8,
                    maximumTotalValues: 220,
                    maximumDecodedKeyByteCount: 64,
                    maximumDecodedValueStringByteCount:
                        IOSPendingRecordingValidation.maximumModelByteCount,
                    maximumNumberTokenByteCount: 20
                )
            )
        } catch BoundedJSONMemberValidationError.inputTooLarge {
            throw IOSFailedHistoryError.sourceTooLarge
        } catch {
            throw IOSFailedHistoryError.malformedData
        }

        let root: Any
        do {
            root = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw IOSFailedHistoryError.malformedData
        }
        guard let object = root as? [String: Any] else {
            throw IOSFailedHistoryError.invalidRecord
        }
        let reader = IOSFailedHistoryObjectReader(object: object)
        guard try reader.integer64("schemaVersion") == supportedSchemaVersion else {
            throw IOSFailedHistoryError.unsupportedSchemaVersion
        }
        guard Set(object.keys) == rootFields else {
            throw IOSFailedHistoryError.invalidRecord
        }

        let rawEntries = try reader.objectArray("entries")
        let rawAudioCleanup = try reader.objectArray("audioCleanup")
        guard rawEntries.count <= IOSFailedHistoryValidation.maximumEntryCount,
              rawAudioCleanup.count
                  <= IOSFailedHistoryValidation.maximumAudioCleanupCount else {
            throw IOSFailedHistoryError.invalidRecord
        }

        do {
            return try IOSFailedHistoryEnvelope(
                revision: reader.integer64("revision"),
                entries: rawEntries.map(decodeEntry),
                audioCleanup: rawAudioCleanup.map(decodeAudioCleanup)
            )
        } catch IOSFailedHistoryError.unsupportedSchemaVersion {
            throw IOSFailedHistoryError.unsupportedSchemaVersion
        } catch {
            throw IOSFailedHistoryError.invalidRecord
        }
    }

    private static func encodedData(
        _ envelope: IOSFailedHistoryEnvelope
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(
                IOSFailedHistoryWireV1(envelope: envelope)
            )
        } catch {
            throw IOSFailedHistoryError.writeFailed
        }
    }

    private static func decodeEntry(
        _ object: [String: Any]
    ) throws -> IOSFailedHistoryEntry {
        guard Set(object.keys) == entryFields else {
            throw IOSFailedHistoryError.invalidRecord
        }
        let reader = IOSFailedHistoryObjectReader(object: object)
        let retryOperation = try reader.nullableObject("retryOperation").map(
            decodeRetryOperation
        )
        guard let failureCategory = IOSFailedHistoryFailureCategory(
            rawValue: try reader.string("failureCategory")
        ), let pipelineStage = IOSFailedHistoryPipelineStage(
            rawValue: try reader.string("pipelineStage")
        ), let outputIntent = DictationOutputIntent(
            rawValue: try reader.string("outputIntent")
        ), let ownershipState = IOSFailedHistoryOwnershipState(
            rawValue: try reader.string("ownershipState")
        ), let retryCount = Int32(exactly: try reader.integer64("retryCount"))
        else {
            throw IOSFailedHistoryError.invalidRecord
        }

        return try IOSFailedHistoryEntry(
            attemptID: canonicalUUID(try reader.string("attemptID")),
            createdAt: IOSFailedHistoryTimestampCodec.date(
                from: try reader.integer64("createdAt")
            ),
            updatedAt: IOSFailedHistoryTimestampCodec.date(
                from: try reader.integer64("updatedAt")
            ),
            policyGeneration: try reader.integer64("policyGeneration"),
            failureCategory: failureCategory,
            pipelineStage: pipelineStage,
            retryCount: retryCount,
            outputIntent: outputIntent,
            transcriptionModel: try reader.string("transcriptionModel"),
            transcriptionLanguageCode: try reader.nullableString(
                "transcriptionLanguageCode"
            ),
            durationMilliseconds: try reader.integer64(
                "durationMilliseconds"
            ),
            byteCount: try reader.integer64("byteCount"),
            audioRelativeIdentifier: try reader.string(
                "audioRelativeIdentifier"
            ),
            ownershipState: ownershipState,
            retryOperation: retryOperation
        )
    }

    private static func decodeRetryOperation(
        _ object: [String: Any]
    ) throws -> IOSFailedHistoryRetryOperation {
        guard Set(object.keys) == retryOperationFields else {
            throw IOSFailedHistoryError.invalidRecord
        }
        let reader = IOSFailedHistoryObjectReader(object: object)
        guard let state = IOSFailedHistoryRetryOperationState(
            rawValue: try reader.string("state")
        ) else {
            throw IOSFailedHistoryError.invalidRecord
        }
        return try IOSFailedHistoryRetryOperation(
            retryID: canonicalUUID(try reader.string("retryID")),
            createdAt: IOSFailedHistoryTimestampCodec.date(
                from: try reader.integer64("createdAt")
            ),
            transcriptionID: canonicalUUID(
                try reader.string("transcriptionID")
            ),
            deliveryID: canonicalUUID(try reader.string("deliveryID")),
            sessionID: canonicalUUID(try reader.string("sessionID")),
            transcriptID: canonicalUUID(try reader.string("transcriptID")),
            state: state
        )
    }

    private static func decodeAudioCleanup(
        _ object: [String: Any]
    ) throws -> IOSFailedHistoryAudioCleanup {
        guard Set(object.keys) == audioCleanupFields else {
            throw IOSFailedHistoryError.invalidRecord
        }
        let reader = IOSFailedHistoryObjectReader(object: object)
        return try IOSFailedHistoryAudioCleanup(
            attemptID: canonicalUUID(try reader.string("attemptID")),
            policyGeneration: try reader.integer64("policyGeneration"),
            queuedAt: IOSFailedHistoryTimestampCodec.date(
                from: try reader.integer64("queuedAt")
            ),
            audioRelativeIdentifier: try reader.string(
                "audioRelativeIdentifier"
            ),
            byteCount: try reader.integer64("byteCount")
        )
    }

    private static func canonicalUUID(_ value: String) throws -> UUID {
        guard let identifier = UUID(uuidString: value),
              value == identifier.uuidString.lowercased() else {
            throw IOSFailedHistoryError.invalidRecord
        }
        return identifier
    }
}

private struct IOSFailedHistoryObjectReader {
    let object: [String: Any]

    func string(_ key: String) throws -> String {
        guard let value = object[key] as? String else {
            throw IOSFailedHistoryError.invalidRecord
        }
        return value
    }

    func nullableString(_ key: String) throws -> String? {
        guard let value = object[key] else {
            throw IOSFailedHistoryError.invalidRecord
        }
        if value is NSNull { return nil }
        guard let value = value as? String else {
            throw IOSFailedHistoryError.invalidRecord
        }
        return value
    }

    func nullableObject(_ key: String) throws -> [String: Any]? {
        guard let value = object[key] else {
            throw IOSFailedHistoryError.invalidRecord
        }
        if value is NSNull { return nil }
        guard let value = value as? [String: Any] else {
            throw IOSFailedHistoryError.invalidRecord
        }
        return value
    }

    func integer64(_ key: String) throws -> Int64 {
        guard let value = object[key] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              !Self.isFloatingPoint(value),
              let integer = Int64(value.stringValue) else {
            throw IOSFailedHistoryError.invalidRecord
        }
        return integer
    }

    func objectArray(_ key: String) throws -> [[String: Any]] {
        guard let value = object[key] as? [Any] else {
            throw IOSFailedHistoryError.invalidRecord
        }
        return try value.map { element in
            guard let object = element as? [String: Any] else {
                throw IOSFailedHistoryError.invalidRecord
            }
            return object
        }
    }

    private static func isFloatingPoint(_ number: NSNumber) -> Bool {
        let type = String(cString: number.objCType)
        return type == "f" || type == "d"
    }
}

private struct IOSFailedHistoryWireV1: Encodable {
    let schemaVersion = 1
    let revision: Int64
    let entries: [Entry]
    let audioCleanup: [AudioCleanup]

    init(envelope: IOSFailedHistoryEnvelope) throws {
        revision = envelope.revision
        entries = try envelope.entries.map(Entry.init)
        audioCleanup = try envelope.audioCleanup.map(AudioCleanup.init)
    }

    struct Entry: Encodable {
        let attemptID: String
        let createdAt: Int64
        let updatedAt: Int64
        let policyGeneration: Int64
        let failureCategory: String
        let pipelineStage: String
        let retryCount: Int32
        let outputIntent: String
        let transcriptionModel: String
        let transcriptionLanguageCode: String?
        let durationMilliseconds: Int64
        let byteCount: Int64
        let audioRelativeIdentifier: String
        let ownershipState: String
        let retryOperation: RetryOperation?

        init(_ entry: IOSFailedHistoryEntry) throws {
            attemptID = IOSFailedHistoryValidation.canonicalIdentifier(
                entry.attemptID
            )
            createdAt = try IOSFailedHistoryTimestampCodec.milliseconds(
                from: entry.createdAt
            )
            updatedAt = try IOSFailedHistoryTimestampCodec.milliseconds(
                from: entry.updatedAt
            )
            policyGeneration = entry.policyGeneration
            failureCategory = entry.failureCategory.rawValue
            pipelineStage = entry.pipelineStage.rawValue
            retryCount = entry.retryCount
            outputIntent = entry.outputIntent.rawValue
            transcriptionModel = entry.transcriptionModel
            transcriptionLanguageCode = entry.transcriptionLanguageCode
            durationMilliseconds = entry.durationMilliseconds
            byteCount = entry.byteCount
            audioRelativeIdentifier = entry.audioRelativeIdentifier
            ownershipState = entry.ownershipState.rawValue
            retryOperation = try entry.retryOperation.map(RetryOperation.init)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(attemptID, forKey: .attemptID)
            try container.encode(createdAt, forKey: .createdAt)
            try container.encode(updatedAt, forKey: .updatedAt)
            try container.encode(policyGeneration, forKey: .policyGeneration)
            try container.encode(failureCategory, forKey: .failureCategory)
            try container.encode(pipelineStage, forKey: .pipelineStage)
            try container.encode(retryCount, forKey: .retryCount)
            try container.encode(outputIntent, forKey: .outputIntent)
            try container.encode(transcriptionModel, forKey: .transcriptionModel)
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
            try container.encode(
                audioRelativeIdentifier,
                forKey: .audioRelativeIdentifier
            )
            try container.encode(ownershipState, forKey: .ownershipState)
            if let retryOperation {
                try container.encode(retryOperation, forKey: .retryOperation)
            } else {
                try container.encodeNil(forKey: .retryOperation)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case attemptID
            case createdAt
            case updatedAt
            case policyGeneration
            case failureCategory
            case pipelineStage
            case retryCount
            case outputIntent
            case transcriptionModel
            case transcriptionLanguageCode
            case durationMilliseconds
            case byteCount
            case audioRelativeIdentifier
            case ownershipState
            case retryOperation
        }
    }

    struct RetryOperation: Encodable {
        let retryID: String
        let createdAt: Int64
        let transcriptionID: String
        let deliveryID: String
        let sessionID: String
        let transcriptID: String
        let state: String

        init(_ operation: IOSFailedHistoryRetryOperation) throws {
            retryID = IOSFailedHistoryValidation.canonicalIdentifier(
                operation.retryID
            )
            createdAt = try IOSFailedHistoryTimestampCodec.milliseconds(
                from: operation.createdAt
            )
            transcriptionID = IOSFailedHistoryValidation.canonicalIdentifier(
                operation.transcriptionID
            )
            deliveryID = IOSFailedHistoryValidation.canonicalIdentifier(
                operation.deliveryID
            )
            sessionID = IOSFailedHistoryValidation.canonicalIdentifier(
                operation.sessionID
            )
            transcriptID = IOSFailedHistoryValidation.canonicalIdentifier(
                operation.transcriptID
            )
            state = operation.state.rawValue
        }
    }

    struct AudioCleanup: Encodable {
        let attemptID: String
        let policyGeneration: Int64
        let queuedAt: Int64
        let audioRelativeIdentifier: String
        let byteCount: Int64

        init(_ cleanup: IOSFailedHistoryAudioCleanup) throws {
            attemptID = IOSFailedHistoryValidation.canonicalIdentifier(
                cleanup.attemptID
            )
            policyGeneration = cleanup.policyGeneration
            queuedAt = try IOSFailedHistoryTimestampCodec.milliseconds(
                from: cleanup.queuedAt
            )
            audioRelativeIdentifier = cleanup.audioRelativeIdentifier
            byteCount = cleanup.byteCount
        }
    }
}
