import Foundation

extension IOSAcceptedHistoryCoordinator {
    /// Makes the selected ready failed row durably unavailable, then attempts
    /// only that Delete receipt's exact audio cleanup under a fresh gate lease.
    /// Once the row-to-tombstone boundary is confirmed, later local-cleanup
    /// trouble never rolls the logical Delete back or reports it as uncommitted.
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
        let failedHistoryAudioCleanupState =
            failedHistoryAudioCleanupState
        let failedHistoryRetryState = failedHistoryRetryState
        let foregroundVoicePersistenceState =
            foregroundVoicePersistenceState
        let failedHistoryMutationInterlock =
            failedHistoryMutationInterlock
        let deliveryStore = deliveryStore
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration

        let logicalDelete: (
            receipt: IOSFailedHistoryTombstoneReceipt,
            cleanupStarted: Bool
        )
        do {
            logicalDelete = try await operationGate.perform { authorization in
                guard await foregroundVoicePersistenceState.current() == nil
                else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                guard await failedHistoryRetryState.hasLiveOwner() == false
                else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
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
                          await failedHistoryAudioCleanupState.current()
                            == nil,
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

                    let cleanupStarted: Bool
                    do {
                        let cleanupAuthorization = try await
                            failedHistoryStore.prepareAudioCleanup(
                                using: receipt,
                                operationLeaseAuthorization: authorization
                            )
                        if await failedHistoryAudioCleanupState.begin(
                            cleanupAuthorization,
                            stateAuthorization:
                                IOSFailedHistoryAudioCleanupStateMutationAuthorization()
                        ) {
                            cleanupStarted = true
                        } else {
                            try? await failedHistoryStore
                                .abandonPreparedAudioCleanup(
                                    using: cleanupAuthorization,
                                    operationLeaseAuthorization:
                                        authorization
                                )
                            cleanupStarted = false
                        }
                    } catch {
                        // The logical Delete is already durable. Its tombstone
                        // remains ordinary provider-free recovery authority.
                        cleanupStarted = false
                    }

                    if let repositoryBinding {
                        _ = repositoryRegistration?.revalidate(
                            expectedBinding: repositoryBinding
                        )
                    }
                    return (receipt, cleanupStarted)
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

        guard logicalDelete.cleanupStarted else {
            return logicalDelete.receipt
        }

        // The first gate turn has ended, so the validated row descriptor and
        // its old lease are released before exact physical cleanup begins.
        // Every post-boundary error leaves the operation state retained for
        // provider-free lifecycle recovery and still returns logical success.
        do {
            _ = try await operationGate.perform { authorization in
                guard await foregroundVoicePersistenceState.current() == nil
                else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                guard await failedHistoryRetryState.hasLiveOwner() == false
                else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                let repositoryBinding = repositoryRegistration?.revalidate()
                guard !repositoryIdentityState.isConflicted,
                      await baselineRecoveryState.value() == false,
                      await acceptanceState.current() == nil,
                      await pendingReplacementState.current() == nil,
                      await outboxWorkerState.current() == nil,
                      await policyCutoverState.current() == nil,
                      await failedHistoryTransferState.current() == nil,
                      await failedHistoryAudioCleanupState.current() != nil,
                      await deliveryStore
                        .hasUncertainAcceptanceForHistoryCoordinator()
                        == false,
                      await deliveryStore
                        .hasRetainedHistoryWorkForPolicyCutover()
                        == false else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                let result = try await Self.resumeFailedHistoryAudioCleanup(
                    pendingStore: pendingRecordingStore,
                    failedStore: failedHistoryStore,
                    cleanupState: failedHistoryAudioCleanupState,
                    mutationInterlock: failedHistoryMutationInterlock,
                    operationLeaseAuthorization: authorization
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
                return result
            }
        } catch {
            // Logical Delete is the user-visible success boundary. Cleanup is
            // exact, local, retained, and retryable; it never resurrects row.
        }
        return logicalDelete.receipt
    }
}
