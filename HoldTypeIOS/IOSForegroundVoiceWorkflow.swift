import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
@_spi(HoldTypeIOSCore) import HoldTypePersistence

private enum IOSForegroundVoiceRetryProviderRequirement: Equatable {
    case none
    case required
    case blocked
}

/// Process-owned imperative shell behind `IOSForegroundVoiceController`.
/// Construction is passive. All provider-capable paths require an explicit,
/// currently active scene proof and sequentially execute the frozen P4 order.
@MainActor
final class IOSForegroundVoiceWorkflow {
    private enum StopTrigger: Equatable {
        case done
        case explicitDiscard
        case interrupted
        case maximumDuration
    }

    private enum ConsentResolution {
        case accepted(IOSV1ProviderConsentObservation)
        case needsSetup
        case unavailable
    }

    private enum PermissionResolution: Equatable {
        case granted
        case denied
        case unavailable
        case timedOut
        case cancelled
        case stale
    }

    private final class SceneLeaseOwner {
        let lease: IOSVoiceSceneStartLease
        private var isFinished = false

        init(_ lease: IOSVoiceSceneStartLease) {
            self.lease = lease
        }

        func finish() {
            guard !isFinished else { return }
            isFinished = true
            lease.finish()
        }
    }

    private final class Attempt {
        enum Origin {
            case foreground(SceneLeaseOwner)
            case keyboard(UUID)
        }

        let token: IOSForegroundVoiceWorkflowAttemptToken
        let origin: Origin
        let forcesTextCorrection: Bool
        let clearsDraftOnStart: Bool
        let draftInsertionMode: IOSVoiceDraftInsertionMode
        var recordingAttemptID: UUID?
        var stopContinuation: CheckedContinuation<StopTrigger, Never>?
        var tailContinuation:
            CheckedContinuation<StopTrigger?, Never>?
        var pendingTrigger: StopTrigger?
        var forcedTrigger: StopTrigger?
        var sceneObservation: IOSVoiceSceneEventSubscription?
        var audioObservation: IOSForegroundVoiceWorkflowObservation?
        var recordingObservation: IOSForegroundVoiceWorkflowObservation?
        var audio: IOSForegroundVoiceWorkflowAudioLease?
        var recording: IOSForegroundVoiceWorkflowRecording?
        var maximumDurationTask: Task<Void, Never>?
        var tailTask: Task<Void, Never>?
        var providerTask:
            Task<IOSForegroundVoiceProcessingResolution, Never>?
        var finalizationLease: IOSForegroundVoiceWorkflowFinalizationLease?
        var finalizationExpired = false
        var isListening = false
        var hasStartedRecording = false
        var hasEnteredFinalization = false
        var isStopTailOpen = false
        var providerFinishTrigger: StopTrigger?
        var processingCancellationAuthority:
            IOSForegroundVoiceProcessingCancellationAuthority?
        var processingCancellationRequested = false
        var resolvedStopTrigger: StopTrigger?
        var requiresInitiatingScene: Bool

        init(
            token: IOSForegroundVoiceWorkflowAttemptToken,
            origin: Origin,
            forcesTextCorrection: Bool = false,
            clearsDraftOnStart: Bool = false,
            draftInsertionMode: IOSVoiceDraftInsertionMode = .replace
        ) {
            self.token = token
            self.origin = origin
            self.forcesTextCorrection = forcesTextCorrection
            self.clearsDraftOnStart = clearsDraftOnStart
            self.draftInsertionMode = draftInsertionMode
            switch origin {
            case .foreground:
                requiresInitiatingScene = true
            case .keyboard:
                requiresInitiatingScene = false
            }
        }

        var sceneLeaseOwner: SceneLeaseOwner? {
            guard case .foreground(let owner) = origin else { return nil }
            return owner
        }

        var sceneLease: IOSVoiceSceneStartLease? {
            sceneLeaseOwner?.lease
        }

        var allowsBackgroundContinuation: Bool {
            if case .keyboard = origin { return true }
            return false
        }

        func matchesKeyboardRequest(_ requestID: UUID) -> Bool {
            guard case .keyboard(let activeRequestID) = origin else {
                return false
            }
            return activeRequestID == requestID
        }
    }

    private let dependencies: IOSForegroundVoiceWorkflowDependencies
    private let configurationLoader: IOSForegroundVoiceConfigurationLoader
    private var activeAttempt: Attempt?
    private var captureRecoveryAttemptID: UUID?
    private var pendingObservation: IOSV1PendingRecordingObservation?
    private var lastConfiguration: IOSForegroundVoiceWorkflowConfiguration?
    private var passiveConfigurationSetupOverride: IOSForegroundVoiceSetup?
    private var activeControllerAuthority: IOSForegroundVoiceAuthority?
    private var activeControllerToken: IOSForegroundVoiceWorkflowAttemptToken?
    private var activeRetryAuthority: IOSForegroundVoiceRetryAuthority?
    private var isRunningRecoveryOperation = false
    private var acceptedKeyboardResult: (requestID: UUID, text: String)?
    private var keyboardWarmAudio: IOSForegroundVoiceWorkflowAudioLease?
    private var keyboardWarmInputIsRunning = false
    private var interruptedCaptureDidBecomeRecoverable:
        @MainActor @Sendable () async -> Void = {}

    init(dependencies: IOSForegroundVoiceWorkflowDependencies) {
        self.dependencies = dependencies
        configurationLoader = IOSForegroundVoiceConfigurationLoader(
            loadSettings: dependencies.loadSettings,
            loadLibrary: dependencies.loadLibrary
        )
    }

    func bindInterruptedCaptureRecoveryObserver(
        _ observe: @escaping @MainActor @Sendable () async -> Void
    ) {
        interruptedCaptureDidBecomeRecoverable = observe
    }

    var client: IOSForegroundVoiceClient {
        IOSForegroundVoiceClient(
            observe: { [weak self] in
                guard let self else {
                    return await MainActor.run {
                        Self.unavailableObservation
                    }
                }
                return await self.observe()
            },
            runStart: {
                [weak self] action,
                lease,
                authority,
                progress in
                guard let self else {
                    return await MainActor.run {
                        lease.finish()
                        return Self.unavailableResolution
                    }
                }
                return await self.runControllerStart(
                    action,
                    sceneLease: lease,
                    authority: authority,
                    progress: progress
                )
            },
            run: { [weak self] operation, authority, progress in
                guard let self else {
                    return await MainActor.run {
                        Self.unavailableResolution
                    }
                }
                return await self.run(
                    operation,
                    authority: authority,
                    progress: progress
                )
            },
            finishUtterance: { [weak self] authority in
                self?.finishControllerUtterance(authority)
                    ?? .unavailable
            },
            cancelUtterance: { [weak self] authority in
                self?.cancelControllerUtterance(authority)
                    ?? .unavailable
            },
            cancelProcessing: { [weak self] authority in
                self?.cancelControllerProcessing(authority)
                    ?? .unavailable
            },
            providerConsentInvalidated: { [weak self] authority in
                self?.providerConsentDidInvalidate(authority)
                    ?? .unavailable
            }
        )
    }

    var keyboardDictationClient: IOSKeyboardDictationWorkflowClient {
        IOSKeyboardDictationWorkflowClient(
            run: { [weak self] requestID, action, progress in
                guard let self else { return .failed }
                return await self.runKeyboardDictation(
                    requestID: requestID,
                    action: action,
                    progress: progress
                )
            },
            finish: { [weak self] requestID in
                self?.finishKeyboardDictation(requestID: requestID) ?? false
            },
            cancel: { [weak self] requestID in
                self?.cancelKeyboardDictation(requestID: requestID) ?? false
            },
            interrupt: { [weak self] requestID in
                self?.interruptKeyboardDictation(requestID: requestID)
                    ?? false
            },
            stopSession: { [weak self] requestID in
                self?.stopKeyboardSession(requestID: requestID)
            },
            ownsRetainedCapture: { [weak self] requestID in
                self?.ownsRetainedKeyboardCapture(requestID: requestID)
                    ?? false
            },
            endWarmSession: { [weak self] in
                self?.endKeyboardWarmSession()
            },
            loadTranslationAvailability: { [weak self] in
                await self?.configurationLoader
                    .loadKeyboardTranslationAvailability() ?? false
            }
        )
    }

    var savedRecordingClient: IOSSavedRecordingWorkflowClient {
        IOSSavedRecordingWorkflowClient(
            retry: { [weak self] expected in
                guard let self else { return false }
                return await self.retrySavedRecording(expected)
            }
        )
    }

    private func retrySavedRecording(
        _ expected: IOSV1SavedRecordingExpectation
    ) async -> Bool {
        guard activeAttempt == nil,
              activeControllerAuthority == nil,
              !isRunningRecoveryOperation else {
            return false
        }
        isRunningRecoveryOperation = true
        defer { isRunningRecoveryOperation = false }

        var promotedCapture: IOSV1PendingRecording?
        if case .completedCapture(let captureExpectation) = expected {
            guard let settings = try? await dependencies.loadSettings(),
                  !settings.transcriptionConfiguration
                    .customLanguageCodeValidation.isInvalid else {
                return false
            }
            do {
                promotedCapture = try await dependencies
                    .recoverCompletedCapture(
                        captureExpectation,
                        settings.transcriptionConfiguration
                    )
            } catch {
                return false
            }
        }

        let canonical: IOSV1PendingRecordingObservation
        do {
            guard let current = try await dependencies.loadPending(),
                  current.availability == .available else {
                return false
            }
            switch expected {
            case .pending(let pendingExpectation):
                guard current.expectation == pendingExpectation else {
                    return false
                }
            case .completedCapture(let captureExpectation):
                guard let promotedCapture,
                      current.recording.attemptID
                    == captureExpectation.attemptID,
                      current.recording.phase == .failed,
                      current.recording == promotedCapture else {
                    return false
                }
            }
            canonical = current
        } catch {
            return false
        }

        pendingObservation = canonical
        let resolution = await runRetryPending(progress: { _ in })
        return resolution.failure == nil
    }

