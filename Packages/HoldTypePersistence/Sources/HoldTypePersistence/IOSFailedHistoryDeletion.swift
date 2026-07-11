import Foundation

extension IOSAcceptedHistoryCoordinator {
    /// Commits only the selected ready failed row into durable cleanup
    /// ownership. Physical audio removal belongs to the later cleanup slice.
    func deleteFailedHistoryEntry(
        attemptID: UUID
    ) async throws -> IOSFailedHistoryTombstoneReceipt {
        guard let pendingRecordingStore else {
            throw IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        }
        let failedHistoryStore = failedHistoryStore
        let operationGate = operationGate
        let baselineRecoveryState = baselineRecoveryState
        let acceptanceState = acceptanceState
        let pendingReplacementState = pendingReplacementState
        let outboxWorkerState = outboxWorkerState
        let policyCutoverState = policyCutoverState
        let failedHistoryTransferState = failedHistoryTransferState
        let failedHistoryMutationInterlock =
            failedHistoryMutationInterlock
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

                    let receipt: IOSFailedHistoryTombstoneReceipt
                    if failedHistoryMutationInterlock.isBlocked {
                        let refreshed = try await failedHistoryStore
                            .refreshRetainedDeleteValidationAuthorization(
                                attemptID: attemptID,
                                operationLeaseAuthorization: authorization
                            )
                        let validatedAudio:
                            IOSFailedHistoryValidatedRowAudio?
                        if let refreshed {
                            validatedAudio = try await pendingRecordingStore
                                .acquireValidatedFailedHistoryRowAudio(
                                    using: refreshed,
                                    operationLeaseAuthorization: authorization
                                )
                        } else {
                            validatedAudio = nil
                        }
                        defer { validatedAudio?.release() }
                        receipt = try await failedHistoryStore
                            .reconcileDeleteCommit(
                                validatedAudio: validatedAudio,
                                operationLeaseAuthorization: authorization
                            )
                    } else {
                        guard try await failedHistoryStore
                            .hasPendingJournalRetirement(
                                operationLeaseAuthorization: authorization
                            ) == false else {
                            throw IOSAcceptedHistoryCoordinatorError
                                .localRecoveryPending
                        }
                        let deleteAuthorization = try await failedHistoryStore
                            .prepareDelete(
                                attemptID: attemptID,
                                operationLeaseAuthorization: authorization
                            )
                        let validatedAudio = try await pendingRecordingStore
                            .acquireValidatedFailedHistoryRowAudio(
                                using: deleteAuthorization,
                                operationLeaseAuthorization: authorization
                            )
                        defer { validatedAudio.release() }
                        do {
                            receipt = try await failedHistoryStore.commitDelete(
                                using: validatedAudio
                            )
                        } catch {
                            guard failedHistoryMutationInterlock.isBlocked else {
                                throw error
                            }
                            receipt = try await failedHistoryStore
                                .reconcileDeleteCommit(
                                    validatedAudio: validatedAudio,
                                    operationLeaseAuthorization: authorization
                                )
                        }
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
                    return receipt
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
}
