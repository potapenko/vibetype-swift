import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSFailedHistoryPolicyCutoverStoreTests {
    @Test func unboundStrictEmptyCompletesButNonemptyFailsClosed()
        async throws {
        let fixture = try PolicyCutoverStoreFixture(productionBound: false)
        let policy = try await fixture.policyReceipt(generation: 2)

        try await fixture.gate.perform { lease in
            let directive = try await fixture.store
                .preparePolicyCutoverDirective(
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            #expect(directive == .complete)
        }

        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [],
                audioCleanup: []
            )
        )
        try await fixture.gate.perform { lease in
            let directive = try await fixture.store
                .preparePolicyCutoverDirective(
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            #expect(directive == .complete)
        }

        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [try failedHistoryTestEntry(policyGeneration: 1)],
                audioCleanup: []
            )
        )
        await #expect(
            throws: IOSFailedHistoryError.repositoryIdentityConflict
        ) {
            try await fixture.gate.perform { lease in
                _ = try await fixture.store.preparePolicyCutoverDirective(
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            }
        }
    }

    @Test func policyReadFiltersExactlyAndFutureStatePrecedesCleanup()
        async throws {
        let fixture = try PolicyCutoverStoreFixture()
        let current = try failedHistoryTestEntry(
            index: 3,
            policyGeneration: 3
        )
        let stale = try failedHistoryTestEntry(
            index: 2,
            policyGeneration: 2
        )
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: IOSFailedHistoryValidation.sortedEntries([
                    current,
                    stale,
                ]),
                audioCleanup: []
            )
        )
        let enabled = try await fixture.policyReceipt(generation: 3)
        let disabled = try await fixture.policyReceipt(
            generation: 3,
            enabled: false
        )
        try await fixture.gate.perform { lease in
            let visible = try await fixture.store
                .loadPolicyFilteredEntries(
                    using: enabled,
                    operationLeaseAuthorization: lease
                )
            let hidden = try await fixture.store
                .loadPolicyFilteredEntries(
                    using: disabled,
                    operationLeaseAuthorization: lease
                )
            #expect(visible == [current])
            #expect(hidden.isEmpty)
        }

        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 2,
                entries: [current],
                audioCleanup: [
                    try failedHistoryTestAudioCleanup(
                        index: 8,
                        policyGeneration: 4
                    ),
                ]
            )
        )
        fixture.fileSystem.resetEvents()
        await #expect(
            throws: IOSFailedHistoryError.stalePolicyGeneration
        ) {
            try await fixture.gate.perform { lease in
                _ = try await fixture.store.preparePolicyCutoverDirective(
                    using: enabled,
                    operationLeaseAuthorization: lease
                )
            }
        }
        #expect(!fixture.mutationInterlock.isBlocked)
        #expect(!fixture.fileSystem.events.contains("replace"))
    }

    @Test func futureRowFailsClosedForReadAndCleanupWithoutMutation()
        async throws {
        let fixture = try PolicyCutoverStoreFixture()
        let policy = try await fixture.policyReceipt(generation: 3)
        let future = try failedHistoryTestEntry(
            index: 9,
            policyGeneration: 4
        )
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 3,
                entries: [future],
                audioCleanup: []
            )
        )

        await #expect(
            throws: IOSFailedHistoryError.stalePolicyGeneration
        ) {
            try await fixture.gate.perform { lease in
                _ = try await fixture.store.loadPolicyFilteredEntries(
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            }
        }
        await #expect(
            throws: IOSFailedHistoryError.stalePolicyGeneration
        ) {
            try await fixture.gate.perform { lease in
                _ = try await fixture.store.preparePolicyCutoverDirective(
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            }
        }

        #expect(try await fixture.store.load()?.entries == [future])
        #expect(!fixture.mutationInterlock.isBlocked)
        #expect(!fixture.fileSystem.events.contains("replace"))
    }

    @Test func directiveUsesFrozenProviderFreePriorityAndOldestRow()
        async throws {
        let fixture = try PolicyCutoverStoreFixture()
        let policy = try await fixture.policyReceipt(generation: 3)
        let pending = try failedHistoryTestEntry(
            index: 5,
            policyGeneration: 1,
            ownershipState: .pendingJournalRetirement
        )
        let tombstone = try failedHistoryTestAudioCleanup(
            index: 6,
            policyGeneration: 1
        )
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [pending],
                audioCleanup: [tombstone]
            )
        )
        try await fixture.gate.perform { lease in
            let directive = try await fixture.store
                .preparePolicyCutoverDirective(
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            guard case .retirePendingMetadata(let authority) = directive else {
                Issue.record("PJR must precede every other failed action")
                return
            }
            #expect(authority.row == pending)
        }

        let retry = try failedHistoryTestRetryOperation(
            index: 7,
            state: .providerDispatched
        )
        let retryRow = try failedHistoryTestEntry(
            index: 7,
            policyGeneration: 1,
            retryCount: 1,
            retryOperation: retry
        )
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 2,
                entries: [retryRow],
                audioCleanup: [tombstone]
            )
        )
        try await fixture.gate.perform { lease in
            let directive = try await fixture.store
                .preparePolicyCutoverDirective(
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            guard case .inspectProcessLostRetry(let inspection) = directive
            else {
                Issue.record("stale Retry must precede tombstone cleanup")
                return
            }
            #expect(inspection.row == retryRow)
        }

        let accepting = try failedHistoryTestRetryOperation(
            index: 8,
            state: .acceptingOutput
        )
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 3,
                entries: [
                    try failedHistoryTestEntry(
                        index: 8,
                        policyGeneration: 1,
                        retryCount: 1,
                        retryOperation: accepting
                    ),
                ],
                audioCleanup: [tombstone]
            )
        )
        try await fixture.gate.perform { lease in
            let directive = try await fixture.store
                .preparePolicyCutoverDirective(
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            #expect(directive == .blockedAcceptingOutput)
        }

        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 4,
                entries: [],
                audioCleanup: [tombstone]
            )
        )
        try await fixture.gate.perform { lease in
            let directive = try await fixture.store
                .preparePolicyCutoverDirective(
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            guard case .recoverAudioCleanup(let authorization) = directive
            else {
                Issue.record("existing cleanup head must be recovered first")
                return
            }
            #expect(authorization.tombstone == tombstone)
            #expect(authorization.purpose == .nextHead)
            try await fixture.store.abandonPreparedAudioCleanup(
                using: authorization,
                operationLeaseAuthorization: lease
            )
        }

        let oldest = try failedHistoryTestEntry(
            index: 10,
            policyGeneration: 1
        )
        let newer = try failedHistoryTestEntry(
            index: 11,
            policyGeneration: 2
        )
        let current = try failedHistoryTestEntry(
            index: 12,
            policyGeneration: 3
        )
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 5,
                entries: IOSFailedHistoryValidation.sortedEntries([
                    oldest,
                    newer,
                    current,
                ]),
                audioCleanup: []
            )
        )
        try await fixture.gate.perform { lease in
            let directive = try await fixture.store
                .preparePolicyCutoverDirective(
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            guard case .invalidateReadyRow(let authorization) = directive
            else {
                Issue.record("oldest invalidated ready row must be selected")
                return
            }
            #expect(authorization.candidate == oldest)
            guard case .policyCutover(let sealedPolicy) =
                    authorization.purpose else {
                Issue.record("policy purpose was not sealed")
                return
            }
            #expect(sealedPolicy == policy)
        }
    }

    @Test func processLostRetryCancellationPreservesRowAndRejectsLiveOwner()
        async throws {
        let fixture = try PolicyCutoverStoreFixture()
        let policy = try await fixture.policyReceipt(generation: 2)
        let operation = try failedHistoryTestRetryOperation(
            index: 20,
            state: .reserved
        )
        let row = try failedHistoryTestEntry(
            index: 20,
            policyGeneration: 1,
            retryCount: 1,
            retryOperation: operation
        )
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [row],
                audioCleanup: []
            )
        )
        let liveOwnerState = fixture.retryState

        try await fixture.gate.perform { lease in
            let directive = try await fixture.store
                .preparePolicyCutoverDirective(
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            guard case .inspectProcessLostRetry(let inspection) = directive
            else {
                Issue.record("missing retry recovery inspection")
                return
            }
            let shadowState = IOSFailedHistoryRetryLiveOwnerState()
            let foreignReservation = try #require(
                await shadowState.reserveProcessLostCancellation(
                    of: inspection,
                    operationLeaseAuthorization: lease
                )
            )
            await #expect(
                throws: IOSFailedHistoryError.compareAndSwapFailed
            ) {
                _ = try await fixture.store.preparePolicyRetryCancellation(
                    inspection: inspection,
                    reservation: foreignReservation,
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            }
            #expect(await liveOwnerState.retainLiveOwner(of: inspection))
            #expect(await liveOwnerState.hasLiveOwner())
            #expect(
                await liveOwnerState.authorizeProcessLostCancellation(
                    of: inspection,
                    operationLeaseAuthorization: lease
                ) == nil
            )
            #expect(await liveOwnerState.clearLiveOwner(of: inspection))
            let reservation = try #require(
                await liveOwnerState.authorizeProcessLostCancellation(
                    of: inspection,
                    operationLeaseAuthorization: lease
                )
            )
            #expect(
                await liveOwnerState.retainLiveOwner(of: inspection) == false
            )
            #expect(await liveOwnerState.hasCancellationReservation())
            #expect(
                await liveOwnerState.reserveProcessLostCancellation(
                    of: inspection,
                    operationLeaseAuthorization: lease
                ) == nil
            )
            let preparation = try await fixture.store
                .preparePolicyRetryCancellation(
                    inspection: inspection,
                    reservation: reservation,
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            guard case .commit(let authorization) = preparation else {
                Issue.record("fresh cancellation must require one commit")
                return
            }
            let completion = try await fixture.store
                .commitPolicyRetryCancellation(
                    using: authorization
                )
            #expect(
                await liveOwnerState.consumeCancellationReservation(
                    using: completion
                )
            )
            #expect(
                await liveOwnerState.hasCancellationReservation() == false
            )
        }

        let outcome = try #require(try await fixture.store.load())
        let retained = try #require(outcome.entries.first)
        #expect(outcome.revision == 2)
        #expect(retained.attemptID == row.attemptID)
        #expect(retained.retryOperation == nil)
        #expect(retained.retryCount == row.retryCount)
        #expect(retained.updatedAt == row.updatedAt)
        #expect(outcome.audioCleanup.isEmpty)
    }

    @Test func policyInvalidationReconcilesSourceAndOutcomeExactly()
        async throws {
        let sourceFixture = try PolicyCutoverStoreFixture()
        let policy = try await sourceFixture.policyReceipt(generation: 2)
        let row = try failedHistoryTestEntry(
            index: 30,
            policyGeneration: 1
        )
        try sourceFixture.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [row],
                audioCleanup: []
            )
        )
        try await sourceFixture.gate.perform { lease in
            let authorization = try policyInvalidationAuthorization(
                try await sourceFixture.store.preparePolicyCutoverDirective(
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            )
            let validated = try policyValidatedAudio(authorization)
            sourceFixture.fileSystem.replaceFailure = .init(
                error: .commitUncertain,
                commitBeforeThrowing: false
            )
            await #expect(throws: IOSFailedHistoryError.commitUncertain) {
                try await sourceFixture.store.commitPolicyInvalidation(
                    using: validated
                )
            }
        }
        try await sourceFixture.gate.perform { lease in
            let refreshed = try policyInvalidationAuthorization(
                try await sourceFixture.store.preparePolicyCutoverDirective(
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            )
            try await sourceFixture.store.commitPolicyInvalidation(
                using: policyValidatedAudio(refreshed)
            )
        }
        let sourceOutcome = try #require(
            try await sourceFixture.store.load()
        )
        #expect(sourceOutcome.entries.isEmpty)
        #expect(sourceOutcome.audioCleanup.count == 1)

        let outcomeFixture = try PolicyCutoverStoreFixture()
        let outcomePolicy = try await outcomeFixture.policyReceipt(
            generation: 2
        )
        try outcomeFixture.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [row],
                audioCleanup: []
            )
        )
        try await outcomeFixture.gate.perform { lease in
            let authorization = try policyInvalidationAuthorization(
                try await outcomeFixture.store.preparePolicyCutoverDirective(
                    using: outcomePolicy,
                    operationLeaseAuthorization: lease
                )
            )
            outcomeFixture.fileSystem.replaceFailure = .init(
                error: .commitUncertain,
                commitBeforeThrowing: true
            )
            await #expect(throws: IOSFailedHistoryError.commitUncertain) {
                try await outcomeFixture.store.commitPolicyInvalidation(
                    using: policyValidatedAudio(authorization)
                )
            }
        }
        try await outcomeFixture.gate.perform { lease in
            let directive = try await outcomeFixture.store
                .preparePolicyCutoverDirective(
                        using: outcomePolicy,
                        operationLeaseAuthorization: lease
                    )
            #expect(directive == .retainedMutationConfirmed)
        }
        let confirmed = try #require(try await outcomeFixture.store.load())
        #expect(confirmed.entries.isEmpty)
        #expect(confirmed.audioCleanup.count == 1)
    }
}

