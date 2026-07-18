import Foundation
import Testing
@_spi(HoldTypeIOSCore) @testable import HoldTypePersistence
@testable import HoldTypeIOS

@MainActor
struct IOSAcceptedTextHistoryStateOwnerTests {
    @Test func homePresentationCoversEveryUserVisibleContentState()
        throws {
        let entries = try historyRecord(1, 2)
        let disabled = IOSAcceptedTextHistoryRecord(
            isEnabled: false,
            entries: []
        )

        #expect(
            IOSAcceptedTextHistoryHomePresentation.resolve(.notLoaded)
                == .loading
        )
        #expect(
            IOSAcceptedTextHistoryHomePresentation.resolve(
                .loadFailed(lastConfirmed: nil)
            ) == .unavailable
        )
        #expect(
            IOSAcceptedTextHistoryHomePresentation.resolve(.ready(disabled))
                == .history(
                    record: disabled,
                    content: .disabled,
                    isStale: false
                )
        )
        #expect(
            IOSAcceptedTextHistoryHomePresentation.resolve(
                .ready(.enabledEmpty)
            ) == .history(
                record: .enabledEmpty,
                content: .empty,
                isStale: false
            )
        )
        #expect(
            IOSAcceptedTextHistoryHomePresentation.resolve(
                .loadFailed(lastConfirmed: entries)
            ) == .history(
                record: entries,
                content: .entries,
                isStale: true
            )
        )
    }

    @Test func savedRecordingStaysFirstAcrossAcceptedHistoryFallbacks() {
        let disabled = IOSAcceptedTextHistoryRecord(
            isEnabled: false,
            entries: []
        )
        let acceptedHistoryPresentations = [
            IOSAcceptedTextHistoryHomePresentation.loading,
            .unavailable,
            .history(
                record: disabled,
                content: .disabled,
                isStale: false
            ),
        ]

        for acceptedHistory in acceptedHistoryPresentations {
            #expect(
                IOSHistoryHomeLayout.resolve(
                    acceptedHistory: acceptedHistory,
                    hasSavedRecording: true
                ) == .savedRecordingFirst(acceptedHistory)
            )
        }

        #expect(
            IOSHistoryHomeLayout.resolve(
                acceptedHistory: .loading,
                hasSavedRecording: false
            ) == .acceptedHistoryOnly(.loading)
        )
    }

    @Test func constructionIsPassiveAndRefreshPublishesConfirmedRecord()
        async throws {
        let fixture = HistoryOwnerFixture(record: try historyRecord(1, 2))
        let owner = IOSAcceptedTextHistoryStateOwner(
            client: historyOwnerClient(fixture)
        )

        #expect(owner.state == .notLoaded)
        #expect(await fixture.loadCallCount == 0)
        #expect(await owner.refresh())
        #expect(owner.state == .ready(try historyRecord(1, 2)))
        #expect(owner.operation == .idle)
        #expect(owner.notice == nil)
    }

    @Test func firstLoadFailureIsUnavailableAndRetryCanRecover()
        async throws {
        let fixture = HistoryOwnerFixture(
            record: try historyRecord(1),
            failNext: .load
        )
        let owner = IOSAcceptedTextHistoryStateOwner(
            client: historyOwnerClient(fixture)
        )

        #expect(!(await owner.refresh()))
        #expect(owner.state == .loadFailed(lastConfirmed: nil))
        #expect(owner.notice == nil)
        #expect(await owner.refresh())
        #expect(owner.state == .ready(try historyRecord(1)))
    }

    @Test func acceptedResultRefreshesPresentationWithoutPublishingSnapshot()
        async throws {
        let fixture = HistoryOwnerFixture(record: try historyRecord(1))
        let publicationProbe = HistoryPublicationProbe()
        let owner = IOSAcceptedTextHistoryStateOwner(
            client: historyOwnerClient(fixture),
            publishKeyboardSnapshot: {
                await publicationProbe.record()
                return true
            }
        )
        #expect(await owner.refresh())
        #expect(await publicationProbe.callCount == 1)

        let updated = try historyRecord(1, 2)
        await fixture.replaceRecord(updated)
        await owner.refreshPresentationAfterAcceptedResult()

        #expect(owner.state == .ready(updated))
        #expect(await publicationProbe.callCount == 1)
    }

    @Test func acceptedResultRefreshCoalescesBehindActiveLoad()
        async throws {
        let fixture = HistoryOwnerFixture(
            record: try historyRecord(1),
            suspendNextLoad: true
        )
        let owner = IOSAcceptedTextHistoryStateOwner(
            client: historyOwnerClient(fixture)
        )
        let activeRefresh = Task { await owner.refresh() }
        try await historyOwnerEventually {
            await fixture.loadCallCount == 1
        }

        await owner.refreshPresentationAfterAcceptedResult()
        await owner.refreshPresentationAfterAcceptedResult()
        let updated = try historyRecord(1, 2)
        await fixture.replaceRecord(updated)
        await fixture.resumeLoad()

        #expect(await activeRefresh.value)
        try await historyOwnerEventually {
            await fixture.loadCallCount == 2
                && owner.state == .ready(updated)
                && owner.operation == .idle
        }
        #expect(await fixture.loadCallCount == 2)
    }

    @Test func failedRefreshKeepsLastConfirmedHistoryVisible()
        async throws {
        let fixture = HistoryOwnerFixture(record: try historyRecord(1, 2))
        let owner = IOSAcceptedTextHistoryStateOwner(
            client: historyOwnerClient(fixture)
        )
        #expect(await owner.refresh())
        await fixture.setFailure(.load)

        #expect(!(await owner.refresh()))
        #expect(
            owner.state == .loadFailed(
                lastConfirmed: try historyRecord(1, 2)
            )
        )
        #expect(owner.notice == nil)
    }

    @Test func successfulMutationsPublishOnlyRepositoryConfirmedRecords()
        async throws {
        let fixture = HistoryOwnerFixture(record: try historyRecord(1, 2))
        let publicationProbe = HistoryPublicationProbe()
        let owner = IOSAcceptedTextHistoryStateOwner(
            client: historyOwnerClient(fixture),
            publishKeyboardSnapshot: {
                await publicationProbe.record()
                return true
            }
        )
        _ = await owner.refresh()

        #expect(await owner.delete(resultID: historyIdentifier(1)))
        #expect(owner.confirmedRecord == (try historyRecord(2)))
        #expect(
            await owner.clearAll(
                ifCurrent: try historyToken(2)
            )
        )
        #expect(owner.confirmedRecord == .enabledEmpty)
        #expect(
            await owner.setEnabled(
                false,
                ifCurrent: IOSAcceptedTextHistorySnapshotToken(
                    record: .enabledEmpty
                )
            )
        )
        #expect(owner.confirmedRecord == IOSAcceptedTextHistoryRecord(
            isEnabled: false,
            entries: []
        ))
        #expect(
            await owner.setEnabled(
                true,
                ifCurrent: IOSAcceptedTextHistorySnapshotToken(
                    record: IOSAcceptedTextHistoryRecord(
                        isEnabled: false,
                        entries: []
                    )
                )
            )
        )
        #expect(owner.confirmedRecord == .enabledEmpty)
        #expect(await fixture.mutationCallCount == 4)
        #expect(await publicationProbe.callCount == 5)
    }

    @Test func failedMutationsKeepConfirmedRecordAndExposeExactWarning()
        async throws {
        let fixture = HistoryOwnerFixture(record: try historyRecord(1, 2))
        let owner = IOSAcceptedTextHistoryStateOwner(
            client: historyOwnerClient(fixture)
        )
        _ = await owner.refresh()
        let original = try historyRecord(1, 2)

        await fixture.setFailure(.delete)
        #expect(!(await owner.delete(resultID: historyIdentifier(1))))
        #expect(owner.confirmedRecord == original)
        #expect(owner.notice == .deleteFailed)

        await fixture.setFailure(.clear)
        #expect(!(await owner.clearAll(ifCurrent: try historyToken(1, 2))))
        #expect(owner.confirmedRecord == original)
        #expect(owner.notice == .clearFailed)

        await fixture.setFailure(.setEnabled)
        #expect(!(
            await owner.setEnabled(
                false,
                ifCurrent: try historyToken(1, 2)
            )
        ))
        #expect(owner.confirmedRecord == original)
        #expect(owner.notice == .disableFailed)

        await fixture.setFailure(.setEnabled)
        #expect(!(
            await owner.setEnabled(
                true,
                ifCurrent: try historyToken(1, 2)
            )
        ))
        #expect(owner.confirmedRecord == original)
        #expect(owner.notice == .enableFailed)
    }

    @Test func staleDestructiveCommandsPublishCurrentRecordWithoutMutating()
        async throws {
        let original = try historyRecord(1, 2)
        let fixture = HistoryOwnerFixture(record: original)
        let owner = IOSAcceptedTextHistoryStateOwner(
            client: historyOwnerClient(fixture)
        )
        _ = await owner.refresh()
        let staleToken = IOSAcceptedTextHistorySnapshotToken(record: original)
        let current = try historyRecord(1, 2, 3)
        await fixture.replaceRecord(current)

        #expect(!(await owner.clearAll(ifCurrent: staleToken)))
        #expect(owner.confirmedRecord == current)
        #expect(owner.notice == .historyChanged)
        #expect(!(await owner.setEnabled(false, ifCurrent: staleToken)))
        #expect(owner.confirmedRecord == current)
        #expect(owner.notice == .historyChanged)
    }

    @Test func activeOperationRejectsCompetingRefresh() async throws {
        let fixture = HistoryOwnerFixture(
            record: try historyRecord(1),
            suspendNextLoad: true
        )
        let owner = IOSAcceptedTextHistoryStateOwner(
            client: historyOwnerClient(fixture)
        )
        let first = Task { await owner.refresh() }
        try await historyOwnerEventually {
            await fixture.loadCallCount == 1
        }

        #expect(owner.operation == .refreshing)
        #expect(!(await owner.refresh()))
        #expect(await fixture.loadCallCount == 1)
        await fixture.resumeLoad()
        #expect(await first.value)
        #expect(owner.operation == .idle)
    }
}

