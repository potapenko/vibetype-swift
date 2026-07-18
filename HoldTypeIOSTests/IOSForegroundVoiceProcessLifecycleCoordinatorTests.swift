import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSForegroundVoiceProcessLifecycleCoordinatorTests {
    @Test
    func constructionIsPassive() async {
        let fixture = LifecycleVoiceClientFixture()
        let controller = IOSForegroundVoiceController(
            client: fixture.client
        )
        var refreshCount = 0
        _ = IOSForegroundVoiceProcessLifecycleCoordinator(
            controller: controller,
            refresh: { _ in
                refreshCount += 1
                return lifecycleRefresh()
            }
        )

        await Task.yield()
        #expect(refreshCount == 0)
        #expect(fixture.observeCount == 0)
        #expect(controller.presentation == .initial)
    }

    @Test
    func queuedLifecycleSignalsWaitForPrimaryPublicationAndRemainOrdered()
        async throws {
        let primaryGate = LifecycleAsyncGate()
        let fixture = LifecycleVoiceClientFixture(primaryGate: primaryGate)
        let controller = IOSForegroundVoiceController(client: fixture.client)
        await controller.activate()
        let scene = controller.sceneRegistry.registerScene(
            initialActivity: .active
        )
        let start = try #require(controller.actionCommands.first {
            $0.action == .startStandard
        })
        #expect(controller.submit(start, from: scene) == .accepted)
        await fixture.primaryDidStart.wait()

        var opportunities: [IOSV1ContainingAppRecoveryOpportunity] = []
        var publicationPhases: [VoiceWorkPhase] = []
        let coordinator = IOSForegroundVoiceProcessLifecycleCoordinator(
            controller: controller,
            refresh: { opportunity in
                opportunities.append(opportunity)
                publicationPhases.append(controller.presentation.phase)
                return lifecycleRefresh()
            }
        )
        let scheduler = IOSContainingAppLifecycleScheduler(
            recover: { opportunity in
                await coordinator.recover(opportunity)
            }
        )
        scheduler.scheduleProcessLaunch()
        scheduler.scheduleForeground()
        for _ in 0..<10 { await Task.yield() }
        #expect(opportunities.isEmpty)
        #expect(controller.presentation.phase == .arming)
        await controller.activate()
        #expect(fixture.observeCount == 1)

        await primaryGate.open()
        await scheduler.waitUntilIdle()

        #expect(opportunities == [.processLaunch, .foregroundOpportunity])
        #expect(publicationPhases == [.inactive, .inactive])
        #expect(fixture.primaryReturnCount == 1)
        #expect(controller.presentation.phase == .inactive)
        #expect(scheduler.latestDisposition == .complete)
    }

    @Test
    func cancellationHostileRefreshKeepsLeaseUntilChildReturns()
        async throws {
        let fixture = LifecycleVoiceClientFixture()
        let controller = IOSForegroundVoiceController(client: fixture.client)
        await controller.activate()
        let scene = controller.sceneRegistry.registerScene(
            initialActivity: .active
        )
        let refreshGate = LifecycleAsyncGate()
        let refreshStarted = LifecycleAsyncGate()
        let coordinator = IOSForegroundVoiceProcessLifecycleCoordinator(
            controller: controller,
            refresh: { _ in
                await refreshStarted.open()
                await refreshGate.wait()
                return lifecycleRefresh()
            }
        )
        let task = Task { await coordinator.recover(.foregroundOpportunity) }
        await refreshStarted.wait()
        task.cancel()

        let command = try #require(controller.actionCommands.first {
            $0.action == .startStandard
        })
        #expect(controller.submit(command, from: scene) == .unavailable)

        await refreshGate.open()
        #expect(await task.value == .pendingLocalRecovery)
        #expect(controller.submit(command, from: scene) == .accepted)
        try await lifecycleCoordinatorEventually {
            fixture.primaryReturnCount == 1
        }
    }

    @Test
    func diagnosticsAreRedacted() {
        let fixture = LifecycleVoiceClientFixture()
        let controller = IOSForegroundVoiceController(client: fixture.client)
        let coordinator = IOSForegroundVoiceProcessLifecycleCoordinator(
            controller: controller,
            refresh: { _ in lifecycleRefresh() }
        )
        let refresh = lifecycleRefresh()

        #expect(String(describing: coordinator).contains("<redacted>"))
        #expect(Mirror(reflecting: coordinator).children.isEmpty)
        #expect(String(describing: refresh).contains("<redacted>"))
        #expect(Mirror(reflecting: refresh).children.isEmpty)
    }
}

private final class LifecycleVoiceClientFixture: @unchecked Sendable {
    let primaryDidStart = LifecycleAsyncGate()
    private let lock = NSLock()
    private let primaryGate: LifecycleAsyncGate?
    private var observeCountStorage = 0
    private var primaryReturnCountStorage = 0

    init(primaryGate: LifecycleAsyncGate? = nil) {
        self.primaryGate = primaryGate
    }

    var observeCount: Int { lock.withLock { observeCountStorage } }
    var primaryReturnCount: Int {
        lock.withLock { primaryReturnCountStorage }
    }

    var client: IOSForegroundVoiceClient {
        IOSForegroundVoiceClient(
            observe: { [weak self] in
                guard let self else { return lifecycleObservation() }
                self.lock.withLock { self.observeCountStorage += 1 }
                return lifecycleObservation()
            },
            runStart: { [weak self] _, lease, _, _ in
                guard let self else {
                    await lease.finish()
                    return IOSForegroundVoiceResolution(
                        observation: lifecycleObservation()
                    )
                }
                await self.primaryDidStart.open()
                await self.primaryGate?.wait()
                self.lock.withLock { self.primaryReturnCountStorage += 1 }
                await lease.finish()
                return IOSForegroundVoiceResolution(
                    observation: lifecycleObservation()
                )
            },
            run: { _, _, _ in
                IOSForegroundVoiceResolution(
                    observation: lifecycleObservation()
                )
            },
            finishUtterance: { _ in .unavailable }
        )
    }
}

private actor LifecycleAsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

private func lifecycleObservation() -> IOSForegroundVoiceObservation {
    IOSForegroundVoiceObservation(
        setup: .ready,
        recovery: .none,
        latestAvailability: .absent
    )
}

private func lifecycleRefresh() -> IOSForegroundVoiceLifecycleRefresh {
    IOSForegroundVoiceLifecycleRefresh(
        observation: lifecycleObservation(),
        disposition: .complete
    )
}

@MainActor
private func lifecycleCoordinatorEventually(
    _ condition: @MainActor () -> Bool
) async throws {
    for _ in 0..<100 where !condition() { await Task.yield() }
    guard condition() else { throw LifecycleCoordinatorTestError.timedOut }
}

private enum LifecycleCoordinatorTestError: Error {
    case timedOut
}
