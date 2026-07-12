import Foundation
import HoldTypePersistence
import Observation

enum IOSContainingAppStateOwnerError: Error, Equatable, Sendable {
    case loadFailed
    case saveFailed
    case operationCancelledBeforeStart
}

enum IOSAppSettingsState: Equatable, Sendable {
    case notLoaded
    case ready(IOSAppSettings)
    case loadFailed
    case saveFailed(lastDurableValue: IOSAppSettings)
}

enum IOSLibraryState: Equatable, Sendable {
    case notLoaded
    case ready(IOSLibraryContent)
    case loadFailed
    case saveFailed(lastDurableValue: IOSLibraryContent)
}

/// Process-owned Settings transaction boundary. Construction is passive;
/// repository I/O begins only from an explicit load, mutation, or provider
/// snapshot request.
@MainActor
@Observable
final class IOSAppSettingsStateOwner {
    typealias Loader = @Sendable () async throws -> IOSAppSettings
    typealias Committer = @Sendable (
        IOSAppSettings
    ) async throws -> IOSAppSettings

    private(set) var state = IOSAppSettingsState.notLoaded

    @ObservationIgnored
    private let core: IOSPersistentStateOwnerCore<IOSAppSettings>

    init(applicationSupportDirectoryURL: URL) {
        let repository = IOSAppSettingsRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        core = IOSPersistentStateOwnerCore(
            load: { try await repository.load() },
            commit: { candidate in
                try await repository.save(candidate)
                return candidate
            }
        )
    }

    init(
        load: @escaping Loader,
        commit: @escaping Committer
    ) {
        core = IOSPersistentStateOwnerCore(
            load: load,
            commit: commit
        )
    }

    func snapshot() -> IOSAppSettingsState { state }

    @discardableResult
    func load() async throws -> IOSAppSettingsState {
        let resolved = try await core.load { [self] coreState in
            state = Self.map(coreState)
        }
        return Self.map(resolved)
    }

    @discardableResult
    func update(
        _ mutation: @escaping @Sendable (inout IOSAppSettings) -> Void
    ) async throws -> IOSAppSettingsState {
        let resolved = try await core.update(mutation) { [self] coreState in
            state = Self.map(coreState)
        }
        return Self.map(resolved)
    }

    func confirmedValueForProviderAction() async throws -> IOSAppSettings {
        try await core.confirmedValue { [self] coreState in
            state = Self.map(coreState)
        }
    }

    private nonisolated static func map(
        _ state: IOSPersistentStateOwnerCore<IOSAppSettings>.State
    ) -> IOSAppSettingsState {
        switch state {
        case .notLoaded:
            .notLoaded
        case .ready(let value):
            .ready(value)
        case .loadFailed:
            .loadFailed
        case .saveFailed(let lastDurableValue):
            .saveFailed(lastDurableValue: lastDurableValue)
        }
    }
}

/// Process-owned Library transaction boundary. The committed value returned
/// by Persistence is authoritative because Library saves may normalize input.
@MainActor
@Observable
final class IOSLibraryStateOwner {
    typealias Loader = @Sendable () async throws -> IOSLibraryContent
    typealias Committer = @Sendable (
        IOSLibraryContent
    ) async throws -> IOSLibraryContent

    private(set) var state = IOSLibraryState.notLoaded

    @ObservationIgnored
    private let core: IOSPersistentStateOwnerCore<IOSLibraryContent>

    init(applicationSupportDirectoryURL: URL) {
        let repository = IOSLibraryRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        core = IOSPersistentStateOwnerCore(
            load: { try await repository.load() },
            commit: { candidate in
                try await repository.save(candidate)
            }
        )
    }

    init(
        load: @escaping Loader,
        commit: @escaping Committer
    ) {
        core = IOSPersistentStateOwnerCore(
            load: load,
            commit: commit
        )
    }

    func snapshot() -> IOSLibraryState { state }

    @discardableResult
    func load() async throws -> IOSLibraryState {
        let resolved = try await core.load { [self] coreState in
            state = Self.map(coreState)
        }
        return Self.map(resolved)
    }

    @discardableResult
    func update(
        _ mutation: @escaping @Sendable (inout IOSLibraryContent) -> Void
    ) async throws -> IOSLibraryState {
        let resolved = try await core.update(mutation) { [self] coreState in
            state = Self.map(coreState)
        }
        return Self.map(resolved)
    }

