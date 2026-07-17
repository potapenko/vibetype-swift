import Foundation
import HoldTypeDomain
import Observation
import UIKit

nonisolated enum IOSKeyboardHandoffCaptureEvent: Equatable, Sendable {
    case listening
    case processing
    case terminal(IOSKeyboardHandoffTerminalDisposition)
}

nonisolated enum IOSKeyboardHandoffTerminalDisposition: Equatable, Sendable {
    case completed
    case cancelled
    case failed
    case expired
}

@MainActor
struct IOSKeyboardDictationSessionDependencies {
    let workflow: IOSKeyboardDictationWorkflowClient
    let supersession: IOSKeyboardHandoffSupersessionClient
    let permission: IOSForegroundVoiceWorkflowPermissionClient
    let loadCommand: (Date) throws -> KeyboardDictationCommandRecord?
    let loadState: (Date) throws -> KeyboardDictationStateRecord?
    let saveState: (KeyboardDictationStateRecord) throws -> Void
    let postStateChanged: () -> Void
    let applicationIsActive: () -> Bool
    let beginBackgroundTask: (
        @escaping @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier
    let endBackgroundTask: (UIBackgroundTaskIdentifier) -> Void
    let scheduleExpiry: (
        Date,
        @escaping @MainActor () -> Void
    ) -> Timer?
    let now: () -> Date
    let makeUUID: () -> UUID
}

/// The bounded keyboard command adapter for the one process-owned Voice
/// workflow. It owns no recorder, provider, accepted-text persistence, or
/// recovery state.
@MainActor
@Observable
final class IOSKeyboardDictationSessionCoordinator {
    enum Presentation: Equatable {
        case stopped
        case preparing
        case ready(Date)
        case listening(Date)
        case processing
        case resultReady
        case failed(String)

        var title: String {
            switch self {
            case .stopped:
                return "Stopped"
            case .preparing:
                return "Preparing…"
            case .ready:
                return "Ready for HoldType Keyboard"
            case .listening:
                return "Listening…"
            case .processing:
                return "Processing…"
            case .resultReady:
                return "Result sent to keyboard"
            case let .failed(message):
                return message
            }
        }

        var allowsSessionExpiry: Bool {
            switch self {
            case .ready, .resultReady:
                true
            case .stopped, .preparing, .listening, .processing, .failed:
                false
            }
        }
    }

    private(set) var presentation: Presentation = .stopped

    private let dependencies: IOSKeyboardDictationSessionDependencies
    private var commandObserver: KeyboardDictationBridgeObserver?
    private var sessionID: UUID?
    private var activeAttempt: KeyboardDictationAttemptIdentity?
    private var deadline: Date?
    private var expiryTimer: Timer?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var lastHandledCommand: KeyboardDictationCommandRecord?
    private var workflowTask: Task<Void, Never>?
    private var workflowGeneration: UInt64 = 0
    private var sessionStopRequested = false
    private var translationAvailable = false
    private var acceptedResult: String?
    private var deliveryClaimID: UUID?
    private var handoffRequestID: UUID?
    private var handoffEventObserver:
        (@MainActor @Sendable (
            UUID,
            IOSKeyboardHandoffCaptureEvent
        ) -> Void)?

    convenience init(
        workflow: IOSKeyboardDictationWorkflowClient,
        supersession: IOSKeyboardHandoffSupersessionClient = .passThrough(),
        permission: IOSForegroundVoiceWorkflowPermissionClient
    ) {
        let store = try? KeyboardDictationBridgeStore.appGroup()
        self.init(
            dependencies: IOSKeyboardDictationSessionDependencies(
                workflow: workflow,
                supersession: supersession,
                permission: permission,
                loadCommand: { date in
                    try store?.loadCommand(at: date)
                },
                loadState: { date in
                    try store?.loadState(at: date)
                },
                saveState: { record in
                    guard let store else {
                        throw KeyboardDictationBridgeStoreError
                            .appGroupContainerUnavailable
                    }
                    try store.saveState(record)
                },
                postStateChanged: {
                    KeyboardDictationBridgeSignal.postStateChanged()
                },
                applicationIsActive: {
                    UIApplication.shared.applicationState == .active
                },
                beginBackgroundTask: { expiration in
                    UIApplication.shared.beginBackgroundTask(
                        withName: "Keyboard Dictation Session",
                        expirationHandler: expiration
                    )
                },
                endBackgroundTask: { identifier in
                    UIApplication.shared.endBackgroundTask(identifier)
                },
                scheduleExpiry: { fireDate, action in
                    let timer = Timer(
                        fire: fireDate,
                        interval: 0,
                        repeats: false
                    ) { _ in
                        Task { @MainActor in action() }
                    }
                    RunLoop.main.add(timer, forMode: .common)
                    return timer
                },
                now: { Date() },
                makeUUID: { UUID() }
            ),
            observesCommands: true
        )
    }

