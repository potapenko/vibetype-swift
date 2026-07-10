import Foundation

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
                      marker.state == .pending else {
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
        let authorization: IOSAcceptedOutputDeliveryAuthorization
        let ownershipProof: IOSAcceptedOutputHistoryOwnershipProof
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

    private let journal: any IOSAcceptedOutputDeliveryJournalStoring
    private let now: @Sendable () -> Date
    private let monotonicNowNanoseconds: @Sendable () -> UInt64

    private var monotonicDeadlines: [UUID: MonotonicDeadline] = [:]
    private var confirmedAuthorizationFileRevision:
        IOSStrictProtectedRecordFileRevision?
    private var uncertainHistoryTransition: UncertainHistoryTransition?
    private var uncertainPendingHistoryReplacement:
        UncertainPendingHistoryReplacement?
    private var uncertainPendingHistoryClear: UncertainPendingHistoryClear?

    public init(applicationSupportDirectoryURL: URL) {
        journal = FoundationIOSAcceptedOutputDeliveryJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        now = { Date() }
        monotonicNowNanoseconds = { DispatchTime.now().uptimeNanoseconds }
    }

    init(
        journal: any IOSAcceptedOutputDeliveryJournalStoring,
        now: @escaping @Sendable () -> Date = { Date() },
        monotonicNowNanoseconds: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        }
    ) {
        self.journal = journal
        self.now = now
        self.monotonicNowNanoseconds = monotonicNowNanoseconds
    }

    /// Commits a newly accepted transcript or atomically replaces the previous
    /// generation-zero delivery after all deferred-owner gates are satisfied.
    public func accept(
        _ preparation: IOSAcceptedOutputDeliveryPreparation
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        try requireNoUncertainHistoryMutation()
        return try performAccept(preparation)
    }

    func replacePendingHistory(
        with preparation: IOSAcceptedOutputDeliveryPreparation,
        authorization: IOSAcceptedOutputDeliveryAuthorization,
        ownershipProof: IOSAcceptedOutputHistoryOwnershipProof
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        let operation = PendingHistoryReplacementOperation(
            preparation: preparation,
            authorization: authorization,
            ownershipProof: ownershipProof
        )
        if let uncertainPendingHistoryReplacement {
            return try reconcilePendingHistoryReplacement(
                uncertainPendingHistoryReplacement,
                operation: operation
            )
        }
        try requireNoUncertainHistoryMutation()
        return try performAccept(
            preparation,
            pendingHistoryReplacement: operation
        )
    }

    public func load() throws -> IOSAcceptedOutputDeliveryObservation? {
        guard let snapshot = try journal.load() else { return nil }
        return observation(for: snapshot.record)
    }

    /// Performs the mandatory identical durability-confirmation rewrite before
    /// an idempotent History upsert may use the accepted payload.
    public func authorizePendingHistoryWrite(
        expected: IOSAcceptedOutputDeliveryExpectation
    ) throws -> IOSAcceptedOutputDeliveryAuthorization {
        try requireNoUncertainHistoryMutation()
        let snapshot = try requireSnapshot(expected: expected)
        try requireActive(snapshot.record)
        guard snapshot.record.historyWrite?.state == .pending,
              snapshot.record.deliveryState != .discarded else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }

        if confirmedAuthorizationFileRevision == snapshot.fileRevision {
            return IOSAcceptedOutputDeliveryAuthorization(snapshot: snapshot)
        }

        let confirmed = try journal.replace(
            snapshot.record,
            expected: snapshot
        )
        try requireActive(confirmed.record)
        confirmedAuthorizationFileRevision = confirmed.fileRevision
        return IOSAcceptedOutputDeliveryAuthorization(snapshot: confirmed)
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

        if snapshot.record.historyWrite?.state == .pending {
            throw IOSAcceptedOutputDeliveryError.historyTransferRequired
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
              snapshot.record.historyWrite?.state == .pending else {
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
        let confirmed = try confirmIdentical(snapshot)
        try journal.remove(expected: confirmed)
        clearTransientState(for: snapshot.record.deliveryID)
        return .removed
    }

    @discardableResult
    public func performStagingMaintenance()
        throws -> IOSAcceptedOutputDeliveryMaintenanceReport {
        IOSAcceptedOutputDeliveryMaintenanceReport(
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
    private func performAccept(
        _ preparation: IOSAcceptedOutputDeliveryPreparation,
        pendingHistoryReplacement: PendingHistoryReplacementOperation? = nil
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        let timestamp = try IOSAcceptedOutputDeliveryTimestampCodec
            .canonicalDate(from: now())
        let newRecord = try makeInitialRecord(
            preparation,
            createdAt: timestamp
        )

        guard let current = try journal.load() else {
            guard pendingHistoryReplacement == nil else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            do {
                let created = try journal.create(newRecord)
                clearTransientState(for: nil)
                return created.record
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
                temporalState: currentTemporalState
            )
        }
        if current.record.collides(with: preparation) {
            throw IOSAcceptedOutputDeliveryError.identityCollision
        }

        try requireBridgeRevoked(current.record)
        if currentTemporalState == .active,
           current.record.historyWrite?.state == .pending {
            guard pendingHistoryReplacement != nil else {
                throw IOSAcceptedOutputDeliveryError.historyTransferRequired
            }
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
                return replaced.record
            } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
                return try reconcilePendingHistoryReplacementConflict(
                    intent
                )
            }
        }

        do {
            let replaced = try commit(newRecord, replacing: current)
            clearTransientState(for: current.record.deliveryID)
            return replaced.record
        } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
            return try reconcileAcceptanceConflict(
                preparation,
                otherwise: .compareAndSwapFailed
            )
        }
    }

    func reconcileAcceptanceConflict(
        _ preparation: IOSAcceptedOutputDeliveryPreparation,
        otherwise error: IOSAcceptedOutputDeliveryError
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        guard let current = try journal.load() else { throw error }
        let currentTemporalState = temporalState(for: current.record)
        if current.record.hasSameAcceptance(as: preparation) {
            return try reconcileSameAcceptance(
                preparation,
                snapshot: current,
                temporalState: currentTemporalState
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
              current.record.historyWrite?.state == .pending else {
            uncertainPendingHistoryReplacement = nil
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        switch temporalState(for: intent.intended) {
        case .active:
            break
        case .rollbackAmbiguous:
            throw IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        case .expired:
            uncertainPendingHistoryReplacement = nil
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
            confirmedAuthorizationFileRevision = nil
            return committed
        } catch IOSAcceptedOutputDeliveryError.commitUncertain {
            uncertainPendingHistoryReplacement = intent
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
    }

    private func reconcileSameAcceptance(
        _ preparation: IOSAcceptedOutputDeliveryPreparation,
        snapshot: IOSAcceptedOutputDeliveryJournalSnapshot,
        temporalState: TemporalState
    ) throws -> IOSAcceptedOutputDeliveryRecord {
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
            let committed = try commit(replacement, replacing: snapshot)
            pruneMonotonicDeadlines(keeping: committed.record.deliveryID)
            return committed.record
        }

        let confirmed = try confirmIdentical(snapshot)
        pruneMonotonicDeadlines(keeping: confirmed.record.deliveryID)
        try requireActive(confirmed.record)
        return confirmed.record
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
              current.record.historyWrite?.state == .pending else {
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
        guard uncertainPendingHistoryReplacement == nil,
              uncertainPendingHistoryClear == nil else {
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
                  historyWrite.state == .pending else {
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
              current.record.historyWrite?.state == .pending else {
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
        }
    }

    func requireNoUncertainHistoryMutation() throws {
        guard uncertainHistoryTransition == nil,
              uncertainPendingHistoryReplacement == nil,
              uncertainPendingHistoryClear == nil else {
            throw IOSAcceptedOutputDeliveryError.commitUncertain
        }
    }

    func makeInitialRecord(
        _ preparation: IOSAcceptedOutputDeliveryPreparation,
        createdAt: Date
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
                historyWrite: preparation.historyWrite
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
