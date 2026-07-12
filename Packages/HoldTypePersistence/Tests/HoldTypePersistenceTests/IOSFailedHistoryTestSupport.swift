import Foundation
import HoldTypeDomain
@testable import HoldTypePersistence

func failedHistoryTestDate(
    offsetMilliseconds: Int64 = 0
) throws -> Date {
    try IOSFailedHistoryTimestampCodec.date(
        from: 1_800_000_000_000 + offsetMilliseconds
    )
}

func failedHistoryTestUUID(
    namespace: UInt8,
    index: Int
) -> UUID {
    let value = String(
        format: "%02x000000-0000-4000-8000-%012llx",
        namespace,
        UInt64(index)
    )
    return UUID(uuidString: value)!
}

func failedHistoryTestRetryOperation(
    index: Int = 1,
    createdAt: Date? = nil,
    state: IOSFailedHistoryRetryOperationState = .reserved
) throws -> IOSFailedHistoryRetryOperation {
    try IOSFailedHistoryRetryOperation(
        retryID: failedHistoryTestUUID(namespace: 0x10, index: index),
        createdAt: createdAt ?? failedHistoryTestDate(
            offsetMilliseconds: Int64(index * 10 + 1)
        ),
        transcriptionID: failedHistoryTestUUID(namespace: 0x11, index: index),
        deliveryID: failedHistoryTestUUID(namespace: 0x12, index: index),
        sessionID: failedHistoryTestUUID(namespace: 0x13, index: index),
        transcriptID: failedHistoryTestUUID(namespace: 0x14, index: index),
        state: state
    )
}

func failedHistoryTestEntry(
    index: Int = 1,
    attemptID explicitAttemptID: UUID? = nil,
    createdAt: Date? = nil,
    updatedAt: Date? = nil,
    policyGeneration: Int64 = 1,
    failureCategory: IOSFailedHistoryFailureCategory = .networkFailure,
    pipelineStage: IOSFailedHistoryPipelineStage = .transcription,
    retryCount: Int32 = 0,
    outputIntent: DictationOutputIntent = .standard,
    transcriptionModel: String = "gpt-4o-mini-transcribe",
    transcriptionLanguageCode: String? = "en",
    durationMilliseconds: Int64 = 1_250,
    byteCount: Int64 = 4_096,
    audioRelativeIdentifier explicitAudioRelativeIdentifier: String? = nil,
    ownershipState: IOSFailedHistoryOwnershipState = .ready,
    retryOperation: IOSFailedHistoryRetryOperation? = nil
) throws -> IOSFailedHistoryEntry {
    let attemptID = explicitAttemptID
        ?? failedHistoryTestUUID(namespace: 0x01, index: index)
    let createdAt = try createdAt ?? failedHistoryTestDate(
        offsetMilliseconds: Int64(index * 10)
    )
    let updatedAt = try updatedAt ?? failedHistoryTestDate(
        offsetMilliseconds: Int64(index * 10 + 2)
    )
    return try IOSFailedHistoryEntry(
        attemptID: attemptID,
        createdAt: createdAt,
        updatedAt: updatedAt,
        policyGeneration: policyGeneration,
        failureCategory: failureCategory,
        pipelineStage: pipelineStage,
        retryCount: retryCount,
        outputIntent: outputIntent,
        transcriptionModel: transcriptionModel,
        transcriptionLanguageCode: transcriptionLanguageCode,
        durationMilliseconds: durationMilliseconds,
        byteCount: byteCount,
        audioRelativeIdentifier: explicitAudioRelativeIdentifier
            ?? IOSPendingRecordingStorageLocation.relativeAudioIdentifier(
                for: attemptID,
                format: .m4a
            ),
        ownershipState: ownershipState,
        retryOperation: retryOperation
    )
}

func failedHistoryTestAudioCleanup(
    index: Int = 1,
    attemptID explicitAttemptID: UUID? = nil,
    policyGeneration: Int64 = 1,
    queuedAt: Date? = nil,
    byteCount: Int64 = 4_096,
    audioRelativeIdentifier explicitAudioRelativeIdentifier: String? = nil
) throws -> IOSFailedHistoryAudioCleanup {
    let attemptID = explicitAttemptID
        ?? failedHistoryTestUUID(namespace: 0x02, index: index)
    return try IOSFailedHistoryAudioCleanup(
        attemptID: attemptID,
        policyGeneration: policyGeneration,
        queuedAt: queuedAt ?? failedHistoryTestDate(
            offsetMilliseconds: Int64(index * 10)
        ),
        audioRelativeIdentifier: explicitAudioRelativeIdentifier
            ?? IOSPendingRecordingStorageLocation.relativeAudioIdentifier(
                for: attemptID,
                format: .m4a
            ),
        byteCount: byteCount
    )
}

