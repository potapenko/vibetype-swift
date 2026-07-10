//
//  OpenAIRequestTaskCoordinator.swift
//  HoldType
//
//  Created by Codex on 7/10/26.
//

import Foundation

nonisolated final class OpenAIRequestTaskCoordinator: @unchecked Sendable {
    private struct ActiveRequest {
        let identifier: UUID
        let cancel: @Sendable () -> Void
    }

    private final class CancellationRegistration: @unchecked Sendable {
        typealias Cancellation = @Sendable () -> Void

        private let lock = NSLock()
        private var cancellation: Cancellation?
        private var isCancelled = false

        func install(
            cancellation: @escaping Cancellation,
            installActiveRequest: () -> Cancellation?
        ) -> (installed: Bool, previousCancellation: Cancellation?) {
            lock.lock()
            guard !isCancelled else {
                lock.unlock()
                return (false, nil)
            }

            let previousCancellation = installActiveRequest()
            self.cancellation = cancellation
            lock.unlock()
            return (true, previousCancellation)
        }

        func cancel() {
            let cancellationAction = lock.withLock {
                isCancelled = true
                return cancellation
            }
            cancellationAction?()
        }
    }

    private final class RequestState<Value: Sendable>: @unchecked Sendable {
        private let identifier: UUID
        private let lock = NSLock()
        private let didFinish: @Sendable (UUID) -> Void
        private var continuation: CheckedContinuation<Value, Error>?
        private var operationTask: Task<Void, Never>?
        private var deadlineTask: Task<Void, Never>?
        private var isFinished = false

        init(
            identifier: UUID,
            continuation: CheckedContinuation<Value, Error>,
            didFinish: @escaping @Sendable (UUID) -> Void
        ) {
            self.identifier = identifier
            self.continuation = continuation
            self.didFinish = didFinish
        }

        func start(
            operation: @escaping @Sendable () async throws -> Value,
            deadline: @escaping @Sendable () async throws -> Never
        ) {
            lock.lock()
            guard !isFinished else {
                lock.unlock()
                return
            }

            let operationTask = Task { [self] in
                do {
                    finish(with: .success(try await operation()))
                } catch {
                    finish(with: .failure(error))
                }
            }
            let deadlineTask = Task { [self] in
                do {
                    try await deadline()
                } catch {
                    finish(with: .failure(error))
                }
            }
            self.operationTask = operationTask
            self.deadlineTask = deadlineTask
            lock.unlock()
        }

        func cancel() {
            finish(with: .failure(CancellationError()))
        }

        private func finish(with result: Result<Value, Error>) {
            let completion: (
                continuation: CheckedContinuation<Value, Error>,
                operationTask: Task<Void, Never>?,
                deadlineTask: Task<Void, Never>?
            )? = lock.withLock {
                guard !isFinished, let continuation else {
                    return nil
                }

                isFinished = true
                self.continuation = nil
                let completion = (
                    continuation: continuation,
                    operationTask: operationTask,
                    deadlineTask: deadlineTask
                )
                operationTask = nil
                deadlineTask = nil
                return completion
            }

            guard let completion else {
                return
            }

            completion.operationTask?.cancel()
            completion.deadlineTask?.cancel()
            didFinish(identifier)
            completion.continuation.resume(with: result)
        }
    }

    private let lock = NSLock()
    private var activeRequest: ActiveRequest?

    func perform<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value,
        deadline: @escaping @Sendable () async throws -> Never
    ) async throws -> Value {
        try Task.checkCancellation()

        let identifier = UUID()
        let cancellationRegistration = CancellationRegistration()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestState = RequestState(
                    identifier: identifier,
                    continuation: continuation,
                    didFinish: { [weak self] identifier in
                        self?.clearActiveRequest(matching: identifier)
                    }
                )

                let cancellation = { @Sendable in requestState.cancel() }
                let installation = cancellationRegistration.install(
                    cancellation: cancellation,
                    installActiveRequest: { [self] in
                        installActiveRequest(
                            ActiveRequest(
                                identifier: identifier,
                                cancel: cancellation
                            )
                        )
                    }
                )

                guard installation.installed else {
                    requestState.cancel()
                    return
                }

                installation.previousCancellation?()
                if Task.isCancelled {
                    cancellationRegistration.cancel()
                }
                requestState.start(
                    operation: operation,
                    deadline: deadline
                )
            }
        } onCancel: {
            cancellationRegistration.cancel()
        }
    }

    func cancelActiveRequest() {
        let cancel = lock.withLock { activeRequest?.cancel }
        cancel?()
    }

    private func installActiveRequest(_ request: ActiveRequest) -> (@Sendable () -> Void)? {
        lock.withLock {
            let previousCancellation = activeRequest?.cancel
            activeRequest = request
            return previousCancellation
        }
    }

    private func clearActiveRequest(matching identifier: UUID) {
        lock.withLock {
            guard activeRequest?.identifier == identifier else {
                return
            }
            activeRequest = nil
        }
    }
}
