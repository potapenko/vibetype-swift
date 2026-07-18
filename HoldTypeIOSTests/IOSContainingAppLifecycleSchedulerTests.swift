@_spi(HoldTypeIOSCore) import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSContainingAppLifecycleSchedulerTests {
    @Test func constructionIsPassiveAndInitialSceneActivationIsCoveredByLaunch()
        async throws {
        let recorder = LifecycleRecoveryRecorder(
            results: [.complete, .complete]
        )
        let scheduler = IOSContainingAppLifecycleScheduler { opportunity in
            await recorder.recover(opportunity)
        }

        await Task.yield()
        #expect(await recorder.opportunities().isEmpty)

        scheduler.scheduleProcessLaunch()
        scheduler.observeAggregateForeground(
            isActive: true,
            isInitialObservation: true
        )
        await scheduler.waitUntilIdle()
        #expect(await recorder.opportunities() == [.processLaunch])

        scheduler.observeAggregateForeground(
            isActive: false,
            isInitialObservation: true
        )
        scheduler.observeAggregateForeground(
            isActive: false,
            isInitialObservation: false
        )
        scheduler.observeAggregateForeground(
            isActive: true,
            isInitialObservation: false
        )
        await scheduler.waitUntilIdle()
        #expect(
            await recorder.opportunities()
                == [.processLaunch, .foregroundOpportunity]
        )
    }

    @Test func foregroundSignalQueuedDuringLaunchRunsAfterCurrentPass()
        async throws {
        let firstPass = LifecycleRecoveryLatch()
        let recorder = LifecycleRecoveryRecorder(
            results: [.complete, .complete],
            blockedPasses: [0: firstPass]
        )
        let scheduler = IOSContainingAppLifecycleScheduler { opportunity in
            await recorder.recover(opportunity)
        }

        scheduler.scheduleProcessLaunch()
        try await lifecycleEventually {
            await recorder.opportunities() == [.processLaunch]
        }
        scheduler.scheduleForeground()
        #expect(await recorder.opportunities() == [.processLaunch])

        await firstPass.open()
        await scheduler.waitUntilIdle()
        #expect(
            await recorder.opportunities()
                == [.processLaunch, .foregroundOpportunity]
        )
        #expect(await recorder.maximumConcurrentRecoveries() == 1)
        #expect(scheduler.latestDisposition == .complete)
    }

    @Test func aggregateForegroundRequiresValidatedFalseToTrueTransition()
        async {
        let recorder = LifecycleRecoveryRecorder(
            results: [.complete, .complete]
        )
        let scheduler = IOSContainingAppLifecycleScheduler { opportunity in
            await recorder.recover(opportunity)
        }

        scheduler.observeAggregateForeground(
            isActive: false,
            isInitialObservation: true
        )
        scheduler.scheduleProcessLaunch()
        await scheduler.waitUntilIdle()

        // The launch pass covers the first aggregate activation even when the
        // initial process snapshot did not yet contain an active scene.
        scheduler.observeAggregateForeground(
            isActive: true,
            isInitialObservation: false
        )
        scheduler.observeAggregateForeground(
            isActive: true,
            isInitialObservation: false
        )
        await scheduler.waitUntilIdle()
        #expect(await recorder.opportunities() == [.processLaunch])

        scheduler.observeAggregateForeground(
            isActive: false,
            isInitialObservation: false
        )
        scheduler.observeAggregateForeground(
            isActive: false,
            isInitialObservation: false
        )
        scheduler.observeAggregateForeground(
            isActive: true,
            isInitialObservation: false
        )
        scheduler.observeAggregateForeground(
            isActive: true,
            isInitialObservation: false
        )
        await scheduler.waitUntilIdle()
        #expect(
            await recorder.opportunities()
                == [.processLaunch, .foregroundOpportunity]
        )
    }

    @Test func foregroundBurstDuringActiveRecoveryCoalescesOnce()
        async throws {
        let firstPass = LifecycleRecoveryLatch()
        let recorder = LifecycleRecoveryRecorder(
            results: [.complete, .complete],
            blockedPasses: [0: firstPass]
        )
        let scheduler = IOSContainingAppLifecycleScheduler { opportunity in
            await recorder.recover(opportunity)
        }

        scheduler.scheduleProcessLaunch()
        try await lifecycleEventually {
            await recorder.opportunities().count == 1
        }
        for _ in 0..<25 {
            scheduler.scheduleForeground()
        }

        await firstPass.open()
        await scheduler.waitUntilIdle()
        #expect(
            await recorder.opportunities()
                == [.processLaunch, .foregroundOpportunity]
        )
        #expect(await recorder.maximumConcurrentRecoveries() == 1)
    }

    @Test func mixedQueuedBurstCoalescesToLaunchBeforeForeground()
        async throws {
        let firstPass = LifecycleRecoveryLatch()
        let recorder = LifecycleRecoveryRecorder(
            results: [.complete, .complete],
            blockedPasses: [0: firstPass]
        )
        let scheduler = IOSContainingAppLifecycleScheduler { opportunity in
            await recorder.recover(opportunity)
        }

        scheduler.scheduleProcessLaunch()
        try await lifecycleEventually {
            await recorder.opportunities().count == 1
        }
        for _ in 0..<25 {
            scheduler.scheduleForeground()
            scheduler.scheduleProcessLaunch()
        }

        await firstPass.open()
        await scheduler.waitUntilIdle()
        #expect(
            await recorder.opportunities()
                == [.processLaunch, .processLaunch]
        )
        #expect(await recorder.maximumConcurrentRecoveries() == 1)
    }

    @Test func pendingLaunchUsesQueuedForegroundAsOneLaunchRetry()
        async throws {
        let firstPass = LifecycleRecoveryLatch()
        let recorder = LifecycleRecoveryRecorder(
            results: [.pendingLocalRecovery, .complete],
            blockedPasses: [0: firstPass]
        )
        let scheduler = IOSContainingAppLifecycleScheduler { opportunity in
            await recorder.recover(opportunity)
        }

        scheduler.scheduleProcessLaunch()
        try await lifecycleEventually {
            await recorder.opportunities().count == 1
        }
        for _ in 0..<25 {
            scheduler.scheduleForeground()
        }

        await firstPass.open()
        await scheduler.waitUntilIdle()
        #expect(
            await recorder.opportunities()
                == [.processLaunch, .processLaunch]
        )
        #expect(await recorder.maximumConcurrentRecoveries() == 1)
        #expect(scheduler.latestDisposition == .complete)
    }

    @Test func deinitCancelsActiveRecoveryWithoutRetainingScheduler()
        async throws {
        let probe = LifecycleCancellationProbe()
        weak var weakScheduler: IOSContainingAppLifecycleScheduler?
        var scheduler: IOSContainingAppLifecycleScheduler? =
            IOSContainingAppLifecycleScheduler { opportunity in
                await probe.recover(opportunity)
            }
        weakScheduler = scheduler

        await Task.yield()
        #expect(await probe.opportunities().isEmpty)
        scheduler?.scheduleProcessLaunch()
        try await lifecycleEventually { await probe.didStart() }

        scheduler = nil
        try await lifecycleEventually {
            let wasCancelled = await probe.wasCancelled()
            return weakScheduler == nil && wasCancelled
        }
        #expect(await probe.opportunities() == [.processLaunch])
    }
}

