import Darwin
import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSAcceptedHistoryStoreTests {
    @Test func missingReadDoesNotWriteAndFirstDecisionCreatesRevisionOne() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        #expect(try await fixture.store.load() == nil)
        #expect(fixture.journal.events == ["load"])
        fixture.journal.resetEvents()

        let capabilities = try await historyCapabilities(index: 1)
        let receipt = try await fixture.store.decideUpsert(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )

        #expect(receipt.decision == .retained)
        #expect(receipt.provesDecision(for: capabilities.delivery))
        #expect(receipt.provesMembership(for: capabilities.delivery))
        #expect(
            String(describing: receipt)
                == "IOSAcceptedHistoryRowReceipt(redacted)"
        )
        #expect(receipt.customMirror.children.isEmpty)
        #expect(fixture.journal.currentEnvelope?.revision == 1)
        #expect(fixture.journal.currentEnvelope?.entries.count == 1)
        #expect(fixture.journal.events == ["load", "create:1"])
    }

    @Test func sealedCapabilitiesMustDescribePendingEnabledGeneration() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let enabled = try await historyCapabilities(index: 1, generation: 2)
        let disabledPolicy = try await historyPolicyReceipt(
            generation: 2,
            enabled: false
        )
        await #expect(throws: IOSAcceptedHistoryError.stalePolicyGeneration) {
            try await fixture.store.decideUpsert(
                delivery: enabled.delivery,
                policy: disabledPolicy
            )
        }

        let wrongGeneration = try await historyPolicyReceipt(
            generation: 3,
            enabled: true
        )
        await #expect(throws: IOSAcceptedHistoryError.stalePolicyGeneration) {
            try await fixture.store.decideUpsert(
                delivery: enabled.delivery,
                policy: wrongGeneration
            )
        }

        let outboxFixture = AcceptedHistoryOutboxStoreFixture()
        let outbox = try await outboxFixture.store.transfer(
            delivery: enabled.delivery,
            policy: enabled.policy
        )
        await #expect(throws: IOSAcceptedHistoryError.stalePolicyGeneration) {
            try await fixture.store.decideUpsert(
                outbox: outbox,
                policy: disabledPolicy
            )
        }
        await #expect(throws: IOSAcceptedHistoryError.stalePolicyGeneration) {
            try await fixture.store.decideUpsert(
                outbox: outbox,
                policy: wrongGeneration
            )
        }

        let terminal = try acceptedHistoryDeliveryAuthorization(
            index: 2,
            generation: 2,
            historyState: .committed
        )
        await #expect(throws: IOSAcceptedHistoryError.stalePolicyGeneration) {
            try await fixture.store.decideUpsert(
                delivery: terminal,
                policy: enabled.policy
            )
        }
        #expect(fixture.journal.currentEnvelope == nil)
    }

    @Test func deliveryOriginRequiresExactCapabilityAndAllowsOutboxCrossProof() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let capabilities = try await historyCapabilities(index: 2)
        let outboxFixture = AcceptedHistoryOutboxStoreFixture()
        let outbox = try await outboxFixture.store.transfer(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )
        let receipt = try await fixture.store.decideUpsert(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )
        let reauthorized = acceptedHistoryReauthorizedDelivery(
            capabilities.delivery,
            fileRevisionToken: 9_002
        )

        #expect(receipt.provesDecision(for: capabilities.delivery))
        #expect(receipt.provesMembership(for: capabilities.delivery))
        #expect(!receipt.provesDecision(for: reauthorized))
        #expect(!receipt.provesMembership(for: reauthorized))
        #expect(receipt.provesDecision(for: outbox))
        #expect(receipt.provesMembership(for: outbox))
    }

    @Test func outboxOriginRequiresExactReceiptAndAllowsDeliveryCrossProof() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let capabilities = try await historyCapabilities(index: 3)
        let outboxFixture = AcceptedHistoryOutboxStoreFixture()
        let original = try await outboxFixture.store.transfer(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )
        let receipt = try await fixture.store.decideUpsert(
            outbox: original,
            policy: capabilities.policy
        )
        let refreshed = try await outboxFixture.store.confirmMembership(
            delivery: capabilities.delivery
        )

        #expect(receipt.provesDecision(for: original))
        #expect(receipt.provesMembership(for: original))
        #expect(!receipt.provesDecision(for: refreshed))
        #expect(!receipt.provesMembership(for: refreshed))
        #expect(receipt.provesDecision(for: capabilities.delivery))
        #expect(receipt.provesMembership(for: capabilities.delivery))
    }

    @Test func observationOriginOutboxReceiptDrivesRelaunchWithoutDelivery() async throws {
        let capabilities = try await historyCapabilities(index: 4)
        let outboxFixture = AcceptedHistoryOutboxStoreFixture()
        _ = try await outboxFixture.store.transfer(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )
        let observation = try #require(
            try await outboxFixture.store.observe()?.first
        )
        let recoveredOutbox = try await outboxFixture.store.confirmMembership(
            observation: observation
        )
        let fixture = AcceptedHistoryStoreFixture()

        _ = try await fixture.store.decideUpsert(
            outbox: recoveredOutbox,
            policy: capabilities.policy
        )
        fixture.setNow(capabilities.delivery.record.expiresAt)
        let receipt = try await fixture.makeStore().confirmMembership(
            outbox: recoveredOutbox,
            policy: capabilities.policy
        )

        #expect(receipt.decision == .retained)
        #expect(receipt.provesDecision(for: recoveredOutbox))
        #expect(receipt.provesMembership(for: recoveredOutbox))
        #expect(fixture.journal.currentEnvelope?.entries.count == 1)
    }

    @Test func crossOwnerReceiptMatchingPreservesExactUnicodeBytes() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let decomposed = try await historyCapabilities(
            index: 5,
            acceptedText: "e\u{301}"
        )
        let receipt = try await fixture.store.decideUpsert(
            delivery: decomposed.delivery,
            policy: decomposed.policy
        )
        let composed = try await historyCapabilities(
            index: 5,
            acceptedText: "é"
        )
        let outboxFixture = AcceptedHistoryOutboxStoreFixture()
        let composedOutbox = try await outboxFixture.store.transfer(
            delivery: composed.delivery,
            policy: composed.policy
        )

        #expect(!receipt.provesDecision(for: composedOutbox))
        #expect(!receipt.provesMembership(for: composedOutbox))
    }

    @Test func duplicatePreservesCacheStaleRowsAndLogicalRevision() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let capabilities = try await historyCapabilities(
            index: 10,
            generation: 2
        )
        let duplicate = try historyEntry(
            from: capabilities.delivery,
            cacheIdentifier: "cache/audio.m4a"
        )
        let stale = try acceptedHistoryStoredEntry(
            index: 11,
            generation: 1,
            createdAt: duplicate.createdAt.addingTimeInterval(-1)
        )
        fixture.journal.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 7,
                entries: [duplicate, stale]
            )
        )

        let receipt = try await fixture.store.decideUpsert(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )

        #expect(receipt.decision == .retained)
        #expect(fixture.journal.currentEnvelope?.revision == 7)
        #expect(fixture.journal.currentEnvelope?.entries == [duplicate, stale])
        #expect(
            fixture.journal.currentEnvelope?.entries[0]
                .cachedAudioRelativeIdentifier == "cache/audio.m4a"
        )
        #expect(fixture.journal.events.suffix(2) == ["load", "replace:7"])
    }

    @Test func collisionScanPrecedesGenerationPruningAndUsesUTF8Bytes() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let capabilities = try await historyCapabilities(
            index: 20,
            generation: 2,
            acceptedText: "e\u{301}"
        )
        let colliding = try acceptedHistoryStoredEntry(
            index: 20,
            generation: 1,
            acceptedText: "é"
        )
        fixture.journal.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 4,
                entries: [colliding]
            )
        )

        await #expect(throws: IOSAcceptedHistoryError.collision) {
            try await fixture.store.decideUpsert(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }
        #expect(fixture.journal.currentEnvelope?.revision == 4)

        let transcriptFixture = AcceptedHistoryStoreFixture()
        let candidate = try await historyCapabilities(index: 21)
        let transcriptCollision = try acceptedHistoryStoredEntry(
            index: 22,
            transcriptID: candidate.delivery.record.transcriptID
        )
        transcriptFixture.journal.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 1,
                entries: [transcriptCollision]
            )
        )
        await #expect(throws: IOSAcceptedHistoryError.collision) {
            try await transcriptFixture.store.decideUpsert(
                delivery: candidate.delivery,
                policy: candidate.policy
            )
        }
    }

    @Test func newGenerationPrunesOlderRowsButRejectsHigherGeneration() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let capabilities = try await historyCapabilities(
            index: 30,
            generation: 2
        )
        let stale = try acceptedHistoryStoredEntry(
            index: 31,
            generation: 1,
            createdAt: capabilities.delivery.record.createdAt
                .addingTimeInterval(-1)
        )
        fixture.journal.install(
            try IOSAcceptedHistoryEnvelope(revision: 3, entries: [stale])
        )

        _ = try await fixture.store.decideUpsert(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )
        #expect(fixture.journal.currentEnvelope?.revision == 4)
        #expect(
            fixture.journal.currentEnvelope?.entries.map(\.policyGeneration)
                == [2]
        )

        let staleCaptureFixture = AcceptedHistoryStoreFixture()
        let higher = try acceptedHistoryStoredEntry(
            index: 32,
            generation: 3
        )
        staleCaptureFixture.journal.install(
            try IOSAcceptedHistoryEnvelope(revision: 1, entries: [higher])
        )
        await #expect(throws: IOSAcceptedHistoryError.stalePolicyGeneration) {
            try await staleCaptureFixture.store.decideUpsert(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }
    }

    @Test func futureGenerationBlocksDuplicateDecisionAndConfirmation() async throws {
        let capabilities = try await historyCapabilities(
            index: 33,
            generation: 2
        )
        let duplicate = try historyEntry(from: capabilities.delivery)
        let future = try acceptedHistoryStoredEntry(
            index: 34,
            generation: 3,
            createdAt: duplicate.createdAt.addingTimeInterval(1)
        )
        let fixture = AcceptedHistoryStoreFixture()
        fixture.journal.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 4,
                entries: IOSAcceptedHistoryValidation.sorted([
                    duplicate,
                    future,
                ])
            )
        )
        let outboxFixture = AcceptedHistoryOutboxStoreFixture()
        let outbox = try await outboxFixture.store.transfer(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )

        await #expect(throws: IOSAcceptedHistoryError.stalePolicyGeneration) {
            try await fixture.store.decideUpsert(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }
        await #expect(throws: IOSAcceptedHistoryError.stalePolicyGeneration) {
            try await fixture.store.decideUpsert(
                outbox: outbox,
                policy: capabilities.policy
            )
        }
        await #expect(throws: IOSAcceptedHistoryError.stalePolicyGeneration) {
            try await fixture.store.confirmMembership(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }
        await #expect(throws: IOSAcceptedHistoryError.stalePolicyGeneration) {
            try await fixture.store.confirmMembership(
                outbox: outbox,
                policy: capabilities.policy
            )
        }
        #expect(fixture.journal.currentEnvelope?.revision == 4)
    }

    @Test func collisionPrecedesFutureGenerationGuardForEveryOrigin() async throws {
        let capabilities = try await historyCapabilities(
            index: 35,
            generation: 2,
            acceptedText: "candidate"
        )
        let colliding = try acceptedHistoryStoredEntry(
            index: 35,
            generation: 3,
            acceptedText: "collision"
        )
        let fixture = AcceptedHistoryStoreFixture()
        fixture.journal.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 5,
                entries: [colliding]
            )
        )
        let outboxFixture = AcceptedHistoryOutboxStoreFixture()
        let outbox = try await outboxFixture.store.transfer(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )

        await #expect(throws: IOSAcceptedHistoryError.collision) {
            try await fixture.store.decideUpsert(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }
        await #expect(throws: IOSAcceptedHistoryError.collision) {
            try await fixture.store.decideUpsert(
                outbox: outbox,
                policy: capabilities.policy
            )
        }
        await #expect(throws: IOSAcceptedHistoryError.collision) {
            try await fixture.store.confirmMembership(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }
        await #expect(throws: IOSAcceptedHistoryError.collision) {
            try await fixture.store.confirmMembership(
                outbox: outbox,
                policy: capabilities.policy
            )
        }
        #expect(fixture.journal.currentEnvelope?.revision == 5)
    }

    @Test func retentionSortsDeterministicallyAndSelfEvictionIsConfirmation() async throws {
        let baseDate = acceptedHistoryStoreDate()
        let existing = try (0..<20).map { offset in
            try acceptedHistoryStoredEntry(
                index: 100 + offset,
                createdAt: baseDate.addingTimeInterval(Double(-offset))
            )
        }
        let fixture = AcceptedHistoryStoreFixture()
        fixture.journal.install(
            try IOSAcceptedHistoryEnvelope(revision: 9, entries: existing)
        )
        let oldCandidate = try await historyCapabilities(
            index: 200,
            createdAt: baseDate.addingTimeInterval(-100)
        )

        let oldDecision = try await fixture.store.decideUpsert(
            delivery: oldCandidate.delivery,
            policy: oldCandidate.policy
        )
        #expect(oldDecision.decision == .notRetained)
        #expect(oldDecision.provesDecision(for: oldCandidate.delivery))
        #expect(!oldDecision.provesMembership(for: oldCandidate.delivery))
        let oldOutboxFixture = AcceptedHistoryOutboxStoreFixture()
        let oldOutbox = try await oldOutboxFixture.store.transfer(
            delivery: oldCandidate.delivery,
            policy: oldCandidate.policy
        )
        #expect(oldDecision.provesDecision(for: oldOutbox))
        #expect(!oldDecision.provesMembership(for: oldOutbox))
        #expect(fixture.journal.currentEnvelope?.revision == 9)
        #expect(fixture.journal.currentEnvelope?.entries == existing)

        let newCandidate = try await historyCapabilities(
            index: 201,
            createdAt: baseDate.addingTimeInterval(1)
        )
        let newDecision = try await fixture.store.decideUpsert(
            delivery: newCandidate.delivery,
            policy: newCandidate.policy
        )
        #expect(newDecision.decision == .retained)
        #expect(newDecision.provesDecision(for: newCandidate.delivery))
        #expect(newDecision.provesMembership(for: newCandidate.delivery))
        #expect(fixture.journal.currentEnvelope?.revision == 10)
        #expect(fixture.journal.currentEnvelope?.entries.count == 20)
        #expect(
            fixture.journal.currentEnvelope?.entries.first?.deliveryID
                == newCandidate.delivery.record.deliveryID
        )
    }

    @Test func equalTimestampUsesCanonicalDeliveryIdentifierOrder() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let date = acceptedHistoryStoreDate()
        let higher = try acceptedHistoryStoredEntry(
            index: 601,
            createdAt: date
        )
        fixture.journal.install(
            try IOSAcceptedHistoryEnvelope(revision: 1, entries: [higher])
        )
        let lower = try await historyCapabilities(
            index: 600,
            createdAt: date
        )

        _ = try await fixture.store.decideUpsert(
            delivery: lower.delivery,
            policy: lower.policy
        )
        #expect(
            fixture.journal.currentEnvelope?.entries.map(\.deliveryID) == [
                lower.delivery.record.deliveryID,
                higher.deliveryID,
            ]
        )
    }

    @Test func equalTimestampCapacityEvictsLexicallyHighestIdentifier() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let date = acceptedHistoryStoreDate()
        let existing = try (1_000..<1_020).map { index in
            try acceptedHistoryStoredEntry(index: index, createdAt: date)
        }
        fixture.journal.install(
            try IOSAcceptedHistoryEnvelope(revision: 1, entries: existing)
        )
        let candidate = try await historyCapabilities(
            index: 999,
            createdAt: date
        )

        _ = try await fixture.store.decideUpsert(
            delivery: candidate.delivery,
            policy: candidate.policy
        )
        let identifiers = try #require(
            fixture.journal.currentEnvelope?.entries.map(\.deliveryID)
        )
        #expect(identifiers.count == 20)
        #expect(identifiers.first == candidate.delivery.record.deliveryID)
        #expect(
            !identifiers.contains(acceptedHistoryUUID(prefix: 0, index: 1_019))
        )
    }

    @Test func encodedByteRetentionUsesCanonicalJSONSize() async throws {
        let hugeText = "a" + String(repeating: "\t", count: 131_070) + "b"
        let baseDate = acceptedHistoryStoreDate()
        var entries: [IOSAcceptedHistoryEntry] = []
        for offset in 0..<15 {
            entries.append(
                try acceptedHistoryStoredEntry(
                    index: 300 + offset,
                    acceptedText: hugeText,
                    createdAt: baseDate.addingTimeInterval(Double(-offset))
                )
            )
        }
        let source = try IOSAcceptedHistoryEnvelope(
            revision: 1,
            entries: entries
        )
        _ = try IOSAcceptedHistoryWireCodec.encode(source)
        let fixture = AcceptedHistoryStoreFixture()
        fixture.journal.install(source)
        let candidate = try await historyCapabilities(
            index: 399,
            acceptedText: hugeText,
            createdAt: baseDate.addingTimeInterval(1)
        )

        _ = try await fixture.store.decideUpsert(
            delivery: candidate.delivery,
            policy: candidate.policy
        )
        let current = try #require(fixture.journal.currentEnvelope)
        #expect(
            try IOSAcceptedHistoryWireCodec.encode(current).count
                <= IOSAcceptedHistoryJournal.maximumByteCount
        )
        #expect(current.entries.count < 16)
        #expect(current.entries.first?.deliveryID == candidate.delivery.record.deliveryID)
    }

    @Test func selfEvictionAtRevisionDigitBoundaryKeepsExactSource() async throws {
        let source = try exactLimitAcceptedHistoryEnvelope(revision: 9)
        #expect(
            try IOSAcceptedHistoryWireCodec.encode(source).count
                == IOSAcceptedHistoryJournal.maximumByteCount
        )
        let fixture = AcceptedHistoryStoreFixture()
        fixture.journal.install(source)
        let candidate = try await historyCapabilities(
            index: 799,
            createdAt: acceptedHistoryStoreDate().addingTimeInterval(-1_000)
        )

        let receipt = try await fixture.store.decideUpsert(
            delivery: candidate.delivery,
            policy: candidate.policy
        )
        #expect(receipt.decision == .notRetained)
        #expect(fixture.journal.currentEnvelope == source)
        #expect(fixture.journal.events.suffix(2) == ["load", "replace:9"])
    }

    @Test func overflowAllowsDuplicateConfirmationButBlocksMutation() async throws {
        let capabilities = try await historyCapabilities(index: 400)
        let entry = try historyEntry(from: capabilities.delivery)
        let duplicateFixture = AcceptedHistoryStoreFixture()
        duplicateFixture.journal.install(
            try IOSAcceptedHistoryEnvelope(
                revision: Int64.max,
                entries: [entry]
            )
        )
        let duplicate = try await duplicateFixture.store.decideUpsert(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )
        #expect(duplicate.decision == .retained)
        #expect(duplicateFixture.journal.currentEnvelope?.revision == Int64.max)

        let mutationFixture = AcceptedHistoryStoreFixture()
        mutationFixture.journal.install(
            try IOSAcceptedHistoryEnvelope(
                revision: Int64.max,
                entries: [entry]
            )
        )
        let other = try await historyCapabilities(
            index: 401,
            createdAt: entry.createdAt.addingTimeInterval(1)
        )
        await #expect(throws: IOSAcceptedHistoryError.revisionOverflow) {
            try await mutationFixture.store.decideUpsert(
                delivery: other.delivery,
                policy: other.policy
            )
        }
        #expect(mutationFixture.journal.currentEnvelope?.entries == [entry])
    }

    @Test func uncertaintyBlocksOtherCandidatesAndRetriesExactIntent() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let first = try await historyCapabilities(index: 500)
        fixture.journal.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
            try await fixture.store.decideUpsert(
                delivery: first.delivery,
                policy: first.policy
            )
        }

        let other = try await historyCapabilities(index: 501)
        await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
            try await fixture.store.decideUpsert(
                delivery: other.delivery,
                policy: other.policy
            )
        }
        await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
            try await fixture.store.pruneInvalidatedRows(
                using: try await historyPolicyReceipt(
                    generation: 2,
                    enabled: false
                )
            )
        }
        let confirmed = try await fixture.store.decideUpsert(
            delivery: first.delivery,
            policy: first.policy
        )
        #expect(confirmed.decision == .retained)
        #expect(fixture.journal.currentEnvelope?.revision == 1)
    }

    @Test func visibleUncertaintyRequiresIdenticalRewriteBeforeReceipt() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let capabilities = try await historyCapabilities(index: 510)
        fixture.journal.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )
        await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
            try await fixture.store.decideUpsert(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }
        #expect(fixture.journal.currentEnvelope?.revision == 1)

        fixture.setNow(capabilities.delivery.record.expiresAt)
        let confirmed = try await fixture.store.confirmMembership(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )
        #expect(confirmed.decision == .retained)
        #expect(fixture.journal.events.suffix(2) == ["load", "replace:1"])
    }

    @Test func invisibleUncertaintyExpiryClearsGateWithoutInserting() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let capabilities = try await historyCapabilities(index: 511)
        fixture.journal.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
            try await fixture.store.decideUpsert(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }

        fixture.setNow(capabilities.delivery.record.expiresAt)
        await #expect(throws: IOSAcceptedHistoryError.expired) {
            try await fixture.store.decideUpsert(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }
        #expect(fixture.journal.currentEnvelope == nil)

        let other = try await historyCapabilities(index: 512)
        fixture.setNow(other.delivery.record.createdAt.addingTimeInterval(1))
        _ = try await fixture.store.decideUpsert(
            delivery: other.delivery,
            policy: other.policy
        )
        #expect(
            fixture.journal.currentEnvelope?.entries.first?.deliveryID
                == other.delivery.record.deliveryID
        )
    }

    @Test func invisibleUncertaintyRollbackKeepsGateAndNeverInserts() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let capabilities = try await historyCapabilities(index: 513)
        fixture.journal.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
            try await fixture.store.decideUpsert(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }

        fixture.setNow(
            capabilities.delivery.record.createdAt.addingTimeInterval(-1)
        )
        await #expect(
            throws: IOSAcceptedHistoryError.clockRollbackAmbiguous
        ) {
            try await fixture.store.decideUpsert(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }
        #expect(fixture.journal.currentEnvelope == nil)

        let other = try await historyCapabilities(index: 514)
        await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
            try await fixture.store.decideUpsert(
                delivery: other.delivery,
                policy: other.policy
            )
        }
        #expect(fixture.journal.currentEnvelope == nil)
    }

    @Test func invisibleSelfEvictionUncertaintyRevalidatesTime() async throws {
        for boundary in 0..<2 {
            let baseDate = acceptedHistoryStoreDate()
            let indexBase = 600 + (boundary * 100)
            let existing = try (0..<20).map { offset in
                try acceptedHistoryStoredEntry(
                    index: indexBase + offset,
                    createdAt: baseDate.addingTimeInterval(Double(-offset))
                )
            }
            let source = try IOSAcceptedHistoryEnvelope(
                revision: 9,
                entries: existing
            )
            let fixture = AcceptedHistoryStoreFixture()
            fixture.journal.install(source)
            let candidate = try await historyCapabilities(
                index: indexBase + 90,
                createdAt: baseDate.addingTimeInterval(-100)
            )
            fixture.journal.failNextReplace(
                with: .commitUncertain,
                commitBeforeThrowing: false
            )

            await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
                try await fixture.store.decideUpsert(
                    delivery: candidate.delivery,
                    policy: candidate.policy
                )
            }

            if boundary == 0 {
                fixture.setNow(candidate.delivery.record.expiresAt)
                await #expect(throws: IOSAcceptedHistoryError.expired) {
                    try await fixture.store.decideUpsert(
                        delivery: candidate.delivery,
                        policy: candidate.policy
                    )
                }
            } else {
                fixture.setNow(
                    candidate.delivery.record.createdAt
                        .addingTimeInterval(-1)
                )
                await #expect(
                    throws: IOSAcceptedHistoryError.clockRollbackAmbiguous
                ) {
                    try await fixture.store.decideUpsert(
                        delivery: candidate.delivery,
                        policy: candidate.policy
                    )
                }
            }
            #expect(fixture.journal.currentEnvelope == source)
        }
    }

    @Test func visibleSelfEvictionUncertaintyProvesDecisionAtTimeBoundary() async throws {
        for boundary in 0..<2 {
            let baseDate = acceptedHistoryStoreDate()
            let indexBase = 800 + (boundary * 100)
            let existing = try (0..<20).map { offset in
                try acceptedHistoryStoredEntry(
                    index: indexBase + offset,
                    createdAt: baseDate.addingTimeInterval(Double(-offset))
                )
            }
            let source = try IOSAcceptedHistoryEnvelope(
                revision: 9,
                entries: existing
            )
            let fixture = AcceptedHistoryStoreFixture()
            fixture.journal.install(source)
            let candidate = try await historyCapabilities(
                index: indexBase + 90,
                createdAt: baseDate.addingTimeInterval(-100)
            )
            fixture.journal.failNextReplace(
                with: .commitUncertain,
                commitBeforeThrowing: true
            )

            await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
                try await fixture.store.decideUpsert(
                    delivery: candidate.delivery,
                    policy: candidate.policy
                )
            }

            if boundary == 0 {
                fixture.setNow(candidate.delivery.record.expiresAt)
            } else {
                fixture.setNow(
                    candidate.delivery.record.createdAt
                        .addingTimeInterval(-1)
                )
            }
            let receipt = try await fixture.store.decideUpsert(
                delivery: candidate.delivery,
                policy: candidate.policy
            )
            #expect(receipt.decision == .notRetained)
            #expect(receipt.provesDecision(for: candidate.delivery))
            #expect(!receipt.provesMembership(for: candidate.delivery))
            #expect(fixture.journal.currentEnvelope == source)
        }
    }

    @Test func canonicalSubmillisecondExpiryNeverCreatesAnAbsentRow() async throws {
        let capabilities = try await historyCapabilities(index: 515)
        let fixture = AcceptedHistoryStoreFixture(
            now: capabilities.delivery.record.expiresAt
                .addingTimeInterval(-0.0004)
        )

        await #expect(throws: IOSAcceptedHistoryError.expired) {
            try await fixture.store.decideUpsert(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }
        #expect(fixture.journal.currentEnvelope == nil)
    }

    @Test func supersededUncertaintyReleasesGateForWinnerRecovery() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let baseline = try IOSAcceptedHistoryEnvelope(revision: 1, entries: [])
        fixture.journal.install(baseline)
        let first = try await historyCapabilities(index: 520)
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
            try await fixture.store.decideUpsert(
                delivery: first.delivery,
                policy: first.policy
            )
        }

        let winner = try await historyCapabilities(index: 521)
        _ = try await fixture.makeStore().decideUpsert(
            delivery: winner.delivery,
            policy: winner.policy
        )
        await #expect(throws: IOSAcceptedHistoryError.compareAndSwapFailed) {
            try await fixture.store.decideUpsert(
                delivery: first.delivery,
                policy: first.policy
            )
        }

        let recovered = try await fixture.store.confirmMembership(
            delivery: winner.delivery,
            policy: winner.policy
        )
        #expect(recovered.decision == .retained)
    }

    @Test func membershipConfirmationNeverInsertsAnAbsentCandidate() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        fixture.journal.install(
            try IOSAcceptedHistoryEnvelope(revision: 1, entries: [])
        )
        let capabilities = try await historyCapabilities(index: 530)

        await #expect(throws: IOSAcceptedHistoryError.compareAndSwapFailed) {
            try await fixture.store.confirmMembership(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }
        #expect(fixture.journal.currentEnvelope?.entries.isEmpty == true)
    }

    @Test func outboxMembershipConfirmationNeverInsertsAnAbsentCandidate() async throws {
        let capabilities = try await historyCapabilities(index: 531)
        let outboxFixture = AcceptedHistoryOutboxStoreFixture()
        let outbox = try await outboxFixture.store.transfer(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )
        let fixture = AcceptedHistoryStoreFixture()
        fixture.journal.install(
            try IOSAcceptedHistoryEnvelope(revision: 1, entries: [])
        )

        await #expect(throws: IOSAcceptedHistoryError.compareAndSwapFailed) {
            try await fixture.store.confirmMembership(
                outbox: outbox,
                policy: capabilities.policy
            )
        }
        #expect(fixture.journal.currentEnvelope?.entries.isEmpty == true)
    }

    @Test func confirmationDoesNotReplayAnInvisibleUncertainUpsert() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let capabilities = try await historyCapabilities(index: 532)
        fixture.journal.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
            try await fixture.store.decideUpsert(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }

        await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
            try await fixture.store.confirmMembership(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }
        #expect(fixture.journal.currentEnvelope == nil)
    }

    @Test func relaunchedStoreConfirmsExactMembershipByIdenticalRewrite() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let capabilities = try await historyCapabilities(index: 535)
        _ = try await fixture.store.decideUpsert(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )
        fixture.journal.resetEvents()
        fixture.setNow(capabilities.delivery.record.expiresAt)

        let confirmed = try await fixture.makeStore().confirmMembership(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )
        #expect(confirmed.decision == .retained)
        #expect(fixture.journal.events == ["load", "replace:1"])
    }

    @Test func membershipConfirmationRecoversUncertainCacheLinkedRewrite() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        let capabilities = try await historyCapabilities(index: 534)
        let cached = try historyEntry(
            from: capabilities.delivery,
            cacheIdentifier: "cache/audio.m4a"
        )
        fixture.journal.install(
            try IOSAcceptedHistoryEnvelope(revision: 4, entries: [cached])
        )
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )

        await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
            try await fixture.store.confirmMembership(
                delivery: capabilities.delivery,
                policy: capabilities.policy
            )
        }
        let confirmed = try await fixture.store.confirmMembership(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )
        #expect(confirmed.decision == .retained)
        #expect(fixture.journal.currentEnvelope?.revision == 4)
        #expect(
            fixture.journal.currentEnvelope?.entries[0]
                .cachedAudioRelativeIdentifier == "cache/audio.m4a"
        )
    }

    @Test func twoStoresConvergeSameCandidateAndPreserveDistinctCandidates() async throws {
        let sameFixture = AcceptedHistoryStoreFixture()
        let same = try await historyCapabilities(index: 536)
        let sameFirst = Task {
            try await sameFixture.store.decideUpsert(
                delivery: same.delivery,
                policy: same.policy
            )
        }
        let sameSecond = Task {
            try await sameFixture.makeStore().decideUpsert(
                delivery: same.delivery,
                policy: same.policy
            )
        }
        let sameResults = await [sameFirst.result, sameSecond.result]
        #expect(sameResults.allSatisfy {
            if case .success = $0 { return true }
            return false
        })
        #expect(sameFixture.journal.currentEnvelope?.revision == 1)
        #expect(sameFixture.journal.currentEnvelope?.entries.count == 1)

        let distinctFixture = AcceptedHistoryStoreFixture()
        let first = try await historyCapabilities(index: 537)
        let second = try await historyCapabilities(
            index: 538,
            createdAt: acceptedHistoryStoreDate().addingTimeInterval(1)
        )
        let firstTask = Task {
            try await distinctFixture.store.decideUpsert(
                delivery: first.delivery,
                policy: first.policy
            )
        }
        let secondTask = Task {
            try await distinctFixture.makeStore().decideUpsert(
                delivery: second.delivery,
                policy: second.policy
            )
        }
        let results = await [firstTask.result, secondTask.result]
        #expect(results.allSatisfy {
            if case .success = $0 { return true }
            return false
        })
        #expect(distinctFixture.journal.currentEnvelope?.revision == 2)
        #expect(distinctFixture.journal.currentEnvelope?.entries.count == 2)
    }

    @Test func competingReplacementsHaveOneWinnerAndRetryWithoutLostUpdate() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        fixture.journal.install(
            try IOSAcceptedHistoryEnvelope(revision: 1, entries: [])
        )
        fixture.journal.delayNextLoads(2)
        let first = try await historyCapabilities(index: 539)
        let second = try await historyCapabilities(
            index: 540,
            createdAt: acceptedHistoryStoreDate().addingTimeInterval(1)
        )
        let firstTask = Task {
            try await fixture.store.decideUpsert(
                delivery: first.delivery,
                policy: first.policy
            )
        }
        let secondTask = Task {
            try await fixture.makeStore().decideUpsert(
                delivery: second.delivery,
                policy: second.policy
            )
        }
        let firstResult = await firstTask.result
        let secondResult = await secondTask.result
        let successCount = [firstResult, secondResult].filter {
            if case .success = $0 { return true }
            return false
        }.count
        #expect(successCount == 1)
        #expect(fixture.journal.currentEnvelope?.revision == 2)

        let loser = if case .failure = firstResult { first } else { second }
        _ = try await fixture.store.decideUpsert(
            delivery: loser.delivery,
            policy: loser.policy
        )
        #expect(fixture.journal.currentEnvelope?.revision == 3)
        #expect(fixture.journal.currentEnvelope?.entries.count == 2)
    }

    @Test func pruneMissingIsNoOpAndCurrentGenerationRewritesIdentically() async throws {
        let policy = try await historyPolicyReceipt(
            generation: 2,
            enabled: false
        )
        let missingFixture = AcceptedHistoryStoreFixture()
        try await missingFixture.store.pruneInvalidatedRows(using: policy)
        #expect(missingFixture.journal.currentEnvelope == nil)
        #expect(missingFixture.journal.events == ["load"])

        let current = try acceptedHistoryStoredEntry(
            index: 541,
            generation: 2,
            cacheIdentifier: "cache/current.m4a"
        )
        let noOpFixture = AcceptedHistoryStoreFixture()
        let source = try IOSAcceptedHistoryEnvelope(
            revision: 7,
            entries: [current]
        )
        noOpFixture.journal.install(source)
        noOpFixture.journal.resetEvents()

        try await noOpFixture.store.pruneInvalidatedRows(using: policy)
        #expect(noOpFixture.journal.currentEnvelope == source)
        #expect(noOpFixture.journal.events == ["load", "replace:7"])
    }

    @Test func pruneRemovesOnlyOlderRowsAndRetainsEmptyEnvelope() async throws {
        let policy = try await historyPolicyReceipt(
            generation: 2,
            enabled: false
        )
        let base = acceptedHistoryStoreDate()
        let staleFirst = try acceptedHistoryStoredEntry(
            index: 542,
            generation: 1,
            createdAt: base.addingTimeInterval(-40)
        )
        let currentFirst = try acceptedHistoryStoredEntry(
            index: 543,
            generation: 2,
            createdAt: base.addingTimeInterval(-30),
            cacheIdentifier: "cache/first.m4a"
        )
        let staleSecond = try acceptedHistoryStoredEntry(
            index: 544,
            generation: 1,
            createdAt: base.addingTimeInterval(-20)
        )
        let currentSecond = try acceptedHistoryStoredEntry(
            index: 545,
            generation: 2,
            createdAt: base.addingTimeInterval(-10),
            cacheIdentifier: "cache/second.m4a"
        )
        let fixture = AcceptedHistoryStoreFixture()
        fixture.journal.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 5,
                entries: [
                    currentSecond, staleSecond, currentFirst, staleFirst,
                ]
            )
        )

        try await fixture.store.pruneInvalidatedRows(using: policy)
        #expect(fixture.journal.currentEnvelope?.revision == 6)
        #expect(fixture.journal.currentEnvelope?.entries == [
            currentSecond, currentFirst,
        ])

        let emptyFixture = AcceptedHistoryStoreFixture()
        emptyFixture.journal.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 3,
                entries: [staleSecond, staleFirst]
            )
        )
        try await emptyFixture.store.pruneInvalidatedRows(using: policy)
        #expect(emptyFixture.journal.currentEnvelope?.revision == 4)
        #expect(emptyFixture.journal.currentEnvelope?.entries.isEmpty == true)
    }

    @Test func pruneRejectsFutureGenerationAndMutationOverflow() async throws {
        let policy = try await historyPolicyReceipt(
            generation: 2,
            enabled: false
        )
        let future = try acceptedHistoryStoredEntry(
            index: 546,
            generation: 3
        )
        let futureFixture = AcceptedHistoryStoreFixture()
        let futureSource = try IOSAcceptedHistoryEnvelope(
            revision: 9,
            entries: [future]
        )
        futureFixture.journal.install(futureSource)
        futureFixture.journal.resetEvents()
        await #expect(
            throws: IOSAcceptedHistoryError.stalePolicyGeneration
        ) {
            try await futureFixture.store.pruneInvalidatedRows(using: policy)
        }
        #expect(futureFixture.journal.currentEnvelope == futureSource)
        #expect(futureFixture.journal.events == ["load"])

        let stale = try acceptedHistoryStoredEntry(
            index: 547,
            generation: 1
        )
        let overflowFixture = AcceptedHistoryStoreFixture()
        let overflowSource = try IOSAcceptedHistoryEnvelope(
            revision: Int64.max,
            entries: [stale]
        )
        overflowFixture.journal.install(overflowSource)
        overflowFixture.journal.resetEvents()
        await #expect(throws: IOSAcceptedHistoryError.revisionOverflow) {
            try await overflowFixture.store.pruneInvalidatedRows(using: policy)
        }
        #expect(overflowFixture.journal.currentEnvelope == overflowSource)
        #expect(overflowFixture.journal.events == ["load"])

        let noOpAtMaximum = AcceptedHistoryStoreFixture()
        let current = try acceptedHistoryStoredEntry(
            index: 548,
            generation: 2
        )
        noOpAtMaximum.journal.install(
            try IOSAcceptedHistoryEnvelope(
                revision: Int64.max,
                entries: [current]
            )
        )
        try await noOpAtMaximum.store.pruneInvalidatedRows(using: policy)
        #expect(noOpAtMaximum.journal.currentEnvelope?.revision == Int64.max)
    }

    @Test func pruneUsesPhysicalCASAcrossStoreActors() async throws {
        let policy = try await historyPolicyReceipt(
            generation: 2,
            enabled: false
        )
        let stale = try acceptedHistoryStoredEntry(
            index: 549,
            generation: 1,
            createdAt: acceptedHistoryStoreDate().addingTimeInterval(-1)
        )
        let current = try acceptedHistoryStoredEntry(
            index: 550,
            generation: 2
        )
        let fixture = AcceptedHistoryStoreFixture()
        fixture.journal.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 3,
                entries: [current, stale]
            )
        )
        fixture.journal.delayNextLoads(2)
        let first = Task {
            try await fixture.store.pruneInvalidatedRows(using: policy)
        }
        let second = Task {
            try await fixture.makeStore().pruneInvalidatedRows(using: policy)
        }
        let results = await [first.result, second.result]
        #expect(results.filter {
            if case .success = $0 { return true }
            return false
        }.count == 1)
        #expect(fixture.journal.currentEnvelope?.revision == 4)
        #expect(fixture.journal.currentEnvelope?.entries == [current])

        try await fixture.store.pruneInvalidatedRows(using: policy)
        #expect(fixture.journal.currentEnvelope?.revision == 4)
    }

    @Test func pruneUncertaintyIsExactReceiptAndStoreWide() async throws {
        let base = acceptedHistoryStoreDate()
        for removesRows in [true, false] {
            for commitWasVisible in [true, false] {
                let fixture = AcceptedHistoryStoreFixture()
                let capabilities = try await historyCapabilities(
                    index: removesRows ? 551 : 552,
                    generation: 2,
                    createdAt: base
                )
                let current = try historyEntry(from: capabilities.delivery)
                let stale = try acceptedHistoryStoredEntry(
                    index: commitWasVisible ? 553 : 554,
                    generation: 1,
                    createdAt: base.addingTimeInterval(-1)
                )
                let source = try IOSAcceptedHistoryEnvelope(
                    revision: 7,
                    entries: removesRows ? [current, stale] : [current]
                )
                fixture.journal.install(source)
                let policy = try await historyPolicyReceipt(
                    generation: 2,
                    enabled: false
                )
                let mismatch = try await historyPolicyReceipt(
                    generation: 3,
                    enabled: true
                )
                fixture.journal.failNextReplace(
                    with: .commitUncertain,
                    commitBeforeThrowing: commitWasVisible
                )

                await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
                    try await fixture.store.pruneInvalidatedRows(using: policy)
                }
                await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
                    try await fixture.store.pruneInvalidatedRows(using: mismatch)
                }
                await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
                    _ = try await fixture.store.load()
                }
                await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
                    _ = try await fixture.store.performStagingMaintenance()
                }
                let other = try await historyCapabilities(
                    index: 555,
                    generation: 2,
                    createdAt: base.addingTimeInterval(1)
                )
                await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
                    _ = try await fixture.store.decideUpsert(
                        delivery: other.delivery,
                        policy: other.policy
                    )
                }
                await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
                    _ = try await fixture.store.confirmMembership(
                        delivery: capabilities.delivery,
                        policy: capabilities.policy
                    )
                }

                try await fixture.store.pruneInvalidatedRows(using: policy)
                #expect(
                    fixture.journal.currentEnvelope?.revision
                        == (removesRows ? 8 : 7)
                )
                #expect(fixture.journal.currentEnvelope?.entries == [current])
            }
        }
    }

    @Test func pruneUncertaintyRejectsSupersedingAcceptedWinner() async throws {
        let base = acceptedHistoryStoreDate()
        let fixture = AcceptedHistoryStoreFixture()
        let currentCapabilities = try await historyCapabilities(
            index: 556,
            generation: 2,
            createdAt: base
        )
        let current = try historyEntry(from: currentCapabilities.delivery)
        let stale = try acceptedHistoryStoredEntry(
            index: 557,
            generation: 1,
            createdAt: base.addingTimeInterval(-1)
        )
        fixture.journal.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 5,
                entries: [current, stale]
            )
        )
        let policy = try await historyPolicyReceipt(
            generation: 2,
            enabled: false
        )
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedHistoryError.commitUncertain) {
            try await fixture.store.pruneInvalidatedRows(using: policy)
        }

        let winner = try await historyCapabilities(
            index: 558,
            generation: 2,
            createdAt: base.addingTimeInterval(1)
        )
        _ = try await fixture.makeStore().decideUpsert(
            delivery: winner.delivery,
            policy: winner.policy
        )
        let winnerEnvelope = fixture.journal.currentEnvelope
        await #expect(
            throws: IOSAcceptedHistoryError.compareAndSwapFailed
        ) {
            try await fixture.store.pruneInvalidatedRows(using: policy)
        }
        #expect(fixture.journal.currentEnvelope == winnerEnvelope)
        #expect(try await fixture.store.load() == winnerEnvelope)
    }

    @Test func maintenanceReportIsForwardedWithoutHistoryPayload() async throws {
        let fixture = AcceptedHistoryStoreFixture()
        fixture.journal.maintenanceReport =
            IOSStrictProtectedRecordMaintenanceReport(
                inspectedEntryCount: 2,
                inspectedByteCount: 32,
                removedFileCount: 1,
                removedByteCount: 16,
                reachedLimit: true
            )

        let report = try await fixture.store.performStagingMaintenance()
        #expect(report.inspectedEntryCount == 2)
        #expect(report.inspectedByteCount == 32)
        #expect(report.removedFileCount == 1)
        #expect(report.removedByteCount == 16)
        #expect(report.reachedLimit)
    }

    @Test func liveRepositoryUsesExactPrivateProtectionAndMarker() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "accepted-history-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: base) }
        let store = IOSAcceptedHistoryStore(
            journal: FoundationIOSAcceptedHistoryJournalRepository(
                applicationSupportDirectoryURL: base
            ),
            now: {
                acceptedHistoryStoreDate().addingTimeInterval(60)
            }
        )
        let capabilities = try await historyCapabilities(index: 540)
        _ = try await store.decideUpsert(
            delivery: capabilities.delivery,
            policy: capabilities.policy
        )

        let rootURL = base.appendingPathComponent("HoldType", isDirectory: true)
        let fileURL = IOSAcceptedHistoryStorageLocation.fileURL(in: base)
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
            IOSStrictProtectedRecordConfiguration.acceptedHistory.marker
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
        await #expect(throws: IOSAcceptedHistoryError.readFailed) {
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
        await #expect(throws: IOSAcceptedHistoryError.readFailed) {
            _ = try await store.load()
        }
        #expect(try Data(contentsOf: fileURL) == preserved)
    }
}

