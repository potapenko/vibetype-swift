import Foundation
import HoldTypePersistence

/// A provider-stage completion that has crossed the current one-shot consent
/// result fence. Success and failure payloads must already be normalized,
/// minimal containing-app values.
enum IOSProviderConsentStageOutcome<Success: Sendable, Failure: Sendable>:
    Sendable {
    case success(Success)
    case failure(Failure)
    case cancelled
    case authorizationUnavailable
}

extension IOSProviderConsentStageOutcome: Equatable
    where Success: Equatable, Failure: Equatable {}

extension IOSProviderConsentStageOutcome:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSProviderConsentStageOutcome(redacted)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Runs one already-preflighted provider stage behind the process-wide consent
/// coordinator. It returns only a normalized result that was consumed by the
/// current consent fence; callers perform asynchronous persistence afterward.
struct IOSProviderConsentStageExecutor: Sendable {
    private let consentCoordinator: IOSProviderConsentCoordinator

    init(consentCoordinator: IOSProviderConsentCoordinator) {
        self.consentCoordinator = consentCoordinator
    }

    func execute<Success: Sendable, Failure: Sendable>(
        _ authorization: IOSProviderConsentAuthorization,
        for stage: IOSProviderConsentProviderStage,
        operation: @escaping @Sendable () async throws -> Success,
        normalizeFailure: @escaping @Sendable (any Error) -> Failure
    ) async -> IOSProviderConsentStageOutcome<Success, Failure> {
        await IOSProviderConsentStageExecutionEngine.execute(
            gate: IOSProviderConsentCoordinatorStageGate(
                coordinator: consentCoordinator
            ),
            authorization: authorization,
            stage: stage,
            operation: operation,
            normalizeFailure: normalizeFailure
        )
    }
}

extension IOSProviderConsentStageExecutor:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSProviderConsentStageExecutor(redacted)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

protocol IOSProviderConsentStageGating: Sendable {
    associatedtype Authorization: Sendable
    associatedtype Registration: Sendable
    associatedtype ResultAuthorization: Sendable

    func registerProviderDispatch(
        _ authorization: Authorization,
        for stage: IOSProviderConsentProviderStage,
        onCancellation: @escaping @Sendable () -> Void
    ) async -> Registration?

    func launchProviderDispatch(
        _ registration: Registration,
        launch: @Sendable () -> Void
    ) async -> Bool

    func cancelProviderDispatch(_ registration: Registration)

    func finishProviderDispatch(
        _ registration: Registration,
        onResultCancellation: @escaping @Sendable () -> Void
    ) async -> ResultAuthorization?

    func consumeProviderResult<Value: Sendable>(
        _ authorization: ResultAuthorization,
        perform operation: @Sendable () throws -> Value
    ) async rethrows -> Value?

    func abandonProviderResult(_ authorization: ResultAuthorization)
}

private struct IOSProviderConsentCoordinatorStageGate:
    IOSProviderConsentStageGating {
    let coordinator: IOSProviderConsentCoordinator

    func registerProviderDispatch(
        _ authorization: IOSProviderConsentAuthorization,
        for stage: IOSProviderConsentProviderStage,
        onCancellation: @escaping @Sendable () -> Void
    ) async -> IOSProviderConsentDispatchRegistration? {
        await coordinator.registerProviderDispatch(
            authorization,
            for: stage,
            onCancellation: onCancellation
        )
    }

    func launchProviderDispatch(
        _ registration: IOSProviderConsentDispatchRegistration,
        launch: @Sendable () -> Void
    ) async -> Bool {
        await coordinator.launchProviderDispatch(
            registration,
            launch: launch
        )
    }

    func cancelProviderDispatch(
        _ registration: IOSProviderConsentDispatchRegistration
    ) {
        coordinator.cancelProviderDispatch(registration)
    }

    func finishProviderDispatch(
        _ registration: IOSProviderConsentDispatchRegistration,
        onResultCancellation: @escaping @Sendable () -> Void
    ) async -> IOSProviderConsentResultAuthorization? {
        await coordinator.finishProviderDispatch(
            registration,
            onResultCancellation: onResultCancellation
        )
    }

    func consumeProviderResult<Value: Sendable>(
        _ authorization: IOSProviderConsentResultAuthorization,
        perform operation: @Sendable () throws -> Value
    ) async rethrows -> Value? {
        try await coordinator.consumeProviderResult(
            authorization,
            perform: operation
        )
    }

    func abandonProviderResult(
        _ authorization: IOSProviderConsentResultAuthorization
    ) {
        coordinator.abandonProviderResult(authorization)
    }
}

