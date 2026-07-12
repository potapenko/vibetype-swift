import Foundation

struct IOSFailedHistoryRetryRelaunchInspectionMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetryRelaunchReservationMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetryPreAcceptanceAbsenceProofMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetryAcceptingRecoveryInspectionMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetryAcceptedOutputAbsenceProofMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetryRecoveredRelationMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetryRecoveredClearAuthorizationMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetryRecoveredClearReceiptMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetryRecoveredTerminalDeliveryProofMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetryRecoveredSuccessAuthorizationMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetryRecoveredSuccessReceiptMint: Sendable {
    init() {}
}

enum IOSFailedHistoryRetryRecoveryResolution: Equatable, Sendable {
    case noWork
    case retryCancelled
    case acceptedOutputRecovered
    case pendingLocalRecovery
}

enum IOSFailedHistoryRetryRelaunchDirective: Equatable, Sendable {
    case noWork
    case cancel(IOSFailedHistoryRetryRelaunchInspection)
    case inspectAcceptingOutput(
        IOSFailedHistoryRetryRelaunchInspection
    )
}

struct IOSFailedHistoryRetryRelaunchInspection: Equatable, Sendable {
    let failedSource: IOSFailedHistoryJournalSnapshot
    let row: IOSFailedHistoryEntry
    let retryOperation: IOSFailedHistoryRetryOperation
    let policyReceipt: IOSHistoryPolicyReceipt
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let retryStateIdentity: IOSFailedHistoryRetryLiveOwnerStateIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    var relationKey: IOSFailedHistoryRetryDeliveryRelationKey {
        IOSFailedHistoryRetryDeliveryRelationKey(
            retryID: retryOperation.retryID,
            deliveryID: retryOperation.deliveryID,
            sessionID: retryOperation.sessionID,
            attemptID: row.attemptID,
            transcriptID: retryOperation.transcriptID,
            failedStoreIdentity: failedStoreIdentity,
            deliveryStoreIdentity: deliveryStoreIdentity,
            ownerIdentity: ownerIdentity,
            repositoryBinding: repositoryBinding
        )
    }

