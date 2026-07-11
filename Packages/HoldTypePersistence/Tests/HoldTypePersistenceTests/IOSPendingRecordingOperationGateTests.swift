import Foundation
import Testing
@testable import HoldTypePersistence

struct IOSPendingRecordingOperationGateTests {
    @Test func transactionsRemainFIFOAcrossSuspension() async throws {
        let events = GateEventRecorder()
        let firstBlocker = AsyncOperationBlocker()
        let gate = IOSPendingRecordingOperationGate { event in
            events.append(event)
        }

        let first = Task {
            try await gate.perform {
                events.appendValue(1)
                await firstBlocker.wait()
                events.appendValue(2)
                return 1
            }
        }
        await firstBlocker.waitUntilSuspended()

        let second = Task {
            try await gate.perform {
                events.appendValue(3)
                return 2
            }
        }
        await events.waitUntilEnqueuedCount(1)

        #expect(events.values == [1])
        await firstBlocker.open()
        #expect(try await first.value == 1)
        #expect(try await second.value == 2)
        #expect(events.values == [1, 2, 3])
        #expect(events.grantedIdentifiers.count == 2)
        #expect(events.releasedIdentifiers == events.grantedIdentifiers)
    }

    @Test func cancelledWaiterNeverRunsAfterTheActiveTransaction() async throws {
        let blocker = AsyncOperationBlocker()
        let gate = IOSPendingRecordingOperationGate()

        let first = Task {
            try await gate.perform {
                await blocker.wait()
                return 1
            }
        }
        await blocker.waitUntilSuspended()

        let didRun = LockedFlag()
        let cancelled = Task {
            try await gate.perform {
                didRun.set()
                return 2
            }
        }
        await Task.yield()
        cancelled.cancel()

        do {
            _ = try await cancelled.value
            Issue.record("A cancelled waiter must not receive a transaction lease.")
        } catch IOSPendingRecordingOperationGate.AcquisitionError.cancelledBeforeLease {
        } catch {
            Issue.record("Unexpected cancellation error: \(type(of: error))")
        }

        await blocker.open()
        #expect(try await first.value == 1)
        #expect(!didRun.value)
    }

    @Test func cancellationAfterGrantDoesNotInterruptTheTransaction() async throws {
        let events = GateEventRecorder()
        let blocker = AsyncOperationBlocker()
        let didFinish = LockedFlag()
        let gate = IOSPendingRecordingOperationGate { event in
            events.append(event)
        }
        let task = Task {
            try await gate.perform {
                await blocker.wait()
                try Task.checkCancellation()
                didFinish.set()
                return 7
            }
        }

        await blocker.waitUntilSuspended()
        task.cancel()
        let tail = Task {
            try await gate.perform { 8 }
        }
        await events.waitUntilEnqueuedCount(1)
        await blocker.open()

        #expect(try await task.value == 7)
        #expect(try await tail.value == 8)
        #expect(didFinish.value)
        #expect(events.grantedIdentifiers.count == 2)
        #expect(events.releasedIdentifiers == events.grantedIdentifiers)
    }

    @Test func transactionCannotReenterTheSameGate() async throws {
        let gate = IOSPendingRecordingOperationGate()

        do {
            _ = try await gate.perform {
                try await gate.perform { 1 }
            }
            Issue.record("Re-entry must fail before it can deadlock the FIFO gate.")
        } catch IOSPendingRecordingOperationGate.AcquisitionError.reentrantOperation {
        } catch {
            Issue.record("Unexpected re-entry error: \(type(of: error))")
        }
    }

    @Test func operationErrorReleasesTheLiveTailExactlyOnce() async throws {
        let events = GateEventRecorder()
        let blocker = AsyncOperationBlocker()
        let gate = IOSPersistenceOperationGate { event in
            events.append(event)
        }

        let failing = Task<Void, Error> {
            try await gate.perform {
                await blocker.wait()
                throw GateTestError.expected
            }
        }
        await blocker.waitUntilSuspended()

        let tail = Task {
            try await gate.perform { 2 }
        }
        await events.waitUntilEnqueuedCount(1)
        await blocker.open()

        do {
            try await failing.value
            Issue.record("The operation error must be returned after releasing its lease.")
        } catch GateTestError.expected {
        } catch {
            Issue.record("Unexpected operation error: \(type(of: error))")
        }

        #expect(try await tail.value == 2)
        #expect(events.grantedIdentifiers.count == 2)
        #expect(events.releasedIdentifiers == events.grantedIdentifiers)
    }

