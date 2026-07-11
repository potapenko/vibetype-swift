import Foundation

/// Opaque identity for one exact persistence-operation gate.
struct IOSPersistenceOperationGateIdentity: Equatable, Sendable {
    private let value = UUID()

    fileprivate init() {}
}

extension IOSPersistenceOperationGateIdentity:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSPersistenceOperationGateIdentity(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// One-time binding between a persistence store and its root operation gate.
final class IOSPersistenceOperationGateBinding: @unchecked Sendable {
    private let lock = NSLock()
    private var identity: IOSPersistenceOperationGateIdentity?

    init(identity: IOSPersistenceOperationGateIdentity? = nil) {
        self.identity = identity
    }

    func bind(_ identity: IOSPersistenceOperationGateIdentity) -> Bool {
        lock.withLock {
            if let current = self.identity {
                return current == identity
            }
            self.identity = identity
            return true
        }
    }

    func proves(
        _ authorization: IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        lock.withLock {
            guard let identity else { return false }
            return authorization.provesActiveLease(for: identity)
        }
    }
}

/// Opaque proof that work is still running under one exact persistence-gate lease.
struct IOSPersistenceOperationLeaseAuthorization: Equatable, Sendable {
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var isActive = true

        func invalidate() {
            lock.withLock {
                isActive = false
            }
        }

        func active() -> Bool {
            lock.withLock { isActive }
        }
    }

    private let gateIdentity: IOSPersistenceOperationGateIdentity
    private let gateIdentifier: ObjectIdentifier
    private let leaseIdentifier: UUID
    private let state: State

    fileprivate init(
        gateIdentity: IOSPersistenceOperationGateIdentity,
        gateIdentifier: ObjectIdentifier,
        leaseIdentifier: UUID
    ) {
        self.gateIdentity = gateIdentity
        self.gateIdentifier = gateIdentifier
        self.leaseIdentifier = leaseIdentifier
        state = State()
    }

    static func == (
        lhs: IOSPersistenceOperationLeaseAuthorization,
        rhs: IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        lhs.gateIdentifier == rhs.gateIdentifier
            && lhs.gateIdentity == rhs.gateIdentity
            && lhs.leaseIdentifier == rhs.leaseIdentifier
            && lhs.state === rhs.state
    }

    func provesSameActiveLease(
        as other: IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        self == other && state.active()
    }

    func provesActiveLease() -> Bool {
        state.active()
    }

    func provesActiveLease(
        for gateIdentity: IOSPersistenceOperationGateIdentity
    ) -> Bool {
        self.gateIdentity == gateIdentity && state.active()
    }

    fileprivate func invalidate() {
        state.invalidate()
    }
}

extension IOSPersistenceOperationLeaseAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSPersistenceOperationLeaseAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Serializes a persistence coordinator's whole transactions across suspension points.
actor IOSPersistenceOperationGate {
    enum AcquisitionError: Error, Equatable, Sendable {
        case cancelledBeforeLease
        case reentrantOperation
    }

    enum Event: Equatable, Sendable {
        case installing(UUID)
        case claiming(UUID)
        case enqueued(UUID)
        case granted(UUID)
        case cancelled(UUID)
        case released(UUID)
    }

    private struct ActiveLeaseContext: Equatable, Sendable {
        let gateIdentifier: ObjectIdentifier
        let leaseIdentifier: UUID
    }

    @TaskLocal private static var activeLeaseContexts: [ActiveLeaseContext] = []

    private struct Lease: Equatable, Sendable {
        let identifier: UUID
    }

    private final class Waiter: @unchecked Sendable {
        private enum Phase {
            case pending
            case granted
            case cancelled
        }

        let identifier: UUID

        private let lock = NSLock()
        private var phase = Phase.pending
        private var continuation: CheckedContinuation<Lease, Error>?

        init(identifier: UUID) {
            self.identifier = identifier
        }

        func install(_ continuation: CheckedContinuation<Lease, Error>) -> Bool {
            lock.lock()
            switch phase {
            case .pending:
                self.continuation = continuation
                lock.unlock()
                return true
            case .cancelled:
                lock.unlock()
                continuation.resume(throwing: AcquisitionError.cancelledBeforeLease)
                return false
            case .granted:
                lock.unlock()
                assertionFailure("A persistence waiter cannot be granted before installation.")
                continuation.resume(throwing: AcquisitionError.cancelledBeforeLease)
                return false
            }
        }

        @discardableResult
        func cancel() -> Bool {
            let continuation: CheckedContinuation<Lease, Error>?

            lock.lock()
            guard case .pending = phase else {
                lock.unlock()
                return false
            }
            phase = .cancelled
            continuation = self.continuation
            self.continuation = nil
            lock.unlock()

            continuation?.resume(throwing: AcquisitionError.cancelledBeforeLease)
            return true
        }

        func claimGrant() -> CheckedContinuation<Lease, Error>? {
            lock.lock()
            guard case .pending = phase,
                  let continuation else {
                lock.unlock()
                return nil
            }
            phase = .granted
            self.continuation = nil
            lock.unlock()
            return continuation
        }
    }

    private let eventSink: @Sendable (Event) -> Void
    nonisolated let identity: IOSPersistenceOperationGateIdentity
    private var activeLease: Lease?
    private var waiters: [Waiter] = []

    init(eventSink: @escaping @Sendable (Event) -> Void = { _ in }) {
        identity = IOSPersistenceOperationGateIdentity()
        self.eventSink = eventSink
    }

    func perform<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await perform { _ in
            try await operation()
        }
    }

    func perform<Value: Sendable>(
        _ operation: @escaping @Sendable (
            IOSPersistenceOperationLeaseAuthorization
        ) async throws -> Value
    ) async throws -> Value {
        let gateIdentifier = ObjectIdentifier(self)
        let inheritedContexts = Self.activeLeaseContexts
        // Escaped tasks may retain old contexts, so only the exact active lease is reentrant.
        if let activeLease,
           inheritedContexts.contains(where: {
               $0.gateIdentifier == gateIdentifier
                   && $0.leaseIdentifier == activeLease.identifier
           }) {
            throw AcquisitionError.reentrantOperation
        }

        let lease = try await acquire()
        let operationContext = ActiveLeaseContext(
            gateIdentifier: gateIdentifier,
            leaseIdentifier: lease.identifier
        )
        let operationAuthorization = IOSPersistenceOperationLeaseAuthorization(
            gateIdentity: identity,
            gateIdentifier: gateIdentifier,
            leaseIdentifier: lease.identifier
        )
        // This unstructured task preserves ambient context without inheriting caller cancellation.
        let operationTask = Task {
            try await Self.$activeLeaseContexts.withValue(
                inheritedContexts + [operationContext]
            ) {
                try await operation(operationAuthorization)
            }
        }
        let result = await operationTask.result
        operationAuthorization.invalidate()
        release(lease)
        return try result.get()
    }

    private func acquire() async throws -> Lease {
        guard !Task.isCancelled else {
            throw AcquisitionError.cancelledBeforeLease
        }

        let identifier = UUID()
        let waiter = Waiter(identifier: identifier)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                eventSink(.installing(identifier))
                guard waiter.install(continuation) else {
                    return
                }
                enqueue(waiter)
            }
        } onCancel: {
            guard waiter.cancel() else {
                return
            }
            eventSink(.cancelled(identifier))
            Task {
                await self.removeCancelledWaiter(identifier: identifier)
            }
        }
    }

    private func enqueue(_ waiter: Waiter) {
        guard activeLease == nil else {
            waiters.append(waiter)
            eventSink(.enqueued(waiter.identifier))
            return
        }
        _ = grant(waiter)
    }

    @discardableResult
    private func grant(_ waiter: Waiter) -> Bool {
        eventSink(.claiming(waiter.identifier))
        guard let continuation = waiter.claimGrant() else {
            return false
        }

        let lease = Lease(identifier: waiter.identifier)
        activeLease = lease
        eventSink(.granted(waiter.identifier))
        continuation.resume(returning: lease)
        return true
    }

    private func release(_ lease: Lease) {
        guard activeLease == lease else {
            assertionFailure("Only the active persistence lease may be released.")
            return
        }

        activeLease = nil
        eventSink(.released(lease.identifier))
        while !waiters.isEmpty {
            if grant(waiters.removeFirst()) {
                return
            }
        }
    }

    private func removeCancelledWaiter(identifier: UUID) {
        waiters.removeAll { $0.identifier == identifier }
    }
}
