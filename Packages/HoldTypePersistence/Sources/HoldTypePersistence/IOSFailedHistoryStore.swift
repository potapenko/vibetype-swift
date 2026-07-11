import Foundation

struct IOSFailedHistoryMetadataRetirementAuthorityMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryPendingOwnershipAbsenceProofMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryPendingRowAbsenceProofMint: Sendable {
    fileprivate init() {}
}

private final class IOSFailedHistoryPendingStoreIdentityBinding:
    @unchecked Sendable {
    private let lock = NSLock()
    private var identity: IOSPendingRecordingStoreIdentity?

    init(identity: IOSPendingRecordingStoreIdentity? = nil) {
        self.identity = identity
    }

    func bind(_ identity: IOSPendingRecordingStoreIdentity) -> Bool {
        lock.withLock {
            if let current = self.identity {
                return current == identity
            }
            self.identity = identity
            return true
        }
    }

    func current() -> IOSPendingRecordingStoreIdentity? {
        lock.withLock { identity }
    }
}

enum IOSFailedHistoryReadyCommitUncertainty: Equatable, Sendable {
    case retryReadyCommit(
        IOSFailedHistoryPendingMetadataRetirementAuthority
    )
    case readyOutcomeConfirmation(
        IOSFailedHistoryPendingMetadataRetirementAuthority
    )

    var authority: IOSFailedHistoryPendingMetadataRetirementAuthority {
        switch self {
        case .retryReadyCommit(let authority),
                .readyOutcomeConfirmation(let authority):
            authority
        }
    }
}