    convenience init(qualificationOnly: Bool) {
        precondition(qualificationOnly)
        self.init(
            dependencies: IOSKeyboardDictationSessionDependencies(
                workflow: IOSKeyboardDictationWorkflowClient(
                    run: { _, _, _ in .failed },
                    finish: { _ in false },
                    cancel: { _ in false }
                ),
                supersession: .passThrough(),
                permission: IOSForegroundVoiceWorkflowPermissionClient(
                    read: { .unavailable },
                    requestIfUndetermined: { .unavailable }
                ),
                loadCommand: { _ in nil },
                loadState: { _ in nil },
                saveState: { _ in
                    throw KeyboardDictationBridgeStoreError.writeFailed
                },
                postStateChanged: {},
                applicationIsActive: { true },
                beginBackgroundTask: { _ in .invalid },
                endBackgroundTask: { _ in },
                scheduleExpiry: { _, _ in nil },
                now: { Date() },
                makeUUID: { UUID() }
            )
        )
    }

    init(
        dependencies: IOSKeyboardDictationSessionDependencies,
        observesCommands: Bool = false
    ) {
        self.dependencies = dependencies
        if observesCommands {
            commandObserver = KeyboardDictationBridgeObserver(
                name: KeyboardDictationBridgeConfiguration.commandNotification
            ) { [weak self] in
                self?.receiveCurrentCommand()
            }
        }
    }

    func startSession() async {
        guard dependencies.applicationIsActive() else {
            presentation = .failed("Session unavailable")
            return
        }

        let previousTask = workflowTask
        interruptCurrentWorkflow()
        await previousTask?.value
        workflowTask = nil
        finishSessionLifetime()
        presentation = .preparing

        switch dependencies.permission.read() {
        case .granted:
            break
        case .undetermined:
            guard await dependencies.permission.requestIfUndetermined()
                    == .granted,
                  dependencies.permission.read() == .granted else {
                presentation = .failed("Allow Microphone")
                return
            }
        case .denied:
            presentation = .failed("Allow Microphone")
            return
        case .unavailable:
            presentation = .failed("Microphone unavailable")
            return
        }

        let now = dependencies.now()
        let sessionID = dependencies.makeUUID()
        let deadline = now.addingTimeInterval(
            KeyboardDictationBridgeConfiguration.sessionLifetime
        )
        self.sessionID = sessionID
        activeAttempt = nil
        acceptedResult = nil
        deliveryClaimID = nil
        self.deadline = deadline
        translationAvailable = await dependencies.workflow
            .loadTranslationAvailability()
        lastHandledCommand = nil
        beginBackgroundTask()
        scheduleExpiry(at: deadline)
        guard publish(
            phase: .ready,
            publishedAt: now,
            expiresAt: deadline
        ) else {
            failAndStop("Session unavailable")
            return
        }
        presentation = .ready(deadline)
    }

