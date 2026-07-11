import Foundation

/// Reports only whether app-private cleanup finished. Policy content and
/// History payloads never cross this boundary.
public enum IOSHistoryPolicyCleanupDisposition: Equatable, Sendable {
    case complete
    case pendingLocalRecovery
}

extension IOSHistoryPolicyCleanupDisposition:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSHistoryPolicyCleanupDisposition(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSHistoryPolicyCutoverCommand: Equatable, Sendable {
    case clear
    case setEnabled(Bool)
}

extension IOSHistoryPolicyCutoverCommand:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSHistoryPolicyCutoverCommand(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSHistoryPolicyCutoverPhase: Equatable, Sendable {
    case establishingPolicy
    case policyCaptured(IOSHistoryPolicyReceipt)
    case pruningAcceptedRows(IOSHistoryPolicyReceipt)
    case recoveringOutbox(IOSHistoryPolicyReceipt)
    case inspectingStandaloneDelivery(IOSHistoryPolicyReceipt)
    case awaitingExpiredDeliveryAbandonment(
        IOSHistoryPolicyReceipt,
        IOSAcceptedOutputDeliveryExpiredObservation
    )
    case cancellingStandaloneDelivery(
        IOSHistoryPolicyReceipt,
        IOSAcceptedOutputDeliveryAuthorization
    )

    var crossedLogicalBoundary: Bool {
        switch self {
        case .establishingPolicy, .policyCaptured:
            false
        case .pruningAcceptedRows, .recoveringOutbox,
             .inspectingStandaloneDelivery,
             .awaitingExpiredDeliveryAbandonment,
             .cancellingStandaloneDelivery:
            true
        }
    }

    var expiredDeliveryAbandonmentObservation:
        IOSAcceptedOutputDeliveryExpiredObservation? {
        guard case .awaitingExpiredDeliveryAbandonment(
            _,
            let observation
        ) = self else {
            return nil
        }
        return observation
    }
}

extension IOSHistoryPolicyCutoverPhase:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSHistoryPolicyCutoverPhase(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSHistoryPolicyCutoverWork: Equatable, Sendable {
    let ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity
    let command: IOSHistoryPolicyCutoverCommand?
    let phase: IOSHistoryPolicyCutoverPhase

    func replacingPhase(_ phase: IOSHistoryPolicyCutoverPhase) -> Self {
        Self(
            ownerIdentity: ownerIdentity,
            command: command,
            phase: phase
        )
    }
}

extension IOSHistoryPolicyCutoverWork:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSHistoryPolicyCutoverWork(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

actor IOSHistoryPolicyCutoverOperationState {
    private var work: IOSHistoryPolicyCutoverWork?

    func current() -> IOSHistoryPolicyCutoverWork? { work }

    func store(_ work: IOSHistoryPolicyCutoverWork) {
        self.work = work
    }

    func clear() {
        work = nil
    }

    func expiredDeliveryAbandonmentObservation(
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity
    ) -> IOSAcceptedOutputDeliveryExpiredObservation? {
        guard work?.ownerIdentity == ownerIdentity else { return nil }
        return work?.phase.expiredDeliveryAbandonmentObservation
    }
}

public extension IOSAcceptedHistoryCoordinator {
    /// Advances the canonical History generation without exposing a partial
    /// user-facing Clear History implementation.
    func clearHistoryPolicy()
        async throws -> IOSHistoryPolicyCleanupDisposition {
        try await performHistoryPolicyCommand(.clear)
    }

    /// Changes the canonical History policy. Repeating the current value is a
    /// durably confirmed no-op and never advances the generation.
    func setHistoryEnabled(
        _ enabled: Bool
    ) async throws -> IOSHistoryPolicyCleanupDisposition {
        try await performHistoryPolicyCommand(.setEnabled(enabled))
    }

    /// Reconciles only app-private state under the already durable policy. It
    /// never repeats a Clear, advances a generation, or calls a provider.
    func recoverHistoryPolicyCleanup()
        async throws -> IOSHistoryPolicyCleanupDisposition {
        let policyStore = policyStore
        let acceptedHistoryStore = acceptedHistoryStore
        let failedHistoryStore = failedHistoryStore
        let outboxStore = outboxStore
        let deliveryStore = deliveryStore
        let baselineRecoveryState = baselineRecoveryState
        let acceptanceState = acceptanceState
        let pendingReplacementState = pendingReplacementState
        let workerState = outboxWorkerState
        let cutoverState = policyCutoverState
        let ownerIdentity = ownerIdentity
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration

        do {
            return try await operationGate.perform {
                let retainedAtEntry = await cutoverState.current()
                let repositoryBinding = repositoryRegistration?.revalidate()
                if repositoryIdentityState.isConflicted {
                    if retainedAtEntry?.ownerIdentity == ownerIdentity,
                       retainedAtEntry?.command != nil,
                       retainedAtEntry?.phase.crossedLogicalBoundary == true {
                        return .pendingLocalRecovery
                    }
                    if retainedAtEntry?.ownerIdentity == ownerIdentity,
                       retainedAtEntry?.phase.crossedLogicalBoundary == false {
                        await cutoverState.clear()
                    }
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                let hasAcceptanceWork = await acceptanceState.current() != nil
                let hasPendingReplacementWork = await pendingReplacementState
                    .current() != nil

                let disposition: IOSHistoryPolicyCleanupDisposition
                if let retained = await cutoverState.current() {
                    if retained.ownerIdentity != ownerIdentity {
                        disposition = .pendingLocalRecovery
                    } else if hasAcceptanceWork
                        || hasPendingReplacementWork
                        || (!retained.phase.crossedLogicalBoundary
                            && retained.command != nil) {
                        disposition = .pendingLocalRecovery
                    } else {
                        do {
                            disposition = try await Self.resumePolicyCutoverWork(
                                retained,
                                policyStore: policyStore,
                                acceptedHistoryStore: acceptedHistoryStore,
                                failedHistoryStore: failedHistoryStore,
                                outboxStore: outboxStore,
                                deliveryStore: deliveryStore,
                                baselineRecoveryState: baselineRecoveryState,
                                workerState: workerState,
                                cutoverState: cutoverState,
                                ownerIdentity: ownerIdentity,
                                repositoryBinding: repositoryBinding,
                                repositoryRegistration: repositoryRegistration,
                                repositoryIdentityState: repositoryIdentityState
                            )
                        } catch {
                            disposition = .pendingLocalRecovery
                        }
                    }
                } else if hasAcceptanceWork || hasPendingReplacementWork {
                    disposition = .pendingLocalRecovery
                } else if await workerState.current() != nil {
                    if await deliveryStore
                        .hasRetainedHistoryWorkForPolicyCutover() {
                        disposition = .pendingLocalRecovery
                    } else {
                        do {
                            let workerResolution = try await Self
                                .recoverOneOutboxHead(
                                    policyStore: policyStore,
                                    acceptedHistoryStore: acceptedHistoryStore,
                                    outboxStore: outboxStore,
                                    deliveryStore: deliveryStore,
                                    workerState: workerState,
                                    ownerIdentity: ownerIdentity
                                )
                            disposition = workerResolution == .noWork
                                ? .complete
                                : .pendingLocalRecovery
                        } catch {
                            disposition = .pendingLocalRecovery
                        }
                    }
                } else if await deliveryStore
                    .hasRetainedHistoryWorkForPolicyCutover() {
                    disposition = .pendingLocalRecovery
                } else {
                    let initial = IOSHistoryPolicyCutoverWork(
                        ownerIdentity: ownerIdentity,
                        command: nil,
                        phase: .establishingPolicy
                    )
                    await cutoverState.store(initial)
                    do {
                        disposition = try await Self.resumePolicyCutoverWork(
                            initial,
                            policyStore: policyStore,
                            acceptedHistoryStore: acceptedHistoryStore,
                            failedHistoryStore: failedHistoryStore,
                            outboxStore: outboxStore,
                            deliveryStore: deliveryStore,
                            baselineRecoveryState: baselineRecoveryState,
                            workerState: workerState,
                            cutoverState: cutoverState,
                            ownerIdentity: ownerIdentity,
                            repositoryBinding: repositoryBinding,
                            repositoryRegistration: repositoryRegistration,
                            repositoryIdentityState: repositoryIdentityState
                        )
                    } catch {
                        disposition = .pendingLocalRecovery
                    }
                }

                do {
                    try Self.requireStablePolicyRepository(
                        repositoryBinding,
                        registration: repositoryRegistration,
                        identityState: repositoryIdentityState
                    )
                } catch IOSAcceptedHistoryCoordinatorError
                    .repositoryIdentityConflict {
                    let retainedAfterWork = await cutoverState.current()
                    if retainedAfterWork?.command != nil,
                       retainedAfterWork?.phase.crossedLogicalBoundary == true {
                        return .pendingLocalRecovery
                    }
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                if disposition == .complete {
                    await cutoverState.clear()
                }
                return disposition
            }
        } catch IOSPersistenceOperationGate.AcquisitionError
            .cancelledBeforeLease {
            throw IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError
            .reentrantOperation {
            throw IOSAcceptedHistoryCoordinatorError.reentrantOperation
        }
    }
}

private extension IOSAcceptedHistoryCoordinator {
    func performHistoryPolicyCommand(
        _ command: IOSHistoryPolicyCutoverCommand
    ) async throws -> IOSHistoryPolicyCleanupDisposition {
        let policyStore = policyStore
        let acceptedHistoryStore = acceptedHistoryStore
        let failedHistoryStore = failedHistoryStore
        let outboxStore = outboxStore
        let deliveryStore = deliveryStore
        let baselineRecoveryState = baselineRecoveryState
        let acceptanceState = acceptanceState
        let pendingReplacementState = pendingReplacementState
        let workerState = outboxWorkerState
        let cutoverState = policyCutoverState
        let ownerIdentity = ownerIdentity
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration

        do {
            return try await operationGate.perform {
                let retainedAtEntry = await cutoverState.current()
                let repositoryBinding = repositoryRegistration?.revalidate()
                if repositoryIdentityState.isConflicted {
                    if retainedAtEntry?.ownerIdentity == ownerIdentity,
                       retainedAtEntry?.command == command,
                       retainedAtEntry?.phase.crossedLogicalBoundary == true {
                        return .pendingLocalRecovery
                    }
                    if retainedAtEntry?.ownerIdentity == ownerIdentity,
                       retainedAtEntry?.phase.crossedLogicalBoundary == false {
                        await cutoverState.clear()
                    }
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }

                let work: IOSHistoryPolicyCutoverWork
                if let retained = await cutoverState.current() {
                    let hasDeliveryWork = await deliveryStore
                        .hasRetainedHistoryWorkForPolicyCutover()
                    guard retained.ownerIdentity == ownerIdentity,
                          retained.command == command else {
                        throw IOSHistoryPolicyError.commitUncertain
                    }
                    let hasAcceptanceWork = await acceptanceState.current()
                        != nil
                    let hasPendingReplacementWork = await pendingReplacementState
                        .current() != nil
                    let hasWorkerWork = await workerState.current() != nil
                    if retained.phase.crossedLogicalBoundary {
                        if hasAcceptanceWork || hasPendingReplacementWork {
                            return .pendingLocalRecovery
                        }
                        switch retained.phase {
                        case .recoveringOutbox:
                            if hasDeliveryWork && !hasWorkerWork {
                                return .pendingLocalRecovery
                            }
                        case .cancellingStandaloneDelivery:
                            if hasWorkerWork {
                                return .pendingLocalRecovery
                            }
                        case .pruningAcceptedRows,
                             .inspectingStandaloneDelivery,
                             .awaitingExpiredDeliveryAbandonment:
                            if hasWorkerWork || hasDeliveryWork {
                                return .pendingLocalRecovery
                            }
                        case .establishingPolicy, .policyCaptured:
                            return .pendingLocalRecovery
                        }
                    } else if hasAcceptanceWork
                        || hasPendingReplacementWork
                        || hasWorkerWork
                        || hasDeliveryWork {
                        throw IOSHistoryPolicyError.commitUncertain
                    }
                    work = retained
                } else {
                    guard await acceptanceState.current() == nil,
                          await pendingReplacementState.current() == nil,
                          await workerState.current() == nil,
                          await deliveryStore
                            .hasRetainedHistoryWorkForPolicyCutover()
                            == false else {
                        throw IOSHistoryPolicyError.commitUncertain
                    }
                    work = IOSHistoryPolicyCutoverWork(
                        ownerIdentity: ownerIdentity,
                        command: command,
                        phase: .establishingPolicy
                    )
                    await cutoverState.store(work)
                }

                let disposition = try await Self.resumePolicyCutoverWork(
                    work,
                    policyStore: policyStore,
                    acceptedHistoryStore: acceptedHistoryStore,
                    failedHistoryStore: failedHistoryStore,
                    outboxStore: outboxStore,
                    deliveryStore: deliveryStore,
                    baselineRecoveryState: baselineRecoveryState,
                    workerState: workerState,
                    cutoverState: cutoverState,
                    ownerIdentity: ownerIdentity,
                    repositoryBinding: repositoryBinding,
                    repositoryRegistration: repositoryRegistration,
                    repositoryIdentityState: repositoryIdentityState
                )
                do {
                    try Self.requireStablePolicyRepository(
                        repositoryBinding,
                        registration: repositoryRegistration,
                        identityState: repositoryIdentityState
                    )
                } catch IOSAcceptedHistoryCoordinatorError
                    .repositoryIdentityConflict {
                    let retainedAfterWork = await cutoverState.current()
                    if retainedAfterWork?.command != nil,
                       retainedAfterWork?.phase.crossedLogicalBoundary == true {
                        return .pendingLocalRecovery
                    }
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                if disposition == .complete {
                    await cutoverState.clear()
                }
                return disposition
            }
        } catch IOSPersistenceOperationGate.AcquisitionError
            .cancelledBeforeLease {
            throw IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError
            .reentrantOperation {
            throw IOSAcceptedHistoryCoordinatorError.reentrantOperation
        }
    }

    static func resumePolicyCutoverWork(
        _ initialWork: IOSHistoryPolicyCutoverWork,
        policyStore: IOSHistoryPolicyStore,
        acceptedHistoryStore: IOSAcceptedHistoryStore,
        failedHistoryStore: IOSFailedHistoryStore,
        outboxStore: IOSAcceptedHistoryOutboxStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        baselineRecoveryState: IOSAcceptedHistoryBaselineRecoveryState,
        workerState: IOSAcceptedHistoryOutboxWorkerOperationState,
        cutoverState: IOSHistoryPolicyCutoverOperationState,
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding?,
        repositoryRegistration:
            IOSAcceptedHistoryCoordinatorRepositoryRegistration?,
        repositoryIdentityState:
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState
    ) async throws -> IOSHistoryPolicyCleanupDisposition {
        var work = initialWork

        while true {
            guard validatePolicyCutoverWork(
                work,
                ownerIdentity: ownerIdentity,
                deliveryStoreIdentity: deliveryStore.storeIdentity
            ) else {
                guard !work.phase.crossedLogicalBoundary else {
                    return .pendingLocalRecovery
                }
                await cutoverState.clear()
                throw IOSHistoryPolicyError.compareAndSwapFailed
            }

            switch work.phase {
            case .establishingPolicy:
                if await deliveryStore
                    .hasRetainedHistoryWorkForPolicyCutover() {
                    guard work.command == nil else {
                        throw IOSHistoryPolicyError.commitUncertain
                    }
                    return .pendingLocalRecovery
                }
                do {
                    let receipt = try await confirmedPolicyReceipt(
                        policyStore: policyStore,
                        acceptedHistoryStore: acceptedHistoryStore,
                        failedHistoryStore: failedHistoryStore,
                        outboxStore: outboxStore,
                        deliveryStore: deliveryStore,
                        baselineRecoveryState: baselineRecoveryState
                    )
                    do {
                        try requireStablePolicyRepository(
                            repositoryBinding,
                            registration: repositoryRegistration,
                            identityState: repositoryIdentityState
                        )
                    } catch IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict {
                        await cutoverState.clear()
                        throw IOSAcceptedHistoryCoordinatorError
                            .repositoryIdentityConflict
                    }
                    if work.command == nil {
                        work = work.replacingPhase(
                            .pruningAcceptedRows(receipt)
                        )
                    } else {
                        work = work.replacingPhase(.policyCaptured(receipt))
                    }
                    await cutoverState.store(work)
                } catch CaptureOperationError.baselineCommitUncertain {
                    await baselineRecoveryState.requireRecovery()
                    throw IOSHistoryPolicyError.commitUncertain
                } catch CaptureOperationError.definitiveBaselineConflict {
                    await baselineRecoveryState.clear()
                    await cutoverState.clear()
                    throw IOSHistoryPolicyError.compareAndSwapFailed
                } catch IOSHistoryPolicyError.compareAndSwapFailed {
                    await cutoverState.clear()
                    throw IOSHistoryPolicyError.compareAndSwapFailed
                } catch IOSHistoryPolicyError.revisionOverflow {
                    await cutoverState.clear()
                    throw IOSHistoryPolicyError.revisionOverflow
                }

            case .policyCaptured(let receipt):
                guard let command = work.command else {
                    await cutoverState.clear()
                    throw IOSHistoryPolicyError.compareAndSwapFailed
                }
                guard await deliveryStore
                    .hasRetainedHistoryWorkForPolicyCutover() == false else {
                    throw IOSHistoryPolicyError.commitUncertain
                }
                do {
                    let committed = try await applyPolicyCommand(
                        command,
                        policyStore: policyStore,
                        receipt: receipt
                    )
                    work = work.replacingPhase(
                        .pruningAcceptedRows(committed)
                    )
                    await cutoverState.store(work)
                    do {
                        try requireStablePolicyRepository(
                            repositoryBinding,
                            registration: repositoryRegistration,
                            identityState: repositoryIdentityState
                        )
                    } catch IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict {
                        return .pendingLocalRecovery
                    }
                } catch IOSHistoryPolicyError.compareAndSwapFailed {
                    await cutoverState.clear()
                    throw IOSHistoryPolicyError.compareAndSwapFailed
                } catch IOSHistoryPolicyError.revisionOverflow {
                    await cutoverState.clear()
                    throw IOSHistoryPolicyError.revisionOverflow
                }

            case .pruningAcceptedRows,
                 .recoveringOutbox,
                 .inspectingStandaloneDelivery,
                 .awaitingExpiredDeliveryAbandonment,
                 .cancellingStandaloneDelivery:
                return await resumePolicyCleanup(
                    work,
                    policyStore: policyStore,
                    acceptedHistoryStore: acceptedHistoryStore,
                    outboxStore: outboxStore,
                    deliveryStore: deliveryStore,
                    workerState: workerState,
                    cutoverState: cutoverState,
                    ownerIdentity: ownerIdentity,
                    repositoryBinding: repositoryBinding,
                    repositoryRegistration: repositoryRegistration,
                    repositoryIdentityState: repositoryIdentityState
                )
            }
        }
    }

    static func confirmedPolicyReceipt(
        policyStore: IOSHistoryPolicyStore,
        acceptedHistoryStore: IOSAcceptedHistoryStore,
        failedHistoryStore: IOSFailedHistoryStore,
        outboxStore: IOSAcceptedHistoryOutboxStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        baselineRecoveryState: IOSAcceptedHistoryBaselineRecoveryState
    ) async throws -> IOSHistoryPolicyReceipt {
        let recoveryRequired = await baselineRecoveryState.value()
        let receipt: IOSHistoryPolicyReceipt
        if recoveryRequired {
            receipt = try await establishGuardedBaseline(
                policyStore: policyStore,
                acceptedHistoryStore: acceptedHistoryStore,
                failedHistoryStore: failedHistoryStore,
                outboxStore: outboxStore,
                deliveryStore: deliveryStore,
                isRecovery: true
            )
        } else if let current = try await policyStore.load() {
            receipt = try await policyStore.confirm(
                expected: IOSHistoryPolicyExpectation(state: current)
            )
        } else {
            receipt = try await establishGuardedBaseline(
                policyStore: policyStore,
                acceptedHistoryStore: acceptedHistoryStore,
                failedHistoryStore: failedHistoryStore,
                outboxStore: outboxStore,
                deliveryStore: deliveryStore,
                isRecovery: false
            )
        }
        await baselineRecoveryState.clear()
        return receipt
    }

    static func applyPolicyCommand(
        _ command: IOSHistoryPolicyCutoverCommand,
        policyStore: IOSHistoryPolicyStore,
        receipt: IOSHistoryPolicyReceipt
    ) async throws -> IOSHistoryPolicyReceipt {
        switch command {
        case .clear:
            return try await policyStore.clear(using: receipt)
        case .setEnabled(let enabled):
            return try await policyStore.setHistoryEnabled(
                enabled,
                using: receipt
            )
        }
    }

    static func resumePolicyCleanup(
        _ initialWork: IOSHistoryPolicyCutoverWork,
        policyStore: IOSHistoryPolicyStore,
        acceptedHistoryStore: IOSAcceptedHistoryStore,
        outboxStore: IOSAcceptedHistoryOutboxStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        workerState: IOSAcceptedHistoryOutboxWorkerOperationState,
        cutoverState: IOSHistoryPolicyCutoverOperationState,
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding?,
        repositoryRegistration:
            IOSAcceptedHistoryCoordinatorRepositoryRegistration?,
        repositoryIdentityState:
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState
    ) async -> IOSHistoryPolicyCleanupDisposition {
        var work = initialWork

        while true {
            do {
                try requireStablePolicyRepository(
                    repositoryBinding,
                    registration: repositoryRegistration,
                    identityState: repositoryIdentityState
                )
            } catch {
                return .pendingLocalRecovery
            }
            guard validatePolicyCutoverWork(
                work,
                ownerIdentity: ownerIdentity,
                deliveryStoreIdentity: deliveryStore.storeIdentity
            ) else {
                if !work.phase.crossedLogicalBoundary {
                    await cutoverState.clear()
                }
                return .pendingLocalRecovery
            }

            switch work.phase {
            case .pruningAcceptedRows(let receipt):
                if await deliveryStore
                    .hasRetainedHistoryWorkForPolicyCutover() {
                    return .pendingLocalRecovery
                }
                do {
                    try await acceptedHistoryStore.pruneInvalidatedRows(
                        using: receipt
                    )
                    work = work.replacingPhase(.recoveringOutbox(receipt))
                    await cutoverState.store(work)
                } catch {
                    return .pendingLocalRecovery
                }

            case .recoveringOutbox(let receipt):
                if await workerState.current() == nil,
                   await deliveryStore
                    .hasRetainedHistoryWorkForPolicyCutover() {
                    return .pendingLocalRecovery
                }
                do {
                    let resolution = try await recoverOneOutboxHead(
                        policyStore: policyStore,
                        acceptedHistoryStore: acceptedHistoryStore,
                        outboxStore: outboxStore,
                        deliveryStore: deliveryStore,
                        workerState: workerState,
                        ownerIdentity: ownerIdentity
                    )
                    switch resolution {
                    case .noWork:
                        work = work.replacingPhase(
                            .inspectingStandaloneDelivery(receipt)
                        )
                        await cutoverState.store(work)
                    case .retired:
                        return .pendingLocalRecovery
                    case .pendingLocalRecovery:
                        return .pendingLocalRecovery
                    }
                } catch {
                    return .pendingLocalRecovery
                }

            case .inspectingStandaloneDelivery(let receipt):
                if await deliveryStore
                    .hasRetainedHistoryWorkForPolicyCutover() {
                    return .pendingLocalRecovery
                }
                do {
                    guard let observation = try await deliveryStore.load()
                    else {
                        return .complete
                    }
                    switch observation {
                    case .expired(let expectation):
                        switch try await deliveryStore
                            .observeExpiredHistoryAbandonment(
                                expected: expectation
                            ) {
                        case .alreadyAbsent:
                            return .complete
                        case .observed(let expiredObservation):
                            work = work.replacingPhase(
                                .awaitingExpiredDeliveryAbandonment(
                                    receipt,
                                    expiredObservation
                                )
                            )
                            await cutoverState.store(work)
                            return .pendingLocalRecovery
                        }
                    case .clockRollbackAmbiguous:
                        return .pendingLocalRecovery
                    case .active(let record):
                        guard record.deliveryState != .discarded,
                              let marker = record.historyWrite else {
                            return .complete
                        }
                        guard marker.policyGeneration
                                <= receipt.state.policyGeneration else {
                            return .pendingLocalRecovery
                        }
                        guard marker.state.isPendingDecision,
                              marker.policyGeneration
                                < receipt.state.policyGeneration else {
                            return .complete
                        }
                        do {
                            let authorization = try await deliveryStore
                                .confirmActiveHistoryRecovery(
                                    expected:
                                        IOSAcceptedOutputDeliveryExpectation(
                                            record: record
                                        )
                                )
                            guard let confirmedMarker = authorization.record
                                .historyWrite,
                                  confirmedMarker.state.isPendingDecision,
                                  confirmedMarker.policyGeneration
                                    < receipt.state.policyGeneration else {
                                work = work.replacingPhase(
                                    .inspectingStandaloneDelivery(receipt)
                                )
                                await cutoverState.store(work)
                                return .pendingLocalRecovery
                            }
                            work = work.replacingPhase(
                                .cancellingStandaloneDelivery(
                                    receipt,
                                    authorization
                                )
                            )
                            await cutoverState.store(work)
                        } catch IOSAcceptedOutputDeliveryError
                            .compareAndSwapFailed {
                            work = work.replacingPhase(
                                .inspectingStandaloneDelivery(receipt)
                            )
                            await cutoverState.store(work)
                            return .pendingLocalRecovery
                        } catch IOSAcceptedOutputDeliveryError.expired {
                            return .pendingLocalRecovery
                        } catch IOSAcceptedOutputDeliveryError
                            .clockRollbackAmbiguous {
                            return .pendingLocalRecovery
                        } catch {
                            return .pendingLocalRecovery
                        }
                    }
                } catch {
                    return .pendingLocalRecovery
                }

            case .awaitingExpiredDeliveryAbandonment(
                _,
                let expiredObservation
            ):
                if await deliveryStore
                    .hasRetainedHistoryWorkForPolicyCutover() {
                    return .pendingLocalRecovery
                }
                do {
                    let isComplete = try await deliveryStore
                        .isExpiredHistoryAbandonmentComplete(
                            observation: expiredObservation
                        )
                    return isComplete ? .complete : .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }

            case .cancellingStandaloneDelivery(
                let receipt,
                let authorization
            ):
                do {
                    _ = try await deliveryStore.cancelHistoryWrite(
                        authorization: authorization,
                        policyInvalidationReceipt: receipt
                    )
                    return .complete
                } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
                    work = work.replacingPhase(
                        .inspectingStandaloneDelivery(receipt)
                    )
                    await cutoverState.store(work)
                    return .pendingLocalRecovery
                } catch IOSAcceptedOutputDeliveryError.expired {
                    work = work.replacingPhase(
                        .inspectingStandaloneDelivery(receipt)
                    )
                    await cutoverState.store(work)
                    return .pendingLocalRecovery
                } catch IOSAcceptedOutputDeliveryError
                    .clockRollbackAmbiguous {
                    work = work.replacingPhase(
                        .inspectingStandaloneDelivery(receipt)
                    )
                    await cutoverState.store(work)
                    return .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }

            case .establishingPolicy, .policyCaptured:
                return .pendingLocalRecovery
            }
        }
    }

    static func validatePolicyCutoverWork(
        _ work: IOSHistoryPolicyCutoverWork,
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity,
        deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    ) -> Bool {
        guard work.ownerIdentity == ownerIdentity else { return false }

        func valid(_ receipt: IOSHistoryPolicyReceipt) -> Bool {
            receipt.capabilityOwnerIdentity == ownerIdentity
        }

        switch work.phase {
        case .establishingPolicy:
            return true
        case .policyCaptured(let receipt):
            return work.command != nil && valid(receipt)
        case .pruningAcceptedRows(let receipt),
             .recoveringOutbox(let receipt),
             .inspectingStandaloneDelivery(let receipt):
            return valid(receipt)
        case .awaitingExpiredDeliveryAbandonment(
            let receipt,
            let observation
        ):
            return valid(receipt)
                && observation.belongs(to: deliveryStoreIdentity)
        case .cancellingStandaloneDelivery(
            let receipt,
            let authorization
        ):
            guard valid(receipt),
                  authorization.storeIdentity == deliveryStoreIdentity,
                  authorization.capabilityOwnerIdentity == ownerIdentity,
                  let marker = authorization.record.historyWrite else {
                return false
            }
            return marker.state.isPendingDecision
                && receipt.state.policyGeneration > marker.policyGeneration
        }
    }

    static func requireStablePolicyRepository(
        _ binding: IOSAcceptedHistoryCoordinatorRepositoryBinding?,
        registration: IOSAcceptedHistoryCoordinatorRepositoryRegistration?,
        identityState: IOSAcceptedHistoryCoordinatorRepositoryIdentityState
    ) throws {
        if let binding {
            _ = registration?.revalidate(expectedBinding: binding)
        }
        guard !identityState.isConflicted else {
            throw IOSAcceptedHistoryCoordinatorError
                .repositoryIdentityConflict
        }
    }
}
