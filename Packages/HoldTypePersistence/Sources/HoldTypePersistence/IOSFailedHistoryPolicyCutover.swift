import Foundation

fileprivate struct IOSFailedHistoryRetryCancellationReservationMint:
    Sendable {
    fileprivate init() {}
}

enum IOSFailedHistoryPolicyCutoverDirective: Equatable, Sendable {
    case retirePendingMetadata(
        IOSFailedHistoryPendingMetadataRetirementAuthority
    )
    case inspectProcessLostRetry(
        IOSFailedHistoryRetryRecoveryInspection
    )
    case completeProcessLostRetryCancellation(
        IOSFailedHistoryRetryCancellationCompletionAuthorization
    )
    case recoverAudioCleanup(
        IOSFailedHistoryAudioCleanupAuthorization
    )
    case invalidateReadyRow(
        IOSFailedHistoryRowAudioValidationAuthorization
    )
    case retainedMutationConfirmed
    case blockedAcceptingOutput
    case complete
}

/// Store-minted identity for one exact durable Retry. Unlike policy recovery
/// inspection, this token is valid for a current-generation Retry and can be
/// retained by C4.4 while its provider handoff remains live.
struct IOSFailedHistoryRetryLiveOwnerToken: Equatable, Sendable {
    let failedSource: IOSFailedHistoryJournalSnapshot
    let row: IOSFailedHistoryEntry
    let retryOperation: IOSFailedHistoryRetryOperation
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let retryStateIdentity: IOSFailedHistoryRetryLiveOwnerStateIdentity
    let repositoryBinding:
        IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRetryLiveOwnerTokenMint,
        failedSource: IOSFailedHistoryJournalSnapshot,
        row: IOSFailedHistoryEntry,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        retryStateIdentity: IOSFailedHistoryRetryLiveOwnerStateIdentity,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil,
              row.ownershipState == .ready,
              let retryOperation = row.retryOperation,
              failedSource.envelope.entries.contains(row) else {
            return nil
        }
        self.failedSource = failedSource
        self.row = row
        self.retryOperation = retryOperation
        self.failedStoreIdentity = failedStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.retryStateIdentity = retryStateIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    func identifiesSameRetry(
        as other: IOSFailedHistoryRetryLiveOwnerToken
    ) -> Bool {
        failedSource == other.failedSource
            && row == other.row
            && retryOperation == other.retryOperation
            && failedStoreIdentity == other.failedStoreIdentity
            && ownerIdentity == other.ownerIdentity
            && retryStateIdentity == other.retryStateIdentity
            && repositoryBinding == other.repositoryBinding
    }
}

struct IOSFailedHistoryRetryRecoveryInspection: Equatable, Sendable {
    let liveOwnerToken: IOSFailedHistoryRetryLiveOwnerToken
    let policyReceipt: IOSHistoryPolicyReceipt

    var failedSource: IOSFailedHistoryJournalSnapshot {
        liveOwnerToken.failedSource
    }
    var row: IOSFailedHistoryEntry { liveOwnerToken.row }
    var retryOperation: IOSFailedHistoryRetryOperation {
        liveOwnerToken.retryOperation
    }
    var failedStoreIdentity: IOSFailedHistoryStoreIdentity {
        liveOwnerToken.failedStoreIdentity
    }
    var ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity {
        liveOwnerToken.ownerIdentity
    }
    var repositoryBinding:
        IOSAcceptedHistoryCoordinatorRepositoryBinding {
        liveOwnerToken.repositoryBinding
    }
    var operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization {
        liveOwnerToken.operationLeaseAuthorization
    }

    init?(
        mint: IOSFailedHistoryRetryRecoveryInspectionMint,
        liveOwnerToken: IOSFailedHistoryRetryLiveOwnerToken,
        policyReceipt: IOSHistoryPolicyReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard policyReceipt.capabilityOwnerIdentity
                == liveOwnerToken.ownerIdentity,
              liveOwnerToken.row.policyGeneration
                < policyReceipt.state.policyGeneration,
              liveOwnerToken.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              liveOwnerToken.retryOperation.state == .reserved
                || liveOwnerToken.retryOperation.state
                    == .providerDispatched else {
            return nil
        }
        self.liveOwnerToken = liveOwnerToken
        self.policyReceipt = policyReceipt
    }

    func identifiesSameRecovery(
        as other: IOSFailedHistoryRetryRecoveryInspection
    ) -> Bool {
        liveOwnerToken.identifiesSameRetry(as: other.liveOwnerToken)
            && policyReceipt == other.policyReceipt
    }
}

struct IOSFailedHistoryRetryLiveOwnerStateIdentity: Equatable, Sendable {
    private let value = UUID()
}

struct IOSFailedHistoryRetryCancellationReservationID: Equatable, Sendable {
    private let value = UUID()
}

/// Atomic process-local ownership of the nil -> cancellation-reserved
/// transition. The stable reservation ID survives a same-recovery lease
/// refresh, while the embedded inspection always carries the active lease.
struct IOSFailedHistoryRetryCancellationReservation: Equatable, Sendable {
    let reservationID: IOSFailedHistoryRetryCancellationReservationID
    let inspection: IOSFailedHistoryRetryRecoveryInspection
    let stateIdentity: IOSFailedHistoryRetryLiveOwnerStateIdentity
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    fileprivate init?(
        mint: IOSFailedHistoryRetryCancellationReservationMint,
        reservationID: IOSFailedHistoryRetryCancellationReservationID,
        inspection: IOSFailedHistoryRetryRecoveryInspection,
        stateIdentity: IOSFailedHistoryRetryLiveOwnerStateIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              inspection.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ) else {
            return nil
        }
        self.reservationID = reservationID
        self.inspection = inspection
        self.stateIdentity = stateIdentity
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    func identifiesSameReservation(
        as other: IOSFailedHistoryRetryCancellationReservation
    ) -> Bool {
        reservationID == other.reservationID
            && inspection.identifiesSameRecovery(as: other.inspection)
            && stateIdentity == other.stateIdentity
    }
}

