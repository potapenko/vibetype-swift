import Foundation

struct IOSAcceptedOutputDeliveryFrozenSlotProofMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetryAcceptingOutputAuthorizationMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetryAcceptingOutputReceiptMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetryTerminalDeliveryProofMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetrySuccessAuthorizationMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetrySuccessReceiptMint: Sendable {
    init() {}
}

struct IOSFailedHistoryRetryDeliveryFreezeReservationID:
    Equatable,
    Sendable {
    private let value = UUID()
}

/// Process-local ownership of the exact delivery slot from observation until
/// the failed row durably enters `acceptingOutput`. The shared interlock, not
/// this value alone, decides whether the reservation is still live.
struct IOSFailedHistoryRetryDeliveryFreezeReservation:
    Equatable,
    Sendable {
    let reservationID: IOSFailedHistoryRetryDeliveryFreezeReservationID
    let relationKey: IOSFailedHistoryRetryDeliveryRelationKey
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization
}

/// The exact delivery slot observed before a Retry crosses into
/// `acceptingOutput`. A present predecessor retains its physical journal
/// revision, not merely its decoded record.
enum IOSAcceptedOutputDeliveryFrozenSlot: Equatable, Sendable {
    case missing
    case existing(IOSAcceptedOutputDeliveryJournalSnapshot)
}

/// Delivery-store proof that one exact Retry preparation observed one exact
/// predecessor while the shared root lease was active.
struct IOSAcceptedOutputDeliveryFrozenSlotProof: Equatable, Sendable {
    let frozenSlot: IOSAcceptedOutputDeliveryFrozenSlot
    let preparation: IOSAcceptedOutputDeliveryPreparation
    let retryingRow: IOSFailedHistoryEntry
    let retryOperation: IOSFailedHistoryRetryOperation
    let freezeReservation:
        IOSFailedHistoryRetryDeliveryFreezeReservation
    let deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSAcceptedOutputDeliveryFrozenSlotProofMint,
        frozenSlot: IOSAcceptedOutputDeliveryFrozenSlot,
        preparation: IOSAcceptedOutputDeliveryPreparation,
        retryingRow: IOSFailedHistoryEntry,
        retryOperation: IOSFailedHistoryRetryOperation,
        freezeReservation:
            IOSFailedHistoryRetryDeliveryFreezeReservation,
        deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil,
              retryingRow.ownershipState == .ready,
              retryingRow.retryOperation == retryOperation,
              retryOperation.state == .providerDispatched,
              freezeReservation.relationKey.retryID
                == retryOperation.retryID,
              freezeReservation.relationKey.deliveryID
                == retryOperation.deliveryID,
              freezeReservation.relationKey.sessionID
                == retryOperation.sessionID,
              freezeReservation.relationKey.attemptID
                == retryingRow.attemptID,
              freezeReservation.relationKey.transcriptID
                == retryOperation.transcriptID,
              freezeReservation.relationKey.deliveryStoreIdentity
                == deliveryStoreIdentity,
              freezeReservation.relationKey.ownerIdentity
                == ownerIdentity,
              freezeReservation.relationKey.repositoryBinding
                == repositoryBinding,
              freezeReservation.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              IOSFailedHistoryRetryAcceptanceValidation
                .preparationMatchesRetry(
                    preparation,
                    row: retryingRow,
                    operation: retryOperation
                ),
              IOSFailedHistoryRetryAcceptanceValidation
                .slotCanBeFrozen(
                    frozenSlot,
                    for: preparation
                ) else {
            return nil
        }

