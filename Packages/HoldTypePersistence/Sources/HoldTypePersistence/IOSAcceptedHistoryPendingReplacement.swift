import Foundation

enum IOSAcceptedHistoryPendingReplacementPhase: Equatable, Sendable {
    case acceptingReplacement
    case observingCurrentDelivery
    case deliveryAuthorized(IOSAcceptedOutputDeliveryAuthorization)
    case policyConfirmed(
        IOSAcceptedOutputDeliveryAuthorization,
        IOSHistoryPolicyReceipt
    )
    case transferReserved(
        IOSAcceptedOutputPendingHistoryTransferReservation
    )
    case outboxTransferred(
        IOSAcceptedOutputPendingHistoryTransferReservation,
        IOSAcceptedHistoryOutboxReceipt
    )
    case invalidationConfirmed(
        IOSAcceptedOutputDeliveryAuthorization,
        IOSHistoryPolicyReceipt
    )
}

extension IOSAcceptedHistoryPendingReplacementPhase:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedHistoryPendingReplacementPhase(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSAcceptedHistoryPendingReplacementWork: Equatable, Sendable {
    let ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity
    let preparation: IOSAcceptedOutputDeliveryPreparation
    let phase: IOSAcceptedHistoryPendingReplacementPhase

    func replacingPhase(
        _ phase: IOSAcceptedHistoryPendingReplacementPhase
    ) -> Self {
        Self(
            ownerIdentity: ownerIdentity,
            preparation: preparation,
            phase: phase
        )
    }
}

extension IOSAcceptedHistoryPendingReplacementWork:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedHistoryPendingReplacementWork(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

actor IOSAcceptedHistoryPendingReplacementOperationState {
    private var work: IOSAcceptedHistoryPendingReplacementWork?

    func current() -> IOSAcceptedHistoryPendingReplacementWork? { work }

    func store(_ work: IOSAcceptedHistoryPendingReplacementWork) {
        self.work = work
    }

    func clear() {
        work = nil
    }
}

private enum IOSAcceptedHistoryPendingReplacementPolicyDisposition:
    Sendable {
    case matching(IOSHistoryPolicyReceipt)
    case invalidated(IOSHistoryPolicyReceipt)
}

extension IOSAcceptedHistoryCoordinator {
    static func resumePendingReplacement(
        _ initialWork: IOSAcceptedHistoryPendingReplacementWork,
        policyStore: IOSHistoryPolicyStore,
        outboxStore: IOSAcceptedHistoryOutboxStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        replacementState: IOSAcceptedHistoryPendingReplacementOperationState,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity
    ) async throws -> IOSAcceptedOutputDeliveryAcceptance {
        var work = initialWork

        while true {
            do {
                try validatePendingReplacementWork(
                    work,
                    ownerIdentity: ownerIdentity,
                    outboxStoreIdentity: outboxStore.storeIdentity
                )
            } catch {
                await replacementState.clear()
                throw error
            }
            switch work.phase {
            case .acceptingReplacement:
                do {
                    let acceptance = try await deliveryStore
                        .acceptForHistoryCoordinator(work.preparation)
                    await replacementState.clear()
                    return acceptance
                } catch IOSAcceptedOutputDeliveryError
                    .historyTransferRequired {
                    work = work.replacingPhase(.observingCurrentDelivery)
                    await replacementState.store(work)
                }

            case .observingCurrentDelivery:
                guard let observation = try await deliveryStore.load() else {
                    work = work.replacingPhase(.acceptingReplacement)
                    await replacementState.store(work)
                    continue
                }
                switch observation {
                case .active(let record):
                    if record.hasSameAcceptance(as: work.preparation) {
                        work = work.replacingPhase(.acceptingReplacement)
                        await replacementState.store(work)
                        continue
                    }
                    if record.collides(with: work.preparation) {
                        await replacementState.clear()
                        throw IOSAcceptedOutputDeliveryError.identityCollision
                    }
                    guard record.deliveryState != .discarded,
                          let marker = record.historyWrite else {
                        work = work.replacingPhase(.acceptingReplacement)
                        await replacementState.store(work)
                        continue
                    }
                    guard marker.state.isPendingDecision else {
                        let authorization = try await deliveryStore
                            .confirmActiveHistoryRecovery(
                                expected:
                                    IOSAcceptedOutputDeliveryExpectation(
                                        record: record
                                    )
                            )
                        switch try await outboxStore.classifyDeliveryAbsence(
                            authorization: authorization,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ) {
                        case .absent(let absenceAuthorization):
                            do {
                                let acceptance = try await deliveryStore
                                    .acceptForHistoryCoordinator(
                                        work.preparation,
                                        outboxAbsenceAuthorization:
                                            absenceAuthorization,
                                        operationLeaseAuthorization:
                                            operationLeaseAuthorization
                                    )
                                await replacementState.clear()
                                return acceptance
                            } catch IOSAcceptedOutputDeliveryError
                                .commitUncertain {
                                await replacementState.clear()
                                throw IOSAcceptedOutputDeliveryError
                                    .commitUncertain
                            }
                        case .matching:
                            await replacementState.clear()
                            throw IOSAcceptedOutputDeliveryError
                                .historyTransferRequired
                        case .collision:
                            await replacementState.clear()
                            throw IOSAcceptedOutputDeliveryError
                                .identityCollision
                        }
                    }
                    do {
                        let authorization = try await deliveryStore
                            .authorizePendingHistoryWrite(
                                expected:
                                    IOSAcceptedOutputDeliveryExpectation(
                                        record: record
                                    )
                            )
                        work = work.replacingPhase(
                            .deliveryAuthorized(authorization)
                        )
                        await replacementState.store(work)
                    } catch IOSAcceptedOutputDeliveryError.expired {
                        work = work.replacingPhase(.acceptingReplacement)
                        await replacementState.store(work)
                    } catch IOSAcceptedOutputDeliveryError
                        .compareAndSwapFailed {
                        work = work.replacingPhase(.acceptingReplacement)
                        await replacementState.store(work)
                    } catch IOSAcceptedOutputDeliveryError
                        .invalidTransition {
                        work = work.replacingPhase(.acceptingReplacement)
                        await replacementState.store(work)
                    }
                case .expired:
                    work = work.replacingPhase(.acceptingReplacement)
                    await replacementState.store(work)
                case .clockRollbackAmbiguous:
                    throw IOSAcceptedOutputDeliveryError
                        .clockRollbackAmbiguous
                }

            case .deliveryAuthorized(let authorization):
                let disposition = try await pendingReplacementPolicyDisposition(
                    policyStore: policyStore,
                    markerGeneration: try pendingMarkerGeneration(
                        authorization
                    )
                )
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
                await replacementState.store(work)

            case .policyConfirmed(let authorization, _):
                do {
                    let disposition = try await
                        pendingReplacementPolicyDisposition(
                            policyStore: policyStore,
                            markerGeneration: try pendingMarkerGeneration(
                                authorization
                            )
                        )
                    let refreshedPolicyReceipt: IOSHistoryPolicyReceipt
                    switch disposition {
                    case .matching(let receipt):
                        refreshedPolicyReceipt = receipt
                    case .invalidated(let invalidationReceipt):
                            work = work.replacingPhase(
                                .invalidationConfirmed(
                                    authorization,
                                    invalidationReceipt
                                )
                            )
                            await replacementState.store(work)
                        continue
                    }
                    let reservation = try await deliveryStore
                        .reservePendingHistoryTransfer(
                            authorization: authorization,
                            policyReceipt: refreshedPolicyReceipt
                        )
                    work = work.replacingPhase(
                        .transferReserved(reservation)
                    )
                    await replacementState.store(work)
                } catch IOSAcceptedOutputDeliveryError.expired {
                    work = work.replacingPhase(.acceptingReplacement)
                    await replacementState.store(work)
                } catch IOSAcceptedOutputDeliveryError
                    .compareAndSwapFailed {
                    work = work.replacingPhase(.acceptingReplacement)
                    await replacementState.store(work)
                }

            case .transferReserved(let reservation):
                do {
                    let outboxReceipt = try await outboxStore.transfer(
                        reservation: reservation
                    )
                    work = work.replacingPhase(
                        .outboxTransferred(reservation, outboxReceipt)
                    )
                    await replacementState.store(work)
                } catch IOSAcceptedHistoryOutboxError.expired {
                    try? await deliveryStore.releasePendingHistoryTransfer(
                        reservation
                    )
                    work = work.replacingPhase(.acceptingReplacement)
                    await replacementState.store(work)
                } catch IOSAcceptedHistoryOutboxError.stalePolicyGeneration {
                    try? await deliveryStore.releasePendingHistoryTransfer(
                        reservation
                    )
                    work = work.replacingPhase(
                        .deliveryAuthorized(
                            reservation.deliveryAuthorization
                        )
                    )
                    await replacementState.store(work)
                } catch IOSAcceptedHistoryOutboxError.compareAndSwapFailed {
                    try? await deliveryStore.releasePendingHistoryTransfer(
                        reservation
                    )
                    work = work.replacingPhase(
                        .deliveryAuthorized(
                            reservation.deliveryAuthorization
                        )
                    )
                    await replacementState.store(work)
                }

            case .outboxTransferred(let reservation, let outboxReceipt):
                do {
                    let record = try await deliveryStore.replacePendingHistory(
                        with: work.preparation,
                        reservation: reservation,
                        ownershipProof: IOSAcceptedOutputHistoryOwnershipProof(
                            outboxReceipt: outboxReceipt
                        )
                    )
                    await replacementState.clear()
                    return IOSAcceptedOutputDeliveryAcceptance(
                        record: record,
                        provenance: .freshCurrentProcess
                    )
                } catch IOSAcceptedOutputDeliveryError.expired {
                    try? await deliveryStore.releasePendingHistoryTransfer(
                        reservation
                    )
                    work = work.replacingPhase(.acceptingReplacement)
                    await replacementState.store(work)
                } catch IOSAcceptedOutputDeliveryError
                    .compareAndSwapFailed {
                    try? await deliveryStore.releasePendingHistoryTransfer(
                        reservation
                    )
                    work = work.replacingPhase(.acceptingReplacement)
                    await replacementState.store(work)
                }

            case .invalidationConfirmed(
                let authorization,
                let invalidationReceipt
            ):
                do {
                    _ = try await deliveryStore.cancelHistoryWrite(
                        authorization: authorization,
                        policyInvalidationReceipt: invalidationReceipt
                    )
                    work = work.replacingPhase(.acceptingReplacement)
                    await replacementState.store(work)
                } catch IOSAcceptedOutputDeliveryError.expired {
                    work = work.replacingPhase(.acceptingReplacement)
                    await replacementState.store(work)
                } catch IOSAcceptedOutputDeliveryError
                    .compareAndSwapFailed {
                    work = work.replacingPhase(.acceptingReplacement)
                    await replacementState.store(work)
                }

            }
        }
    }

    private static func pendingReplacementPolicyDisposition(
        policyStore: IOSHistoryPolicyStore,
        markerGeneration: Int64
    ) async throws -> IOSAcceptedHistoryPendingReplacementPolicyDisposition {
        guard let state = try await policyStore.load() else {
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }
        let receipt = try await policyStore.confirm(
            expected: IOSHistoryPolicyExpectation(state: state)
        )
        if receipt.state.historyEnabled,
           receipt.state.policyGeneration == markerGeneration {
            return .matching(receipt)
        }
        if receipt.state.policyGeneration > markerGeneration {
            return .invalidated(receipt)
        }
        throw IOSHistoryPolicyError.compareAndSwapFailed
    }

    private static func pendingMarkerGeneration(
        _ authorization: IOSAcceptedOutputDeliveryAuthorization
    ) throws -> Int64 {
        guard let marker = authorization.record.historyWrite,
              marker.state.isPendingDecision else {
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        return marker.policyGeneration
    }

    private static func validatePendingReplacementWork(
        _ work: IOSAcceptedHistoryPendingReplacementWork,
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity,
        outboxStoreIdentity: IOSAcceptedHistoryOutboxStoreIdentity
    ) throws {
        guard work.ownerIdentity == ownerIdentity else {
            throw IOSAcceptedOutputDeliveryError.invalidPreparation
        }
        try validateHistoryPreparation(
            preparation: work.preparation,
            ownerIdentity: ownerIdentity
        )

        switch work.phase {
        case .acceptingReplacement, .observingCurrentDelivery:
            return
        case .deliveryAuthorized(let authorization):
            try validatePendingReplacementAuthorization(
                authorization,
                preparation: work.preparation,
                ownerIdentity: ownerIdentity
            )
        case .policyConfirmed(let authorization, let receipt):
            let marker = try validatePendingReplacementAuthorization(
                authorization,
                preparation: work.preparation,
                ownerIdentity: ownerIdentity
            )
            guard receipt.capabilityOwnerIdentity == ownerIdentity,
                  receipt.state.historyEnabled,
                  receipt.state.policyGeneration
                    == marker.policyGeneration else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
        case .transferReserved(let reservation):
            let authorization = reservation.deliveryAuthorization
            let marker = try validatePendingReplacementAuthorization(
                authorization,
                preparation: work.preparation,
                ownerIdentity: ownerIdentity
            )
            guard reservation.matches(
                    authorization: authorization,
                    policyGeneration: reservation.confirmedPolicyGeneration,
                    ownerIdentity: ownerIdentity
                  ),
                  (reservation.permitsOwnershipProof(from: nil)
                    || reservation.permitsOwnershipProof(
                        from: outboxStoreIdentity
                    )),
                  reservation.confirmedPolicyGeneration
                    == marker.policyGeneration else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
        case .outboxTransferred(let reservation, let receipt):
            let authorization = reservation.deliveryAuthorization
            let marker = try validatePendingReplacementAuthorization(
                authorization,
                preparation: work.preparation,
                ownerIdentity: ownerIdentity
            )
            guard reservation.matches(
                    authorization: authorization,
                    policyGeneration: marker.policyGeneration,
                    ownerIdentity: ownerIdentity
                  ),
                  receipt.capabilityOwnerIdentity == ownerIdentity,
                  receipt.storeIdentity == outboxStoreIdentity,
                  reservation.permitsOwnershipProof(
                      from: receipt.storeIdentity
                  ),
                  receipt.provesMembershipForDeliveryRemoval(
                    for: authorization
                  ) else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
        case .invalidationConfirmed(let authorization, let receipt):
            let marker = try validatePendingReplacementAuthorization(
                authorization,
                preparation: work.preparation,
                ownerIdentity: ownerIdentity
            )
            guard receipt.capabilityOwnerIdentity == ownerIdentity,
                  receipt.state.policyGeneration
                    > marker.policyGeneration else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
        }
    }

    @discardableResult
    private static func validatePendingReplacementAuthorization(
        _ authorization: IOSAcceptedOutputDeliveryAuthorization,
        preparation: IOSAcceptedOutputDeliveryPreparation,
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity
    ) throws -> IOSAcceptedOutputHistoryWrite {
        let record = authorization.record
        guard authorization.capabilityOwnerIdentity == ownerIdentity,
              record.deliveryState != .discarded,
              record.publicationGeneration == 0,
              record.acceptedText != nil,
              let marker = record.historyWrite,
              marker.state.isPendingDecision,
              !record.hasSameAcceptance(as: preparation),
              !record.collides(with: preparation) else {
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
        return marker
    }
}
