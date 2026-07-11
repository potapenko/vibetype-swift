import Foundation

public enum IOSAcceptedHistoryOutboxRecoveryResolution:
    Equatable,
    Sendable {
    case noWork
    case retired
    case pendingLocalRecovery
}

extension IOSAcceptedHistoryOutboxRecoveryResolution:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSAcceptedHistoryOutboxRecoveryResolution(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSAcceptedHistoryOutboxWorkerPhase: Equatable, Sendable {
    case headObserved(IOSAcceptedHistoryOutboxObservation)
    case membershipConfirmed(IOSAcceptedHistoryOutboxReceipt)
    case policyConfirmed(
        IOSAcceptedHistoryOutboxTemporalReceipt,
        IOSHistoryPolicyReceipt
    )
    case rowDecided(
        IOSAcceptedHistoryOutboxTemporalReceipt,
        IOSHistoryPolicyReceipt,
        IOSAcceptedHistoryRowReceipt
    )
    case policyRevalidated(
        IOSAcceptedHistoryOutboxReceipt,
        IOSAcceptedHistoryRowReceipt
    )
    case invalidationConfirmed(
        IOSAcceptedHistoryOutboxTemporalReceipt,
        IOSHistoryPolicyReceipt
    )
    case markerAuthorized(
        IOSAcceptedHistoryOutboxReceipt,
        IOSAcceptedHistoryRowReceipt,
        IOSAcceptedOutputDeliveryAuthorization
    )
    case cancellationAuthorized(
        IOSAcceptedHistoryOutboxReceipt,
        IOSHistoryPolicyReceipt,
        IOSAcceptedOutputDeliveryAuthorization
    )
    case retiringProcessed(
        IOSAcceptedHistoryOutboxReceipt,
        IOSAcceptedHistoryRowReceipt
    )
    case retiringTerminal(
        IOSAcceptedHistoryOutboxReceipt,
        IOSAcceptedOutputDeliveryAuthorization
    )
    case retiringInvalidated(
        IOSAcceptedHistoryOutboxReceipt,
        IOSHistoryPolicyReceipt
    )
    case retiringExpired(IOSAcceptedHistoryOutboxTemporalReceipt)
}

extension IOSAcceptedHistoryOutboxWorkerPhase:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedHistoryOutboxWorkerPhase(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSAcceptedHistoryOutboxWorkerWork: Equatable, Sendable {
    let ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity
    let phase: IOSAcceptedHistoryOutboxWorkerPhase

    func replacingPhase(
        _ phase: IOSAcceptedHistoryOutboxWorkerPhase
    ) -> Self {
        Self(ownerIdentity: ownerIdentity, phase: phase)
    }
}

extension IOSAcceptedHistoryOutboxWorkerWork:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedHistoryOutboxWorkerWork(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

actor IOSAcceptedHistoryOutboxWorkerOperationState {
    private var work: IOSAcceptedHistoryOutboxWorkerWork?

    func current() -> IOSAcceptedHistoryOutboxWorkerWork? { work }

    func store(_ work: IOSAcceptedHistoryOutboxWorkerWork) {
        self.work = work
    }

    func clear() {
        work = nil
    }
}

private enum IOSAcceptedHistoryOutboxWorkerPolicyDisposition: Sendable {
    case matching(IOSHistoryPolicyReceipt)
    case invalidated(IOSHistoryPolicyReceipt)
}

public extension IOSAcceptedHistoryCoordinator {
    /// Reconciles at most one app-private FIFO outbox head and never performs
    /// provider work. A second entry always requires a second call.
    func recoverAcceptedHistoryOutbox()
        async throws -> IOSAcceptedHistoryOutboxRecoveryResolution {
        let policyStore = policyStore
        let acceptedHistoryStore = acceptedHistoryStore
        let outboxStore = outboxStore
        let deliveryStore = deliveryStore
        let acceptanceState = acceptanceState
        let pendingReplacementState = pendingReplacementState
        let workerState = outboxWorkerState
        let ownerIdentity = ownerIdentity
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration

        do {
            return try await operationGate.perform {
                let repositoryBinding = repositoryRegistration?.revalidate()
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }

                var resolution =
                    IOSAcceptedHistoryOutboxRecoveryResolution
                        .pendingLocalRecovery
                do {
                    guard await acceptanceState.current() == nil,
                          await pendingReplacementState.current() == nil,
                          await deliveryStore
                            .hasUncertainAcceptanceForHistoryCoordinator()
                            == false else {
                        return .pendingLocalRecovery
                    }

                    let work: IOSAcceptedHistoryOutboxWorkerWork
                    if let retained = await workerState.current() {
                        work = retained
                    } else {
                        guard let head = try await outboxStore.observeHead()
                        else {
                            resolution = .noWork
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
                        work = IOSAcceptedHistoryOutboxWorkerWork(
                            ownerIdentity: ownerIdentity,
                            phase: .headObserved(head)
                        )
                        await workerState.store(work)
                    }

                    resolution = await Self.resumeOutboxWorker(
                        work,
                        policyStore: policyStore,
                        acceptedHistoryStore: acceptedHistoryStore,
                        outboxStore: outboxStore,
                        deliveryStore: deliveryStore,
                        workerState: workerState,
                        ownerIdentity: ownerIdentity
                    )
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
                    resolution = .pendingLocalRecovery
                }

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
        } catch IOSPersistenceOperationGate.AcquisitionError.cancelledBeforeLease {
            throw IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError.reentrantOperation {
            throw IOSAcceptedHistoryCoordinatorError.reentrantOperation
        }
    }
}

private extension IOSAcceptedHistoryCoordinator {
    static func resumeOutboxWorker(
        _ initialWork: IOSAcceptedHistoryOutboxWorkerWork,
        policyStore: IOSHistoryPolicyStore,
        acceptedHistoryStore: IOSAcceptedHistoryStore,
        outboxStore: IOSAcceptedHistoryOutboxStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        workerState: IOSAcceptedHistoryOutboxWorkerOperationState,
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity
    ) async -> IOSAcceptedHistoryOutboxRecoveryResolution {
        var work = initialWork

        while true {
            guard validateOutboxWorkerWork(
                work,
                ownerIdentity: ownerIdentity,
                outboxStoreIdentity: outboxStore.storeIdentity,
                deliveryStoreIdentity: deliveryStore.storeIdentity
            ) else {
                await workerState.clear()
                return .pendingLocalRecovery
            }

            switch work.phase {
            case .headObserved(let observation):
                do {
                    let membership = try await outboxStore.confirmMembership(
                        observation: observation
                    )
                    work = work.replacingPhase(
                        .membershipConfirmed(membership)
                    )
                    await workerState.store(work)
                } catch IOSAcceptedHistoryOutboxError.compareAndSwapFailed {
                    await workerState.clear()
                    return .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }

            case .membershipConfirmed(let membership):
                do {
                    let temporal = try await outboxStore
                        .classifyTemporalState(membership: membership)
                    switch temporal.temporalState {
                    case .live:
                        let disposition = try await outboxWorkerPolicyDisposition(
                            policyStore: policyStore,
                            membership: membership
                        )
                        switch disposition {
                        case .matching(let receipt):
                            work = work.replacingPhase(
                                .policyConfirmed(temporal, receipt)
                            )
                        case .invalidated(let receipt):
                            work = work.replacingPhase(
                                .invalidationConfirmed(temporal, receipt)
                            )
                        }
                        await workerState.store(work)
                    case .expired:
                        work = work.replacingPhase(.retiringExpired(temporal))
                        await workerState.store(work)
                    case .clockRollbackAmbiguous:
                        return .pendingLocalRecovery
                    }
                } catch IOSAcceptedHistoryOutboxError.compareAndSwapFailed {
                    await workerState.clear()
                    return .pendingLocalRecovery
                } catch IOSHistoryPolicyError.compareAndSwapFailed {
                    await workerState.clear()
                    return .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }

            case .policyConfirmed(let temporal, let policyReceipt):
                let membership = temporal.membership
                do {
                    let delivery = try await deliveryStore
                        .confirmMatchingHistoryDelivery(
                            membership: membership
                        )
                    switch delivery {
                    case .confirmed(let authorization):
                        switch authorization.record.historyWrite?.state {
                        case .committed:
                            work = work.replacingPhase(
                                .retiringTerminal(
                                    membership,
                                    authorization
                                )
                            )
                            await workerState.store(work)
                            continue
                        case .cancelled, .none:
                            return .pendingLocalRecovery
                        case .pending, .pendingReplacement:
                            break
                        }
                    case .absentOrUnrelated:
                        break
                    case .expired, .clockRollbackAmbiguous:
                        work = work.replacingPhase(
                            .membershipConfirmed(membership)
                        )
                        await workerState.store(work)
                        return .pendingLocalRecovery
                    }

                    let rowReceipt = try await acceptedHistoryStore.decideUpsert(
                        outbox: membership,
                        policy: policyReceipt
                    )
                    work = work.replacingPhase(
                        .rowDecided(temporal, policyReceipt, rowReceipt)
                    )
                    await workerState.store(work)
                } catch IOSAcceptedHistoryError.expired {
                    work = work.replacingPhase(
                        .membershipConfirmed(membership)
                    )
                    await workerState.store(work)
                    return .pendingLocalRecovery
                } catch IOSAcceptedHistoryError.compareAndSwapFailed {
                    await workerState.clear()
                    return .pendingLocalRecovery
                } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
                    await workerState.clear()
                    return .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }

            case .rowDecided(
                let temporal,
                let firstPolicyReceipt,
                let rowReceipt
            ):
                do {
                    let disposition = try await
                        revalidatedOutboxWorkerPolicyDisposition(
                            policyStore: policyStore,
                            expected: firstPolicyReceipt,
                            membership: temporal.membership
                        )
                    switch disposition {
                    case .matching:
                        work = work.replacingPhase(
                            .policyRevalidated(
                                temporal.membership,
                                rowReceipt
                            )
                        )
                    case .invalidated(let receipt):
                        work = work.replacingPhase(
                            .invalidationConfirmed(temporal, receipt)
                        )
                    }
                    await workerState.store(work)
                } catch IOSHistoryPolicyError.compareAndSwapFailed {
                    await workerState.clear()
                    return .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }

            case .policyRevalidated(let membership, let rowReceipt):
                do {
                    let delivery = try await deliveryStore
                        .confirmMatchingHistoryDelivery(
                            membership: membership
                        )
                    switch delivery {
                    case .absentOrUnrelated, .expired:
                        work = work.replacingPhase(
                            .retiringProcessed(membership, rowReceipt)
                        )
                    case .clockRollbackAmbiguous:
                        return .pendingLocalRecovery
                    case .confirmed(let authorization):
                        switch authorization.record.historyWrite?.state {
                        case .pending, .pendingReplacement:
                            work = work.replacingPhase(
                                .markerAuthorized(
                                    membership,
                                    rowReceipt,
                                    authorization
                                )
                            )
                        case .committed:
                            work = work.replacingPhase(
                                .retiringProcessed(membership, rowReceipt)
                            )
                        case .cancelled, .none:
                            return .pendingLocalRecovery
                        }
                    }
                    await workerState.store(work)
                } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
                    await workerState.clear()
                    return .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }

            case .invalidationConfirmed(let temporal, let policyReceipt):
                let membership = temporal.membership
                do {
                    let delivery = try await deliveryStore
                        .confirmMatchingHistoryDelivery(
                            membership: membership
                        )
                    switch delivery {
                    case .absentOrUnrelated, .expired:
                        work = work.replacingPhase(
                            .retiringInvalidated(membership, policyReceipt)
                        )
                    case .clockRollbackAmbiguous:
                        return .pendingLocalRecovery
                    case .confirmed(let authorization):
                        switch authorization.record.historyWrite?.state {
                        case .pending, .pendingReplacement:
                            work = work.replacingPhase(
                                .cancellationAuthorized(
                                    membership,
                                    policyReceipt,
                                    authorization
                                )
                            )
                        case .committed, .cancelled:
                            work = work.replacingPhase(
                                .retiringInvalidated(
                                    membership,
                                    policyReceipt
                                )
                            )
                        case .none:
                            return .pendingLocalRecovery
                        }
                    }
                    await workerState.store(work)
                } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
                    await workerState.clear()
                    return .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }

            case .markerAuthorized(
                let membership,
                let rowReceipt,
                let authorization
            ):
                do {
                    _ = try await deliveryStore.commitHistoryWrite(
                        authorization: authorization,
                        rowReceipt: rowReceipt
                    )
                    work = work.replacingPhase(
                        .retiringProcessed(membership, rowReceipt)
                    )
                    await workerState.store(work)
                } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
                    await workerState.clear()
                    return .pendingLocalRecovery
                } catch IOSAcceptedOutputDeliveryError.expired {
                    work = work.replacingPhase(
                        .retiringProcessed(membership, rowReceipt)
                    )
                    await workerState.store(work)
                } catch {
                    return .pendingLocalRecovery
                }

            case .cancellationAuthorized(
                let membership,
                let policyReceipt,
                let authorization
            ):
                do {
                    _ = try await deliveryStore.cancelHistoryWrite(
                        authorization: authorization,
                        policyInvalidationReceipt: policyReceipt
                    )
                    work = work.replacingPhase(
                        .retiringInvalidated(membership, policyReceipt)
                    )
                    await workerState.store(work)
                } catch IOSAcceptedOutputDeliveryError.compareAndSwapFailed {
                    await workerState.clear()
                    return .pendingLocalRecovery
                } catch IOSAcceptedOutputDeliveryError.expired {
                    work = work.replacingPhase(
                        .retiringInvalidated(membership, policyReceipt)
                    )
                    await workerState.store(work)
                } catch {
                    return .pendingLocalRecovery
                }

            case .retiringProcessed(let membership, let rowReceipt):
                do {
                    try await outboxStore.retireProcessed(
                        membership: membership,
                        decision: rowReceipt
                    )
                    await workerState.clear()
                    return .retired
                } catch IOSAcceptedHistoryOutboxError.compareAndSwapFailed {
                    await workerState.clear()
                    return .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }

            case .retiringTerminal(let membership, let authorization):
                do {
                    try await outboxStore.retireProcessed(
                        membership: membership,
                        terminalDelivery: authorization
                    )
                    await workerState.clear()
                    return .retired
                } catch IOSAcceptedHistoryOutboxError.compareAndSwapFailed {
                    await workerState.clear()
                    return .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }

            case .retiringInvalidated(let membership, let policyReceipt):
                do {
                    try await outboxStore.retireInvalidated(
                        membership: membership,
                        policy: policyReceipt
                    )
                    await workerState.clear()
                    return .retired
                } catch IOSAcceptedHistoryOutboxError.compareAndSwapFailed {
                    await workerState.clear()
                    return .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }

            case .retiringExpired(let temporal):
                do {
                    try await outboxStore.retireExpired(
                        classification: temporal
                    )
                    await workerState.clear()
                    return .retired
                } catch IOSAcceptedHistoryOutboxError.compareAndSwapFailed {
                    await workerState.clear()
                    return .pendingLocalRecovery
                } catch {
                    return .pendingLocalRecovery
                }
            }
        }
    }

    static func outboxWorkerPolicyDisposition(
        policyStore: IOSHistoryPolicyStore,
        membership: IOSAcceptedHistoryOutboxReceipt
    ) async throws -> IOSAcceptedHistoryOutboxWorkerPolicyDisposition {
        guard let state = try await policyStore.load() else {
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }
        let receipt = try await policyStore.confirm(
            expected: IOSHistoryPolicyExpectation(state: state)
        )
        return try classifyOutboxWorkerPolicy(
            receipt,
            membership: membership
        )
    }

    static func revalidatedOutboxWorkerPolicyDisposition(
        policyStore: IOSHistoryPolicyStore,
        expected firstReceipt: IOSHistoryPolicyReceipt,
        membership: IOSAcceptedHistoryOutboxReceipt
    ) async throws -> IOSAcceptedHistoryOutboxWorkerPolicyDisposition {
        do {
            let receipt = try await policyStore.confirm(
                expected: IOSHistoryPolicyExpectation(
                    state: firstReceipt.state
                )
            )
            return try classifyOutboxWorkerPolicy(
                receipt,
                membership: membership
            )
        } catch IOSHistoryPolicyError.compareAndSwapFailed {
            return try await outboxWorkerPolicyDisposition(
                policyStore: policyStore,
                membership: membership
            )
        }
    }

    static func classifyOutboxWorkerPolicy(
        _ receipt: IOSHistoryPolicyReceipt,
        membership: IOSAcceptedHistoryOutboxReceipt
    ) throws -> IOSAcceptedHistoryOutboxWorkerPolicyDisposition {
        guard let entry = membership.confirmedEntryForAcceptedDecision()
        else {
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }
        if receipt.state.historyEnabled,
           receipt.state.policyGeneration == entry.policyGeneration {
            return .matching(receipt)
        }
        if receipt.state.policyGeneration > entry.policyGeneration {
            return .invalidated(receipt)
        }
        throw IOSHistoryPolicyError.compareAndSwapFailed
    }

    static func validateOutboxWorkerWork(
        _ work: IOSAcceptedHistoryOutboxWorkerWork,
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity,
        outboxStoreIdentity: IOSAcceptedHistoryOutboxStoreIdentity,
        deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    ) -> Bool {
        guard work.ownerIdentity == ownerIdentity else { return false }

        func valid(
            _ membership: IOSAcceptedHistoryOutboxReceipt
        ) -> Bool {
            membership.capabilityOwnerIdentity == ownerIdentity
                && membership.storeIdentity == outboxStoreIdentity
                && membership.deliveryStoreIdentity == deliveryStoreIdentity
                && membership.provesHeadMembership()
        }

        switch work.phase {
        case .headObserved(let observation):
            return observation.capabilityOwnerIdentity == ownerIdentity
                && observation.storeIdentity == outboxStoreIdentity
                && observation.isHead
        case .membershipConfirmed(let membership):
            return valid(membership)
        case .policyConfirmed(let temporal, let policy),
             .invalidationConfirmed(let temporal, let policy):
            return valid(temporal.membership)
                && temporal.temporalState == .live
                && policy.capabilityOwnerIdentity == ownerIdentity
        case .rowDecided(let temporal, let policy, let row):
            return valid(temporal.membership)
                && temporal.temporalState == .live
                && policy.capabilityOwnerIdentity == ownerIdentity
                && row.capabilityOwnerIdentity == ownerIdentity
                && row.provesDecision(for: temporal.membership)
        case .policyRevalidated(let membership, let row),
             .retiringProcessed(let membership, let row):
            return valid(membership)
                && row.capabilityOwnerIdentity == ownerIdentity
                && row.provesDecision(for: membership)
        case .markerAuthorized(let membership, let row, let authorization):
            return valid(membership)
                && row.capabilityOwnerIdentity == ownerIdentity
                && row.provesDecision(for: membership)
                && authorization.capabilityOwnerIdentity == ownerIdentity
                && authorization.storeIdentity == deliveryStoreIdentity
                && row.provesDecision(for: authorization)
                && membership.deliveryRelation(to: authorization) == .pending
        case .cancellationAuthorized(
            let membership,
            let policy,
            let authorization
        ):
            guard valid(membership),
                  let entry = membership.confirmedEntryForAcceptedDecision(),
                  let marker = authorization.record.historyWrite else {
                return false
            }
            return policy.capabilityOwnerIdentity == ownerIdentity
                && authorization.capabilityOwnerIdentity == ownerIdentity
                && authorization.storeIdentity == deliveryStoreIdentity
                && membership.deliveryRelation(to: authorization) == .pending
                && policy.state.policyGeneration > entry.policyGeneration
                && policy.state.policyGeneration > marker.policyGeneration
        case .retiringTerminal(let membership, let authorization):
            return valid(membership)
                && authorization.capabilityOwnerIdentity == ownerIdentity
                && authorization.storeIdentity == deliveryStoreIdentity
                && authorization.record.historyWrite?.state == .committed
                && membership.deliveryRelation(to: authorization)
                    == .committed
        case .retiringInvalidated(let membership, let policy):
            guard valid(membership),
                  let entry = membership.confirmedEntryForAcceptedDecision()
            else {
                return false
            }
            return policy.capabilityOwnerIdentity == ownerIdentity
                && policy.state.policyGeneration > entry.policyGeneration
        case .retiringExpired(let temporal):
            return valid(temporal.membership)
                && temporal.temporalState == .expired
        }
    }
}
