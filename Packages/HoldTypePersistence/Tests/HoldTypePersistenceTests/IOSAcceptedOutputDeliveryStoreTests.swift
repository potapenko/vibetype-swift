import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSAcceptedOutputDeliveryStoreTests {
    @Test func guardedBaselineAcceptsMissingAndNilHistoryAtEveryTemporalState() async throws {
        let missing = AcceptedDeliveryStoreFixture()
        let missingEvidence = try await missing.store.proveGuardedBaseline()
        #expect(
            String(describing: missingEvidence)
                == "IOSAcceptedOutputDeliveryGuardedBaselineEvidence(redacted)"
        )
        #expect(missingEvidence.customMirror.children.isEmpty)

        let fixture = AcceptedDeliveryStoreFixture()
        let accepted = try await fixture.store.accept(
            fixture.preparation(historyWrite: nil)
        )
        _ = try await fixture.store.proveGuardedBaseline()

        fixture.clock.wall = accepted.expiresAt
        _ = try await fixture.store.proveGuardedBaseline()

        fixture.clock.wall = accepted.createdAt.addingTimeInterval(-1)
        _ = try await fixture.store.proveGuardedBaseline()
    }

    @Test func guardedBaselineRejectsEveryMarkerRegardlessOfTemporalState() async throws {
        let states: [(IOSAcceptedOutputHistoryWriteState, TimeInterval)] = [
            (.pending, 0),
            (.committed, 86_400),
            (.cancelled, -1),
        ]
        for (state, clockOffset) in states {
            let fixture = AcceptedDeliveryStoreFixture()
            let pending = try fixture.historyWrite()
            let preparation = fixture.preparation(historyWrite: pending)
            let accepted = try await fixture.store.accept(preparation)
            let marker = try pending.replacingState(state)
            fixture.journal.install(
                try IOSAcceptedOutputDeliveryRecord(
                    revision: accepted.revision,
                    deliveryID: accepted.deliveryID,
                    sessionID: accepted.sessionID,
                    attemptID: accepted.attemptID,
                    transcriptID: accepted.transcriptID,
                    acceptedText: accepted.acceptedText,
                    outputIntent: accepted.outputIntent,
                    createdAt: accepted.createdAt,
                    updatedAt: accepted.updatedAt,
                    expiresAt: accepted.expiresAt,
                    deliveryState: accepted.deliveryState,
                    automaticInsertionPreferenceEnabled:
                        accepted.automaticInsertionPreferenceEnabled,
                    keepLatestResult: accepted.keepLatestResult,
                    publicationGeneration: accepted.publicationGeneration,
                    historyWrite: marker
                )
            )
            fixture.clock.wall = accepted.createdAt.addingTimeInterval(
                clockOffset
            )

            await #expect(
                throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            ) {
                _ = try await fixture.store.proveGuardedBaseline()
            }
        }
    }

    @Test func guardedBaselineRejectsEveryUncertaintyFamily() async throws {
        let acceptance = AcceptedDeliveryStoreFixture()
        acceptance.journal.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await acceptance.store.accept(acceptance.preparation())
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await acceptance.store.proveGuardedBaseline()
        }

        let transition = AcceptedDeliveryStoreFixture()
        let (_, transitionAuthorization) = try await transition
            .acceptAndAuthorize()
        let rowReceipt = try await transition.retainedRowReceipt(
            for: transitionAuthorization
        )
        transition.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await transition.store.commitHistoryWrite(
                authorization: transitionAuthorization,
                rowReceipt: rowReceipt
            )
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await transition.store.proveGuardedBaseline()
        }

        let replacement = AcceptedDeliveryStoreFixture()
        let (_, replacementAuthorization) = try await replacement
            .acceptAndAuthorize()
        let replacementProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await replacement.outboxReceipt(
                for: replacementAuthorization
            )
        )
        replacement.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await replacement.store.replacePendingHistory(
                with: replacement.preparation(rawAcceptedText: "replacement"),
                authorization: replacementAuthorization,
                ownershipProof: replacementProof
            )
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await replacement.store.proveGuardedBaseline()
        }

        let clear = AcceptedDeliveryStoreFixture()
        let (_, clearAuthorization) = try await clear.acceptAndAuthorize()
        let clearProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await clear.outboxReceipt(
                for: clearAuthorization
            )
        )
        clear.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await clear.store.clearPendingHistory(
                authorization: clearAuthorization,
                ownershipProof: clearProof
            )
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await clear.store.proveGuardedBaseline()
        }
    }

    @Test func guardedBaselinePropagatesTypedReadFailures() async {
        let fixture = AcceptedDeliveryStoreFixture()
        for error in [
            IOSAcceptedOutputDeliveryError.sourceTooLarge,
            .malformedData,
            .unsupportedSchemaVersion,
            .dataProtectionUnavailable,
            .readFailed,
        ] {
            fixture.journal.failLoads(with: error)
            await #expect(throws: error) {
                _ = try await fixture.store.proveGuardedBaseline()
            }
            fixture.journal.failLoads(with: nil)
        }
    }

    @Test func acceptanceCommitsGenerationZeroAndAnExactImmutableDeadline() async throws {
        let fixture = AcceptedDeliveryStoreFixture()

        let record = try await fixture.store.accept(fixture.preparation())

        #expect(record.revision == 1)
        #expect(record.deliveryState == .pending)
        #expect(record.publicationGeneration == 0)
        #expect(record.createdAt == fixture.clock.wall)
        #expect(record.updatedAt == fixture.clock.wall)
        #expect(
            record.expiresAt
                == fixture.clock.wall.addingTimeInterval(24 * 60 * 60)
        )
        #expect(fixture.journal.events == ["load", "create"])
    }

    @Test func wallExpiryIsActiveImmediatelyBeforeAndExpiredAtDeadline() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let record = try await fixture.store.accept(fixture.preparation())

        fixture.clock.wall = record.expiresAt.addingTimeInterval(-0.001)
        #expect(try await fixture.store.load() == .active(record))
        fixture.clock.wall = record.expiresAt
        #expect(
            try await fixture.store.load()
                == .expired(IOSAcceptedOutputDeliveryExpectation(record: record))
        )
        fixture.clock.wall = record.expiresAt.addingTimeInterval(0.001)
        #expect(
            try await fixture.store.load()
                == .expired(IOSAcceptedOutputDeliveryExpectation(record: record))
        )
    }

    @Test func monotonicDeadlineCanOnlyShortenWallEligibility() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let record = try await fixture.store.accept(fixture.preparation())
        _ = try await fixture.store.load()

        fixture.clock.monotonicNanoseconds = 86_400_000_000_000
        #expect(
            try await fixture.store.load()
                == .expired(IOSAcceptedOutputDeliveryExpectation(record: record))
        )
    }

    @Test func rollbackBlocksMutationButExplicitClearRetainsUpdatedAt() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let record = try await fixture.store.accept(fixture.preparation())
        fixture.clock.wall = record.createdAt.addingTimeInterval(-0.001)

        #expect(
            try await fixture.store.load()
                == .clockRollbackAmbiguous(
                    IOSAcceptedOutputDeliveryExpectation(record: record)
                )
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        ) {
            try await fixture.store.disableKeepLatestResult(
                expected: IOSAcceptedOutputDeliveryExpectation(record: record)
            )
        }

        #expect(
            try await fixture.store.clear(
                expected: IOSAcceptedOutputDeliveryExpectation(record: record)
            ) == .removed
        )
        let removed = try #require(fixture.journal.removedRecords.last)
        #expect(removed.deliveryState == .discarded)
        #expect(removed.updatedAt == record.updatedAt)
        #expect(removed.acceptedText == nil)
    }

    @Test func clearEvaluatesTemporalStateOnlyOnceBeforeMutation() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let record = try await fixture.store.accept(fixture.preparation())
        fixture.clock.resetWallReadCount()

        #expect(
            try await fixture.store.clear(
                expected: IOSAcceptedOutputDeliveryExpectation(record: record)
            ) == .removed
        )

        #expect(fixture.clock.wallReadCount == 2)
    }

    @Test func historyAuthorizationRewritesBeforeUpsertAndTransition() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let history = try fixture.historyWrite()
        let preparation = fixture.preparation(historyWrite: history)
        let accepted = try await fixture.store.accept(preparation)
        fixture.journal.resetEvents()

        let authorization = try await fixture.store
            .authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
            )
        #expect(authorization.record == accepted)
        #expect(fixture.journal.events == ["load", "replace:1"])

        let rowReceipt = try await fixture.retainedRowReceipt(
            for: authorization
        )
        let committed = try await fixture.store.commitHistoryWrite(
            authorization: authorization,
            rowReceipt: rowReceipt
        )
        #expect(committed.revision == 2)
        #expect(committed.historyWrite?.state == .committed)
        #expect(committed.historyWrite?.hasSameMetadata(as: history) == true)
        #expect(committed.updatedAt == fixture.clock.wall)
    }

    @Test func historyAuthorizationRevalidatesExpiryAfterDurabilityRewrite() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let accepted = try await fixture.store.accept(
            fixture.preparation(historyWrite: try fixture.historyWrite())
        )
        fixture.clock.enqueueWallReadOverrides([
            accepted.expiresAt.addingTimeInterval(-0.001),
            accepted.expiresAt,
        ])

        await #expect(throws: IOSAcceptedOutputDeliveryError.expired) {
            try await fixture.store.authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
            )
        }

        #expect(fixture.journal.replacementRecords.last == accepted)
    }

    @Test func acceptanceConfirmationDoesNotMintHistoryAuthority() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let preparation = fixture.preparation(
            historyWrite: try fixture.historyWrite()
        )
        let accepted = try await fixture.store.accept(preparation)
        _ = try await fixture.store.accept(preparation)
        fixture.journal.resetEvents()

        _ = try await fixture.store.authorizePendingHistoryWrite(
            expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
        )

        #expect(fixture.journal.events == ["load", "replace:1"])
    }

    @Test func relaunchedProcessConfirmsPriorVisibleCommitBeforeAuthority() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let preparation = fixture.preparation(
            historyWrite: try fixture.historyWrite()
        )
        let priorProcessRecord = try fixture.record(preparation: preparation)
        fixture.journal.install(priorProcessRecord)

        let authorization = try await fixture.store
            .authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: priorProcessRecord
                )
            )

        #expect(authorization.record == priorProcessRecord)
        #expect(fixture.journal.replacementRecords == [priorProcessRecord])
        #expect(fixture.journal.currentRecord?.revision == 1)
        #expect(
            fixture.journal.currentRecord?.updatedAt
                == priorProcessRecord.updatedAt
        )
    }

    @Test func uncertainAuthorizationCannotMintAuthorityAndRetryConfirmsBytes() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let accepted = try await fixture.store.accept(
            fixture.preparation(historyWrite: try fixture.historyWrite())
        )
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
            )
        }
        #expect(fixture.journal.currentRecord == accepted)

        let authorization = try await fixture.store
            .authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
            )
        let rowReceipt = try await fixture.retainedRowReceipt(
            for: authorization
        )
        let committed = try await fixture.store.commitHistoryWrite(
            authorization: authorization,
            rowReceipt: rowReceipt
        )
        #expect(committed.historyWrite?.state == .committed)
    }

    @Test func uncertainHistoryTransitionRequiresIdenticalConfirmationRetry() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (_, authorization) = try await fixture.acceptAndAuthorize()
        let rowReceipt = try await fixture.retainedRowReceipt(
            for: authorization
        )
        let foreignReceipt = try await fixture.retainedRowReceipt(
            for: authorization,
            fileRevisionToken: 99
        )
        #expect(foreignReceipt != rowReceipt)
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.commitHistoryWrite(
                authorization: authorization,
                rowReceipt: rowReceipt
            )
        }
        let visible = try #require(fixture.journal.currentRecord)
        #expect(visible.revision == 2)
        #expect(visible.historyWrite?.state == .committed)

        let replacementCount = fixture.journal.replacementRecords.count
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.commitHistoryWrite(
                authorization: authorization,
                rowReceipt: foreignReceipt
            )
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.accept(
                fixture.preparation(rawAcceptedText: "blocked transition")
            )
        }
        #expect(fixture.journal.replacementRecords.count == replacementCount)

        fixture.clock.wall = visible.expiresAt
        let confirmed = try await fixture.store.commitHistoryWrite(
            authorization: authorization,
            rowReceipt: rowReceipt
        )
        #expect(confirmed == visible)
        #expect(fixture.journal.replacementRecords.last == visible)
    }

    @Test func invisibleUncertainHistoryTransitionRevalidatesExpiry() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (accepted, authorization) = try await fixture.acceptAndAuthorize()
        let rowReceipt = try await fixture.retainedRowReceipt(
            for: authorization
        )
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.commitHistoryWrite(
                authorization: authorization,
                rowReceipt: rowReceipt
            )
        }
        #expect(fixture.journal.currentRecord == accepted)
        let replacementCount = fixture.journal.replacementRecords.count

        fixture.clock.wall = accepted.expiresAt
        await #expect(throws: IOSAcceptedOutputDeliveryError.expired) {
            try await fixture.store.commitHistoryWrite(
                authorization: authorization,
                rowReceipt: rowReceipt
            )
        }
        #expect(fixture.journal.currentRecord == accepted)
        #expect(fixture.journal.replacementRecords.count == replacementCount)
    }

    @Test func missingCurrentClearsHistoryTransitionUncertaintyGate() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (_, authorization) = try await fixture.acceptAndAuthorize()
        let rowReceipt = try await fixture.retainedRowReceipt(
            for: authorization
        )
        let ownershipProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await fixture.outboxReceipt(
                for: authorization
            )
        )
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.commitHistoryWrite(
                authorization: authorization,
                rowReceipt: rowReceipt
            )
        }
        #expect(
            try await fixture.makeStore().clearPendingHistory(
                authorization: authorization,
                ownershipProof: ownershipProof
            ) == .removed
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await fixture.store.commitHistoryWrite(
                authorization: authorization,
                rowReceipt: rowReceipt
            )
        }

        let replacement = fixture.preparation(
            rawAcceptedText: "after missing transition"
        )
        let accepted = try await fixture.store.accept(replacement)
        #expect(accepted.hasSameAcceptance(as: replacement))
    }

    @Test func differentWinnerClearsHistoryTransitionUncertaintyGate() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (_, authorization) = try await fixture.acceptAndAuthorize()
        let rowReceipt = try await fixture.retainedRowReceipt(
            for: authorization
        )
        let invalidation = try await fixture.policyReceipt(generation: 2)
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.commitHistoryWrite(
                authorization: authorization,
                rowReceipt: rowReceipt
            )
        }
        let winner = try await fixture.makeStore().cancelHistoryWrite(
            authorization: authorization,
            policyInvalidationReceipt: invalidation
        )
        #expect(winner.historyWrite?.state == .cancelled)
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await fixture.store.commitHistoryWrite(
                authorization: authorization,
                rowReceipt: rowReceipt
            )
        }

        let replacement = fixture.preparation(
            rawAcceptedText: "after transition winner"
        )
        let accepted = try await fixture.store.accept(replacement)
        #expect(accepted.hasSameAcceptance(as: replacement))
    }

    @Test func historyCommitAcceptsDurableNotRetainedDecision() async throws {
        let droppedFixture = AcceptedDeliveryStoreFixture()
        let (_, droppedAuthorization) = try await droppedFixture
            .acceptAndAuthorize()
        let droppedReceipt = try await droppedFixture.notRetainedRowReceipt(
            for: droppedAuthorization
        )
        #expect(droppedReceipt.decision == .notRetained)
        let droppedCommit = try await droppedFixture.store.commitHistoryWrite(
            authorization: droppedAuthorization,
            rowReceipt: droppedReceipt
        )
        #expect(droppedCommit.historyWrite?.state == .committed)
    }

    @Test func historyCommitRejectsStaleForeignAndUnicodeAlteredReceipts() async throws {
        let staleFixture = AcceptedDeliveryStoreFixture()
        let (staleAccepted, firstAuthorization) = try await staleFixture
            .acceptAndAuthorize()
        let staleReceipt = try await staleFixture.retainedRowReceipt(
            for: firstAuthorization
        )
        let refreshedAuthorization = try await staleFixture.makeStore()
            .authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: staleAccepted
                )
            )
        #expect(firstAuthorization != refreshedAuthorization)
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await staleFixture.store.commitHistoryWrite(
                authorization: refreshedAuthorization,
                rowReceipt: staleReceipt
            )
        }

        let targetFixture = AcceptedDeliveryStoreFixture()
        let (_, targetAuthorization) = try await targetFixture
            .acceptAndAuthorize()
        let foreignFixture = AcceptedDeliveryStoreFixture()
        let (_, foreignAuthorization) = try await foreignFixture
            .acceptAndAuthorize()
        let foreignReceipt = try await foreignFixture.retainedRowReceipt(
            for: foreignAuthorization
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await targetFixture.store.commitHistoryWrite(
                authorization: targetAuthorization,
                rowReceipt: foreignReceipt
            )
        }

        let unicodeFixture = AcceptedDeliveryStoreFixture()
        let unicodePreparation = unicodeFixture.preparation(
            rawAcceptedText: "e\u{301}",
            historyWrite: try unicodeFixture.historyWrite()
        )
        let (_, unicodeAuthorization) = try await unicodeFixture
            .acceptAndAuthorize(unicodePreparation)
        let composedFixture = AcceptedDeliveryStoreFixture()
        let (_, composedAuthorization) = try await composedFixture
            .acceptAndAuthorize(
                composedFixture.preparation(
                deliveryID: unicodePreparation.deliveryID,
                sessionID: unicodePreparation.sessionID,
                attemptID: unicodePreparation.attemptID,
                transcriptID: unicodePreparation.transcriptID,
                rawAcceptedText: "é",
                historyWrite: try composedFixture.historyWrite()
                )
            )
        let composedOutbox = try await composedFixture.outboxReceipt(
            for: composedAuthorization
        )
        let composedRow = try await composedFixture.rowReceipt(
            for: composedOutbox
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await unicodeFixture.store.commitHistoryWrite(
                authorization: unicodeAuthorization,
                rowReceipt: composedRow
            )
        }
    }

    @Test func historyCancelIsOneWayIdempotentAndConflictsWithCommit() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (_, authorization) = try await fixture.acceptAndAuthorize()
        let invalidation = try await fixture.policyReceipt(generation: 2)
        let cancelled = try await fixture.store.cancelHistoryWrite(
            authorization: authorization,
            policyInvalidationReceipt: invalidation
        )
        #expect(cancelled.historyWrite?.state == .cancelled)

        let retried = try await fixture.store.cancelHistoryWrite(
            authorization: authorization,
            policyInvalidationReceipt: invalidation
        )
        #expect(retried == cancelled)
        let currentExpectation = IOSAcceptedOutputDeliveryExpectation(
            record: retried
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.invalidTransition) {
            let authorization = try await fixture.store
                .authorizePendingHistoryWrite(expected: currentExpectation)
            let rowReceipt = try await fixture.retainedRowReceipt(
                for: authorization
            )
            _ = try await fixture.store.commitHistoryWrite(
                authorization: authorization,
                rowReceipt: rowReceipt
            )
        }
    }

    @Test func historyCancelRequiresAConfirmedStrictlyNewerPolicyGeneration() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (_, authorization) = try await fixture.acceptAndAuthorize(
            fixture.preparation(
                historyWrite: try fixture.historyWrite(policyGeneration: 2)
            )
        )
        let replacementCount = fixture.journal.replacementRecords.count

        for generation in [Int64(1), 2] {
            let receipt = try await fixture.policyReceipt(
                generation: generation
            )
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            ) {
                try await fixture.store.cancelHistoryWrite(
                    authorization: authorization,
                    policyInvalidationReceipt: receipt
                )
            }
        }
        #expect(fixture.journal.replacementRecords.count == replacementCount)

        let newer = try await fixture.policyReceipt(generation: 3)
        let cancelled = try await fixture.store.cancelHistoryWrite(
            authorization: authorization,
            policyInvalidationReceipt: newer
        )
        #expect(cancelled.historyWrite?.state == .cancelled)
    }

    @Test func uncertainCancelRequiresTheExactPolicyReceiptPair() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (_, authorization) = try await fixture.acceptAndAuthorize()
        let exactReceipt = try await fixture.policyReceipt(
            generation: 2,
            fileRevisionToken: 1
        )
        let foreignReceipt = try await fixture.policyReceipt(
            generation: 2,
            fileRevisionToken: 99
        )
        #expect(exactReceipt != foreignReceipt)
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.cancelHistoryWrite(
                authorization: authorization,
                policyInvalidationReceipt: exactReceipt
            )
        }
        let visible = try #require(fixture.journal.currentRecord)
        #expect(visible.historyWrite?.state == .cancelled)
        let replacementCount = fixture.journal.replacementRecords.count

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.cancelHistoryWrite(
                authorization: authorization,
                policyInvalidationReceipt: foreignReceipt
            )
        }
        #expect(fixture.journal.replacementRecords.count == replacementCount)

        fixture.clock.wall = visible.createdAt.addingTimeInterval(-1)
        let confirmed = try await fixture.store.cancelHistoryWrite(
            authorization: authorization,
            policyInvalidationReceipt: exactReceipt
        )
        #expect(confirmed == visible)
    }

    @Test func duplicateAcceptanceNeverRecreatesHistoryOrKeepLatestIntent() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let history = try fixture.historyWrite()
        let preparation = fixture.preparation(
            keepLatestResult: true,
            historyWrite: history
        )
        let accepted = try await fixture.store.accept(preparation)
        let authorization = try await fixture.store
            .authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
            )
        let rowReceipt = try await fixture.retainedRowReceipt(
            for: authorization
        )
        let committed = try await fixture.store.commitHistoryWrite(
            authorization: authorization,
            rowReceipt: rowReceipt
        )
        let disabled = try await fixture.store.disableKeepLatestResult(
            expected: IOSAcceptedOutputDeliveryExpectation(record: committed)
        )

        let replayed = try await fixture.store.accept(preparation)
        #expect(replayed.revision == disabled.revision)
        #expect(!replayed.keepLatestResult)
        #expect(replayed.historyWrite?.state == .committed)
        #expect(replayed.updatedAt == disabled.updatedAt)
    }

    @Test func duplicateAcceptanceCanOnlyWeakenKeepLatestIntent() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let original = fixture.preparation(keepLatestResult: true)
        let accepted = try await fixture.store.accept(original)
        let revocation = fixture.preparation(
            deliveryID: original.deliveryID,
            sessionID: original.sessionID,
            attemptID: original.attemptID,
            transcriptID: original.transcriptID,
            rawAcceptedText: original.acceptedText,
            keepLatestResult: false
        )

        let weakened = try await fixture.store.accept(revocation)
        #expect(weakened.revision == accepted.revision + 1)
        #expect(!weakened.keepLatestResult)

        let replayedOriginal = try await fixture.store.accept(original)
        #expect(replayedOriginal.revision == weakened.revision)
        #expect(!replayedOriginal.keepLatestResult)
    }

    @Test func ordinaryAcceptanceCreateUncertaintyRequiresExactRetry() async throws {
        for commitWasVisible in [false, true] {
            let fixture = AcceptedDeliveryStoreFixture()
            let preparation = fixture.preparation(
                rawAcceptedText: "create secret \(commitWasVisible)"
            )
            let intended = try fixture.record(preparation: preparation)
            fixture.journal.failNextCreate(
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )

            await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
                try await fixture.store.accept(preparation)
            }
            #expect(
                fixture.journal.currentRecord
                    == (commitWasVisible ? intended : nil)
            )

            let mismatch = fixture.preparation(
                rawAcceptedText: "mismatched create secret"
            )
            let eventCount = fixture.journal.events.count
            do {
                _ = try await fixture.store.accept(mismatch)
                Issue.record("Mismatched acceptance unexpectedly succeeded")
            } catch let error as IOSAcceptedOutputDeliveryError {
                #expect(error == .commitUncertain)
                #expect(error.description == "IOSAcceptedOutputDeliveryError(redacted)")
                #expect(error.customMirror.children.count == 1)
                #expect(error.customMirror.children.first?.label == "state")
                #expect(
                    String(
                        describing: error.customMirror.children.first?.value
                    ) == "Optional(\"redacted\")"
                )
                #expect(!String(reflecting: error).contains(mismatch.acceptedText))
            }
            #expect(fixture.journal.events.count == eventCount)

            fixture.journal.resetEvents()
            let confirmed = try await fixture.store.accept(preparation)

            #expect(confirmed == intended)
            #expect(
                fixture.journal.events
                    == (commitWasVisible
                        ? ["load", "replace:1"]
                        : ["load", "create"])
            )
        }
    }

    @Test func ordinaryReplacementUncertaintyUsesItsSealedIntendedRecord() async throws {
        for commitWasVisible in [false, true] {
            let fixture = AcceptedDeliveryStoreFixture()
            let old = try await fixture.store.accept(fixture.preparation())
            let preparation = fixture.preparation(
                rawAcceptedText: "replacement \(commitWasVisible)"
            )
            let intended = try fixture.record(preparation: preparation)
            fixture.journal.failNextReplace(
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )

            await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
                try await fixture.store.accept(preparation)
            }
            #expect(
                fixture.journal.currentRecord
                    == (commitWasVisible ? intended : old)
            )

            fixture.clock.wall = fixture.clock.wall.addingTimeInterval(60)
            let confirmed = try await fixture.store.accept(preparation)

            #expect(confirmed == intended)
            #expect(confirmed.createdAt == intended.createdAt)
            #expect(confirmed.updatedAt == intended.updatedAt)
            #expect(confirmed.revision == 1)
        }
    }

    @Test func sameAcceptanceUncertaintyConfirmsWithoutLogicalMutation() async throws {
        for commitWasVisible in [false, true] {
            let fixture = AcceptedDeliveryStoreFixture()
            let preparation = fixture.preparation(
                rawAcceptedText: "identical \(commitWasVisible)"
            )
            let accepted = try await fixture.store.accept(preparation)
            fixture.journal.failNextReplace(
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )

            await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
                try await fixture.store.accept(preparation)
            }
            let confirmed = try await fixture.store.accept(preparation)

            #expect(confirmed == accepted)
            #expect(confirmed.revision == accepted.revision)
            #expect(confirmed.updatedAt == accepted.updatedAt)
            #expect(fixture.journal.replacementRecords.last == accepted)
        }
    }

    @Test func keepLatestWeakeningUncertaintyKeepsSealedRevisionAndTimestamp() async throws {
        for commitWasVisible in [false, true] {
            let fixture = AcceptedDeliveryStoreFixture()
            let original = fixture.preparation(keepLatestResult: true)
            let accepted = try await fixture.store.accept(original)
            let weakeningTime = accepted.createdAt.addingTimeInterval(10)
            fixture.clock.wall = weakeningTime
            let weakening = fixture.preparation(
                deliveryID: original.deliveryID,
                sessionID: original.sessionID,
                attemptID: original.attemptID,
                transcriptID: original.transcriptID,
                rawAcceptedText: original.acceptedText,
                keepLatestResult: false
            )
            fixture.journal.failNextReplace(
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )

            await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
                try await fixture.store.accept(weakening)
            }
            fixture.clock.wall = weakeningTime.addingTimeInterval(20)
            let confirmed = try await fixture.store.accept(weakening)

            #expect(confirmed.revision == accepted.revision + 1)
            #expect(confirmed.updatedAt == weakeningTime)
            #expect(!confirmed.keepLatestResult)
        }
    }

    @Test func visibleAcceptanceUncertaintyConfirmsDespiteRollbackOrExpiry() async throws {
        let rollbackFixture = AcceptedDeliveryStoreFixture()
        let create = rollbackFixture.preparation(rawAcceptedText: "rollback")
        let createIntended = try rollbackFixture.record(preparation: create)
        rollbackFixture.journal.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await rollbackFixture.store.accept(create)
        }
        rollbackFixture.clock.wall = createIntended.createdAt
            .addingTimeInterval(-1)

        let rollbackConfirmed = try await rollbackFixture.store.accept(create)

        #expect(rollbackConfirmed == createIntended)
        #expect(
            try await rollbackFixture.store.load()
                == .clockRollbackAmbiguous(
                    IOSAcceptedOutputDeliveryExpectation(
                        record: createIntended
                    )
                )
        )

        let expiryFixture = AcceptedDeliveryStoreFixture()
        _ = try await expiryFixture.store.accept(expiryFixture.preparation())
        let replacement = expiryFixture.preparation(rawAcceptedText: "expiry")
        let replacementIntended = try expiryFixture.record(
            preparation: replacement
        )
        expiryFixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await expiryFixture.store.accept(replacement)
        }
        expiryFixture.clock.wall = replacementIntended.expiresAt

        let expiryConfirmed = try await expiryFixture.store.accept(replacement)

        #expect(expiryConfirmed == replacementIntended)
        #expect(
            try await expiryFixture.store.load()
                == .expired(
                    IOSAcceptedOutputDeliveryExpectation(
                        record: replacementIntended
                    )
                )
        )
    }

    @Test func visibleIntentSurvivesASecondInvisibleConfirmationFailure() async throws {
        for retryAtExpiry in [false, true] {
            let fixture = AcceptedDeliveryStoreFixture()
            _ = try await fixture.store.accept(fixture.preparation())
            let replacement = fixture.preparation(
                rawAcceptedText: retryAtExpiry
                    ? "second failure expiry"
                    : "second failure rollback"
            )
            let intended = try fixture.record(preparation: replacement)
            fixture.journal.failNextReplace(
                with: .commitUncertain,
                commitBeforeThrowing: true
            )
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                try await fixture.store.accept(replacement)
            }

            fixture.clock.wall = retryAtExpiry
                ? intended.expiresAt
                : intended.createdAt.addingTimeInterval(-1)
            fixture.journal.failNextReplace(
                with: .commitUncertain,
                commitBeforeThrowing: false
            )
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                try await fixture.store.accept(replacement)
            }
            #expect(fixture.journal.currentRecord == intended)

            let confirmed = try await fixture.store.accept(replacement)

            #expect(confirmed == intended)
            #expect(fixture.journal.replacementRecords.last == intended)
        }
    }

    @Test func invisibleAcceptanceUncertaintyRetainsOrClearsItsGateExactly() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let preparation = fixture.preparation(rawAcceptedText: "temporal secret")
        let intended = try fixture.record(preparation: preparation)
        fixture.journal.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.accept(preparation)
        }

        for loadError in [
            IOSAcceptedOutputDeliveryError.readFailed,
            .dataProtectionUnavailable,
        ] {
            fixture.journal.failLoads(with: loadError)
            await #expect(throws: loadError) {
                try await fixture.store.accept(preparation)
            }
            fixture.journal.failLoads(with: nil)
            await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
                try await fixture.store.load()
            }
        }

        fixture.clock.wall = intended.createdAt.addingTimeInterval(-1)
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        ) {
            try await fixture.store.accept(preparation)
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.load()
        }

        fixture.clock.wall = intended.expiresAt
        await #expect(throws: IOSAcceptedOutputDeliveryError.expired) {
            try await fixture.store.accept(preparation)
        }
        #expect(try await fixture.store.load() == nil)
    }

    @Test func acceptanceUncertaintyBlocksEveryOtherStorePath() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let preparation = fixture.preparation(
            historyWrite: try fixture.historyWrite()
        )
        let accepted = try await fixture.store.accept(preparation)
        let authorization = try await fixture.store.authorizePendingHistoryWrite(
            expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
        )
        let rowReceipt = try await fixture.retainedRowReceipt(
            for: authorization
        )
        let policy = try await fixture.policyReceipt(generation: 2)
        let outbox = try await fixture.outboxReceipt(for: authorization)
        let ownership = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: outbox
        )
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.accept(preparation)
        }

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.load()
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
            )
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.commitHistoryWrite(
                authorization: authorization,
                rowReceipt: rowReceipt
            )
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.cancelHistoryWrite(
                authorization: authorization,
                policyInvalidationReceipt: policy
            )
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.replacePendingHistory(
                with: fixture.preparation(rawAcceptedText: "replacement"),
                authorization: authorization,
                ownershipProof: ownership
            )
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.clearPendingHistory(
                authorization: authorization,
                ownershipProof: ownership
            )
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.disableKeepLatestResult(
                expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
            )
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.clear(
                expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
            )
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.removeExpired(
                expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
            )
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.performStagingMaintenance()
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.discardUnreadableLocalResult()
        }

        #expect(try await fixture.store.accept(preparation) == accepted)
    }

    @Test func supersedingOrMissingWinnerClearsAcceptanceUncertainty() async throws {
        let winnerFixture = AcceptedDeliveryStoreFixture()
        let old = try await winnerFixture.store.accept(
            winnerFixture.preparation()
        )
        let uncertain = winnerFixture.preparation(
            rawAcceptedText: "uncertain winner"
        )
        winnerFixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await winnerFixture.store.accept(uncertain)
        }
        let winningPreparation = winnerFixture.preparation(
            rawAcceptedText: "actual winner"
        )
        let winner = try await winnerFixture.makeStore().accept(
            winningPreparation
        )
        #expect(winner.deliveryID != old.deliveryID)

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await winnerFixture.store.accept(uncertain)
        }
        #expect(try await winnerFixture.store.load() == .active(winner))

        let missingFixture = AcceptedDeliveryStoreFixture()
        let existing = try await missingFixture.store.accept(
            missingFixture.preparation()
        )
        let missingUncertain = missingFixture.preparation(
            rawAcceptedText: "missing winner"
        )
        missingFixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await missingFixture.store.accept(missingUncertain)
        }
        #expect(
            try await missingFixture.makeStore().clear(
                expected: IOSAcceptedOutputDeliveryExpectation(record: existing)
            ) == .removed
        )

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await missingFixture.store.accept(missingUncertain)
        }
        #expect(try await missingFixture.store.load() == nil)
    }

    @Test func physicalSourceRewriteCannotAuthorizeInvisibleAcceptanceReplay() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let original = fixture.preparation(rawAcceptedText: "physical source")
        let accepted = try await fixture.store.accept(original)
        let replacement = fixture.preparation(rawAcceptedText: "stale replay")
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.accept(replacement)
        }

        #expect(try await fixture.makeStore().accept(original) == accepted)
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await fixture.store.accept(replacement)
        }
        #expect(try await fixture.store.load() == .active(accepted))
    }

    @Test func visibleSameAcceptanceRetryPreservesMonotonicExpiry() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let preparation = fixture.preparation(rawAcceptedText: "monotonic")
        let accepted = try await fixture.store.accept(preparation)
        #expect(try await fixture.store.load() == .active(accepted))
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.accept(preparation)
        }

        fixture.clock.monotonicNanoseconds = 86_400_000_000_000
        #expect(try await fixture.store.accept(preparation) == accepted)
        #expect(
            try await fixture.store.load()
                == .expired(IOSAcceptedOutputDeliveryExpectation(record: accepted))
        )
    }

    @Test func invisibleMutationExpiryClearsIntentWithoutRestoringWallEligibility() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let original = fixture.preparation(
            rawAcceptedText: "invisible monotonic",
            keepLatestResult: true
        )
        let accepted = try await fixture.store.accept(original)
        let weakening = fixture.preparation(
            deliveryID: original.deliveryID,
            sessionID: original.sessionID,
            attemptID: original.attemptID,
            transcriptID: original.transcriptID,
            rawAcceptedText: original.acceptedText,
            keepLatestResult: false
        )
        #expect(try await fixture.store.load() == .active(accepted))
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.accept(weakening)
        }

        fixture.clock.monotonicNanoseconds = 86_400_000_000_000
        await #expect(throws: IOSAcceptedOutputDeliveryError.expired) {
            try await fixture.store.accept(weakening)
        }
        #expect(
            try await fixture.store.load()
                == .expired(IOSAcceptedOutputDeliveryExpectation(record: accepted))
        )
    }

    @Test func pendingHistoryDecisionUsesOneTemporalSnapshot() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let accepted = try await fixture.store.accept(
            fixture.preparation(historyWrite: try fixture.historyWrite())
        )
        fixture.clock.resetWallReadCount()
        fixture.clock.enqueueWallReadOverrides([
            accepted.createdAt.addingTimeInterval(1),
            accepted.createdAt.addingTimeInterval(1),
            accepted.createdAt.addingTimeInterval(-1),
        ])

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.historyTransferRequired
        ) {
            try await fixture.store.accept(
                fixture.preparation(rawAcceptedText: "replacement")
            )
        }

        #expect(fixture.clock.wallReadCount == 2)
        #expect(fixture.journal.currentRecord == accepted)
    }

    @Test func concurrentIdenticalCreateConflictIsReconciled() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let preparation = fixture.preparation()
        fixture.journal.failNextCreate(
            with: .slotOccupied,
            commitBeforeThrowing: true
        )

        let accepted = try await fixture.store.accept(preparation)

        #expect(accepted.hasSameAcceptance(as: preparation))
        #expect(fixture.journal.currentRecord == accepted)
        #expect(fixture.journal.events == [
            "load", "create", "load", "replace:1",
        ])
    }

    @Test func concurrentIdenticalReplacementConflictIsReconciled() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        _ = try await fixture.store.accept(fixture.preparation())
        let replacement = fixture.preparation(rawAcceptedText: "new result")
        fixture.journal.failNextReplace(
            with: .compareAndSwapFailed,
            commitBeforeThrowing: true
        )

        let accepted = try await fixture.store.accept(replacement)

        #expect(accepted.hasSameAcceptance(as: replacement))
        #expect(fixture.journal.currentRecord == accepted)
        #expect(fixture.journal.replacementRecords.last == accepted)
    }

    @Test func replacementAllowsReusedAttemptWithFreshTranscriptButRejectsFullCollision() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let firstPreparation = fixture.preparation()
        _ = try await fixture.store.accept(firstPreparation)

        let retryPreparation = fixture.preparation(
            deliveryID: UUID(),
            sessionID: firstPreparation.sessionID,
            attemptID: firstPreparation.attemptID,
            transcriptID: UUID(),
            rawAcceptedText: "retry result"
        )
        let retry = try await fixture.store.accept(retryPreparation)
        #expect(retry.attemptID == firstPreparation.attemptID)
        #expect(retry.transcriptID != firstPreparation.transcriptID)

        let collision = fixture.preparation(
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: retry.attemptID,
            transcriptID: retry.transcriptID,
            rawAcceptedText: "different bytes"
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.identityCollision) {
            try await fixture.store.accept(collision)
        }
        #expect(fixture.journal.currentRecord == retry)
    }

    @Test func pendingHistoryBlocksClearAndReplacementUntilOutboxExists() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let accepted = try await fixture.store.accept(
            fixture.preparation(historyWrite: try fixture.historyWrite())
        )

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.historyTransferRequired
        ) {
            try await fixture.store.clear(
                expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
            )
        }
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.historyTransferRequired
        ) {
            try await fixture.store.accept(
                fixture.preparation(rawAcceptedText: "replacement")
            )
        }
        #expect(fixture.journal.currentRecord == accepted)
    }

    @Test func exactOutboxProofCanClearPendingHistory() async throws {
        let outboxFixture = AcceptedDeliveryStoreFixture()
        let (_, outboxAuthorization) = try await outboxFixture
            .acceptAndAuthorize()
        let outboxReceipt = try await outboxFixture.outboxReceipt(
            for: outboxAuthorization
        )
        let outboxProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: outboxReceipt
        )
        #expect(
            String(describing: outboxProof)
                == "IOSAcceptedOutputHistoryOwnershipProof(redacted)"
        )
        #expect(
            try await outboxFixture.store.clearPendingHistory(
                authorization: outboxAuthorization,
                ownershipProof: outboxProof
            ) == .removed
        )
        #expect(outboxFixture.journal.currentRecord == nil)
    }

    @Test func retainedRowProofAtomicallyReplacesPendingHistory() async throws {
        let rowFixture = AcceptedDeliveryStoreFixture()
        let (_, rowAuthorization) = try await rowFixture.acceptAndAuthorize()
        let rowProof = IOSAcceptedOutputHistoryOwnershipProof(
            retainedRowReceipt: try await rowFixture.retainedRowReceipt(
                for: rowAuthorization
            )
        )
        let rowReplacement = rowFixture.preparation(
            rawAcceptedText: "row replacement"
        )
        let replacedFromRow = try await rowFixture.store.replacePendingHistory(
            with: rowReplacement,
            authorization: rowAuthorization,
            ownershipProof: rowProof
        )
        #expect(replacedFromRow.hasSameAcceptance(as: rowReplacement))
        #expect(rowFixture.journal.removedRecords.isEmpty)
    }

    @Test func proofBoundReplacementUncertaintyRequiresExactPair() async throws {
        for commitWasVisible in [true, false] {
            let fixture = AcceptedDeliveryStoreFixture()
            let (_, authorization) = try await fixture.acceptAndAuthorize()
            let exactProof = IOSAcceptedOutputHistoryOwnershipProof(
                outboxReceipt: try await fixture.outboxReceipt(
                    for: authorization
                )
            )
            let foreignProof = IOSAcceptedOutputHistoryOwnershipProof(
                retainedRowReceipt: try await fixture.retainedRowReceipt(
                    for: authorization
                )
            )
            let replacement = fixture.preparation(
                rawAcceptedText: commitWasVisible
                    ? "visible replacement"
                    : "invisible replacement"
            )
            fixture.journal.failNextReplace(
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )

            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                try await fixture.store.replacePendingHistory(
                    with: replacement,
                    authorization: authorization,
                    ownershipProof: exactProof
                )
            }
            #expect(
                fixture.journal.currentRecord?.hasSameAcceptance(
                    as: replacement
                ) == commitWasVisible
            )
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                try await fixture.store.accept(replacement)
            }
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                try await fixture.store.replacePendingHistory(
                    with: replacement,
                    authorization: authorization,
                    ownershipProof: foreignProof
                )
            }

            if commitWasVisible {
                fixture.clock.wall = try #require(
                    fixture.journal.currentRecord
                ).expiresAt
            }
            let confirmed = try await fixture.store.replacePendingHistory(
                with: replacement,
                authorization: authorization,
                ownershipProof: exactProof
            )
            #expect(confirmed.hasSameAcceptance(as: replacement))
        }
    }

    @Test func missingCurrentClearsReplacementUncertaintyGate() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (_, authorization) = try await fixture.acceptAndAuthorize()
        let ownershipProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await fixture.outboxReceipt(
                for: authorization
            )
        )
        let uncertainReplacement = fixture.preparation(
            rawAcceptedText: "missing replacement"
        )
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.replacePendingHistory(
                with: uncertainReplacement,
                authorization: authorization,
                ownershipProof: ownershipProof
            )
        }
        #expect(
            try await fixture.makeStore().clearPendingHistory(
                authorization: authorization,
                ownershipProof: ownershipProof
            ) == .removed
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await fixture.store.replacePendingHistory(
                with: uncertainReplacement,
                authorization: authorization,
                ownershipProof: ownershipProof
            )
        }

        let replacement = fixture.preparation(
            rawAcceptedText: "after missing replacement"
        )
        let accepted = try await fixture.store.accept(replacement)
        #expect(accepted.hasSameAcceptance(as: replacement))
    }

    @Test func differentWinnerClearsReplacementUncertaintyGate() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (_, authorization) = try await fixture.acceptAndAuthorize()
        let ownershipProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await fixture.outboxReceipt(
                for: authorization
            )
        )
        let uncertainReplacement = fixture.preparation(
            rawAcceptedText: "losing replacement"
        )
        let winningReplacement = fixture.preparation(
            rawAcceptedText: "winning replacement"
        )
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.replacePendingHistory(
                with: uncertainReplacement,
                authorization: authorization,
                ownershipProof: ownershipProof
            )
        }
        let winner = try await fixture.makeStore().replacePendingHistory(
            with: winningReplacement,
            authorization: authorization,
            ownershipProof: ownershipProof
        )
        #expect(winner.hasSameAcceptance(as: winningReplacement))
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await fixture.store.replacePendingHistory(
                with: uncertainReplacement,
                authorization: authorization,
                ownershipProof: ownershipProof
            )
        }

        let recovered = try await fixture.store.accept(winningReplacement)
        #expect(recovered.hasSameAcceptance(as: winningReplacement))
    }

    @Test func specialReplacementReplayRequiresExactAuthorizationSnapshot() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (_, authorization) = try await fixture.acceptAndAuthorize()
        let ownershipProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await fixture.outboxReceipt(
                for: authorization
            )
        )
        let acceptedText = try #require(authorization.record.acceptedText)
        let replay = fixture.preparation(
            deliveryID: authorization.record.deliveryID,
            sessionID: authorization.record.sessionID,
            attemptID: authorization.record.attemptID,
            transcriptID: authorization.record.transcriptID,
            rawAcceptedText: acceptedText,
            keepLatestResult: authorization.record.keepLatestResult,
            historyWrite: authorization.record.historyWrite
        )
        let refreshed = try await fixture.makeStore()
            .authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: authorization.record
                )
            )
        #expect(refreshed != authorization)

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await fixture.store.replacePendingHistory(
                with: replay,
                authorization: authorization,
                ownershipProof: ownershipProof
            )
        }
        #expect(fixture.journal.currentRecord == authorization.record)

        let recovered = try await fixture.store.accept(replay)
        #expect(recovered.hasSameAcceptance(as: replay))
    }

    @Test func specialReplacementReplayDoesNotSkipKeepLatestRevocation() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (_, authorization) = try await fixture.acceptAndAuthorize()
        let ownershipProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await fixture.outboxReceipt(
                for: authorization
            )
        )
        let retained = fixture.preparation(
            rawAcceptedText: "same accepted replacement",
            keepLatestResult: true
        )
        let revocation = fixture.preparation(
            deliveryID: retained.deliveryID,
            sessionID: retained.sessionID,
            attemptID: retained.attemptID,
            transcriptID: retained.transcriptID,
            rawAcceptedText: retained.acceptedText,
            keepLatestResult: false
        )
        let firstStore = fixture.makeStore()
        let secondStore = fixture.makeStore()

        let first = try await firstStore.replacePendingHistory(
            with: retained,
            authorization: authorization,
            ownershipProof: ownershipProof
        )
        #expect(first.keepLatestResult)
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await secondStore.replacePendingHistory(
                with: revocation,
                authorization: authorization,
                ownershipProof: ownershipProof
            )
        }
        #expect(fixture.journal.currentRecord?.keepLatestResult == true)

        let weakened = try await fixture.store.accept(revocation)
        #expect(!weakened.keepLatestResult)
    }

    @Test func invisibleReplacementRevalidatesSealedIntentTime() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (accepted, authorization) = try await fixture.acceptAndAuthorize()
        let ownershipProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await fixture.outboxReceipt(
                for: authorization
            )
        )
        let firstAttempt = accepted.updatedAt.addingTimeInterval(10)
        let replacement = fixture.preparation(
            rawAcceptedText: "temporally sealed replacement"
        )
        fixture.clock.wall = firstAttempt
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.replacePendingHistory(
                with: replacement,
                authorization: authorization,
                ownershipProof: ownershipProof
            )
        }
        fixture.clock.wall = accepted.updatedAt.addingTimeInterval(5)
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        ) {
            try await fixture.store.replacePendingHistory(
                with: replacement,
                authorization: authorization,
                ownershipProof: ownershipProof
            )
        }
        #expect(fixture.journal.currentRecord == authorization.record)
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.accept(
                fixture.preparation(rawAcceptedText: "blocked by rollback")
            )
        }

        fixture.clock.wall = firstAttempt.addingTimeInterval(1)
        let recovered = try await fixture.store.replacePendingHistory(
            with: replacement,
            authorization: authorization,
            ownershipProof: ownershipProof
        )
        #expect(recovered.hasSameAcceptance(as: replacement))
        #expect(recovered.createdAt == firstAttempt)

        let expiryFixture = AcceptedDeliveryStoreFixture()
        let (expiryAccepted, expiryAuthorization) = try await expiryFixture
            .acceptAndAuthorize()
        let expiryProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await expiryFixture.outboxReceipt(
                for: expiryAuthorization
            )
        )
        let expiryAttempt = expiryAccepted.updatedAt.addingTimeInterval(10)
        let expiryReplacement = expiryFixture.preparation(
            rawAcceptedText: "expiring sealed replacement"
        )
        expiryFixture.clock.wall = expiryAttempt
        expiryFixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await expiryFixture.store.replacePendingHistory(
                with: expiryReplacement,
                authorization: expiryAuthorization,
                ownershipProof: expiryProof
            )
        }
        expiryFixture.clock.wall = expiryAttempt.addingTimeInterval(86_400)
        await #expect(throws: IOSAcceptedOutputDeliveryError.expired) {
            try await expiryFixture.store.replacePendingHistory(
                with: expiryReplacement,
                authorization: expiryAuthorization,
                ownershipProof: expiryProof
            )
        }
        #expect(
            try await expiryFixture.store.removeExpired(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: expiryAuthorization.record
                )
            ) == .removed
        )
    }

    @Test func proofBoundClearUncertaintyRequiresExactPair() async throws {
        for commitWasVisible in [true, false] {
            let fixture = AcceptedDeliveryStoreFixture()
            let (_, authorization) = try await fixture.acceptAndAuthorize()
            let exactProof = IOSAcceptedOutputHistoryOwnershipProof(
                outboxReceipt: try await fixture.outboxReceipt(
                    for: authorization
                )
            )
            let foreignProof = IOSAcceptedOutputHistoryOwnershipProof(
                retainedRowReceipt: try await fixture.retainedRowReceipt(
                    for: authorization
                )
            )
            fixture.journal.failNextReplace(
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )

            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                try await fixture.store.clearPendingHistory(
                    authorization: authorization,
                    ownershipProof: exactProof
                )
            }
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                try await fixture.store.clearPendingHistory(
                    authorization: authorization,
                    ownershipProof: foreignProof
                )
            }
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                try await fixture.store.accept(
                    fixture.preparation(rawAcceptedText: "blocked clear")
                )
            }
            #expect(
                try await fixture.store.clearPendingHistory(
                    authorization: authorization,
                    ownershipProof: exactProof
                ) == .removed
            )
        }

        let removalFixture = AcceptedDeliveryStoreFixture()
        let (_, removalAuthorization) = try await removalFixture
            .acceptAndAuthorize()
        let exactProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await removalFixture.outboxReceipt(
                for: removalAuthorization
            )
        )
        let foreignProof = IOSAcceptedOutputHistoryOwnershipProof(
            retainedRowReceipt: try await removalFixture.retainedRowReceipt(
                for: removalAuthorization
            )
        )
        removalFixture.journal.removeError = .removalCommitUncertain
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.removalCommitUncertain
        ) {
            try await removalFixture.store.clearPendingHistory(
                authorization: removalAuthorization,
                ownershipProof: exactProof
            )
        }
        removalFixture.journal.removeError = nil
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.removalCommitUncertain
        ) {
            try await removalFixture.store.clearPendingHistory(
                authorization: removalAuthorization,
                ownershipProof: foreignProof
            )
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await removalFixture.store.accept(
                removalFixture.preparation(
                    rawAcceptedText: "blocked removal uncertainty"
                )
            )
        }
        #expect(
            try await removalFixture.store.clearPendingHistory(
                authorization: removalAuthorization,
                ownershipProof: exactProof
            ) == .removed
        )
    }

    @Test func invisibleClearRevalidatesSealedTombstoneTime() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (accepted, authorization) = try await fixture.acceptAndAuthorize()
        let ownershipProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await fixture.outboxReceipt(
                for: authorization
            )
        )
        let firstAttempt = accepted.updatedAt.addingTimeInterval(10)
        fixture.clock.wall = firstAttempt
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.clearPendingHistory(
                authorization: authorization,
                ownershipProof: ownershipProof
            )
        }
        fixture.clock.wall = accepted.updatedAt.addingTimeInterval(5)
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        ) {
            try await fixture.store.clearPendingHistory(
                authorization: authorization,
                ownershipProof: ownershipProof
            )
        }
        #expect(fixture.journal.currentRecord == authorization.record)
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.accept(
                fixture.preparation(rawAcceptedText: "blocked clear rollback")
            )
        }

        fixture.clock.wall = firstAttempt.addingTimeInterval(1)
        #expect(
            try await fixture.store.clearPendingHistory(
                authorization: authorization,
                ownershipProof: ownershipProof
            ) == .removed
        )

        let rollbackFixture = AcceptedDeliveryStoreFixture()
        let (rollbackAccepted, rollbackAuthorization) = try await rollbackFixture
            .acceptAndAuthorize()
        let rollbackProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await rollbackFixture.outboxReceipt(
                for: rollbackAuthorization
            )
        )
        rollbackFixture.clock.wall = rollbackAccepted.createdAt
            .addingTimeInterval(-1)
        rollbackFixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await rollbackFixture.store.clearPendingHistory(
                authorization: rollbackAuthorization,
                ownershipProof: rollbackProof
            )
        }
        #expect(
            try await rollbackFixture.store.clearPendingHistory(
                authorization: rollbackAuthorization,
                ownershipProof: rollbackProof
            ) == .removed
        )

        let expiryFixture = AcceptedDeliveryStoreFixture()
        let (_, expiryAuthorization) = try await expiryFixture
            .acceptAndAuthorize()
        let expiryProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await expiryFixture.outboxReceipt(
                for: expiryAuthorization
            )
        )
        expiryFixture.clock.wall = expiryAuthorization.record.updatedAt
            .addingTimeInterval(10)
        expiryFixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await expiryFixture.store.clearPendingHistory(
                authorization: expiryAuthorization,
                ownershipProof: expiryProof
            )
        }
        expiryFixture.clock.wall = expiryAuthorization.record.expiresAt
        await #expect(throws: IOSAcceptedOutputDeliveryError.expired) {
            try await expiryFixture.store.clearPendingHistory(
                authorization: expiryAuthorization,
                ownershipProof: expiryProof
            )
        }
        #expect(
            try await expiryFixture.store.removeExpired(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: expiryAuthorization.record
                )
            ) == .removed
        )
    }

    @Test func terminalHistoryStatesAllowOrdinaryReplacementWithoutProof() async throws {
        let committedFixture = AcceptedDeliveryStoreFixture()
        let (_, committedAuthorization) = try await committedFixture
            .acceptAndAuthorize()
        let committedReceipt = try await committedFixture.retainedRowReceipt(
            for: committedAuthorization
        )
        _ = try await committedFixture.store.commitHistoryWrite(
            authorization: committedAuthorization,
            rowReceipt: committedReceipt
        )
        let afterCommit = committedFixture.preparation(
            rawAcceptedText: "after commit"
        )
        #expect(
            try await committedFixture.store.accept(afterCommit)
                .hasSameAcceptance(as: afterCommit)
        )

        let cancelledFixture = AcceptedDeliveryStoreFixture()
        let (_, cancelledAuthorization) = try await cancelledFixture
            .acceptAndAuthorize()
        _ = try await cancelledFixture.store.cancelHistoryWrite(
            authorization: cancelledAuthorization,
            policyInvalidationReceipt: try await cancelledFixture.policyReceipt(
                generation: 2
            )
        )
        let afterCancel = cancelledFixture.preparation(
            rawAcceptedText: "after cancel"
        )
        #expect(
            try await cancelledFixture.store.accept(afterCancel)
                .hasSameAcceptance(as: afterCancel)
        )
    }

    @Test func nonOwnershipReceiptsCannotClearPendingHistory() async throws {
        let droppedFixture = AcceptedDeliveryStoreFixture()
        let (droppedAccepted, droppedAuthorization) = try await droppedFixture
            .acceptAndAuthorize()
        let droppedProof = IOSAcceptedOutputHistoryOwnershipProof(
            retainedRowReceipt: try await droppedFixture.notRetainedRowReceipt(
                for: droppedAuthorization
            )
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await droppedFixture.store.clearPendingHistory(
                authorization: droppedAuthorization,
                ownershipProof: droppedProof
            )
        }
        #expect(droppedFixture.journal.currentRecord == droppedAccepted)

        let observationFixture = AcceptedDeliveryStoreFixture()
        let (observationAccepted, observationAuthorization) =
            try await observationFixture.acceptAndAuthorize()
        let observationProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await observationFixture
                .observationOutboxReceipt(for: observationAuthorization)
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await observationFixture.store.clearPendingHistory(
                authorization: observationAuthorization,
                ownershipProof: observationProof
            )
        }
        #expect(observationFixture.journal.currentRecord == observationAccepted)
    }

    @Test func ownershipProofPinsDeliveryAuthorizationAndExactUTF8() async throws {
        let staleFixture = AcceptedDeliveryStoreFixture()
        let (staleAccepted, firstAuthorization) = try await staleFixture
            .acceptAndAuthorize()
        let staleProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await staleFixture.outboxReceipt(
                for: firstAuthorization
            )
        )
        let refreshedAuthorization = try await staleFixture.makeStore()
            .authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: staleAccepted
                )
            )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await staleFixture.store.clearPendingHistory(
                authorization: refreshedAuthorization,
                ownershipProof: staleProof
            )
        }

        let targetFixture = AcceptedDeliveryStoreFixture()
        let (_, targetAuthorization) = try await targetFixture
            .acceptAndAuthorize()
        let foreignFixture = AcceptedDeliveryStoreFixture()
        let (_, foreignAuthorization) = try await foreignFixture
            .acceptAndAuthorize()
        let foreignProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await foreignFixture.outboxReceipt(
                for: foreignAuthorization
            )
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await targetFixture.store.clearPendingHistory(
                authorization: targetAuthorization,
                ownershipProof: foreignProof
            )
        }

        let unicodeFixture = AcceptedDeliveryStoreFixture()
        let unicodePreparation = unicodeFixture.preparation(
            rawAcceptedText: "e\u{301}",
            historyWrite: try unicodeFixture.historyWrite()
        )
        let (_, unicodeAuthorization) = try await unicodeFixture
            .acceptAndAuthorize(unicodePreparation)
        let composedFixture = AcceptedDeliveryStoreFixture()
        let (_, composedAuthorization) = try await composedFixture
            .acceptAndAuthorize(
                composedFixture.preparation(
                deliveryID: unicodePreparation.deliveryID,
                sessionID: unicodePreparation.sessionID,
                attemptID: unicodePreparation.attemptID,
                transcriptID: unicodePreparation.transcriptID,
                rawAcceptedText: "é",
                historyWrite: try composedFixture.historyWrite()
                )
            )
        let composedRowReceipt = try await composedFixture.rowReceipt(
            for: try await composedFixture.outboxReceipt(
                for: composedAuthorization
            )
        )
        let composedProof = IOSAcceptedOutputHistoryOwnershipProof(
            retainedRowReceipt: composedRowReceipt
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await unicodeFixture.store.clearPendingHistory(
                authorization: unicodeAuthorization,
                ownershipProof: composedProof
            )
        }
    }

    @Test func ownershipClearAllowsRollbackButReplacementAndBridgeRemainIndependent() async throws {
        let clearFixture = AcceptedDeliveryStoreFixture()
        let (clearAccepted, clearAuthorization) = try await clearFixture
            .acceptAndAuthorize()
        let clearProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await clearFixture.outboxReceipt(
                for: clearAuthorization
            )
        )
        clearFixture.clock.wall = clearAccepted.createdAt.addingTimeInterval(-1)
        #expect(
            try await clearFixture.store.clearPendingHistory(
                authorization: clearAuthorization,
                ownershipProof: clearProof
            ) == .removed
        )
        #expect(
            clearFixture.journal.removedRecords.last?.updatedAt
                == clearAccepted.updatedAt
        )

        let replaceFixture = AcceptedDeliveryStoreFixture()
        let (replaceAccepted, replaceAuthorization) = try await replaceFixture
            .acceptAndAuthorize()
        let replaceProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await replaceFixture.outboxReceipt(
                for: replaceAuthorization
            )
        )
        replaceFixture.clock.wall = replaceAccepted.createdAt.addingTimeInterval(-1)
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        ) {
            try await replaceFixture.store.replacePendingHistory(
                with: replaceFixture.preparation(rawAcceptedText: "replacement"),
                authorization: replaceAuthorization,
                ownershipProof: replaceProof
            )
        }

        let bridgeFixture = AcceptedDeliveryStoreFixture()
        let bridgePreparation = bridgeFixture.preparation(
            historyWrite: try bridgeFixture.historyWrite()
        )
        let bridgeRecord = try bridgeFixture.record(
            preparation: bridgePreparation,
            publicationGeneration: 1
        )
        bridgeFixture.journal.install(bridgeRecord)
        let bridgeAuthorization = try await bridgeFixture.store
            .authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: bridgeRecord
                )
            )
        let bridgeProof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await bridgeFixture.outboxReceipt(
                for: bridgeAuthorization
            )
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.bridgeRevocationRequired
        ) {
            try await bridgeFixture.store.clearPendingHistory(
                authorization: bridgeAuthorization,
                ownershipProof: bridgeProof
            )
        }
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.bridgeRevocationRequired
        ) {
            try await bridgeFixture.store.replacePendingHistory(
                with: bridgeFixture.preparation(rawAcceptedText: "replacement"),
                authorization: bridgeAuthorization,
                ownershipProof: bridgeProof
            )
        }
    }

    @Test func twoStoresCannotBothReplaceOneProofBoundPendingSlot() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (_, authorization) = try await fixture.acceptAndAuthorize()
        let proof = IOSAcceptedOutputHistoryOwnershipProof(
            outboxReceipt: try await fixture.outboxReceipt(for: authorization)
        )
        let firstStore = fixture.makeStore()
        let secondStore = fixture.makeStore()
        let firstPreparation = fixture.preparation(rawAcceptedText: "first")
        let secondPreparation = fixture.preparation(rawAcceptedText: "second")

        let first = try await firstStore.replacePendingHistory(
            with: firstPreparation,
            authorization: authorization,
            ownershipProof: proof
        )
        #expect(first.hasSameAcceptance(as: firstPreparation))

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await secondStore.replacePendingHistory(
                with: secondPreparation,
                authorization: authorization,
                ownershipProof: proof
            )
        }
        #expect(
            fixture.journal.currentRecord?.hasSameAcceptance(
                as: firstPreparation
            ) == true
        )
    }

    @Test func expiryAbandonsPendingHistoryAndRemovesWithoutTombstone() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let accepted = try await fixture.store.accept(
            fixture.preparation(historyWrite: try fixture.historyWrite())
        )
        fixture.clock.wall = accepted.expiresAt

        #expect(
            try await fixture.store.removeExpired(
                expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
            ) == .removed
        )
        #expect(fixture.journal.currentRecord == nil)
        #expect(fixture.journal.removedRecords.last?.deliveryState == .pending)
        #expect(
            fixture.journal.replacementRecords.last?.revision
                == accepted.revision
        )
    }

    @Test func replacementPreservesOldBytesBeforeRenameAndRequiresRetryAfterUncertainty() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let old = try await fixture.store.accept(fixture.preparation())
        let replacement = fixture.preparation(rawAcceptedText: "new result")

        fixture.journal.failNextReplace(
            with: .writeFailed,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.writeFailed) {
            try await fixture.store.accept(replacement)
        }
        #expect(fixture.journal.currentRecord == old)

        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.accept(replacement)
        }
        let visible = try #require(fixture.journal.currentRecord)
        #expect(visible.deliveryID == replacement.deliveryID)
        #expect(visible.publicationGeneration == 0)

        let confirmed = try await fixture.store.accept(replacement)
        #expect(confirmed == visible)
        #expect(fixture.journal.replacementRecords.last == visible)
    }

    @Test func staleActorsCannotApplyDifferentRevisionNMutations() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let accepted = try await fixture.store.accept(
            fixture.preparation(
                keepLatestResult: true,
                historyWrite: try fixture.historyWrite()
            )
        )
        let otherStore = fixture.makeStore()
        let expectation = IOSAcceptedOutputDeliveryExpectation(record: accepted)
        let authorization = try await fixture.store
            .authorizePendingHistoryWrite(expected: expectation)
        let invalidation = try await fixture.policyReceipt(generation: 2)

        let disableTask = Task {
            try await fixture.store.disableKeepLatestResult(
                expected: expectation
            )
        }
        let cancelTask = Task {
            try await otherStore.cancelHistoryWrite(
                authorization: authorization,
                policyInvalidationReceipt: invalidation
            )
        }
        let results = await [disableTask.result, cancelTask.result]
        let successCount = results.filter {
            if case .success = $0 { return true }
            return false
        }.count
        #expect(successCount == 1)
        #expect(fixture.journal.currentRecord?.revision == 2)
    }

    @Test func revisionOverflowFailsWithoutWriting() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let preparation = fixture.preparation(keepLatestResult: true)
        let record = try fixture.record(
            preparation: preparation,
            revision: Int64.max
        )
        fixture.journal.install(record)

        await #expect(throws: IOSAcceptedOutputDeliveryError.revisionOverflow) {
            try await fixture.store.disableKeepLatestResult(
                expected: IOSAcceptedOutputDeliveryExpectation(record: record)
            )
        }
        #expect(fixture.journal.currentRecord == record)
    }

    @Test func generationOneOperationsFailClosedWithoutBridgeCheckpoint() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let preparation = fixture.preparation()
        let record = try fixture.record(
            preparation: preparation,
            publicationGeneration: 1
        )
        fixture.journal.install(record)

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.bridgeRevocationRequired
        ) {
            try await fixture.store.clear(
                expected: IOSAcceptedOutputDeliveryExpectation(record: record)
            )
        }
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.bridgeRevocationRequired
        ) {
            try await fixture.store.accept(
                fixture.preparation(rawAcceptedText: "new")
            )
        }
        #expect(fixture.journal.currentRecord == record)
    }

    @Test func opaqueDiscardFailsClosedBeforeExactRemoval() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        fixture.journal.installOpaque()

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.bridgeRevocationRequired
        ) {
            try await fixture.store.discardUnreadableLocalResult()
        }
        #expect(fixture.journal.opaquePresent)
        #expect(fixture.journal.opaqueRemoveCount == 0)
    }

    @Test func stagingMaintenanceIsBoundedReportFromStrictLayer() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        fixture.journal.maintenanceReport = IOSStrictProtectedRecordMaintenanceReport(
            inspectedEntryCount: 32,
            inspectedByteCount: 4_194_304,
            removedFileCount: 2,
            removedByteCount: 512,
            reachedLimit: true
        )

        let report = try await fixture.store.performStagingMaintenance()
        #expect(report.inspectedEntryCount == 32)
        #expect(report.inspectedByteCount == 4_194_304)
        #expect(report.removedFileCount == 2)
        #expect(report.removedByteCount == 512)
        #expect(report.reachedLimit)
    }

    @Test func removalUncertaintyDoesNotAuthorizeAnyFurtherAction() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let accepted = try await fixture.store.accept(fixture.preparation())
        fixture.journal.removeError = .removalCommitUncertain

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.removalCommitUncertain
        ) {
            try await fixture.store.clear(
                expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
            )
        }
        #expect(fixture.journal.currentRecord?.deliveryState == .discarded)
        #expect(fixture.journal.currentRecord?.acceptedText == nil)
    }
}