        self.frozenSlot = frozenSlot
        self.preparation = preparation
        self.retryingRow = retryingRow
        self.retryOperation = retryOperation
        self.freezeReservation = freezeReservation
        self.deliveryStoreIdentity = deliveryStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

enum IOSFailedHistoryRetryAcceptingOutputPreparation:
    Equatable,
    Sendable {
    case commit(IOSFailedHistoryRetryAcceptingOutputAuthorization)
    case completed(IOSFailedHistoryRetryAcceptingOutputReceipt)
}

/// Failed-store authority for the exact
/// `providerDispatched -> acceptingOutput` mutation. The mutation changes only
/// the operation state and failed-envelope revision; `updatedAt` and every
/// failed-row payload field remain byte-for-byte unchanged.
struct IOSFailedHistoryRetryAcceptingOutputAuthorization:
    Equatable,
    Sendable {
    let dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt
    let providerCompletionClaim:
        IOSFailedHistoryRetryProviderCompletionClaim
    let frozenSlotProof: IOSAcceptedOutputDeliveryFrozenSlotProof
    let failedSource: IOSFailedHistoryJournalSnapshot
    let providerDispatchedRow: IOSFailedHistoryEntry
    let acceptingRow: IOSFailedHistoryEntry
    let providerDispatchedOperation: IOSFailedHistoryRetryOperation
    let acceptingOperation: IOSFailedHistoryRetryOperation
    let outcome: IOSFailedHistoryEnvelope
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    var relationKey: IOSFailedHistoryRetryDeliveryRelationKey {
        IOSFailedHistoryRetryDeliveryRelationKey(
            retryID: acceptingOperation.retryID,
            deliveryID: acceptingOperation.deliveryID,
            sessionID: acceptingOperation.sessionID,
            attemptID: acceptingRow.attemptID,
            transcriptID: acceptingOperation.transcriptID,
            failedStoreIdentity: failedStoreIdentity,
            deliveryStoreIdentity: deliveryStoreIdentity,
            ownerIdentity: ownerIdentity,
            repositoryBinding: repositoryBinding
        )
    }

    init?(
        mint: IOSFailedHistoryRetryAcceptingOutputAuthorizationMint,
        dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        providerCompletionClaim:
            IOSFailedHistoryRetryProviderCompletionClaim,
        frozenSlotProof: IOSAcceptedOutputDeliveryFrozenSlotProof,
        failedSource: IOSFailedHistoryJournalSnapshot,
        acceptingRow: IOSFailedHistoryEntry,
        acceptingOperation: IOSFailedHistoryRetryOperation,
        outcome: IOSFailedHistoryEnvelope,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        let providerDispatchedRow = dispatchReceipt.row
        let providerDispatchedOperation = dispatchReceipt.retryOperation
        let nextRevision = failedSource.envelope.revision
            .addingReportingOverflow(1)

        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil,
              dispatchReceipt.failedStoreIdentity == failedStoreIdentity,
              dispatchReceipt.ownerIdentity == ownerIdentity,
              dispatchReceipt.repositoryBinding == repositoryBinding,
              dispatchReceipt.durableSnapshot == failedSource,
              dispatchReceipt.row == providerDispatchedRow,
              dispatchReceipt.retryOperation == providerDispatchedOperation,
              providerDispatchedOperation.state == .providerDispatched,
              providerCompletionClaim.liveOwnerToken
                == dispatchReceipt.liveOwnerToken,
              frozenSlotProof.retryingRow == providerDispatchedRow,
              frozenSlotProof.retryOperation == providerDispatchedOperation,
              frozenSlotProof.deliveryStoreIdentity == deliveryStoreIdentity,
              frozenSlotProof.freezeReservation.relationKey
                .failedStoreIdentity == failedStoreIdentity,
              frozenSlotProof.ownerIdentity == ownerIdentity,
              frozenSlotProof.repositoryBinding == repositoryBinding,
              frozenSlotProof.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              IOSFailedHistoryRetryAcceptanceValidation
                .isStateOnlyTransition(
                    from: providerDispatchedOperation,
                    to: acceptingOperation,
                    targetState: .acceptingOutput
                ),
              acceptingRow.retryOperation == acceptingOperation,
              IOSFailedHistoryRetryAcceptanceValidation
                .preservesFailedRow(
                    providerDispatchedRow,
                    in: acceptingRow
                ),
              !nextRevision.overflow,
              outcome.revision == nextRevision.partialValue,
              outcome.audioCleanup == failedSource.envelope.audioCleanup,
              IOSFailedHistoryRetryAcceptanceValidation
                .isExactRowReplacement(
                    source: failedSource.envelope,
                    candidate: providerDispatchedRow,
                    replacement: acceptingRow,
                    outcome: outcome
                ) else {
            return nil
        }

        self.dispatchReceipt = dispatchReceipt
        self.providerCompletionClaim = providerCompletionClaim
        self.frozenSlotProof = frozenSlotProof
        self.failedSource = failedSource
        self.providerDispatchedRow = providerDispatchedRow
        self.acceptingRow = acceptingRow
        self.providerDispatchedOperation = providerDispatchedOperation
        self.acceptingOperation = acceptingOperation
        self.outcome = outcome
        self.failedStoreIdentity = failedStoreIdentity
        self.deliveryStoreIdentity = deliveryStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    func identifiesSameAcceptance(
        as other: IOSFailedHistoryRetryAcceptingOutputAuthorization
    ) -> Bool {
        dispatchReceipt.identifiesSameDispatch(as: other.dispatchReceipt)
            && providerCompletionClaim == other.providerCompletionClaim
            && frozenSlotProof == other.frozenSlotProof
            && failedSource == other.failedSource
            && providerDispatchedRow == other.providerDispatchedRow
            && acceptingRow == other.acceptingRow
            && providerDispatchedOperation
                == other.providerDispatchedOperation
            && acceptingOperation == other.acceptingOperation
            && outcome == other.outcome
            && failedStoreIdentity == other.failedStoreIdentity
            && deliveryStoreIdentity == other.deliveryStoreIdentity
            && ownerIdentity == other.ownerIdentity
            && repositoryBinding == other.repositoryBinding
    }
}

struct IOSFailedHistoryRetryAcceptingOutputReceipt:
    Equatable,
    Sendable {
    let authorization: IOSFailedHistoryRetryAcceptingOutputAuthorization
    let durableSnapshot: IOSFailedHistoryJournalSnapshot
    let row: IOSFailedHistoryEntry
    let retryOperation: IOSFailedHistoryRetryOperation
    let frozenSlotProof: IOSAcceptedOutputDeliveryFrozenSlotProof
    let providerCompletionClaim:
        IOSFailedHistoryRetryProviderCompletionClaim
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    var relationKey: IOSFailedHistoryRetryDeliveryRelationKey {
        authorization.relationKey
    }

    init?(
        mint: IOSFailedHistoryRetryAcceptingOutputReceiptMint,
        authorization: IOSFailedHistoryRetryAcceptingOutputAuthorization,
        durableSnapshot: IOSFailedHistoryJournalSnapshot,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              authorization.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              durableSnapshot.envelope == authorization.outcome,
              durableSnapshot.envelope.entries.contains(
                  authorization.acceptingRow
              ),
              authorization.acceptingRow.retryOperation
                == authorization.acceptingOperation,
              authorization.acceptingOperation.state == .acceptingOutput else {
            return nil
        }

        self.authorization = authorization
        self.durableSnapshot = durableSnapshot
        row = authorization.acceptingRow
        retryOperation = authorization.acceptingOperation
        frozenSlotProof = authorization.frozenSlotProof
        providerCompletionClaim = authorization.providerCompletionClaim
        failedStoreIdentity = authorization.failedStoreIdentity
        deliveryStoreIdentity = authorization.deliveryStoreIdentity
        ownerIdentity = authorization.ownerIdentity
        repositoryBinding = authorization.repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

/// Delivery-store proof that the Retry delivery is durably present with the
/// exact accepted bytes and a terminal History marker.
struct IOSFailedHistoryRetryTerminalDeliveryProof: Equatable, Sendable {
    let acceptingOutputReceipt:
        IOSFailedHistoryRetryAcceptingOutputReceipt
    let deliveryAuthorization: IOSAcceptedOutputDeliveryAuthorization
    let preparation: IOSAcceptedOutputDeliveryPreparation
    let deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRetryTerminalDeliveryProofMint,
        acceptingOutputReceipt:
            IOSFailedHistoryRetryAcceptingOutputReceipt,
        deliveryAuthorization: IOSAcceptedOutputDeliveryAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        let preparation = acceptingOutputReceipt.frozenSlotProof.preparation
        guard operationLeaseAuthorization.provesActiveLease(),
              acceptingOutputReceipt.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              acceptingOutputReceipt.repositoryBinding.physicalRootIdentity
                != nil,
              deliveryAuthorization.storeIdentity
                == acceptingOutputReceipt.deliveryStoreIdentity,
              deliveryAuthorization.capabilityOwnerIdentity
                == acceptingOutputReceipt.ownerIdentity,
              IOSFailedHistoryRetryAcceptanceValidation
                .isExactTerminalDelivery(
                    deliveryAuthorization.record,
                    for: preparation,
                    retryID: acceptingOutputReceipt.retryOperation.retryID
                ) else {
            return nil
        }

        self.acceptingOutputReceipt = acceptingOutputReceipt
        self.deliveryAuthorization = deliveryAuthorization
        self.preparation = preparation
        deliveryStoreIdentity = acceptingOutputReceipt.deliveryStoreIdentity
        ownerIdentity = acceptingOutputReceipt.ownerIdentity
        repositoryBinding = acceptingOutputReceipt.repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

enum IOSFailedHistoryRetrySuccessPreparation: Equatable, Sendable {
    case commit(IOSFailedHistoryRetrySuccessAuthorization)
    case completed(IOSFailedHistoryRetrySuccessReceipt)
}

/// Failed-store authority for retiring only the exact successful accepting row
/// into its pre-authorized audio-cleanup tombstone. It never unlinks audio.
struct IOSFailedHistoryRetrySuccessAuthorization:
    Equatable,
    Sendable {
    let acceptingOutputReceipt:
        IOSFailedHistoryRetryAcceptingOutputReceipt
    let terminalDeliveryProof: IOSFailedHistoryRetryTerminalDeliveryProof
    let failedSource: IOSFailedHistoryJournalSnapshot
    let acceptingRow: IOSFailedHistoryEntry
    let retryOperation: IOSFailedHistoryRetryOperation
    let tombstone: IOSFailedHistoryAudioCleanup
    let outcome: IOSFailedHistoryEnvelope
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRetrySuccessAuthorizationMint,
        acceptingOutputReceipt:
            IOSFailedHistoryRetryAcceptingOutputReceipt,
        terminalDeliveryProof: IOSFailedHistoryRetryTerminalDeliveryProof,
        tombstone: IOSFailedHistoryAudioCleanup,
        outcome: IOSFailedHistoryEnvelope,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        let failedSource = acceptingOutputReceipt.durableSnapshot
        let acceptingRow = acceptingOutputReceipt.row
        let retryOperation = acceptingOutputReceipt.retryOperation
        let nextRevision = failedSource.envelope.revision
            .addingReportingOverflow(1)

        guard operationLeaseAuthorization.provesActiveLease(),
              acceptingOutputReceipt.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              acceptingOutputReceipt.repositoryBinding.physicalRootIdentity
                != nil,
              terminalDeliveryProof.acceptingOutputReceipt
                == acceptingOutputReceipt,
              terminalDeliveryProof.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              acceptingRow.ownershipState == .ready,
              acceptingRow.retryOperation == retryOperation,
              retryOperation.state == .acceptingOutput,
              failedSource.envelope.entries.contains(acceptingRow),
              failedSource.envelope.audioCleanup.count
                < IOSFailedHistoryValidation.maximumAudioCleanupCount,
              tombstone.attemptID == acceptingRow.attemptID,
              tombstone.policyGeneration == acceptingRow.policyGeneration,
              tombstone.queuedAt >= acceptingRow.updatedAt,
              tombstone.audioRelativeIdentifier
                == acceptingRow.audioRelativeIdentifier,
              tombstone.byteCount == acceptingRow.byteCount,
              !nextRevision.overflow,
              outcome.revision == nextRevision.partialValue,
              IOSFailedHistoryRetryAcceptanceValidation
                .isExactSuccessOutcome(
                    source: failedSource.envelope,
                    candidate: acceptingRow,
                    tombstone: tombstone,
                    outcome: outcome
                ) else {
            return nil
        }

        self.acceptingOutputReceipt = acceptingOutputReceipt
        self.terminalDeliveryProof = terminalDeliveryProof
        self.failedSource = failedSource
        self.acceptingRow = acceptingRow
        self.retryOperation = retryOperation
        self.tombstone = tombstone
        self.outcome = outcome
        failedStoreIdentity = acceptingOutputReceipt.failedStoreIdentity
        deliveryStoreIdentity = acceptingOutputReceipt.deliveryStoreIdentity
        ownerIdentity = acceptingOutputReceipt.ownerIdentity
        repositoryBinding = acceptingOutputReceipt.repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    func identifiesSameSuccess(
        as other: IOSFailedHistoryRetrySuccessAuthorization
    ) -> Bool {
        acceptingOutputReceipt == other.acceptingOutputReceipt
            && terminalDeliveryProof == other.terminalDeliveryProof
            && failedSource == other.failedSource
            && acceptingRow == other.acceptingRow
            && retryOperation == other.retryOperation
            && tombstone == other.tombstone
            && outcome == other.outcome
            && failedStoreIdentity == other.failedStoreIdentity
            && deliveryStoreIdentity == other.deliveryStoreIdentity
            && ownerIdentity == other.ownerIdentity
            && repositoryBinding == other.repositoryBinding
    }
}

struct IOSFailedHistoryRetrySuccessReceipt: Equatable, Sendable {
    let authorization: IOSFailedHistoryRetrySuccessAuthorization
    let durableSnapshot: IOSFailedHistoryJournalSnapshot
    let tombstone: IOSFailedHistoryAudioCleanup
    let retryOperation: IOSFailedHistoryRetryOperation
    let providerCompletionClaim:
        IOSFailedHistoryRetryProviderCompletionClaim
    let terminalDeliveryProof: IOSFailedHistoryRetryTerminalDeliveryProof
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRetrySuccessReceiptMint,
        authorization: IOSFailedHistoryRetrySuccessAuthorization,
        durableSnapshot: IOSFailedHistoryJournalSnapshot,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
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
                  $0.attemptID == authorization.acceptingRow.attemptID
                      || $0.audioRelativeIdentifier
                        == authorization.acceptingRow.audioRelativeIdentifier
              }) else {
            return nil
        }

        self.authorization = authorization
        self.durableSnapshot = durableSnapshot
        tombstone = authorization.tombstone
        retryOperation = authorization.retryOperation
        providerCompletionClaim = authorization.acceptingOutputReceipt
            .providerCompletionClaim
        terminalDeliveryProof = authorization.terminalDeliveryProof
        failedStoreIdentity = authorization.failedStoreIdentity
        deliveryStoreIdentity = authorization.deliveryStoreIdentity
        ownerIdentity = authorization.ownerIdentity
        repositoryBinding = authorization.repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

private enum IOSFailedHistoryRetryAcceptanceValidation {
    static func preparationMatchesRetry(
        _ preparation: IOSAcceptedOutputDeliveryPreparation,
        row: IOSFailedHistoryEntry,
        operation: IOSFailedHistoryRetryOperation
    ) -> Bool {
        guard preparation.deliveryID == operation.deliveryID,
              preparation.sessionID == operation.sessionID,
              preparation.attemptID == row.attemptID,
              preparation.transcriptID == operation.transcriptID,
              preparation.outputIntent == row.outputIntent,
              !preparation.automaticInsertionPreferenceEnabled,
              let historyWrite = preparation.historyWrite,
              historyWrite.state == .pending,
              historyWrite.policyGeneration == row.policyGeneration,
              IOSAcceptedOutputDeliveryValidation.bytesEqual(
                  historyWrite.transcriptionModel,
                  row.transcriptionModel
              ),
              historyWrite.transcriptionLanguageCode
                == row.transcriptionLanguageCode,
              historyWrite.durationMilliseconds
                == row.durationMilliseconds else {
            return false
        }
        return true
    }

    static func slotCanBeFrozen(
        _ slot: IOSAcceptedOutputDeliveryFrozenSlot,
        for preparation: IOSAcceptedOutputDeliveryPreparation
    ) -> Bool {
        switch slot {
        case .missing:
            return true
        case .existing(let snapshot):
            return isWhollyUnrelated(
                snapshot.record,
                to: preparation
            )
        }
    }

    static func isWhollyUnrelated(
        _ record: IOSAcceptedOutputDeliveryRecord,
        to preparation: IOSAcceptedOutputDeliveryPreparation
    ) -> Bool {
        let existingIdentities: Set<UUID> = [
            record.deliveryID,
            record.sessionID,
            record.attemptID,
            record.transcriptID,
        ]
        let retryIdentities: Set<UUID> = [
            preparation.deliveryID,
            preparation.sessionID,
            preparation.attemptID,
            preparation.transcriptID,
        ]
        return existingIdentities.isDisjoint(with: retryIdentities)
    }

    static func isStateOnlyTransition(
        from source: IOSFailedHistoryRetryOperation,
        to target: IOSFailedHistoryRetryOperation,
        targetState: IOSFailedHistoryRetryOperationState
    ) -> Bool {
        source.retryID == target.retryID
            && source.createdAt == target.createdAt
            && source.transcriptionID == target.transcriptionID
            && source.deliveryID == target.deliveryID
            && source.sessionID == target.sessionID
            && source.transcriptID == target.transcriptID
            && target.state == targetState
    }

    static func preservesFailedRow(
        _ source: IOSFailedHistoryEntry,
        in target: IOSFailedHistoryEntry
    ) -> Bool {
        source.attemptID == target.attemptID
            && source.createdAt == target.createdAt
            && source.updatedAt == target.updatedAt
            && source.policyGeneration == target.policyGeneration
            && source.failureCategory == target.failureCategory
            && source.pipelineStage == target.pipelineStage
            && source.retryCount == target.retryCount
            && source.outputIntent == target.outputIntent
            && IOSAcceptedOutputDeliveryValidation.bytesEqual(
                source.transcriptionModel,
                target.transcriptionModel
            )
            && source.transcriptionLanguageCode
                == target.transcriptionLanguageCode
            && source.durationMilliseconds == target.durationMilliseconds
            && source.byteCount == target.byteCount
            && source.audioRelativeIdentifier
                == target.audioRelativeIdentifier
            && source.ownershipState == target.ownershipState
    }

    static func isExactRowReplacement(
        source: IOSFailedHistoryEnvelope,
        candidate: IOSFailedHistoryEntry,
        replacement: IOSFailedHistoryEntry,
        outcome: IOSFailedHistoryEnvelope
    ) -> Bool {
        guard let index = source.entries.firstIndex(of: candidate) else {
            return false
        }
        var entries = source.entries
        entries[index] = replacement
        return outcome.entries
            == IOSFailedHistoryValidation.sortedEntries(entries)
    }

    static func isExactTerminalDelivery(
        _ record: IOSAcceptedOutputDeliveryRecord,
        for preparation: IOSAcceptedOutputDeliveryPreparation,
        retryID: UUID
    ) -> Bool {
        guard record.deliveryID == preparation.deliveryID,
              record.sessionID == preparation.sessionID,
              record.attemptID == preparation.attemptID,
              record.transcriptID == preparation.transcriptID,
              record.failedRetryID == retryID,
              record.acceptedText.map({
                  IOSAcceptedOutputDeliveryValidation.bytesEqual(
                      $0,
                      preparation.acceptedText
                  )
              }) == true,
              record.outputIntent == preparation.outputIntent,
              record.deliveryState == .pending,
              !record.automaticInsertionPreferenceEnabled,
              !preparation.automaticInsertionPreferenceEnabled,
              record.keepLatestResult == preparation.keepLatestResult,
              record.publicationGeneration == 0,
              let recordHistory = record.historyWrite,
              let preparationHistory = preparation.historyWrite,
              recordHistory.state == .committed
                || recordHistory.state == .cancelled,
              preparationHistory.state == .pending,
              recordHistory.hasSameMetadata(as: preparationHistory) else {
            return false
        }
        return true
    }

    static func isExactSuccessOutcome(
        source: IOSFailedHistoryEnvelope,
        candidate: IOSFailedHistoryEntry,
        tombstone: IOSFailedHistoryAudioCleanup,
        outcome: IOSFailedHistoryEnvelope
    ) -> Bool {
        guard let candidateIndex = source.entries.firstIndex(of: candidate),
              !source.audioCleanup.contains(where: {
                  $0.attemptID == tombstone.attemptID
                      || $0.audioRelativeIdentifier
                        == tombstone.audioRelativeIdentifier
              }) else {
            return false
        }
        var entries = source.entries
        entries.remove(at: candidateIndex)
        let cleanup = IOSFailedHistoryValidation.sortedAudioCleanup(
            source.audioCleanup + [tombstone]
        )
        return outcome.entries == entries
            && outcome.audioCleanup == cleanup
    }
}

extension IOSAcceptedOutputDeliveryFrozenSlot:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedOutputDeliveryFrozenSlot(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryDeliveryFreezeReservationID:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryDeliveryFreezeReservationID(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryDeliveryFreezeReservation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryDeliveryFreezeReservation(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSAcceptedOutputDeliveryFrozenSlotProof:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedOutputDeliveryFrozenSlotProof(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryAcceptingOutputPreparation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryAcceptingOutputPreparation(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryAcceptingOutputAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryAcceptingOutputAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryAcceptingOutputReceipt:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryAcceptingOutputReceipt(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryTerminalDeliveryProof:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryTerminalDeliveryProof(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetrySuccessPreparation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetrySuccessPreparation(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetrySuccessAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetrySuccessAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetrySuccessReceipt:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetrySuccessReceipt(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
