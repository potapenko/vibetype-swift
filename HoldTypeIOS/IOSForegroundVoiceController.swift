import HoldTypeDomain
import Observation
@_spi(HoldTypeIOSCore) import HoldTypePersistence

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
    case microphonePermissionDenied
    case microphoneUnavailable
    case microphonePermissionTimedOut
    case tooShort
    case maximumDuration
}

enum IOSForegroundVoiceWarning: Equatable, Sendable {
    case historySaveFailed
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
    let warning: IOSForegroundVoiceWarning?
    let recovery: IOSForegroundVoiceRecovery
    let availableActions: [IOSForegroundVoiceAction]
    let latestAvailability: IOSForegroundVoiceLatestAvailability

    init(
        phase: VoiceWorkPhase,
        stage: VoiceAttemptStage?,
        outcome: VoiceAttemptOutcome?,
        setup: IOSForegroundVoiceSetup,
        failure: IOSForegroundVoiceFailure?,
        recovery: IOSForegroundVoiceRecovery,
        availableActions: [IOSForegroundVoiceAction],
        latestAvailability: IOSForegroundVoiceLatestAvailability,
        warning: IOSForegroundVoiceWarning? = nil
    ) {
        self.phase = phase
        self.stage = stage
        self.outcome = outcome
        self.setup = setup
        self.failure = failure
        self.warning = warning
        self.recovery = recovery
        self.availableActions = availableActions
        self.latestAvailability = latestAvailability
    }

    static let initial = IOSForegroundVoicePresentation(
        phase: .inactive,
        stage: nil,
        outcome: nil,
        setup: .unknown,
        failure: nil,
        recovery: .none,
        availableActions: [],
        latestAvailability: .unknown,
        warning: nil
    )
}

struct IOSForegroundVoiceObservation: Equatable, Sendable {
    let setup: IOSForegroundVoiceSetup
    let recovery: IOSForegroundVoiceRecovery
    let stage: VoiceAttemptStage?
    let latestAvailability: IOSForegroundVoiceLatestAvailability
    let translationAvailable: Bool

    init(
        setup: IOSForegroundVoiceSetup,
        recovery: IOSForegroundVoiceRecovery,
        stage: VoiceAttemptStage? = nil,
        latestAvailability: IOSForegroundVoiceLatestAvailability,
        translationAvailable: Bool = false
    ) {
        self.setup = setup
        self.recovery = recovery
        self.stage = stage
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
    let warning: IOSForegroundVoiceWarning?

    init(
        observation: IOSForegroundVoiceObservation,
        stage: VoiceAttemptStage? = nil,
        outcome: VoiceAttemptOutcome? = nil,
        failure: IOSForegroundVoiceFailure? = nil,
        warning: IOSForegroundVoiceWarning? = nil
    ) {
        self.observation = observation
        self.stage = stage
        self.outcome = outcome
        self.failure = failure
        self.warning = warning
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
    typealias RunStart = @Sendable (
        DictationOutputIntent,
        IOSVoiceSceneStartLease,
        IOSForegroundVoiceAuthority,
        @escaping Progress
    ) async -> IOSForegroundVoiceResolution
    typealias Run = @Sendable (
        IOSForegroundVoiceOperation,
        IOSForegroundVoiceAuthority,
        @escaping Progress
    ) async -> IOSForegroundVoiceResolution
    typealias FinishUtterance = @MainActor @Sendable (
        IOSForegroundVoiceAuthority
    ) -> IOSForegroundVoiceControlDisposition
    typealias ProviderConsentInvalidated = @MainActor @Sendable (
        IOSForegroundVoiceAuthority
    ) -> IOSForegroundVoiceControlDisposition

    let observe: Observe
    let runStart: RunStart
    let run: Run
    let finishUtterance: FinishUtterance
    let providerConsentInvalidated: ProviderConsentInvalidated

    init(
        observe: @escaping Observe,
        runStart: @escaping RunStart,
        run: @escaping Run,
        finishUtterance: @escaping FinishUtterance,
        providerConsentInvalidated: @escaping ProviderConsentInvalidated = {
            _ in .unavailable
        }
    ) {
        self.observe = observe
        self.runStart = runStart
        self.run = run
        self.finishUtterance = finishUtterance
        self.providerConsentInvalidated = providerConsentInvalidated
    }
}

@MainActor
@Observable
final class IOSForegroundVoiceController {
    private(set) var presentation = IOSForegroundVoicePresentation.initial

    @ObservationIgnored
    private let client: IOSForegroundVoiceClient
    @ObservationIgnored
    let sceneRegistry: IOSVoiceSceneRegistry
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
    private var activeOperation: IOSForegroundVoiceOperation?
    @ObservationIgnored
    private var activeProgressPosition: ProgressPosition?
    @ObservationIgnored
    private var presentationRevision: UInt64 = 0
    @ObservationIgnored
    private var nextAuthorityValue: UInt64 = 0
    @ObservationIgnored
    private var cancellationRequested = false
    @ObservationIgnored
    private var cancellationKind: CancellationKind?
    @ObservationIgnored
    private var finishRequested = false
    @ObservationIgnored
    private var providerConsentInvalidationRequested = false
    @ObservationIgnored
    private var lifecycleRefreshIsWaiting = false

    convenience init(client: IOSForegroundVoiceClient) {
        self.init(
            client: client,
            sceneRegistry: IOSVoiceSceneRegistry()
        )
    }

    init(
        client: IOSForegroundVoiceClient,
        sceneRegistry: IOSVoiceSceneRegistry
    ) {
        self.client = client
        self.sceneRegistry = sceneRegistry
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
        guard activeWork == nil, !lifecycleRefreshIsWaiting else { return }

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
                stage: observation.stage,
                outcome: self.activationOutcome(
                    for: observation.recovery
                ),
                failure: nil
            )
        }
        activeTask = task
        await task.value
    }

