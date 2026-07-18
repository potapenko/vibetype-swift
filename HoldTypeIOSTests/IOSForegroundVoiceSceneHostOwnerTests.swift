import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSForegroundVoiceSceneHostOwnerTests {
    @Test func constructionIsPassiveAndDiagnosticsAreRedacted() {
        let fixture = VoiceSceneHostClientFixture()
        let registry = IOSVoiceSceneRegistry()
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient(),
            sceneRegistry: registry
        )
        let owner = IOSForegroundVoiceSceneHostOwner(
            controller: controller,
            sceneRegistry: registry
        )

        #expect(registry.snapshot.registeredSceneCount == 0)
        #expect(fixture.observeCallCount == 0)
        #expect(fixture.runStartCallCount == 0)
        #expect(owner.promptPresentation == .unavailable)
        #expect(owner.actionCommands.isEmpty)
        #expect(String(describing: owner) == "IOSForegroundVoiceSceneHostOwner")
        #expect(String(reflecting: owner) == "IOSForegroundVoiceSceneHostOwner")

        var diagnosticDump = ""
        dump(owner, to: &diagnosticDump)
        #expect(!diagnosticDump.contains("sceneFacade"))
        #expect(!diagnosticDump.contains("controller"))
        #expect(!diagnosticDump.contains("sceneRegistry"))
    }

    @Test func explicitRegistrationTracksActivityAndRetiresExactlyOnce() {
        let fixture = VoiceSceneHostClientFixture()
        let registry = IOSVoiceSceneRegistry()
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient(),
            sceneRegistry: registry
        )
        let owner = IOSForegroundVoiceSceneHostOwner(
            controller: controller,
            sceneRegistry: registry
        )

        #expect(owner.updateActivity(.active) == .stale)
        #expect(owner.registerOrUpdateActivity(.active) == .accepted)
        #expect(owner.register(initialActivity: .background) == .unchanged)
        #expect(registry.snapshot.registeredSceneCount == 1)
        #expect(registry.snapshot.foregroundActiveSceneCount == 1)

        #expect(owner.updateActivity(.background) == .accepted)
        #expect(owner.updateActivity(.background) == .unchanged)
        #expect(registry.snapshot.registeredSceneCount == 1)
        #expect(registry.snapshot.foregroundActiveSceneCount == 0)

        #expect(owner.unregister() == .accepted)
        #expect(owner.unregister() == .stale)
        #expect(owner.promptPresentation == .unavailable)
        #expect(registry.snapshot.registeredSceneCount == 0)
        #expect(owner.updateActivity(.active) == .stale)
        #expect(owner.registerOrUpdateActivity(.active) == .stale)
        #expect(owner.register(initialActivity: .active) == .stale)
        #expect(registry.snapshot.registeredSceneCount == 0)
    }

    @Test func lastReleaseOffMainUnregistersTheExactScene() async throws {
        let fixture = VoiceSceneHostClientFixture()
        let registry = IOSVoiceSceneRegistry()
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient(),
            sceneRegistry: registry
        )
        var owner: IOSForegroundVoiceSceneHostOwner? =
            IOSForegroundVoiceSceneHostOwner(
                controller: controller,
                sceneRegistry: registry
            )
        #expect(owner?.register(initialActivity: .active) == .accepted)
        #expect(registry.snapshot.registeredSceneCount == 1)

        weak let releasedOwner = owner
        let releaseBox = VoiceSceneHostCrossExecutorReleaseBox(
            try #require(owner)
        )
        owner = nil
        #expect(releasedOwner != nil)

        await Task.detached {
            releaseBox.release()
        }.value

        try await voiceSceneHostEventually {
            releasedOwner == nil
                && registry.snapshot.registeredSceneCount == 0
        }
        #expect(registry.snapshot.foregroundActiveSceneCount == 0)
    }

    @Test func submitUsesExactFacadeAndPromptOwnershipNeverTransfers()
        async throws {
        let fixture = VoiceSceneHostClientFixture()
        let registry = IOSVoiceSceneRegistry()
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient(),
            sceneRegistry: registry
        )
        let initiatingOwner = IOSForegroundVoiceSceneHostOwner(
            controller: controller,
            sceneRegistry: registry
        )
        let otherOwner = IOSForegroundVoiceSceneHostOwner(
            controller: controller,
            sceneRegistry: registry
        )

        #expect(initiatingOwner.register(initialActivity: .active) == .accepted)
        #expect(otherOwner.register(initialActivity: .active) == .accepted)
        await controller.activate()
        let command = try #require(
            initiatingOwner.actionCommands.first {
                $0.action == .startStandard
            }
        )

        #expect(initiatingOwner.submit(command) == .accepted)
        #expect(initiatingOwner.promptPresentation == .ownedByThisScene)
        #expect(otherOwner.promptPresentation == .ownedByAnotherScene)
        try await voiceSceneHostEventually {
            fixture.runStartCallCount == 1
        }
        let firstLease = try #require(fixture.lastStartLease)

        #expect(initiatingOwner.unregister() == .accepted)
        #expect(initiatingOwner.updateActivity(.active) == .stale)
        #expect(initiatingOwner.submit(command) == .unavailable)
        #expect(initiatingOwner.promptPresentation == .unavailable)
        #expect(otherOwner.promptPresentation == .available)
        #expect(registry.validateContinuation(firstLease) == .stale)
        #expect(!firstLease.finish())

        fixture.resolveStart()
        try await voiceSceneHostEventually {
            controller.presentation.phase == .inactive
        }

        let nextCommand = try #require(
            otherOwner.actionCommands.first {
                $0.action == .startStandard
            }
        )
        #expect(otherOwner.submit(nextCommand) == .accepted)
        #expect(otherOwner.promptPresentation == .ownedByThisScene)
        try await voiceSceneHostEventually {
            fixture.runStartCallCount == 2
        }
        fixture.resolveStart()
        try await voiceSceneHostEventually {
            controller.presentation.phase == .inactive
        }
        #expect(otherOwner.promptPresentation == .available)
    }

}

