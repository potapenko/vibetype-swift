import Foundation

enum IOSFailedHistoryRowAudioValidationPurpose: Equatable, Sendable {
    case delete
    case retention(IOSPendingFailedHistoryTransferPreparation)
}

struct IOSFailedHistoryRowAudioValidationAuthorization: Equatable, Sendable {
    let failedSource: IOSFailedHistoryJournalSnapshot
    let candidate: IOSFailedHistoryEntry
    let tombstone: IOSFailedHistoryAudioCleanup
    let outcome: IOSFailedHistoryEnvelope
    let purpose: IOSFailedHistoryRowAudioValidationPurpose
    let failedInventory: IOSFailedHistoryProtectedAudioInventory
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRowAudioValidationAuthorizationMint,
        failedSource: IOSFailedHistoryJournalSnapshot,
        candidate: IOSFailedHistoryEntry,
        tombstone: IOSFailedHistoryAudioCleanup,
        outcome: IOSFailedHistoryEnvelope,
        purpose: IOSFailedHistoryRowAudioValidationPurpose,
        failedInventory: IOSFailedHistoryProtectedAudioInventory,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        let nextRevision = failedSource.envelope.revision
            .addingReportingOverflow(1)
        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil,
              failedInventory.failedSource == failedSource,
              failedInventory.failedStoreIdentity == failedStoreIdentity,
              failedInventory.expectedPendingStoreIdentity
                == expectedPendingStoreIdentity,
              failedInventory.ownerIdentity == ownerIdentity,
              failedInventory.repositoryBinding == repositoryBinding,
              failedInventory.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              !nextRevision.overflow,
              outcome.revision == nextRevision.partialValue,
              failedSource.envelope.entries.contains(candidate),
              candidate.ownershipState == .ready,
              candidate.retryOperation == nil,
              tombstone.attemptID == candidate.attemptID,
              tombstone.policyGeneration == candidate.policyGeneration,
              tombstone.audioRelativeIdentifier
                == candidate.audioRelativeIdentifier,
              tombstone.byteCount == candidate.byteCount,
              !outcome.entries.contains(candidate),
              outcome.audioCleanup.contains(tombstone) else {
            return nil
        }
        self.failedSource = failedSource
        self.candidate = candidate
        self.tombstone = tombstone
        self.outcome = outcome
        self.purpose = purpose
        self.failedInventory = failedInventory
        self.failedStoreIdentity = failedStoreIdentity
        self.expectedPendingStoreIdentity = expectedPendingStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

final class IOSFailedHistoryValidatedRowAudio: @unchecked Sendable {
    let authorization: IOSFailedHistoryRowAudioValidationAuthorization

    private let audioLease: any IOSPendingRecordingPublishedAudioLease
    private let lock = NSLock()
    private var released = false

    init?(
        mint: IOSFailedHistoryValidatedRowAudioMint,
        authorization: IOSFailedHistoryRowAudioValidationAuthorization,
        audioLease: any IOSPendingRecordingPublishedAudioLease
    ) {
        _ = mint
        guard Self.matches(audioLease, authorization: authorization) else {
            return nil
        }
        self.authorization = authorization
        self.audioLease = audioLease
    }

    #if DEBUG
    init?(
        testingAuthorization authorization:
            IOSFailedHistoryRowAudioValidationAuthorization,
        audioLease: any IOSPendingRecordingPublishedAudioLease
    ) {
        guard Self.matches(audioLease, authorization: authorization) else {
            return nil
        }
        self.authorization = authorization
        self.audioLease = audioLease
    }
    #endif

    deinit { release() }

    func revalidate() async throws {
        let initialAuthorization = authorization.operationLeaseAuthorization
        guard initialAuthorization.provesActiveLease(),
              !lock.withLock({ released }) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        let artifact = try await audioLease.revalidate()
        guard initialAuthorization.provesActiveLease(),
              !lock.withLock({ released }),
              Self.matches(audioLease, authorization: authorization),
              artifact.byteCount == authorization.candidate.byteCount else {
            throw IOSFailedHistoryError.invalidTransition
        }
    }

    func release() {
        let shouldRelease = lock.withLock {
            guard !released else { return false }
            released = true
            return true
        }
        if shouldRelease { audioLease.release() }
    }

    private static func matches(
        _ lease: any IOSPendingRecordingPublishedAudioLease,
        authorization: IOSFailedHistoryRowAudioValidationAuthorization
    ) -> Bool {
        authorization.operationLeaseAuthorization.provesActiveLease()
            && lease.relativeIdentifier
                == authorization.candidate.audioRelativeIdentifier
            && lease.durationMilliseconds
                == authorization.candidate.durationMilliseconds
            && lease.audioArtifact.byteCount
                == authorization.candidate.byteCount
    }
}

struct IOSFailedHistoryTombstoneReceipt: Equatable, Sendable {
    let failedSource: IOSFailedHistoryJournalSnapshot
    let tombstone: IOSFailedHistoryAudioCleanup
    let outcome: IOSFailedHistoryEnvelope
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryTombstoneReceiptMint,
        authorization: IOSFailedHistoryRowAudioValidationAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard authorization.purpose == .delete,
              operationLeaseAuthorization.provesActiveLease() else {
            return nil
        }
        failedSource = authorization.failedSource
        tombstone = authorization.tombstone
        outcome = authorization.outcome
        failedStoreIdentity = authorization.failedStoreIdentity
        expectedPendingStoreIdentity =
            authorization.expectedPendingStoreIdentity
        ownerIdentity = authorization.ownerIdentity
        repositoryBinding = authorization.repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

extension IOSFailedHistoryRowAudioValidationPurpose:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRowAudioValidationPurpose(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRowAudioValidationAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRowAudioValidationAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryValidatedRowAudio:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryValidatedRowAudio(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryTombstoneReceipt:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryTombstoneReceipt(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