    /// Serializes lifecycle recovery behind the exact active Voice task. The
    /// terminal Voice publication completes before this method atomically
    /// claims activation ownership, so recovery never mutates presentation
    /// during a primary operation and a new Start cannot race the refresh.
    func performLifecycleRefresh(
        _ refresh: @escaping @MainActor @Sendable () async
            -> IOSForegroundVoiceLifecycleRefresh
    ) async -> IOSContainingAppRecoveryDisposition {
        if activeWork != nil { lifecycleRefreshIsWaiting = true }
        while let activeWork {
            guard let currentTask = activeTask else {
                lifecycleRefreshIsWaiting = false
                return .pendingLocalRecovery
            }
            await currentTask.value
            guard !Task.isCancelled else {
                lifecycleRefreshIsWaiting = false
                return .pendingLocalRecovery
            }
            if self.activeWork == activeWork {
                lifecycleRefreshIsWaiting = false
                return .pendingLocalRecovery
            }
        }

        guard !Task.isCancelled else {
            lifecycleRefreshIsWaiting = false
            return .pendingLocalRecovery
        }
        let serial = nextSerial()
        activeWork = .activation(serial)
        lifecycleRefreshIsWaiting = false
        let storage = LifecycleRefreshStorage()
        let task = Task { @MainActor in
            storage.result = await refresh()
        }
        activeTask = task

        return await withTaskCancellationHandler {
            await task.value
            guard activeWork == .activation(serial) else {
                return .pendingLocalRecovery
            }
            activeTask = nil
            activeWork = nil
            guard !Task.isCancelled, let result = storage.result else {
                return .pendingLocalRecovery
            }
            apply(
                result.observation,
                stage: result.observation.stage,
                outcome: activationOutcome(
                    for: result.observation.recovery
                ),
                failure: nil
            )
            return result.disposition
        } onCancel: {
            task.cancel()
        }
    }

    @discardableResult
    func submit(
        _ command: IOSForegroundVoiceActionCommand,
        from initiatingScene: IOSVoiceSceneFacade? = nil
    ) -> IOSForegroundVoiceActionAdmission {
        guard command.presentationRevision == presentationRevision else {
            return .stale
        }
        guard presentation.availableActions.contains(command.action) else {
            return .unavailable
        }

        switch command.action {
        case .startStandard:
            guard let initiatingScene,
                  let startLease = sceneRegistry.acquireStartLease(
                    initiatingScene: initiatingScene.identity
                  ),
                  begin(.start(.standard), startLease: startLease) else {
                return .unavailable
            }
        case .startTranslation:
            guard let initiatingScene,
                  let startLease = sceneRegistry.acquireStartLease(
                    initiatingScene: initiatingScene.identity
                  ),
                  begin(.start(.translate), startLease: startLease) else {
                return .unavailable
            }
        case .retryPending:
            guard begin(.retryPending) else { return .unavailable }
        case .recoverRecording:
            guard begin(.recoverRecording) else { return .unavailable }
        case .discard:
            guard begin(.discard) else { return .unavailable }
        case .retrySavingResult:
            guard begin(.retrySavingResult) else { return .unavailable }
        case .retryLocalCheckpoint:
            guard begin(.retryLocalCheckpoint) else { return .unavailable }
        case .finishUtterance:
            finishCurrentUtterance()
        case .cancelStart, .cancelUtterance:
            cancelCurrentOperation(kind: .ordinary)
        case .cancelProcessing:
            cancelCurrentOperation(kind: .processing)
        }
        return .accepted
    }