    @Test func leaseAuthorizationIsOpaqueAndInvalidBeforeRelease() async throws {
        let probe = GateLeaseAuthorizationProbe()
        let gate = IOSPersistenceOperationGate { event in
            guard case .released = event else { return }
            probe.observeRelease()
        }

        let retained = try await gate.perform { authorization in
            probe.store(authorization)
            #expect(authorization.provesActiveLease())
            #expect(
                String(reflecting: authorization)
                    == "IOSPersistenceOperationLeaseAuthorization(redacted)"
            )
            #expect(authorization.customMirror.children.isEmpty)
            return authorization
        }

        #expect(!retained.provesActiveLease())
        #expect(probe.wasInactiveAtRelease)
    }

    @Test func operationGateBindingAcceptsOnlyItsExactActiveRootLease()
        async throws {
        let exactGate = IOSPersistenceOperationGate()
        let foreignGate = IOSPersistenceOperationGate()
        let binding = IOSPersistenceOperationGateBinding(
            identity: exactGate.identity
        )

        try await exactGate.perform { exactLease in
            #expect(binding.proves(exactLease))
            try await foreignGate.perform { foreignLease in
                #expect(!binding.proves(foreignLease))
            }
        }

        #expect(
            String(reflecting: exactGate.identity)
                == "IOSPersistenceOperationGateIdentity(redacted)"
        )
        #expect(exactGate.identity.customMirror.children.isEmpty)
    }

    @Test func spawnedTaskCannotReenterTheActiveLease() async throws {
        let gate = IOSPersistenceOperationGate()

        try await gate.perform {
            let nested = Task {
                try await gate.perform { 1 }
            }

            do {
                _ = try await nested.value
                Issue.record("A spawned task must retain the active lease context.")
            } catch IOSPersistenceOperationGate.AcquisitionError.reentrantOperation {
            } catch {
                Issue.record("Unexpected spawned-task re-entry error: \(type(of: error))")
            }
        }

        #expect(try await gate.perform { 2 } == 2)
    }

    @Test func operationPreservesAnUnrelatedTaskLocalContext() async throws {
        let gate = IOSPersistenceOperationGate()

        let inheritedValue = try await UnrelatedGateTaskContext.$value.withValue("trace-canary") {
            try await gate.perform {
                UnrelatedGateTaskContext.value
            }
        }

        #expect(inheritedValue == "trace-canary")
    }

    @Test func crossGateCycleCannotReenterAnOuterActiveLease() async throws {
        let firstGate = IOSPersistenceOperationGate()
        let secondGate = IOSPersistenceOperationGate()

        do {
            _ = try await firstGate.perform {
                try await secondGate.perform {
                    try await firstGate.perform { 1 }
                }
            }
            Issue.record("A -> B -> A must reject the still-active A lease.")
        } catch IOSPersistenceOperationGate.AcquisitionError.reentrantOperation {
        } catch {
            Issue.record("Unexpected cross-gate re-entry error: \(type(of: error))")
        }

        #expect(try await firstGate.perform { 2 } == 2)
        #expect(try await secondGate.perform { 3 } == 3)
    }

    @Test func transactionMayUseAnotherIndependentGate() async throws {
        let firstGate = IOSPersistenceOperationGate()
        let secondGate = IOSPersistenceOperationGate()

        let value = try await firstGate.perform {
            try await secondGate.perform { 7 }
        }

        #expect(value == 7)
    }

    @Test func escapedTaskWithStaleContextMayAcquireAfterRelease() async throws {
        let events = GateEventRecorder()
        let staleTaskBlocker = AsyncOperationBlocker()
        let currentOperationBlocker = AsyncOperationBlocker()
        let gate = IOSPersistenceOperationGate { event in
            events.append(event)
        }

        let escapedTask = try await gate.perform {
            Task {
                await staleTaskBlocker.wait()
                return try await gate.perform { 9 }
            }
        }

        await staleTaskBlocker.waitUntilSuspended()
        let currentOperation = Task {
            try await gate.perform {
                await currentOperationBlocker.wait()
                return 2
            }
        }
        await currentOperationBlocker.waitUntilSuspended()

        await staleTaskBlocker.open()
        await events.waitUntilEnqueuedCount(1)
        await currentOperationBlocker.open()

        #expect(try await currentOperation.value == 2)
        #expect(try await escapedTask.value == 9)
    }

    @Test func cancellationBeforeWaiterInstallationResumesExactlyOnce() async throws {
        let boundary = GateBoundaryBlocker()
        let operationDidRun = LockedFlag()
        let gate = IOSPersistenceOperationGate { event in
            if case .installing = event {
                boundary.blockOnce()
            }
        }

        let task = Task {
            try await gate.perform {
                operationDidRun.set()
                return 1
            }
        }
        #expect(boundary.waitUntilBlocked())
        task.cancel()
        boundary.open()

        do {
            _ = try await task.value
            Issue.record("Cancellation before continuation installation must reject the lease.")
        } catch IOSPersistenceOperationGate.AcquisitionError.cancelledBeforeLease {
        } catch {
            Issue.record("Unexpected pre-install cancellation error: \(type(of: error))")
        }

        #expect(!operationDidRun.value)
        #expect(try await gate.perform { 2 } == 2)
    }

    @Test func cancellationBeforeGrantClaimResumesExactlyOnce() async throws {
        let boundary = GateBoundaryBlocker()
        let operationDidRun = LockedFlag()
        let gate = IOSPersistenceOperationGate { event in
            if case .claiming = event {
                boundary.blockOnce()
            }
        }

        let task = Task {
            try await gate.perform {
                operationDidRun.set()
                return 1
            }
        }
        #expect(boundary.waitUntilBlocked())
        task.cancel()
        boundary.open()

        do {
            _ = try await task.value
            Issue.record("Cancellation before grant claim must reject the lease.")
        } catch IOSPersistenceOperationGate.AcquisitionError.cancelledBeforeLease {
        } catch {
            Issue.record("Unexpected pre-grant cancellation error: \(type(of: error))")
        }

        #expect(!operationDidRun.value)
        #expect(try await gate.perform { 2 } == 2)
    }

    @Test func cancellationStormDoesNotBlockALiveTail() async throws {
        let events = GateEventRecorder()
        let blocker = AsyncOperationBlocker()
        let cancelledOperationDidRun = LockedFlag()
        let gate = IOSPersistenceOperationGate { event in
            events.append(event)
        }

        let active = Task {
            try await gate.perform {
                await blocker.wait()
                return 1
            }
        }
        await blocker.waitUntilSuspended()

        let cancelledTasks = (0..<16).map { _ in
            Task {
                try await gate.perform {
                    cancelledOperationDidRun.set()
                    return -1
                }
            }
        }
        await events.waitUntilEnqueuedCount(cancelledTasks.count)
        for task in cancelledTasks {
            task.cancel()
        }
        for task in cancelledTasks {
            do {
                _ = try await task.value
                Issue.record("A cancelled queued operation must not receive a lease.")
            } catch IOSPersistenceOperationGate.AcquisitionError.cancelledBeforeLease {
            } catch {
                Issue.record("Unexpected cancellation-storm error: \(type(of: error))")
            }
        }

        let tail = Task {
            try await gate.perform { 2 }
        }
        await events.waitUntilEnqueuedCount(cancelledTasks.count + 1)
        await blocker.open()

        #expect(try await active.value == 1)
        #expect(try await tail.value == 2)
        #expect(!cancelledOperationDidRun.value)
        #expect(events.grantedIdentifiers.count == 2)
        #expect(events.releasedIdentifiers == events.grantedIdentifiers)
    }
}

