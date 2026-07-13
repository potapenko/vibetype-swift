@MainActor
final class IOSVoiceSceneLifecycleBinding:
    CustomDebugStringConvertible,
    CustomReflectable,
    CustomStringConvertible {
    private weak var registry: IOSVoiceSceneRegistry?
    private let scheduler: IOSContainingAppLifecycleScheduler
    private var eventSubscription: IOSVoiceSceneEventSubscription?

    init(
        registry: IOSVoiceSceneRegistry,
        scheduler: IOSContainingAppLifecycleScheduler
    ) {
        self.registry = registry
        self.scheduler = scheduler

        scheduler.observeAggregateForeground(
            isActive: registry.snapshot.isForegroundActive,
            isInitialObservation: true
        )
        eventSubscription = registry.observeEvents { [weak self] event in
            self?.observe(event)
        }
    }

    var description: String { "IOSVoiceSceneLifecycleBinding" }
    var debugDescription: String { description }

    var customMirror: Mirror {
        Mirror(self, children: ["binding": "content-free"])
    }

    @discardableResult
    func cancel() -> Bool {
        guard let eventSubscription else { return false }
        self.eventSubscription = nil
        return eventSubscription.cancel()
    }

    private func observe(_ event: IOSVoiceSceneRegistryEvent) {
        guard let registry, registry.validate(event) else { return }

        switch event.kind {
        case .aggregateBecameActive:
            scheduler.observeAggregateForeground(
                isActive: true,
                isInitialObservation: false
            )
        case .lastActiveSceneLost:
            scheduler.observeAggregateForeground(
                isActive: false,
                isInitialObservation: false
            )
        case .initiatingSceneBecameUnavailable,
             .initiatingSceneReactivatedAfterPermission:
            break
        }
    }
}
