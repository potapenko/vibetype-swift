import Foundation
import HoldTypeDomain

struct IOSFailedHistoryMetadataRetirementAuthorityMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryPendingOwnershipAbsenceProofMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryPendingRowAbsenceProofMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryTransferRecoveryInspectionMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryProtectedAudioInventoryMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryRowAudioValidationAuthorizationMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryTombstoneReceiptMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryAudioCleanupAuthorizationMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryAudioCleanupCompletionAuthorizationMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryRetryRecoveryInspectionMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryPolicyRetryCancellationAuthorizationMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryRetryLiveOwnerTokenMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryRetryCancellationCompletionAuthorizationMint:
    Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryRetryReservationAuthorizationMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryRetryReservationReceiptMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryRetryDispatchAuthorizationMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryRetryDispatchReceiptMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryRetryCancellationAuthorizationMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryRetryCancellationReceiptMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryRetryFailureAuthorizationMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryRetryFailureReceiptMint: Sendable {
    fileprivate init() {}
}

private final class IOSFailedHistoryPendingStoreIdentityBinding:
    @unchecked Sendable {
    private let lock = NSLock()
    private var identity: IOSPendingRecordingStoreIdentity?

    init(identity: IOSPendingRecordingStoreIdentity? = nil) {
        self.identity = identity
    }

    func bind(_ identity: IOSPendingRecordingStoreIdentity) -> Bool {
        lock.withLock {
            if let current = self.identity {
                return current == identity
            }
            self.identity = identity
            return true
        }
    }

    func current() -> IOSPendingRecordingStoreIdentity? {
        lock.withLock { identity }
    }
}

private final class IOSFailedHistoryRetryStateIdentityBinding:
    @unchecked Sendable {
    private let lock = NSLock()
    private var identity: IOSFailedHistoryRetryLiveOwnerStateIdentity?

    init(identity: IOSFailedHistoryRetryLiveOwnerStateIdentity? = nil) {
        self.identity = identity
    }

    func bind(_ identity: IOSFailedHistoryRetryLiveOwnerStateIdentity) -> Bool {
        lock.withLock {
            if let current = self.identity {
                return current == identity
            }
            self.identity = identity
            return true
        }
    }

    func current() -> IOSFailedHistoryRetryLiveOwnerStateIdentity? {
        lock.withLock { identity }
    }
}

enum IOSFailedHistoryReadyCommitUncertainty: Equatable, Sendable {
    case retryReadyCommit(
        IOSFailedHistoryPendingMetadataRetirementAuthority
    )
    case readyOutcomeConfirmation(
        IOSFailedHistoryPendingMetadataRetirementAuthority
    )

    var authority: IOSFailedHistoryPendingMetadataRetirementAuthority {
        switch self {
        case .retryReadyCommit(let authority),
                .readyOutcomeConfirmation(let authority):
            authority
        }
    }
}

struct IOSFailedHistoryRetryDeliveryRelationKey: Equatable, Sendable {
    let retryID: UUID
    let deliveryID: UUID
    let sessionID: UUID
    let attemptID: UUID
    let transcriptID: UUID
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
}