private actor LifecycleRecoveryRecorder {
    private let results: [IOSV1ContainingAppRecoveryDisposition]
    private let blockedPasses: [Int: LifecycleRecoveryLatch]
    private var calls: [IOSV1ContainingAppRecoveryOpportunity] = []
    private var activeRecoveries = 0
    private var maximumActiveRecoveries = 0

    init(
        results: [IOSV1ContainingAppRecoveryDisposition],
        blockedPasses: [Int: LifecycleRecoveryLatch] = [:]
    ) {
        self.results = results
        self.blockedPasses = blockedPasses
    }

    func recover(
        _ opportunity: IOSV1ContainingAppRecoveryOpportunity
    ) async -> IOSV1ContainingAppRecoveryDisposition {
        let index = calls.count
        calls.append(opportunity)
        activeRecoveries += 1
        maximumActiveRecoveries = max(
            maximumActiveRecoveries,
            activeRecoveries
        )
        if let latch = blockedPasses[index] {
            await latch.wait()
        }
        activeRecoveries -= 1
        guard results.indices.contains(index) else {
            return .pendingLocalRecovery
        }
        return results[index]
    }

    func opportunities() -> [IOSV1ContainingAppRecoveryOpportunity] {
        calls
    }

    func maximumConcurrentRecoveries() -> Int {
        maximumActiveRecoveries
    }
}

private actor LifecycleCancellationProbe {
    private var calls: [IOSV1ContainingAppRecoveryOpportunity] = []
    private var cancellationObserved = false

    func recover(
        _ opportunity: IOSV1ContainingAppRecoveryOpportunity
    ) async -> IOSV1ContainingAppRecoveryDisposition {
        calls.append(opportunity)
        do {
            try await Task.sleep(for: .seconds(3_600))
            return .complete
        } catch {
            cancellationObserved = true
            return .pendingLocalRecovery
        }
    }

    func didStart() -> Bool { !calls.isEmpty }

    func wasCancelled() -> Bool { cancellationObserved }

    func opportunities() -> [IOSV1ContainingAppRecoveryOpportunity] { calls }
}

private actor LifecycleRecoveryLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private func lifecycleEventually(
    _ predicate: @escaping @MainActor @Sendable () async -> Bool
) async throws {
    for _ in 0..<100 {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for containing-app lifecycle recovery.")
}