    /// Starts the first attempt for one fresh keyboard launch without asking
    /// for a second app-side tap. Preflight owns any foreground permission UI;
    /// this entry point requires the resulting granted state and otherwise
    /// fails closed before recorder work.
    @discardableResult
    func startHandoff(
        _ intent: KeyboardHandoffIntentRecord,
        observe: @escaping @MainActor @Sendable (
            UUID,
            IOSKeyboardHandoffCaptureEvent
        ) -> Void
    ) async -> Bool {
        guard dependencies.applicationIsActive(),
              intent.isPending(at: dependencies.now()) else {
            return false
        }

        // Active capture and provider/finalization work already own the user's
        // recording. A new keyboard tap must not cancel that work or retire
        // its audio.
        switch presentation {
        case .listening, .processing:
            return false
        case .stopped, .preparing, .ready, .resultReady, .failed:
            break
        }
        if let activeAttempt,
           dependencies.workflow.ownsRetainedCapture(
               activeAttempt.attemptID
           ) {
            return false
        }

        // Only pre-start or otherwise empty work may reach supersession here.
        // A terminal failed state can own the user's preserved Pending
        // recording and is never retired merely because the microphone was
        // tapped again.
        let supersededAttemptID = activeAttempt?.attemptID
        let previousTask = workflowTask
        interruptCurrentWorkflow()
        await previousTask?.value
        workflowTask = nil
        finishSessionLifetime()

        if let supersededAttemptID,
           !(await dependencies.supersession.retire(supersededAttemptID)) {
            presentation = .failed("Try Again")
            return false
        }

        let now = dependencies.now()
        guard intent.isPending(at: now),
              dependencies.applicationIsActive(),
              dependencies.permission.read() == .granted else {
            presentation = .failed("Try Again")
            return false
        }

        presentation = .preparing
        let deadline = now.addingTimeInterval(
            KeyboardDictationBridgeConfiguration.sessionLifetime
        )
        workflowGeneration &+= 1
        let admissionGeneration = workflowGeneration
        let sessionID = dependencies.makeUUID()
        let activeAttempt = KeyboardDictationAttemptIdentity(
            sessionID: sessionID,
            attemptID: dependencies.makeUUID(),
            requestID: intent.requestID,
            sourceDocumentID: intent.sourceDocumentID
        )
        self.sessionID = sessionID
        self.activeAttempt = activeAttempt
        acceptedResult = nil
        deliveryClaimID = nil
        self.deadline = deadline
        handoffRequestID = intent.requestID
        handoffEventObserver = observe
        translationAvailable = await dependencies.workflow
            .loadTranslationAvailability()
        guard workflowGeneration == admissionGeneration,
              self.sessionID == sessionID,
              self.activeAttempt == activeAttempt,
              self.deadline == deadline,
              handoffRequestID == intent.requestID,
              intent.isPending(at: dependencies.now()),
              dependencies.applicationIsActive(),
              !intent.action.translates || translationAvailable else {
            if self.activeAttempt == activeAttempt {
                finishSessionLifetime(handoffTerminal: .failed)
                presentation = .failed("Try Again")
            }
            return false
        }

        lastHandledCommand = nil
        beginBackgroundTask()
        scheduleExpiry(at: deadline)
        guard publish(
            phase: .ready,
            publishedAt: now,
            expiresAt: deadline
        ) else {
            failAndStop("Session unavailable")
            return false
        }
        presentation = .ready(deadline)
        startRecording(
            attempt: activeAttempt,
            action: intent.action
        )
        return true
    }

    /// Rebinds presentation to the exact active capture without replacing its
    /// session or attempt. This also lets a recreated scene keep showing the
    /// live handoff instead of treating a fresh launch intent as supersession.
    func observeActiveListeningHandoff(
        _ observe: @escaping @MainActor @Sendable (
            UUID,
            IOSKeyboardHandoffCaptureEvent
        ) -> Void
    ) -> UUID? {
        guard let activeAttempt else {
            return nil
        }
        let ownsRetainedCapture = dependencies.workflow
            .ownsRetainedCapture(activeAttempt.attemptID)
        guard presentation.isListening || ownsRetainedCapture else {
            return nil
        }
        handoffRequestID = activeAttempt.requestID
        handoffEventObserver = observe
        return activeAttempt.requestID
    }

    /// Cancels only the matching handoff and waits for the shared workflow to
    /// finish stopping capture before the presentation owner dismisses.
    func cancelHandoff(requestID: UUID) async {
        guard activeAttempt?.requestID == requestID,
              handoffRequestID == requestID else {
            return
        }
        let preservesCapture = activeAttempt.map {
            dependencies.workflow.ownsRetainedCapture($0.attemptID)
        } ?? false
        let task = workflowTask
        if preservesCapture {
            interruptCurrentWorkflow()
        } else {
            discardCurrentWorkflow()
        }
        await task?.value
        guard activeAttempt?.requestID == requestID else { return }
        publishUnavailableIfCurrent()
        finishSessionLifetime(
            handoffTerminal: preservesCapture ? .failed : .cancelled
        )
        workflowTask = nil
        presentation = .stopped
    }

    /// Internal replacement retires coordination without inheriting the
    /// sheet's explicit user-cancel authority.
    func interruptHandoffForSupersession(requestID: UUID) async {
        guard activeAttempt?.requestID == requestID,
              handoffRequestID == requestID else {
            return
        }
        let task = workflowTask
        interruptCurrentWorkflow()
        await task?.value
        guard activeAttempt?.requestID == requestID else { return }
        publishUnavailableIfCurrent()
        finishSessionLifetime(handoffTerminal: .failed)
        workflowTask = nil
        presentation = .stopped
    }

