import Darwin
import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

private let outboxCapabilityOwnerIdentity =
    IOSAcceptedHistoryCapabilityOwnerIdentity()
private let outboxDeliveryStoreIdentity =
    IOSAcceptedOutputDeliveryStoreIdentity()

struct IOSAcceptedHistoryOutboxStoreTests {
    @Test func guardedBaselineAcceptsOnlyMissingOrValidEmptyState() async throws {
        let missing = OutboxStoreFixture(now: outboxStoreDate())
        let missingEvidence = try await missing.store.proveGuardedBaseline()
        #expect(
            String(describing: missingEvidence)
                == "IOSAcceptedHistoryOutboxGuardedBaselineEvidence(redacted)"
        )
        #expect(missingEvidence.customMirror.children.isEmpty)

        let empty = OutboxStoreFixture(now: outboxStoreDate())
        empty.journal.install(
            try IOSAcceptedHistoryOutboxEnvelope(revision: 1, entries: [])
        )
        _ = try await empty.store.proveGuardedBaseline()

        let nonempty = OutboxStoreFixture(now: outboxStoreDate())
        nonempty.journal.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [try outboxStoredEntry(index: 900)]
            )
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed) {
            _ = try await nonempty.store.proveGuardedBaseline()
        }
    }

    @Test func guardedBaselineRejectsMembershipAndRetirementUncertainty() async throws {
        let now = outboxStoreDate()
        let membership = OutboxStoreFixture(now: now)
        let candidate = try await outboxCapabilities(index: 901, createdAt: now)
        membership.journal.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            _ = try await membership.store.transferForTesting(
                delivery: candidate.delivery,
                policy: candidate.policy
            )
        }
        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            _ = try await membership.store.proveGuardedBaseline()
        }

        let retirement = OutboxStoreFixture(now: now)
        let retirementCandidate = try await outboxCapabilities(
            index: 902,
            createdAt: now
        )
        let receipt = try await outboxMembershipReceipt(
            fixture: retirement,
            capabilities: retirementCandidate
        )
        let decision = try await outboxRowReceipt(membership: receipt)
        retirement.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            try await retirement.store.retireProcessed(
                membership: receipt,
                decision: decision
            )
        }
        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            _ = try await retirement.store.proveGuardedBaseline()
        }
    }

    @Test func guardedBaselinePropagatesTypedReadFailures() async {
        let fixture = OutboxStoreFixture(now: outboxStoreDate())
        for error in [
            IOSAcceptedHistoryOutboxError.sourceTooLarge,
            .malformedData,
            .unsupportedSchemaVersion,
            .dataProtectionUnavailable,
            .readFailed,
        ] {
            fixture.journal.failNextLoad(with: error)
            await #expect(throws: error) {
                _ = try await fixture.store.proveGuardedBaseline()
            }
        }
    }

    @Test func foreignObservationsReceiptsAndAuthoritiesFailBeforeJournalIO()
        async throws {
        let now = outboxStoreDate()
        let localFixture = OutboxStoreFixture(now: now)
        let localCapabilities = try await outboxCapabilities(
            index: 903,
            createdAt: now
        )
        let localMembership = try await outboxMembershipReceipt(
            fixture: localFixture,
            capabilities: localCapabilities
        )

        let foreignOwner = IOSAcceptedHistoryCapabilityOwnerIdentity()
        let foreignFixture = OutboxStoreFixture(
            now: now,
            capabilityOwnerIdentity: foreignOwner
        )
        let foreignCapabilities = try await outboxCapabilities(
            index: 904,
            createdAt: now,
            capabilityOwnerIdentity: foreignOwner
        )
        let foreignMembership = try await outboxMembershipReceipt(
            fixture: foreignFixture,
            capabilities: foreignCapabilities
        )
        let foreignObservation = try #require(
            try await foreignFixture.store.observe()?.first
        )
        let foreignDecision = try await outboxRowReceipt(
            membership: foreignMembership
        )
        let foreignPolicy = try await outboxPolicyReceipt(
            generation: 2,
            enabled: false,
            capabilityOwnerIdentity: foreignOwner
        )
        let foreignStoreIdentity = IOSAcceptedOutputDeliveryStoreIdentity()
        let foreignStorePending = IOSAcceptedOutputDeliveryAuthorization(
            snapshot: localCapabilities.delivery.snapshot,
            storeIdentity: foreignStoreIdentity,
            capabilityOwnerIdentity: outboxCapabilityOwnerIdentity
        )
        let foreignStoreTerminal = try outboxDeliveryAuthorization(
            index: 903,
            createdAt: now,
            historyState: .committed,
            storeIdentity: foreignStoreIdentity
        )
        localFixture.journal.resetEvents()
        let localClockReads = localFixture.clock.readCount

        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            _ = try await localFixture.store.transferForTesting(
                delivery: foreignCapabilities.delivery,
                policy: localCapabilities.policy
            )
        }
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            _ = try await localFixture.store.transferForTesting(
                delivery: localCapabilities.delivery,
                policy: foreignPolicy
            )
        }
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            _ = try await localFixture.store.confirmMembership(
                delivery: foreignCapabilities.delivery
            )
        }
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            _ = try await localFixture.store.confirmMembership(
                delivery: foreignStorePending
            )
        }
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            _ = try await localFixture.operationGate.perform { lease in
                try await localFixture.store.classifyDeliveryAbsence(
                    authorization: foreignStoreTerminal,
                    operationLeaseAuthorization: lease
                )
            }
        }
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            _ = try await localFixture.store.confirmMembership(
                observation: foreignObservation
            )
        }
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await localFixture.store.retireProcessed(
                membership: foreignMembership,
                decision: foreignDecision
            )
        }
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await localFixture.store.retireInvalidated(
                membership: foreignMembership,
                policy: foreignPolicy
            )
        }
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await localFixture.store.retireExpired(
                membership: foreignMembership
            )
        }
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await localFixture.store.retireProcessed(
                membership: localMembership,
                decision: foreignDecision
            )
        }
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await localFixture.store.retireInvalidated(
                membership: localMembership,
                policy: foreignPolicy
            )
        }
        #expect(
            localMembership.deliveryRelation(to: foreignStoreTerminal)
                == .collision
        )
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await localFixture.store.retireProcessed(
                membership: localMembership,
                terminalDelivery: foreignStoreTerminal
            )
        }

        #expect(localFixture.journal.events.isEmpty)
        #expect(localFixture.clock.readCount == localClockReads)
        #expect(localFixture.journal.currentEnvelope?.entries.count == 1)
    }

    @Test func missingReadAndFirstTransferAreStrictAndReceiptIsIdentityBound() async throws {
        let fixture = OutboxStoreFixture(now: outboxStoreDate())
        #expect(try await fixture.store.load() == nil)
        #expect(fixture.journal.events == ["load"])
        fixture.journal.resetEvents()
        let capabilities = try await outboxCapabilities(index: 1)

        let receipt = try await fixture.store.transferForTesting(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )
        #expect(
            receipt.provesMembershipForDeliveryRemoval(
                for: capabilities.delivery
            )
        )
        let confirmedEntry = try #require(
            receipt.confirmedEntryForAcceptedDecision()
        )
        #expect(
            confirmedEntry.hasSameImmutableBytes(
                as: try outboxEntry(from: capabilities.delivery)
            )
        )
        #expect(
            String(describing: receipt)
                == "IOSAcceptedHistoryOutboxReceipt(redacted)"
        )
        #expect(receipt.customMirror.children.isEmpty)
        #expect(fixture.journal.currentEnvelope?.revision == 1)
        #expect(fixture.journal.currentEnvelope?.entries.count == 1)
        #expect(fixture.journal.events == ["load", "create:1"])

        let wrong = try outboxDeliveryAuthorization(index: 2)
        #expect(!receipt.provesMembershipForDeliveryRemoval(for: wrong))
        let wrongFileRevision = try outboxDeliveryAuthorization(
            index: 1,
            fileRevisionToken: 10_001
        )
        #expect(
            !receipt.provesMembershipForDeliveryRemoval(
                for: wrongFileRevision
            )
        )
    }

    @Test func transferUsesOneTemporalSnapshotAndExactBoundaries() async throws {
        let createdAt = outboxStoreDate()
        let rollbackFixture = OutboxStoreFixture(
            now: createdAt.addingTimeInterval(-0.001)
        )
        let capabilities = try await outboxCapabilities(
            index: 10,
            createdAt: createdAt
        )
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.clockRollbackAmbiguous
        ) {
            try await rollbackFixture.store.transferForTesting(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }

        let liveFixture = OutboxStoreFixture(now: createdAt)
        _ = try await liveFixture.store.transferForTesting(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )

        let expiredFixture = OutboxStoreFixture(
            now: createdAt.addingTimeInterval(86_400)
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.expired) {
            try await expiredFixture.store.transferForTesting(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }

        let submillisecondCreatedAtFixture = OutboxStoreFixture(
            now: createdAt.addingTimeInterval(-0.0004)
        )
        _ = try await submillisecondCreatedAtFixture.store.transferForTesting(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )

        let submillisecondExpiryFixture = OutboxStoreFixture(
            now: createdAt.addingTimeInterval(86_400 - 0.0004)
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.expired) {
            try await submillisecondExpiryFixture.store.transferForTesting(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }
        #expect(rollbackFixture.clock.readCount == 1)
        #expect(liveFixture.clock.readCount == 1)
        #expect(expiredFixture.clock.readCount == 1)
        #expect(submillisecondCreatedAtFixture.clock.readCount == 1)
        #expect(submillisecondExpiryFixture.clock.readCount == 1)
    }

    @Test func sealedTransferRequiresPendingEnabledMatchingGeneration() async throws {
        let fixture = OutboxStoreFixture(now: outboxStoreDate())
        let capabilities = try await outboxCapabilities(
            index: 20,
            generation: 2
        )
        let disabled = try await outboxPolicyReceipt(
            generation: 2,
            enabled: false
        )
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.stalePolicyGeneration
        ) {
            try await fixture.store.transferForTesting(
                delivery: capabilities.delivery,
                policy: disabled
            )
        }
        let wrongGeneration = try await outboxPolicyReceipt(
            generation: 3,
            enabled: true
        )
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.stalePolicyGeneration
        ) {
            try await fixture.store.transferForTesting(
                delivery: capabilities.delivery,
                policy: wrongGeneration
            )
        }
        let replayable = try outboxDeliveryAuthorization(
            index: 22,
            generation: 2,
            historyState: .pendingReplacement
        )
        let replayReceipt = try await fixture.store.transferForTesting(
            delivery: replayable,
            policy: capabilities.policy
        )
        #expect(
            replayReceipt.provesMembershipForDeliveryRemoval(
                for: replayable
            )
        )
        let terminal = try outboxDeliveryAuthorization(
            index: 21,
            generation: 2,
            historyState: .committed
        )
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.stalePolicyGeneration
        ) {
            try await fixture.store.transferForTesting(
                delivery: terminal,
                policy: capabilities.policy
            )
        }
    }

    @Test func duplicateConfirmsWithoutPruningOrRevisionChange() async throws {
        let now = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: now)
        let capabilities = try await outboxCapabilities(
            index: 30,
            generation: 2,
            createdAt: now.addingTimeInterval(-10)
        )
        let duplicate = try outboxEntry(from: capabilities.delivery)
        let expired = try outboxStoredEntry(
            index: 31,
            generation: 1,
            createdAt: now.addingTimeInterval(-100_000)
        )
        fixture.journal.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 7,
                entries: [expired, duplicate]
            )
        )

        let receipt = try await fixture.store.transferForTesting(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )
        #expect(
            receipt.provesMembershipForDeliveryRemoval(
                for: capabilities.delivery
            )
        )
        #expect(fixture.journal.currentEnvelope?.revision == 7)
        #expect(fixture.journal.currentEnvelope?.entries == [expired, duplicate])
        #expect(fixture.journal.events.suffix(2) == ["load", "replace:7"])
    }

    @Test func collisionScanIncludesExpiredAndStaleEntriesAndUsesBytes() async throws {
        let now = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: now)
        let capabilities = try await outboxCapabilities(
            index: 40,
            generation: 2,
            acceptedText: "e\u{301}",
            createdAt: now.addingTimeInterval(-10)
        )
        let colliding = try outboxStoredEntry(
            index: 40,
            generation: 1,
            acceptedText: "é",
            createdAt: now.addingTimeInterval(-100_000)
        )
        fixture.journal.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 3,
                entries: [colliding]
            )
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.collision) {
            try await fixture.store.transferForTesting(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }

        let transcriptFixture = OutboxStoreFixture(now: now)
        let candidate = try await outboxCapabilities(
            index: 41,
            createdAt: now.addingTimeInterval(-10)
        )
        let transcriptCollision = try outboxStoredEntry(
            index: 42,
            transcriptID: candidate.delivery.record.transcriptID,
            createdAt: now.addingTimeInterval(-20)
        )
        transcriptFixture.journal.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [transcriptCollision]
            )
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.collision) {
            try await transcriptFixture.store.transferForTesting(
                delivery: candidate.delivery,
                policy: candidate.policy
            )
        }
    }

    @Test func transferAtomicallyPrunesExpiredAndStaleRows() async throws {
        let now = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: now)
        let stale = try outboxStoredEntry(
            index: 50,
            generation: 1,
            createdAt: now.addingTimeInterval(-100)
        )
        let expired = try outboxStoredEntry(
            index: 51,
            generation: 2,
            createdAt: now.addingTimeInterval(-100_000)
        )
        let current = try outboxStoredEntry(
            index: 52,
            generation: 2,
            createdAt: now.addingTimeInterval(-50)
        )
        fixture.journal.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 4,
                entries: [expired, stale, current]
            )
        )
        let candidate = try await outboxCapabilities(
            index: 53,
            generation: 2,
            createdAt: now.addingTimeInterval(-10)
        )

        _ = try await fixture.store.transferForTesting(
            delivery: candidate.delivery,
            policy: candidate.policy
        )
        #expect(fixture.journal.currentEnvelope?.revision == 5)
        #expect(fixture.journal.currentEnvelope?.entries.map(\.deliveryID) == [
            current.deliveryID,
            candidate.delivery.record.deliveryID,
        ])
    }

    @Test func futureGenerationFailsClosedWithoutPruning() async throws {
        let now = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: now)
        let future = try outboxStoredEntry(
            index: 60,
            generation: 3,
            createdAt: now.addingTimeInterval(-100)
        )
        fixture.journal.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 2,
                entries: [future]
            )
        )
        let candidate = try await outboxCapabilities(
            index: 61,
            generation: 2,
            createdAt: now.addingTimeInterval(-10)
        )
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.stalePolicyGeneration
        ) {
            try await fixture.store.transferForTesting(
                delivery: candidate.delivery,
                policy: candidate.policy
            )
        }
        #expect(fixture.journal.currentEnvelope?.entries == [future])
    }

    @Test func twentyLiveEntriesNeverEvictForAnotherTransfer() async throws {
        let now = outboxStoreDate()
        let entries = try (0..<20).map { offset in
            try outboxStoredEntry(
                index: 100 + offset,
                createdAt: now.addingTimeInterval(Double(-100 + offset))
            )
        }
        let source = try IOSAcceptedHistoryOutboxEnvelope(
            revision: 9,
            entries: entries
        )
        let fixture = OutboxStoreFixture(now: now)
        fixture.journal.install(source)
        let candidate = try await outboxCapabilities(
            index: 200,
            createdAt: now.addingTimeInterval(-10)
        )

        await #expect(throws: IOSAcceptedHistoryOutboxError.capacityExceeded) {
            try await fixture.store.transferForTesting(
                delivery: candidate.delivery,
                policy: candidate.policy
            )
        }
        #expect(fixture.journal.currentEnvelope == source)
        #expect(!fixture.journal.events.contains(where: { $0.hasPrefix("replace") }))
    }

    @Test func encodedByteCapacityNeverEvictsLiveEntries() async throws {
        let now = outboxStoreDate()
        let hugeText = "a" + String(repeating: "\t", count: 131_070) + "b"
        let entries = try (0..<15).map { offset in
            try outboxStoredEntry(
                index: 300 + offset,
                acceptedText: hugeText,
                createdAt: now.addingTimeInterval(Double(-100 + offset))
            )
        }
        let source = try IOSAcceptedHistoryOutboxEnvelope(
            revision: 1,
            entries: entries
        )
        _ = try IOSAcceptedHistoryOutboxWireCodec.encode(source)
        let fixture = OutboxStoreFixture(now: now)
        fixture.journal.install(source)
        let candidate = try await outboxCapabilities(
            index: 399,
            acceptedText: hugeText,
            createdAt: now.addingTimeInterval(-10)
        )

        await #expect(throws: IOSAcceptedHistoryOutboxError.capacityExceeded) {
            try await fixture.store.transferForTesting(
                delivery: candidate.delivery,
                policy: candidate.policy
            )
        }
        #expect(fixture.journal.currentEnvelope == source)
    }

    @Test func insufficientExpiredPruningDoesNotCommitPartialCleanup() async throws {
        let now = outboxStoreDate()
        let hugeText = "a" + String(repeating: "\t", count: 131_070) + "b"
        let expired = try outboxStoredEntry(
            index: 380,
            createdAt: now.addingTimeInterval(-100_000)
        )
        let live = try (0..<15).map { offset in
            try outboxStoredEntry(
                index: 381 + offset,
                acceptedText: hugeText,
                createdAt: now.addingTimeInterval(Double(-100 + offset))
            )
        }
        let source = try IOSAcceptedHistoryOutboxEnvelope(
            revision: 8,
            entries: [expired] + live
        )
        _ = try IOSAcceptedHistoryOutboxWireCodec.encode(source)
        let fixture = OutboxStoreFixture(now: now)
        fixture.journal.install(source)
        let candidate = try await outboxCapabilities(
            index: 398,
            acceptedText: hugeText,
            createdAt: now.addingTimeInterval(-10)
        )

        await #expect(throws: IOSAcceptedHistoryOutboxError.capacityExceeded) {
            try await fixture.store.transferForTesting(
                delivery: candidate.delivery,
                policy: candidate.policy
            )
        }
        #expect(fixture.journal.currentEnvelope == source)
        #expect(
            fixture.journal.currentEnvelope?.entries.first?.deliveryID
                == expired.deliveryID
        )
    }

    @Test func rollbackInAnyPersistedEntryBlocksTransferWithoutMutation() async throws {
        let now = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: now)
        let future = try outboxStoredEntry(
            index: 400,
            createdAt: now.addingTimeInterval(1)
        )
        fixture.journal.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [future]
            )
        )
        let candidate = try await outboxCapabilities(
            index: 401,
            createdAt: now
        )
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.clockRollbackAmbiguous
        ) {
            try await fixture.store.transferForTesting(
                delivery: candidate.delivery,
                policy: candidate.policy
            )
        }
        #expect(fixture.journal.currentEnvelope?.entries == [future])
    }

    @Test func confirmationRecoversExactExpiredOrRollbackMembership() async throws {
        let now = outboxStoreDate()
        for createdAt in [
            now.addingTimeInterval(-100_000),
            now.addingTimeInterval(1),
        ] {
            let fixture = OutboxStoreFixture(now: now)
            let capabilities = try await outboxCapabilities(
                index: createdAt < now ? 410 : 411,
                createdAt: createdAt
            )
            let entry = try outboxEntry(from: capabilities.delivery)
            fixture.journal.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 4,
                    entries: [entry]
                )
            )

            let receipt = try await fixture.store.confirmMembership(
                delivery: capabilities.delivery
            )
            #expect(
                receipt.provesMembershipForDeliveryRemoval(
                    for: capabilities.delivery
                )
            )
            #expect(fixture.journal.currentEnvelope?.revision == 4)
        }
    }

    @Test func duplicateAtMaximumSucceedsButNewMembershipOverflows() async throws {
        let now = outboxStoreDate()
        let duplicate = try await outboxCapabilities(
            index: 420,
            createdAt: now.addingTimeInterval(-10)
        )
        let entry = try outboxEntry(from: duplicate.delivery)
        let fixture = OutboxStoreFixture(now: now)
        fixture.journal.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: Int64.max,
                entries: [entry]
            )
        )
        _ = try await fixture.store.transferForTesting(
            delivery: duplicate.delivery,
            policy: duplicate.policy
        )

        let other = try await outboxCapabilities(
            index: 421,
            createdAt: now.addingTimeInterval(-5)
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.revisionOverflow) {
            try await fixture.store.transferForTesting(
                delivery: other.delivery,
                policy: other.policy
            )
        }
        #expect(fixture.journal.currentEnvelope?.entries == [entry])
    }

    @Test func uncertaintyBlocksOtherTransferAndConfirmsExactRetry() async throws {
        let now = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: now)
        let first = try await outboxCapabilities(index: 430, createdAt: now)
        fixture.journal.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            try await fixture.store.transferForTesting(
                delivery: first.delivery,
                policy: first.policy
            )
        }
        let other = try await outboxCapabilities(index: 431, createdAt: now)
        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            try await fixture.store.transferForTesting(
                delivery: other.delivery,
                policy: other.policy
            )
        }
        let receipt = try await fixture.store.transferForTesting(
            delivery: first.delivery,
            policy: first.policy
        )
        #expect(
            receipt.provesMembershipForDeliveryRemoval(for: first.delivery)
        )
        #expect(fixture.journal.events.suffix(2) == ["load", "replace:1"])
    }

    @Test func prepublicationReplacementUncertaintyIsAStoreWideGate() async throws {
        let now = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: now)
        fixture.journal.install(
            try IOSAcceptedHistoryOutboxEnvelope(revision: 1, entries: [])
        )
        let first = try await outboxCapabilities(index: 435, createdAt: now)
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            try await fixture.store.transferForTesting(
                delivery: first.delivery,
                policy: first.policy
            )
        }
        let other = try await outboxCapabilities(index: 436, createdAt: now)
        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            try await fixture.store.transferForTesting(
                delivery: other.delivery,
                policy: other.policy
            )
        }

        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            try await fixture.store.confirmMembership(delivery: first.delivery)
        }
        #expect(fixture.journal.currentEnvelope?.revision == 1)
        #expect(fixture.journal.currentEnvelope?.entries.isEmpty == true)

        let receipt = try await fixture.store.transferForTesting(
            delivery: first.delivery,
            policy: first.policy
        )
        #expect(
            receipt.provesMembershipForDeliveryRemoval(for: first.delivery)
        )
        #expect(fixture.journal.currentEnvelope?.revision == 2)
    }

    @Test func prepublicationCreateConfirmationNeverInsertsMembership() async throws {
        let now = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: now)
        let capabilities = try await outboxCapabilities(
            index: 437,
            createdAt: now
        )
        fixture.journal.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            try await fixture.store.transferForTesting(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }

        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            try await fixture.store.confirmMembership(
                delivery: capabilities.delivery
            )
        }
        #expect(fixture.journal.currentEnvelope == nil)
        #expect(fixture.journal.events.filter { $0 == "create:1" }.count == 1)
    }

    @Test func invisibleUncertainTransferRevalidatesTimeBeforePublishing() async throws {
        let now = outboxStoreDate()
        let createFixture = OutboxStoreFixture(now: now)
        let createCapabilities = try await outboxCapabilities(
            index: 438,
            createdAt: now
        )
        createFixture.journal.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            try await createFixture.store.transferForTesting(
                delivery: createCapabilities.delivery,
                policy: createCapabilities.policy
            )
        }
        createFixture.clock.set(now.addingTimeInterval(86_400))
        await #expect(throws: IOSAcceptedHistoryOutboxError.expired) {
            try await createFixture.store.transferForTesting(
                delivery: createCapabilities.delivery,
                policy: createCapabilities.policy
            )
        }
        #expect(createFixture.journal.currentEnvelope == nil)
        #expect(
            createFixture.journal.events.filter { $0 == "create:1" }.count == 1
        )
        let nextCapabilities = try await outboxCapabilities(
            index: 446,
            createdAt: now.addingTimeInterval(86_400)
        )
        let nextReceipt = try await createFixture.store.transferForTesting(
            delivery: nextCapabilities.delivery,
            policy: nextCapabilities.policy
        )
        #expect(
            nextReceipt.provesMembershipForDeliveryRemoval(
                for: nextCapabilities.delivery
            )
        )

        let replaceFixture = OutboxStoreFixture(now: now)
        replaceFixture.journal.install(
            try IOSAcceptedHistoryOutboxEnvelope(revision: 1, entries: [])
        )
        let replaceCapabilities = try await outboxCapabilities(
            index: 439,
            createdAt: now
        )
        replaceFixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            try await replaceFixture.store.transferForTesting(
                delivery: replaceCapabilities.delivery,
                policy: replaceCapabilities.policy
            )
        }
        replaceFixture.clock.set(now.addingTimeInterval(-0.001))
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.clockRollbackAmbiguous
        ) {
            try await replaceFixture.store.transferForTesting(
                delivery: replaceCapabilities.delivery,
                policy: replaceCapabilities.policy
            )
        }
        #expect(replaceFixture.journal.currentEnvelope?.revision == 1)
        #expect(replaceFixture.journal.currentEnvelope?.entries.isEmpty == true)
        #expect(
            replaceFixture.journal.events.filter { $0 == "replace:2" }.count
                == 1
        )

        replaceFixture.clock.set(now)
        let recovered = try await replaceFixture.store.transferForTesting(
            delivery: replaceCapabilities.delivery,
            policy: replaceCapabilities.policy
        )
        #expect(
            recovered.provesMembershipForDeliveryRemoval(
                for: replaceCapabilities.delivery
            )
        )
        #expect(replaceFixture.journal.currentEnvelope?.revision == 2)
    }

    @Test func visibleUncertaintyRemainsConfirmableAcrossTimeBoundaries() async throws {
        let now = outboxStoreDate()
        for (index, confirmationTime) in [
            (442, now.addingTimeInterval(86_400)),
            (443, now.addingTimeInterval(-0.001)),
        ] {
            let fixture = OutboxStoreFixture(now: now)
            let capabilities = try await outboxCapabilities(
                index: index,
                createdAt: now
            )
            fixture.journal.failNextCreate(
                with: .commitUncertain,
                commitBeforeThrowing: true
            )
            await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
                try await fixture.store.transferForTesting(
                    delivery: capabilities.delivery,
                    policy: capabilities.policy
                )
            }
            fixture.clock.set(confirmationTime)

            let receipt = try await fixture.store.confirmMembership(
                delivery: capabilities.delivery
            )
            #expect(
                receipt.provesMembershipForDeliveryRemoval(
                    for: capabilities.delivery
                )
            )
            #expect(fixture.journal.currentEnvelope?.revision == 1)
            #expect(fixture.clock.readCount == 1)
        }
    }

    @Test func snapshotObservationRecoversAfterRelaunchWithoutDelivery() async throws {
        let now = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: now)
        let capabilities = try await outboxCapabilities(
            index: 444,
            createdAt: now
        )
        _ = try await fixture.store.transferForTesting(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )
        fixture.clock.set(now.addingTimeInterval(86_400))
        let relaunchedStore = fixture.makeStore()
        let observations = try #require(try await relaunchedStore.observe())
        let observation = try #require(observations.first)
        #expect(
            String(describing: observation)
                == "IOSAcceptedHistoryOutboxObservation(redacted)"
        )
        #expect(observation.customMirror.children.isEmpty)

        let receipt = try await relaunchedStore.confirmMembership(
            observation: observation
        )
        #expect(receipt.provesMembership(for: observation))
        #expect(
            !receipt.provesMembershipForDeliveryRemoval(
                for: capabilities.delivery
            )
        )
        #expect(receipt.confirmedEntryForAcceptedDecision() != nil)
        #expect(
            String(reflecting: receipt)
                == "IOSAcceptedHistoryOutboxReceipt(redacted)"
        )
        #expect(receipt.customMirror.children.isEmpty)

        let differentObservations = try #require(
            try await fixture.makeStore().observe()
        )
        let differentObservation = try #require(differentObservations.first)
        #expect(!receipt.provesMembership(for: differentObservation))

        let staleObservations = try #require(
            try await fixture.makeStore().observe()
        )
        let staleObservation = try #require(staleObservations.first)
        let other = try await outboxCapabilities(
            index: 445,
            createdAt: now.addingTimeInterval(86_400)
        )
        _ = try await fixture.makeStore().transferForTesting(
            delivery: other.delivery,
            policy: other.policy
        )
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await fixture.makeStore().confirmMembership(
                observation: staleObservation
            )
        }
    }

    @Test func staleObservationCannotResolveVisibleUncertainty() async throws {
        let now = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: now)
        let capabilities = try await outboxCapabilities(
            index: 447,
            createdAt: now
        )
        _ = try await fixture.store.transferForTesting(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )
        let observations = try #require(try await fixture.store.observe())
        let staleObservation = try #require(observations.first)
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            try await fixture.store.transferForTesting(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }

        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await fixture.store.confirmMembership(
                observation: staleObservation
            )
        }
        let receipt = try await fixture.store.confirmMembership(
            delivery: capabilities.delivery
        )
        #expect(
            receipt.provesMembershipForDeliveryRemoval(
                for: capabilities.delivery
            )
        )
    }

    @Test func twoStoresUsePhysicalCASWithoutLostMembership() async throws {
        let now = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: now)
        fixture.journal.install(
            try IOSAcceptedHistoryOutboxEnvelope(revision: 1, entries: [])
        )
        fixture.journal.freezeNextLoads(2)
        let first = try await outboxCapabilities(index: 440, createdAt: now)
        let second = try await outboxCapabilities(index: 441, createdAt: now)
        let firstTask = Task {
            try await fixture.store.transferForTesting(
                delivery: first.delivery,
                policy: first.policy
            )
        }
        let secondTask = Task {
            try await fixture.makeStore().transferForTesting(
                delivery: second.delivery,
                policy: second.policy
            )
        }
        let firstResult = await firstTask.result
        let secondResult = await secondTask.result
        #expect([firstResult, secondResult].filter {
            if case .success = $0 { return true }
            return false
        }.count == 1)
        let loser = if case .failure = firstResult { first } else { second }
        _ = try await fixture.store.transferForTesting(
            delivery: loser.delivery,
            policy: loser.policy
        )
        #expect(fixture.journal.currentEnvelope?.revision == 3)
        #expect(fixture.journal.currentEnvelope?.entries.count == 2)
    }

    @Test func headObservationAndEveryRetirementEnforceStrictFIFO() async throws {
        let now = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: now)
        let first = try await outboxCapabilities(
            index: 700,
            createdAt: now.addingTimeInterval(-20)
        )
        let second = try await outboxCapabilities(
            index: 701,
            createdAt: now.addingTimeInterval(-10)
        )
        _ = try await fixture.store.transferForTesting(
            delivery: first.delivery,
            policy: first.policy
        )
        let nonHeadMembership = try await fixture.store.transferForTesting(
            delivery: second.delivery,
            policy: second.policy
        )
        let head = try #require(try await fixture.store.observeHead())
        #expect(head.isHead)
        #expect(head.entry.deliveryID == first.delivery.record.deliveryID)
        #expect(try await fixture.store.observe()?.count == 1)

        let nonHeadDecision = try await outboxRowReceipt(
            membership: nonHeadMembership
        )
        let terminal = try outboxDeliveryAuthorization(
            index: 701,
            createdAt: now.addingTimeInterval(-10),
            historyState: .committed
        )
        let invalidation = try await outboxPolicyReceipt(
            generation: 2,
            enabled: false
        )
        let source = fixture.journal.currentEnvelope
        let clockReads = fixture.clock.readCount
        fixture.journal.resetEvents()

        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            _ = try await fixture.store.classifyTemporalState(
                membership: nonHeadMembership
            )
        }
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await fixture.store.retireProcessed(
                membership: nonHeadMembership,
                decision: nonHeadDecision
            )
        }
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await fixture.store.retireProcessed(
                membership: nonHeadMembership,
                terminalDelivery: terminal
            )
        }
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await fixture.store.retireInvalidated(
                membership: nonHeadMembership,
                policy: invalidation
            )
        }
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await fixture.store.retireExpired(
                membership: nonHeadMembership
            )
        }

        #expect(fixture.journal.currentEnvelope == source)
        #expect(
            !fixture.journal.events.contains(where: {
                $0.hasPrefix("replace")
            })
        )
        #expect(fixture.clock.readCount == clockReads)
    }

    @Test func temporalReceiptSealsOneClockSampleAcrossUncertainRetry()
        async throws {
        let createdAt = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: createdAt)
        let capabilities = try await outboxCapabilities(
            index: 702,
            createdAt: createdAt
        )
        let membership = try await outboxMembershipReceipt(
            fixture: fixture,
            capabilities: capabilities,
            origin: .observation
        )
        fixture.clock.set(createdAt.addingTimeInterval(86_400))
        let readsBefore = fixture.clock.readCount
        let classification = try await fixture.store.classifyTemporalState(
            membership: membership
        )
        #expect(classification.temporalState == .expired)
        #expect(classification.membership == membership)
        #expect(fixture.clock.readCount == readsBefore + 1)
        #expect(
            String(reflecting: classification)
                == "IOSAcceptedHistoryOutboxTemporalReceipt(redacted)"
        )
        #expect(classification.customMirror.children.isEmpty)

        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            try await fixture.store.retireExpired(
                classification: classification
            )
        }
        fixture.clock.set(createdAt)
        let readsBeforeRetry = fixture.clock.readCount
        try await fixture.store.retireExpired(classification: classification)
        #expect(fixture.clock.readCount == readsBeforeRetry)
        #expect(fixture.journal.currentEnvelope?.entries.isEmpty == true)
    }

    @Test func membershipDeliveryRelationUsesExactPayloadAndIdentity()
        async throws {
        let createdAt = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: createdAt)
        let capabilities = try await outboxCapabilities(
            index: 703,
            createdAt: createdAt
        )
        let membership = try await outboxMembershipReceipt(
            fixture: fixture,
            capabilities: capabilities
        )
        let entry = try #require(
            membership.confirmedEntryForAcceptedDecision()
        )

        for state in [
            IOSAcceptedOutputHistoryWriteState.pending,
            .pendingReplacement,
        ] {
            let authorization = try outboxDeliveryAuthorization(
                index: 703,
                createdAt: createdAt,
                historyState: state
            )
            #expect(membership.deliveryRelation(to: authorization) == .pending)
        }
        #expect(
            membership.deliveryRelation(
                to: try outboxDeliveryAuthorization(
                    index: 703,
                    createdAt: createdAt,
                    historyState: .committed
                )
            ) == .committed
        )
        #expect(
            membership.deliveryRelation(
                to: try outboxDeliveryAuthorization(
                    index: 703,
                    createdAt: createdAt,
                    historyState: .cancelled
                )
            ) == .cancelled
        )
        #expect(
            membership.deliveryRelation(
                to: try outboxDiscardedAuthorization(
                    matching: entry,
                    index: 703
                )
            ) == .discarded
        )
        #expect(
            membership.deliveryRelation(
                to: try outboxDeliveryAuthorization(
                    index: 704,
                    createdAt: createdAt
                )
            ) == .unrelated
        )

        let collisions = try [
            outboxDeliveryAuthorization(
                index: 703,
                acceptedText: "Different bytes",
                createdAt: createdAt
            ),
            outboxDeliveryAuthorization(
                index: 703,
                generation: 2,
                createdAt: createdAt
            ),
            outboxDeliveryAuthorization(
                index: 703,
                createdAt: createdAt,
                transcriptID: outboxUUID(prefix: 3, index: 999)
            ),
            outboxDeliveryAuthorization(
                index: 999,
                createdAt: createdAt,
                transcriptID: entry.transcriptID
            ),
            outboxDeliveryAuthorization(
                index: 703,
                createdAt: createdAt.addingTimeInterval(1)
            ),
            outboxDeliveryAuthorization(
                index: 703,
                createdAt: createdAt,
                outputIntent: .translate
            ),
            outboxDeliveryAuthorization(
                index: 703,
                createdAt: createdAt,
                transcriptionModel: "whisper-1"
            ),
            outboxDeliveryAuthorization(
                index: 703,
                createdAt: createdAt,
                transcriptionLanguageCode: "fr"
            ),
            outboxDeliveryAuthorization(
                index: 703,
                createdAt: createdAt,
                durationMilliseconds: 2_500
            ),
        ]
        for authorization in collisions {
            #expect(
                membership.deliveryRelation(to: authorization) == .collision
            )
        }
        #expect(
            String(describing: IOSAcceptedHistoryOutboxDeliveryRelation.pending)
                == "IOSAcceptedHistoryOutboxDeliveryRelation(redacted)"
        )
    }

    @Test func committedTerminalDeliveryRetiresNotRetainedHeadWithoutRow()
        async throws {
        let createdAt = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: createdAt)
        let capabilities = try await outboxCapabilities(
            index: 705,
            createdAt: createdAt
        )
        let membership = try await outboxMembershipReceipt(
            fixture: fixture,
            capabilities: capabilities,
            origin: .observation
        )
        let terminal = try outboxDeliveryAuthorization(
            index: 705,
            createdAt: createdAt,
            historyState: .committed
        )

        try await fixture.store.retireProcessed(
            membership: membership,
            terminalDelivery: terminal
        )
        #expect(fixture.journal.currentEnvelope?.revision == 2)
        #expect(fixture.journal.currentEnvelope?.entries.isEmpty == true)

        let rejected = OutboxStoreFixture(now: createdAt)
        let rejectedMembership = try await outboxMembershipReceipt(
            fixture: rejected,
            capabilities: capabilities,
            origin: .observation
        )
        rejected.journal.resetEvents()
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await rejected.store.retireProcessed(
                membership: rejectedMembership,
                terminalDelivery: try outboxDeliveryAuthorization(
                    index: 705,
                    createdAt: createdAt,
                    historyState: .cancelled
                )
            )
        }
        #expect(rejected.journal.currentEnvelope?.entries.count == 1)
        #expect(rejected.journal.events == ["load"])
    }

    @Test func deliveryAbsenceDispositionScansAndSealsExactSnapshot()
        async throws {
        let createdAt = outboxStoreDate()
        let terminal = try outboxDeliveryAuthorization(
            index: 706,
            createdAt: createdAt,
            historyState: .committed
        )

        let missing = OutboxStoreFixture(now: createdAt)
        let (missingAuthorization, expiredMissingLease) = try await missing
            .operationGate
            .perform { lease in
                let disposition = try await missing.store
                    .classifyDeliveryAbsence(
                        authorization: terminal,
                        operationLeaseAuthorization: lease
                    )
                guard case .absent(let authorization) = disposition else {
                    Issue.record("Missing outbox must mint absence authorization")
                    throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
                }
                #expect(
                    authorization.provesAbsence(
                        for: terminal,
                        deliveryStoreIdentity: missing.deliveryStoreIdentity,
                        outboxStoreIdentity: missing.store.storeIdentity,
                        ownerIdentity: outboxCapabilityOwnerIdentity,
                        operationLeaseAuthorization: lease
                    )
                )
                return (authorization, lease)
            }
        #expect(
            !missingAuthorization.provesAbsence(
                for: terminal,
                deliveryStoreIdentity: missing.deliveryStoreIdentity,
                outboxStoreIdentity: missing.store.storeIdentity,
                ownerIdentity: outboxCapabilityOwnerIdentity,
                operationLeaseAuthorization: expiredMissingLease
            )
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed) {
            _ = try await missing.store.classifyDeliveryAbsence(
                authorization: terminal,
                operationLeaseAuthorization: expiredMissingLease
            )
        }
        #expect(missing.journal.events == ["load"])

        let matching = OutboxStoreFixture(now: createdAt)
        _ = try await outboxMembershipReceipt(
            fixture: matching,
            capabilities: try await outboxCapabilities(
                index: 706,
                createdAt: createdAt
            )
        )
        matching.journal.resetEvents()
        #expect(
            try await matching.operationGate.perform { lease in
                try await matching.store.classifyDeliveryAbsence(
                    authorization: terminal,
                    operationLeaseAuthorization: lease
                )
            } == .matching
        )
        #expect(matching.journal.events == ["load"])

        let collision = OutboxStoreFixture(now: createdAt)
        collision.journal.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [
                    try outboxStoredEntry(
                        index: 706,
                        acceptedText: "Different bytes",
                        createdAt: createdAt
                    ),
                ]
            )
        )
        #expect(
            try await collision.operationGate.perform { lease in
                try await collision.store.classifyDeliveryAbsence(
                    authorization: terminal,
                    operationLeaseAuthorization: lease
                )
            } == .collision
        )
        #expect(collision.journal.events == ["load"])

        let absent = OutboxStoreFixture(now: createdAt)
        absent.journal.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 4,
                entries: [
                    try outboxStoredEntry(
                        index: 707,
                        createdAt: createdAt
                    ),
                ]
            )
        )
        absent.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            _ = try await absent.operationGate.perform { lease in
                try await absent.store.classifyDeliveryAbsence(
                    authorization: terminal,
                    operationLeaseAuthorization: lease
                )
            }
        }
        await #expect(throws: IOSAcceptedHistoryOutboxError.commitUncertain) {
            _ = try await absent.store.observeHead()
        }
        try await absent.operationGate.perform { lease in
            let disposition = try await absent.store.classifyDeliveryAbsence(
                authorization: terminal,
                operationLeaseAuthorization: lease
            )
            guard case .absent(let authorization) = disposition else {
                Issue.record("Unrelated existing outbox must confirm absence")
                return
            }
            #expect(
                authorization.provesAbsence(
                    for: terminal,
                    deliveryStoreIdentity: absent.deliveryStoreIdentity,
                    outboxStoreIdentity: absent.store.storeIdentity,
                    ownerIdentity: outboxCapabilityOwnerIdentity,
                    operationLeaseAuthorization: lease
                )
            )
            #expect(
                !authorization.provesAbsence(
                    for: terminal,
                    deliveryStoreIdentity:
                        IOSAcceptedOutputDeliveryStoreIdentity(),
                    outboxStoreIdentity: absent.store.storeIdentity,
                    ownerIdentity: outboxCapabilityOwnerIdentity,
                    operationLeaseAuthorization: lease
                )
            )
            #expect(
                !authorization.provesAbsence(
                    for: terminal,
                    deliveryStoreIdentity: absent.deliveryStoreIdentity,
                    outboxStoreIdentity:
                        IOSAcceptedHistoryOutboxStoreIdentity(),
                    ownerIdentity: outboxCapabilityOwnerIdentity,
                    operationLeaseAuthorization: lease
                )
            )
            #expect(
                !authorization.provesAbsence(
                    for: try outboxDeliveryAuthorization(
                        index: 708,
                        createdAt: createdAt,
                        historyState: .committed
                    ),
                    deliveryStoreIdentity: absent.deliveryStoreIdentity,
                    outboxStoreIdentity: absent.store.storeIdentity,
                    ownerIdentity: outboxCapabilityOwnerIdentity,
                    operationLeaseAuthorization: lease
                )
            )
            #expect(
                String(reflecting: authorization)
                    == "IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization(redacted)"
            )
            #expect(authorization.customMirror.children.isEmpty)
            #expect(
                String(reflecting: disposition)
                    == "IOSAcceptedHistoryOutboxDeliveryAbsenceDisposition(redacted)"
            )
        }
    }

    @Test func deliveryAbsenceRejectsForeignActiveGateBeforeJournalIO()
        async throws {
        let createdAt = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: createdAt)
        let terminal = try outboxDeliveryAuthorization(
            index: 708,
            createdAt: createdAt,
            historyState: .committed
        )
        let foreignGate = IOSPersistenceOperationGate()
        fixture.journal.resetEvents()
        let clockReads = fixture.clock.readCount

        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            _ = try await foreignGate.perform { lease in
                try await fixture.store.classifyDeliveryAbsence(
                    authorization: terminal,
                    operationLeaseAuthorization: lease
                )
            }
        }

        #expect(fixture.journal.events.isEmpty)
        #expect(fixture.clock.readCount == clockReads)
    }

    @Test func processedRetirementAcceptsBothOriginsAndRetentionDecisions() async throws {
        let cases: [(Int, OutboxMembershipOrigin, Bool)] = [
            (460, .delivery, true),
            (461, .observation, true),
            (462, .delivery, false),
            (492, .observation, false),
        ]
        for (index, origin, retained) in cases {
            let now = outboxStoreDate()
            let fixture = OutboxStoreFixture(now: now)
            let capabilities = try await outboxCapabilities(
                index: index,
                createdAt: now
            )
            let membership = try await outboxMembershipReceipt(
                fixture: fixture,
                capabilities: capabilities,
                origin: origin
            )
            let decision = try await outboxRowReceipt(
                membership: membership,
                retained: retained
            )
            #expect(
                decision.decision
                    == (retained ? .retained : .notRetained)
            )

            try await fixture.store.retireProcessed(
                membership: membership,
                decision: decision
            )
            #expect(fixture.journal.currentEnvelope?.revision == 2)
            #expect(fixture.journal.currentEnvelope?.entries.isEmpty == true)
        }
    }

    @Test func retirementRejectsWrongEvidenceAndRequiresNewerPolicy() async throws {
        let now = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: now)
        let capabilities = try await outboxCapabilities(
            index: 463,
            generation: 2,
            createdAt: now
        )
        let membership = try await outboxMembershipReceipt(
            fixture: fixture,
            capabilities: capabilities
        )

        let foreignFixture = OutboxStoreFixture(now: now)
        let foreignMembership = try await outboxMembershipReceipt(
            fixture: foreignFixture,
            capabilities: try await outboxCapabilities(
                index: 464,
                generation: 2,
                createdAt: now
            )
        )
        let foreignDecision = try await outboxRowReceipt(
            membership: foreignMembership
        )
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await fixture.store.retireProcessed(
                membership: membership,
                decision: foreignDecision
            )
        }
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await fixture.store.retireProcessed(
                membership: foreignMembership,
                decision: foreignDecision
            )
        }

        for generation in [Int64(1), 2] {
            await #expect(
                throws: IOSAcceptedHistoryOutboxError.stalePolicyGeneration
            ) {
                try await fixture.store.retireInvalidated(
                    membership: membership,
                    policy: try await outboxPolicyReceipt(
                        generation: generation,
                        enabled: false
                    )
                )
            }
        }
        #expect(fixture.journal.currentEnvelope?.entries.count == 1)

        try await fixture.store.retireInvalidated(
            membership: membership,
            policy: try await outboxPolicyReceipt(
                generation: 3,
                enabled: false
            )
        )
        #expect(fixture.journal.currentEnvelope?.entries.isEmpty == true)
        #expect(
            String(describing: IOSAcceptedHistoryOutboxError.invalidTransition)
                == "IOSAcceptedHistoryOutboxError(redacted)"
        )
    }

    @Test func expiredRetirementUsesOneCanonicalMillisecondSnapshot() async throws {
        let createdAt = outboxStoreDate()
        let failureCases: [(Int, Date, IOSAcceptedHistoryOutboxError)] = [
            (
                465,
                createdAt.addingTimeInterval(86_400 - 0.0006),
                .invalidTransition
            ),
            (
                466,
                createdAt.addingTimeInterval(-0.001),
                .clockRollbackAmbiguous
            ),
        ]
        for (index, retirementTime, error) in failureCases {
            let fixture = OutboxStoreFixture(now: createdAt)
            let membership = try await outboxMembershipReceipt(
                fixture: fixture,
                capabilities: try await outboxCapabilities(
                    index: index,
                    createdAt: createdAt
                )
            )
            fixture.clock.set(retirementTime)
            let readsBefore = fixture.clock.readCount
            await #expect(throws: error) {
                try await fixture.store.retireExpired(
                    membership: membership
                )
            }
            #expect(fixture.clock.readCount == readsBefore + 1)
            #expect(fixture.journal.currentEnvelope?.entries.count == 1)
        }

        for (index, retirementTime) in [
            (467, createdAt.addingTimeInterval(86_400 - 0.0004)),
            (468, createdAt.addingTimeInterval(86_400)),
        ] {
            let fixture = OutboxStoreFixture(now: createdAt)
            let membership = try await outboxMembershipReceipt(
                fixture: fixture,
                capabilities: try await outboxCapabilities(
                    index: index,
                    createdAt: createdAt
                )
            )
            fixture.clock.set(retirementTime)
            let readsBefore = fixture.clock.readCount
            try await fixture.store.retireExpired(membership: membership)
            #expect(fixture.clock.readCount == readsBefore + 1)
            #expect(fixture.journal.currentEnvelope?.entries.isEmpty == true)
        }
    }

    @Test func retirementPreservesUnrelatedRowsAndRejectsRevisionOverflow() async throws {
        let now = outboxStoreDate()
        let fixture = OutboxStoreFixture(now: now)
        let target = try await outboxCapabilities(
            index: 469,
            createdAt: now.addingTimeInterval(-30)
        )
        let firstOther = try await outboxCapabilities(
            index: 470,
            createdAt: now.addingTimeInterval(-20)
        )
        let secondOther = try await outboxCapabilities(
            index: 471,
            createdAt: now.addingTimeInterval(-10)
        )
        _ = try await fixture.store.transferForTesting(
            delivery: target.delivery,
            policy: target.policy
        )
        _ = try await fixture.store.transferForTesting(
            delivery: firstOther.delivery,
            policy: firstOther.policy
        )
        _ = try await fixture.store.transferForTesting(
            delivery: secondOther.delivery,
            policy: secondOther.policy
        )
        let observations = try #require(try await fixture.store.observe())
        let targetObservation = try #require(observations.first(where: {
            $0.entry.deliveryID == target.delivery.record.deliveryID
        }))
        let membership = try await fixture.store.confirmMembership(
            observation: targetObservation
        )
        let decision = try await outboxRowReceipt(membership: membership)

        try await fixture.store.retireProcessed(
            membership: membership,
            decision: decision
        )
        #expect(fixture.journal.currentEnvelope?.revision == 4)
        #expect(fixture.journal.currentEnvelope?.entries.map(\.deliveryID) == [
            firstOther.delivery.record.deliveryID,
            secondOther.delivery.record.deliveryID,
        ])

        let overflowFixture = OutboxStoreFixture(now: now)
        let overflowEntry = try outboxStoredEntry(
            index: 472,
            createdAt: now
        )
        let overflowSource = try IOSAcceptedHistoryOutboxEnvelope(
            revision: Int64.max,
            entries: [overflowEntry]
        )
        overflowFixture.journal.install(overflowSource)
        let overflowObservations = try #require(
            try await overflowFixture.store.observe()
        )
        let overflowObservation = try #require(overflowObservations.first)
        let overflowMembership = try await overflowFixture.store
            .confirmMembership(observation: overflowObservation)
        let overflowDecision = try await outboxRowReceipt(
            membership: overflowMembership
        )
        overflowFixture.journal.resetEvents()
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.revisionOverflow
        ) {
            try await overflowFixture.store.retireProcessed(
                membership: overflowMembership,
                decision: overflowDecision
            )
        }
        #expect(overflowFixture.journal.currentEnvelope == overflowSource)
        #expect(overflowFixture.journal.events == ["load"])
    }

    @Test func staleReceiptAndTwoActorsCannotRetirePastPhysicalCAS() async throws {
        let now = outboxStoreDate()
        let staleFixture = OutboxStoreFixture(now: now)
        let staleMembership = try await outboxMembershipReceipt(
            fixture: staleFixture,
            capabilities: try await outboxCapabilities(
                index: 473,
                createdAt: now
            )
        )
        let staleDecision = try await outboxRowReceipt(
            membership: staleMembership
        )
        let other = try await outboxCapabilities(
            index: 474,
            createdAt: now
        )
        _ = try await staleFixture.store.transferForTesting(
            delivery: other.delivery,
            policy: other.policy
        )
        let staleSource = staleFixture.journal.currentEnvelope
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            try await staleFixture.store.retireProcessed(
                membership: staleMembership,
                decision: staleDecision
            )
        }
        #expect(staleFixture.journal.currentEnvelope == staleSource)

        let raceFixture = OutboxStoreFixture(now: now)
        let raceMembership = try await outboxMembershipReceipt(
            fixture: raceFixture,
            capabilities: try await outboxCapabilities(
                index: 475,
                createdAt: now
            )
        )
        let raceDecision = try await outboxRowReceipt(
            membership: raceMembership
        )
        raceFixture.journal.freezeNextLoads(2)
        let firstStore = raceFixture.store
        let secondStore = raceFixture.makeStore()
        let first = Task {
            try await firstStore.retireProcessed(
                membership: raceMembership,
                decision: raceDecision
            )
        }
        let second = Task {
            try await secondStore.retireProcessed(
                membership: raceMembership,
                decision: raceDecision
            )
        }
        let results = await [first.result, second.result]
        #expect(results.filter {
            if case .success = $0 { return true }
            return false
        }.count == 1)
        #expect(raceFixture.journal.currentEnvelope?.revision == 2)
        #expect(raceFixture.journal.currentEnvelope?.entries.isEmpty == true)

        let terminalRaceFixture = OutboxStoreFixture(now: now)
        let terminalRaceMembership = try await outboxMembershipReceipt(
            fixture: terminalRaceFixture,
            capabilities: try await outboxCapabilities(
                index: 476,
                createdAt: now
            )
        )
        let terminal = try outboxDeliveryAuthorization(
            index: 476,
            createdAt: now,
            historyState: .committed
        )
        terminalRaceFixture.journal.freezeNextLoads(2)
        let firstTerminalStore = terminalRaceFixture.store
        let secondTerminalStore = terminalRaceFixture.makeStore()
        let firstTerminal = Task {
            try await firstTerminalStore.retireProcessed(
                membership: terminalRaceMembership,
                terminalDelivery: terminal
            )
        }
        let secondTerminal = Task {
            try await secondTerminalStore.retireProcessed(
                membership: terminalRaceMembership,
                terminalDelivery: terminal
            )
        }
        let terminalResults = await [
            firstTerminal.result,
            secondTerminal.result,
        ]
        #expect(terminalResults.filter {
            if case .success = $0 { return true }
            return false
        }.count == 1)
        #expect(terminalRaceFixture.journal.currentEnvelope?.revision == 2)
        #expect(
            terminalRaceFixture.journal.currentEnvelope?.entries.isEmpty
                == true
        )
    }

    @Test func retirementUncertaintyIsExactPairAndStoreWide() async throws {
        let now = outboxStoreDate()
        for authorityIndex in 0..<4 {
            for commitWasVisible in [true, false] {
                let index = 476 + authorityIndex * 2
                    + (commitWasVisible ? 0 : 1)
                let fixture = OutboxStoreFixture(now: now)
                let capabilities = try await outboxCapabilities(
                    index: index,
                    createdAt: now
                )
                let membership = try await outboxMembershipReceipt(
                    fixture: fixture,
                    capabilities: capabilities
                )
                let decision = try await outboxRowReceipt(
                    membership: membership
                )
                let invalidation = try await outboxPolicyReceipt(
                    generation: 2,
                    enabled: false
                )
                let terminal = try outboxDeliveryAuthorization(
                    index: index,
                    createdAt: now,
                    historyState: .committed
                )
                let authority: OutboxRetirementAuthority = switch authorityIndex {
                case 0: .processed(decision)
                case 1: .terminal(terminal)
                case 2: .invalidated(invalidation)
                default: .expired
                }
                if authorityIndex == 3 {
                    fixture.clock.set(now.addingTimeInterval(86_400))
                }
                fixture.journal.failNextReplace(
                    with: .commitUncertain,
                    commitBeforeThrowing: commitWasVisible
                )

                await #expect(
                    throws: IOSAcceptedHistoryOutboxError.commitUncertain
                ) {
                    try await retireOutbox(
                        store: fixture.store,
                        membership: membership,
                        authority: authority
                    )
                }
                #expect(
                    fixture.journal.currentEnvelope?.entries.isEmpty
                        == commitWasVisible
                )
                await #expect(
                    throws: IOSAcceptedHistoryOutboxError.commitUncertain
                ) {
                    _ = try await fixture.store.observe()
                }
                await #expect(
                    throws: IOSAcceptedHistoryOutboxError.commitUncertain
                ) {
                    _ = try await fixture.store.load()
                }
                await #expect(
                    throws: IOSAcceptedHistoryOutboxError.commitUncertain
                ) {
                    _ = try await fixture.store.performStagingMaintenance()
                }
                await #expect(
                    throws: IOSAcceptedHistoryOutboxError.commitUncertain
                ) {
                    _ = try await fixture.store.confirmMembership(
                        delivery: capabilities.delivery
                    )
                }
                let other = try await outboxCapabilities(
                    index: 490 + index,
                    createdAt: now
                )
                await #expect(
                    throws: IOSAcceptedHistoryOutboxError.commitUncertain
                ) {
                    _ = try await fixture.store.transferForTesting(
                        delivery: other.delivery,
                        policy: other.policy
                    )
                }

                let mismatch: OutboxRetirementAuthority = authorityIndex == 0
                    ? .invalidated(invalidation)
                    : .processed(decision)
                await #expect(
                    throws: IOSAcceptedHistoryOutboxError.commitUncertain
                ) {
                    try await retireOutbox(
                        store: fixture.store,
                        membership: membership,
                        authority: mismatch
                    )
                }

                if authorityIndex == 3 {
                    fixture.clock.set(now.addingTimeInterval(10))
                    let readsBefore = fixture.clock.readCount
                    try await retireOutbox(
                        store: fixture.store,
                        membership: membership,
                        authority: authority
                    )
                    #expect(fixture.clock.readCount == readsBefore)
                    #expect(fixture.journal.currentEnvelope?.revision == 2)
                    #expect(
                        fixture.journal.currentEnvelope?.entries.isEmpty
                            == true
                    )
                    continue
                }

                try await retireOutbox(
                    store: fixture.store,
                    membership: membership,
                    authority: authority
                )
                #expect(fixture.journal.currentEnvelope?.revision == 2)
                #expect(
                    fixture.journal.currentEnvelope?.entries.isEmpty == true
                )
            }
        }
    }

    @Test func liveRepositoryUsesExactProtectionBackupAndMarker() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "accepted-history-outbox-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: base) }
        let now = outboxStoreDate()
        let capabilityOwnerIdentity =
            IOSAcceptedHistoryCapabilityOwnerIdentity()
        let store = IOSAcceptedHistoryOutboxStore(
            journal: FoundationIOSAcceptedHistoryOutboxJournalRepository(
                applicationSupportDirectoryURL: base
            ),
            now: { now },
            deliveryStoreIdentity: outboxDeliveryStoreIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
        let capabilities = try await outboxCapabilities(
            index: 450,
            createdAt: now,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
        _ = try await store.transferForTesting(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )

        let rootURL = base.appendingPathComponent("HoldType", isDirectory: true)
        let fileURL = IOSAcceptedHistoryOutboxStorageLocation.fileURL(in: base)
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
            IOSStrictProtectedRecordConfiguration.acceptedHistoryOutbox.marker
        )
        var bytes = [UInt8](repeating: 0, count: marker.value.count + 1)
        let byteCount = marker.name.withCString { name in
            bytes.withUnsafeMutableBytes {
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
        #expect(byteCount == marker.value.count)
        #expect(Array(bytes.prefix(marker.value.count)) == marker.value)
        let preserved = try Data(contentsOf: fileURL)
        #expect(
            marker.name.withCString {
                Darwin.fremovexattr(validDescriptor, $0, 0)
            } == 0
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.readFailed) {
            _ = try await store.load()
        }
        #expect(try Data(contentsOf: fileURL) == preserved)

        let wrongMarker = Array("v2".utf8)
        #expect(
            marker.name.withCString { name in
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
            } == 0
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.readFailed) {
            _ = try await store.load()
        }
        #expect(try Data(contentsOf: fileURL) == preserved)
    }
}

