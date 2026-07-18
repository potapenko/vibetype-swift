import Foundation

@MainActor
protocol RecordingDurationMonitoring: AnyObject {
    func start(
        maximumDurationWholeSeconds: Int,
        onElapsedWholeSecond: @escaping @MainActor (Int) -> Void
    )
    func stop()
}

@MainActor
final class ContinuousRecordingDurationMonitor: RecordingDurationMonitoring {
    private var task: Task<Void, Never>?

    func start(
        maximumDurationWholeSeconds: Int,
        onElapsedWholeSecond: @escaping @MainActor (Int) -> Void
    ) {
        stop()
        let resolvedMaximumDurationWholeSeconds = max(
            1,
            maximumDurationWholeSeconds
        )
        task = Task { @MainActor in
            let clock = ContinuousClock()
            let startedAt = clock.now
            var lastDeliveredSecond = 0

            while !Task.isCancelled,
                  lastDeliveredSecond < resolvedMaximumDurationWholeSeconds {
                do {
                    try await clock.sleep(for: .seconds(1))
                } catch {
                    return
                }

                let elapsedComponents = startedAt.duration(to: clock.now).components
                let elapsedWholeSecond = min(
                    resolvedMaximumDurationWholeSeconds,
                    max(0, Int(elapsedComponents.seconds))
                )
                guard elapsedWholeSecond > lastDeliveredSecond else {
                    continue
                }

                for second in (lastDeliveredSecond + 1)...elapsedWholeSecond {
                    guard !Task.isCancelled else {
                        return
                    }
                    onElapsedWholeSecond(second)
                }
                lastDeliveredSecond = elapsedWholeSecond
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
