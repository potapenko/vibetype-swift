import Foundation
import Testing
@testable import HoldTypePersistence

struct IOSHistoryPolicyStoreTests {
    @Test func missingReadDoesNotWrite() async throws {
        let fixture = HistoryPolicyStoreFixture()

        #expect(try await fixture.store.load() == nil)
        #expect(fixture.journal.events == ["load"])
    }

    @Test func clearDisableAndEnableHaveExactMutationAndNoOpRules() async throws {
        let fixture = HistoryPolicyStoreFixture()
        let baseline = try await fixture.establishBaseline()

        let disabled = try await fixture.store.setHistoryEnabled(
            false,
            using: baseline
        )
        #expect(disabled.state.revision == 2)
        #expect(!disabled.state.historyEnabled)
        fixture.journal.resetEvents()

        let repeatedDisable = try await fixture.store.setHistoryEnabled(
            false,
            using: disabled
        )
        #expect(repeatedDisable == disabled)
        #expect(fixture.journal.events == ["load"])

        let clearedWhileDisabled = try await fixture.store.clear(
            using: disabled
        )
        #expect(clearedWhileDisabled.state.revision == 3)
        #expect(!clearedWhileDisabled.state.historyEnabled)

        let enabled = try await fixture.store.setHistoryEnabled(
            true,
            using: clearedWhileDisabled
        )
        #expect(enabled.state.revision == 4)
        #expect(enabled.state.historyEnabled)
    }

