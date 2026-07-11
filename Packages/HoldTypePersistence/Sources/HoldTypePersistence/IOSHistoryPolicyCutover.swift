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
    case reconcilingFailedHistory(IOSHistoryPolicyReceipt)
    case recoveringFailedTransfer(IOSHistoryPolicyReceipt)
    case inspectingProcessLostFailedRetry(
        IOSHistoryPolicyReceipt,
        IOSFailedHistoryRetryRecoveryInspection
    )
    case cancellingProcessLostFailedRetry(
        IOSHistoryPolicyReceipt,
        IOSFailedHistoryPolicyRetryCancellationAuthorization
    )
    case completingProcessLostFailedRetry(
        IOSHistoryPolicyReceipt,
        IOSFailedHistoryRetryCancellationCompletionAuthorization
    )
    case invalidatingFailedRow(
        IOSHistoryPolicyReceipt,
        IOSFailedHistoryRowAudioValidationAuthorization
    )
    case recoveringFailedAudio(
        IOSHistoryPolicyReceipt,
        IOSFailedHistoryAudioCleanupAuthorization
    )
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
        case .reconcilingFailedHistory, .recoveringFailedTransfer,
             .inspectingProcessLostFailedRetry,
             .cancellingProcessLostFailedRetry,
             .completingProcessLostFailedRetry,
             .invalidatingFailedRow, .recoveringFailedAudio,
             .pruningAcceptedRows, .recoveringOutbox,
             .inspectingStandaloneDelivery,
             .awaitingExpiredDeliveryAbandonment,
             .cancellingStandaloneDelivery:
            true
        }
    }

    var isFailedHistoryReconciliation: Bool {
        switch self {
        case .reconcilingFailedHistory, .recoveringFailedTransfer,
             .inspectingProcessLostFailedRetry,
             .cancellingProcessLostFailedRetry,
             .completingProcessLostFailedRetry,
             .invalidatingFailedRow, .recoveringFailedAudio:
            true
        case .establishingPolicy, .policyCaptured, .pruningAcceptedRows,
             .recoveringOutbox, .inspectingStandaloneDelivery,
             .awaitingExpiredDeliveryAbandonment,
             .cancellingStandaloneDelivery:
            false
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
        let pendingRecordingStore = pendingRecordingStore
        let outboxStore = outboxStore
        let deliveryStore = deliveryStore
        let baselineRecoveryState = baselineRecoveryState
        let acceptanceState = acceptanceState
        let pendingReplacementState = pendingReplacementState
        let workerState = outboxWorkerState
        let cutoverState = policyCutoverState
        let failedHistoryTransferState = failedHistoryTransferState
        let failedHistoryAudioCleanupState = failedHistoryAudioCleanupState
        let failedHistoryRetryState = failedHistoryRetryState
        let failedHistoryMutationInterlock =
            failedHistoryMutationInterlock
        let ownerIdentity = ownerIdentity
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration

        do {
            return try await operationGate.perform {
                operationLeaseAuthorization in
                let retainedAtEntry = await cutoverState.current()
                let mayResumeFailedHistory = retainedAtEntry?.ownerIdentity
                    == ownerIdentity
                    && retainedAtEntry?.phase.isFailedHistoryReconciliation
                        == true
                guard await failedHistoryRetryState.hasLiveOwner() == false else {
                    return .pendingLocalRecovery
                }
                let hasFailedTransferState = await failedHistoryTransferState
                    .current() != nil
                let hasFailedAudioCleanupState = await
                    failedHistoryAudioCleanupState.current() != nil
                if failedHistoryMutationInterlock.isBlocked
                    || hasFailedTransferState
                    || hasFailedAudioCleanupState {
                    guard mayResumeFailedHistory else {
                        return .pendingLocalRecovery
                    }
                }
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
                                pendingRecordingStore: pendingRecordingStore,
                                outboxStore: outboxStore,
                                deliveryStore: deliveryStore,
                                baselineRecoveryState: baselineRecoveryState,
                                workerState: workerState,
                                failedHistoryTransferState:
                                    failedHistoryTransferState,
                                failedHistoryAudioCleanupState:
                                    failedHistoryAudioCleanupState,
                                failedHistoryRetryState: failedHistoryRetryState,
                                failedHistoryMutationInterlock:
                                    failedHistoryMutationInterlock,
                                cutoverState: cutoverState,
                                ownerIdentity: ownerIdentity,
                                repositoryBinding: repositoryBinding,
                                repositoryRegistration: repositoryRegistration,
                                repositoryIdentityState: repositoryIdentityState,
                                operationLeaseAuthorization:
                                    operationLeaseAuthorization
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
                            pendingRecordingStore: pendingRecordingStore,
                            outboxStore: outboxStore,
                            deliveryStore: deliveryStore,
                            baselineRecoveryState: baselineRecoveryState,
                            workerState: workerState,
                            failedHistoryTransferState:
                                failedHistoryTransferState,
                            failedHistoryAudioCleanupState:
                                failedHistoryAudioCleanupState,
                            failedHistoryRetryState: failedHistoryRetryState,
                            failedHistoryMutationInterlock:
                                failedHistoryMutationInterlock,
                            cutoverState: cutoverState,
                            ownerIdentity: ownerIdentity,
                            repositoryBinding: repositoryBinding,
                            repositoryRegistration: repositoryRegistration,
                            repositoryIdentityState: repositoryIdentityState,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
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
        let pendingRecordingStore = pendingRecordingStore
        let outboxStore = outboxStore
        let deliveryStore = deliveryStore
        let baselineRecoveryState = baselineRecoveryState
        let acceptanceState = acceptanceState
        let pendingReplacementState = pendingReplacementState
        let workerState = outboxWorkerState
        let cutoverState = policyCutoverState
        let failedHistoryTransferState = failedHistoryTransferState
        let failedHistoryAudioCleanupState = failedHistoryAudioCleanupState
        let failedHistoryRetryState = failedHistoryRetryState
        let failedHistoryMutationInterlock =
            failedHistoryMutationInterlock
        let ownerIdentity = ownerIdentity
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration

        do {
            return try await operationGate.perform {
                operationLeaseAuthorization in
                let retainedAtEntry = await cutoverState.current()
                let mayResumeFailedHistory = retainedAtEntry?.ownerIdentity
                    == ownerIdentity
                    && retainedAtEntry?.command == command
                    && retainedAtEntry?.phase.isFailedHistoryReconciliation
                        == true
                if await failedHistoryRetryState.hasLiveOwner() {
                    if retainedAtEntry?.ownerIdentity == ownerIdentity,
                       retainedAtEntry?.command == command,
                       retainedAtEntry?.phase.crossedLogicalBoundary == true {
                        return .pendingLocalRecovery
                    }
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                let hasFailedTransferState = await failedHistoryTransferState
                    .current() != nil
                let hasFailedAudioCleanupState = await
                    failedHistoryAudioCleanupState.current() != nil
                if (hasFailedTransferState
                    || hasFailedAudioCleanupState
                    || failedHistoryMutationInterlock.isBlocked)
                    && !mayResumeFailedHistory {
                    if retainedAtEntry?.ownerIdentity == ownerIdentity,
                       retainedAtEntry?.command == command,
                       retainedAtEntry?.phase.crossedLogicalBoundary == true {
                        return .pendingLocalRecovery
                    }
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
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

                do {
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
                        case .reconcilingFailedHistory,
                             .recoveringFailedTransfer,
                             .inspectingProcessLostFailedRetry,
                             .cancellingProcessLostFailedRetry,
                             .completingProcessLostFailedRetry,
                             .invalidatingFailedRow,
                             .recoveringFailedAudio,
                             .pruningAcceptedRows,
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
                    pendingRecordingStore: pendingRecordingStore,
                    outboxStore: outboxStore,
                    deliveryStore: deliveryStore,
                    baselineRecoveryState: baselineRecoveryState,
                    workerState: workerState,
                    failedHistoryTransferState: failedHistoryTransferState,
                    failedHistoryAudioCleanupState:
                        failedHistoryAudioCleanupState,
                    failedHistoryRetryState: failedHistoryRetryState,
                    failedHistoryMutationInterlock:
                        failedHistoryMutationInterlock,
                    cutoverState: cutoverState,
                    ownerIdentity: ownerIdentity,
                    repositoryBinding: repositoryBinding,
                    repositoryRegistration: repositoryRegistration,
                    repositoryIdentityState: repositoryIdentityState,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
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
                } catch {
                    if let repositoryBinding {
                        _ = repositoryRegistration?.revalidate(
                            expectedBinding: repositoryBinding
                        )
                    }
                    guard repositoryIdentityState.isConflicted else {
                        throw error
                    }
                    let retainedAfterFailure = await cutoverState.current()
                    if retainedAfterFailure?.ownerIdentity == ownerIdentity,
                       retainedAfterFailure?.command == command,
                       retainedAfterFailure?.phase.crossedLogicalBoundary
                        == true {
                        return .pendingLocalRecovery
                    }
                    if retainedAfterFailure?.ownerIdentity == ownerIdentity,
                       retainedAfterFailure?.command == command,
                       case .policyCaptured = retainedAfterFailure?.phase,
                       error as? IOSHistoryPolicyError == .commitUncertain {
                        return .pendingLocalRecovery
                    }
                    if retainedAfterFailure?.ownerIdentity == ownerIdentity,
                       retainedAfterFailure?.command == command,
                       retainedAfterFailure?.phase.crossedLogicalBoundary
                        == false {
                        await cutoverState.clear()
                    }
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
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
        pendingRecordingStore: IOSPendingRecordingStore?,
        outboxStore: IOSAcceptedHistoryOutboxStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        baselineRecoveryState: IOSAcceptedHistoryBaselineRecoveryState,
        workerState: IOSAcceptedHistoryOutboxWorkerOperationState,
        failedHistoryTransferState: IOSFailedHistoryTransferOperationState,
        failedHistoryAudioCleanupState:
            IOSFailedHistoryAudioCleanupOperationState,
        failedHistoryRetryState: IOSFailedHistoryRetryLiveOwnerState,
        failedHistoryMutationInterlock: IOSFailedHistoryMutationInterlock,
        cutoverState: IOSHistoryPolicyCutoverOperationState,
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding?,
        repositoryRegistration:
            IOSAcceptedHistoryCoordinatorRepositoryRegistration?,
        repositoryIdentityState:
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
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
                            .reconcilingFailedHistory(receipt)
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
                        .reconcilingFailedHistory(committed)
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

            case .reconcilingFailedHistory,
                 .recoveringFailedTransfer,
                 .inspectingProcessLostFailedRetry,
                 .cancellingProcessLostFailedRetry,
                 .completingProcessLostFailedRetry,
                 .invalidatingFailedRow,
                 .recoveringFailedAudio,
                 .pruningAcceptedRows,
                 .recoveringOutbox,
                 .inspectingStandaloneDelivery,
                 .awaitingExpiredDeliveryAbandonment,
                 .cancellingStandaloneDelivery:
                return await resumePolicyCleanup(
                    work,
                    policyStore: policyStore,
                    acceptedHistoryStore: acceptedHistoryStore,
                    failedHistoryStore: failedHistoryStore,
                    pendingRecordingStore: pendingRecordingStore,
                    outboxStore: outboxStore,
                    deliveryStore: deliveryStore,
                    workerState: workerState,
                    failedHistoryTransferState: failedHistoryTransferState,
                    failedHistoryAudioCleanupState:
                        failedHistoryAudioCleanupState,
                    failedHistoryRetryState: failedHistoryRetryState,
                    failedHistoryMutationInterlock:
                        failedHistoryMutationInterlock,
                    cutoverState: cutoverState,
                    ownerIdentity: ownerIdentity,
                    repositoryBinding: repositoryBinding,
                    repositoryRegistration: repositoryRegistration,
                    repositoryIdentityState: repositoryIdentityState,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
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
        failedHistoryStore: IOSFailedHistoryStore,
        pendingRecordingStore: IOSPendingRecordingStore?,
        outboxStore: IOSAcceptedHistoryOutboxStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        workerState: IOSAcceptedHistoryOutboxWorkerOperationState,
        failedHistoryTransferState: IOSFailedHistoryTransferOperationState,
        failedHistoryAudioCleanupState:
            IOSFailedHistoryAudioCleanupOperationState,
        failedHistoryRetryState: IOSFailedHistoryRetryLiveOwnerState,
        failedHistoryMutationInterlock: IOSFailedHistoryMutationInterlock,
        cutoverState: IOSHistoryPolicyCutoverOperationState,
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding?,
        repositoryRegistration:
            IOSAcceptedHistoryCoordinatorRepositoryRegistration?,
        repositoryIdentityState:
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
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
            case .reconcilingFailedHistory(let receipt):
                guard await failedHistoryRetryState.hasLiveOwner() == false,
                      await failedHistoryTransferState.current() == nil,
                      await failedHistoryAudioCleanupState.current() == nil else {
                    return .pendingLocalRecovery
                }
                do {
                    switch try await failedHistoryStore
                        .preparePolicyCutoverDirective(
                            using: receipt,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ) {
                    case .retirePendingMetadata:
                        work = work.replacingPhase(
                            .recoveringFailedTransfer(receipt)
                        )
                        await cutoverState.store(work)

                    case .inspectProcessLostRetry(let inspection):
                        work = work.replacingPhase(
                            .inspectingProcessLostFailedRetry(
                                receipt,
                                inspection
                            )
                        )
                        await cutoverState.store(work)

                    case .completeProcessLostRetryCancellation(
                        let completion
                    ):
                        work = work.replacingPhase(
                            .completingProcessLostFailedRetry(
                                receipt,
                                completion
                            )
                        )
                        await cutoverState.store(work)

                    case .recoverAudioCleanup(let authorization):
                        guard await failedHistoryAudioCleanupState.begin(
                                authorization,
                                stateAuthorization:
                                    IOSFailedHistoryAudioCleanupStateMutationAuthorization()
                              ) else {
                            try? await failedHistoryStore
                                .abandonPreparedAudioCleanup(
                                    using: authorization,
                                    operationLeaseAuthorization:
                                        operationLeaseAuthorization
                                )
                            return .pendingLocalRecovery
                        }
                        work = work.replacingPhase(
                            .recoveringFailedAudio(receipt, authorization)
                        )
                        await cutoverState.store(work)

                    case .invalidateReadyRow(let authorization):
                        work = work.replacingPhase(
                            .invalidatingFailedRow(receipt, authorization)
                        )
                        await cutoverState.store(work)

                    case .retainedMutationConfirmed:
                        return .pendingLocalRecovery

                    case .blockedAcceptingOutput:
                        return .pendingLocalRecovery

                    case .complete:
                        work = work.replacingPhase(
                            .pruningAcceptedRows(receipt)
                        )
                        await cutoverState.store(work)
                    }
                } catch {
                    return .pendingLocalRecovery
                }

            case .recoveringFailedTransfer(let receipt):
                guard let pendingRecordingStore,
                      let repositoryBinding,
                      await failedHistoryAudioCleanupState.current() == nil,
                      await failedHistoryRetryState.hasLiveOwner() == false else {
                    return .pendingLocalRecovery
                }
                do {
                    _ = try await resumeFailedHistoryPendingJournalRetirementForPolicyCutover(
                        pendingStore: pendingRecordingStore,
                        failedStore: failedHistoryStore,
                        transferState: failedHistoryTransferState,
                        policyReceipt: receipt,
                        repositoryBinding: repositoryBinding,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                    work = work.replacingPhase(
                        .reconcilingFailedHistory(receipt)
                    )
                    await cutoverState.store(work)
                    return .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }

            case .inspectingProcessLostFailedRetry(
                let receipt,
                let inspection
            ):
                guard inspection.operationLeaseAuthorization
                    .provesSameActiveLease(
                        as: operationLeaseAuthorization
                    ) else {
                    work = work.replacingPhase(
                        .reconcilingFailedHistory(receipt)
                    )
                    await cutoverState.store(work)
                    return .pendingLocalRecovery
                }
                guard await failedHistoryTransferState.current() == nil,
                      await failedHistoryAudioCleanupState.current() == nil,
                      let reservation = await failedHistoryRetryState
                        .reserveProcessLostCancellation(
                            of: inspection,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ), reservation.stateIdentity
                            == failedHistoryRetryState.identity else {
                    return .pendingLocalRecovery
                }
                do {
                    switch try await failedHistoryStore
                        .preparePolicyRetryCancellation(
                            inspection: inspection,
                            reservation: reservation,
                            using: receipt,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ) {
                    case .commit(let authorization):
                        work = work.replacingPhase(
                            .cancellingProcessLostFailedRetry(
                                receipt,
                                authorization
                            )
                        )
                        await cutoverState.store(work)

                    case .completed(let completion):
                        work = work.replacingPhase(
                            .completingProcessLostFailedRetry(
                                receipt,
                                completion
                            )
                        )
                        await cutoverState.store(work)
                    }
                } catch {
                    return .pendingLocalRecovery
                }

            case .cancellingProcessLostFailedRetry(
                let receipt,
                let authorization
            ):
                guard authorization.operationLeaseAuthorization
                    .provesSameActiveLease(
                        as: operationLeaseAuthorization
                    ) else {
                    work = work.replacingPhase(
                        .reconcilingFailedHistory(receipt)
                    )
                    await cutoverState.store(work)
                    return .pendingLocalRecovery
                }
                do {
                    let completion = try await failedHistoryStore
                        .commitPolicyRetryCancellation(using: authorization)
                    work = work.replacingPhase(
                        .completingProcessLostFailedRetry(
                            receipt,
                            completion
                        )
                    )
                    await cutoverState.store(work)
                } catch {
                    return .pendingLocalRecovery
                }

            case .completingProcessLostFailedRetry(
                let receipt,
                let retainedCompletion
            ):
                do {
                    let completion:
                        IOSFailedHistoryRetryCancellationCompletionAuthorization
                    if retainedCompletion.operationLeaseAuthorization
                        .provesSameActiveLease(
                            as: operationLeaseAuthorization
                        ) {
                        completion = retainedCompletion
                    } else {
                        completion = try await failedHistoryStore
                            .refreshPolicyRetryCancellationCompletion(
                                retainedCompletion,
                                operationLeaseAuthorization:
                                    operationLeaseAuthorization
                            )
                        work = work.replacingPhase(
                            .completingProcessLostFailedRetry(
                                receipt,
                                completion
                            )
                        )
                        await cutoverState.store(work)
                    }
                    guard await failedHistoryRetryState
                        .consumeCancellationReservation(
                            using: completion
                        ) else {
                        return .pendingLocalRecovery
                    }
                    work = work.replacingPhase(
                        .reconcilingFailedHistory(receipt)
                    )
                    await cutoverState.store(work)
                    return .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }

            case .invalidatingFailedRow(let receipt, let authorization):
                guard let pendingRecordingStore else {
                    return .pendingLocalRecovery
                }
                guard authorization.operationLeaseAuthorization
                    .provesSameActiveLease(
                        as: operationLeaseAuthorization
                    ) else {
                    work = work.replacingPhase(
                        .reconcilingFailedHistory(receipt)
                    )
                    await cutoverState.store(work)
                    return .pendingLocalRecovery
                }
                do {
                    let validatedAudio = try await pendingRecordingStore
                        .acquireValidatedFailedHistoryRowAudio(
                            using: authorization,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        )
                    defer { validatedAudio.release() }
                    try await failedHistoryStore.commitPolicyInvalidation(
                        using: validatedAudio
                    )
                    work = work.replacingPhase(
                        .reconcilingFailedHistory(receipt)
                    )
                    await cutoverState.store(work)
                    return .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }

            case .recoveringFailedAudio(let receipt, let authorization):
                guard let pendingRecordingStore,
                      await failedHistoryTransferState.current() == nil,
                      await failedHistoryRetryState.hasLiveOwner() == false,
                      await failedHistoryAudioCleanupState.retainsCleanup(
                        matching: authorization
                      ) else {
                    return .pendingLocalRecovery
                }
                do {
                    _ = try await resumeFailedHistoryAudioCleanup(
                        pendingStore: pendingRecordingStore,
                        failedStore: failedHistoryStore,
                        cleanupState: failedHistoryAudioCleanupState,
                        mutationInterlock: failedHistoryMutationInterlock,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                    work = work.replacingPhase(
                        .reconcilingFailedHistory(receipt)
                    )
                    await cutoverState.store(work)
                    return .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }

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
        case .reconcilingFailedHistory(let receipt),
             .recoveringFailedTransfer(let receipt):
            return valid(receipt)
        case .inspectingProcessLostFailedRetry(let receipt, _),
             .cancellingProcessLostFailedRetry(let receipt, _),
             .completingProcessLostFailedRetry(let receipt, _):
            return valid(receipt)
        case .invalidatingFailedRow(let receipt, let authorization):
            return valid(receipt)
                && authorization.ownerIdentity == ownerIdentity
                && authorization.purpose == .policyCutover(receipt)
        case .recoveringFailedAudio(let receipt, let authorization):
            return valid(receipt)
                && authorization.ownerIdentity == ownerIdentity
                && authorization.purpose == .nextHead
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
