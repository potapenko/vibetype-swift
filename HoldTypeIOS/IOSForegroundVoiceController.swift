import HoldTypeDomain
import Observation

enum IOSForegroundVoiceSetup: Equatable, Sendable {
    case unknown
    case ready
    case needsSetup(RecoveryDestination)
    case unavailable
}

enum IOSForegroundVoiceFailure: Equatable, Sendable {
    case operationFailed
    case localRecovery
    case unavailable
    case tooShort
    case maximumDuration
}

enum IOSForegroundVoiceRecovery: Equatable, Sendable {
    case none
    case captureRecoverOrDiscard
    case captureRecoverOnly
    case captureDiscardOnly
    case pendingRetryOrDiscard
    case savingResult
    case localCheckpoint(VoiceAttemptStage)
    case blocked
}

enum IOSForegroundVoiceLatestAvailability: Equatable, Sendable {
    case unknown
    case absent
    case available
    case priorAvailableWhileSaving
    case expired
    case clockRollbackAmbiguous
    case cleanupPending
    case unavailable
}

enum IOSForegroundVoiceAction: Equatable, Sendable {
    case startStandard
    case startTranslation
    case cancelStart
    case finishUtterance
    case cancelUtterance
    case cancelProcessing
    case recoverRecording
    case retryPending
    case discard
    case retrySavingResult
    case retryLocalCheckpoint
}

struct IOSForegroundVoiceActionCommand: Equatable, Sendable {
    let action: IOSForegroundVoiceAction

    fileprivate let presentationRevision: UInt64
}

enum IOSForegroundVoiceActionAdmission: Equatable, Sendable {
    case accepted
    case stale
    case unavailable
}

struct IOSForegroundVoicePresentation: Equatable, Sendable {
    let phase: VoiceWorkPhase
    let stage: VoiceAttemptStage?
    let outcome: VoiceAttemptOutcome?
    let setup: IOSForegroundVoiceSetup
    let failure: IOSForegroundVoiceFailure?
    let recovery: IOSForegroundVoiceRecovery
    let availableActions: [IOSForegroundVoiceAction]
    let latestAvailability: IOSForegroundVoiceLatestAvailability

    static let initial = IOSForegroundVoicePresentation(
        phase: .inactive,
        stage: nil,
        outcome: nil,
        setup: .unknown,
        failure: nil,
        recovery: .none,
        availableActions: [],
        latestAvailability: .unknown
    )
}

struct IOSForegroundVoiceObservation: Equatable, Sendable {
    let setup: IOSForegroundVoiceSetup
    let recovery: IOSForegroundVoiceRecovery
    let latestAvailability: IOSForegroundVoiceLatestAvailability
    let translationAvailable: Bool

    init(
        setup: IOSForegroundVoiceSetup,
        recovery: IOSForegroundVoiceRecovery,
        latestAvailability: IOSForegroundVoiceLatestAvailability,
        translationAvailable: Bool = false
    ) {
        self.setup = setup
        self.recovery = recovery
        self.latestAvailability = latestAvailability
        self.translationAvailable = translationAvailable
    }
}

enum IOSForegroundVoiceOperation: Equatable, Sendable {
    case start(DictationOutputIntent)
    case retryPending
    case recoverRecording
    case discard
    case retrySavingResult
    case retryLocalCheckpoint
}

enum IOSForegroundVoiceProgress: Equatable, Sendable {
    case listening
    case finalizing
    case processing(VoiceAttemptStage)
}

struct IOSForegroundVoiceResolution: Equatable, Sendable {
    let observation: IOSForegroundVoiceObservation
    let stage: VoiceAttemptStage?
    let outcome: VoiceAttemptOutcome?
    let failure: IOSForegroundVoiceFailure?

    init(
        observation: IOSForegroundVoiceObservation,
        stage: VoiceAttemptStage? = nil,
        outcome: VoiceAttemptOutcome? = nil,
        failure: IOSForegroundVoiceFailure? = nil
    ) {
        self.observation = observation
        self.stage = stage
        self.outcome = outcome
        self.failure = failure
    }
}

