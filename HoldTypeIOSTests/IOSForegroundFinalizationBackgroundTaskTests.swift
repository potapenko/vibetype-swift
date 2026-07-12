import Foundation
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSForegroundFinalizationBackgroundTaskTests {
    @Test func completionUsesOneNamedAssertionAndEndsItExactlyOnce()
        async {
        let system = BackgroundTaskFake()
        let timeout = FinalizationLatch()
        let adapter = makeAdapter(system: system, timeout: timeout)

        let result = await adapter.perform {}

        #expect(result == .completed)
        #expect(system.beginNames == [
            IOSForegroundFinalizationBackgroundTask.assertionName
        ])
        #expect(system.ended == [.init(rawValue: 1)])
        #expect(
            IOSForegroundFinalizationBackgroundTask.maximumDuration
                == .seconds(10)
        )
        await timeout.open()
    }

    @Test func deniedAssertionStillRunsBoundedForegroundWork() async {
        let system = BackgroundTaskFake(grantsAssertion: false)
        let timeout = FinalizationLatch()
        let adapter = makeAdapter(system: system, timeout: timeout)
        let work = FinalizationWorkRecorder()

        let result = await adapter.perform {
            await work.record()
        }

        #expect(result == .completed)
        let didRun = await work.didRun()
        #expect(didRun)
        #expect(system.beginNames.count == 1)
        #expect(system.ended.isEmpty)
        await timeout.open()
    }

    @Test func systemExpirationWinsAndLateWorkCannotEndTwice()
        async throws {
        let system = BackgroundTaskFake()
        let timeout = FinalizationLatch()
        let work = FinalizationLatch()
        let adapter = makeAdapter(system: system, timeout: timeout)

        async let pending = adapter.perform {
            try await work.sleep(for: .seconds(99))
        }
        try await finalizationEventually {
            guard system.expiration != nil else { return false }
            return await work.requestedDurations().count == 1
        }
        system.expire()
        let result = await pending
        #expect(result == .expired)
        #expect(system.ended == [.init(rawValue: 1)])

        await work.open()
        await timeout.open()
        await Task.yield()
        #expect(system.ended == [.init(rawValue: 1)])
    }

    @Test func tenSecondWatchdogWinsAndCancelsSuspendedWork()
        async throws {
        let system = BackgroundTaskFake()
        let timeout = FinalizationLatch()
        let work = FinalizationLatch()
        let adapter = makeAdapter(system: system, timeout: timeout)

        async let pending = adapter.perform {
            try await work.sleep(for: .seconds(99))
        }
        try await finalizationEventually {
            await timeout.requestedDurations() == [.seconds(10)]
        }
        await timeout.open()
        let result = await pending
        #expect(result == .timedOut)
        #expect(system.ended == [.init(rawValue: 1)])
        await work.open()
    }

    @Test func callerCancellationAndOperationFailureAreTyped()
        async throws {
        let cancellationSystem = BackgroundTaskFake()
        let cancellationTimeout = FinalizationLatch()
        let work = FinalizationLatch()
        let cancellationAdapter = makeAdapter(
            system: cancellationSystem,
            timeout: cancellationTimeout
        )
        let task = Task { @MainActor in
            await cancellationAdapter.perform {
                try await work.sleep(for: .seconds(99))
            }
        }
        try await finalizationEventually {
            await work.requestedDurations().count == 1
        }
        task.cancel()
        let cancellationResult = await task.value
        #expect(cancellationResult == .cancelled)
        #expect(cancellationSystem.ended == [.init(rawValue: 1)])
        await work.open()
        await cancellationTimeout.open()

        let failureSystem = BackgroundTaskFake()
        let failureTimeout = FinalizationLatch()
        let failureAdapter = makeAdapter(
            system: failureSystem,
            timeout: failureTimeout
        )
        let failureResult = await failureAdapter.perform {
            throw FinalizationTestError.expected
        }
        #expect(failureResult == .failed)
        #expect(failureSystem.ended == [.init(rawValue: 1)])
        await failureTimeout.open()
    }

    @Test func concurrentCallIsBusyAndCannotAcquireASecondAssertion()
        async throws {
        let system = BackgroundTaskFake()
        let timeout = FinalizationLatch()
        let work = FinalizationLatch()
        let adapter = makeAdapter(system: system, timeout: timeout)

        async let first = adapter.perform {
            try await work.sleep(for: .seconds(99))
        }
        try await finalizationEventually {
            await work.requestedDurations().count == 1
        }
        let competing = await adapter.perform {}
        #expect(competing == .busy)
        #expect(system.beginNames.count == 1)

        system.expire()
        let result = await first
        #expect(result == .expired)
        await work.open()
        await timeout.open()
    }

    @Test func diagnosticsAndReflectionAreRedacted() {
        let system = BackgroundTaskFake()
        let timeout = FinalizationLatch()
        let adapter = makeAdapter(system: system, timeout: timeout)
        let identifier = IOSForegroundBackgroundTaskIdentifier(rawValue: 42)

        for value in [
            String(describing: identifier),
            String(reflecting: identifier),
            String(describing: system.client),
            String(reflecting: system.client),
            String(describing:
                IOSForegroundFinalizationBackgroundDisposition.expired),
            String(reflecting:
                IOSForegroundFinalizationBackgroundDisposition.expired),
            String(describing: adapter),
            String(reflecting: adapter),
        ] {
            #expect(value.contains("<redacted>"))
            #expect(!value.contains("42"))
        }
        #expect(Mirror(reflecting: identifier).children.isEmpty)
        #expect(Mirror(reflecting: system.client).children.isEmpty)
        #expect(Mirror(reflecting: adapter).children.isEmpty)
    }

    private func makeAdapter(
        system: BackgroundTaskFake,
        timeout: FinalizationLatch
    ) -> IOSForegroundFinalizationBackgroundTask {
        IOSForegroundFinalizationBackgroundTask(
            client: system.client,
            sleep: { duration in
                try await timeout.sleep(for: duration)
            }
        )
    }
}

@MainActor
private final class BackgroundTaskFake {
    let grantsAssertion: Bool
    private(set) var beginNames: [String] = []
    private(set) var ended: [IOSForegroundBackgroundTaskIdentifier] = []
    private(set) var expiration: (@MainActor @Sendable () -> Void)?

    init(grantsAssertion: Bool = true) {
        self.grantsAssertion = grantsAssertion
    }

    var client: IOSForegroundBackgroundTaskClient {
        IOSForegroundBackgroundTaskClient(
            begin: { [weak self] name, expiration in
                guard let self else { return nil }
                beginNames.append(name)
                self.expiration = expiration
                guard grantsAssertion else { return nil }
                return IOSForegroundBackgroundTaskIdentifier(rawValue: 1)
            },
            end: { [weak self] identifier in
                self?.ended.append(identifier)
            }
        )
    }

    func expire() {
        expiration?()
    }
}

private actor FinalizationLatch {
    private var durations: [Duration] = []
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async throws {
        durations.append(duration)
        if isOpen { return }
        try Task.checkCancellation()
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
        try Task.checkCancellation()
    }

    func requestedDurations() -> [Duration] { durations }

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

private actor FinalizationWorkRecorder {
    private var ran = false

    func record() { ran = true }
    func didRun() -> Bool { ran }
}

private enum FinalizationTestError: Error {
    case expected
}

@MainActor
private func finalizationEventually(
    _ predicate: @escaping @MainActor @Sendable () async -> Bool
) async throws {
    for _ in 0..<100 {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for finalization adapter state.")
}
