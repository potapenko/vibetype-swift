import Foundation
import HoldTypeDomain

enum IOSFailedHistoryError: Error, Equatable, Sendable {
    case invalidEntry
    case invalidRecord
    case sourceTooLarge
    case malformedData
    case unsupportedSchemaVersion
    case readFailed
    case writeFailed
    case dataProtectionUnavailable
    case slotOccupied
    case compareAndSwapFailed
    case collision
    case capacityExceeded
    case stalePolicyGeneration
    case revisionOverflow
    case retryCountOverflow
    case commitUncertain
    case invalidTransition
    case maintenanceFailed
}

enum IOSFailedHistoryFailureCategory: String, CaseIterable, Equatable,
    Sendable {
    case credentialRejected
    case networkUnavailable
    case networkFailure
    case timedOut
    case rateLimited
    case providerUnavailable
    case providerRejected
    case invalidResponse
    case emptyResult
    case echoRejected
}

enum IOSFailedHistoryPipelineStage: String, CaseIterable, Equatable,
    Sendable {
    case transcription
    case translation
}

enum IOSFailedHistoryOwnershipState: String, CaseIterable, Equatable, Sendable {
    case pendingJournalRetirement
    case ready
}

enum IOSFailedHistoryRetryOperationState: String, CaseIterable, Equatable,
    Sendable {
    case reserved
    case providerDispatched
    case acceptingOutput
}

struct IOSFailedHistoryRetryOperation: Equatable, Sendable {
    let retryID: UUID
    let createdAt: Date
    let transcriptionID: UUID
    let deliveryID: UUID
    let sessionID: UUID
    let transcriptID: UUID
    let state: IOSFailedHistoryRetryOperationState

    init(
        retryID: UUID,
        createdAt: Date,
        transcriptionID: UUID,
        deliveryID: UUID,
        sessionID: UUID,
        transcriptID: UUID,
        state: IOSFailedHistoryRetryOperationState
    ) throws {
        let identifiers = [
            retryID,
            transcriptionID,
            deliveryID,
            sessionID,
            transcriptID,
        ]
        guard Set(identifiers).count == identifiers.count,
              (try? IOSFailedHistoryTimestampCodec.milliseconds(
                  from: createdAt
              )) != nil else {
            throw IOSFailedHistoryError.invalidEntry
        }

        self.retryID = retryID
        self.createdAt = createdAt
        self.transcriptionID = transcriptionID
        self.deliveryID = deliveryID
        self.sessionID = sessionID
        self.transcriptID = transcriptID
        self.state = state
    }
}

struct IOSFailedHistoryEntry: Equatable, Sendable {
    let attemptID: UUID
    let createdAt: Date
    let updatedAt: Date
    let policyGeneration: Int64
    let failureCategory: IOSFailedHistoryFailureCategory
    let pipelineStage: IOSFailedHistoryPipelineStage
    let retryCount: Int32
    let outputIntent: DictationOutputIntent
    let transcriptionModel: String
    let transcriptionLanguageCode: String?
    let durationMilliseconds: Int64
    let byteCount: Int64
    let audioRelativeIdentifier: String
    let ownershipState: IOSFailedHistoryOwnershipState
    let retryOperation: IOSFailedHistoryRetryOperation?

    init(
        attemptID: UUID,
        createdAt: Date,
        updatedAt: Date,
        policyGeneration: Int64,
        failureCategory: IOSFailedHistoryFailureCategory,
        pipelineStage: IOSFailedHistoryPipelineStage,
        retryCount: Int32,
        outputIntent: DictationOutputIntent,
        transcriptionModel: String,
        transcriptionLanguageCode: String?,
        durationMilliseconds: Int64,
        byteCount: Int64,
        audioRelativeIdentifier: String,
        ownershipState: IOSFailedHistoryOwnershipState,
        retryOperation: IOSFailedHistoryRetryOperation?
    ) throws {
        let parsedAudio = IOSPendingRecordingStorageLocation
            .parseRelativeAudioIdentifier(audioRelativeIdentifier)
        guard IOSPendingRecordingValidation.isValidModel(transcriptionModel),
              IOSPendingRecordingValidation.isValidLanguageCode(
                  transcriptionLanguageCode
              ),
              IOSPendingRecordingValidation.isValidDurationMilliseconds(
                  durationMilliseconds
              ),
              IOSPendingRecordingValidation.isValidByteCount(byteCount),
              let parsedAudio,
              parsedAudio.attemptID == attemptID,
              policyGeneration > 0,
              retryCount >= 0,
              (try? IOSFailedHistoryTimestampCodec.milliseconds(
                  from: createdAt
              )) != nil,
              (try? IOSFailedHistoryTimestampCodec.milliseconds(
                  from: updatedAt
              )) != nil,
              updatedAt >= createdAt,
              (retryOperation?.createdAt ?? createdAt) >= createdAt,
              (retryOperation?.createdAt ?? updatedAt) <= updatedAt,
              pipelineStage != .translation || outputIntent == .translate,
              retryOperation == nil || ownershipState == .ready,
              retryOperation == nil || retryCount > 0,
              ownershipState == .ready || retryCount == 0 else {
            throw IOSFailedHistoryError.invalidEntry
        }

        self.attemptID = attemptID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.policyGeneration = policyGeneration
        self.failureCategory = failureCategory
        self.pipelineStage = pipelineStage
        self.retryCount = retryCount
        self.outputIntent = outputIntent
        self.transcriptionModel = transcriptionModel
        self.transcriptionLanguageCode = transcriptionLanguageCode
        self.durationMilliseconds = durationMilliseconds
        self.byteCount = byteCount
        self.audioRelativeIdentifier = audioRelativeIdentifier
        self.ownershipState = ownershipState
        self.retryOperation = retryOperation
    }
}

