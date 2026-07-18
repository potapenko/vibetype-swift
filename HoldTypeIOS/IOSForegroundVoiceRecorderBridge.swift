import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypePersistence

/// Narrow, fakeable surface over one descriptor-bound recorder adapter.
nonisolated struct IOSForegroundVoiceRecorderBridgeDriver: Sendable {
    let start: @MainActor @Sendable (
        IOSVoiceRecorderAttemptToken
    ) async -> IOSVoiceRecorderStartResult
    let stop: @MainActor @Sendable (
        IOSVoiceRecorderAttemptToken,
        IOSVoiceRecorderStopReason
    ) async -> IOSVoiceRecorderStopResult
    let waitForTerminal: @MainActor @Sendable (
        IOSVoiceRecorderAttemptToken
    ) -> IOSVoiceRecorderTerminalWait
    let isActivelyRecording: @MainActor @Sendable (
        IOSVoiceRecorderAttemptToken
    ) -> Bool

    @MainActor
    init(adapter: IOSVoiceRecorderAdapter) {
        start = { [adapter] token in
            await adapter.start(for: token)
        }
        stop = { [adapter] token, reason in
            await adapter.stop(for: token, reason: reason)
        }
        waitForTerminal = { [adapter] token in
            adapter.waitForTerminal(for: token)
        }
        isActivelyRecording = { [adapter] token in
            adapter.isActivelyRecording(for: token)
        }
    }

    init(
        start: @escaping @MainActor @Sendable (
            IOSVoiceRecorderAttemptToken
        ) async -> IOSVoiceRecorderStartResult,
        stop: @escaping @MainActor @Sendable (
            IOSVoiceRecorderAttemptToken,
            IOSVoiceRecorderStopReason
        ) async -> IOSVoiceRecorderStopResult,
        waitForTerminal: @escaping @MainActor @Sendable (
            IOSVoiceRecorderAttemptToken
        ) -> IOSVoiceRecorderTerminalWait,
        isActivelyRecording: @escaping @MainActor @Sendable (
            IOSVoiceRecorderAttemptToken
        ) -> Bool
    ) {
        self.start = start
        self.stop = stop
        self.waitForTerminal = waitForTerminal
        self.isActivelyRecording = isActivelyRecording
    }
}

/// Creates the capture lease before constructing the recorder adapter and
/// maps its exact terminal ownership into the process Voice workflow.
@MainActor
final class IOSForegroundVoiceRecorderBridge {
    typealias MakeDriver = @MainActor @Sendable (
        UUID,
        DictationOutputIntent,
        IOSVoiceDraftInsertionMode,
        Bool,
        RecordingDurationLimit
    ) async throws -> IOSForegroundVoiceRecorderBridgeDriver
    typealias PreparePending = @MainActor @Sendable (
        IOSVoiceRecorderCompletedCaptureHandoff,
        TranscriptionConfiguration,
        IOSAcceptedAudioRetention
    ) async throws -> IOSV1PendingRecording

    private let makeDriver: MakeDriver
    private let preparePending: PreparePending
    private let feedback: IOSForegroundVoiceFeedbackBridge?

    init(
        persistenceOwner: IOSV1ForegroundVoicePersistenceOwner,
        recorderClient: IOSVoiceRecorderClient = .live,
        feedback: IOSForegroundVoiceFeedbackBridge? = nil,
        diagnose: @escaping IOSVoiceRecorderAdapter.DiagnosticHandler = {
            _ in
        }
    ) {
        makeDriver = {
            attemptID,
            outputIntent,
            draftInsertionMode,
            forcesTextCorrection,
            recordingDurationLimit in
            let lease = try await persistenceOwner.createCapture(
                attemptID: attemptID,
                outputIntent: outputIntent,
                draftInsertionMode: draftInsertionMode,
                forcesTextCorrection: forcesTextCorrection,
                recordingDurationLimit: recordingDurationLimit
            )
            let adapter = IOSVoiceRecorderAdapter(
                lease: lease,
                recordingDurationLimit: recordingDurationLimit,
                client: recorderClient,
                diagnose: diagnose
            )
            return IOSForegroundVoiceRecorderBridgeDriver(adapter: adapter)
        }
        preparePending = { handoff, configuration, retention in
            try await handoff.preparePending(
                using: persistenceOwner,
                transcriptionConfiguration: configuration,
                acceptedAudioRetention: retention
            )
        }
        self.feedback = feedback
    }

    init(
        makeDriver: @escaping MakeDriver,
        preparePending: @escaping PreparePending,
        feedback: IOSForegroundVoiceFeedbackBridge? = nil
    ) {
        self.makeDriver = makeDriver
        self.preparePending = preparePending
        self.feedback = feedback
    }