    func stopSession() {
        guard sessionID != nil else {
            presentation = .stopped
            return
        }
        sessionStopRequested = true
        suspendIdleExpiry()
        dependencies.workflow.stopSession(activeAttempt?.attemptID)
        if case .resultReady = presentation {
            // Provider and canonical Latest persistence are already complete.
            // The coordinator still retains its attempt only for keyboard
            // delivery, so Stop Session may tear that projection down now.
            publishUnavailableIfCurrent()
            finishSessionLifetime(cancelWorkflowTask: false)
            workflowTask = nil
            presentation = .stopped
            return
        }
        guard activeAttempt == nil else { return }
        publishUnavailableIfCurrent()
        finishSessionLifetime(cancelWorkflowTask: false)
        workflowTask = nil
        presentation = .stopped
    }

    /// Internal test seam and Darwin-notification reducer. Loading at the
    /// injected current time rejects stale commands before any workflow call.
    func receiveCurrentCommand() {
        let now = dependencies.now()
        guard let sessionID,
              let deadline,
              deadline > now,
              let command = try? dependencies.loadCommand(now),
              command.sessionID == sessionID,
              command != lastHandledCommand else {
            return
        }
        switch command.kind {
        case .start:
            guard activeAttempt == nil,
                  workflowTask == nil,
                  case .ready = presentation,
                  !command.action.translates || translationAvailable else {
                return
            }
            let attempt = KeyboardDictationAttemptIdentity(
                sessionID: command.sessionID,
                attemptID: command.attemptID,
                requestID: command.requestID,
                sourceDocumentID: command.sourceDocumentID
            )
            activeAttempt = attempt
            acceptedResult = nil
            deliveryClaimID = nil
            guard startRecording(
                attempt: attempt,
                action: command.action
            ) else {
                activeAttempt = nil
                return
            }
            lastHandledCommand = command
        case .finish:
            guard let activeAttempt,
                  activeAttempt.matches(command) else { return }
            guard finishRecording(
                attempt: activeAttempt
            ) else { return }
            lastHandledCommand = command
        case .cancel:
            guard let activeAttempt,
                  activeAttempt.matches(command) else { return }
            guard cancelRecording(
                attempt: activeAttempt
            ) else { return }
            lastHandledCommand = command
        case .claimDelivery:
            guard let activeAttempt,
                  activeAttempt.matches(command),
                  case .resultReady = presentation,
                  deliveryClaimID == nil,
                  let claimID = command.deliveryClaimID,
                  let acceptedResult else {
                return
            }
            deliveryClaimID = claimID
            guard publish(
                phase: .resultReady,
                result: acceptedResult,
                deliveryClaimID: claimID,
                expiresAt: deadline
            ) else {
                deliveryClaimID = nil
                failAndStop("Result available in Latest")
                return
            }
            lastHandledCommand = command
        case .acknowledgeDelivery:
            guard let activeAttempt,
                  activeAttempt.matches(command),
                  case .resultReady = presentation,
                  command.deliveryClaimID == deliveryClaimID else {
                return
            }
            lastHandledCommand = command
            completeAttemptForWarmReuse()
        }
    }

    @discardableResult
    private func startRecording(
        attempt: KeyboardDictationAttemptIdentity,
        action: KeyboardVoiceAction
    ) -> Bool {
        guard workflowTask == nil,
              case .ready = presentation,
              !action.translates || translationAvailable else {
            return false
        }
        workflowGeneration &+= 1
        let generation = workflowGeneration
        let workflow = dependencies.workflow
        suspendIdleExpiry()
        deadline = stateDeadline(for: .listening)
        workflowTask = Task { @MainActor [weak self] in
            let resolution = await workflow.run(attempt.attemptID, action) {
                [weak self] progress in
                self?.receive(
                    progress,
                    attempt: attempt,
                    generation: generation
                )
            }
            guard let self else { return }
            self.receive(
                resolution,
                attempt: attempt,
                generation: generation
            )
            if self.workflowGeneration == generation {
                self.workflowTask = nil
            }
        }
        return true
    }

    private func finishRecording(
        attempt: KeyboardDictationAttemptIdentity
    ) -> Bool {
        guard case .listening = presentation,
              dependencies.workflow.finish(attempt.attemptID) else {
            return false
        }
        let deadline = stateDeadline(for: .processing)
        self.deadline = deadline
        beginBackgroundTaskIfNeeded()
        _ = publish(
            phase: .processing,
            expiresAt: deadline
        )
        // App Group publication is a keyboard-coordination projection. Once
        // Done owns the live workflow it cannot revoke recorder finalization
        // or provider authority; the containing app keeps presenting it.
        presentation = .processing
        return true
    }