/// Store-minted completion-only proof. It can consume only the matching
/// process-local reservation after the exact retryOperation-nil outcome is
/// durable; it grants no row, provider, or filesystem authority.
struct IOSFailedHistoryRetryCancellationCompletionAuthorization:
    Equatable,
    Sendable {
    let reservation: IOSFailedHistoryRetryCancellationReservation
    let outcome: IOSFailedHistoryEnvelope
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding:
        IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryRetryCancellationCompletionAuthorizationMint,
        reservation: IOSFailedHistoryRetryCancellationReservation,
        outcome: IOSFailedHistoryEnvelope,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil,
              reservation.inspection.failedStoreIdentity
                == failedStoreIdentity,
              reservation.inspection.ownerIdentity == ownerIdentity,
              reservation.inspection.repositoryBinding
                == repositoryBinding else {
            return nil
        }
        self.reservation = reservation
        self.outcome = outcome
        self.failedStoreIdentity = failedStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

struct IOSFailedHistoryRetryProviderRegistrationEpoch: Equatable, Sendable {
    private let value = UUID()
}

struct IOSFailedHistoryRetryProviderLaunchEpoch: Equatable, Sendable {
    private let value = UUID()
}

struct IOSFailedHistoryRetryProviderTerminalEpoch: Equatable, Sendable {
    private let value = UUID()
}

fileprivate struct IOSFailedHistoryRetryProviderClaimMint: Sendable {
    fileprivate init() {}
}

fileprivate enum IOSFailedHistoryRetryProviderTerminalKind:
    Equatable,
    Sendable {
    case cancellation
    case completion
}

fileprivate final class IOSFailedHistoryRetryProviderLaunchPermit:
    @unchecked Sendable {
    private enum State {
        case pending
        case waiting(CheckedContinuation<Void, Error>)
        case launched
        case cancelled
    }

    private let lock = NSLock()
    private var state = State.pending

    func waitForLaunch() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let immediateResult: Result<Void, Error>? = lock.withLock {
                switch state {
                case .pending:
                    state = .waiting(continuation)
                    return nil
                case .waiting:
                    preconditionFailure("Provider launch permit has one waiter")
                case .launched:
                    return .success(())
                case .cancelled:
                    return .failure(CancellationError())
                }
            }
            if let immediateResult {
                continuation.resume(with: immediateResult)
            }
        }
    }

    func launch() {
        let continuation: CheckedContinuation<Void, Error>? =
            lock.withLock {
                switch state {
                case .pending:
                    state = .launched
                    return nil
                case .waiting(let continuation):
                    state = .launched
                    return continuation
                case .launched, .cancelled:
                    return nil
                }
            }
        continuation?.resume()
    }

    func cancel() {
        let continuation: CheckedContinuation<Void, Error>? =
            lock.withLock {
                switch state {
                case .pending:
                    state = .cancelled
                    return nil
                case .waiting(let continuation):
                    state = .cancelled
                    return continuation
                case .launched, .cancelled:
                    return nil
                }
            }
        continuation?.resume(throwing: CancellationError())
    }
}

