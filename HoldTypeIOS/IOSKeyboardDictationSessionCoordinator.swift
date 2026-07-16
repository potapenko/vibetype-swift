import Foundation
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
        cancelCurrentWorkflow()
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

        let supersededAttemptID = activeAttempt?.attemptID
            ?? (try? dependencies.loadState(.distantPast))?.attemptID
        let previousTask = workflowTask
        cancelCurrentWorkflow()
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
            deadline: deadline,
            action: intent.action
        )
        return true
    }

    /// Cancels only the matching handoff and waits for the shared workflow to
    /// finish stopping capture before the presentation owner dismisses.
    func cancelHandoff(requestID: UUID) async {
        guard activeAttempt?.requestID == requestID,
              handoffRequestID == requestID else {
            return
        }
        let task = workflowTask
        cancelCurrentWorkflow()
        await task?.value
        guard activeAttempt?.requestID == requestID else { return }
        publishUnavailableIfCurrent()
        finishSessionLifetime(handoffTerminal: .cancelled)
        workflowTask = nil
        presentation = .stopped
    }

    func stopSession() {
        cancelCurrentWorkflow()
        publishUnavailableIfCurrent()
        finishSessionLifetime(handoffTerminal: .cancelled)
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
                deadline: deadline,
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
                attempt: activeAttempt,
                deadline: deadline
            ) else { return }
            lastHandledCommand = command
        case .cancel:
            guard let activeAttempt,
                  activeAttempt.matches(command) else { return }
            guard cancelRecording(
                attempt: activeAttempt,
                deadline: deadline
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
            completeAttemptForWarmReuse(deadline: deadline)
        }
    }

    @discardableResult
    private func startRecording(
        attempt: KeyboardDictationAttemptIdentity,
        deadline: Date,
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
        workflowTask = Task { @MainActor [weak self] in
            let resolution = await workflow.run(attempt.attemptID, action) {
                [weak self] progress in
                self?.receive(
                    progress,
                    attempt: attempt,
                    deadline: deadline,
                    generation: generation
                )
            }
            guard let self else { return }
            self.receive(
                resolution,
                attempt: attempt,
                deadline: deadline,
                generation: generation
            )
            if self.workflowGeneration == generation {
                self.workflowTask = nil
            }
        }
        return true
    }

    private func finishRecording(
        attempt: KeyboardDictationAttemptIdentity,
        deadline: Date
    ) -> Bool {
        guard case .listening = presentation,
              dependencies.workflow.finish(attempt.attemptID) else {
            return false
        }
        guard publish(
            phase: .processing,
            expiresAt: deadline
        ) else {
            failAndStop("Session unavailable")
            return true
        }
        presentation = .processing
        return true
    }

    private func cancelRecording(
        attempt: KeyboardDictationAttemptIdentity,
        deadline: Date
    ) -> Bool {
        guard dependencies.workflow.cancel(attempt.attemptID) else {
            return false
        }
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
        deadline: Date,
        generation: UInt64
    ) {
        guard ownsCurrentWorkflow(
            attempt: attempt,
            deadline: deadline,
            generation: generation
        ) else {
            return
        }
        let phase: KeyboardDictationStatePhase
        switch progress {
        case .listening:
            phase = .listening
            presentation = .listening(deadline)
        case .processing:
            phase = .processing
            presentation = .processing
        }
        guard publish(
            phase: phase,
            expiresAt: deadline
        ) else {
            failAndStop("Session unavailable")
            return
        }
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
        deadline: Date,
        generation: UInt64
    ) {
        guard ownsCurrentWorkflow(
            attempt: attempt,
            deadline: deadline,
            generation: generation
        ) else {
            return
        }
        switch resolution {
        case .accepted(let text):
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
            emitHandoff(
                .terminal(.completed),
                requestID: attempt.requestID,
                endsObservation: true
            )
        case .cancelled:
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
        deadline: Date,
        generation: UInt64
    ) -> Bool {
        activeAttempt == attempt
            && self.deadline == deadline
            && workflowGeneration == generation
            && deadline > dependencies.now()
    }

    private func cancelCurrentWorkflow() {
        if let activeAttempt {
            _ = dependencies.workflow.cancel(activeAttempt.attemptID)
        }
        workflowTask?.cancel()
    }

    private func failAndStop(_ message: String) {
        if sessionID != nil,
           let deadline,
           deadline > dependencies.now() {
            _ = publish(
                phase: .failed,
                expiresAt: deadline
            )
        }
        cancelCurrentWorkflow()
        finishSessionLifetime(handoffTerminal: .failed)
        presentation = .failed(message)
    }

    private func publishUnavailableIfCurrent() {
        guard sessionID != nil,
              let deadline,
              deadline > dependencies.now() else {
            return
        }
        _ = publish(
            phase: .unavailable,
            expiresAt: deadline
        )
    }

    private func expireSession() {
        guard sessionID != nil else { return }
        cancelCurrentWorkflow()
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
            Task { @MainActor [weak self] in self?.expireSession() }
        }
    }

    private func scheduleExpiry(at date: Date) {
        expiryTimer?.invalidate()
        expiryTimer = dependencies.scheduleExpiry(date) { [weak self] in
            self?.expireSession()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        dependencies.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func completeAttemptForWarmReuse(deadline: Date) {
        activeAttempt = nil
        acceptedResult = nil
        deliveryClaimID = nil
        guard publish(
            phase: .ready,
            expiresAt: deadline
        ) else {
            finishSessionLifetime()
            presentation = .failed("Session unavailable")
            return
        }
        presentation = .ready(deadline)
    }

    private func finishSessionLifetime(
        cancelWorkflowTask: Bool = true,
        handoffTerminal: IOSKeyboardHandoffTerminalDisposition? = nil
    ) {
        if sessionID != nil {
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

/// Presentation-only owner for the temporary sheet over the unchanged Voice
/// screen. The session coordinator remains the sole keyboard workflow owner.
@MainActor
@Observable
final class IOSKeyboardHandoffPresentationOwner {
    private(set) var presentation: IOSKeyboardHandoffSheetPresentation?

    @ObservationIgnored
    private let session: IOSKeyboardDictationSessionCoordinator
    @ObservationIgnored
    private let preflight: IOSKeyboardHandoffPreflightClient
    private var activeRequestID: UUID?
    private var generation: UInt64 = 0
    private var cancellationTask: Task<Void, Never>?

    init(
        session: IOSKeyboardDictationSessionCoordinator,
        preflight: IOSKeyboardHandoffPreflightClient = .passThrough()
    ) {
        self.session = session
        self.preflight = preflight
    }

    func start(_ intent: KeyboardHandoffIntentRecord) async {
        let previousRequestID = activeRequestID
        generation &+= 1
        let currentGeneration = generation
        activeRequestID = intent.requestID
        presentation = IOSKeyboardHandoffSheetPresentation(
            phase: .starting
        )

        // A close from the previous sheet may still be waiting for recorder
        // cancellation. A fresh request supersedes its presentation
        // immediately, but does not race that cleanup inside the shared
        // keyboard session.
        await cancellationTask?.value
        if let previousRequestID,
           previousRequestID != intent.requestID {
            await session.cancelHandoff(requestID: previousRequestID)
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

        let started = await session.startHandoff(intent) {
            [weak self] requestID, event in
            self?.receive(event, requestID: requestID)
        }
        guard generation == currentGeneration,
              activeRequestID == intent.requestID else {
            return
        }
        if !started {
            presentation = IOSKeyboardHandoffSheetPresentation(
                runtimeFailure: .startUnavailable
            )
        }
    }

    func cancelFromSheet() {
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
        guard let requestID = activeRequestID else { return }
        await cancel(requestID: requestID)
    }

    private func cancel(requestID: UUID) async {
        await session.cancelHandoff(requestID: requestID)
        guard activeRequestID == requestID else { return }
        generation &+= 1
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
        case .terminal(.failed):
            activeRequestID = nil
            presentation = nil
        case .terminal(.expired):
            presentation = IOSKeyboardHandoffSheetPresentation(
                runtimeFailure: .expired
            )
        }
    }
}