private func policyInvalidationAuthorization(
    _ directive: IOSFailedHistoryPolicyCutoverDirective
) throws -> IOSFailedHistoryRowAudioValidationAuthorization {
    guard case .invalidateReadyRow(let authorization) = directive else {
        throw IOSFailedHistoryError.invalidTransition
    }
    return authorization
}

private func policyValidatedAudio(
    _ authorization: IOSFailedHistoryRowAudioValidationAuthorization
) throws -> IOSFailedHistoryValidatedRowAudio {
    try #require(
        IOSFailedHistoryValidatedRowAudio(
            testingAuthorization: authorization,
            audioLease: PolicyCutoverAudioLease(
                row: authorization.candidate
            )
        )
    )
}

private final class PolicyCutoverAudioLease:
    IOSPendingRecordingPublishedAudioLease,
    @unchecked Sendable {
    let relativeIdentifier: String
    let audioArtifact: AudioRecordingArtifact
    let durationMilliseconds: Int64

    init(row: IOSFailedHistoryEntry) {
        relativeIdentifier = row.audioRelativeIdentifier
        durationMilliseconds = row.durationMilliseconds
        audioArtifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/policy-cutover.m4a"),
            duration: Double(row.durationMilliseconds) / 1_000,
            byteCount: row.byteCount
        )
    }

    func revalidate() async throws -> AudioRecordingArtifact {
        audioArtifact
    }

    func read(
        atOffset: Int64,
        maximumByteCount: Int
    ) async throws -> Data {
        _ = atOffset
        _ = maximumByteCount
        return Data()
    }

    func release() {}
}

