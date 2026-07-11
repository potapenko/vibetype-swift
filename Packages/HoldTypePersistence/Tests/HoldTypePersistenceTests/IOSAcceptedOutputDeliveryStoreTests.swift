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
            (.pendingReplacement, 1),
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
            _ = try await replacement.store.replacePendingHistoryForTesting(
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
        let terminalAuthorization = try await fixture.store
            .confirmActiveHistoryRecovery(
                expected: IOSAcceptedOutputDeliveryExpectation(record: winner)
            )
        let absence = try await fixture.outboxAbsenceAuthorization(
            for: terminalAuthorization
        )
        let accepted = try await fixture.store.acceptForHistoryCoordinator(
            replacement,
            outboxAbsenceAuthorization: absence
        ).record
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

    @Test func crossOwnerHistoryCapabilitiesFailBeforeDeliveryJournalIO()
        async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (_, authorization) = try await fixture.acceptAndAuthorize()
        let localRow = try await fixture.retainedRowReceipt(
            for: authorization
        )
        let localOwnership = IOSAcceptedOutputHistoryOwnershipProof(
            retainedRowReceipt: localRow
        )
        let localPolicy = try await fixture.policyReceipt(generation: 1)
        let localReservation = try await fixture.store
            .reservePendingHistoryTransfer(
                authorization: authorization,
                policyReceipt: localPolicy
            )
        let foreignOwner = IOSAcceptedHistoryCapabilityOwnerIdentity()
        let foreignAuthorization = IOSAcceptedOutputDeliveryAuthorization(
            snapshot: authorization.snapshot,
            capabilityOwnerIdentity: foreignOwner
        )
        #expect(foreignAuthorization != authorization)
        let foreignRow = try await fixture.retainedRowReceipt(
            for: foreignAuthorization,
            capabilityOwnerIdentity: foreignOwner
        )
        let foreignOwnership = IOSAcceptedOutputHistoryOwnershipProof(
            retainedRowReceipt: foreignRow
        )
        let foreignInvalidation = try await fixture.policyReceipt(
            generation: 2,
            capabilityOwnerIdentity: foreignOwner
        )
        fixture.journal.resetEvents()
        fixture.clock.resetWallReadCount()

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            _ = try await fixture.store.commitHistoryWrite(
                authorization: authorization,
                rowReceipt: foreignRow
            )
        }
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            _ = try await fixture.store.clearPendingHistory(
                authorization: authorization,
                ownershipProof: foreignOwnership
            )
        }
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            _ = try await fixture.store.cancelHistoryWrite(
                authorization: authorization,
                policyInvalidationReceipt: foreignInvalidation
            )
        }

        let marker = try #require(authorization.record.historyWrite)
        let foreignCapturePolicy = try await fixture.policyReceipt(
            generation: 1,
            capabilityOwnerIdentity: foreignOwner
        )
        let foreignDisabledPolicy = try await fixture.policyReceipt(
            generation: 2,
            enabled: false,
            capabilityOwnerIdentity: foreignOwner
        )
        let foreignCaptureOwner = IOSAcceptedOutputHistoryCapture(
            testingPolicyReceipt: localPolicy,
            ownerIdentity: foreignOwner,
            historyWrite: marker
        )
        let foreignCapturePolicyOwner = IOSAcceptedOutputHistoryCapture(
            testingPolicyReceipt: foreignCapturePolicy,
            ownerIdentity: fixture.capabilityOwnerIdentity,
            historyWrite: marker
        )
        let foreignDisabledPolicyOwner = IOSAcceptedOutputHistoryCapture(
            testingPolicyReceipt: foreignDisabledPolicy,
            ownerIdentity: fixture.capabilityOwnerIdentity,
            historyWrite: nil
        )

        func preparation(
            capture: IOSAcceptedOutputHistoryCapture
        ) throws -> IOSAcceptedOutputDeliveryPreparation {
            try IOSAcceptedOutputDeliveryPreparation(
                deliveryID: UUID(),
                sessionID: UUID(),
                attemptID: UUID(),
                transcriptID: UUID(),
                rawAcceptedText: "replacement",
                outputIntent: .standard,
                automaticInsertionPreferenceEnabled: true,
                keepLatestResult: true,
                historyCapture: capture
            )
        }

        for capture in [
            foreignCaptureOwner,
            foreignCapturePolicyOwner,
            foreignDisabledPolicyOwner,
        ] {
            let replacement = try preparation(capture: capture)
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.invalidPreparation
            ) {
                _ = try await fixture.store.acceptForHistoryCoordinator(
                    replacement
                )
            }
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.invalidPreparation
            ) {
                _ = try await fixture.store.replacePendingHistory(
                    with: replacement,
                    reservation: localReservation,
                    ownershipProof: localOwnership
                )
            }
        }

        #expect(fixture.journal.events.isEmpty)
        #expect(fixture.clock.wallReadCount == 0)
        #expect(fixture.journal.currentRecord == authorization.record)
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
            try await fixture.store.replacePendingHistoryForTesting(
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

    @Test func pendingTransferReservationRequiresExactRevokedBridgeAuthority()
        async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let (accepted, authorization) = try await fixture.acceptAndAuthorize()
        let policy = try await fixture.policyReceipt()
        let rowReceipt = try await fixture.retainedRowReceipt(
            for: authorization
        )

        let bridgeReservation = try await fixture.store
            .reserveBridgePublication(authorization: authorization)
        #expect(
            String(describing: bridgeReservation)
                == "IOSAcceptedOutputBridgePublicationReservation(redacted)"
        )
        #expect(bridgeReservation.customMirror.children.isEmpty)
        #expect(
            !String(reflecting: bridgeReservation).contains(
                authorization.record.acceptedText ?? ""
            )
        )
        let bridgeEvents = fixture.journal.events.count
        #expect(
            try await fixture.store.reserveBridgePublication(
                authorization: authorization
            ) == bridgeReservation
        )
        #expect(fixture.journal.events.count == bridgeEvents)
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await fixture.store.reservePendingHistoryTransfer(
                authorization: authorization,
                policyReceipt: policy
            )
        }
        #expect(fixture.journal.events.count == bridgeEvents)
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await fixture.store.commitHistoryWrite(
                authorization: authorization,
                rowReceipt: rowReceipt
            )
        }
        #expect(fixture.journal.events.count == bridgeEvents)
        try await fixture.store.releaseBridgePublication(bridgeReservation)

        let reservation = try await fixture.store
            .reservePendingHistoryTransfer(
                authorization: authorization,
                policyReceipt: policy
            )
        #expect(
            String(describing: reservation)
                == "IOSAcceptedOutputPendingHistoryTransferReservation(redacted)"
        )
        #expect(reservation.customMirror.children.isEmpty)
        #expect(
            !String(reflecting: reservation).contains(
                authorization.record.acceptedText ?? ""
            )
        )
        let reservationEvents = fixture.journal.events.count
        #expect(
            try await fixture.store.reservePendingHistoryTransfer(
                authorization: authorization,
                policyReceipt: policy
            ) == reservation
        )
        #expect(fixture.journal.events.count == reservationEvents)
        let eventCountAfterReservation = fixture.journal.events.count
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await fixture.store.reserveBridgePublication(
                authorization: authorization
            )
        }
        #expect(fixture.journal.events.count == eventCountAfterReservation)
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await fixture.store.commitHistoryWrite(
                authorization: authorization,
                rowReceipt: rowReceipt
            )
        }
        #expect(fixture.journal.events.count == eventCountAfterReservation)

        let foreign = AcceptedDeliveryStoreFixture()
        let (_, foreignAuthorization) = try await foreign.acceptAndAuthorize()
        let eventCount = fixture.journal.events.count
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            _ = try await fixture.store.reservePendingHistoryTransfer(
                authorization: foreignAuthorization,
                policyReceipt: policy
            )
        }
        #expect(fixture.journal.events.count == eventCount)

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await foreign.store.releasePendingHistoryTransfer(reservation)
        }
        try await fixture.store.releasePendingHistoryTransfer(reservation)
        let finalBridgeReservation = try await fixture.store
            .reserveBridgePublication(authorization: authorization)
        try await fixture.store.releaseBridgePublication(
            finalBridgeReservation
        )

        let published = try IOSAcceptedOutputDeliveryRecord(
            revision: accepted.revision + 1,
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
            publicationGeneration: 1,
            historyWrite: accepted.historyWrite
        )
        fixture.journal.install(published)
        let publishedStore = fixture.makeStore()
        let publishedAuthorization = try await publishedStore
            .authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: published
                )
            )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.bridgeRevocationRequired
        ) {
            _ = try await publishedStore.reservePendingHistoryTransfer(
                authorization: publishedAuthorization,
                policyReceipt: try await fixture.policyReceipt()
            )
        }
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
            rawAcceptedText: "row replacement",
            historyWrite: try rowFixture.historyWrite()
        )
        let replacedFromRow = try await rowFixture.store.replacePendingHistoryForTesting(
            with: rowReplacement,
            authorization: rowAuthorization,
            ownershipProof: rowProof
        )
        #expect(replacedFromRow.hasSameAcceptance(as: rowReplacement))
        #expect(
            replacedFromRow.historyWrite?.state == .pendingReplacement
        )
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
                try await fixture.store.replacePendingHistoryForTesting(
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
                throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            ) {
                try await fixture.store.replacePendingHistoryForTesting(
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
            let confirmed = try await fixture.store.replacePendingHistoryForTesting(
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
            try await fixture.store.replacePendingHistoryForTesting(
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
            try await fixture.store.replacePendingHistoryForTesting(
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
            try await fixture.store.replacePendingHistoryForTesting(
                with: uncertainReplacement,
                authorization: authorization,
                ownershipProof: ownershipProof
            )
        }
        let winner = try await fixture.makeStore()
            .replacePendingHistoryForTesting(
                with: winningReplacement,
                authorization: authorization,
                ownershipProof: ownershipProof
            )
        #expect(winner.hasSameAcceptance(as: winningReplacement))
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await fixture.store.replacePendingHistoryForTesting(
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
            try await fixture.store.replacePendingHistoryForTesting(
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

        let first = try await firstStore.replacePendingHistoryForTesting(
            with: retained,
            authorization: authorization,
            ownershipProof: ownershipProof
        )
        #expect(first.keepLatestResult)
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await secondStore.replacePendingHistoryForTesting(
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
            try await fixture.store.replacePendingHistoryForTesting(
                with: replacement,
                authorization: authorization,
                ownershipProof: ownershipProof
            )
        }
        fixture.clock.wall = accepted.updatedAt.addingTimeInterval(5)
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.clockRollbackAmbiguous
        ) {
            try await fixture.store.replacePendingHistoryForTesting(
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
        let recovered = try await fixture.store.replacePendingHistoryForTesting(
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
            try await expiryFixture.store.replacePendingHistoryForTesting(
                with: expiryReplacement,
                authorization: expiryAuthorization,
                ownershipProof: expiryProof
            )
        }
        expiryFixture.clock.wall = expiryAttempt.addingTimeInterval(86_400)
        await #expect(throws: IOSAcceptedOutputDeliveryError.expired) {
            try await expiryFixture.store.replacePendingHistoryForTesting(
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

    @Test func terminalHistoryStatesRequireAbsenceForOrdinaryReplacement()
        async throws {
        let committedFixture = AcceptedDeliveryStoreFixture()
        let (_, committedAuthorization) = try await committedFixture
            .acceptAndAuthorize()
        let committedReceipt = try await committedFixture.retainedRowReceipt(
            for: committedAuthorization
        )
        let committed = try await committedFixture.store.commitHistoryWrite(
            authorization: committedAuthorization,
            rowReceipt: committedReceipt
        )
        let afterCommit = committedFixture.preparation(
            rawAcceptedText: "after commit"
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.historyTransferRequired
        ) {
            _ = try await committedFixture.store.accept(afterCommit)
        }
        let confirmedCommit = try await committedFixture.store
            .confirmActiveHistoryRecovery(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: committed
                )
            )
        let committedAbsence = try await committedFixture
            .outboxAbsenceAuthorization(for: confirmedCommit)
        #expect(
            try await committedFixture.store.acceptForHistoryCoordinator(
                afterCommit,
                outboxAbsenceAuthorization: committedAbsence
            ).record.hasSameAcceptance(as: afterCommit)
        )

        let cancelledFixture = AcceptedDeliveryStoreFixture()
        let (_, cancelledAuthorization) = try await cancelledFixture
            .acceptAndAuthorize()
        let cancelled = try await cancelledFixture.store.cancelHistoryWrite(
            authorization: cancelledAuthorization,
            policyInvalidationReceipt: try await cancelledFixture.policyReceipt(
                generation: 2
            )
        )
        let afterCancel = cancelledFixture.preparation(
            rawAcceptedText: "after cancel"
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.historyTransferRequired
        ) {
            _ = try await cancelledFixture.store.accept(afterCancel)
        }
        let confirmedCancel = try await cancelledFixture.store
            .confirmActiveHistoryRecovery(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: cancelled
                )
            )
        let cancelledAbsence = try await cancelledFixture
            .outboxAbsenceAuthorization(for: confirmedCancel)
        #expect(
            try await cancelledFixture.store.acceptForHistoryCoordinator(
                afterCancel,
                outboxAbsenceAuthorization: cancelledAbsence
            ).record.hasSameAcceptance(as: afterCancel)
        )
    }

    @Test func transferReservationIsStoreBoundAndRevokedAfterUse()
        async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let secretPreparation = fixture.preparation(
            rawAcceptedText: "TRANSFER-LEASE-SECRET",
            historyWrite: try fixture.historyWrite()
        )
        let (_, authorization) = try await fixture.acceptAndAuthorize(
            secretPreparation
        )
        let policy = try await fixture.policyReceipt()
        let reservation = try await fixture.store
            .reservePendingHistoryTransfer(
                authorization: authorization,
                policyReceipt: policy
            )
        let outboxJournal = AcceptedDeliveryOutboxFakeJournal()
        let outboxStore = IOSAcceptedHistoryOutboxStore(
            journal: outboxJournal,
            now: { [clock = fixture.clock] in clock.wall },
            deliveryStoreIdentity: fixture.store.storeIdentity,
            capabilityOwnerIdentity: fixture.capabilityOwnerIdentity
        )
        let receipt = try await outboxStore.transfer(
            reservation: reservation
        )
        _ = try await fixture.store.replacePendingHistory(
            with: fixture.preparation(rawAcceptedText: "replacement"),
            reservation: reservation,
            ownershipProof: IOSAcceptedOutputHistoryOwnershipProof(
                outboxReceipt: receipt
            )
        )
        let consumedCounts = (
            outboxJournal.loadCount,
            outboxJournal.createCount,
            outboxJournal.replaceCount
        )

        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            _ = try await outboxStore.transfer(reservation: reservation)
        }
        #expect(outboxJournal.loadCount == consumedCounts.0)
        #expect(outboxJournal.createCount == consumedCounts.1)
        #expect(outboxJournal.replaceCount == consumedCounts.2)

        let releasedFixture = AcceptedDeliveryStoreFixture()
        let (_, releasedAuthorization) = try await releasedFixture
            .acceptAndAuthorize()
        let releasedReservation = try await releasedFixture
            .transferReservation(for: releasedAuthorization)
        let releasedJournal = AcceptedDeliveryOutboxFakeJournal()
        let releasedOutbox = IOSAcceptedHistoryOutboxStore(
            journal: releasedJournal,
            now: { [clock = releasedFixture.clock] in clock.wall },
            deliveryStoreIdentity: releasedFixture.store.storeIdentity,
            capabilityOwnerIdentity: releasedFixture.capabilityOwnerIdentity
        )
        try await releasedFixture.store.releasePendingHistoryTransfer(
            releasedReservation
        )
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            _ = try await releasedOutbox.transfer(
                reservation: releasedReservation
            )
        }
        #expect(releasedJournal.loadCount == 0)

        let local = AcceptedDeliveryStoreFixture()
        let (localRecord, _) = try await local.acceptAndAuthorize()
        let foreignJournal = AcceptedDeliveryFakeJournal()
        foreignJournal.install(localRecord)
        let foreignStore = IOSAcceptedOutputDeliveryStore(
            journal: foreignJournal,
            now: { [clock = local.clock] in clock.wall },
            monotonicNowNanoseconds: {
                [clock = local.clock] in clock.monotonicNanoseconds
            },
            capabilityOwnerIdentity: local.capabilityOwnerIdentity
        )
        let foreignAuthorization = try await foreignStore
            .authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: localRecord
                )
            )
        let foreignReservation = try await foreignStore
            .reservePendingHistoryTransfer(
                authorization: foreignAuthorization,
                policyReceipt: try await local.policyReceipt()
            )
        let localOutboxJournal = AcceptedDeliveryOutboxFakeJournal()
        let localOutbox = IOSAcceptedHistoryOutboxStore(
            journal: localOutboxJournal,
            now: { [clock = local.clock] in clock.wall },
            deliveryStoreIdentity: local.store.storeIdentity,
            capabilityOwnerIdentity: local.capabilityOwnerIdentity
        )
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        ) {
            _ = try await localOutbox.transfer(
                reservation: foreignReservation
            )
        }
        #expect(localOutboxJournal.loadCount == 0)

        let rendered = String(describing: reservation)
            + String(reflecting: reservation)
            + String(describing: Mirror(reflecting: reservation))
        #expect(rendered.contains("redacted"))
        #expect(!rendered.contains("TRANSFER-LEASE-SECRET"))
        #expect(reservation.customMirror.children.isEmpty)
    }

    @Test func transferLeaseUsesMonotonicExpiryWithoutWedgingConfirmation()
        async throws {
        let expiryNanoseconds = UInt64(
            IOSAcceptedOutputDeliveryValidation.lifetimeMilliseconds
        ) * 1_000_000

        let unclaimed = AcceptedDeliveryStoreFixture()
        let (_, unclaimedAuthorization) = try await unclaimed
            .acceptAndAuthorize()
        let unclaimedReservation = try await unclaimed
            .transferReservation(for: unclaimedAuthorization)
        let unclaimedJournal = AcceptedDeliveryOutboxFakeJournal()
        let unclaimedOutbox = IOSAcceptedHistoryOutboxStore(
            journal: unclaimedJournal,
            now: { [clock = unclaimed.clock] in clock.wall },
            deliveryStoreIdentity: unclaimed.store.storeIdentity,
            capabilityOwnerIdentity: unclaimed.capabilityOwnerIdentity
        )
        unclaimed.clock.monotonicNanoseconds = expiryNanoseconds
        await #expect(throws: IOSAcceptedHistoryOutboxError.expired) {
            _ = try await unclaimedOutbox.transfer(
                reservation: unclaimedReservation
            )
        }
        #expect(unclaimedJournal.loadCount == 0)

        for visible in [false, true] {
            let fixture = AcceptedDeliveryStoreFixture()
            let (_, authorization) = try await fixture.acceptAndAuthorize()
            let reservation = try await fixture.transferReservation(
                for: authorization
            )
            let journal = AcceptedDeliveryOutboxFakeJournal()
            journal.failNextCreate(
                with: .commitUncertain,
                commitBeforeThrowing: visible
            )
            let outbox = IOSAcceptedHistoryOutboxStore(
                journal: journal,
                now: { [clock = fixture.clock] in clock.wall },
                deliveryStoreIdentity: fixture.store.storeIdentity,
                capabilityOwnerIdentity: fixture.capabilityOwnerIdentity
            )
            await #expect(
                throws: IOSAcceptedHistoryOutboxError.commitUncertain
            ) {
                _ = try await outbox.transfer(reservation: reservation)
            }
            fixture.clock.monotonicNanoseconds = expiryNanoseconds

            if visible {
                let receipt = try await outbox.transfer(
                    reservation: reservation
                )
                #expect(
                    receipt.provesMembershipForDeliveryRemoval(
                        for: authorization
                    )
                )
                #expect(journal.replaceCount == 1)
            } else {
                await #expect(throws: IOSAcceptedHistoryOutboxError.expired) {
                    _ = try await outbox.transfer(reservation: reservation)
                }
                #expect(try await outbox.observe() == nil)
                #expect(journal.replaceCount == 0)
            }
        }
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
            try await replaceFixture.store.replacePendingHistoryForTesting(
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
            retainedRowReceipt: try await bridgeFixture.retainedRowReceipt(
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
            try await bridgeFixture.store.replacePendingHistoryForTesting(
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

        let first = try await firstStore.replacePendingHistoryForTesting(
            with: firstPreparation,
            authorization: authorization,
            ownershipProof: proof
        )
        #expect(first.hasSameAcceptance(as: firstPreparation))

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            try await secondStore.replacePendingHistoryForTesting(
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

    @Test func terminalHistoryReplacementRequiresExactOutboxAbsence()
        async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let terminal = try await fixture.terminalHistory(state: .committed)
        let replacement = fixture.preparation(
            rawAcceptedText: "replacement after terminal history"
        )

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.historyTransferRequired
        ) {
            _ = try await fixture.store.acceptForHistoryCoordinator(
                replacement
            )
        }

        let foreign = AcceptedDeliveryStoreFixture(
            capabilityOwnerIdentity: fixture.capabilityOwnerIdentity
        )
        let foreignTerminal = try await foreign.terminalHistory(
            state: .committed
        )
        let foreignAbsence = try await foreign.outboxAbsenceAuthorization(
            for: foreignTerminal.authorization
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            _ = try await fixture.store.acceptForHistoryCoordinator(
                replacement,
                outboxAbsenceAuthorization: foreignAbsence
            )
        }

        let exactAbsence = try await fixture.outboxAbsenceAuthorization(
            for: terminal.authorization
        )
        let accepted = try await fixture.store.acceptForHistoryCoordinator(
            replacement,
            outboxAbsenceAuthorization: exactAbsence
        )
        #expect(accepted.record.hasSameAcceptance(as: replacement))
        #expect(accepted.record.historyWrite == nil)
    }

    @Test func terminalHistoryReplacementRejectsForeignAndStaleAbsence()
        async throws {
        let stale = AcceptedDeliveryStoreFixture()
        let staleTerminal = try await stale.terminalHistory(state: .cancelled)
        let staleAbsence = try await stale.outboxAbsenceAuthorization(
            for: staleTerminal.authorization
        )
        let weakened = try await stale.store.disableKeepLatestResult(
            expected: IOSAcceptedOutputDeliveryExpectation(
                record: staleTerminal.record
            )
        )
        #expect(!weakened.keepLatestResult)
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            _ = try await stale.store.acceptForHistoryCoordinator(
                stale.preparation(rawAcceptedText: "stale capability"),
                outboxAbsenceAuthorization: staleAbsence
            )
        }

        let target = AcceptedDeliveryStoreFixture()
        _ = try await target.terminalHistory(state: .committed)
        let foreignOwner = AcceptedDeliveryStoreFixture()
        let foreignTerminal = try await foreignOwner.terminalHistory(
            state: .committed
        )
        let foreignAbsence = try await foreignOwner.outboxAbsenceAuthorization(
            for: foreignTerminal.authorization
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            _ = try await target.store.acceptForHistoryCoordinator(
                target.preparation(rawAcceptedText: "foreign capability"),
                outboxAbsenceAuthorization: foreignAbsence
            )
        }
    }

    @Test func terminalHistoryReplacementUncertaintyResumesRetainedAbsence()
        async throws {
        for commitWasVisible in [true, false] {
            let fixture = AcceptedDeliveryStoreFixture()
            let terminal = try await fixture.terminalHistory(state: .committed)
            let exactAbsence = try await fixture.outboxAbsenceAuthorization(
                for: terminal.authorization
            )
            let replacement = fixture.preparation(
                rawAcceptedText: commitWasVisible
                    ? "visible terminal replacement"
                    : "invisible terminal replacement"
            )
            fixture.journal.failNextReplace(
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )

            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                _ = try await fixture.store.acceptForHistoryCoordinator(
                    replacement,
                    outboxAbsenceAuthorization: exactAbsence
                )
            }
            let eventCount = fixture.journal.events.count
            let foreign = AcceptedDeliveryStoreFixture(
                capabilityOwnerIdentity: fixture.capabilityOwnerIdentity
            )
            let foreignTerminal = try await foreign.terminalHistory(
                state: .committed
            )
            let foreignAbsence = try await foreign.outboxAbsenceAuthorization(
                for: foreignTerminal.authorization
            )
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                _ = try await fixture.store.acceptForHistoryCoordinator(
                    replacement,
                    outboxAbsenceAuthorization: foreignAbsence
                )
            }
            #expect(fixture.journal.events.count == eventCount)

            let confirmed = try await fixture.store
                .acceptForHistoryCoordinator(
                    replacement
                )
            #expect(confirmed.record.hasSameAcceptance(as: replacement))
        }
    }

    @Test func terminalHistoryClearRequiresExactAbsenceExceptAtExpiry()
        async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let terminal = try await fixture.terminalHistory(state: .committed)
        let expectation = IOSAcceptedOutputDeliveryExpectation(
            record: terminal.record
        )
        let absence = try await fixture.outboxAbsenceAuthorization(
            for: terminal.authorization
        )

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.historyTransferRequired
        ) {
            _ = try await fixture.store.clear(expected: expectation)
        }
        #expect(
            try await fixture.store.clear(
                expected: expectation,
                outboxAbsenceAuthorization: absence
            ) == .removed
        )
        #expect(fixture.journal.currentRecord == nil)

        let rollback = AcceptedDeliveryStoreFixture()
        let rollbackTerminal = try await rollback.terminalHistory(
            state: .cancelled
        )
        rollback.clock.wall = rollbackTerminal.record.createdAt
            .addingTimeInterval(-1)
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.historyTransferRequired
        ) {
            _ = try await rollback.store.clear(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: rollbackTerminal.record
                )
            )
        }

        let expired = AcceptedDeliveryStoreFixture()
        let expiredTerminal = try await expired.terminalHistory(
            state: .committed
        )
        expired.clock.wall = expiredTerminal.record.expiresAt
        #expect(
            try await expired.store.clear(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: expiredTerminal.record
                )
            ) == .removed
        )
    }

    @Test func historyNilReplacementRemainsIndependentOfOutboxAbsence()
        async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        _ = try await fixture.store.accept(
            fixture.preparation(rawAcceptedText: "first", historyWrite: nil)
        )
        let replacement = fixture.preparation(
            rawAcceptedText: "second",
            historyWrite: nil
        )

        let accepted = try await fixture.store.acceptForHistoryCoordinator(
            replacement
        )

        #expect(accepted.record.hasSameAcceptance(as: replacement))
    }

    @Test func matchingHistoryDeliveryConfirmsPendingAndTerminalRelations()
        async throws {
        let pendingFixture = AcceptedDeliveryStoreFixture()
        let (_, pendingAuthorization) = try await pendingFixture
            .acceptAndAuthorize()
        let pendingMembership = try await pendingFixture.outboxReceipt(
            for: pendingAuthorization
        )
        pendingFixture.journal.resetEvents()

        let pendingDisposition = try await pendingFixture.store
            .confirmMatchingHistoryDelivery(membership: pendingMembership)
        guard case .confirmed(let confirmedPending) = pendingDisposition else {
            Issue.record("Expected a confirmed pending delivery")
            return
        }
        #expect(confirmedPending.record == pendingAuthorization.record)
        #expect(pendingFixture.journal.events == ["load", "replace:1"])
        #expect(
            String(describing: pendingDisposition)
                == "IOSAcceptedOutputHistoryDeliveryDisposition(redacted)"
        )
        #expect(pendingDisposition.customMirror.children.isEmpty)

        for state in [
            IOSAcceptedOutputHistoryWriteState.committed,
            .cancelled,
        ] {
            let fixture = AcceptedDeliveryStoreFixture()
            let terminal = try await fixture.terminalHistory(state: state)
            fixture.journal.resetEvents()

            let disposition = try await fixture.store
                .confirmMatchingHistoryDelivery(
                    membership: terminal.membership
                )
            guard case .confirmed(let authorization) = disposition else {
                Issue.record("Expected a confirmed terminal delivery")
                continue
            }
            #expect(authorization.record == terminal.record)
            #expect(fixture.journal.events == [
                "load", "replace:\(terminal.record.revision)",
            ])
        }
    }

    @Test func matchingHistoryDeliveryClassifiesTemporalAbsenceAndCollision()
        async throws {
        let expired = AcceptedDeliveryStoreFixture()
        let (expiredRecord, expiredAuthorization) = try await expired
            .acceptAndAuthorize()
        let expiredMembership = try await expired.outboxReceipt(
            for: expiredAuthorization
        )
        expired.clock.wall = expiredRecord.expiresAt
        expired.journal.resetEvents()
        #expect(
            try await expired.store.confirmMatchingHistoryDelivery(
                membership: expiredMembership
            ) == .expired
        )
        #expect(expired.journal.events == ["load"])

        let rollback = AcceptedDeliveryStoreFixture()
        let (rollbackRecord, rollbackAuthorization) = try await rollback
            .acceptAndAuthorize()
        let rollbackMembership = try await rollback.outboxReceipt(
            for: rollbackAuthorization
        )
        rollback.clock.wall = rollbackRecord.createdAt.addingTimeInterval(-1)
        rollback.journal.resetEvents()
        #expect(
            try await rollback.store.confirmMatchingHistoryDelivery(
                membership: rollbackMembership
            ) == .clockRollbackAmbiguous
        )
        #expect(rollback.journal.events == ["load"])

        let unrelated = AcceptedDeliveryStoreFixture()
        let (_, unrelatedAuthorization) = try await unrelated
            .acceptAndAuthorize()
        let unrelatedMembership = try await unrelated.outboxReceipt(
            for: unrelatedAuthorization
        )
        unrelated.journal.install(
            try unrelated.record(
                preparation: unrelated.preparation(historyWrite: nil)
            )
        )
        unrelated.journal.resetEvents()
        #expect(
            try await unrelated.store.confirmMatchingHistoryDelivery(
                membership: unrelatedMembership
            ) == .absentOrUnrelated
        )
        #expect(unrelated.journal.events == ["load"])

        let discarded = AcceptedDeliveryStoreFixture()
        let (discardedRecord, discardedAuthorization) = try await discarded
            .acceptAndAuthorize()
        let discardedMembership = try await discarded.outboxReceipt(
            for: discardedAuthorization
        )
        discarded.journal.install(
            try discarded.discardedRecord(from: discardedRecord)
        )
        discarded.journal.resetEvents()
        #expect(
            try await discarded.store.confirmMatchingHistoryDelivery(
                membership: discardedMembership
            ) == .absentOrUnrelated
        )
        #expect(discarded.journal.events == ["load"])

        let collision = AcceptedDeliveryStoreFixture()
        let (collisionRecord, collisionAuthorization) = try await collision
            .acceptAndAuthorize()
        let collisionMembership = try await collision.outboxReceipt(
            for: collisionAuthorization
        )
        collision.journal.install(
            try collision.record(
                replacing: collisionRecord,
                acceptedText: "different bytes"
            )
        )
        collision.journal.resetEvents()
        await #expect(throws: IOSAcceptedOutputDeliveryError.identityCollision) {
            _ = try await collision.store.confirmMatchingHistoryDelivery(
                membership: collisionMembership
            )
        }
        #expect(collision.journal.events == ["load"])
    }

    @Test func matchingHistoryDeliveryRejectsForeignOwnerBeforeJournalIO()
        async throws {
        let target = AcceptedDeliveryStoreFixture()
        _ = try await target.store.accept(
            target.preparation(historyWrite: try target.historyWrite())
        )
        let foreign = AcceptedDeliveryStoreFixture()
        let (_, foreignAuthorization) = try await foreign.acceptAndAuthorize()
        let foreignMembership = try await foreign.outboxReceipt(
            for: foreignAuthorization
        )
        target.journal.resetEvents()
        target.clock.resetWallReadCount()

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            _ = try await target.store.confirmMatchingHistoryDelivery(
                membership: foreignMembership
            )
        }
        #expect(target.journal.events.isEmpty)
        #expect(target.clock.wallReadCount == 0)
    }

    @Test func matchingHistoryDeliveryUncertaintyRequiresExactConfirmationRetry()
        async throws {
        for commitWasVisible in [true, false] {
            let fixture = AcceptedDeliveryStoreFixture()
            let (_, authorization) = try await fixture.acceptAndAuthorize()
            let membership = try await fixture.outboxReceipt(
                for: authorization
            )
            fixture.journal.failNextReplace(
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )

            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                _ = try await fixture.store.confirmMatchingHistoryDelivery(
                    membership: membership
                )
            }
            let confirmed = try await fixture.store
                .confirmMatchingHistoryDelivery(membership: membership)
            guard case .confirmed(let retriedAuthorization) = confirmed else {
                Issue.record("Expected exact matching retry to confirm")
                continue
            }
            #expect(retriedAuthorization.record == authorization.record)
        }
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
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    lazy var store = makeStore()

    init(
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
            IOSAcceptedHistoryCapabilityOwnerIdentity()
    ) {
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
    }

    func makeStore() -> IOSAcceptedOutputDeliveryStore {
        IOSAcceptedOutputDeliveryStore(
            journal: journal,
            now: { [clock] in clock.wall },
            monotonicNowNanoseconds: {
                [clock] in clock.monotonicNanoseconds
            },
            capabilityOwnerIdentity: capabilityOwnerIdentity
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
        fileRevisionToken: UInt64 = 1,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity?
            = nil
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
        return try await IOSHistoryPolicyStore(
            journal: journal,
            capabilityOwnerIdentity: capabilityOwnerIdentity
                ?? self.capabilityOwnerIdentity
        ).confirm(
            expected: IOSHistoryPolicyExpectation(state: state)
        )
    }

    func retainedRowReceipt(
        for authorization: IOSAcceptedOutputDeliveryAuthorization,
        fileRevisionToken: UInt64 = 1,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity?
            = nil
    ) async throws -> IOSAcceptedHistoryRowReceipt {
        let receiptOwner = capabilityOwnerIdentity
            ?? authorization.capabilityOwnerIdentity
        let policy = try await policyReceipt(
            generation: try #require(
                authorization.record.historyWrite
            ).policyGeneration,
            capabilityOwnerIdentity: receiptOwner
        )
        return try await IOSAcceptedHistoryStore(
            journal: AcceptedDeliveryHistoryFakeJournal(
                initialFileRevisionToken: fileRevisionToken
            ),
            now: { [clock] in clock.wall },
            capabilityOwnerIdentity: receiptOwner
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
            generation: marker.policyGeneration,
            capabilityOwnerIdentity: authorization.capabilityOwnerIdentity
        )
        return try await IOSAcceptedHistoryStore(
            journal: journal,
            now: {
                authorization.record.createdAt.addingTimeInterval(100)
            },
            capabilityOwnerIdentity: authorization.capabilityOwnerIdentity
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
            generation: marker.policyGeneration,
            capabilityOwnerIdentity: authorization.capabilityOwnerIdentity
        )
        return try await IOSAcceptedHistoryOutboxStore(
            journal: AcceptedDeliveryOutboxFakeJournal(),
            now: { [clock] in clock.wall },
            capabilityOwnerIdentity: authorization.capabilityOwnerIdentity
        ).transferForTesting(
            delivery: authorization,
            policy: policy
        )
    }

    func transferReservation(
        for authorization: IOSAcceptedOutputDeliveryAuthorization,
        using targetStore: IOSAcceptedOutputDeliveryStore? = nil
    ) async throws -> IOSAcceptedOutputPendingHistoryTransferReservation {
        let marker = try #require(authorization.record.historyWrite)
        let policy = try await policyReceipt(
            generation: marker.policyGeneration,
            capabilityOwnerIdentity: authorization.capabilityOwnerIdentity
        )
        return try await (targetStore ?? store)
            .reservePendingHistoryTransfer(
                authorization: authorization,
                policyReceipt: policy
            )
    }

    func observationOutboxReceipt(
        for authorization: IOSAcceptedOutputDeliveryAuthorization
    ) async throws -> IOSAcceptedHistoryOutboxReceipt {
        let marker = try #require(authorization.record.historyWrite)
        let policy = try await policyReceipt(
            generation: marker.policyGeneration,
            capabilityOwnerIdentity: authorization.capabilityOwnerIdentity
        )
        let journal = AcceptedDeliveryOutboxFakeJournal()
        _ = try await IOSAcceptedHistoryOutboxStore(
            journal: journal,
            now: { [clock] in clock.wall },
            capabilityOwnerIdentity: authorization.capabilityOwnerIdentity
        ).transferForTesting(
            delivery: authorization,
            policy: policy
        )
        let relaunched = IOSAcceptedHistoryOutboxStore(
            journal: journal,
            now: { [clock] in clock.wall },
            capabilityOwnerIdentity: authorization.capabilityOwnerIdentity
        )
        let observations = try #require(try await relaunched.observe())
        return try await relaunched.confirmMembership(
            observation: try #require(observations.first)
        )
    }

    func outboxAbsenceAuthorization(
        for authorization: IOSAcceptedOutputDeliveryAuthorization
    ) async throws -> IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization {
        let outbox = IOSAcceptedHistoryOutboxStore(
            journal: AcceptedDeliveryOutboxFakeJournal(),
            now: { [clock] in clock.wall },
            deliveryStoreIdentity: store.storeIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
        let disposition = try await outbox.classifyDeliveryAbsence(
            authorization: authorization
        )
        guard case .absent(let absence) = disposition else {
            Issue.record("Expected an empty outbox absence authorization")
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        return absence
    }

    func rowReceipt(
        for outbox: IOSAcceptedHistoryOutboxReceipt,
        policyGeneration: Int64 = 1
    ) async throws -> IOSAcceptedHistoryRowReceipt {
        let policy = try await policyReceipt(
            generation: policyGeneration,
            capabilityOwnerIdentity: outbox.capabilityOwnerIdentity
        )
        return try await IOSAcceptedHistoryStore(
            journal: AcceptedDeliveryHistoryFakeJournal(),
            now: { [clock] in clock.wall },
            capabilityOwnerIdentity: outbox.capabilityOwnerIdentity
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

    func terminalHistory(
        state: IOSAcceptedOutputHistoryWriteState
    ) async throws -> (
        record: IOSAcceptedOutputDeliveryRecord,
        authorization: IOSAcceptedOutputDeliveryAuthorization,
        membership: IOSAcceptedHistoryOutboxReceipt
    ) {
        let (_, pendingAuthorization) = try await acceptAndAuthorize()
        let membership = try await outboxReceipt(for: pendingAuthorization)
        let terminal: IOSAcceptedOutputDeliveryRecord
        switch state {
        case .committed:
            terminal = try await store.commitHistoryWrite(
                authorization: pendingAuthorization,
                rowReceipt: try await retainedRowReceipt(
                    for: pendingAuthorization
                )
            )
        case .cancelled:
            terminal = try await store.cancelHistoryWrite(
                authorization: pendingAuthorization,
                policyInvalidationReceipt: try await policyReceipt(
                    generation: 2
                )
            )
        case .pending, .pendingReplacement:
            Issue.record("terminalHistory requires a terminal marker state")
            throw IOSAcceptedOutputDeliveryError.invalidTransition
        }
        let authorization = try await store.confirmActiveHistoryRecovery(
            expected: IOSAcceptedOutputDeliveryExpectation(record: terminal)
        )
        return (terminal, authorization, membership)
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

    func record(
        replacing old: IOSAcceptedOutputDeliveryRecord,
        acceptedText: String
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        try IOSAcceptedOutputDeliveryRecord(
            revision: old.revision,
            deliveryID: old.deliveryID,
            sessionID: old.sessionID,
            attemptID: old.attemptID,
            transcriptID: old.transcriptID,
            acceptedText: acceptedText,
            outputIntent: old.outputIntent,
            createdAt: old.createdAt,
            updatedAt: old.updatedAt,
            expiresAt: old.expiresAt,
            deliveryState: old.deliveryState,
            automaticInsertionPreferenceEnabled:
                old.automaticInsertionPreferenceEnabled,
            keepLatestResult: old.keepLatestResult,
            publicationGeneration: old.publicationGeneration,
            historyWrite: old.historyWrite
        )
    }

    func discardedRecord(
        from old: IOSAcceptedOutputDeliveryRecord
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        try IOSAcceptedOutputDeliveryRecord(
            revision: old.revision + 1,
            deliveryID: old.deliveryID,
            sessionID: old.sessionID,
            attemptID: old.attemptID,
            transcriptID: old.transcriptID,
            acceptedText: nil,
            outputIntent: old.outputIntent,
            createdAt: old.createdAt,
            updatedAt: old.updatedAt,
            expiresAt: old.expiresAt,
            deliveryState: .discarded,
            automaticInsertionPreferenceEnabled: false,
            keepLatestResult: old.keepLatestResult,
            publicationGeneration: old.publicationGeneration,
            historyWrite: nil
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
    private struct Failure {
        let error: IOSAcceptedHistoryOutboxError
        let commitBeforeThrowing: Bool
    }

    private let lock = NSLock()
    private var snapshot: IOSAcceptedHistoryOutboxJournalSnapshot?
    private var nextToken: UInt64 = 1
    private var createFailure: Failure?
    private var storedLoadCount = 0
    private var storedCreateCount = 0
    private var storedReplaceCount = 0

    var loadCount: Int { lock.withLock { storedLoadCount } }
    var createCount: Int { lock.withLock { storedCreateCount } }
    var replaceCount: Int { lock.withLock { storedReplaceCount } }

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

    func load() throws -> IOSAcceptedHistoryOutboxJournalSnapshot? {
        lock.withLock {
            storedLoadCount += 1
            return snapshot
        }
    }

    func create(
        _ envelope: IOSAcceptedHistoryOutboxEnvelope,
        authorization: IOSAcceptedHistoryOutboxJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryOutboxJournalSnapshot {
        try lock.withLock {
            storedCreateCount += 1
            guard snapshot == nil else {
                throw IOSAcceptedHistoryOutboxError.slotOccupied
            }
            let created = makeSnapshotLocked(envelope)
            if let failure = createFailure {
                createFailure = nil
                if failure.commitBeforeThrowing { snapshot = created }
                throw failure.error
            }
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
            storedReplaceCount += 1
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