    private func cancelRecording(
        attempt: KeyboardDictationAttemptIdentity
    ) -> Bool {
        guard dependencies.workflow.cancel(attempt.attemptID) else {
            return false
        }
        let deadline = dependencies.now().addingTimeInterval(1)
        _ = publish(
            phase: .unavailable,
            expiresAt: deadline
        )
        finishSessionLifetime(
            cancelWorkflowTask: false,
            handoffTerminal: .cancelled
        )
        presentation = .stopped
        return true
    }

    private func receive(
        _ progress: IOSKeyboardDictationWorkflowProgress,
        attempt: KeyboardDictationAttemptIdentity,
        generation: UInt64
    ) {
        guard ownsCurrentWorkflow(
            attempt: attempt,
            generation: generation
        ) else {
            return
        }
        let phase: KeyboardDictationStatePhase
        switch progress {
        case .listening(let limit):
            let deadline = dependencies.now().addingTimeInterval(
                limit.duration + Self.listeningFinalizationGrace
            )
            self.deadline = deadline
            // Background audio now owns continuation; retire the finite warm
            // assertion so finalization can acquire a fresh bounded one.
            endBackgroundTask()
            phase = .listening
            presentation = .listening(deadline)
        case .processing:
            let deadline = stateDeadline(for: .processing)
            self.deadline = deadline
            beginBackgroundTaskIfNeeded()
            phase = .processing
            presentation = .processing
        }
        guard let deadline else {
            failAndStop("Session unavailable")
            return
        }
        _ = publish(
            phase: phase,
            expiresAt: deadline
        )
        // The shared-state write may fail while this process still owns a
        // healthy recorder/finalizer. Keep the local workflow and handoff
        // presentation alive; later durable recovery remains authoritative.
        switch progress {
        case .listening:
            emitHandoff(.listening, requestID: attempt.requestID)
        case .processing:
            emitHandoff(
                .processing,
                requestID: attempt.requestID
            )
        }
    }

    private func receive(
        _ resolution: IOSKeyboardDictationWorkflowResolution,
        attempt: KeyboardDictationAttemptIdentity,
        generation: UInt64
    ) {
        guard ownsCurrentWorkflow(
            attempt: attempt,
            generation: generation
        ) else {
            return
        }
        switch resolution {
        case .accepted(let text):
            let deadline = stateDeadline(for: .resultReady)
            self.deadline = deadline
            acceptedResult = text
            deliveryClaimID = nil
            guard publish(
                phase: .resultReady,
                result: text,
                expiresAt: deadline
            ) else {
                failAndStop("Result available in Latest")
                return
            }
            presentation = .resultReady
            // Provider work is complete. Result delivery gets its own fresh
            // warm-session assertion and expiry window.
            endBackgroundTask()
            beginBackgroundTaskIfNeeded()
            scheduleExpiry(at: deadline)
            emitHandoff(
                .terminal(.completed),
                requestID: attempt.requestID,
                endsObservation: true
            )
        case .interruptedSaved:
            let deadline = stateDeadline(for: .failed)
            self.deadline = deadline
            _ = publish(
                phase: .failed,
                expiresAt: deadline
            )
            finishSessionLifetime(
                cancelWorkflowTask: false,
                handoffTerminal: .failed
            )
            presentation = .failed(
                "Recording interrupted — saved to History"
            )
        case .transcriptionUncertainSaved:
            let deadline = stateDeadline(for: .failed)
            self.deadline = deadline
            _ = publish(
                phase: .failed,
                expiresAt: deadline
            )
            finishSessionLifetime(
                cancelWorkflowTask: false,
                handoffTerminal: .failed
            )
            presentation = .failed(
                "Transcription outcome uncertain — recording saved to History"
            )
        case .cancelled:
            let deadline = dependencies.now().addingTimeInterval(1)
            _ = publish(
                phase: .unavailable,
                expiresAt: deadline
            )
            finishSessionLifetime(
                cancelWorkflowTask: false,
                handoffTerminal: .cancelled
            )
            presentation = .stopped
        case .failed:
            failAndStop("Try Again")
        }
    }

    private func ownsCurrentWorkflow(
        attempt: KeyboardDictationAttemptIdentity,
        generation: UInt64
    ) -> Bool {
        activeAttempt == attempt
            && workflowGeneration == generation
    }

    private func discardCurrentWorkflow() {
        if let activeAttempt {
            _ = dependencies.workflow.cancel(activeAttempt.attemptID)
        }
        workflowTask?.cancel()
    }