struct IOSForegroundVoiceAuthority: Equatable, Hashable, Sendable {
    fileprivate let value: UInt64
}

enum IOSForegroundVoiceControlDisposition: Equatable, Sendable {
    case accepted
    case unavailable
}

struct IOSForegroundVoiceClient: Sendable {
    typealias Observe = @Sendable () async -> IOSForegroundVoiceObservation
    typealias Progress = @MainActor @Sendable (
        IOSForegroundVoiceProgress
    ) -> Void
    typealias Run = @Sendable (
        IOSForegroundVoiceOperation,
        IOSForegroundVoiceAuthority,
        @escaping Progress
    ) async -> IOSForegroundVoiceResolution
    typealias FinishUtterance = @MainActor @Sendable (
        IOSForegroundVoiceAuthority
    ) -> IOSForegroundVoiceControlDisposition

    let observe: Observe
    let run: Run
    let finishUtterance: FinishUtterance

    init(
        observe: @escaping Observe,
        run: @escaping Run,
        finishUtterance: @escaping FinishUtterance
    ) {
        self.observe = observe
        self.run = run
        self.finishUtterance = finishUtterance
    }
}

@MainActor
@Observable
final class IOSForegroundVoiceController {
    private(set) var presentation = IOSForegroundVoicePresentation.initial

    @ObservationIgnored
    private let client: IOSForegroundVoiceClient
    @ObservationIgnored
    private var activeTask: Task<Void, Never>?
    @ObservationIgnored
    private var activeWork: ActiveWork?
    @ObservationIgnored
    private var activeAuthority: IOSForegroundVoiceAuthority?
    @ObservationIgnored
    private var activeBaselineLatestAvailability:
        IOSForegroundVoiceLatestAvailability?
    @ObservationIgnored
    private var presentationRevision: UInt64 = 0
    @ObservationIgnored
    private var nextAuthorityValue: UInt64 = 0
    @ObservationIgnored
    private var cancellationRequested = false
    @ObservationIgnored
    private var finishRequested = false

    init(client: IOSForegroundVoiceClient) {
        self.client = client
    }

    deinit {
        activeTask?.cancel()
    }

    var actionCommands: [IOSForegroundVoiceActionCommand] {
        presentation.availableActions.map {
            IOSForegroundVoiceActionCommand(
                action: $0,
                presentationRevision: presentationRevision
            )
        }
    }

    func activate() async {
        if case .activation? = activeWork {
            await activeTask?.value
            return
        }
        guard activeWork == nil else { return }

        let serial = nextSerial()
        activeWork = .activation(serial)
        publish(
            phase: presentation.phase,
            stage: presentation.stage,
            outcome: presentation.outcome,
            setup: presentation.setup,
            failure: nil,
            recovery: presentation.recovery,
            latestAvailability: presentation.latestAvailability
        )

        let client = client
        let task = Task { @MainActor [weak self] in
            let observation = await client.observe()
            guard let self,
                  self.activeWork == .activation(serial) else {
                return
            }
            self.activeTask = nil
            self.activeWork = nil
            self.apply(
                observation,
                stage: nil,
                outcome: nil,
                failure: nil
            )
        }
        activeTask = task
        await task.value
    }

    @discardableResult
    func submit(
        _ command: IOSForegroundVoiceActionCommand
    ) -> IOSForegroundVoiceActionAdmission {
        guard command.presentationRevision == presentationRevision else {
            return .stale
        }
        guard presentation.availableActions.contains(command.action) else {
            return .unavailable
        }

        switch command.action {
        case .startStandard:
            begin(.start(.standard))
        case .startTranslation:
            begin(.start(.translate))
        case .retryPending:
            begin(.retryPending)
        case .recoverRecording:
            begin(.recoverRecording)
        case .discard:
            begin(.discard)
        case .retrySavingResult:
            begin(.retrySavingResult)
        case .retryLocalCheckpoint:
            begin(.retryLocalCheckpoint)
        case .finishUtterance:
            finishCurrentUtterance()
        case .cancelStart, .cancelUtterance, .cancelProcessing:
            cancelCurrentOperation()
        }
        return .accepted
    }