    func apply(
        _ mutation: IOSLibraryMutation
    ) async throws -> IOSLibraryMutationCompletion {
        let result = try await core.transact(
            { content in
                let receipt = mutation.apply(to: &content)
                return receipt.disposition == .committed
                    ? .commit(receipt)
                    : .finishWithoutCommit(receipt)
            },
            publish: { [self] coreState in
                state = Self.map(coreState)
            }
        )
        return IOSLibraryMutationCompletion(
            state: Self.map(result.state),
            receipt: result.receipt
        )
    }

    func confirmedValueForProviderAction() async throws -> IOSLibraryContent {
        try await core.confirmedValue { [self] coreState in
            state = Self.map(coreState)
        }
    }

    private nonisolated static func map(
        _ state: IOSPersistentStateOwnerCore<IOSLibraryContent>.State
    ) -> IOSLibraryState {
        switch state {
        case .notLoaded:
            .notLoaded
        case .ready(let value):
            .ready(value)
        case .loadFailed:
            .loadFailed
        case .saveFailed(let lastDurableValue):
            .saveFailed(lastDurableValue: lastDurableValue)
        }
    }
}

private nonisolated enum IOSPersistentStateMutationDirective<Receipt: Sendable>:
    Sendable {
    case commit(Receipt)
    case finishWithoutCommit(Receipt)
}

private nonisolated struct IOSPersistentStateMutationResult<
    State: Sendable,
    Receipt: Sendable
>: Sendable {
    let state: State
    let receipt: Receipt
}

private actor IOSPersistentStateOwnerCore<Value: Equatable & Sendable> {
    enum State: Equatable, Sendable {
        case notLoaded
        case ready(Value)
        case loadFailed
        case saveFailed(Value)
    }

    typealias Loader = @Sendable () async throws -> Value
    typealias Committer = @Sendable (Value) async throws -> Value
    typealias Publisher = @MainActor @Sendable (State) -> Void

    private let loadValue: Loader
    private let commitValue: Committer
    private let operationGate = IOSContainingAppStateOperationGate()
    private var state = State.notLoaded

    init(
        load: @escaping Loader,
        commit: @escaping Committer
    ) {
        loadValue = load
        commitValue = commit
    }

    func load(
        publish: @escaping Publisher
    ) async throws -> State {
        try await performExclusive { [self] in
            try await performLoad(publish: publish)
        }
    }

    func update(
        _ mutation: @escaping @Sendable (inout Value) -> Void,
        publish: @escaping Publisher
    ) async throws -> State {
        try await performExclusive { [self] in
            try await performUpdate(mutation, publish: publish)
        }
    }

    func confirmedValue(
        publish: @escaping Publisher
    ) async throws -> Value {
        try await performExclusive { [self] in
            try await performConfirmedValue(publish: publish)
        }
    }

    func transact<Receipt: Sendable>(
        _ mutation: @escaping @Sendable (
            inout Value
        ) -> IOSPersistentStateMutationDirective<Receipt>,
        publish: @escaping Publisher
    ) async throws -> IOSPersistentStateMutationResult<State, Receipt> {
        try await performExclusive { [self] in
            try await performTransaction(mutation, publish: publish)
        }
    }

    private func performLoad(
        publish: @escaping Publisher
    ) async throws -> State {
        do {
            _ = try await resolveDurableValue()
            await publish(state)
            return state
        } catch {
            await publish(state)
            throw error
        }
    }

    private func performUpdate(
        _ mutation: @escaping @Sendable (inout Value) -> Void,
        publish: @escaping Publisher
    ) async throws -> State {
        let durableValue: Value
        do {
            durableValue = try await resolveDurableValue()
        } catch {
            await publish(state)
            throw error
        }
        var candidate = durableValue
        mutation(&candidate)

        do {
            let committedValue = try await commitValue(candidate)
            state = .ready(committedValue)
            await publish(state)
            return state
        } catch {
            state = .saveFailed(durableValue)
            await publish(state)
            throw IOSContainingAppStateOwnerError.saveFailed
        }
    }

    private func performTransaction<Receipt: Sendable>(
        _ mutation: @escaping @Sendable (
            inout Value
        ) -> IOSPersistentStateMutationDirective<Receipt>,
        publish: @escaping Publisher
    ) async throws -> IOSPersistentStateMutationResult<State, Receipt> {
        let durableValue: Value
        do {
            durableValue = try await resolveDurableValue()
        } catch {
            await publish(state)
            throw error
        }

        var candidate = durableValue
        let directive = mutation(&candidate)
        switch directive {
        case .finishWithoutCommit(let receipt):
            await publish(state)
            return IOSPersistentStateMutationResult(
                state: state,
                receipt: receipt
            )
        case .commit(let receipt):
            do {
                let committedValue = try await commitValue(candidate)
                state = .ready(committedValue)
                await publish(state)
                return IOSPersistentStateMutationResult(
                    state: state,
                    receipt: receipt
                )
            } catch {
                state = .saveFailed(durableValue)
                await publish(state)
                throw IOSContainingAppStateOwnerError.saveFailed
            }
        }
    }

    private func performConfirmedValue(
        publish: @escaping Publisher
    ) async throws -> Value {
        do {
            let value = try await resolveDurableValue()
            await publish(state)
            return value
        } catch {
            await publish(state)
            throw error
        }
    }

    private func resolveDurableValue() async throws -> Value {
        switch state {
        case .ready(let value), .saveFailed(let value):
            return value
        case .notLoaded, .loadFailed:
            do {
                let value = try await loadValue()
                state = .ready(value)
                return value
            } catch {
                state = .loadFailed
                throw IOSContainingAppStateOwnerError.loadFailed
            }
        }
    }

    private func performExclusive<Result: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        do {
            return try await operationGate.perform(operation)
        } catch IOSContainingAppStateOperationGate.AcquisitionError
            .cancelledBeforeLease {
            throw IOSContainingAppStateOwnerError
                .operationCancelledBeforeStart
        }
    }
}

