import Foundation
import HoldTypeDomain

enum IOSFailedHistoryRetryCredentialEligibility: Equatable, Sendable {
    case available
    case unavailable
}

/// Transient containing-app setup frozen before the durable reservation. It
/// contains no credential material; eligibility is only the already-validated
/// result of the app-owned credential/setup check.
struct IOSFailedHistoryRetrySetupSnapshot: Equatable, Sendable {
    let transcriptionConfiguration: TranscriptionConfiguration
    let transcriptionPromptComposition: TranscriptionPromptComposition
    let textCorrectionConfiguration: TextCorrectionConfiguration
    let postProcessingConfiguration: TranscriptPostProcessingConfiguration
    let translationConfiguration: TranslationConfiguration?
    let keepLatestResult: Bool

    init(
        credentialEligibility:
            IOSFailedHistoryRetryCredentialEligibility,
        transcriptionConfiguration: TranscriptionConfiguration,
        transcriptionPromptComposition: TranscriptionPromptComposition,
        textCorrectionConfiguration: TextCorrectionConfiguration,
        postProcessingConfiguration: TranscriptPostProcessingConfiguration,
        translationConfiguration: TranslationConfiguration?,
        keepLatestResult: Bool
    ) throws {
        guard credentialEligibility == .available,
              !transcriptionConfiguration.customLanguageCodeValidation
                .isInvalid,
              IOSPendingRecordingValidation.isValidModel(
                  transcriptionConfiguration.resolvedModel
              ),
              IOSPendingRecordingValidation.isValidLanguageCode(
                  transcriptionConfiguration.resolvedLanguageCode
              ),
              transcriptionPromptComposition.contextEchoGuardText == nil,
              (!textCorrectionConfiguration.isEnabled
                  || IOSPendingRecordingValidation.isValidModel(
                      textCorrectionConfiguration.resolvedModel
                  )),
              translationConfiguration.map({ configuration in
                  configuration.canRunAction
                      && IOSPendingRecordingValidation.isValidModel(
                          configuration.resolvedModel
                      )
              }) ?? true else {
            throw IOSFailedHistoryError.invalidTransition
        }
        self.transcriptionConfiguration = transcriptionConfiguration
        self.transcriptionPromptComposition =
            transcriptionPromptComposition
        self.textCorrectionConfiguration = textCorrectionConfiguration
        self.postProcessingConfiguration = postProcessingConfiguration
        self.translationConfiguration = translationConfiguration
        self.keepLatestResult = keepLatestResult
    }

    func supports(_ outputIntent: DictationOutputIntent) -> Bool {
        switch outputIntent {
        case .standard:
            translationConfiguration == nil
        case .translate:
            translationConfiguration?.canRunAction == true
        }
    }
}