fileprivate final class IOSFailedHistoryRetryProviderLifecycle:
    @unchecked Sendable {
    private enum Phase {
        case available
        case launchClaimed(
            IOSFailedHistoryRetryProviderLaunchEpoch,
            IOSFailedHistoryRetryProviderLaunchPermit
        )
        case running(
            IOSFailedHistoryRetryProviderLaunchEpoch,
            IOSFailedHistoryRetryProviderLaunchPermit,
            cancellation: @Sendable () -> Void,
            launched: Bool
        )
        case terminal(
            IOSFailedHistoryRetryProviderTerminalKind,
            IOSFailedHistoryRetryProviderTerminalEpoch
        )
        case retired
    }

    private struct CancellationAction {
        let terminalEpoch: IOSFailedHistoryRetryProviderTerminalEpoch
        let permit: IOSFailedHistoryRetryProviderLaunchPermit?
        let cancellation: (@Sendable () -> Void)?
    }

    private let lock = NSLock()
    private let registrationEpoch:
        IOSFailedHistoryRetryProviderRegistrationEpoch
    private var phase = Phase.available

    init(
        registrationEpoch: IOSFailedHistoryRetryProviderRegistrationEpoch
    ) {
        self.registrationEpoch = registrationEpoch
    }

    func permitsProviderDispatch(
        registrationEpoch candidate:
            IOSFailedHistoryRetryProviderRegistrationEpoch
    ) -> Bool {
        lock.withLock {
            guard registrationEpoch == candidate else { return false }
            switch phase {
            case .available, .launchClaimed, .running:
                return true
            case .terminal, .retired:
                return false
            }
        }
    }

    func claimLaunch() -> (
        IOSFailedHistoryRetryProviderLaunchEpoch,
        IOSFailedHistoryRetryProviderLaunchPermit
    )? {
        lock.withLock {
            guard case .available = phase else { return nil }
            let epoch = IOSFailedHistoryRetryProviderLaunchEpoch()
            let permit = IOSFailedHistoryRetryProviderLaunchPermit()
            phase = .launchClaimed(epoch, permit)
            return (epoch, permit)
        }
    }

    func installRunningCancellation(
        launchEpoch: IOSFailedHistoryRetryProviderLaunchEpoch,
        cancellation: @escaping @Sendable () -> Void
    ) -> Bool {
        lock.withLock {
            guard case .launchClaimed(let retainedEpoch, let permit) = phase,
                  retainedEpoch == launchEpoch else {
                return false
            }
            phase = .running(
                retainedEpoch,
                permit,
                cancellation: cancellation,
                launched: false
            )
            return true
        }
    }

    func launch(
        launchEpoch: IOSFailedHistoryRetryProviderLaunchEpoch
    ) -> Bool {
        lock.withLock {
            guard case .running(
                let retainedEpoch,
                let permit,
                let cancellation,
                false
            ) = phase, retainedEpoch == launchEpoch else {
                return false
            }
            phase = .running(
                retainedEpoch,
                permit,
                cancellation: cancellation,
                launched: true
            )
            permit.launch()
            return true
        }
    }

    func cancel() -> IOSFailedHistoryRetryProviderTerminalEpoch? {
        let action: CancellationAction? = lock.withLock {
            let permit: IOSFailedHistoryRetryProviderLaunchPermit?
            let cancellation: (@Sendable () -> Void)?
            switch phase {
            case .available:
                permit = nil
                cancellation = nil
            case .launchClaimed(_, let retainedPermit):
                permit = retainedPermit
                cancellation = nil
            case .running(_, let retainedPermit, let retainedCancellation, _):
                permit = retainedPermit
                cancellation = retainedCancellation
            case .terminal, .retired:
                return nil
            }
            let terminalEpoch =
                IOSFailedHistoryRetryProviderTerminalEpoch()
            phase = .terminal(.cancellation, terminalEpoch)
            return CancellationAction(
                terminalEpoch: terminalEpoch,
                permit: permit,
                cancellation: cancellation
            )
        }
        action?.permit?.cancel()
        action?.cancellation?()
        return action?.terminalEpoch
    }

    func complete(
        launchEpoch: IOSFailedHistoryRetryProviderLaunchEpoch
    ) -> IOSFailedHistoryRetryProviderTerminalEpoch? {
        lock.withLock {
            guard case .running(let retainedEpoch, _, _, true) = phase,
                  retainedEpoch == launchEpoch else {
                return nil
            }
            let terminalEpoch =
                IOSFailedHistoryRetryProviderTerminalEpoch()
            phase = .terminal(.completion, terminalEpoch)
            return terminalEpoch
        }
    }

    func consumeTerminal(
        kind: IOSFailedHistoryRetryProviderTerminalKind,
        epoch: IOSFailedHistoryRetryProviderTerminalEpoch
    ) -> Bool {
        lock.withLock {
            guard case .terminal(let retainedKind, let retainedEpoch) = phase,
                  retainedKind == kind,
                  retainedEpoch == epoch else {
                return false
            }
            phase = .retired
            return true
        }
    }
}

private struct IOSFailedHistoryRetryProviderStateBinding: Equatable, Sendable {
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let physicalRootIdentity: IOSPersistenceRepositoryRootIdentity
}

private final class IOSFailedHistoryRetryProviderStateBindingBox:
    @unchecked Sendable {
    private let lock = NSLock()
    private var binding: IOSFailedHistoryRetryProviderStateBinding?

    func bind(_ candidate: IOSFailedHistoryRetryProviderStateBinding) -> Bool {
        lock.withLock {
            if let binding { return binding == candidate }
            binding = candidate
            return true
        }
    }

    func matches(_ token: IOSFailedHistoryRetryLiveOwnerToken) -> Bool {
        lock.withLock {
            guard let binding,
                  let physicalRootIdentity =
                    token.repositoryBinding.physicalRootIdentity else {
                return false
            }
            return binding.failedStoreIdentity == token.failedStoreIdentity
                && binding.ownerIdentity == token.ownerIdentity
                && binding.physicalRootIdentity == physicalRootIdentity
        }
    }
}

/// Process-local provider lifecycle for one exact durable Retry.
struct IOSFailedHistoryRetryProviderRegistration: Equatable, Sendable {
    let liveOwnerToken: IOSFailedHistoryRetryLiveOwnerToken
    let epoch: IOSFailedHistoryRetryProviderRegistrationEpoch
    fileprivate let lifecycle: IOSFailedHistoryRetryProviderLifecycle

    fileprivate init(
        liveOwnerToken: IOSFailedHistoryRetryLiveOwnerToken
    ) {
        self.liveOwnerToken = liveOwnerToken
        let epoch = IOSFailedHistoryRetryProviderRegistrationEpoch()
        self.epoch = epoch
        lifecycle = IOSFailedHistoryRetryProviderLifecycle(
            registrationEpoch: epoch
        )
    }

    static func == (
        lhs: IOSFailedHistoryRetryProviderRegistration,
        rhs: IOSFailedHistoryRetryProviderRegistration
    ) -> Bool {
        lhs.epoch == rhs.epoch
            && lhs.liveOwnerToken == rhs.liveOwnerToken
            && lhs.lifecycle === rhs.lifecycle
    }