private actor HistoryPublicationProbe {
    private(set) var callCount = 0

    func record() {
        callCount += 1
    }
}

private enum HistoryOwnerFixtureAction: Sendable {
    case load
    case delete
    case clear
    case setEnabled
}

private enum HistoryOwnerFixtureError: Error {
    case failed
}

private actor HistoryOwnerFixture {
    private var record: IOSAcceptedTextHistoryRecord
    private var nextFailure: HistoryOwnerFixtureAction?
    private var shouldSuspendNextLoad: Bool
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private(set) var loadCallCount = 0
    private(set) var mutationCallCount = 0

    init(
        record: IOSAcceptedTextHistoryRecord,
        failNext: HistoryOwnerFixtureAction? = nil,
        suspendNextLoad: Bool = false
    ) {
        self.record = record
        nextFailure = failNext
        shouldSuspendNextLoad = suspendNextLoad
    }

    func setFailure(_ action: HistoryOwnerFixtureAction) {
        nextFailure = action
    }

    func replaceRecord(_ replacement: IOSAcceptedTextHistoryRecord) {
        record = replacement
    }

    func resumeLoad() {
        let continuation = loadContinuation
        loadContinuation = nil
        continuation?.resume()
    }

    fileprivate func load() async throws -> IOSAcceptedTextHistoryRecord {
        loadCallCount += 1
        if shouldSuspendNextLoad {
            shouldSuspendNextLoad = false
            await withCheckedContinuation { continuation in
                loadContinuation = continuation
            }
        }
        try failIfRequested(.load)
        return record
    }

    fileprivate func delete(
        _ resultID: UUID
    ) throws -> IOSAcceptedTextHistoryRecord {
        mutationCallCount += 1
        try failIfRequested(.delete)
        record = IOSAcceptedTextHistoryRecord(
            isEnabled: record.isEnabled,
            entries: record.entries.filter { $0.resultID != resultID }
        )
        return record
    }

    fileprivate func clearAll(
        ifCurrent expected: IOSAcceptedTextHistorySnapshotToken
    ) throws -> IOSAcceptedTextHistoryMutationResult {
        mutationCallCount += 1
        try failIfRequested(.clear)
        guard IOSAcceptedTextHistorySnapshotToken(record: record) == expected
        else {
            return .stale(record)
        }
        record = IOSAcceptedTextHistoryRecord(
            isEnabled: record.isEnabled,
            entries: []
        )
        return .confirmed(record)
    }

    fileprivate func setEnabled(
        _ isEnabled: Bool,
        ifCurrent expected: IOSAcceptedTextHistorySnapshotToken
    ) throws -> IOSAcceptedTextHistoryMutationResult {
        mutationCallCount += 1
        try failIfRequested(.setEnabled)
        guard IOSAcceptedTextHistorySnapshotToken(record: record) == expected
        else {
            return .stale(record)
        }
        record = IOSAcceptedTextHistoryRecord(
            isEnabled: isEnabled,
            entries: isEnabled ? record.entries : []
        )
        return .confirmed(record)
    }

    private func failIfRequested(
        _ action: HistoryOwnerFixtureAction
    ) throws {
        guard nextFailure == action else { return }
        nextFailure = nil
        throw HistoryOwnerFixtureError.failed
    }
}