private enum OutboxMembershipOrigin: Equatable {
    case delivery
    case observation
}

private enum OutboxRetirementAuthority {
    case processed(IOSAcceptedHistoryRowReceipt)
    case terminal(IOSAcceptedOutputDeliveryAuthorization)
    case invalidated(IOSHistoryPolicyReceipt)
    case expired
}

private func outboxMembershipReceipt(
    fixture: OutboxStoreFixture,
    capabilities: OutboxCapabilities,
    origin: OutboxMembershipOrigin = .delivery
) async throws -> IOSAcceptedHistoryOutboxReceipt {
    let deliveryReceipt = try await fixture.store.transferForTesting(
        delivery: capabilities.delivery,
        policy: capabilities.policy
    )
    guard origin == .observation else { return deliveryReceipt }
    let observations = try #require(try await fixture.store.observe())
    let observation = try #require(observations.first(where: {
        $0.entry.deliveryID == capabilities.delivery.record.deliveryID
    }))
    return try await fixture.store.confirmMembership(observation: observation)
}

private func outboxRowReceipt(
    membership: IOSAcceptedHistoryOutboxReceipt,
    retained: Bool = true
) async throws -> IOSAcceptedHistoryRowReceipt {
    let entry = try #require(
        membership.confirmedEntryForAcceptedDecision()
    )
    let envelope: IOSAcceptedHistoryEnvelope?
    if retained {
        envelope = nil
    } else {
        let newer = try (0..<20).map { offset in
            try IOSAcceptedHistoryEntry(
                deliveryID: UUID(),
                transcriptID: UUID(),
                acceptedText: "newer \(offset)",
                outputIntent: .standard,
                createdAt: entry.createdAt.addingTimeInterval(
                    Double(20 - offset)
                ),
                policyGeneration: entry.policyGeneration,
                transcriptionModel: entry.transcriptionModel,
                transcriptionLanguageCode: entry.transcriptionLanguageCode,
                durationMilliseconds: entry.durationMilliseconds,
                cachedAudioRelativeIdentifier: nil
            )
        }
        envelope = try IOSAcceptedHistoryEnvelope(
            revision: 1,
            entries: IOSAcceptedHistoryValidation.sorted(newer)
        )
    }
    let policy = try await outboxPolicyReceipt(
        generation: entry.policyGeneration,
        enabled: true,
        capabilityOwnerIdentity: membership.capabilityOwnerIdentity
    )
    return try await IOSAcceptedHistoryStore(
        journal: OutboxAcceptedHistoryFakeJournal(
            envelope: envelope
        ),
        now: { entry.createdAt.addingTimeInterval(100) },
        capabilityOwnerIdentity: membership.capabilityOwnerIdentity
    ).decideUpsert(outbox: membership, policy: policy)
}