    /// Proves that this exact live registration still owns the exact durable
    /// provider dispatch. The registration epoch is process-local and cannot
    /// be reconstructed from a copyable Store receipt.
    func provesProviderDispatch(
        _ receipt: IOSFailedHistoryRetryDispatchReceipt
    ) -> Bool {
        guard liveOwnerToken.retryOperation.state == .providerDispatched,
              receipt.retryOperation.state == .providerDispatched,
              lifecycle.permitsProviderDispatch(
                registrationEpoch: epoch
              ),
              liveOwnerToken == receipt.liveOwnerToken,
              liveOwnerToken.failedSource == receipt.durableSnapshot,
              liveOwnerToken.row == receipt.row,
              liveOwnerToken.retryOperation == receipt.retryOperation,
              liveOwnerToken.failedStoreIdentity
                == receipt.failedStoreIdentity,
              liveOwnerToken.ownerIdentity == receipt.ownerIdentity,
              liveOwnerToken.repositoryBinding == receipt.repositoryBinding,
              let registrationRoot = liveOwnerToken.repositoryBinding
                .physicalRootIdentity,
              let receiptRoot = receipt.repositoryBinding
                .physicalRootIdentity,
              registrationRoot == receiptRoot else {
            return false
        }
        return true
    }

    fileprivate func claimLaunch()
        -> IOSFailedHistoryRetryProviderLaunchClaim? {
        guard liveOwnerToken.retryOperation.state == .providerDispatched,
              let (launchEpoch, permit) = lifecycle.claimLaunch() else {
            return nil
        }
        return IOSFailedHistoryRetryProviderLaunchClaim(
            mint: IOSFailedHistoryRetryProviderClaimMint(),
            registration: self,
            launchEpoch: launchEpoch,
            permit: permit
        )
    }

    fileprivate func cancel()
        -> IOSFailedHistoryRetryProviderTerminalEpoch? {
        lifecycle.cancel()
    }

    fileprivate func consumeTerminal(
        kind: IOSFailedHistoryRetryProviderTerminalKind,
        epoch: IOSFailedHistoryRetryProviderTerminalEpoch
    ) -> Bool {
        lifecycle.consumeTerminal(kind: kind, epoch: epoch)
    }
}

struct IOSFailedHistoryRetryProviderLaunchClaim: Equatable, Sendable {
    let liveOwnerToken: IOSFailedHistoryRetryLiveOwnerToken
    let registrationEpoch: IOSFailedHistoryRetryProviderRegistrationEpoch
    let launchEpoch: IOSFailedHistoryRetryProviderLaunchEpoch
    private let lifecycle: IOSFailedHistoryRetryProviderLifecycle
    private let permit: IOSFailedHistoryRetryProviderLaunchPermit

    fileprivate init(
        mint: IOSFailedHistoryRetryProviderClaimMint,
        registration: IOSFailedHistoryRetryProviderRegistration,
        launchEpoch: IOSFailedHistoryRetryProviderLaunchEpoch,
        permit: IOSFailedHistoryRetryProviderLaunchPermit
    ) {
        _ = mint
        liveOwnerToken = registration.liveOwnerToken
        registrationEpoch = registration.epoch
        self.launchEpoch = launchEpoch
        lifecycle = registration.lifecycle
        self.permit = permit
    }

    static func == (
        lhs: IOSFailedHistoryRetryProviderLaunchClaim,
        rhs: IOSFailedHistoryRetryProviderLaunchClaim
    ) -> Bool {
        lhs.liveOwnerToken == rhs.liveOwnerToken
            && lhs.registrationEpoch == rhs.registrationEpoch
            && lhs.launchEpoch == rhs.launchEpoch
            && lhs.lifecycle === rhs.lifecycle
            && lhs.permit === rhs.permit
    }

    func installRunningCancellation(
        _ cancellation: @escaping @Sendable () -> Void
    ) -> Bool {
        lifecycle.installRunningCancellation(
            launchEpoch: launchEpoch,
            cancellation: cancellation
        )
    }

    func waitForLaunch() async throws {
        try await permit.waitForLaunch()
    }

    func launch() -> Bool {
        lifecycle.launch(launchEpoch: launchEpoch)
    }

    fileprivate func complete()
        -> IOSFailedHistoryRetryProviderTerminalEpoch? {
        lifecycle.complete(launchEpoch: launchEpoch)
    }

    fileprivate func belongs(
        to registration: IOSFailedHistoryRetryProviderRegistration
    ) -> Bool {
        liveOwnerToken == registration.liveOwnerToken
            && registrationEpoch == registration.epoch
            && lifecycle === registration.lifecycle
    }
}

struct IOSFailedHistoryRetryProviderCancellationClaim: Equatable, Sendable {
    let liveOwnerToken: IOSFailedHistoryRetryLiveOwnerToken
    let registrationEpoch: IOSFailedHistoryRetryProviderRegistrationEpoch
    let terminalEpoch: IOSFailedHistoryRetryProviderTerminalEpoch
    private let lifecycle: IOSFailedHistoryRetryProviderLifecycle

    fileprivate init(
        mint: IOSFailedHistoryRetryProviderClaimMint,
        registration: IOSFailedHistoryRetryProviderRegistration,
        terminalEpoch: IOSFailedHistoryRetryProviderTerminalEpoch
    ) {
        _ = mint
        liveOwnerToken = registration.liveOwnerToken
        registrationEpoch = registration.epoch
        self.terminalEpoch = terminalEpoch
        lifecycle = registration.lifecycle
    }

    static func == (
        lhs: IOSFailedHistoryRetryProviderCancellationClaim,
        rhs: IOSFailedHistoryRetryProviderCancellationClaim
    ) -> Bool {
        lhs.liveOwnerToken == rhs.liveOwnerToken
            && lhs.registrationEpoch == rhs.registrationEpoch
            && lhs.terminalEpoch == rhs.terminalEpoch
            && lhs.lifecycle === rhs.lifecycle
    }

