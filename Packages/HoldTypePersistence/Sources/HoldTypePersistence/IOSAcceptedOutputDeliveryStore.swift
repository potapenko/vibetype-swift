import Foundation

struct IOSAcceptedOutputDeliveryGuardedBaselineEvidence: Sendable {
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity

    fileprivate init(
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    ) {
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
    }
}

enum IOSAcceptedOutputDeliveryAcceptanceProvenance: Equatable, Sendable {
    case freshCurrentProcess
    case preexisting
    case failedRetry(IOSFailedHistoryRetryDeliveryRelationKey)
}

enum IOSAcceptedOutputHistoryDeliveryDisposition: Equatable, Sendable {
    case absentOrUnrelated
    case confirmed(IOSAcceptedOutputDeliveryAuthorization)
    case expired
    case clockRollbackAmbiguous
}

extension IOSAcceptedOutputHistoryDeliveryDisposition:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedOutputHistoryDeliveryDisposition(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSAcceptedOutputDeliveryStoreIdentity: Equatable, Sendable {
    private let value = UUID()
}

private final class IOSFailedHistoryRetryDeliveryPermitAuthority:
    @unchecked Sendable {
    private let interlock: IOSFailedHistoryMutationInterlock
    private let operationGateBinding: IOSPersistenceOperationGateBinding
    private let deliveryStoreIdentity:
        IOSAcceptedOutputDeliveryStoreIdentity
    private let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity

    init(
        interlock: IOSFailedHistoryMutationInterlock,
        operationGateBinding: IOSPersistenceOperationGateBinding,
        deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    ) {
        self.interlock = interlock
        self.operationGateBinding = operationGateBinding
        self.deliveryStoreIdentity = deliveryStoreIdentity
        self.ownerIdentity = ownerIdentity
    }

    func permits(
        _ receipt: IOSFailedHistoryRetryDeliveryRelationReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        operationGateBinding.proves(operationLeaseAuthorization)
            && receipt.deliveryStoreIdentity == deliveryStoreIdentity
            && receipt.ownerIdentity == ownerIdentity
            && receipt.operationLeaseAuthorization.provesSameActiveLease(
                as: operationLeaseAuthorization
            )
            && interlock.permitsRetryDeliveryRelation(
                receipt.relationKey,
                freezeReservation:
                    receipt.relationReservation,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
    }
}

/// Delivery-store-minted authority for the one active failed-Retry relation.
/// The raw relation key remains an identity only; it cannot bypass mutation
/// admission without this exact store, owner, root gate, receipt, and lease.
struct IOSFailedHistoryRetryDeliveryPermit: Sendable {
    let relationReceipt: IOSFailedHistoryRetryDeliveryRelationReceipt
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization
    private let authority: IOSFailedHistoryRetryDeliveryPermitAuthority

    fileprivate init(
        relationReceipt: IOSFailedHistoryRetryDeliveryRelationReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        authority: IOSFailedHistoryRetryDeliveryPermitAuthority
    ) {
        self.relationReceipt = relationReceipt
        self.operationLeaseAuthorization = operationLeaseAuthorization
        self.authority = authority
    }

    var relationKey: IOSFailedHistoryRetryDeliveryRelationKey {
        relationReceipt.relationKey
    }

    func provesActiveRelation() -> Bool {
        authority.permits(
            relationReceipt,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }
}

extension IOSFailedHistoryRetryDeliveryPermit:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryDeliveryPermit(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

private final class IOSAcceptedOutputFailedRelationInterlockBinding:
    @unchecked Sendable {
    private let lock = NSLock()
    private var interlock: IOSFailedHistoryMutationInterlock?

    init(_ interlock: IOSFailedHistoryMutationInterlock? = nil) {
        self.interlock = interlock
    }

    func bind(_ interlock: IOSFailedHistoryMutationInterlock) -> Bool {
        lock.withLock {
            if let current = self.interlock {
                return current === interlock
            }
            self.interlock = interlock
            return true
        }
    }

    func current() -> IOSFailedHistoryMutationInterlock? {
        lock.withLock { interlock }
    }
}

enum IOSAcceptedOutputPendingHistoryTransferClaimResult: Equatable {
    case claimed
    case claimedExpired
    case expired
    case invalid
}

private final class IOSAcceptedOutputPendingHistoryTransferLease:
    @unchecked Sendable {
    private enum State: Equatable {
        case active
        case claimed(IOSAcceptedHistoryOutboxStoreIdentity)
        case consumed
        case released
    }

    private let lock = NSLock()
    private let monotonicExpiryNanoseconds: UInt64
    private let monotonicNowNanoseconds: @Sendable () -> UInt64
    private var state = State.active

    init(
        monotonicExpiryNanoseconds: UInt64,
        monotonicNowNanoseconds: @escaping @Sendable () -> UInt64
    ) {
        self.monotonicExpiryNanoseconds = monotonicExpiryNanoseconds
        self.monotonicNowNanoseconds = monotonicNowNanoseconds
    }

    func claim(
        for outboxStoreIdentity: IOSAcceptedHistoryOutboxStoreIdentity
    ) -> IOSAcceptedOutputPendingHistoryTransferClaimResult {
        lock.withLock {
            switch state {
            case .active:
                guard monotonicNowNanoseconds()
                        < monotonicExpiryNanoseconds else {
                    return .expired
                }
                state = .claimed(outboxStoreIdentity)
                return .claimed
            case .claimed(let existing) where existing == outboxStoreIdentity:
                return monotonicNowNanoseconds()
                    < monotonicExpiryNanoseconds
                    ? .claimed
                    : .claimedExpired
            case .claimed, .consumed, .released:
                return .invalid
            }
        }
    }

    func permits(
        outboxStoreIdentity: IOSAcceptedHistoryOutboxStoreIdentity?
    ) -> Bool {
        lock.withLock {
            switch (state, outboxStoreIdentity) {
            case (.active, .none): true
            case (.claimed(let expected), .some(let supplied)):
                expected == supplied
            case (.active, .some), (.claimed, .none), (.consumed, _),
                 (.released, _):
                false
            }
        }
    }

    func consume() {
        lock.withLock {
            switch state {
            case .active, .claimed:
                state = .consumed
            case .consumed, .released:
                break
            }
        }
    }

    func release() {
        lock.withLock {
            switch state {
            case .active, .claimed:
                state = .released
            case .consumed, .released:
                break
            }
        }
    }
}

struct IOSAcceptedOutputPendingHistoryTransferReservation:
    Sendable {
    fileprivate let authorization: IOSAcceptedOutputDeliveryAuthorization
    fileprivate let policyGeneration: Int64
    fileprivate let storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    fileprivate let reservationID: UUID
    private let lease: IOSAcceptedOutputPendingHistoryTransferLease

    var capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity {
        authorization.capabilityOwnerIdentity
    }

    var deliveryAuthorization: IOSAcceptedOutputDeliveryAuthorization {
        authorization
    }

    var confirmedPolicyGeneration: Int64 {
        policyGeneration
    }

    func claimForOutbox(
        authorization: IOSAcceptedOutputDeliveryAuthorization,
        policyGeneration: Int64,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity,
        outboxStoreIdentity: IOSAcceptedHistoryOutboxStoreIdentity
    ) -> IOSAcceptedOutputPendingHistoryTransferClaimResult {
        guard self.authorization == authorization,
              self.policyGeneration == policyGeneration,
              capabilityOwnerIdentity == ownerIdentity,
              storeIdentity == deliveryStoreIdentity else {
            return .invalid
        }
        return lease.claim(for: outboxStoreIdentity)
    }

    func matches(
        authorization: IOSAcceptedOutputDeliveryAuthorization,
        policyGeneration: Int64,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    ) -> Bool {
        self.authorization == authorization
            && self.policyGeneration == policyGeneration
            && capabilityOwnerIdentity == ownerIdentity
    }

    func permitsOwnershipProof(
        from outboxStoreIdentity: IOSAcceptedHistoryOutboxStoreIdentity?
    ) -> Bool {
        lease.permits(outboxStoreIdentity: outboxStoreIdentity)
    }

    fileprivate func consume() {
        lease.consume()
    }

    fileprivate func release() {
        lease.release()
    }

    fileprivate init(
        authorization: IOSAcceptedOutputDeliveryAuthorization,
        policyGeneration: Int64,
        storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity,
        monotonicExpiryNanoseconds: UInt64,
        monotonicNowNanoseconds: @escaping @Sendable () -> UInt64
    ) {
        self.authorization = authorization
        self.policyGeneration = policyGeneration
        self.storeIdentity = storeIdentity
        reservationID = UUID()
        lease = IOSAcceptedOutputPendingHistoryTransferLease(
            monotonicExpiryNanoseconds: monotonicExpiryNanoseconds,
            monotonicNowNanoseconds: monotonicNowNanoseconds
        )
    }
}

extension IOSAcceptedOutputPendingHistoryTransferReservation: Equatable {
    static func == (
        lhs: IOSAcceptedOutputPendingHistoryTransferReservation,
        rhs: IOSAcceptedOutputPendingHistoryTransferReservation
    ) -> Bool {
        lhs.authorization == rhs.authorization
            && lhs.policyGeneration == rhs.policyGeneration
            && lhs.storeIdentity == rhs.storeIdentity
            && lhs.reservationID == rhs.reservationID
    }
}

extension IOSAcceptedOutputPendingHistoryTransferReservation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedOutputPendingHistoryTransferReservation(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSAcceptedOutputBridgePublicationReservation: Equatable, Sendable {
    fileprivate let snapshot: IOSAcceptedOutputDeliveryJournalSnapshot
    fileprivate let storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    fileprivate let reservationID: UUID
}

extension IOSAcceptedOutputBridgePublicationReservation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedOutputBridgePublicationReservation(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSAcceptedOutputDeliveryStoreIdentity:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedOutputDeliveryStoreIdentity(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSAcceptedOutputDeliveryAcceptance: Equatable, Sendable {
    let record: IOSAcceptedOutputDeliveryRecord
    let provenance: IOSAcceptedOutputDeliveryAcceptanceProvenance
}

struct IOSAcceptedOutputDeliveryExpiredRemovalAuthorization:
    Equatable,
    Sendable {
    fileprivate let snapshot: IOSAcceptedOutputDeliveryJournalSnapshot
    fileprivate let observationSnapshot:
        IOSAcceptedOutputDeliveryJournalSnapshot
    fileprivate let storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity

    var record: IOSAcceptedOutputDeliveryRecord { snapshot.record }
}

struct IOSAcceptedOutputDeliveryExpiredObservation: Equatable, Sendable {
    fileprivate let snapshot: IOSAcceptedOutputDeliveryJournalSnapshot
    fileprivate let storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity

    var record: IOSAcceptedOutputDeliveryRecord { snapshot.record }

    func belongs(
        to storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    ) -> Bool {
        self.storeIdentity == storeIdentity
    }

    func provesLineage(
        of authorization:
            IOSAcceptedOutputDeliveryExpiredRemovalAuthorization
    ) -> Bool {
        storeIdentity == authorization.storeIdentity
            && snapshot == authorization.observationSnapshot
            && record == authorization.record
    }
}

enum IOSAcceptedOutputDeliveryExpiredObservationResult: Equatable, Sendable {
    case alreadyAbsent
    case observed(IOSAcceptedOutputDeliveryExpiredObservation)
}

enum IOSAcceptedOutputDeliveryExpiredRemovalPreparation:
    Equatable,
    Sendable {
    case alreadyAbsent
    case authorized(IOSAcceptedOutputDeliveryExpiredRemovalAuthorization)
}

extension IOSAcceptedOutputDeliveryAcceptanceProvenance:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedOutputDeliveryAcceptanceProvenance(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSAcceptedOutputDeliveryAcceptance:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedOutputDeliveryAcceptance(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSAcceptedOutputDeliveryExpiredRemovalAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedOutputDeliveryExpiredRemovalAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSAcceptedOutputDeliveryExpiredObservation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedOutputDeliveryExpiredObservation(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSAcceptedOutputDeliveryExpiredObservationResult:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedOutputDeliveryExpiredObservationResult(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSAcceptedOutputDeliveryExpiredRemovalPreparation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedOutputDeliveryExpiredRemovalPreparation(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSAcceptedOutputDeliveryGuardedBaselineEvidence:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedOutputDeliveryGuardedBaselineEvidence(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

public struct IOSAcceptedOutputDeliveryMaintenanceReport: Equatable, Sendable {
    public let inspectedEntryCount: Int
    public let inspectedByteCount: Int64
    public let removedFileCount: Int
    public let removedByteCount: Int64
    public let reachedLimit: Bool

    init(_ report: IOSStrictProtectedRecordMaintenanceReport) {
        inspectedEntryCount = report.inspectedEntryCount
        inspectedByteCount = report.inspectedByteCount
        removedFileCount = report.removedFileCount
        removedByteCount = report.removedByteCount
        reachedLimit = report.reachedLimit
    }
}

/// Owns the containing app's one crash-safe accepted-output delivery slot.
public actor IOSAcceptedOutputDeliveryStore {
    nonisolated let capabilityOwnerIdentity:
        IOSAcceptedHistoryCapabilityOwnerIdentity
    private enum TemporalState: Equatable {
        case active
        case expired
        case rollbackAmbiguous
    }

    private struct MonotonicDeadline: Sendable {
        let expiresAt: Date
        let uptimeNanoseconds: UInt64
    }

    private enum HistoryTransitionOperation: Equatable, Sendable {
        case commit(
            IOSAcceptedOutputDeliveryAuthorization,
            IOSAcceptedHistoryRowReceipt
        )
        case cancel(
            IOSAcceptedOutputDeliveryAuthorization,
            IOSHistoryPolicyReceipt
        )

        var authorization: IOSAcceptedOutputDeliveryAuthorization {
            switch self {
            case .commit(let authorization, _),
                 .cancel(let authorization, _):
                authorization
            }
        }

        var targetState: IOSAcceptedOutputHistoryWriteState {
            switch self {
            case .commit: .committed
            case .cancel: .cancelled
            }
        }

        var provesRequiredCapability: Bool {
            switch self {
            case .commit(let authorization, let receipt):
                return receipt.provesDecision(for: authorization)
            case .cancel(let authorization, let receipt):
                guard let marker = authorization.record.historyWrite,
                      marker.state.isPendingDecision else {
                    return false
                }
                return receipt.state.policyGeneration > marker.policyGeneration
            }
        }
    }

    private struct UncertainHistoryTransition: Equatable, Sendable {
        let operation: HistoryTransitionOperation
        let intended: IOSAcceptedOutputDeliveryRecord
    }

    private struct PendingHistoryReplacementOperation: Equatable, Sendable {
        let preparation: IOSAcceptedOutputDeliveryPreparation
        let reservation:
            IOSAcceptedOutputPendingHistoryTransferReservation
        let ownershipProof: IOSAcceptedOutputHistoryOwnershipProof

        var authorization: IOSAcceptedOutputDeliveryAuthorization {
            reservation.authorization
        }
    }

    private struct UncertainPendingHistoryReplacement: Equatable, Sendable {
        let operation: PendingHistoryReplacementOperation
        let intended: IOSAcceptedOutputDeliveryRecord
    }

    private struct PendingHistoryClearOperation: Equatable, Sendable {
        let authorization: IOSAcceptedOutputDeliveryAuthorization
        let ownershipProof: IOSAcceptedOutputHistoryOwnershipProof
    }

    private enum PendingHistoryClearStage: Equatable, Sendable {
        case tombstoneCommit
        case removalCommit
    }

    private struct UncertainPendingHistoryClear: Equatable, Sendable {
        let operation: PendingHistoryClearOperation
        let tombstone: IOSAcceptedOutputDeliveryRecord
        let stage: PendingHistoryClearStage
    }

    private enum AcceptanceSource: Equatable, Sendable {
        case missing
        case existing(IOSAcceptedOutputDeliveryJournalSnapshot)
    }

    private struct UncertainAcceptanceIntent: Equatable, Sendable {
        let preparation: IOSAcceptedOutputDeliveryPreparation
        let source: AcceptanceSource
        let intended: IOSAcceptedOutputDeliveryRecord
        let provenance: IOSAcceptedOutputDeliveryAcceptanceProvenance

        var intendedWasVisibleInSource: Bool {
            guard case .existing(let source) = source else { return false }
            return source.record == intended
        }
    }

    private let journal: any IOSAcceptedOutputDeliveryJournalStoring
    nonisolated let storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    nonisolated let outboxStoreIdentity:
        IOSAcceptedHistoryOutboxStoreIdentity
    private nonisolated let operationGateBinding:
        IOSPersistenceOperationGateBinding
    private nonisolated let failedRelationInterlockBinding:
        IOSAcceptedOutputFailedRelationInterlockBinding
    private let now: @Sendable () -> Date
    private let monotonicNowNanoseconds: @Sendable () -> UInt64

    private var monotonicDeadlines: [UUID: MonotonicDeadline] = [:]
    private var confirmedAuthorizationFileRevision:
        IOSStrictProtectedRecordFileRevision?
    private var uncertainHistoryTransition: UncertainHistoryTransition?
    private var uncertainPendingHistoryReplacement:
        UncertainPendingHistoryReplacement?
    private var uncertainPendingHistoryClear: UncertainPendingHistoryClear?
    private var uncertainAcceptanceIntent: UncertainAcceptanceIntent?
    private var pendingHistoryTransferReservation:
        IOSAcceptedOutputPendingHistoryTransferReservation?
    private var pendingBridgePublicationReservation:
        IOSAcceptedOutputBridgePublicationReservation?
    private var foregroundVoiceCleanupPending = false

    init(
        applicationSupportDirectoryURL: URL,
        storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity =
            IOSAcceptedOutputDeliveryStoreIdentity(),
        outboxStoreIdentity: IOSAcceptedHistoryOutboxStoreIdentity =
            IOSAcceptedHistoryOutboxStoreIdentity(),
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
            IOSAcceptedHistoryCapabilityOwnerIdentity(),
        operationGateIdentity: IOSPersistenceOperationGateIdentity? = nil,
        failedHistoryMutationInterlock:
            IOSFailedHistoryMutationInterlock? = nil,
        repositoryGuard:
            IOSAcceptedHistoryCoordinatorRepositoryGuard? = nil
    ) {
        journal = FoundationIOSAcceptedOutputDeliveryJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            repositoryGuard: repositoryGuard
        )
        now = { Date() }
        monotonicNowNanoseconds = { DispatchTime.now().uptimeNanoseconds }
        self.storeIdentity = storeIdentity
        self.outboxStoreIdentity = outboxStoreIdentity
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        operationGateBinding = IOSPersistenceOperationGateBinding(
            identity: operationGateIdentity
        )
        failedRelationInterlockBinding =
            IOSAcceptedOutputFailedRelationInterlockBinding(
                failedHistoryMutationInterlock
            )
    }

    init(
        journal: any IOSAcceptedOutputDeliveryJournalStoring,
        now: @escaping @Sendable () -> Date = { Date() },
        monotonicNowNanoseconds: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        },
        storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity =
            IOSAcceptedOutputDeliveryStoreIdentity(),
        outboxStoreIdentity: IOSAcceptedHistoryOutboxStoreIdentity =
            IOSAcceptedHistoryOutboxStoreIdentity(),
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
            IOSAcceptedHistoryCapabilityOwnerIdentity(),
        operationGateIdentity: IOSPersistenceOperationGateIdentity? = nil,
        failedHistoryMutationInterlock:
            IOSFailedHistoryMutationInterlock? = nil
    ) {
        self.journal = journal
        self.storeIdentity = storeIdentity
        self.outboxStoreIdentity = outboxStoreIdentity
        self.now = now
        self.monotonicNowNanoseconds = monotonicNowNanoseconds
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        operationGateBinding = IOSPersistenceOperationGateBinding(
            identity: operationGateIdentity
        )
        failedRelationInterlockBinding =
            IOSAcceptedOutputFailedRelationInterlockBinding(
                failedHistoryMutationInterlock
            )
    }

    nonisolated func bindOperationGateIdentity(
        _ identity: IOSPersistenceOperationGateIdentity
    ) -> Bool {
        operationGateBinding.bind(identity)
    }

    nonisolated func bindFailedHistoryMutationInterlock(
        _ interlock: IOSFailedHistoryMutationInterlock
    ) -> Bool {
        failedRelationInterlockBinding.bind(interlock)
    }

    func authorizeFailedRetryDeliveryPermit(
        acceptingOutputReceipt:
            IOSFailedHistoryRetryAcceptingOutputReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryDeliveryPermit {
        guard let interlock = failedRelationInterlockBinding.current(),
              acceptingOutputReceipt.deliveryStoreIdentity == storeIdentity,
              acceptingOutputReceipt.ownerIdentity
                == capabilityOwnerIdentity,
              acceptingOutputReceipt.frozenSlotProof.deliveryStoreIdentity
                == storeIdentity,
              acceptingOutputReceipt.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        let permit = IOSFailedHistoryRetryDeliveryPermit(
            relationReceipt: .live(acceptingOutputReceipt),
            operationLeaseAuthorization: operationLeaseAuthorization,
            authority: IOSFailedHistoryRetryDeliveryPermitAuthority(
                interlock: interlock,
                operationGateBinding: operationGateBinding,
                deliveryStoreIdentity: storeIdentity,
                ownerIdentity: capabilityOwnerIdentity
            )
        )
        guard permit.provesActiveRelation() else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        return permit
    }

    func authorizeFailedRetryDeliveryPermit(
        recoveredRelation: IOSFailedHistoryRetryRecoveredRelation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryDeliveryPermit {
        guard let interlock = failedRelationInterlockBinding.current(),
              recoveredRelation.deliveryStoreIdentity == storeIdentity,
              recoveredRelation.ownerIdentity == capabilityOwnerIdentity,
              recoveredRelation.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        let permit = IOSFailedHistoryRetryDeliveryPermit(
            relationReceipt: .relaunched(recoveredRelation),
            operationLeaseAuthorization: operationLeaseAuthorization,
            authority: IOSFailedHistoryRetryDeliveryPermitAuthority(
                interlock: interlock,
                operationGateBinding: operationGateBinding,
                deliveryStoreIdentity: storeIdentity,
                ownerIdentity: capabilityOwnerIdentity
            )
        )
        guard permit.provesActiveRelation() else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        return permit
    }

    func proveFailedRetryPreAcceptanceAbsence(
        reservation: IOSFailedHistoryRetryRelaunchReservation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryPreAcceptanceAbsenceProof {
        let inspection = reservation.inspection
        guard operationGateBinding.proves(operationLeaseAuthorization),
              reservation.operationLeaseAuthorization.provesSameActiveLease(
                as: operationLeaseAuthorization
              ),
              inspection.deliveryStoreIdentity == storeIdentity,
              inspection.ownerIdentity == capabilityOwnerIdentity,
              inspection.retryOperation.state == .reserved
                || inspection.retryOperation.state == .providerDispatched,
              let interlock = failedRelationInterlockBinding.current(),
              interlock.requiresRetryRecoveryScan,
              !interlock.hasRetryDeliveryProtection else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        let observedSlot: IOSFailedHistoryRetryObservedDeliverySlot
        if let current = try journal.load() {
            let record = current.record
            guard temporalState(for: record) != .rollbackAmbiguous else {
                throw IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
            }
            guard record.failedRetryID != inspection.retryOperation.retryID,
                  record.isWhollyUnrelatedToFailedRetry(
                    row: inspection.row,
                    operation: inspection.retryOperation
                  ) else {
                throw IOSAcceptedOutputDeliveryError.identityCollision
            }
            observedSlot = .whollyUnrelated(try confirmIdentical(current))
        } else {
            observedSlot = .missing
        }
        guard let proof = IOSFailedHistoryRetryPreAcceptanceAbsenceProof(
            mint: IOSFailedHistoryRetryPreAcceptanceAbsenceProofMint(),
            reservation: reservation,
            observedSlot: observedSlot,
            deliveryStoreIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return proof
    }

    func classifyFailedRetryRelaunchDelivery(
        acceptingInspection:
            IOSFailedHistoryRetryAcceptingRecoveryInspection,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryRelaunchDeliveryClassification {
        let inspection = acceptingInspection.inspection
        guard operationGateBinding.proves(operationLeaseAuthorization),
              acceptingInspection.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              inspection.deliveryStoreIdentity == storeIdentity,
              inspection.ownerIdentity == capabilityOwnerIdentity,
              let interlock = failedRelationInterlockBinding.current(),
              interlock.permitsRetryDeliveryRelation(
                acceptingInspection.relationKey,
                freezeReservation:
                    acceptingInspection.relationReservation,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
              ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        guard let current = try journal.load() else {
            guard let proof =
                    IOSFailedHistoryRetryAcceptedOutputAbsenceProof(
                        mint:
                            IOSFailedHistoryRetryAcceptedOutputAbsenceProofMint(),
                        acceptingInspection: acceptingInspection,
                        observedSlot: .missing,
                        deliveryStoreIdentity: storeIdentity,
                        ownerIdentity: capabilityOwnerIdentity,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    ) else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            return .missing(proof)
        }

        let record = current.record
        guard temporalState(for: record) != .rollbackAmbiguous else {
            throw IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        }
        if record.hasExactFailedRetryRecoveryAcceptance(
            row: inspection.row,
            operation: inspection.retryOperation
        ) {
            let confirmed = try confirmIdentical(current)
            let authorization = IOSAcceptedOutputDeliveryAuthorization(
                snapshot: confirmed,
                storeIdentity: storeIdentity,
                capabilityOwnerIdentity: capabilityOwnerIdentity
            )
            guard let acceptedText = confirmed.record.acceptedText,
                  let historyWrite = confirmed.record.historyWrite,
                  let preparation = try? IOSAcceptedOutputDeliveryPreparation(
                    deliveryID: confirmed.record.deliveryID,
                    sessionID: confirmed.record.sessionID,
                    attemptID: confirmed.record.attemptID,
                    transcriptID: confirmed.record.transcriptID,
                    rawAcceptedText: acceptedText,
                    outputIntent: confirmed.record.outputIntent,
                    automaticInsertionPreferenceEnabled: false,
                    keepLatestResult: confirmed.record.keepLatestResult,
                    historyWrite: historyWrite.replacingState(.pending)
                  ),
                  let relation = IOSFailedHistoryRetryRecoveredRelation(
                    mint: IOSFailedHistoryRetryRecoveredRelationMint(),
                    acceptingInspection: acceptingInspection,
                    deliveryAuthorization: authorization,
                    preparation: preparation,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                  ) else {
                return .collision
            }
            return .matching(relation)
        }

        guard record.failedRetryID != inspection.retryOperation.retryID,
              record.isWhollyUnrelatedToFailedRetry(
                row: inspection.row,
                operation: inspection.retryOperation
              ) else {
            return .collision
        }
        let confirmed = try confirmIdentical(current)
        guard let proof = IOSFailedHistoryRetryAcceptedOutputAbsenceProof(
            mint: IOSFailedHistoryRetryAcceptedOutputAbsenceProofMint(),
            acceptingInspection: acceptingInspection,
            observedSlot: .whollyUnrelated(confirmed),
            deliveryStoreIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return .frozenPredecessor(proof)
    }

    func confirmFailedRetryRecoveredTerminalDelivery(
        relation: IOSFailedHistoryRetryRecoveredRelation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryRecoveredTerminalDeliveryProof {
        let permit = try authorizeFailedRetryDeliveryPermit(
            recoveredRelation: relation,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireNoUncertainHistoryMutation()
        let current = try requireCurrentSnapshot()
        guard current.record.hasExactFailedRetryRecoveryAcceptance(
            row: relation.row,
            operation: relation.retryOperation
        ), current.record.historyWrite?.state == .committed
            || current.record.historyWrite?.state == .cancelled else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        _ = permit
        let confirmed = try confirmIdentical(current)
        let authorization = IOSAcceptedOutputDeliveryAuthorization(
            snapshot: confirmed,
            storeIdentity: storeIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
        guard let proof =
                IOSFailedHistoryRetryRecoveredTerminalDeliveryProof(
                    mint:
                        IOSFailedHistoryRetryRecoveredTerminalDeliveryProofMint(),
                    relation: relation,
                    deliveryAuthorization: authorization,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return proof
    }

    /// Commits a newly accepted transcript or atomically replaces the previous
    /// generation-zero delivery after all deferred-owner gates are satisfied.
    func accept(
        _ preparation: IOSAcceptedOutputDeliveryPreparation
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        try acceptForHistoryCoordinator(preparation).record
    }

    func acceptForHistoryCoordinator(
        _ preparation: IOSAcceptedOutputDeliveryPreparation,
        outboxAbsenceAuthorization:
            IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization? = nil,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization? = nil,
        failedRetryPermit:
            IOSFailedHistoryRetryDeliveryPermit? = nil
    ) throws -> IOSAcceptedOutputDeliveryAcceptance {
        try requireFailedRetryRelationDisposition(
            failedRetryPermit,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireFailedRetryPreparation(
            preparation,
            permit: failedRetryPermit
        )
        if outboxAbsenceAuthorization != nil {
            guard let operationLeaseAuthorization,
                  operationGateBinding.proves(
                      operationLeaseAuthorization
                  ) else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
        }
        try requirePreparationOwner(preparation)
        if let uncertainAcceptanceIntent {
            try requireNoUncertainHistoryMutationExceptAcceptance()
            guard preparation == uncertainAcceptanceIntent.preparation else {
                throw IOSAcceptedOutputDeliveryError.commitUncertain
            }
            return try reconcileAcceptance(
                uncertainAcceptanceIntent,
                outboxAbsenceAuthorization: outboxAbsenceAuthorization,
                operationLeaseAuthorization: operationLeaseAuthorization,
                failedRetryPermit: failedRetryPermit
            )
        }
        try requireNoUncertainHistoryMutation()
        return try performAccept(
            preparation,
            outboxAbsenceAuthorization: outboxAbsenceAuthorization,
            operationLeaseAuthorization: operationLeaseAuthorization,
            failedRetryPermit: failedRetryPermit
        )
    }

    func hasUncertainAcceptanceForHistoryCoordinator() -> Bool {
        uncertainAcceptanceIntent != nil
    }

    /// A policy cutover must not invalidate any process-retained delivery
    /// capability or reservation that is not represented by its own exact
    /// cutover phase.
    func hasRetainedHistoryWorkForPolicyCutover() -> Bool {
        uncertainHistoryTransition != nil
            || uncertainPendingHistoryReplacement != nil
            || uncertainPendingHistoryClear != nil
            || uncertainAcceptanceIntent != nil
            || pendingHistoryTransferReservation != nil
            || pendingBridgePublicationReservation != nil
    }

    func hasOnlyRetainedFailedRetryHistoryWork(
        for relationReceipt:
            IOSFailedHistoryRetryDeliveryRelationReceipt
    ) -> Bool {
        guard uncertainPendingHistoryReplacement == nil,
              uncertainPendingHistoryClear == nil,
              uncertainAcceptanceIntent == nil,
              pendingHistoryTransferReservation == nil,
              pendingBridgePublicationReservation == nil,
              let uncertainHistoryTransition else {
            return false
        }
        return uncertainHistoryTransition.operation.authorization.record
            .hasExactFailedRetryAcceptance(
                as: relationReceipt.preparation,
                retryID: relationReceipt.retryOperation.retryID
            )
    }

    func replacePendingHistory(
        with preparation: IOSAcceptedOutputDeliveryPreparation,
        reservation: IOSAcceptedOutputPendingHistoryTransferReservation,
        ownershipProof: IOSAcceptedOutputHistoryOwnershipProof,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization? = nil,
        failedRetryPermit:
            IOSFailedHistoryRetryDeliveryPermit? = nil
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        try requireFailedRetryRelationDisposition(
            failedRetryPermit,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireFailedRetryPreparation(
            preparation,
            permit: failedRetryPermit
        )
        try requirePreparationOwner(preparation)
        let authorization = reservation.authorization
        try requireFailedRetryFrozenPredecessor(
            authorization.record,
            permit: failedRetryPermit
        )
        guard authorization.storeIdentity == storeIdentity,
              authorization.capabilityOwnerIdentity == capabilityOwnerIdentity,
              reservation.storeIdentity == storeIdentity,
              pendingHistoryTransferReservation == reservation,
              ownershipProof.capabilityOwnerIdentity
                == capabilityOwnerIdentity,
              ownershipProof.provesOwnership(
                  for: authorization,
                  under: reservation
              ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        let operation = PendingHistoryReplacementOperation(
            preparation: preparation,
            reservation: reservation,
            ownershipProof: ownershipProof
        )
        if let uncertainPendingHistoryReplacement {
            return try reconcilePendingHistoryReplacement(
                uncertainPendingHistoryReplacement,
                operation: operation
            )
        }
        try requireNoUncertainHistoryMutation(allowing: reservation)
        do {
            return try performAccept(
                preparation,
                pendingHistoryReplacement: operation,
                operationLeaseAuthorization: operationLeaseAuthorization,
                failedRetryPermit: failedRetryPermit
            ).record
        } catch IOSAcceptedOutputDeliveryError.expired {
            clearPendingHistoryTransferReservation(reservation)
            throw IOSAcceptedOutputDeliveryError.expired
        } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
            clearPendingHistoryTransferReservation(reservation)
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        } catch IOSAcceptedOutputDeliveryError.identityCollision {
            clearPendingHistoryTransferReservation(reservation)
            throw IOSAcceptedOutputDeliveryError.identityCollision
        } catch IOSAcceptedOutputDeliveryError.bridgeRevocationRequired {
            clearPendingHistoryTransferReservation(reservation)
            throw IOSAcceptedOutputDeliveryError.bridgeRevocationRequired
        }
    }

    public func load() throws -> IOSAcceptedOutputDeliveryObservation? {
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: nil
        )
        try requireNoUncertainAcceptance()
        guard let snapshot = try journal.load() else { return nil }
        return observation(for: snapshot.record)
    }

    func freezeFailedRetrySlot(
        preparation: IOSAcceptedOutputDeliveryPreparation,
        dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSAcceptedOutputDeliveryFrozenSlotProof {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              dispatchReceipt.ownerIdentity == capabilityOwnerIdentity,
              dispatchReceipt.retryOperation.state == .providerDispatched,
              preparation.deliveryID
                == dispatchReceipt.retryOperation.deliveryID,
              preparation.sessionID
                == dispatchReceipt.retryOperation.sessionID,
              preparation.attemptID == dispatchReceipt.row.attemptID,
              preparation.transcriptID
                == dispatchReceipt.retryOperation.transcriptID else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: nil
        )
        try requirePreparationOwner(preparation)
        try requireNoUncertainHistoryMutation()
        guard let interlock = failedRelationInterlockBinding.current() else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        let operation = dispatchReceipt.retryOperation
        let relationKey = IOSFailedHistoryRetryDeliveryRelationKey(
            retryID: operation.retryID,
            deliveryID: operation.deliveryID,
            sessionID: operation.sessionID,
            attemptID: dispatchReceipt.row.attemptID,
            transcriptID: operation.transcriptID,
            failedStoreIdentity: dispatchReceipt.failedStoreIdentity,
            deliveryStoreIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: dispatchReceipt.repositoryBinding
        )
        guard let freezeReservation = interlock.reserveRetryDeliveryFreeze(
            relationKey,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        do {
            let frozenSlot: IOSAcceptedOutputDeliveryFrozenSlot
            if let current = try journal.load() {
                guard current.record.isWhollyUnrelatedToFailedRetry(
                    row: dispatchReceipt.row,
                    operation: operation
                ) else {
                    throw IOSAcceptedOutputDeliveryError.identityCollision
                }
                frozenSlot = .existing(current)
            } else {
                frozenSlot = .missing
            }
            guard let proof = IOSAcceptedOutputDeliveryFrozenSlotProof(
                mint: IOSAcceptedOutputDeliveryFrozenSlotProofMint(),
                frozenSlot: frozenSlot,
                preparation: preparation,
                retryingRow: dispatchReceipt.row,
                retryOperation: operation,
                freezeReservation: freezeReservation,
                deliveryStoreIdentity: storeIdentity,
                ownerIdentity: capabilityOwnerIdentity,
                repositoryBinding: dispatchReceipt.repositoryBinding,
                operationLeaseAuthorization: operationLeaseAuthorization
            ) else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            return proof
        } catch {
            _ = interlock.clearRetryDeliveryFreeze(freezeReservation)
            throw error
        }
    }

    func refreshFailedRetryFrozenSlotProof(
        from receipt: IOSFailedHistoryRetryAcceptingOutputReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSAcceptedOutputDeliveryFrozenSlotProof {
        guard receipt.deliveryStoreIdentity == storeIdentity,
              receipt.ownerIdentity == capabilityOwnerIdentity,
              receipt.frozenSlotProof.deliveryStoreIdentity
                == storeIdentity else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return try refreshFailedRetryFrozenSlotProof(
            retainedProof: receipt.frozenSlotProof,
            relationKey: receipt.relationKey,
            repositoryBinding: receipt.repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func refreshFailedRetryFrozenSlotProof(
        from retainedProof: IOSAcceptedOutputDeliveryFrozenSlotProof,
        dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSAcceptedOutputDeliveryFrozenSlotProof {
        guard retainedProof.deliveryStoreIdentity == storeIdentity,
              retainedProof.ownerIdentity == capabilityOwnerIdentity,
              retainedProof.retryingRow == dispatchReceipt.row,
              retainedProof.retryOperation
                == dispatchReceipt.retryOperation,
              retainedProof.repositoryBinding
                == dispatchReceipt.repositoryBinding else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        let operation = dispatchReceipt.retryOperation
        let relationKey = IOSFailedHistoryRetryDeliveryRelationKey(
            retryID: operation.retryID,
            deliveryID: operation.deliveryID,
            sessionID: operation.sessionID,
            attemptID: dispatchReceipt.row.attemptID,
            transcriptID: operation.transcriptID,
            failedStoreIdentity: dispatchReceipt.failedStoreIdentity,
            deliveryStoreIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: dispatchReceipt.repositoryBinding
        )
        return try refreshFailedRetryFrozenSlotProof(
            retainedProof: retainedProof,
            relationKey: relationKey,
            repositoryBinding: dispatchReceipt.repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    private func refreshFailedRetryFrozenSlotProof(
        retainedProof: IOSAcceptedOutputDeliveryFrozenSlotProof,
        relationKey: IOSFailedHistoryRetryDeliveryRelationKey,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSAcceptedOutputDeliveryFrozenSlotProof {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              relationKey.deliveryStoreIdentity == storeIdentity,
              relationKey.ownerIdentity == capabilityOwnerIdentity,
              relationKey.repositoryBinding == repositoryBinding,
              retainedProof.freezeReservation.relationKey
                == relationKey,
              let interlock = failedRelationInterlockBinding.current(),
              let refreshedReservation = interlock
                .refreshRetryDeliveryFreeze(
                    retainedProof.freezeReservation,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        try requireNoUncertainHistoryMutationExceptAcceptance()
        let current = try journal.load()
        let currentIsAccepted = current?.record
            .hasExactFailedRetryAcceptance(
                as: retainedProof.preparation,
                retryID: relationKey.retryID
            ) == true
        let predecessorIsUnchanged: Bool = switch (
            retainedProof.frozenSlot,
            current
        ) {
        case (.missing, .none):
            true
        case (.existing(let predecessor), .some(let observed)):
            predecessor == observed
                || isFailedRetryFrozenPredecessorLineage(
                    observed.record,
                    predecessor: predecessor.record
                )
        case (.missing, .some), (.existing, .none):
            false
        }
        guard currentIsAccepted || predecessorIsUnchanged else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        guard let refreshed = IOSAcceptedOutputDeliveryFrozenSlotProof(
            mint: IOSAcceptedOutputDeliveryFrozenSlotProofMint(),
            frozenSlot: retainedProof.frozenSlot,
            preparation: retainedProof.preparation,
            retryingRow: retainedProof.retryingRow,
            retryOperation: retainedProof.retryOperation,
            freezeReservation: refreshedReservation,
            deliveryStoreIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return refreshed
    }

    @discardableResult
    func releaseFailedRetryFrozenSlotReservation(
        _ proof: IOSAcceptedOutputDeliveryFrozenSlotProof,
        dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> Bool {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              proof.deliveryStoreIdentity == storeIdentity,
              proof.ownerIdentity == capabilityOwnerIdentity,
              proof.retryingRow == dispatchReceipt.row,
              proof.retryOperation == dispatchReceipt.retryOperation,
              proof.repositoryBinding == dispatchReceipt.repositoryBinding,
              proof.freezeReservation.relationKey.failedStoreIdentity
                == dispatchReceipt.failedStoreIdentity,
              let interlock = failedRelationInterlockBinding.current() else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return interlock.clearRetryDeliveryFreeze(
            proof.freezeReservation
        )
    }

    func confirmFailedRetryTerminalDelivery(
        acceptingOutputReceipt:
            IOSFailedHistoryRetryAcceptingOutputReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryRetryTerminalDeliveryProof {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              acceptingOutputReceipt.deliveryStoreIdentity == storeIdentity,
              acceptingOutputReceipt.ownerIdentity
                == capabilityOwnerIdentity else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        _ = try authorizeFailedRetryDeliveryPermit(
            acceptingOutputReceipt: acceptingOutputReceipt,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireNoUncertainHistoryMutation()
        let current = try requireCurrentSnapshot()
        guard current.record.hasExactFailedRetryAcceptance(
            as: acceptingOutputReceipt.frozenSlotProof.preparation,
            retryID: acceptingOutputReceipt.retryOperation.retryID
        ), current.record.historyWrite?.state == .committed
            || current.record.historyWrite?.state == .cancelled else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        let confirmed = try confirmIdentical(current)
        let authorization = IOSAcceptedOutputDeliveryAuthorization(
            snapshot: confirmed,
            storeIdentity: storeIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
        guard let proof = IOSFailedHistoryRetryTerminalDeliveryProof(
            mint: IOSFailedHistoryRetryTerminalDeliveryProofMint(),
            acceptingOutputReceipt: acceptingOutputReceipt,
            deliveryAuthorization: authorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return proof
    }

    func acceptFailedRetry(
        _ preparation: IOSAcceptedOutputDeliveryPreparation,
        acceptingOutputReceipt:
            IOSFailedHistoryRetryAcceptingOutputReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        outboxAbsenceAuthorization:
            IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization? = nil
    ) throws -> IOSAcceptedOutputDeliveryAcceptance {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              acceptingOutputReceipt.deliveryStoreIdentity == storeIdentity,
              acceptingOutputReceipt.ownerIdentity
                == capabilityOwnerIdentity,
              preparation
                == acceptingOutputReceipt.frozenSlotProof.preparation else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        let failedRetryPermit = try authorizeFailedRetryDeliveryPermit(
            acceptingOutputReceipt: acceptingOutputReceipt,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let current = try journal.load()
        let currentIsAccepted = current?.record
            .hasExactFailedRetryAcceptance(
                as: preparation,
                retryID: acceptingOutputReceipt.retryOperation.retryID
            ) == true
        let predecessorIsUnchanged: Bool = switch (
            acceptingOutputReceipt.frozenSlotProof.frozenSlot,
            current
        ) {
        case (.missing, .none):
            true
        case (.existing(let predecessor), .some(let observed)):
            predecessor == observed
                || isFailedRetryFrozenPredecessorLineage(
                    observed.record,
                    predecessor: predecessor.record
                )
        case (.missing, .some), (.existing, .none):
            false
        }
        guard currentIsAccepted || predecessorIsUnchanged else {
            if let current,
               !current.record.isWhollyUnrelatedToFailedRetry(
                   row: acceptingOutputReceipt.row,
                   operation: acceptingOutputReceipt.retryOperation
               ) {
                throw IOSAcceptedOutputDeliveryError.identityCollision
            }
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        return try acceptForHistoryCoordinator(
            preparation,
            outboxAbsenceAuthorization: outboxAbsenceAuthorization,
            operationLeaseAuthorization: operationLeaseAuthorization,
            failedRetryPermit: failedRetryPermit
        )
    }

    /// Narrow coordinator read used only to reconcile a retained acceptance
    /// whose commit result is uncertain. Public callers remain blocked.
    func loadForHistoryCoordinatorDuringAcceptance()
        throws -> IOSAcceptedOutputDeliveryObservation? {
        try requireNoUncertainHistoryMutationExceptAcceptance()
        let current = try journal.load()
        if let intent = uncertainAcceptanceIntent {
            let sourceStillCurrent: Bool = switch (intent.source, current) {
            case (.missing, .none): true
            case (.existing(let source), .some(let current)):
                source == current || source.record == current.record
            default: false
            }
            guard sourceStillCurrent
                    || current?.record == intent.intended else {
                throw IOSAcceptedOutputDeliveryError.commitUncertain
            }
        }
        guard let current else { return nil }
        return observation(for: current.record)
    }

    func loadForPendingHistoryReplacement(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        failedRetryPermit:
            IOSFailedHistoryRetryDeliveryPermit?
    ) throws -> IOSAcceptedOutputDeliveryObservation? {
        try requireFailedRetryRelationDisposition(
            failedRetryPermit,
            operationLeaseAuthorization:
                operationLeaseAuthorization
        )
        try requireNoUncertainAcceptance()
        guard let current = try journal.load() else { return nil }
        if let failedRetryPermit {
            try requireFailedRetryFrozenPredecessor(
                current.record,
                permit: failedRetryPermit
            )
        }
        return observation(for: current.record)
    }

    func proveGuardedBaseline()
        throws -> IOSAcceptedOutputDeliveryGuardedBaselineEvidence {
        try requireNoUncertainHistoryMutation()
        guard try journal.load()?.record.historyWrite == nil else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return IOSAcceptedOutputDeliveryGuardedBaselineEvidence(
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
    }

    /// Performs the mandatory identical durability-confirmation rewrite before
    /// an idempotent History upsert may use the accepted payload.
    func authorizePendingHistoryWrite(
        expected: IOSAcceptedOutputDeliveryExpectation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization? = nil,
        failedRetryPermit:
            IOSFailedHistoryRetryDeliveryPermit? = nil
    ) throws -> IOSAcceptedOutputDeliveryAuthorization {
        let authorization = try confirmActiveHistoryRecovery(
            expected: expected,
            operationLeaseAuthorization: operationLeaseAuthorization,
            failedRetryPermit: failedRetryPermit
        )
        guard authorization.record.historyWrite?.state.isPendingDecision
                == true else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        return authorization
    }

    /// Atomically blocks a future bridge publication before the coordinator
    /// crosses the outbox await boundary for this exact delivery.
    func reservePendingHistoryTransfer(
        authorization: IOSAcceptedOutputDeliveryAuthorization,
        policyReceipt: IOSHistoryPolicyReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization? = nil,
        failedRetryPermit:
            IOSFailedHistoryRetryDeliveryPermit? = nil
    ) throws -> IOSAcceptedOutputPendingHistoryTransferReservation {
        try requireFailedRetryRelationDisposition(
            failedRetryPermit,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireFailedRetryFrozenPredecessor(
            authorization.record,
            permit: failedRetryPermit
        )
        guard authorization.storeIdentity == storeIdentity,
              authorization.capabilityOwnerIdentity == capabilityOwnerIdentity,
              policyReceipt.capabilityOwnerIdentity
                == capabilityOwnerIdentity,
              let marker = authorization.record.historyWrite,
              marker.state.isPendingDecision,
              policyReceipt.state.historyEnabled,
              policyReceipt.state.policyGeneration
                == marker.policyGeneration else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        if let reservation = pendingHistoryTransferReservation {
            guard reservation.authorization == authorization,
                  reservation.policyGeneration
                    == policyReceipt.state.policyGeneration,
                  reservation.storeIdentity == storeIdentity else {
                throw IOSAcceptedOutputDeliveryError.commitUncertain
            }
            return reservation
        }
        try requireNoUncertainHistoryMutation()
        let current = try requireCurrentSnapshot()
        guard current == authorization.snapshot,
              current.record.historyWrite?.state.isPendingDecision == true else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireActive(current.record)
        try requireBridgeRevoked(current.record)
        guard let monotonicDeadline = monotonicDeadlines[
            current.record.deliveryID
        ], monotonicDeadline.expiresAt == current.record.expiresAt else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        let reservation = IOSAcceptedOutputPendingHistoryTransferReservation(
            authorization: authorization,
            policyGeneration: policyReceipt.state.policyGeneration,
            storeIdentity: storeIdentity,
            monotonicExpiryNanoseconds: monotonicDeadline.uptimeNanoseconds,
            monotonicNowNanoseconds: monotonicNowNanoseconds
        )
        pendingHistoryTransferReservation = reservation
        return reservation
    }

    func releasePendingHistoryTransfer(
        _ reservation: IOSAcceptedOutputPendingHistoryTransferReservation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization? = nil,
        failedRetryPermit:
            IOSFailedHistoryRetryDeliveryPermit? = nil
    ) throws {
        try requireFailedRetryRelationDisposition(
            failedRetryPermit,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireFailedRetryFrozenPredecessor(
            reservation.authorization.record,
            permit: failedRetryPermit
        )
        guard reservation.storeIdentity == storeIdentity,
              pendingHistoryTransferReservation == reservation,
              uncertainPendingHistoryReplacement == nil else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        reservation.release()
        pendingHistoryTransferReservation = nil
    }

    /// Mutually excludes the future generation-one bridge commit and App Group
    /// write from pending-History transfer. Process loss safely drops the
    /// reservation because generation zero remains the only durable state.
    func reserveBridgePublication(
        authorization: IOSAcceptedOutputDeliveryAuthorization
    ) throws -> IOSAcceptedOutputBridgePublicationReservation {
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: nil
        )
        guard authorization.storeIdentity == storeIdentity,
              authorization.capabilityOwnerIdentity
                == capabilityOwnerIdentity else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        if let reservation = pendingBridgePublicationReservation {
            guard authorization.snapshot == reservation.snapshot,
                  reservation.storeIdentity == storeIdentity else {
                throw IOSAcceptedOutputDeliveryError.commitUncertain
            }
            return reservation
        }
        try requireNoUncertainHistoryMutation()
        let snapshot = try requireCurrentSnapshot()
        guard snapshot == authorization.snapshot else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireActive(snapshot.record)
        guard snapshot.record.deliveryState != .discarded,
              snapshot.record.publicationGeneration == 0 else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        let reservation = IOSAcceptedOutputBridgePublicationReservation(
            snapshot: snapshot,
            storeIdentity: storeIdentity,
            reservationID: UUID()
        )
        pendingBridgePublicationReservation = reservation
        return reservation
    }

    func releaseBridgePublication(
        _ reservation: IOSAcceptedOutputBridgePublicationReservation
    ) throws {
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: nil
        )
        guard reservation.storeIdentity == storeIdentity,
              pendingBridgePublicationReservation == reservation else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        pendingBridgePublicationReservation = nil
    }

    /// Reconstructs physical delivery authority without interpreting the
    /// History marker. Every active marker state uses the same strict rewrite.
    func confirmActiveHistoryRecovery(
        expected: IOSAcceptedOutputDeliveryExpectation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization? = nil,
        failedRetryPermit:
            IOSFailedHistoryRetryDeliveryPermit? = nil
    ) throws -> IOSAcceptedOutputDeliveryAuthorization {
        try requireFailedRetryRelationDisposition(
            failedRetryPermit,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireNoUncertainHistoryMutation()
        let snapshot = try requireSnapshot(expected: expected)
        try requireFailedRetryRelatedRecord(
            snapshot.record,
            permit: failedRetryPermit
        )
        try requireActiveHistoryRecovery(
            snapshot.record,
            failedRetryPermit: failedRetryPermit
        )
        guard snapshot.record.deliveryState != .discarded else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        if confirmedAuthorizationFileRevision == snapshot.fileRevision {
            return IOSAcceptedOutputDeliveryAuthorization(
                snapshot: snapshot,
                storeIdentity: storeIdentity,
                capabilityOwnerIdentity: capabilityOwnerIdentity
            )
        }

        let confirmed = try journal.replace(
            snapshot.record,
            expected: snapshot
        )
        try requireActiveHistoryRecovery(
            confirmed.record,
            failedRetryPermit: failedRetryPermit
        )
        guard confirmed.record.deliveryState != .discarded else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        confirmedAuthorizationFileRevision = confirmed.fileRevision
        return IOSAcceptedOutputDeliveryAuthorization(
            snapshot: confirmed,
            storeIdentity: storeIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
    }

    /// Reconfirms only the exact retained source while an acceptance commit is
    /// uncertain. A visible intended replacement never needs terminal authority.
    func confirmActiveHistoryRecoveryDuringAcceptance(
        expected: IOSAcceptedOutputDeliveryExpectation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization? = nil,
        failedRetryPermit:
            IOSFailedHistoryRetryDeliveryPermit? = nil
    ) throws -> IOSAcceptedOutputDeliveryAuthorization {
        try requireFailedRetryRelationDisposition(
            failedRetryPermit,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireNoUncertainHistoryMutationExceptAcceptance()
        let retainedSource: IOSAcceptedOutputDeliveryJournalSnapshot?
        if let intent = uncertainAcceptanceIntent {
            guard case .existing(let source) = intent.source,
                  expected.matches(source.record) else {
                throw IOSAcceptedOutputDeliveryError.commitUncertain
            }
            retainedSource = source
        } else {
            retainedSource = nil
        }

        let snapshot = try requireSnapshot(expected: expected)
        try requireFailedRetryRelatedRecord(
            snapshot.record,
            permit: failedRetryPermit
        )
        if let retainedSource,
           snapshot != retainedSource,
           snapshot.record != retainedSource.record {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        try requireActiveHistoryRecovery(
            snapshot.record,
            failedRetryPermit: failedRetryPermit
        )
        guard snapshot.record.deliveryState != .discarded else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        if confirmedAuthorizationFileRevision == snapshot.fileRevision {
            return IOSAcceptedOutputDeliveryAuthorization(
                snapshot: snapshot,
                storeIdentity: storeIdentity,
                capabilityOwnerIdentity: capabilityOwnerIdentity
            )
        }

        let confirmed = try journal.replace(
            snapshot.record,
            expected: snapshot
        )
        try requireActiveHistoryRecovery(
            confirmed.record,
            failedRetryPermit: failedRetryPermit
        )
        guard confirmed.record.deliveryState != .discarded else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        if let intent = uncertainAcceptanceIntent {
            uncertainAcceptanceIntent = UncertainAcceptanceIntent(
                preparation: intent.preparation,
                source: .existing(confirmed),
                intended: intent.intended,
                provenance: intent.provenance
            )
        }
        confirmedAuthorizationFileRevision = confirmed.fileRevision
        return IOSAcceptedOutputDeliveryAuthorization(
            snapshot: confirmed,
            storeIdentity: storeIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
    }

    /// Confirms the exact delivery relation for a durable outbox membership.
    /// Only an identical physical rewrite can mint terminal-marker authority.
    func confirmMatchingHistoryDelivery(
        membership: IOSAcceptedHistoryOutboxReceipt
    ) throws -> IOSAcceptedOutputHistoryDeliveryDisposition {
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: nil
        )
        guard membership.deliveryStoreIdentity == storeIdentity,
              membership.storeIdentity == outboxStoreIdentity,
              membership.capabilityOwnerIdentity
                == capabilityOwnerIdentity else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireNoUncertainHistoryMutation()
        guard let snapshot = try journal.load() else {
            return .absentOrUnrelated
        }
        let observed = IOSAcceptedOutputDeliveryAuthorization(
            snapshot: snapshot,
            storeIdentity: storeIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
        switch membership.deliveryRelation(to: observed) {
        case .unrelated, .discarded:
            return .absentOrUnrelated
        case .collision:
            throw IOSAcceptedOutputDeliveryError.identityCollision
        case .pending, .committed, .cancelled:
            break
        }

        switch temporalState(for: snapshot.record) {
        case .expired:
            return .expired
        case .rollbackAmbiguous:
            return .clockRollbackAmbiguous
        case .active:
            let confirmed = try confirmIdentical(snapshot)
            confirmedAuthorizationFileRevision = confirmed.fileRevision
            return .confirmed(
                IOSAcceptedOutputDeliveryAuthorization(
                    snapshot: confirmed,
                    storeIdentity: storeIdentity,
                    capabilityOwnerIdentity: capabilityOwnerIdentity
                )
            )
        }
    }

    /// Records the exact durable History decision for this delivery.
    func commitHistoryWrite(
        authorization: IOSAcceptedOutputDeliveryAuthorization,
        rowReceipt: IOSAcceptedHistoryRowReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization? = nil,
        failedRetryPermit:
            IOSFailedHistoryRetryDeliveryPermit? = nil
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        try requireFailedRetryRelationDisposition(
            failedRetryPermit,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireFailedRetryAcceptedRecord(
            authorization.record,
            permit: failedRetryPermit
        )
        return try transitionHistoryWrite(
            .commit(authorization, rowReceipt)
        )
    }

    func cancelHistoryWrite(
        authorization: IOSAcceptedOutputDeliveryAuthorization,
        policyInvalidationReceipt: IOSHistoryPolicyReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization? = nil,
        failedRetryPermit:
            IOSFailedHistoryRetryDeliveryPermit? = nil
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        try requireFailedRetryRelationDisposition(
            failedRetryPermit,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireFailedRetryRelatedRecord(
            authorization.record,
            permit: failedRetryPermit
        )
        return try transitionHistoryWrite(
            .cancel(authorization, policyInvalidationReceipt)
        )
    }

    public func disableKeepLatestResult(
        expected: IOSAcceptedOutputDeliveryExpectation
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: nil
        )
        try requireNoUncertainHistoryMutation()
        let snapshot = try requireCurrentSnapshot()
        try requireActive(snapshot.record)

        if expected.matches(snapshot.record) {
            guard snapshot.record.deliveryState != .discarded else {
                throw IOSAcceptedOutputDeliveryError.invalidTransition
            }
            guard snapshot.record.keepLatestResult else {
                return snapshot.record
            }
            let replacement = try record(
                replacing: snapshot.record,
                revision: try nextRevision(after: snapshot.record.revision),
                updatedAt: try mutationNow(for: snapshot.record),
                keepLatestResult: false
            )
            return try commit(replacement, replacing: snapshot).record
        }

        guard isImmediateRetry(snapshot.record, after: expected),
              !snapshot.record.keepLatestResult else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return try confirmIdentical(snapshot).record
    }

    /// Explicit user clear. Generation-one values and pending History work stay
    /// blocked until their owning bridge/outbox checkpoints exist.
    public func clear(
        expected: IOSAcceptedOutputDeliveryExpectation
    ) throws -> IOSAcceptedOutputDeliveryRemovalResult {
        return try clear(
            expected: expected,
            outboxAbsenceAuthorization: nil,
            operationLeaseAuthorization: nil
        )
    }

    func clear(
        expected: IOSAcceptedOutputDeliveryExpectation,
        outboxAbsenceAuthorization:
            IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSAcceptedOutputDeliveryRemovalResult {
        guard operationGateBinding.proves(
            operationLeaseAuthorization
        ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return try clear(
            expected: expected,
            outboxAbsenceAuthorization: Optional(outboxAbsenceAuthorization),
            operationLeaseAuthorization:
                Optional(operationLeaseAuthorization)
        )
    }

    private func clear(
        expected: IOSAcceptedOutputDeliveryExpectation,
        outboxAbsenceAuthorization:
            IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization?,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization?
    ) throws -> IOSAcceptedOutputDeliveryRemovalResult {
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: nil
        )
        try requireNoUncertainHistoryMutation()
        guard let snapshot = try journal.load() else { return .alreadyAbsent }

        if snapshot.record.deliveryState == .discarded {
            guard expected.matches(snapshot.record)
                    || isImmediateRetry(
                        snapshot.record,
                        after: expected,
                        allowsDiscardedProvenanceClear: true
                    ) else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            try requireBridgeRevoked(snapshot.record)
            let confirmed = try confirmIdentical(snapshot)
            try journal.remove(expected: confirmed)
            clearTransientState(for: snapshot.record.deliveryID)
            return .removed
        }

        guard expected.matches(snapshot.record) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireBridgeRevoked(snapshot.record)

        let currentTemporalState = temporalState(for: snapshot.record)
        switch currentTemporalState {
        case .expired:
            let confirmed = try confirmIdentical(snapshot)
            try journal.remove(expected: confirmed)
            clearTransientState(for: snapshot.record.deliveryID)
            return .removed
        case .active, .rollbackAmbiguous:
            break
        }

        if snapshot.record.historyWrite?.state.isPendingDecision == true {
            throw IOSAcceptedOutputDeliveryError.historyTransferRequired
        }
        if snapshot.record.historyWrite != nil {
            try requireOutboxAbsenceAuthorization(
                outboxAbsenceAuthorization,
                for: snapshot,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        }

        let mutationDate: Date
        switch currentTemporalState {
        case .active:
            mutationDate = try mutationNow(for: snapshot.record)
        case .rollbackAmbiguous:
            mutationDate = snapshot.record.updatedAt
        case .expired:
            preconditionFailure("Expired clear returned above")
        }

        let tombstone = try record(
            replacing: snapshot.record,
            revision: try nextRevision(after: snapshot.record.revision),
            updatedAt: mutationDate,
            acceptedText: .some(nil),
            deliveryState: .discarded,
            automaticInsertionPreferenceEnabled: false,
            failedRetryID: .some(nil),
            historyWrite: .some(nil)
        )
        let committed = try commit(tombstone, replacing: snapshot)
        try journal.remove(expected: committed)
        clearTransientState(for: snapshot.record.deliveryID)
        return .removed
    }

    func clearPendingHistory(
        authorization: IOSAcceptedOutputDeliveryAuthorization,
        ownershipProof: IOSAcceptedOutputHistoryOwnershipProof
    ) throws -> IOSAcceptedOutputDeliveryRemovalResult {
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: nil
        )
        guard authorization.storeIdentity == storeIdentity,
              authorization.capabilityOwnerIdentity == capabilityOwnerIdentity,
              ownershipProof.capabilityOwnerIdentity
                == capabilityOwnerIdentity else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        let operation = PendingHistoryClearOperation(
            authorization: authorization,
            ownershipProof: ownershipProof
        )
        if let uncertainPendingHistoryClear {
            return try reconcilePendingHistoryClear(
                uncertainPendingHistoryClear,
                operation: operation
            )
        }
        try requireNoUncertainHistoryMutation()
        guard let snapshot = try journal.load() else { return .alreadyAbsent }
        guard ownershipProof.provesOwnership(for: authorization) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }

        if snapshot.record.deliveryState == .discarded {
            guard isImmediateRetry(
                snapshot.record,
                after: IOSAcceptedOutputDeliveryExpectation(
                    record: authorization.record
                ),
                allowsDiscardedProvenanceClear: true
            ) else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            try requireBridgeRevoked(snapshot.record)
            let intent = UncertainPendingHistoryClear(
                operation: operation,
                tombstone: snapshot.record,
                stage: .removalCommit
            )
            let confirmed = try confirmPendingHistoryClearTombstone(
                intent,
                replacing: snapshot
            )
            return try removePendingHistoryClear(
                intent,
                confirmed: confirmed
            )
        }

        guard snapshot == authorization.snapshot,
              snapshot.record.historyWrite?.state.isPendingDecision == true else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireBridgeRevoked(snapshot.record)

        let mutationDate: Date
        switch temporalState(for: snapshot.record) {
        case .active:
            mutationDate = try mutationNow(for: snapshot.record)
        case .rollbackAmbiguous:
            mutationDate = snapshot.record.updatedAt
        case .expired:
            throw IOSAcceptedOutputDeliveryError.expired
        }

        let tombstone = try record(
            replacing: snapshot.record,
            revision: try nextRevision(after: snapshot.record.revision),
            updatedAt: mutationDate,
            acceptedText: .some(nil),
            deliveryState: .discarded,
            automaticInsertionPreferenceEnabled: false,
            failedRetryID: .some(nil),
            historyWrite: .some(nil)
        )
        let intent = UncertainPendingHistoryClear(
            operation: operation,
            tombstone: tombstone,
            stage: .tombstoneCommit
        )
        let committed = try confirmPendingHistoryClearTombstone(
            intent,
            replacing: snapshot
        )
        return try removePendingHistoryClear(intent, confirmed: committed)
    }

    /// Removes an expired generation-zero record directly, without creating a
    /// logically impossible post-expiry tombstone.
    public func removeExpired(
        expected: IOSAcceptedOutputDeliveryExpectation
    ) throws -> IOSAcceptedOutputDeliveryRemovalResult {
        let observation: IOSAcceptedOutputDeliveryExpiredObservation
        switch try observeExpiredHistoryAbandonment(expected: expected) {
        case .alreadyAbsent:
            return .alreadyAbsent
        case .observed(let observed):
            observation = observed
        }
        switch try confirmExpiredHistoryAbandonment(
            observation: observation
        ) {
        case .alreadyAbsent:
            return .alreadyAbsent
        case .authorized(let authorization):
            return try continueExpiredHistoryAbandonment(
                authorization: authorization
            )
        }
    }

    func observeExpiredHistoryAbandonment(
        expected: IOSAcceptedOutputDeliveryExpectation
    ) throws -> IOSAcceptedOutputDeliveryExpiredObservationResult {
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: nil
        )
        try requireNoUncertainHistoryMutation()
        guard let snapshot = try journal.load() else { return .alreadyAbsent }
        guard expected.matches(snapshot.record) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        switch temporalState(for: snapshot.record) {
        case .expired:
            break
        case .active:
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        case .rollbackAmbiguous:
            throw IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        }
        try requireBridgeRevoked(snapshot.record)
        return .observed(
            IOSAcceptedOutputDeliveryExpiredObservation(
                snapshot: snapshot,
                storeIdentity: storeIdentity
            )
        )
    }

    func confirmExpiredHistoryAbandonment(
        observation: IOSAcceptedOutputDeliveryExpiredObservation
    ) throws -> IOSAcceptedOutputDeliveryExpiredRemovalPreparation {
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: nil
        )
        guard observation.storeIdentity == storeIdentity else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireNoUncertainHistoryMutation()
        guard let current = try journal.load() else { return .alreadyAbsent }
        guard current.record == observation.record else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        let confirmed = try confirmIdentical(current)
        return .authorized(
            IOSAcceptedOutputDeliveryExpiredRemovalAuthorization(
                snapshot: confirmed,
                observationSnapshot: observation.snapshot,
                storeIdentity: storeIdentity
            )
        )
    }

    func isExpiredHistoryAbandonmentComplete(
        observation: IOSAcceptedOutputDeliveryExpiredObservation
    ) throws -> Bool {
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: nil
        )
        guard observation.storeIdentity == storeIdentity else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireNoUncertainHistoryMutation()
        guard let current = try journal.load() else { return true }
        guard current.record == observation.record else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return false
    }

    func continueExpiredHistoryAbandonment(
        authorization: IOSAcceptedOutputDeliveryExpiredRemovalAuthorization
    ) throws -> IOSAcceptedOutputDeliveryRemovalResult {
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: nil
        )
        guard authorization.storeIdentity == storeIdentity else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireNoUncertainHistoryMutation()
        guard let current = try journal.load() else {
            clearTransientState(for: authorization.record.deliveryID)
            return .alreadyAbsent
        }
        guard current.record == authorization.record else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        let confirmed = current == authorization.snapshot
            ? current
            : try confirmIdentical(current)
        try journal.remove(expected: confirmed)
        clearTransientState(for: authorization.record.deliveryID)
        return .removed
    }

    @discardableResult
    public func performStagingMaintenance()
        throws -> IOSAcceptedOutputDeliveryMaintenanceReport {
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: nil
        )
        try requireNoUncertainAcceptance()
        return IOSAcceptedOutputDeliveryMaintenanceReport(
            try journal.performStagingMaintenance(now: now())
        )
    }

    /// Opaque bytes stay preserved until the production bridge can prove that
    /// no unexpired app-group projection remains.
    public func discardUnreadableLocalResult()
        throws -> IOSAcceptedOutputDeliveryRemovalResult {
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: nil
        )
        try requireNoUncertainHistoryMutation()
        guard try journal.loadOpaque() != nil else { return .alreadyAbsent }
        throw IOSAcceptedOutputDeliveryError.bridgeRevocationRequired
    }

    func acceptForegroundVoiceOutput(
        _ preparation: IOSAcceptedOutputDeliveryPreparation,
        pendingRecording: IOSPendingRecording,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              preparation.historyWrite == nil,
              preparation.historyCapture == nil,
              !preparation.automaticInsertionPreferenceEnabled,
              preparation.attemptID == pendingRecording.attemptID,
              preparation.transcriptID
                == pendingRecording.transcriptionID,
              preparation.outputIntent == pendingRecording.outputIntent,
              pendingRecording.phase == .outputDelivery else {
            throw IOSAcceptedOutputDeliveryError.invalidPreparation
        }
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        if let uncertainAcceptanceIntent {
            guard uncertainAcceptanceIntent.preparation == preparation else {
                throw IOSAcceptedOutputDeliveryError.commitUncertain
            }
        } else {
            try requireNoUncertainHistoryMutation()
            if let current = try journal.load(),
               !current.record.hasSameAcceptance(as: preparation) {
                guard current.record.isForegroundVoiceAppOnlyRecord else {
                    throw IOSAcceptedOutputDeliveryError.invalidTransition
                }
            }
        }

        let accepted = try acceptForHistoryCoordinator(
            preparation,
            operationLeaseAuthorization: operationLeaseAuthorization
        ).record
        guard accepted.isExactForegroundVoiceDestination(
            for: pendingRecording
        ) else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        return accepted
    }

    func confirmForegroundVoiceDestination(
        expected: IOSAcceptedOutputDeliveryExpectation,
        pendingRecording: IOSPendingRecording,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSForegroundVoiceAcceptedDestinationAuthorization {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              pendingRecording.phase == .outputDelivery else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireNoUncertainHistoryMutation()
        let current = try requireSnapshot(expected: expected)
        guard current.record.isExactForegroundVoiceDestination(
            for: pendingRecording
        ) else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        let confirmed = try confirmIdentical(current)
        guard confirmed.record.isExactForegroundVoiceDestination(
            for: pendingRecording
        ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return IOSForegroundVoiceAcceptedDestinationAuthorization(
            record: confirmed.record,
            snapshot: confirmed,
            storeIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    /// Mints a captured-foreground retirement proof from the coordinator's
    /// durable acceptance result without rewriting the delivery journal. A
    /// History recovery operation may still retain authority tied to the
    /// current physical snapshot, so an identical confirmation write here
    /// would revoke the capability needed to finish that local recovery.
    func authorizeForegroundVoiceCapturedDestination(
        acceptance: IOSAcceptedHistoryAcceptanceResult,
        preparation: IOSAcceptedOutputDeliveryPreparation,
        pendingRecording: IOSPendingRecording,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSForegroundVoiceCapturedDestinationAuthorization {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              preparation.historyCapture != nil,
              !preparation.automaticInsertionPreferenceEnabled,
              preparation.attemptID == pendingRecording.attemptID,
              preparation.transcriptID
                == pendingRecording.transcriptionID,
              preparation.outputIntent == pendingRecording.outputIntent,
              pendingRecording.phase == .outputDelivery else {
            throw IOSAcceptedOutputDeliveryError.invalidPreparation
        }
        try requirePreparationOwner(preparation)
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let current = try requireCurrentSnapshot()
        try requireActive(current.record)
        guard acceptance.deliveryRecord
                .isExactForegroundVoiceCapturedDestination(
                    for: pendingRecording,
                    preparation: preparation
                ),
              current.record.isExactForegroundVoiceCapturedDestination(
                  for: pendingRecording,
                  preparation: preparation
              ),
              resolutionIsCoherentForCapturedForegroundRetirement(
                  acceptance.resolution,
                  acceptanceRecord: acceptance.deliveryRecord,
                  currentRecord: current.record,
                  preparation: preparation
              ) else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        return IOSForegroundVoiceCapturedDestinationAuthorization(
            record: current.record,
            snapshot: current,
            preparation: preparation,
            storeIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func loadForegroundVoiceLatestResult(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSAcceptedOutputDeliveryObservation? {
        guard operationGateBinding.proves(operationLeaseAuthorization) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireNoUncertainHistoryMutation()
        guard let current = try journal.load() else {
            try journal.confirmCanonicalAbsence()
            foregroundVoiceCleanupPending = false
            return nil
        }
        guard current.record.isForegroundVoiceAppOnlyRecord else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        if current.record.deliveryState == .discarded {
            return .active(current.record)
        }
        return observation(for: current.record)
    }

    private func resolutionIsCoherentForCapturedForegroundRetirement(
        _ resolution: IOSAcceptedHistoryAcceptanceResolution,
        acceptanceRecord: IOSAcceptedOutputDeliveryRecord,
        currentRecord: IOSAcceptedOutputDeliveryRecord,
        preparation: IOSAcceptedOutputDeliveryPreparation
    ) -> Bool {
        switch resolution {
        case .notRequested:
            acceptanceRecord.historyWrite == nil
                && currentRecord.historyWrite == nil
                && preparation.historyWrite == nil
        case .committed:
            acceptanceRecord.historyWrite?.state == .committed
                && currentRecord.historyWrite?.state == .committed
        case .cancelled:
            acceptanceRecord.historyWrite?.state == .cancelled
                && currentRecord.historyWrite?.state == .cancelled
        case .pendingLocalRecovery:
            true
        }
    }

    func loadForegroundVoiceLatestResultWhileSaving(
        preparation: IOSAcceptedOutputDeliveryPreparation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSAcceptedOutputDeliveryObservation? {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              preparation.historyWrite == nil,
              preparation.historyCapture == nil,
              !preparation.automaticInsertionPreferenceEnabled else {
            throw IOSAcceptedOutputDeliveryError.invalidPreparation
        }
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireNoUncertainHistoryMutationExceptAcceptance()
        if let uncertainAcceptanceIntent,
           uncertainAcceptanceIntent.preparation != preparation {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        guard let current = try journal.load() else {
            try journal.confirmCanonicalAbsence()
            foregroundVoiceCleanupPending = false
            return nil
        }
        guard current.record.isForegroundVoiceAppOnlyRecord else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        if current.record.deliveryState == .discarded {
            return .active(current.record)
        }
        return observation(for: current.record)
    }

    func resumeForegroundVoiceDestinationIfPresent(
        preparation: IOSAcceptedOutputDeliveryPreparation,
        pendingRecording: IOSPendingRecording,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSForegroundVoiceAcceptedDestinationAuthorization? {
        try confirmForegroundVoiceDestinationIfPresent(
            preparation: preparation,
            pendingRecording: pendingRecording,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func confirmForegroundVoiceDestinationIfPresent(
        pendingRecording: IOSPendingRecording,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSForegroundVoiceAcceptedDestinationAuthorization? {
        try confirmForegroundVoiceDestinationIfPresent(
            preparation: nil,
            pendingRecording: pendingRecording,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    private func confirmForegroundVoiceDestinationIfPresent(
        preparation: IOSAcceptedOutputDeliveryPreparation?,
        pendingRecording: IOSPendingRecording,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSForegroundVoiceAcceptedDestinationAuthorization? {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              pendingRecording.phase == .outputDelivery else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        if let preparation {
            guard preparation.historyWrite == nil,
                  preparation.historyCapture == nil,
                  !preparation.automaticInsertionPreferenceEnabled,
                  preparation.attemptID == pendingRecording.attemptID,
                  preparation.transcriptID
                    == pendingRecording.transcriptionID,
                  preparation.outputIntent == pendingRecording.outputIntent else {
                throw IOSAcceptedOutputDeliveryError.invalidPreparation
            }
        }
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireNoUncertainHistoryMutationExceptAcceptance()
        if let uncertainAcceptanceIntent,
           let preparation,
           uncertainAcceptanceIntent.preparation != preparation {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        guard let current = try journal.load() else {
            try journal.confirmCanonicalAbsence()
            foregroundVoiceCleanupPending = false
            return nil
        }
        if let preparation {
            if current.record.hasSameAcceptance(as: preparation) {
                guard current.record.isExactForegroundVoiceDestination(
                    for: pendingRecording
                ) else {
                    throw IOSAcceptedOutputDeliveryError.invalidTransition
                }
            } else {
                guard !current.record.collides(with: preparation) else {
                    throw IOSAcceptedOutputDeliveryError.identityCollision
                }
                return nil
            }
        } else {
            guard current.record.isExactForegroundVoiceDestination(
                for: pendingRecording
            ) else {
                return nil
            }
        }

        let confirmed = try confirmIdentical(current)
        if let intent = uncertainAcceptanceIntent,
           intent.intended == confirmed.record {
            clearAcceptanceIntent(keeping: confirmed)
        }
        return IOSForegroundVoiceAcceptedDestinationAuthorization(
            record: confirmed.record,
            snapshot: confirmed,
            storeIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func clearForegroundVoiceLatestResult(
        expected: IOSAcceptedOutputDeliveryExpectation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSForegroundVoiceClearResult {
        guard operationGateBinding.proves(operationLeaseAuthorization) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireNoUncertainHistoryMutation()
        if let current = try journal.load() {
            guard current.record.isForegroundVoiceAppOnlyRecord else {
                throw IOSAcceptedOutputDeliveryError.invalidTransition
            }
        }

        do {
            return try mapForegroundVoiceClearResult(
                clear(expected: expected)
            )
        } catch IOSAcceptedOutputDeliveryError.commitUncertain {
            do {
                return try mapForegroundVoiceClearResult(
                    clear(expected: expected)
                )
            } catch IOSAcceptedOutputDeliveryError.removalCommitUncertain {
                foregroundVoiceCleanupPending = true
                return .clearedCleanupPending
            } catch {
                if try hasConfirmedForegroundVoiceTombstone(
                    after: expected
                ) {
                    foregroundVoiceCleanupPending = true
                    return .clearedCleanupPending
                }
                throw error
            }
        } catch IOSAcceptedOutputDeliveryError.removalCommitUncertain {
            foregroundVoiceCleanupPending = true
            return .clearedCleanupPending
        } catch {
            if try hasConfirmedForegroundVoiceTombstone(after: expected) {
                foregroundVoiceCleanupPending = true
                return .clearedCleanupPending
            }
            throw error
        }
    }

    func retryForegroundVoiceLatestResultCleanup(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSForegroundVoiceClearResult {
        guard operationGateBinding.proves(operationLeaseAuthorization) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireNoUncertainHistoryMutation()

        guard let current = try journal.load() else {
            do {
                try journal.confirmCanonicalAbsence()
                foregroundVoiceCleanupPending = false
                return .alreadyAbsent
            } catch let error as IOSAcceptedOutputDeliveryError
                where isForegroundVoiceCleanupRetryable(error) {
                foregroundVoiceCleanupPending = true
                return .clearedCleanupPending
            }
        }
        guard current.record.isForegroundVoiceAppOnlyRecord,
              current.record.deliveryState == .discarded else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        let confirmed = try confirmIdentical(current)
        do {
            try journal.remove(expected: confirmed)
            foregroundVoiceCleanupPending = false
            return .cleared
        } catch let error as IOSAcceptedOutputDeliveryError
            where isForegroundVoiceCleanupRetryable(error) {
            foregroundVoiceCleanupPending = true
            return .clearedCleanupPending
        }
    }

    func hasForegroundVoiceCleanupPending() -> Bool {
        foregroundVoiceCleanupPending
    }

    func proveForegroundVoiceDestinationAbsent(
        preparation: IOSAcceptedOutputDeliveryPreparation,
        pendingRecording: IOSPendingRecording,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSForegroundVoiceNoDestinationAuthorization {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              preparation.historyWrite == nil,
              preparation.historyCapture == nil,
              !preparation.automaticInsertionPreferenceEnabled,
              pendingRecording.phase == .outputDelivery,
              preparation.attemptID == pendingRecording.attemptID,
              preparation.transcriptID
                == pendingRecording.transcriptionID,
              preparation.outputIntent == pendingRecording.outputIntent else {
            throw IOSAcceptedOutputDeliveryError.invalidPreparation
        }
        try requireFailedRetryRelationDisposition(
            nil,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireNoUncertainHistoryMutationExceptAcceptance()

        if let intent = uncertainAcceptanceIntent {
            guard intent.preparation == preparation else {
                throw IOSAcceptedOutputDeliveryError.commitUncertain
            }
            let current = try journal.load()
            if current?.record == intent.intended {
                throw IOSAcceptedOutputDeliveryError.invalidTransition
            }
            let sourceStillCurrent: Bool = switch (intent.source, current) {
            case (.missing, .none):
                true
            case (.existing(let source), .some(let current)):
                source == current
            default:
                false
            }
            guard sourceStillCurrent else {
                throw IOSAcceptedOutputDeliveryError.commitUncertain
            }
            clearAcceptanceIntent(keeping: current)
        }

        try requireNoUncertainHistoryMutation()
        if let current = try journal.load() {
            if current.record.hasSameAcceptance(as: preparation) {
                throw IOSAcceptedOutputDeliveryError.invalidTransition
            }
            guard !current.record.collides(with: preparation) else {
                throw IOSAcceptedOutputDeliveryError.identityCollision
            }
        } else {
            try journal.confirmCanonicalAbsence()
        }

        return IOSForegroundVoiceNoDestinationAuthorization(
            preparation: preparation,
            pendingRecording: pendingRecording,
            storeIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    private func mapForegroundVoiceClearResult(
        _ result: IOSAcceptedOutputDeliveryRemovalResult
    ) throws -> IOSForegroundVoiceClearResult {
        switch result {
        case .removed:
            foregroundVoiceCleanupPending = false
            return .cleared
        case .alreadyAbsent:
            try journal.confirmCanonicalAbsence()
            foregroundVoiceCleanupPending = false
            return .alreadyAbsent
        }
    }

    private func isForegroundVoiceCleanupRetryable(
        _ error: IOSAcceptedOutputDeliveryError
    ) -> Bool {
        switch error {
        case .readFailed,
             .writeFailed,
             .dataProtectionUnavailable,
             .commitUncertain,
             .removeFailed,
             .removalCommitUncertain:
            true
        case .invalidPreparation,
             .invalidRecord,
             .sourceTooLarge,
             .malformedData,
             .unsupportedSchemaVersion,
             .slotOccupied,
             .compareAndSwapFailed,
             .identityCollision,
             .invalidTransition,
             .revisionOverflow,
             .expired,
             .clockRollbackAmbiguous,
             .historyTransferRequired,
             .bridgeRevocationRequired:
            false
        }
    }

    private func hasConfirmedForegroundVoiceTombstone(
        after expected: IOSAcceptedOutputDeliveryExpectation
    ) throws -> Bool {
        guard let current = try journal.load(),
              current.record.isForegroundVoiceAppOnlyRecord,
              current.record.deliveryState == .discarded,
              isImmediateRetry(
                  current.record,
                  after: expected,
                  allowsDiscardedProvenanceClear: true
              ) else {
            return false
        }
        _ = try confirmIdentical(current)
        return true
    }
}

private extension IOSAcceptedOutputDeliveryStore {
    func requireFailedRetryRelationDisposition(
        _ permit: IOSFailedHistoryRetryDeliveryPermit?,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization?
    ) throws {
        guard let interlock = failedRelationInterlockBinding.current() else {
            guard permit == nil else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            return
        }
        guard !interlock.requiresRetryRecoveryScan else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        guard interlock.hasRetryDeliveryProtection else {
            guard permit == nil else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            return
        }
        guard let permit,
              let operationLeaseAuthorization,
              permit.operationLeaseAuthorization.provesSameActiveLease(
                  as: operationLeaseAuthorization
              ),
              permit.relationReceipt.deliveryStoreIdentity
                == storeIdentity,
              permit.relationReceipt.ownerIdentity
                == capabilityOwnerIdentity,
              permit.provesActiveRelation() else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
    }

    func requireFailedRetryPreparation(
        _ preparation: IOSAcceptedOutputDeliveryPreparation,
        permit: IOSFailedHistoryRetryDeliveryPermit?
    ) throws {
        guard let permit else { return }
        guard preparation
                == permit.relationReceipt.preparation
        else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
    }

    func requireFailedRetryAcceptedRecord(
        _ record: IOSAcceptedOutputDeliveryRecord,
        permit: IOSFailedHistoryRetryDeliveryPermit?
    ) throws {
        guard let permit else { return }
        guard record.hasExactFailedRetryAcceptance(
            as: permit.relationReceipt.preparation,
            retryID: permit.relationReceipt.retryOperation.retryID
        ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
    }

    func requireFailedRetryFrozenPredecessor(
        _ record: IOSAcceptedOutputDeliveryRecord,
        permit: IOSFailedHistoryRetryDeliveryPermit?
    ) throws {
        guard let permit else { return }
        guard case .live(let receipt) = permit.relationReceipt else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        guard case .existing(let predecessor) = receipt.frozenSlotProof
                .frozenSlot,
              isFailedRetryFrozenPredecessorLineage(
                  record,
                  predecessor: predecessor.record
              ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
    }

    func isFailedRetryFrozenPredecessorLineage(
        _ record: IOSAcceptedOutputDeliveryRecord,
        predecessor: IOSAcceptedOutputDeliveryRecord
    ) -> Bool {
        if record == predecessor { return true }
        let nextRevision = predecessor.revision.addingReportingOverflow(1)
        guard !nextRevision.overflow,
              record.revision == nextRevision.partialValue,
              record.deliveryID == predecessor.deliveryID,
              record.sessionID == predecessor.sessionID,
              record.attemptID == predecessor.attemptID,
              record.transcriptID == predecessor.transcriptID,
              record.failedRetryID == predecessor.failedRetryID,
              IOSAcceptedOutputDeliveryValidation.optionalBytesEqual(
                  record.acceptedText,
                  predecessor.acceptedText
              ),
              record.outputIntent == predecessor.outputIntent,
              record.createdAt == predecessor.createdAt,
              record.updatedAt >= predecessor.updatedAt,
              record.expiresAt == predecessor.expiresAt,
              record.deliveryState == predecessor.deliveryState,
              record.automaticInsertionPreferenceEnabled
                == predecessor.automaticInsertionPreferenceEnabled,
              record.keepLatestResult == predecessor.keepLatestResult,
              record.publicationGeneration
                == predecessor.publicationGeneration,
              let previousHistory = predecessor.historyWrite,
              previousHistory.state.isPendingDecision,
              let currentHistory = record.historyWrite,
              currentHistory.state == .cancelled,
              currentHistory.hasSameMetadata(as: previousHistory) else {
            return false
        }
        return true
    }

    func requireFailedRetryRelatedRecord(
        _ record: IOSAcceptedOutputDeliveryRecord,
        permit: IOSFailedHistoryRetryDeliveryPermit?
    ) throws {
        guard let permit else { return }
        if record.hasExactFailedRetryAcceptance(
            as: permit.relationReceipt.preparation,
            retryID: permit.relationReceipt.retryOperation.retryID
        ) {
            return
        }
        try requireFailedRetryFrozenPredecessor(record, permit: permit)
    }

    func requirePreparationOwner(
        _ preparation: IOSAcceptedOutputDeliveryPreparation
    ) throws {
        guard let capture = preparation.historyCapture else { return }
        guard capture.ownerIdentity == capabilityOwnerIdentity,
              capture.policyReceipt.capabilityOwnerIdentity
                == capabilityOwnerIdentity else {
            throw IOSAcceptedOutputDeliveryError.invalidPreparation
        }
    }

    private func performAccept(
        _ preparation: IOSAcceptedOutputDeliveryPreparation,
        pendingHistoryReplacement: PendingHistoryReplacementOperation? = nil,
        outboxAbsenceAuthorization:
            IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization? = nil,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization? = nil,
        failedRetryPermit:
            IOSFailedHistoryRetryDeliveryPermit? = nil
    ) throws -> IOSAcceptedOutputDeliveryAcceptance {
        try requireFailedRetryRelationDisposition(
            failedRetryPermit,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireFailedRetryPreparation(
            preparation,
            permit: failedRetryPermit
        )
        let timestamp = try IOSAcceptedOutputDeliveryTimestampCodec
            .canonicalDate(from: now())
        let acceptanceProvenance: IOSAcceptedOutputDeliveryAcceptanceProvenance =
            failedRetryPermit.map {
                .failedRetry($0.relationKey)
            } ?? .freshCurrentProcess
        let newRecord = try makeInitialRecord(
            preparation,
            createdAt: timestamp,
            failedRetryID: failedRetryPermit?.relationKey.retryID,
            marksReplayableReplacement:
                pendingHistoryReplacement != nil
                    && failedRetryPermit == nil
        )

        guard let current = try journal.load() else {
            if let failedRetryPermit,
               case .live(let receipt) = failedRetryPermit.relationReceipt,
               case .existing = receipt.frozenSlotProof.frozenSlot {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            if let failedRetryPermit,
               case .relaunched = failedRetryPermit.relationReceipt {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            guard pendingHistoryReplacement == nil else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            do {
                let created = try publishAcceptance(
                    newRecord,
                    source: .missing,
                    preparation: preparation,
                    provenance: acceptanceProvenance
                )
                clearTransientState(for: nil)
                return IOSAcceptedOutputDeliveryAcceptance(
                    record: created.record,
                    provenance: acceptanceProvenance
                )
            } catch IOSAcceptedOutputDeliveryError.slotOccupied {
                return try reconcileAcceptanceConflict(
                    preparation,
                    otherwise: .slotOccupied,
                    provenance: acceptanceProvenance,
                    failedRetryPermit: failedRetryPermit
                )
            }
        }

        try requireFailedRetryRelatedRecord(
            current.record,
            permit: failedRetryPermit
        )

        if let pendingHistoryReplacement {
            let authorization = pendingHistoryReplacement.authorization
            guard pendingHistoryReplacement.ownershipProof.provesOwnership(
                for: authorization
            ) else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            guard current == authorization.snapshot else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
        }

        let currentTemporalState = temporalState(for: current.record)
        switch currentTemporalState {
        case .rollbackAmbiguous:
            throw IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        case .active:
            break
        case .expired:
            if pendingHistoryReplacement != nil {
                throw IOSAcceptedOutputDeliveryError.expired
            }
        }

        if current.record.hasSameAcceptance(
            as: preparation,
            failedRetryID: failedRetryPermit?.relationKey.retryID
        ) {
            return try reconcileSameAcceptance(
                preparation,
                snapshot: current,
                temporalState: currentTemporalState,
                recordsOrdinaryAcceptanceUncertainty:
                    pendingHistoryReplacement == nil,
                provenance: failedRetryPermit.map {
                    .failedRetry($0.relationKey)
                } ?? .preexisting
            )
        }
        if current.record.collides(with: preparation) {
            throw IOSAcceptedOutputDeliveryError.identityCollision
        }

        try requireBridgeRevoked(current.record)
        if currentTemporalState == .active,
           current.record.historyWrite?.state.isPendingDecision == true {
            guard pendingHistoryReplacement != nil else {
                throw IOSAcceptedOutputDeliveryError.historyTransferRequired
            }
        }

        if currentTemporalState == .active,
           current.record.historyWrite != nil,
           current.record.historyWrite?.state.isPendingDecision == false {
            guard let outboxAbsenceAuthorization else {
                throw IOSAcceptedOutputDeliveryError.historyTransferRequired
            }
            try requireOutboxAbsenceAuthorization(
                outboxAbsenceAuthorization,
                for: current,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        }

        if let pendingHistoryReplacement {
            let intent = UncertainPendingHistoryReplacement(
                operation: pendingHistoryReplacement,
                intended: newRecord
            )
            do {
                let replaced = try publishPendingHistoryReplacement(
                    intent,
                    replacing: current
                )
                clearTransientState(for: current.record.deliveryID)
                return IOSAcceptedOutputDeliveryAcceptance(
                    record: replaced.record,
                    provenance: acceptanceProvenance
                )
            } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
                return IOSAcceptedOutputDeliveryAcceptance(
                    record: try reconcilePendingHistoryReplacementConflict(
                        intent
                    ),
                    provenance: acceptanceProvenance
                )
            }
        }

        do {
            let replaced = try publishAcceptance(
                newRecord,
                source: .existing(current),
                preparation: preparation,
                provenance: acceptanceProvenance
            )
            clearTransientState(for: current.record.deliveryID)
            return IOSAcceptedOutputDeliveryAcceptance(
                record: replaced.record,
                provenance: acceptanceProvenance
            )
        } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
            return try reconcileAcceptanceConflict(
                preparation,
                otherwise: .compareAndSwapFailed,
                provenance: acceptanceProvenance,
                failedRetryPermit: failedRetryPermit
            )
        }
    }

    private func reconcileAcceptance(
        _ intent: UncertainAcceptanceIntent,
        outboxAbsenceAuthorization:
            IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization?,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization?,
        failedRetryPermit:
            IOSFailedHistoryRetryDeliveryPermit?
    ) throws -> IOSAcceptedOutputDeliveryAcceptance {
        try requireFailedRetryRelationDisposition(
            failedRetryPermit,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireFailedRetryPreparation(
            intent.preparation,
            permit: failedRetryPermit
        )
        let current = try journal.load()
        let sourceStillCurrent: Bool = switch (intent.source, current) {
        case (.missing, .none): true
        case (.existing(let source), .some(let current)): source == current
        default: false
        }

        let publicationSource: AcceptanceSource
        if sourceStillCurrent {
            if !intent.intendedWasVisibleInSource {
                try requireActiveAcceptanceIntent(
                    intent,
                    current: current
                )
                if case .existing(let source) = intent.source,
                   temporalState(for: source.record) == .active,
                   source.record.historyWrite != nil,
                   source.record.historyWrite?.state.isPendingDecision == false {
                    try requireOutboxAbsenceAuthorization(
                        outboxAbsenceAuthorization,
                        for: source,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                }
            }
            publicationSource = intent.source
        } else if let current,
                  current.record == intent.intended {
            publicationSource = .existing(current)
        } else {
            clearAcceptanceIntent(keeping: current)
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }

        do {
            let confirmed = try publishAcceptance(
                intent.intended,
                source: publicationSource,
                preparation: intent.preparation,
                provenance: intent.provenance
            )
            pruneMonotonicDeadlines(
                keeping: confirmed.record.deliveryID
            )
            return IOSAcceptedOutputDeliveryAcceptance(
                record: confirmed.record,
                provenance: intent.provenance
            )
        } catch IOSAcceptedOutputDeliveryError.slotOccupied {
            return try reconcileAcceptancePublicationConflict(intent)
        } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
            return try reconcileAcceptancePublicationConflict(intent)
        }
    }

    private func reconcileAcceptancePublicationConflict(
        _ intent: UncertainAcceptanceIntent
    ) throws -> IOSAcceptedOutputDeliveryAcceptance {
        let current = try journal.load()
        guard let current,
              current.record == intent.intended else {
            clearAcceptanceIntent(keeping: current)
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        do {
            let confirmed = try publishAcceptance(
                intent.intended,
                source: .existing(current),
                preparation: intent.preparation,
                provenance: intent.provenance
            )
            pruneMonotonicDeadlines(
                keeping: confirmed.record.deliveryID
            )
            return IOSAcceptedOutputDeliveryAcceptance(
                record: confirmed.record,
                provenance: intent.provenance
            )
        } catch IOSAcceptedOutputDeliveryError.slotOccupied {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
    }

    private func requireActiveAcceptanceIntent(
        _ intent: UncertainAcceptanceIntent,
        current: IOSAcceptedOutputDeliveryJournalSnapshot?
    ) throws {
        switch temporalState(for: intent.intended) {
        case .active:
            return
        case .rollbackAmbiguous:
            throw IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        case .expired:
            clearAcceptanceIntent(keeping: current)
            throw IOSAcceptedOutputDeliveryError.expired
        }
    }

    private func clearAcceptanceIntent(
        keeping current: IOSAcceptedOutputDeliveryJournalSnapshot?
    ) {
        uncertainAcceptanceIntent = nil
        confirmedAuthorizationFileRevision = nil
        if let current {
            pruneMonotonicDeadlines(keeping: current.record.deliveryID)
        } else {
            monotonicDeadlines.removeAll()
        }
    }

    private func publishAcceptance(
        _ intended: IOSAcceptedOutputDeliveryRecord,
        source: AcceptanceSource,
        preparation: IOSAcceptedOutputDeliveryPreparation,
        provenance: IOSAcceptedOutputDeliveryAcceptanceProvenance
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        let intent = UncertainAcceptanceIntent(
            preparation: preparation,
            source: source,
            intended: intended,
            provenance: provenance
        )
        do {
            let committed: IOSAcceptedOutputDeliveryJournalSnapshot =
                switch source {
                case .missing:
                    try journal.create(intended)
                case .existing(let snapshot):
                    try journal.replace(intended, expected: snapshot)
                }
            uncertainAcceptanceIntent = nil
            confirmedAuthorizationFileRevision = nil
            return committed
        } catch IOSAcceptedOutputDeliveryError.commitUncertain {
            uncertainAcceptanceIntent = intent
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
    }

    func reconcileAcceptanceConflict(
        _ preparation: IOSAcceptedOutputDeliveryPreparation,
        otherwise error: IOSAcceptedOutputDeliveryError,
        provenance: IOSAcceptedOutputDeliveryAcceptanceProvenance = .preexisting,
        failedRetryPermit: IOSFailedHistoryRetryDeliveryPermit? = nil
    ) throws -> IOSAcceptedOutputDeliveryAcceptance {
        guard let current = try journal.load() else { throw error }
        let currentTemporalState = temporalState(for: current.record)
        if let failedRetryPermit {
            guard current.record.hasExactFailedRetryAcceptance(
                as: preparation,
                retryID: failedRetryPermit.relationReceipt
                    .retryOperation.retryID
            ) else {
                if !current.record.isWhollyUnrelatedToFailedRetry(
                    row: failedRetryPermit.relationReceipt.row,
                    operation:
                        failedRetryPermit.relationReceipt.retryOperation
                ) {
                    throw IOSAcceptedOutputDeliveryError.identityCollision
                }
                throw error
            }
        }
        if current.record.hasSameAcceptance(
            as: preparation,
            failedRetryID: failedRetryPermit?.relationKey.retryID
        ) {
            return try reconcileSameAcceptance(
                preparation,
                snapshot: current,
                temporalState: currentTemporalState,
                recordsOrdinaryAcceptanceUncertainty: true,
                provenance: provenance
            )
        }
        if current.record.collides(with: preparation) {
            throw IOSAcceptedOutputDeliveryError.identityCollision
        }
        throw error
    }

    private func reconcilePendingHistoryReplacement(
        _ intent: UncertainPendingHistoryReplacement,
        operation: PendingHistoryReplacementOperation
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        guard operation == intent.operation else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        guard let current = try journal.load() else {
            uncertainPendingHistoryReplacement = nil
            clearPendingHistoryTransferReservation(
                intent.operation.reservation
            )
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }

        if current != operation.authorization.snapshot,
           current.record == intent.intended {
            let confirmed = try publishPendingHistoryReplacement(
                intent,
                replacing: current
            )
            clearTransientState(for: operation.authorization.record.deliveryID)
            return confirmed.record
        }

        guard current == operation.authorization.snapshot,
              operation.ownershipProof.provesOwnership(
                  for: operation.authorization
              ),
              current.record.historyWrite?.state.isPendingDecision == true else {
            uncertainPendingHistoryReplacement = nil
            clearPendingHistoryTransferReservation(
                intent.operation.reservation
            )
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        switch temporalState(for: intent.intended) {
        case .active:
            break
        case .rollbackAmbiguous:
            throw IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        case .expired:
            uncertainPendingHistoryReplacement = nil
            clearPendingHistoryTransferReservation(
                intent.operation.reservation
            )
            throw IOSAcceptedOutputDeliveryError.expired
        }
        try requireBridgeRevoked(current.record)
        let replaced = try publishPendingHistoryReplacement(
            intent,
            replacing: current
        )
        clearTransientState(for: current.record.deliveryID)
        return replaced.record
    }

    private func reconcilePendingHistoryReplacementConflict(
        _ intent: UncertainPendingHistoryReplacement
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        let current = try requireCurrentSnapshot()
        guard current.record == intent.intended else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        let confirmed = try publishPendingHistoryReplacement(
            intent,
            replacing: current
        )
        clearTransientState(
            for: intent.operation.authorization.record.deliveryID
        )
        return confirmed.record
    }

    private func publishPendingHistoryReplacement(
        _ intent: UncertainPendingHistoryReplacement,
        replacing snapshot: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        do {
            let committed = try journal.replace(
                intent.intended,
                expected: snapshot
            )
            uncertainPendingHistoryReplacement = nil
            if pendingHistoryTransferReservation
                == intent.operation.reservation {
                intent.operation.reservation.consume()
                pendingHistoryTransferReservation = nil
            }
            confirmedAuthorizationFileRevision = nil
            return committed
        } catch IOSAcceptedOutputDeliveryError.commitUncertain {
            uncertainPendingHistoryReplacement = intent
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
            guard uncertainPendingHistoryReplacement == nil else {
                throw IOSAcceptedOutputDeliveryError.commitUncertain
            }
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
    }

    private func clearPendingHistoryTransferReservation(
        _ reservation: IOSAcceptedOutputPendingHistoryTransferReservation
    ) {
        if pendingHistoryTransferReservation == reservation {
            reservation.release()
            pendingHistoryTransferReservation = nil
        }
    }

    private func reconcileSameAcceptance(
        _ preparation: IOSAcceptedOutputDeliveryPreparation,
        snapshot: IOSAcceptedOutputDeliveryJournalSnapshot,
        temporalState: TemporalState,
        recordsOrdinaryAcceptanceUncertainty: Bool,
        provenance: IOSAcceptedOutputDeliveryAcceptanceProvenance
    ) throws -> IOSAcceptedOutputDeliveryAcceptance {
        let protectedFailedRetryID: UUID? = switch provenance {
        case .failedRetry(let relationKey): relationKey.retryID
        case .freshCurrentProcess, .preexisting: nil
        }
        switch temporalState {
        case .active:
            break
        case .expired:
            guard snapshot.record.failedRetryID
                    == protectedFailedRetryID,
                  protectedFailedRetryID != nil else {
                throw IOSAcceptedOutputDeliveryError.expired
            }
        case .rollbackAmbiguous:
            throw IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        }

        if snapshot.record.keepLatestResult,
           !preparation.keepLatestResult {
            let replacement = try record(
                replacing: snapshot.record,
                revision: try nextRevision(after: snapshot.record.revision),
                updatedAt: try mutationNow(for: snapshot.record),
                keepLatestResult: false
            )
            let committed: IOSAcceptedOutputDeliveryJournalSnapshot
            if recordsOrdinaryAcceptanceUncertainty {
                committed = try publishAcceptance(
                    replacement,
                    source: .existing(snapshot),
                    preparation: preparation,
                    provenance: provenance
                )
            } else {
                committed = try commit(replacement, replacing: snapshot)
            }
            pruneMonotonicDeadlines(keeping: committed.record.deliveryID)
            return IOSAcceptedOutputDeliveryAcceptance(
                record: committed.record,
                provenance: provenance
            )
        }

        let confirmed: IOSAcceptedOutputDeliveryJournalSnapshot
        if recordsOrdinaryAcceptanceUncertainty {
            confirmed = try publishAcceptance(
                snapshot.record,
                source: .existing(snapshot),
                preparation: preparation,
                provenance: provenance
            )
        } else {
            confirmed = try confirmIdentical(snapshot)
        }
        pruneMonotonicDeadlines(keeping: confirmed.record.deliveryID)
        if protectedFailedRetryID == nil {
            try requireActive(confirmed.record)
        } else {
            guard confirmed.record.failedRetryID
                    == protectedFailedRetryID else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
        }
        return IOSAcceptedOutputDeliveryAcceptance(
            record: confirmed.record,
            provenance: provenance
        )
    }

    func observation(
        for record: IOSAcceptedOutputDeliveryRecord
    ) -> IOSAcceptedOutputDeliveryObservation {
        switch temporalState(for: record) {
        case .active:
            .active(record)
        case .expired:
            .expired(IOSAcceptedOutputDeliveryExpectation(record: record))
        case .rollbackAmbiguous:
            .clockRollbackAmbiguous(
                IOSAcceptedOutputDeliveryExpectation(record: record)
            )
        }
    }

    private func temporalState(
        for record: IOSAcceptedOutputDeliveryRecord
    ) -> TemporalState {
        guard let wallNow = try? IOSAcceptedOutputDeliveryTimestampCodec
            .canonicalDate(from: now()) else {
            return .rollbackAmbiguous
        }
        if wallNow < record.createdAt || wallNow < record.updatedAt {
            return .rollbackAmbiguous
        }
        if wallNow >= record.expiresAt {
            return .expired
        }

        let monotonicNow = monotonicNowNanoseconds()
        let deadline: MonotonicDeadline
        if let existing = monotonicDeadlines[record.deliveryID],
           existing.expiresAt == record.expiresAt {
            deadline = existing
        } else {
            guard let wallMilliseconds = try? IOSAcceptedOutputDeliveryTimestampCodec
                .milliseconds(from: wallNow),
                  let expiryMilliseconds = try? IOSAcceptedOutputDeliveryTimestampCodec
                    .milliseconds(from: record.expiresAt) else {
                return .rollbackAmbiguous
            }
            let remainingMilliseconds = max(
                0,
                expiryMilliseconds - wallMilliseconds
            )
            let delta = UInt64(remainingMilliseconds).multipliedReportingOverflow(
                by: 1_000_000
            )
            let sum = monotonicNow.addingReportingOverflow(
                delta.overflow ? UInt64.max : delta.partialValue
            )
            deadline = MonotonicDeadline(
                expiresAt: record.expiresAt,
                uptimeNanoseconds: sum.overflow ? UInt64.max : sum.partialValue
            )
            monotonicDeadlines[record.deliveryID] = deadline
        }
        return monotonicNow >= deadline.uptimeNanoseconds ? .expired : .active
    }

    func requireActive(_ record: IOSAcceptedOutputDeliveryRecord) throws {
        switch temporalState(for: record) {
        case .active:
            return
        case .expired:
            throw IOSAcceptedOutputDeliveryError.expired
        case .rollbackAmbiguous:
            throw IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        }
    }

    func requireActiveHistoryRecovery(
        _ record: IOSAcceptedOutputDeliveryRecord,
        failedRetryPermit: IOSFailedHistoryRetryDeliveryPermit?
    ) throws {
        switch temporalState(for: record) {
        case .active:
            return
        case .expired:
            guard let failedRetryPermit,
                  record.hasExactFailedRetryAcceptance(
                    as: failedRetryPermit.relationReceipt.preparation,
                    retryID: failedRetryPermit.relationReceipt
                        .retryOperation.retryID
                  ) else {
                throw IOSAcceptedOutputDeliveryError.expired
            }
        case .rollbackAmbiguous:
            throw IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        }
    }

    private func reconcilePendingHistoryClear(
        _ intent: UncertainPendingHistoryClear,
        operation: PendingHistoryClearOperation
    ) throws -> IOSAcceptedOutputDeliveryRemovalResult {
        guard operation == intent.operation else {
            switch intent.stage {
            case .tombstoneCommit:
                throw IOSAcceptedOutputDeliveryError.commitUncertain
            case .removalCommit:
                throw IOSAcceptedOutputDeliveryError.removalCommitUncertain
            }
        }

        guard let current = try journal.load() else {
            guard intent.stage == .removalCommit else {
                uncertainPendingHistoryClear = nil
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            uncertainPendingHistoryClear = nil
            clearTransientState(
                for: operation.authorization.record.deliveryID
            )
            return .removed
        }

        if current.record == intent.tombstone {
            let confirmed = try confirmPendingHistoryClearTombstone(
                intent,
                replacing: current
            )
            return try removePendingHistoryClear(
                intent,
                confirmed: confirmed
            )
        }

        guard intent.stage == .tombstoneCommit,
              current == operation.authorization.snapshot,
              operation.ownershipProof.provesOwnership(
                  for: operation.authorization
              ),
              current.record.historyWrite?.state.isPendingDecision == true else {
            uncertainPendingHistoryClear = nil
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireBridgeRevoked(current.record)
        switch temporalState(for: intent.tombstone) {
        case .active:
            break
        case .rollbackAmbiguous:
            guard intent.tombstone.updatedAt == current.record.updatedAt else {
                throw IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
            }
        case .expired:
            uncertainPendingHistoryClear = nil
            throw IOSAcceptedOutputDeliveryError.expired
        }
        let committed = try confirmPendingHistoryClearTombstone(
            intent,
            replacing: current
        )
        return try removePendingHistoryClear(intent, confirmed: committed)
    }

    private func confirmPendingHistoryClearTombstone(
        _ intent: UncertainPendingHistoryClear,
        replacing snapshot: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        do {
            let committed = try journal.replace(
                intent.tombstone,
                expected: snapshot
            )
            uncertainPendingHistoryClear = nil
            confirmedAuthorizationFileRevision = nil
            return committed
        } catch IOSAcceptedOutputDeliveryError.commitUncertain {
            uncertainPendingHistoryClear = intent
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
    }

    private func removePendingHistoryClear(
        _ intent: UncertainPendingHistoryClear,
        confirmed: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws -> IOSAcceptedOutputDeliveryRemovalResult {
        do {
            try journal.remove(expected: confirmed)
            uncertainPendingHistoryClear = nil
            clearTransientState(
                for: intent.operation.authorization.record.deliveryID
            )
            return .removed
        } catch IOSAcceptedOutputDeliveryError.removalCommitUncertain {
            uncertainPendingHistoryClear = UncertainPendingHistoryClear(
                operation: intent.operation,
                tombstone: intent.tombstone,
                stage: .removalCommit
            )
            throw IOSAcceptedOutputDeliveryError.removalCommitUncertain
        }
    }

    private func transitionHistoryWrite(
        _ operation: HistoryTransitionOperation
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        let ownersMatch: Bool = switch operation {
        case .commit(let authorization, let receipt):
            authorization.storeIdentity == storeIdentity
                && authorization.capabilityOwnerIdentity
                    == capabilityOwnerIdentity
                && receipt.capabilityOwnerIdentity == capabilityOwnerIdentity
        case .cancel(let authorization, let receipt):
            authorization.storeIdentity == storeIdentity
                && authorization.capabilityOwnerIdentity
                    == capabilityOwnerIdentity
                && receipt.capabilityOwnerIdentity == capabilityOwnerIdentity
        }
        guard ownersMatch else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireNoUncertainAcceptance()
        guard uncertainPendingHistoryReplacement == nil,
              uncertainPendingHistoryClear == nil,
              pendingHistoryTransferReservation == nil,
              pendingBridgePublicationReservation == nil else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        let current = try journal.load()

        if let uncertainHistoryTransition {
            return try reconcileHistoryTransition(
                uncertainHistoryTransition,
                operation: operation,
                current: current
            )
        }
        guard let current else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }

        guard operation.provesRequiredCapability else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }

        let authorization = operation.authorization
        if current == authorization.snapshot {
            let mutationDate = try historyTransitionMutationDate(
                for: current.record,
                authorization: authorization.record
            )
            guard let historyWrite = current.record.historyWrite,
                  historyWrite.state.isPendingDecision else {
                throw IOSAcceptedOutputDeliveryError.invalidTransition
            }
            let intended = try record(
                replacing: current.record,
                revision: try nextRevision(after: current.record.revision),
                updatedAt: mutationDate,
                historyWrite: try historyWrite.replacingState(
                    operation.targetState
                )
            )
            return try publishHistoryTransition(
                UncertainHistoryTransition(
                    operation: operation,
                    intended: intended
                ),
                replacing: current
            ).record
        }

        guard isImmediateRetry(
            current.record,
            after: IOSAcceptedOutputDeliveryExpectation(
                record: authorization.record
            )
        ),
              current.record.historyWrite?.state == operation.targetState else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return try confirmIdentical(current).record
    }

    private func reconcileHistoryTransition(
        _ intent: UncertainHistoryTransition,
        operation: HistoryTransitionOperation,
        current: IOSAcceptedOutputDeliveryJournalSnapshot?
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        guard operation == intent.operation else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        guard let current else {
            uncertainHistoryTransition = nil
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }

        if current.record == intent.intended {
            return try publishHistoryTransition(
                intent,
                replacing: current
            ).record
        }

        guard current == operation.authorization.snapshot,
              current.record.historyWrite?.state.isPendingDecision == true else {
            uncertainHistoryTransition = nil
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }

        switch temporalState(for: intent.intended) {
        case .active:
            _ = try mutationNow(for: intent.intended)
        case .expired:
            guard intent.intended.failedRetryID != nil else {
                uncertainHistoryTransition = nil
                throw IOSAcceptedOutputDeliveryError.expired
            }
        case .rollbackAmbiguous:
            throw IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        }
        return try publishHistoryTransition(
            intent,
            replacing: current
        ).record
    }

    private func publishHistoryTransition(
        _ intent: UncertainHistoryTransition,
        replacing snapshot: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        do {
            let committed = try journal.replace(
                intent.intended,
                expected: snapshot
            )
            uncertainHistoryTransition = nil
            confirmedAuthorizationFileRevision = nil
            return committed
        } catch IOSAcceptedOutputDeliveryError.commitUncertain {
            uncertainHistoryTransition = intent
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
            guard uncertainHistoryTransition == nil else {
                throw IOSAcceptedOutputDeliveryError.commitUncertain
            }
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
    }

    func requireNoUncertainHistoryMutation() throws {
        try requireNoUncertainHistoryMutationExceptAcceptance()
        try requireNoUncertainAcceptance()
    }

    func requireNoUncertainHistoryMutation(
        allowing reservation:
            IOSAcceptedOutputPendingHistoryTransferReservation
    ) throws {
        try requireNoUncertainHistoryMutationExceptAcceptance(
            allowing: reservation
        )
        try requireNoUncertainAcceptance()
    }

    func requireNoUncertainHistoryMutationExceptAcceptance() throws {
        guard pendingHistoryTransferReservation == nil,
              pendingBridgePublicationReservation == nil else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        try requireNoUncertainHistoryMutationExceptAcceptance(
            allowing: nil
        )
    }

    func requireNoUncertainHistoryMutationExceptAcceptance(
        allowing reservation:
            IOSAcceptedOutputPendingHistoryTransferReservation?
    ) throws {
        guard uncertainHistoryTransition == nil,
              uncertainPendingHistoryReplacement == nil,
              uncertainPendingHistoryClear == nil,
              pendingHistoryTransferReservation == nil
                || pendingHistoryTransferReservation == reservation,
              pendingBridgePublicationReservation == nil else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
    }

    func requireNoUncertainAcceptance() throws {
        guard uncertainAcceptanceIntent == nil else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
    }

    func makeInitialRecord(
        _ preparation: IOSAcceptedOutputDeliveryPreparation,
        createdAt: Date,
        failedRetryID: UUID? = nil,
        marksReplayableReplacement: Bool = false
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        let createdMilliseconds = try IOSAcceptedOutputDeliveryTimestampCodec
            .milliseconds(from: createdAt)
        let expiry = createdMilliseconds.addingReportingOverflow(
            IOSAcceptedOutputDeliveryValidation.lifetimeMilliseconds
        )
        guard !expiry.overflow else {
            throw IOSAcceptedOutputDeliveryError.invalidPreparation
        }
        let expiresAt = Date(
            timeIntervalSince1970: Double(expiry.partialValue) / 1_000
        )
        do {
            let historyWrite = if marksReplayableReplacement,
                                  let marker = preparation.historyWrite {
                try marker.replacingState(.pendingReplacement)
            } else {
                preparation.historyWrite
            }
            return try IOSAcceptedOutputDeliveryRecord(
                revision: 1,
                deliveryID: preparation.deliveryID,
                sessionID: preparation.sessionID,
                attemptID: preparation.attemptID,
                transcriptID: preparation.transcriptID,
                failedRetryID: failedRetryID,
                acceptedText: preparation.acceptedText,
                outputIntent: preparation.outputIntent,
                createdAt: createdAt,
                updatedAt: createdAt,
                expiresAt: expiresAt,
                deliveryState: .pending,
                automaticInsertionPreferenceEnabled:
                    preparation.automaticInsertionPreferenceEnabled,
                keepLatestResult: preparation.keepLatestResult,
                publicationGeneration: 0,
                historyWrite: historyWrite
            )
        } catch {
            throw IOSAcceptedOutputDeliveryError.invalidPreparation
        }
    }

    func record(
        replacing old: IOSAcceptedOutputDeliveryRecord,
        revision: Int64,
        updatedAt: Date,
        acceptedText: String?? = nil,
        deliveryState: IOSAcceptedOutputDeliveryState? = nil,
        automaticInsertionPreferenceEnabled: Bool? = nil,
        keepLatestResult: Bool? = nil,
        failedRetryID: UUID?? = nil,
        historyWrite: IOSAcceptedOutputHistoryWrite?? = nil
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        try IOSAcceptedOutputDeliveryRecord(
            revision: revision,
            deliveryID: old.deliveryID,
            sessionID: old.sessionID,
            attemptID: old.attemptID,
            transcriptID: old.transcriptID,
            failedRetryID: failedRetryID ?? old.failedRetryID,
            acceptedText: acceptedText ?? old.acceptedText,
            outputIntent: old.outputIntent,
            createdAt: old.createdAt,
            updatedAt: updatedAt,
            expiresAt: old.expiresAt,
            deliveryState: deliveryState ?? old.deliveryState,
            automaticInsertionPreferenceEnabled:
                automaticInsertionPreferenceEnabled
                    ?? old.automaticInsertionPreferenceEnabled,
            keepLatestResult: keepLatestResult ?? old.keepLatestResult,
            publicationGeneration: old.publicationGeneration,
            historyWrite: historyWrite ?? old.historyWrite
        )
    }

    func mutationNow(
        for record: IOSAcceptedOutputDeliveryRecord
    ) throws -> Date {
        let timestamp = try IOSAcceptedOutputDeliveryTimestampCodec
            .canonicalDate(from: now())
        guard timestamp >= record.updatedAt,
              timestamp < record.expiresAt else {
            if timestamp < record.updatedAt {
                throw IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
            }
            throw IOSAcceptedOutputDeliveryError.expired
        }
        return timestamp
    }

    func historyTransitionMutationDate(
        for record: IOSAcceptedOutputDeliveryRecord,
        authorization: IOSAcceptedOutputDeliveryRecord
    ) throws -> Date {
        switch temporalState(for: record) {
        case .active:
            return try mutationNow(for: record)
        case .expired:
            guard let failedRetryID = record.failedRetryID,
                  authorization.failedRetryID == failedRetryID else {
                throw IOSAcceptedOutputDeliveryError.expired
            }
            return record.expiresAt
        case .rollbackAmbiguous:
            throw IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        }
    }

    func nextRevision(after revision: Int64) throws -> Int64 {
        let next = revision.addingReportingOverflow(1)
        guard !next.overflow else {
            throw IOSAcceptedOutputDeliveryError.revisionOverflow
        }
        return next.partialValue
    }

    func requireCurrentSnapshot()
        throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        guard let snapshot = try journal.load() else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return snapshot
    }

    func requireSnapshot(
        expected: IOSAcceptedOutputDeliveryExpectation
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        let snapshot = try requireCurrentSnapshot()
        guard expected.matches(snapshot.record) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return snapshot
    }

    func commit(
        _ replacement: IOSAcceptedOutputDeliveryRecord,
        replacing snapshot: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        let committed = try journal.replace(replacement, expected: snapshot)
        confirmedAuthorizationFileRevision = nil
        return committed
    }

    func confirmIdentical(
        _ snapshot: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        let confirmed = try journal.replace(
            snapshot.record,
            expected: snapshot
        )
        guard confirmed.record == snapshot.record else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
        return confirmed
    }

    func requireBridgeRevoked(
        _ record: IOSAcceptedOutputDeliveryRecord
    ) throws {
        guard record.publicationGeneration == 0 else {
            throw IOSAcceptedOutputDeliveryError.bridgeRevocationRequired
        }
    }

    func requireOutboxAbsenceAuthorization(
        _ authorization:
            IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization?,
        for snapshot: IOSAcceptedOutputDeliveryJournalSnapshot,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization?
    ) throws {
        guard let authorization else {
            throw IOSAcceptedOutputDeliveryError.historyTransferRequired
        }
        guard let operationLeaseAuthorization else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        guard operationGateBinding.proves(
            operationLeaseAuthorization
        ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        let delivery = IOSAcceptedOutputDeliveryAuthorization(
            snapshot: snapshot,
            storeIdentity: storeIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
        guard authorization.provesAbsence(
            for: delivery,
            deliveryStoreIdentity: storeIdentity,
            outboxStoreIdentity: outboxStoreIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
    }

    func isImmediateRetry(
        _ record: IOSAcceptedOutputDeliveryRecord,
        after expected: IOSAcceptedOutputDeliveryExpectation,
        allowsDiscardedProvenanceClear: Bool = false
    ) -> Bool {
        let provenanceMatches = expected.failedRetryID
            == record.failedRetryID
            || (allowsDiscardedProvenanceClear
                && expected.failedRetryID != nil
                && record.failedRetryID == nil
                && record.deliveryState == .discarded)
        guard expected.matchesIdentity(record), provenanceMatches else {
            return false
        }
        let next = expected.revision.addingReportingOverflow(1)
        return !next.overflow && record.revision == next.partialValue
    }

    func clearTransientState(for deliveryID: UUID?) {
        if let deliveryID {
            monotonicDeadlines[deliveryID] = nil
        } else {
            monotonicDeadlines.removeAll()
        }
        confirmedAuthorizationFileRevision = nil
    }

    func pruneMonotonicDeadlines(keeping deliveryID: UUID) {
        monotonicDeadlines = monotonicDeadlines.filter {
            $0.key == deliveryID
        }
    }
}
