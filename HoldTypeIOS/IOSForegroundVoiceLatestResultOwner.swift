import Foundation
import Observation
@_spi(HoldTypeIOSCore) import HoldTypePersistence

nonisolated enum IOSForegroundVoiceLatestResultStatus: Equatable, Sendable {
    case notLoaded
    case absent
    case ready
    case priorWhileSaving
    case savingWithoutPrior
    case expired
    case clockRollbackAmbiguous
    case clearing
    case cleanupPending
    case unavailable
}

nonisolated enum IOSForegroundVoiceLatestResultNotice: Equatable, Sendable {
    case loadFailed
    case clearFailed
    case clearStateUnknown
    case resultChanged
}

/// Text-bearing presentation for the process-owned Latest Result surface.
/// Persistence identity remains private to the owner, and reflection is
/// intentionally content-free.
nonisolated struct IOSForegroundVoiceLatestResultPresentation:
    Equatable,
    Sendable {
    let status: IOSForegroundVoiceLatestResultStatus
    let text: String?
    let notice: IOSForegroundVoiceLatestResultNotice?

    static let initial = IOSForegroundVoiceLatestResultPresentation(
        status: .notLoaded,
        text: nil,
        notice: nil
    )
}

nonisolated struct IOSForegroundVoiceLatestResultClearCommand:
    Equatable,
    Sendable {
    fileprivate let presentationRevision: UInt64
}

nonisolated enum IOSForegroundVoiceLatestResultClearAdmission:
    Equatable,
    Sendable {
    case accepted
    case stale
    case unavailable
}

nonisolated enum IOSForegroundVoiceLatestResultOwnerError:
    Error,
    Equatable,
    Sendable {
    case invalidObservation
    case loadFailed
}

private nonisolated struct IOSForegroundVoiceLatestResultClient: Sendable {
    typealias Load = @Sendable () async throws
        -> IOSForegroundVoiceLatestResultObservation
    typealias Clear = @Sendable (
        IOSAcceptedOutputDeliveryExpectation
    ) async throws -> IOSForegroundVoiceClearResult

    let load: Load
    let clear: Clear
}

private nonisolated struct IOSForegroundVoiceLatestResultSelection: Sendable {
    let record: IOSAcceptedOutputDeliveryRecord

    var expectation: IOSAcceptedOutputDeliveryExpectation {
        IOSAcceptedOutputDeliveryExpectation(record: record)
    }
}

private nonisolated enum IOSForegroundVoiceLatestResultClearExecution:
    Sendable {
    case completed(IOSForegroundVoiceClearResult)
    case failed(reconciliation: IOSForegroundVoiceLatestResultObservation?)
}

private nonisolated enum IOSForegroundVoiceLatestResultLoadExecution:
    Sendable {
    case completed(IOSForegroundVoiceLatestResultObservation)
    case failed(isCancellation: Bool)
}

private nonisolated struct IOSForegroundVoiceLatestResultSequenced<
    Value: Sendable
>:
    Sendable {
    let sequence: UInt64
    let value: Value
}