private struct AcceptedHistoryCapabilities {
    let delivery: IOSAcceptedOutputDeliveryAuthorization
    let policy: IOSHistoryPolicyReceipt
}

private func historyCapabilities(
    index: Int,
    generation: Int64 = 1,
    acceptedText: String = "Accepted text",
    createdAt: Date = acceptedHistoryStoreDate()
) async throws -> AcceptedHistoryCapabilities {
    AcceptedHistoryCapabilities(
        delivery: try acceptedHistoryDeliveryAuthorization(
            index: index,
            generation: generation,
            acceptedText: acceptedText,
            createdAt: createdAt
        ),
        policy: try await historyPolicyReceipt(
            generation: generation,
            enabled: true
        )
    )
}

private func acceptedHistoryDeliveryAuthorization(
    index: Int,
    generation: Int64,
    acceptedText: String = "Accepted text",
    createdAt: Date = acceptedHistoryStoreDate(),
    historyState: IOSAcceptedOutputHistoryWriteState = .pending
) throws -> IOSAcceptedOutputDeliveryAuthorization {
    let marker = try IOSAcceptedOutputHistoryWrite(
        state: historyState,
        policyGeneration: generation,
        transcriptionModel: "gpt-4o-mini-transcribe",
        transcriptionLanguageCode: "en",
        durationMilliseconds: 1_250
    )
    let record = try IOSAcceptedOutputDeliveryRecord(
        revision: 1,
        deliveryID: acceptedHistoryUUID(prefix: 0, index: index),
        sessionID: acceptedHistoryUUID(prefix: 1, index: index),
        attemptID: acceptedHistoryUUID(prefix: 2, index: index),
        transcriptID: acceptedHistoryUUID(prefix: 3, index: index),
        acceptedText: acceptedText,
        outputIntent: .standard,
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
                testingToken: UInt64(index + 1)
            )
        )
    )
}

