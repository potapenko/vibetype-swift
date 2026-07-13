import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) @testable import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSForegroundVoiceLatestResultOwnerTests {
    @Test func constructionIsPassiveAndEveryDurableStateMapsWithoutIdentity()
        async throws {
        let record = try latestResultRecord(text: "exact accepted text")
        let expectation = IOSAcceptedOutputDeliveryExpectation(record: record)
        let saving = try latestSavingExpectation()
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(record)),
                .value(.savingResult(saving, priorResult: record)),
                .value(.savingResult(saving, priorResult: nil)),
                .value(.expired(expectation)),
                .value(.clockRollbackAmbiguous(expectation)),
                .value(.clearedCleanupPending),
                .value(.absent),
            ]
        )
        let owner = latestResultOwner(probe: probe)

        #expect(owner.presentation == .initial)
        #expect(owner.clearCommand == nil)
        let passiveSnapshot = await probe.snapshot()
        #expect(passiveSnapshot == .init(loads: 0, clears: []))

        _ = try await owner.loadForVoiceWorkflow()
        #expect(
            owner.presentation == IOSForegroundVoiceLatestResultPresentation(
                status: .ready,
                text: "exact accepted text",
                notice: nil
            )
        )
        #expect(owner.clearCommand != nil)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.presentation.status == .priorWhileSaving)
        #expect(owner.presentation.text == "exact accepted text")
        #expect(owner.clearCommand == nil)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.presentation.status == .savingWithoutPrior)
        #expect(owner.presentation.text == nil)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.presentation.status == .expired)
        #expect(owner.clearCommand == nil)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.presentation.status == .clockRollbackAmbiguous)
        #expect(owner.presentation.text == nil)
        #expect(owner.clearCommand != nil)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.presentation.status == .cleanupPending)
        #expect(owner.presentation.text == nil)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.presentation.status == .absent)
        #expect(owner.clearCommand == nil)
        let mappedSnapshot = await probe.snapshot()
        #expect(
            mappedSnapshot == .init(
                loads: 7,
                clears: [],
                maximumConcurrentCalls: 1
            )
        )
    }

    @Test func staleClearCommandCannotClearAReplacement() async throws {
        let old = try latestResultRecord(text: "old")
        let replacement = try latestResultRecord(text: "replacement")
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(old)),
                .value(.resultReady(replacement)),
            ]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        let stale = try #require(owner.clearCommand)
        _ = try await owner.loadForVoiceWorkflow()

        #expect(owner.clear(stale) == .stale)
        #expect(owner.presentation.text == "replacement")
        let snapshot = await probe.snapshot()
        #expect(snapshot.clears.isEmpty)
    }

    @Test func confirmedClearUsesExactExpectationAndHidesCleanupTombstone()
        async throws {
        let record = try latestResultRecord(text: "clear me")
        let expected = IOSAcceptedOutputDeliveryExpectation(record: record)
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record))],
            clears: [.value(.clearedCleanupPending)]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        let command = try #require(owner.clearCommand)
        #expect(owner.clear(command) == .accepted)
        #expect(owner.presentation.status == .clearing)
        #expect(owner.presentation.text == "clear me")
        #expect(owner.clearCommand == nil)

        await owner.waitUntilClearIsIdle()

        #expect(owner.presentation.status == .cleanupPending)
        #expect(owner.presentation.text == nil)
        #expect(owner.clearCommand == nil)
        let snapshot = await probe.snapshot()
        #expect(snapshot.clears == [expected])
    }

    @Test func failedClearReconcilesSameRecordAndKeepsItRetryable()
        async throws {
        let record = try latestResultRecord(text: "still durable")
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(record)),
                .value(.resultReady(record)),
            ],
            clears: [.failure]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await owner.waitUntilClearIsIdle()

        #expect(owner.presentation.status == .ready)
        #expect(owner.presentation.text == "still durable")
        #expect(owner.presentation.notice == .clearFailed)
        #expect(owner.clearCommand != nil)
    }

    @Test func failedClearPublishesNewerReplacementWithoutRetryingIt()
        async throws {
        let old = try latestResultRecord(text: "old selected result")
        let replacement = try latestResultRecord(text: "new durable result")
        let oldExpectation = IOSAcceptedOutputDeliveryExpectation(record: old)
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(old)),
                .value(.resultReady(replacement)),
            ],
            clears: [.failure]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await owner.waitUntilClearIsIdle()

        #expect(owner.presentation.status == .ready)
        #expect(owner.presentation.text == "new durable result")
        #expect(owner.presentation.notice == .resultChanged)
        let snapshot = await probe.snapshot()
        #expect(snapshot.clears == [oldExpectation])
    }

    @Test func unknownClearOutcomeHidesUnconfirmedText() async throws {
        let record = try latestResultRecord(text: "recoverable text")
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record)), .failure],
            clears: [.failure]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await owner.waitUntilClearIsIdle()

        #expect(owner.presentation.status == .unavailable)
        #expect(owner.presentation.text == nil)
        #expect(owner.presentation.notice == .clearStateUnknown)
        #expect(owner.clearCommand == nil)
    }

    @Test func genericLoadFailureHidesPreviouslyPublishedText() async throws {
        let record = try latestResultRecord(text: "previously confirmed")
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record)), .failure]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        await #expect(
            throws: IOSForegroundVoiceLatestResultOwnerError.self
        ) {
            _ = try await owner.loadForVoiceWorkflow()
        }

        #expect(owner.presentation.status == .unavailable)
        #expect(owner.presentation.text == nil)
        #expect(owner.presentation.notice == .loadFailed)
        #expect(owner.clearCommand == nil)
    }

    @Test func admittedClearOutlivesCallerAndSerializesACompetingLoad()
        async throws {
        let record = try latestResultRecord(text: "owned until tombstone")
        let clearStarted = LatestResultTestGate()
        let clearRelease = LatestResultTestGate()
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record)), .value(.absent)],
            clears: [.value(.cleared)],
            clearStarted: clearStarted,
            clearRelease: clearRelease
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await clearStarted.wait()

        let competingLoad = Task { @MainActor in
            try await owner.loadForVoiceWorkflow()
        }
        await Task.yield()
        let blockedSnapshot = await probe.snapshot()
        #expect(blockedSnapshot.loads == 1)
        #expect(blockedSnapshot.maximumConcurrentCalls == 1)

        await clearRelease.open()
        await owner.waitUntilClearIsIdle()
        _ = try await competingLoad.value

        #expect(owner.presentation.status == .absent)
        #expect(owner.presentation.text == nil)
        let finalSnapshot = await probe.snapshot()
        #expect(finalSnapshot.maximumConcurrentCalls == 1)
    }

    @Test func cancelledLoadDoesNotErasePreviouslyPublishedResult()
        async throws {
        let record = try latestResultRecord(text: "do not erase")
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record)), .cancelled]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        await #expect(throws: CancellationError.self) {
            _ = try await owner.loadForVoiceWorkflow()
        }

        #expect(owner.presentation.status == .ready)
        #expect(owner.presentation.text == "do not erase")
        #expect(owner.presentation.notice == nil)
    }

    @Test func newerQueuedLoadReplacesAnOlderOverlappingPublication()
        async throws {
        let old = try latestResultRecord(text: "old load")
        let replacement = try latestResultRecord(text: "newer queued load")
        let firstLoadStarted = LatestResultTestGate()
        let firstLoadRelease = LatestResultTestGate()
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(old)),
                .value(.resultReady(replacement)),
            ],
            firstLoadStarted: firstLoadStarted,
            firstLoadRelease: firstLoadRelease
        )
        let owner = latestResultOwner(probe: probe)

        let first = Task { @MainActor in
            try await owner.loadForVoiceWorkflow()
        }
        await firstLoadStarted.wait()
        let second = Task { @MainActor in
            try await owner.loadForVoiceWorkflow()
        }
        await Task.yield()
        await firstLoadRelease.open()
        _ = try await first.value
        _ = try await second.value

        #expect(owner.presentation.status == .ready)
        #expect(owner.presentation.text == "newer queued load")
        #expect(owner.clearCommand != nil)
    }

    @Test func postClearQueuedLoadCanPublishAReplacement() async throws {
        let old = try latestResultRecord(text: "clear target")
        let replacement = try latestResultRecord(text: "post-clear replacement")
        let clearStarted = LatestResultTestGate()
        let clearRelease = LatestResultTestGate()
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(old)),
                .value(.resultReady(replacement)),
            ],
            clears: [.value(.cleared)],
            clearStarted: clearStarted,
            clearRelease: clearRelease
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await clearStarted.wait()
        let replacementLoad = Task { @MainActor in
            try await owner.loadForVoiceWorkflow()
        }
        await Task.yield()
        await clearRelease.open()
        await owner.waitUntilClearIsIdle()
        _ = try await replacementLoad.value

        #expect(owner.presentation.status == .ready)
        #expect(owner.presentation.text == "post-clear replacement")
        #expect(owner.clearCommand != nil)
    }

    @Test func olderFailureCannotReplaceANewerSuccessfulPublication()
        async throws {
        let replacement = try latestResultRecord(text: "newer success")
        let firstPublicationStarted = LatestResultTestGate()
        let firstPublicationRelease = LatestResultTestGate()
        let probe = LatestResultClientProbe(
            loads: [.failure, .value(.resultReady(replacement))]
        )
        let owner = latestResultOwner(
            probe: probe,
            beforePublishing: { sequence in
                guard sequence == 1 else { return }
                await firstPublicationStarted.open()
                await firstPublicationRelease.wait()
            }
        )

        let olderFailure = Task { @MainActor in
            try await owner.loadForVoiceWorkflow()
        }
        await firstPublicationStarted.wait()
        _ = try await owner.loadForVoiceWorkflow()
        await firstPublicationRelease.open()
        await #expect(
            throws: IOSForegroundVoiceLatestResultOwnerError.self
        ) {
            _ = try await olderFailure.value
        }

        #expect(owner.presentation.status == .ready)
        #expect(owner.presentation.text == "newer success")
        #expect(owner.presentation.notice == nil)
        #expect(owner.clearCommand != nil)
    }

    @Test func newerQueuedFailureCannotBeOverwrittenByClearCompletion()
        async throws {
        let record = try latestResultRecord(text: "clear target")
        let clearPublicationStarted = LatestResultTestGate()
        let clearPublicationRelease = LatestResultTestGate()
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record)), .failure],
            clears: [.value(.cleared)]
        )
        let owner = latestResultOwner(
            probe: probe,
            beforePublishing: { sequence in
                guard sequence == 2 else { return }
                await clearPublicationStarted.open()
                await clearPublicationRelease.wait()
            }
        )

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await clearPublicationStarted.wait()
        await #expect(
            throws: IOSForegroundVoiceLatestResultOwnerError.self
        ) {
            _ = try await owner.loadForVoiceWorkflow()
        }
        await clearPublicationRelease.open()
        await owner.waitUntilClearIsIdle()

        #expect(owner.presentation.status == .unavailable)
        #expect(owner.presentation.text == nil)
        #expect(owner.presentation.notice == .loadFailed)
        #expect(owner.clearCommand == nil)
    }

    @Test func textBearingValuesAndCommandsAreReflectionRedacted()
        async throws {
        let secret = "TRANSCRIPT-SENTINEL-DO-NOT-REFLECT"
        let record = try latestResultRecord(text: secret)
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record))]
        )
        let owner = latestResultOwner(probe: probe)
        _ = try await owner.loadForVoiceWorkflow()
        let command = try #require(owner.clearCommand)

        for rendered in [
            String(describing: owner),
            String(reflecting: owner),
            String(describing: owner.presentation),
            String(reflecting: owner.presentation),
            String(describing: command),
            String(reflecting: command),
        ] {
            #expect(!rendered.contains(secret))
            #expect(rendered.localizedCaseInsensitiveContains("redacted"))
        }
        #expect(Mirror(reflecting: owner).children.isEmpty)
        #expect(Mirror(reflecting: owner.presentation).children.isEmpty)
        #expect(Mirror(reflecting: command).children.isEmpty)
    }
}