private func retireOutbox(
    store: IOSAcceptedHistoryOutboxStore,
    membership: IOSAcceptedHistoryOutboxReceipt,
    authority: OutboxRetirementAuthority
) async throws {
    switch authority {
    case .processed(let decision):
        try await store.retireProcessed(
            membership: membership,
            decision: decision
        )
    case .terminal(let delivery):
        try await store.retireProcessed(
            membership: membership,
            terminalDelivery: delivery
        )
    case .invalidated(let policy):
        try await store.retireInvalidated(
            membership: membership,
            policy: policy
        )
    case .expired:
        try await store.retireExpired(membership: membership)
    }
}

private struct OutboxCapabilities {
    let delivery: IOSAcceptedOutputDeliveryAuthorization
    let policy: IOSHistoryPolicyReceipt
}

private func outboxCapabilities(
    index: Int,
    generation: Int64 = 1,
    acceptedText: String = "Accepted text",
    createdAt: Date = outboxStoreDate(),
    capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
        outboxCapabilityOwnerIdentity
) async throws -> OutboxCapabilities {
    OutboxCapabilities(
        delivery: try outboxDeliveryAuthorization(
            index: index,
            generation: generation,
            acceptedText: acceptedText,
            createdAt: createdAt,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        ),
        policy: try await outboxPolicyReceipt(
            generation: generation,
            enabled: true,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
    )
}

private func outboxDeliveryAuthorization(
    index: Int,
    generation: Int64 = 1,
    acceptedText: String = "Accepted text",
    createdAt: Date = outboxStoreDate(),
    historyState: IOSAcceptedOutputHistoryWriteState = .pending,
    fileRevisionToken: UInt64? = nil,
    capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
        outboxCapabilityOwnerIdentity,
    storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity =
        outboxDeliveryStoreIdentity,
    deliveryID: UUID? = nil,
    transcriptID: UUID? = nil,
    outputIntent: DictationOutputIntent = .standard,
    transcriptionModel: String = "gpt-4o-mini-transcribe",
    transcriptionLanguageCode: String? = "en",
    durationMilliseconds: Int64? = 1_250
) throws -> IOSAcceptedOutputDeliveryAuthorization {
    let marker = try IOSAcceptedOutputHistoryWrite(
        state: historyState,
        policyGeneration: generation,
        transcriptionModel: transcriptionModel,
        transcriptionLanguageCode: transcriptionLanguageCode,
        durationMilliseconds: durationMilliseconds
    )
    let record = try IOSAcceptedOutputDeliveryRecord(
        revision: 1,
        deliveryID: deliveryID ?? outboxUUID(prefix: 0, index: index),
        sessionID: outboxUUID(prefix: 1, index: index),
        attemptID: outboxUUID(prefix: 2, index: index),
        transcriptID: transcriptID ?? outboxUUID(prefix: 3, index: index),
        acceptedText: acceptedText,
        outputIntent: outputIntent,
        createdAt: createdAt,
        updatedAt: createdAt,
        expiresAt: createdAt.addingTimeInterval(86_400),
        deliveryState: .pending,
        automaticInsertionPreferenceEnabled: true,
        keepLatestResult: false,
        publicationGeneration: 0,
        historyWrite: marker
    )
    return IOSAcceptedOutputDeliveryAuthorization(
        snapshot: IOSAcceptedOutputDeliveryJournalSnapshot(
            record: record,
            fileRevision: IOSStrictProtectedRecordFileRevision(
                testingToken: fileRevisionToken ?? UInt64(index + 1)
            )
        ),
        storeIdentity: storeIdentity,
        capabilityOwnerIdentity: capabilityOwnerIdentity
    )
}

private func outboxDiscardedAuthorization(
    matching entry: IOSAcceptedHistoryOutboxEntry,
    index: Int,
    capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
        outboxCapabilityOwnerIdentity,
    storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity =
        outboxDeliveryStoreIdentity
) throws -> IOSAcceptedOutputDeliveryAuthorization {
    let record = try IOSAcceptedOutputDeliveryRecord(
        revision: 2,
        deliveryID: entry.deliveryID,
        sessionID: outboxUUID(prefix: 1, index: index),
        attemptID: outboxUUID(prefix: 2, index: index),
        transcriptID: entry.transcriptID,
        acceptedText: nil,
        outputIntent: entry.outputIntent,
        createdAt: entry.createdAt,
        updatedAt: entry.createdAt,
        expiresAt: entry.expiresAt,
        deliveryState: .discarded,
        automaticInsertionPreferenceEnabled: false,
        keepLatestResult: false,
        publicationGeneration: 0,
        historyWrite: nil
    )
    return IOSAcceptedOutputDeliveryAuthorization(
        snapshot: IOSAcceptedOutputDeliveryJournalSnapshot(
            record: record,
            fileRevision: IOSStrictProtectedRecordFileRevision(
                testingToken: UInt64(index + 10_000)
            )
        ),
        storeIdentity: storeIdentity,
        capabilityOwnerIdentity: capabilityOwnerIdentity
    )
}

private func outboxPolicyReceipt(
    generation: Int64,
    enabled: Bool,
    capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
        outboxCapabilityOwnerIdentity
) async throws -> IOSHistoryPolicyReceipt {
    let state = try IOSHistoryPolicyState(
        revision: generation,
        historyEnabled: enabled,
        policyGeneration: generation
    )
    let journal = OutboxPolicyFakeJournal(state: state)
    return try await IOSHistoryPolicyStore(
        journal: journal,
        capabilityOwnerIdentity: capabilityOwnerIdentity
    ).confirm(
        expected: IOSHistoryPolicyExpectation(state: state)
    )
}

private func outboxEntry(
    from authorization: IOSAcceptedOutputDeliveryAuthorization
) throws -> IOSAcceptedHistoryOutboxEntry {
    let record = authorization.record
    let marker = try #require(record.historyWrite)
    return try IOSAcceptedHistoryOutboxEntry(
        deliveryID: record.deliveryID,
        transcriptID: record.transcriptID,
        acceptedText: try #require(record.acceptedText),
        outputIntent: record.outputIntent,
        createdAt: record.createdAt,
        expiresAt: record.expiresAt,
        policyGeneration: marker.policyGeneration,
        transcriptionModel: marker.transcriptionModel,
        transcriptionLanguageCode: marker.transcriptionLanguageCode,
        durationMilliseconds: marker.durationMilliseconds
    )
}

private func outboxStoredEntry(
    index: Int,
    generation: Int64 = 1,
    transcriptID: UUID? = nil,
    acceptedText: String = "Accepted text",
    createdAt: Date = outboxStoreDate()
) throws -> IOSAcceptedHistoryOutboxEntry {
    try IOSAcceptedHistoryOutboxEntry(
        deliveryID: outboxUUID(prefix: 0, index: index),
        transcriptID: transcriptID ?? outboxUUID(prefix: 3, index: index),
        acceptedText: acceptedText,
        outputIntent: .standard,
        createdAt: createdAt,
        expiresAt: createdAt.addingTimeInterval(86_400),
        policyGeneration: generation,
        transcriptionModel: "gpt-4o-mini-transcribe",
        transcriptionLanguageCode: "en",
        durationMilliseconds: 1_250
    )
}

private func outboxStoreDate() -> Date {
    Date(timeIntervalSince1970: 1_800_000_000)
}

private func outboxUUID(prefix: Int, index: Int) -> UUID {
    UUID(
        uuidString: String(
            format: "%08x-0000-4000-8000-%012x",
            prefix,
            index
        )
    )!
}

private final class OutboxClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    private var count = 0

    init(_ value: Date) { self.value = value }

    var readCount: Int { lock.withLock { count } }

    func set(_ value: Date) {
        lock.withLock { self.value = value }
    }

    func read() -> Date {
        lock.withLock { count += 1 }
        return value
    }
}