extension IOSFailedHistoryRetrySetupSnapshot: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetrySetupSnapshot(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// A successful provider invocation plus the exact terminal authority required
/// by the next durable Retry transition. C4.4B consumes this value; C4.4A does
/// not interpret provider outcomes or clear the live owner on completion.
struct IOSFailedHistoryRetryProviderCompletion<Outcome: Sendable>: Sendable {
    let outcome: Outcome
    let dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt
    let claim: IOSFailedHistoryRetryProviderCompletionClaim
    let setup: IOSFailedHistoryRetrySetupSnapshot
}

extension IOSFailedHistoryRetryProviderCompletion: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryProviderCompletion(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Narrow transient input for one provider pipeline. It exposes only the
/// descriptor-backed audio, the already-frozen setup, the Usage identity, and
/// the preserved output intent; no Store receipt or mutation authority crosses
/// the provider boundary.
struct IOSFailedHistoryRetryProviderInvocation: Sendable {
    let audio: IOSPendingTranscriptionAudio
    let setup: IOSFailedHistoryRetrySetupSnapshot
    let transcriptionID: UUID
    let outputIntent: DictationOutputIntent
}

extension IOSFailedHistoryRetryProviderInvocation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryProviderInvocation(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// The sole successful provider output. Dropping it before local acceptance
/// claims the result converts the exact completed Retry back into the prior
/// recoverable failed row; it never leaves a completed live owner wedged.
final class IOSFailedHistoryRetryAcceptedProviderOutput:
    @unchecked Sendable {
    let transcript: AcceptedTranscript
    let dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt
    let completionClaim: IOSFailedHistoryRetryProviderCompletionClaim
    let setup: IOSFailedHistoryRetrySetupSnapshot

    private let terminalRelay: IOSFailedHistoryRetryCancellationRelay
    private let acceptanceLock = NSLock()
    private var acceptanceClaimed = false

    fileprivate init(
        transcript: AcceptedTranscript,
        dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        completionClaim: IOSFailedHistoryRetryProviderCompletionClaim,
        setup: IOSFailedHistoryRetrySetupSnapshot,
        terminalRelay: IOSFailedHistoryRetryCancellationRelay
    ) {
        self.transcript = transcript
        self.dispatchReceipt = dispatchReceipt
        self.completionClaim = completionClaim
        self.setup = setup
        self.terminalRelay = terminalRelay
    }

    func accept()
        async throws -> IOSAcceptedHistoryAcceptanceResolution {
        acceptanceLock.withLock {
            acceptanceClaimed = true
        }
        return try await terminalRelay.completeProviderAcceptance(
            transcript: transcript,
            claim: completionClaim,
            setup: setup
        )
    }

    deinit {
        let shouldAbandon = acceptanceLock.withLock {
            !acceptanceClaimed
        }
        if shouldAbandon {
            terminalRelay.requestProviderOutputAbandonment()
        }
    }
}

extension IOSFailedHistoryRetryAcceptedProviderOutput:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryAcceptedProviderOutput(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSFailedHistoryRetryPipelineExecutionResult: Sendable {
    case accepted(IOSFailedHistoryRetryAcceptedProviderOutput)
    case failed
}

extension IOSFailedHistoryRetryPipelineExecutionResult:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryPipelineExecutionResult(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// One process-local, one-shot provider handoff for an exact durable Retry.
/// The provider closure runs only after the root gate turn that created this
/// value has ended. Cancellation and deinit both use the same exact durable
/// cleanup relay.
final class IOSFailedHistoryRetryHandoff: @unchecked Sendable {
    private let audio: IOSPendingTranscriptionAudio
    private let dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt
    private let registration: IOSFailedHistoryRetryProviderRegistration
    private let retryState: IOSFailedHistoryRetryLiveOwnerState
    private let setup: IOSFailedHistoryRetrySetupSnapshot
    private let cancellationRelay:
        IOSFailedHistoryRetryCancellationRelay

    fileprivate init(
        audio: IOSPendingTranscriptionAudio,
        dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        registration: IOSFailedHistoryRetryProviderRegistration,
        retryState: IOSFailedHistoryRetryLiveOwnerState,
        setup: IOSFailedHistoryRetrySetupSnapshot,
        cancellationRelay: IOSFailedHistoryRetryCancellationRelay
    ) {
        self.audio = audio
        self.dispatchReceipt = dispatchReceipt
        self.registration = registration
        self.retryState = retryState
        self.setup = setup
        self.cancellationRelay = cancellationRelay
    }

    #if DEBUG
    /// C4.4A test seam. Production builds expose only the fixed C4.4B pipeline
    /// below, never an arbitrary provider-capable closure.
    func execute<Outcome: Sendable>(
        _ operation: @escaping @Sendable (
            IOSPendingTranscriptionAudio,
            IOSFailedHistoryRetrySetupSnapshot
        ) async -> Outcome
    ) async throws -> IOSFailedHistoryRetryProviderCompletion<Outcome> {
        try await executeProvider { invocation in
            await operation(invocation.audio, invocation.setup)
        }
    }
    #endif

    func executePipeline(
        _ pipeline: IOSFailedHistoryRetryPipeline
    ) async throws -> IOSFailedHistoryRetryPipelineExecutionResult {
        let completion = try await executeProvider { invocation in
            try await pipeline.run(invocation)
        }

        switch completion.outcome {
        case .accepted(let transcript):
            return .accepted(
                IOSFailedHistoryRetryAcceptedProviderOutput(
                    transcript: transcript,
                    dispatchReceipt: completion.dispatchReceipt,
                    completionClaim: completion.claim,
                    setup: completion.setup,
                    terminalRelay: cancellationRelay
                )
            )
        case .failed(let failure):
            let disposition: IOSFailedHistoryRetryFailureDisposition
            if let category = failure.durableCategory {
                disposition = .mapped(
                    category: category,
                    stage: failure.stage
                )
            } else {
                disposition = .preservePrevious
            }
            try await cancellationRelay.completeProviderFailure(
                claim: completion.claim,
                disposition: disposition
            )
            return .failed
        }
    }

    private func executeProvider<Outcome: Sendable>(
        _ operation: @escaping @Sendable (
            IOSFailedHistoryRetryProviderInvocation
        ) async throws -> Outcome
    ) async throws -> IOSFailedHistoryRetryProviderCompletion<Outcome> {
        guard let launchClaim = await retryState.claimProviderLaunch(
            registration
        ) else {
            throw IOSPendingRecordingError.dispatchAlreadyCommitted
        }

        let audio = audio
        let setup = setup
        let transcriptionID = dispatchReceipt.retryOperation.transcriptionID
        let outputIntent = dispatchReceipt.row.outputIntent
        let providerTask = Task<Outcome, Error> {
            defer { audio.invalidate() }
            try await launchClaim.waitForLaunch()
            try Task.checkCancellation()
            return try await IOSFailedHistoryRetryProviderTaskContext
                .$cancellationOwnerIdentity.withValue(
                    ObjectIdentifier(cancellationRelay)
                ) {
                    try await operation(
                        IOSFailedHistoryRetryProviderInvocation(
                            audio: audio,
                            setup: setup,
                            transcriptionID: transcriptionID,
                            outputIntent: outputIntent
                        )
                    )
                }
        }
        await cancellationRelay.registerProviderDrain {
            _ = await providerTask.result
        }
        guard launchClaim.installRunningCancellation({
            providerTask.cancel()
        }) else {
            providerTask.cancel()
            _ = await providerTask.result
            try await cancellationRelay.cancel()
            throw IOSPendingRecordingError.dispatchAlreadyCommitted
        }

        if Task.isCancelled {
            try await cancellationRelay.cancel()
            _ = await providerTask.result
            throw CancellationError()
        }
        guard launchClaim.launch() else {
            providerTask.cancel()
            _ = await providerTask.result
            try await cancellationRelay.cancel()
            throw IOSPendingRecordingError.dispatchAlreadyCommitted
        }

        return try await withTaskCancellationHandler {
            let result = await providerTask.result
            if Task.isCancelled {
                try await cancellationRelay.cancel()
                throw CancellationError()
            }
            switch result {
            case .success(let outcome):
                guard let terminal = await retryState
                    .claimProviderCompletion(launchClaim),
                      case .completion(let completionClaim) = terminal else {
                    try await cancellationRelay.cancel()
                    throw CancellationError()
                }
                await cancellationRelay.markProviderCompletionClaimed()
                return IOSFailedHistoryRetryProviderCompletion(
                    outcome: outcome,
                    dispatchReceipt: dispatchReceipt,
                    claim: completionClaim,
                    setup: setup
                )
            case .failure:
                try await cancellationRelay.cancel()
                throw CancellationError()
            }
        } onCancel: {
            cancellationRelay.requestCancellation()
        }
    }

    func cancel() async throws {
        if IOSFailedHistoryRetryProviderTaskContext
            .cancellationOwnerIdentity
            == ObjectIdentifier(cancellationRelay) {
            try await cancellationRelay.cancelFromProviderTask()
        } else {
            try await cancellationRelay.cancel()
        }
    }

    /// Nonblocking cancellation request for callback tasks that cannot safely
    /// await the provider task they are helping unwind.
    func requestCancellation() {
        cancellationRelay.requestCancellation()
    }

    deinit {
        cancellationRelay.requestCancellation()
    }
}

private enum IOSFailedHistoryRetryProviderTaskContext {
    @TaskLocal static var cancellationOwnerIdentity: ObjectIdentifier?
}

extension IOSFailedHistoryRetryHandoff: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryHandoff(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

private actor IOSFailedHistoryRetryCancellationRelay:
    IOSFailedHistoryRetryProviderTerminalOwner {
    private struct InFlight: Sendable {
        let id: UUID
        let task: Task<Void, Error>
    }

    private enum AcceptanceProgress: Sendable {
        case pending(
            IOSFailedHistoryRetryAcceptingOutputReceipt
        )
        case completed(
            IOSFailedHistoryRetrySuccessReceipt,
            IOSAcceptedHistoryAcceptanceResolution
        )
    }

    private struct AcceptanceInFlight: Sendable {
        let id: UUID
        let task: Task<AcceptanceProgress, Error>
    }

    private final class AcceptanceCheckpointState: @unchecked Sendable {
        private let lock = NSLock()
        private var frozenProof:
            IOSAcceptedOutputDeliveryFrozenSlotProof?

        func loadFrozenProof()
            -> IOSAcceptedOutputDeliveryFrozenSlotProof? {
            lock.withLock { frozenProof }
        }

        func storeFrozenProof(
            _ proof: IOSAcceptedOutputDeliveryFrozenSlotProof
        ) {
            lock.withLock { frozenProof = proof }
        }

        func clear() {
            lock.withLock { frozenProof = nil }
        }
    }

    private let dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt
    private let registration: IOSFailedHistoryRetryProviderRegistration
    private let retryState: IOSFailedHistoryRetryLiveOwnerState
    private let operationGate: IOSPersistenceOperationGate
    private let failedStore: IOSFailedHistoryStore
    private let policyStore: IOSHistoryPolicyStore
    private let acceptedHistoryStore: IOSAcceptedHistoryStore
    private let outboxStore: IOSAcceptedHistoryOutboxStore
    private let deliveryStore: IOSAcceptedOutputDeliveryStore
    private let acceptanceState: IOSAcceptedHistoryAcceptanceOperationState
    private let pendingReplacementState:
        IOSAcceptedHistoryPendingReplacementOperationState
    private let ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity
    private let repositoryIdentityState:
        IOSAcceptedHistoryCoordinatorRepositoryIdentityState
    private let repositoryRegistration:
        IOSAcceptedHistoryCoordinatorRepositoryRegistration?

    private var cancellationClaim:
        IOSFailedHistoryRetryProviderCancellationClaim?
    private var cancellationClaimTask:
        Task<IOSFailedHistoryRetryProviderCancellationClaim, Error>?
    private var providerDrain: (@Sendable () async -> Void)?
    private var inFlight: InFlight?
    private var providerFailureInFlight: InFlight?
    private var providerFailureClaim:
        IOSFailedHistoryRetryProviderCompletionClaim?
    private var providerFailureDisposition:
        IOSFailedHistoryRetryFailureDisposition?
    private var providerAcceptanceTranscript: AcceptedTranscript?
    private var providerAcceptanceClaim:
        IOSFailedHistoryRetryProviderCompletionClaim?
    private var providerAcceptanceSetup:
        IOSFailedHistoryRetrySetupSnapshot?
    private var providerAcceptanceReceipt:
        IOSFailedHistoryRetryAcceptingOutputReceipt?
    private var providerAcceptanceInFlight: AcceptanceInFlight?
    private var providerAcceptanceResolution:
        IOSAcceptedHistoryAcceptanceResolution?
    private let providerAcceptanceCheckpointState =
        AcceptanceCheckpointState()
    private var cancellationCompleted = false
    private var providerCompletionClaimed = false
    private var providerFailureCompleted = false
    private var providerAcceptanceCompleted = false
    private var audioInvalidations: [@Sendable () -> Void]

    init(
        dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        registration: IOSFailedHistoryRetryProviderRegistration,
        retryState: IOSFailedHistoryRetryLiveOwnerState,
        operationGate: IOSPersistenceOperationGate,
        failedStore: IOSFailedHistoryStore,
        policyStore: IOSHistoryPolicyStore,
        acceptedHistoryStore: IOSAcceptedHistoryStore,
        outboxStore: IOSAcceptedHistoryOutboxStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        acceptanceState: IOSAcceptedHistoryAcceptanceOperationState,
        pendingReplacementState:
            IOSAcceptedHistoryPendingReplacementOperationState,
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity,
        repositoryIdentityState:
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState,
        repositoryRegistration:
            IOSAcceptedHistoryCoordinatorRepositoryRegistration?,
        audioInvalidation: @escaping @Sendable () -> Void
    ) {
        self.dispatchReceipt = dispatchReceipt
        self.registration = registration
        self.retryState = retryState
        self.operationGate = operationGate
        self.failedStore = failedStore
        self.policyStore = policyStore
        self.acceptedHistoryStore = acceptedHistoryStore
        self.outboxStore = outboxStore
        self.deliveryStore = deliveryStore
        self.acceptanceState = acceptanceState
        self.pendingReplacementState = pendingReplacementState
        self.ownerIdentity = ownerIdentity
        self.repositoryIdentityState = repositoryIdentityState
        self.repositoryRegistration = repositoryRegistration
        audioInvalidations = [audioInvalidation]
    }

    nonisolated func requestCancellation() {
        Task.detached { [self] in
            for _ in 0..<3 {
                do {
                    try await cancel()
                    return
                } catch {
                    await Task.yield()
                }
            }
        }
    }

    nonisolated func requestProviderCompletionRecovery() {
        Task.detached { [self] in
            for _ in 0..<3 {
                do {
                    try await recoverProviderCompletion()
                    return
                } catch {
                    await Task.yield()
                }
            }
        }
    }

    nonisolated func requestProviderOutputAbandonment() {
        Task.detached { [self] in
            for _ in 0..<3 {
                do {
                    try await abandonProviderOutput()
                    return
                } catch {
                    await Task.yield()
                }
            }
        }
    }

    func registerProviderDrain(
        _ drain: @escaping @Sendable () async -> Void
    ) {
        guard providerDrain == nil,
              !cancellationCompleted,
              !providerCompletionClaimed else {
            return
        }
        providerDrain = drain
    }

    func registerProviderAudio(_ audio: IOSPendingTranscriptionAudio) {
        guard cancellationClaim == nil,
              !cancellationCompleted,
              !providerCompletionClaimed else {
            audio.invalidate()
            return
        }
        audioInvalidations.append { audio.invalidate() }
    }

    func markProviderCompletionClaimed() {
        providerCompletionClaimed = true
        providerDrain = nil
        invalidateProviderAudio()
    }

    func completeProviderFailure(
        claim: IOSFailedHistoryRetryProviderCompletionClaim,
        disposition: IOSFailedHistoryRetryFailureDisposition
    ) async throws {
        guard providerCompletionClaimed,
              !cancellationCompleted,
              providerAcceptanceClaim == nil,
              !providerFailureCompleted else {
            if providerFailureCompleted { return }
            throw IOSFailedHistoryError.invalidTransition
        }
        if let providerFailureClaim {
            guard providerFailureClaim == claim else {
                throw IOSFailedHistoryError.invalidTransition
            }
        } else {
            providerFailureClaim = claim
        }
        if let providerFailureDisposition {
            guard providerFailureDisposition == disposition else {
                throw IOSFailedHistoryError.invalidTransition
            }
        } else {
            providerFailureDisposition = disposition
        }
        try await awaitProviderFailureWork()
    }

    func completeProviderAcceptance(
        transcript: AcceptedTranscript,
        claim: IOSFailedHistoryRetryProviderCompletionClaim,
        setup: IOSFailedHistoryRetrySetupSnapshot
    ) async throws -> IOSAcceptedHistoryAcceptanceResolution {
        guard providerCompletionClaimed,
              !cancellationCompleted,
              !providerFailureCompleted,
              providerFailureClaim == nil,
              providerFailureDisposition == nil else {
            throw IOSFailedHistoryError.invalidTransition
        }
        if let providerAcceptanceClaim {
            guard providerAcceptanceClaim == claim,
                  providerAcceptanceTranscript == transcript,
                  providerAcceptanceSetup == setup else {
                throw IOSFailedHistoryError.invalidTransition
            }
        } else {
            providerAcceptanceClaim = claim
            providerAcceptanceTranscript = transcript
            providerAcceptanceSetup = setup
        }
        if providerAcceptanceCompleted,
           let providerAcceptanceResolution {
            return providerAcceptanceResolution
        }
        return try await awaitProviderAcceptanceWork()
    }

    func cancel() async throws {
        guard !cancellationCompleted else { return }
        guard !providerCompletionClaimed else {
            throw IOSFailedHistoryError.invalidTransition
        }
        let work = cancellationWork()

        do {
            try await work.task.value
            if inFlight?.id == work.id {
                inFlight = nil
                cancellationCompleted = true
                providerDrain = nil
            }
        } catch {
            if inFlight?.id == work.id {
                inFlight = nil
            }
            throw error
        }
    }

    /// A provider task cannot await its own drain. It atomically retires the
    /// provider authority, starts the normal cleanup relay, and returns so that
    /// the provider closure can unwind and satisfy that relay's drain.
    func cancelFromProviderTask() async throws {
        guard !cancellationCompleted else { return }
        guard !providerCompletionClaimed else {
            throw IOSFailedHistoryError.invalidTransition
        }
        _ = try await exactCancellationClaim()
        invalidateProviderAudio()
        _ = cancellationWork()
    }

    private func cancellationWork() -> InFlight {
        if let inFlight { return inFlight }
        let id = UUID()
        let task = Task.detached { [self] in
            try await performCancellation()
        }
        let work = InFlight(id: id, task: task)
        inFlight = work
        return work
    }

    private func recoverProviderCompletion() async throws {
        if providerAcceptanceClaim != nil {
            _ = try await awaitProviderAcceptanceWork()
            return
        }
        try await recoverProviderFailure()
    }

    private func recoverProviderFailure() async throws {
        guard providerCompletionClaimed,
              providerFailureClaim != nil,
              providerFailureDisposition != nil,
              !providerFailureCompleted else {
            return
        }
        try await awaitProviderFailureWork()
    }

    private func abandonProviderOutput() async throws {
        guard providerCompletionClaimed,
              providerAcceptanceClaim == nil,
              !providerFailureCompleted else {
            return
        }
        let claim = try await exactProviderCompletionClaim()
        try await completeProviderFailure(
            claim: claim,
            disposition: .preservePrevious
        )
    }

    private func awaitProviderFailureWork() async throws {
        let work = providerFailureWork()
        do {
            try await work.task.value
            if providerFailureInFlight?.id == work.id {
                providerFailureInFlight = nil
                providerFailureCompleted = true
            }
        } catch {
            if providerFailureInFlight?.id == work.id {
                providerFailureInFlight = nil
            }
            throw error
        }
    }

    private func awaitProviderAcceptanceWork()
        async throws -> IOSAcceptedHistoryAcceptanceResolution {
        let work = providerAcceptanceWork()
        do {
            let progress = try await work.task.value
            if providerAcceptanceCompleted,
               let providerAcceptanceResolution {
                return providerAcceptanceResolution
            }
            if providerAcceptanceInFlight?.id == work.id {
                providerAcceptanceInFlight = nil
            }
            switch progress {
            case .pending(let receipt):
                if providerAcceptanceReceipt == nil {
                    providerAcceptanceReceipt = receipt
                }
                return .pendingLocalRecovery
            case .completed(let receipt, let resolution):
                _ = receipt
                providerAcceptanceReceipt = nil
                providerAcceptanceResolution = resolution
                providerAcceptanceCompleted = true
                return resolution
            }
        } catch {
            if providerAcceptanceInFlight?.id == work.id {
                providerAcceptanceInFlight = nil
            }
            throw error
        }
    }

    private func providerAcceptanceWork() -> AcceptanceInFlight {
        if let providerAcceptanceInFlight {
            return providerAcceptanceInFlight
        }
        let id = UUID()
        let retainedReceipt = providerAcceptanceReceipt
        let task = Task.detached { [self] in
            try await performProviderAcceptance(
                retainedReceipt: retainedReceipt
            )
        }
        let work = AcceptanceInFlight(id: id, task: task)
        providerAcceptanceInFlight = work
        return work
    }

    private func providerFailureWork() -> InFlight {
        if let providerFailureInFlight {
            return providerFailureInFlight
        }
        let id = UUID()
        let task = Task.detached { [self] in
            try await performProviderFailure()
        }
        let work = InFlight(id: id, task: task)
        providerFailureInFlight = work
        return work
    }

    private func exactProviderCompletionClaim() async throws
        -> IOSFailedHistoryRetryProviderCompletionClaim {
        if let providerFailureClaim {
            return providerFailureClaim
        }
        guard let claim = await retryState.retainedProviderCompletion(
            registration
        ) else {
            throw IOSFailedHistoryError.invalidTransition
        }
        providerFailureClaim = claim
        return claim
    }

    private func exactCancellationClaim() async throws
        -> IOSFailedHistoryRetryProviderCancellationClaim {
        if let cancellationClaim { return cancellationClaim }
        let task: Task<
            IOSFailedHistoryRetryProviderCancellationClaim,
            Error
        >
        if let cancellationClaimTask {
            task = cancellationClaimTask
        } else {
            let retryState = retryState
            let registration = registration
            task = Task.detached {
                guard let terminal = await retryState
                    .claimProviderCancellation(registration),
                      case .cancellation(let claim) = terminal else {
                    throw IOSFailedHistoryError.invalidTransition
                }
                return claim
            }
            cancellationClaimTask = task
        }
        do {
            let claim = try await task.value
            cancellationClaim = claim
            cancellationClaimTask = nil
            return claim
        } catch {
            cancellationClaimTask = nil
            throw error
        }
    }

    private func performProviderAcceptance(
        retainedReceipt: IOSFailedHistoryRetryAcceptingOutputReceipt?
    ) async throws -> AcceptanceProgress {
        guard let transcript = providerAcceptanceTranscript,
              let claim = providerAcceptanceClaim,
              let setup = providerAcceptanceSetup else {
            throw IOSFailedHistoryError.invalidTransition
        }
        let operationGate = operationGate
        let dispatchReceipt = dispatchReceipt
        let retryState = retryState
        let failedStore = failedStore
        let policyStore = policyStore
        let acceptedHistoryStore = acceptedHistoryStore
        let outboxStore = outboxStore
        let deliveryStore = deliveryStore
        let acceptanceState = acceptanceState
        let pendingReplacementState = pendingReplacementState
        let ownerIdentity = ownerIdentity
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration
        let acceptanceCheckpointState =
            providerAcceptanceCheckpointState

        do {
            return try await operationGate.perform { lease in
                let repositoryBinding = repositoryRegistration?.revalidate()
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }

                let policyReceipt = dispatchReceipt.authorization
                    .reservationReceipt.authorization.policyReceipt
                let historyWrite = try IOSAcceptedOutputHistoryWrite(
                    policyGeneration: dispatchReceipt.row.policyGeneration,
                    transcriptionModel:
                        dispatchReceipt.row.transcriptionModel,
                    transcriptionLanguageCode:
                        dispatchReceipt.row.transcriptionLanguageCode,
                    durationMilliseconds:
                        dispatchReceipt.row.durationMilliseconds
                )
                let capture = IOSAcceptedOutputHistoryCapture(
                    policyReceipt: policyReceipt,
                    ownerIdentity: ownerIdentity,
                    historyWrite: historyWrite
                )
                let preparation = try IOSAcceptedOutputDeliveryPreparation(
                    deliveryID: dispatchReceipt.retryOperation.deliveryID,
                    sessionID: dispatchReceipt.retryOperation.sessionID,
                    attemptID: dispatchReceipt.row.attemptID,
                    transcriptID: dispatchReceipt.retryOperation.transcriptID,
                    rawAcceptedText: transcript.text,
                    outputIntent: dispatchReceipt.row.outputIntent,
                    automaticInsertionPreferenceEnabled: false,
                    keepLatestResult: setup.keepLatestResult,
                    historyCapture: capture
                )

                var acceptingReceipt:
                    IOSFailedHistoryRetryAcceptingOutputReceipt?
                var frozenProofForAttempt:
                    IOSAcceptedOutputDeliveryFrozenSlotProof?
                do {
                    let frozenProof: IOSAcceptedOutputDeliveryFrozenSlotProof
                    if let retainedReceipt {
                        frozenProof = try await deliveryStore
                            .refreshFailedRetryFrozenSlotProof(
                                from: retainedReceipt,
                                operationLeaseAuthorization: lease
                            )
                    } else if let retainedProof = acceptanceCheckpointState
                        .loadFrozenProof() {
                        frozenProof = try await deliveryStore
                            .refreshFailedRetryFrozenSlotProof(
                                from: retainedProof,
                                dispatchReceipt: dispatchReceipt,
                                operationLeaseAuthorization: lease
                            )
                    } else {
                        frozenProof = try await deliveryStore
                            .freezeFailedRetrySlot(
                                preparation: preparation,
                                dispatchReceipt: dispatchReceipt,
                                operationLeaseAuthorization: lease
                            )
                    }
                    frozenProofForAttempt = frozenProof
                    acceptanceCheckpointState.storeFrozenProof(frozenProof)
                    if let retainedReceipt,
                       let refreshed = try await failedStore
                        .refreshRetryAcceptingOutputReceiptForRetainedSuccess(
                            from: retainedReceipt,
                            frozenSlotProof: frozenProof,
                            operationLeaseAuthorization: lease
                        ) {
                        acceptingReceipt = refreshed
                    } else {
                        acceptingReceipt = try await
                            IOSAcceptedHistoryCoordinator
                                .commitExactRetryAcceptingOutput(
                                    dispatchReceipt: dispatchReceipt,
                                    providerCompletionClaim: claim,
                                    frozenSlotProof: frozenProof,
                                    failedStore: failedStore,
                                    operationLeaseAuthorization: lease
                                )
                    }

                    guard let acceptingReceipt else {
                        throw IOSFailedHistoryError.invalidTransition
                    }
                    let acceptance = try await IOSAcceptedHistoryCoordinator
                        .acceptFailedRetryWithinLease(
                            preparation: preparation,
                            acceptingOutputReceipt: acceptingReceipt,
                            policyStore: policyStore,
                            acceptedHistoryStore: acceptedHistoryStore,
                            outboxStore: outboxStore,
                            deliveryStore: deliveryStore,
                            acceptanceState: acceptanceState,
                            pendingReplacementState:
                                pendingReplacementState,
                            operationLeaseAuthorization: lease,
                            ownerIdentity: ownerIdentity
                        )
                    guard acceptance.resolution
                            != .pendingLocalRecovery else {
                        return .pending(acceptingReceipt)
                    }
                    let terminalProof = try await deliveryStore
                        .confirmFailedRetryTerminalDelivery(
                            acceptingOutputReceipt: acceptingReceipt,
                            operationLeaseAuthorization: lease
                        )
                    if let repositoryBinding {
                        _ = repositoryRegistration?.revalidate(
                            expectedBinding: repositoryBinding
                        )
                    }
                    guard !repositoryIdentityState.isConflicted else {
                        return .pending(acceptingReceipt)
                    }
                    let successReceipt = try await
                        IOSAcceptedHistoryCoordinator.commitExactRetrySuccess(
                            acceptingOutputReceipt: acceptingReceipt,
                            terminalDeliveryProof: terminalProof,
                            failedStore: failedStore,
                            operationLeaseAuthorization: lease
                        )
                    guard await retryState.consumeProviderSuccess(
                        using: successReceipt
                    ) else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                    acceptanceCheckpointState.clear()
                    return .completed(
                        successReceipt,
                        acceptance.resolution
                    )
                } catch {
                    if let acceptingReceipt {
                        return .pending(acceptingReceipt)
                    }
                    if let frozenProofForAttempt {
                        _ = try? await deliveryStore
                            .releaseFailedRetryFrozenSlotReservation(
                                frozenProofForAttempt,
                                dispatchReceipt: dispatchReceipt,
                                operationLeaseAuthorization: lease
                            )
                    }
                    if !failedStore.mutationInterlock
                        .hasRetryDeliveryProtection {
                        acceptanceCheckpointState.clear()
                    }
                    throw error
                }
            }
        } catch IOSPersistenceOperationGate.AcquisitionError
            .cancelledBeforeLease {
            throw IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError
            .reentrantOperation {
            throw IOSAcceptedHistoryCoordinatorError.reentrantOperation
        }
    }

    private func performCancellation() async throws {
        let claim = try await exactCancellationClaim()

        // The terminal claim has already retired provider authority. Releasing
        // descriptor access and draining a registered task happen before the
        // durable row becomes retryable again.
        invalidateProviderAudio()
        if let providerDrain {
            await providerDrain()
        }

        let operationGate = operationGate
        let dispatchReceipt = dispatchReceipt
        let retryState = retryState
        let failedStore = failedStore
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration
        do {
            try await operationGate.perform { lease in
                let repositoryBinding = repositoryRegistration?.revalidate()
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                let receipt = try await IOSAcceptedHistoryCoordinator
                    .commitExactRetryCancellation(
                        dispatchReceipt: dispatchReceipt,
                        providerCancellationClaim: claim,
                        failedStore: failedStore,
                        operationLeaseAuthorization: lease
                    )
                guard await retryState.consumeProviderCancellation(
                    using: receipt
                ) else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                if let repositoryBinding {
                    _ = repositoryRegistration?.revalidate(
                        expectedBinding: repositoryBinding
                    )
                }
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
            }
        } catch IOSPersistenceOperationGate.AcquisitionError
            .cancelledBeforeLease {
            throw IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError
            .reentrantOperation {
            throw IOSAcceptedHistoryCoordinatorError.reentrantOperation
        }
    }

    private func performProviderFailure() async throws {
        let claim = try await exactProviderCompletionClaim()
        guard let disposition = providerFailureDisposition else {
            throw IOSFailedHistoryError.invalidTransition
        }

        let operationGate = operationGate
        let dispatchReceipt = dispatchReceipt
        let retryState = retryState
        let failedStore = failedStore
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration
        do {
            try await operationGate.perform { lease in
                let repositoryBinding = repositoryRegistration?.revalidate()
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                let receipt = try await IOSAcceptedHistoryCoordinator
                    .commitExactRetryFailure(
                        dispatchReceipt: dispatchReceipt,
                        providerCompletionClaim: claim,
                        disposition: disposition,
                        failedStore: failedStore,
                        operationLeaseAuthorization: lease
                    )
                guard await retryState.consumeProviderFailure(
                    using: receipt
                ) else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                if let repositoryBinding {
                    _ = repositoryRegistration?.revalidate(
                        expectedBinding: repositoryBinding
                    )
                }
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
            }
        } catch IOSPersistenceOperationGate.AcquisitionError
            .cancelledBeforeLease {
            throw IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError
            .reentrantOperation {
            throw IOSAcceptedHistoryCoordinatorError.reentrantOperation
        }
    }

    private func invalidateProviderAudio() {
        let invalidations = audioInvalidations
        audioInvalidations.removeAll()
        for invalidate in invalidations {
            invalidate()
        }
    }
}

extension IOSAcceptedHistoryCoordinator {
    /// Reserves exactly one ready failed row, validates and holds its descriptor,
    /// durably publishes provider dispatch, and registers the matching stable
    /// live owner before the root gate is released.
    func prepareFailedHistoryRetry(
        attemptID: UUID,
        setup: IOSFailedHistoryRetrySetupSnapshot
    ) async throws -> IOSFailedHistoryRetryHandoff {
        guard let pendingRecordingStore else {
            throw IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        }
        let policyStore = policyStore
        let acceptedHistoryStore = acceptedHistoryStore
        let failedStore = failedHistoryStore
        let outboxStore = outboxStore
        let retryState = failedHistoryRetryState
        let operationGate = operationGate
        let baselineRecoveryState = baselineRecoveryState
        let acceptanceState = acceptanceState
        let pendingReplacementState = pendingReplacementState
        let outboxWorkerState = outboxWorkerState
        let policyCutoverState = policyCutoverState
        let failedTransferState = failedHistoryTransferState
        let failedAudioCleanupState = failedHistoryAudioCleanupState
        let failedMutationInterlock = failedHistoryMutationInterlock
        let deliveryStore = deliveryStore
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration
        let ownerIdentity = ownerIdentity
        let transcriptionConfiguration = setup.transcriptionConfiguration

        // A previous provider completion may have exhausted its bounded local
        // Store attempts after the exact terminal claim was already retained.
        // Retrigger only that terminal work; provider work is never repeated.
        if await retryState.requestRetainedProviderCompletionRecovery() {
            throw IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        }

        // A previous handoff may have exhausted its bounded immediate cleanup
        // attempts after already minting the exact terminal cancellation claim.
        // Retrigger only that terminal work here; an active provider whose
        // cancellation has not begun remains untouched and is rejected below.
        if await retryState.requestRetainedProviderCancellation() {
            throw IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        }

        let handoff: IOSFailedHistoryRetryHandoff
        do {
            handoff = try await operationGate.perform { lease in
                let repositoryBinding = repositoryRegistration?.revalidate()
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                do {
                    guard await baselineRecoveryState.value() == false,
                          await acceptanceState.current() == nil,
                          await pendingReplacementState.current() == nil,
                          await outboxWorkerState.current() == nil,
                          await policyCutoverState.current() == nil,
                          await failedTransferState.current() == nil,
                          await failedAudioCleanupState.current() == nil,
                          await retryState.hasLiveOwner() == false,
                          await retryState.hasCancellationReservation()
                            == false,
                          !failedMutationInterlock.isBlocked,
                          await deliveryStore
                            .hasUncertainAcceptanceForHistoryCoordinator()
                            == false,
                          await deliveryStore
                            .hasRetainedHistoryWorkForPolicyCutover()
                            == false else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                    guard try await outboxStore.observeHead() == nil else {
                        // A durable predecessor transfer must be reconciled
                        // before provider dispatch. Once Retry owns the failed
                        // relation, the ordinary outbox worker is deliberately
                        // excluded and could no longer drain this head.
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }

                    guard let currentPolicy = try await policyStore.load(),
                          currentPolicy.historyEnabled else {
                        throw IOSFailedHistoryError.stalePolicyGeneration
                    }
                    let policyReceipt = try await policyStore.confirm(
                        expected: IOSHistoryPolicyExpectation(
                            state: currentPolicy
                        )
                    )
                    guard policyReceipt.state == currentPolicy,
                          policyReceipt.state.historyEnabled else {
                        throw IOSFailedHistoryError.stalePolicyGeneration
                    }

                    let initialPreparation = try await failedStore
                        .prepareRetryReservation(
                            attemptID: attemptID,
                            transcriptionConfiguration:
                                transcriptionConfiguration,
                            using: policyReceipt,
                            operationLeaseAuthorization: lease
                        )
                    guard case .commit(let reservationAuthorization) =
                            initialPreparation else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                    guard setup.supports(
                        reservationAuthorization.candidate.outputIntent
                    ) else {
                        throw IOSFailedHistoryError.invalidTransition
                    }

                    let audioSource = try await pendingRecordingStore
                        .acquireValidatedFailedHistoryRetryAudio(
                            using: reservationAuthorization,
                            operationLeaseAuthorization: lease
                        )
                    let reservationReceipt = try await Self
                        .commitExactRetryReservation(
                            initialAuthorization: reservationAuthorization,
                            audioSource: audioSource,
                            attemptID: attemptID,
                            transcriptionConfiguration:
                                transcriptionConfiguration,
                            policyReceipt: policyReceipt,
                            failedStore: failedStore,
                            operationLeaseAuthorization: lease
                        )

                    let initialDispatch:
                        IOSFailedHistoryRetryDispatchPreparation
                    do {
                        initialDispatch = try await failedStore
                            .prepareRetryDispatch(
                                using: reservationReceipt,
                                operationLeaseAuthorization: lease
                            )
                    } catch {
                        let dispatchPreparationError = error
                        guard !failedMutationInterlock.isBlocked else {
                            throw dispatchPreparationError
                        }
                        do {
                            _ = try await Self.cancelExactRetryReservation(
                                reservationReceipt: reservationReceipt,
                                failedStore: failedStore,
                                operationLeaseAuthorization: lease
                            )
                        } catch {
                            throw IOSAcceptedHistoryCoordinatorError
                                .localRecoveryPending
                        }
                        throw dispatchPreparationError
                    }
                    guard case .commit(let dispatchAuthorization) =
                            initialDispatch else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }

                    let dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt
                    do {
                        dispatchReceipt = try await Self
                            .commitExactRetryDispatch(
                                initialAuthorization: dispatchAuthorization,
                                reservationReceipt: reservationReceipt,
                                failedStore: failedStore,
                                operationLeaseAuthorization: lease
                            )
                    } catch {
                        let dispatchCommitError = error
                        // A dispatch uncertainty may already be durable and must
                        // be recovered as that exact operation. Only a definite
                        // pre-dispatch failure may return the row to retryable.
                        if !failedMutationInterlock.isBlocked {
                            do {
                                _ = try await Self
                                    .cancelExactRetryReservation(
                                        reservationReceipt:
                                            reservationReceipt,
                                        failedStore: failedStore,
                                        operationLeaseAuthorization: lease
                                    )
                            } catch {
                                throw IOSAcceptedHistoryCoordinatorError
                                    .localRecoveryPending
                            }
                        }
                        throw dispatchCommitError
                    }

                    if let repositoryBinding {
                        _ = repositoryRegistration?.revalidate(
                            expectedBinding: repositoryBinding
                        )
                    }
                    guard !repositoryIdentityState.isConflicted,
                          let registration = await retryState
                            .registerLiveOwner(
                                dispatchReceipt.liveOwnerToken
                            ) else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .repositoryIdentityConflict
                    }
                    let relay = IOSFailedHistoryRetryCancellationRelay(
                        dispatchReceipt: dispatchReceipt,
                        registration: registration,
                        retryState: retryState,
                        operationGate: operationGate,
                        failedStore: failedStore,
                        policyStore: policyStore,
                        acceptedHistoryStore: acceptedHistoryStore,
                        outboxStore: outboxStore,
                        deliveryStore: deliveryStore,
                        acceptanceState: acceptanceState,
                        pendingReplacementState: pendingReplacementState,
                        ownerIdentity: ownerIdentity,
                        repositoryIdentityState: repositoryIdentityState,
                        repositoryRegistration: repositoryRegistration,
                        audioInvalidation: { audioSource.invalidate() }
                    )
                    guard await retryState.retainProviderTerminalOwner(
                        relay,
                        for: registration
                    ) else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }

                    let audio: IOSPendingTranscriptionAudio
                    do {
                        audio = try audioSource.take(
                            using: dispatchReceipt,
                            registration: registration
                        )
                    } catch {
                        let audioTransferError = error
                        audioSource.invalidate()
                        guard let terminal = await retryState
                            .claimProviderCancellation(registration),
                              case .cancellation(let claim) = terminal else {
                            throw IOSAcceptedHistoryCoordinatorError
                                .localRecoveryPending
                        }
                        do {
                            let receipt = try await Self
                                .commitExactRetryCancellation(
                                dispatchReceipt: dispatchReceipt,
                                providerCancellationClaim: claim,
                                failedStore: failedStore,
                                operationLeaseAuthorization: lease
                            )
                            guard await retryState
                                .consumeProviderCancellation(using: receipt)
                            else {
                                throw IOSAcceptedHistoryCoordinatorError
                                    .localRecoveryPending
                            }
                        } catch {
                            relay.requestCancellation()
                            throw error
                        }
                        throw audioTransferError
                    }
                    await relay.registerProviderAudio(audio)
                    return IOSFailedHistoryRetryHandoff(
                        audio: audio,
                        dispatchReceipt: dispatchReceipt,
                        registration: registration,
                        retryState: retryState,
                        setup: setup,
                        cancellationRelay: relay
                    )
                } catch {
                    if let repositoryBinding {
                        _ = repositoryRegistration?.revalidate(
                            expectedBinding: repositoryBinding
                        )
                    }
                    if repositoryIdentityState.isConflicted {
                        throw IOSAcceptedHistoryCoordinatorError
                            .repositoryIdentityConflict
                    }
                    throw error
                }
            }
        } catch IOSPersistenceOperationGate.AcquisitionError
            .cancelledBeforeLease {
            throw IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError
            .reentrantOperation {
            throw IOSAcceptedHistoryCoordinatorError.reentrantOperation
        }

        if Task.isCancelled {
            try await handoff.cancel()
            throw CancellationError()
        }
        return handoff
    }

    fileprivate static func commitExactRetryReservation(
        initialAuthorization:
            IOSFailedHistoryRetryReservationAuthorization,
        audioSource: IOSFailedHistoryRetryAudioSource,
        attemptID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration,
        policyReceipt: IOSHistoryPolicyReceipt,
        failedStore: IOSFailedHistoryStore,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryRetryReservationReceipt {
        do {
            return try await failedStore.commitRetryReservation(
                using: initialAuthorization,
                validatedAudio: audioSource.validationReceipt
            )
        } catch IOSFailedHistoryError.commitUncertain {
            let retained = try await failedStore.prepareRetryReservation(
                attemptID: attemptID,
                transcriptionConfiguration: transcriptionConfiguration,
                using: policyReceipt,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
            switch retained {
            case .completed(let receipt):
                return receipt
            case .commit(let authorization):
                guard authorization.identifiesSameReservation(
                    as: initialAuthorization
                ) else {
                    throw IOSFailedHistoryError.commitUncertain
                }
                return try await failedStore.commitRetryReservation(
                    using: authorization,
                    validatedAudio: audioSource.validationReceipt
                )
            }
        }
    }

    fileprivate static func commitExactRetryDispatch(
        initialAuthorization: IOSFailedHistoryRetryDispatchAuthorization,
        reservationReceipt: IOSFailedHistoryRetryReservationReceipt,
        failedStore: IOSFailedHistoryStore,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryRetryDispatchReceipt {
        do {
            return try await failedStore.commitRetryDispatch(
                using: initialAuthorization
            )
        } catch IOSFailedHistoryError.commitUncertain {
            let retained = try await failedStore.prepareRetryDispatch(
                using: reservationReceipt,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
            switch retained {
            case .completed(let receipt):
                return receipt
            case .commit(let authorization):
                guard authorization.identifiesSameDispatch(
                    as: initialAuthorization
                ) else {
                    throw IOSFailedHistoryError.commitUncertain
                }
                return try await failedStore.commitRetryDispatch(
                    using: authorization
                )
            }
        }
    }

    @discardableResult
    fileprivate static func cancelExactRetryReservation(
        reservationReceipt: IOSFailedHistoryRetryReservationReceipt,
        failedStore: IOSFailedHistoryStore,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryRetryCancellationReceipt {
        let preparation = try await failedStore.prepareRetryCancellation(
            using: reservationReceipt,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        switch preparation {
        case .completed(let receipt):
            return receipt
        case .commit(let authorization):
            do {
                return try await failedStore.commitRetryCancellation(
                    using: authorization
                )
            } catch IOSFailedHistoryError.commitUncertain {
                let retained = try await failedStore
                    .prepareRetryCancellation(
                        using: reservationReceipt,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                switch retained {
                case .completed(let receipt):
                    return receipt
                case .commit(let refreshed):
                    guard refreshed.identifiesSameCancellation(
                        as: authorization
                    ) else {
                        throw IOSFailedHistoryError.commitUncertain
                    }
                    return try await failedStore.commitRetryCancellation(
                        using: refreshed
                    )
                }
            }
        }
    }

    fileprivate static func commitExactRetryCancellation(
        dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        providerCancellationClaim:
            IOSFailedHistoryRetryProviderCancellationClaim,
        failedStore: IOSFailedHistoryStore,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryRetryCancellationReceipt {
        let preparation = try await failedStore.prepareRetryCancellation(
            using: dispatchReceipt,
            providerCancellationClaim: providerCancellationClaim,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        switch preparation {
        case .completed(let receipt):
            return receipt
        case .commit(let authorization):
            do {
                return try await failedStore.commitRetryCancellation(
                    using: authorization
                )
            } catch IOSFailedHistoryError.commitUncertain {
                let retained = try await failedStore
                    .prepareRetryCancellation(
                        using: dispatchReceipt,
                        providerCancellationClaim:
                            providerCancellationClaim,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                switch retained {
                case .completed(let receipt):
                    return receipt
                case .commit(let refreshed):
                    guard refreshed.identifiesSameCancellation(
                        as: authorization
                    ) else {
                        throw IOSFailedHistoryError.commitUncertain
                    }
                    return try await failedStore.commitRetryCancellation(
                        using: refreshed
                    )
                }
            }
        }
    }

    fileprivate static func commitExactRetryFailure(
        dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        providerCompletionClaim:
            IOSFailedHistoryRetryProviderCompletionClaim,
        disposition: IOSFailedHistoryRetryFailureDisposition,
        failedStore: IOSFailedHistoryStore,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryRetryFailureReceipt {
        let preparation = try await failedStore.prepareRetryFailure(
            using: dispatchReceipt,
            providerCompletionClaim: providerCompletionClaim,
            disposition: disposition,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        switch preparation {
        case .completed(let receipt):
            return receipt
        case .commit(let authorization):
            do {
                return try await failedStore.commitRetryFailure(
                    using: authorization
                )
            } catch IOSFailedHistoryError.commitUncertain {
                let retained = try await failedStore.prepareRetryFailure(
                    using: dispatchReceipt,
                    providerCompletionClaim: providerCompletionClaim,
                    disposition: disposition,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
                switch retained {
                case .completed(let receipt):
                    return receipt
                case .commit(let refreshed):
                    guard refreshed.identifiesSameFailure(
                        as: authorization
                    ) else {
                        throw IOSFailedHistoryError.commitUncertain
                    }
                    return try await failedStore.commitRetryFailure(
                        using: refreshed
                    )
                }
            }
        }
    }

    fileprivate static func commitExactRetryAcceptingOutput(
        dispatchReceipt: IOSFailedHistoryRetryDispatchReceipt,
        providerCompletionClaim:
            IOSFailedHistoryRetryProviderCompletionClaim,
        frozenSlotProof: IOSAcceptedOutputDeliveryFrozenSlotProof,
        failedStore: IOSFailedHistoryStore,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryRetryAcceptingOutputReceipt {
        let preparation = try await failedStore.prepareRetryAcceptingOutput(
            using: dispatchReceipt,
            providerCompletionClaim: providerCompletionClaim,
            frozenSlotProof: frozenSlotProof,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        switch preparation {
        case .completed(let receipt):
            return receipt
        case .commit(let authorization):
            do {
                return try await failedStore.commitRetryAcceptingOutput(
                    using: authorization
                )
            } catch IOSFailedHistoryError.commitUncertain {
                let retained = try await failedStore
                    .prepareRetryAcceptingOutput(
                        using: dispatchReceipt,
                        providerCompletionClaim: providerCompletionClaim,
                        frozenSlotProof: frozenSlotProof,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                switch retained {
                case .completed(let receipt):
                    return receipt
                case .commit(let refreshed):
                    guard refreshed.identifiesSameAcceptance(
                        as: authorization
                    ) else {
                        throw IOSFailedHistoryError.commitUncertain
                    }
                    return try await failedStore.commitRetryAcceptingOutput(
                        using: refreshed
                    )
                }
            }
        }
    }

    fileprivate static func commitExactRetrySuccess(
        acceptingOutputReceipt:
            IOSFailedHistoryRetryAcceptingOutputReceipt,
        terminalDeliveryProof: IOSFailedHistoryRetryTerminalDeliveryProof,
        failedStore: IOSFailedHistoryStore,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryRetrySuccessReceipt {
        let preparation = try await failedStore.prepareRetrySuccess(
            using: acceptingOutputReceipt,
            terminalDeliveryProof: terminalDeliveryProof,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        switch preparation {
        case .completed(let receipt):
            return receipt
        case .commit(let authorization):
            do {
                return try await failedStore.commitRetrySuccess(
                    using: authorization
                )
            } catch IOSFailedHistoryError.commitUncertain {
                let retained = try await failedStore.prepareRetrySuccess(
                    using: acceptingOutputReceipt,
                    terminalDeliveryProof: terminalDeliveryProof,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
                switch retained {
                case .completed(let receipt):
                    return receipt
                case .commit(let refreshed):
                    guard refreshed.identifiesSameSuccess(
                        as: authorization
                    ) else {
                        throw IOSFailedHistoryError.commitUncertain
                    }
                    return try await failedStore.commitRetrySuccess(
                        using: refreshed
                    )
                }
            }
        }
    }
}