@MainActor
private func historyOwnerClient(
    _ fixture: HistoryOwnerFixture
) -> IOSAcceptedTextHistoryClient {
    IOSAcceptedTextHistoryClient(
        load: { try await fixture.load() },
        delete: { try await fixture.delete($0) },
        clearAll: { try await fixture.clearAll(ifCurrent: $0) },
        setEnabled: {
            try await fixture.setEnabled($0, ifCurrent: $1)
        }
    )
}

private func historyRecord(
    _ identifiers: Int...
) throws -> IOSAcceptedTextHistoryRecord {
    try historyRecord(identifiers[...])
}

private func historyIdentifier(_ value: Int) -> UUID {
    UUID(
        uuidString: String(
            format: "00000000-0000-0000-0000-%012d",
            value
        )
    )!
}

private func historyToken(
    _ identifiers: Int...
) throws -> IOSAcceptedTextHistorySnapshotToken {
    IOSAcceptedTextHistorySnapshotToken(
        record: try historyRecord(identifiers)
    )
}

private func historyRecord(
    _ identifiers: [Int]
) throws -> IOSAcceptedTextHistoryRecord {
    try historyRecord(identifiers[...])
}

private func historyRecord(
    _ identifiers: ArraySlice<Int>
) throws -> IOSAcceptedTextHistoryRecord {
    IOSAcceptedTextHistoryRecord(
        isEnabled: true,
        entries: try identifiers.reversed().map { identifier in
            try IOSAcceptedTextHistoryEntry(
                resultID: historyIdentifier(identifier),
                text: "Accepted history text \(identifier)",
                createdAt: Date(
                    timeIntervalSince1970: TimeInterval(identifier)
                )
            )
        }
    )
}

@MainActor
private func historyOwnerEventually(
    _ condition: @escaping @MainActor () async -> Bool
) async throws {
    for _ in 0..<200 {
        if await condition() { return }
        await Task.yield()
    }
    throw HistoryOwnerFixtureError.failed
}