private func acceptedHistoryReauthorizedDelivery(
    _ authorization: IOSAcceptedOutputDeliveryAuthorization,
    fileRevisionToken: UInt64
) -> IOSAcceptedOutputDeliveryAuthorization {
    IOSAcceptedOutputDeliveryAuthorization(
        snapshot: IOSAcceptedOutputDeliveryJournalSnapshot(
            record: authorization.record,
            fileRevision: IOSStrictProtectedRecordFileRevision(
                testingToken: fileRevisionToken
            )
        )
    )
}

private func historyPolicyReceipt(
    generation: Int64,
    enabled: Bool
) async throws -> IOSHistoryPolicyReceipt {
    let state = try IOSHistoryPolicyState(
        revision: generation,
        historyEnabled: enabled,
        policyGeneration: generation
    )
    let journal = AcceptedHistoryPolicyFakeJournal(state: state)
    return try await IOSHistoryPolicyStore(journal: journal).confirm(
        expected: IOSHistoryPolicyExpectation(state: state)
    )
}

private func historyEntry(
    from authorization: IOSAcceptedOutputDeliveryAuthorization,
    cacheIdentifier: String? = nil
) throws -> IOSAcceptedHistoryEntry {
    let record = authorization.record
    let marker = try #require(record.historyWrite)
    return try IOSAcceptedHistoryEntry(
        deliveryID: record.deliveryID,
        transcriptID: record.transcriptID,
        acceptedText: try #require(record.acceptedText),
        outputIntent: record.outputIntent,
        createdAt: record.createdAt,
        policyGeneration: marker.policyGeneration,
        transcriptionModel: marker.transcriptionModel,
        transcriptionLanguageCode: marker.transcriptionLanguageCode,
        durationMilliseconds: marker.durationMilliseconds,
        cachedAudioRelativeIdentifier: cacheIdentifier
    )
}