private final class PolicyCutoverStoreFixture: @unchecked Sendable {
    let gate: IOSPersistenceOperationGate
    let mutationInterlock = IOSFailedHistoryMutationInterlock()
    let fileSystem = FailedHistoryFakeFileSystem()
    let retryState: IOSFailedHistoryRetryLiveOwnerState
    let store: IOSFailedHistoryStore
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity

    private let parentURL: URL?

    init(productionBound: Bool = true) throws {
        gate = IOSPersistenceOperationGate()
        let repository = FoundationIOSFailedHistoryJournalRepository(
            fileSystem: fileSystem
        )
        if productionBound {
            let parent = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "failed-policy-cutover-\(UUID().uuidString)",
                    isDirectory: true
                )
            let root = parent.appendingPathComponent(
                "root",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            let context = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
                .context(for: root)
            parentURL = parent
            ownerIdentity = context.ownerIdentity
            retryState = context.failedHistoryRetryState
            store = IOSFailedHistoryStore(
                journal: repository,
                capabilityOwnerIdentity: ownerIdentity,
                operationGateIdentity: gate.identity,
                expectedPendingStoreIdentity:
                    context.pendingRecordingStoreIdentity,
                retryLiveOwnerState: retryState,
                repositoryGuard: context.repositoryGuard,
                mutationInterlock: mutationInterlock,
                now: { Date(timeIntervalSince1970: 1_900_000_000) }
            )
        } else {
            parentURL = nil
            ownerIdentity = IOSAcceptedHistoryCapabilityOwnerIdentity()
            retryState = IOSFailedHistoryRetryLiveOwnerState()
            store = IOSFailedHistoryStore(
                journal: repository,
                capabilityOwnerIdentity: ownerIdentity,
                operationGateIdentity: gate.identity,
                retryLiveOwnerState: retryState,
                mutationInterlock: mutationInterlock,
                now: { Date(timeIntervalSince1970: 1_900_000_000) }
            )
        }
    }

