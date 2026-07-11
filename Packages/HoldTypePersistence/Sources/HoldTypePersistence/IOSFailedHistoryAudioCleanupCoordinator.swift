import Foundation

enum IOSFailedHistoryAudioCleanupResult: Equatable, Sendable {
    case cleaned
    case noWork
}

extension IOSFailedHistoryAudioCleanupResult:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryAudioCleanupResult(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSFailedHistoryAudioCleanupSemanticPhase: Equatable, Sendable {
    case removing(IOSFailedHistoryAudioCleanupAuthorization)
    case retiring(IOSFailedHistoryAudioCleanupReceipt)
    case completed(IOSFailedHistoryAudioCleanupCompletionAuthorization)
}

extension IOSFailedHistoryAudioCleanupSemanticPhase:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryAudioCleanupSemanticPhase(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSFailedHistoryAudioCleanupStateMutationAuthorization {
    init() {}
}

actor IOSFailedHistoryAudioCleanupOperationState {
    private var phase: IOSFailedHistoryAudioCleanupSemanticPhase?

    func current() -> IOSFailedHistoryAudioCleanupSemanticPhase? { phase }

    /// Compares the cleanup's stable Store/root identity rather than its lease,
    /// so policy cutover can recognize the same retained operation after refresh.
    func retainsCleanup(
        matching authorization: IOSFailedHistoryAudioCleanupAuthorization
    ) -> Bool {
        switch phase {
        case .removing(let retained):
            retained.identifiesSameCleanup(as: authorization)
        case .retiring(let receipt):
            receipt.authorization.identifiesSameCleanup(as: authorization)
        case .completed(let completion):
            completion.identifiesSameCleanup(as: authorization)
        case nil:
            false
        }
    }

    func begin(
        _ authorization: IOSFailedHistoryAudioCleanupAuthorization,
        stateAuthorization:
            IOSFailedHistoryAudioCleanupStateMutationAuthorization
    ) -> Bool {
        _ = stateAuthorization
        guard phase == nil,
              authorization.operationLeaseAuthorization
                .provesActiveLease() else {
            return false
        }
        phase = .removing(authorization)
        return true
    }

    fileprivate func refreshRemoving(
        _ refreshed: IOSFailedHistoryAudioCleanupAuthorization,
        stateAuthorization:
            IOSFailedHistoryAudioCleanupStateMutationAuthorization
    ) -> Bool {
        _ = stateAuthorization
        guard case .removing(let retained) = phase,
              retained.identifiesSameCleanup(as: refreshed),
              refreshed.operationLeaseAuthorization
                .provesActiveLease() else {
            return false
        }
        phase = .removing(refreshed)
        return true
    }

    fileprivate func recordRetiring(
        _ receipt: IOSFailedHistoryAudioCleanupReceipt,
        from authorization: IOSFailedHistoryAudioCleanupAuthorization,
        stateAuthorization:
            IOSFailedHistoryAudioCleanupStateMutationAuthorization
    ) -> Bool {
        _ = stateAuthorization
        guard phase == .removing(authorization),
              receipt.authorization == authorization,
              authorization.operationLeaseAuthorization
                .provesActiveLease() else {
            return false
        }
        phase = .retiring(receipt)
        return true
    }

    fileprivate func refreshRetiring(
        _ refreshed: IOSFailedHistoryAudioCleanupReceipt,
        stateAuthorization:
            IOSFailedHistoryAudioCleanupStateMutationAuthorization
    ) -> Bool {
        _ = stateAuthorization
        guard case .retiring(let retained) = phase,
              retained.issuerStoreIdentity
                == refreshed.issuerStoreIdentity,
              retained.authorization.identifiesSameCleanup(
                  as: refreshed.authorization
              ),
              refreshed.authorization.operationLeaseAuthorization
                .provesActiveLease() else {
            return false
        }
        phase = .retiring(refreshed)
        return true
    }

    fileprivate func recordCompleted(
        _ completion:
            IOSFailedHistoryAudioCleanupCompletionAuthorization,
        stateAuthorization:
            IOSFailedHistoryAudioCleanupStateMutationAuthorization
    ) -> Bool {
        _ = stateAuthorization
        guard case .retiring(let retained) = phase,
              completion.identifiesSameCleanup(
                  as: retained.authorization
              ),
              completion.operationLeaseAuthorization
                .provesActiveLease() else {
            return false
        }
        phase = .completed(completion)
        return true
    }

    fileprivate func clearCompleted(
        _ completion:
            IOSFailedHistoryAudioCleanupCompletionAuthorization,
        stateAuthorization:
            IOSFailedHistoryAudioCleanupStateMutationAuthorization
    ) -> Bool {
        _ = stateAuthorization
        guard phase == .completed(completion) else { return false }
        phase = nil
        return true
    }

    fileprivate func abandonBeforeFilesystem(
        _ authorization: IOSFailedHistoryAudioCleanupAuthorization,
        stateAuthorization:
            IOSFailedHistoryAudioCleanupStateMutationAuthorization
    ) -> Bool {
        _ = stateAuthorization
        guard phase == .removing(authorization),
              authorization.operationLeaseAuthorization
                .provesActiveLease() else {
            return false
        }
        phase = nil
        return true
    }
}

private extension IOSFailedHistoryAudioCleanupAuthorization {
    func identifiesSameCleanup(
        as other: IOSFailedHistoryAudioCleanupAuthorization
    ) -> Bool {
        failedSource == other.failedSource
            && tombstone == other.tombstone
            && outcome == other.outcome
            && purpose == other.purpose
            && operationID == other.operationID
            && failedStoreIdentity == other.failedStoreIdentity
            && expectedPendingStoreIdentity
                == other.expectedPendingStoreIdentity
            && ownerIdentity == other.ownerIdentity
            && repositoryBinding == other.repositoryBinding
    }
}

private extension IOSFailedHistoryAudioCleanupCompletionAuthorization {
    func identifiesSameCleanup(
        as authorization: IOSFailedHistoryAudioCleanupAuthorization
    ) -> Bool {
        operationID == authorization.operationID
            && failedStoreIdentity == authorization.failedStoreIdentity
            && expectedPendingStoreIdentity
                == authorization.expectedPendingStoreIdentity
            && ownerIdentity == authorization.ownerIdentity
            && repositoryBinding == authorization.repositoryBinding
    }
}

extension IOSAcceptedHistoryCoordinator {
    func recoverFailedHistoryAudioCleanup()
        async throws -> IOSFailedHistoryAudioCleanupResult {
        guard let pendingRecordingStore else {
            throw IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        }
        let failedHistoryStore = failedHistoryStore
        let operationGate = operationGate
        let cleanupState = failedHistoryAudioCleanupState
        let failedHistoryMutationInterlock =
            failedHistoryMutationInterlock
        let baselineRecoveryState = baselineRecoveryState
        let acceptanceState = acceptanceState
        let pendingReplacementState = pendingReplacementState
        let outboxWorkerState = outboxWorkerState
        let policyCutoverState = policyCutoverState
        let failedHistoryTransferState = failedHistoryTransferState
        let deliveryStore = deliveryStore
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration

        do {
            return try await operationGate.perform { authorization in
                let repositoryBinding = repositoryRegistration?.revalidate()
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                do {
                    guard await baselineRecoveryState.value() == false,
                          await acceptanceState.current() == nil,
                          await pendingReplacementState.current() == nil,
                          await outboxWorkerState.current() == nil,
                          await policyCutoverState.current() == nil,
                          await failedHistoryTransferState.current() == nil,
                          await deliveryStore
                            .hasUncertainAcceptanceForHistoryCoordinator()
                            == false,
                          await deliveryStore
                            .hasRetainedHistoryWorkForPolicyCutover()
                            == false else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }

                    let result: IOSFailedHistoryAudioCleanupResult
                    if await cleanupState.current() != nil {
                        result = try await Self.resumeFailedHistoryAudioCleanup(
                            pendingStore: pendingRecordingStore,
                            failedStore: failedHistoryStore,
                            cleanupState: cleanupState,
                            mutationInterlock:
                                failedHistoryMutationInterlock,
                            operationLeaseAuthorization: authorization
                        )
                    } else {
                        guard !failedHistoryMutationInterlock.isBlocked,
                              try await failedHistoryStore
                                .hasPendingJournalRetirement(
                                    operationLeaseAuthorization:
                                        authorization
                                ) == false else {
                            throw IOSAcceptedHistoryCoordinatorError
                                .localRecoveryPending
                        }
                        guard let cleanupAuthorization = try await
                            failedHistoryStore.prepareNextAudioCleanup(
                                operationLeaseAuthorization: authorization
                            ) else {
                            return .noWork
                        }
                        guard await cleanupState.begin(
                            cleanupAuthorization,
                            stateAuthorization:
                                IOSFailedHistoryAudioCleanupStateMutationAuthorization()
                        ) else {
                            try await failedHistoryStore
                                .abandonPreparedAudioCleanup(
                                    using: cleanupAuthorization,
                                    operationLeaseAuthorization: authorization
                                )
                            throw IOSAcceptedHistoryCoordinatorError
                                .localRecoveryPending
                        }
                        result = try await Self.resumeFailedHistoryAudioCleanup(
                            pendingStore: pendingRecordingStore,
                            failedStore: failedHistoryStore,
                            cleanupState: cleanupState,
                            mutationInterlock:
                                failedHistoryMutationInterlock,
                            operationLeaseAuthorization: authorization
                        )
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
        } catch IOSPersistenceOperationGate.AcquisitionError
            .cancelledBeforeLease {
            throw IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError
            .reentrantOperation {
            throw IOSAcceptedHistoryCoordinatorError.reentrantOperation
        }
    }

    static func resumeFailedHistoryAudioCleanup(
        pendingStore: IOSPendingRecordingStore,
        failedStore: IOSFailedHistoryStore,
        cleanupState: IOSFailedHistoryAudioCleanupOperationState,
        mutationInterlock: IOSFailedHistoryMutationInterlock,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryAudioCleanupResult {
        let stateAuthorization =
            IOSFailedHistoryAudioCleanupStateMutationAuthorization()

        while let phase = await cleanupState.current() {
            switch phase {
            case .removing(let retained):
                let authorization:
                    IOSFailedHistoryAudioCleanupAuthorization
                if retained.operationLeaseAuthorization
                    .provesSameActiveLease(
                        as: operationLeaseAuthorization
                    ) {
                    authorization = retained
                } else {
                    guard let refreshed = try await failedStore
                        .refreshAudioCleanupAuthorization(
                            retained,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ), await cleanupState.refreshRemoving(
                            refreshed,
                            stateAuthorization: stateAuthorization
                        ) else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                    authorization = refreshed
                }
                let receipt = try await pendingStore
                    .reconcileFailedHistoryAudioCleanup(
                        using: authorization,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                guard await cleanupState.recordRetiring(
                    receipt,
                    from: authorization,
                    stateAuthorization: stateAuthorization
                ) else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }

            case .retiring(let retainedReceipt):
                let retained = retainedReceipt.authorization
                let authorization:
                    IOSFailedHistoryAudioCleanupAuthorization
                let receipt: IOSFailedHistoryAudioCleanupReceipt

                if retained.operationLeaseAuthorization
                    .provesSameActiveLease(
                        as: operationLeaseAuthorization
                    ) {
                    authorization = retained
                    receipt = retainedReceipt
                } else if let refreshed = try await failedStore
                    .refreshAudioCleanupAuthorization(
                        retained,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    ) {
                    let refreshedReceipt = try await pendingStore
                        .reconcileFailedHistoryAudioCleanup(
                            using: refreshed,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        )
                    guard await cleanupState.refreshRetiring(
                        refreshedReceipt,
                        stateAuthorization: stateAuthorization
                    ) else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                    authorization = refreshed
                    receipt = refreshedReceipt
                } else {
                    let completion:
                        IOSFailedHistoryAudioCleanupCompletionAuthorization
                    do {
                        // A nil refresh also occurs after a definitive journal
                        // commit when only the later completion read failed.
                        // Complete that exact durable outcome first; reconcile
                        // only when Store confirms retained CAS uncertainty.
                        completion = try await failedStore
                            .completeAudioCleanup(
                                using: retained,
                                operationLeaseAuthorization:
                                    operationLeaseAuthorization
                            )
                    } catch IOSFailedHistoryError.commitUncertain {
                        try await failedStore.reconcileAudioCleanupCommit(
                            receipt: nil,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        )
                        completion = try await failedStore
                            .completeAudioCleanup(
                                using: retained,
                                operationLeaseAuthorization:
                                    operationLeaseAuthorization
                            )
                    }
                    guard await cleanupState.recordCompleted(
                        completion,
                        stateAuthorization: stateAuthorization
                    ) else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                    continue
                }

                do {
                    try await failedStore.commitAudioCleanup(using: receipt)
                } catch IOSFailedHistoryError.commitUncertain {
                    if let refreshedAfterCommit = try await failedStore
                        .refreshAudioCleanupAuthorization(
                            authorization,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ) {
                        let refreshedReceipt = try await pendingStore
                            .reconcileFailedHistoryAudioCleanup(
                                using: refreshedAfterCommit,
                                operationLeaseAuthorization:
                                    operationLeaseAuthorization
                            )
                        guard await cleanupState.refreshRetiring(
                            refreshedReceipt,
                            stateAuthorization: stateAuthorization
                        ) else {
                            throw IOSAcceptedHistoryCoordinatorError
                                .localRecoveryPending
                        }
                        try await failedStore.reconcileAudioCleanupCommit(
                            receipt: refreshedReceipt,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        )
                    } else {
                        try await failedStore.reconcileAudioCleanupCommit(
                            receipt: nil,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        )
                    }
                }
                let completion = try await failedStore.completeAudioCleanup(
                    using: authorization,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
                guard await cleanupState.recordCompleted(
                    completion,
                    stateAuthorization: stateAuthorization
                ) else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }

            case .completed(let completion):
                guard mutationInterlock.clearAudioCleanup(
                    using: completion,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ), await cleanupState.clearCompleted(
                    completion,
                    stateAuthorization: stateAuthorization
                ) else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                return .cleaned
            }
        }
        throw IOSAcceptedHistoryCoordinatorError.localRecoveryPending
    }
}
