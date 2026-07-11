import Foundation

fileprivate struct IOSFailedHistoryRetryCancellationReservationMint:
    Sendable {
    fileprivate init() {}
}

enum IOSFailedHistoryPolicyCutoverDirective: Equatable, Sendable {
    case retirePendingMetadata(
        IOSFailedHistoryPendingMetadataRetirementAuthority
    )
    case inspectProcessLostRetry(
        IOSFailedHistoryRetryRecoveryInspection
    )
    case completeProcessLostRetryCancellation(
        IOSFailedHistoryRetryCancellationCompletionAuthorization
    )
    case recoverAudioCleanup(
        IOSFailedHistoryAudioCleanupAuthorization
    )
    case invalidateReadyRow(
        IOSFailedHistoryRowAudioValidationAuthorization
    )
    case retainedMutationConfirmed
    case blockedAcceptingOutput
    case complete
}

/// Store-minted identity for one exact durable Retry. Unlike policy recovery
/// inspection, this token is valid for a current-generation Retry and can be
/// retained by C4.4 while its provider handoff remains live.
struct IOSFailedHistoryRetryLiveOwnerToken: Equatable, Sendable {
    let failedSource: IOSFailedHistoryJournalSnapshot
    let row: IOSFailedHistoryEntry
    let retryOperation: IOSFailedHistoryRetryOperation
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let retryStateIdentity: IOSFailedHistoryRetryLiveOwnerStateIdentity
    let repositoryBinding:
        IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRetryLiveOwnerTokenMint,
        failedSource: IOSFailedHistoryJournalSnapshot,
        row: IOSFailedHistoryEntry,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        retryStateIdentity: IOSFailedHistoryRetryLiveOwnerStateIdentity,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil,
              row.ownershipState == .ready,
              let retryOperation = row.retryOperation,
              failedSource.envelope.entries.contains(row) else {
            return nil
        }
        self.failedSource = failedSource
        self.row = row
        self.retryOperation = retryOperation
        self.failedStoreIdentity = failedStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.retryStateIdentity = retryStateIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    func identifiesSameRetry(
        as other: IOSFailedHistoryRetryLiveOwnerToken
    ) -> Bool {
        failedSource == other.failedSource
            && row == other.row
            && retryOperation == other.retryOperation
            && failedStoreIdentity == other.failedStoreIdentity
            && ownerIdentity == other.ownerIdentity
            && retryStateIdentity == other.retryStateIdentity
            && repositoryBinding == other.repositoryBinding
    }
}

struct IOSFailedHistoryRetryRecoveryInspection: Equatable, Sendable {
    let liveOwnerToken: IOSFailedHistoryRetryLiveOwnerToken
    let policyReceipt: IOSHistoryPolicyReceipt

    var failedSource: IOSFailedHistoryJournalSnapshot {
        liveOwnerToken.failedSource
    }
    var row: IOSFailedHistoryEntry { liveOwnerToken.row }
    var retryOperation: IOSFailedHistoryRetryOperation {
        liveOwnerToken.retryOperation
    }
    var failedStoreIdentity: IOSFailedHistoryStoreIdentity {
        liveOwnerToken.failedStoreIdentity
    }
    var ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity {
        liveOwnerToken.ownerIdentity
    }
    var repositoryBinding:
        IOSAcceptedHistoryCoordinatorRepositoryBinding {
        liveOwnerToken.repositoryBinding
    }
    var operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization {
        liveOwnerToken.operationLeaseAuthorization
    }

    init?(
        mint: IOSFailedHistoryRetryRecoveryInspectionMint,
        liveOwnerToken: IOSFailedHistoryRetryLiveOwnerToken,
        policyReceipt: IOSHistoryPolicyReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard policyReceipt.capabilityOwnerIdentity
                == liveOwnerToken.ownerIdentity,
              liveOwnerToken.row.policyGeneration
                < policyReceipt.state.policyGeneration,
              liveOwnerToken.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              liveOwnerToken.retryOperation.state == .reserved
                || liveOwnerToken.retryOperation.state
                    == .providerDispatched else {
            return nil
        }
        self.liveOwnerToken = liveOwnerToken
        self.policyReceipt = policyReceipt
    }

    func identifiesSameRecovery(
        as other: IOSFailedHistoryRetryRecoveryInspection
    ) -> Bool {
        liveOwnerToken.identifiesSameRetry(as: other.liveOwnerToken)
            && policyReceipt == other.policyReceipt
    }
}

struct IOSFailedHistoryRetryLiveOwnerStateIdentity: Equatable, Sendable {
    private let value = UUID()
}