private func acceptedHistoryStoredEntry(
    index: Int,
    generation: Int64 = 1,
    transcriptID: UUID? = nil,
    acceptedText: String = "Accepted text",
    createdAt: Date = acceptedHistoryStoreDate(),
    cacheIdentifier: String? = nil
) throws -> IOSAcceptedHistoryEntry {
    try IOSAcceptedHistoryEntry(
        deliveryID: acceptedHistoryUUID(prefix: 0, index: index),
        transcriptID: transcriptID
            ?? acceptedHistoryUUID(prefix: 3, index: index),
        acceptedText: acceptedText,
        outputIntent: .standard,
        createdAt: createdAt,
        policyGeneration: generation,
        transcriptionModel: "gpt-4o-mini-transcribe",
        transcriptionLanguageCode: "en",
        durationMilliseconds: 1_250,
        cachedAudioRelativeIdentifier: cacheIdentifier
    )
}

private func exactLimitAcceptedHistoryEnvelope(
    revision: Int64
) throws -> IOSAcceptedHistoryEnvelope {
    let fullText = "a" + String(repeating: "\t", count: 131_070) + "b"
    let baseDate = acceptedHistoryStoreDate()
    let entries = try (0..<15).map { offset in
        try acceptedHistoryStoredEntry(
            index: 700 + offset,
            acceptedText: fullText,
            createdAt: baseDate.addingTimeInterval(Double(-offset))
        )
    }

    func envelope(tabCount: Int, includesASCIIByte: Bool)
        throws -> IOSAcceptedHistoryEnvelope {
        let text = "a"
            + String(repeating: "\t", count: tabCount)
            + (includesASCIIByte ? "x" : "")
            + "b"
        let final = try acceptedHistoryStoredEntry(
            index: 715,
            acceptedText: text,
            createdAt: baseDate.addingTimeInterval(-15)
        )
        return try IOSAcceptedHistoryEnvelope(
            revision: revision,
            entries: entries + [final]
        )
    }

    var lower = 0
    var upper = 131_070
    var best = 0
    while lower <= upper {
        let middle = lower + (upper - lower) / 2
        let candidate = try envelope(
            tabCount: middle,
            includesASCIIByte: false
        )
        if try IOSAcceptedHistoryWireCodec.isWithinEncodedLimit(candidate) {
            best = middle
            lower = middle + 1
        } else {
            upper = middle - 1
        }
    }

    var exact = try envelope(tabCount: best, includesASCIIByte: false)
    var exactSize = try IOSAcceptedHistoryWireCodec.encode(exact).count
    if exactSize < IOSAcceptedHistoryJournal.maximumByteCount {
        exact = try envelope(tabCount: best, includesASCIIByte: true)
        exactSize = try IOSAcceptedHistoryWireCodec.encode(exact).count
    }
    guard exactSize == IOSAcceptedHistoryJournal.maximumByteCount else {
        throw IOSAcceptedHistoryError.invalidRecord
    }
    return exact
}