    fileprivate func belongs(
        to registration: IOSFailedHistoryRetryProviderRegistration
    ) -> Bool {
        liveOwnerToken == registration.liveOwnerToken
            && registrationEpoch == registration.epoch
            && lifecycle === registration.lifecycle
    }
}

struct IOSFailedHistoryRetryProviderCompletionClaim: Equatable, Sendable {
    let liveOwnerToken: IOSFailedHistoryRetryLiveOwnerToken
    let registrationEpoch: IOSFailedHistoryRetryProviderRegistrationEpoch
    let terminalEpoch: IOSFailedHistoryRetryProviderTerminalEpoch
    private let lifecycle: IOSFailedHistoryRetryProviderLifecycle

    fileprivate init(
        mint: IOSFailedHistoryRetryProviderClaimMint,
        registration: IOSFailedHistoryRetryProviderRegistration,
        terminalEpoch: IOSFailedHistoryRetryProviderTerminalEpoch
    ) {
        _ = mint
        liveOwnerToken = registration.liveOwnerToken
        registrationEpoch = registration.epoch
        self.terminalEpoch = terminalEpoch
        lifecycle = registration.lifecycle
    }

    static func == (
        lhs: IOSFailedHistoryRetryProviderCompletionClaim,
        rhs: IOSFailedHistoryRetryProviderCompletionClaim
    ) -> Bool {
        lhs.liveOwnerToken == rhs.liveOwnerToken
            && lhs.registrationEpoch == rhs.registrationEpoch
            && lhs.terminalEpoch == rhs.terminalEpoch
            && lhs.lifecycle === rhs.lifecycle
    }

    fileprivate func belongs(
        to registration: IOSFailedHistoryRetryProviderRegistration
    ) -> Bool {
        liveOwnerToken == registration.liveOwnerToken
            && registrationEpoch == registration.epoch
            && lifecycle === registration.lifecycle
    }
}

enum IOSFailedHistoryRetryProviderTerminalClaim: Equatable, Sendable {
    case cancellation(IOSFailedHistoryRetryProviderCancellationClaim)
    case completion(IOSFailedHistoryRetryProviderCompletionClaim)

    var liveOwnerToken: IOSFailedHistoryRetryLiveOwnerToken {
        switch self {
        case .cancellation(let claim): return claim.liveOwnerToken
        case .completion(let claim): return claim.liveOwnerToken
        }
    }

    var registrationEpoch:
        IOSFailedHistoryRetryProviderRegistrationEpoch {
        switch self {
        case .cancellation(let claim): return claim.registrationEpoch
        case .completion(let claim): return claim.registrationEpoch
        }
    }

    var terminalEpoch: IOSFailedHistoryRetryProviderTerminalEpoch {
        switch self {
        case .cancellation(let claim): return claim.terminalEpoch
        case .completion(let claim): return claim.terminalEpoch
        }
    }
}

protocol IOSFailedHistoryRetryProviderTerminalOwner: AnyObject, Sendable {
    func requestCancellation()
    func requestProviderCompletionRecovery()
}