    private func begin(_ operation: IOSForegroundVoiceOperation) {
        guard activeWork == nil else { return }

        let authority = IOSForegroundVoiceAuthority(value: nextSerial())
        activeAuthority = authority
        activeBaselineLatestAvailability = presentation.latestAvailability
        activeWork = .primary(authority)
        cancellationRequested = false
        finishRequested = false

        let initial = initialPresentation(for: operation)
        publish(
            phase: initial.phase,
            stage: initial.stage,
            outcome: nil,
            setup: presentation.setup,
            failure: nil,
            recovery: .none,
            latestAvailability: presentation.latestAvailability
        )

        let client = client
        let progress: IOSForegroundVoiceClient.Progress = {
            [weak self] progress in
            self?.receive(progress, authority: authority)
        }
        activeTask = Task { @MainActor [weak self] in
            let resolution = await client.run(
                operation,
                authority,
                progress
            )
            self?.complete(resolution, authority: authority)
        }
    }

    private func finishCurrentUtterance() {
        guard presentation.phase == .listening,
              !finishRequested,
              let authority = activeAuthority else {
            return
        }
        finishRequested = true
        let disposition = client.finishUtterance(authority)
        let failure: IOSForegroundVoiceFailure?
        switch disposition {
        case .accepted:
            failure = nil
        case .unavailable:
            finishRequested = false
            failure = .operationFailed
        }
        publish(
            phase: presentation.phase,
            stage: presentation.stage,
            outcome: presentation.outcome,
            setup: presentation.setup,
            failure: failure,
            recovery: presentation.recovery,
            latestAvailability: presentation.latestAvailability
        )
    }

    private func cancelCurrentOperation() {
        guard !cancellationRequested,
              case .primary? = activeWork else {
            return
        }
        cancellationRequested = true
        publish(
            phase: presentation.phase,
            stage: presentation.stage,
            outcome: presentation.outcome,
            setup: presentation.setup,
            failure: presentation.failure,
            recovery: presentation.recovery,
            latestAvailability: presentation.latestAvailability
        )
        activeTask?.cancel()
    }

    private func receive(
        _ progress: IOSForegroundVoiceProgress,
        authority: IOSForegroundVoiceAuthority
    ) {
        guard activeWork == .primary(authority),
              activeAuthority == authority,
              !cancellationRequested else {
            return
        }

        let phase: VoiceWorkPhase
        let stage: VoiceAttemptStage?
        switch progress {
        case .listening:
            phase = .listening
            stage = nil
        case .finalizing:
            phase = .finalizing
            stage = .recordingFinalization
        case .processing(let reportedStage):
            phase = .processing
            stage = reportedStage
        }
        publish(
            phase: phase,
            stage: stage,
            outcome: presentation.outcome,
            setup: presentation.setup,
            failure: nil,
            recovery: presentation.recovery,
            latestAvailability: presentation.latestAvailability
        )
    }

    private func complete(
        _ resolution: IOSForegroundVoiceResolution,
        authority: IOSForegroundVoiceAuthority
    ) {
        guard activeWork == .primary(authority),
              activeAuthority == authority else {
            return
        }
        let wasCancelled = cancellationRequested
        let observation: IOSForegroundVoiceObservation
        let outcome: VoiceAttemptOutcome?
        let failure: IOSForegroundVoiceFailure?
        if wasCancelled, resolution.outcome == .resultReady {
            observation = IOSForegroundVoiceObservation(
                setup: presentation.setup,
                recovery: .blocked,
                latestAvailability:
                    activeBaselineLatestAvailability
                    ?? presentation.latestAvailability,
                translationAvailable: false
            )
            outcome = nil
            failure = .localRecovery
        } else {
            observation = resolution.observation
            outcome = resolution.outcome
            failure = resolution.failure
        }
        activeTask = nil
        activeWork = nil
        activeAuthority = nil
        activeBaselineLatestAvailability = nil
        cancellationRequested = false
        finishRequested = false
        apply(
            observation,
            stage: resolution.stage,
            outcome: outcome,
            failure: failure
        )
    }