    private func interruptCurrentWorkflow() {
        if let activeAttempt {
            _ = dependencies.workflow.interrupt(activeAttempt.attemptID)
        }
        workflowTask?.cancel()
    }

    private func failAndStop(_ message: String) {
        if sessionID != nil {
            let failureDeadline = stateDeadline(for: .failed)
            _ = publish(
                phase: .failed,
                expiresAt: failureDeadline
            )
        }
        interruptCurrentWorkflow()
        finishSessionLifetime(handoffTerminal: .failed)
        presentation = .failed(message)
    }

    private func publishUnavailableIfCurrent() {
        guard sessionID != nil else { return }
        _ = publish(
            phase: .unavailable,
            expiresAt: dependencies.now().addingTimeInterval(1)
        )
    }

    private func expireSession() {
        guard sessionID != nil,
              presentation.allowsSessionExpiry else {
            return
        }
        interruptCurrentWorkflow()
        let now = dependencies.now()
        _ = publish(
            phase: .unavailable,
            publishedAt: now,
            expiresAt: now.addingTimeInterval(1)
        )
        finishSessionLifetime(handoffTerminal: .expired)
        presentation = .stopped
    }

    private func publish(
        phase: KeyboardDictationStatePhase,
        result: String? = nil,
        deliveryClaimID: UUID? = nil,
        publishedAt: Date? = nil,
        expiresAt: Date
    ) -> Bool {
        let publicationDate = publishedAt ?? dependencies.now()
        guard let sessionID else { return false }
        guard let record = KeyboardDictationStateRecord(
            sessionID: sessionID,
            attemptID: activeAttempt?.attemptID,
            requestID: activeAttempt?.requestID,
            sourceDocumentID: activeAttempt?.sourceDocumentID,
            deliveryClaimID: deliveryClaimID,
            phase: phase,
            translationAvailable: translationAvailable,
            result: result,
            publishedAt: publicationDate,
            expiresAt: expiresAt
        ) else {
            return false
        }
        do {
            try dependencies.saveState(record)
            dependencies.postStateChanged()
            return true
        } catch {
            return false
        }
    }

    private func beginBackgroundTask() {
        backgroundTask = dependencies.beginBackgroundTask { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.presentation.allowsSessionExpiry {
                    self.expireSession()
                } else {
                    // Active audio is protected by the app's background-audio
                    // mode. Expiry of this finite assertion must never cancel
                    // Listening or Processing.
                    self.endBackgroundTask()
                }
            }
        }
    }

    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTask == .invalid else { return }
        beginBackgroundTask()
    }

    private func scheduleExpiry(at date: Date) {
        expiryTimer?.invalidate()
        expiryTimer = dependencies.scheduleExpiry(date) { [weak self] in
            self?.expireSession()
        }
    }

    private func suspendIdleExpiry() {
        expiryTimer?.invalidate()
        expiryTimer = nil
    }

    private func stateDeadline(
        for phase: KeyboardDictationStatePhase
    ) -> Date {
        dependencies.now().addingTimeInterval(
            KeyboardDictationBridgeConfiguration.maximumStateLifetime(
                for: phase
            )
        )
    }

    /// The App Group Listening record outlives capture by only the bounded
    /// recorder-close tolerance. Ready continues to use its independent
    /// 60-second warm-session lifetime.
    private static let listeningFinalizationGrace: TimeInterval = 2

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        dependencies.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func completeAttemptForWarmReuse() {
        if sessionStopRequested {
            publishUnavailableIfCurrent()
            finishSessionLifetime(cancelWorkflowTask: false)
            workflowTask = nil
            presentation = .stopped
            return
        }
        activeAttempt = nil
        acceptedResult = nil
        deliveryClaimID = nil
        let deadline = stateDeadline(for: .ready)
        self.deadline = deadline
        beginBackgroundTaskIfNeeded()
        guard publish(
            phase: .ready,
            expiresAt: deadline
        ) else {
            finishSessionLifetime()
            presentation = .failed("Session unavailable")
            return
        }
        presentation = .ready(deadline)
        scheduleExpiry(at: deadline)
    }

    private func finishSessionLifetime(
        cancelWorkflowTask: Bool = true,
        handoffTerminal: IOSKeyboardHandoffTerminalDisposition? = nil
    ) {
        if sessionID != nil, !sessionStopRequested {
            dependencies.workflow.endWarmSession()
        }
        if let requestID = activeAttempt?.requestID,
           handoffRequestID == requestID {
            emitHandoff(
                .terminal(handoffTerminal ?? .failed),
                requestID: requestID,
                endsObservation: true
            )
        }
        workflowGeneration &+= 1
        expiryTimer?.invalidate()
        expiryTimer = nil
        sessionID = nil
        activeAttempt = nil
        acceptedResult = nil
        deliveryClaimID = nil
        deadline = nil
        translationAvailable = false
        lastHandledCommand = nil
        sessionStopRequested = false
        if cancelWorkflowTask {
            workflowTask?.cancel()
        }
        endBackgroundTask()
    }

    private func emitHandoff(
        _ event: IOSKeyboardHandoffCaptureEvent,
        requestID: UUID,
        endsObservation: Bool = false
    ) {
        guard handoffRequestID == requestID,
              let observer = handoffEventObserver else {
            return
        }
        observer(requestID, event)
        if endsObservation {
            handoffRequestID = nil
            handoffEventObserver = nil
        }
    }
}