/// FIFO gate for whole state-owner transactions. It intentionally shields an
/// acquired local transaction from ordinary caller cancellation so a commit
/// cannot be reported as cancelled after becoming durable.
private actor IOSContainingAppStateOperationGate {
    enum AcquisitionError: Error, Equatable, Sendable {
        case cancelledBeforeLease
    }

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

        func install(
            _ continuation: CheckedContinuation<Lease, Error>
        ) -> Bool {
            lock.lock()
            switch phase {
            case .pending:
                self.continuation = continuation
                lock.unlock()
                return true
            case .cancelled:
                lock.unlock()
                continuation.resume(
                    throwing: AcquisitionError.cancelledBeforeLease
                )
                return false
            case .granted:
                lock.unlock()
                assertionFailure(
                    "A state-owner waiter cannot be granted before installation."
                )
                continuation.resume(
                    throwing: AcquisitionError.cancelledBeforeLease
                )
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

            continuation?.resume(
                throwing: AcquisitionError.cancelledBeforeLease
            )
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

    private var activeLease: Lease?
    private var waiters: [Waiter] = []

    func perform<Result: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        let lease = try await acquire()
        let operationTask = Task {
            try await operation()
        }
        let result = await operationTask.result
        release(lease)
        return try result.get()
    }

    private func acquire() async throws -> Lease {
        guard !Task.isCancelled else {
            throw AcquisitionError.cancelledBeforeLease
        }

        let waiter = Waiter(identifier: UUID())
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard waiter.install(continuation) else { return }
                enqueue(waiter)
            }
        } onCancel: {
            guard waiter.cancel() else { return }
            Task {
                await self.removeCancelledWaiter(
                    identifier: waiter.identifier
                )
            }
        }
    }

    private func enqueue(_ waiter: Waiter) {
        guard activeLease == nil else {
            waiters.append(waiter)
            return
        }
        _ = grant(waiter)
    }

    @discardableResult
    private func grant(_ waiter: Waiter) -> Bool {
        guard let continuation = waiter.claimGrant() else {
            return false
        }
        let lease = Lease(identifier: waiter.identifier)
        activeLease = lease
        continuation.resume(returning: lease)
        return true
    }

    private func release(_ lease: Lease) {
        guard activeLease == lease else {
            assertionFailure(
                "Only the active state-owner lease may be released."
            )
            return
        }

        activeLease = nil
        while !waiters.isEmpty {
            if grant(waiters.removeFirst()) { return }
        }
    }

    private func removeCancelledWaiter(identifier: UUID) {
        waiters.removeAll { $0.identifier == identifier }
    }
}

extension IOSContainingAppStateOwnerError: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSContainingAppStateOwnerError(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSAppSettingsState: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSAppSettingsState(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSLibraryState: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSLibraryState(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSAppSettingsStateOwner: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSAppSettingsStateOwner(redacted)"
    }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSLibraryStateOwner: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSLibraryStateOwner(redacted)"
    }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}
