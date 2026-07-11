import Foundation
import Testing
@testable import HoldTypePersistence

extension IOSAcceptedHistoryOutboxStore {
    func transferForTesting(
        delivery: IOSAcceptedOutputDeliveryAuthorization,
        policy: IOSHistoryPolicyReceipt
    ) async throws -> IOSAcceptedHistoryOutboxReceipt {
        let deliveryStore = IOSAcceptedOutputDeliveryStore(
            journal: IOSAcceptedHistoryTransferTestDeliveryJournal(
                snapshot: delivery.snapshot
            ),
            now: { delivery.record.createdAt.addingTimeInterval(1) },
            monotonicNowNanoseconds: { 1 },
            storeIdentity: deliveryStoreIdentity,
            outboxStoreIdentity: storeIdentity,
            capabilityOwnerIdentity: delivery.capabilityOwnerIdentity
        )
        let reservation: IOSAcceptedOutputPendingHistoryTransferReservation
        do {
            reservation = try await deliveryStore
                .reservePendingHistoryTransfer(
                    authorization: delivery,
                    policyReceipt: policy
                )
        } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
            if delivery.capabilityOwnerIdentity
                != policy.capabilityOwnerIdentity {
                throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
            }
            throw IOSAcceptedHistoryOutboxError.stalePolicyGeneration
        }
        return try transfer(
            reservation: reservation
        )
    }
}

private final class IOSAcceptedHistoryTransferTestDeliveryJournal:
    IOSAcceptedOutputDeliveryJournalStoring,
    @unchecked Sendable {
    private let snapshot: IOSAcceptedOutputDeliveryJournalSnapshot

    init(snapshot: IOSAcceptedOutputDeliveryJournalSnapshot) {
        self.snapshot = snapshot
    }

    func load() throws -> IOSAcceptedOutputDeliveryJournalSnapshot? {
        snapshot
    }

    func loadOpaque() throws -> IOSAcceptedOutputDeliveryOpaqueSnapshot? {
        nil
    }

    func create(
        _ record: IOSAcceptedOutputDeliveryRecord
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        throw IOSAcceptedOutputDeliveryError.slotOccupied
    }

    func replace(
        _ record: IOSAcceptedOutputDeliveryRecord,
        expected: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
    }

    func remove(
        expected: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws {
        throw IOSAcceptedOutputDeliveryError.removeFailed
    }

    func removeOpaque(
        expected: IOSAcceptedOutputDeliveryOpaqueSnapshot
    ) throws {
        throw IOSAcceptedOutputDeliveryError.removeFailed
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        .empty
    }
}

extension IOSAcceptedOutputDeliveryStore {
    func replacePendingHistoryForTesting(
        with preparation: IOSAcceptedOutputDeliveryPreparation,
        authorization: IOSAcceptedOutputDeliveryAuthorization,
        ownershipProof: IOSAcceptedOutputHistoryOwnershipProof
    ) async throws -> IOSAcceptedOutputDeliveryRecord {
        let marker = try #require(authorization.record.historyWrite)
        let state = try IOSHistoryPolicyState(
            revision: marker.policyGeneration,
            historyEnabled: true,
            policyGeneration: marker.policyGeneration
        )
        let policyStore = IOSHistoryPolicyStore(
            journal: IOSAcceptedHistoryTransferTestPolicyJournal(state: state),
            capabilityOwnerIdentity: authorization.capabilityOwnerIdentity
        )
        let policyReceipt = try await policyStore.confirm(
            expected: IOSHistoryPolicyExpectation(state: state)
        )
        let reservation = try reservePendingHistoryTransfer(
            authorization: authorization,
            policyReceipt: policyReceipt
        )
        if let outboxStoreIdentity = ownershipProof.outboxStoreIdentity {
            let claim = reservation.claimForOutbox(
                authorization: authorization,
                policyGeneration: marker.policyGeneration,
                ownerIdentity: authorization.capabilityOwnerIdentity,
                deliveryStoreIdentity: storeIdentity,
                outboxStoreIdentity: outboxStoreIdentity
            )
            try #require(claim == .claimed)
        }
        return try replacePendingHistory(
            with: preparation,
            reservation: reservation,
            ownershipProof: ownershipProof
        )
    }
}

private final class IOSAcceptedHistoryTransferTestPolicyJournal:
    IOSHistoryPolicyJournalStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: IOSHistoryPolicyJournalSnapshot
    private var nextRevision: UInt64 = 2

    init(state: IOSHistoryPolicyState) {
        snapshot = IOSHistoryPolicyJournalSnapshot(
            state: state,
            fileRevision: IOSStrictProtectedRecordFileRevision(
                testingToken: 1
            )
        )
    }

    func load() throws -> IOSHistoryPolicyJournalSnapshot? {
        lock.withLock { snapshot }
    }

    func create(
        _ state: IOSHistoryPolicyState
    ) throws -> IOSHistoryPolicyJournalSnapshot {
        throw IOSHistoryPolicyError.slotOccupied
    }

    func replace(
        _ state: IOSHistoryPolicyState,
        expected: IOSHistoryPolicyJournalSnapshot
    ) throws -> IOSHistoryPolicyJournalSnapshot {
        try lock.withLock {
            guard snapshot == expected else {
                throw IOSHistoryPolicyError.compareAndSwapFailed
            }
            let replacement = IOSHistoryPolicyJournalSnapshot(
                state: state,
                fileRevision: IOSStrictProtectedRecordFileRevision(
                    testingToken: nextRevision
                )
            )
            nextRevision += 1
            snapshot = replacement
            return replacement
        }
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        .empty
    }
}