private extension IOSKeyboardDictationSessionCoordinator.Presentation {
    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}

/// Presentation-only owner for the temporary sheet over the unchanged Voice
/// screen. The session coordinator remains the sole keyboard workflow owner.
@MainActor
@Observable
final class IOSKeyboardHandoffPresentationOwner {
    private static let maximumStartAttemptCount = 8

    private(set) var presentation: IOSKeyboardHandoffSheetPresentation?

    @ObservationIgnored
    private let session: IOSKeyboardDictationSessionCoordinator
    @ObservationIgnored
    private let preflight: IOSKeyboardHandoffPreflightClient
    @ObservationIgnored
    private let pendingRecordingOwner:
        IOSPendingRecordingHistoryStateOwner?
    @ObservationIgnored
    private let waitBeforeStartRetry: @MainActor @Sendable () async -> Void
    private var activeRequestID: UUID?
    private var armingRequestID: UUID?
    private var generation: UInt64 = 0
    private var cancellationTask: Task<Void, Never>?

    init(
        session: IOSKeyboardDictationSessionCoordinator,
        preflight: IOSKeyboardHandoffPreflightClient = .passThrough(),
        pendingRecordingOwner:
            IOSPendingRecordingHistoryStateOwner? = nil,
        waitBeforeStartRetry: @escaping @MainActor @Sendable () async -> Void = {
            try? await Task.sleep(for: .milliseconds(150))
        }
    ) {
        self.session = session
        self.preflight = preflight
        self.pendingRecordingOwner = pendingRecordingOwner
        self.waitBeforeStartRetry = waitBeforeStartRetry
    }

    var savedRecordingOwner: IOSPendingRecordingHistoryStateOwner? {
        pendingRecordingOwner
    }

    func start(_ intent: KeyboardHandoffIntentRecord) async {
        // Listening owns a live, potentially non-empty recording. A fresh
        // launch only re-presents that exact attempt; it must not run preflight
        // or reach recorder supersession.
        if cancellationTask == nil,
           retainActiveListeningHandoffIfAvailable() {
            return
        }

        // Processing already owns a durable Pending transition. A fresh tap
        // may reveal that exact saved owner, but it never supersedes it.
        if session.presentation == .processing {
            await revealCurrentSavedRecordingIfAvailable()
            return
        }
        let previousRequestID = activeRequestID
        generation &+= 1
        let currentGeneration = generation
        activeRequestID = intent.requestID
        presentation = IOSKeyboardHandoffSheetPresentation(
            phase: .starting
        )

        if await revealSavedRecordingIfAvailable(
            requestID: intent.requestID,
            generation: currentGeneration
        ) {
            return
        }
        guard generation == currentGeneration,
              activeRequestID == intent.requestID else {
            return
        }

        // A close from the previous sheet may still be waiting for recorder
        // cancellation. A fresh request supersedes its presentation
        // immediately, but does not race that cleanup inside the shared
        // keyboard session.
        await cancellationTask?.value
        if let previousRequestID,
           previousRequestID != intent.requestID {
            await session.interruptHandoffForSupersession(
                requestID: previousRequestID
            )
        }
        guard generation == currentGeneration,
              activeRequestID == intent.requestID else {
            return
        }

        let preflightResult = await preflight.run(intent)
        guard generation == currentGeneration,
              activeRequestID == intent.requestID else {
            return
        }
        if case .blocked(let issue) = preflightResult {
            presentation = IOSKeyboardHandoffSheetPresentation(issue: issue)
            return
        }

        armingRequestID = intent.requestID
        for startAttemptIndex in 0..<Self.maximumStartAttemptCount {
            if startAttemptIndex > 0 {
                await waitBeforeStartRetry()
            }
            guard generation == currentGeneration,
                  activeRequestID == intent.requestID else {
                return
            }

            let started = await session.startHandoff(intent) {
                [weak self] requestID, event in
                self?.receive(event, requestID: requestID)
            }
            guard generation == currentGeneration,
                  activeRequestID == intent.requestID else {
                return
            }
            if started {
                armingRequestID = nil
                return
            }
            if retainActiveListeningHandoffIfAvailable() {
                return
            }
            if await revealSavedRecordingIfAvailable(
                requestID: intent.requestID,
                generation: currentGeneration
            ) {
                return
            }
        }

        armingRequestID = nil
        activeRequestID = nil
        presentation = nil
    }

