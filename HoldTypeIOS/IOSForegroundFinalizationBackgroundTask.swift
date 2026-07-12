import UIKit

nonisolated struct IOSForegroundBackgroundTaskIdentifier:
    Equatable,
    Hashable,
    Sendable {
    fileprivate let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

nonisolated struct IOSForegroundBackgroundTaskClient: Sendable {
    typealias Begin = @MainActor @Sendable (
        String,
        @escaping @MainActor @Sendable () -> Void
    ) -> IOSForegroundBackgroundTaskIdentifier?
    typealias End = @MainActor @Sendable (
        IOSForegroundBackgroundTaskIdentifier
    ) -> Void

    let begin: Begin
    let end: End

    init(begin: @escaping Begin, end: @escaping End) {
        self.begin = begin
        self.end = end
    }

    nonisolated static let live = IOSForegroundBackgroundTaskClient(
        begin: { name, expiration in
            let identifier = UIApplication.shared.beginBackgroundTask(
                withName: name,
                expirationHandler: expiration
            )
            guard identifier != .invalid else { return nil }
            return IOSForegroundBackgroundTaskIdentifier(
                rawValue: identifier.rawValue
            )
        },
        end: { identifier in
            UIApplication.shared.endBackgroundTask(
                UIBackgroundTaskIdentifier(rawValue: identifier.rawValue)
            )
        }
    )
}

nonisolated enum IOSForegroundFinalizationBackgroundDisposition:
    Equatable,
    Sendable {
    case completed
    case failed
    case expired
    case timedOut
    case cancelled
    case busy
}

@MainActor
final class IOSForegroundFinalizationBackgroundTask {
    typealias Operation = @Sendable () async throws -> Void
    typealias Sleep = @Sendable (Duration) async throws -> Void

    static let assertionName = "HoldType foreground recording finalization"
    static let maximumDuration = Duration.seconds(10)

    private let client: IOSForegroundBackgroundTaskClient
    private let sleep: Sleep
    private var isRunning = false

    init(
        client: IOSForegroundBackgroundTaskClient = .live,
        sleep: @escaping Sleep = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.client = client
        self.sleep = sleep
    }

    func perform(
        _ operation: @escaping Operation
    ) async -> IOSForegroundFinalizationBackgroundDisposition {
        guard !isRunning else { return .busy }
        isRunning = true

        let race = IOSForegroundFinalizationRace()
        let identifier = client.begin(Self.assertionName) {
            Task {
                await race.resolve(.expired)
            }
        }
        let operationTask = Task.detached {
            do {
                try await operation()
                await race.resolve(.completed)
            } catch is CancellationError {
                await race.resolve(.cancelled)
            } catch {
                await race.resolve(.failed)
            }
        }
        let sleep = sleep
        let timeoutTask = Task.detached {
            do {
                try await sleep(Self.maximumDuration)
                await race.resolve(.timedOut)
            } catch {
                return
            }
        }

        let disposition = await withTaskCancellationHandler {
            await race.wait()
        } onCancel: {
            Task {
                await race.resolve(.cancelled)
            }
        }

        operationTask.cancel()
        timeoutTask.cancel()
        if let identifier {
            client.end(identifier)
        }
        isRunning = false
        return disposition
    }
}

private actor IOSForegroundFinalizationRace {
    private var resolution:
        IOSForegroundFinalizationBackgroundDisposition?
    private var continuation: CheckedContinuation<
        IOSForegroundFinalizationBackgroundDisposition,
        Never
    >?

    func wait() async -> IOSForegroundFinalizationBackgroundDisposition {
        if let resolution { return resolution }
        return await withCheckedContinuation { continuation in
            if let resolution {
                continuation.resume(returning: resolution)
            } else {
                self.continuation = continuation
            }
        }
    }

    func resolve(
        _ disposition: IOSForegroundFinalizationBackgroundDisposition
    ) {
        guard resolution == nil else { return }
        resolution = disposition
        continuation?.resume(returning: disposition)
        continuation = nil
    }
}

extension IOSForegroundBackgroundTaskIdentifier:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSForegroundBackgroundTaskIdentifier(<redacted>)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundBackgroundTaskClient:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSForegroundBackgroundTaskClient(<redacted>)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundFinalizationBackgroundDisposition:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSForegroundFinalizationBackgroundDisposition(<redacted>)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundFinalizationBackgroundTask:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSForegroundFinalizationBackgroundTask(<redacted>)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}
