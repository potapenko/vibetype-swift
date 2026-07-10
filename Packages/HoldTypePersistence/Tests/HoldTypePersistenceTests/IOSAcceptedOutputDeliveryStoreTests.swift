import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSAcceptedOutputDeliveryStoreTests {
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

        let committed = try await fixture.store.commitHistoryWrite(
            authorization: authorization
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
        let committed = try await fixture.store.commitHistoryWrite(
            authorization: authorization
        )
        #expect(committed.historyWrite?.state == .committed)
    }

    @Test func uncertainHistoryTransitionRequiresIdenticalConfirmationRetry() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let accepted = try await fixture.store.accept(
            fixture.preparation(historyWrite: try fixture.historyWrite())
        )
        let authorization = try await fixture.store
            .authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
            )
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try await fixture.store.commitHistoryWrite(
                authorization: authorization
            )
        }
        let visible = try #require(fixture.journal.currentRecord)
        #expect(visible.revision == 2)
        #expect(visible.historyWrite?.state == .committed)

        let confirmed = try await fixture.store.commitHistoryWrite(
            authorization: authorization
        )
        #expect(confirmed == visible)
        #expect(fixture.journal.replacementRecords.last == visible)
    }

    @Test func historyCancelIsOneWayIdempotentAndConflictsWithCommit() async throws {
        let fixture = AcceptedDeliveryStoreFixture()
        let accepted = try await fixture.store.accept(
            fixture.preparation(historyWrite: try fixture.historyWrite())
        )
        let expected = IOSAcceptedOutputDeliveryExpectation(record: accepted)
        let cancelled = try await fixture.store.cancelHistoryWrite(
            expected: expected
        )
        #expect(cancelled.historyWrite?.state == .cancelled)

        let retried = try await fixture.store.cancelHistoryWrite(
            expected: expected
        )
        #expect(retried == cancelled)
        let currentExpectation = IOSAcceptedOutputDeliveryExpectation(
            record: retried
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.invalidTransition) {
            let authorization = try await fixture.store
                .authorizePendingHistoryWrite(expected: currentExpectation)
            _ = try await fixture.store.commitHistoryWrite(
                authorization: authorization
            )
        }
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
        let committed = try await fixture.store.commitHistoryWrite(
            authorization: authorization
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

        let disableTask = Task {
            try await fixture.store.disableKeepLatestResult(
                expected: expectation
            )
        }
        let cancelTask = Task {
            try await otherStore.cancelHistoryWrite(expected: expectation)
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
        lock.withLock {
            storedEvents.append("load")
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

    func historyWrite() throws -> IOSAcceptedOutputHistoryWrite {
        try IOSAcceptedOutputHistoryWrite(
            policyGeneration: 1,
            transcriptionModel: "model",
            transcriptionLanguageCode: "en",
            durationMilliseconds: 1_000
        )
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