extension IOSFailedHistoryReadyCommitUncertainty:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryReadyCommitUncertainty(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

final class IOSFailedHistoryMutationInterlock: @unchecked Sendable {
    private let lock = NSLock()
    private var blocked = false

    var isBlocked: Bool { lock.withLock { blocked } }

    fileprivate func retainUncertainty() {
        lock.withLock { blocked = true }
    }

    fileprivate func clearUncertainty() {
        lock.withLock { blocked = false }
    }
}

struct IOSFailedHistoryStoreIdentity: Equatable, Sendable {
    private let value = UUID()
}

extension IOSFailedHistoryStoreIdentity:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSFailedHistoryStoreIdentity(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSFailedHistoryJournalMutationAuthorization: Sendable {
    let expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?

    fileprivate init(
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) {
        self.expectedRepositoryRoot = expectedRepositoryRoot
    }

    #if DEBUG
    init(testingToken: Void) {
        _ = testingToken
        self.init(expectedRepositoryRoot: nil)
    }
    #endif
}

fileprivate enum IOSFailedHistoryMutationSource: Equatable, Sendable {
    case missing
    case existing(IOSFailedHistoryJournalSnapshot)
}

fileprivate struct IOSFailedHistoryUncertainMutationIntent:
    Equatable,
    Sendable {
    let source: IOSFailedHistoryMutationSource
    let outcome: IOSFailedHistoryEnvelope
}

private enum IOSFailedHistoryTransferMutationIntent: Sendable {
    case pendingRow(
        preparation: IOSPendingFailedHistoryTransferPreparation,
        outcome: IOSFailedHistoryEnvelope
    )
    case ready(
        failedSource: IOSFailedHistoryJournalSnapshot,
        row: IOSFailedHistoryEntry,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        outcome: IOSFailedHistoryEnvelope
    )
}

struct IOSFailedHistoryMutationCapability: Equatable, Sendable {
    fileprivate let source: IOSFailedHistoryMutationSource
    fileprivate let outcome: IOSFailedHistoryEnvelope
    fileprivate let retainedIntent: IOSFailedHistoryUncertainMutationIntent?
    let storeIdentity: IOSFailedHistoryStoreIdentity
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization
    fileprivate let repositoryBinding:
        IOSAcceptedHistoryCoordinatorRepositoryBinding?

    fileprivate init(
        source: IOSFailedHistoryMutationSource,
        outcome: IOSFailedHistoryEnvelope,
        retainedIntent: IOSFailedHistoryUncertainMutationIntent?,
        storeIdentity: IOSFailedHistoryStoreIdentity,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding?
    ) {
        self.source = source
        self.outcome = outcome
        self.retainedIntent = retainedIntent
        self.storeIdentity = storeIdentity
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        self.operationLeaseAuthorization = operationLeaseAuthorization
        self.repositoryBinding = repositoryBinding
    }
}

extension IOSFailedHistoryMutationCapability:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryMutationCapability(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSFailedHistoryMutationReceipt: Equatable, Sendable {
    fileprivate let snapshot: IOSFailedHistoryJournalSnapshot
    let storeIdentity: IOSFailedHistoryStoreIdentity
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization
    fileprivate let repositoryBinding:
        IOSAcceptedHistoryCoordinatorRepositoryBinding?

    fileprivate init(
        snapshot: IOSFailedHistoryJournalSnapshot,
        storeIdentity: IOSFailedHistoryStoreIdentity,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding?
    ) {
        self.snapshot = snapshot
        self.storeIdentity = storeIdentity
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        self.operationLeaseAuthorization = operationLeaseAuthorization
        self.repositoryBinding = repositoryBinding
    }
}

extension IOSFailedHistoryMutationReceipt:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSFailedHistoryMutationReceipt(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSFailedHistoryGuardedBaselineEvidence: Sendable {
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity

    fileprivate init(
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    ) {
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
    }
}

extension IOSFailedHistoryGuardedBaselineEvidence:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryGuardedBaselineEvidence(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Internal raw repository. App-facing reads are added only with policy
/// filtering and audio-availability projection in the integration checkpoint.
actor IOSFailedHistoryStore: IOSPendingRecordingFailedOwnershipInspecting {
    nonisolated let capabilityOwnerIdentity:
        IOSAcceptedHistoryCapabilityOwnerIdentity
    nonisolated let storeIdentity: IOSFailedHistoryStoreIdentity
    private let journal: any IOSFailedHistoryJournalStoring
    private let now: @Sendable () -> Date
    private let operationGateBinding: IOSPersistenceOperationGateBinding
    private nonisolated let pendingStoreIdentityBinding:
        IOSFailedHistoryPendingStoreIdentityBinding
    private let repositoryGuard:
        IOSAcceptedHistoryCoordinatorRepositoryGuard?
    nonisolated let mutationInterlock: IOSFailedHistoryMutationInterlock
    private var uncertainMutationIntent:
        IOSFailedHistoryUncertainMutationIntent?
    private var transferMutationIntent:
        IOSFailedHistoryTransferMutationIntent?

    init(
        applicationSupportDirectoryURL: URL,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        storeIdentity: IOSFailedHistoryStoreIdentity =
            IOSFailedHistoryStoreIdentity(),
        operationGateIdentity: IOSPersistenceOperationGateIdentity? = nil,
        expectedPendingStoreIdentity:
            IOSPendingRecordingStoreIdentity? = nil,
        repositoryGuard:
            IOSAcceptedHistoryCoordinatorRepositoryGuard? = nil,
        mutationInterlock: IOSFailedHistoryMutationInterlock =
            IOSFailedHistoryMutationInterlock()
    ) {
        journal = FoundationIOSFailedHistoryJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            repositoryGuard: repositoryGuard
        )
        now = { Date() }
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        self.storeIdentity = storeIdentity
        operationGateBinding = IOSPersistenceOperationGateBinding(
            identity: operationGateIdentity
        )
        pendingStoreIdentityBinding =
            IOSFailedHistoryPendingStoreIdentityBinding(
                identity: expectedPendingStoreIdentity
            )
        self.repositoryGuard = repositoryGuard
        self.mutationInterlock = mutationInterlock
    }

    init(
        journal: any IOSFailedHistoryJournalStoring,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        storeIdentity: IOSFailedHistoryStoreIdentity =
            IOSFailedHistoryStoreIdentity(),
        operationGateIdentity: IOSPersistenceOperationGateIdentity? = nil,
        expectedPendingStoreIdentity:
            IOSPendingRecordingStoreIdentity? = nil,
        repositoryGuard:
            IOSAcceptedHistoryCoordinatorRepositoryGuard? = nil,
        mutationInterlock: IOSFailedHistoryMutationInterlock =
            IOSFailedHistoryMutationInterlock(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.journal = journal
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        self.storeIdentity = storeIdentity
        operationGateBinding = IOSPersistenceOperationGateBinding(
            identity: operationGateIdentity
        )
        pendingStoreIdentityBinding =
            IOSFailedHistoryPendingStoreIdentityBinding(
                identity: expectedPendingStoreIdentity
            )
        self.repositoryGuard = repositoryGuard
        self.mutationInterlock = mutationInterlock
        self.now = now
    }

    nonisolated func bindOperationGateIdentity(
        _ identity: IOSPersistenceOperationGateIdentity
    ) -> Bool {
        operationGateBinding.bind(identity)
    }

    nonisolated func bindExpectedPendingStoreIdentity(
        _ identity: IOSPendingRecordingStoreIdentity
    ) -> Bool {
        pendingStoreIdentityBinding.bind(identity)
    }

    func commitPendingJournalRetirement(
        _ preparation: IOSPendingFailedHistoryTransferPreparation
    ) async throws -> IOSFailedHistoryPendingMetadataRetirementAuthority {
        try requireActiveLease(preparation.operationLeaseAuthorization)
        guard uncertainMutationIntent == nil,
              transferMutationIntent == nil else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        try validate(
            preparation,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding
        )
        try await preparation.revalidateAudio()

        let source = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        let outcome = try appendingPendingJournalRetirement(
            preparation.intendedRow,
            to: source?.envelope
        )
        transferMutationIntent = .pendingRow(
            preparation: preparation,
            outcome: outcome
        )
        do {
            let capability = try reserveExactMutation(
                outcome,
                operationLeaseAuthorization:
                    preparation.operationLeaseAuthorization
            )
            guard capability.source == mutationSource(for: source) else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
            let receipt = try commitExactMutation(
                capability
            )
            return try metadataRetirementAuthority(
                receipt: receipt,
                row: preparation.intendedRow,
                origin: .committed(preparation.pendingSnapshot),
                expectedPendingStoreIdentity: pendingStoreIdentity,
                repositoryBinding: repositoryBinding,
                operationLeaseAuthorization:
                    preparation.operationLeaseAuthorization
            )
        } catch {
            if uncertainMutationIntent == nil {
                transferMutationIntent = nil
            }
            throw error
        }
    }

    /// Reconciles only the exact append retained by this Store. The original
    /// descriptor-backed preparation is revalidated, but its expired lease is
    /// never reused as mutation authority.
    func reconcilePendingJournalRetirementCommit(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryPendingMetadataRetirementAuthority {
        try requireActiveLease(operationLeaseAuthorization)
        guard uncertainMutationIntent != nil,
              case .pendingRow(let preparation, let outcome) =
                transferMutationIntent else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard preparation.operationLeaseAuthorization.provesSameActiveLease(
                  as: operationLeaseAuthorization
              ) else {
            throw IOSFailedHistoryError.commitUncertain
        }
        try validate(
            preparation,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding
        )
        try await preparation.revalidateAudio()

        let receipt = try commitExactMutation(
            reserveExactMutation(
                outcome,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        )
        return try metadataRetirementAuthority(
            receipt: receipt,
            row: preparation.intendedRow,
            origin: .committed(preparation.pendingSnapshot),
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    /// Proves that a retained pre-row preparation did not become a failed-row
    /// owner. The old preparation lease must already be dead; only this fresh
    /// store-minted proof may let the transfer state release its audio lease.
    func provePendingJournalRetirementAppendAbsent(
        for preparation: IOSPendingFailedHistoryTransferPreparation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryPendingRowAbsenceProof {
        try requireActiveLease(operationLeaseAuthorization)
        guard !preparation.operationLeaseAuthorization.provesActiveLease(),
              uncertainMutationIntent == nil,
              transferMutationIntent == nil,
              !mutationInterlock.isBlocked else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard preparation.pendingStoreIdentity == pendingStoreIdentity,
              preparation.failedStoreIdentity == storeIdentity,
              preparation.ownerIdentity == capabilityOwnerIdentity,
              preparation.repositoryBinding == repositoryBinding,
              IOSFailedHistoryPendingMatchIdentity(
                  pending: preparation.pendingSnapshot.recording
              ) == IOSFailedHistoryPendingMatchIdentity(
                  failedRow: preparation.intendedRow
              ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }

        if let envelope = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )?.envelope {
            let rowCollision = envelope.entries.contains {
                $0.attemptID == preparation.intendedRow.attemptID
                    || $0.audioRelativeIdentifier
                        == preparation.intendedRow.audioRelativeIdentifier
            }
            let cleanupCollision = envelope.audioCleanup.contains {
                $0.attemptID == preparation.intendedRow.attemptID
                    || $0.audioRelativeIdentifier
                        == preparation.intendedRow.audioRelativeIdentifier
            }
            guard !rowCollision, !cleanupCollision else {
                throw IOSFailedHistoryError.collision
            }
        }
        guard let proof = IOSFailedHistoryPendingRowAbsenceProof(
            mint: IOSFailedHistoryPendingRowAbsenceProofMint(),
            preparation: preparation,
            failedStoreIdentity: storeIdentity,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return proof
    }

    /// Reconstructs only journal-retirement authority. Policy is intentionally
    /// not consulted after the failed row became canonical.
    func makeRelaunchedPendingMetadataRetirementAuthority(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryPendingMetadataRetirementAuthority? {
        try requireActiveLease(operationLeaseAuthorization)
        try requireNoMutationUncertainty()
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard let source = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        ),
        let row = source.envelope.entries.first(where: {
            $0.ownershipState == .pendingJournalRetirement
        }) else {
            return nil
        }
        guard let authority = IOSFailedHistoryPendingMetadataRetirementAuthority(
            mint: IOSFailedHistoryMetadataRetirementAuthorityMint(),
            failedSource: source,
            row: row,
            origin: .relaunched,
            failedStoreIdentity: storeIdentity,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        return authority
    }

    func commitReady(
        using receipt: IOSPendingRecordingMetadataAbsenceReceipt
    ) throws {
        let authorization = receipt.authority.operationLeaseAuthorization
        try requireActiveLease(authorization)
        let pendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        try validate(
            receipt,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding
        )

        if let transferMutationIntent {
            guard uncertainMutationIntent != nil,
                  case .ready(
                    let failedSource,
                    let row,
                    let retainedPendingStoreIdentity,
                    let retainedRepositoryBinding,
                    let outcome
                  ) = transferMutationIntent,
                  receipt.authority.origin == .readyOutcomeConfirmation,
                  receipt.outcome.provesPreexistingAbsence,
                  receipt.authority.failedSource == failedSource,
                  receipt.authority.row == row,
                  retainedPendingStoreIdentity == pendingStoreIdentity,
                  retainedRepositoryBinding == repositoryBinding else {
                throw IOSFailedHistoryError.commitUncertain
            }
            _ = try commitExactMutation(
                reserveExactMutation(
                    outcome,
                    operationLeaseAuthorization: authorization
                )
            )
            return
        }

        guard uncertainMutationIntent == nil,
              receipt.authority.origin != .readyOutcomeConfirmation else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let failedSource = receipt.authority.failedSource
        guard try loadJournalSnapshot(repositoryBinding: repositoryBinding)
                == failedSource else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let outcome = try readyOutcome(
            from: failedSource,
            row: receipt.authority.row
        )
        transferMutationIntent = .ready(
            failedSource: failedSource,
            row: receipt.authority.row,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryBinding: repositoryBinding,
            outcome: outcome
        )
        do {
            let capability = try reserveExactMutation(
                outcome,
                operationLeaseAuthorization: authorization
            )
            guard capability.source == .existing(failedSource) else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
            _ = try commitExactMutation(
                capability
            )
        } catch {
            if uncertainMutationIntent == nil {
                transferMutationIntent = nil
            }
            throw error
        }
    }

    /// Classifies only the exact retained PJR -> ready mutation. Both cases
    /// issue proof-only authority; neither can remove a present Pending journal.
    func classifyReadyCommitUncertainty(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryReadyCommitUncertainty {
        try requireActiveLease(operationLeaseAuthorization)
        guard let uncertainMutationIntent,
              case .ready(
                let failedSource,
                let row,
                let pendingStoreIdentity,
                let retainedRepositoryBinding,
                let outcome
              ) = transferMutationIntent else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let expectedPendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        let repositoryBinding = try requireProductionRepositoryBinding()
        guard pendingStoreIdentity == expectedPendingStoreIdentity,
              retainedRepositoryBinding == repositoryBinding,
              uncertainMutationIntent.outcome == outcome else {
            throw IOSFailedHistoryError.commitUncertain
        }
        let current = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        let sourceIsVisible = current == failedSource
        let outcomeIsVisible = current?.envelope == outcome
        guard sourceIsVisible || outcomeIsVisible else {
            throw IOSFailedHistoryError.commitUncertain
        }
        guard let authority = IOSFailedHistoryPendingMetadataRetirementAuthority(
            mint: IOSFailedHistoryMetadataRetirementAuthorityMint(),
            failedSource: failedSource,
            row: row,
            origin: .readyOutcomeConfirmation,
            failedStoreIdentity: storeIdentity,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.commitUncertain
        }
        return sourceIsVisible
            ? .retryReadyCommit(authority)
            : .readyOutcomeConfirmation(authority)
    }

    func provePendingOwnershipAbsent(
        for pendingKey: IOSFailedHistoryPendingOwnershipKey,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryPendingOwnershipAbsenceProof {
        try requireActiveLease(operationLeaseAuthorization)
        try requireNoMutationUncertainty()
        let boundPendingStoreIdentity = try requireExpectedPendingStoreIdentity()
        guard expectedPendingStoreIdentity == boundPendingStoreIdentity else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        let repositoryBinding = try requireProductionRepositoryBinding()
        let source = try loadJournalSnapshot(
            repositoryBinding: repositoryBinding
        )
        if let envelope = source?.envelope {
            let rowCollision = envelope.entries.contains {
                $0.attemptID == pendingKey.attemptID
                    || $0.audioRelativeIdentifier
                        == pendingKey.audioRelativeIdentifier
            }
            let cleanupCollision = envelope.audioCleanup.contains {
                $0.attemptID == pendingKey.attemptID
                    || $0.audioRelativeIdentifier
                        == pendingKey.audioRelativeIdentifier
            }
            guard !rowCollision, !cleanupCollision else {
                throw IOSFailedHistoryError.collision
            }
        }
        guard let proof = IOSFailedHistoryPendingOwnershipAbsenceProof(
            mint: IOSFailedHistoryPendingOwnershipAbsenceProofMint(),
            failedStoreIdentity: storeIdentity,
            expectedPendingStoreIdentity: boundPendingStoreIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            pendingKey: pendingKey,
            failedSource: source,
            repositoryBinding: repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return proof
    }

    /// Raw state is coordinator-only because old policy generations and audio
    /// cleanup tombstones intentionally survive until bounded reconciliation.
    func load() throws -> IOSFailedHistoryEnvelope? {
        try requireNoMutationUncertainty()
        return try journal.load()?.envelope
    }

    func proveGuardedBaseline()
        throws -> IOSFailedHistoryGuardedBaselineEvidence {
        try requireNoMutationUncertainty()
        if let envelope = try journal.load()?.envelope {
            guard envelope.entries.isEmpty,
                  envelope.audioCleanup.isEmpty else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
        }
        return IOSFailedHistoryGuardedBaselineEvidence(
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
    }

    @discardableResult
    func performStagingMaintenance(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    )
        throws -> IOSFailedHistoryMaintenanceReport {
        try requireActiveLease(operationLeaseAuthorization)
        try requireNoMutationUncertainty()
        let repositoryBinding = try currentRepositoryBinding()
        do {
            let report = try journal.performStagingMaintenance(
                now: now(),
                expectedRepositoryRoot:
                    repositoryBinding?.physicalRootIdentity
            )
            try requireRepositoryBinding(repositoryBinding)
            return IOSFailedHistoryMaintenanceReport(report)
        } catch {
            do {
                try requireRepositoryBinding(repositoryBinding)
            } catch {
                throw IOSFailedHistoryError.repositoryIdentityConflict
            }
            throw error
        }
    }

    #if DEBUG
    func reserveExactMutationForTesting(
        _ outcome: IOSFailedHistoryEnvelope,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryMutationCapability {
        try reserveExactMutation(
            outcome,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func commitExactMutationForTesting(
        _ capability: IOSFailedHistoryMutationCapability
    ) throws -> IOSFailedHistoryMutationReceipt {
        try commitExactMutation(capability)
    }

    func mutateExactForTesting(
        _ outcome: IOSFailedHistoryEnvelope,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryMutationReceipt {
        let capability = try reserveExactMutation(
            outcome,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        return try commitExactMutation(capability)
    }

    func validateMutationReceiptForTesting(
        _ receipt: IOSFailedHistoryMutationReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryEnvelope {
        try validatedSnapshot(
            for: receipt,
            operationLeaseAuthorization: operationLeaseAuthorization
        ).envelope
    }

    func retainMutationUncertaintyForTesting() {
        mutationInterlock.retainUncertainty()
    }
    #endif
}

private extension IOSFailedHistoryStore {
    func mutationSource(
        for snapshot: IOSFailedHistoryJournalSnapshot?
    ) -> IOSFailedHistoryMutationSource {
        if let snapshot { return .existing(snapshot) }
        return .missing
    }

    func requireExpectedPendingStoreIdentity()
        throws -> IOSPendingRecordingStoreIdentity {
        guard let identity = pendingStoreIdentityBinding.current() else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return identity
    }

    func requireProductionRepositoryBinding()
        throws -> IOSAcceptedHistoryCoordinatorRepositoryBinding {
        guard let binding = try currentRepositoryBinding(),
              binding.physicalRootIdentity != nil else {
            throw IOSFailedHistoryError.repositoryIdentityConflict
        }
        return binding
    }

    func loadJournalSnapshot(
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    ) throws -> IOSFailedHistoryJournalSnapshot? {
        try requireRepositoryBinding(repositoryBinding)
        do {
            let snapshot = try journal.load()
            try requireRepositoryBinding(repositoryBinding)
            return snapshot
        } catch {
            do {
                try requireRepositoryBinding(repositoryBinding)
            } catch {
                throw IOSFailedHistoryError.repositoryIdentityConflict
            }
            throw error
        }
    }

    func validate(
        _ preparation: IOSPendingFailedHistoryTransferPreparation,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    ) throws {
        guard preparation.operationLeaseAuthorization.provesActiveLease(),
              preparation.pendingStoreIdentity
                == expectedPendingStoreIdentity,
              preparation.failedStoreIdentity == storeIdentity,
              preparation.ownerIdentity == capabilityOwnerIdentity,
              preparation.repositoryBinding == repositoryBinding,
              preparation.policyReceipt.capabilityOwnerIdentity
                == capabilityOwnerIdentity,
              preparation.policyReceipt.state.historyEnabled,
              preparation.policyReceipt.state.policyGeneration
                == preparation.intendedRow.policyGeneration,
              preparation.audioMetadataMatchesPendingSnapshot,
              IOSFailedHistoryPendingMatchIdentity(
                  pending: preparation.pendingSnapshot.recording
              ) == IOSFailedHistoryPendingMatchIdentity(
                  failedRow: preparation.intendedRow
              ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    func appendingPendingJournalRetirement(
        _ row: IOSFailedHistoryEntry,
        to current: IOSFailedHistoryEnvelope?
    ) throws -> IOSFailedHistoryEnvelope {
        guard row.ownershipState == .pendingJournalRetirement,
              row.retryCount == 0,
              row.retryOperation == nil else {
            throw IOSFailedHistoryError.invalidTransition
        }
        let entries = current?.entries ?? []
        let cleanup = current?.audioCleanup ?? []
        guard entries.count < IOSFailedHistoryValidation.maximumEntryCount,
              cleanup.count
                < IOSFailedHistoryValidation.maximumAudioCleanupCount else {
            throw IOSFailedHistoryError.capacityExceeded
        }
        guard !entries.contains(where: {
            $0.ownershipState == .pendingJournalRetirement
        }) else {
            throw IOSFailedHistoryError.slotOccupied
        }
        let rowCollision = entries.contains {
            $0.attemptID == row.attemptID
                || $0.audioRelativeIdentifier == row.audioRelativeIdentifier
        }
        let cleanupCollision = cleanup.contains {
            $0.attemptID == row.attemptID
                || $0.audioRelativeIdentifier == row.audioRelativeIdentifier
        }
        guard !rowCollision, !cleanupCollision else {
            throw IOSFailedHistoryError.collision
        }

        let revision: Int64
        if let current {
            let next = current.revision.addingReportingOverflow(1)
            guard !next.overflow else {
                throw IOSFailedHistoryError.revisionOverflow
            }
            revision = next.partialValue
        } else {
            revision = 1
        }
        return try IOSFailedHistoryEnvelope(
            revision: revision,
            entries: IOSFailedHistoryValidation.sortedEntries(entries + [row]),
            audioCleanup: cleanup
        )
    }

    func validate(
        _ receipt: IOSPendingRecordingMetadataAbsenceReceipt,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    ) throws {
        let authority = receipt.authority
        guard receipt.issuerStoreIdentity == expectedPendingStoreIdentity,
              authority.expectedPendingStoreIdentity
                == expectedPendingStoreIdentity,
              authority.failedStoreIdentity == storeIdentity,
              authority.ownerIdentity == capabilityOwnerIdentity,
              authority.repositoryBinding == repositoryBinding,
              authority.operationLeaseAuthorization.provesActiveLease(),
              receipt.evidence.binding.repositoryRoot
                == repositoryBinding.physicalRootIdentity,
              receipt.evidence.provesCanonicalPendingRecordingPath else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    func readyOutcome(
        from source: IOSFailedHistoryJournalSnapshot,
        row: IOSFailedHistoryEntry
    ) throws -> IOSFailedHistoryEnvelope {
        guard row.ownershipState == .pendingJournalRetirement,
              source.envelope.entries.contains(row) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        let next = source.envelope.revision.addingReportingOverflow(1)
        guard !next.overflow else {
            throw IOSFailedHistoryError.revisionOverflow
        }
        let readyRow = try IOSFailedHistoryEntry(
            attemptID: row.attemptID,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            policyGeneration: row.policyGeneration,
            failureCategory: row.failureCategory,
            pipelineStage: row.pipelineStage,
            retryCount: row.retryCount,
            outputIntent: row.outputIntent,
            transcriptionModel: row.transcriptionModel,
            transcriptionLanguageCode: row.transcriptionLanguageCode,
            durationMilliseconds: row.durationMilliseconds,
            byteCount: row.byteCount,
            audioRelativeIdentifier: row.audioRelativeIdentifier,
            ownershipState: .ready,
            retryOperation: row.retryOperation
        )
        guard let rowIndex = source.envelope.entries.firstIndex(of: row) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        var entries = source.envelope.entries
        entries[rowIndex] = readyRow
        return try IOSFailedHistoryEnvelope(
            revision: next.partialValue,
            entries: entries,
            audioCleanup: source.envelope.audioCleanup
        )
    }

    func metadataRetirementAuthority(
        receipt: IOSFailedHistoryMutationReceipt,
        row: IOSFailedHistoryEntry,
        origin: IOSFailedHistoryPendingMetadataRetirementAuthority.Origin,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryPendingMetadataRetirementAuthority {
        guard receipt.storeIdentity == storeIdentity,
              receipt.capabilityOwnerIdentity == capabilityOwnerIdentity,
              receipt.operationLeaseAuthorization.provesSameActiveLease(
                  as: operationLeaseAuthorization
              ),
              receipt.repositoryBinding == repositoryBinding,
              let authority =
                IOSFailedHistoryPendingMetadataRetirementAuthority(
                    mint: IOSFailedHistoryMetadataRetirementAuthorityMint(),
                    failedSource: receipt.snapshot,
                    row: row,
                    origin: origin,
                    failedStoreIdentity: storeIdentity,
                    expectedPendingStoreIdentity:
                        expectedPendingStoreIdentity,
                    ownerIdentity: capabilityOwnerIdentity,
                    repositoryBinding: repositoryBinding,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        return authority
    }

    func reserveExactMutation(
        _ outcome: IOSFailedHistoryEnvelope,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryMutationCapability {
        try requireActiveLease(operationLeaseAuthorization)
        let repositoryBinding = try currentRepositoryBinding()

        if let intent = uncertainMutationIntent {
            guard intent.outcome == outcome else {
                throw IOSFailedHistoryError.commitUncertain
            }
            let current = try journal.load()
            let sourceStillCurrent: Bool = switch (intent.source, current) {
            case (.missing, .none): true
            case (.existing(let source), .some(let current)):
                source == current
            default: false
            }
            if sourceStillCurrent {
                return mutationCapability(
                    source: intent.source,
                    outcome: outcome,
                    retainedIntent: intent,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization,
                    repositoryBinding: repositoryBinding
                )
            }
            if let current,
               current.envelope == outcome {
                return mutationCapability(
                    source: .existing(current),
                    outcome: outcome,
                    retainedIntent: intent,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization,
                    repositoryBinding: repositoryBinding
                )
            }
            throw IOSFailedHistoryError.commitUncertain
        }

        let source: IOSFailedHistoryMutationSource =
            if let current = try journal.load() {
                .existing(current)
            } else {
                .missing
            }
        try requireNextRevision(outcome, after: source)
        return mutationCapability(
            source: source,
            outcome: outcome,
            retainedIntent: nil,
            operationLeaseAuthorization: operationLeaseAuthorization,
            repositoryBinding: repositoryBinding
        )
    }

    func commitExactMutation(
        _ capability: IOSFailedHistoryMutationCapability
    ) throws -> IOSFailedHistoryMutationReceipt {
        try requireCapability(capability)
        if let retainedIntent = capability.retainedIntent {
            guard uncertainMutationIntent == retainedIntent,
                  retainedIntent.outcome == capability.outcome else {
                throw IOSFailedHistoryError.commitUncertain
            }
        } else {
            guard uncertainMutationIntent == nil else {
                throw IOSFailedHistoryError.commitUncertain
            }
        }
        return try publish(
            capability.outcome,
            source: capability.source,
            capability: capability
        )
    }

    func publish(
        _ outcome: IOSFailedHistoryEnvelope,
        source: IOSFailedHistoryMutationSource,
        capability: IOSFailedHistoryMutationCapability
    ) throws -> IOSFailedHistoryMutationReceipt {
        let attemptedIntent = IOSFailedHistoryUncertainMutationIntent(
            source: source,
            outcome: outcome
        )
        let retainedIntent = capability.retainedIntent
        do {
            try requireRepositoryBinding(capability.repositoryBinding)
            let snapshot: IOSFailedHistoryJournalSnapshot = switch source {
            case .missing:
                try journal.create(
                    outcome,
                    authorization:
                        IOSFailedHistoryJournalMutationAuthorization(
                            expectedRepositoryRoot: capability
                                .repositoryBinding?.physicalRootIdentity
                        )
                )
            case .existing(let current):
                try journal.replace(
                    outcome,
                    expected: current,
                    authorization:
                        IOSFailedHistoryJournalMutationAuthorization(
                            expectedRepositoryRoot: capability
                                .repositoryBinding?.physicalRootIdentity
                        )
                )
            }
            guard snapshot.envelope == outcome else {
                retainMutationIntent(attemptedIntent)
                throw IOSFailedHistoryError.commitUncertain
            }
            do {
                try requireRepositoryBinding(capability.repositoryBinding)
            } catch {
                retainMutationIntent(attemptedIntent)
                throw error
            }
            clearMutationIntent()
            return IOSFailedHistoryMutationReceipt(
                snapshot: snapshot,
                storeIdentity: storeIdentity,
                capabilityOwnerIdentity: capabilityOwnerIdentity,
                operationLeaseAuthorization:
                    capability.operationLeaseAuthorization,
                repositoryBinding: capability.repositoryBinding
            )
        } catch IOSFailedHistoryError.commitUncertain {
            retainMutationIntent(attemptedIntent)
            throw IOSFailedHistoryError.commitUncertain
        } catch IOSFailedHistoryError.compareAndSwapFailed {
            guard let retainedIntent else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
            retainMutationIntent(retainedIntent)
            throw IOSFailedHistoryError.commitUncertain
        } catch {
            do {
                try requireRepositoryBinding(capability.repositoryBinding)
            } catch {
                throw IOSFailedHistoryError.repositoryIdentityConflict
            }
            if let retainedIntent {
                retainMutationIntent(retainedIntent)
                throw IOSFailedHistoryError.commitUncertain
            }
            throw error
        }
    }

    func mutationCapability(
        source: IOSFailedHistoryMutationSource,
        outcome: IOSFailedHistoryEnvelope,
        retainedIntent: IOSFailedHistoryUncertainMutationIntent?,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        repositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding?
    ) -> IOSFailedHistoryMutationCapability {
        IOSFailedHistoryMutationCapability(
            source: source,
            outcome: outcome,
            retainedIntent: retainedIntent,
            storeIdentity: storeIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization,
            repositoryBinding: repositoryBinding
        )
    }

    func requireNextRevision(
        _ outcome: IOSFailedHistoryEnvelope,
        after source: IOSFailedHistoryMutationSource
    ) throws {
        switch source {
        case .missing:
            guard outcome.revision == 1 else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
        case .existing(let current):
            let next = current.envelope.revision.addingReportingOverflow(1)
            guard !next.overflow else {
                throw IOSFailedHistoryError.revisionOverflow
            }
            guard outcome.revision == next.partialValue else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
        }
    }

    func validatedSnapshot(
        for receipt: IOSFailedHistoryMutationReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSFailedHistoryJournalSnapshot {
        try requireActiveLease(operationLeaseAuthorization)
        try requireNoMutationUncertainty()
        guard receipt.storeIdentity == storeIdentity,
              receipt.capabilityOwnerIdentity == capabilityOwnerIdentity,
              receipt.operationLeaseAuthorization.provesSameActiveLease(
                  as: operationLeaseAuthorization
              ) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        try requireRepositoryBinding(receipt.repositoryBinding)
        guard let current = try journal.load(),
              current == receipt.snapshot else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        try requireRepositoryBinding(receipt.repositoryBinding)
        return current
    }

    func requireCapability(
        _ capability: IOSFailedHistoryMutationCapability
    ) throws {
        try requireActiveLease(capability.operationLeaseAuthorization)
        guard capability.storeIdentity == storeIdentity,
              capability.capabilityOwnerIdentity
                == capabilityOwnerIdentity else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        try requireRepositoryBinding(capability.repositoryBinding)
    }

    func requireActiveLease(
        _ authorization: IOSPersistenceOperationLeaseAuthorization
    ) throws {
        guard operationGateBinding.proves(authorization) else {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }

    func requireNoMutationUncertainty() throws {
        guard uncertainMutationIntent == nil else {
            throw IOSFailedHistoryError.commitUncertain
        }
    }

    func retainMutationIntent(
        _ intent: IOSFailedHistoryUncertainMutationIntent
    ) {
        uncertainMutationIntent = intent
        mutationInterlock.retainUncertainty()
    }

    func clearMutationIntent() {
        uncertainMutationIntent = nil
        transferMutationIntent = nil
        mutationInterlock.clearUncertainty()
    }

    func currentRepositoryBinding()
        throws -> IOSAcceptedHistoryCoordinatorRepositoryBinding? {
        guard let repositoryGuard else { return nil }
        do {
            return try repositoryGuard.revalidate()
        } catch {
            throw IOSFailedHistoryError.repositoryIdentityConflict
        }
    }

    func requireRepositoryBinding(
        _ expected: IOSAcceptedHistoryCoordinatorRepositoryBinding?
    ) throws {
        switch (repositoryGuard, expected) {
        case (.none, .none):
            return
        case (.some(let repositoryGuard), .some(let expected)):
            do {
                _ = try repositoryGuard.revalidate(
                    expectedBinding: expected
                )
            } catch {
                throw IOSFailedHistoryError.repositoryIdentityConflict
            }
        case (.none, .some), (.some, .none):
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
    }
}