    private func begin(
        _ operation: IOSForegroundVoiceOperation,
        startLease: IOSVoiceSceneStartLease? = nil
    ) -> Bool {
        guard activeWork == nil, !lifecycleRefreshIsWaiting else {
            startLease?.finish()
            return false
        }

        let authority = IOSForegroundVoiceAuthority(value: nextSerial())
        activeAuthority = authority
        activeBaselineLatestAvailability = presentation.latestAvailability
        activeOperation = operation
        activeWork = .primary(authority)
        cancellationRequested = false
        cancellationKind = nil
        finishRequested = false
        providerConsentInvalidationRequested = false

        let initial = initialPresentation(for: operation)
        activeProgressPosition = initialProgressPosition(
            for: operation,
            presentation: initial
        )
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
            let resolution: IOSForegroundVoiceResolution
            if case let .start(intent) = operation,
               let startLease {
                resolution = await client.runStart(
                    intent,
                    startLease,
                    authority,
                    progress
                )
            } else {
                resolution = await client.run(
                    operation,
                    authority,
                    progress
                )
            }
            self?.complete(resolution, authority: authority)
        }
        return true
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

    private func cancelCurrentOperation(kind: CancellationKind) {
        guard !cancellationRequested,
              case .primary? = activeWork else {
            return
        }
        cancellationRequested = true
        cancellationKind = kind
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

    /// Stops provider-capable work after the consent gate has already closed.
    /// A Start follows the workflow's interruption path so valid capture stays
    /// recoverable. Other provider work settles through the already-closed
    /// provider gate; it is never reinterpreted as ordinary user cancellation
    /// because accepted output may already be durable.
    func providerConsentDidInvalidate() {
        guard !providerConsentInvalidationRequested,
              !cancellationRequested,
              case .primary(let authority)? = activeWork,
              activeAuthority == authority else {
            return
        }
        providerConsentInvalidationRequested = true
        publish(
            phase: presentation.phase,
            stage: presentation.stage,
            outcome: presentation.outcome,
            setup: presentation.setup,
            failure: presentation.failure,
            recovery: presentation.recovery,
            latestAvailability: presentation.latestAvailability
        )

        _ = client.providerConsentInvalidated(authority)
    }

    private func receive(
        _ progress: IOSForegroundVoiceProgress,
        authority: IOSForegroundVoiceAuthority
    ) {
        guard activeWork == .primary(authority),
              activeAuthority == authority,
              !cancellationRequested,
              !providerConsentInvalidationRequested,
              let projection = progressProjection(for: progress),
              let activeProgressPosition,
              projection.position.rawValue
                > activeProgressPosition.rawValue else {
            return
        }
        self.activeProgressPosition = projection.position
        publish(
            phase: projection.phase,
            stage: projection.stage,
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
        let projection: TerminalProjection
        if let cancellationKind {
            projection = cancelledProjection(
                resolution,
                kind: cancellationKind
            )
        } else {
            projection = terminalProjection(for: resolution)
        }
        activeTask = nil
        activeWork = nil
        activeAuthority = nil
        activeBaselineLatestAvailability = nil
        activeOperation = nil
        activeProgressPosition = nil
        cancellationRequested = false
        cancellationKind = nil
        finishRequested = false
        providerConsentInvalidationRequested = false
        apply(
            projection.observation,
            stage: projection.stage,
            outcome: projection.outcome,
            failure: projection.failure,
            warning: projection.warning
        )
    }

    private func apply(
        _ observation: IOSForegroundVoiceObservation,
        stage: VoiceAttemptStage?,
        outcome: VoiceAttemptOutcome?,
        failure: IOSForegroundVoiceFailure?,
        warning: IOSForegroundVoiceWarning? = nil
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
            translationAvailable: observation.translationAvailable,
            warning: warning
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
        translationAvailable: Bool? = nil,
        warning: IOSForegroundVoiceWarning? = nil
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
            latestAvailability: latestAvailability,
            warning: warning
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
        if cancellationRequested || providerConsentInvalidationRequested {
            return []
        }
        if case .primary? = activeWork {
            switch phase {
            case .arming:
                return [.cancelStart]
            case .listening:
                return finishRequested
                    ? [.cancelUtterance]
                    : [.finishUtterance, .cancelUtterance]
            case .processing:
                guard processingCancellationIsAvailable,
                      stage == .transcription
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
            (.processing, .transcription)
        case .recoverRecording, .discard:
            (.finalizing, .recordingFinalization)
        case .retrySavingResult:
            (.processing, presentation.stage)
        case .retryLocalCheckpoint:
            (.processing, presentation.stage)
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
            return reportedStage
        case .localCheckpoint(let stage):
            return stage
        case .none, .blocked:
            return nil
        }
    }

    private func activationOutcome(
        for recovery: IOSForegroundVoiceRecovery
    ) -> VoiceAttemptOutcome? {
        switch recovery {
        case .pendingRetryOrDiscard, .localCheckpoint:
            return .recoverableFailure
        case .none,
             .captureRecoverOrDiscard,
             .captureRecoverOnly,
             .captureDiscardOnly,
             .savingResult,
             .blocked:
            return nil
        }
    }

    private func terminalProjection(
        for resolution: IOSForegroundVoiceResolution
    ) -> TerminalProjection {
        let reportedStage = resolution.stage
            ?? resolution.observation.stage
        let outcome: VoiceAttemptOutcome?
        let failure: IOSForegroundVoiceFailure?

        switch resolution.observation.recovery {
        case .pendingRetryOrDiscard, .localCheckpoint:
            outcome = .recoverableFailure
            failure = resolution.failure
        case .savingResult, .blocked:
            outcome = nil
            failure = resolution.failure
        case .captureRecoverOrDiscard,
             .captureRecoverOnly,
             .captureDiscardOnly:
            outcome = nil
            failure = resolution.failure
        case .none:
            if resolution.outcome == .recoverableFailure {
                outcome = nil
            } else {
                outcome = resolution.outcome
            }
            failure = outcome == .resultReady
                ? nil
                : resolution.failure
        }

        return TerminalProjection(
            observation: resolution.observation,
            stage: reportedStage,
            outcome: outcome,
            failure: failure,
            warning: resolution.warning
        )
    }

    private func cancelledProjection(
        _ resolution: IOSForegroundVoiceResolution,
        kind: CancellationKind
    ) -> TerminalProjection {
        let latest = activeBaselineLatestAvailability
            ?? presentation.latestAvailability
        if resolution.outcome == .resultReady {
            return TerminalProjection(
                observation: IOSForegroundVoiceObservation(
                    setup: presentation.setup,
                    recovery: .blocked,
                    latestAvailability: latest
                ),
                stage: nil,
                outcome: nil,
                failure: .localRecovery
            )
        }

        switch kind {
        case .ordinary:
            if resolution.observation.recovery != .none {
                let reportedStage = resolution.stage
                    ?? resolution.observation.stage
                return TerminalProjection(
                    observation: IOSForegroundVoiceObservation(
                        setup: resolution.observation.setup,
                        recovery: resolution.observation.recovery,
                        stage: reportedStage,
                        latestAvailability:
                            resolution.observation.latestAvailability,
                        translationAvailable:
                            resolution.observation.translationAvailable
                    ),
                    stage: reportedStage,
                    outcome: nil,
                    failure: resolution.failure
                )
            }
            return TerminalProjection(
                observation: IOSForegroundVoiceObservation(
                    setup: resolution.observation.setup,
                    recovery: .none,
                    latestAvailability: latest,
                    translationAvailable:
                        resolution.observation.translationAvailable
                ),
                stage: nil,
                outcome: nil,
                failure: nil
            )
        case .processing:
            return cancelledProcessingProjection(
                resolution,
                latestAvailability: latest
            )
        }
    }

    private func cancelledProcessingProjection(
        _ resolution: IOSForegroundVoiceResolution,
        latestAvailability: IOSForegroundVoiceLatestAvailability
    ) -> TerminalProjection {
        let reportedStage = resolution.stage
            ?? resolution.observation.stage
        let setup = resolution.observation.setup
        let translationAvailable =
            resolution.observation.translationAvailable

        switch resolution.observation.recovery {
        case .pendingRetryOrDiscard:
            return TerminalProjection(
                observation: IOSForegroundVoiceObservation(
                    setup: setup,
                    recovery: .pendingRetryOrDiscard,
                    stage: reportedStage,
                    latestAvailability: latestAvailability,
                    translationAvailable: translationAvailable
                ),
                stage: reportedStage,
                outcome: .recoverableFailure,
                failure: resolution.failure
            )
        case .localCheckpoint(let retainedStage):
            return TerminalProjection(
                observation: IOSForegroundVoiceObservation(
                    setup: setup,
                    recovery: .localCheckpoint(retainedStage),
                    stage: retainedStage,
                    latestAvailability: latestAvailability,
                    translationAvailable: translationAvailable
                ),
                stage: retainedStage,
                outcome: .recoverableFailure,
                failure: resolution.failure
            )
        case .savingResult:
            return TerminalProjection(
                observation: IOSForegroundVoiceObservation(
                    setup: setup,
                    recovery: .savingResult,
                    stage: reportedStage,
                    latestAvailability: latestAvailability,
                    translationAvailable: translationAvailable
                ),
                stage: reportedStage,
                outcome: nil,
                failure: resolution.failure
            )
        case .blocked:
            return TerminalProjection(
                observation: IOSForegroundVoiceObservation(
                    setup: setup,
                    recovery: .blocked,
                    latestAvailability: latestAvailability,
                    translationAvailable: translationAvailable
                ),
                stage: nil,
                outcome: nil,
                failure: resolution.failure ?? .localRecovery
            )
        case .none:
            return TerminalProjection(
                observation: IOSForegroundVoiceObservation(
                    setup: setup,
                    recovery: .none,
                    latestAvailability: latestAvailability,
                    translationAvailable: translationAvailable
                ),
                stage: nil,
                outcome: nil,
                failure: nil
            )
        case .captureRecoverOrDiscard,
             .captureRecoverOnly,
             .captureDiscardOnly:
            return TerminalProjection(
                observation: IOSForegroundVoiceObservation(
                    setup: setup,
                    recovery: .blocked,
                    latestAvailability: latestAvailability,
                    translationAvailable: translationAvailable
                ),
                stage: nil,
                outcome: nil,
                failure: .localRecovery
            )
        }
    }

    private var processingCancellationIsAvailable: Bool {
        guard let activeOperation else { return false }
        switch activeOperation {
        case .start, .retryPending, .retryLocalCheckpoint:
            return true
        case .recoverRecording, .discard, .retrySavingResult:
            return false
        }
    }

    private func initialProgressPosition(
        for operation: IOSForegroundVoiceOperation,
        presentation: (phase: VoiceWorkPhase, stage: VoiceAttemptStage?)
    ) -> ProgressPosition {
        if operation == .retrySavingResult {
            return presentation.stage == .outputDelivery
                ? .outputDelivery
                : .postProcessing
        }

        switch presentation.phase {
        case .arming:
            return .arming
        case .listening:
            return .listening
        case .finalizing:
            return .finalizing
        case .processing:
            return progressPosition(for: presentation.stage)
                ?? .finalizing
        case .inactive, .ready:
            return .arming
        }
    }

    private func progressProjection(
        for progress: IOSForegroundVoiceProgress
    ) -> ProgressProjection? {
        switch progress {
        case .listening:
            return ProgressProjection(
                position: .listening,
                phase: .listening,
                stage: nil
            )
        case .finalizing:
            return ProgressProjection(
                position: .finalizing,
                phase: .finalizing,
                stage: .recordingFinalization
            )
        case .processing(let stage):
            guard let position = progressPosition(for: stage),
                  stage != .recordingFinalization else {
                return nil
            }
            return ProgressProjection(
                position: position,
                phase: .processing,
                stage: stage
            )
        }
    }

    private func progressPosition(
        for stage: VoiceAttemptStage?
    ) -> ProgressPosition? {
        switch stage {
        case .recordingFinalization:
            return .finalizing
        case .transcription:
            return .transcription
        case .postProcessing:
            return .postProcessing
        case .outputDelivery:
            return .outputDelivery
        case nil:
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

    private final class LifecycleRefreshStorage {
        var result: IOSForegroundVoiceLifecycleRefresh?
    }

    private enum CancellationKind {
        case ordinary
        case processing
    }

    private enum ProgressPosition: Int {
        case arming
        case listening
        case finalizing
        case transcription
        case postProcessing
        case outputDelivery
    }

    private struct ProgressProjection {
        let position: ProgressPosition
        let phase: VoiceWorkPhase
        let stage: VoiceAttemptStage?
    }

    private struct TerminalProjection {
        let observation: IOSForegroundVoiceObservation
        let stage: VoiceAttemptStage?
        let outcome: VoiceAttemptOutcome?
        let failure: IOSForegroundVoiceFailure?
        let warning: IOSForegroundVoiceWarning?

        init(
            observation: IOSForegroundVoiceObservation,
            stage: VoiceAttemptStage?,
            outcome: VoiceAttemptOutcome?,
            failure: IOSForegroundVoiceFailure?,
            warning: IOSForegroundVoiceWarning? = nil
        ) {
            self.observation = observation
            self.stage = stage
            self.outcome = outcome
            self.failure = failure
            self.warning = warning
        }
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

nonisolated protocol IOSForegroundVoiceRedactedValue:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {}

extension IOSForegroundVoiceRedactedValue {
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceSetup: IOSForegroundVoiceRedactedValue {
    nonisolated var description: String { "IOSForegroundVoiceSetup(<redacted>)" }
}

extension IOSForegroundVoiceFailure: IOSForegroundVoiceRedactedValue {
    nonisolated var description: String { "IOSForegroundVoiceFailure(<redacted>)" }
}

extension IOSForegroundVoiceWarning: IOSForegroundVoiceRedactedValue {
    nonisolated var description: String {
        "IOSForegroundVoiceWarning(<redacted>)"
    }
}

extension IOSForegroundVoiceRecovery: IOSForegroundVoiceRedactedValue {
    nonisolated var description: String { "IOSForegroundVoiceRecovery(<redacted>)" }
}

extension IOSForegroundVoiceLatestAvailability:
    IOSForegroundVoiceRedactedValue {
    nonisolated var description: String {
        "IOSForegroundVoiceLatestAvailability(<redacted>)"
    }
}

extension IOSForegroundVoiceAction: IOSForegroundVoiceRedactedValue {
    nonisolated var description: String { "IOSForegroundVoiceAction(<redacted>)" }
}

extension IOSForegroundVoiceActionCommand: IOSForegroundVoiceRedactedValue {
    nonisolated var description: String {
        "IOSForegroundVoiceActionCommand(<redacted>)"
    }
}

extension IOSForegroundVoiceActionAdmission:
    IOSForegroundVoiceRedactedValue {
    nonisolated var description: String {
        "IOSForegroundVoiceActionAdmission(<redacted>)"
    }
}

extension IOSForegroundVoicePresentation: IOSForegroundVoiceRedactedValue {
    nonisolated var description: String {
        "IOSForegroundVoicePresentation(<redacted>)"
    }
}

extension IOSForegroundVoiceObservation: IOSForegroundVoiceRedactedValue {
    nonisolated var description: String {
        "IOSForegroundVoiceObservation(<redacted>)"
    }
}

extension IOSForegroundVoiceOperation: IOSForegroundVoiceRedactedValue {
    nonisolated var description: String {
        "IOSForegroundVoiceOperation(<redacted>)"
    }
}

extension IOSForegroundVoiceProgress: IOSForegroundVoiceRedactedValue {
    nonisolated var description: String { "IOSForegroundVoiceProgress(<redacted>)" }
}

extension IOSForegroundVoiceResolution: IOSForegroundVoiceRedactedValue {
    nonisolated var description: String {
        "IOSForegroundVoiceResolution(<redacted>)"
    }
}

extension IOSForegroundVoiceAuthority: IOSForegroundVoiceRedactedValue {
    nonisolated var description: String { "IOSForegroundVoiceAuthority(<redacted>)" }
}

extension IOSForegroundVoiceControlDisposition:
    IOSForegroundVoiceRedactedValue {
    nonisolated var description: String {
        "IOSForegroundVoiceControlDisposition(<redacted>)"
    }
}

extension IOSForegroundVoiceClient: IOSForegroundVoiceRedactedValue {
    nonisolated var description: String { "IOSForegroundVoiceClient(<redacted>)" }
}