    private func apply(
        _ observation: IOSForegroundVoiceObservation,
        stage: VoiceAttemptStage?,
        outcome: VoiceAttemptOutcome?,
        failure: IOSForegroundVoiceFailure?
    ) {
        publish(
            phase: .inactive,
            stage: terminalStage(
                for: observation.recovery,
                reportedStage: stage,
                outcome: outcome
            ),
            outcome: outcome,
            setup: observation.setup,
            failure: failure,
            recovery: observation.recovery,
            latestAvailability: observation.latestAvailability,
            translationAvailable: observation.translationAvailable
        )
    }

    private func publish(
        phase: VoiceWorkPhase,
        stage: VoiceAttemptStage?,
        outcome: VoiceAttemptOutcome?,
        setup: IOSForegroundVoiceSetup,
        failure: IOSForegroundVoiceFailure?,
        recovery: IOSForegroundVoiceRecovery,
        latestAvailability: IOSForegroundVoiceLatestAvailability,
        translationAvailable: Bool? = nil
    ) {
        presentationRevision &+= 1
        let translationAvailable = translationAvailable
            ?? presentation.availableActions.contains(.startTranslation)
        let availableActions = availableActions(
            phase: phase,
            stage: stage,
            setup: setup,
            recovery: recovery,
            latestAvailability: latestAvailability,
            translationAvailable: translationAvailable
        )
        presentation = IOSForegroundVoicePresentation(
            phase: phase,
            stage: stage,
            outcome: outcome,
            setup: setup,
            failure: failure,
            recovery: recovery,
            availableActions: availableActions,
            latestAvailability: latestAvailability
        )
    }

    private func availableActions(
        phase: VoiceWorkPhase,
        stage: VoiceAttemptStage?,
        setup: IOSForegroundVoiceSetup,
        recovery: IOSForegroundVoiceRecovery,
        latestAvailability: IOSForegroundVoiceLatestAvailability,
        translationAvailable: Bool
    ) -> [IOSForegroundVoiceAction] {
        if case .activation? = activeWork { return [] }
        if cancellationRequested { return [] }
        if case .primary? = activeWork {
            switch phase {
            case .arming:
                return [.cancelStart]
            case .listening:
                return finishRequested
                    ? [.cancelUtterance]
                    : [.finishUtterance, .cancelUtterance]
            case .processing:
                guard stage == .transcription
                        || stage == .postProcessing else {
                    return []
                }
                return [.cancelProcessing]
            case .inactive, .ready, .finalizing:
                return []
            }
        }

        switch recovery {
        case .captureRecoverOrDiscard:
            return [.recoverRecording, .discard]
        case .captureRecoverOnly:
            return [.recoverRecording]
        case .captureDiscardOnly:
            return [.discard]
        case .pendingRetryOrDiscard:
            return [.retryPending, .discard]
        case .savingResult:
            return [.retrySavingResult]
        case .localCheckpoint:
            return [.retryLocalCheckpoint]
        case .blocked:
            return []
        case .none:
            guard setup == .ready else { return [] }
            var actions: [IOSForegroundVoiceAction] = [.startStandard]
            if translationAvailable {
                actions.append(.startTranslation)
            }
            return actions
        }
    }

    private func initialPresentation(
        for operation: IOSForegroundVoiceOperation
    ) -> (phase: VoiceWorkPhase, stage: VoiceAttemptStage?) {
        switch operation {
        case .start:
            (.arming, nil)
        case .retryPending:
            (.processing, nil)
        case .recoverRecording, .discard:
            (.finalizing, .recordingFinalization)
        case .retrySavingResult:
            (.processing, .outputDelivery)
        case .retryLocalCheckpoint:
            (.processing, nil)
        }
    }