private final class OutboxPolicyFakeJournal:
    IOSHistoryPolicyJournalStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: IOSHistoryPolicyJournalSnapshot
    private var nextToken: UInt64 = 2

    init(state: IOSHistoryPolicyState) {
        snapshot = IOSHistoryPolicyJournalSnapshot(
            state: state,
            fileRevision: IOSStrictProtectedRecordFileRevision(testingToken: 1)
        )
    }

    func load() throws -> IOSHistoryPolicyJournalSnapshot? {
        lock.withLock { snapshot }
    }

    func replace(
        _ state: IOSHistoryPolicyState,
        expected: IOSHistoryPolicyJournalSnapshot
    ) throws -> IOSHistoryPolicyJournalSnapshot {
        try lock.withLock {
            guard snapshot == expected else {
                throw IOSHistoryPolicyError.compareAndSwapFailed
            }
            let replacement = IOSHistoryPolicyJournalSnapshot(
                state: state,
                fileRevision: IOSStrictProtectedRecordFileRevision(
                    testingToken: nextToken
                )
            )
            nextToken += 1
            snapshot = replacement
            return replacement
        }
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport { .empty }
}

private final class OutboxAcceptedHistoryFakeJournal:
    IOSAcceptedHistoryJournalStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: IOSAcceptedHistoryJournalSnapshot?
    private var nextToken: UInt64 = 1

    init(envelope: IOSAcceptedHistoryEnvelope?) {
        if let envelope {
            snapshot = IOSAcceptedHistoryJournalSnapshot(
                envelope: envelope,
                fileRevision: IOSStrictProtectedRecordFileRevision(
                    testingToken: nextToken
                )
            )
            nextToken += 1
        }
    }

    func load() throws -> IOSAcceptedHistoryJournalSnapshot? {
        lock.withLock { snapshot }
    }

    func create(
        _ envelope: IOSAcceptedHistoryEnvelope,
        authorization: IOSAcceptedHistoryJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryJournalSnapshot {
        try lock.withLock {
            guard snapshot == nil else {
                throw IOSAcceptedHistoryError.slotOccupied
            }
            let created = makeSnapshot(envelope)
            snapshot = created
            return created
        }
    }

    func replace(
        _ envelope: IOSAcceptedHistoryEnvelope,
        expected: IOSAcceptedHistoryJournalSnapshot,
        authorization: IOSAcceptedHistoryJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryJournalSnapshot {
        try lock.withLock {
            guard snapshot?.fileRevision == expected.fileRevision else {
                throw IOSAcceptedHistoryError.compareAndSwapFailed
            }
            let replacement = makeSnapshot(envelope)
            snapshot = replacement
            return replacement
        }
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport { .empty }

    private func makeSnapshot(
        _ envelope: IOSAcceptedHistoryEnvelope
    ) -> IOSAcceptedHistoryJournalSnapshot {
        defer { nextToken += 1 }
        return IOSAcceptedHistoryJournalSnapshot(
            envelope: envelope,
            fileRevision: IOSStrictProtectedRecordFileRevision(
                testingToken: nextToken
            )
        )
    }
}

private final class OutboxFakeJournal:
    IOSAcceptedHistoryOutboxJournalStoring,
    @unchecked Sendable {
    private struct Failure {
        let error: IOSAcceptedHistoryOutboxError
        let commitBeforeThrowing: Bool
    }

    private let lock = NSLock()
    private var snapshot: IOSAcceptedHistoryOutboxJournalSnapshot?
    private var nextToken: UInt64 = 1
    private var createFailure: Failure?
    private var replaceFailure: Failure?
    private var loadFailure: IOSAcceptedHistoryOutboxError?
    private var frozenLoadRemainingCount = 0
    private var frozenLoadSnapshot: IOSAcceptedHistoryOutboxJournalSnapshot?
    private var storedEvents: [String] = []

    var events: [String] { lock.withLock { storedEvents } }
    var currentEnvelope: IOSAcceptedHistoryOutboxEnvelope? {
        lock.withLock { snapshot?.envelope }
    }

    func resetEvents() { lock.withLock { storedEvents = [] } }

    func install(_ envelope: IOSAcceptedHistoryOutboxEnvelope) {
        lock.withLock {
            snapshot = IOSAcceptedHistoryOutboxJournalSnapshot(
                envelope: envelope,
                fileRevision: makeRevisionLocked()
            )
        }
    }

    func failNextCreate(
        with error: IOSAcceptedHistoryOutboxError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            createFailure = Failure(
                error: error,
                commitBeforeThrowing: commitBeforeThrowing
            )
        }
    }

    func failNextReplace(
        with error: IOSAcceptedHistoryOutboxError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            replaceFailure = Failure(
                error: error,
                commitBeforeThrowing: commitBeforeThrowing
            )
        }
    }

    func failNextLoad(with error: IOSAcceptedHistoryOutboxError) {
        lock.withLock { loadFailure = error }
    }

    func freezeNextLoads(_ count: Int) {
        precondition(count > 0)
        lock.withLock {
            precondition(frozenLoadRemainingCount == 0)
            frozenLoadRemainingCount = count
            frozenLoadSnapshot = snapshot
        }
    }

    func load() throws -> IOSAcceptedHistoryOutboxJournalSnapshot? {
        try lock.withLock {
            storedEvents.append("load")
            if let loadFailure {
                self.loadFailure = nil
                throw loadFailure
            }
            guard frozenLoadRemainingCount > 0 else { return snapshot }
            frozenLoadRemainingCount -= 1
            let result = frozenLoadSnapshot
            if frozenLoadRemainingCount == 0 {
                frozenLoadSnapshot = nil
            }
            return result
        }
    }

    func create(
        _ envelope: IOSAcceptedHistoryOutboxEnvelope,
        authorization: IOSAcceptedHistoryOutboxJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryOutboxJournalSnapshot {
        try lock.withLock {
            storedEvents.append("create:\(envelope.revision)")
            guard snapshot == nil else {
                throw IOSAcceptedHistoryOutboxError.slotOccupied
            }
            if let failure = createFailure {
                createFailure = nil
                if failure.commitBeforeThrowing {
                    snapshot = IOSAcceptedHistoryOutboxJournalSnapshot(
                        envelope: envelope,
                        fileRevision: makeRevisionLocked()
                    )
                }
                throw failure.error
            }
            let created = IOSAcceptedHistoryOutboxJournalSnapshot(
                envelope: envelope,
                fileRevision: makeRevisionLocked()
            )
            snapshot = created
            return created
        }
    }

    func replace(
        _ envelope: IOSAcceptedHistoryOutboxEnvelope,
        expected: IOSAcceptedHistoryOutboxJournalSnapshot,
        authorization: IOSAcceptedHistoryOutboxJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryOutboxJournalSnapshot {
        try lock.withLock {
            storedEvents.append("replace:\(envelope.revision)")
            guard snapshot?.fileRevision == expected.fileRevision else {
                throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
            }
            if let failure = replaceFailure {
                replaceFailure = nil
                if failure.commitBeforeThrowing {
                    snapshot = IOSAcceptedHistoryOutboxJournalSnapshot(
                        envelope: envelope,
                        fileRevision: makeRevisionLocked()
                    )
                }
                throw failure.error
            }
            let replacement = IOSAcceptedHistoryOutboxJournalSnapshot(
                envelope: envelope,
                fileRevision: makeRevisionLocked()
            )
            snapshot = replacement
            return replacement
        }
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport { .empty }

    private func makeRevisionLocked()
        -> IOSStrictProtectedRecordFileRevision {
        defer { nextToken += 1 }
        return IOSStrictProtectedRecordFileRevision(testingToken: nextToken)
    }
}

private final class OutboxStoreFixture: @unchecked Sendable {
    let journal = OutboxFakeJournal()
    let clock: OutboxClock
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let storeIdentity = IOSAcceptedHistoryOutboxStoreIdentity()
    let operationGate: IOSPersistenceOperationGate
    lazy var store = makeStore()

    init(
        now: Date,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
            outboxCapabilityOwnerIdentity,
        deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity =
            outboxDeliveryStoreIdentity,
        operationGate: IOSPersistenceOperationGate =
            IOSPersistenceOperationGate()
    ) {
        clock = OutboxClock(now)
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        self.deliveryStoreIdentity = deliveryStoreIdentity
        self.operationGate = operationGate
    }

    func makeStore() -> IOSAcceptedHistoryOutboxStore {
        IOSAcceptedHistoryOutboxStore(
            journal: journal,
            now: { [clock] in clock.read() },
            deliveryStoreIdentity: deliveryStoreIdentity,
            storeIdentity: storeIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity,
            operationGateIdentity: operationGate.identity
        )
    }
}