final class FailedHistoryFakeFileSystem:
    IOSStrictProtectedRecordFileSystem,
    @unchecked Sendable {
    struct Failure {
        let error: IOSStrictProtectedRecordFileSystemError
        let commitBeforeThrowing: Bool
    }

    var file: IOSStrictProtectedRecordFile?
    var readError: IOSStrictProtectedRecordFileSystemError?
    var readErrorAfterNextReplace:
        IOSStrictProtectedRecordFileSystemError?
    var createFailure: Failure?
    var replaceFailure: Failure?
    var persistentReplaceFailure: Failure?
    var replaceFailureAfterSuccessfulReplaces:
        (remaining: Int, failure: Failure)?
    var persistentReplaceFailureAfterSuccessfulReplaces:
        (remaining: Int, failure: Failure)?
    var maintenanceError: IOSStrictProtectedRecordFileSystemError?
    var maintenanceReport = IOSStrictProtectedRecordMaintenanceReport.empty
    private(set) var events: [String] = []

    private var nextToken: UInt64 = 1

    func install(_ data: Data) {
        file = IOSStrictProtectedRecordFile(
            data: data,
            revision: makeRevision()
        )
    }

    func readFileIfPresent() throws -> IOSStrictProtectedRecordFile? {
        events.append("load")
        if let readError { throw readError }
        return file
    }

    func createFile(
        with data: Data
    ) throws -> IOSStrictProtectedRecordFileRevision {
        events.append("create")
        if let failure = createFailure {
            createFailure = nil
            if failure.commitBeforeThrowing {
                install(data)
            }
            throw failure.error
        }
        guard file == nil else {
            throw IOSStrictProtectedRecordFileSystemError.destinationConflict
        }
        install(data)
        return file!.revision
    }

    func replaceFile(
        with data: Data,
        expected: IOSStrictProtectedRecordFileRevision
    ) throws -> IOSStrictProtectedRecordFileRevision {
        events.append("replace")
        guard file?.revision == expected else {
            throw IOSStrictProtectedRecordFileSystemError.staleRevision
        }
        if var scheduled = replaceFailureAfterSuccessfulReplaces {
            if scheduled.remaining == 0 {
                replaceFailureAfterSuccessfulReplaces = nil
                if scheduled.failure.commitBeforeThrowing {
                    install(data)
                }
                throw scheduled.failure.error
            }
            scheduled.remaining -= 1
            replaceFailureAfterSuccessfulReplaces = scheduled
        }
        if var scheduled = persistentReplaceFailureAfterSuccessfulReplaces {
            if scheduled.remaining == 0 {
                persistentReplaceFailureAfterSuccessfulReplaces = nil
                persistentReplaceFailure = scheduled.failure
            } else {
                scheduled.remaining -= 1
                persistentReplaceFailureAfterSuccessfulReplaces = scheduled
            }
        }
        if let failure = replaceFailure {
            replaceFailure = nil
            if failure.commitBeforeThrowing {
                install(data)
            }
            throw failure.error
        }
        if let failure = persistentReplaceFailure {
            if failure.commitBeforeThrowing {
                install(data)
            }
            throw failure.error
        }
        install(data)
        if let readErrorAfterNextReplace {
            self.readErrorAfterNextReplace = nil
            readError = readErrorAfterNextReplace
        }
        return file!.revision
    }

    func removeFile(
        expected: IOSStrictProtectedRecordFileRevision
    ) throws {
        _ = expected
        throw IOSStrictProtectedRecordFileSystemError.removeFailed
    }

    func removeAbandonedTemporaryFiles(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        _ = now
        events.append("maintenance")
        if let maintenanceError { throw maintenanceError }
        return maintenanceReport
    }

    func resetEvents() {
        events = []
    }

    private func makeRevision() -> IOSStrictProtectedRecordFileRevision {
        defer { nextToken += 1 }
        return IOSStrictProtectedRecordFileRevision(testingToken: nextToken)
    }
}

func requireFailedHistorySendable<Value: Sendable>(
    _ type: Value.Type
) {}