@MainActor
private final class VoiceSceneHostClientFixture {
    private(set) var observeCallCount = 0
    private(set) var runStartCallCount = 0
    private(set) var lastStartLease: IOSVoiceSceneStartLease?

    private var startContinuation:
        CheckedContinuation<IOSForegroundVoiceResolution, Never>?

    func makeClient() -> IOSForegroundVoiceClient {
        IOSForegroundVoiceClient(
            observe: {
                await self.observe()
            },
            runStart: { _, lease, _, _ in
                await self.runStart(lease: lease)
            },
            run: { _, _, _ in
                voiceSceneHostResolution()
            },
            finishUtterance: { _ in .unavailable }
        )
    }

    func resolveStart() {
        guard let startContinuation else {
            Issue.record("Expected a suspended scene-host Start.")
            return
        }
        self.startContinuation = nil
        startContinuation.resume(returning: voiceSceneHostResolution())
    }

    private func observe() -> IOSForegroundVoiceObservation {
        observeCallCount += 1
        return voiceSceneHostObservation()
    }

    private func runStart(
        lease: IOSVoiceSceneStartLease
    ) async -> IOSForegroundVoiceResolution {
        runStartCallCount += 1
        lastStartLease = lease
        let resolution = await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
        _ = lease.finish()
        return resolution
    }
}

private func voiceSceneHostObservation() -> IOSForegroundVoiceObservation {
    IOSForegroundVoiceObservation(
        setup: .ready,
        recovery: .none
    )
}

private func voiceSceneHostResolution() -> IOSForegroundVoiceResolution {
    IOSForegroundVoiceResolution(
        observation: voiceSceneHostObservation()
    )
}

@MainActor
private func voiceSceneHostEventually(
    _ predicate: @escaping @MainActor () -> Bool
) async throws {
    for _ in 0..<300 {
        if predicate() { return }
        await Task.yield()
    }
    throw VoiceSceneHostTestTimeout()
}

private struct VoiceSceneHostTestTimeout: Error {}

private nonisolated final class VoiceSceneHostCrossExecutorReleaseBox<
    Value: AnyObject
>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    init(_ value: Value) {
        self.value = value
    }

    func release() {
        lock.lock()
        value = nil
        lock.unlock()
    }
}
