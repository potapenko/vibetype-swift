import Foundation

struct IOSAcceptedHistoryCapabilityOwnerIdentity: Equatable, Sendable {
    private let value = UUID()
}

extension IOSAcceptedHistoryCapabilityOwnerIdentity:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedHistoryCapabilityOwnerIdentity(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

typealias IOSAcceptedHistoryCoordinatorOwnerIdentity =
    IOSAcceptedHistoryCapabilityOwnerIdentity

public enum IOSAcceptedHistoryAcceptanceResolution: Equatable, Sendable {
    case notRequested
    case committed
    case cancelled
    case pendingLocalRecovery
}

extension IOSAcceptedHistoryAcceptanceResolution:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSAcceptedHistoryAcceptanceResolution(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

public struct IOSAcceptedHistoryAcceptanceResult: Equatable, Sendable {
    public let deliveryRecord: IOSAcceptedOutputDeliveryRecord
    public let resolution: IOSAcceptedHistoryAcceptanceResolution

    init(
        deliveryRecord: IOSAcceptedOutputDeliveryRecord,
        resolution: IOSAcceptedHistoryAcceptanceResolution
    ) {
        self.deliveryRecord = deliveryRecord
        self.resolution = resolution
    }
}

extension IOSAcceptedHistoryAcceptanceResult:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSAcceptedHistoryAcceptanceResult(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSAcceptedHistoryAcceptancePhase: Equatable, Sendable {
    case deliveryAccepted(IOSAcceptedOutputDeliveryRecord)
    case deliveryAuthorized(IOSAcceptedOutputDeliveryAuthorization)
    case policyConfirmed(
        IOSAcceptedOutputDeliveryAuthorization,
        IOSHistoryPolicyReceipt
    )
    case rowDecided(
        IOSAcceptedOutputDeliveryAuthorization,
        IOSHistoryPolicyReceipt,
        IOSAcceptedHistoryRowReceipt
    )
    case policyRevalidated(
        IOSAcceptedOutputDeliveryAuthorization,
        IOSAcceptedHistoryRowReceipt
    )
    case invalidationConfirmed(
        IOSAcceptedOutputDeliveryAuthorization,
        IOSHistoryPolicyReceipt
    )
    case abandoningExpired(IOSAcceptedOutputDeliveryRecord)
    case confirmingExpired(IOSAcceptedOutputDeliveryExpiredObservation)
    case removingExpired(
        IOSAcceptedOutputDeliveryExpiredRemovalAuthorization
    )

    var deliveryRecord: IOSAcceptedOutputDeliveryRecord {
        switch self {
        case .deliveryAccepted(let record),
             .abandoningExpired(let record):
            record
        case .removingExpired(let authorization):
            authorization.record
        case .confirmingExpired(let observation):
            observation.record
        case .deliveryAuthorized(let authorization),
             .policyConfirmed(let authorization, _),
             .rowDecided(let authorization, _, _),
             .policyRevalidated(let authorization, _),
             .invalidationConfirmed(let authorization, _):
            authorization.record
        }
    }
}

extension IOSAcceptedHistoryAcceptancePhase:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedHistoryAcceptancePhase(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSAcceptedHistoryAcceptanceWork: Equatable, Sendable {
    case fresh(
        IOSAcceptedOutputDeliveryPreparation,
        IOSAcceptedHistoryAcceptancePhase
    )
    case preexisting(
        IOSAcceptedOutputDeliveryPreparation,
        IOSAcceptedHistoryAcceptancePhase
    )
    case relaunched(IOSAcceptedHistoryAcceptancePhase)
    case replayableReplacement(IOSAcceptedHistoryAcceptancePhase)

    var phase: IOSAcceptedHistoryAcceptancePhase {
        switch self {
        case .fresh(_, let phase),
             .preexisting(_, let phase),
             .relaunched(let phase),
             .replayableReplacement(let phase):
            phase
        }
    }

    var acceptedPreparation: IOSAcceptedOutputDeliveryPreparation? {
        switch self {
        case .fresh(let preparation, _),
             .preexisting(let preparation, _):
            preparation
        case .relaunched, .replayableReplacement:
            nil
        }
    }

    var freshPreparation: IOSAcceptedOutputDeliveryPreparation? {
        guard case .fresh(let preparation, _) = self else { return nil }
        return preparation
    }

    var mayInsertAbsentHistoryRow: Bool {
        switch self {
        case .fresh, .replayableReplacement:
            true
        case .preexisting, .relaunched:
            false
        }
    }

    func mayResume(
        with preparation: IOSAcceptedOutputDeliveryPreparation
    ) -> Bool {
        if acceptedPreparation == preparation { return true }
        guard case .replayableReplacement = self else { return false }
        return phase.deliveryRecord.hasSameAcceptance(as: preparation)
    }

    func replacingPhase(
        _ phase: IOSAcceptedHistoryAcceptancePhase
    ) -> Self {
        switch self {
        case .fresh(let preparation, _): .fresh(preparation, phase)
        case .preexisting(let preparation, _):
            .preexisting(preparation, phase)
        case .relaunched: .relaunched(phase)
        case .replayableReplacement: .replayableReplacement(phase)
        }
    }
}

extension IOSAcceptedHistoryAcceptanceWork:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSAcceptedHistoryAcceptanceWork(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

actor IOSAcceptedHistoryAcceptanceOperationState {
    private var work: IOSAcceptedHistoryAcceptanceWork?

    func current() -> IOSAcceptedHistoryAcceptanceWork? { work }

    func store(_ work: IOSAcceptedHistoryAcceptanceWork) {
        self.work = work
    }

    func clear() {
        work = nil
    }
}

private enum IOSAcceptedHistoryPolicyDisposition: Sendable {
    case matching(IOSHistoryPolicyReceipt)
    case invalidated(IOSHistoryPolicyReceipt)
}

private enum IOSAcceptedHistoryTransferRequirementResolution: Sendable {
    case accepted(IOSAcceptedOutputDeliveryAcceptance)
    case pendingDecision
}

private struct IOSAcceptedHistoryRecoveryOutcome: Sendable {
    let resolution: IOSAcceptedHistoryAcceptanceResolution?
    let observedDelivery: Bool

    func preservingObservedDelivery() -> Self {
        Self(resolution: resolution, observedDelivery: true)
    }
}

private struct IOSAcceptedHistoryResumeOutcome: Sendable {
    let result: IOSAcceptedHistoryAcceptanceResult
    let didAbandon: Bool
    let wasSuperseded: Bool
}

public extension IOSAcceptedHistoryCoordinator {
    /// Crosses the provider-replay boundary exactly once, then resolves or
    /// retains all History-only work in the shared process context.
    func accept(
        _ preparation: IOSAcceptedOutputDeliveryPreparation
    ) async throws -> IOSAcceptedHistoryAcceptanceResult {
        let policyStore = policyStore
        let acceptedHistoryStore = acceptedHistoryStore
        let outboxStore = outboxStore
        let deliveryStore = deliveryStore
        let acceptanceState = acceptanceState
        let pendingReplacementState = pendingReplacementState
        let outboxWorkerState = outboxWorkerState
        let ownerIdentity = ownerIdentity
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration

        do {
            return try await operationGate.perform {
                operationLeaseAuthorization in
                let repositoryBinding = repositoryRegistration?.revalidate()
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                do {
                    guard await outboxWorkerState.current() == nil else {
                        throw IOSAcceptedOutputDeliveryError.commitUncertain
                    }
                    try Self.validateHistoryPreparation(
                        preparation: preparation,
                        ownerIdentity: ownerIdentity
                    )
                    let result: IOSAcceptedHistoryAcceptanceResult
                    if let retained = await acceptanceState.current() {
                        guard await pendingReplacementState.current() == nil else {
                            throw IOSAcceptedOutputDeliveryError.commitUncertain
                        }
                        guard retained.mayResume(with: preparation) else {
                            throw IOSAcceptedOutputDeliveryError.commitUncertain
                        }
                        result = await Self.resume(
                            retained,
                            policyStore: policyStore,
                            acceptedHistoryStore: acceptedHistoryStore,
                            deliveryStore: deliveryStore,
                            acceptanceState: acceptanceState
                        ).result
                    } else {
                        let acceptance: IOSAcceptedOutputDeliveryAcceptance
                        if let replacement = await pendingReplacementState
                            .current() {
                            guard replacement.preparation == preparation else {
                                throw IOSAcceptedOutputDeliveryError
                                    .commitUncertain
                            }
                            acceptance = try await Self
                                .resumePendingReplacement(
                                    replacement,
                                    policyStore: policyStore,
                                    outboxStore: outboxStore,
                                    deliveryStore: deliveryStore,
                                    replacementState: pendingReplacementState,
                                    operationLeaseAuthorization:
                                        operationLeaseAuthorization,
                                    ownerIdentity: ownerIdentity
                                )
                        } else {
                            do {
                                acceptance = try await deliveryStore
                                    .acceptForHistoryCoordinator(preparation)
                            } catch IOSAcceptedOutputDeliveryError
                                .historyTransferRequired {
                                switch try await Self
                                    .resolveHistoryTransferRequirement(
                                        preparation: preparation,
                                        outboxStore: outboxStore,
                                        deliveryStore: deliveryStore,
                                        operationLeaseAuthorization:
                                            operationLeaseAuthorization
                                    ) {
                                case .accepted(let resolved):
                                    acceptance = resolved
                                case .pendingDecision:
                                    let replacement =
                                        IOSAcceptedHistoryPendingReplacementWork(
                                            ownerIdentity: ownerIdentity,
                                            preparation: preparation,
                                            phase: .observingCurrentDelivery
                                        )
                                    await pendingReplacementState.store(
                                        replacement
                                    )
                                    acceptance = try await Self
                                        .resumePendingReplacement(
                                            replacement,
                                            policyStore: policyStore,
                                            outboxStore: outboxStore,
                                            deliveryStore: deliveryStore,
                                            replacementState:
                                                pendingReplacementState,
                                            operationLeaseAuthorization:
                                                operationLeaseAuthorization,
                                            ownerIdentity: ownerIdentity
                                        )
                                }
                            }
                        }
                        let record = acceptance.record
                        if let resolution = Self.terminalResolution(
                            for: record
                        ) {
                            result = IOSAcceptedHistoryAcceptanceResult(
                                deliveryRecord: record,
                                resolution: resolution
                            )
                        } else {
                            let work = Self.acceptanceWork(
                                for: acceptance,
                                preparation: preparation
                            )
                            await acceptanceState.store(work)
                            result = await Self.resume(
                                work,
                                policyStore: policyStore,
                                acceptedHistoryStore: acceptedHistoryStore,
                                deliveryStore: deliveryStore,
                                acceptanceState: acceptanceState
                            ).result
                        }
                    }
                    guard Self.repositoryBindingIsValid(
                        repositoryBinding,
                        registration: repositoryRegistration,
                        identityState: repositoryIdentityState
                    ) else {
                        return IOSAcceptedHistoryAcceptanceResult(
                            deliveryRecord: result.deliveryRecord,
                            resolution: .pendingLocalRecovery
                        )
                    }
                    if result.resolution != .pendingLocalRecovery {
                        await acceptanceState.clear()
                    }
                    return result
                } catch {
                    if let repositoryBinding {
                        _ = repositoryRegistration?.revalidate(
                            expectedBinding: repositoryBinding
                        )
                    }
                    if repositoryIdentityState.isConflicted {
                        throw IOSAcceptedHistoryCoordinatorError
                            .repositoryIdentityConflict
                    }
                    throw error
                }
            }
        } catch IOSPersistenceOperationGate.AcquisitionError.cancelledBeforeLease {
            throw IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError.reentrantOperation {
            throw IOSAcceptedHistoryCoordinatorError.reentrantOperation
        }
    }

    /// Reconciles only local durable state. It never calls a provider. An
    /// absent row is replayable after relaunch only for the store-minted
    /// proof-bound pending-replacement marker.
    func recoverAcceptedHistory()
        async throws -> IOSAcceptedHistoryAcceptanceResolution? {
        let policyStore = policyStore
        let acceptedHistoryStore = acceptedHistoryStore
        let outboxStore = outboxStore
        let deliveryStore = deliveryStore
        let acceptanceState = acceptanceState
        let pendingReplacementState = pendingReplacementState
        let outboxWorkerState = outboxWorkerState
        let ownerIdentity = ownerIdentity
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration

        do {
            return try await operationGate.perform {
                operationLeaseAuthorization in
                let repositoryBinding = repositoryRegistration?.revalidate()
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                do {
                    guard await outboxWorkerState.current() == nil else {
                        return .pendingLocalRecovery
                    }
                    let outcome: IOSAcceptedHistoryRecoveryOutcome
                    if let replacement = await pendingReplacementState
                        .current() {
                        do {
                            let acceptance = try await Self
                                .resumePendingReplacement(
                                    replacement,
                                    policyStore: policyStore,
                                    outboxStore: outboxStore,
                                    deliveryStore: deliveryStore,
                                    replacementState: pendingReplacementState,
                                    operationLeaseAuthorization:
                                        operationLeaseAuthorization,
                                    ownerIdentity: ownerIdentity
                                )
                            if let terminal = Self.terminalResolution(
                                for: acceptance.record
                            ) {
                                outcome = IOSAcceptedHistoryRecoveryOutcome(
                                    resolution: terminal,
                                    observedDelivery: true
                                )
                            } else {
                                let work = Self.acceptanceWork(
                                    for: acceptance,
                                    preparation: replacement.preparation
                                )
                                await acceptanceState.store(work)
                                let resumed = await Self.resume(
                                    work,
                                    policyStore: policyStore,
                                    acceptedHistoryStore: acceptedHistoryStore,
                                    deliveryStore: deliveryStore,
                                    acceptanceState: acceptanceState
                                )
                                outcome = IOSAcceptedHistoryRecoveryOutcome(
                                    resolution: resumed.didAbandon
                                        ? nil
                                        : resumed.result.resolution,
                                    observedDelivery: true
                                )
                            }
                        } catch {
                            outcome = IOSAcceptedHistoryRecoveryOutcome(
                                resolution: .pendingLocalRecovery,
                                observedDelivery: true
                            )
                        }
                    } else if let retained = await acceptanceState.current() {
                        let resumeOutcome = await Self.resume(
                            retained,
                            policyStore: policyStore,
                            acceptedHistoryStore: acceptedHistoryStore,
                            deliveryStore: deliveryStore,
                            acceptanceState: acceptanceState
                        )
                        if resumeOutcome.wasSuperseded {
                            outcome = await Self.recoverAfterProcessLoss(
                                policyStore: policyStore,
                                acceptedHistoryStore: acceptedHistoryStore,
                                deliveryStore: deliveryStore,
                                acceptanceState: acceptanceState,
                                mayReloadAfterSupersession: false
                            ).preservingObservedDelivery()
                        } else {
                            outcome = IOSAcceptedHistoryRecoveryOutcome(
                                resolution: resumeOutcome.didAbandon
                                    ? nil
                                    : resumeOutcome.result.resolution,
                                observedDelivery: true
                            )
                        }
                    } else {
                        outcome = await Self.recoverAfterProcessLoss(
                            policyStore: policyStore,
                            acceptedHistoryStore: acceptedHistoryStore,
                            deliveryStore: deliveryStore,
                            acceptanceState: acceptanceState
                        )
                    }
                    guard Self.repositoryBindingIsValid(
                        repositoryBinding,
                        registration: repositoryRegistration,
                        identityState: repositoryIdentityState
                    ) else {
                        if outcome.observedDelivery {
                            return .pendingLocalRecovery
                        }
                        throw IOSAcceptedHistoryCoordinatorError
                            .repositoryIdentityConflict
                    }
                    if outcome.resolution == .committed
                        || outcome.resolution == .cancelled
                        || outcome.resolution == .notRequested {
                        await acceptanceState.clear()
                    }
                    return outcome.resolution
                } catch {
                    if let repositoryBinding {
                        _ = repositoryRegistration?.revalidate(
                            expectedBinding: repositoryBinding
                        )
                    }
                    if repositoryIdentityState.isConflicted {
                        throw IOSAcceptedHistoryCoordinatorError
                            .repositoryIdentityConflict
                    }
                    throw error
                }
            }
        } catch IOSPersistenceOperationGate.AcquisitionError.cancelledBeforeLease {
            throw IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError.reentrantOperation {
            throw IOSAcceptedHistoryCoordinatorError.reentrantOperation
        }
    }
}

extension IOSAcceptedHistoryCoordinator {
    static func validateHistoryPreparation(
        preparation: IOSAcceptedOutputDeliveryPreparation,
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity
    ) throws {
        guard let capture = preparation.historyCapture,
              capture.ownerIdentity == ownerIdentity,
              capture.policyReceipt.capabilityOwnerIdentity == ownerIdentity,
              preparation.historyWrite == capture.historyWrite,
              capture.policyReceipt.state.historyEnabled
                == (capture.historyWrite != nil) else {
            throw IOSAcceptedOutputDeliveryError.invalidPreparation
        }
        if let marker = capture.historyWrite {
            guard marker.state == .pending,
                  marker.policyGeneration
                    == capture.policyReceipt.state.policyGeneration else {
                throw IOSAcceptedOutputDeliveryError.invalidPreparation
            }
        }
    }
}

private extension IOSAcceptedHistoryCoordinator {
    static func resolveHistoryTransferRequirement(
        preparation: IOSAcceptedOutputDeliveryPreparation,
        outboxStore: IOSAcceptedHistoryOutboxStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSAcceptedHistoryTransferRequirementResolution {
        guard let observation = try await deliveryStore
            .loadForHistoryCoordinatorDuringAcceptance() else {
            return .accepted(
                try await deliveryStore.acceptForHistoryCoordinator(
                    preparation
                )
            )
        }

        switch observation {
        case .expired:
            return .accepted(
                try await deliveryStore.acceptForHistoryCoordinator(
                    preparation
                )
            )
        case .clockRollbackAmbiguous:
            throw IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        case .active(let record):
            if record.hasSameAcceptance(as: preparation) {
                return .accepted(
                    try await deliveryStore.acceptForHistoryCoordinator(
                        preparation
                    )
                )
            }
            if record.collides(with: preparation) {
                throw IOSAcceptedOutputDeliveryError.identityCollision
            }
            guard record.deliveryState != .discarded,
                  let marker = record.historyWrite else {
                return .accepted(
                    try await deliveryStore.acceptForHistoryCoordinator(
                        preparation
                    )
                )
            }
            guard !marker.state.isPendingDecision else {
                return .pendingDecision
            }

            let authorization: IOSAcceptedOutputDeliveryAuthorization
            do {
                authorization = try await deliveryStore
                    .confirmActiveHistoryRecoveryDuringAcceptance(
                        expected: IOSAcceptedOutputDeliveryExpectation(
                            record: record
                        )
                    )
            } catch IOSAcceptedOutputDeliveryError.expired {
                return .accepted(
                    try await deliveryStore.acceptForHistoryCoordinator(
                        preparation
                    )
                )
            }

            switch try await outboxStore.classifyDeliveryAbsence(
                authorization: authorization,
                operationLeaseAuthorization: operationLeaseAuthorization
            ) {
            case .absent(let absenceAuthorization):
                return .accepted(
                    try await deliveryStore.acceptForHistoryCoordinator(
                        preparation,
                        outboxAbsenceAuthorization: absenceAuthorization,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                )
            case .matching:
                throw IOSAcceptedOutputDeliveryError
                    .historyTransferRequired
            case .collision:
                throw IOSAcceptedOutputDeliveryError.identityCollision
            }
        }
    }

    static func acceptanceWork(
        for acceptance: IOSAcceptedOutputDeliveryAcceptance,
        preparation: IOSAcceptedOutputDeliveryPreparation
    ) -> IOSAcceptedHistoryAcceptanceWork {
        let phase = IOSAcceptedHistoryAcceptancePhase.deliveryAccepted(
            acceptance.record
        )
        switch acceptance.provenance {
        case .freshCurrentProcess:
            return .fresh(preparation, phase)
        case .preexisting:
            if acceptance.record.historyWrite?.state
                .mayReplayAbsentHistoryRow == true {
                return .replayableReplacement(phase)
            }
            return .preexisting(preparation, phase)
        }
    }

    static func repositoryBindingIsValid(
        _ binding: IOSAcceptedHistoryCoordinatorRepositoryBinding?,
        registration: IOSAcceptedHistoryCoordinatorRepositoryRegistration?,
        identityState: IOSAcceptedHistoryCoordinatorRepositoryIdentityState
    ) -> Bool {
        if let binding {
            _ = registration?.revalidate(expectedBinding: binding)
        }
        return !identityState.isConflicted
    }

    static func terminalResolution(
        for record: IOSAcceptedOutputDeliveryRecord
    ) -> IOSAcceptedHistoryAcceptanceResolution? {
        guard let historyWrite = record.historyWrite else {
            return .notRequested
        }
        return switch historyWrite.state {
        case .pending, .pendingReplacement: nil
        case .committed: .committed
        case .cancelled: .cancelled
        }
    }

    static func resume(
        _ initialWork: IOSAcceptedHistoryAcceptanceWork,
        policyStore: IOSHistoryPolicyStore,
        acceptedHistoryStore: IOSAcceptedHistoryStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        acceptanceState: IOSAcceptedHistoryAcceptanceOperationState
    ) async -> IOSAcceptedHistoryResumeOutcome {
        var work = initialWork

        while true {
            switch work.phase {
            case .deliveryAccepted(let record):
                do {
                    let authorization = try await deliveryStore
                        .authorizePendingHistoryWrite(
                            expected: IOSAcceptedOutputDeliveryExpectation(
                                record: record
                            )
                        )
                    work = work.replacingPhase(
                        .deliveryAuthorized(authorization)
                    )
                    await acceptanceState.store(work)
                } catch IOSAcceptedOutputDeliveryError.expired {
                    return await abandonExpired(
                        work,
                        deliveryStore: deliveryStore,
                        acceptanceState: acceptanceState
                    )
                } catch {
                    return pendingOutcome(for: work)
                }

            case .deliveryAuthorized(let authorization):
                do {
                    let disposition: IOSAcceptedHistoryPolicyDisposition
                    if let capture = work.freshPreparation?.historyCapture {
                        disposition = try await policyDisposition(
                            policyStore: policyStore,
                            expectedState: capture.policyReceipt.state,
                            markerGeneration: markerGeneration(
                                authorization
                            )
                        )
                    } else {
                        disposition = try await relaunchedPolicyDisposition(
                            policyStore: policyStore,
                            markerGeneration: markerGeneration(
                                authorization
                            )
                        )
                    }
                    switch disposition {
                    case .matching(let receipt):
                        work = work.replacingPhase(
                            .policyConfirmed(authorization, receipt)
                        )
                    case .invalidated(let receipt):
                        work = work.replacingPhase(
                            .invalidationConfirmed(authorization, receipt)
                        )
                    }
                    await acceptanceState.store(work)
                } catch {
                    return pendingOutcome(for: work)
                }

            case .policyConfirmed(let authorization, let policyReceipt):
                do {
                    let rowReceipt: IOSAcceptedHistoryRowReceipt
                    if authorization.record.historyWrite?.state
                        == .pendingReplacement {
                        rowReceipt = try await acceptedHistoryStore
                            .decideReplayableReplacement(
                                delivery: authorization,
                                policy: policyReceipt
                            )
                    } else if work.mayInsertAbsentHistoryRow {
                        rowReceipt = try await acceptedHistoryStore.decideUpsert(
                            delivery: authorization,
                            policy: policyReceipt
                        )
                    } else {
                        rowReceipt = try await acceptedHistoryStore
                            .confirmMembership(
                                delivery: authorization,
                                policy: policyReceipt
                            )
                    }
                    work = work.replacingPhase(
                        .rowDecided(
                            authorization,
                            policyReceipt,
                            rowReceipt
                        )
                    )
                    await acceptanceState.store(work)
                } catch IOSAcceptedHistoryError.expired {
                    return await abandonExpired(
                        work,
                        deliveryStore: deliveryStore,
                        acceptanceState: acceptanceState
                    )
                } catch {
                    return pendingOutcome(for: work)
                }

            case .rowDecided(
                let authorization,
                let firstPolicyReceipt,
                let rowReceipt
            ):
                do {
                    let disposition = try await policyDisposition(
                        policyStore: policyStore,
                        expectedState: firstPolicyReceipt.state,
                        markerGeneration: markerGeneration(authorization)
                    )
                    switch disposition {
                    case .matching:
                        work = work.replacingPhase(
                            .policyRevalidated(authorization, rowReceipt)
                        )
                    case .invalidated(let receipt):
                        work = work.replacingPhase(
                            .invalidationConfirmed(authorization, receipt)
                        )
                    }
                    await acceptanceState.store(work)
                } catch {
                    return pendingOutcome(for: work)
                }

            case .policyRevalidated(let authorization, let rowReceipt):
                do {
                    let committed = try await deliveryStore.commitHistoryWrite(
                        authorization: authorization,
                        rowReceipt: rowReceipt
                    )
                    return IOSAcceptedHistoryResumeOutcome(
                        result: IOSAcceptedHistoryAcceptanceResult(
                            deliveryRecord: committed,
                            resolution: .committed
                        ),
                        didAbandon: false,
                        wasSuperseded: false
                    )
                } catch IOSAcceptedOutputDeliveryError.expired {
                    return await abandonExpired(
                        work,
                        deliveryStore: deliveryStore,
                        acceptanceState: acceptanceState
                    )
                } catch {
                    return pendingOutcome(for: work)
                }

            case .invalidationConfirmed(
                let authorization,
                let invalidationReceipt
            ):
                do {
                    let cancelled = try await deliveryStore.cancelHistoryWrite(
                        authorization: authorization,
                        policyInvalidationReceipt: invalidationReceipt
                    )
                    return IOSAcceptedHistoryResumeOutcome(
                        result: IOSAcceptedHistoryAcceptanceResult(
                            deliveryRecord: cancelled,
                            resolution: .cancelled
                        ),
                        didAbandon: false,
                        wasSuperseded: false
                    )
                } catch IOSAcceptedOutputDeliveryError.expired {
                    return await abandonExpired(
                        work,
                        deliveryStore: deliveryStore,
                        acceptanceState: acceptanceState
                    )
                } catch {
                    return pendingOutcome(for: work)
                }

            case .abandoningExpired:
                return await observeExpiredAbandonment(
                    work,
                    deliveryStore: deliveryStore,
                    acceptanceState: acceptanceState
                )

            case .confirmingExpired(let observation):
                return await confirmExpiredAbandonment(
                    work,
                    observation: observation,
                    deliveryStore: deliveryStore,
                    acceptanceState: acceptanceState
                )

            case .removingExpired(let authorization):
                return await continueExpiredAbandonment(
                    work,
                    authorization: authorization,
                    deliveryStore: deliveryStore,
                    acceptanceState: acceptanceState
                )
            }
        }
    }

    static func recoverAfterProcessLoss(
        policyStore: IOSHistoryPolicyStore,
        acceptedHistoryStore: IOSAcceptedHistoryStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        acceptanceState: IOSAcceptedHistoryAcceptanceOperationState,
        mayReloadAfterSupersession: Bool = true
    ) async -> IOSAcceptedHistoryRecoveryOutcome {
        let observation: IOSAcceptedOutputDeliveryObservation?
        do {
            observation = try await deliveryStore.load()
        } catch {
            return IOSAcceptedHistoryRecoveryOutcome(
                resolution: .pendingLocalRecovery,
                observedDelivery: false
            )
        }

        guard let observation else {
            return IOSAcceptedHistoryRecoveryOutcome(
                resolution: nil,
                observedDelivery: false
            )
        }
        switch observation {
        case .clockRollbackAmbiguous:
            return IOSAcceptedHistoryRecoveryOutcome(
                resolution: .pendingLocalRecovery,
                observedDelivery: true
            )
        case .expired(let expectation):
            return await recoverExpiredAfterProcessLoss(
                expectation: expectation,
                policyStore: policyStore,
                acceptedHistoryStore: acceptedHistoryStore,
                deliveryStore: deliveryStore,
                acceptanceState: acceptanceState,
                mayReloadAfterSupersession: mayReloadAfterSupersession
            )
        case .active(let record):
            let authorization: IOSAcceptedOutputDeliveryAuthorization
            do {
                authorization = try await deliveryStore
                    .confirmActiveHistoryRecovery(
                        expected: IOSAcceptedOutputDeliveryExpectation(
                            record: record
                        )
                    )
            } catch IOSAcceptedOutputDeliveryError.expired {
                let work = IOSAcceptedHistoryAcceptanceWork.relaunched(
                    .deliveryAccepted(record)
                )
                await acceptanceState.store(work)
                let abandonment = await abandonExpired(
                    work,
                    deliveryStore: deliveryStore,
                    acceptanceState: acceptanceState
                )
                if abandonment.wasSuperseded,
                   mayReloadAfterSupersession {
                    return await recoverAfterProcessLoss(
                        policyStore: policyStore,
                        acceptedHistoryStore: acceptedHistoryStore,
                        deliveryStore: deliveryStore,
                        acceptanceState: acceptanceState,
                        mayReloadAfterSupersession: false
                    ).preservingObservedDelivery()
                }
                return IOSAcceptedHistoryRecoveryOutcome(
                    resolution: abandonment.didAbandon
                        ? nil
                        : .pendingLocalRecovery,
                    observedDelivery: true
                )
            } catch {
                return IOSAcceptedHistoryRecoveryOutcome(
                    resolution: .pendingLocalRecovery,
                    observedDelivery: true
                )
            }

            if let terminal = terminalResolution(
                for: authorization.record
            ) {
                return IOSAcceptedHistoryRecoveryOutcome(
                    resolution: terminal,
                    observedDelivery: true
                )
            }
            let work: IOSAcceptedHistoryAcceptanceWork =
                if authorization.record.historyWrite?.state
                    .mayReplayAbsentHistoryRow == true {
                    .replayableReplacement(
                        .deliveryAuthorized(authorization)
                    )
                } else {
                    .relaunched(.deliveryAuthorized(authorization))
                }
            await acceptanceState.store(work)
            let resumeOutcome = await resume(
                work,
                policyStore: policyStore,
                acceptedHistoryStore: acceptedHistoryStore,
                deliveryStore: deliveryStore,
                acceptanceState: acceptanceState
            )
            if resumeOutcome.wasSuperseded,
               mayReloadAfterSupersession {
                return await recoverAfterProcessLoss(
                    policyStore: policyStore,
                    acceptedHistoryStore: acceptedHistoryStore,
                    deliveryStore: deliveryStore,
                    acceptanceState: acceptanceState,
                    mayReloadAfterSupersession: false
                ).preservingObservedDelivery()
            }
            return IOSAcceptedHistoryRecoveryOutcome(
                resolution: resumeOutcome.wasSuperseded
                    ? .pendingLocalRecovery
                    : (resumeOutcome.didAbandon
                        ? nil
                        : resumeOutcome.result.resolution),
                observedDelivery: true
            )
        }
    }

    static func markerGeneration(
        _ authorization: IOSAcceptedOutputDeliveryAuthorization
    ) throws -> Int64 {
        guard let marker = authorization.record.historyWrite,
              marker.state.isPendingDecision else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        return marker.policyGeneration
    }

    static func policyDisposition(
        policyStore: IOSHistoryPolicyStore,
        expectedState: IOSHistoryPolicyState,
        markerGeneration: Int64
    ) async throws -> IOSAcceptedHistoryPolicyDisposition {
        do {
            let receipt = try await policyStore.confirm(
                expected: IOSHistoryPolicyExpectation(state: expectedState)
            )
            return try classify(
                receipt,
                markerGeneration: markerGeneration
            )
        } catch IOSHistoryPolicyError.compareAndSwapFailed {
            return try await relaunchedPolicyDisposition(
                policyStore: policyStore,
                markerGeneration: markerGeneration
            )
        }
    }

    static func relaunchedPolicyDisposition(
        policyStore: IOSHistoryPolicyStore,
        markerGeneration: Int64
    ) async throws -> IOSAcceptedHistoryPolicyDisposition {
        guard let state = try await policyStore.load() else {
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }
        let receipt = try await policyStore.confirm(
            expected: IOSHistoryPolicyExpectation(state: state)
        )
        return try classify(
            receipt,
            markerGeneration: markerGeneration
        )
    }

    static func classify(
        _ receipt: IOSHistoryPolicyReceipt,
        markerGeneration: Int64
    ) throws -> IOSAcceptedHistoryPolicyDisposition {
        if receipt.state.policyGeneration == markerGeneration,
           receipt.state.historyEnabled {
            return .matching(receipt)
        }
        if receipt.state.policyGeneration > markerGeneration {
            return .invalidated(receipt)
        }
        throw IOSHistoryPolicyError.compareAndSwapFailed
    }

    static func pendingOutcome(
        for work: IOSAcceptedHistoryAcceptanceWork
    ) -> IOSAcceptedHistoryResumeOutcome {
        IOSAcceptedHistoryResumeOutcome(
            result: IOSAcceptedHistoryAcceptanceResult(
                deliveryRecord: work.phase.deliveryRecord,
                resolution: .pendingLocalRecovery
            ),
            didAbandon: false,
            wasSuperseded: false
        )
    }

    static func abandonExpired(
        _ work: IOSAcceptedHistoryAcceptanceWork,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        acceptanceState: IOSAcceptedHistoryAcceptanceOperationState
    ) async -> IOSAcceptedHistoryResumeOutcome {
        let abandoning = work.replacingPhase(
            .abandoningExpired(work.phase.deliveryRecord)
        )
        await acceptanceState.store(abandoning)
        return await observeExpiredAbandonment(
            abandoning,
            deliveryStore: deliveryStore,
            acceptanceState: acceptanceState
        )
    }

    static func observeExpiredAbandonment(
        _ work: IOSAcceptedHistoryAcceptanceWork,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        acceptanceState: IOSAcceptedHistoryAcceptanceOperationState
    ) async -> IOSAcceptedHistoryResumeOutcome {
        do {
            let observation = try await deliveryStore
                .observeExpiredHistoryAbandonment(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: work.phase.deliveryRecord
                )
            )
            switch observation {
            case .alreadyAbsent:
                await acceptanceState.clear()
                return abandonedOutcome(for: work)
            case .observed(let observed):
                let confirming = work.replacingPhase(
                    .confirmingExpired(observed)
                )
                await acceptanceState.store(confirming)
                return await confirmExpiredAbandonment(
                    confirming,
                    observation: observed,
                    deliveryStore: deliveryStore,
                    acceptanceState: acceptanceState
                )
            }
        } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
            await acceptanceState.clear()
            return supersededOutcome(for: work)
        } catch {
            return pendingOutcome(for: work)
        }
    }

    static func confirmExpiredAbandonment(
        _ work: IOSAcceptedHistoryAcceptanceWork,
        observation: IOSAcceptedOutputDeliveryExpiredObservation,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        acceptanceState: IOSAcceptedHistoryAcceptanceOperationState
    ) async -> IOSAcceptedHistoryResumeOutcome {
        do {
            switch try await deliveryStore.confirmExpiredHistoryAbandonment(
                observation: observation
            ) {
            case .alreadyAbsent:
                await acceptanceState.clear()
                return abandonedOutcome(for: work)
            case .authorized(let authorization):
                let removing = work.replacingPhase(
                    .removingExpired(authorization)
                )
                await acceptanceState.store(removing)
                return await continueExpiredAbandonment(
                    removing,
                    authorization: authorization,
                    deliveryStore: deliveryStore,
                    acceptanceState: acceptanceState
                )
            }
        } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
            await acceptanceState.clear()
            return supersededOutcome(for: work)
        } catch {
            return pendingOutcome(for: work)
        }
    }

    static func continueExpiredAbandonment(
        _ work: IOSAcceptedHistoryAcceptanceWork,
        authorization: IOSAcceptedOutputDeliveryExpiredRemovalAuthorization,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        acceptanceState: IOSAcceptedHistoryAcceptanceOperationState
    ) async -> IOSAcceptedHistoryResumeOutcome {
        do {
            _ = try await deliveryStore.continueExpiredHistoryAbandonment(
                authorization: authorization
            )
            await acceptanceState.clear()
            return abandonedOutcome(for: work)
        } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
            await acceptanceState.clear()
            return supersededOutcome(for: work)
        } catch {
            return pendingOutcome(for: work)
        }
    }

    static func abandonedOutcome(
        for work: IOSAcceptedHistoryAcceptanceWork
    ) -> IOSAcceptedHistoryResumeOutcome {
        IOSAcceptedHistoryResumeOutcome(
            result: IOSAcceptedHistoryAcceptanceResult(
                deliveryRecord: work.phase.deliveryRecord,
                resolution: .pendingLocalRecovery
            ),
            didAbandon: true,
            wasSuperseded: false
        )
    }

    static func supersededOutcome(
        for work: IOSAcceptedHistoryAcceptanceWork
    ) -> IOSAcceptedHistoryResumeOutcome {
        IOSAcceptedHistoryResumeOutcome(
            result: IOSAcceptedHistoryAcceptanceResult(
                deliveryRecord: work.phase.deliveryRecord,
                resolution: .pendingLocalRecovery
            ),
            didAbandon: false,
            wasSuperseded: true
        )
    }

    static func recoverExpiredAfterProcessLoss(
        expectation: IOSAcceptedOutputDeliveryExpectation,
        policyStore: IOSHistoryPolicyStore,
        acceptedHistoryStore: IOSAcceptedHistoryStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        acceptanceState: IOSAcceptedHistoryAcceptanceOperationState,
        mayReloadAfterSupersession: Bool
    ) async -> IOSAcceptedHistoryRecoveryOutcome {
        do {
            switch try await deliveryStore.observeExpiredHistoryAbandonment(
                expected: expectation
            ) {
            case .alreadyAbsent:
                return IOSAcceptedHistoryRecoveryOutcome(
                    resolution: nil,
                    observedDelivery: true
                )
            case .observed(let observation):
                let work = IOSAcceptedHistoryAcceptanceWork.relaunched(
                    .confirmingExpired(observation)
                )
                await acceptanceState.store(work)
                let outcome = await confirmExpiredAbandonment(
                    work,
                    observation: observation,
                    deliveryStore: deliveryStore,
                    acceptanceState: acceptanceState
                )
                if outcome.wasSuperseded,
                   mayReloadAfterSupersession {
                    return await recoverAfterProcessLoss(
                        policyStore: policyStore,
                        acceptedHistoryStore: acceptedHistoryStore,
                        deliveryStore: deliveryStore,
                        acceptanceState: acceptanceState,
                        mayReloadAfterSupersession: false
                    ).preservingObservedDelivery()
                }
                return IOSAcceptedHistoryRecoveryOutcome(
                    resolution: outcome.didAbandon
                        ? nil
                        : .pendingLocalRecovery,
                    observedDelivery: true
                )
            }
        } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            where mayReloadAfterSupersession {
            return await recoverAfterProcessLoss(
                policyStore: policyStore,
                acceptedHistoryStore: acceptedHistoryStore,
                deliveryStore: deliveryStore,
                acceptanceState: acceptanceState,
                mayReloadAfterSupersession: false
            ).preservingObservedDelivery()
        } catch {
            return IOSAcceptedHistoryRecoveryOutcome(
                resolution: .pendingLocalRecovery,
                observedDelivery: true
            )
        }
    }
}