private enum GateTestError: Error {
    case expected
}

private enum UnrelatedGateTaskContext {
    @TaskLocal static var value: String?
}

nonisolated private final class GateEventRecorder: @unchecked Sendable {
    private struct EnqueuedObserver {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var storedEvents: [IOSPendingRecordingOperationGate.Event] = []
    private var storedValues: [Int] = []
    private var enqueuedCount = 0
    private var enqueuedObservers: [EnqueuedObserver] = []

    var values: [Int] {
        lock.withLock { storedValues }
    }

    var grantedIdentifiers: [UUID] {
        lock.withLock {
            storedEvents.compactMap { event in
                guard case .granted(let identifier) = event else {
                    return nil
                }
                return identifier
            }
        }
    }

    var releasedIdentifiers: [UUID] {
        lock.withLock {
            storedEvents.compactMap { event in
                guard case .released(let identifier) = event else {
                    return nil
                }
                return identifier
            }
        }
    }

    func append(_ event: IOSPendingRecordingOperationGate.Event) {
        let readyObservers: [EnqueuedObserver]

        lock.lock()
        storedEvents.append(event)
        if case .enqueued = event {
            enqueuedCount += 1
        }
        readyObservers = enqueuedObservers.filter { enqueuedCount >= $0.expectedCount }
        enqueuedObservers.removeAll { enqueuedCount >= $0.expectedCount }
        lock.unlock()

        for observer in readyObservers {
            observer.continuation.resume()
        }
    }

    func appendValue(_ value: Int) {
        lock.withLock { storedValues.append(value) }
    }

    func waitUntilEnqueuedCount(_ expectedCount: Int) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            guard enqueuedCount < expectedCount else {
                lock.unlock()
                continuation.resume()
                return
            }
            enqueuedObservers.append(
                EnqueuedObserver(
                    expectedCount: expectedCount,
                    continuation: continuation
                )
            )
            lock.unlock()
        }
    }
}