    private func terminalStage(
        for recovery: IOSForegroundVoiceRecovery,
        reportedStage: VoiceAttemptStage?,
        outcome: VoiceAttemptOutcome?
    ) -> VoiceAttemptStage? {
        guard outcome != .resultReady,
              recovery != .blocked else {
            return nil
        }

        switch recovery {
        case .captureRecoverOrDiscard,
             .captureRecoverOnly,
             .captureDiscardOnly,
             .pendingRetryOrDiscard:
            return reportedStage
        case .savingResult:
            return .outputDelivery
        case .localCheckpoint(let stage):
            return stage
        case .none, .blocked:
            return nil
        }
    }

    private func nextSerial() -> UInt64 {
        nextAuthorityValue &+= 1
        return nextAuthorityValue
    }

    private enum ActiveWork: Equatable {
        case activation(UInt64)
        case primary(IOSForegroundVoiceAuthority)
    }
}

extension IOSForegroundVoiceController:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSForegroundVoiceController(<redacted>)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

protocol IOSForegroundVoiceRedactedValue:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {}

extension IOSForegroundVoiceRedactedValue {
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceSetup: IOSForegroundVoiceRedactedValue {
    var description: String { "IOSForegroundVoiceSetup(<redacted>)" }
}

extension IOSForegroundVoiceFailure: IOSForegroundVoiceRedactedValue {
    var description: String { "IOSForegroundVoiceFailure(<redacted>)" }
}

extension IOSForegroundVoiceRecovery: IOSForegroundVoiceRedactedValue {
    var description: String { "IOSForegroundVoiceRecovery(<redacted>)" }
}

extension IOSForegroundVoiceLatestAvailability:
    IOSForegroundVoiceRedactedValue {
    var description: String {
        "IOSForegroundVoiceLatestAvailability(<redacted>)"
    }
}

extension IOSForegroundVoiceAction: IOSForegroundVoiceRedactedValue {
    var description: String { "IOSForegroundVoiceAction(<redacted>)" }
}

extension IOSForegroundVoiceActionCommand: IOSForegroundVoiceRedactedValue {
    var description: String {
        "IOSForegroundVoiceActionCommand(<redacted>)"
    }
}

extension IOSForegroundVoiceActionAdmission:
    IOSForegroundVoiceRedactedValue {
    var description: String {
        "IOSForegroundVoiceActionAdmission(<redacted>)"
    }
}

extension IOSForegroundVoicePresentation: IOSForegroundVoiceRedactedValue {
    var description: String {
        "IOSForegroundVoicePresentation(<redacted>)"
    }
}

extension IOSForegroundVoiceObservation: IOSForegroundVoiceRedactedValue {
    var description: String {
        "IOSForegroundVoiceObservation(<redacted>)"
    }
}

extension IOSForegroundVoiceOperation: IOSForegroundVoiceRedactedValue {
    var description: String {
        "IOSForegroundVoiceOperation(<redacted>)"
    }
}

extension IOSForegroundVoiceProgress: IOSForegroundVoiceRedactedValue {
    var description: String { "IOSForegroundVoiceProgress(<redacted>)" }
}

extension IOSForegroundVoiceResolution: IOSForegroundVoiceRedactedValue {
    var description: String {
        "IOSForegroundVoiceResolution(<redacted>)"
    }
}

extension IOSForegroundVoiceAuthority: IOSForegroundVoiceRedactedValue {
    var description: String { "IOSForegroundVoiceAuthority(<redacted>)" }
}

extension IOSForegroundVoiceControlDisposition:
    IOSForegroundVoiceRedactedValue {
    var description: String {
        "IOSForegroundVoiceControlDisposition(<redacted>)"
    }
}

extension IOSForegroundVoiceClient: IOSForegroundVoiceRedactedValue {
    var description: String { "IOSForegroundVoiceClient(<redacted>)" }
}