    func makeRecording(
        attemptID: UUID,
        outputIntent: DictationOutputIntent,
        draftInsertionMode: IOSVoiceDraftInsertionMode = .replace,
        forcesTextCorrection: Bool = false,
        recordingDurationLimit: RecordingDurationLimit = .defaultValue
    ) async throws -> IOSForegroundVoiceWorkflowRecording {
        let driver = try await makeDriver(
            attemptID,
            outputIntent,
            draftInsertionMode,
            forcesTextCorrection,
            recordingDurationLimit
        )
        let owner = AttemptOwner(
            driver: driver,
            preparePending: preparePending,
            feedback: feedback,
            feedbackHandle: feedback?.recorderAttemptHandle,
            warningSchedule: VoiceSessionWarningSchedule(
                limit: recordingDurationLimit
            )
        )
        return owner.recording
    }
}

@MainActor
private final class IOSForegroundVoiceRecorderBridgeAttemptOwner {
    private let driver: IOSForegroundVoiceRecorderBridgeDriver
    private let token = IOSVoiceRecorderAttemptToken()
    private let preparePending:
        IOSForegroundVoiceRecorderBridge.PreparePending
    private let feedback: IOSForegroundVoiceFeedbackBridge?
    private let feedbackHandle: IOSForegroundVoiceFeedbackAttemptHandle?
    private let warningSchedule: VoiceSessionWarningSchedule

    private var receiveTerminal: (@MainActor @Sendable (
        IOSForegroundVoiceWorkflowCaptureStopReason
    ) -> Void)?
    private var observationGeneration: UInt64 = 0
    private var terminalTask: Task<Void, Never>?
    private var pendingTerminalResult: IOSVoiceRecorderStopResult?
    private var terminalResultWasHandled = false
    private var stopTask:
        Task<IOSForegroundVoiceWorkflowCaptureStopResult, Never>?
    private var limitWarningTask: Task<Void, Never>?
    private var retainedCaptureBegan = false
    private var feedbackCloseWasForwarded = false

    init(
        driver: IOSForegroundVoiceRecorderBridgeDriver,
        preparePending: @escaping
            IOSForegroundVoiceRecorderBridge.PreparePending,
        feedback: IOSForegroundVoiceFeedbackBridge?,
        feedbackHandle: IOSForegroundVoiceFeedbackAttemptHandle?,
        warningSchedule: VoiceSessionWarningSchedule = .init(
            limit: .defaultValue
        )
    ) {
        self.driver = driver
        self.preparePending = preparePending
        self.feedback = feedback
        self.feedbackHandle = feedbackHandle
        self.warningSchedule = warningSchedule
    }

    var recording: IOSForegroundVoiceWorkflowRecording {
        IOSForegroundVoiceWorkflowRecording(
            start: { [self] in await start() },
            stop: { [self] reason in await stop(reason) },
            isActive: { [self] in
                driver.isActivelyRecording(token)
            },
            observeTerminal: { [self] receive in
                observeTerminal(receive)
            }
        )
    }

    private func start() async
        -> IOSForegroundVoiceWorkflowRecordingStartResult {
        let result = await driver.start(token)
        installTerminalWaitIfNeeded()

        switch result {
        case .recording:
            if let feedback {
                guard let feedbackHandle,
                      feedback.retainedCaptureDidBegin(
                          for: feedbackHandle
                      ) else {
                    if let feedbackHandle {
                        feedback.retainedCaptureDidNotBegin(
                            for: feedbackHandle
                        )
                    }
                    // The recorder has already crossed retained capture.
                    // Feedback state cannot grant destructive authority.
                    terminalResultWasHandled = true
                    pendingTerminalResult = await driver.stop(
                        token,
                        .interrupted
                    )
                    return .failed
                }
            }
            retainedCaptureBegan = true
            scheduleLimitWarnings()
            return .started
        case .cancelled:
            if let feedbackHandle {
                feedback?.retainedCaptureDidNotBegin(for: feedbackHandle)
            }
            return .cancelled
        case .busy, .failed:
            if let feedbackHandle {
                feedback?.retainedCaptureDidNotBegin(for: feedbackHandle)
            }
            return .failed
        }
    }

    private func stop(
        _ reason: IOSForegroundVoiceWorkflowCaptureStopReason
    ) async -> IOSForegroundVoiceWorkflowCaptureStopResult {
        if let stopTask { return await stopTask.value }
        let task = Task { @MainActor [self] in
            await performStop(reason)
        }
        stopTask = task
        let result = await task.value
        stopTask = nil
        return result
    }

    private func performStop(
        _ reason: IOSForegroundVoiceWorkflowCaptureStopReason
    ) async -> IOSForegroundVoiceWorkflowCaptureStopResult {
        terminalResultWasHandled = true
        let recorderResult: IOSVoiceRecorderStopResult
        if let pendingTerminalResult {
            self.pendingTerminalResult = nil
            recorderResult = pendingTerminalResult
        } else {
            let terminalDelivery = terminalTask
            recorderResult = await driver.stop(token, Self.map(reason))
            await terminalDelivery?.value
        }
        await forwardRecorderCloseIfNeeded(reason)
        return map(recorderResult)
    }