private func acceptedHistoryStoreDate() -> Date {
    Date(timeIntervalSince1970: 1_800_000_000)
}

private func acceptedHistoryUUID(prefix: Int, index: Int) -> UUID {
    let value = String(
        format: "%08x-0000-4000-8000-%012x",
        prefix,
        index
    )
    return UUID(uuidString: value)!
}

private final class AcceptedHistoryPolicyFakeJournal:
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
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        .empty
    }
}

private final class AcceptedHistoryFakeJournal:
    IOSAcceptedHistoryJournalStoring,
    @unchecked Sendable {
    private struct Failure {
        let error: IOSAcceptedHistoryError
        let commitBeforeThrowing: Bool
    }

    private let lock = NSLock()
    private var snapshot: IOSAcceptedHistoryJournalSnapshot?
    private var nextToken: UInt64 = 1
    private var createFailure: Failure?
    private var replaceFailure: Failure?
    private var delayedLoadCount = 0
    private var storedEvents: [String] = []
    var maintenanceReport = IOSStrictProtectedRecordMaintenanceReport.empty

    var events: [String] { lock.withLock { storedEvents } }
    var currentEnvelope: IOSAcceptedHistoryEnvelope? {
        lock.withLock { snapshot?.envelope }
    }

    func resetEvents() {
        lock.withLock { storedEvents = [] }
    }

    func install(_ envelope: IOSAcceptedHistoryEnvelope) {
        lock.withLock {
            snapshot = IOSAcceptedHistoryJournalSnapshot(
                envelope: envelope,
                fileRevision: makeRevisionLocked()
            )
        }
    }

    func failNextCreate(
        with error: IOSAcceptedHistoryError,
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
        with error: IOSAcceptedHistoryError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            replaceFailure = Failure(
                error: error,
                commitBeforeThrowing: commitBeforeThrowing
            )
        }
    }

    func delayNextLoads(_ count: Int) {
        lock.withLock { delayedLoadCount = count }
    }

    func load() throws -> IOSAcceptedHistoryJournalSnapshot? {
        let result: (IOSAcceptedHistoryJournalSnapshot?, Bool) = lock.withLock {
            storedEvents.append("load")
            let shouldDelay = delayedLoadCount > 0
            if shouldDelay { delayedLoadCount -= 1 }
            return (snapshot, shouldDelay)
        }
        if result.1 { Thread.sleep(forTimeInterval: 0.02) }
        return result.0
    }

    func create(
        _ envelope: IOSAcceptedHistoryEnvelope,
        authorization: IOSAcceptedHistoryJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryJournalSnapshot {
        try lock.withLock {
            storedEvents.append("create:\(envelope.revision)")
            guard snapshot == nil else {
                throw IOSAcceptedHistoryError.slotOccupied
            }
            if let failure = createFailure {
                createFailure = nil
                if failure.commitBeforeThrowing {
                    snapshot = IOSAcceptedHistoryJournalSnapshot(
                        envelope: envelope,
                        fileRevision: makeRevisionLocked()
                    )
                }
                throw failure.error
            }
            let created = IOSAcceptedHistoryJournalSnapshot(
                envelope: envelope,
                fileRevision: makeRevisionLocked()
            )
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
            storedEvents.append("replace:\(envelope.revision)")
            guard snapshot?.fileRevision == expected.fileRevision else {
                throw IOSAcceptedHistoryError.compareAndSwapFailed
            }
            if let failure = replaceFailure {
                replaceFailure = nil
                if failure.commitBeforeThrowing {
                    snapshot = IOSAcceptedHistoryJournalSnapshot(
                        envelope: envelope,
                        fileRevision: makeRevisionLocked()
                    )
                }
                throw failure.error
            }
            let replacement = IOSAcceptedHistoryJournalSnapshot(
                envelope: envelope,
                fileRevision: makeRevisionLocked()
            )
            snapshot = replacement
            return replacement
        }
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        maintenanceReport
    }

    private func makeRevisionLocked()
        -> IOSStrictProtectedRecordFileRevision {
        defer { nextToken += 1 }
        return IOSStrictProtectedRecordFileRevision(testingToken: nextToken)
    }
}