extension IOSFailedHistoryEntry {
    static func == (
        lhs: IOSFailedHistoryEntry,
        rhs: IOSFailedHistoryEntry
    ) -> Bool {
        lhs.attemptID == rhs.attemptID
            && lhs.createdAt == rhs.createdAt
            && lhs.updatedAt == rhs.updatedAt
            && lhs.policyGeneration == rhs.policyGeneration
            && lhs.failureCategory == rhs.failureCategory
            && lhs.pipelineStage == rhs.pipelineStage
            && lhs.retryCount == rhs.retryCount
            && lhs.outputIntent == rhs.outputIntent
            && IOSAcceptedOutputDeliveryValidation.bytesEqual(
                lhs.transcriptionModel,
                rhs.transcriptionModel
            )
            && lhs.transcriptionLanguageCode == rhs.transcriptionLanguageCode
            && lhs.durationMilliseconds == rhs.durationMilliseconds
            && lhs.byteCount == rhs.byteCount
            && lhs.audioRelativeIdentifier == rhs.audioRelativeIdentifier
            && lhs.ownershipState == rhs.ownershipState
            && lhs.retryOperation == rhs.retryOperation
    }
}

struct IOSFailedHistoryAudioCleanup: Equatable, Sendable {
    let attemptID: UUID
    let policyGeneration: Int64
    let queuedAt: Date
    let audioRelativeIdentifier: String
    let byteCount: Int64

    init(
        attemptID: UUID,
        policyGeneration: Int64,
        queuedAt: Date,
        audioRelativeIdentifier: String,
        byteCount: Int64
    ) throws {
        let parsedAudio = IOSPendingRecordingStorageLocation
            .parseRelativeAudioIdentifier(audioRelativeIdentifier)
        guard policyGeneration > 0,
              let parsedAudio,
              parsedAudio.attemptID == attemptID,
              IOSPendingRecordingValidation.isValidByteCount(byteCount),
              (try? IOSFailedHistoryTimestampCodec.milliseconds(
                  from: queuedAt
              )) != nil else {
            throw IOSFailedHistoryError.invalidEntry
        }

        self.attemptID = attemptID
        self.policyGeneration = policyGeneration
        self.queuedAt = queuedAt
        self.audioRelativeIdentifier = audioRelativeIdentifier
        self.byteCount = byteCount
    }
}

struct IOSFailedHistoryEnvelope: Equatable, Sendable {
    let revision: Int64
    let entries: [IOSFailedHistoryEntry]
    let audioCleanup: [IOSFailedHistoryAudioCleanup]

    init(
        revision: Int64,
        entries: [IOSFailedHistoryEntry],
        audioCleanup: [IOSFailedHistoryAudioCleanup]
    ) throws {
        let entryAttemptIDs = entries.map(\.attemptID)
        let cleanupAttemptIDs = audioCleanup.map(\.attemptID)
        let entryAudioIdentifiers = entries.map(\.audioRelativeIdentifier)
        let cleanupAudioIdentifiers = audioCleanup.map(\.audioRelativeIdentifier)
        let allAttemptIDs = entryAttemptIDs + cleanupAttemptIDs
        let allAudioIdentifiers = entryAudioIdentifiers + cleanupAudioIdentifiers

        guard revision >= 1,
              entries.count <= IOSFailedHistoryValidation.maximumEntryCount,
              audioCleanup.count
                  <= IOSFailedHistoryValidation.maximumAudioCleanupCount,
              entries == IOSFailedHistoryValidation.sortedEntries(entries),
              audioCleanup
                  == IOSFailedHistoryValidation.sortedAudioCleanup(audioCleanup),
              Set(allAttemptIDs).count == allAttemptIDs.count,
              Set(allAudioIdentifiers).count == allAudioIdentifiers.count,
              entries.lazy.filter({ $0.retryOperation != nil }).count <= 1 else {
            throw IOSFailedHistoryError.invalidRecord
        }

        self.revision = revision
        self.entries = entries
        self.audioCleanup = audioCleanup
    }
}

struct IOSFailedHistoryMaintenanceReport: Equatable, Sendable {
    let inspectedEntryCount: Int
    let inspectedByteCount: Int64
    let removedFileCount: Int
    let removedByteCount: Int64
    let reachedLimit: Bool

