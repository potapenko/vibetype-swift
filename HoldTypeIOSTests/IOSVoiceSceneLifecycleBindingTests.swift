@_spi(HoldTypeIOSCore) import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSVoiceSceneLifecycleBindingTests {
    @Test func constructionSeedsCurrentAggregateWithoutRecoveryAndIsRedacted()
        async {
        let registry = IOSVoiceSceneRegistry()
        let scene = registry.registerScene(initialActivity: .active)
        let recorder = VoiceSceneLifecycleRecoveryRecorder()
        let scheduler = IOSContainingAppLifecycleScheduler { opportunity in
            await recorder.recover(opportunity)
        }
        let binding = IOSVoiceSceneLifecycleBinding(
            registry: registry,
            scheduler: scheduler
        )

        await Task.yield()
        #expect(await recorder.opportunities().isEmpty)
        #expect(registry.activeEventSubscriptionCount == 1)
        #expect(
            String(reflecting: binding)
                == "IOSVoiceSceneLifecycleBinding"
        )
        var dumpValue = ""
        dump(binding, to: &dumpValue)
        #expect(!dumpValue.contains("registry"))
        #expect(!dumpValue.contains("scheduler"))

        scheduler.scheduleProcessLaunch()
        await scheduler.waitUntilIdle()
        #expect(await recorder.opportunities() == [.processLaunch])

        #expect(scene.updateActivity(.inactive) == .accepted)
        #expect(scene.updateActivity(.active) == .accepted)
        #expect(scene.updateActivity(.active) == .unchanged)
        await scheduler.waitUntilIdle()
        #expect(
            await recorder.opportunities()
                == [.processLaunch, .foregroundOpportunity]
        )
    }

    @Test func staleAggregateEventsCannotConsumeLaunchCoveredFirstActivation()
        async {
        let registry = IOSVoiceSceneRegistry()
        let scene = registry.registerScene(initialActivity: .background)
        let reentrantMutation = VoiceSceneLifecycleReentrantMutation(
            scene: scene
        )
        let mutatingSubscription = registry.observeEvents { event in
            reentrantMutation.receive(event)
        }
        defer { mutatingSubscription.cancel() }

        let recorder = VoiceSceneLifecycleRecoveryRecorder()
        let scheduler = IOSContainingAppLifecycleScheduler { opportunity in
            await recorder.recover(opportunity)
        }
        let binding = IOSVoiceSceneLifecycleBinding(
            registry: registry,
            scheduler: scheduler
        )
        defer { binding.cancel() }

        scheduler.scheduleProcessLaunch()
        await scheduler.waitUntilIdle()

        #expect(scene.updateActivity(.active) == .accepted)
        await scheduler.waitUntilIdle()
        #expect(!registry.snapshot.isForegroundActive)
        #expect(await recorder.opportunities() == [.processLaunch])

        reentrantMutation.isEnabled = false
        #expect(scene.updateActivity(.active) == .accepted)
        await scheduler.waitUntilIdle()
        #expect(await recorder.opportunities() == [.processLaunch])

        #expect(scene.updateActivity(.inactive) == .accepted)
        #expect(scene.updateActivity(.active) == .accepted)
        await scheduler.waitUntilIdle()
        #expect(
            await recorder.opportunities()
                == [.processLaunch, .foregroundOpportunity]
        )
    }

    @Test func multiWindowAggregateAndPromptEventsScheduleOnlyOneForeground()
        async throws {
        let registry = IOSVoiceSceneRegistry()
        let initiating = registry.registerScene(initialActivity: .active)
        let other = registry.registerScene(initialActivity: .active)
        let recorder = VoiceSceneLifecycleRecoveryRecorder()
        let scheduler = IOSContainingAppLifecycleScheduler { opportunity in
            await recorder.recover(opportunity)
        }
        let binding = IOSVoiceSceneLifecycleBinding(
            registry: registry,
            scheduler: scheduler
        )
        defer { binding.cancel() }

        scheduler.scheduleProcessLaunch()
        await scheduler.waitUntilIdle()
        let lease = try #require(initiating.acquireStartLease())

        // Invalidating prompt ownership while another scene stays active is
        // not an aggregate foreground transition.
        #expect(initiating.unregister() == .accepted)
        #expect(registry.validateContinuation(lease) == .stale)
        await scheduler.waitUntilIdle()
        #expect(await recorder.opportunities() == [.processLaunch])

        #expect(other.updateActivity(.inactive) == .accepted)
        let third = registry.registerScene(initialActivity: .active)
        _ = registry.registerScene(initialActivity: .active)
        #expect(third.updateActivity(.inactive) == .accepted)
        await scheduler.waitUntilIdle()
        #expect(
            await recorder.opportunities()
                == [.processLaunch, .foregroundOpportunity]
        )
    }

    @Test func cancellationAndDeinitializationRemoveExactSubscription()
        async {
        let registry = IOSVoiceSceneRegistry()
        let scene = registry.registerScene(initialActivity: .active)
        let scheduler = IOSContainingAppLifecycleScheduler { _ in .complete }
        var binding: IOSVoiceSceneLifecycleBinding? =
            IOSVoiceSceneLifecycleBinding(
                registry: registry,
                scheduler: scheduler
            )
        weak let weakBinding = binding

        #expect(registry.activeEventSubscriptionCount == 1)
        #expect(binding?.cancel() == true)
        #expect(binding?.cancel() == false)
        #expect(registry.activeEventSubscriptionCount == 0)
        binding = nil
        #expect(weakBinding == nil)
        #expect(scene.updateActivity(.inactive) == .accepted)
        #expect(scene.updateActivity(.active) == .accepted)
        await scheduler.waitUntilIdle()

        let deinitRegistry = IOSVoiceSceneRegistry()
        let deinitScheduler = IOSContainingAppLifecycleScheduler { _ in
            .complete
        }
        var deinitBinding: IOSVoiceSceneLifecycleBinding? =
            IOSVoiceSceneLifecycleBinding(
                registry: deinitRegistry,
                scheduler: deinitScheduler
            )
        weak let weakDeinitBinding = deinitBinding
        #expect(deinitRegistry.activeEventSubscriptionCount == 1)

        deinitBinding = nil
        for _ in 0..<100
        where deinitRegistry.activeEventSubscriptionCount != 0 {
            await Task.yield()
        }
        #expect(weakDeinitBinding == nil)
        #expect(deinitRegistry.activeEventSubscriptionCount == 0)
    }
}

private actor VoiceSceneLifecycleRecoveryRecorder {
    private var values: [IOSV1ContainingAppRecoveryOpportunity] = []

    func recover(
        _ opportunity: IOSV1ContainingAppRecoveryOpportunity
    ) -> IOSV1ContainingAppRecoveryDisposition {
        values.append(opportunity)
        return .complete
    }

    func opportunities() -> [IOSV1ContainingAppRecoveryOpportunity] {
        values
    }
}

@MainActor
private final class VoiceSceneLifecycleReentrantMutation {
    let scene: IOSVoiceSceneFacade
    var isEnabled = true

    init(scene: IOSVoiceSceneFacade) {
        self.scene = scene
    }

    func receive(_ event: IOSVoiceSceneRegistryEvent) {
        guard isEnabled, event.kind == .aggregateBecameActive else { return }
        _ = scene.updateActivity(.inactive)
    }
}