    deinit {
        if let parentURL {
            try? FileManager.default.removeItem(at: parentURL)
        }
    }

    func install(_ envelope: IOSFailedHistoryEnvelope) throws {
        fileSystem.install(try IOSFailedHistoryWireCodec.encode(envelope))
        fileSystem.resetEvents()
    }

    func policyReceipt(
        generation: Int64,
        enabled: Bool = true
    ) async throws -> IOSHistoryPolicyReceipt {
        let state = try IOSHistoryPolicyState(
            revision: generation,
            historyEnabled: enabled,
            policyGeneration: generation
        )
        let policyStore = IOSHistoryPolicyStore(
            journal: PolicyCutoverPolicyJournal(state: state),
            capabilityOwnerIdentity: ownerIdentity
        )
        return try await policyStore.confirm(
            expected: IOSHistoryPolicyExpectation(state: state)
        )
    }
}

private final class PolicyCutoverPolicyJournal:
    IOSHistoryPolicyJournalStoring,
    @unchecked Sendable {
    private var snapshot: IOSHistoryPolicyJournalSnapshot
    private var nextToken: UInt64 = 2

    init(state: IOSHistoryPolicyState) {
        snapshot = IOSHistoryPolicyJournalSnapshot(
            state: state,
            fileRevision: IOSStrictProtectedRecordFileRevision(
                testingToken: 1
            )
        )
    }

    func load() throws -> IOSHistoryPolicyJournalSnapshot? { snapshot }

    func replace(
        _ state: IOSHistoryPolicyState,
        expected: IOSHistoryPolicyJournalSnapshot
    ) throws -> IOSHistoryPolicyJournalSnapshot {
        guard snapshot == expected else {
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }
        snapshot = IOSHistoryPolicyJournalSnapshot(
            state: state,
            fileRevision: IOSStrictProtectedRecordFileRevision(
                testingToken: nextToken
            )
        )
        nextToken += 1
        return snapshot
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        _ = now
        return .empty
    }
}
