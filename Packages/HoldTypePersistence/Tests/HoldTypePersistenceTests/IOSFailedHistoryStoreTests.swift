import Darwin
import Foundation
import Testing
@testable import HoldTypePersistence

struct IOSFailedHistoryStoreTests {
    @Test func storeIdentityIsUniqueRedactedAndGateBindingIsOneTime()
        async throws {
        let first = FailedHistoryStoreFixture()
        let second = FailedHistoryStoreFixture()
        let gate = IOSPersistenceOperationGate()
        let foreignGate = IOSPersistenceOperationGate()

        #expect(first.store.storeIdentity != second.store.storeIdentity)
        #expect(
            String(describing: first.store.storeIdentity)
                == "IOSFailedHistoryStoreIdentity(redacted)"
        )
        #expect(first.store.storeIdentity.customMirror.children.isEmpty)
        #expect(first.store.bindOperationGateIdentity(gate.identity))
        #expect(first.store.bindOperationGateIdentity(gate.identity))
        #expect(!first.store.bindOperationGateIdentity(foreignGate.identity))
        requireFailedHistorySendable(IOSFailedHistoryStoreIdentity.self)
        requireFailedHistorySendable(
            IOSFailedHistoryMutationCapability.self
        )
        requireFailedHistorySendable(IOSFailedHistoryMutationReceipt.self)
        requireFailedHistorySendable(
            IOSFailedHistoryProtectedAudioInventory.self
        )
        requireFailedHistorySendable(
            IOSFailedHistoryProtectedAudioInventory.Artifact.self
        )
    }

    @Test func missingLoadIsNilAndDoesNotCreateStorage() async throws {
        let fixture = FailedHistoryStoreFixture()
        #expect(try await fixture.store.load() == nil)
        #expect(fixture.fileSystem.file == nil)
        #expect(fixture.fileSystem.events == ["load"])
    }

    @Test func protectedAudioInventorySealsCanonicalRowsAndTombstones()
        async throws {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "failed-audio-inventory-\(UUID().uuidString)",
                isDirectory: true
            )
        let root = parent.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        let context = registry.context(for: root)
        let row = try failedHistoryTestEntry(
            index: 30,
            ownershipState: .pendingJournalRetirement
        )
        let tombstone = try failedHistoryTestAudioCleanup(index: 31)
        let envelope = try IOSFailedHistoryEnvelope(
            revision: 1,
            entries: [row],
            audioCleanup: [tombstone]
        )

        try await context.operationGate.perform { lease in
            _ = try await context.failedHistoryStore
                .mutateExactForTesting(
                    envelope,
                    operationLeaseAuthorization: lease
                )
            let inventory = try await context.failedHistoryStore
                .sealProtectedAudioInventory(
                    expectedPendingStoreIdentity:
                        context.pendingRecordingStoreIdentity,
                    operationLeaseAuthorization: lease
                )

            #expect(inventory.failedSource?.envelope == envelope)
            #expect(inventory.hasPendingJournalRetirement)
            #expect(
                inventory.artifacts == [
                    .row(
                        attemptID: row.attemptID,
                        relativeIdentifier: row.audioRelativeIdentifier,
                        durationMilliseconds: row.durationMilliseconds,
                        byteCount: row.byteCount
                    ),
                    .tombstone(
                        attemptID: tombstone.attemptID,
                        relativeIdentifier:
                            tombstone.audioRelativeIdentifier,
                        byteCount: tombstone.byteCount
                    ),
                ]
            )
            #expect(
                String(describing: inventory)
                    == "IOSFailedHistoryProtectedAudioInventory(redacted)"
            )
            #expect(inventory.customMirror.children.isEmpty)
            #expect(
                String(describing: inventory.artifacts[0])
                    == "IOSFailedHistoryProtectedAudioInventory.Artifact(redacted)"
            )
            try await context.failedHistoryStore
                .revalidateProtectedAudioInventory(
                    inventory,
                    operationLeaseAuthorization: lease
                )
        }
    }

    @Test func protectedAudioInventoryRejectsForeignStaleAndChangedState()
        async throws {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "failed-audio-inventory-revalidation-\(UUID().uuidString)",
                isDirectory: true
            )
        let root = parent.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        let context = registry.context(for: root)

        let inventory = try await context.operationGate.perform { lease in
            await #expect(
                throws: IOSFailedHistoryError.compareAndSwapFailed
            ) {
                _ = try await context.failedHistoryStore
                    .sealProtectedAudioInventory(
                        expectedPendingStoreIdentity:
                            IOSPendingRecordingStoreIdentity(),
                        operationLeaseAuthorization: lease
                    )
            }
            return try await context.failedHistoryStore
                .sealProtectedAudioInventory(
                    expectedPendingStoreIdentity:
                        context.pendingRecordingStoreIdentity,
                    operationLeaseAuthorization: lease
                )
        }

        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            try await context.failedHistoryStore
                .revalidateProtectedAudioInventory(
                    inventory,
                    operationLeaseAuthorization:
                        inventory.operationLeaseAuthorization
                )
        }

        try await context.operationGate.perform { lease in
            let current = try await context.failedHistoryStore
                .sealProtectedAudioInventory(
                    expectedPendingStoreIdentity:
                        context.pendingRecordingStoreIdentity,
                    operationLeaseAuthorization: lease
                )
            _ = try await context.failedHistoryStore
                .mutateExactForTesting(
                    IOSFailedHistoryEnvelope(
                        revision: 1,
                        entries: [try failedHistoryTestEntry(index: 32)],
                        audioCleanup: []
                    ),
                    operationLeaseAuthorization: lease
                )
            await #expect(
                throws: IOSFailedHistoryError.compareAndSwapFailed
            ) {
                try await context.failedHistoryStore
                    .revalidateProtectedAudioInventory(
                        current,
                        operationLeaseAuthorization: lease
                    )
            }
        }
    }

    @Test func guardedBaselineRequiresProvenMissingOrEmptyState() async throws {
        let missing = FailedHistoryStoreFixture()
        let missingEvidence = try await missing.store.proveGuardedBaseline()
        #expect(
            missingEvidence.capabilityOwnerIdentity == missing.ownerIdentity
        )
        #expect(
            String(describing: missingEvidence)
                == "IOSFailedHistoryGuardedBaselineEvidence(redacted)"
        )
        #expect(missingEvidence.customMirror.children.isEmpty)

        let empty = FailedHistoryStoreFixture()
        try empty.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [],
                audioCleanup: []
            )
        )
        _ = try await empty.store.proveGuardedBaseline()

        let row = FailedHistoryStoreFixture()
        try row.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [try failedHistoryTestEntry()],
                audioCleanup: []
            )
        )
        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try await row.store.proveGuardedBaseline()
        }

        let cleanup = FailedHistoryStoreFixture()
        try cleanup.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [],
                audioCleanup: [try failedHistoryTestAudioCleanup()]
            )
        )
        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try await cleanup.store.proveGuardedBaseline()
        }
    }

    @Test func rawLoadPreservesAllInternalStateForCoordinatorRecovery()
        async throws {
        let fixture = FailedHistoryStoreFixture()
        let envelope = try IOSFailedHistoryEnvelope(
            revision: 9,
            entries: [try failedHistoryTestEntry(policyGeneration: 7)],
            audioCleanup: [
                try failedHistoryTestAudioCleanup(policyGeneration: 3),
            ]
        )
        try fixture.install(envelope)
        #expect(try await fixture.store.load() == envelope)
    }

    @Test func typedReadFailuresPropagateWithoutMutation() async throws {
        let fixture = FailedHistoryStoreFixture()
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [],
                audioCleanup: []
            )
        )
        let original = fixture.fileSystem.file?.data

        for (fileError, expected) in [
            (IOSStrictProtectedRecordFileSystemError.sourceTooLarge,
             IOSFailedHistoryError.sourceTooLarge),
            (.protectedDataUnavailable, .dataProtectionUnavailable),
            (.readFailed, .readFailed),
        ] {
            fixture.fileSystem.readError = fileError
            await #expect(throws: expected) {
                _ = try await fixture.store.load()
            }
        }
        #expect(fixture.fileSystem.file?.data == original)
    }

    @Test func stagingMaintenanceUsesInjectedClockAndRedactedReport()
        async throws {
        let fixture = FailedHistoryStoreFixture()
        fixture.fileSystem.maintenanceReport =
            IOSStrictProtectedRecordMaintenanceReport(
                inspectedEntryCount: 2,
                inspectedByteCount: 30,
                removedFileCount: 1,
                removedByteCount: 10,
                reachedLimit: false
            )
        let gate = IOSPersistenceOperationGate()
        #expect(fixture.store.bindOperationGateIdentity(gate.identity))
        let report = try await gate.perform { lease in
            try await fixture.store.performStagingMaintenance(
                operationLeaseAuthorization: lease
            )
        }

        #expect(report.inspectedEntryCount == 2)
        #expect(report.removedFileCount == 1)
        #expect(
            String(describing: report)
                == "IOSFailedHistoryMaintenanceReport(redacted)"
        )
        #expect(fixture.fileSystem.events == ["maintenance"])
    }

    @Test func exactMutationCreatesRevisionOneThenReplacesWithNextRevision()
        async throws {
        let fixture = FailedHistoryStoreFixture()
        let gate = IOSPersistenceOperationGate()
        #expect(fixture.store.bindOperationGateIdentity(gate.identity))
        let first = try failedHistoryStoreEnvelope(revision: 1, index: 10)

        let firstReceipt = try await gate.perform { lease in
            let capability = try await fixture.store
                .reserveExactMutationForTesting(
                    first,
                    operationLeaseAuthorization: lease
                )
            #expect(
                String(describing: capability)
                    == "IOSFailedHistoryMutationCapability(redacted)"
            )
            #expect(capability.customMirror.children.isEmpty)
            let receipt = try await fixture.store
                .commitExactMutationForTesting(capability)
            #expect(
                try await fixture.store.validateMutationReceiptForTesting(
                    receipt,
                    operationLeaseAuthorization: lease
                ) == first
            )
            return receipt
        }
        #expect(
            String(describing: firstReceipt)
                == "IOSFailedHistoryMutationReceipt(redacted)"
        )
        #expect(firstReceipt.customMirror.children.isEmpty)
        #expect(fixture.fileSystem.events == ["load", "create", "load"])

        fixture.fileSystem.resetEvents()
        let second = try failedHistoryStoreEnvelope(revision: 2, index: 11)
        _ = try await gate.perform { lease in
            try await fixture.store.mutateExactForTesting(
                second,
                operationLeaseAuthorization: lease
            )
        }
        #expect(fixture.fileSystem.events == ["load", "replace"])
        #expect(try await fixture.store.load() == second)
    }

    @Test func revisionOverflowFailsBeforeMutationIO() async throws {
        let fixture = FailedHistoryStoreFixture()
        let gate = IOSPersistenceOperationGate()
        #expect(fixture.store.bindOperationGateIdentity(gate.identity))
        try fixture.install(
            failedHistoryStoreEnvelope(revision: Int64.max, index: 20)
        )
        let outcome = try failedHistoryStoreEnvelope(
            revision: Int64.max,
            index: 21
        )

        await #expect(throws: IOSFailedHistoryError.revisionOverflow) {
            _ = try await gate.perform { lease in
                try await fixture.store.mutateExactForTesting(
                    outcome,
                    operationLeaseAuthorization: lease
                )
            }
        }
        #expect(fixture.fileSystem.events == ["load"])
    }

    @Test func unboundForeignAndExpiredLeasesFailBeforeRepositoryIO()
        async throws {
        let outcome = try failedHistoryStoreEnvelope(revision: 1, index: 30)

        let unbound = FailedHistoryStoreFixture()
        let gate = IOSPersistenceOperationGate()
        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try await gate.perform { lease in
                try await unbound.store.mutateExactForTesting(
                    outcome,
                    operationLeaseAuthorization: lease
                )
            }
        }
        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try await gate.perform { lease in
                try await unbound.store.performStagingMaintenance(
                    operationLeaseAuthorization: lease
                )
            }
        }
        #expect(unbound.fileSystem.events.isEmpty)

        let foreign = FailedHistoryStoreFixture()
        #expect(foreign.store.bindOperationGateIdentity(gate.identity))
        let foreignGate = IOSPersistenceOperationGate()
        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try await foreignGate.perform { lease in
                try await foreign.store.mutateExactForTesting(
                    outcome,
                    operationLeaseAuthorization: lease
                )
            }
        }
        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try await foreignGate.perform { lease in
                try await foreign.store.performStagingMaintenance(
                    operationLeaseAuthorization: lease
                )
            }
        }
        #expect(foreign.fileSystem.events.isEmpty)

        let expired = FailedHistoryStoreFixture()
        #expect(expired.store.bindOperationGateIdentity(gate.identity))
        let expiredLease = try await gate.perform { $0 }
        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try await expired.store.mutateExactForTesting(
                outcome,
                operationLeaseAuthorization: expiredLease
            )
        }
        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try await expired.store.performStagingMaintenance(
                operationLeaseAuthorization: expiredLease
            )
        }
        #expect(expired.fileSystem.events.isEmpty)
    }

    @Test func visibleAndInvisibleCreateAndReplaceUncertaintyRetryIdentically()
        async throws {
        for hasSource in [false, true] {
            for commitWasVisible in [false, true] {
                let fixture = FailedHistoryStoreFixture()
                let gate = IOSPersistenceOperationGate()
                #expect(
                    fixture.store.bindOperationGateIdentity(gate.identity)
                )
                let sourceRevision: Int64 = hasSource ? 7 : 0
                if hasSource {
                    try fixture.install(
                        failedHistoryStoreEnvelope(
                            revision: sourceRevision,
                            index: 40
                        )
                    )
                }
                let outcome = try failedHistoryStoreEnvelope(
                    revision: sourceRevision + 1,
                    index: 41
                )
                let failure = FailedHistoryFakeFileSystem.Failure(
                    error: .commitUncertain,
                    commitBeforeThrowing: commitWasVisible
                )
                if hasSource {
                    fixture.fileSystem.replaceFailure = failure
                } else {
                    fixture.fileSystem.createFailure = failure
                }

                await #expect(throws: IOSFailedHistoryError.commitUncertain) {
                    _ = try await gate.perform { lease in
                        try await fixture.store.mutateExactForTesting(
                            outcome,
                            operationLeaseAuthorization: lease
                        )
                    }
                }
                #expect(fixture.mutationInterlock.isBlocked)

                fixture.fileSystem.resetEvents()
                let receipt = try await gate.perform { lease in
                    let receipt = try await fixture.store
                        .mutateExactForTesting(
                            outcome,
                            operationLeaseAuthorization: lease
                        )
                    #expect(
                        try await fixture.store
                            .validateMutationReceiptForTesting(
                                receipt,
                                operationLeaseAuthorization: lease
                            ) == outcome
                    )
                    return receipt
                }
                #expect(
                    receipt.storeIdentity == fixture.store.storeIdentity
                )
                #expect(
                    receipt.capabilityOwnerIdentity == fixture.ownerIdentity
                )
                #expect(!fixture.mutationInterlock.isBlocked)
                #expect(
                    fixture.fileSystem.events
                        == [
                            "load",
                            (hasSource || commitWasVisible)
                                ? "replace" : "create",
                            "load",
                        ]
                )
                #expect(try await fixture.store.load() == outcome)
            }
        }
    }

    @Test func uncertaintyBlocksRawOperationsAndUnrelatedMutationWithoutIO()
        async throws {
        let fixture = FailedHistoryStoreFixture()
        let gate = IOSPersistenceOperationGate()
        #expect(fixture.store.bindOperationGateIdentity(gate.identity))
        let intended = try failedHistoryStoreEnvelope(revision: 1, index: 50)
        fixture.fileSystem.createFailure = FailedHistoryFakeFileSystem.Failure(
            error: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSFailedHistoryError.commitUncertain) {
            _ = try await gate.perform { lease in
                try await fixture.store.mutateExactForTesting(
                    intended,
                    operationLeaseAuthorization: lease
                )
            }
        }

        fixture.fileSystem.resetEvents()
        await #expect(throws: IOSFailedHistoryError.commitUncertain) {
            _ = try await fixture.store.load()
        }
        #expect(fixture.mutationInterlock.isBlocked)
        await #expect(throws: IOSFailedHistoryError.commitUncertain) {
            _ = try await fixture.store.proveGuardedBaseline()
        }
        await #expect(throws: IOSFailedHistoryError.commitUncertain) {
            _ = try await gate.perform { lease in
                try await fixture.store.performStagingMaintenance(
                    operationLeaseAuthorization: lease
                )
            }
        }
        let unrelated = try failedHistoryStoreEnvelope(
            revision: 1,
            index: 51
        )
        await #expect(throws: IOSFailedHistoryError.commitUncertain) {
            _ = try await gate.perform { lease in
                try await fixture.store.mutateExactForTesting(
                    unrelated,
                    operationLeaseAuthorization: lease
                )
            }
        }
        #expect(fixture.fileSystem.events.isEmpty)
    }

    @Test func stalePhysicalSnapshotCannotCommitReservedMutation()
        async throws {
        let fixture = FailedHistoryStoreFixture()
        let gate = IOSPersistenceOperationGate()
        #expect(fixture.store.bindOperationGateIdentity(gate.identity))
        try fixture.install(
            failedHistoryStoreEnvelope(revision: 3, index: 60)
        )
        let outcome = try failedHistoryStoreEnvelope(revision: 4, index: 61)
        let raced = try failedHistoryStoreEnvelope(revision: 3, index: 62)

        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try await gate.perform { lease in
                let capability = try await fixture.store
                    .reserveExactMutationForTesting(
                        outcome,
                        operationLeaseAuthorization: lease
                    )
                try fixture.install(raced)
                return try await fixture.store
                    .commitExactMutationForTesting(capability)
            }
        }
        #expect(fixture.fileSystem.events == ["replace"])
        #expect(try await fixture.store.load() == raced)
    }

    @Test func unrecognizedUncertainWinnerKeepsRecoveryBlocked()
        async throws {
        let fixture = FailedHistoryStoreFixture()
        let gate = IOSPersistenceOperationGate()
        #expect(fixture.store.bindOperationGateIdentity(gate.identity))
        let intended = try failedHistoryStoreEnvelope(revision: 1, index: 63)
        fixture.fileSystem.createFailure = FailedHistoryFakeFileSystem.Failure(
            error: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSFailedHistoryError.commitUncertain) {
            _ = try await gate.perform { lease in
                try await fixture.store.mutateExactForTesting(
                    intended,
                    operationLeaseAuthorization: lease
                )
            }
        }

        try fixture.install(
            failedHistoryStoreEnvelope(revision: 1, index: 64)
        )
        await #expect(throws: IOSFailedHistoryError.commitUncertain) {
            _ = try await gate.perform { lease in
                try await fixture.store.mutateExactForTesting(
                    intended,
                    operationLeaseAuthorization: lease
                )
            }
        }
        await #expect(throws: IOSFailedHistoryError.commitUncertain) {
            _ = try await fixture.store.load()
        }
    }

    @Test func staleReceiptFailsDuringTheSameActiveLease() async throws {
        let fixture = FailedHistoryStoreFixture()
        let gate = IOSPersistenceOperationGate()
        #expect(fixture.store.bindOperationGateIdentity(gate.identity))
        let first = try failedHistoryStoreEnvelope(revision: 1, index: 65)
        let second = try failedHistoryStoreEnvelope(revision: 2, index: 66)

        try await gate.perform { lease in
            let firstReceipt = try await fixture.store.mutateExactForTesting(
                first,
                operationLeaseAuthorization: lease
            )
            _ = try await fixture.store.mutateExactForTesting(
                second,
                operationLeaseAuthorization: lease
            )
            await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
                _ = try await fixture.store
                    .validateMutationReceiptForTesting(
                        firstReceipt,
                        operationLeaseAuthorization: lease
                    )
            }
        }
    }

    @Test func reservedCapabilityExpiresWithItsLeaseBeforeCommit()
        async throws {
        let fixture = FailedHistoryStoreFixture()
        let gate = IOSPersistenceOperationGate()
        #expect(fixture.store.bindOperationGateIdentity(gate.identity))
        let outcome = try failedHistoryStoreEnvelope(revision: 1, index: 67)
        let capability = try await gate.perform { lease in
            try await fixture.store.reserveExactMutationForTesting(
                outcome,
                operationLeaseAuthorization: lease
            )
        }
        fixture.fileSystem.resetEvents()

        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try await fixture.store
                .commitExactMutationForTesting(capability)
        }
        #expect(fixture.fileSystem.events.isEmpty)
    }

    @Test func invalidRevisionStepsFailBeforeMutationIO() async throws {
        for (sourceRevision, outcomeRevision) in [
            (Int64?.none, Int64(2)),
            (Int64?.some(4), Int64(4)),
            (Int64?.some(4), Int64(6)),
        ] {
            let fixture = FailedHistoryStoreFixture()
            let gate = IOSPersistenceOperationGate()
            #expect(fixture.store.bindOperationGateIdentity(gate.identity))
            if let sourceRevision {
                try fixture.install(
                    failedHistoryStoreEnvelope(
                        revision: sourceRevision,
                        index: 68
                    )
                )
            }
            let outcome = try failedHistoryStoreEnvelope(
                revision: outcomeRevision,
                index: 69
            )

            await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
                _ = try await gate.perform { lease in
                    try await fixture.store.mutateExactForTesting(
                        outcome,
                        operationLeaseAuthorization: lease
                    )
                }
            }
            #expect(fixture.fileSystem.events == ["load"])
        }
    }

    @Test func rootReplacementBetweenReserveAndCommitWritesNothing()
        async throws {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "failed-history-root-swap-\(UUID().uuidString)",
            isDirectory: true
        )
        let root = parent.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        let context = registry.context(for: root)
        let outcome = try failedHistoryStoreEnvelope(revision: 1, index: 70)

        await #expect(
            throws: IOSFailedHistoryError.repositoryIdentityConflict
        ) {
            _ = try await context.operationGate.perform { lease in
                let capability = try await context.failedHistoryStore
                    .reserveExactMutationForTesting(
                        outcome,
                        operationLeaseAuthorization: lease
                    )
                try FileManager.default.removeItem(at: root)
                try FileManager.default.createDirectory(
                    at: root,
                    withIntermediateDirectories: false
                )
                return try await context.failedHistoryStore
                    .commitExactMutationForTesting(capability)
            }
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: IOSFailedHistoryStorageLocation.fileURL(in: root).path
            )
        )
    }

    @Test func rootSwapAfterPrevalidationBeforeJournalOpenWritesNothing()
        async throws {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "failed-history-root-open-race-\(UUID().uuidString)",
                isDirectory: true
            )
        let root = parent.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }

        let context = registry.context(for: root)
        let swapper = FailedHistoryRootSwap(root: root)
        let fileSystem = FoundationIOSStrictProtectedRecordFileSystem(
            applicationSupportDirectoryURL: root,
            configuration: .failedHistory,
            beforeRepositoryRootOpen: {
                try swapper.replaceRootOnce()
            }
        )
        let store = IOSFailedHistoryStore(
            journal: FoundationIOSFailedHistoryJournalRepository(
                fileSystem: fileSystem
            ),
            capabilityOwnerIdentity: context.ownerIdentity,
            operationGateIdentity: context.operationGate.identity,
            repositoryGuard: context.repositoryGuard,
            mutationInterlock: context.failedHistoryMutationInterlock
        )
        let outcome = try failedHistoryStoreEnvelope(
            revision: 1,
            index: 71
        )

        await #expect(
            throws: IOSFailedHistoryError.repositoryIdentityConflict
        ) {
            _ = try await context.operationGate.perform { lease in
                let capability = try await store
                    .reserveExactMutationForTesting(
                        outcome,
                        operationLeaseAuthorization: lease
                    )
                return try await store
                    .commitExactMutationForTesting(capability)
            }
        }

        #expect(swapper.didReplaceRoot)
        #expect(
            !FileManager.default.fileExists(
                atPath: IOSFailedHistoryStorageLocation.fileURL(in: root).path
            )
        )
    }

    @Test func capabilityAndReceiptRejectForeignStoreOrExpiredLeaseWithoutIO()
        async throws {
        let fixture = FailedHistoryStoreFixture()
        let foreign = FailedHistoryStoreFixture()
        let gate = IOSPersistenceOperationGate()
        #expect(fixture.store.bindOperationGateIdentity(gate.identity))
        #expect(foreign.store.bindOperationGateIdentity(gate.identity))
        let outcome = try failedHistoryStoreEnvelope(revision: 1, index: 70)

        let receipt = try await gate.perform { lease in
            let capability = try await fixture.store
                .reserveExactMutationForTesting(
                    outcome,
                    operationLeaseAuthorization: lease
                )
            foreign.fileSystem.resetEvents()
            await #expect(
                throws: IOSFailedHistoryError.compareAndSwapFailed
            ) {
                _ = try await foreign.store
                    .commitExactMutationForTesting(capability)
            }
            #expect(foreign.fileSystem.events.isEmpty)

            let receipt = try await fixture.store
                .commitExactMutationForTesting(capability)
            await #expect(
                throws: IOSFailedHistoryError.compareAndSwapFailed
            ) {
                _ = try await foreign.store
                    .validateMutationReceiptForTesting(
                        receipt,
                        operationLeaseAuthorization: lease
                    )
            }
            #expect(foreign.fileSystem.events.isEmpty)
            return receipt
        }

        fixture.fileSystem.resetEvents()
        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try await fixture.store.validateMutationReceiptForTesting(
                receipt,
                operationLeaseAuthorization:
                    receipt.operationLeaseAuthorization
            )
        }
        #expect(fixture.fileSystem.events.isEmpty)
    }

    @Test func liveRepositoryUsesExactPrivateProtectionAndMarker() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "failed-history-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: base) }

        let ownerIdentity = IOSAcceptedHistoryCapabilityOwnerIdentity()
        let repository = FoundationIOSFailedHistoryJournalRepository(
            applicationSupportDirectoryURL: base
        )
        let store = IOSFailedHistoryStore(
            journal: repository,
            capabilityOwnerIdentity: ownerIdentity
        )
        let envelope = try IOSFailedHistoryEnvelope(
            revision: 1,
            entries: [try failedHistoryTestEntry()],
            audioCleanup: []
        )
        _ = try repository.create(
            envelope,
            authorization: IOSFailedHistoryJournalMutationAuthorization(
                testingToken: ()
            )
        )
        #expect(try await store.load() == envelope)

        let rootURL = base.appendingPathComponent("HoldType", isDirectory: true)
        let fileURL = IOSFailedHistoryStorageLocation.fileURL(in: base)
        let rootAttributes = try FileManager.default.attributesOfItem(
            atPath: rootURL.path
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )
        #expect(
            (rootAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700
        )
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(
            try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true
        )
        #if os(iOS) && !targetEnvironment(simulator)
        #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
        #else
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            #expect(protection == .complete)
        }
        #endif

        let descriptor = Darwin.open(fileURL.path, O_RDWR | O_CLOEXEC)
        let validDescriptor = try #require(descriptor >= 0 ? descriptor : nil)
        defer { Darwin.close(validDescriptor) }
        let marker = try #require(
            IOSStrictProtectedRecordConfiguration.failedHistory.marker
        )
        var markerBytes = [UInt8](repeating: 0, count: marker.value.count + 1)
        let markerByteCount = marker.name.withCString { name in
            markerBytes.withUnsafeMutableBytes {
                Darwin.fgetxattr(
                    validDescriptor,
                    name,
                    $0.baseAddress,
                    $0.count,
                    0,
                    0
                )
            }
        }
        #expect(markerByteCount == marker.value.count)
        #expect(Array(markerBytes.prefix(marker.value.count)) == marker.value)

        let preserved = try Data(contentsOf: fileURL)
        #expect(
            marker.name.withCString {
                Darwin.fremovexattr(validDescriptor, $0, 0)
            } == 0
        )
        await #expect(throws: IOSFailedHistoryError.readFailed) {
            _ = try await store.load()
        }
        #expect(try Data(contentsOf: fileURL) == preserved)

        let wrongMarker = Array("v2".utf8)
        let setResult = marker.name.withCString { name in
            wrongMarker.withUnsafeBytes {
                Darwin.fsetxattr(
                    validDescriptor,
                    name,
                    $0.baseAddress,
                    $0.count,
                    0,
                    Int32(XATTR_CREATE)
                )
            }
        }
        #expect(setResult == 0)
        await #expect(throws: IOSFailedHistoryError.readFailed) {
            _ = try await store.load()
        }
        #expect(try Data(contentsOf: fileURL) == preserved)
    }
}

