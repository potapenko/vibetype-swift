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
    fileprivate let storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity

    var record: IOSAcceptedOutputDeliveryRecord { snapshot.record }
}

struct IOSAcceptedOutputDeliveryExpiredObservation: Equatable, Sendable {
    fileprivate let snapshot: IOSAcceptedOutputDeliveryJournalSnapshot
    fileprivate let storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity

    var record: IOSAcceptedOutputDeliveryRecord { snapshot.record }
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
        let outboxAbsenceAuthorization:
            IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization?

        var intendedWasVisibleInSource: Bool {
            guard case .existing(let source) = source else { return false }
            return source.record == intended
        }
    }

    private let journal: any IOSAcceptedOutputDeliveryJournalStoring
    nonisolated let storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity
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

    init(
        applicationSupportDirectoryURL: URL,
        storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity =
            IOSAcceptedOutputDeliveryStoreIdentity(),
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
            IOSAcceptedHistoryCapabilityOwnerIdentity()
    ) {
        journal = FoundationIOSAcceptedOutputDeliveryJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        now = { Date() }
        monotonicNowNanoseconds = { DispatchTime.now().uptimeNanoseconds }
        self.storeIdentity = storeIdentity
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
    }

    init(
        journal: any IOSAcceptedOutputDeliveryJournalStoring,
        now: @escaping @Sendable () -> Date = { Date() },
        monotonicNowNanoseconds: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        },
        storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity =
            IOSAcceptedOutputDeliveryStoreIdentity(),
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
            IOSAcceptedHistoryCapabilityOwnerIdentity()
    ) {
        self.journal = journal
        self.storeIdentity = storeIdentity
        self.now = now
        self.monotonicNowNanoseconds = monotonicNowNanoseconds
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
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
            IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization? = nil
    ) throws -> IOSAcceptedOutputDeliveryAcceptance {
        try requirePreparationOwner(preparation)
        if let uncertainAcceptanceIntent {
            try requireNoUncertainHistoryMutationExceptAcceptance()
            guard preparation == uncertainAcceptanceIntent.preparation else {
                throw IOSAcceptedOutputDeliveryError.commitUncertain
            }
            if let outboxAbsenceAuthorization,
               let retained = uncertainAcceptanceIntent
                .outboxAbsenceAuthorization,
               outboxAbsenceAuthorization != retained {
                throw IOSAcceptedOutputDeliveryError.commitUncertain
            }
            return try reconcileAcceptance(uncertainAcceptanceIntent)
        }
        try requireNoUncertainHistoryMutation()
        return try performAccept(
            preparation,
            outboxAbsenceAuthorization: outboxAbsenceAuthorization
        )
    }

    func replacePendingHistory(
        with preparation: IOSAcceptedOutputDeliveryPreparation,
        reservation: IOSAcceptedOutputPendingHistoryTransferReservation,
        ownershipProof: IOSAcceptedOutputHistoryOwnershipProof
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        try requirePreparationOwner(preparation)
        let authorization = reservation.authorization
        guard authorization.capabilityOwnerIdentity == capabilityOwnerIdentity,
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
                pendingHistoryReplacement: operation
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
        try requireNoUncertainAcceptance()
        guard let snapshot = try journal.load() else { return nil }
        return observation(for: snapshot.record)
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
        expected: IOSAcceptedOutputDeliveryExpectation
    ) throws -> IOSAcceptedOutputDeliveryAuthorization {
        let authorization = try confirmActiveHistoryRecovery(
            expected: expected
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
        policyReceipt: IOSHistoryPolicyReceipt
    ) throws -> IOSAcceptedOutputPendingHistoryTransferReservation {
        guard authorization.capabilityOwnerIdentity == capabilityOwnerIdentity,
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
        _ reservation: IOSAcceptedOutputPendingHistoryTransferReservation
    ) throws {
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
        guard authorization.capabilityOwnerIdentity
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
        guard reservation.storeIdentity == storeIdentity,
              pendingBridgePublicationReservation == reservation else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        pendingBridgePublicationReservation = nil
    }

    /// Reconstructs physical delivery authority without interpreting the
    /// History marker. Every active marker state uses the same strict rewrite.
    func confirmActiveHistoryRecovery(
        expected: IOSAcceptedOutputDeliveryExpectation
    ) throws -> IOSAcceptedOutputDeliveryAuthorization {
        try requireNoUncertainHistoryMutation()
        let snapshot = try requireSnapshot(expected: expected)
        try requireActive(snapshot.record)
        guard snapshot.record.deliveryState != .discarded else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        if confirmedAuthorizationFileRevision == snapshot.fileRevision {
            return IOSAcceptedOutputDeliveryAuthorization(
                snapshot: snapshot,
                capabilityOwnerIdentity: capabilityOwnerIdentity
            )
        }

        let confirmed = try journal.replace(
            snapshot.record,
            expected: snapshot
        )
        try requireActive(confirmed.record)
        guard confirmed.record.deliveryState != .discarded else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        confirmedAuthorizationFileRevision = confirmed.fileRevision
        return IOSAcceptedOutputDeliveryAuthorization(
            snapshot: confirmed,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
    }

    /// Confirms the exact delivery relation for a durable outbox membership.
    /// Only an identical physical rewrite can mint terminal-marker authority.
    func confirmMatchingHistoryDelivery(
        membership: IOSAcceptedHistoryOutboxReceipt
    ) throws -> IOSAcceptedOutputHistoryDeliveryDisposition {
        guard membership.capabilityOwnerIdentity
                == capabilityOwnerIdentity else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        try requireNoUncertainHistoryMutation()
        guard let snapshot = try journal.load() else {
            return .absentOrUnrelated
        }
        let observed = IOSAcceptedOutputDeliveryAuthorization(
            snapshot: snapshot,
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
                    capabilityOwnerIdentity: capabilityOwnerIdentity
                )
            )
        }
    }

    /// Records the exact durable History decision for this delivery.
    func commitHistoryWrite(
        authorization: IOSAcceptedOutputDeliveryAuthorization,
        rowReceipt: IOSAcceptedHistoryRowReceipt
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        return try transitionHistoryWrite(
            .commit(authorization, rowReceipt)
        )
    }

    func cancelHistoryWrite(
        authorization: IOSAcceptedOutputDeliveryAuthorization,
        policyInvalidationReceipt: IOSHistoryPolicyReceipt
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        return try transitionHistoryWrite(
            .cancel(authorization, policyInvalidationReceipt)
        )
    }

    public func disableKeepLatestResult(
        expected: IOSAcceptedOutputDeliveryExpectation
    ) throws -> IOSAcceptedOutputDeliveryRecord {
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
        try clear(
            expected: expected,
            outboxAbsenceAuthorization: nil
        )
    }

    func clear(
        expected: IOSAcceptedOutputDeliveryExpectation,
        outboxAbsenceAuthorization:
            IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization
    ) throws -> IOSAcceptedOutputDeliveryRemovalResult {
        try clear(
            expected: expected,
            outboxAbsenceAuthorization: Optional(outboxAbsenceAuthorization)
        )
    }

    private func clear(
        expected: IOSAcceptedOutputDeliveryExpectation,
        outboxAbsenceAuthorization:
            IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization?
    ) throws -> IOSAcceptedOutputDeliveryRemovalResult {
        try requireNoUncertainHistoryMutation()
        guard let snapshot = try journal.load() else { return .alreadyAbsent }

        if snapshot.record.deliveryState == .discarded {
            guard expected.matches(snapshot.record)
                    || isImmediateRetry(snapshot.record, after: expected) else {
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
                for: snapshot
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
        guard authorization.capabilityOwnerIdentity == capabilityOwnerIdentity,
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
                )
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
                storeIdentity: storeIdentity
            )
        )
    }

    func continueExpiredHistoryAbandonment(
        authorization: IOSAcceptedOutputDeliveryExpiredRemovalAuthorization
    ) throws -> IOSAcceptedOutputDeliveryRemovalResult {
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
        try requireNoUncertainAcceptance()
        return IOSAcceptedOutputDeliveryMaintenanceReport(
            try journal.performStagingMaintenance(now: now())
        )
    }

    /// Opaque bytes stay preserved until the production bridge can prove that
    /// no unexpired app-group projection remains.
    public func discardUnreadableLocalResult()
        throws -> IOSAcceptedOutputDeliveryRemovalResult {
        try requireNoUncertainHistoryMutation()
        guard try journal.loadOpaque() != nil else { return .alreadyAbsent }
        throw IOSAcceptedOutputDeliveryError.bridgeRevocationRequired
    }
}