private final class AcceptedHistoryOutboxFakeJournal:
    IOSAcceptedHistoryOutboxJournalStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: IOSAcceptedHistoryOutboxJournalSnapshot?
    private var nextToken: UInt64 = 10_000

    func load() throws -> IOSAcceptedHistoryOutboxJournalSnapshot? {
        lock.withLock { snapshot }
    }

    func create(
        _ envelope: IOSAcceptedHistoryOutboxEnvelope,
        authorization: IOSAcceptedHistoryOutboxJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryOutboxJournalSnapshot {
        try lock.withLock {
            guard snapshot == nil else {
                throw IOSAcceptedHistoryOutboxError.slotOccupied
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
            guard snapshot == expected else {
                throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
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
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        .empty
    }

    private func makeRevisionLocked()
        -> IOSStrictProtectedRecordFileRevision {
        defer { nextToken += 1 }
        return IOSStrictProtectedRecordFileRevision(testingToken: nextToken)
    }
}

private final class AcceptedHistoryTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedNow: Date

    init(now: Date) {
        storedNow = now
    }

    func read() -> Date {
        lock.withLock { storedNow }
    }

    func set(_ now: Date) {
        lock.withLock { storedNow = now }
    }
}

private final class AcceptedHistoryOutboxStoreFixture: @unchecked Sendable {
    let journal = AcceptedHistoryOutboxFakeJournal()
    lazy var store = IOSAcceptedHistoryOutboxStore(
        journal: journal,
        now: {
            acceptedHistoryStoreDate().addingTimeInterval(60)
        }
    )
}

private final class AcceptedHistoryStoreFixture: @unchecked Sendable {
    let journal = AcceptedHistoryFakeJournal()
    private let clock: AcceptedHistoryTestClock
    lazy var store = makeStore()

    init(
        now: Date = acceptedHistoryStoreDate().addingTimeInterval(60)
    ) {
        clock = AcceptedHistoryTestClock(now: now)
    }

    func makeStore() -> IOSAcceptedHistoryStore {
        IOSAcceptedHistoryStore(
            journal: journal,
            now: { [clock] in clock.read() }
        )
    }

    func setNow(_ now: Date) {
        clock.set(now)
    }
}