private final class FailedHistoryRootSwap: @unchecked Sendable {
    private let lock = NSLock()
    private let root: URL
    private var replaced = false

    init(root: URL) {
        self.root = root
    }

    var didReplaceRoot: Bool {
        lock.withLock { replaced }
    }

    func replaceRootOnce() throws {
        try lock.withLock {
            guard !replaced else { return }
            let detached = root.deletingLastPathComponent()
                .appendingPathComponent("detached-root", isDirectory: true)
            try FileManager.default.moveItem(at: root, to: detached)
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: false
            )
            replaced = true
        }
    }
}

private func failedHistoryStoreEnvelope(
    revision: Int64,
    index: Int
) throws -> IOSFailedHistoryEnvelope {
    try IOSFailedHistoryEnvelope(
        revision: revision,
        entries: [try failedHistoryTestEntry(index: index)],
        audioCleanup: []
    )
}

private final class FailedHistoryStoreFixture: @unchecked Sendable {
    let ownerIdentity = IOSAcceptedHistoryCapabilityOwnerIdentity()
    let mutationInterlock = IOSFailedHistoryMutationInterlock()
    let fileSystem = FailedHistoryFakeFileSystem()
    let repository: FoundationIOSFailedHistoryJournalRepository
    let store: IOSFailedHistoryStore

    init() {
        repository = FoundationIOSFailedHistoryJournalRepository(
            fileSystem: fileSystem,
            stagingMaintenance: { [fileSystem] now in
                try fileSystem.removeAbandonedTemporaryFiles(now: now)
            }
        )
        store = IOSFailedHistoryStore(
            journal: repository,
            capabilityOwnerIdentity: ownerIdentity,
            mutationInterlock: mutationInterlock,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    func install(_ envelope: IOSFailedHistoryEnvelope) throws {
        fileSystem.install(try IOSFailedHistoryWireCodec.encode(envelope))
        fileSystem.resetEvents()
    }
}