private nonisolated enum LatestResultProbeError: Error {
    case failed
}

private nonisolated enum LatestResultLoadStep: Sendable {
    case value(IOSForegroundVoiceLatestResultObservation)
    case failure
    case cancelled
}

private nonisolated enum LatestResultClearStep: Sendable {
    case value(IOSForegroundVoiceClearResult)
    case failure
}

private actor LatestResultClientProbe {
    nonisolated struct Snapshot: Equatable, Sendable {
        let loads: Int
        let clears: [IOSAcceptedOutputDeliveryExpectation]
        var maximumConcurrentCalls: Int = 0
    }

    private var loadSteps: [LatestResultLoadStep]
    private var clearSteps: [LatestResultClearStep]
    private let clearStarted: LatestResultTestGate?
    private let clearRelease: LatestResultTestGate?
    private let firstLoadStarted: LatestResultTestGate?
    private let firstLoadRelease: LatestResultTestGate?
    private var loadCount = 0
    private var clearExpectations: [IOSAcceptedOutputDeliveryExpectation] = []
    private var activeCalls = 0
    private var maximumConcurrentCalls = 0

    init(
        loads: [LatestResultLoadStep],
        clears: [LatestResultClearStep] = [],
        clearStarted: LatestResultTestGate? = nil,
        clearRelease: LatestResultTestGate? = nil,
        firstLoadStarted: LatestResultTestGate? = nil,
        firstLoadRelease: LatestResultTestGate? = nil
    ) {
        loadSteps = loads
        clearSteps = clears
        self.clearStarted = clearStarted
        self.clearRelease = clearRelease
        self.firstLoadStarted = firstLoadStarted
        self.firstLoadRelease = firstLoadRelease
    }

    func load() async throws -> IOSForegroundVoiceLatestResultObservation {
        beginCall()
        defer { endCall() }
        let index = loadCount
        loadCount += 1
        if index == 0 {
            await firstLoadStarted?.open()
            await firstLoadRelease?.wait()
        }
        guard !loadSteps.isEmpty else { throw LatestResultProbeError.failed }
        switch loadSteps.removeFirst() {
        case .value(let observation):
            return observation
        case .failure:
            throw LatestResultProbeError.failed
        case .cancelled:
            throw CancellationError()
        }
    }

    func clear(
        _ expected: IOSAcceptedOutputDeliveryExpectation
    ) async throws -> IOSForegroundVoiceClearResult {
        beginCall()
        defer { endCall() }
        clearExpectations.append(expected)
        await clearStarted?.open()
        await clearRelease?.wait()
        guard !clearSteps.isEmpty else { throw LatestResultProbeError.failed }
        switch clearSteps.removeFirst() {
        case .value(let result):
            return result
        case .failure:
            throw LatestResultProbeError.failed
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(
            loads: loadCount,
            clears: clearExpectations,
            maximumConcurrentCalls: maximumConcurrentCalls
        )
    }

    private func beginCall() {
        activeCalls += 1
        maximumConcurrentCalls = max(maximumConcurrentCalls, activeCalls)
    }

    private func endCall() {
        activeCalls -= 1
    }
}

private actor LatestResultTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

@MainActor
private func latestResultOwner(
    probe: LatestResultClientProbe,
    beforePublishing: @escaping
        IOSForegroundVoiceLatestResultOwner.BeforePublishing = { _ in }
) -> IOSForegroundVoiceLatestResultOwner {
    IOSForegroundVoiceLatestResultOwner(
        load: { try await probe.load() },
        clear: { try await probe.clear($0) },
        beforePublishing: beforePublishing
    )
}

private func latestResultRecord(
    text: String
) throws -> IOSAcceptedOutputDeliveryRecord {
    let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    let expiresAt = Date(
        timeIntervalSince1970:
            createdAt.timeIntervalSince1970
                + TimeInterval(
                    IOSAcceptedOutputDeliveryValidation.lifetimeMilliseconds
                ) / 1_000
    )
    return try IOSAcceptedOutputDeliveryRecord(
        revision: 1,
        deliveryID: UUID(),
        sessionID: UUID(),
        attemptID: UUID(),
        transcriptID: UUID(),
        acceptedText: text,
        outputIntent: .standard,
        createdAt: createdAt,
        updatedAt: createdAt,
        expiresAt: expiresAt,
        deliveryState: .pending,
        automaticInsertionPreferenceEnabled: false,
        keepLatestResult: true,
        publicationGeneration: 0,
        historyWrite: nil
    )
}

private func latestSavingExpectation()
    throws -> IOSForegroundVoiceSavingResultExpectation {
    let preparation = try IOSForegroundVoiceAcceptedOutputPreparation(
        deliveryID: UUID(),
        sessionID: UUID(),
        attemptID: UUID(),
        transcriptID: UUID(),
        rawAcceptedText: "saving",
        outputIntent: .standard,
        keepLatestResult: true
    )
    return IOSForegroundVoiceSavingResultExpectation(
        preparation: preparation.deliveryPreparation
    )
}
