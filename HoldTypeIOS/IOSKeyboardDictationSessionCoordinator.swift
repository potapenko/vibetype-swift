import Foundation
import Observation
import UIKit

@MainActor
struct IOSKeyboardDictationSessionDependencies {
    let workflow: IOSKeyboardDictationWorkflowClient
    let permission: IOSForegroundVoiceWorkflowPermissionClient
    let loadCommand: (Date) throws -> KeyboardDictationCommandRecord?
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
    private var requestID: UUID?
    private var deadline: Date?
    private var expiryTimer: Timer?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var lastHandledCommand: KeyboardDictationCommandRecord?
    private var workflowTask: Task<Void, Never>?
    private var workflowGeneration: UInt64 = 0

    convenience init(
        workflow: IOSKeyboardDictationWorkflowClient,
        permission: IOSForegroundVoiceWorkflowPermissionClient
    ) {
        let store = try? KeyboardDictationBridgeStore.appGroup()
        self.init(
            dependencies: IOSKeyboardDictationSessionDependencies(
                workflow: workflow,
                permission: permission,
                loadCommand: { date in
                    try store?.loadCommand(at: date)
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
                    run: { _, _ in .failed },
                    finish: { _ in false },
                    cancel: { _ in false }
                ),
                permission: IOSForegroundVoiceWorkflowPermissionClient(
                    read: { .unavailable },
                    requestIfUndetermined: { .unavailable }
                ),
                loadCommand: { _ in nil },
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
            presentation = .failed("Open HoldType")
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
        let requestID = dependencies.makeUUID()
        let deadline = now.addingTimeInterval(
            KeyboardDictationBridgeConfiguration.sessionLifetime
        )
        self.requestID = requestID
        self.deadline = deadline
        lastHandledCommand = nil
        beginBackgroundTask()
        scheduleExpiry(at: deadline)
        guard publish(
            phase: .ready,
            requestID: requestID,
            publishedAt: now,
            expiresAt: deadline
        ) else {
            failAndStop("Session unavailable")
            return
        }
        presentation = .ready(deadline)
    }

    func stopSession() {
        cancelCurrentWorkflow()
        publishUnavailableIfCurrent()
        finishSessionLifetime()
        presentation = .stopped
    }

    /// Internal test seam and Darwin-notification reducer. Loading at the
    /// injected current time rejects stale commands before any workflow call.
    func receiveCurrentCommand() {
        let now = dependencies.now()
        guard let requestID,
              let deadline,
              deadline > now,
              let command = try? dependencies.loadCommand(now),
              command.requestID == requestID,
              command != lastHandledCommand else {
            return
        }
        lastHandledCommand = command

        switch command.kind {
        case .start:
            startRecording(requestID: requestID, deadline: deadline)
        case .finish:
            finishRecording(requestID: requestID, deadline: deadline)
        case .cancel:
            cancelRecording(requestID: requestID, deadline: deadline)
        }
    }

    private func startRecording(requestID: UUID, deadline: Date) {
        guard workflowTask == nil,
              case .ready = presentation else {
            return
        }
        workflowGeneration &+= 1
        let generation = workflowGeneration
        let workflow = dependencies.workflow
        workflowTask = Task { @MainActor [weak self] in
            let resolution = await workflow.run(requestID) {
                [weak self] progress in
                self?.receive(
                    progress,
                    requestID: requestID,
                    deadline: deadline,
                    generation: generation
                )
            }
            guard let self else { return }
            self.receive(
                resolution,
                requestID: requestID,
                deadline: deadline,
                generation: generation
            )
            if self.workflowGeneration == generation {
                self.workflowTask = nil
            }
        }
    }

    private func finishRecording(requestID: UUID, deadline: Date) {
        guard case .listening = presentation,
              dependencies.workflow.finish(requestID) else {
            return
        }
        guard publish(
            phase: .processing,
            requestID: requestID,
            expiresAt: deadline
        ) else {
            failAndStop("Session unavailable")
            return
        }
        presentation = .processing
    }

    private func cancelRecording(requestID: UUID, deadline: Date) {
        guard dependencies.workflow.cancel(requestID) else { return }
        _ = publish(
            phase: .unavailable,
            requestID: requestID,
            expiresAt: deadline
        )
        finishSessionLifetime(cancelWorkflowTask: false)
        presentation = .stopped
    }

    private func receive(
        _ progress: IOSKeyboardDictationWorkflowProgress,
        requestID: UUID,
        deadline: Date,
        generation: UInt64
    ) {
        guard ownsCurrentWorkflow(
            requestID: requestID,
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
            requestID: requestID,
            expiresAt: deadline
        ) else {
            failAndStop("Session unavailable")
            return
        }
    }

    private func receive(
        _ resolution: IOSKeyboardDictationWorkflowResolution,
        requestID: UUID,
        deadline: Date,
        generation: UInt64
    ) {
        guard ownsCurrentWorkflow(
            requestID: requestID,
            deadline: deadline,
            generation: generation
        ) else {
            return
        }
        switch resolution {
        case .accepted(let text):
            guard publish(
                phase: .resultReady,
                requestID: requestID,
                result: text,
                expiresAt: deadline
            ) else {
                failAndStop("Result available in Latest")
                return
            }
            endBackgroundTask()
            presentation = .resultReady
        case .cancelled:
            _ = publish(
                phase: .unavailable,
                requestID: requestID,
                expiresAt: deadline
            )
            finishSessionLifetime(cancelWorkflowTask: false)
            presentation = .stopped
        case .failed:
            failAndStop("Try Again")
        }
    }

    private func ownsCurrentWorkflow(
        requestID: UUID,
        deadline: Date,
        generation: UInt64
    ) -> Bool {
        self.requestID == requestID
            && self.deadline == deadline
            && workflowGeneration == generation
            && deadline > dependencies.now()
    }

    private func cancelCurrentWorkflow() {
        if let requestID {
            _ = dependencies.workflow.cancel(requestID)
        }
        workflowTask?.cancel()
    }

    private func failAndStop(_ message: String) {
        if let requestID,
           let deadline,
           deadline > dependencies.now() {
            _ = publish(
                phase: .failed,
                requestID: requestID,
                expiresAt: deadline
            )
        }
        cancelCurrentWorkflow()
        finishSessionLifetime()
        presentation = .failed(message)
    }

    private func publishUnavailableIfCurrent() {
        guard let requestID,
              let deadline,
              deadline > dependencies.now() else {
            return
        }
        _ = publish(
            phase: .unavailable,
            requestID: requestID,
            expiresAt: deadline
        )
    }

    private func expireSession() {
        guard let requestID else { return }
        cancelCurrentWorkflow()
        let now = dependencies.now()
        _ = publish(
            phase: .unavailable,
            requestID: requestID,
            publishedAt: now,
            expiresAt: now.addingTimeInterval(1)
        )
        finishSessionLifetime()
        presentation = .stopped
    }

    private func publish(
        phase: KeyboardDictationStatePhase,
        requestID: UUID,
        result: String? = nil,
        publishedAt: Date? = nil,
        expiresAt: Date
    ) -> Bool {
        let publicationDate = publishedAt ?? dependencies.now()
        guard let record = KeyboardDictationStateRecord(
            requestID: requestID,
            phase: phase,
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

    private func finishSessionLifetime(cancelWorkflowTask: Bool = true) {
        workflowGeneration &+= 1
        expiryTimer?.invalidate()
        expiryTimer = nil
        requestID = nil
        deadline = nil
        lastHandledCommand = nil
        if cancelWorkflowTask {
            workflowTask?.cancel()
        }
        endBackgroundTask()
    }
}