    init(_ report: IOSStrictProtectedRecordMaintenanceReport) {
        inspectedEntryCount = report.inspectedEntryCount
        inspectedByteCount = report.inspectedByteCount
        removedFileCount = report.removedFileCount
        removedByteCount = report.removedByteCount
        reachedLimit = report.reachedLimit
    }
}

enum IOSFailedHistoryValidation {
    static let maximumEntryCount = 5
    static let maximumAudioCleanupCount = 5
    static let maximumRetryCount = Int32.max

    static func sortedEntries(
        _ entries: [IOSFailedHistoryEntry]
    ) -> [IOSFailedHistoryEntry] {
        entries.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return canonicalIdentifier(lhs.attemptID)
                < canonicalIdentifier(rhs.attemptID)
        }
    }

    static func sortedAudioCleanup(
        _ cleanup: [IOSFailedHistoryAudioCleanup]
    ) -> [IOSFailedHistoryAudioCleanup] {
        cleanup.sorted { lhs, rhs in
            if lhs.queuedAt != rhs.queuedAt {
                return lhs.queuedAt < rhs.queuedAt
            }
            return canonicalIdentifier(lhs.attemptID)
                < canonicalIdentifier(rhs.attemptID)
        }
    }

    static func canonicalIdentifier(_ identifier: UUID) -> String {
        identifier.uuidString.lowercased()
    }
}

enum IOSFailedHistoryTimestampCodec {
    private static let millisecondsPerSecond = 1_000.0
    private static let minimumInt64Value = -9_223_372_036_854_775_808.0
    private static let maximumInt64ValueExclusive = 9_223_372_036_854_775_808.0

    static func canonicalDate(from date: Date) throws -> Date {
        let milliseconds = try milliseconds(from: date, requireCanonical: false)
        let canonical = Date(
            timeIntervalSince1970:
                Double(milliseconds) / millisecondsPerSecond
        )
        guard canonical.timeIntervalSinceReferenceDate.isFinite else {
            throw IOSFailedHistoryError.invalidRecord
        }
        return canonical
    }

    static func milliseconds(from date: Date) throws -> Int64 {
        try milliseconds(from: date, requireCanonical: true)
    }

    static func date(from milliseconds: Int64) throws -> Date {
        let date = Date(
            timeIntervalSince1970:
                Double(milliseconds) / millisecondsPerSecond
        )
        guard date.timeIntervalSinceReferenceDate.isFinite,
              try self.milliseconds(from: date) == milliseconds else {
            throw IOSFailedHistoryError.invalidRecord
        }
        return date
    }

    private static func milliseconds(
        from date: Date,
        requireCanonical: Bool
    ) throws -> Int64 {
        let seconds = date.timeIntervalSince1970
        let scaled = seconds * millisecondsPerSecond
        guard seconds.isFinite,
              scaled.isFinite,
              scaled >= minimumInt64Value,
              scaled < maximumInt64ValueExclusive else {
            throw IOSFailedHistoryError.invalidRecord
        }
        let roundedValue = scaled.rounded(.toNearestOrAwayFromZero)
        guard roundedValue >= minimumInt64Value,
              roundedValue < maximumInt64ValueExclusive else {
            throw IOSFailedHistoryError.invalidRecord
        }
        let rounded = Int64(roundedValue)
        if requireCanonical {
            let canonical = Date(
                timeIntervalSince1970:
                    Double(rounded) / millisecondsPerSecond
            )
            guard canonical == date else {
                throw IOSFailedHistoryError.invalidRecord
            }
        }
        return rounded
    }
}

extension IOSFailedHistoryError: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSFailedHistoryError(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { IOSFailedHistoryRedaction.mirror(of: self) }
}

extension IOSFailedHistoryFailureCategory: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryFailureCategory(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { IOSFailedHistoryRedaction.mirror(of: self) }
}

extension IOSFailedHistoryPipelineStage: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSFailedHistoryPipelineStage(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { IOSFailedHistoryRedaction.mirror(of: self) }
}

extension IOSFailedHistoryOwnershipState: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSFailedHistoryOwnershipState(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { IOSFailedHistoryRedaction.mirror(of: self) }
}

extension IOSFailedHistoryRetryOperationState: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryOperationState(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { IOSFailedHistoryRedaction.mirror(of: self) }
}

extension IOSFailedHistoryRetryOperation: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSFailedHistoryRetryOperation(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { IOSFailedHistoryRedaction.mirror(of: self) }
}

extension IOSFailedHistoryEntry: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSFailedHistoryEntry(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { IOSFailedHistoryRedaction.mirror(of: self) }
}

extension IOSFailedHistoryAudioCleanup: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSFailedHistoryAudioCleanup(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { IOSFailedHistoryRedaction.mirror(of: self) }
}

extension IOSFailedHistoryEnvelope: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSFailedHistoryEnvelope(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { IOSFailedHistoryRedaction.mirror(of: self) }
}

extension IOSFailedHistoryMaintenanceReport: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSFailedHistoryMaintenanceReport(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { IOSFailedHistoryRedaction.mirror(of: self) }
}

private enum IOSFailedHistoryRedaction {
    static func mirror(of value: Any) -> Mirror {
        Mirror(value, children: [:])
    }
}