    func cancelFromSheet() {
        if presentation?.phase == .savedRecording {
            closeSavedRecordingPresentation()
            return
        }
        guard cancellationTask == nil,
              let requestID = activeRequestID else {
            return
        }
        cancellationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.cancel(requestID: requestID)
            self.cancellationTask = nil
        }
    }

    func cancelActiveHandoff() async {
        if presentation?.phase == .savedRecording {
            closeSavedRecordingPresentation()
            return
        }
        guard let requestID = activeRequestID else { return }
        await cancel(requestID: requestID)
    }

    func savedRecordingDidResolve() {
        guard presentation?.phase == .savedRecording,
              pendingRecordingOwner?.isConfirmedAbsent == true else {
            return
        }
        closeSavedRecordingPresentation()
    }

    private func cancel(requestID: UUID) async {
        await session.cancelHandoff(requestID: requestID)
        guard activeRequestID == requestID else { return }
        generation &+= 1
        armingRequestID = nil
        activeRequestID = nil
        presentation = nil
    }

    private func receive(
        _ event: IOSKeyboardHandoffCaptureEvent,
        requestID: UUID
    ) {
        guard activeRequestID == requestID else { return }
        switch event {
        case .listening:
            presentation = IOSKeyboardHandoffSheetPresentation(
                phase: .listening
            )
        case .processing:
            presentation = IOSKeyboardHandoffSheetPresentation(
                phase: .processing
            )
        case .terminal(.completed), .terminal(.cancelled):
            activeRequestID = nil
            presentation = nil
        case .terminal(.failed), .terminal(.expired):
            guard armingRequestID != requestID else { return }
            let currentGeneration = generation
            Task { @MainActor [weak self] in
                guard let self else { return }
                let revealed = await self.revealSavedRecordingIfAvailable(
                    requestID: requestID,
                    generation: currentGeneration
                )
                guard self.generation == currentGeneration,
                      self.activeRequestID == requestID,
                      !revealed else {
                    return
                }
                self.activeRequestID = nil
                self.presentation = nil
            }
        }
    }

    private func retainActiveListeningHandoffIfAvailable() -> Bool {
        guard let requestID = session.observeActiveListeningHandoff({
            [weak self] requestID, event in
            self?.receive(event, requestID: requestID)
        }) else {
            return false
        }
        armingRequestID = nil
        activeRequestID = requestID
        presentation = IOSKeyboardHandoffSheetPresentation(
            phase: .listening
        )
        return true
    }

    private func revealCurrentSavedRecordingIfAvailable() async {
        guard let pendingRecordingOwner else { return }
        let confirmed = await pendingRecordingOwner.refresh()
        guard pendingRecordingOwner.shouldPresentSavedRecording
                || (!confirmed
                    && !pendingRecordingOwner.isConfirmedAbsent) else {
            return
        }
        presentation = IOSKeyboardHandoffSheetPresentation(
            phase: .savedRecording
        )
    }

    private func revealSavedRecordingIfAvailable(
        requestID: UUID,
        generation expectedGeneration: UInt64
    ) async -> Bool {
        guard let pendingRecordingOwner else { return false }
        let confirmed = await pendingRecordingOwner.refresh()
        guard generation == expectedGeneration,
              activeRequestID == requestID,
              pendingRecordingOwner.shouldPresentSavedRecording
                || (!confirmed
                    && !pendingRecordingOwner.isConfirmedAbsent) else {
            return false
        }
        armingRequestID = nil
        presentation = IOSKeyboardHandoffSheetPresentation(
            phase: .savedRecording
        )
        return true
    }

    private func closeSavedRecordingPresentation() {
        generation &+= 1
        armingRequestID = nil
        activeRequestID = nil
        presentation = nil
        guard let pendingRecordingOwner else { return }
        Task { await pendingRecordingOwner.stopPlayback() }
    }
}