struct IOSFailedHistoryRetryCancellationReservationID: Equatable, Sendable {
    private let value = UUID()
}

/// Atomic process-local ownership of the nil -> cancellation-reserved
/// transition. The stable reservation ID survives a same-recovery lease
/// refresh, while the embedded inspection always carries the active lease.
struct IOSFailedHistoryRetryCancellationReservation: Equatable, Sendable {
    let reservationID: IOSFailedHistoryRetryCancellationReservationID
    let inspection: IOSFailedHistoryRetryRecoveryInspection
    let stateIdentity: IOSFailedHistoryRetryLiveOwnerStateIdentity
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    fileprivate init?(
        mint: IOSFailedHistoryRetryCancellationReservationMint,
        reservationID: IOSFailedHistoryRetryCancellationReservationID,
        inspection: IOSFailedHistoryRetryRecoveryInspection,
        stateIdentity: IOSFailedHistoryRetryLiveOwnerStateIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              inspection.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ) else {
            return nil
        }
        self.reservationID = reservationID
        self.inspection = inspection
        self.stateIdentity = stateIdentity
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    func identifiesSameReservation(
        as other: IOSFailedHistoryRetryCancellationReservation
    ) -> Bool {
        reservationID == other.reservationID
            && inspection.identifiesSameRecovery(as: other.inspection)
            && stateIdentity == other.stateIdentity
    }
}