    private func observeTerminal(
        _ receive: @escaping @MainActor @Sendable (
            IOSForegroundVoiceWorkflowCaptureStopReason
        ) -> Void
    ) -> IOSForegroundVoiceWorkflowObservation {
        observationGeneration &+= 1
        if observationGeneration == 0 { observationGeneration = 1 }
        let generation = observationGeneration
        receiveTerminal = receive
        return IOSForegroundVoiceWorkflowObservation { [weak self] in
            guard let self,
                  self.observationGeneration == generation else {
                return
            }
            self.receiveTerminal = nil
        }
    }

    private func installTerminalWaitIfNeeded() {
        guard terminalTask == nil else { return }
        let wait = driver.waitForTerminal(token)
        terminalTask = Task { @MainActor [weak self, wait] in
            let event = await wait.value()
            guard !Task.isCancelled, let self else { return }
            await self.receive(event)
        }
    }

    private func receive(_ event: IOSVoiceRecorderTerminalEvent) async {
        terminalTask = nil
        guard let reason = Self.map(event.cause) else {
            release(event.result)
            return
        }
        if !terminalResultWasHandled {
            pendingTerminalResult = event.result
        }
        await forwardRecorderCloseIfNeeded(reason)
        receiveTerminal?(reason)
    }

    private func forwardRecorderCloseIfNeeded(
        _ reason: IOSForegroundVoiceWorkflowCaptureStopReason
    ) async {
        guard retainedCaptureBegan,
              !feedbackCloseWasForwarded,
              let feedbackHandle else {
            return
        }
        feedbackCloseWasForwarded = true
        limitWarningTask?.cancel()
        limitWarningTask = nil
        await feedback?.recorderDidClose(reason, for: feedbackHandle)
    }

    private func scheduleLimitWarnings() {
        guard let feedback, let feedbackHandle else {
            return
        }
        let clock = ContinuousClock()
        let startedAt = clock.now
        let warnings = warningSchedule.warnings
        limitWarningTask = Task { @MainActor [weak self] in
            for warning in warnings {
                do {
                    try await clock.sleep(
                        until: startedAt.advanced(
                            by: .seconds(warning.elapsedWholeSeconds)
                        )
                    )
                } catch {
                    return
                }
                guard let self,
                      !Task.isCancelled,
                      self.retainedCaptureBegan,
                      !self.feedbackCloseWasForwarded else {
                    return
                }
                feedback.playLimitWarning(
                    warning,
                    for: feedbackHandle
                )
            }
        }
    }

    private func map(
        _ result: IOSVoiceRecorderStopResult
    ) -> IOSForegroundVoiceWorkflowCaptureStopResult {
        switch result {
        case .completed(let capture):
            guard let handoff = capture.claimPersistenceHandoff() else {
                capture.release()
                return .preserved
            }
            return .completed(
                IOSForegroundVoiceWorkflowCaptureHandoff(
                    durationMilliseconds: capture.durationMilliseconds,
                    prepare: { [preparePending] configuration, retention in
                        try await preparePending(
                            handoff,
                            configuration,
                            retention
                        )
                    },
                    release: { handoff.release() }
                )
            )
        case .discarded:
            return .discarded
        case .invalid(let reason):
            return .invalid(reason)
        case .preserved:
            return .preserved
        case .stale:
            return .stale
        }
    }

    private func release(_ result: IOSVoiceRecorderStopResult) {
        if case .completed(let capture) = result { capture.release() }
    }

    private static func map(
        _ reason: IOSForegroundVoiceWorkflowCaptureStopReason
    ) -> IOSVoiceRecorderStopReason {
        switch reason {
        case .done: .done
        case .cancelled: .cancelled
        case .interrupted: .interrupted
        case .maximumDuration: .maximumDuration
        }
    }

    private static func map(
        _ cause: IOSVoiceRecorderTerminalCause
    ) -> IOSForegroundVoiceWorkflowCaptureStopReason? {
        switch cause {
        case .done:
            .done
        case .cancelled:
            .cancelled
        case .interrupted, .recorderEndedUnexpectedly, .failed:
            .interrupted
        case .maximumDuration:
            .maximumDuration
        case .stale:
            nil
        }
    }
}

private typealias AttemptOwner =
    IOSForegroundVoiceRecorderBridgeAttemptOwner

extension IOSForegroundVoiceRecorderBridge:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSForegroundVoiceRecorderBridge(<redacted>)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceRecorderBridgeDriver:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSForegroundVoiceRecorderBridgeDriver(<redacted>)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