/// Serializes Latest reads and Clear as one facade client. Actor isolation by
/// itself is reentrant at each persistence await, so this core hands an
/// explicit FIFO lease from one operation to the next.
private actor IOSForegroundVoiceLatestResultOperationCore {
    private let client: IOSForegroundVoiceLatestResultClient
    private var operationIsActive = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var completionSequence: UInt64 = 0

    init(client: IOSForegroundVoiceLatestResultClient) {
        self.client = client
    }

    func load() async
        -> IOSForegroundVoiceLatestResultSequenced<
            IOSForegroundVoiceLatestResultLoadExecution
        > {
        await acquireOperation()
        do {
            try Task.checkCancellation()
            let observation = try await client.load()
            let sequence = nextCompletionSequence()
            releaseOperation()
            return IOSForegroundVoiceLatestResultSequenced(
                sequence: sequence,
                value: .completed(observation)
            )
        } catch {
            let sequence = nextCompletionSequence()
            releaseOperation()
            return IOSForegroundVoiceLatestResultSequenced(
                sequence: sequence,
                value: .failed(
                    isCancellation: Self.isCancellation(error)
                )
            )
        }
    }

    /// Once Clear is admitted, reconciliation is part of that process-owned
    /// operation. It deliberately ignores cancellation of the initiating UI
    /// caller and keeps the exact expectation captured at admission.
    func clear(
        expected: IOSAcceptedOutputDeliveryExpectation
    ) async -> IOSForegroundVoiceLatestResultSequenced<
        IOSForegroundVoiceLatestResultClearExecution
    > {
        await acquireOperation()
        do {
            let result = try await client.clear(expected)
            let sequence = nextCompletionSequence()
            releaseOperation()
            return IOSForegroundVoiceLatestResultSequenced(
                sequence: sequence,
                value: .completed(result)
            )
        } catch {
            let reconciliation = try? await client.load()
            let sequence = nextCompletionSequence()
            releaseOperation()
            return IOSForegroundVoiceLatestResultSequenced(
                sequence: sequence,
                value: .failed(reconciliation: reconciliation)
            )
        }
    }

    private func acquireOperation() async {
        guard operationIsActive else {
            operationIsActive = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func releaseOperation() {
        guard !waiters.isEmpty else {
            operationIsActive = false
            return
        }
        waiters.removeFirst().resume()
    }

    private func nextCompletionSequence() -> UInt64 {
        completionSequence &+= 1
        return completionSequence
    }

    private nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let error = error as? IOSForegroundVoicePersistenceError,
           error == .cancelledBeforeOperation {
            return true
        }
        return false
    }
}

/// The single process-owned text authority for the Voice Latest Result card.
/// The Voice controller receives only its payload-free availability mapping;
/// records, expectations, and accepted text never enter controller state.
@MainActor
@Observable
final class IOSForegroundVoiceLatestResultOwner {
    typealias BeforePublishing = @MainActor @Sendable (UInt64) async -> Void

    private(set) var presentation =
        IOSForegroundVoiceLatestResultPresentation.initial

    @ObservationIgnored
    private let operationCore: IOSForegroundVoiceLatestResultOperationCore
    @ObservationIgnored
    private let beforePublishing: BeforePublishing
    @ObservationIgnored
    private var selection: IOSForegroundVoiceLatestResultSelection?
    @ObservationIgnored
    private var clearExpectation: IOSAcceptedOutputDeliveryExpectation?
    @ObservationIgnored
    private var clearTask: Task<Void, Never>?
    @ObservationIgnored
    private var presentationRevision: UInt64 = 0
    @ObservationIgnored
    private var publicationEpoch: UInt64 = 0
    @ObservationIgnored
    private var latestPublishedCoreSequence: UInt64 = 0

    convenience init(persistenceOwner: IOSForegroundVoicePersistenceOwner) {
        self.init(
            load: { try await persistenceOwner.loadLatestResult() },
            clear: { expectation in
                try await persistenceOwner.clearLatestResult(
                    expected: expectation
                )
            }
        )
    }

    init(
        load: @escaping @Sendable () async throws
            -> IOSForegroundVoiceLatestResultObservation,
        clear: @escaping @Sendable (
            IOSAcceptedOutputDeliveryExpectation
        ) async throws -> IOSForegroundVoiceClearResult,
        beforePublishing: @escaping BeforePublishing = { _ in }
    ) {
        operationCore = IOSForegroundVoiceLatestResultOperationCore(
            client: IOSForegroundVoiceLatestResultClient(
                load: load,
                clear: clear
            )
        )
        self.beforePublishing = beforePublishing
    }

    deinit {
        clearTask?.cancel()
    }

    var clearCommand: IOSForegroundVoiceLatestResultClearCommand? {
        guard clearTask == nil,
              clearExpectation != nil,
              presentation.status == .ready
                || presentation.status == .clockRollbackAmbiguous else {
            return nil
        }
        return IOSForegroundVoiceLatestResultClearCommand(
            presentationRevision: presentationRevision
        )
    }

    /// The workflow's only Latest loader. The same durable observation updates
    /// this text owner and is returned unchanged for the controller's
    /// payload-free projection.
    func loadForVoiceWorkflow() async throws
        -> IOSForegroundVoiceLatestResultObservation {
        let startingEpoch = publicationEpoch
        let completion = await operationCore.load()
        await beforePublishing(completion.sequence)
        switch completion.value {
        case .completed(let observation):
            do {
                let projection = try Self.projection(for: observation)
                if publicationEpoch == startingEpoch,
                   completion.sequence > latestPublishedCoreSequence {
                    latestPublishedCoreSequence = completion.sequence
                    publish(projection)
                }
                return observation
            } catch {
                if publicationEpoch == startingEpoch,
                   completion.sequence > latestPublishedCoreSequence {
                    latestPublishedCoreSequence = completion.sequence
                    publishUnavailable(notice: .loadFailed)
                }
                throw error
            }
        case .failed(let isCancellation):
            if !isCancellation,
               publicationEpoch == startingEpoch,
               completion.sequence > latestPublishedCoreSequence {
                latestPublishedCoreSequence = completion.sequence
                publishUnavailable(notice: .loadFailed)
            }
            if isCancellation { throw CancellationError() }
            throw IOSForegroundVoiceLatestResultOwnerError.loadFailed
        }
    }

    /// Admits an exact revision-bound Clear and transfers its lifetime to this
    /// process owner before returning. The caller receives no task handle that
    /// could cancel an already-admitted destructive operation.
    @discardableResult
    func clear(
        _ command: IOSForegroundVoiceLatestResultClearCommand
    ) -> IOSForegroundVoiceLatestResultClearAdmission {
        guard command.presentationRevision == presentationRevision else {
            return .stale
        }
        guard clearTask == nil, let expected = clearExpectation else {
            return .unavailable
        }

        let retainedText = presentation.text
        invalidateOutstandingPublications()
        publish(
            Projection(
                presentation: IOSForegroundVoiceLatestResultPresentation(
                    status: .clearing,
                    text: retainedText,
                    notice: nil
                ),
                selection: selection,
                clearExpectation: nil
            )
        )

        let operationCore = operationCore
        clearTask = Task { @MainActor [weak self] in
            let completion = await operationCore.clear(expected: expected)
            guard let self else { return }
            await self.completeClear(
                completion,
                expected: expected
            )
        }
        return .accepted
    }

    /// Test and composition synchronization seam. It never starts or retries
    /// work; it only waits for an already-admitted Clear to reconcile.
    func waitUntilClearIsIdle() async {
        await clearTask?.value
    }

    private func completeClear(
        _ completion: IOSForegroundVoiceLatestResultSequenced<
            IOSForegroundVoiceLatestResultClearExecution
        >,
        expected: IOSAcceptedOutputDeliveryExpectation
    ) async {
        await beforePublishing(completion.sequence)
        clearTask = nil
        guard completion.sequence > latestPublishedCoreSequence else {
            return
        }
        latestPublishedCoreSequence = completion.sequence
        let execution = completion.value
        switch execution {
        case .completed(let result):
            switch result {
            case .cleared, .alreadyAbsent:
                publish(
                    Projection(
                        presentation: IOSForegroundVoiceLatestResultPresentation(
                            status: .absent,
                            text: nil,
                            notice: nil
                        ),
                        selection: nil,
                        clearExpectation: nil
                    )
                )
            case .clearedCleanupPending:
                publish(
                    Projection(
                        presentation: IOSForegroundVoiceLatestResultPresentation(
                            status: .cleanupPending,
                            text: nil,
                            notice: nil
                        ),
                        selection: nil,
                        clearExpectation: nil
                    )
                )
            }
        case .failed(let reconciliation):
            guard let reconciliation,
                  let projection = try? Self.projection(
                      for: reconciliation
                  ) else {
                publishUnavailable(
                    notice: .clearStateUnknown
                )
                return
            }
            publish(
                projection.withNotice(
                    Self.clearFailureNotice(
                        after: reconciliation,
                        expected: expected
                    )
                )
            )
        }
    }

    private func publishUnavailable(
        notice: IOSForegroundVoiceLatestResultNotice
    ) {
        publish(
            Projection(
                presentation: IOSForegroundVoiceLatestResultPresentation(
                    status: .unavailable,
                    text: nil,
                    notice: notice
                ),
                selection: nil,
                clearExpectation: nil
            )
        )
    }

    private func publish(_ projection: Projection) {
        presentationRevision &+= 1
        presentation = projection.presentation
        selection = projection.selection
        clearExpectation = projection.clearExpectation
    }

    private func invalidateOutstandingPublications() {
        publicationEpoch &+= 1
    }

    private nonisolated struct Projection {
        let presentation: IOSForegroundVoiceLatestResultPresentation
        let selection: IOSForegroundVoiceLatestResultSelection?
        let clearExpectation: IOSAcceptedOutputDeliveryExpectation?

        func withNotice(
            _ notice: IOSForegroundVoiceLatestResultNotice?
        ) -> Projection {
            Projection(
                presentation: IOSForegroundVoiceLatestResultPresentation(
                    status: presentation.status,
                    text: presentation.text,
                    notice: notice
                ),
                selection: selection,
                clearExpectation: clearExpectation
            )
        }
    }

    private nonisolated static func projection(
        for observation: IOSForegroundVoiceLatestResultObservation
    ) throws -> Projection {
        switch observation {
        case .absent:
            return Projection(
                presentation: IOSForegroundVoiceLatestResultPresentation(
                    status: .absent,
                    text: nil,
                    notice: nil
                ),
                selection: nil,
                clearExpectation: nil
            )
        case .resultReady(let record):
            guard let text = record.acceptedText else {
                throw IOSForegroundVoiceLatestResultOwnerError
                    .invalidObservation
            }
            let selection = IOSForegroundVoiceLatestResultSelection(
                record: record
            )
            return Projection(
                presentation: IOSForegroundVoiceLatestResultPresentation(
                    status: .ready,
                    text: text,
                    notice: nil
                ),
                selection: selection,
                clearExpectation: selection.expectation
            )
        case .savingResult(_, let priorResult):
            guard let priorResult else {
                return Projection(
                    presentation: IOSForegroundVoiceLatestResultPresentation(
                        status: .savingWithoutPrior,
                        text: nil,
                        notice: nil
                    ),
                    selection: nil,
                    clearExpectation: nil
                )
            }
            guard let text = priorResult.acceptedText else {
                throw IOSForegroundVoiceLatestResultOwnerError
                    .invalidObservation
            }
            let selection = IOSForegroundVoiceLatestResultSelection(
                record: priorResult
            )
            return Projection(
                presentation: IOSForegroundVoiceLatestResultPresentation(
                    status: .priorWhileSaving,
                    text: text,
                    notice: nil
                ),
                selection: selection,
                clearExpectation: nil
            )
        case .expired:
            return Projection(
                presentation: IOSForegroundVoiceLatestResultPresentation(
                    status: .expired,
                    text: nil,
                    notice: nil
                ),
                selection: nil,
                clearExpectation: nil
            )
        case .clockRollbackAmbiguous(let expectation):
            return Projection(
                presentation: IOSForegroundVoiceLatestResultPresentation(
                    status: .clockRollbackAmbiguous,
                    text: nil,
                    notice: nil
                ),
                selection: nil,
                clearExpectation: expectation
            )
        case .clearedCleanupPending:
            return Projection(
                presentation: IOSForegroundVoiceLatestResultPresentation(
                    status: .cleanupPending,
                    text: nil,
                    notice: nil
                ),
                selection: nil,
                clearExpectation: nil
            )
        }
    }

    private nonisolated static func clearFailureNotice(
        after observation: IOSForegroundVoiceLatestResultObservation,
        expected: IOSAcceptedOutputDeliveryExpectation
    ) -> IOSForegroundVoiceLatestResultNotice? {
        switch observation {
        case .resultReady(let record):
            return IOSAcceptedOutputDeliveryExpectation(record: record)
                == expected ? .clearFailed : .resultChanged
        case .savingResult(_, let priorResult):
            guard let priorResult else { return .resultChanged }
            return IOSAcceptedOutputDeliveryExpectation(record: priorResult)
                == expected ? .clearFailed : .resultChanged
        case .clockRollbackAmbiguous(let current):
            return current == expected ? .clearFailed : .resultChanged
        case .absent, .expired, .clearedCleanupPending:
            return nil
        }
    }

}

extension IOSForegroundVoiceLatestResultOwner:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSForegroundVoiceLatestResultOwner(<redacted>)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceLatestResultPresentation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSForegroundVoiceLatestResultPresentation(<redacted>)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceLatestResultClearCommand:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSForegroundVoiceLatestResultClearCommand(<redacted>)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