private extension IOSAcceptedOutputDeliveryStore {
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
            IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization? = nil
    ) throws -> IOSAcceptedOutputDeliveryAcceptance {
        let timestamp = try IOSAcceptedOutputDeliveryTimestampCodec
            .canonicalDate(from: now())
        let newRecord = try makeInitialRecord(
            preparation,
            createdAt: timestamp,
            marksReplayableReplacement: pendingHistoryReplacement != nil
        )

        guard let current = try journal.load() else {
            guard pendingHistoryReplacement == nil else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            do {
                let created = try publishAcceptance(
                    newRecord,
                    source: .missing,
                    preparation: preparation,
                    provenance: .freshCurrentProcess
                )
                clearTransientState(for: nil)
                return IOSAcceptedOutputDeliveryAcceptance(
                    record: created.record,
                    provenance: .freshCurrentProcess
                )
            } catch IOSAcceptedOutputDeliveryError.slotOccupied {
                return try reconcileAcceptanceConflict(
                    preparation,
                    otherwise: .slotOccupied
                )
            }
        }

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

        if current.record.hasSameAcceptance(as: preparation) {
            return try reconcileSameAcceptance(
                preparation,
                snapshot: current,
                temporalState: currentTemporalState,
                recordsOrdinaryAcceptanceUncertainty:
                    pendingHistoryReplacement == nil,
                provenance: .preexisting
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

        let confirmedOutboxAbsenceAuthorization:
            IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization?
        if currentTemporalState == .active,
           current.record.historyWrite != nil,
           current.record.historyWrite?.state.isPendingDecision == false {
            guard let outboxAbsenceAuthorization else {
                throw IOSAcceptedOutputDeliveryError.historyTransferRequired
            }
            try requireOutboxAbsenceAuthorization(
                outboxAbsenceAuthorization,
                for: current
            )
            confirmedOutboxAbsenceAuthorization = outboxAbsenceAuthorization
        } else {
            confirmedOutboxAbsenceAuthorization = nil
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
                    provenance: .freshCurrentProcess
                )
            } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
                return IOSAcceptedOutputDeliveryAcceptance(
                    record: try reconcilePendingHistoryReplacementConflict(
                        intent
                    ),
                    provenance: .freshCurrentProcess
                )
            }
        }

        do {
            let replaced = try publishAcceptance(
                newRecord,
                source: .existing(current),
                preparation: preparation,
                provenance: .freshCurrentProcess,
                outboxAbsenceAuthorization:
                    confirmedOutboxAbsenceAuthorization
            )
            clearTransientState(for: current.record.deliveryID)
            return IOSAcceptedOutputDeliveryAcceptance(
                record: replaced.record,
                provenance: .freshCurrentProcess
            )
        } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
            return try reconcileAcceptanceConflict(
                preparation,
                otherwise: .compareAndSwapFailed
            )
        }
    }

    private func reconcileAcceptance(
        _ intent: UncertainAcceptanceIntent
    ) throws -> IOSAcceptedOutputDeliveryAcceptance {
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
                provenance: intent.provenance,
                outboxAbsenceAuthorization:
                    intent.outboxAbsenceAuthorization
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
                provenance: intent.provenance,
                outboxAbsenceAuthorization:
                    intent.outboxAbsenceAuthorization
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
        provenance: IOSAcceptedOutputDeliveryAcceptanceProvenance,
        outboxAbsenceAuthorization:
            IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization? = nil
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        let intent = UncertainAcceptanceIntent(
            preparation: preparation,
            source: source,
            intended: intended,
            provenance: provenance,
            outboxAbsenceAuthorization: outboxAbsenceAuthorization
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
        otherwise error: IOSAcceptedOutputDeliveryError
    ) throws -> IOSAcceptedOutputDeliveryAcceptance {
        guard let current = try journal.load() else { throw error }
        let currentTemporalState = temporalState(for: current.record)
        if current.record.hasSameAcceptance(as: preparation) {
            return try reconcileSameAcceptance(
                preparation,
                snapshot: current,
                temporalState: currentTemporalState,
                recordsOrdinaryAcceptanceUncertainty: true,
                provenance: .preexisting
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
        switch temporalState {
        case .active:
            break
        case .expired:
            throw IOSAcceptedOutputDeliveryError.expired
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
        try requireActive(confirmed.record)
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
            authorization.capabilityOwnerIdentity == capabilityOwnerIdentity
                && receipt.capabilityOwnerIdentity == capabilityOwnerIdentity
        case .cancel(let authorization, let receipt):
            authorization.capabilityOwnerIdentity == capabilityOwnerIdentity
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
            try requireActive(current.record)
            guard let historyWrite = current.record.historyWrite,
                  historyWrite.state.isPendingDecision else {
                throw IOSAcceptedOutputDeliveryError.invalidTransition
            }
            let intended = try record(
                replacing: current.record,
                revision: try nextRevision(after: current.record.revision),
                updatedAt: try mutationNow(for: current.record),
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

        do {
            _ = try mutationNow(for: intent.intended)
        } catch IOSAcceptedOutputDeliveryError.expired {
            uncertainHistoryTransition = nil
            throw IOSAcceptedOutputDeliveryError.expired
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
        historyWrite: IOSAcceptedOutputHistoryWrite?? = nil
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        try IOSAcceptedOutputDeliveryRecord(
            revision: revision,
            deliveryID: old.deliveryID,
            sessionID: old.sessionID,
            attemptID: old.attemptID,
            transcriptID: old.transcriptID,
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
        try journal.replace(snapshot.record, expected: snapshot)
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
        for snapshot: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws {
        guard let authorization else {
            throw IOSAcceptedOutputDeliveryError.historyTransferRequired
        }
        let delivery = IOSAcceptedOutputDeliveryAuthorization(
            snapshot: snapshot,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
        guard authorization.provesAbsence(
            for: delivery,
            deliveryStoreIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity
        ) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
    }

    func isImmediateRetry(
        _ record: IOSAcceptedOutputDeliveryRecord,
        after expected: IOSAcceptedOutputDeliveryExpectation
    ) -> Bool {
        guard expected.matchesIdentity(record) else { return false }
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