    private func runControllerStart(
        _ action: IOSForegroundVoiceStartAction,
        sceneLease: IOSVoiceSceneStartLease,
        authority: IOSForegroundVoiceAuthority,
        progress: @escaping IOSForegroundVoiceClient.Progress
    ) async -> IOSForegroundVoiceResolution {
        guard activeControllerAuthority == nil,
              activeControllerToken == nil else {
            sceneLease.finish()
            return Self.busyResolution
        }
        let token = IOSForegroundVoiceWorkflowAttemptToken()
        activeControllerAuthority = authority
        activeControllerToken = token
        defer {
            if activeControllerAuthority == authority,
               activeControllerToken == token {
                activeControllerAuthority = nil
                activeControllerToken = nil
            }
        }
        return await start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: action.outputIntent,
                sceneLease: sceneLease,
                forcesTextCorrection: action.forcesTextCorrection,
                clearsDraftOnStart: action.clearsDraftOnStart,
                draftInsertionMode: action.draftInsertionMode
            ),
            token: token,
            progress: progress
        )
    }

    private func finishControllerUtterance(
        _ authority: IOSForegroundVoiceAuthority
    ) -> IOSForegroundVoiceControlDisposition {
        guard activeControllerAuthority == authority,
              let token = activeControllerToken else {
            return .unavailable
        }
        return finishUtterance(token)
    }

    private func cancelControllerUtterance(
        _ authority: IOSForegroundVoiceAuthority
    ) -> IOSForegroundVoiceControlDisposition {
        guard activeControllerAuthority == authority,
              activeControllerToken != nil,
              let attempt = activeAttempt,
              attempt.isListening,
              !attempt.hasEnteredFinalization,
              (attempt.providerFinishTrigger == nil
                || attempt.isStopTailOpen),
              attempt.forcedTrigger == nil,
              attempt.pendingTrigger == nil else {
            return .unavailable
        }
        requestStop(.explicitDiscard, for: attempt)
        return .accepted
    }

    private func providerConsentDidInvalidate(
        _ authority: IOSForegroundVoiceAuthority
    ) -> IOSForegroundVoiceControlDisposition {
        guard activeControllerAuthority == authority,
              activeControllerToken != nil,
              let attempt = activeAttempt else {
            return .unavailable
        }
        requestStop(.interrupted, for: attempt)
        return .accepted
    }

    private func cancelControllerProcessing(
        _ authority: IOSForegroundVoiceAuthority
    ) -> IOSForegroundVoiceControlDisposition {
        guard activeControllerAuthority == authority else {
            return .unavailable
        }
        if let attempt = activeAttempt,
           let cancellationAuthority =
               attempt.processingCancellationAuthority,
           attempt.providerTask != nil,
           !attempt.processingCancellationRequested {
            attempt.processingCancellationRequested = true
            cancellationAuthority.cancelExplicitly()
            attempt.providerTask?.cancel()
            return .accepted
        }
        if let retryAuthority = activeRetryAuthority,
           retryAuthority.canContinue {
            retryAuthority.cancelProcessingExplicitly()
            return .accepted
        }
        return .unavailable
    }

    /// Runs the exact scene-bound Start path. The returned token is also the
    /// only authority accepted by `finishUtterance(_:)`.
    func start(
        _ request: IOSForegroundVoiceWorkflowStartRequest,
        token: IOSForegroundVoiceWorkflowAttemptToken,
        progress: @escaping IOSForegroundVoiceClient.Progress
    ) async -> IOSForegroundVoiceResolution {
        let leaseOwner = SceneLeaseOwner(request.sceneLease)
        defer { leaseOwner.finish() }
        guard activeAttempt == nil,
              !isRunningRecoveryOperation else {
            return Self.busyResolution
        }
        return await runStart(
            request.outputIntent,
            origin: .foreground(leaseOwner),
            token: token,
            forcesTextCorrection: request.forcesTextCorrection,
            clearsDraftOnStart: request.clearsDraftOnStart,
            draftInsertionMode: request.draftInsertionMode,
            progress: progress
        )
    }

    func finishUtterance(
        _ token: IOSForegroundVoiceWorkflowAttemptToken
    ) -> IOSForegroundVoiceControlDisposition {
        guard let attempt = activeAttempt,
              attempt.token == token,
              attempt.isListening,
              attempt.recording?.isActive == true,
              !attempt.hasEnteredFinalization,
              attempt.providerFinishTrigger == nil,
              attempt.forcedTrigger == nil,
              attempt.pendingTrigger == nil else {
            return .unavailable
        }
        requestStop(.done, for: attempt)
        return .accepted
    }

    private func runKeyboardDictation(
        requestID: UUID,
        action: KeyboardVoiceAction,
        progress: @escaping IOSKeyboardDictationWorkflowClient.Progress
    ) async -> IOSKeyboardDictationWorkflowResolution {
        guard await waitForKeyboardStartAvailability() else {
            return .failed
        }
        let token = IOSForegroundVoiceWorkflowAttemptToken()
        let intent: DictationOutputIntent = action.translates
            ? .translate
            : .standard
        let resolution = await runStart(
            intent,
            origin: .keyboard(requestID),
            token: token,
            forcesTextCorrection: action.corrects,
            progress: { value in
                switch value {
                case .listening(let limit):
                    progress(.listening(limit))
                case .finalizing, .processing:
                    progress(.processing)
                }
            }
        )
        if let acceptedKeyboardResult,
           acceptedKeyboardResult.requestID == requestID {
            self.acceptedKeyboardResult = nil
            return .accepted(acceptedKeyboardResult.text)
        }
        if resolution.outcome == .interrupted,
           resolution.observation.recovery == .captureRecoverOrDiscard {
            return .interruptedSaved
        }
        if resolution.transcriptionReplayBlocked,
           resolution.observation.recovery == .blocked {
            return .transcriptionUncertainSaved
        }
        return resolution.failure == nil && resolution.outcome == nil
            ? .cancelled
            : .failed
    }

    /// A containing-app launch can still be completing local lifecycle
    /// recovery when a fresh keyboard URL arrives. That recovery owns no user
    /// request, so a keyboard tap waits briefly instead of surfacing a stale
    /// failure or requiring a second tap.
    private func waitForKeyboardStartAvailability() async -> Bool {
        guard activeAttempt == nil else { return false }
        for _ in 0..<60 {
            guard !Task.isCancelled, activeAttempt == nil else { return false }
            if !isRunningRecoveryOperation { return true }
            do {
                try await dependencies.sleep(.milliseconds(50))
            } catch {
                return false
            }
        }
        return activeAttempt == nil && !isRunningRecoveryOperation
    }

    private func finishKeyboardDictation(requestID: UUID) -> Bool {
        guard let attempt = activeAttempt,
              attempt.matchesKeyboardRequest(requestID),
              attempt.isListening,
              attempt.recording?.isActive == true,
              !attempt.hasEnteredFinalization,
              (attempt.providerFinishTrigger == nil
                || attempt.isStopTailOpen),
              attempt.forcedTrigger == nil,
              attempt.pendingTrigger == nil else {
            return false
        }
        requestStop(.done, for: attempt)
        return true
    }

    private func cancelKeyboardDictation(requestID: UUID) -> Bool {
        guard let attempt = activeAttempt,
              attempt.matchesKeyboardRequest(requestID),
              attempt.isListening,
              !attempt.hasEnteredFinalization,
              attempt.providerFinishTrigger == nil,
              attempt.forcedTrigger == nil,
              attempt.pendingTrigger == nil else {
            return false
        }
        requestStop(.explicitDiscard, for: attempt)
        return true
    }

    private func interruptKeyboardDictation(requestID: UUID) -> Bool {
        guard let attempt = activeAttempt,
              attempt.matchesKeyboardRequest(requestID) else {
            return false
        }
        requestStop(.interrupted, for: attempt)
        return true
    }

    private func stopKeyboardSession(requestID: UUID?) {
        endKeyboardWarmSession()
        guard let requestID,
              let attempt = activeAttempt,
              attempt.matchesKeyboardRequest(requestID),
              !attempt.hasEnteredFinalization,
              attempt.providerFinishTrigger == nil else {
            return
        }
        requestStop(.interrupted, for: attempt)
    }

    private func ownsRetainedKeyboardCapture(requestID: UUID) -> Bool {
        guard let attempt = activeAttempt,
              attempt.matchesKeyboardRequest(requestID) else {
            return false
        }
        return attempt.hasStartedRecording
            || attempt.hasEnteredFinalization
            || attempt.recordingAttemptID != nil
                && attempt.recording?.isActive == true
    }

    private func observe(
        includeConfiguration: Bool = true
    ) async -> IOSForegroundVoiceObservation {
        let capture = await dependencies.reconcileCaptureSources()
        return await loadDurableObservation(
            capture: capture,
            includeConfiguration: includeConfiguration
        ).observation
    }

    /// Sole process-lifecycle recovery owner. The controller lifecycle lease
    /// guarantees this cannot overlap primary Voice work; the guard remains a
    /// fail-closed defense for direct test or future internal callers.
    func recoverLifecycle(
        _ opportunity: IOSV1ContainingAppRecoveryOpportunity
    ) async -> IOSForegroundVoiceLifecycleRefresh {
        guard activeAttempt == nil,
              !isRunningRecoveryOperation,
              !Task.isCancelled else {
            return IOSForegroundVoiceLifecycleRefresh(
                observation: Self.unavailableObservation,
                disposition: .pendingLocalRecovery
            )
        }
        isRunningRecoveryOperation = true
        defer { isRunningRecoveryOperation = false }

        let orphanRepair = opportunity == .processLaunch
            ? await dependencies.repairOrphanedCaptureAtProcessLaunch()
            : nil
        guard !Task.isCancelled else {
            return cancelledLifecycleRefresh(
                capture: orphanRepair ?? .blocked
            )
        }
        var capture = await dependencies.reconcileCaptureSources()
        let orphanRepairBlocked = orphanRepair == .blocked
        if orphanRepairBlocked { capture = .blocked }
        guard !Task.isCancelled else {
            return cancelledLifecycleRefresh(capture: capture)
        }
        let historyDisposition = await dependencies
            .recoverContainingAppLifecycle(opportunity)
        guard !Task.isCancelled else {
            return cancelledLifecycleRefresh(capture: capture)
        }
        if opportunity == .processLaunch,
           historyDisposition == .complete,
           capture == .blocked,
           !orphanRepairBlocked {
            capture = await dependencies.reconcileCaptureSources()
            guard !Task.isCancelled else {
                return cancelledLifecycleRefresh(capture: capture)
            }
        }
        let durable = await loadDurableObservation(
            capture: capture,
            includeConfiguration: true,
            continueIf: { !Task.isCancelled }
        )
        let isBlockedUnknown = capture == .blocked
        let disposition: IOSV1ContainingAppRecoveryDisposition =
            historyDisposition == .complete
                && durable.localLoadsSucceeded
                && !isBlockedUnknown
                && !Task.isCancelled
            ? .complete
            : .pendingLocalRecovery
        return IOSForegroundVoiceLifecycleRefresh(
            observation: durable.observation,
            disposition: disposition
        )
    }

    private func cancelledLifecycleRefresh(
        capture: IOSV1ForegroundVoiceCaptureRecoveryObservation
    ) -> IOSForegroundVoiceLifecycleRefresh {
        IOSForegroundVoiceLifecycleRefresh(
            observation: applyDurableFailure(capture: capture),
            disposition: .pendingLocalRecovery
        )
    }

    private struct DurableObservationResolution {
        let observation: IOSForegroundVoiceObservation
        let localLoadsSucceeded: Bool
    }

    private func loadDurableObservation(
        capture: IOSV1ForegroundVoiceCaptureRecoveryObservation,
        includeConfiguration: Bool,
        continueIf: @MainActor () -> Bool = { true }
    ) async -> DurableObservationResolution {
        do {
            let pending = try await dependencies.loadPending()
            guard continueIf() else { throw CancellationError() }
            _ = try await dependencies.loadLatest()
            guard continueIf() else { throw CancellationError() }
            let durable = IOSForegroundVoiceWorkflowDurableObservation(
                capture: capture,
                pending: pending
            )
            if includeConfiguration,
               mapRecovery(
                    capture: capture,
                    pending: pending
                ) == .none {
                switch await configurationLoader.load(
                    .standard,
                    continueIf: continueIf
                ) {
                case .available(let configuration):
                    lastConfiguration = configuration
                    passiveConfigurationSetupOverride = nil
                case .settingsUnavailable, .libraryUnavailable:
                    lastConfiguration = nil
                    passiveConfigurationSetupOverride = .unavailable
                    return DurableObservationResolution(
                        observation: apply(durable),
                        localLoadsSucceeded: false
                    )
                case .invalid(let destination):
                    lastConfiguration = nil
                    passiveConfigurationSetupOverride =
                        .needsSetup(destination)
                }
            }
            return DurableObservationResolution(
                observation: apply(durable),
                localLoadsSucceeded: true
            )
        } catch {
            if includeConfiguration {
                lastConfiguration = nil
                passiveConfigurationSetupOverride = .unavailable
            }
            return DurableObservationResolution(
                observation: applyDurableFailure(capture: capture),
                localLoadsSucceeded: false
            )
        }
    }

    private func run(
        _ operation: IOSForegroundVoiceOperation,
        authority: IOSForegroundVoiceAuthority,
        progress: @escaping IOSForegroundVoiceClient.Progress
    ) async -> IOSForegroundVoiceResolution {
        guard activeControllerAuthority == nil,
              activeAttempt == nil,
              !isRunningRecoveryOperation else {
            return Self.busyResolution
        }
        activeControllerAuthority = authority
        isRunningRecoveryOperation = true
        defer {
            isRunningRecoveryOperation = false
            if activeControllerAuthority == authority {
                activeControllerAuthority = nil
            }
        }

        switch operation {
        case .start:
            return IOSForegroundVoiceResolution(
                observation: IOSForegroundVoiceObservation(
                    setup: .unavailable,
                    recovery: .none,
                    translationAvailable: translationIsAvailable
                ),
                failure: .unavailable
            )
        case .checkAgain:
            let observation = await observe(includeConfiguration: true)
            return IOSForegroundVoiceResolution(
                observation: observation,
                failure: observation.setup == .unavailable
                    ? .localRecovery
                    : nil
            )
        case .retryPending:
            return await runRetryPending(progress: progress)
        case .recoverRecording:
            return await runRecoverRecording()
        case .discard:
            return await runDiscard()
        }
    }

    private func runStart(
        _ intent: DictationOutputIntent,
        origin: Attempt.Origin,
        token: IOSForegroundVoiceWorkflowAttemptToken,
        forcesTextCorrection: Bool = false,
        clearsDraftOnStart: Bool = false,
        draftInsertionMode: IOSVoiceDraftInsertionMode = .replace,
        progress: @escaping IOSForegroundVoiceClient.Progress
    ) async -> IOSForegroundVoiceResolution {
        if case .foreground(let sceneLeaseOwner) = origin,
           dependencies.sceneRegistry.validateContinuation(
               sceneLeaseOwner.lease
           ) != .ready {
            return await blockedPreflight(failure: .unavailable)
        }

        let attempt = Attempt(
            token: token,
            origin: origin,
            forcesTextCorrection: forcesTextCorrection,
            clearsDraftOnStart: clearsDraftOnStart,
            draftInsertionMode: draftInsertionMode
        )
        activeAttempt = attempt
        dependencies.recordDiagnostic(
            .voiceStartRequested(
                origin: Self.diagnosticOrigin(origin),
                action: Self.diagnosticAction(
                    intent: intent,
                    forcesTextCorrection: forcesTextCorrection
                )
            )
        )
        if case .foreground = origin {
            attempt.sceneObservation = dependencies.sceneRegistry.observeEvents {
                [weak self, weak attempt] event in
                guard let self, let attempt,
                      self.activeAttempt === attempt else {
                    return
                }
                guard self.dependencies.sceneRegistry.validate(event) else {
                    return
                }
                switch event.kind {
                case .lastActiveSceneLost(
                    .expectedMicrophonePermissionPrompt
                ), .aggregateBecameActive,
                     .initiatingSceneReactivatedAfterPermission:
                    break
                case .lastActiveSceneLost(.voiceWorkMustStop):
                    // Scene phase is presentation state, not proof that the
                    // recorder lost microphone capability. Before retained
                    // capture it may retire arming; after capture starts the
                    // audio/recorder observers own interruption authority.
                    guard !attempt.hasStartedRecording else { break }
                    self.dependencies.cancelStartBoundary()
                    self.requestStop(.interrupted, for: attempt)
                case .initiatingSceneBecameUnavailable
                    where attempt.requiresInitiatingScene:
                    self.dependencies.cancelStartBoundary()
                    self.requestStop(.interrupted, for: attempt)
                case .initiatingSceneBecameUnavailable:
                    break
                }
            }
        }

        let resolution = await withTaskCancellationHandler {
            await performStart(
                intent,
                attempt: attempt,
                progress: progress
            )
        } onCancel: {
            Task { @MainActor [weak self, weak attempt] in
                guard let self, let attempt else { return }
                self.requestStop(.interrupted, for: attempt)
            }
        }
        if let trigger = attempt.resolvedStopTrigger {
            dependencies.recordDiagnostic(
                .voiceStopResolved(
                    reason: Self.diagnosticStopReason(trigger),
                    durability: Self.diagnosticDurability(
                        resolution.observation.recovery
                    ),
                    providerAuthority:
                        attempt.providerFinishTrigger == nil
                            || attempt.forcedTrigger == .explicitDiscard
                        ? .absent : .granted,
                    attempt: attempt.recordingAttemptID.map(
                        IOSDiagnosticCorrelationTag.init
                    )
                )
            )
        }
        dependencies.recordDiagnostic(
            .voiceCompleted(Self.diagnosticOutcome(resolution))
        )
        return resolution
    }

    private func performStart(
        _ intent: DictationOutputIntent,
        attempt: Attempt,
        progress: @escaping IOSForegroundVoiceClient.Progress
    ) async -> IOSForegroundVoiceResolution {
        defer { retire(attempt) }

        guard await hasNoDurableRecoveryOwner(),
              canContinueArming(
                attempt,
                requireInitiatingScene: attempt.requiresInitiatingScene
              ) else {
            return await blockedPreflight(failure: .localRecovery)
        }
        let configuration: IOSForegroundVoiceWorkflowConfiguration
        switch await configurationLoader.load(
            intent,
            continueIf: { [weak self, weak attempt] in
                guard let self, let attempt else { return false }
                return self.canContinueArming(
                    attempt,
                    requireInitiatingScene: attempt.requiresInitiatingScene
                )
            }
        ) {
        case .available(let value):
            configuration = value
        case .settingsUnavailable, .libraryUnavailable:
            return await blockedPreflight(failure: .localRecovery)
        case .invalid(let destination):
            return await blockedPreflight(
                setup: .needsSetup(destination),
                failure: .unavailable
            )
        }
        guard canContinueArming(
            attempt,
            requireInitiatingScene: attempt.requiresInitiatingScene
        ) else { return await blockedPreflight(failure: .unavailable) }
        lastConfiguration = configuration
        passiveConfigurationSetupOverride = nil

        let consent: IOSV1ProviderConsentObservation
        switch await resolveConsent(for: attempt) {
        case .accepted(let observation):
            consent = observation
        case .needsSetup:
            return await blockedPreflight(
                setup: .needsSetup(.microphoneAndPrivacy),
                failure: nil
            )
        case .unavailable:
            return await blockedPreflight(failure: .localRecovery)
        }
        guard canContinueArming(
            attempt,
            requireInitiatingScene: attempt.requiresInitiatingScene
        ) else { return await blockedPreflight(failure: .unavailable) }

        let credential: IOSForegroundVoiceWorkflowCredentialProof
        switch await dependencies.resolveCredential() {
        case .available(let proof):
            credential = proof
        case .needsSetup:
            return await blockedPreflight(
                setup: .needsSetup(.openAI),
                failure: nil
            )
        case .unavailable:
            return await blockedPreflight(
                setup: .needsSetup(.openAI),
                failure: .credentialUnavailable
            )
        }
        guard canContinueArming(
            attempt,
            requireInitiatingScene: attempt.requiresInitiatingScene
        ) else { return await blockedPreflight(failure: .unavailable) }

        switch await resolvePermission(for: attempt) {
        case .granted:
            break
        case .denied:
            return await blockedPreflight(
                setup: .needsSetup(.microphoneAndPrivacy),
                failure: .microphonePermissionDenied
            )
        case .unavailable:
            return await blockedPreflight(
                setup: .needsSetup(.microphoneAndPrivacy),
                failure: .microphoneUnavailable
            )
        case .timedOut:
            return await blockedPreflight(
                setup: .ready,
                failure: .microphonePermissionTimedOut
            )
        case .cancelled:
            return await blockedPreflight(setup: .ready, failure: nil)
        case .stale:
            return await blockedPreflight(failure: .unavailable)
        }
        guard canContinueArming(
            attempt,
            requireInitiatingScene: attempt.requiresInitiatingScene
        ) else { return await blockedPreflight(failure: .unavailable) }

        // Consent and the system permission interaction are complete. The
        // process attempt remains admitted, but no scene owns presentation
        // from this point forward.
        attempt.requiresInitiatingScene = false
        attempt.sceneLeaseOwner?.finish()
        guard canContinueArming(
            attempt,
            requireInitiatingScene: false
        ) else { return await blockedPreflight(failure: .unavailable) }

        guard await revalidate(
            attempt: attempt,
            intent: intent,
            configuration: configuration,
            consent: consent,
            credential: credential,
            requireGrantedPermission: true
        ) else {
            return await blockedPreflight(failure: .unavailable)
        }
        guard canContinueArming(
            attempt,
            requireInitiatingScene: false
        ) else { return await blockedPreflight(failure: .unavailable) }

        let reusesKeyboardWarmAudio = attempt.allowsBackgroundContinuation
            && keyboardWarmAudio != nil
        if !reusesKeyboardWarmAudio {
            guard await dependencies.stopHistoryPlayback(),
                  canContinueArming(
                      attempt,
                      requireInitiatingScene: false
                  ) else {
                return await blockedPreflight(failure: .operationFailed)
            }
        }

        if attempt.clearsDraftOnStart {
            guard await dependencies.prepareDraftForNewDictation() else {
                return await blockedPreflight(failure: .draftClearFailed)
            }
            guard canContinueArming(
                attempt,
                requireInitiatingScene: false
            ) else { return await blockedPreflight(failure: .unavailable) }
        }

        guard canContinueArming(
            attempt,
            requireInitiatingScene: false
        ) else { return await blockedPreflight(failure: .unavailable) }
        dependencies.recordDiagnostic(.audio(.activationStarted))
        do {
            if reusesKeyboardWarmAudio {
                attempt.audio = keyboardWarmAudio
                keyboardWarmAudio = nil
            } else {
                endKeyboardWarmSession()
                attempt.audio = try dependencies.activateAudio()
            }
            dependencies.recordDiagnostic(.audio(.activated))
        } catch {
            dependencies.recordDiagnostic(.audio(.activationFailed))
            return await blockedPreflight(failure: .operationFailed)
        }
        guard canContinueArming(
            attempt,
            requireInitiatingScene: false
        ) else { return await blockedPreflight(failure: .unavailable) }
        do {
            guard let audio = attempt.audio else {
                return await blockedPreflight(failure: .unavailable)
            }
            try audio.freezeAndValidateInput()
            dependencies.recordDiagnostic(.audio(.inputValidated))
        } catch {
            dependencies.recordDiagnostic(.audio(.inputInvalid))
            return await blockedPreflight(failure: .unavailable)
        }
        guard canContinueArming(
            attempt,
            requireInitiatingScene: false
        ) else { return await blockedPreflight(failure: .unavailable) }
        attempt.audioObservation = attempt.audio?.observe {
            [weak self, weak attempt] event in
            guard let self, let attempt, self.activeAttempt === attempt else {
                return
            }
            switch event {
            case .interruption, .routeInvalid, .mediaServicesLost,
                 .mediaServicesReset, .ended:
                self.requestStop(.interrupted, for: attempt)
            case .routeNeedsRevalidation:
                guard let audio = attempt.audio else {
                    self.requestStop(.interrupted, for: attempt)
                    return
                }
                if attempt.hasStartedRecording,
                   attempt.recording?.isActive != true {
                    self.requestStop(.interrupted, for: attempt)
                    return
                }
                do {
                    try audio.freezeAndValidateInput()
                } catch {
                    self.requestStop(.interrupted, for: attempt)
                }
            }
        }

        let cuesEnabled = configuration.settings
            .voiceSessionPreferences.audioCuesEnabled
        // Keep background repeat attempts input-only while preserving the
        // boundary token and haptic. The initial foreground handoff retains
        // the user's configured start cue.
        let startBoundaryAudioCuesEnabled = cuesEnabled
            && !reusesKeyboardWarmAudio
        guard await dependencies.playStartBoundary(
            startBoundaryAudioCuesEnabled
        ) else {
            return await blockedPreflight(failure: .operationFailed)
        }
        guard canContinueArming(
            attempt,
            requireInitiatingScene: false
        ) else { return await blockedPreflight(failure: .unavailable) }
        guard await revalidate(
            attempt: attempt,
            intent: intent,
            configuration: configuration,
            consent: consent,
            credential: credential,
            requireGrantedPermission: true
        ) else {
            return await blockedPreflight(failure: .unavailable)
        }
        guard canContinueArming(
            attempt,
            requireInitiatingScene: false
        ) else { return await blockedPreflight(failure: .unavailable) }
        do {
            guard let audio = attempt.audio else {
                return await blockedPreflight(failure: .unavailable)
            }
            try audio.freezeAndValidateInput()
            dependencies.recordDiagnostic(.audio(.inputValidated))
        } catch {
            dependencies.recordDiagnostic(.audio(.inputInvalid))
            return await blockedPreflight(failure: .unavailable)
        }

        guard canContinueArming(
            attempt,
            requireInitiatingScene: false
        ) else { return await blockedPreflight(failure: .unavailable) }
        do {
            let recordingAttemptID = dependencies.makeUUID()
            attempt.recordingAttemptID = recordingAttemptID
            attempt.recording = try await dependencies.makeRecording(
                recordingAttemptID,
                intent,
                attempt.draftInsertionMode,
                attempt.forcesTextCorrection,
                configuration.settings.voiceSessionPreferences
                    .recordingDurationLimit
            )
        } catch {
            return await blockedPreflight(failure: .localRecovery)
        }
        guard canContinueArming(
            attempt,
            requireInitiatingScene: false
        ) else {
            return await resolveStoppedAttempt(
                attempt.forcedTrigger ?? .interrupted,
                attempt: attempt,
                configuration: configuration,
                consent: consent,
                credential: credential,
                progress: progress
            )
        }
        attempt.recordingObservation = attempt.recording?.observeTerminal {
            [weak self, weak attempt] reason in
            guard let self, let attempt, self.activeAttempt === attempt else {
                return
            }
            switch reason {
            case .done, .cancelled:
                break
            case .interrupted:
                self.requestStop(.interrupted, for: attempt)
            case .maximumDuration:
                self.requestStop(.maximumDuration, for: attempt)
            }
        }
        guard canContinueArming(
            attempt,
            requireInitiatingScene: false
        ) else {
            return await resolveStoppedAttempt(
                attempt.forcedTrigger ?? .interrupted,
                attempt: attempt,
                configuration: configuration,
                consent: consent,
                credential: credential,
                progress: progress
            )
        }
        let startResult = await attempt.recording?.start() ?? .failed
        switch startResult {
        case .started:
            break
        case .cancelled:
            return await resolveStoppedAttempt(
                attempt.forcedTrigger ?? .interrupted,
                attempt: attempt,
                configuration: configuration,
                consent: consent,
                credential: credential,
                progress: progress
            )
        case .failed:
            let resolution = await resolveStoppedAttempt(
                attempt.forcedTrigger ?? .interrupted,
                attempt: attempt,
                configuration: configuration,
                consent: consent,
                credential: credential,
                progress: progress
            )
            guard attempt.forcedTrigger == nil else { return resolution }
            return IOSForegroundVoiceResolution(
                observation: resolution.observation,
                stage: resolution.stage,
                outcome: .interrupted,
                failure: resolution.observation.recovery == .none
                    ? .operationFailed
                    : resolution.failure ?? .localRecovery
            )
        }
        attempt.hasStartedRecording = true
        attempt.isListening = true
        let recordingDurationLimit = configuration.settings
            .voiceSessionPreferences.recordingDurationLimit
        progress(.listening(recordingDurationLimit))
        scheduleMaximumDuration(
            for: attempt,
            limit: recordingDurationLimit
        )
        dependencies.recordDiagnostic(
            .voiceRecordingStarted(
                origin: Self.diagnosticOrigin(attempt.origin)
            )
        )

        if attempt.allowsBackgroundContinuation,
           !keyboardWarmInputIsRunning {
            do {
                try dependencies.beginKeyboardWarmInput()
                keyboardWarmInputIsRunning = true
            } catch {
                // The keeper only makes a later warm attempt possible. The
                // already-active recorder remains the authority for this
                // utterance and must not be stopped by an auxiliary failure.
                keyboardWarmInputIsRunning = false
            }
        }

        guard canContinueArming(
            attempt,
            requireInitiatingScene: false
        ) else {
            return await resolveStoppedAttempt(
                attempt.forcedTrigger ?? .interrupted,
                attempt: attempt,
                configuration: configuration,
                consent: consent,
                credential: credential,
                progress: progress
            )
        }
        guard attempt.recording?.isActive == true else {
            return await resolveStoppedAttempt(
                .interrupted,
                attempt: attempt,
                configuration: configuration,
                consent: consent,
                credential: credential,
                progress: progress
            )
        }
        guard await revalidate(
                attempt: attempt,
                intent: intent,
                configuration: configuration,
                consent: consent,
                credential: credential,
                requireGrantedPermission: true,
                requireNoDurableOwner: false
            ) else {
            return await resolveStoppedAttempt(
                attempt.forcedTrigger ?? .interrupted,
                attempt: attempt,
                configuration: configuration,
                consent: consent,
                credential: credential,
                progress: progress
            )
        }
        guard canContinueArming(
            attempt,
            requireInitiatingScene: false
        ) else {
            return await resolveStoppedAttempt(
                attempt.forcedTrigger ?? .interrupted,
                attempt: attempt,
                configuration: configuration,
                consent: consent,
                credential: credential,
                progress: progress
            )
        }
        do {
            guard let audio = attempt.audio else {
                throw CancellationError()
            }
            try audio.freezeAndValidateInput()
        } catch {
            return await resolveStoppedAttempt(
                .interrupted,
                attempt: attempt,
                configuration: configuration,
                consent: consent,
                credential: credential,
                progress: progress
            )
        }

        let trigger = await waitForStop(on: attempt)
        return await resolveStoppedAttempt(
            trigger,
            attempt: attempt,
            configuration: configuration,
            consent: consent,
            credential: credential,
            progress: progress
        )
    }

    private func resolveStoppedAttempt(
        _ requestedTrigger: StopTrigger,
        attempt: Attempt,
        configuration: IOSForegroundVoiceWorkflowConfiguration,
        consent: IOSV1ProviderConsentObservation,
        credential: IOSForegroundVoiceWorkflowCredentialProof,
        progress: @escaping IOSForegroundVoiceClient.Progress
    ) async -> IOSForegroundVoiceResolution {
        var trigger = requestedTrigger
        if trigger == .done {
            let seconds = configuration.settings.voiceSessionPreferences
                .recordingStopTailDuration.duration
            if seconds > 0 {
                attempt.isStopTailOpen = true
                if let forced = await waitForTail(
                    .milliseconds(Int64(seconds * 1_000)),
                    attempt: attempt
                ) {
                    trigger = forced
                }
                attempt.isStopTailOpen = false
            }
            if let forced = attempt.forcedTrigger { trigger = forced }
        }
        attempt.hasEnteredFinalization = true

        attempt.maximumDurationTask?.cancel()
        attempt.maximumDurationTask = nil
        attempt.isListening = false
        let stopReason: IOSForegroundVoiceWorkflowCaptureStopReason = switch trigger {
        case .done: .done
        case .explicitDiscard: .cancelled
        case .interrupted: .interrupted
        case .maximumDuration: .maximumDuration
        }
        if trigger != .explicitDiscard { progress(.finalizing) }
        if trigger != .explicitDiscard {
            attempt.finalizationLease = dependencies.beginFinalization {
                [weak self, weak attempt] in
                guard let self, let attempt else { return }
                attempt.finalizationExpired = true
                self.requestStop(.interrupted, for: attempt)
            }
        }
        let result = await attempt.recording?.stop(stopReason) ?? .stale
        if let forced = attempt.forcedTrigger {
            trigger = forced
        }
        attempt.resolvedStopTrigger = trigger
        attempt.audioObservation?.cancel()
        attempt.audioObservation = nil

        switch result {
        case .completed(let capture):
            if attempt.finalizationExpired {
                finishFinalization(for: attempt)
                deactivateAudio(for: attempt)
                capture.release()
                return IOSForegroundVoiceResolution(
                    observation: await repairAndObserveInterruptedCapture(),
                    stage: .recordingFinalization,
                    outcome: trigger == .interrupted ? .interrupted : nil,
                    failure: .localRecovery
                )
            }
            guard let providerFinishTrigger = attempt.providerFinishTrigger else {
                finishFinalization(for: attempt)
                deactivateAudio(for: attempt)
                capture.release()
                let observation = await repairAndObserveInterruptedCapture()
                return IOSForegroundVoiceResolution(
                    observation: observation,
                    stage: .recordingFinalization,
                    outcome: trigger == .interrupted ? .interrupted : nil,
                    failure: nil
                )
            }
            if trigger == .done || trigger == .maximumDuration {
                await dependencies.playStopBoundary(
                    configuration.settings.voiceSessionPreferences
                        .audioCuesEnabled
                )
            }
            if attempt.finalizationExpired
                || !allowsProviderContinuation(for: attempt) {
                capture.release()
                finishFinalization(for: attempt)
                deactivateAudio(for: attempt)
                return IOSForegroundVoiceResolution(
                    observation: await repairAndObserveInterruptedCapture(),
                    stage: .recordingFinalization,
                    outcome: attempt.forcedTrigger == .interrupted
                        ? .interrupted
                        : nil,
                    failure: .localRecovery
                )
            }
            retainAudioForKeyboardWarmReuseOrDeactivate(for: attempt)
            let pending: IOSV1PendingRecording
            do {
                pending = try await capture.preparePending(
                    transcriptionConfiguration:
                        configuration.settings.transcriptionConfiguration,
                    acceptedAudioRetention: IOSAcceptedAudioRetention.resolved(
                        requested: providerFinishTrigger == .maximumDuration
                            ? .savedFiveMinute
                            : .recordingCachePolicy,
                        finalizedDurationMilliseconds:
                            capture.durationMilliseconds,
                        recordingDurationLimit:
                            configuration.settings.voiceSessionPreferences
                                .recordingDurationLimit
                    )
                )
            } catch {
                capture.release()
                finishFinalization(for: attempt)
                return IOSForegroundVoiceResolution(
                    observation: await observeDurableTerminalState(),
                    stage: .recordingFinalization,
                    failure: .localRecovery
                )
            }
            capture.release()
            let finalizationExpired = attempt.finalizationExpired
            finishFinalization(for: attempt)
            guard !finalizationExpired,
                  canContinueProvider(for: attempt) else {
                return IOSForegroundVoiceResolution(
                    observation: await observeDurableTerminalState(),
                    stage: .recordingFinalization,
                    outcome: attempt.forcedTrigger == .interrupted
                        ? .interrupted
                        : .recoverableFailure,
                    failure: .localRecovery
                )
            }
            guard canContinueProvider(for: attempt),
                  await dependencies.revalidateConsent(consent),
                  canContinueProvider(for: attempt),
                  await dependencies.revalidateCredential(credential),
                  canContinueProvider(for: attempt) else {
                return IOSForegroundVoiceResolution(
                    observation: await observeDurableTerminalState(),
                    stage: .recordingFinalization,
                    outcome: .recoverableFailure,
                    failure: .localRecovery
                )
            }
            return await runProcessor(
                IOSForegroundVoiceWorkflowProcessingRequest(
                    pendingRecording: pending,
                    mode: .initial,
                    configuration: configuration,
                    credential: credential,
                    consentObservation: consent,
                    forcesTextCorrection: pending.forcesTextCorrection,
                    draftInsertionMode: pending.draftInsertionMode
                ),
                attempt: attempt,
                progress: progress
            )
        case .discarded:
            finishFinalization(for: attempt)
            deactivateAudio(for: attempt)
            return IOSForegroundVoiceResolution(
                observation: await observeDurableTerminalState(),
                stage: nil,
                outcome: trigger == .interrupted ? .interrupted : nil,
                failure: nil
            )
        case .invalid(let reason):
            finishFinalization(for: attempt)
            deactivateAudio(for: attempt)
            return IOSForegroundVoiceResolution(
                observation: await observeDurableTerminalState(),
                stage: nil,
                outcome: trigger == .interrupted ? .interrupted : nil,
                failure: failure(for: reason)
            )
        case .preserved:
            finishFinalization(for: attempt)
            deactivateAudio(for: attempt)
            return IOSForegroundVoiceResolution(
                observation: await repairAndObserveInterruptedCapture(),
                stage: .recordingFinalization,
                outcome: trigger == .interrupted ? .interrupted : nil,
                failure: .localRecovery
            )
        case .stale:
            finishFinalization(for: attempt)
            deactivateAudio(for: attempt)
            return IOSForegroundVoiceResolution(
                observation: await observeDurableTerminalState(),
                stage: .recordingFinalization,
                outcome: trigger == .interrupted ? .interrupted : nil,
                failure: .localRecovery
            )
        }
    }

    private func runRetryPending(
        progress: @escaping IOSForegroundVoiceClient.Progress
    ) async -> IOSForegroundVoiceResolution {
        let expectedPending = pendingObservation
        let registry = dependencies.sceneRegistry
        let authority = IOSForegroundVoiceRetryAuthority()
        guard activeRetryAuthority == nil else {
            return Self.busyResolution
        }
        activeRetryAuthority = authority
        let observation = registry.observeEvents { event in
            guard registry.validate(event) else { return }
            if event.kind == .lastActiveSceneLost(.voiceWorkMustStop) {
                authority.terminate()
            }
        }
        defer {
            observation.cancel()
            if activeRetryAuthority === authority {
                activeRetryAuthority = nil
            }
        }
        if !registry.snapshot.isForegroundActive { authority.terminate() }

        return await withTaskCancellationHandler {
            await performRetryPending(
                expectedPending: expectedPending,
                authority: authority,
                registry: registry,
                progress: progress
            )
        } onCancel: {
            authority.terminate()
        }
    }

    private func performRetryPending(
        expectedPending: IOSV1PendingRecordingObservation?,
        authority: IOSForegroundVoiceRetryAuthority,
        registry: IOSVoiceSceneRegistry,
        progress: @escaping IOSForegroundVoiceClient.Progress
    ) async -> IOSForegroundVoiceResolution {
        guard retryCanContinue(authority, registry: registry) else {
            return pendingRetryLossResolution()
        }
        guard let expectedPending,
              expectedPending.availability == .available,
              expectedPending.recording.phase == .readyForTranscription
                || expectedPending.recording.phase == .failed else {
            return await pendingRetryPreflightResolution(
                failure: .localRecovery,
                authority: authority,
                registry: registry
            )
        }

        // Canonical Pending is the first async read. Cached observation state
        // never authorizes provider dispatch.
        let pending: IOSV1PendingRecordingObservation
        do {
            guard let current = try await dependencies.loadPending() else {
                return await pendingRetryPreflightResolution(
                    failure: .localRecovery,
                    authority: authority,
                    registry: registry
                )
            }
            pending = current
        } catch {
            return await pendingRetryPreflightResolution(
                failure: .localRecovery,
                authority: authority,
                registry: registry
            )
        }
        guard retryCanContinue(authority, registry: registry),
              pending == expectedPending,
              pending.availability == .available,
              pending.recording.phase == .readyForTranscription
                || pending.recording.phase == .failed else {
            return await pendingRetryPreflightResolution(
                failure: .localRecovery,
                authority: authority,
                registry: registry
            )
        }

        if retryProviderRequirementBeforeConfiguration(
            for: pending.recording
        ) == .blocked {
            return await pendingRetryPreflightResolution(
                failure: .localRecovery,
                authority: authority,
                registry: registry
            )
        }

        let configuration: IOSForegroundVoiceWorkflowConfiguration
        switch await configurationLoader.load(
            pending.recording.outputIntent,
            validateProviderSettings: false,
            continueIf: {
                retryCanContinue(authority, registry: registry)
            }
        ) {
        case .available(let value):
            configuration = value
        case .settingsUnavailable, .libraryUnavailable:
            return await pendingRetryPreflightResolution(
                failure: .localRecovery,
                authority: authority,
                registry: registry
            )
        case .invalid(let destination):
            return await pendingRetryPreflightResolution(
                setup: .needsSetup(destination),
                failure: .unavailable,
                authority: authority,
                registry: registry
            )
        }
        guard retryCanContinue(authority, registry: registry) else {
            return pendingRetryLossResolution()
        }
        let providerRequirement = retryProviderRequirement(
            for: pending.recording,
            configuration: configuration
        )
        guard providerRequirement != .blocked else {
            return await pendingRetryPreflightResolution(
                failure: .localRecovery,
                authority: authority,
                registry: registry
            )
        }
        if providerRequirement == .required,
           let destination = configurationLoader
               .invalidProviderConfigurationDestination(
                   pending.recording.outputIntent,
                   configuration: configuration
               ) {
            return await pendingRetryPreflightResolution(
                setup: .needsSetup(destination),
                failure: .unavailable,
                authority: authority,
                registry: registry
            )
        }
        let consent: IOSV1ProviderConsentObservation?
        let credential: IOSForegroundVoiceWorkflowCredentialProof?
        if providerRequirement == .required {
            switch await resolveConsentWithoutPresentation() {
            case .accepted(let value):
                consent = value
            case .needsSetup:
                return await pendingRetryPreflightResolution(
                    setup: .needsSetup(.microphoneAndPrivacy),
                    failure: nil,
                    authority: authority,
                    registry: registry
                )
            case .unavailable:
                return await pendingRetryPreflightResolution(
                    failure: .localRecovery,
                    authority: authority,
                    registry: registry
                )
            }
            guard retryCanContinue(authority, registry: registry) else {
                return pendingRetryLossResolution()
            }
            switch await dependencies.resolveCredential() {
            case .available(let value):
                credential = value
            case .needsSetup:
                return await pendingRetryPreflightResolution(
                    setup: .needsSetup(.openAI),
                    failure: nil,
                    authority: authority,
                    registry: registry
                )
            case .unavailable:
                return await pendingRetryPreflightResolution(
                    setup: .needsSetup(.openAI),
                    failure: .credentialUnavailable,
                    authority: authority,
                    registry: registry
                )
            }
            guard retryCanContinue(authority, registry: registry) else {
                return pendingRetryLossResolution()
            }
            guard let consent,
                  await dependencies.revalidateConsent(consent),
                  retryCanContinue(authority, registry: registry) else {
                return await pendingRetryPreflightResolution(
                    failure: .unavailable,
                    authority: authority,
                    registry: registry
                )
            }
            guard let credential,
                  await dependencies.revalidateCredential(credential),
                  retryCanContinue(authority, registry: registry) else {
                return await pendingRetryPreflightResolution(
                    setup: .needsSetup(.openAI),
                    failure: .credentialUnavailable,
                    authority: authority,
                    registry: registry
                )
            }
        } else {
            consent = nil
            credential = nil
        }

        // Immediately before dispatch, prove the exact Pending and the frozen
        // Settings/Library snapshot still match canonical storage.
        let currentConfiguration: IOSForegroundVoiceWorkflowConfiguration
        switch await configurationLoader.load(
            pending.recording.outputIntent,
            validateProviderSettings: false,
            continueIf: {
                retryCanContinue(authority, registry: registry)
            }
        ) {
        case .available(let value):
            currentConfiguration = value
        case .settingsUnavailable, .libraryUnavailable:
            return await pendingRetryPreflightResolution(
                failure: .localRecovery,
                authority: authority,
                registry: registry
            )
        case .invalid(let destination):
            return await pendingRetryPreflightResolution(
                setup: .needsSetup(destination),
                failure: .unavailable,
                authority: authority,
                registry: registry
            )
        }
        if providerRequirement == .required,
           let destination = configurationLoader
               .invalidProviderConfigurationDestination(
                   pending.recording.outputIntent,
                   configuration: currentConfiguration
               ) {
            return await pendingRetryPreflightResolution(
                setup: .needsSetup(destination),
                failure: .unavailable,
                authority: authority,
                registry: registry
            )
        }
        guard retryCanContinue(authority, registry: registry),
              currentConfiguration.settings == configuration.settings,
              currentConfiguration.library == configuration.library else {
            return await pendingRetryPreflightResolution(
                failure: .localRecovery,
                authority: authority,
                registry: registry
            )
        }
        do {
            guard let currentPending = try await dependencies.loadPending(),
                  currentPending == pending,
                  retryCanContinue(authority, registry: registry) else {
                return await pendingRetryPreflightResolution(
                    failure: .localRecovery,
                    authority: authority,
                    registry: registry
                )
            }
        } catch {
            return await pendingRetryPreflightResolution(
                failure: .localRecovery,
                authority: authority,
                registry: registry
            )
        }
        if let consent {
            guard await dependencies.revalidateConsent(consent),
                  retryCanContinue(authority, registry: registry) else {
                return await pendingRetryPreflightResolution(
                    failure: .unavailable,
                    authority: authority,
                    registry: registry
                )
            }
        }
        if let credential {
            guard await dependencies.revalidateCredential(credential),
                  retryCanContinue(authority, registry: registry) else {
                return await pendingRetryPreflightResolution(
                    failure: .unavailable,
                    authority: authority,
                    registry: registry
                )
            }
        }
        do {
            guard let dispatchPending = try await dependencies.loadPending(),
                  dispatchPending == pending,
                  retryCanContinue(authority, registry: registry) else {
                return await pendingRetryPreflightResolution(
                    failure: .localRecovery,
                    authority: authority,
                    registry: registry
                )
            }
        } catch {
            return await pendingRetryPreflightResolution(
                failure: .localRecovery,
                authority: authority,
                registry: registry
            )
        }

        return await runAggregateProcessor(
            IOSForegroundVoiceWorkflowProcessingRequest(
                pendingRecording: pending.recording,
                mode: .retry,
                configuration: configuration,
                credential: credential,
                consentObservation: consent,
                forcesTextCorrection: pending.recording.forcesTextCorrection,
                draftInsertionMode: pending.recording.draftInsertionMode,
                cancellationAuthority:
                    authority.processingCancellationAuthority
            ),
            authority: authority,
            registry: registry,
            progress: progress
        )
    }

    private func retryProviderRequirement(
        for recording: IOSV1PendingRecording,
        configuration: IOSForegroundVoiceWorkflowConfiguration
    ) -> IOSForegroundVoiceRetryProviderRequirement {
        guard let stage = recording.textCheckpointStage else {
            return recording.transcriptionReplayBlocked ? .blocked : .required
        }
        return switch stage {
        case .outputReady:
            IOSForegroundVoiceRetryProviderRequirement.none
        case .translationInFlight:
            .blocked
        case .translationReady:
            .required
        case .correctionInFlight:
            recording.outputIntent == .translate
                ? .required : IOSForegroundVoiceRetryProviderRequirement.none
        case .transcriptionAccepted:
            recording.outputIntent == .translate
                || recording.forcesTextCorrection
                || configuration.settings.textCorrectionConfiguration.isEnabled
                ? .required : .none
        }
    }

    private func retryProviderRequirementBeforeConfiguration(
        for recording: IOSV1PendingRecording
    ) -> IOSForegroundVoiceRetryProviderRequirement? {
        guard let stage = recording.textCheckpointStage else {
            return recording.transcriptionReplayBlocked ? .blocked : .required
        }
        return switch stage {
        case .outputReady:
            IOSForegroundVoiceRetryProviderRequirement.none
        case .translationInFlight:
            .blocked
        case .translationReady:
            .required
        case .correctionInFlight:
            recording.outputIntent == .translate
                ? .required : IOSForegroundVoiceRetryProviderRequirement.none
        case .transcriptionAccepted:
            recording.outputIntent == .translate
                || recording.forcesTextCorrection ? .required : nil
        }
    }

    private func runRecoverRecording() async -> IOSForegroundVoiceResolution {
        guard let attemptID = captureRecoveryAttemptID,
              let settings = try? await dependencies.loadSettings(),
              !settings.transcriptionConfiguration
                .customLanguageCodeValidation.isInvalid else {
            return await blockedPreflight(failure: .localRecovery)
        }
        do {
            _ = try await dependencies.recoverCapture(
                attemptID,
                settings.transcriptionConfiguration
            )
            return IOSForegroundVoiceResolution(
                observation: await observeDurableTerminalState(),
                stage: .recordingFinalization
            )
        } catch {
            return IOSForegroundVoiceResolution(
                observation: await observeDurableTerminalState(),
                stage: .recordingFinalization,
                failure: .localRecovery
            )
        }
    }

    private func runDiscard() async -> IOSForegroundVoiceResolution {
        do {
            if let attemptID = captureRecoveryAttemptID {
                try await dependencies.discardCapture(attemptID)
            } else if let pending = pendingObservation {
                _ = try await dependencies.discardPending(
                    pending.expectation
                )
            } else {
                return await blockedPreflight(failure: .localRecovery)
            }
            return IOSForegroundVoiceResolution(
                observation: await observe(),
                stage: .recordingFinalization
            )
        } catch {
            return IOSForegroundVoiceResolution(
                observation: await observe(),
                stage: .recordingFinalization,
                failure: .localRecovery
            )
        }
    }

    private func mapProcessing(
        _ resolution: IOSForegroundVoiceProcessingResolution
    ) async -> IOSForegroundVoiceResolution {
        switch resolution {
        case .acceptance(let acceptance):
            if case .resultReady(let record, _) = acceptance,
               let attempt = activeAttempt,
               let recordingAttemptID = attempt.recordingAttemptID,
               record.sourceAttemptID == recordingAttemptID,
               case .keyboard(let requestID) = attempt.origin {
                acceptedKeyboardResult = (
                    requestID: requestID,
                    text: record.acceptedText
                )
            }
            return await mapAcceptance(acceptance)
        case .retryAvailable(let recording, let failure, let stage):
            return IOSForegroundVoiceResolution(
                observation: await observe(),
                stage: stage,
                outcome: .recoverableFailure,
                failure: map(failure),
                transcriptionReplayBlocked:
                    recording.transcriptionReplayBlocked
            )
        case .notStarted(let failure):
            return IOSForegroundVoiceResolution(
                observation: await observe(),
                failure: map(failure)
            )
        case .busy:
            return Self.busyResolution
        }
    }

    private func runProcessor(
        _ request: IOSForegroundVoiceWorkflowProcessingRequest,
        attempt: Attempt,
        progress: @escaping IOSForegroundVoiceClient.Progress
    ) async -> IOSForegroundVoiceResolution {
        guard canContinueProvider(for: attempt) else {
            return IOSForegroundVoiceResolution(
                observation: await observeDurableTerminalState(),
                stage: .recordingFinalization,
                outcome: .recoverableFailure,
                failure: .localRecovery
            )
        }
        dependencies.recordDiagnostic(
            .providerStarted(Self.diagnosticProviderMode(request.mode))
        )
        attempt.processingCancellationAuthority =
            request.cancellationAuthority
        let process = dependencies.process
        let task = Task {
            return await process(request) { stage in
                guard !Task.isCancelled,
                      self.activeAttempt === attempt,
                      self.allowsProviderContinuation(for: attempt),
                      self.canContinueProvider(for: attempt) else {
                    return
                }
                progress(.processing(stage))
            }
        }
        attempt.providerTask = task
        let result = await task.value
        dependencies.recordDiagnostic(
            .providerCompleted(Self.diagnosticOutcome(result))
        )
        attempt.providerTask = nil
        guard canContinueProvider(for: attempt) else {
            return IOSForegroundVoiceResolution(
                observation: await observeDurableTerminalState(),
                stage: .recordingFinalization,
                outcome: .recoverableFailure,
                failure: .localRecovery
            )
        }
        return await mapProcessing(result)
    }

    private func runAggregateProcessor(
        _ request: IOSForegroundVoiceWorkflowProcessingRequest,
        authority: IOSForegroundVoiceRetryAuthority,
        registry: IOSVoiceSceneRegistry,
        progress: @escaping IOSForegroundVoiceClient.Progress
    ) async -> IOSForegroundVoiceResolution {
        guard retryCanContinue(authority, registry: registry) else {
            return pendingRetryLossResolution()
        }
        dependencies.recordDiagnostic(
            .providerStarted(Self.diagnosticProviderMode(request.mode))
        )
        let process = dependencies.process
        let operation = Task {
            guard authority.canContinue, !Task.isCancelled else {
                return IOSForegroundVoiceProcessingResolution.notStarted(
                    .cancelled
                )
            }
            return await process(request) { stage in
                guard authority.canContinue,
                      !Task.isCancelled,
                      registry.snapshot.isForegroundActive else {
                    return
                }
                progress(.processing(stage))
            }
        }
        guard authority.install(operation) else {
            return pendingRetryLossResolution()
        }
        let result = await operation.value
        dependencies.recordDiagnostic(
            .providerCompleted(Self.diagnosticOutcome(result))
        )
        authority.clearChild()
        guard retryCanContinue(authority, registry: registry) else {
            return await pendingRetryDurableCancellationResolution()
        }
        return await mapProcessing(result)
    }

    private func retryCanContinue(
        _ authority: IOSForegroundVoiceRetryAuthority,
        registry: IOSVoiceSceneRegistry
    ) -> Bool {
        authority.canContinue
            && !Task.isCancelled
            && registry.snapshot.isForegroundActive
    }

    private func pendingRetryLossResolution() ->
        IOSForegroundVoiceResolution {
        IOSForegroundVoiceResolution(
            observation: IOSForegroundVoiceObservation(
                setup: passiveSetup,
                recovery: .pendingRetryOrDiscard,
                stage: .transcription,
                translationAvailable: translationIsAvailable
            ),
            stage: .transcription,
            outcome: .recoverableFailure,
            failure: .localRecovery
        )
    }

    private func pendingRetryDurableCancellationResolution() async ->
        IOSForegroundVoiceResolution {
        let observation = await observeDurableTerminalState()
        return IOSForegroundVoiceResolution(
            observation: observation,
            stage: observation.stage,
            outcome: observation.recovery == .pendingRetryOrDiscard
                ? .recoverableFailure : nil,
            failure: .localRecovery,
            transcriptionReplayBlocked: observation.recovery == .blocked
        )
    }

    private func pendingRetryPreflightResolution(
        setup: IOSForegroundVoiceSetup = .unavailable,
        failure: IOSForegroundVoiceFailure?,
        authority: IOSForegroundVoiceRetryAuthority,
        registry: IOSVoiceSceneRegistry
    ) async -> IOSForegroundVoiceResolution {
        guard retryCanContinue(authority, registry: registry) else {
            return pendingRetryLossResolution()
        }
        let current = await observeDurableTerminalState()
        guard retryCanContinue(authority, registry: registry) else {
            return pendingRetryLossResolution()
        }
        return IOSForegroundVoiceResolution(
            observation: IOSForegroundVoiceObservation(
                setup: setup,
                recovery: current.recovery,
                stage: current.stage,
                translationAvailable: current.translationAvailable
            ),
            stage: current.stage,
            failure: failure
        )
    }

    private func mapAcceptance(
        _ acceptance: IOSV1ForegroundVoiceAcceptanceResult
    ) async -> IOSForegroundVoiceResolution {
        let observation = await observe()
        switch acceptance {
        case .resultReady(_, let notice):
            return IOSForegroundVoiceResolution(
                observation: observation,
                outcome: .resultReady,
                warning: map(notice)
            )
        }
    }

    private func map(
        _ notice: IOSV1ForegroundVoiceAcceptanceNotice?
    ) -> IOSForegroundVoiceWarning? {
        switch notice {
        case nil:
            nil
        case .historyWriteFailed:
            .historySaveFailed
        case .localCleanupPending,
             .historyWriteFailedAndLocalCleanupPending:
            .localCleanupPending
        }
    }

    private func hasNoDurableRecoveryOwner() async -> Bool {
        let observation = await observe(includeConfiguration: false)
        return observation.recovery == .none
    }

    /// Terminal reconciliation must outlive cancellation of the operation
    /// task; otherwise a cancelled persistence read can manufacture `.blocked`
    /// and hide the exact durable source (or invent one after a clean discard).
    private func observeDurableTerminalState() async
        -> IOSForegroundVoiceObservation {
        let task = Task.detached { @MainActor [weak self] in
            guard let self else { return Self.unavailableObservation }
            return await self.observe()
        }
        return await task.value
    }

    private func repairAndObserveInterruptedCapture() async
        -> IOSForegroundVoiceObservation {
        let task = Task.detached { @MainActor [weak self] in
            guard let self else { return Self.unavailableObservation }
            let repaired = await self.dependencies
                .repairInterruptedCaptureAfterRecorderStops()
            if case .some(.recoverable) = repaired {
                await self.interruptedCaptureDidBecomeRecoverable()
            }
            return await self.observe()
        }
        return await task.value
    }

    private func resolveConsent(
        for attempt: Attempt
    ) async -> ConsentResolution {
        if attempt.allowsBackgroundContinuation {
            return await resolveConsentWithoutPresentation()
        }
        guard let sceneLease = attempt.sceneLease else {
            return .unavailable
        }
        return await resolveConsent(sceneLease: sceneLease)
    }

    private func resolveConsent(
        sceneLease: IOSVoiceSceneStartLease
    ) async -> ConsentResolution {
        let observed = await dependencies.observeConsent()
        if observed.status == .acceptedCurrentDisclosure,
           await dependencies.revalidateConsent(observed) {
            return .accepted(observed)
        }
        switch observed.status {
        case .localDataUnavailable, .mutationNotSaved:
            return .unavailable
        case .notReviewed, .reviewRequired, .withdrawn,
             .acceptedCurrentDisclosure:
            break
        }
        guard dependencies.sceneRegistry.validateContinuation(sceneLease)
                == .ready,
              let accepted = await dependencies.continueConsent(
                  sceneLease,
                  observed
              ) else {
            return dependencies.sceneRegistry.validateContinuation(sceneLease)
                == .ready ? .needsSetup : .unavailable
        }
        guard accepted.status == .acceptedCurrentDisclosure,
              dependencies.sceneRegistry.validateContinuation(sceneLease)
                == .ready else {
            return .needsSetup
        }
        guard await dependencies.revalidateConsent(accepted) else {
            return .needsSetup
        }
        return .accepted(accepted)
    }

    private func resolveConsentWithoutPresentation() async
        -> ConsentResolution {
        let observed = await dependencies.observeConsent()
        guard observed.status == .acceptedCurrentDisclosure else {
            return observed.status == .localDataUnavailable
                || observed.status == .mutationNotSaved
                ? .unavailable
                : .needsSetup
        }
        guard await dependencies.revalidateConsent(observed) else {
            return .needsSetup
        }
        return .accepted(observed)
    }

    private func resolvePermission(
        for attempt: Attempt
    ) async -> PermissionResolution {
        let status = dependencies.permission.read()
        switch status {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .unavailable:
            return .unavailable
        case .undetermined:
            guard !attempt.allowsBackgroundContinuation,
                  let sceneLease = attempt.sceneLease else {
                return .stale
            }
            guard dependencies.sceneRegistry
                .beginExpectedMicrophonePermissionPrompt(
                    sceneLease
                ) else {
                return .stale
            }
            let outcome = await dependencies.permission
                .requestIfUndetermined()

            switch outcome {
            case .timedOut:
                _ = dependencies.sceneRegistry
                    .microphonePermissionPromptDidReturn(sceneLease)
                return .timedOut
            case .cancelled:
                _ = dependencies.sceneRegistry
                    .microphonePermissionPromptDidReturn(sceneLease)
                return .cancelled
            case .unavailable:
                _ = dependencies.sceneRegistry
                    .microphonePermissionPromptDidReturn(sceneLease)
                return .unavailable
            case .granted, .denied:
                break
            }

            var validation = dependencies.sceneRegistry
                .microphonePermissionPromptDidReturn(sceneLease)
            if validation == .awaitingInitiatingSceneReactivation {
                validation = await dependencies.sceneRegistry
                    .waitUntilInitiatingSceneActive(sceneLease)
            }
            guard validation == .ready,
                  !Task.isCancelled,
                  attempt.forcedTrigger == nil else {
                return .stale
            }
            switch outcome {
            case .granted:
                return dependencies.permission.read() == .granted
                    ? .granted
                    : .unavailable
            case .denied:
                return .denied
            case .unavailable, .timedOut, .cancelled:
                return .stale
            }
        }
    }

    private func revalidate(
        attempt: Attempt,
        intent: DictationOutputIntent,
        configuration: IOSForegroundVoiceWorkflowConfiguration,
        consent: IOSV1ProviderConsentObservation,
        credential: IOSForegroundVoiceWorkflowCredentialProof,
        requireGrantedPermission: Bool,
        requireNoDurableOwner: Bool = true
    ) async -> Bool {
        guard canContinueArming(
            attempt,
            requireInitiatingScene: attempt.requiresInitiatingScene
        ) else {
            return false
        }
        if requireNoDurableOwner,
           !(await hasNoDurableRecoveryOwner()) {
            return false
        }
        guard canContinueArming(
            attempt,
            requireInitiatingScene: attempt.requiresInitiatingScene
        ) else { return false }
        let current: IOSForegroundVoiceWorkflowConfiguration
        switch await configurationLoader.load(
            intent,
            continueIf: { [weak self, weak attempt] in
                guard let self, let attempt else { return false }
                return self.canContinueArming(
                    attempt,
                    requireInitiatingScene: attempt.requiresInitiatingScene
                )
            }
        ) {
        case .available(let value):
            current = value
        case .settingsUnavailable, .libraryUnavailable, .invalid:
            return false
        }
        guard current.settings == configuration.settings,
              current.library == configuration.library,
              canContinueArming(
                attempt,
                requireInitiatingScene: attempt.requiresInitiatingScene
              ),
              await dependencies.revalidateConsent(consent),
              canContinueArming(
                attempt,
                requireInitiatingScene: attempt.requiresInitiatingScene
              ),
              await dependencies.revalidateCredential(credential),
              canContinueArming(
                attempt,
                requireInitiatingScene: attempt.requiresInitiatingScene
              ) else {
            return false
        }
        return !requireGrantedPermission
            || dependencies.permission.read() == .granted
    }

    private func deactivateAudio(for attempt: Attempt) {
        let hadAudio = attempt.audio != nil
        attempt.audioObservation?.cancel()
        attempt.audioObservation = nil
        attempt.audio?.deactivate()
        attempt.audio = nil
        if hadAudio {
            dependencies.recordDiagnostic(.audio(.deactivated))
        }
    }

    /// iOS rejects a new audio-session activation initiated after the app has
    /// returned to the background. A successful keyboard capture therefore
    /// keeps its already-active lease until the bounded keyboard session ends.
    /// Foreground Voice never enters this path and keeps its existing cleanup.
    private func retainAudioForKeyboardWarmReuseOrDeactivate(
        for attempt: Attempt
    ) {
        guard attempt.allowsBackgroundContinuation,
              keyboardWarmInputIsRunning,
              let audio = attempt.audio else {
            deactivateAudio(for: attempt)
            return
        }
        keyboardWarmAudio?.deactivate()
        keyboardWarmAudio = audio
        attempt.audio = nil
    }

    private func endKeyboardWarmSession() {
        if keyboardWarmInputIsRunning {
            dependencies.endKeyboardWarmInput()
            keyboardWarmInputIsRunning = false
        }
        let hadWarmAudio = keyboardWarmAudio != nil
        keyboardWarmAudio?.deactivate()
        keyboardWarmAudio = nil
        if hadWarmAudio {
            dependencies.recordDiagnostic(.audio(.deactivated))
        }
    }

    private func finishFinalization(for attempt: Attempt) {
        attempt.finalizationLease?.finish()
        attempt.finalizationLease = nil
    }

    private func waitForStop(on attempt: Attempt) async -> StopTrigger {
        if let pending = attempt.pendingTrigger {
            attempt.pendingTrigger = nil
            return pending
        }
        return await withCheckedContinuation { continuation in
            attempt.stopContinuation = continuation
        }
    }

    private func requestStop(_ trigger: StopTrigger, for attempt: Attempt) {
        guard activeAttempt === attempt else { return }
        if trigger == .done || trigger == .maximumDuration {
            // Finish/limit authority is first-writer-wins. A late callback may
            // not convert an already claimed interruption, teardown, or
            // explicit Discard into an automatic provider upload.
            if trigger == .maximumDuration,
               attempt.providerFinishTrigger == .done,
               attempt.isStopTailOpen,
               attempt.forcedTrigger == nil {
                // The frozen configured limit may preempt an already-owned
                // Done tail and upgrades retention without creating a second
                // provider authority.
                attempt.providerFinishTrigger = .maximumDuration
            } else {
                guard attempt.providerFinishTrigger == nil,
                      attempt.forcedTrigger == nil,
                      attempt.pendingTrigger == nil,
                      !attempt.hasEnteredFinalization else {
                    return
                }
                attempt.providerFinishTrigger = trigger
            }
        }
        if attempt.pendingTrigger == nil,
           attempt.forcedTrigger == nil {
            dependencies.recordDiagnostic(
                .voiceStopRequested(Self.diagnosticStopReason(trigger))
            )
        }
        switch trigger {
        case .done:
            break
        case .explicitDiscard:
            // Explicit Discard is the only post-start authority that may
            // revoke an already accepted Done/maximum provider handoff.
            attempt.forcedTrigger = .explicitDiscard
        case .interrupted:
            if attempt.forcedTrigger == nil {
                attempt.forcedTrigger = trigger
            }
        case .maximumDuration:
            if attempt.forcedTrigger == nil {
                attempt.forcedTrigger = trigger
            }
        }
        if let continuation = attempt.tailContinuation,
           trigger != .done {
            attempt.tailContinuation = nil
            attempt.tailTask?.cancel()
            attempt.tailTask = nil
            continuation.resume(returning: trigger)
        } else if let continuation = attempt.stopContinuation {
            attempt.stopContinuation = nil
            continuation.resume(returning: trigger)
        } else if attempt.pendingTrigger == nil {
            attempt.pendingTrigger = trigger
        }
        let revokesProvider = trigger == .explicitDiscard
            || (trigger == .interrupted
                && attempt.providerFinishTrigger == nil)
        if revokesProvider {
            attempt.providerTask?.cancel()
        }
    }

    private static func diagnosticOrigin(
        _ origin: Attempt.Origin
    ) -> IOSDiagnosticVoiceOrigin {
        switch origin {
        case .foreground:
            .foreground
        case .keyboard:
            .keyboard
        }
    }

    private static func diagnosticAction(
        intent: DictationOutputIntent,
        forcesTextCorrection: Bool
    ) -> IOSDiagnosticVoiceAction {
        if forcesTextCorrection && intent == .translate {
            return .translateAndImprove
        }
        if forcesTextCorrection { return .improve }
        return intent == .translate ? .translate : .standard
    }

    private static func diagnosticStopReason(
        _ trigger: StopTrigger
    ) -> IOSDiagnosticVoiceStopReason {
        switch trigger {
        case .done:
            .done
        case .explicitDiscard:
            .cancelled
        case .interrupted:
            .interrupted
        case .maximumDuration:
            .maximumDuration
        }
    }

    private static func diagnosticProviderMode(
        _ mode: IOSForegroundVoiceProcessingMode
    ) -> IOSDiagnosticProviderMode {
        switch mode {
        case .initial:
            .initial
        case .retry:
            .retry
        }
    }

    private static func diagnosticDurability(
        _ recovery: IOSForegroundVoiceRecovery
    ) -> IOSDiagnosticVoiceDurability {
        switch recovery {
        case .none:
            .none
        case .captureRecoverOrDiscard:
            .recoverableCapture
        case .captureDiscardOnly:
            .discardOnlyCapture
        case .pendingRetryOrDiscard:
            .pendingRecording
        case .blocked:
            .blocked
        }
    }

    private static func diagnosticOutcome(
        _ resolution: IOSForegroundVoiceProcessingResolution
    ) -> IOSDiagnosticOutcome {
        switch resolution {
        case .acceptance:
            .succeeded
        case .notStarted(.cancelled):
            .cancelled
        case .notStarted(.timedOut):
            .timedOut
        case .notStarted, .retryAvailable:
            .failed
        case .busy:
            .unavailable
        }
    }

    private static func diagnosticOutcome(
        _ resolution: IOSForegroundVoiceResolution
    ) -> IOSDiagnosticOutcome {
        if resolution.failure == .microphonePermissionTimedOut {
            return .timedOut
        }
        if resolution.failure != nil { return .failed }
        return switch resolution.outcome {
        case .resultReady:
            .succeeded
        case .interrupted:
            .cancelled
        case .expired:
            .stale
        case .recoverableFailure:
            .failed
        case nil:
            .unavailable
        }
    }

    private func waitForTail(
        _ duration: Duration,
        attempt: Attempt
    ) async -> StopTrigger? {
        if let forced = attempt.forcedTrigger { return forced }
        let sleep = dependencies.sleep
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                attempt.tailContinuation = continuation
                attempt.tailTask = Task { @MainActor [weak attempt] in
                    do {
                        try await sleep(duration)
                    } catch {
                        guard !Task.isCancelled,
                              let attempt,
                              let continuation = attempt.tailContinuation else {
                            return
                        }
                        attempt.tailContinuation = nil
                        attempt.tailTask = nil
                        continuation.resume(returning: .interrupted)
                        return
                    }
                    guard let attempt,
                          let continuation = attempt.tailContinuation else {
                        return
                    }
                    attempt.tailContinuation = nil
                    attempt.tailTask = nil
                    continuation.resume(returning: nil)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self, weak attempt] in
                guard let self, let attempt else { return }
                self.requestStop(.interrupted, for: attempt)
            }
        }
    }

    private func scheduleMaximumDuration(
        for attempt: Attempt,
        limit: RecordingDurationLimit
    ) {
        let sleep = dependencies.sleep
        attempt.maximumDurationTask = Task { @MainActor [weak self, weak attempt] in
            do {
                try await sleep(.seconds(limit.wholeSeconds))
            } catch {
                guard !Task.isCancelled,
                      let self,
                      let attempt,
                      self.activeAttempt === attempt else {
                    return
                }
                self.requestStop(.interrupted, for: attempt)
                return
            }
            guard let self, let attempt else { return }
            self.requestStop(.maximumDuration, for: attempt)
        }
    }

    private func retire(_ attempt: Attempt) {
        guard activeAttempt === attempt else { return }
        attempt.maximumDurationTask?.cancel()
        attempt.maximumDurationTask = nil
        attempt.tailTask?.cancel()
        attempt.tailTask = nil
        attempt.tailContinuation?.resume(returning: .interrupted)
        attempt.tailContinuation = nil
        attempt.providerTask?.cancel()
        attempt.providerTask = nil
        finishFinalization(for: attempt)
        attempt.sceneObservation?.cancel()
        attempt.sceneObservation = nil
        attempt.audioObservation?.cancel()
        attempt.audioObservation = nil
        attempt.audio?.deactivate()
        attempt.audio = nil
        attempt.recordingObservation?.cancel()
        attempt.recordingObservation = nil
        activeAttempt = nil
    }

    private func canContinueProvider(for attempt: Attempt) -> Bool {
        activeAttempt === attempt
            && !attempt.processingCancellationRequested
            && (!Task.isCancelled
                || attempt.providerFinishTrigger != nil)
            && allowsProviderContinuation(for: attempt)
            && (attempt.providerFinishTrigger != nil
                || attempt.allowsBackgroundContinuation
                || dependencies.sceneRegistry.snapshot.isForegroundActive)
    }

    private func allowsProviderContinuation(for attempt: Attempt) -> Bool {
        !attempt.processingCancellationRequested
            && attempt.forcedTrigger != .explicitDiscard
            && (attempt.providerFinishTrigger != nil
            || attempt.forcedTrigger == nil
            || attempt.forcedTrigger == .maximumDuration)
    }

    private func canContinueArming(
        _ attempt: Attempt,
        requireInitiatingScene: Bool
    ) -> Bool {
        guard activeAttempt === attempt,
              !Task.isCancelled,
              attempt.forcedTrigger == nil else {
            return false
        }
        if attempt.allowsBackgroundContinuation {
            return !requireInitiatingScene
        }
        if attempt.hasStartedRecording {
            return true
        }
        guard dependencies.sceneRegistry.snapshot.isForegroundActive else {
            return false
        }
        guard requireInitiatingScene else { return true }
        guard let sceneLease = attempt.sceneLease else { return false }
        return dependencies.sceneRegistry.validateContinuation(sceneLease)
            == .ready
    }

    private func apply(
        _ durable: IOSForegroundVoiceWorkflowDurableObservation
    ) -> IOSForegroundVoiceObservation {
        captureRecoveryAttemptID = switch durable.capture {
        case .recoverable(let attemptID), .discardOnly(let attemptID):
            attemptID
        case .empty, .blocked:
            nil
        }
        pendingObservation = durable.pending

        let recovery = mapRecovery(
            capture: durable.capture,
            pending: durable.pending
        )
        return IOSForegroundVoiceObservation(
            setup: recovery == .blocked ? .unavailable : passiveSetup,
            recovery: recovery,
            stage: stage(for: durable.pending),
            translationAvailable: translationIsAvailable
        )
    }

    private func applyDurableFailure(
        capture: IOSV1ForegroundVoiceCaptureRecoveryObservation
    ) -> IOSForegroundVoiceObservation {
        captureRecoveryAttemptID = switch capture {
        case .recoverable(let attemptID), .discardOnly(let attemptID):
            attemptID
        case .empty, .blocked:
            nil
        }
        pendingObservation = nil
        let recovery: IOSForegroundVoiceRecovery = switch capture {
        case .recoverable:
            .captureRecoverOrDiscard
        case .discardOnly:
            .captureDiscardOnly
        case .empty, .blocked:
            .blocked
        }
        return IOSForegroundVoiceObservation(
            setup: .unavailable,
            recovery: recovery
        )
    }

    private func mapRecovery(
        capture: IOSV1ForegroundVoiceCaptureRecoveryObservation,
        pending: IOSV1PendingRecordingObservation?
    ) -> IOSForegroundVoiceRecovery {
        switch capture {
        case .recoverable:
            return .captureRecoverOrDiscard
        case .discardOnly:
            return .captureDiscardOnly
        case .blocked:
            return .blocked
        case .empty:
            break
        }

        guard let pending else { return .none }
        guard pending.availability == .available else { return .blocked }
        switch pending.recording.phase {
        case .readyForTranscription, .failed:
            return .pendingRetryOrDiscard
        case .transcribing, .postProcessing, .outputDelivery,
             .acceptedCleanup:
            return .blocked
        }
    }

    private func stage(
        for pending: IOSV1PendingRecordingObservation?
    ) -> VoiceAttemptStage? {
        guard let pending else { return nil }
        switch pending.recording.phase {
        case .readyForTranscription, .failed:
            return .transcription
        case .transcribing:
            return .transcription
        case .postProcessing:
            return .postProcessing
        case .outputDelivery, .acceptedCleanup:
            return .outputDelivery
        }
    }

    private func failure(
        for reason: IOSV1ForegroundVoiceCaptureInvalidReason
    ) -> IOSForegroundVoiceFailure {
        switch reason {
        case .tooShort, .empty: .tooShort
        case .maximumDurationReached: .maximumDuration
        case .invalidMedia: .operationFailed
        }
    }

    private func map(
        _ failure: IOSForegroundVoiceProcessingFailure
    ) -> IOSForegroundVoiceFailure {
        switch failure {
        case .localPersistence: .localRecovery
        case .invalidConfiguration, .providerConsentUnavailable,
             .credentialRejected, .networkUnavailable, .networkFailure,
             .timedOut, .providerUnavailable, .invalidRecording,
             .invalidResponse, .cancelled:
            .operationFailed
        }
    }

    private var translationIsAvailable: Bool {
        guard passiveSetup == .ready else { return false }
        return lastConfiguration?.settings.translationConfiguration
            .isConfigurationReady ?? false
    }

    private var passiveSetup: IOSForegroundVoiceSetup {
        if let passiveConfigurationSetupOverride {
            return passiveConfigurationSetupOverride
        }
        guard let settings = lastConfiguration?.settings else {
            return .unavailable
        }
        if settings.transcriptionConfiguration
            .customLanguageCodeValidation.isInvalid {
            return .needsSetup(.transcription)
        }
        return .ready
    }

    private func blockedPreflight(
        setup: IOSForegroundVoiceSetup? = nil,
        failure: IOSForegroundVoiceFailure?
    ) async -> IOSForegroundVoiceResolution {
        let current = await observe(includeConfiguration: false)
        return IOSForegroundVoiceResolution(
            observation: IOSForegroundVoiceObservation(
                setup: setup ?? passiveSetup,
                recovery: current.recovery,
                stage: current.stage,
                translationAvailable: current.translationAvailable
            ),
            failure: failure
        )
    }

    private static let unavailableObservation = IOSForegroundVoiceObservation(
        setup: .unavailable,
        recovery: .blocked
    )

    private static let unavailableResolution = IOSForegroundVoiceResolution(
        observation: unavailableObservation,
        failure: .unavailable
    )

    private static let busyResolution = IOSForegroundVoiceResolution(
        observation: IOSForegroundVoiceObservation(
            setup: .unavailable,
            recovery: .blocked
        )
    )
}

extension IOSForegroundVoiceWorkflow:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSForegroundVoiceWorkflow(<redacted>)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}