private final class AcceptedDeliveryTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedWall = Date(timeIntervalSince1970: 1_800_000_000)
    private var storedWallReadCount = 0
    private var storedWallReadOverrides: [Date] = []
    private var storedMonotonicNanoseconds: UInt64 = 0

    var wall: Date {
        get {
            lock.withLock {
                storedWallReadCount += 1
                if !storedWallReadOverrides.isEmpty {
                    return storedWallReadOverrides.removeFirst()
                }
                return storedWall
            }
        }
        set { lock.withLock { storedWall = newValue } }
    }

    var wallReadCount: Int {
        lock.withLock { storedWallReadCount }
    }

    func resetWallReadCount() {
        lock.withLock { storedWallReadCount = 0 }
    }

    func enqueueWallReadOverrides(_ values: [Date]) {
        lock.withLock { storedWallReadOverrides.append(contentsOf: values) }
    }

    var monotonicNanoseconds: UInt64 {
        get { lock.withLock { storedMonotonicNanoseconds } }
        set { lock.withLock { storedMonotonicNanoseconds = newValue } }
    }
}

private final class AcceptedDeliveryFakeJournal:
    IOSAcceptedOutputDeliveryJournalStoring,
    @unchecked Sendable {
    private struct ReplacementFailure {
        let error: IOSAcceptedOutputDeliveryError
        let commitBeforeThrowing: Bool
    }

    private let lock = NSLock()
    private var snapshot: IOSAcceptedOutputDeliveryJournalSnapshot?
    private var nextToken: UInt64 = 1
    private var createFailure: ReplacementFailure?
    private var replacementFailure: ReplacementFailure?
    private var loadFailure: IOSAcceptedOutputDeliveryError?
    private var storedEvents: [String] = []
    private var storedReplacementRecords: [IOSAcceptedOutputDeliveryRecord] = []
    private var storedRemovedRecords: [IOSAcceptedOutputDeliveryRecord] = []
    private var storedOpaqueRevision: IOSStrictProtectedRecordFileRevision?
    private var storedOpaqueRemoveCount = 0

    var removeError: IOSAcceptedOutputDeliveryError?
    var maintenanceReport = IOSStrictProtectedRecordMaintenanceReport.empty

    var events: [String] { lock.withLock { storedEvents } }
    var replacementRecords: [IOSAcceptedOutputDeliveryRecord] {
        lock.withLock { storedReplacementRecords }
    }
    var removedRecords: [IOSAcceptedOutputDeliveryRecord] {
        lock.withLock { storedRemovedRecords }
    }
    var currentRecord: IOSAcceptedOutputDeliveryRecord? {
        lock.withLock { snapshot?.record }
    }
    var opaquePresent: Bool {
        lock.withLock { storedOpaqueRevision != nil }
    }
    var opaqueRemoveCount: Int {
        lock.withLock { storedOpaqueRemoveCount }
    }

    func resetEvents() {
        lock.withLock { storedEvents = [] }
    }

    func failNextReplace(
        with error: IOSAcceptedOutputDeliveryError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            replacementFailure = ReplacementFailure(
                error: error,
                commitBeforeThrowing: commitBeforeThrowing
            )
        }
    }

    func failNextCreate(
        with error: IOSAcceptedOutputDeliveryError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            createFailure = ReplacementFailure(
                error: error,
                commitBeforeThrowing: commitBeforeThrowing
            )
        }
    }

    func failLoads(with error: IOSAcceptedOutputDeliveryError?) {
        lock.withLock { loadFailure = error }
    }

    func install(_ record: IOSAcceptedOutputDeliveryRecord) {
        lock.withLock {
            snapshot = IOSAcceptedOutputDeliveryJournalSnapshot(
                record: record,
                fileRevision: makeRevisionLocked()
            )
        }
    }

    func installOpaque() {
        lock.withLock { storedOpaqueRevision = makeRevisionLocked() }
    }

    func load() throws -> IOSAcceptedOutputDeliveryJournalSnapshot? {
        try lock.withLock {
            storedEvents.append("load")
            if let loadFailure { throw loadFailure }
            return snapshot
        }
    }

    func loadOpaque() throws -> IOSAcceptedOutputDeliveryOpaqueSnapshot? {
        lock.withLock {
            storedOpaqueRevision.map(
                IOSAcceptedOutputDeliveryOpaqueSnapshot.init(fileRevision:)
            )
        }
    }

    func create(
        _ record: IOSAcceptedOutputDeliveryRecord
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        try lock.withLock {
            storedEvents.append("create")
            guard snapshot == nil else {
                throw IOSAcceptedOutputDeliveryError.slotOccupied
            }
            if let failure = createFailure {
                createFailure = nil
                if failure.commitBeforeThrowing {
                    snapshot = IOSAcceptedOutputDeliveryJournalSnapshot(
                        record: record,
                        fileRevision: makeRevisionLocked()
                    )
                }
                throw failure.error
            }
            let created = IOSAcceptedOutputDeliveryJournalSnapshot(
                record: record,
                fileRevision: makeRevisionLocked()
            )
            snapshot = created
            return created
        }
    }

    func replace(
        _ record: IOSAcceptedOutputDeliveryRecord,
        expected: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        try lock.withLock {
            storedEvents.append("replace:\(record.revision)")
            storedReplacementRecords.append(record)
            guard snapshot?.fileRevision == expected.fileRevision else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            if let failure = replacementFailure {
                replacementFailure = nil
                if failure.commitBeforeThrowing {
                    snapshot = IOSAcceptedOutputDeliveryJournalSnapshot(
                        record: record,
                        fileRevision: makeRevisionLocked()
                    )
                }
                throw failure.error
            }
            let replacement = IOSAcceptedOutputDeliveryJournalSnapshot(
                record: record,
                fileRevision: makeRevisionLocked()
            )
            snapshot = replacement
            return replacement
        }
    }

    func remove(
        expected: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws {
        try lock.withLock {
            guard snapshot?.fileRevision == expected.fileRevision else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            storedRemovedRecords.append(expected.record)
            if let removeError { throw removeError }
            snapshot = nil
        }
    }

    func removeOpaque(
        expected: IOSAcceptedOutputDeliveryOpaqueSnapshot
    ) throws {
        try lock.withLock {
            guard storedOpaqueRevision == expected.fileRevision else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            storedOpaqueRevision = nil
            storedOpaqueRemoveCount += 1
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

private final class AcceptedDeliveryStoreFixture: @unchecked Sendable {
    let journal = AcceptedDeliveryFakeJournal()
    let clock = AcceptedDeliveryTestClock()
    lazy var store = makeStore()

    func makeStore() -> IOSAcceptedOutputDeliveryStore {
        IOSAcceptedOutputDeliveryStore(
            journal: journal,
            now: { [clock] in clock.wall },
            monotonicNowNanoseconds: {
                [clock] in clock.monotonicNanoseconds
            }
        )
    }

    func historyWrite(
        policyGeneration: Int64 = 1,
        transcriptionModel: String = "model",
        transcriptionLanguageCode: String? = "en",
        durationMilliseconds: Int64? = 1_000
    ) throws -> IOSAcceptedOutputHistoryWrite {
        try IOSAcceptedOutputHistoryWrite(
            policyGeneration: policyGeneration,
            transcriptionModel: transcriptionModel,
            transcriptionLanguageCode: transcriptionLanguageCode,
            durationMilliseconds: durationMilliseconds
        )
    }

    func policyReceipt(
        generation: Int64 = 1,
        enabled: Bool = true,
        fileRevisionToken: UInt64 = 1
    ) async throws -> IOSHistoryPolicyReceipt {
        let state = try IOSHistoryPolicyState(
            revision: generation,
            historyEnabled: enabled,
            policyGeneration: generation
        )
        let journal = AcceptedDeliveryPolicyFakeJournal(
            state: state,
            fileRevisionToken: fileRevisionToken
        )
        return try await IOSHistoryPolicyStore(journal: journal).confirm(
            expected: IOSHistoryPolicyExpectation(state: state)
        )
    }

    func retainedRowReceipt(
        for authorization: IOSAcceptedOutputDeliveryAuthorization,
        fileRevisionToken: UInt64 = 1
    ) async throws -> IOSAcceptedHistoryRowReceipt {
        let policy = try await policyReceipt(
            generation: try #require(
                authorization.record.historyWrite
            ).policyGeneration
        )
        return try await IOSAcceptedHistoryStore(
            journal: AcceptedDeliveryHistoryFakeJournal(
                initialFileRevisionToken: fileRevisionToken
            ),
            now: { [clock] in clock.wall }
        ).decideUpsert(
            delivery: authorization,
            policy: policy
        )
    }

    func notRetainedRowReceipt(
        for authorization: IOSAcceptedOutputDeliveryAuthorization
    ) async throws -> IOSAcceptedHistoryRowReceipt {
        let marker = try #require(authorization.record.historyWrite)
        let entries = try (0..<20).map { offset in
            try IOSAcceptedHistoryEntry(
                deliveryID: UUID(),
                transcriptID: UUID(),
                acceptedText: "newer \(offset)",
                outputIntent: .standard,
                createdAt: authorization.record.createdAt.addingTimeInterval(
                    Double(20 - offset)
                ),
                policyGeneration: marker.policyGeneration,
                transcriptionModel: marker.transcriptionModel,
                transcriptionLanguageCode: marker.transcriptionLanguageCode,
                durationMilliseconds: marker.durationMilliseconds,
                cachedAudioRelativeIdentifier: nil
            )
        }
        let envelope = try IOSAcceptedHistoryEnvelope(
            revision: 1,
            entries: IOSAcceptedHistoryValidation.sorted(entries)
        )
        let journal = AcceptedDeliveryHistoryFakeJournal(envelope: envelope)
        let policy = try await policyReceipt(
            generation: marker.policyGeneration
        )
        return try await IOSAcceptedHistoryStore(
            journal: journal,
            now: {
                authorization.record.createdAt.addingTimeInterval(100)
            }
        ).decideUpsert(
            delivery: authorization,
            policy: policy
        )
    }

    func outboxReceipt(
        for authorization: IOSAcceptedOutputDeliveryAuthorization
    ) async throws -> IOSAcceptedHistoryOutboxReceipt {
        let marker = try #require(authorization.record.historyWrite)
        let policy = try await policyReceipt(
            generation: marker.policyGeneration
        )
        return try await IOSAcceptedHistoryOutboxStore(
            journal: AcceptedDeliveryOutboxFakeJournal(),
            now: { [clock] in clock.wall }
        ).transfer(
            delivery: authorization,
            policy: policy
        )
    }

    func observationOutboxReceipt(
        for authorization: IOSAcceptedOutputDeliveryAuthorization
    ) async throws -> IOSAcceptedHistoryOutboxReceipt {
        let marker = try #require(authorization.record.historyWrite)
        let policy = try await policyReceipt(
            generation: marker.policyGeneration
        )
        let journal = AcceptedDeliveryOutboxFakeJournal()
        _ = try await IOSAcceptedHistoryOutboxStore(
            journal: journal,
            now: { [clock] in clock.wall }
        ).transfer(
            delivery: authorization,
            policy: policy
        )
        let relaunched = IOSAcceptedHistoryOutboxStore(
            journal: journal,
            now: { [clock] in clock.wall }
        )
        let observations = try #require(try await relaunched.observe())
        return try await relaunched.confirmMembership(
            observation: try #require(observations.first)
        )
    }

    func rowReceipt(
        for outbox: IOSAcceptedHistoryOutboxReceipt,
        policyGeneration: Int64 = 1
    ) async throws -> IOSAcceptedHistoryRowReceipt {
        let policy = try await policyReceipt(generation: policyGeneration)
        return try await IOSAcceptedHistoryStore(
            journal: AcceptedDeliveryHistoryFakeJournal(),
            now: { [clock] in clock.wall }
        ).decideUpsert(outbox: outbox, policy: policy)
    }

    func acceptAndAuthorize(
        _ suppliedPreparation: IOSAcceptedOutputDeliveryPreparation? = nil
    ) async throws -> (
        accepted: IOSAcceptedOutputDeliveryRecord,
        authorization: IOSAcceptedOutputDeliveryAuthorization
    ) {
        let preparation = try suppliedPreparation
            ?? self.preparation(historyWrite: historyWrite())
        let accepted = try await store.accept(preparation)
        let authorization = try await store.authorizePendingHistoryWrite(
            expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
        )
        return (accepted, authorization)
    }

    func preparation(
        deliveryID: UUID = UUID(),
        sessionID: UUID = UUID(),
        attemptID: UUID = UUID(),
        transcriptID: UUID = UUID(),
        rawAcceptedText: String = "accepted",
        keepLatestResult: Bool = true,
        historyWrite: IOSAcceptedOutputHistoryWrite? = nil
    ) -> IOSAcceptedOutputDeliveryPreparation {
        try! IOSAcceptedOutputDeliveryPreparation(
            deliveryID: deliveryID,
            sessionID: sessionID,
            attemptID: attemptID,
            transcriptID: transcriptID,
            rawAcceptedText: rawAcceptedText,
            outputIntent: .standard,
            automaticInsertionPreferenceEnabled: true,
            keepLatestResult: keepLatestResult,
            historyWrite: historyWrite
        )
    }

    func record(
        preparation: IOSAcceptedOutputDeliveryPreparation,
        revision: Int64 = 1,
        publicationGeneration: Int64 = 0
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        try IOSAcceptedOutputDeliveryRecord(
            revision: revision,
            deliveryID: preparation.deliveryID,
            sessionID: preparation.sessionID,
            attemptID: preparation.attemptID,
            transcriptID: preparation.transcriptID,
            acceptedText: preparation.acceptedText,
            outputIntent: preparation.outputIntent,
            createdAt: clock.wall,
            updatedAt: clock.wall,
            expiresAt: clock.wall.addingTimeInterval(86_400),
            deliveryState: .pending,
            automaticInsertionPreferenceEnabled: true,
            keepLatestResult: preparation.keepLatestResult,
            publicationGeneration: publicationGeneration,
            historyWrite: preparation.historyWrite
        )
    }
}

final class AcceptedDeliveryPolicyFakeJournal:
    IOSHistoryPolicyJournalStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: IOSHistoryPolicyJournalSnapshot
    private var nextToken: UInt64

    init(
        state: IOSHistoryPolicyState,
        fileRevisionToken: UInt64 = 1
    ) {
        snapshot = IOSHistoryPolicyJournalSnapshot(
            state: state,
            fileRevision: IOSStrictProtectedRecordFileRevision(
                testingToken: fileRevisionToken
            )
        )
        nextToken = fileRevisionToken + 1
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

private final class AcceptedDeliveryHistoryFakeJournal:
    IOSAcceptedHistoryJournalStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: IOSAcceptedHistoryJournalSnapshot?
    private var nextToken: UInt64

    init(
        envelope: IOSAcceptedHistoryEnvelope? = nil,
        initialFileRevisionToken: UInt64 = 1
    ) {
        nextToken = initialFileRevisionToken
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
            let created = makeSnapshotLocked(envelope)
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
            let replacement = makeSnapshotLocked(envelope)
            snapshot = replacement
            return replacement
        }
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport { .empty }

    private func makeSnapshotLocked(
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

private final class AcceptedDeliveryOutboxFakeJournal:
    IOSAcceptedHistoryOutboxJournalStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: IOSAcceptedHistoryOutboxJournalSnapshot?
    private var nextToken: UInt64 = 1

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
            let created = makeSnapshotLocked(envelope)
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
            guard snapshot?.fileRevision == expected.fileRevision else {
                throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
            }
            let replacement = makeSnapshotLocked(envelope)
            snapshot = replacement
            return replacement
        }
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport { .empty }

    private func makeSnapshotLocked(
        _ envelope: IOSAcceptedHistoryOutboxEnvelope
    ) -> IOSAcceptedHistoryOutboxJournalSnapshot {
        defer { nextToken += 1 }
        return IOSAcceptedHistoryOutboxJournalSnapshot(
            envelope: envelope,
            fileRevision: IOSStrictProtectedRecordFileRevision(
                testingToken: nextToken
            )
        )
    }
}