    init?(
        mint: IOSFailedHistoryRetryRelaunchInspectionMint,
        failedSource: IOSFailedHistoryJournalSnapshot,
        row: IOSFailedHistoryEntry,
        policyReceipt: IOSHistoryPolicyReceipt,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        retryStateIdentity: IOSFailedHistoryRetryLiveOwnerStateIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil,
              policyReceipt.capabilityOwnerIdentity == ownerIdentity,
              row.ownershipState == .ready,
              let retryOperation = row.retryOperation,
              failedSource.envelope.entries.contains(row),
              row.policyGeneration <= policyReceipt.state.policyGeneration,
              row.policyGeneration < policyReceipt.state.policyGeneration
                || policyReceipt.state.historyEnabled else {
            return nil
        }
        self.failedSource = failedSource
        self.row = row
        self.retryOperation = retryOperation
        self.policyReceipt = policyReceipt
        self.failedStoreIdentity = failedStoreIdentity
        self.deliveryStoreIdentity = deliveryStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.retryStateIdentity = retryStateIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    func identifiesSameRecovery(
        as other: IOSFailedHistoryRetryRelaunchInspection
    ) -> Bool {
        let retainedPolicy = policyReceipt.state
        let refreshedPolicy = other.policyReceipt.state
        let policyCanRefresh = refreshedPolicy == retainedPolicy
            || refreshedPolicy.policyGeneration
                > retainedPolicy.policyGeneration
                && refreshedPolicy.revision >= retainedPolicy.revision
        return failedSource == other.failedSource
            && row == other.row
            && retryOperation == other.retryOperation
            && policyCanRefresh
            && policyReceipt.capabilityOwnerIdentity
                == other.policyReceipt.capabilityOwnerIdentity
            && failedStoreIdentity == other.failedStoreIdentity
            && deliveryStoreIdentity == other.deliveryStoreIdentity
            && ownerIdentity == other.ownerIdentity
            && retryStateIdentity == other.retryStateIdentity
            && repositoryBinding == other.repositoryBinding
    }
}

struct IOSFailedHistoryRetryRelaunchReservationID: Equatable, Sendable {
    private let value = UUID()
}

struct IOSFailedHistoryRetryRelaunchReservation: Equatable, Sendable {
    let reservationID: IOSFailedHistoryRetryRelaunchReservationID
    let inspection: IOSFailedHistoryRetryRelaunchInspection
    let stateIdentity: IOSFailedHistoryRetryLiveOwnerStateIdentity
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRetryRelaunchReservationMint,
        reservationID: IOSFailedHistoryRetryRelaunchReservationID,
        inspection: IOSFailedHistoryRetryRelaunchInspection,
        stateIdentity: IOSFailedHistoryRetryLiveOwnerStateIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              inspection.retryStateIdentity == stateIdentity,
              inspection.operationLeaseAuthorization.provesSameActiveLease(
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
        as other: IOSFailedHistoryRetryRelaunchReservation
    ) -> Bool {
        reservationID == other.reservationID
            && inspection.identifiesSameRecovery(as: other.inspection)
            && stateIdentity == other.stateIdentity
    }
}

enum IOSFailedHistoryRetryObservedDeliverySlot: Equatable, Sendable {
    case missing
    case whollyUnrelated(IOSAcceptedOutputDeliveryJournalSnapshot)
}

struct IOSFailedHistoryRetryPreAcceptanceAbsenceProof:
    Equatable,
    Sendable {
    let reservation: IOSFailedHistoryRetryRelaunchReservation
    let observedSlot: IOSFailedHistoryRetryObservedDeliverySlot
    let deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRetryPreAcceptanceAbsenceProofMint,
        reservation: IOSFailedHistoryRetryRelaunchReservation,
        observedSlot: IOSFailedHistoryRetryObservedDeliverySlot,
        deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        let inspection = reservation.inspection
        guard operationLeaseAuthorization.provesActiveLease(),
              reservation.operationLeaseAuthorization.provesSameActiveLease(
                as: operationLeaseAuthorization
              ),
              inspection.retryOperation.state == .reserved
                || inspection.retryOperation.state == .providerDispatched,
              inspection.deliveryStoreIdentity == deliveryStoreIdentity,
              inspection.ownerIdentity == ownerIdentity else {
            return nil
        }
        self.reservation = reservation
        self.observedSlot = observedSlot
        self.deliveryStoreIdentity = deliveryStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

struct IOSFailedHistoryRetryAcceptingRecoveryInspection:
    Equatable,
    Sendable {
    let reservation: IOSFailedHistoryRetryRelaunchReservation
    let relationReservation:
        IOSFailedHistoryRetryDeliveryFreezeReservation
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    var inspection: IOSFailedHistoryRetryRelaunchInspection {
        reservation.inspection
    }
    var relationKey: IOSFailedHistoryRetryDeliveryRelationKey {
        inspection.relationKey
    }

    init?(
        mint: IOSFailedHistoryRetryAcceptingRecoveryInspectionMint,
        reservation: IOSFailedHistoryRetryRelaunchReservation,
        relationReservation:
            IOSFailedHistoryRetryDeliveryFreezeReservation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              reservation.operationLeaseAuthorization.provesSameActiveLease(
                as: operationLeaseAuthorization
              ),
              reservation.inspection.retryOperation.state
                == .acceptingOutput,
              relationReservation.relationKey
                == reservation.inspection.relationKey,
              relationReservation.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ) else {
            return nil
        }
        self.reservation = reservation
        self.relationReservation = relationReservation
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

struct IOSFailedHistoryRetryAcceptedOutputAbsenceProof:
    Equatable,
    Sendable {
    let acceptingInspection:
        IOSFailedHistoryRetryAcceptingRecoveryInspection
    let observedSlot: IOSFailedHistoryRetryObservedDeliverySlot
    let deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRetryAcceptedOutputAbsenceProofMint,
        acceptingInspection:
            IOSFailedHistoryRetryAcceptingRecoveryInspection,
        observedSlot: IOSFailedHistoryRetryObservedDeliverySlot,
        deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        let inspection = acceptingInspection.inspection
        guard operationLeaseAuthorization.provesActiveLease(),
              acceptingInspection.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              inspection.deliveryStoreIdentity == deliveryStoreIdentity,
              inspection.ownerIdentity == ownerIdentity else {
            return nil
        }
        self.acceptingInspection = acceptingInspection
        self.observedSlot = observedSlot
        self.deliveryStoreIdentity = deliveryStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

struct IOSFailedHistoryRetryRecoveredRelation: Equatable, Sendable {
    let acceptingInspection:
        IOSFailedHistoryRetryAcceptingRecoveryInspection
    let deliveryAuthorization: IOSAcceptedOutputDeliveryAuthorization
    let preparation: IOSAcceptedOutputDeliveryPreparation
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    var relationKey: IOSFailedHistoryRetryDeliveryRelationKey {
        acceptingInspection.relationKey
    }
    var row: IOSFailedHistoryEntry {
        acceptingInspection.inspection.row
    }
    var retryOperation: IOSFailedHistoryRetryOperation {
        acceptingInspection.inspection.retryOperation
    }
    var failedStoreIdentity: IOSFailedHistoryStoreIdentity {
        acceptingInspection.inspection.failedStoreIdentity
    }
    var deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity {
        acceptingInspection.inspection.deliveryStoreIdentity
    }
    var ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity {
        acceptingInspection.inspection.ownerIdentity
    }
    var repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding {
        acceptingInspection.inspection.repositoryBinding
    }
    var relationReservation:
        IOSFailedHistoryRetryDeliveryFreezeReservation {
        acceptingInspection.relationReservation
    }

    init?(
        mint: IOSFailedHistoryRetryRecoveredRelationMint,
        acceptingInspection:
            IOSFailedHistoryRetryAcceptingRecoveryInspection,
        deliveryAuthorization: IOSAcceptedOutputDeliveryAuthorization,
        preparation: IOSAcceptedOutputDeliveryPreparation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        let inspection = acceptingInspection.inspection
        guard operationLeaseAuthorization.provesActiveLease(),
              acceptingInspection.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              deliveryAuthorization.storeIdentity
                == inspection.deliveryStoreIdentity,
              deliveryAuthorization.capabilityOwnerIdentity
                == inspection.ownerIdentity,
              deliveryAuthorization.record
                .hasExactFailedRetryRecoveryAcceptance(
                    row: inspection.row,
                    operation: inspection.retryOperation
                ),
              deliveryAuthorization.record.hasSameAcceptance(
                as: preparation,
                failedRetryID: inspection.retryOperation.retryID
              ) else {
            return nil
        }
        self.acceptingInspection = acceptingInspection
        self.deliveryAuthorization = deliveryAuthorization
        self.preparation = preparation
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

enum IOSFailedHistoryRetryRelaunchDeliveryClassification:
    Equatable,
    Sendable {
    case missing(IOSFailedHistoryRetryAcceptedOutputAbsenceProof)
    case frozenPredecessor(
        IOSFailedHistoryRetryAcceptedOutputAbsenceProof
    )
    case matching(IOSFailedHistoryRetryRecoveredRelation)
    case collision
}

enum IOSFailedHistoryRetryDeliveryRelationReceipt: Equatable, Sendable {
    case live(IOSFailedHistoryRetryAcceptingOutputReceipt)
    case relaunched(IOSFailedHistoryRetryRecoveredRelation)

    var preparation: IOSAcceptedOutputDeliveryPreparation {
        switch self {
        case .live(let receipt): receipt.frozenSlotProof.preparation
        case .relaunched(let relation): relation.preparation
        }
    }
    var row: IOSFailedHistoryEntry {
        switch self {
        case .live(let receipt): receipt.row
        case .relaunched(let relation): relation.row
        }
    }
    var retryOperation: IOSFailedHistoryRetryOperation {
        switch self {
        case .live(let receipt): receipt.retryOperation
        case .relaunched(let relation): relation.retryOperation
        }
    }
    var relationKey: IOSFailedHistoryRetryDeliveryRelationKey {
        switch self {
        case .live(let receipt): receipt.relationKey
        case .relaunched(let relation): relation.relationKey
        }
    }
    var relationReservation:
        IOSFailedHistoryRetryDeliveryFreezeReservation {
        switch self {
        case .live(let receipt):
            receipt.frozenSlotProof.freezeReservation
        case .relaunched(let relation): relation.relationReservation
        }
    }
    var deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity {
        switch self {
        case .live(let receipt): receipt.deliveryStoreIdentity
        case .relaunched(let relation): relation.deliveryStoreIdentity
        }
    }
    var ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity {
        switch self {
        case .live(let receipt): receipt.ownerIdentity
        case .relaunched(let relation): relation.ownerIdentity
        }
    }
    var repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding {
        switch self {
        case .live(let receipt): receipt.repositoryBinding
        case .relaunched(let relation): relation.repositoryBinding
        }
    }
    var operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization {
        switch self {
        case .live(let receipt): receipt.operationLeaseAuthorization
        case .relaunched(let relation):
            relation.operationLeaseAuthorization
        }
    }
    var policyReceipt: IOSHistoryPolicyReceipt {
        switch self {
        case .live(let receipt):
            receipt.authorization.dispatchReceipt.authorization
                .reservationReceipt.authorization.policyReceipt
        case .relaunched(let relation):
            relation.acceptingInspection.inspection.policyReceipt
        }
    }
}

enum IOSFailedHistoryRetryRecoveredClearPreparation:
    Equatable,
    Sendable {
    case commit(IOSFailedHistoryRetryRecoveredClearAuthorization)
    case completed(IOSFailedHistoryRetryRecoveredClearReceipt)
}

struct IOSFailedHistoryRetryRecoveredClearAuthorization:
    Equatable,
    Sendable {
    let reservation: IOSFailedHistoryRetryRelaunchReservation
    let absenceProof: IOSFailedHistoryRetryAcceptedOutputAbsenceProof?
    let preAcceptanceAbsenceProof:
        IOSFailedHistoryRetryPreAcceptanceAbsenceProof?
    let outcome: IOSFailedHistoryEnvelope
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRetryRecoveredClearAuthorizationMint,
        reservation: IOSFailedHistoryRetryRelaunchReservation,
        absenceProof: IOSFailedHistoryRetryAcceptedOutputAbsenceProof?,
        preAcceptanceAbsenceProof:
            IOSFailedHistoryRetryPreAcceptanceAbsenceProof?,
        outcome: IOSFailedHistoryEnvelope,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        let operation = reservation.inspection.retryOperation
        let hasAcceptingProof = absenceProof != nil
        guard operationLeaseAuthorization.provesActiveLease(),
              reservation.operationLeaseAuthorization.provesSameActiveLease(
                as: operationLeaseAuthorization
              ),
              hasAcceptingProof != (preAcceptanceAbsenceProof != nil),
              (operation.state == .acceptingOutput) == hasAcceptingProof,
              absenceProof?.acceptingInspection.reservation == reservation
                || preAcceptanceAbsenceProof?.reservation == reservation,
              reservation.inspection.failedStoreIdentity
                == failedStoreIdentity,
              reservation.inspection.ownerIdentity == ownerIdentity,
              reservation.inspection.repositoryBinding
                == repositoryBinding else {
            return nil
        }
        self.reservation = reservation
        self.absenceProof = absenceProof
        self.preAcceptanceAbsenceProof = preAcceptanceAbsenceProof
        self.outcome = outcome
        self.failedStoreIdentity = failedStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

struct IOSFailedHistoryRetryRecoveredClearReceipt: Equatable, Sendable {
    let authorization: IOSFailedHistoryRetryRecoveredClearAuthorization
    let durableSnapshot: IOSFailedHistoryJournalSnapshot
    let row: IOSFailedHistoryEntry
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRetryRecoveredClearReceiptMint,
        authorization: IOSFailedHistoryRetryRecoveredClearAuthorization,
        durableSnapshot: IOSFailedHistoryJournalSnapshot,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        let inspection = authorization.reservation.inspection
        guard operationLeaseAuthorization.provesActiveLease(),
              authorization.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              durableSnapshot.envelope == authorization.outcome,
              let row = durableSnapshot.envelope.entries.first(where: {
                $0.attemptID == inspection.row.attemptID
              }),
              row.retryOperation == nil else {
            return nil
        }
        self.authorization = authorization
        self.durableSnapshot = durableSnapshot
        self.row = row
        failedStoreIdentity = authorization.failedStoreIdentity
        ownerIdentity = authorization.ownerIdentity
        repositoryBinding = authorization.repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

struct IOSFailedHistoryRetryRecoveredTerminalDeliveryProof:
    Equatable,
    Sendable {
    let relation: IOSFailedHistoryRetryRecoveredRelation
    let deliveryAuthorization: IOSAcceptedOutputDeliveryAuthorization
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRetryRecoveredTerminalDeliveryProofMint,
        relation: IOSFailedHistoryRetryRecoveredRelation,
        deliveryAuthorization: IOSAcceptedOutputDeliveryAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              relation.operationLeaseAuthorization.provesSameActiveLease(
                as: operationLeaseAuthorization
              ),
              deliveryAuthorization.storeIdentity
                == relation.deliveryStoreIdentity,
              deliveryAuthorization.capabilityOwnerIdentity
                == relation.ownerIdentity,
              deliveryAuthorization.record
                .hasExactFailedRetryRecoveryAcceptance(
                    row: relation.row,
                    operation: relation.retryOperation
                ),
              deliveryAuthorization.record.historyWrite?.state == .committed
                || deliveryAuthorization.record.historyWrite?.state
                    == .cancelled else {
            return nil
        }
        self.relation = relation
        self.deliveryAuthorization = deliveryAuthorization
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

enum IOSFailedHistoryRetryRecoveredSuccessPreparation:
    Equatable,
    Sendable {
    case commit(IOSFailedHistoryRetryRecoveredSuccessAuthorization)
    case completed(IOSFailedHistoryRetryRecoveredSuccessReceipt)
}

struct IOSFailedHistoryRetryRecoveredSuccessAuthorization:
    Equatable,
    Sendable {
    let terminalProof:
        IOSFailedHistoryRetryRecoveredTerminalDeliveryProof
    let tombstone: IOSFailedHistoryAudioCleanup
    let outcome: IOSFailedHistoryEnvelope
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRetryRecoveredSuccessAuthorizationMint,
        terminalProof:
            IOSFailedHistoryRetryRecoveredTerminalDeliveryProof,
        tombstone: IOSFailedHistoryAudioCleanup,
        outcome: IOSFailedHistoryEnvelope,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        let relation = terminalProof.relation
        guard operationLeaseAuthorization.provesActiveLease(),
              terminalProof.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              relation.failedStoreIdentity == failedStoreIdentity,
              relation.ownerIdentity == ownerIdentity,
              relation.repositoryBinding == repositoryBinding else {
            return nil
        }
        self.terminalProof = terminalProof
        self.tombstone = tombstone
        self.outcome = outcome
        self.failedStoreIdentity = failedStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

struct IOSFailedHistoryRetryRecoveredSuccessReceipt:
    Equatable,
    Sendable {
    let authorization:
        IOSFailedHistoryRetryRecoveredSuccessAuthorization
    let durableSnapshot: IOSFailedHistoryJournalSnapshot
    let tombstone: IOSFailedHistoryAudioCleanup
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRetryRecoveredSuccessReceiptMint,
        authorization:
            IOSFailedHistoryRetryRecoveredSuccessAuthorization,
        durableSnapshot: IOSFailedHistoryJournalSnapshot,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        let relation = authorization.terminalProof.relation
        guard operationLeaseAuthorization.provesActiveLease(),
              authorization.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              durableSnapshot.envelope == authorization.outcome,
              durableSnapshot.envelope.audioCleanup.contains(
                authorization.tombstone
              ),
              !durableSnapshot.envelope.entries.contains(where: {
                $0.attemptID == relation.row.attemptID
                    || $0.audioRelativeIdentifier
                        == relation.row.audioRelativeIdentifier
              }) else {
            return nil
        }
        self.authorization = authorization
        self.durableSnapshot = durableSnapshot
        tombstone = authorization.tombstone
        failedStoreIdentity = authorization.failedStoreIdentity
        ownerIdentity = authorization.ownerIdentity
        repositoryBinding = authorization.repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

extension IOSAcceptedHistoryCoordinator {
    /// C4.4D internal boundary. C4.5 wires this provider-free operation into
    /// containing-app lifecycle and exposes only a redacted app result.
    func recoverInterruptedFailedHistoryRetry()
        async throws -> IOSFailedHistoryRetryRecoveryResolution {
        let policyStore = policyStore
        let acceptedHistoryStore = acceptedHistoryStore
        let failedStore = failedHistoryStore
        let deliveryStore = deliveryStore
        let retryState = failedHistoryRetryState
        let acceptanceState = acceptanceState
        let pendingReplacementState = pendingReplacementState
        let policyCutoverState = policyCutoverState
        let failedTransferState = failedHistoryTransferState
        let failedAudioCleanupState = failedHistoryAudioCleanupState
        let foregroundVoicePersistenceState =
            foregroundVoicePersistenceState
        let ownerIdentity = ownerIdentity
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration

        do {
            return try await operationGate.perform { lease in
                guard await foregroundVoicePersistenceState.current() == nil
                else {
                    return .pendingLocalRecovery
                }
                let repositoryBinding = repositoryRegistration?.revalidate()
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                guard await policyCutoverState.current() == nil,
                      await failedTransferState.current() == nil,
                      await failedAudioCleanupState.current() == nil,
                      await pendingReplacementState.current() == nil else {
                    return .pendingLocalRecovery
                }
                if await retryState
                    .requestRetainedProviderCompletionRecovery() {
                    return .pendingLocalRecovery
                }
                if await retryState.requestRetainedProviderCancellation() {
                    return .pendingLocalRecovery
                }
                guard await retryState.hasLiveOwner() == false else {
                    return .pendingLocalRecovery
                }

                let policyReceipt: IOSHistoryPolicyReceipt?
                if let currentPolicy = try await policyStore.load() {
                    policyReceipt = try await policyStore.confirm(
                        expected: IOSHistoryPolicyExpectation(
                            state: currentPolicy
                        )
                    )
                } else {
                    policyReceipt = nil
                }
                let resolution = await Self
                    .recoverInterruptedFailedHistoryRetryWithinLease(
                        policyReceipt: policyReceipt,
                        policyStore: policyStore,
                        acceptedHistoryStore: acceptedHistoryStore,
                        failedStore: failedStore,
                        deliveryStore: deliveryStore,
                        retryState: retryState,
                        acceptanceState: acceptanceState,
                        pendingReplacementState:
                            pendingReplacementState,
                        ownerIdentity: ownerIdentity,
                        operationLeaseAuthorization: lease,
                        stopAfterHistoryTransition: false
                    )
                if let repositoryBinding {
                    _ = repositoryRegistration?.revalidate(
                        expectedBinding: repositoryBinding
                    )
                }
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                return resolution
            }
        } catch IOSPersistenceOperationGate.AcquisitionError
            .cancelledBeforeLease {
            throw IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError
            .reentrantOperation {
            throw IOSAcceptedHistoryCoordinatorError.reentrantOperation
        }
    }

    static func recoverInterruptedFailedHistoryRetryWithinLease(
        policyReceipt: IOSHistoryPolicyReceipt?,
        policyStore: IOSHistoryPolicyStore,
        acceptedHistoryStore: IOSAcceptedHistoryStore,
        failedStore: IOSFailedHistoryStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        retryState: IOSFailedHistoryRetryLiveOwnerState,
        acceptanceState: IOSAcceptedHistoryAcceptanceOperationState,
        pendingReplacementState:
            IOSAcceptedHistoryPendingReplacementOperationState,
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        stopAfterHistoryTransition: Bool
    ) async -> IOSFailedHistoryRetryRecoveryResolution {
        do {
            let directive = try await failedStore
                .prepareRetryRelaunchDirective(
                    using: policyReceipt,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
            switch directive {
            case .noWork:
                return .noWork

            case .cancel(let inspection):
                guard let reservation = await retryState
                    .reserveRelaunchRecovery(
                        of: inspection,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    ) else {
                    return .pendingLocalRecovery
                }
                let proof = try await deliveryStore
                    .proveFailedRetryPreAcceptanceAbsence(
                        reservation: reservation,
                        operationLeaseAuthorization:
                        operationLeaseAuthorization
                    )
                let preparation = try await failedStore
                    .prepareRecoveredRetryClear(
                        reservation: reservation,
                        preAcceptanceAbsenceProof: proof,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                let receipt: IOSFailedHistoryRetryRecoveredClearReceipt
                switch preparation {
                case .commit(let authorization):
                    receipt = try await failedStore
                        .commitRecoveredRetryClear(using: authorization)
                case .completed(let completed):
                    receipt = completed
                }
                guard await retryState.consumeRelaunchRecovery(
                    using: receipt
                ) else {
                    return .pendingLocalRecovery
                }
                try await failedStore.finishRecoveredRetryClear(
                    using: receipt,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
                return .retryCancelled

            case .inspectAcceptingOutput(let inspection):
                guard let reservation = await retryState
                    .reserveRelaunchRecovery(
                        of: inspection,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    ) else {
                    return .pendingLocalRecovery
                }
                let acceptingInspection = try await failedStore
                    .installRetryAcceptingRecoveryRelation(
                        reservation: reservation,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                let classification = try await deliveryStore
                    .classifyFailedRetryRelaunchDelivery(
                        acceptingInspection: acceptingInspection,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                switch classification {
                case .collision:
                    return .pendingLocalRecovery

                case .missing(let proof),
                     .frozenPredecessor(let proof):
                    let preparation = try await failedStore
                        .prepareRecoveredRetryClear(
                            reservation: reservation,
                            acceptedOutputAbsenceProof: proof,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        )
                    let receipt:
                        IOSFailedHistoryRetryRecoveredClearReceipt
                    switch preparation {
                    case .commit(let authorization):
                        receipt = try await failedStore
                            .commitRecoveredRetryClear(using: authorization)
                    case .completed(let completed):
                        receipt = completed
                    }
                    guard await retryState.consumeRelaunchRecovery(
                        using: receipt
                    ) else {
                        return .pendingLocalRecovery
                    }
                    try await failedStore.finishRecoveredRetryClear(
                        using: receipt,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                    return .retryCancelled

                case .matching(let relation):
                    let markerWasPending = relation.deliveryAuthorization
                        .record.historyWrite?.state == .pending
                    let history = try await recoverFailedRetryRelationWithinLease(
                        relation: relation,
                        policyStore: policyStore,
                        acceptedHistoryStore: acceptedHistoryStore,
                        deliveryStore: deliveryStore,
                        acceptanceState: acceptanceState,
                        pendingReplacementState:
                            pendingReplacementState,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization,
                        ownerIdentity: ownerIdentity
                    )
                    guard history.resolution != .pendingLocalRecovery else {
                        return .pendingLocalRecovery
                    }
                    if stopAfterHistoryTransition && markerWasPending {
                        return .pendingLocalRecovery
                    }
                    let refreshedClassification = try await deliveryStore
                        .classifyFailedRetryRelaunchDelivery(
                            acceptingInspection: acceptingInspection,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        )
                    guard case .matching(let terminalRelation) =
                            refreshedClassification,
                          terminalRelation.relationKey
                            == relation.relationKey,
                          terminalRelation.preparation
                            == relation.preparation,
                          terminalRelation.deliveryAuthorization.record
                            == history.deliveryRecord else {
                        return .pendingLocalRecovery
                    }
                    let terminalProof = try await deliveryStore
                        .confirmFailedRetryRecoveredTerminalDelivery(
                            relation: terminalRelation,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        )
                    let success = try await failedStore
                        .prepareRecoveredRetrySuccess(
                            terminalProof: terminalProof,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        )
                    let receipt:
                        IOSFailedHistoryRetryRecoveredSuccessReceipt
                    switch success {
                    case .commit(let authorization):
                        receipt = try await failedStore
                            .commitRecoveredRetrySuccess(
                                using: authorization
                            )
                    case .completed(let completed):
                        receipt = completed
                    }
                    guard await retryState.consumeRelaunchRecovery(
                        using: receipt
                    ) else {
                        return .pendingLocalRecovery
                    }
                    try await failedStore.finishRecoveredRetrySuccess(
                        using: receipt,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                    return .acceptedOutputRecovered
                }
            }
        } catch {
            return .pendingLocalRecovery
        }
    }
}

protocol IOSFailedHistoryRetryRecoveryRedacted:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {}

extension IOSFailedHistoryRetryRecoveryRedacted {
    var description: String {
        "IOSFailedHistoryRetryRecoveryCapability(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryRelaunchInspectionMint:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRelaunchReservationMint:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryPreAcceptanceAbsenceProofMint:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryAcceptingRecoveryInspectionMint:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryAcceptedOutputAbsenceProofMint:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRecoveredRelationMint:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRecoveredClearAuthorizationMint:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRecoveredClearReceiptMint:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRecoveredTerminalDeliveryProofMint:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRecoveredSuccessAuthorizationMint:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRecoveredSuccessReceiptMint:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRecoveryResolution:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRelaunchDirective:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRelaunchInspection:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRelaunchReservationID:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRelaunchReservation:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryObservedDeliverySlot:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryPreAcceptanceAbsenceProof:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryAcceptingRecoveryInspection:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryAcceptedOutputAbsenceProof:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRecoveredRelation:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRelaunchDeliveryClassification:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryDeliveryRelationReceipt:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRecoveredClearPreparation:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRecoveredClearAuthorization:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRecoveredClearReceipt:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRecoveredTerminalDeliveryProof:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRecoveredSuccessPreparation:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRecoveredSuccessAuthorization:
    IOSFailedHistoryRetryRecoveryRedacted {}
extension IOSFailedHistoryRetryRecoveredSuccessReceipt:
    IOSFailedHistoryRetryRecoveryRedacted {}