extension IOSFailedHistoryRetryDeliveryRelationKey:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryDeliveryRelationKey(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryReadyCommitUncertainty:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryReadyCommitUncertainty(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

final class IOSFailedHistoryMutationInterlock: @unchecked Sendable {
    private enum DeliveryProtection: Equatable {
        case frozen(IOSFailedHistoryRetryDeliveryFreezeReservation)
        case relation(IOSFailedHistoryRetryDeliveryFreezeReservation)
    }

    private struct CleanupBinding: Equatable {
        let operationID: IOSFailedHistoryAudioCleanupOperationID
        let failedStoreIdentity: IOSFailedHistoryStoreIdentity
        let expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity
        let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
        let repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding

        init(_ authorization: IOSFailedHistoryAudioCleanupAuthorization) {
            operationID = authorization.operationID
            failedStoreIdentity = authorization.failedStoreIdentity
            expectedPendingStoreIdentity =
                authorization.expectedPendingStoreIdentity
            ownerIdentity = authorization.ownerIdentity
            repositoryBinding = authorization.repositoryBinding
        }

        init(
            _ authorization:
                IOSFailedHistoryAudioCleanupCompletionAuthorization
        ) {
            operationID = authorization.operationID
            failedStoreIdentity = authorization.failedStoreIdentity
            expectedPendingStoreIdentity =
                authorization.expectedPendingStoreIdentity
            ownerIdentity = authorization.ownerIdentity
            repositoryBinding = authorization.repositoryBinding
        }
    }

    private let lock = NSLock()
    private var mutationBlocked = false
    private var cleanupBinding: CleanupBinding?
    private var deliveryProtection: DeliveryProtection?

    var isBlocked: Bool {
        lock.withLock {
            mutationBlocked || cleanupBinding != nil
                || deliveryProtection != nil
        }
    }

    var hasRetryDeliveryRelation: Bool {
        lock.withLock {
            guard case .relation = deliveryProtection else { return false }
            return true
        }
    }

    var hasRetryDeliveryProtection: Bool {
        lock.withLock { deliveryProtection != nil }
    }

    fileprivate var isMutationBlocked: Bool {
        lock.withLock { mutationBlocked }
    }

    fileprivate var isCleanupBlocked: Bool {
        lock.withLock { cleanupBinding != nil }
    }

    fileprivate func retainsAudioCleanup(
        using authorization: IOSFailedHistoryAudioCleanupAuthorization
    ) -> Bool {
        lock.withLock { cleanupBinding == CleanupBinding(authorization) }
    }

    fileprivate func retainUncertainty() {
        lock.withLock { mutationBlocked = true }
    }

    fileprivate func clearUncertainty() {
        lock.withLock { mutationBlocked = false }
    }

    func reserveRetryDeliveryFreeze(
        _ key: IOSFailedHistoryRetryDeliveryRelationKey,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) -> IOSFailedHistoryRetryDeliveryFreezeReservation? {
        guard operationLeaseAuthorization.provesActiveLease() else {
            return nil
        }
        return lock.withLock {
            guard !mutationBlocked,
                  cleanupBinding == nil,
                  deliveryProtection == nil else {
                return nil
            }
            let reservation =
                IOSFailedHistoryRetryDeliveryFreezeReservation(
                    reservationID:
                        IOSFailedHistoryRetryDeliveryFreezeReservationID(),
                    relationKey: key,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
            deliveryProtection = .frozen(reservation)
            return reservation
        }
    }

    func permitsRetryDeliveryFreeze(
        _ reservation: IOSFailedHistoryRetryDeliveryFreezeReservation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        guard operationLeaseAuthorization.provesActiveLease() else {
            return false
        }
        return lock.withLock {
            guard !mutationBlocked, cleanupBinding == nil else {
                return false
            }
            switch deliveryProtection {
            case .frozen(let retained):
                return retained == reservation
            case .relation(let retained):
                return retained.reservationID == reservation.reservationID
                    && retained.relationKey == reservation.relationKey
            case nil:
                return false
            }
        }
    }

    func refreshRetryDeliveryFreeze(
        _ reservation: IOSFailedHistoryRetryDeliveryFreezeReservation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) -> IOSFailedHistoryRetryDeliveryFreezeReservation? {
        guard operationLeaseAuthorization.provesActiveLease() else {
            return nil
        }
        return lock.withLock {
            let refreshed = IOSFailedHistoryRetryDeliveryFreezeReservation(
                reservationID: reservation.reservationID,
                relationKey: reservation.relationKey,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
            switch deliveryProtection {
            case .frozen(let retained):
                guard retained.reservationID == reservation.reservationID,
                      retained.relationKey == reservation.relationKey,
                      !mutationBlocked,
                      cleanupBinding == nil else {
                    return nil
                }
                deliveryProtection = .frozen(refreshed)
                return refreshed
            case .relation(let retained):
                guard retained.reservationID == reservation.reservationID,
                      retained.relationKey
                        == reservation.relationKey else {
                    return nil
                }
                deliveryProtection = .relation(refreshed)
                return refreshed
            case nil:
                return nil
            }
        }
    }

    fileprivate func upgradeRetryDeliveryFreeze(
        _ reservation: IOSFailedHistoryRetryDeliveryFreezeReservation,
        to key: IOSFailedHistoryRetryDeliveryRelationKey
    ) -> Bool {
        lock.withLock {
            switch deliveryProtection {
            case .frozen(let retained):
                guard retained == reservation,
                      retained.relationKey == key else {
                    return false
                }
                deliveryProtection = .relation(reservation)
                return true
            case .relation(let retained):
                return retained.reservationID
                        == reservation.reservationID
                    && retained.relationKey == key
            case nil:
                return false
            }
        }
    }

    @discardableResult
    func clearRetryDeliveryFreeze(
        _ reservation: IOSFailedHistoryRetryDeliveryFreezeReservation
    ) -> Bool {
        lock.withLock {
            guard case .frozen(let retained) = deliveryProtection,
                  retained == reservation else {
                return false
            }
            deliveryProtection = nil
            return true
        }
    }

    func permitsRetryDeliveryRelation(
        _ key: IOSFailedHistoryRetryDeliveryRelationKey,
        freezeReservation:
            IOSFailedHistoryRetryDeliveryFreezeReservation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        guard operationLeaseAuthorization.provesActiveLease() else {
            return false
        }
        return lock.withLock {
            guard case .relation(let retained) = deliveryProtection else {
                return false
            }
            return retained.reservationID
                    == freezeReservation.reservationID
                && retained.relationKey == key
                && freezeReservation.relationKey == key
        }
    }

    @discardableResult
    fileprivate func clearRetryDeliveryRelation(
        _ key: IOSFailedHistoryRetryDeliveryRelationKey,
        freezeReservation:
            IOSFailedHistoryRetryDeliveryFreezeReservation
    ) -> Bool {
        lock.withLock {
            guard case .relation(let retained) = deliveryProtection,
                  retained.reservationID
                    == freezeReservation.reservationID,
                  retained.relationKey == key,
                  freezeReservation.relationKey == key else {
                return false
            }
            deliveryProtection = nil
            return true
        }
    }

    fileprivate func retainAudioCleanup(
        using authorization: IOSFailedHistoryAudioCleanupAuthorization
    ) -> Bool {
        let binding = CleanupBinding(authorization)
        return lock.withLock {
            guard cleanupBinding == nil || cleanupBinding == binding else {
                return false
            }
            cleanupBinding = binding
            return true
        }
    }

    func hasRetainedAudioCleanup(
        using authorization: IOSFailedHistoryAudioCleanupAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        guard operationLeaseAuthorization.provesActiveLease(),
              authorization.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              authorization.repositoryBinding.physicalRootIdentity != nil else {
            return false
        }
        return lock.withLock {
            cleanupBinding == CleanupBinding(authorization)
        }
    }

    @discardableResult
    func clearAudioCleanup(
        using authorization:
            IOSFailedHistoryAudioCleanupCompletionAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        guard operationLeaseAuthorization.provesActiveLease(),
              authorization.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              authorization.repositoryBinding.physicalRootIdentity != nil else {
            return false
        }
        return lock.withLock {
            guard cleanupBinding == CleanupBinding(authorization) else {
                return false
            }
            cleanupBinding = nil
            return true
        }
    }

    fileprivate func abandonAudioCleanup(
        using authorization: IOSFailedHistoryAudioCleanupAuthorization
    ) -> Bool {
        guard authorization.operationLeaseAuthorization.provesActiveLease()
        else {
            return false
        }
        return lock.withLock {
            guard cleanupBinding == CleanupBinding(authorization) else {
                return false
            }
            cleanupBinding = nil
            return true
        }
    }
}

struct IOSFailedHistoryStoreIdentity: Equatable, Sendable {
    private let value = UUID()
}

extension IOSFailedHistoryStoreIdentity:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSFailedHistoryStoreIdentity(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSFailedHistoryJournalMutationAuthorization: Sendable {
    let expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?

    fileprivate init(
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) {
        self.expectedRepositoryRoot = expectedRepositoryRoot
    }

    #if DEBUG
    init(testingToken: Void) {
        _ = testingToken
        self.init(expectedRepositoryRoot: nil)
    }
    #endif
}

fileprivate enum IOSFailedHistoryMutationSource: Equatable, Sendable {
    case missing
    case existing(IOSFailedHistoryJournalSnapshot)
}

fileprivate struct IOSFailedHistoryUncertainMutationIntent:
    Equatable,
    Sendable {
    let source: IOSFailedHistoryMutationSource
    let outcome: IOSFailedHistoryEnvelope
}

private enum IOSFailedHistoryTransferMutationIntent: Sendable {
    case pendingRow(
        preparation: IOSPendingFailedHistoryTransferPreparation,
        retentionAuthorization:
            IOSFailedHistoryRowAudioValidationAuthorization?,
        outcome: IOSFailedHistoryEnvelope
    )
    case ready(
        failedSource: IOSFailedHistoryJournalSnapshot,
        row: IOSFailedHistoryEntry,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        outcome: IOSFailedHistoryEnvelope
    )
}

private struct IOSFailedHistoryRowRemovalMutationIntent: Sendable {
    let authorization: IOSFailedHistoryRowAudioValidationAuthorization
    let outcome: IOSFailedHistoryEnvelope
}

private struct IOSFailedHistoryAudioCleanupMutationIntent: Sendable {
    var authorization: IOSFailedHistoryAudioCleanupAuthorization
    let outcome: IOSFailedHistoryEnvelope
    var retirementReceipt: IOSFailedHistoryAudioCleanupReceipt?
}

private struct IOSFailedHistoryRetryCancellationMutationIntent: Sendable {
    var authorization:
        IOSFailedHistoryPolicyRetryCancellationAuthorization
    let outcome: IOSFailedHistoryEnvelope
}

private enum IOSFailedHistoryRetryMutationIntent: Sendable {
    case reservation(IOSFailedHistoryRetryReservationAuthorization)
    case dispatch(IOSFailedHistoryRetryDispatchAuthorization)
    case cancellation(IOSFailedHistoryRetryCancellationAuthorization)
    case failure(IOSFailedHistoryRetryFailureAuthorization)
    case acceptingOutput(
        IOSFailedHistoryRetryAcceptingOutputAuthorization
    )
    case success(IOSFailedHistoryRetrySuccessAuthorization)
}

struct IOSFailedHistoryMutationCapability: Equatable, Sendable {
    fileprivate let source: IOSFailedHistoryMutationSource
    fileprivate let outcome: IOSFailedHistoryEnvelope
    fileprivate let retainedIntent: IOSFailedHistoryUncertainMutationIntent?
    let storeIdentity: IOSFailedHistoryStoreIdentity
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization
    fileprivate let repositoryBinding:
        IOSAcceptedHistoryCoordinatorRepositoryBinding?

    fileprivate init(
        source: IOSFailedHistoryMutationSource,
        outcome: IOSFailedHistoryEnvelope,
        retainedIntent: IOSFailedHistoryUncertainMutationIntent?,
        storeIdentity: IOSFailedHistoryStoreIdentity,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding?
    ) {
        self.source = source
        self.outcome = outcome
        self.retainedIntent = retainedIntent
        self.storeIdentity = storeIdentity
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        self.operationLeaseAuthorization = operationLeaseAuthorization
        self.repositoryBinding = repositoryBinding
    }
}

extension IOSFailedHistoryMutationCapability:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryMutationCapability(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSFailedHistoryMutationReceipt: Equatable, Sendable {
    fileprivate let snapshot: IOSFailedHistoryJournalSnapshot
    let storeIdentity: IOSFailedHistoryStoreIdentity
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization
    fileprivate let repositoryBinding:
        IOSAcceptedHistoryCoordinatorRepositoryBinding?

    fileprivate init(
        snapshot: IOSFailedHistoryJournalSnapshot,
        storeIdentity: IOSFailedHistoryStoreIdentity,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding?
    ) {
        self.snapshot = snapshot
        self.storeIdentity = storeIdentity
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        self.operationLeaseAuthorization = operationLeaseAuthorization
        self.repositoryBinding = repositoryBinding
    }
}

extension IOSFailedHistoryMutationReceipt:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSFailedHistoryMutationReceipt(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSFailedHistoryGuardedBaselineEvidence: Sendable {
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity

    fileprivate init(
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    ) {
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
    }
}

extension IOSFailedHistoryGuardedBaselineEvidence:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryGuardedBaselineEvidence(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Internal raw repository. App-facing reads are added only with policy
/// filtering and audio-availability projection in the integration checkpoint.
actor IOSFailedHistoryStore: IOSPendingRecordingFailedOwnershipInspecting {
    nonisolated let capabilityOwnerIdentity:
        IOSAcceptedHistoryCapabilityOwnerIdentity
    nonisolated let storeIdentity: IOSFailedHistoryStoreIdentity

    nonisolated var failedStoreIdentity: IOSFailedHistoryStoreIdentity {
        storeIdentity
    }
    private let journal: any IOSFailedHistoryJournalStoring
    private let now: @Sendable () -> Date
    private let operationGateBinding: IOSPersistenceOperationGateBinding
    private nonisolated let pendingStoreIdentityBinding:
        IOSFailedHistoryPendingStoreIdentityBinding
    private nonisolated let retryStateIdentityBinding:
        IOSFailedHistoryRetryStateIdentityBinding
    nonisolated let retryLiveOwnerState:
        IOSFailedHistoryRetryLiveOwnerState
    private let repositoryGuard:
        IOSAcceptedHistoryCoordinatorRepositoryGuard?
    nonisolated let mutationInterlock: IOSFailedHistoryMutationInterlock
    private var uncertainMutationIntent:
        IOSFailedHistoryUncertainMutationIntent?
    private var transferMutationIntent:
        IOSFailedHistoryTransferMutationIntent?
    private var rowRemovalMutationIntent:
        IOSFailedHistoryRowRemovalMutationIntent?
    private var audioCleanupMutationIntent:
        IOSFailedHistoryAudioCleanupMutationIntent?
    private var retryCancellationMutationIntent:
        IOSFailedHistoryRetryCancellationMutationIntent?
    private var retryMutationIntent: IOSFailedHistoryRetryMutationIntent?

    init(
        applicationSupportDirectoryURL: URL,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        storeIdentity: IOSFailedHistoryStoreIdentity =
            IOSFailedHistoryStoreIdentity(),
        operationGateIdentity: IOSPersistenceOperationGateIdentity? = nil,
        expectedPendingStoreIdentity:
            IOSPendingRecordingStoreIdentity? = nil,
        retryLiveOwnerState: IOSFailedHistoryRetryLiveOwnerState =
            IOSFailedHistoryRetryLiveOwnerState(),
        repositoryGuard:
            IOSAcceptedHistoryCoordinatorRepositoryGuard? = nil,
        mutationInterlock: IOSFailedHistoryMutationInterlock =
            IOSFailedHistoryMutationInterlock()
    ) {
        journal = FoundationIOSFailedHistoryJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            repositoryGuard: repositoryGuard
        )
        now = { Date() }
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        self.storeIdentity = storeIdentity
        operationGateBinding = IOSPersistenceOperationGateBinding(
            identity: operationGateIdentity
        )
        pendingStoreIdentityBinding =
            IOSFailedHistoryPendingStoreIdentityBinding(
                identity: expectedPendingStoreIdentity
            )
        self.retryLiveOwnerState = retryLiveOwnerState
        retryStateIdentityBinding =
            IOSFailedHistoryRetryStateIdentityBinding(
                identity: retryLiveOwnerState.identity
            )
        self.repositoryGuard = repositoryGuard
        self.mutationInterlock = mutationInterlock
    }

    init(
        journal: any IOSFailedHistoryJournalStoring,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        storeIdentity: IOSFailedHistoryStoreIdentity =
            IOSFailedHistoryStoreIdentity(),
        operationGateIdentity: IOSPersistenceOperationGateIdentity? = nil,
        expectedPendingStoreIdentity:
            IOSPendingRecordingStoreIdentity? = nil,
        retryLiveOwnerState: IOSFailedHistoryRetryLiveOwnerState =
            IOSFailedHistoryRetryLiveOwnerState(),
        repositoryGuard:
            IOSAcceptedHistoryCoordinatorRepositoryGuard? = nil,
        mutationInterlock: IOSFailedHistoryMutationInterlock =
            IOSFailedHistoryMutationInterlock(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.journal = journal
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        self.storeIdentity = storeIdentity
        operationGateBinding = IOSPersistenceOperationGateBinding(
            identity: operationGateIdentity
        )
        pendingStoreIdentityBinding =
            IOSFailedHistoryPendingStoreIdentityBinding(
                identity: expectedPendingStoreIdentity
            )
        self.retryLiveOwnerState = retryLiveOwnerState
        retryStateIdentityBinding =
            IOSFailedHistoryRetryStateIdentityBinding(
                identity: retryLiveOwnerState.identity
            )
        self.repositoryGuard = repositoryGuard
        self.mutationInterlock = mutationInterlock
        self.now = now
    }

    nonisolated func bindOperationGateIdentity(
        _ identity: IOSPersistenceOperationGateIdentity
    ) -> Bool {
        operationGateBinding.bind(identity)
    }

    nonisolated func bindExpectedPendingStoreIdentity(
        _ identity: IOSPendingRecordingStoreIdentity
    ) -> Bool {
        pendingStoreIdentityBinding.bind(identity)
    }

    nonisolated func bindRetryLiveOwnerStateIdentity(
        _ identity: IOSFailedHistoryRetryLiveOwnerStateIdentity
    ) -> Bool {
        retryStateIdentityBinding.bind(identity)
    }

    func sealProtectedAudioInventory(
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryProtectedAudioInventory {
        try requireActiveLease(operationLeaseAuthorization)
        try requireNoMutationUncertainty()
        guard transferMutationIntent == nil,
              !mutationInterlock.isBlocked,
              try requireExpectedPendingStoreIdentity()
                == expectedPendingStoreIdentity else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let repositoryBinding = try requireProductionRepositoryBinding()
        let source = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        guard let inventory = IOSFailedHistoryProtectedAudioInventory(
            mint: IOSFailedHistoryProtectedAudioInventoryMint(),
            failedSource: source,
            failedStoreIdentity: storeIdentity,
            expectedPendingStoreIdentity: expectedPendingStoreIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return inventory
    }

    func revalidateProtectedAudioInventory(
        _ inventory: IOSFailedHistoryProtectedAudioInventory,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws {
        try requireActiveLease(operationLeaseAuthorization)
        try requireNoMutationUncertainty()
        guard transferMutationIntent == nil,
              !mutationInterlock.isBlocked,
              inventory.failedStoreIdentity == storeIdentity,
              inventory.ownerIdentity == capabilityOwnerIdentity,
              inventory.operationLeaseAuthorization.provesSameActiveLease(
                  as: operationLeaseAuthorization
              ),
              try requireExpectedPendingStoreIdentity()
                == inventory.expectedPendingStoreIdentity else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard inventory.repositoryBinding == repositoryBinding,
              try loadJournalSnapshot(
                  repositoryBinding: repositoryBinding
              ) == inventory.failedSource else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    /// Applies the logical History filter without exposing cleanup ownership.
    /// Raw state remains app-private and future generations fail closed.
    func loadPolicyFilteredEntries(
        using policy: IOSHistoryPolicyReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> [IOSFailedHistoryEntry] {
        try requireActiveLease(operationLeaseAuthorization)
        guard policy.capabilityOwnerIdentity == capabilityOwnerIdentity else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let repositoryBinding = try currentRepositoryBinding()
        let source: IOSFailedHistoryJournalSnapshot?
        if let repositoryBinding {
            guard repositoryBinding.physicalRootIdentity != nil else {
                throw IOSFailedHistoryError.repositoryIdentityConflict
            }
            source = try loadJournalSnapshot(
                repositoryBinding: repositoryBinding
            )
        } else {
            source = try journal.load()
        }
        guard let source else {
            return []
        }
        try validatePolicyCutoverGenerations(
            source.envelope,
            using: policy
        )
        guard source.envelope.entries.isEmpty
                && source.envelope.audioCleanup.isEmpty
                || repositoryBinding?.physicalRootIdentity != nil else {
            throw IOSFailedHistoryError.repositoryIdentityConflict
        }
        guard policy.state.historyEnabled else { return [] }
        return source.envelope.entries.filter {
            $0.policyGeneration == policy.state.policyGeneration
        }
    }

    /// Freezes one explicit Retry without issuing provider authority. The
    /// returned authorization carries the exact failed-audio inventory so the
    /// Pending store can validate and open that row before this mutation is
    /// committed.
    func prepareRetryReservation(
        attemptID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration,
        using policy: IOSHistoryPolicyReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryReservationPreparation {
        try requireActiveLease(operationLeaseAuthorization)
        let configuration = try validatedRetryConfiguration(
            transcriptionConfiguration
        )
        guard policy.capabilityOwnerIdentity == capabilityOwnerIdentity else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        guard policy.state.historyEnabled else {
            throw IOSFailedHistoryError.stalePolicyGeneration
        }
        let repositoryBinding = try requireProductionRepositoryBinding()
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()

        if uncertainMutationIntent != nil {
            return try retainedRetryReservationPreparation(
                attemptID: attemptID,
                model: configuration.model,
                languageCode: configuration.languageCode,
                policy: policy,
                pendingStoreIdentity: pendingStoreIdentity,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        }

        try requireFreshRetryMutationAdmission()
        guard let source = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        try validatePolicyCutoverGenerations(
            source.envelope,
            using: policy
        )
        guard let candidate = source.envelope.entries.first(where: {
            $0.attemptID == attemptID
        }), candidate.policyGeneration == policy.state.policyGeneration,
              candidate.ownershipState == .ready,
              candidate.retryOperation == nil,
              source.envelope.entries.allSatisfy({
                  $0.retryOperation == nil
              }) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        guard source.envelope.audioCleanup.count
                < IOSFailedHistoryValidation.maximumAudioCleanupCount else {
            throw IOSFailedHistoryError.capacityExceeded
        }
        guard candidate.retryCount
                < IOSFailedHistoryValidation.maximumRetryCount else {
            throw IOSFailedHistoryError.retryCountOverflow
        }

        let reservationTime = try canonicalRetryTime(
            after: candidate.updatedAt
        )
        let operation = try makeRetryOperation(
            createdAt: reservationTime,
            state: .reserved
        )
        let reservedRow = try retryRow(
            replacing: candidate,
            updatedAt: reservationTime,
            retryCount: candidate.retryCount + 1,
            model: configuration.model,
            languageCode: configuration.languageCode,
            operation: operation
        )
        let outcome = try retryReplacementOutcome(
            source: source,
            candidate: candidate,
            replacement: reservedRow
        )
        return .commit(
            try retryReservationAuthorization(
                source: source,
                candidate: candidate,
                reservedRow: reservedRow,
                operation: operation,
                outcome: outcome,
                policy: policy,
                pendingStoreIdentity: pendingStoreIdentity,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        )
    }

    func commitRetryReservation(
        using authorization:
            IOSFailedHistoryRetryReservationAuthorization,
        validatedAudio:
            IOSFailedHistoryRetryAudioValidationReceipt
    ) throws -> IOSFailedHistoryRetryReservationReceipt {
        try validateRetryReservationAuthorization(authorization)
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard validatedAudio.provesHeld(
            for: authorization,
            failedStoreIdentity: storeIdentity,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization:
                authorization.operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        if let uncertainMutationIntent {
            guard case .reservation(let retained) = retryMutationIntent,
                  uncertainMutationIntent.outcome == retained.outcome,
                  retained.identifiesSameReservation(
                      as: authorization
                  ) else {
                throw IOSFailedHistoryError.commitUncertain
            }
        } else {
            try requireFreshRetryMutationAdmission()
        }
        retryMutationIntent = .reservation(authorization)
        do {
            let capability = try reserveExactMutation(
                authorization.outcome,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
            if uncertainMutationIntent == nil {
                guard capability.source == .existing(
                    authorization.failedSource
                ) else {
                    throw IOSFailedHistoryError.compareAndSwapFailed
                }
            }
            let receipt = try commitExactMutation(capability)
            return try retryReservationReceipt(
                authorization: authorization,
                mutationReceipt: receipt,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
        } catch {
            if uncertainMutationIntent == nil {
                retryMutationIntent = nil
            }
            throw error
        }
    }

    /// Publishes the durable provider-launch boundary. A caller may launch
    /// only from the returned exact receipt and its live-owner token.
    func prepareRetryDispatch(
        using reservationReceipt:
            IOSFailedHistoryRetryReservationReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryDispatchPreparation {
        try requireActiveLease(operationLeaseAuthorization)
        let repositoryBinding = try requireProductionRepositoryBinding()
        try validateRetryReservationReceipt(
            reservationReceipt,
            repositoryBinding: repositoryBinding
        )
        if uncertainMutationIntent != nil {
            return try retainedRetryDispatchPreparation(
                reservationReceipt: reservationReceipt,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        }

        guard reservationReceipt.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }

        try requireFreshRetryMutationAdmission()
        let source = reservationReceipt.durableSnapshot
        let dispatchedOperation = try retryOperation(
            replacingStateOf: reservationReceipt.retryOperation,
            with: .providerDispatched
        )
        let dispatchedRow = try retryRow(
            replacing: reservationReceipt.row,
            updatedAt: reservationReceipt.row.updatedAt,
            retryCount: reservationReceipt.row.retryCount,
            model: reservationReceipt.row.transcriptionModel,
            languageCode:
                reservationReceipt.row.transcriptionLanguageCode,
            operation: dispatchedOperation
        )
        let outcome = try retryReplacementOutcome(
            source: source,
            candidate: reservationReceipt.row,
            replacement: dispatchedRow
        )
        let authorization = try retryDispatchAuthorization(
            reservationReceipt: reservationReceipt,
            source: source,
            dispatchedRow: dispatchedRow,
            operation: dispatchedOperation,
            outcome: outcome,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        )
        guard let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        if current.envelope == outcome,
           current != source {
            return .completed(
                try retryDispatchReceipt(
                    authorization: authorization,
                    durableSnapshot: current,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
            )
        }
        guard current == source else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return .commit(authorization)
    }

    func commitRetryDispatch(
        using authorization: IOSFailedHistoryRetryDispatchAuthorization
    ) throws -> IOSFailedHistoryRetryDispatchReceipt {
        try validateRetryDispatchAuthorization(authorization)
        if let uncertainMutationIntent {
            guard case .dispatch(let retained) = retryMutationIntent,
                  uncertainMutationIntent.outcome == retained.outcome,
                  retained.identifiesSameDispatch(as: authorization) else {
                throw IOSFailedHistoryError.commitUncertain
            }
        } else {
            try requireFreshRetryMutationAdmission()
        }
        retryMutationIntent = .dispatch(authorization)
        do {
            let capability = try reserveExactMutation(
                authorization.outcome,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
            if uncertainMutationIntent == nil {
                guard capability.source == .existing(
                    authorization.failedSource
                ) else {
                    throw IOSFailedHistoryError.compareAndSwapFailed
                }
            }
            let receipt = try commitExactMutation(capability)
            return try retryDispatchReceipt(
                authorization: authorization,
                durableSnapshot: receipt.snapshot,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
        } catch {
            if uncertainMutationIntent == nil {
                retryMutationIntent = nil
            }
            throw error
        }
    }

    func prepareRetryCancellation(
        using reservationReceipt:
            IOSFailedHistoryRetryReservationReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryCancellationPreparation {
        try prepareRetryCancellation(
            sourceReceipt: .reservation(reservationReceipt),
            providerCancellationClaim: nil,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        )
    }

    func prepareRetryCancellation(
        using dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        providerCancellationClaim:
            IOSFailedHistoryRetryProviderCancellationClaim,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryCancellationPreparation {
        try prepareRetryCancellation(
            sourceReceipt: .dispatch(dispatchReceipt),
            providerCancellationClaim: providerCancellationClaim,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        )
    }

    func commitRetryCancellation(
        using authorization:
            IOSFailedHistoryRetryCancellationAuthorization
    ) throws -> IOSFailedHistoryRetryCancellationReceipt {
        try validateRetryCancellationAuthorization(authorization)
        if let uncertainMutationIntent {
            guard case .cancellation(let retained) = retryMutationIntent,
                  uncertainMutationIntent.outcome == retained.outcome,
                  retained.identifiesSameCancellation(
                      as: authorization
                  ) else {
                throw IOSFailedHistoryError.commitUncertain
            }
        } else {
            try requireFreshRetryMutationAdmission()
        }
        retryMutationIntent = .cancellation(authorization)
        do {
            let capability = try reserveExactMutation(
                authorization.outcome,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
            if uncertainMutationIntent == nil {
                guard capability.source == .existing(
                    authorization.failedSource
                ) else {
                    throw IOSFailedHistoryError.compareAndSwapFailed
                }
            }
            let receipt = try commitExactMutation(capability)
            return try retryCancellationReceipt(
                authorization: authorization,
                durableSnapshot: receipt.snapshot,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
        } catch {
            if uncertainMutationIntent == nil {
                retryMutationIntent = nil
            }
            throw error
        }
    }

    /// Prepares the exact durable failure transition for a provider-completed
    /// Retry. The retry count and operation identity cannot be advanced here.
    func prepareRetryFailure(
        using dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        providerCompletionClaim:
            IOSFailedHistoryRetryProviderCompletionClaim,
        disposition: IOSFailedHistoryRetryFailureDisposition,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryFailurePreparation {
        try requireActiveLease(operationLeaseAuthorization)
        let repositoryBinding = try requireProductionRepositoryBinding()
        try validateRetryDispatchReceipt(
            dispatchReceipt,
            repositoryBinding: repositoryBinding
        )
        guard providerCompletionClaim.liveOwnerToken
                == dispatchReceipt.liveOwnerToken else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        if uncertainMutationIntent != nil {
            return try retainedRetryFailurePreparation(
                dispatchReceipt: dispatchReceipt,
                providerCompletionClaim: providerCompletionClaim,
                disposition: disposition,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        }

        try requireFreshRetryMutationAdmission()
        let source = dispatchReceipt.durableSnapshot
        guard let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        ), current == source else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let retainedRow = try retryFailureRow(
            replacing: dispatchReceipt.row,
            disposition: disposition,
            updatedAt: try canonicalRetryTime(
                after: dispatchReceipt.row.updatedAt
            )
        )
        let outcome = try retryReplacementOutcome(
            source: source,
            candidate: dispatchReceipt.row,
            replacement: retainedRow
        )
        return .commit(
            try retryFailureAuthorization(
                dispatchReceipt: dispatchReceipt,
                providerCompletionClaim: providerCompletionClaim,
                disposition: disposition,
                source: source,
                retainedRow: retainedRow,
                outcome: outcome,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        )
    }

    func commitRetryFailure(
        using authorization: IOSFailedHistoryRetryFailureAuthorization
    ) throws -> IOSFailedHistoryRetryFailureReceipt {
        try validateRetryFailureAuthorization(authorization)
        if let uncertainMutationIntent {
            guard case .failure(let retained) = retryMutationIntent,
                  uncertainMutationIntent.outcome == retained.outcome,
                  retained.identifiesSameFailure(as: authorization) else {
                throw IOSFailedHistoryError.commitUncertain
            }
        } else {
            try requireFreshRetryMutationAdmission()
        }
        retryMutationIntent = .failure(authorization)
        do {
            let capability = try reserveExactMutation(
                authorization.outcome,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
            if uncertainMutationIntent == nil {
                guard capability.source == .existing(
                    authorization.failedSource
                ) else {
                    throw IOSFailedHistoryError.compareAndSwapFailed
                }
            }
            let receipt = try commitExactMutation(capability)
            return try retryFailureReceipt(
                authorization: authorization,
                durableSnapshot: receipt.snapshot,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
        } catch {
            if uncertainMutationIntent == nil {
                retryMutationIntent = nil
            }
            throw error
        }
    }

    func prepareRetryAcceptingOutput(
        using dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        providerCompletionClaim:
            IOSFailedHistoryRetryProviderCompletionClaim,
        frozenSlotProof: IOSAcceptedOutputDeliveryFrozenSlotProof,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryAcceptingOutputPreparation {
        try requireActiveLease(operationLeaseAuthorization)
        let repositoryBinding = try requireProductionRepositoryBinding()
        try validateRetryDispatchReceipt(
            dispatchReceipt,
            repositoryBinding: repositoryBinding
        )
        guard providerCompletionClaim.liveOwnerToken
                == dispatchReceipt.liveOwnerToken,
              frozenSlotProof.retryingRow == dispatchReceipt.row,
              frozenSlotProof.retryOperation
                == dispatchReceipt.retryOperation,
              frozenSlotProof.ownerIdentity == capabilityOwnerIdentity,
              frozenSlotProof.repositoryBinding == repositoryBinding,
              frozenSlotProof.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }

        if uncertainMutationIntent != nil {
            return try retainedRetryAcceptingOutputPreparation(
                dispatchReceipt: dispatchReceipt,
                providerCompletionClaim: providerCompletionClaim,
                frozenSlotProof: frozenSlotProof,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        }

        let acceptingOperation = try retryOperation(
            replacingStateOf: dispatchReceipt.retryOperation,
            with: .acceptingOutput
        )
        let acceptingRow = try retryRow(
            replacing: dispatchReceipt.row,
            updatedAt: dispatchReceipt.row.updatedAt,
            retryCount: dispatchReceipt.row.retryCount,
            model: dispatchReceipt.row.transcriptionModel,
            languageCode: dispatchReceipt.row.transcriptionLanguageCode,
            operation: acceptingOperation
        )
        let outcome = try retryReplacementOutcome(
            source: dispatchReceipt.durableSnapshot,
            candidate: dispatchReceipt.row,
            replacement: acceptingRow
        )
        let authorization = try retryAcceptingOutputAuthorization(
            dispatchReceipt: dispatchReceipt,
            providerCompletionClaim: providerCompletionClaim,
            frozenSlotProof: frozenSlotProof,
            acceptingRow: acceptingRow,
            acceptingOperation: acceptingOperation,
            outcome: outcome,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        )

        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if let current, current.envelope == outcome,
           current != dispatchReceipt.durableSnapshot {
            guard mutationInterlock.upgradeRetryDeliveryFreeze(
                frozenSlotProof.freezeReservation,
                to: authorization.relationKey
            ) else {
                throw IOSFailedHistoryError.commitUncertain
            }
            return .completed(
                try retryAcceptingOutputReceipt(
                    authorization: authorization,
                    durableSnapshot: current,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
            )
        }
        try requireFreshRetryAcceptingOutputAdmission(
            frozenSlotProof.freezeReservation,
            relationKey: authorization.relationKey,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard current == dispatchReceipt.durableSnapshot else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return .commit(authorization)
    }

    func commitRetryAcceptingOutput(
        using authorization:
            IOSFailedHistoryRetryAcceptingOutputAuthorization
    ) throws -> IOSFailedHistoryRetryAcceptingOutputReceipt {
        try validateRetryAcceptingOutputAuthorization(authorization)
        if let uncertainMutationIntent {
            guard case .acceptingOutput(let retained) = retryMutationIntent,
                  uncertainMutationIntent.outcome == retained.outcome,
                  retained.identifiesSameAcceptance(as: authorization) else {
                throw IOSFailedHistoryError.commitUncertain
            }
        } else {
            try requireFreshRetryAcceptingOutputAdmission(
                authorization.frozenSlotProof.freezeReservation,
                relationKey: authorization.relationKey,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
        }
        guard mutationInterlock.upgradeRetryDeliveryFreeze(
            authorization.frozenSlotProof.freezeReservation,
            to: authorization.relationKey
        ) else {
            throw IOSFailedHistoryError.commitUncertain
        }
        retryMutationIntent = .acceptingOutput(authorization)
        do {
            let capability = try reserveExactMutation(
                authorization.outcome,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
            if uncertainMutationIntent == nil {
                guard capability.source == .existing(
                    authorization.failedSource
                ) else {
                    throw IOSFailedHistoryError.compareAndSwapFailed
                }
            }
            let receipt = try commitExactMutation(capability)
            return try retryAcceptingOutputReceipt(
                authorization: authorization,
                durableSnapshot: receipt.snapshot,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
        } catch {
            if uncertainMutationIntent == nil {
                retryMutationIntent = nil
                _ = mutationInterlock.clearRetryDeliveryRelation(
                    authorization.relationKey,
                    freezeReservation: authorization.frozenSlotProof
                        .freezeReservation
                )
            }
            throw error
        }
    }

    func prepareRetrySuccess(
        using acceptingOutputReceipt:
            IOSFailedHistoryRetryAcceptingOutputReceipt,
        terminalDeliveryProof: IOSFailedHistoryRetryTerminalDeliveryProof,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetrySuccessPreparation {
        try requireActiveLease(operationLeaseAuthorization)
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard acceptingOutputReceipt.failedStoreIdentity == storeIdentity,
              acceptingOutputReceipt.ownerIdentity
                == capabilityOwnerIdentity,
              acceptingOutputReceipt.repositoryBinding == repositoryBinding,
              acceptingOutputReceipt.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              terminalDeliveryProof.acceptingOutputReceipt
                == acceptingOutputReceipt,
              terminalDeliveryProof.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              mutationInterlock.permitsRetryDeliveryRelation(
                  acceptingOutputReceipt.relationKey,
                  freezeReservation: acceptingOutputReceipt
                    .frozenSlotProof.freezeReservation,
                  operationLeaseAuthorization:
                      operationLeaseAuthorization
              ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }

        if uncertainMutationIntent != nil {
            return try retainedRetrySuccessPreparation(
                acceptingOutputReceipt: acceptingOutputReceipt,
                terminalDeliveryProof: terminalDeliveryProof,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        }
        guard let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        ), current == acceptingOutputReceipt.durableSnapshot else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let tombstone = try IOSFailedHistoryAudioCleanup(
            attemptID: acceptingOutputReceipt.row.attemptID,
            policyGeneration: acceptingOutputReceipt.row.policyGeneration,
            queuedAt: try canonicalRetryTime(
                after: acceptingOutputReceipt.row.updatedAt
            ),
            audioRelativeIdentifier:
                acceptingOutputReceipt.row.audioRelativeIdentifier,
            byteCount: acceptingOutputReceipt.row.byteCount
        )
        guard let candidateIndex = current.envelope.entries.firstIndex(
            of: acceptingOutputReceipt.row
        ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        var entries = current.envelope.entries
        entries.remove(at: candidateIndex)
        let nextRevision = current.envelope.revision.addingReportingOverflow(1)
        guard !nextRevision.overflow else {
            throw IOSFailedHistoryError.revisionOverflow
        }
        let outcome = try IOSFailedHistoryEnvelope(
            revision: nextRevision.partialValue,
            entries: entries,
            audioCleanup: IOSFailedHistoryValidation.sortedAudioCleanup(
                current.envelope.audioCleanup + [tombstone]
            )
        )
        guard let authorization = IOSFailedHistoryRetrySuccessAuthorization(
            mint: IOSFailedHistoryRetrySuccessAuthorizationMint(),
            acceptingOutputReceipt: acceptingOutputReceipt,
            terminalDeliveryProof: terminalDeliveryProof,
            tombstone: tombstone,
            outcome: outcome,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return .commit(authorization)
    }

    /// Refreshes the historical accepting receipt only when the exact next
    /// success mutation is already retained as commit-uncertain. This does not
    /// change the retained success phase or authorize a new provider result;
    /// it lets the same terminal delivery re-enter success reconciliation
    /// under the current root lease.
    func refreshRetryAcceptingOutputReceiptForRetainedSuccess(
        from previousReceipt:
            IOSFailedHistoryRetryAcceptingOutputReceipt,
        frozenSlotProof: IOSAcceptedOutputDeliveryFrozenSlotProof,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryAcceptingOutputReceipt? {
        try requireActiveLease(operationLeaseAuthorization)
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard let uncertainMutationIntent else { return nil }
        guard case .success(let retained) = retryMutationIntent,
              uncertainMutationIntent.outcome == retained.outcome,
              retained.acceptingOutputReceipt.relationKey
                == previousReceipt.relationKey,
              retained.acceptingOutputReceipt.durableSnapshot
                == previousReceipt.durableSnapshot,
              retained.acceptingOutputReceipt.frozenSlotProof.preparation
                == frozenSlotProof.preparation,
              retained.acceptingOutputReceipt.frozenSlotProof.frozenSlot
                == frozenSlotProof.frozenSlot,
              mutationInterlock.permitsRetryDeliveryRelation(
                  previousReceipt.relationKey,
                  freezeReservation: previousReceipt.frozenSlotProof
                    .freezeReservation,
                  operationLeaseAuthorization:
                      operationLeaseAuthorization
              ) else {
            return nil
        }
        let retainedAuthorization = retained.acceptingOutputReceipt
            .authorization
        let refreshedAuthorization = try retryAcceptingOutputAuthorization(
            dispatchReceipt: retainedAuthorization.dispatchReceipt,
            providerCompletionClaim:
                retainedAuthorization.providerCompletionClaim,
            frozenSlotProof: frozenSlotProof,
            acceptingRow: retainedAuthorization.acceptingRow,
            acceptingOperation:
                retainedAuthorization.acceptingOperation,
            outcome: retainedAuthorization.outcome,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        )
        guard refreshedAuthorization.relationKey
                == previousReceipt.relationKey else {
            throw IOSFailedHistoryError.commitUncertain
        }
        return try retryAcceptingOutputReceipt(
            authorization: refreshedAuthorization,
            durableSnapshot:
                retained.acceptingOutputReceipt.durableSnapshot,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        )
    }

    func commitRetrySuccess(
        using authorization: IOSFailedHistoryRetrySuccessAuthorization
    ) throws -> IOSFailedHistoryRetrySuccessReceipt {
        try validateRetrySuccessAuthorization(authorization)
        if let uncertainMutationIntent {
            guard case .success(let retained) = retryMutationIntent,
                  uncertainMutationIntent.outcome == retained.outcome,
                  retained.identifiesSameSuccess(as: authorization) else {
                throw IOSFailedHistoryError.commitUncertain
            }
        }
        guard mutationInterlock.permitsRetryDeliveryRelation(
            authorization.acceptingOutputReceipt.relationKey,
            freezeReservation: authorization.acceptingOutputReceipt
                .frozenSlotProof.freezeReservation,
            operationLeaseAuthorization:
                authorization.operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.commitUncertain
        }
        retryMutationIntent = .success(authorization)
        let capability = try reserveExactMutation(
            authorization.outcome,
            operationLeaseAuthorization:
                authorization.operationLeaseAuthorization
        )
        if uncertainMutationIntent == nil {
            guard capability.source == .existing(
                authorization.failedSource
            ) else {
                retryMutationIntent = nil
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
        }
        do {
            let mutationReceipt = try commitExactMutation(capability)
            guard let receipt = IOSFailedHistoryRetrySuccessReceipt(
                mint: IOSFailedHistoryRetrySuccessReceiptMint(),
                authorization: authorization,
                durableSnapshot: mutationReceipt.snapshot,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            ), mutationInterlock.clearRetryDeliveryRelation(
                authorization.acceptingOutputReceipt.relationKey,
                freezeReservation: authorization.acceptingOutputReceipt
                    .frozenSlotProof.freezeReservation
            ) else {
                throw IOSFailedHistoryError.commitUncertain
            }
            return receipt
        } catch {
            if uncertainMutationIntent == nil {
                retryMutationIntent = nil
            }
            throw error
        }
    }

    /// Returns registration identity for the sole exact durable Retry, if one
    /// exists. It grants no provider, mutation, delivery, or filesystem
    /// authority and accepts no caller-provided row or identifier.
    func prepareRetryLiveOwnerToken(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryLiveOwnerToken? {
        try requireActiveLease(operationLeaseAuthorization)
        try requireNoMutationUncertainty()
        guard transferMutationIntent == nil,
              rowRemovalMutationIntent == nil,
              retryCancellationMutationIntent == nil,
              audioCleanupMutationIntent == nil,
              !mutationInterlock.isBlocked else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let repositoryBinding = try requireProductionRepositoryBinding()
        let source = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        guard let source,
              let row = source.envelope.entries.first(where: {
                $0.retryOperation != nil
              }) else {
            return nil
        }
        guard let token = IOSFailedHistoryRetryLiveOwnerToken(
            mint: IOSFailedHistoryRetryLiveOwnerTokenMint(),
            failedSource: source,
            row: row,
            failedStoreIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            retryStateIdentity: try requireExpectedRetryStateIdentity(),
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        return token
    }

    /// Selects exactly one provider-free failed-domain cutover action. Future
    /// rows or tombstones are rejected before cleanup interlocks are retained.
    func preparePolicyCutoverDirective(
        using policy: IOSHistoryPolicyReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryPolicyCutoverDirective {
        try requireActiveLease(operationLeaseAuthorization)
        guard policy.capabilityOwnerIdentity == capabilityOwnerIdentity else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let provisionalRepositoryBinding = try currentRepositoryBinding()
        let source: IOSFailedHistoryJournalSnapshot?
        if let provisionalRepositoryBinding {
            guard provisionalRepositoryBinding.physicalRootIdentity != nil
            else {
                throw IOSFailedHistoryError.repositoryIdentityConflict
            }
            source = try loadJournalSnapshot(
                repositoryBinding: provisionalRepositoryBinding
            )
        } else {
            source = try journal.load()
        }
        if let source {
            try validatePolicyCutoverGenerations(
                source.envelope,
                using: policy
            )
        }

        if source == nil
            || source?.envelope.entries.isEmpty == true
                && source?.envelope.audioCleanup.isEmpty == true {
            guard uncertainMutationIntent == nil,
                  transferMutationIntent == nil,
                  rowRemovalMutationIntent == nil,
                  retryCancellationMutationIntent == nil,
                  audioCleanupMutationIntent == nil,
                  !mutationInterlock.isBlocked else {
                throw IOSFailedHistoryError.commitUncertain
            }
            return .complete
        }

        guard let repositoryBinding = provisionalRepositoryBinding,
              repositoryBinding.physicalRootIdentity != nil else {
            throw IOSFailedHistoryError.repositoryIdentityConflict
        }
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()

        if uncertainMutationIntent != nil {
            return try retainedPolicyCutoverDirective(
                current: source,
                policy: policy,
                pendingStoreIdentity: pendingStoreIdentity,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        }

        guard transferMutationIntent == nil,
              rowRemovalMutationIntent == nil,
              retryCancellationMutationIntent == nil,
              audioCleanupMutationIntent == nil,
              !mutationInterlock.isBlocked else {
            throw IOSFailedHistoryError.commitUncertain
        }
        guard let source else { return .complete }

        if let row = source.envelope.entries.first(where: {
            $0.ownershipState == .pendingJournalRetirement
        }) {
            guard let authority =
                    IOSFailedHistoryPendingMetadataRetirementAuthority(
                        mint:
                            IOSFailedHistoryMetadataRetirementAuthorityMint(),
                        failedSource: source,
                        row: row,
                        origin: .relaunched,
                        failedStoreIdentity: storeIdentity,
                        expectedPendingStoreIdentity:
                            pendingStoreIdentity,
                        ownerIdentity: capabilityOwnerIdentity,
                        repositoryBinding: repositoryBinding,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    ) else {
                throw IOSFailedHistoryError.invalidTransition
            }
            return .retirePendingMetadata(authority)
        }

        if let retryRow = source.envelope.entries.first(where: {
            $0.policyGeneration < policy.state.policyGeneration
                && $0.retryOperation != nil
        }) {
            guard let retryOperation = retryRow.retryOperation else {
                throw IOSFailedHistoryError.invalidTransition
            }
            if retryOperation.state == .acceptingOutput {
                return .blockedAcceptingOutput
            }
            guard let liveOwnerToken = IOSFailedHistoryRetryLiveOwnerToken(
                    mint: IOSFailedHistoryRetryLiveOwnerTokenMint(),
                    failedSource: source,
                    row: retryRow,
                    failedStoreIdentity: storeIdentity,
                    ownerIdentity: capabilityOwnerIdentity,
                    retryStateIdentity:
                        try requireExpectedRetryStateIdentity(),
                    repositoryBinding: repositoryBinding,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                  ), let inspection =
                    IOSFailedHistoryRetryRecoveryInspection(
                        mint:
                            IOSFailedHistoryRetryRecoveryInspectionMint(),
                        liveOwnerToken: liveOwnerToken,
                        policyReceipt: policy,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    ) else {
                throw IOSFailedHistoryError.invalidTransition
            }
            return .inspectProcessLostRetry(inspection)
        }

        if let tombstone = source.envelope.audioCleanup.first {
            let authorization = try audioCleanupAuthorization(
                source: source,
                tombstone: tombstone,
                outcome: audioCleanupOutcome(
                    source: source,
                    tombstone: tombstone
                ),
                purpose: .nextHead,
                operationID: IOSFailedHistoryAudioCleanupOperationID(),
                pendingStoreIdentity: pendingStoreIdentity,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
            guard mutationInterlock.retainAudioCleanup(
                using: authorization
            ) else {
                throw IOSFailedHistoryError.commitUncertain
            }
            return .recoverAudioCleanup(authorization)
        }

        guard let candidate = source.envelope.entries.last(where: {
            $0.policyGeneration < policy.state.policyGeneration
        }) else {
            return .complete
        }
        let removal = try rowRemovalOutcome(
            source: source,
            candidate: candidate,
            queuedAt: now()
        )
        let authorization = try rowAudioValidationAuthorization(
            source: source,
            candidate: candidate,
            tombstone: removal.tombstone,
            outcome: removal.outcome,
            purpose: .policyCutover(policy),
            pendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        )
        return .invalidateReadyRow(authorization)
    }

    /// Converts an exact process-loss observation into one frozen retry
    /// cancellation outcome. No provider authority crosses this boundary.
    func preparePolicyRetryCancellation(
        inspection: IOSFailedHistoryRetryRecoveryInspection,
        reservation: IOSFailedHistoryRetryCancellationReservation,
        using policy: IOSHistoryPolicyReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryPolicyRetryCancellationPreparation {
        try requireActiveLease(operationLeaseAuthorization)
        let repositoryBinding = try requireProductionRepositoryBinding()
        let retryStateIdentity = try requireExpectedRetryStateIdentity()
        guard policy.capabilityOwnerIdentity == capabilityOwnerIdentity,
              inspection.policyReceipt == policy,
              inspection.failedStoreIdentity == storeIdentity,
              inspection.ownerIdentity == capabilityOwnerIdentity,
              inspection.repositoryBinding == repositoryBinding,
              inspection.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              reservation.inspection == inspection,
              reservation.stateIdentity == retryStateIdentity,
              reservation.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if let current {
            try validatePolicyCutoverGenerations(
                current.envelope,
                using: policy
            )
        }

        if let uncertainMutationIntent {
            guard let intent = retryCancellationMutationIntent,
                  uncertainMutationIntent.outcome == intent.outcome,
                  intent.authorization.identifiesSameCancellation(
                    as: try policyRetryCancellationAuthorization(
                        inspection: inspection,
                        reservation: reservation,
                        outcome: intent.outcome,
                        repositoryBinding: repositoryBinding,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                  ) else {
                throw IOSFailedHistoryError.commitUncertain
            }
            if current?.envelope == intent.outcome,
               current != inspection.failedSource {
                let receipt = try commitExactMutation(
                    reserveExactMutation(
                        intent.outcome,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                )
                return .completed(
                    try policyRetryCancellationCompletionAuthorization(
                        reservation: reservation,
                        outcome: intent.outcome,
                        receipt: receipt,
                        repositoryBinding: repositoryBinding,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                )
            }
            guard current == inspection.failedSource else {
                throw IOSFailedHistoryError.commitUncertain
            }
            return .commit(
                try policyRetryCancellationAuthorization(
                    inspection: inspection,
                    reservation: reservation,
                    outcome: intent.outcome,
                    repositoryBinding: repositoryBinding,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
            )
        }

        guard transferMutationIntent == nil,
              rowRemovalMutationIntent == nil,
              retryCancellationMutationIntent == nil,
              audioCleanupMutationIntent == nil,
              !mutationInterlock.isBlocked,
              current == inspection.failedSource else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let outcome = try retryCancellationOutcome(
            source: inspection.failedSource,
            row: inspection.row
        )
        return .commit(
            try policyRetryCancellationAuthorization(
                inspection: inspection,
                reservation: reservation,
                outcome: outcome,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        )
    }

    func commitPolicyRetryCancellation(
        using authorization:
            IOSFailedHistoryPolicyRetryCancellationAuthorization
    ) throws -> IOSFailedHistoryRetryCancellationCompletionAuthorization {
        try requireActiveLease(
            authorization.operationLeaseAuthorization
        )
        try validatePolicyRetryCancellationAuthorization(authorization)
        if let uncertainMutationIntent {
            guard let intent = retryCancellationMutationIntent,
                  uncertainMutationIntent.outcome == intent.outcome,
                  intent.authorization.identifiesSameCancellation(
                    as: authorization
                  ) else {
                throw IOSFailedHistoryError.commitUncertain
            }
        } else {
            guard transferMutationIntent == nil,
                  rowRemovalMutationIntent == nil,
                  retryCancellationMutationIntent == nil,
                  audioCleanupMutationIntent == nil,
                  !mutationInterlock.isBlocked else {
                throw IOSFailedHistoryError.commitUncertain
            }
        }
        retryCancellationMutationIntent =
            IOSFailedHistoryRetryCancellationMutationIntent(
                authorization: authorization,
                outcome: authorization.outcome
            )
        do {
            let capability = try reserveExactMutation(
                authorization.outcome,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
            if uncertainMutationIntent == nil {
                guard capability.source == .existing(
                    authorization.inspection.failedSource
                ) else {
                    throw IOSFailedHistoryError.compareAndSwapFailed
                }
            }
            let receipt = try commitExactMutation(capability)
            return try policyRetryCancellationCompletionAuthorization(
                reservation: authorization.reservation,
                outcome: authorization.outcome,
                receipt: receipt,
                repositoryBinding: authorization.repositoryBinding,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
        } catch {
            if uncertainMutationIntent == nil {
                retryCancellationMutationIntent = nil
            }
            throw error
        }
    }

    /// Reissues only a completion whose exact retryOperation-nil outcome is
    /// still the durable failed root. This is the sole inactive-lease path for
    /// consuming a retained process-local cancellation reservation.
    func refreshPolicyRetryCancellationCompletion(
        _ retained:
            IOSFailedHistoryRetryCancellationCompletionAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryCancellationCompletionAuthorization {
        try requireActiveLease(operationLeaseAuthorization)
        let repositoryBinding = try requireProductionRepositoryBinding()
        let retryStateIdentity = try requireExpectedRetryStateIdentity()
        guard retained.failedStoreIdentity == storeIdentity,
              retained.ownerIdentity == capabilityOwnerIdentity,
              retained.repositoryBinding == repositoryBinding,
              retained.reservation.stateIdentity
                == retryStateIdentity,
              let current = try loadJournalSnapshot(
                repositoryBinding: repositoryBinding
              ), current.envelope == retained.outcome,
              try retryCancellationOutcome(
                source: retained.reservation.inspection.failedSource,
                row: retained.reservation.inspection.row
              ) == retained.outcome,
              let completion =
                IOSFailedHistoryRetryCancellationCompletionAuthorization(
                    mint:
                        IOSFailedHistoryRetryCancellationCompletionAuthorizationMint(),
                    reservation: retained.reservation,
                    outcome: retained.outcome,
                    failedStoreIdentity: storeIdentity,
                    ownerIdentity: capabilityOwnerIdentity,
                    repositoryBinding: repositoryBinding,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return completion
    }

    func commitPolicyInvalidation(
        using validatedAudio: IOSFailedHistoryValidatedRowAudio
    ) async throws {
        let authorization = validatedAudio.authorization
        try requireActiveLease(
            authorization.operationLeaseAuthorization
        )
        guard case .policyCutover(let policy) = authorization.purpose,
              policy.capabilityOwnerIdentity == capabilityOwnerIdentity,
              authorization.candidate.policyGeneration
                < policy.state.policyGeneration,
              !mutationInterlock.isCleanupBlocked else {
            throw IOSFailedHistoryError.invalidTransition
        }
        if let uncertainMutationIntent {
            guard let intent = rowRemovalMutationIntent,
                  uncertainMutationIntent.outcome == intent.outcome,
                  identifiesSameRowMutation(
                    intent.authorization,
                    authorization
                  ) else {
                throw IOSFailedHistoryError.commitUncertain
            }
        } else {
            guard transferMutationIntent == nil,
                  rowRemovalMutationIntent == nil,
                  retryCancellationMutationIntent == nil,
                  audioCleanupMutationIntent == nil,
                  !mutationInterlock.isBlocked else {
                throw IOSFailedHistoryError.commitUncertain
            }
        }
        try await validatedAudio.revalidate()
        try validateRowAudioAuthorization(authorization)
        rowRemovalMutationIntent = IOSFailedHistoryRowRemovalMutationIntent(
            authorization: authorization,
            outcome: authorization.outcome
        )
        do {
            let capability = try reserveExactMutation(
                authorization.outcome,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
            if uncertainMutationIntent == nil {
                guard capability.source == .existing(
                    authorization.failedSource
                ) else {
                    throw IOSFailedHistoryError.compareAndSwapFailed
                }
            }
            _ = try commitExactMutation(capability)
        } catch {
            if uncertainMutationIntent == nil {
                rowRemovalMutationIntent = nil
            }
            throw error
        }
    }

    func prepareDelete(
        attemptID: UUID,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRowAudioValidationAuthorization {
        try requireActiveLease(operationLeaseAuthorization)
        try requireNoMutationUncertainty()
        guard transferMutationIntent == nil,
              rowRemovalMutationIntent == nil,
              !mutationInterlock.isBlocked else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard let source = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        ), let candidate = source.envelope.entries.first(where: {
            $0.attemptID == attemptID
        }) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let removal = try rowRemovalOutcome(
            source: source,
            candidate: candidate,
            queuedAt: now()
        )
        return try rowAudioValidationAuthorization(
            source: source,
            candidate: candidate,
            tombstone: removal.tombstone,
            outcome: removal.outcome,
            purpose: .delete,
            pendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    /// Returns nil below capacity. At capacity the absolute canonical oldest
    /// row is the only candidate; an unsafe oldest row never falls through.
    func prepareRetention(
        for preparation: IOSPendingFailedHistoryTransferPreparation
    ) throws -> IOSFailedHistoryRowAudioValidationAuthorization? {
        let authorization = preparation.operationLeaseAuthorization
        try requireActiveLease(authorization)
        try requireNoMutationUncertainty()
        guard transferMutationIntent == nil,
              rowRemovalMutationIntent == nil,
              !mutationInterlock.isBlocked else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        try validate(
            preparation,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding
        )
        guard let source = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        ) else {
            return nil
        }
        guard source.envelope.entries.count
                == IOSFailedHistoryValidation.maximumEntryCount else {
            return nil
        }
        let retention = try retentionOutcome(
            source: source,
            preparation: preparation,
            queuedAt: preparation.intendedRow.updatedAt
        )
        return try rowAudioValidationAuthorization(
            source: source,
            candidate: retention.candidate,
            tombstone: retention.tombstone,
            outcome: retention.outcome,
            purpose: .retention(preparation),
            pendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: authorization
        )
    }

    /// Reissues only an exact source-visible row-audio check. Outcome-visible
    /// uncertainty is confirmed by the matching commit API without reopening
    /// or revalidating the evicted audio.
    func refreshRowAudioValidationAuthorization(
        _ retained: IOSFailedHistoryRowAudioValidationAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRowAudioValidationAuthorization {
        try requireActiveLease(operationLeaseAuthorization)
        guard !mutationInterlock.isCleanupBlocked else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard retained.failedStoreIdentity == storeIdentity,
              retained.expectedPendingStoreIdentity == pendingStoreIdentity,
              retained.ownerIdentity == capabilityOwnerIdentity,
              retained.repositoryBinding == repositoryBinding,
              let current = try loadJournalSnapshot(
                repositoryBinding: repositoryBinding
              ), current == retained.failedSource else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        switch retained.purpose {
        case .delete:
            if let uncertainMutationIntent {
                guard uncertainMutationIntent.outcome == retained.outcome,
                      let rowRemovalMutationIntent,
                      identifiesSameRowMutation(
                        rowRemovalMutationIntent.authorization,
                        retained
                      ) else {
                    throw IOSFailedHistoryError.commitUncertain
                }
            } else {
                guard transferMutationIntent == nil,
                      rowRemovalMutationIntent == nil else {
                    throw IOSFailedHistoryError.commitUncertain
                }
            }
        case .retention(let preparation):
            guard preparation.operationLeaseAuthorization
                    .provesSameActiveLease(
                        as: operationLeaseAuthorization
                    ), preparation.repositoryBinding == repositoryBinding else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
            if let uncertainMutationIntent {
                guard uncertainMutationIntent.outcome == retained.outcome,
                      case .pendingRow(
                        let retainedPreparation,
                        let retainedAuthorization?,
                        let retainedOutcome
                      ) = transferMutationIntent,
                      retainedPreparation == preparation,
                      retainedOutcome == retained.outcome,
                      identifiesSameRowMutation(
                        retainedAuthorization,
                        retained
                      ) else {
                    throw IOSFailedHistoryError.commitUncertain
                }
            } else {
                guard transferMutationIntent == nil,
                      rowRemovalMutationIntent == nil else {
                    throw IOSFailedHistoryError.commitUncertain
                }
            }
        case .policyCutover(let policy):
            guard policy.capabilityOwnerIdentity
                    == capabilityOwnerIdentity,
                  retained.candidate.policyGeneration
                    < policy.state.policyGeneration else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
            if let uncertainMutationIntent {
                guard uncertainMutationIntent.outcome
                        == retained.outcome,
                      let rowRemovalMutationIntent,
                      identifiesSameRowMutation(
                        rowRemovalMutationIntent.authorization,
                        retained
                      ) else {
                    throw IOSFailedHistoryError.commitUncertain
                }
            } else {
                guard transferMutationIntent == nil,
                      rowRemovalMutationIntent == nil,
                      retryCancellationMutationIntent == nil else {
                    throw IOSFailedHistoryError.commitUncertain
                }
            }
        }

        let refreshed = try rowAudioValidationAuthorization(
            source: retained.failedSource,
            candidate: retained.candidate,
            tombstone: retained.tombstone,
            outcome: retained.outcome,
            purpose: retained.purpose,
            pendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        if uncertainMutationIntent != nil {
            switch refreshed.purpose {
            case .delete:
                rowRemovalMutationIntent =
                    IOSFailedHistoryRowRemovalMutationIntent(
                        authorization: refreshed,
                        outcome: refreshed.outcome
                    )
            case .retention(let preparation):
                transferMutationIntent = .pendingRow(
                    preparation: preparation,
                    retentionAuthorization: refreshed,
                    outcome: refreshed.outcome
                )
            case .policyCutover:
                rowRemovalMutationIntent =
                    IOSFailedHistoryRowRemovalMutationIntent(
                        authorization: refreshed,
                        outcome: refreshed.outcome
                    )
            }
        }
        return refreshed
    }

    func refreshRetainedDeleteValidationAuthorization(
        attemptID: UUID,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRowAudioValidationAuthorization? {
        try requireActiveLease(operationLeaseAuthorization)
        guard uncertainMutationIntent != nil,
              let rowRemovalMutationIntent,
              rowRemovalMutationIntent.authorization.purpose == .delete,
              rowRemovalMutationIntent.authorization.candidate.attemptID
                == attemptID else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let retained = rowRemovalMutationIntent.authorization
        let repositoryBinding = try requireProductionRepositoryBinding()
        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if current?.envelope == retained.outcome,
           current != retained.failedSource {
            return nil
        }
        guard current == retained.failedSource else {
            throw IOSFailedHistoryError.commitUncertain
        }
        return try refreshRowAudioValidationAuthorization(
            retained,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func refreshRetainedRetentionValidationAuthorization(
        for preparation: IOSPendingFailedHistoryTransferPreparation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRowAudioValidationAuthorization? {
        try requireActiveLease(operationLeaseAuthorization)
        guard uncertainMutationIntent != nil,
              case .pendingRow(
                let retainedPreparation,
                let retainedAuthorization?,
                _
              ) = transferMutationIntent,
              retainedPreparation == preparation,
              case .retention(let authorizedPreparation) =
                retainedAuthorization.purpose,
              authorizedPreparation == preparation else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let repositoryBinding = try requireProductionRepositoryBinding()
        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if current?.envelope == retainedAuthorization.outcome,
           current != retainedAuthorization.failedSource {
            return nil
        }
        guard current == retainedAuthorization.failedSource else {
            throw IOSFailedHistoryError.commitUncertain
        }
        return try refreshRowAudioValidationAuthorization(
            retainedAuthorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func commitDelete(
        using validatedAudio: IOSFailedHistoryValidatedRowAudio
    ) async throws -> IOSFailedHistoryTombstoneReceipt {
        let authorization = validatedAudio.authorization
        try requireActiveLease(authorization.operationLeaseAuthorization)
        guard authorization.purpose == .delete,
              !mutationInterlock.isCleanupBlocked,
              uncertainMutationIntent == nil,
              transferMutationIntent == nil,
              rowRemovalMutationIntent == nil else {
            throw IOSFailedHistoryError.commitUncertain
        }
        try await validatedAudio.revalidate()
        try validateRowAudioAuthorization(authorization)
        rowRemovalMutationIntent = IOSFailedHistoryRowRemovalMutationIntent(
            authorization: authorization,
            outcome: authorization.outcome
        )
        do {
            let capability = try reserveExactMutation(
                authorization.outcome,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
            guard capability.source == .existing(
                authorization.failedSource
            ) else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
            _ = try commitExactMutation(capability)
            return try tombstoneReceipt(
                authorization,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
            )
        } catch {
            if uncertainMutationIntent == nil {
                rowRemovalMutationIntent = nil
            }
            throw error
        }
    }

    /// Reconciles only the retained Delete mutation. Source-visible state
    /// requires a freshly validated descriptor; outcome-visible state does not.
    func reconcileDeleteCommit(
        validatedAudio: IOSFailedHistoryValidatedRowAudio?,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryTombstoneReceipt {
        try requireActiveLease(operationLeaseAuthorization)
        guard let uncertainMutationIntent,
              let rowRemovalMutationIntent,
              uncertainMutationIntent.outcome
                == rowRemovalMutationIntent.outcome else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let retained = rowRemovalMutationIntent.authorization
        let repositoryBinding = try requireProductionRepositoryBinding()
        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if current == retained.failedSource {
            guard let validatedAudio,
                  identifiesSameRowMutation(
                    validatedAudio.authorization,
                    retained
                  ), validatedAudio.authorization
                    .operationLeaseAuthorization.provesSameActiveLease(
                        as: operationLeaseAuthorization
                    ) else {
                throw IOSFailedHistoryError.invalidTransition
            }
            try await validatedAudio.revalidate()
            try validateRowAudioAuthorization(validatedAudio.authorization)
        } else {
            guard current?.envelope == retained.outcome else {
                throw IOSFailedHistoryError.commitUncertain
            }
        }
        _ = try commitExactMutation(
            reserveExactMutation(
                retained.outcome,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        )
        return try tombstoneReceipt(
            retained,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    /// Ordinary lifecycle cleanup may select only the canonical tombstone head.
    /// The returned capability also retains the cross-turn cleanup interlock.
    func prepareNextAudioCleanup(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryAudioCleanupAuthorization? {
        try requireFreshAudioCleanupAdmission(
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard let source = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        ), let tombstone = source.envelope.audioCleanup.first else {
            return nil
        }
        let authorization = try audioCleanupAuthorization(
            source: source,
            tombstone: tombstone,
            outcome: audioCleanupOutcome(
                source: source,
                tombstone: tombstone
            ),
            purpose: .nextHead,
            operationID: IOSFailedHistoryAudioCleanupOperationID(),
            pendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard mutationInterlock.retainAudioCleanup(using: authorization) else {
            throw IOSFailedHistoryError.commitUncertain
        }
        return authorization
    }

    /// Explicit Delete may clean only the tombstone created by that exact
    /// logical-removal receipt, even when it is not the lifecycle queue head.
    func prepareAudioCleanup(
        using receipt: IOSFailedHistoryTombstoneReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryAudioCleanupAuthorization {
        try requireFreshAudioCleanupAdmission(
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard receipt.failedStoreIdentity == storeIdentity,
              receipt.expectedPendingStoreIdentity == pendingStoreIdentity,
              receipt.ownerIdentity == capabilityOwnerIdentity,
              receipt.repositoryBinding == repositoryBinding,
              receipt.operationLeaseAuthorization.provesSameActiveLease(
                as: operationLeaseAuthorization
              ),
              let source = try loadJournalSnapshot(
                repositoryBinding: repositoryBinding
              ), source.envelope == receipt.outcome,
              source.envelope.audioCleanup.contains(receipt.tombstone) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let authorization = try audioCleanupAuthorization(
            source: source,
            tombstone: receipt.tombstone,
            outcome: audioCleanupOutcome(
                source: source,
                tombstone: receipt.tombstone
            ),
            purpose: .explicitDelete(receipt),
            operationID: IOSFailedHistoryAudioCleanupOperationID(),
            pendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard mutationInterlock.retainAudioCleanup(using: authorization) else {
            throw IOSFailedHistoryError.commitUncertain
        }
        return authorization
    }

    /// Reissues only the exact retained cleanup capability. A visible source
    /// requires a fresh filesystem receipt; a visible retirement outcome does
    /// not authorize another audio observation.
    func refreshAudioCleanupAuthorization(
        _ retained: IOSFailedHistoryAudioCleanupAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryAudioCleanupAuthorization? {
        try requireActiveLease(operationLeaseAuthorization)
        let retainedLeaseIsRefreshable = retained.operationLeaseAuthorization
            .provesSameActiveLease(as: operationLeaseAuthorization)
            || !retained.operationLeaseAuthorization.provesActiveLease()
        guard retainedLeaseIsRefreshable,
              mutationInterlock.retainsAudioCleanup(
                using: retained
              ) else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let intent = audioCleanupMutationIntent
        if let intent {
            guard identifiesSameAudioCleanup(
                    retained,
                    intent.authorization
                  ), intent.outcome == retained.outcome else {
                throw IOSFailedHistoryError.commitUncertain
            }
            try requireMatchingAudioCleanupMutationUncertainty(intent)
        } else {
            guard !mutationInterlock.isMutationBlocked,
                  uncertainMutationIntent == nil else {
                throw IOSFailedHistoryError.commitUncertain
            }
        }
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard retained.failedStoreIdentity == storeIdentity,
              retained.expectedPendingStoreIdentity == pendingStoreIdentity,
              retained.ownerIdentity == capabilityOwnerIdentity,
              retained.repositoryBinding == repositoryBinding else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if current == retained.failedSource {
            let refreshed = try audioCleanupAuthorization(
                source: retained.failedSource,
                tombstone: retained.tombstone,
                outcome: retained.outcome,
                purpose: retained.purpose,
                operationID: retained.operationID,
                pendingStoreIdentity: pendingStoreIdentity,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
            if intent != nil {
                audioCleanupMutationIntent?.authorization = refreshed
            }
            return refreshed
        }
        guard intent?.retirementReceipt != nil,
              current?.envelope == retained.outcome else {
            throw IOSFailedHistoryError.commitUncertain
        }
        return nil
    }

    /// Retires only the tombstone sealed by the Pending/filesystem receipt.
    /// Cleanup state remains interlocked until the coordinator clears its exact
    /// completed phase.
    func commitAudioCleanup(
        using receipt: IOSFailedHistoryAudioCleanupReceipt
    ) throws {
        let authorization = receipt.authorization
        try requireActiveLease(authorization.operationLeaseAuthorization)
        guard !mutationInterlock.isMutationBlocked,
              mutationInterlock.hasRetainedAudioCleanup(
                using: authorization,
                operationLeaseAuthorization:
                    authorization.operationLeaseAuthorization
              ),
              uncertainMutationIntent == nil else {
            throw IOSFailedHistoryError.commitUncertain
        }
        if let intent = audioCleanupMutationIntent {
            guard identifiesSameAudioCleanup(
                    authorization,
                    intent.authorization
                  ), intent.outcome == authorization.outcome else {
                throw IOSFailedHistoryError.commitUncertain
            }
        }
        try validateAudioCleanupReceipt(receipt)
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        ) == authorization.failedSource else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        var intent = audioCleanupMutationIntent
            ?? IOSFailedHistoryAudioCleanupMutationIntent(
                authorization: authorization,
                outcome: authorization.outcome,
                retirementReceipt: nil
            )
        intent.authorization = authorization
        intent.retirementReceipt = receipt
        audioCleanupMutationIntent = intent
        let capability = try reserveExactMutation(
            authorization.outcome,
            operationLeaseAuthorization:
                authorization.operationLeaseAuthorization
        )
        guard capability.source == .existing(authorization.failedSource) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        _ = try commitExactMutation(capability)
    }

    /// Reconciles only this cleanup's exact failed-journal CAS uncertainty.
    /// Source-visible state requires a fresh exact absence receipt; an exact
    /// visible outcome is confirmed without touching protected audio.
    func reconcileAudioCleanupCommit(
        receipt: IOSFailedHistoryAudioCleanupReceipt?,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws {
        try requireActiveLease(operationLeaseAuthorization)
        guard mutationInterlock.isMutationBlocked,
              let uncertainMutationIntent,
              var intent = audioCleanupMutationIntent,
              mutationInterlock.retainsAudioCleanup(
                using: intent.authorization
              ),
              intent.retirementReceipt != nil,
              uncertainMutationIntent.outcome == intent.outcome else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let repositoryBinding = try requireProductionRepositoryBinding()
        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if current == intent.authorization.failedSource {
            guard let receipt,
                  identifiesSameAudioCleanup(
                    receipt.authorization,
                    intent.authorization
                  ), receipt.authorization.operationLeaseAuthorization
                    .provesSameActiveLease(
                        as: operationLeaseAuthorization
                    ) else {
                throw IOSFailedHistoryError.invalidTransition
            }
            try validateAudioCleanupReceipt(receipt)
            intent.authorization = receipt.authorization
            intent.retirementReceipt = receipt
            audioCleanupMutationIntent = intent
        } else {
            guard receipt == nil,
                  current?.envelope == intent.outcome else {
                throw IOSFailedHistoryError.commitUncertain
            }
        }
        _ = try commitExactMutation(
            reserveExactMutation(
                intent.outcome,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        )
    }

    /// Confirms that the coordinator's exact cleanup phase is still retained.
    func hasRetainedAudioCleanup(
        matching retained: IOSFailedHistoryAudioCleanupAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> Bool {
        try requireActiveLease(operationLeaseAuthorization)
        guard mutationInterlock.hasRetainedAudioCleanup(
            using: retained,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            return false
        }
        guard let intent = audioCleanupMutationIntent else { return true }
        return identifiesSameAudioCleanup(retained, intent.authorization)
    }

    /// Clears only the Store semantic phase after exact durable retirement.
    /// The coordinator state remains responsible for clearing cleanupBlocked.
    func completeAudioCleanup(
        using retained: IOSFailedHistoryAudioCleanupAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryAudioCleanupCompletionAuthorization {
        try requireActiveLease(operationLeaseAuthorization)
        let retainedLeaseIsRefreshable = retained.operationLeaseAuthorization
            .provesSameActiveLease(as: operationLeaseAuthorization)
            || !retained.operationLeaseAuthorization.provesActiveLease()
        guard retainedLeaseIsRefreshable,
              mutationInterlock.retainsAudioCleanup(
                using: retained
              ),
              !mutationInterlock.isMutationBlocked,
              uncertainMutationIntent == nil,
              let intent = audioCleanupMutationIntent,
              intent.retirementReceipt != nil,
              identifiesSameAudioCleanup(retained, intent.authorization) else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard retained.repositoryBinding == repositoryBinding,
              let current = try loadJournalSnapshot(
                repositoryBinding: repositoryBinding
              ), current != intent.authorization.failedSource,
              current.envelope == intent.outcome else {
            throw IOSFailedHistoryError.commitUncertain
        }
        guard let completion =
                IOSFailedHistoryAudioCleanupCompletionAuthorization(
                    mint:
                        IOSFailedHistoryAudioCleanupCompletionAuthorizationMint(),
                    operationID: intent.authorization.operationID,
                    failedStoreIdentity: storeIdentity,
                    expectedPendingStoreIdentity:
                        intent.authorization.expectedPendingStoreIdentity,
                    ownerIdentity: capabilityOwnerIdentity,
                    repositoryBinding: repositoryBinding,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            throw IOSFailedHistoryError.commitUncertain
        }
        audioCleanupMutationIntent = nil
        return completion
    }

    /// Narrow rollback used only when coordinator state admission fails before
    /// the cleanup authorization reaches Pending or the filesystem.
    func abandonPreparedAudioCleanup(
        using authorization: IOSFailedHistoryAudioCleanupAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws {
        try requireActiveLease(operationLeaseAuthorization)
        guard mutationInterlock.hasRetainedAudioCleanup(
                using: authorization,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
              ),
              !mutationInterlock.isMutationBlocked,
              uncertainMutationIntent == nil,
              audioCleanupMutationIntent == nil else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        ) == authorization.failedSource else {
            throw IOSFailedHistoryError.commitUncertain
        }
        audioCleanupMutationIntent = nil
        guard mutationInterlock.abandonAudioCleanup(
            using: authorization
        ) else {
            throw IOSFailedHistoryError.commitUncertain
        }
    }

    func commitPendingJournalRetirement(
        _ preparation: IOSPendingFailedHistoryTransferPreparation
    ) async throws -> IOSFailedHistoryPendingMetadataRetirementAuthority {
        try requireActiveLease(preparation.operationLeaseAuthorization)
        guard !mutationInterlock.isCleanupBlocked,
              uncertainMutationIntent == nil,
              transferMutationIntent == nil else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        try validate(
            preparation,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding
        )
        try await preparation.revalidateAudio()

        let source = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        let outcome = try appendingPendingJournalRetirement(
            preparation.intendedRow,
            to: source?.envelope
        )
        transferMutationIntent = .pendingRow(
            preparation: preparation,
            retentionAuthorization: nil,
            outcome: outcome
        )
        do {
            let capability = try reserveExactMutation(
                outcome,
                operationLeaseAuthorization:
                    preparation.operationLeaseAuthorization
            )
            guard capability.source == mutationSource(for: source) else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
            let receipt = try commitExactMutation(
                capability
            )
            return try metadataRetirementAuthority(
                receipt: receipt,
                row: preparation.intendedRow,
                origin: .committed(preparation.pendingSnapshot),
                expectedPendingStoreIdentity: pendingStoreIdentity,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization:
                    preparation.operationLeaseAuthorization
            )
        } catch {
            if uncertainMutationIntent == nil {
                transferMutationIntent = nil
            }
            throw error
        }
    }

    /// At capacity, admission and oldest-row cleanup ownership are one exact
    /// failed-root mutation. Neither audio file is removed here.
    func commitPendingJournalRetirement(
        _ preparation: IOSPendingFailedHistoryTransferPreparation,
        validatedEviction: IOSFailedHistoryValidatedRowAudio
    ) async throws -> IOSFailedHistoryPendingMetadataRetirementAuthority {
        let authorization = validatedEviction.authorization
        try requireActiveLease(preparation.operationLeaseAuthorization)
        guard case .retention(let retainedPreparation) = authorization.purpose,
              retainedPreparation == preparation,
              authorization.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: preparation.operationLeaseAuthorization
                ), !mutationInterlock.isCleanupBlocked,
              uncertainMutationIntent == nil,
              transferMutationIntent == nil,
              rowRemovalMutationIntent == nil else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        try validate(
            preparation,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding
        )
        try await preparation.revalidateAudio()
        try await validatedEviction.revalidate()
        try validateRowAudioAuthorization(authorization)
        guard authorization.failedSource.envelope.entries.count
                == IOSFailedHistoryValidation.maximumEntryCount,
              authorization.outcome.entries.contains(
                preparation.intendedRow
              ) else {
            throw IOSFailedHistoryError.invalidTransition
        }

        transferMutationIntent = .pendingRow(
            preparation: preparation,
            retentionAuthorization: authorization,
            outcome: authorization.outcome
        )
        do {
            let capability = try reserveExactMutation(
                authorization.outcome,
                operationLeaseAuthorization:
                    preparation.operationLeaseAuthorization
            )
            guard capability.source == .existing(
                authorization.failedSource
            ) else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
            let receipt = try commitExactMutation(capability)
            return try metadataRetirementAuthority(
                receipt: receipt,
                row: preparation.intendedRow,
                origin: .committed(preparation.pendingSnapshot),
                expectedPendingStoreIdentity: pendingStoreIdentity,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization:
                    preparation.operationLeaseAuthorization
            )
        } catch {
            if uncertainMutationIntent == nil {
                transferMutationIntent = nil
            }
            throw error
        }
    }

    /// Reconciles only the exact append retained by this Store. The original
    /// descriptor-backed preparation is revalidated, but its expired lease is
    /// never reused as mutation authority.
    func reconcilePendingJournalRetirementCommit(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryPendingMetadataRetirementAuthority {
        try requireActiveLease(operationLeaseAuthorization)
        guard uncertainMutationIntent != nil,
              case .pendingRow(
                let preparation,
                let retentionAuthorization,
                let outcome
              ) =
                transferMutationIntent else {
            throw IOSFailedHistoryError.commitUncertain
        }
        guard retentionAuthorization == nil else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard preparation.operationLeaseAuthorization.provesSameActiveLease(
                  as: operationLeaseAuthorization
              ) else {
            throw IOSFailedHistoryError.commitUncertain
        }
        try validate(
            preparation,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding
        )
        try await preparation.revalidateAudio()

        let receipt = try commitExactMutation(
            reserveExactMutation(
                outcome,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        )
        return try metadataRetirementAuthority(
            receipt: receipt,
            row: preparation.intendedRow,
            origin: .committed(preparation.pendingSnapshot),
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    /// Retention reconciliation requires a fresh candidate descriptor only
    /// while the exact old source remains visible. A visible intended outcome
    /// is confirmed without reopening the now-tombstoned audio.
    func reconcilePendingJournalRetirementCommit(
        validatedEviction: IOSFailedHistoryValidatedRowAudio?,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryPendingMetadataRetirementAuthority {
        try requireActiveLease(operationLeaseAuthorization)
        guard let uncertainMutationIntent,
              case .pendingRow(
                let preparation,
                let retainedAuthorization?,
                let outcome
              ) = transferMutationIntent,
              uncertainMutationIntent.outcome == outcome else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard preparation.operationLeaseAuthorization.provesSameActiveLease(
                  as: operationLeaseAuthorization
              ) else {
            throw IOSFailedHistoryError.commitUncertain
        }
        try validate(
            preparation,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding
        )
        try await preparation.revalidateAudio()
        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if current == retainedAuthorization.failedSource {
            guard let validatedEviction,
                  identifiesSameRowMutation(
                    validatedEviction.authorization,
                    retainedAuthorization
                  ), validatedEviction.authorization
                    .operationLeaseAuthorization.provesSameActiveLease(
                        as: operationLeaseAuthorization
                    ) else {
                throw IOSFailedHistoryError.invalidTransition
            }
            try await validatedEviction.revalidate()
            try validateRowAudioAuthorization(
                validatedEviction.authorization
            )
        } else {
            guard current?.envelope == outcome else {
                throw IOSFailedHistoryError.commitUncertain
            }
        }

        let receipt = try commitExactMutation(
            reserveExactMutation(
                outcome,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        )
        return try metadataRetirementAuthority(
            receipt: receipt,
            row: preparation.intendedRow,
            origin: .committed(preparation.pendingSnapshot),
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    /// Proves that a retained pre-row preparation did not become a failed-row
    /// owner. The proof may use the exact still-active preparation lease after
    /// a definitive failure, or a fresh lease after the old one expires.
    func provePendingJournalRetirementAppendAbsent(
        for preparation: IOSPendingFailedHistoryTransferPreparation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryPendingRowAbsenceProof {
        try requireActiveLease(operationLeaseAuthorization)
        let exactPreparationLease = preparation
            .operationLeaseAuthorization
            .provesSameActiveLease(as: operationLeaseAuthorization)
        guard (exactPreparationLease
                || !preparation.operationLeaseAuthorization
                    .provesActiveLease()),
              uncertainMutationIntent == nil,
              transferMutationIntent == nil,
              !mutationInterlock.isBlocked else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard preparation.pendingStoreIdentity == pendingStoreIdentity,
              preparation.failedStoreIdentity == storeIdentity,
              preparation.ownerIdentity == capabilityOwnerIdentity,
              preparation.repositoryBinding == repositoryBinding,
              IOSFailedHistoryPendingMatchIdentity(
                  pending: preparation.pendingSnapshot.recording
              ) == IOSFailedHistoryPendingMatchIdentity(
                  failedRow: preparation.intendedRow
              ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }

        if let envelope = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )?.envelope {
            let rowCollision = envelope.entries.contains {
                $0.attemptID == preparation.intendedRow.attemptID
                    || $0.audioRelativeIdentifier
                        == preparation.intendedRow.audioRelativeIdentifier
            }
            let cleanupCollision = envelope.audioCleanup.contains {
                $0.attemptID == preparation.intendedRow.attemptID
                    || $0.audioRelativeIdentifier
                        == preparation.intendedRow.audioRelativeIdentifier
            }
            guard !rowCollision, !cleanupCollision else {
                throw IOSFailedHistoryError.collision
            }
        }
        guard let proof = IOSFailedHistoryPendingRowAbsenceProof(
            mint: IOSFailedHistoryPendingRowAbsenceProofMint(),
            preparation: preparation,
            failedStoreIdentity: storeIdentity,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return proof
    }

    /// Reconstructs only journal-retirement authority. Policy is intentionally
    /// not consulted after the failed row became canonical.
    func makeRelaunchedPendingMetadataRetirementAuthority(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryPendingMetadataRetirementAuthority? {
        switch try inspectTransferRecovery(
            operationLeaseAuthorization: operationLeaseAuthorization
        ) {
        case .retirePendingMetadata(let authority):
            return authority
        case .verifyTerminal:
            return nil
        }
    }

    /// Seals either the one row-derived retirement directive or the complete
    /// non-PJR failed snapshot needed to distinguish terminal ready ownership
    /// from an unrelated current Pending recording.
    func inspectTransferRecovery(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryTransferRecoveryDirective {
        try requireActiveLease(operationLeaseAuthorization)
        try requireNoMutationUncertainty()
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        let source = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if let source,
           let row = source.envelope.entries.first(where: {
            $0.ownershipState == .pendingJournalRetirement
           }) {
            guard let authority =
                    IOSFailedHistoryPendingMetadataRetirementAuthority(
                        mint:
                            IOSFailedHistoryMetadataRetirementAuthorityMint(),
                        failedSource: source,
                        row: row,
                        origin: .relaunched,
                        failedStoreIdentity: storeIdentity,
                        expectedPendingStoreIdentity:
                            pendingStoreIdentity,
                        ownerIdentity: capabilityOwnerIdentity,
                        repositoryBinding: repositoryBinding,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    ) else {
                throw IOSFailedHistoryError.invalidTransition
            }
            return .retirePendingMetadata(authority)
        }
        guard let inspection = IOSFailedHistoryTransferRecoveryInspection(
            mint: IOSFailedHistoryTransferRecoveryInspectionMint(),
            failedSource: source,
            failedStoreIdentity: storeIdentity,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        return .verifyTerminal(inspection)
    }

    func hasPendingJournalRetirement(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> Bool {
        try requireActiveLease(operationLeaseAuthorization)
        try requireNoMutationUncertainty()
        let envelope: IOSFailedHistoryEnvelope?
        if let repositoryBinding = try currentRepositoryBinding() {
            envelope = try loadJournalSnapshot(
                repositoryBinding: repositoryBinding
            )?.envelope
        } else {
            envelope = try journal.load()?.envelope
        }
        return envelope?.entries.contains(where: {
            $0.ownershipState == .pendingJournalRetirement
        }) == true
    }

    /// Reissues one retained process-local observation under a fresh lease
    /// without weakening a committed exact Pending source into relaunch
    /// matching authority.
    func refreshPendingMetadataRetirementAuthority(
        _ retained:
            IOSFailedHistoryPendingMetadataRetirementAuthority,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryPendingMetadataRetirementAuthority {
        try requireActiveLease(operationLeaseAuthorization)
        try requireNoMutationUncertainty()
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard retained.failedStoreIdentity == storeIdentity,
              retained.expectedPendingStoreIdentity
                == pendingStoreIdentity,
              retained.ownerIdentity == capabilityOwnerIdentity,
              retained.repositoryBinding == repositoryBinding,
              retained.origin != .readyOutcomeConfirmation,
              let current = try loadJournalSnapshot(
                  repositoryBinding: repositoryBinding
              ),
              current == retained.failedSource,
              current.envelope.entries.contains(retained.row),
              let refreshed =
                IOSFailedHistoryPendingMetadataRetirementAuthority(
                    mint:
                        IOSFailedHistoryMetadataRetirementAuthorityMint(),
                    failedSource: current,
                    row: retained.row,
                    origin: retained.origin,
                    failedStoreIdentity: storeIdentity,
                    expectedPendingStoreIdentity:
                        pendingStoreIdentity,
                    ownerIdentity: capabilityOwnerIdentity,
                    repositoryBinding: repositoryBinding,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return refreshed
    }

    func commitReady(
        using receipt: IOSPendingRecordingMetadataAbsenceReceipt
    ) throws {
        let authorization = receipt.authority.operationLeaseAuthorization
        try requireActiveLease(authorization)
        guard !mutationInterlock.isCleanupBlocked else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        try validate(
            receipt,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding
        )

        if let transferMutationIntent {
            guard uncertainMutationIntent != nil,
                  case .ready(
                    let failedSource,
                    let row,
                    let retainedPendingStoreIdentity,
                    let retainedRepositoryBinding,
                    let outcome
                  ) = transferMutationIntent,
                  receipt.authority.origin == .readyOutcomeConfirmation,
                  receipt.outcome.provesPreexistingAbsence,
                  receipt.authority.failedSource == failedSource,
                  receipt.authority.row == row,
                  retainedPendingStoreIdentity == pendingStoreIdentity,
                  retainedRepositoryBinding == repositoryBinding else {
                throw IOSFailedHistoryError.commitUncertain
            }
            _ = try commitExactMutation(
                reserveExactMutation(
                    outcome,
                    operationLeaseAuthorization: authorization
                )
            )
            return
        }

        guard uncertainMutationIntent == nil,
              receipt.authority.origin != .readyOutcomeConfirmation else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let failedSource = receipt.authority.failedSource
        guard try loadJournalSnapshot(repositoryBinding: repositoryBinding)
                == failedSource else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let outcome = try readyOutcome(
            from: failedSource,
            row: receipt.authority.row
        )
        transferMutationIntent = .ready(
            failedSource: failedSource,
            row: receipt.authority.row,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding,
            outcome: outcome
        )
        do {
            let capability = try reserveExactMutation(
                outcome,
                operationLeaseAuthorization: authorization
            )
            guard capability.source == .existing(failedSource) else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
            _ = try commitExactMutation(
                capability
            )
        } catch {
            if uncertainMutationIntent == nil {
                transferMutationIntent = nil
            }
            throw error
        }
    }

    /// Classifies only the exact retained PJR -> ready mutation. Both cases
    /// issue proof-only authority; neither can remove a present Pending journal.
    func classifyReadyCommitUncertainty(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryReadyCommitUncertainty {
        try requireActiveLease(operationLeaseAuthorization)
        guard let uncertainMutationIntent,
              case .ready(
                let failedSource,
                let row,
                let pendingStoreIdentity,
                let retainedRepositoryBinding,
                let outcome
              ) = transferMutationIntent else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let expectedPendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard pendingStoreIdentity == expectedPendingStoreIdentity,
              retainedRepositoryBinding == repositoryBinding,
              uncertainMutationIntent.outcome == outcome else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        let sourceIsVisible = current == failedSource
        let outcomeIsVisible = current?.envelope == outcome
        guard sourceIsVisible || outcomeIsVisible else {
            throw IOSFailedHistoryError.commitUncertain
        }
        guard let authority = IOSFailedHistoryPendingMetadataRetirementAuthority(
            mint: IOSFailedHistoryMetadataRetirementAuthorityMint(),
            failedSource: failedSource,
            row: row,
            origin: .readyOutcomeConfirmation,
            failedStoreIdentity: storeIdentity,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.commitUncertain
        }
        return sourceIsVisible
            ? .retryReadyCommit(authority)
            : .readyOutcomeConfirmation(authority)
    }

    func provePendingOwnershipAbsent(
        for pendingKey: IOSFailedHistoryPendingOwnershipKey,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryPendingOwnershipAbsenceProof {
        try requireActiveLease(operationLeaseAuthorization)
        try requireNoMutationUncertainty()
        let boundPendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        guard expectedPendingStoreIdentity == boundPendingStoreIdentity else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let repositoryBinding = try requireProductionRepositoryBinding()
        let source = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if let envelope = source?.envelope {
            let rowCollision = envelope.entries.contains {
                $0.attemptID == pendingKey.attemptID
                    || $0.audioRelativeIdentifier
                        == pendingKey.audioRelativeIdentifier
            }
            let cleanupCollision = envelope.audioCleanup.contains {
                $0.attemptID == pendingKey.attemptID
                    || $0.audioRelativeIdentifier
                        == pendingKey.audioRelativeIdentifier
            }
            guard !rowCollision, !cleanupCollision else {
                throw IOSFailedHistoryError.collision
            }
            guard !envelope.entries.contains(where: {
                $0.ownershipState == .pendingJournalRetirement
            }) else {
                throw IOSFailedHistoryError.slotOccupied
            }
        }
        guard let proof = IOSFailedHistoryPendingOwnershipAbsenceProof(
            mint: IOSFailedHistoryPendingOwnershipAbsenceProofMint(),
            failedStoreIdentity: storeIdentity,
            expectedPendingStoreIdentity: boundPendingStoreIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            pendingKey: pendingKey,
            failedSource: source,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return proof
    }

    /// Raw state is coordinator-only because old policy generations and audio
    /// cleanup tombstones intentionally survive until bounded reconciliation.
    func load() throws -> IOSFailedHistoryEnvelope? {
        try requireNoMutationUncertainty()
        return try journal.load()?.envelope
    }

    func proveGuardedBaseline()
        throws -> IOSFailedHistoryGuardedBaselineEvidence {
        try requireNoMutationUncertainty()
        if let envelope = try journal.load()?.envelope {
            guard envelope.entries.isEmpty,
                  envelope.audioCleanup.isEmpty else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
        }
        return IOSFailedHistoryGuardedBaselineEvidence(
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
    }

    @discardableResult
    func performStagingMaintenance(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    )
        throws -> IOSFailedHistoryMaintenanceReport {
        try requireActiveLease(operationLeaseAuthorization)
        try requireNoMutationUncertainty()
        let repositoryBinding = try currentRepositoryBinding()
        do {
            let report = try journal.performStagingMaintenance(
                now: now(),
                expectedRepositoryRoot:
                    repositoryBinding?.physicalRootIdentity
            )
            try requireRepositoryBinding(repositoryBinding)
            return IOSFailedHistoryMaintenanceReport(report)
        } catch {
            do {
                try requireRepositoryBinding(repositoryBinding)
            } catch {
                throw IOSFailedHistoryError.repositoryIdentityConflict
            }
            throw error
        }
    }

    #if DEBUG
    func reserveExactMutationForTesting(
        _ outcome: IOSFailedHistoryEnvelope,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryMutationCapability {
        try reserveExactMutation(
            outcome,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func commitExactMutationForTesting(
        _ capability: IOSFailedHistoryMutationCapability
    ) throws -> IOSFailedHistoryMutationReceipt {
        try commitExactMutation(capability)
    }

    func mutateExactForTesting(
        _ outcome: IOSFailedHistoryEnvelope,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryMutationReceipt {
        let capability = try reserveExactMutation(
            outcome,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        return try commitExactMutation(capability)
    }

    func validateMutationReceiptForTesting(
        _ receipt: IOSFailedHistoryMutationReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryEnvelope {
        try validatedSnapshot(
            for: receipt,
            operationLeaseAuthorization: operationLeaseAuthorization
        ).envelope
    }

    func retainMutationUncertaintyForTesting() {
        mutationInterlock.retainUncertainty()
    }
    #endif
}

private extension IOSFailedHistoryStore {
    struct RowRemovalOutcome {
        let tombstone: IOSFailedHistoryAudioCleanup
        let outcome: IOSFailedHistoryEnvelope
    }

    struct RetentionOutcome {
        let candidate: IOSFailedHistoryEntry
        let tombstone: IOSFailedHistoryAudioCleanup
        let outcome: IOSFailedHistoryEnvelope
    }

    func validatedRetryConfiguration(
        _ configuration: TranscriptionConfiguration
    ) throws -> (model: String, languageCode: String?) {
        let model = configuration.resolvedModel
        let languageCode = configuration.resolvedLanguageCode
        guard !configuration.customLanguageCodeValidation.isInvalid,
              IOSPendingRecordingValidation.isValidModel(model),
              IOSPendingRecordingValidation.isValidLanguageCode(
                  languageCode
              ) else {
            throw IOSFailedHistoryError.invalidEntry
        }
        return (model, languageCode)
    }

    func requireFreshRetryMutationAdmission() throws {
        try requireNoMutationUncertainty()
        guard transferMutationIntent == nil,
              rowRemovalMutationIntent == nil,
              retryCancellationMutationIntent == nil,
              audioCleanupMutationIntent == nil,
              retryMutationIntent == nil,
              !mutationInterlock.isBlocked else {
            throw IOSFailedHistoryError.commitUncertain
        }
    }

    func requireFreshRetryAcceptingOutputAdmission(
        _ reservation: IOSFailedHistoryRetryDeliveryFreezeReservation,
        relationKey: IOSFailedHistoryRetryDeliveryRelationKey,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws {
        try requireNoMutationUncertainty()
        guard transferMutationIntent == nil,
              rowRemovalMutationIntent == nil,
              retryCancellationMutationIntent == nil,
              audioCleanupMutationIntent == nil,
              retryMutationIntent == nil,
              reservation.relationKey == relationKey,
              mutationInterlock.permitsRetryDeliveryFreeze(
                  reservation,
                  operationLeaseAuthorization:
                      operationLeaseAuthorization
              ) else {
            throw IOSFailedHistoryError.commitUncertain
        }
    }

    func canonicalRetryTime(after priorDate: Date) throws -> Date {
        let candidate = try IOSFailedHistoryTimestampCodec.canonicalDate(
            from: now()
        )
        return max(candidate, priorDate)
    }

    func makeRetryOperation(
        createdAt: Date,
        state: IOSFailedHistoryRetryOperationState
    ) throws -> IOSFailedHistoryRetryOperation {
        var identifiers: [UUID] = []
        var uniqueIdentifiers: Set<UUID> = []
        while identifiers.count < 5 {
            let candidate = UUID()
            if uniqueIdentifiers.insert(candidate).inserted {
                identifiers.append(candidate)
            }
        }
        return try IOSFailedHistoryRetryOperation(
            retryID: identifiers[0],
            createdAt: createdAt,
            transcriptionID: identifiers[1],
            deliveryID: identifiers[2],
            sessionID: identifiers[3],
            transcriptID: identifiers[4],
            state: state
        )
    }

    func retryOperation(
        replacingStateOf operation: IOSFailedHistoryRetryOperation,
        with state: IOSFailedHistoryRetryOperationState
    ) throws -> IOSFailedHistoryRetryOperation {
        try IOSFailedHistoryRetryOperation(
            retryID: operation.retryID,
            createdAt: operation.createdAt,
            transcriptionID: operation.transcriptionID,
            deliveryID: operation.deliveryID,
            sessionID: operation.sessionID,
            transcriptID: operation.transcriptID,
            state: state
        )
    }

    func retryRow(
        replacing row: IOSFailedHistoryEntry,
        updatedAt: Date,
        retryCount: Int32,
        model: String,
        languageCode: String?,
        operation: IOSFailedHistoryRetryOperation?
    ) throws -> IOSFailedHistoryEntry {
        try IOSFailedHistoryEntry(
            attemptID: row.attemptID,
            createdAt: row.createdAt,
            updatedAt: updatedAt,
            policyGeneration: row.policyGeneration,
            failureCategory: row.failureCategory,
            pipelineStage: row.pipelineStage,
            retryCount: retryCount,
            outputIntent: row.outputIntent,
            transcriptionModel: model,
            transcriptionLanguageCode: languageCode,
            durationMilliseconds: row.durationMilliseconds,
            byteCount: row.byteCount,
            audioRelativeIdentifier: row.audioRelativeIdentifier,
            ownershipState: row.ownershipState,
            retryOperation: operation
        )
    }

    func retryReplacementOutcome(
        source: IOSFailedHistoryJournalSnapshot,
        candidate: IOSFailedHistoryEntry,
        replacement: IOSFailedHistoryEntry
    ) throws -> IOSFailedHistoryEnvelope {
        guard let index = source.envelope.entries.firstIndex(of: candidate)
        else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let nextRevision = source.envelope.revision
            .addingReportingOverflow(1)
        guard !nextRevision.overflow else {
            throw IOSFailedHistoryError.revisionOverflow
        }
        var entries = source.envelope.entries
        entries[index] = replacement
        return try IOSFailedHistoryEnvelope(
            revision: nextRevision.partialValue,
            entries: IOSFailedHistoryValidation.sortedEntries(entries),
            audioCleanup: source.envelope.audioCleanup
        )
    }

    func retryReservationAuthorization(
        source: IOSFailedHistoryJournalSnapshot,
        candidate: IOSFailedHistoryEntry,
        reservedRow: IOSFailedHistoryEntry,
        operation: IOSFailedHistoryRetryOperation,
        outcome: IOSFailedHistoryEnvelope,
        policy: IOSHistoryPolicyReceipt,
        pendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryReservationAuthorization {
        guard let inventory = IOSFailedHistoryProtectedAudioInventory(
                mint: IOSFailedHistoryProtectedAudioInventoryMint(),
                failedSource: source,
                failedStoreIdentity: storeIdentity,
                expectedPendingStoreIdentity: pendingStoreIdentity,
                ownerIdentity: capabilityOwnerIdentity,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
              ), let authorization =
                IOSFailedHistoryRetryReservationAuthorization(
                    mint:
                        IOSFailedHistoryRetryReservationAuthorizationMint(),
                    failedSource: source,
                    candidate: candidate,
                    reservedRow: reservedRow,
                    retryOperation: operation,
                    outcome: outcome,
                    policyReceipt: policy,
                    failedInventory: inventory,
                    failedStoreIdentity: storeIdentity,
                    expectedPendingStoreIdentity: pendingStoreIdentity,
                    ownerIdentity: capabilityOwnerIdentity,
                    repositoryBinding: repositoryBinding,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        return authorization
    }

    func validateRetryReservationAuthorization(
        _ authorization: IOSFailedHistoryRetryReservationAuthorization
    ) throws {
        try requireActiveLease(
            authorization.operationLeaseAuthorization
        )
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard authorization.failedStoreIdentity == storeIdentity,
              authorization.expectedPendingStoreIdentity
                == pendingStoreIdentity,
              authorization.ownerIdentity == capabilityOwnerIdentity,
              authorization.repositoryBinding == repositoryBinding,
              let current = try loadJournalSnapshot(
                  repositoryBinding: repositoryBinding
              ), current == authorization.failedSource else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        try validatePolicyCutoverGenerations(
            current.envelope,
            using: authorization.policyReceipt
        )
        let expected = try retryReservationAuthorization(
            source: authorization.failedSource,
            candidate: authorization.candidate,
            reservedRow: authorization.reservedRow,
            operation: authorization.retryOperation,
            outcome: authorization.outcome,
            policy: authorization.policyReceipt,
            pendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization:
                authorization.operationLeaseAuthorization
        )
        guard expected == authorization else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    func retryReservationReceipt(
        authorization: IOSFailedHistoryRetryReservationAuthorization,
        mutationReceipt: IOSFailedHistoryMutationReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryReservationReceipt {
        guard mutationReceipt.storeIdentity == storeIdentity,
              mutationReceipt.capabilityOwnerIdentity
                == capabilityOwnerIdentity,
              mutationReceipt.repositoryBinding
                == authorization.repositoryBinding,
              mutationReceipt.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ), let receipt = IOSFailedHistoryRetryReservationReceipt(
                    mint: IOSFailedHistoryRetryReservationReceiptMint(),
                    authorization: authorization,
                    durableSnapshot: mutationReceipt.snapshot,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return receipt
    }

    func validateRetryReservationReceipt(
        _ receipt: IOSFailedHistoryRetryReservationReceipt,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding
    ) throws {
        guard receipt.failedStoreIdentity == storeIdentity,
              receipt.ownerIdentity == capabilityOwnerIdentity,
              receipt.repositoryBinding == repositoryBinding,
              receipt.durableSnapshot.envelope
                == receipt.authorization.outcome,
              receipt.durableSnapshot.envelope.entries.contains(
                  receipt.row
              ),
              receipt.row.retryOperation == receipt.retryOperation,
              receipt.retryOperation.state == .reserved,
              receipt.authorization.failedStoreIdentity == storeIdentity,
              receipt.authorization.ownerIdentity
                == capabilityOwnerIdentity,
              receipt.authorization.repositoryBinding
                == repositoryBinding else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    func retainedRetryReservationPreparation(
        attemptID: UUID,
        model: String,
        languageCode: String?,
        policy: IOSHistoryPolicyReceipt,
        pendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryReservationPreparation {
        guard let uncertainMutationIntent,
              case .reservation(let retained) = retryMutationIntent,
              uncertainMutationIntent.outcome == retained.outcome,
              retained.candidate.attemptID == attemptID,
              retained.policyReceipt == policy,
              IOSAcceptedOutputDeliveryValidation.bytesEqual(
                  retained.reservedRow.transcriptionModel,
                  model
              ),
              retained.reservedRow.transcriptionLanguageCode
                == languageCode else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let refreshed = try retryReservationAuthorization(
            source: retained.failedSource,
            candidate: retained.candidate,
            reservedRow: retained.reservedRow,
            operation: retained.retryOperation,
            outcome: retained.outcome,
            policy: retained.policyReceipt,
            pendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        )
        retryMutationIntent = .reservation(refreshed)
        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if current == retained.failedSource {
            return .commit(refreshed)
        }
        guard current?.envelope == retained.outcome else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let mutationReceipt = try commitExactMutation(
            reserveExactMutation(
                retained.outcome,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        )
        return .completed(
            try retryReservationReceipt(
                authorization: refreshed,
                mutationReceipt: mutationReceipt,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        )
    }

    func retryDispatchAuthorization(
        reservationReceipt: IOSFailedHistoryRetryReservationReceipt,
        source: IOSFailedHistoryJournalSnapshot,
        dispatchedRow: IOSFailedHistoryEntry,
        operation: IOSFailedHistoryRetryOperation,
        outcome: IOSFailedHistoryEnvelope,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryDispatchAuthorization {
        guard let authorization = IOSFailedHistoryRetryDispatchAuthorization(
            mint: IOSFailedHistoryRetryDispatchAuthorizationMint(),
            reservationReceipt: reservationReceipt,
            failedSource: source,
            reservedRow: reservationReceipt.row,
            dispatchedRow: dispatchedRow,
            retryOperation: operation,
            outcome: outcome,
            failedStoreIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        return authorization
    }

    func validateRetryDispatchAuthorization(
        _ authorization: IOSFailedHistoryRetryDispatchAuthorization
    ) throws {
        try requireActiveLease(
            authorization.operationLeaseAuthorization
        )
        let repositoryBinding = try requireProductionRepositoryBinding()
        try validateRetryReservationReceipt(
            authorization.reservationReceipt,
            repositoryBinding: repositoryBinding
        )
        guard authorization.failedStoreIdentity == storeIdentity,
              authorization.ownerIdentity == capabilityOwnerIdentity,
              authorization.repositoryBinding == repositoryBinding,
              let current = try loadJournalSnapshot(
                  repositoryBinding: repositoryBinding
              ), current == authorization.failedSource else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let expected = try retryDispatchAuthorization(
            reservationReceipt: authorization.reservationReceipt,
            source: authorization.failedSource,
            dispatchedRow: authorization.dispatchedRow,
            operation: authorization.retryOperation,
            outcome: authorization.outcome,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization:
                authorization.operationLeaseAuthorization
        )
        guard expected == authorization else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    func retryDispatchReceipt(
        authorization: IOSFailedHistoryRetryDispatchAuthorization,
        durableSnapshot: IOSFailedHistoryJournalSnapshot,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryDispatchReceipt {
        guard let token = IOSFailedHistoryRetryLiveOwnerToken(
                mint: IOSFailedHistoryRetryLiveOwnerTokenMint(),
                failedSource: durableSnapshot,
                row: authorization.dispatchedRow,
                failedStoreIdentity: storeIdentity,
                ownerIdentity: capabilityOwnerIdentity,
                retryStateIdentity:
                    try requireExpectedRetryStateIdentity(),
                repositoryBinding: authorization.repositoryBinding,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
              ), let receipt = IOSFailedHistoryRetryDispatchReceipt(
                mint: IOSFailedHistoryRetryDispatchReceiptMint(),
                authorization: authorization,
                durableSnapshot: durableSnapshot,
                liveOwnerToken: token,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
              ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return receipt
    }

    func retainedRetryDispatchPreparation(
        reservationReceipt: IOSFailedHistoryRetryReservationReceipt,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryDispatchPreparation {
        guard let uncertainMutationIntent,
              case .dispatch(let retained) = retryMutationIntent,
              uncertainMutationIntent.outcome == retained.outcome,
              retained.reservationReceipt.identifiesSameReservation(
                  as: reservationReceipt
              ) else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let refreshedReservationReceipt = try refreshRetryReservationReceipt(
            reservationReceipt,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        )
        let refreshed = try retryDispatchAuthorization(
            reservationReceipt: refreshedReservationReceipt,
            source: retained.failedSource,
            dispatchedRow: retained.dispatchedRow,
            operation: retained.retryOperation,
            outcome: retained.outcome,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        )
        retryMutationIntent = .dispatch(refreshed)
        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if current == retained.failedSource {
            return .commit(refreshed)
        }
        guard let current, current.envelope == retained.outcome else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let mutationReceipt = try commitExactMutation(
            reserveExactMutation(
                retained.outcome,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        )
        return .completed(
            try retryDispatchReceipt(
                authorization: refreshed,
                durableSnapshot: mutationReceipt.snapshot,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        )
    }

    func refreshRetryReservationReceipt(
        _ receipt: IOSFailedHistoryRetryReservationReceipt,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryReservationReceipt {
        try validateRetryReservationReceipt(
            receipt,
            repositoryBinding: repositoryBinding
        )
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let authorization = try retryReservationAuthorization(
            source: receipt.authorization.failedSource,
            candidate: receipt.authorization.candidate,
            reservedRow: receipt.authorization.reservedRow,
            operation: receipt.authorization.retryOperation,
            outcome: receipt.authorization.outcome,
            policy: receipt.authorization.policyReceipt,
            pendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        )
        guard let refreshed = IOSFailedHistoryRetryReservationReceipt(
            mint: IOSFailedHistoryRetryReservationReceiptMint(),
            authorization: authorization,
            durableSnapshot: receipt.durableSnapshot,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return refreshed
    }

    func validateRetryDispatchReceipt(
        _ receipt: IOSFailedHistoryRetryDispatchReceipt,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding
    ) throws {
        guard receipt.failedStoreIdentity == storeIdentity,
              receipt.ownerIdentity == capabilityOwnerIdentity,
              receipt.repositoryBinding == repositoryBinding,
              receipt.durableSnapshot.envelope
                == receipt.authorization.outcome,
              receipt.durableSnapshot.envelope.entries.contains(
                  receipt.row
              ),
              receipt.row.retryOperation == receipt.retryOperation,
              receipt.retryOperation.state == .providerDispatched,
              receipt.authorization.failedStoreIdentity == storeIdentity,
              receipt.authorization.ownerIdentity
                == capabilityOwnerIdentity,
              receipt.authorization.repositoryBinding
                == repositoryBinding,
              receipt.liveOwnerToken.failedSource
                == receipt.durableSnapshot,
              receipt.liveOwnerToken.row == receipt.row,
              receipt.liveOwnerToken.retryOperation
                == receipt.retryOperation else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    func prepareRetryCancellation(
        sourceReceipt: IOSFailedHistoryRetryCancellationSource,
        providerCancellationClaim:
            IOSFailedHistoryRetryProviderCancellationClaim?,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryCancellationPreparation {
        try requireActiveLease(operationLeaseAuthorization)
        let repositoryBinding = try requireProductionRepositoryBinding()
        switch sourceReceipt {
        case .reservation(let receipt):
            try validateRetryReservationReceipt(
                receipt,
                repositoryBinding: repositoryBinding
            )
        case .dispatch(let receipt):
            try validateRetryDispatchReceipt(
                receipt,
                repositoryBinding: repositoryBinding
            )
        }

        if uncertainMutationIntent != nil {
            return try retainedRetryCancellationPreparation(
                sourceReceipt: sourceReceipt,
                providerCancellationClaim: providerCancellationClaim,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        }

        try requireFreshRetryMutationAdmission()
        guard let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        ), current == sourceReceipt.durableSnapshot else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let retryingRow = sourceReceipt.row
        let retainedRow = try retryRow(
            replacing: retryingRow,
            updatedAt: try canonicalRetryTime(
                after: retryingRow.updatedAt
            ),
            retryCount: retryingRow.retryCount,
            model: retryingRow.transcriptionModel,
            languageCode: retryingRow.transcriptionLanguageCode,
            operation: nil
        )
        let outcome = try retryReplacementOutcome(
            source: current,
            candidate: retryingRow,
            replacement: retainedRow
        )
        return .commit(
            try retryCancellationAuthorization(
                sourceReceipt: sourceReceipt,
                source: current,
                retainedRow: retainedRow,
                outcome: outcome,
                providerCancellationClaim: providerCancellationClaim,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        )
    }

    func retryCancellationAuthorization(
        sourceReceipt: IOSFailedHistoryRetryCancellationSource,
        source: IOSFailedHistoryJournalSnapshot,
        retainedRow: IOSFailedHistoryEntry,
        outcome: IOSFailedHistoryEnvelope,
        providerCancellationClaim:
            IOSFailedHistoryRetryProviderCancellationClaim?,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryCancellationAuthorization {
        guard let authorization =
                IOSFailedHistoryRetryCancellationAuthorization(
                    mint:
                        IOSFailedHistoryRetryCancellationAuthorizationMint(),
                    sourceReceipt: sourceReceipt,
                    failedSource: source,
                    retryingRow: sourceReceipt.row,
                    retainedRow: retainedRow,
                    retryOperation: sourceReceipt.retryOperation,
                    outcome: outcome,
                    providerCancellationClaim:
                        providerCancellationClaim,
                    failedStoreIdentity: storeIdentity,
                    ownerIdentity: capabilityOwnerIdentity,
                    repositoryBinding: repositoryBinding,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        return authorization
    }

    func validateRetryCancellationAuthorization(
        _ authorization: IOSFailedHistoryRetryCancellationAuthorization
    ) throws {
        try requireActiveLease(
            authorization.operationLeaseAuthorization
        )
        let repositoryBinding = try requireProductionRepositoryBinding()
        switch authorization.sourceReceipt {
        case .reservation(let receipt):
            try validateRetryReservationReceipt(
                receipt,
                repositoryBinding: repositoryBinding
            )
        case .dispatch(let receipt):
            try validateRetryDispatchReceipt(
                receipt,
                repositoryBinding: repositoryBinding
            )
        }
        guard authorization.failedStoreIdentity == storeIdentity,
              authorization.ownerIdentity == capabilityOwnerIdentity,
              authorization.repositoryBinding == repositoryBinding,
              let current = try loadJournalSnapshot(
                  repositoryBinding: repositoryBinding
              ), current == authorization.failedSource else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let expected = try retryCancellationAuthorization(
            sourceReceipt: authorization.sourceReceipt,
            source: authorization.failedSource,
            retainedRow: authorization.retainedRow,
            outcome: authorization.outcome,
            providerCancellationClaim:
                authorization.providerCancellationClaim,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization:
                authorization.operationLeaseAuthorization
        )
        guard expected == authorization else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    func retryCancellationReceipt(
        authorization: IOSFailedHistoryRetryCancellationAuthorization,
        durableSnapshot: IOSFailedHistoryJournalSnapshot,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryCancellationReceipt {
        guard let receipt = IOSFailedHistoryRetryCancellationReceipt(
            mint: IOSFailedHistoryRetryCancellationReceiptMint(),
            authorization: authorization,
            durableSnapshot: durableSnapshot,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return receipt
    }

    func retainedRetryCancellationPreparation(
        sourceReceipt: IOSFailedHistoryRetryCancellationSource,
        providerCancellationClaim:
            IOSFailedHistoryRetryProviderCancellationClaim?,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryCancellationPreparation {
        guard let uncertainMutationIntent,
              case .cancellation(let retained) = retryMutationIntent,
              uncertainMutationIntent.outcome == retained.outcome,
              retained.sourceReceipt.identifiesSameSource(
                  as: sourceReceipt
              ), retained.providerCancellationClaim
                == providerCancellationClaim else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let refreshed = try retryCancellationAuthorization(
            sourceReceipt: sourceReceipt,
            source: retained.failedSource,
            retainedRow: retained.retainedRow,
            outcome: retained.outcome,
            providerCancellationClaim: providerCancellationClaim,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        )
        retryMutationIntent = .cancellation(refreshed)
        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if current == retained.failedSource {
            return .commit(refreshed)
        }
        guard let current, current.envelope == retained.outcome else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let mutationReceipt = try commitExactMutation(
            reserveExactMutation(
                retained.outcome,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        )
        return .completed(
            try retryCancellationReceipt(
                authorization: refreshed,
                durableSnapshot: mutationReceipt.snapshot,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        )
    }

    func retryFailureRow(
        replacing row: IOSFailedHistoryEntry,
        disposition: IOSFailedHistoryRetryFailureDisposition,
        updatedAt: Date
    ) throws -> IOSFailedHistoryEntry {
        let failureCategory: IOSFailedHistoryFailureCategory
        let pipelineStage: IOSFailedHistoryPipelineStage
        switch disposition {
        case .mapped(let category, let stage):
            failureCategory = category
            pipelineStage = stage
        case .preservePrevious:
            failureCategory = row.failureCategory
            pipelineStage = row.pipelineStage
        }
        return try IOSFailedHistoryEntry(
            attemptID: row.attemptID,
            createdAt: row.createdAt,
            updatedAt: updatedAt,
            policyGeneration: row.policyGeneration,
            failureCategory: failureCategory,
            pipelineStage: pipelineStage,
            retryCount: row.retryCount,
            outputIntent: row.outputIntent,
            transcriptionModel: row.transcriptionModel,
            transcriptionLanguageCode: row.transcriptionLanguageCode,
            durationMilliseconds: row.durationMilliseconds,
            byteCount: row.byteCount,
            audioRelativeIdentifier: row.audioRelativeIdentifier,
            ownershipState: row.ownershipState,
            retryOperation: nil
        )
    }

    func retryFailureAuthorization(
        dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        providerCompletionClaim:
            IOSFailedHistoryRetryProviderCompletionClaim,
        disposition: IOSFailedHistoryRetryFailureDisposition,
        source: IOSFailedHistoryJournalSnapshot,
        retainedRow: IOSFailedHistoryEntry,
        outcome: IOSFailedHistoryEnvelope,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryFailureAuthorization {
        guard let authorization = IOSFailedHistoryRetryFailureAuthorization(
            mint: IOSFailedHistoryRetryFailureAuthorizationMint(),
            dispatchReceipt: dispatchReceipt,
            providerCompletionClaim: providerCompletionClaim,
            disposition: disposition,
            failedSource: source,
            retryingRow: dispatchReceipt.row,
            retainedRow: retainedRow,
            retryOperation: dispatchReceipt.retryOperation,
            outcome: outcome,
            failedStoreIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        return authorization
    }

    func validateRetryFailureAuthorization(
        _ authorization: IOSFailedHistoryRetryFailureAuthorization
    ) throws {
        try requireActiveLease(
            authorization.operationLeaseAuthorization
        )
        let repositoryBinding = try requireProductionRepositoryBinding()
        try validateRetryDispatchReceipt(
            authorization.dispatchReceipt,
            repositoryBinding: repositoryBinding
        )
        guard authorization.failedStoreIdentity == storeIdentity,
              authorization.ownerIdentity == capabilityOwnerIdentity,
              authorization.repositoryBinding == repositoryBinding,
              authorization.providerCompletionClaim.liveOwnerToken
                == authorization.dispatchReceipt.liveOwnerToken,
              let current = try loadJournalSnapshot(
                repositoryBinding: repositoryBinding
              ), current == authorization.failedSource else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let expected = try retryFailureAuthorization(
            dispatchReceipt: authorization.dispatchReceipt,
            providerCompletionClaim:
                authorization.providerCompletionClaim,
            disposition: authorization.disposition,
            source: authorization.failedSource,
            retainedRow: authorization.retainedRow,
            outcome: authorization.outcome,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization:
                authorization.operationLeaseAuthorization
        )
        guard expected == authorization else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    func retryFailureReceipt(
        authorization: IOSFailedHistoryRetryFailureAuthorization,
        durableSnapshot: IOSFailedHistoryJournalSnapshot,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryFailureReceipt {
        guard let receipt = IOSFailedHistoryRetryFailureReceipt(
            mint: IOSFailedHistoryRetryFailureReceiptMint(),
            authorization: authorization,
            durableSnapshot: durableSnapshot,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return receipt
    }

    func retainedRetryFailurePreparation(
        dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        providerCompletionClaim:
            IOSFailedHistoryRetryProviderCompletionClaim,
        disposition: IOSFailedHistoryRetryFailureDisposition,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryFailurePreparation {
        guard let uncertainMutationIntent,
              case .failure(let retained) = retryMutationIntent,
              uncertainMutationIntent.outcome == retained.outcome,
              retained.dispatchReceipt.identifiesSameDispatch(
                as: dispatchReceipt
              ),
              retained.providerCompletionClaim
                == providerCompletionClaim,
              retained.disposition == disposition else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let refreshed = try retryFailureAuthorization(
            dispatchReceipt: dispatchReceipt,
            providerCompletionClaim: providerCompletionClaim,
            disposition: disposition,
            source: retained.failedSource,
            retainedRow: retained.retainedRow,
            outcome: retained.outcome,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        )
        retryMutationIntent = .failure(refreshed)
        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if current == retained.failedSource {
            return .commit(refreshed)
        }
        guard let current, current.envelope == retained.outcome else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let mutationReceipt = try commitExactMutation(
            reserveExactMutation(
                retained.outcome,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        )
        return .completed(
            try retryFailureReceipt(
                authorization: refreshed,
                durableSnapshot: mutationReceipt.snapshot,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        )
    }

    func retryAcceptingOutputAuthorization(
        dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        providerCompletionClaim:
            IOSFailedHistoryRetryProviderCompletionClaim,
        frozenSlotProof: IOSAcceptedOutputDeliveryFrozenSlotProof,
        acceptingRow: IOSFailedHistoryEntry,
        acceptingOperation: IOSFailedHistoryRetryOperation,
        outcome: IOSFailedHistoryEnvelope,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryAcceptingOutputAuthorization {
        guard let authorization =
                IOSFailedHistoryRetryAcceptingOutputAuthorization(
                    mint:
                        IOSFailedHistoryRetryAcceptingOutputAuthorizationMint(),
                    dispatchReceipt: dispatchReceipt,
                    providerCompletionClaim: providerCompletionClaim,
                    frozenSlotProof: frozenSlotProof,
                    failedSource: dispatchReceipt.durableSnapshot,
                    acceptingRow: acceptingRow,
                    acceptingOperation: acceptingOperation,
                    outcome: outcome,
                    failedStoreIdentity: storeIdentity,
                    deliveryStoreIdentity:
                        frozenSlotProof.deliveryStoreIdentity,
                    ownerIdentity: capabilityOwnerIdentity,
                    repositoryBinding: repositoryBinding,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return authorization
    }

    func retryAcceptingOutputReceipt(
        authorization: IOSFailedHistoryRetryAcceptingOutputAuthorization,
        durableSnapshot: IOSFailedHistoryJournalSnapshot,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryAcceptingOutputReceipt {
        guard let receipt = IOSFailedHistoryRetryAcceptingOutputReceipt(
            mint: IOSFailedHistoryRetryAcceptingOutputReceiptMint(),
            authorization: authorization,
            durableSnapshot: durableSnapshot,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return receipt
    }

    func validateRetryAcceptingOutputAuthorization(
        _ authorization:
            IOSFailedHistoryRetryAcceptingOutputAuthorization
    ) throws {
        try requireActiveLease(
            authorization.operationLeaseAuthorization
        )
        let repositoryBinding = try requireProductionRepositoryBinding()
        try validateRetryDispatchReceipt(
            authorization.dispatchReceipt,
            repositoryBinding: repositoryBinding
        )
        guard authorization.failedStoreIdentity == storeIdentity,
              authorization.ownerIdentity == capabilityOwnerIdentity,
              authorization.repositoryBinding == repositoryBinding,
              authorization.providerCompletionClaim.liveOwnerToken
                == authorization.dispatchReceipt.liveOwnerToken,
              let expected = try? retryAcceptingOutputAuthorization(
                  dispatchReceipt: authorization.dispatchReceipt,
                  providerCompletionClaim:
                      authorization.providerCompletionClaim,
                  frozenSlotProof: authorization.frozenSlotProof,
                  acceptingRow: authorization.acceptingRow,
                  acceptingOperation: authorization.acceptingOperation,
                  outcome: authorization.outcome,
                  repositoryBinding: repositoryBinding,
                  operationLeaseAuthorization:
                      authorization.operationLeaseAuthorization
              ), expected == authorization else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    func retainedRetryAcceptingOutputPreparation(
        dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        providerCompletionClaim:
            IOSFailedHistoryRetryProviderCompletionClaim,
        frozenSlotProof: IOSAcceptedOutputDeliveryFrozenSlotProof,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryAcceptingOutputPreparation {
        guard let uncertainMutationIntent,
              case .acceptingOutput(let retained) = retryMutationIntent,
              uncertainMutationIntent.outcome == retained.outcome,
              retained.dispatchReceipt.identifiesSameDispatch(
                as: dispatchReceipt
              ),
              retained.providerCompletionClaim == providerCompletionClaim,
              retained.frozenSlotProof.frozenSlot
                == frozenSlotProof.frozenSlot,
              retained.frozenSlotProof.preparation
                == frozenSlotProof.preparation else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let refreshed = try retryAcceptingOutputAuthorization(
            dispatchReceipt: dispatchReceipt,
            providerCompletionClaim: providerCompletionClaim,
            frozenSlotProof: frozenSlotProof,
            acceptingRow: retained.acceptingRow,
            acceptingOperation: retained.acceptingOperation,
            outcome: retained.outcome,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard mutationInterlock.upgradeRetryDeliveryFreeze(
            frozenSlotProof.freezeReservation,
            to: refreshed.relationKey
        ) else {
            throw IOSFailedHistoryError.commitUncertain
        }
        retryMutationIntent = .acceptingOutput(refreshed)
        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if current == retained.failedSource {
            return .commit(refreshed)
        }
        guard let current, current.envelope == retained.outcome else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let mutationReceipt = try commitExactMutation(
            reserveExactMutation(
                retained.outcome,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        )
        return .completed(
            try retryAcceptingOutputReceipt(
                authorization: refreshed,
                durableSnapshot: mutationReceipt.snapshot,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        )
    }

    func validateRetrySuccessAuthorization(
        _ authorization: IOSFailedHistoryRetrySuccessAuthorization
    ) throws {
        try requireActiveLease(
            authorization.operationLeaseAuthorization
        )
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard authorization.failedStoreIdentity == storeIdentity,
              authorization.ownerIdentity == capabilityOwnerIdentity,
              authorization.repositoryBinding == repositoryBinding,
              authorization.acceptingOutputReceipt.failedStoreIdentity
                == storeIdentity,
              authorization.acceptingOutputReceipt.ownerIdentity
                == capabilityOwnerIdentity,
              authorization.acceptingOutputReceipt.repositoryBinding
                == repositoryBinding,
              let current = try loadJournalSnapshot(
                  repositoryBinding: repositoryBinding
              ), current == authorization.failedSource,
              let expected = IOSFailedHistoryRetrySuccessAuthorization(
                  mint: IOSFailedHistoryRetrySuccessAuthorizationMint(),
                  acceptingOutputReceipt:
                      authorization.acceptingOutputReceipt,
                  terminalDeliveryProof:
                      authorization.terminalDeliveryProof,
                  tombstone: authorization.tombstone,
                  outcome: authorization.outcome,
                  operationLeaseAuthorization:
                      authorization.operationLeaseAuthorization
              ), expected == authorization else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    func retainedRetrySuccessPreparation(
        acceptingOutputReceipt:
            IOSFailedHistoryRetryAcceptingOutputReceipt,
        terminalDeliveryProof: IOSFailedHistoryRetryTerminalDeliveryProof,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetrySuccessPreparation {
        guard let uncertainMutationIntent,
              case .success(let retained) = retryMutationIntent,
              uncertainMutationIntent.outcome == retained.outcome,
              retained.acceptingOutputReceipt.durableSnapshot
                == acceptingOutputReceipt.durableSnapshot,
              retained.acceptingOutputReceipt.retryOperation
                == acceptingOutputReceipt.retryOperation,
              retained.terminalDeliveryProof.deliveryAuthorization.record
                == terminalDeliveryProof.deliveryAuthorization.record else {
            throw IOSFailedHistoryError.commitUncertain
        }
        guard let refreshed = IOSFailedHistoryRetrySuccessAuthorization(
            mint: IOSFailedHistoryRetrySuccessAuthorizationMint(),
            acceptingOutputReceipt: acceptingOutputReceipt,
            terminalDeliveryProof: terminalDeliveryProof,
            tombstone: retained.tombstone,
            outcome: retained.outcome,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        _ = repositoryBinding
        retryMutationIntent = .success(refreshed)
        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if current == retained.failedSource {
            return .commit(refreshed)
        }
        guard let current, current.envelope == retained.outcome else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let mutationReceipt = try commitExactMutation(
            reserveExactMutation(
                retained.outcome,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        )
        guard let receipt = IOSFailedHistoryRetrySuccessReceipt(
            mint: IOSFailedHistoryRetrySuccessReceiptMint(),
            authorization: refreshed,
            durableSnapshot: mutationReceipt.snapshot,
            operationLeaseAuthorization: operationLeaseAuthorization
        ), mutationInterlock.clearRetryDeliveryRelation(
            acceptingOutputReceipt.relationKey,
            freezeReservation: acceptingOutputReceipt.frozenSlotProof
                .freezeReservation
        ) else {
            throw IOSFailedHistoryError.commitUncertain
        }
        return .completed(receipt)
    }

    func validatePolicyCutoverGenerations(
        _ envelope: IOSFailedHistoryEnvelope,
        using policy: IOSHistoryPolicyReceipt
    ) throws {
        guard envelope.entries.allSatisfy({
            $0.policyGeneration <= policy.state.policyGeneration
        }), envelope.audioCleanup.allSatisfy({
            $0.policyGeneration <= policy.state.policyGeneration
        }) else {
            throw IOSFailedHistoryError.stalePolicyGeneration
        }
    }

    func retainedPolicyCutoverDirective(
        current: IOSFailedHistoryJournalSnapshot?,
        policy: IOSHistoryPolicyReceipt,
        pendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryPolicyCutoverDirective {
        _ = pendingStoreIdentity
        guard let uncertainMutationIntent else {
            throw IOSFailedHistoryError.commitUncertain
        }

        if let rowIntent = rowRemovalMutationIntent,
           case .policyCutover(let retainedPolicy) =
            rowIntent.authorization.purpose,
           retainedPolicy == policy,
           uncertainMutationIntent.outcome == rowIntent.outcome {
            if current?.envelope == rowIntent.outcome,
               current != rowIntent.authorization.failedSource {
                _ = try commitExactMutation(
                    reserveExactMutation(
                        rowIntent.outcome,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                )
                return .retainedMutationConfirmed
            }
            guard current == rowIntent.authorization.failedSource else {
                throw IOSFailedHistoryError.commitUncertain
            }
            let refreshed = try refreshRowAudioValidationAuthorization(
                rowIntent.authorization,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
            return .invalidateReadyRow(refreshed)
        }

        if let retryIntent = retryCancellationMutationIntent,
           retryIntent.authorization.inspection.policyReceipt == policy,
           uncertainMutationIntent.outcome == retryIntent.outcome {
            if current?.envelope == retryIntent.outcome,
               current
                != retryIntent.authorization.inspection.failedSource {
                let receipt = try commitExactMutation(
                    reserveExactMutation(
                        retryIntent.outcome,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                )
                return .completeProcessLostRetryCancellation(
                    try policyRetryCancellationCompletionAuthorization(
                        reservation:
                            retryIntent.authorization.reservation,
                        outcome: retryIntent.outcome,
                        receipt: receipt,
                        repositoryBinding: repositoryBinding,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                )
            }
            guard current
                    == retryIntent.authorization.inspection.failedSource,
                  let liveOwnerToken =
                    IOSFailedHistoryRetryLiveOwnerToken(
                        mint: IOSFailedHistoryRetryLiveOwnerTokenMint(),
                        failedSource: retryIntent.authorization.inspection
                            .failedSource,
                        row: retryIntent.authorization.inspection.row,
                        failedStoreIdentity: storeIdentity,
                        ownerIdentity: capabilityOwnerIdentity,
                        retryStateIdentity:
                            try requireExpectedRetryStateIdentity(),
                        repositoryBinding: repositoryBinding,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    ),
                  let inspection =
                    IOSFailedHistoryRetryRecoveryInspection(
                        mint:
                            IOSFailedHistoryRetryRecoveryInspectionMint(),
                        liveOwnerToken: liveOwnerToken,
                        policyReceipt: policy,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    ) else {
                throw IOSFailedHistoryError.commitUncertain
            }
            return .inspectProcessLostRetry(inspection)
        }

        throw IOSFailedHistoryError.commitUncertain
    }

    func retryCancellationOutcome(
        source: IOSFailedHistoryJournalSnapshot,
        row: IOSFailedHistoryEntry
    ) throws -> IOSFailedHistoryEnvelope {
        guard row.ownershipState == .ready,
              let retryOperation = row.retryOperation,
              retryOperation.state == .reserved
                || retryOperation.state == .providerDispatched,
              let rowIndex = source.envelope.entries.firstIndex(of: row)
        else {
            throw IOSFailedHistoryError.invalidTransition
        }
        let retainedRow = try IOSFailedHistoryEntry(
            attemptID: row.attemptID,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            policyGeneration: row.policyGeneration,
            failureCategory: row.failureCategory,
            pipelineStage: row.pipelineStage,
            retryCount: row.retryCount,
            outputIntent: row.outputIntent,
            transcriptionModel: row.transcriptionModel,
            transcriptionLanguageCode: row.transcriptionLanguageCode,
            durationMilliseconds: row.durationMilliseconds,
            byteCount: row.byteCount,
            audioRelativeIdentifier: row.audioRelativeIdentifier,
            ownershipState: row.ownershipState,
            retryOperation: nil
        )
        let nextRevision = source.envelope.revision
            .addingReportingOverflow(1)
        guard !nextRevision.overflow else {
            throw IOSFailedHistoryError.revisionOverflow
        }
        var entries = source.envelope.entries
        entries[rowIndex] = retainedRow
        return try IOSFailedHistoryEnvelope(
            revision: nextRevision.partialValue,
            entries: IOSFailedHistoryValidation.sortedEntries(entries),
            audioCleanup: source.envelope.audioCleanup
        )
    }

    func policyRetryCancellationAuthorization(
        inspection: IOSFailedHistoryRetryRecoveryInspection,
        reservation: IOSFailedHistoryRetryCancellationReservation,
        outcome: IOSFailedHistoryEnvelope,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryPolicyRetryCancellationAuthorization {
        guard let authorization =
                IOSFailedHistoryPolicyRetryCancellationAuthorization(
                    mint:
                        IOSFailedHistoryPolicyRetryCancellationAuthorizationMint(),
                    inspection: inspection,
                    reservation: reservation,
                    outcome: outcome,
                    failedStoreIdentity: storeIdentity,
                    ownerIdentity: capabilityOwnerIdentity,
                    repositoryBinding: repositoryBinding,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        return authorization
    }

    func policyRetryCancellationCompletionAuthorization(
        reservation: IOSFailedHistoryRetryCancellationReservation,
        outcome: IOSFailedHistoryEnvelope,
        receipt: IOSFailedHistoryMutationReceipt,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryCancellationCompletionAuthorization {
        try requireActiveLease(operationLeaseAuthorization)
        let retryStateIdentity = try requireExpectedRetryStateIdentity()
        guard reservation.stateIdentity
                == retryStateIdentity,
              receipt.storeIdentity == storeIdentity,
              receipt.capabilityOwnerIdentity == capabilityOwnerIdentity,
              receipt.repositoryBinding == repositoryBinding,
              receipt.operationLeaseAuthorization.provesSameActiveLease(
                as: operationLeaseAuthorization
              ),
              receipt.snapshot.envelope == outcome,
              let rowIndex = reservation.inspection.failedSource.envelope.entries
                .firstIndex(of: reservation.inspection.row),
              outcome.entries.indices.contains(rowIndex),
              outcome.entries[rowIndex].attemptID
                == reservation.inspection.row.attemptID,
              outcome.entries[rowIndex].retryOperation == nil,
              let completion =
                IOSFailedHistoryRetryCancellationCompletionAuthorization(
                    mint:
                        IOSFailedHistoryRetryCancellationCompletionAuthorizationMint(),
                    reservation: reservation,
                    outcome: outcome,
                    failedStoreIdentity: storeIdentity,
                    ownerIdentity: capabilityOwnerIdentity,
                    repositoryBinding: repositoryBinding,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return completion
    }

    func validatePolicyRetryCancellationAuthorization(
        _ authorization:
            IOSFailedHistoryPolicyRetryCancellationAuthorization
    ) throws {
        try requireActiveLease(
            authorization.operationLeaseAuthorization
        )
        let repositoryBinding = try requireProductionRepositoryBinding()
        let retryStateIdentity = try requireExpectedRetryStateIdentity()
        guard authorization.failedStoreIdentity == storeIdentity,
              authorization.ownerIdentity == capabilityOwnerIdentity,
              authorization.repositoryBinding == repositoryBinding,
              authorization.inspection.failedStoreIdentity
                == storeIdentity,
              authorization.inspection.ownerIdentity
                == capabilityOwnerIdentity,
              authorization.inspection.repositoryBinding
                == repositoryBinding,
              authorization.inspection.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: authorization.operationLeaseAuthorization
                ),
              authorization.reservation.inspection
                == authorization.inspection,
              authorization.reservation.stateIdentity == retryStateIdentity,
              authorization.reservation.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: authorization.operationLeaseAuthorization
                ),
              let current = try loadJournalSnapshot(
                repositoryBinding: repositoryBinding
              ), current == authorization.inspection.failedSource,
              try retryCancellationOutcome(
                source: authorization.inspection.failedSource,
                row: authorization.inspection.row
              ) == authorization.outcome else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        try validatePolicyCutoverGenerations(
            current.envelope,
            using: authorization.inspection.policyReceipt
        )
    }

    func requireFreshAudioCleanupAdmission(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws {
        try requireActiveLease(operationLeaseAuthorization)
        try requireNoMutationUncertainty()
        guard transferMutationIntent == nil,
              rowRemovalMutationIntent == nil,
              audioCleanupMutationIntent == nil,
              !mutationInterlock.isBlocked else {
            throw IOSFailedHistoryError.commitUncertain
        }
    }

    func audioCleanupOutcome(
        source: IOSFailedHistoryJournalSnapshot,
        tombstone: IOSFailedHistoryAudioCleanup
    ) throws -> IOSFailedHistoryEnvelope {
        guard let tombstoneIndex = source.envelope.audioCleanup.firstIndex(
            of: tombstone
        ) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        let nextRevision = source.envelope.revision
            .addingReportingOverflow(1)
        guard !nextRevision.overflow else {
            throw IOSFailedHistoryError.revisionOverflow
        }
        var cleanup = source.envelope.audioCleanup
        cleanup.remove(at: tombstoneIndex)
        return try IOSFailedHistoryEnvelope(
            revision: nextRevision.partialValue,
            entries: source.envelope.entries,
            audioCleanup: cleanup
        )
    }

    func audioCleanupAuthorization(
        source: IOSFailedHistoryJournalSnapshot,
        tombstone: IOSFailedHistoryAudioCleanup,
        outcome: IOSFailedHistoryEnvelope,
        purpose: IOSFailedHistoryAudioCleanupPurpose,
        operationID: IOSFailedHistoryAudioCleanupOperationID,
        pendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryAudioCleanupAuthorization {
        guard let failedInventory = IOSFailedHistoryProtectedAudioInventory(
            mint: IOSFailedHistoryProtectedAudioInventoryMint(),
            failedSource: source,
            failedStoreIdentity: storeIdentity,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        ), let authorization = IOSFailedHistoryAudioCleanupAuthorization(
            mint: IOSFailedHistoryAudioCleanupAuthorizationMint(),
            failedSource: source,
            tombstone: tombstone,
            outcome: outcome,
            purpose: purpose,
            operationID: operationID,
            failedInventory: failedInventory,
            failedStoreIdentity: storeIdentity,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        return authorization
    }

    func validateAudioCleanupReceipt(
        _ receipt: IOSFailedHistoryAudioCleanupReceipt
    ) throws {
        let authorization = receipt.authorization
        try requireActiveLease(authorization.operationLeaseAuthorization)
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard receipt.issuerStoreIdentity == pendingStoreIdentity,
              authorization.failedStoreIdentity == storeIdentity,
              authorization.expectedPendingStoreIdentity
                == pendingStoreIdentity,
              authorization.ownerIdentity == capabilityOwnerIdentity,
              authorization.repositoryBinding == repositoryBinding,
              authorization.failedInventory.failedSource
                == authorization.failedSource,
              authorization.failedInventory.failedStoreIdentity
                == storeIdentity,
              authorization.failedInventory.expectedPendingStoreIdentity
                == pendingStoreIdentity,
              authorization.failedInventory.ownerIdentity
                == capabilityOwnerIdentity,
              authorization.failedInventory.repositoryBinding
                == repositoryBinding,
              authorization.failedInventory.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: authorization.operationLeaseAuthorization
                ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        switch receipt.outcome {
        case .removed(let evidence):
            guard evidence.provesRemoval(of: authorization) else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
        case .alreadyAbsent(let evidence):
            guard evidence.provesPreexistingAbsence(of: authorization) else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
        }
    }

    func requireMatchingAudioCleanupMutationUncertainty(
        _ intent: IOSFailedHistoryAudioCleanupMutationIntent
    ) throws {
        if mutationInterlock.isMutationBlocked {
            guard let uncertainMutationIntent,
                  uncertainMutationIntent.outcome == intent.outcome,
                  transferMutationIntent == nil,
                  rowRemovalMutationIntent == nil else {
                throw IOSFailedHistoryError.commitUncertain
            }
        } else {
            guard uncertainMutationIntent == nil else {
                throw IOSFailedHistoryError.commitUncertain
            }
        }
    }

    func identifiesSameAudioCleanup(
        _ lhs: IOSFailedHistoryAudioCleanupAuthorization,
        _ rhs: IOSFailedHistoryAudioCleanupAuthorization
    ) -> Bool {
        lhs.failedSource == rhs.failedSource
            && lhs.tombstone == rhs.tombstone
            && lhs.outcome == rhs.outcome
            && lhs.purpose == rhs.purpose
            && lhs.operationID == rhs.operationID
            && lhs.failedStoreIdentity == rhs.failedStoreIdentity
            && lhs.expectedPendingStoreIdentity
                == rhs.expectedPendingStoreIdentity
            && lhs.ownerIdentity == rhs.ownerIdentity
            && lhs.repositoryBinding == rhs.repositoryBinding
    }

    func rowRemovalOutcome(
        source: IOSFailedHistoryJournalSnapshot,
        candidate: IOSFailedHistoryEntry,
        queuedAt: Date
    ) throws -> RowRemovalOutcome {
        guard candidate.ownershipState == .ready,
              candidate.retryOperation == nil,
              source.envelope.entries.contains(candidate) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        guard source.envelope.audioCleanup.count
                < IOSFailedHistoryValidation.maximumAudioCleanupCount else {
            throw IOSFailedHistoryError.capacityExceeded
        }
        let canonicalQueuedAt = try IOSFailedHistoryTimestampCodec
            .canonicalDate(from: queuedAt)
        let tombstone = try IOSFailedHistoryAudioCleanup(
            attemptID: candidate.attemptID,
            policyGeneration: candidate.policyGeneration,
            queuedAt: canonicalQueuedAt,
            audioRelativeIdentifier: candidate.audioRelativeIdentifier,
            byteCount: candidate.byteCount
        )
        let nextRevision = source.envelope.revision
            .addingReportingOverflow(1)
        guard !nextRevision.overflow else {
            throw IOSFailedHistoryError.revisionOverflow
        }
        guard let candidateIndex = source.envelope.entries.firstIndex(
            of: candidate
        ) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        var entries = source.envelope.entries
        entries.remove(at: candidateIndex)
        let outcome = try IOSFailedHistoryEnvelope(
            revision: nextRevision.partialValue,
            entries: entries,
            audioCleanup: IOSFailedHistoryValidation.sortedAudioCleanup(
                source.envelope.audioCleanup + [tombstone]
            )
        )
        return RowRemovalOutcome(
            tombstone: tombstone,
            outcome: outcome
        )
    }

    func retentionOutcome(
        source: IOSFailedHistoryJournalSnapshot,
        preparation: IOSPendingFailedHistoryTransferPreparation,
        queuedAt: Date
    ) throws -> RetentionOutcome {
        let envelope = source.envelope
        guard envelope.entries.count
                == IOSFailedHistoryValidation.maximumEntryCount,
              let candidate = envelope.entries.last,
              candidate.ownershipState == .ready,
              candidate.retryOperation == nil,
              preparation.intendedRow.ownershipState
                == .pendingJournalRetirement,
              preparation.intendedRow.retryCount == 0,
              preparation.intendedRow.retryOperation == nil,
              !envelope.entries.contains(where: {
                $0.ownershipState == .pendingJournalRetirement
              }) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        let incoming = preparation.intendedRow
        let rowCollision = envelope.entries.contains {
            $0.attemptID == incoming.attemptID
                || $0.audioRelativeIdentifier
                    == incoming.audioRelativeIdentifier
        }
        let cleanupCollision = envelope.audioCleanup.contains {
            $0.attemptID == incoming.attemptID
                || $0.audioRelativeIdentifier
                    == incoming.audioRelativeIdentifier
        }
        guard !rowCollision, !cleanupCollision else {
            throw IOSFailedHistoryError.collision
        }
        let removal = try rowRemovalOutcome(
            source: source,
            candidate: candidate,
            queuedAt: queuedAt
        )
        var entries = removal.outcome.entries
        entries.append(incoming)
        let outcome = try IOSFailedHistoryEnvelope(
            revision: removal.outcome.revision,
            entries: IOSFailedHistoryValidation.sortedEntries(entries),
            audioCleanup: removal.outcome.audioCleanup
        )
        return RetentionOutcome(
            candidate: candidate,
            tombstone: removal.tombstone,
            outcome: outcome
        )
    }

    func rowAudioValidationAuthorization(
        source: IOSFailedHistoryJournalSnapshot,
        candidate: IOSFailedHistoryEntry,
        tombstone: IOSFailedHistoryAudioCleanup,
        outcome: IOSFailedHistoryEnvelope,
        purpose: IOSFailedHistoryRowAudioValidationPurpose,
        pendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRowAudioValidationAuthorization {
        guard let failedInventory = IOSFailedHistoryProtectedAudioInventory(
            mint: IOSFailedHistoryProtectedAudioInventoryMint(),
            failedSource: source,
            failedStoreIdentity: storeIdentity,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        ), let authorization =
            IOSFailedHistoryRowAudioValidationAuthorization(
                mint: IOSFailedHistoryRowAudioValidationAuthorizationMint(),
                failedSource: source,
                candidate: candidate,
                tombstone: tombstone,
                outcome: outcome,
                purpose: purpose,
                failedInventory: failedInventory,
                failedStoreIdentity: storeIdentity,
                expectedPendingStoreIdentity: pendingStoreIdentity,
                ownerIdentity: capabilityOwnerIdentity,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            ) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        return authorization
    }

    func validateRowAudioAuthorization(
        _ authorization: IOSFailedHistoryRowAudioValidationAuthorization
    ) throws {
        try requireActiveLease(authorization.operationLeaseAuthorization)
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard authorization.failedStoreIdentity == storeIdentity,
              authorization.expectedPendingStoreIdentity
                == pendingStoreIdentity,
              authorization.ownerIdentity == capabilityOwnerIdentity,
              authorization.repositoryBinding == repositoryBinding,
              authorization.failedInventory.failedSource
                == authorization.failedSource,
              authorization.failedInventory.failedStoreIdentity
                == storeIdentity,
              authorization.failedInventory.expectedPendingStoreIdentity
                == pendingStoreIdentity,
              authorization.failedInventory.ownerIdentity
                == capabilityOwnerIdentity,
              authorization.failedInventory.repositoryBinding
                == repositoryBinding,
              authorization.failedInventory.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: authorization.operationLeaseAuthorization
                ), try loadJournalSnapshot(
                    repositoryBinding: repositoryBinding
                ) == authorization.failedSource else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    func identifiesSameRowMutation(
        _ lhs: IOSFailedHistoryRowAudioValidationAuthorization,
        _ rhs: IOSFailedHistoryRowAudioValidationAuthorization
    ) -> Bool {
        lhs.failedSource == rhs.failedSource
            && lhs.candidate == rhs.candidate
            && lhs.tombstone == rhs.tombstone
            && lhs.outcome == rhs.outcome
            && lhs.purpose == rhs.purpose
            && lhs.failedStoreIdentity == rhs.failedStoreIdentity
            && lhs.expectedPendingStoreIdentity
                == rhs.expectedPendingStoreIdentity
            && lhs.ownerIdentity == rhs.ownerIdentity
            && lhs.repositoryBinding == rhs.repositoryBinding
    }

    func tombstoneReceipt(
        _ authorization: IOSFailedHistoryRowAudioValidationAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryTombstoneReceipt {
        guard let receipt = IOSFailedHistoryTombstoneReceipt(
            mint: IOSFailedHistoryTombstoneReceiptMint(),
            authorization: authorization,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        return receipt
    }

    func mutationSource(
        for snapshot: IOSFailedHistoryJournalSnapshot?
    ) -> IOSFailedHistoryMutationSource {
        if let snapshot { return .existing(snapshot) }
        return .missing
    }

    func requireExpectedPendingStoreIdentity()
        throws -> IOSPendingRecordingStoreIdentity {
        guard let identity = pendingStoreIdentityBinding.current() else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return identity
    }

    func requireExpectedRetryStateIdentity()
        throws -> IOSFailedHistoryRetryLiveOwnerStateIdentity {
        guard let identity = retryStateIdentityBinding.current() else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return identity
    }

    func requireProductionRepositoryBinding()
        throws -> IOSAcceptedHistoryCoordinatorRepositoryBinding {
        guard let binding = try currentRepositoryBinding(),
              binding.physicalRootIdentity != nil else {
            throw IOSFailedHistoryError.repositoryIdentityConflict
        }
        return binding
    }

    func loadJournalSnapshot(
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    ) throws -> IOSFailedHistoryJournalSnapshot? {
        try requireRepositoryBinding(repositoryBinding)
        do {
            let snapshot = try journal.load()
            try requireRepositoryBinding(repositoryBinding)
            return snapshot
        } catch {
            do {
                try requireRepositoryBinding(repositoryBinding)
            } catch {
                throw IOSFailedHistoryError.repositoryIdentityConflict
            }
            throw error
        }
    }

    func validate(
        _ preparation: IOSPendingFailedHistoryTransferPreparation,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    ) throws {
        guard preparation.operationLeaseAuthorization.provesActiveLease(),
              preparation.pendingStoreIdentity
                == expectedPendingStoreIdentity,
              preparation.failedStoreIdentity == storeIdentity,
              preparation.ownerIdentity == capabilityOwnerIdentity,
              preparation.repositoryBinding == repositoryBinding,
              preparation.policyReceipt.capabilityOwnerIdentity
                == capabilityOwnerIdentity,
              preparation.policyReceipt.state.historyEnabled,
              preparation.policyReceipt.state.policyGeneration
                == preparation.intendedRow.policyGeneration,
              preparation.audioMetadataMatchesPendingSnapshot,
              IOSFailedHistoryPendingMatchIdentity(
                  pending: preparation.pendingSnapshot.recording
              ) == IOSFailedHistoryPendingMatchIdentity(
                  failedRow: preparation.intendedRow
              ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    func appendingPendingJournalRetirement(
        _ row: IOSFailedHistoryEntry,
        to current: IOSFailedHistoryEnvelope?
    ) throws -> IOSFailedHistoryEnvelope {
        guard row.ownershipState == .pendingJournalRetirement,
              row.retryCount == 0,
              row.retryOperation == nil else {
            throw IOSFailedHistoryError.invalidTransition
        }
        let entries = current?.entries ?? []
        let cleanup = current?.audioCleanup ?? []
        guard entries.count < IOSFailedHistoryValidation.maximumEntryCount,
              cleanup.count
                < IOSFailedHistoryValidation.maximumAudioCleanupCount else {
            throw IOSFailedHistoryError.capacityExceeded
        }
        guard !entries.contains(where: {
            $0.ownershipState == .pendingJournalRetirement
        }) else {
            throw IOSFailedHistoryError.slotOccupied
        }
        let rowCollision = entries.contains {
            $0.attemptID == row.attemptID
                || $0.audioRelativeIdentifier == row.audioRelativeIdentifier
        }
        let cleanupCollision = cleanup.contains {
            $0.attemptID == row.attemptID
                || $0.audioRelativeIdentifier == row.audioRelativeIdentifier
        }
        guard !rowCollision, !cleanupCollision else {
            throw IOSFailedHistoryError.collision
        }

        let revision: Int64
        if let current {
            let next = current.revision.addingReportingOverflow(1)
            guard !next.overflow else {
                throw IOSFailedHistoryError.revisionOverflow
            }
            revision = next.partialValue
        } else {
            revision = 1
        }
        return try IOSFailedHistoryEnvelope(
            revision: revision,
            entries: IOSFailedHistoryValidation.sortedEntries(entries + [row]),
            audioCleanup: cleanup
        )
    }

    func validate(
        _ receipt: IOSPendingRecordingMetadataAbsenceReceipt,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    ) throws {
        let authority = receipt.authority
        guard receipt.issuerStoreIdentity == expectedPendingStoreIdentity,
              authority.expectedPendingStoreIdentity
                == expectedPendingStoreIdentity,
              authority.failedStoreIdentity == storeIdentity,
              authority.ownerIdentity == capabilityOwnerIdentity,
              authority.repositoryBinding == repositoryBinding,
              authority.operationLeaseAuthorization.provesActiveLease(),
              receipt.evidence.binding.repositoryRoot
                == repositoryBinding.physicalRootIdentity,
              receipt.evidence.provesCanonicalPendingRecordingPath else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    func readyOutcome(
        from source: IOSFailedHistoryJournalSnapshot,
        row: IOSFailedHistoryEntry
    ) throws -> IOSFailedHistoryEnvelope {
        guard row.ownershipState == .pendingJournalRetirement,
              source.envelope.entries.contains(row) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        let next = source.envelope.revision.addingReportingOverflow(1)
        guard !next.overflow else {
            throw IOSFailedHistoryError.revisionOverflow
        }
        let readyRow = try IOSFailedHistoryEntry(
            attemptID: row.attemptID,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            policyGeneration: row.policyGeneration,
            failureCategory: row.failureCategory,
            pipelineStage: row.pipelineStage,
            retryCount: row.retryCount,
            outputIntent: row.outputIntent,
            transcriptionModel: row.transcriptionModel,
            transcriptionLanguageCode: row.transcriptionLanguageCode,
            durationMilliseconds: row.durationMilliseconds,
            byteCount: row.byteCount,
            audioRelativeIdentifier: row.audioRelativeIdentifier,
            ownershipState: .ready,
            retryOperation: row.retryOperation
        )
        guard let rowIndex = source.envelope.entries.firstIndex(of: row) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        var entries = source.envelope.entries
        entries[rowIndex] = readyRow
        return try IOSFailedHistoryEnvelope(
            revision: next.partialValue,
            entries: entries,
            audioCleanup: source.envelope.audioCleanup
        )
    }

    func metadataRetirementAuthority(
        receipt: IOSFailedHistoryMutationReceipt,
        row: IOSFailedHistoryEntry,
        origin: IOSFailedHistoryPendingMetadataRetirementAuthority.Origin,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryPendingMetadataRetirementAuthority {
        guard receipt.storeIdentity == storeIdentity,
              receipt.capabilityOwnerIdentity == capabilityOwnerIdentity,
              receipt.operationLeaseAuthorization.provesSameActiveLease(
                  as: operationLeaseAuthorization
              ),
              receipt.repositoryBinding == repositoryBinding,
              let authority =
                IOSFailedHistoryPendingMetadataRetirementAuthority(
                    mint: IOSFailedHistoryMetadataRetirementAuthorityMint(),
                    failedSource: receipt.snapshot,
                    row: row,
                    origin: origin,
                    failedStoreIdentity: storeIdentity,
                    expectedPendingStoreIdentity:
                        expectedPendingStoreIdentity,
                    ownerIdentity: capabilityOwnerIdentity,
                    repositoryBinding: repositoryBinding,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return authority
    }

    func reserveExactMutation(
        _ outcome: IOSFailedHistoryEnvelope,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryMutationCapability {
        try requireActiveLease(operationLeaseAuthorization)
        let repositoryBinding = try currentRepositoryBinding()

        if let intent = uncertainMutationIntent {
            guard intent.outcome == outcome else {
                throw IOSFailedHistoryError.commitUncertain
            }
            let current = try journal.load()
            let sourceStillCurrent: Bool = switch (intent.source, current) {
            case (.missing, .none): true
            case (.existing(let source), .some(let current)):
                source == current
            default: false
            }
            if sourceStillCurrent {
                return mutationCapability(
                    source: intent.source,
                    outcome: outcome,
                    retainedIntent: intent,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization,
                    repositoryBinding: repositoryBinding
                )
            }
            if let current,
               current.envelope == outcome {
                return mutationCapability(
                    source: .existing(current),
                    outcome: outcome,
                    retainedIntent: intent,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization,
                    repositoryBinding: repositoryBinding
                )
            }
            throw IOSFailedHistoryError.commitUncertain
        }

        let source: IOSFailedHistoryMutationSource =
            if let current = try journal.load() {
                .existing(current)
            } else {
                .missing
            }
        try requireNextRevision(outcome, after: source)
        return mutationCapability(
            source: source,
            outcome: outcome,
            retainedIntent: nil,
            operationLeaseAuthorization: operationLeaseAuthorization,
            repositoryBinding: repositoryBinding
        )
    }

    func commitExactMutation(
        _ capability: IOSFailedHistoryMutationCapability
    ) throws -> IOSFailedHistoryMutationReceipt {
        try requireCapability(capability)
        if let retainedIntent = capability.retainedIntent {
            guard uncertainMutationIntent == retainedIntent,
                  retainedIntent.outcome == capability.outcome else {
                throw IOSFailedHistoryError.commitUncertain
            }
        } else {
            guard uncertainMutationIntent == nil else {
                throw IOSFailedHistoryError.commitUncertain
            }
        }
        return try publish(
            capability.outcome,
            source: capability.source,
            capability: capability
        )
    }

    func publish(
        _ outcome: IOSFailedHistoryEnvelope,
        source: IOSFailedHistoryMutationSource,
        capability: IOSFailedHistoryMutationCapability
    ) throws -> IOSFailedHistoryMutationReceipt {
        let attemptedIntent = IOSFailedHistoryUncertainMutationIntent(
            source: source,
            outcome: outcome
        )
        let retainedIntent = capability.retainedIntent
        do {
            try requireRepositoryBinding(capability.repositoryBinding)
            let snapshot: IOSFailedHistoryJournalSnapshot = switch source {
            case .missing:
                try journal.create(
                    outcome,
                    authorization:
                        IOSFailedHistoryJournalMutationAuthorization(
                            expectedRepositoryRoot: capability
                                .repositoryBinding?.physicalRootIdentity
                        )
                )
            case .existing(let current):
                try journal.replace(
                    outcome,
                    expected: current,
                    authorization:
                        IOSFailedHistoryJournalMutationAuthorization(
                            expectedRepositoryRoot: capability
                                .repositoryBinding?.physicalRootIdentity
                        )
                )
            }
            guard snapshot.envelope == outcome else {
                retainMutationIntent(attemptedIntent)
                throw IOSFailedHistoryError.commitUncertain
            }
            do {
                try requireRepositoryBinding(capability.repositoryBinding)
            } catch {
                retainMutationIntent(attemptedIntent)
                throw error
            }
            clearMutationIntent()
            return IOSFailedHistoryMutationReceipt(
                snapshot: snapshot,
                storeIdentity: storeIdentity,
                capabilityOwnerIdentity: capabilityOwnerIdentity,
                operationLeaseAuthorization:
                    capability.operationLeaseAuthorization,
                repositoryBinding: capability.repositoryBinding
            )
        } catch IOSFailedHistoryError.commitUncertain {
            retainMutationIntent(attemptedIntent)
            throw IOSFailedHistoryError.commitUncertain
        } catch IOSFailedHistoryError.compareAndSwapFailed {
            guard let retainedIntent else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
            retainMutationIntent(retainedIntent)
            throw IOSFailedHistoryError.commitUncertain
        } catch {
            do {
                try requireRepositoryBinding(capability.repositoryBinding)
            } catch {
                throw IOSFailedHistoryError.repositoryIdentityConflict
            }
            if let retainedIntent {
                retainMutationIntent(retainedIntent)
                throw IOSFailedHistoryError.commitUncertain
            }
            throw error
        }
    }

    func mutationCapability(
        source: IOSFailedHistoryMutationSource,
        outcome: IOSFailedHistoryEnvelope,
        retainedIntent: IOSFailedHistoryUncertainMutationIntent?,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding?
    ) -> IOSFailedHistoryMutationCapability {
        IOSFailedHistoryMutationCapability(
            source: source,
            outcome: outcome,
            retainedIntent: retainedIntent,
            storeIdentity: storeIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization,
            repositoryBinding: repositoryBinding
        )
    }

    func requireNextRevision(
        _ outcome: IOSFailedHistoryEnvelope,
        after source: IOSFailedHistoryMutationSource
    ) throws {
        switch source {
        case .missing:
            guard outcome.revision == 1 else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
        case .existing(let current):
            let next = current.envelope.revision.addingReportingOverflow(1)
            guard !next.overflow else {
                throw IOSFailedHistoryError.revisionOverflow
            }
            guard outcome.revision == next.partialValue else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
        }
    }

    func validatedSnapshot(
        for receipt: IOSFailedHistoryMutationReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryJournalSnapshot {
        try requireActiveLease(operationLeaseAuthorization)
        try requireNoMutationUncertainty()
        guard receipt.storeIdentity == storeIdentity,
              receipt.capabilityOwnerIdentity == capabilityOwnerIdentity,
              receipt.operationLeaseAuthorization.provesSameActiveLease(
                  as: operationLeaseAuthorization
              ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        try requireRepositoryBinding(receipt.repositoryBinding)
        guard let current = try journal.load(),
              current == receipt.snapshot else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        try requireRepositoryBinding(receipt.repositoryBinding)
        return current
    }

    func requireCapability(
        _ capability: IOSFailedHistoryMutationCapability
    ) throws {
        try requireActiveLease(capability.operationLeaseAuthorization)
        guard capability.storeIdentity == storeIdentity,
              capability.capabilityOwnerIdentity
                == capabilityOwnerIdentity else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        try requireRepositoryBinding(capability.repositoryBinding)
    }

    func requireActiveLease(
        _ authorization: IOSPersistenceOperationLeaseAuthorization
    ) throws {
        guard operationGateBinding.proves(authorization) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    func requireNoMutationUncertainty() throws {
        guard uncertainMutationIntent == nil,
              !mutationInterlock.isCleanupBlocked else {
            throw IOSFailedHistoryError.commitUncertain
        }
    }

    func retainMutationIntent(
        _ intent: IOSFailedHistoryUncertainMutationIntent
    ) {
        uncertainMutationIntent = intent
        mutationInterlock.retainUncertainty()
    }

    func clearMutationIntent() {
        uncertainMutationIntent = nil
        transferMutationIntent = nil
        rowRemovalMutationIntent = nil
        retryCancellationMutationIntent = nil
        retryMutationIntent = nil
        mutationInterlock.clearUncertainty()
    }

    func currentRepositoryBinding()
        throws -> IOSAcceptedHistoryCoordinatorRepositoryBinding? {
        guard let repositoryGuard else { return nil }
        do {
            return try repositoryGuard.revalidate()
        } catch {
            throw IOSFailedHistoryError.repositoryIdentityConflict
        }
    }

    func requireRepositoryBinding(
        _ expected: IOSAcceptedHistoryCoordinatorRepositoryBinding?
    ) throws {
        switch (repositoryGuard, expected) {
        case (.none, .none):
            return
        case (.some(let repositoryGuard), .some(let expected)):
            do {
                _ = try repositoryGuard.revalidate(
                    expectedBinding: expected
                )
            } catch {
                throw IOSFailedHistoryError.repositoryIdentityConflict
            }
        case (.none, .some), (.some, .none):
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }
}