    @Test func sameStateNoOpAtMaximumDoesNotOverflowOrWrite() async throws {
        let fixture = HistoryPolicyStoreFixture()
        let maximum = try IOSHistoryPolicyState(
            revision: Int64.max,
            historyEnabled: false,
            policyGeneration: Int64.max
        )
        fixture.journal.install(maximum)
        let receipt = try await fixture.store.confirm(
            expected: IOSHistoryPolicyExpectation(state: maximum)
        )
        fixture.journal.resetEvents()

        let noOp = try await fixture.store.setHistoryEnabled(
            false,
            using: receipt
        )
        #expect(noOp == receipt)
        #expect(fixture.journal.events == ["load"])

        await #expect(throws: IOSHistoryPolicyError.revisionOverflow) {
            try await fixture.store.clear(using: receipt)
        }
        #expect(fixture.journal.currentState == maximum)
    }

    @Test func uncertainVisibleSuccessRequiresAnIdenticalRetry() async throws {
        let fixture = HistoryPolicyStoreFixture()
        let baseline = try await fixture.establishBaseline()
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )

        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            try await fixture.store.clear(using: baseline)
        }
        #expect(fixture.journal.currentState?.revision == 2)

        let confirmed = try await fixture.store.clear(using: baseline)
        #expect(confirmed.state.revision == 2)
        #expect(fixture.journal.replacementStates.suffix(2).allSatisfy {
            $0.revision == 2
        })
    }

    @Test func uncertainPrepublicationBlocksEveryDifferentOperation() async throws {
        let fixture = HistoryPolicyStoreFixture()
        let baseline = try await fixture.establishBaseline()
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )

        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            try await fixture.store.clear(using: baseline)
        }
        #expect(fixture.journal.currentState == .baseline)
        fixture.journal.resetEvents()

        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            try await fixture.store.setHistoryEnabled(true, using: baseline)
        }
        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            try await fixture.store.setHistoryEnabled(false, using: baseline)
        }
        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            try await fixture.store.confirm(
                expected: IOSHistoryPolicyExpectation(state: .baseline)
            )
        }
        #expect(fixture.journal.events == ["load", "load", "load"])

        let confirmed = try await fixture.store.clear(using: baseline)
        #expect(confirmed.state.revision == 2)
        #expect(confirmed.state.historyEnabled)
    }

    @Test func confirmationCanReconcileOnlyTheUncertainIntendedState() async throws {
        let fixture = HistoryPolicyStoreFixture()
        let baseline = try await fixture.establishBaseline()
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )

        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            try await fixture.store.clear(using: baseline)
        }
        let intended = try IOSHistoryPolicyState(
            revision: 2,
            historyEnabled: true,
            policyGeneration: 2
        )

        let confirmed = try await fixture.store.confirm(
            expected: IOSHistoryPolicyExpectation(state: intended)
        )
        #expect(confirmed.state == intended)

        await #expect(throws: IOSHistoryPolicyError.compareAndSwapFailed) {
            try await fixture.store.clear(using: baseline)
        }
    }

    @Test func supersededUncertaintyCanRecoverThroughTheDurableWinner() async throws {
        let fixture = HistoryPolicyStoreFixture()
        let baseline = try await fixture.establishBaseline()
        fixture.journal.failNextReplace(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )

        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            try await fixture.store.clear(using: baseline)
        }
        let winner = try await fixture.makeStore().setHistoryEnabled(
            false,
            using: baseline
        )

        await #expect(throws: IOSHistoryPolicyError.compareAndSwapFailed) {
            try await fixture.store.clear(using: baseline)
        }
        #expect(try await fixture.store.load() == winner.state)

        let recovered = try await fixture.store.confirm(
            expected: IOSHistoryPolicyExpectation(state: winner.state)
        )
        #expect(recovered.state == winner.state)
    }

    @Test func receiptDiagnosticsAndReflectionAreRedacted() async throws {
        let receipt = try await HistoryPolicyStoreFixture().establishBaseline()

        #expect(
            String(describing: receipt) == "IOSHistoryPolicyReceipt(redacted)"
        )
        #expect(receipt.customMirror.children.isEmpty)
    }

    @Test func successfulMutationCannotBeReplayedWithOldReceipt() async throws {
        let fixture = HistoryPolicyStoreFixture()
        let baseline = try await fixture.establishBaseline()

        _ = try await fixture.store.clear(using: baseline)

        await #expect(throws: IOSHistoryPolicyError.compareAndSwapFailed) {
            try await fixture.store.clear(using: baseline)
        }
        #expect(fixture.journal.currentState?.revision == 2)
    }

    @Test func competingIdenticalClearsHaveExactlyOneWinner() async throws {
        let fixture = HistoryPolicyStoreFixture()
        let baseline = try await fixture.establishBaseline()
        let otherStore = fixture.makeStore()

        let firstTask = Task {
            try await fixture.store.clear(using: baseline)
        }
        let secondTask = Task {
            try await otherStore.clear(using: baseline)
        }
        let results = await [firstTask.result, secondTask.result]
        let successCount = results.filter {
            if case .success = $0 { return true }
            return false
        }.count

        #expect(successCount == 1)
        #expect(fixture.journal.currentState?.revision == 2)
    }

    @Test func competingClearAndDisableHaveExactlyOneWinner() async throws {
        let fixture = HistoryPolicyStoreFixture()
        let baseline = try await fixture.establishBaseline()
        let otherStore = fixture.makeStore()

        let clearTask = Task {
            try await fixture.store.clear(using: baseline)
        }
        let disableTask = Task {
            try await otherStore.setHistoryEnabled(false, using: baseline)
        }
        let results = await [clearTask.result, disableTask.result]
        let successCount = results.filter {
            if case .success = $0 { return true }
            return false
        }.count

        #expect(successCount == 1)
        #expect(fixture.journal.currentState?.revision == 2)
    }

    @Test func relaunchConfirmationRewritesAndStalePhysicalReceiptCannotNoOp() async throws {
        let fixture = HistoryPolicyStoreFixture()
        let baseline = try await fixture.establishBaseline()
        let expectation = IOSHistoryPolicyExpectation(state: baseline.state)
        fixture.journal.resetEvents()

        let confirmed = try await fixture.makeStore().confirm(
            expected: expectation
        )
        #expect(confirmed.state == baseline.state)
        #expect(fixture.journal.events == ["load", "replace:1"])

        await #expect(throws: IOSHistoryPolicyError.compareAndSwapFailed) {
            try await fixture.store.setHistoryEnabled(true, using: baseline)
        }
    }

    @Test func maintenanceReportIsForwardedWithoutPolicyPayload() async throws {
        let fixture = HistoryPolicyStoreFixture()
        fixture.journal.maintenanceReport = IOSStrictProtectedRecordMaintenanceReport(
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
}

private final class HistoryPolicyFakeJournal:
    IOSHistoryPolicyJournalStoring,
    @unchecked Sendable {
    private struct Failure {
        let error: IOSHistoryPolicyError
        let commitBeforeThrowing: Bool
    }

    private let lock = NSLock()
    private var snapshot: IOSHistoryPolicyJournalSnapshot?
    private var nextToken: UInt64 = 1
    private var replaceFailure: Failure?
    private var storedEvents: [String] = []
    private var storedReplacementStates: [IOSHistoryPolicyState] = []

    var maintenanceReport = IOSStrictProtectedRecordMaintenanceReport.empty

    var events: [String] { lock.withLock { storedEvents } }
    var currentState: IOSHistoryPolicyState? {
        lock.withLock { snapshot?.state }
    }
    var replacementStates: [IOSHistoryPolicyState] {
        lock.withLock { storedReplacementStates }
    }

    func resetEvents() {
        lock.withLock { storedEvents = [] }
    }

    func install(
        _ state: IOSHistoryPolicyState
    ) {
        lock.withLock {
            let installed = IOSHistoryPolicyJournalSnapshot(
                state: state,
                fileRevision: makeRevisionLocked()
            )
            snapshot = installed
        }
    }

    func failNextReplace(
        with error: IOSHistoryPolicyError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            replaceFailure = Failure(
                error: error,
                commitBeforeThrowing: commitBeforeThrowing
            )
        }
    }

    func load() throws -> IOSHistoryPolicyJournalSnapshot? {
        lock.withLock {
            storedEvents.append("load")
            return snapshot
        }
    }

    func replace(
        _ state: IOSHistoryPolicyState,
        expected: IOSHistoryPolicyJournalSnapshot
    ) throws -> IOSHistoryPolicyJournalSnapshot {
        try lock.withLock {
            storedEvents.append("replace:\(state.revision)")
            storedReplacementStates.append(state)
            guard snapshot?.fileRevision == expected.fileRevision else {
                throw IOSHistoryPolicyError.compareAndSwapFailed
            }
            if let failure = replaceFailure {
                replaceFailure = nil
                if failure.commitBeforeThrowing {
                    snapshot = IOSHistoryPolicyJournalSnapshot(
                        state: state,
                        fileRevision: makeRevisionLocked()
                    )
                }
                throw failure.error
            }
            let replacement = IOSHistoryPolicyJournalSnapshot(
                state: state,
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

private final class HistoryPolicyStoreFixture: @unchecked Sendable {
    let journal = HistoryPolicyFakeJournal()
    lazy var store = makeStore()

    func makeStore() -> IOSHistoryPolicyStore {
        IOSHistoryPolicyStore(
            journal: journal,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    func establishBaseline() async throws -> IOSHistoryPolicyReceipt {
        journal.install(.baseline)
        return try await store.confirm(
            expected: IOSHistoryPolicyExpectation(state: .baseline)
        )
    }
}