actor IOSFailedHistoryRetryLiveOwnerState {
    private enum Phase: Equatable, Sendable {
        case idle
        case recoveryGuard(IOSFailedHistoryRetryLiveOwnerToken)
        case provider(IOSFailedHistoryRetryProviderRegistration)
        case cancellationReserved(
            IOSFailedHistoryRetryCancellationReservation
        )
    }

    nonisolated let identity =
        IOSFailedHistoryRetryLiveOwnerStateIdentity()
    private nonisolated let providerBinding =
        IOSFailedHistoryRetryProviderStateBindingBox()
    private var phase: Phase = .idle
    private var retainedProviderCancellationClaim:
        IOSFailedHistoryRetryProviderCancellationClaim?
    private var retainedProviderCompletionClaim:
        IOSFailedHistoryRetryProviderCompletionClaim?
    private var retainedProviderTerminalOwner:
        (any IOSFailedHistoryRetryProviderTerminalOwner)?

    nonisolated func bindProviderRegistration(
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        physicalRootIdentity: IOSPersistenceRepositoryRootIdentity
    ) -> Bool {
        providerBinding.bind(
            IOSFailedHistoryRetryProviderStateBinding(
                failedStoreIdentity: failedStoreIdentity,
                ownerIdentity: ownerIdentity,
                physicalRootIdentity: physicalRootIdentity
            )
        )
    }

    func hasLiveOwner() -> Bool {
        switch phase {
        case .recoveryGuard, .provider:
            return true
        case .idle, .cancellationReserved:
            return false
        }
    }

    func hasCancellationReservation() -> Bool {
        if case .cancellationReserved = phase { return true }
        return false
    }

    func registerLiveOwner(
        _ token: IOSFailedHistoryRetryLiveOwnerToken
    ) -> IOSFailedHistoryRetryProviderRegistration? {
        guard phase == .idle,
              retainedProviderCancellationClaim == nil,
              retainedProviderCompletionClaim == nil,
              retainedProviderTerminalOwner == nil,
              token.retryOperation.state == .providerDispatched,
              token.retryStateIdentity == identity,
              token.operationLeaseAuthorization.provesActiveLease(),
              providerBinding.matches(token) else {
            return nil
        }
        let registration = IOSFailedHistoryRetryProviderRegistration(
            liveOwnerToken: token
        )
        phase = .provider(registration)
        return registration
    }

    func retainLiveOwner(
        _ token: IOSFailedHistoryRetryLiveOwnerToken
    ) -> Bool {
        guard phase == .idle,
              retainedProviderCancellationClaim == nil,
              retainedProviderCompletionClaim == nil,
              retainedProviderTerminalOwner == nil,
              token.retryOperation.state == .reserved,
              token.retryStateIdentity == identity,
              token.operationLeaseAuthorization.provesActiveLease() else {
            return false
        }
        phase = .recoveryGuard(token)
        return true
    }

    func retainLiveOwner(
        of inspection: IOSFailedHistoryRetryRecoveryInspection
    ) -> Bool {
        retainLiveOwner(inspection.liveOwnerToken)
    }

    @discardableResult
    func clearLiveOwner(
        _ token: IOSFailedHistoryRetryLiveOwnerToken
    ) -> Bool {
        guard case .recoveryGuard(let retained) = phase,
              retained == token else {
            return false
        }
        phase = .idle
        return true
    }

    @discardableResult
    func clearLiveOwner(
        _ registration: IOSFailedHistoryRetryProviderRegistration
    ) -> Bool {
        _ = registration
        return false
    }

    @discardableResult
    func clearLiveOwner(
        of inspection: IOSFailedHistoryRetryRecoveryInspection
    ) -> Bool {
        clearLiveOwner(inspection.liveOwnerToken)
    }

    func claimProviderLaunch(
        _ registration: IOSFailedHistoryRetryProviderRegistration
    ) -> IOSFailedHistoryRetryProviderLaunchClaim? {
        guard case .provider(let retained) = phase,
              retained == registration else {
            return nil
        }
        return retained.claimLaunch()
    }

    func retainProviderTerminalOwner(
        _ owner: any IOSFailedHistoryRetryProviderTerminalOwner,
        for registration: IOSFailedHistoryRetryProviderRegistration
    ) -> Bool {
        guard case .provider(let retained) = phase,
              retained == registration else {
            return false
        }
        if let retainedProviderTerminalOwner {
            return retainedProviderTerminalOwner === owner
        }
        retainedProviderTerminalOwner = owner
        return true
    }

    @discardableResult
    func requestRetainedProviderCancellation() -> Bool {
        guard case .provider = phase,
              retainedProviderCancellationClaim != nil,
              let retainedProviderTerminalOwner else {
            return false
        }
        retainedProviderTerminalOwner.requestCancellation()
        return true
    }

    /// Retriggers only an already-completed provider's retained terminal work.
    /// It never invents a failure disposition or replays provider work.
    @discardableResult
    func requestRetainedProviderCompletionRecovery() -> Bool {
        guard case .provider = phase,
              retainedProviderCompletionClaim != nil,
              let retainedProviderTerminalOwner else {
            return false
        }
        retainedProviderTerminalOwner.requestProviderCompletionRecovery()
        return true
    }

    func claimProviderCancellation(
        _ registration: IOSFailedHistoryRetryProviderRegistration
    ) -> IOSFailedHistoryRetryProviderTerminalClaim? {
        guard case .provider(let retained) = phase,
              retained == registration else {
            return nil
        }
        if let retainedProviderCancellationClaim,
           retainedProviderCancellationClaim.belongs(to: retained) {
            return .cancellation(retainedProviderCancellationClaim)
        }
        guard let terminalEpoch = retained.cancel() else { return nil }
        let claim = IOSFailedHistoryRetryProviderCancellationClaim(
            mint: IOSFailedHistoryRetryProviderClaimMint(),
            registration: retained,
            terminalEpoch: terminalEpoch
        )
        retainedProviderCancellationClaim = claim
        return .cancellation(claim)
    }

    /// Re-exposes only the already-minted exact claim so retained Store
    /// uncertainty can resume without inventing a new terminal epoch.
    func retainedProviderCancellation(
        _ registration: IOSFailedHistoryRetryProviderRegistration
    ) -> IOSFailedHistoryRetryProviderCancellationClaim? {
        guard case .provider(let retained) = phase,
              retained == registration,
              let retainedProviderCancellationClaim,
              retainedProviderCancellationClaim.belongs(to: retained) else {
            return nil
        }
        return retainedProviderCancellationClaim
    }

    func claimProviderCompletion(
        _ launchClaim: IOSFailedHistoryRetryProviderLaunchClaim
    ) -> IOSFailedHistoryRetryProviderTerminalClaim? {
        guard case .provider(let registration) = phase,
              launchClaim.belongs(to: registration),
              let terminalEpoch = launchClaim.complete() else {
            return nil
        }
        let claim = IOSFailedHistoryRetryProviderCompletionClaim(
            mint: IOSFailedHistoryRetryProviderClaimMint(),
            registration: registration,
            terminalEpoch: terminalEpoch
        )
        retainedProviderCompletionClaim = claim
        return .completion(claim)
    }

    /// Re-exposes only the already-minted exact completion claim so the
    /// provider-completed durable failure may reconcile Store uncertainty
    /// without minting another terminal epoch.
    func retainedProviderCompletion(
        _ registration: IOSFailedHistoryRetryProviderRegistration
    ) -> IOSFailedHistoryRetryProviderCompletionClaim? {
        guard case .provider(let retained) = phase,
              retained == registration,
              let retainedProviderCompletionClaim,
              retainedProviderCompletionClaim.belongs(to: retained) else {
            return nil
        }
        return retainedProviderCompletionClaim
    }

    /// Retires only the exact provider completion whose Store receipt proves
    /// that the matching failed Retry has been retained durably without an
    /// active retry operation.
    @discardableResult
    func consumeProviderFailure(
        using receipt: IOSFailedHistoryRetryFailureReceipt
    ) -> Bool {
        let completion = receipt.providerCompletionClaim
        guard receipt.operationLeaseAuthorization.provesActiveLease(),
              receipt.row.retryOperation == nil,
              receipt.durableSnapshot.envelope.entries.contains(receipt.row),
              receipt.authorization.providerCompletionClaim == completion,
              completion.liveOwnerToken.retryOperation
                == receipt.retryOperation,
              completion.liveOwnerToken.failedStoreIdentity
                == receipt.failedStoreIdentity,
              completion.liveOwnerToken.ownerIdentity
                == receipt.ownerIdentity,
              completion.liveOwnerToken.repositoryBinding
                == receipt.repositoryBinding,
              retainedProviderCompletionClaim == completion,
              case .provider(let registration) = phase,
              completion.belongs(to: registration),
              registration.consumeTerminal(
                  kind: .completion,
                  epoch: completion.terminalEpoch
              ) else {
            return false
        }
        retainedProviderCancellationClaim = nil
        retainedProviderCompletionClaim = nil
        retainedProviderTerminalOwner = nil
        phase = .idle
        return true
    }

    /// Retires only the exact provider completion whose Store receipt proves
    /// the matching Retry delivery is terminal and its failed row has moved to
    /// durable audio-cleanup ownership.
    @discardableResult
    func consumeProviderSuccess(
        using receipt: IOSFailedHistoryRetrySuccessReceipt
    ) -> Bool {
        let completion = receipt.providerCompletionClaim
        guard receipt.operationLeaseAuthorization.provesActiveLease(),
              receipt.durableSnapshot.envelope.audioCleanup.contains(
                receipt.tombstone
              ),
              (receipt.terminalDeliveryProof.deliveryAuthorization.record
                .historyWrite?.state == .committed
                || receipt.terminalDeliveryProof.deliveryAuthorization.record
                    .historyWrite?.state == .cancelled),
              completion.liveOwnerToken.retryOperation
                == receipt.authorization.acceptingOutputReceipt
                    .authorization.providerDispatchedOperation,
              completion.liveOwnerToken.failedStoreIdentity
                == receipt.failedStoreIdentity,
              completion.liveOwnerToken.ownerIdentity
                == receipt.ownerIdentity,
              completion.liveOwnerToken.repositoryBinding
                == receipt.repositoryBinding,
              retainedProviderCompletionClaim == completion,
              case .provider(let registration) = phase,
              completion.belongs(to: registration),
              registration.consumeTerminal(
                  kind: .completion,
                  epoch: completion.terminalEpoch
              ) else {
            return false
        }
        retainedProviderCancellationClaim = nil
        retainedProviderCompletionClaim = nil
        retainedProviderTerminalOwner = nil
        phase = .idle
        return true
    }

    /// Retires only an exact provider cancellation whose Store receipt proves
    /// that the matching durable retry operation is already absent.
    @discardableResult
    func consumeProviderCancellation(
        using receipt: IOSFailedHistoryRetryCancellationReceipt
    ) -> Bool {
        guard receipt.operationLeaseAuthorization.provesActiveLease(),
              receipt.row.retryOperation == nil,
              receipt.durableSnapshot.envelope.entries.contains(receipt.row),
              let cancellation = receipt.authorization
                .providerCancellationClaim,
              cancellation.liveOwnerToken.retryOperation
                == receipt.retryOperation,
              cancellation.liveOwnerToken.failedStoreIdentity
                == receipt.failedStoreIdentity,
              cancellation.liveOwnerToken.ownerIdentity
                == receipt.ownerIdentity,
              cancellation.liveOwnerToken.repositoryBinding
                == receipt.repositoryBinding,
              case .provider(let registration) = phase,
              cancellation.belongs(to: registration),
              registration.consumeTerminal(
                  kind: .cancellation,
                  epoch: cancellation.terminalEpoch
              ) else {
            return false
        }
        retainedProviderCancellationClaim = nil
        retainedProviderCompletionClaim = nil
        retainedProviderTerminalOwner = nil
        phase = .idle
        return true
    }

    #if DEBUG
    /// Unit-test-only lifecycle probe. Production terminal retirement requires
    /// the Store-minted durable receipt above.
    @discardableResult
    func consumeProviderTerminal(
        _ claim: IOSFailedHistoryRetryProviderTerminalClaim
    ) -> Bool {
        guard case .provider(let registration) = phase else { return false }
        let consumed: Bool
        switch claim {
        case .cancellation(let cancellation):
            guard cancellation.belongs(to: registration) else { return false }
            consumed = registration.consumeTerminal(
                kind: .cancellation,
                epoch: cancellation.terminalEpoch
            )
        case .completion(let completion):
            guard completion.belongs(to: registration) else { return false }
            consumed = registration.consumeTerminal(
                kind: .completion,
                epoch: completion.terminalEpoch
            )
        }
        guard consumed else { return false }
        retainedProviderCancellationClaim = nil
        retainedProviderCompletionClaim = nil
        retainedProviderTerminalOwner = nil
        phase = .idle
        return true
    }
    #endif

    func reserveProcessLostCancellation(
        of inspection: IOSFailedHistoryRetryRecoveryInspection,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) -> IOSFailedHistoryRetryCancellationReservation? {
        let reservationID: IOSFailedHistoryRetryCancellationReservationID
        switch phase {
        case .idle:
            guard retainedProviderCancellationClaim == nil,
                  retainedProviderCompletionClaim == nil,
                  retainedProviderTerminalOwner == nil else {
                return nil
            }
            reservationID = IOSFailedHistoryRetryCancellationReservationID()
        case .recoveryGuard, .provider:
            // The lease proves that registration was minted under the root
            // gate; it does not bound the lifetime of provider work after that
            // gate turn ends. Only exact owner completion may return this
            // process-local state to idle. A relaunched process receives a new
            // idle state instead of reclassifying this live owner locally.
            return nil
        case .cancellationReserved(let retained):
            // An active reservation is consumable and cannot be minted twice.
            // An inactive one refreshes only from the Store's exact same
            // source/row/retry recovery inspection under the new lease.
            guard !retained.operationLeaseAuthorization.provesActiveLease(),
                  retained.inspection.identifiesSameRecovery(
                    as: inspection
                  ) else {
                return nil
            }
            reservationID = retained.reservationID
        }
        guard let reservation =
                IOSFailedHistoryRetryCancellationReservation(
                    mint:
                        IOSFailedHistoryRetryCancellationReservationMint(),
                    reservationID: reservationID,
                    inspection: inspection,
                    stateIdentity: identity,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            return nil
        }
        phase = .cancellationReserved(reservation)
        return reservation
    }

    func authorizeProcessLostCancellation(
        of inspection: IOSFailedHistoryRetryRecoveryInspection,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) -> IOSFailedHistoryRetryCancellationReservation? {
        reserveProcessLostCancellation(
            of: inspection,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    @discardableResult
    func consumeCancellationReservation(
        using completion:
            IOSFailedHistoryRetryCancellationCompletionAuthorization
    ) -> Bool {
        guard completion.operationLeaseAuthorization.provesActiveLease(),
              completion.reservation.stateIdentity == identity,
              case .cancellationReserved(let retained) = phase,
              retained.identifiesSameReservation(
                as: completion.reservation
              ) else {
            return false
        }
        phase = .idle
        return true
    }
}

struct IOSFailedHistoryPolicyRetryCancellationAuthorization:
    Equatable,
    Sendable {
    let inspection: IOSFailedHistoryRetryRecoveryInspection
    let reservation: IOSFailedHistoryRetryCancellationReservation
    let outcome: IOSFailedHistoryEnvelope
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding:
        IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryPolicyRetryCancellationAuthorizationMint,
        inspection: IOSFailedHistoryRetryRecoveryInspection,
        reservation: IOSFailedHistoryRetryCancellationReservation,
        outcome: IOSFailedHistoryEnvelope,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        let nextRevision = inspection.failedSource.envelope.revision
            .addingReportingOverflow(1)
        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil,
              inspection.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              reservation.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              reservation.inspection == inspection,
              inspection.failedStoreIdentity == failedStoreIdentity,
              inspection.ownerIdentity == ownerIdentity,
              inspection.repositoryBinding == repositoryBinding,
              !nextRevision.overflow,
              outcome.revision == nextRevision.partialValue,
              outcome.audioCleanup
                == inspection.failedSource.envelope.audioCleanup,
              let sourceIndex = inspection.failedSource.envelope.entries
                .firstIndex(of: inspection.row),
              outcome.entries.indices.contains(sourceIndex),
              outcome.entries[sourceIndex].attemptID
                == inspection.row.attemptID,
              outcome.entries[sourceIndex].retryOperation == nil else {
            return nil
        }
        self.inspection = inspection
        self.reservation = reservation
        self.outcome = outcome
        self.failedStoreIdentity = failedStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    func identifiesSameCancellation(
        as other: IOSFailedHistoryPolicyRetryCancellationAuthorization
    ) -> Bool {
        inspection.identifiesSameRecovery(as: other.inspection)
            && reservation.identifiesSameReservation(
                as: other.reservation
            )
            && outcome == other.outcome
            && failedStoreIdentity == other.failedStoreIdentity
            && ownerIdentity == other.ownerIdentity
            && repositoryBinding == other.repositoryBinding
    }
}

enum IOSFailedHistoryPolicyRetryCancellationPreparation: Equatable, Sendable {
    case commit(IOSFailedHistoryPolicyRetryCancellationAuthorization)
    case completed(
        IOSFailedHistoryRetryCancellationCompletionAuthorization
    )
}

extension IOSFailedHistoryPolicyCutoverDirective:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryPolicyCutoverDirective(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryLiveOwnerToken:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryLiveOwnerToken(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryRecoveryInspection:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryRecoveryInspection(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryLiveOwnerStateIdentity:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryLiveOwnerStateIdentity(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryCancellationReservationID:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryCancellationReservationID(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryCancellationReservation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryCancellationReservation(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryCancellationCompletionAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryCancellationCompletionAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryProviderRegistration:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryProviderRegistration(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryProviderRegistrationEpoch:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryProviderRegistrationEpoch(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryProviderLaunchEpoch:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryProviderLaunchEpoch(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryProviderTerminalEpoch:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryProviderTerminalEpoch(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryProviderLaunchClaim:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryProviderLaunchClaim(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryProviderCancellationClaim:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryProviderCancellationClaim(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryProviderCompletionClaim:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryProviderCompletionClaim(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryProviderTerminalClaim:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryProviderTerminalClaim(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryPolicyRetryCancellationAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryPolicyRetryCancellationAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryPolicyRetryCancellationPreparation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryPolicyRetryCancellationPreparation(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