/// Store-minted completion-only proof. It can consume only the matching
/// process-local reservation after the exact retryOperation-nil outcome is
/// durable; it grants no row, provider, or filesystem authority.
struct IOSFailedHistoryRetryCancellationCompletionAuthorization:
    Equatable,
    Sendable {
    let reservation: IOSFailedHistoryRetryCancellationReservation
    let outcome: IOSFailedHistoryEnvelope
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding:
        IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRetryCancellationCompletionAuthorizationMint,
        reservation: IOSFailedHistoryRetryCancellationReservation,
        outcome: IOSFailedHistoryEnvelope,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil,
              reservation.inspection.failedStoreIdentity
                == failedStoreIdentity,
              reservation.inspection.ownerIdentity == ownerIdentity,
              reservation.inspection.repositoryBinding
                == repositoryBinding else {
            return nil
        }
        self.reservation = reservation
        self.outcome = outcome
        self.failedStoreIdentity = failedStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

actor IOSFailedHistoryRetryLiveOwnerState {
    private enum Phase: Equatable, Sendable {
        case idle
        case live(IOSFailedHistoryRetryLiveOwnerToken)
        case cancellationReserved(
            IOSFailedHistoryRetryCancellationReservation
        )
    }

    nonisolated let identity =
        IOSFailedHistoryRetryLiveOwnerStateIdentity()
    private var phase: Phase = .idle

    func hasLiveOwner() -> Bool {
        if case .live(let token) = phase {
            guard token.operationLeaseAuthorization.provesActiveLease() else {
                phase = .idle
                return false
            }
            return true
        }
        return false
    }

    func hasCancellationReservation() -> Bool {
        if case .cancellationReserved = phase { return true }
        return false
    }

    func retainLiveOwner(
        _ token: IOSFailedHistoryRetryLiveOwnerToken
    ) -> Bool {
        guard phase == .idle,
              token.retryStateIdentity == identity,
              token.operationLeaseAuthorization.provesActiveLease() else {
            return false
        }
        phase = .live(token)
        return true
    }

    func retainLiveOwner(
        of inspection: IOSFailedHistoryRetryRecoveryInspection
    ) -> Bool {
        retainLiveOwner(inspection.liveOwnerToken)
    }

    @discardableResult
    func clearLiveOwner(
        _ token: IOSFailedHistoryRetryLiveOwnerToken
    ) -> Bool {
        guard case .live(let retained) = phase,
              retained == token else {
            return false
        }
        phase = .idle
        return true
    }

    @discardableResult
    func clearLiveOwner(
        of inspection: IOSFailedHistoryRetryRecoveryInspection
    ) -> Bool {
        clearLiveOwner(inspection.liveOwnerToken)
    }

    func reserveProcessLostCancellation(
        of inspection: IOSFailedHistoryRetryRecoveryInspection,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) -> IOSFailedHistoryRetryCancellationReservation? {
        let reservationID: IOSFailedHistoryRetryCancellationReservationID
        switch phase {
        case .idle:
            reservationID = IOSFailedHistoryRetryCancellationReservationID()
        case .live(let retained):
            guard !retained.operationLeaseAuthorization.provesActiveLease(),
                  retained.identifiesSameRetry(
                    as: inspection.liveOwnerToken
                  ) else {
                return nil
            }
            reservationID = IOSFailedHistoryRetryCancellationReservationID()
        case .cancellationReserved(let retained):
            // An active reservation is consumable and cannot be minted twice.
            // An inactive one refreshes only from the Store's exact same
            // source/row/retry recovery inspection under the new lease.
            guard !retained.operationLeaseAuthorization.provesActiveLease(),
                  retained.inspection.identifiesSameRecovery(
                    as: inspection
                  ) else {
                return nil
            }
            reservationID = retained.reservationID
        }
        guard let reservation =
                IOSFailedHistoryRetryCancellationReservation(
                    mint:
                        IOSFailedHistoryRetryCancellationReservationMint(),
                    reservationID: reservationID,
                    inspection: inspection,
                    stateIdentity: identity,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            return nil
        }
        phase = .cancellationReserved(reservation)
        return reservation
    }

    func authorizeProcessLostCancellation(
        of inspection: IOSFailedHistoryRetryRecoveryInspection,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) -> IOSFailedHistoryRetryCancellationReservation? {
        reserveProcessLostCancellation(
            of: inspection,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    @discardableResult
    func consumeCancellationReservation(
        using completion:
            IOSFailedHistoryRetryCancellationCompletionAuthorization
    ) -> Bool {
        guard completion.operationLeaseAuthorization.provesActiveLease(),
              completion.reservation.stateIdentity == identity,
              case .cancellationReserved(let retained) = phase,
              retained.identifiesSameReservation(
                as: completion.reservation
              ) else {
            return false
        }
        phase = .idle
        return true
    }
}

struct IOSFailedHistoryPolicyRetryCancellationAuthorization:
    Equatable,
    Sendable {
    let inspection: IOSFailedHistoryRetryRecoveryInspection
    let reservation: IOSFailedHistoryRetryCancellationReservation
    let outcome: IOSFailedHistoryEnvelope
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding:
        IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryPolicyRetryCancellationAuthorizationMint,
        inspection: IOSFailedHistoryRetryRecoveryInspection,
        reservation: IOSFailedHistoryRetryCancellationReservation,
        outcome: IOSFailedHistoryEnvelope,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        let nextRevision = inspection.failedSource.envelope.revision
            .addingReportingOverflow(1)
        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil,
              inspection.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              reservation.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              reservation.inspection == inspection,
              inspection.failedStoreIdentity == failedStoreIdentity,
              inspection.ownerIdentity == ownerIdentity,
              inspection.repositoryBinding == repositoryBinding,
              !nextRevision.overflow,
              outcome.revision == nextRevision.partialValue,
              outcome.audioCleanup
                == inspection.failedSource.envelope.audioCleanup,
              let sourceIndex = inspection.failedSource.envelope.entries
                .firstIndex(of: inspection.row),
              outcome.entries.indices.contains(sourceIndex),
              outcome.entries[sourceIndex].attemptID
                == inspection.row.attemptID,
              outcome.entries[sourceIndex].retryOperation == nil else {
            return nil
        }
        self.inspection = inspection
        self.reservation = reservation
        self.outcome = outcome
        self.failedStoreIdentity = failedStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    func identifiesSameCancellation(
        as other: IOSFailedHistoryPolicyRetryCancellationAuthorization
    ) -> Bool {
        inspection.identifiesSameRecovery(as: other.inspection)
            && reservation.identifiesSameReservation(
                as: other.reservation
            )
            && outcome == other.outcome
            && failedStoreIdentity == other.failedStoreIdentity
            && ownerIdentity == other.ownerIdentity
            && repositoryBinding == other.repositoryBinding
    }
}

enum IOSFailedHistoryPolicyRetryCancellationPreparation: Equatable, Sendable {
    case commit(IOSFailedHistoryPolicyRetryCancellationAuthorization)
    case completed(
        IOSFailedHistoryRetryCancellationCompletionAuthorization
    )
}

extension IOSFailedHistoryPolicyCutoverDirective:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryPolicyCutoverDirective(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryLiveOwnerToken:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryLiveOwnerToken(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryRecoveryInspection:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryRecoveryInspection(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryLiveOwnerStateIdentity:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryLiveOwnerStateIdentity(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryCancellationReservationID:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryCancellationReservationID(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryCancellationReservation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryCancellationReservation(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryCancellationCompletionAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryCancellationCompletionAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryPolicyRetryCancellationAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryPolicyRetryCancellationAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryPolicyRetryCancellationPreparation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryPolicyRetryCancellationPreparation(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