enum IOSProviderConsentStageExecutionEngine {
    static func execute<
        Gate: IOSProviderConsentStageGating,
        Success: Sendable,
        Failure: Sendable
    >(
        gate: Gate,
        authorization: Gate.Authorization,
        stage: IOSProviderConsentProviderStage,
        operation: @escaping @Sendable () async throws -> Success,
        normalizeFailure: @escaping @Sendable (any Error) -> Failure
    ) async -> IOSProviderConsentStageOutcome<Success, Failure> {
        typealias Outcome = IOSProviderConsentStageOutcome<Success, Failure>

        let launchPermit = IOSProviderConsentStageLaunchPermit()
        let completion = IOSProviderConsentStageCompletion<Success, Failure>()
        let providerTask = Task<Void, Never> {
            guard await launchPermit.waitForLaunch(),
                  !Task.isCancelled else {
                return
            }
            do {
                let value = try await operation()
                guard !Task.isCancelled else { return }
                completion.resolve(.success(value))
            } catch {
                guard !Task.isCancelled else { return }
                let normalizedFailure = normalizeFailure(error)
                guard !Task.isCancelled else { return }
                completion.resolve(.failure(normalizedFailure))
            }
        }
        let cancelPreparedTask: @Sendable (Outcome) -> Void = { outcome in
            completion.resolve(outcome)
            launchPermit.cancel()
            providerTask.cancel()
        }

        return await withTaskCancellationHandler {
            let registration = await gate.registerProviderDispatch(
                authorization,
                for: stage,
                onCancellation: {
                    cancelPreparedTask(.authorizationUnavailable)
                }
            )
            guard let registration else {
                let outcome: Outcome = Task.isCancelled
                    ? .cancelled
                    : .authorizationUnavailable
                cancelPreparedTask(outcome)
                return outcome
            }

            return await withTaskCancellationHandler {
                guard !Task.isCancelled else {
                    gate.cancelProviderDispatch(registration)
                    cancelPreparedTask(.cancelled)
                    return .cancelled
                }

                let didLaunch = await gate.launchProviderDispatch(
                    registration,
                    launch: { launchPermit.launch() }
                )
                guard didLaunch else {
                    let outcome: Outcome = Task.isCancelled
                        ? .cancelled
                        : .authorizationUnavailable
                    cancelPreparedTask(outcome)
                    return outcome
                }

                let normalizedOutcome = await completion.value()
                switch normalizedOutcome {
                case .cancelled, .authorizationUnavailable:
                    return normalizedOutcome
                case .success, .failure:
                    break
                }

                guard !Task.isCancelled else {
                    gate.cancelProviderDispatch(registration)
                    return .cancelled
                }
                guard let resultAuthorization =
                    await gate.finishProviderDispatch(
                        registration,
                        onResultCancellation: {}
                    ) else {
                    return Task.isCancelled
                        ? .cancelled
                        : .authorizationUnavailable
                }

                return await withTaskCancellationHandler {
                    guard !Task.isCancelled else {
                        gate.abandonProviderResult(resultAuthorization)
                        return .cancelled
                    }
                    let consumed = await gate.consumeProviderResult(
                        resultAuthorization,
                        perform: { normalizedOutcome }
                    )
                    guard let consumed else {
                        return Task.isCancelled
                            ? .cancelled
                            : .authorizationUnavailable
                    }
                    // The consent closure above is deliberately synchronous.
                    // Any Pending or accepted-output await belongs to the caller
                    // after this normalized value has been returned.
                    return consumed
                } onCancel: {
                    gate.abandonProviderResult(resultAuthorization)
                }
            } onCancel: {
                cancelPreparedTask(.cancelled)
                gate.cancelProviderDispatch(registration)
            }
        } onCancel: {
            cancelPreparedTask(.cancelled)
        }
    }
}

private final class IOSProviderConsentStageLaunchPermit:
    @unchecked Sendable {
    private enum State {
        case waiting
        case launched
        case cancelled
    }

    private let lock = NSLock()
    private var state = State.waiting
    private var continuation: CheckedContinuation<Bool, Never>?

    func waitForLaunch() async -> Bool {
        await withCheckedContinuation { continuation in
            let immediate: Bool? = lock.withLock {
                switch state {
                case .waiting:
                    precondition(self.continuation == nil)
                    self.continuation = continuation
                    return nil
                case .launched:
                    return true
                case .cancelled:
                    return false
                }
            }
            if let immediate {
                continuation.resume(returning: immediate)
            }
        }
    }

    func launch() {
        resolve(as: .launched, value: true)
    }

    func cancel() {
        resolve(as: .cancelled, value: false)
    }

    private func resolve(as newState: State, value: Bool) {
        let continuation = lock.withLock { ()
            -> CheckedContinuation<Bool, Never>? in
            guard case .waiting = state else { return nil }
            state = newState
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: value)
    }
}

private final class IOSProviderConsentStageCompletion<
    Success: Sendable,
    Failure: Sendable
>: @unchecked Sendable {
    typealias Outcome = IOSProviderConsentStageOutcome<Success, Failure>

    private let lock = NSLock()
    private var outcome: Outcome?
    private var continuation: CheckedContinuation<Outcome, Never>?

    func value() async -> Outcome {
        await withCheckedContinuation { continuation in
            let immediate = lock.withLock { () -> Outcome? in
                if let outcome { return outcome }
                precondition(self.continuation == nil)
                self.continuation = continuation
                return nil
            }
            if let immediate {
                continuation.resume(returning: immediate)
            }
        }
    }

    func resolve(_ outcome: Outcome) {
        let continuation = lock.withLock { ()
            -> CheckedContinuation<Outcome, Never>? in
            guard self.outcome == nil else { return nil }
            self.outcome = outcome
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: outcome)
    }
}