nonisolated private final class GateLeaseAuthorizationProbe:
    @unchecked Sendable {
    private let lock = NSLock()
    private var authorization: IOSPersistenceOperationLeaseAuthorization?
    private var storedWasInactiveAtRelease = false

    var wasInactiveAtRelease: Bool {
        lock.withLock { storedWasInactiveAtRelease }
    }

    func store(_ authorization: IOSPersistenceOperationLeaseAuthorization) {
        lock.withLock {
            self.authorization = authorization
        }
    }

    func observeRelease() {
        lock.withLock {
            storedWasInactiveAtRelease = authorization?.provesActiveLease() == false
        }
    }
}

nonisolated private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.withLock { storedValue }
    }

    func set() {
        lock.withLock { storedValue = true }
    }
}

nonisolated private final class GateBoundaryBlocker: @unchecked Sendable {
    private let lock = NSLock()
    private let blocked = DispatchSemaphore(value: 0)
    private let releaseSignal = DispatchSemaphore(value: 0)
    private var didBlock = false

    func blockOnce() {
        let shouldBlock = lock.withLock {
            guard !didBlock else {
                return false
            }
            didBlock = true
            return true
        }
        guard shouldBlock else {
            return
        }

        blocked.signal()
        _ = releaseSignal.wait(timeout: .now() + 10)
    }

    func waitUntilBlocked() -> Bool {
        blocked.wait(timeout: .now() + 10) == .success
    }

    func open() {
        releaseSignal.signal()
    }
}

private actor AsyncOperationBlocker {
    private var blockingContinuation: CheckedContinuation<Void, Never>?
    private var observerContinuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private var isSuspended = false

    func wait() async {
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            blockingContinuation = continuation
            isSuspended = true
            let observers = observerContinuations
            observerContinuations.removeAll()
            for observer in observers {
                observer.resume()
            }
        }
    }

    func waitUntilSuspended() async {
        guard !isSuspended else {
            return
        }
        await withCheckedContinuation { continuation in
            observerContinuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        blockingContinuation?.resume()
        blockingContinuation = nil
    }
}
