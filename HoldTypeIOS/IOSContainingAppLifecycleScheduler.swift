@_spi(HoldTypeIOSCore) import HoldTypePersistence

@MainActor
final class IOSContainingAppLifecycleScheduler {
    typealias Recovery = @Sendable (
        IOSV1ContainingAppRecoveryOpportunity
    ) async -> IOSV1ContainingAppRecoveryDisposition

    private let recover: Recovery
    private var activeTask: Task<Void, Never>?
    // Signals may request one bounded follow-up pass, but a disposition never
    // creates an automatic retry loop.
    private var pendingOpportunity:
        IOSV1ContainingAppRecoveryOpportunity?
    private var processLaunchRecoveryCompleted = false
    private var observedInitialAggregateForeground = false
    private var aggregateForegroundIsActive = false
    private var initialActivationCoveredByLaunch = false

    private(set) var latestDisposition:
        IOSV1ContainingAppRecoveryDisposition = .pendingLocalRecovery

    init(recover: @escaping Recovery) {
        self.recover = recover
    }

    func scheduleProcessLaunch() {
        enqueue(.processLaunch)
    }

    func scheduleForeground() {
        enqueue(.foregroundOpportunity)
    }

    func observeAggregateForeground(
        isActive: Bool,
        isInitialObservation: Bool
    ) {
        if !observedInitialAggregateForeground {
            observedInitialAggregateForeground = true
            aggregateForegroundIsActive = isActive
            initialActivationCoveredByLaunch = isActive
            return
        }

        // A process binding seeds exactly one initial aggregate snapshot. The
        // The aggregate source may repeat initial observations, so refresh
        // its baseline without scheduling lifecycle work.
        if isInitialObservation {
            aggregateForegroundIsActive = isActive
            if isActive { initialActivationCoveredByLaunch = true }
            return
        }
        guard aggregateForegroundIsActive != isActive else { return }
        aggregateForegroundIsActive = isActive
        guard isActive else { return }
        guard initialActivationCoveredByLaunch else {
            initialActivationCoveredByLaunch = true
            return
        }
        scheduleForeground()
    }

    func waitUntilIdle() async {
        while let task = activeTask {
            await task.value
        }
    }

    private func enqueue(
        _ signal: IOSV1ContainingAppRecoveryOpportunity
    ) {
        pendingOpportunity = merged(
            pendingOpportunity,
            with: signal
        )
        startNextIfNeeded()
    }

    private func startNextIfNeeded() {
        guard activeTask == nil,
              let opportunity = takeNextOpportunity() else {
            return
        }
        let recover = recover
        activeTask = Task { [weak self] in
            let disposition = await recover(opportunity)
            guard let self else { return }
            finish(
                opportunity,
                disposition: disposition
            )
        }
    }

    private func takeNextOpportunity()
        -> IOSV1ContainingAppRecoveryOpportunity? {
        guard let pendingOpportunity else { return nil }
        self.pendingOpportunity = nil
        if pendingOpportunity == .foregroundOpportunity,
           !processLaunchRecoveryCompleted {
            return .processLaunch
        }
        return pendingOpportunity
    }

    private func merged(
        _ pending: IOSV1ContainingAppRecoveryOpportunity?,
        with signal: IOSV1ContainingAppRecoveryOpportunity
    ) -> IOSV1ContainingAppRecoveryOpportunity {
        guard let pending else { return signal }
        // Launch recovery is the stronger opportunity and covers coalesced
        // foreground work while preserving launch-before-foreground ordering.
        return switch (pending, signal) {
        case (.processLaunch, _), (_, .processLaunch):
            .processLaunch
        case (.foregroundOpportunity, .foregroundOpportunity):
            .foregroundOpportunity
        }
    }

    private func finish(
        _ opportunity: IOSV1ContainingAppRecoveryOpportunity,
        disposition: IOSV1ContainingAppRecoveryDisposition
    ) {
        latestDisposition = disposition
        if opportunity == .processLaunch,
           disposition == .complete {
            processLaunchRecoveryCompleted = true
        }
        activeTask = nil
        startNextIfNeeded()
    }

    deinit {
        activeTask?.cancel()
    }
}
