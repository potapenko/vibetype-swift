import AudioToolbox
import AVFAudio
import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypePersistence

nonisolated struct IOSVoiceRecorderAttemptToken:
    Equatable,
    Hashable,
    Sendable
{
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated struct IOSVoiceRecorderEncodingSettings: Equatable, Sendable {
    let formatID: UInt32
    let sampleRate: Double
    let channelCount: Int
    let encoderAudioQuality: Int

    static let foregroundAAC = Self(
        formatID: kAudioFormatMPEG4AAC,
        sampleRate: 44_100,
        channelCount: 1,
        encoderAudioQuality: AVAudioQuality.high.rawValue
    )
}

nonisolated enum IOSVoiceRecorderEvent: Equatable, Sendable {
    case finished(successfully: Bool)
    case encodeError
}

nonisolated enum IOSVoiceRecorderStartResult: Equatable, Sendable {
    case recording
    case cancelled
    case busy
    case failed(IOSVoiceRecorderFailure)
}

nonisolated enum IOSVoiceRecorderStopReason: Equatable, Sendable {
    case done
    case cancelled
    case interrupted
    case maximumDuration
}

nonisolated enum IOSVoiceRecorderFailure: String, Error, Equatable, Sendable {
    case recorderCreationFailed
    case checkpointFailed
    case prepareFailed
    case recordFailed
    case captureTransitionFailed
    case captureCompletionFailed
    case recorderEndedUnexpectedly
}

nonisolated enum IOSVoiceRecorderCompletedCaptureHandoffError:
    Error,
    Equatable,
    Sendable
{
    case unavailable
}

nonisolated enum IOSVoiceRecorderDiagnostic: String, Equatable, Sendable {
    case recorderCreated = "voice recorder created"
    case checkpointValidated = "voice recorder checkpoint validated"
    case retainedCaptureBegan = "retained capture began"
    case recorderStopped = "voice recorder stopped"
    case sourcePreserved = "voice capture source preserved"
    case sourceDiscarded = "voice capture source discarded"
    case sourceCompleted = "voice capture source completed"
    case recorderReportedUnsuccessfulFinish =
        "voice recorder reported unsuccessful finish"
    case staleCallbackIgnored = "stale recorder callback ignored"
    case operationFailed = "voice recorder operation failed"
}

@MainActor
final class IOSVoiceRecorderCompletedCaptureHandoff {
    typealias PreparePending = @MainActor @Sendable (
        IOSV1ForegroundVoicePersistenceOwner,
        TranscriptionConfiguration,
        IOSAcceptedAudioRetention
    ) async throws -> IOSV1PendingRecording

    private enum State {
        case available
        case preparing
        case transferred
        case released
    }

    private let preparePendingAction: PreparePending
    private let releaseToken: IOSVoiceRecorderMainActorActionToken
    private var state = State.available
    private var releaseWasRequested = false

    init(
        preparePending: @escaping PreparePending,
        release: @escaping @MainActor @Sendable () -> Void
    ) {
        preparePendingAction = preparePending
        releaseToken = IOSVoiceRecorderMainActorActionToken(release)
    }

    func preparePending(
        using owner: IOSV1ForegroundVoicePersistenceOwner,
        transcriptionConfiguration: TranscriptionConfiguration,
        acceptedAudioRetention: IOSAcceptedAudioRetention =
            .recordingCachePolicy
    ) async throws -> IOSV1PendingRecording {
        guard case .available = state else {
            throw IOSVoiceRecorderCompletedCaptureHandoffError.unavailable
        }
        state = .preparing
        do {
            let recording = try await preparePendingAction(
                owner,
                transcriptionConfiguration,
                acceptedAudioRetention
            )
            state = .transferred
            releaseOnce()
            return recording
        } catch {
            // A failed or uncertain Persistence handoff keeps the exact
            // completed source alive. The caller may retry this capability or
            // release it into ordinary capture-source recovery.
            if releaseWasRequested {
                state = .released
                releaseOnce()
            } else {
                state = .available
            }
            throw error
        }
    }

    func release() {
        switch state {
        case .available:
            state = .released
            releaseOnce()
        case .preparing:
            releaseWasRequested = true
        case .transferred, .released:
            break
        }
    }

    private func releaseOnce() {
        releaseToken.run()
    }
}

@MainActor
final class IOSVoiceRecorderCompletedCapture {
    let durationMilliseconds: Int64
    let byteCount: Int64

    private var handoff: IOSVoiceRecorderCompletedCaptureHandoff?

    init(
        durationMilliseconds: Int64,
        byteCount: Int64,
        preparePending: @escaping
            IOSVoiceRecorderCompletedCaptureHandoff.PreparePending = {
                _, _, _ in
                throw IOSVoiceRecorderCompletedCaptureHandoffError
                    .unavailable
            },
        release: @escaping @MainActor @Sendable () -> Void
    ) {
        self.durationMilliseconds = durationMilliseconds
        self.byteCount = byteCount
        handoff = IOSVoiceRecorderCompletedCaptureHandoff(
            preparePending: preparePending,
            release: release
        )
    }

    convenience init(capture: IOSV1ForegroundVoiceCompletedCapture) {
        self.init(
            durationMilliseconds: capture.durationMilliseconds,
            byteCount: capture.byteCount,
            preparePending: { owner, configuration, retention in
                try await owner.prepareCompletedCapture(
                    capture,
                    transcriptionConfiguration: configuration,
                    acceptedAudioRetention: retention
                )
            },
            release: { capture.release() }
        )
    }

    /// Transfers ownership of the opaque descriptor-bound capability once.
    /// Neither this wrapper nor the handoff exposes the capture URL.
    func claimPersistenceHandoff()
        -> IOSVoiceRecorderCompletedCaptureHandoff? {
        defer { handoff = nil }
        return handoff
    }

    func release() {
        handoff?.release()
        handoff = nil
    }

}

nonisolated enum IOSVoiceRecorderStopResult: Sendable {
    case completed(IOSVoiceRecorderCompletedCapture)
    case invalid(IOSV1ForegroundVoiceCaptureInvalidReason)
    case discarded
    case preserved(IOSVoiceRecorderFailure)
    case stale
}

nonisolated enum IOSVoiceRecorderTerminalCause: Equatable, Sendable {
    case done
    case cancelled
    case interrupted
    case maximumDuration
    case recorderEndedUnexpectedly
    case failed(IOSVoiceRecorderFailure)
    case stale
}

nonisolated struct IOSVoiceRecorderTerminalEvent: Sendable {
    let cause: IOSVoiceRecorderTerminalCause
    let result: IOSVoiceRecorderStopResult

    static let stale = Self(cause: .stale, result: .stale)
}

/// Single-use ownership of one terminal-event claim. Keeping or awaiting this
/// handle never keeps the recorder adapter alive. Dropping or cancelling it
/// releases an unfulfilled claim so a replacement workflow waiter can attach.
@MainActor
final class IOSVoiceRecorderTerminalWait {
    typealias Wait = @MainActor @Sendable () async ->
        IOSVoiceRecorderTerminalEvent
    typealias Cancel = @MainActor @Sendable () -> Void

    private enum State {
        case available
        case waiting
        case resolved
    }

    private let waitAction: Wait
    private let cancelToken: IOSVoiceRecorderMainActorActionToken
    private var state = State.available

    init(
        wait: @escaping Wait,
        cancel: Cancel? = nil
    ) {
        waitAction = wait
        cancelToken = IOSVoiceRecorderMainActorActionToken(cancel)
    }

    func value() async -> IOSVoiceRecorderTerminalEvent {
        guard case .available = state else { return .stale }
        state = .waiting
        let event = await withTaskCancellationHandler {
            await waitAction()
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
        state = .resolved
        cancelToken.discard()
        return event
    }

    func cancel() {
        if case .resolved = state { return }
        state = .resolved
        cancelToken.run()
    }
}

/// Thread-safe exact-once storage for a MainActor cleanup action. The normal
/// owner path calls `run()` synchronously on MainActor. If the last reference
/// instead disappears on another executor, token deinitialization performs one
/// supported asynchronous hop without assuming executor identity.
private nonisolated final class IOSVoiceRecorderMainActorActionToken:
    @unchecked Sendable {
    typealias Action = @MainActor @Sendable () -> Void

    private let lock = NSLock()
    private var action: Action?

    init(_ action: Action?) {
        self.action = action
    }

    @MainActor
    func run() {
        take()?()
    }

    func discard() {
        _ = take()
    }

    private func take() -> Action? {
        lock.lock()
        defer { lock.unlock() }
        let pendingAction: Action? = action
        self.action = nil
        return pendingAction
    }

    deinit {
        guard let action = take() else { return }
        Task { @MainActor in action() }
    }
}

@MainActor
protocol IOSVoiceAudioRecorder: AnyObject {
    var currentTime: TimeInterval { get }
    var isRecording: Bool { get }

    func prepareToRecord() -> Bool
    func record(forDuration duration: TimeInterval) -> Bool
    func normalizedPowerLevel() -> Double?
    func stop()
}

enum IOSVoiceAudioMeter {
    static let silenceFloorDecibels: Float = -60

    static func normalizedLevel(decibels: Float) -> Double? {
        guard decibels.isFinite else { return nil }
        let clamped = min(0, max(silenceFloorDecibels, decibels))
        return Double(
            (clamped - silenceFloorDecibels) / -silenceFloorDecibels
        )
    }
}

nonisolated struct IOSVoiceRecorderClient: Sendable {
    typealias EventHandler = @MainActor @Sendable (
        IOSVoiceRecorderEvent
    ) -> Void
    typealias MakeRecorder = @MainActor @Sendable (
        URL,
        IOSVoiceRecorderEncodingSettings,
        @escaping EventHandler
    ) throws -> any IOSVoiceAudioRecorder
    typealias Sleep = @MainActor @Sendable (Duration) async throws -> Void
    typealias MonotonicNow = @MainActor @Sendable () -> TimeInterval

    let makeRecorder: MakeRecorder
    let sleep: Sleep
    let monotonicNow: MonotonicNow

    init(
        makeRecorder: @escaping MakeRecorder,
        sleep: @escaping Sleep,
        monotonicNow: @escaping MonotonicNow = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.makeRecorder = makeRecorder
        self.sleep = sleep
        self.monotonicNow = monotonicNow
    }

    nonisolated static let live = Self(
        makeRecorder: { url, settings, receive in
            try IOSVoiceAVAudioRecorder(
                url: url,
                settings: settings,
                receive: receive
            )
        },
        sleep: { duration in
            try await ContinuousClock().sleep(for: duration)
        },
        monotonicNow: {
            ProcessInfo.processInfo.systemUptime
        }
    )
}

@MainActor
protocol IOSVoiceRecorderCaptureSourceSystem: AnyObject {
    func withTransientRecordingURL(
        _ body: (URL) throws -> Void
    ) throws
    func revalidateRecorderCheckpoint() async throws
    func beginFinalizing() async throws
    func completeAfterRecorderClose(
        fallbackDurationMilliseconds: Int64?
    ) async throws
        -> IOSVoiceRecorderCaptureFinalization
    func beginDiscardingBeforeRecorderStop() async throws
    func finishDiscardAfterRecorderStop() async throws
    func release()
}

nonisolated enum IOSVoiceRecorderCaptureFinalization: Sendable {
    case completed(IOSVoiceRecorderCompletedCapture)
    case discarded(IOSV1ForegroundVoiceCaptureInvalidReason)
}

/// Fail-closed candidate around AVAudioRecorder. It owns recorder lifetime but
/// never exposes or stores the capture source URL outside the lease callback.
@MainActor
final class IOSVoiceRecorderAdapter {
    typealias DiagnosticHandler = @MainActor @Sendable (
        IOSVoiceRecorderDiagnostic
    ) -> Void

    // Default-value aliases remain useful to qualification tests and callers
    // that do not choose a custom limit. Live attempts use the frozen instance
    // value below.
    nonisolated static let maximumDuration =
        RecordingDurationLimit.defaultValue.duration
    nonisolated static let maximumDurationWatchdog: Duration = .seconds(
        RecordingDurationLimit.defaultValue.wholeSeconds
    )
    nonisolated static let recorderSafetyDuration =
        RecordingDurationLimit.defaultValue.duration + 1

    private enum Phase {
        case idle
        case arming
        case recording
        case stopping
    }

    private enum InternalStopReason {
        case done
        case cancelled
        case interrupted
        case maximumDuration
        case recorderEnded
        case preserveFailure(IOSVoiceRecorderFailure)
    }

    private final class Attempt {
        let token: IOSVoiceRecorderAttemptToken
        let generation: UInt64
        var recorder: (any IOSVoiceAudioRecorder)?
        var deferredRecorderEvent: IOSVoiceRecorderEvent?
        var pendingStopReason: InternalStopReason?
        var stopTask: Task<IOSVoiceRecorderStopResult, Never>?
        var terminalCause: IOSVoiceRecorderTerminalCause?
        var terminalWaiter: TerminalWaiter?
        var stopWaiters: [
            CheckedContinuation<IOSVoiceRecorderStopResult, Never>
        ] = []
        var maximumDurationTask: Task<Void, Never>?
        var recordingStartedAt: TimeInterval?
        var finalizedElapsedMilliseconds: Int64?
        private var recorderWasStopped = false
        private var sourceWasReleased = false

        init(token: IOSVoiceRecorderAttemptToken, generation: UInt64) {
            self.token = token
            self.generation = generation
        }

        func stopRecorderOnce() -> Bool {
            guard !recorderWasStopped, let recorder else { return false }
            recorderWasStopped = true
            recorder.stop()
            return true
        }

        func releaseSourceOnce(
            _ source: any IOSVoiceRecorderCaptureSourceSystem
        ) -> Bool {
            guard !sourceWasReleased else { return false }
            sourceWasReleased = true
            source.release()
            return true
        }
    }

    @MainActor
    private final class TerminalWaiter: Sendable {
        let identifier: UInt64
        private var continuation:
            CheckedContinuation<IOSVoiceRecorderTerminalEvent, Never>?
        private var bufferedEvent: IOSVoiceRecorderTerminalEvent?
        private var wasResolved = false

        init(identifier: UInt64) {
            self.identifier = identifier
        }

        func value() async -> IOSVoiceRecorderTerminalEvent {
            if let bufferedEvent {
                self.bufferedEvent = nil
                return bufferedEvent
            }
            return await withCheckedContinuation { continuation in
                guard !wasResolved else {
                    continuation.resume(returning: .stale)
                    return
                }
                self.continuation = continuation
            }
        }

        func resolve(with event: IOSVoiceRecorderTerminalEvent) {
            guard !wasResolved else { return }
            wasResolved = true
            if let continuation {
                self.continuation = nil
                continuation.resume(returning: event)
            } else {
                bufferedEvent = event
            }
        }
    }

    private final class WeakCompletedCapture {
        weak var value: IOSVoiceRecorderCompletedCapture?

        init(_ value: IOSVoiceRecorderCompletedCapture) {
            self.value = value
        }
    }

    private enum StoredTerminalResult {
        case completed(WeakCompletedCapture)
        case invalid(IOSV1ForegroundVoiceCaptureInvalidReason)
        case discarded
        case preserved(IOSVoiceRecorderFailure)
        case stale

        init(_ result: IOSVoiceRecorderStopResult) {
            switch result {
            case let .completed(capture):
                self = .completed(WeakCompletedCapture(capture))
            case let .invalid(reason):
                self = .invalid(reason)
            case .discarded:
                self = .discarded
            case let .preserved(failure):
                self = .preserved(failure)
            case .stale:
                self = .stale
            }
        }

        func materialize() -> IOSVoiceRecorderStopResult? {
            switch self {
            case let .completed(reference):
                reference.value.map(IOSVoiceRecorderStopResult.completed)
            case let .invalid(reason):
                .invalid(reason)
            case .discarded:
                .discarded
            case let .preserved(failure):
                .preserved(failure)
            case .stale:
                .stale
            }
        }
    }

    private let captureSource: any IOSVoiceRecorderCaptureSourceSystem
    private let client: IOSVoiceRecorderClient
    private let diagnose: DiagnosticHandler
    private let recordingDurationLimit: RecordingDurationLimit
    private var phase = Phase.idle
    private var activeAttempt: Attempt?
    private var nextGeneration: UInt64 = 0
    private var nextTerminalWaiterIdentifier: UInt64 = 0
    private var lastTerminal: LastTerminal?
    private var activeAttemptTeardown: IOSVoiceRecorderMainActorActionToken?

    private struct LastTerminal {
        let token: IOSVoiceRecorderAttemptToken
        let cause: IOSVoiceRecorderTerminalCause
        let storedResult: StoredTerminalResult
        var eventWasConsumed: Bool

        func result() -> IOSVoiceRecorderStopResult {
            storedResult.materialize() ?? .stale
        }

        func event() -> IOSVoiceRecorderTerminalEvent {
            guard let result = storedResult.materialize() else {
                return .stale
            }
            return IOSVoiceRecorderTerminalEvent(cause: cause, result: result)
        }
    }

    convenience init(
        lease: IOSV1ForegroundVoiceCaptureLease,
        recordingDurationLimit: RecordingDurationLimit = .defaultValue,
        client: IOSVoiceRecorderClient = .live,
        diagnose: @escaping DiagnosticHandler = { _ in }
    ) {
        self.init(
            captureSource: IOSVoiceRecorderCaptureSourceLeaseSystem(
                lease: lease
            ),
            recordingDurationLimit: recordingDurationLimit,
            client: client,
            diagnose: diagnose
        )
    }

    init(
        captureSource: any IOSVoiceRecorderCaptureSourceSystem,
        recordingDurationLimit: RecordingDurationLimit = .defaultValue,
        client: IOSVoiceRecorderClient,
        diagnose: @escaping DiagnosticHandler = { _ in }
    ) {
        self.captureSource = captureSource
        self.recordingDurationLimit = recordingDurationLimit
        self.client = client
        self.diagnose = diagnose
    }

    private func installTeardown(for attempt: Attempt) {
        let captureSource = captureSource
        activeAttemptTeardown = IOSVoiceRecorderMainActorActionToken {
            [attempt, captureSource] in
            attempt.maximumDurationTask?.cancel()
            attempt.maximumDurationTask = nil
            attempt.terminalWaiter?.resolve(with: .stale)
            attempt.terminalWaiter = nil
            if attempt.stopTask == nil {
                _ = attempt.stopRecorderOnce()
                _ = attempt.releaseSourceOnce(captureSource)
            }
        }
    }

    private func retireTeardown() {
        activeAttemptTeardown?.discard()
        activeAttemptTeardown = nil
    }

    func start(
        for token: IOSVoiceRecorderAttemptToken
    ) async -> IOSVoiceRecorderStartResult {
        guard activeAttempt == nil, phase == .idle else { return .busy }

        let attempt = Attempt(
            token: token,
            generation: makeGeneration()
        )
        activeAttempt = attempt
        installTeardown(for: attempt)
        lastTerminal = nil
        phase = .arming
        let generation = attempt.generation

        return await withTaskCancellationHandler {
            markTaskCancellationIfNeeded(attempt)
            return await arm(attempt)
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.requestStartTaskCancellation(
                    token: token,
                    generation: generation
                )
            }
        }
    }

    private func arm(
        _ attempt: Attempt
    ) async -> IOSVoiceRecorderStartResult {
        let token = attempt.token
        if let result = await finishPendingArmingStopIfNeeded(attempt) {
            return result
        }

        do {
            try captureSource.withTransientRecordingURL { url in
                attempt.recorder = try client.makeRecorder(
                    url,
                    .foregroundAAC
                ) { [weak self] event in
                    self?.receiveRecorderEvent(
                        event,
                        token: token,
                        generation: attempt.generation
                    )
                }
            }
            diagnose(.recorderCreated)
        } catch {
            return await failStart(
                attempt,
                failure: .recorderCreationFailed
            )
        }

        if let event = attempt.deferredRecorderEvent {
            attempt.deferredRecorderEvent = nil
            receiveRecorderEvent(
                event,
                token: token,
                generation: attempt.generation
            )
        }
        markTaskCancellationIfNeeded(attempt)
        if let result = await finishPendingArmingStopIfNeeded(attempt) {
            return result
        }

        do {
            try await captureSource.revalidateRecorderCheckpoint()
            diagnose(.checkpointValidated)
        } catch {
            // Identity uncertainty wins over cancellation. The exact source is
            // preserved when checkpoint proof did not complete.
            return await failStart(
                attempt,
                failure: .checkpointFailed
            )
        }
        markTaskCancellationIfNeeded(attempt)
        if let result = await finishPendingArmingStopIfNeeded(attempt) {
            return result
        }

        guard let recorder = attempt.recorder else {
            return await failStart(
                attempt,
                failure: .recorderCreationFailed
            )
        }
        let prepared = recorder.prepareToRecord()
        markTaskCancellationIfNeeded(attempt)
        if let result = await finishPendingArmingStopIfNeeded(attempt) {
            return result
        }

        do {
            try await captureSource.revalidateRecorderCheckpoint()
            diagnose(.checkpointValidated)
        } catch {
            // The post-prepare proof is also fail-closed under cancellation.
            return await failStart(
                attempt,
                failure: .checkpointFailed
            )
        }
        markTaskCancellationIfNeeded(attempt)
        if let result = await finishPendingArmingStopIfNeeded(attempt) {
            return result
        }
        guard prepared else {
            return await failStart(
                attempt,
                failure: .prepareFailed
            )
        }

        attempt.recordingStartedAt = client.monotonicNow()
        let didRecord = recorder.record(
            forDuration: recorderSafetyDuration
        )
        markTaskCancellationIfNeeded(attempt)
        if let result = await finishPendingArmingStopIfNeeded(attempt) {
            return result
        }
        guard didRecord else {
            return await failStart(
                attempt,
                failure: .recordFailed
            )
        }

        phase = .recording
        markTaskCancellationIfNeeded(attempt)
        if let result = await finishPendingArmingStopIfNeeded(attempt) {
            return result
        }
        scheduleMaximumDuration(for: attempt)
        diagnose(.retainedCaptureBegan)
        return .recording
    }

    func stop(
        for token: IOSVoiceRecorderAttemptToken,
        reason: IOSVoiceRecorderStopReason
    ) async -> IOSVoiceRecorderStopResult {
        guard let attempt = activeAttempt, attempt.token == token else {
            if let lastTerminal, lastTerminal.token == token {
                return lastTerminal.result()
            }
            return .stale
        }
        if let task = attempt.stopTask { return await task.value }

        let internalReason: InternalStopReason = switch reason {
        case .done:
            .done
        case .cancelled:
            .cancelled
        case .interrupted:
            .interrupted
        case .maximumDuration:
            .maximumDuration
        }

        guard phase != .arming else {
            if attempt.pendingStopReason == nil {
                attempt.pendingStopReason = internalReason
            }
            return await withCheckedContinuation { continuation in
                attempt.stopWaiters.append(continuation)
            }
        }
        return await beginStop(attempt, reason: internalReason)
    }

    /// Delivers the terminal event for an attempt exactly once. The event is
    /// independent of the idempotent `stop` result so an internal watchdog or
    /// delegate-owned stop cannot leave a workflow waiting in Listening.
    func waitForTerminal(
        for token: IOSVoiceRecorderAttemptToken
    ) -> IOSVoiceRecorderTerminalWait {
        claimTerminalWait(for: token)
    }

    func isActivelyRecording(
        for token: IOSVoiceRecorderAttemptToken
    ) -> Bool {
        guard phase == .recording,
              let attempt = activeAttempt,
              attempt.token == token else {
            return false
        }
        return attempt.recorder?.isRecording == true
    }

    func presentationInputLevel(
        for token: IOSVoiceRecorderAttemptToken
    ) -> Double? {
        guard phase == .recording,
              let attempt = activeAttempt,
              attempt.token == token,
              let recorder = attempt.recorder,
              recorder.isRecording else {
            return nil
        }
        return recorder.normalizedPowerLevel()
    }

    private func claimTerminalWait(
        for token: IOSVoiceRecorderAttemptToken
    ) -> IOSVoiceRecorderTerminalWait {
        guard !Task.isCancelled else {
            return IOSVoiceRecorderTerminalWait(wait: { .stale })
        }
        if let attempt = activeAttempt, attempt.token == token {
            guard attempt.terminalWaiter == nil else {
                return IOSVoiceRecorderTerminalWait(wait: { .stale })
            }
            nextTerminalWaiterIdentifier &+= 1
            if nextTerminalWaiterIdentifier == 0 {
                nextTerminalWaiterIdentifier = 1
            }
            let waiter = TerminalWaiter(
                identifier: nextTerminalWaiterIdentifier
            )
            attempt.terminalWaiter = waiter
            let generation = attempt.generation
            return IOSVoiceRecorderTerminalWait(
                wait: { await waiter.value() },
                cancel: { [weak self] in
                    if let self {
                        self.cancelTerminalWait(
                            waiter,
                            token: token,
                            generation: generation
                        )
                    } else {
                        waiter.resolve(with: .stale)
                    }
                }
            )
        }

        guard var terminal = lastTerminal,
              terminal.token == token,
              !terminal.eventWasConsumed else {
            return IOSVoiceRecorderTerminalWait(wait: { .stale })
        }
        terminal.eventWasConsumed = true
        lastTerminal = terminal
        let event = terminal.event()
        return IOSVoiceRecorderTerminalWait(wait: { event })
    }

    private func cancelTerminalWait(
        _ waiter: TerminalWaiter,
        token: IOSVoiceRecorderAttemptToken,
        generation: UInt64
    ) {
        guard let attempt = activeAttempt,
              attempt.token == token,
              attempt.generation == generation,
              attempt.terminalWaiter === waiter else {
            waiter.resolve(with: .stale)
            return
        }
        attempt.terminalWaiter = nil
        waiter.resolve(with: .stale)
    }

    private func failStart(
        _ attempt: Attempt,
        failure: IOSVoiceRecorderFailure
    ) async -> IOSVoiceRecorderStartResult {
        // AVAudioRecorder may already have emitted container headers or media
        // before prepare/record reports false. Internal arming failure has no
        // authority to unlink that unclassified source; live/launch repair
        // proves exact zero or promotes positive bytes after recorder close.
        let result = await beginStop(
            attempt,
            reason: .preserveFailure(failure)
        )
        if case let .preserved(cleanupFailure) = result,
           cleanupFailure != failure {
            return .failed(cleanupFailure)
        }
        return .failed(failure)
    }

    private func finishPendingArmingStopIfNeeded(
        _ attempt: Attempt
    ) async -> IOSVoiceRecorderStartResult? {
        guard let reason = attempt.pendingStopReason else { return nil }
        attempt.pendingStopReason = nil
        let effectiveReason: InternalStopReason
        let startResult: IOSVoiceRecorderStartResult
        switch reason {
        case let .preserveFailure(failure):
            effectiveReason = reason
            startResult = .failed(failure)
        case .recorderEnded:
            effectiveReason = .recorderEnded
            startResult = .failed(.recorderEndedUnexpectedly)
        case .done:
            effectiveReason = .done
            startResult = .cancelled
        case .cancelled:
            effectiveReason = .cancelled
            startResult = .cancelled
        case .interrupted:
            effectiveReason = .interrupted
            startResult = .cancelled
        case .maximumDuration:
            effectiveReason = .maximumDuration
            startResult = .cancelled
        }
        let stopResult = await beginStop(attempt, reason: effectiveReason)
        if case let .preserved(cleanupFailure) = stopResult {
            return .failed(cleanupFailure)
        }
        return startResult
    }

    private func markTaskCancellationIfNeeded(_ attempt: Attempt) {
        guard Task.isCancelled, attempt.pendingStopReason == nil else {
            return
        }
        // Task ownership is not user authority to discard captured audio.
        // Explicit Cancel reaches the adapter through stop(..., .cancelled).
        attempt.pendingStopReason = .interrupted
    }

    private func requestStartTaskCancellation(
        token: IOSVoiceRecorderAttemptToken,
        generation: UInt64
    ) {
        guard let attempt = activeAttempt,
              attempt.token == token,
              attempt.generation == generation else {
            return
        }
        switch phase {
        case .arming:
            if attempt.pendingStopReason == nil {
                attempt.pendingStopReason = .interrupted
            }
        case .recording:
            _ = claimStopAuthority(attempt, reason: .interrupted)
        case .idle, .stopping:
            break
        }
    }

    private func beginStop(
        _ attempt: Attempt,
        reason: InternalStopReason
    ) async -> IOSVoiceRecorderStopResult {
        guard let task = claimStopAuthority(attempt, reason: reason) else {
            return terminalResult(for: attempt.token)
        }
        return await task.value
    }

    /// Claims terminal authority without suspension. Delegate, watchdog, and
    /// explicit actions all use this gate so callback observation order is the
    /// stop order even though source cleanup remains asynchronous.
    private func claimStopAuthority(
        _ attempt: Attempt,
        reason: InternalStopReason
    ) -> Task<IOSVoiceRecorderStopResult, Never>? {
        if let task = attempt.stopTask { return task }
        guard activeAttempt === attempt else { return nil }

        phase = .stopping
        attempt.maximumDurationTask?.cancel()
        attempt.maximumDurationTask = nil
        attempt.finalizedElapsedMilliseconds = elapsedMilliseconds(
            for: attempt
        )
        attempt.terminalCause = terminalCause(for: reason)
        let task = Task { @MainActor [self, attempt] in
            let result = await executeStop(attempt, reason: reason)
            finishAttempt(attempt, result: result)
            return result
        }
        attempt.stopTask = task
        return task
    }

    private func executeStop(
        _ attempt: Attempt,
        reason: InternalStopReason
    ) async -> IOSVoiceRecorderStopResult {
        switch reason {
        case .done, .interrupted, .maximumDuration:
            return await finalizeCompletedAttempt(attempt)
        case .preserveFailure(let failure):
            stopRecorder(attempt)
            preserveSource(attempt)
            return .preserved(failure)
        case .recorderEnded:
            // A recorder/encoder callback can arrive after useful audio was
            // already written. Close and validate that exact source while the
            // live lease still owns it so a valid partial becomes completed
            // local recovery. The terminal cause remains unexpected, which
            // prevents the workflow from treating this as Done or dispatching
            // provider work automatically.
            return await finalizeCompletedAttempt(attempt)
        case .cancelled:
            return await discardAttempt(attempt, reason: reason)
        }
    }

    private func finalizeCompletedAttempt(
        _ attempt: Attempt
    ) async -> IOSVoiceRecorderStopResult {
        do {
            try await captureSource.beginFinalizing()
        } catch {
            diagnose(.operationFailed)
            stopRecorder(attempt)
            preserveSource(attempt)
            return .preserved(.captureTransitionFailed)
        }

        stopRecorder(attempt)
        do {
            let finalization = try await captureSource
                .completeAfterRecorderClose(
                    fallbackDurationMilliseconds:
                        attempt.finalizedElapsedMilliseconds
                )
            switch finalization {
            case let .completed(completed):
                diagnose(.sourceCompleted)
                return .completed(completed)
            case let .discarded(reason):
                diagnose(.sourceDiscarded)
                return .invalid(reason)
            }
        } catch {
            diagnose(.operationFailed)
            preserveSource(attempt)
            return .preserved(.captureCompletionFailed)
        }
    }

    private func discardAttempt(
        _ attempt: Attempt,
        reason: InternalStopReason
    ) async -> IOSVoiceRecorderStopResult {
        do {
            try await captureSource.beginDiscardingBeforeRecorderStop()
        } catch {
            diagnose(.operationFailed)
            stopRecorder(attempt)
            preserveSource(attempt)
            return .preserved(.captureTransitionFailed)
        }

        stopRecorder(attempt)
        do {
            try await captureSource.finishDiscardAfterRecorderStop()
            diagnose(.sourceDiscarded)
        } catch {
            diagnose(.operationFailed)
            preserveSource(attempt)
            return .preserved(.captureCompletionFailed)
        }

        switch reason {
        case .maximumDuration:
            return .invalid(.maximumDurationReached)
        case .done, .cancelled, .interrupted, .recorderEnded,
             .preserveFailure:
            return .discarded
        }
    }

    private func stopRecorder(_ attempt: Attempt) {
        if attempt.stopRecorderOnce() { diagnose(.recorderStopped) }
    }

    private func preserveSource(_ attempt: Attempt) {
        if attempt.releaseSourceOnce(captureSource) {
            diagnose(.sourcePreserved)
        }
    }

    private func finishAttempt(
        _ attempt: Attempt,
        result: IOSVoiceRecorderStopResult
    ) {
        guard activeAttempt === attempt else { return }
        attempt.stopTask = nil
        activeAttempt = nil
        retireTeardown()
        phase = .idle
        let event = IOSVoiceRecorderTerminalEvent(
            cause: attempt.terminalCause ?? .failed(.recorderEndedUnexpectedly),
            result: result
        )
        let terminalWaiter = attempt.terminalWaiter
        attempt.terminalWaiter = nil
        lastTerminal = LastTerminal(
            token: attempt.token,
            cause: event.cause,
            storedResult: StoredTerminalResult(result),
            eventWasConsumed: terminalWaiter != nil
        )
        let waiters = attempt.stopWaiters
        attempt.stopWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: result) }
        terminalWaiter?.resolve(with: event)
    }

    private func terminalResult(
        for token: IOSVoiceRecorderAttemptToken
    ) -> IOSVoiceRecorderStopResult {
        guard let lastTerminal, lastTerminal.token == token else {
            return .stale
        }
        return lastTerminal.result()
    }

    private func terminalCause(
        for reason: InternalStopReason
    ) -> IOSVoiceRecorderTerminalCause {
        switch reason {
        case .done:
            .done
        case .cancelled:
            .cancelled
        case .interrupted:
            .interrupted
        case .maximumDuration:
            .maximumDuration
        case .recorderEnded:
            .recorderEndedUnexpectedly
        case .preserveFailure(let failure):
            .failed(failure)
        }
    }

    private func receiveRecorderEvent(
        _ event: IOSVoiceRecorderEvent,
        token: IOSVoiceRecorderAttemptToken,
        generation: UInt64
    ) {
        guard let attempt = activeAttempt,
              attempt.token == token,
              attempt.generation == generation else {
            diagnose(.staleCallbackIgnored)
            return
        }
        guard attempt.recorder != nil else {
            guard attempt.deferredRecorderEvent == nil else {
                diagnose(.staleCallbackIgnored)
                return
            }
            attempt.deferredRecorderEvent = event
            return
        }

        switch phase {
        case .arming:
            if attempt.pendingStopReason == nil {
                attempt.pendingStopReason = .recorderEnded
            }
        case .recording:
            _ = claimStopAuthority(
                attempt,
                reason: stopReason(for: event, attempt: attempt)
            )
        case .stopping:
            break
        case .idle:
            diagnose(.staleCallbackIgnored)
        }
    }

    private func stopReason(
        for event: IOSVoiceRecorderEvent,
        attempt: Attempt
    ) -> InternalStopReason {
        if case .finished(successfully: false) = event {
            diagnose(.recorderReportedUnsuccessfulFinish)
        }
        guard let startedAt = attempt.recordingStartedAt,
              startedAt.isFinite else {
            return .recorderEnded
        }
        let now = client.monotonicNow()
        guard now.isFinite,
              now >= startedAt,
              now - startedAt >= maximumDuration else {
            return .recorderEnded
        }
        return .maximumDuration
    }

    private func elapsedMilliseconds(for attempt: Attempt) -> Int64? {
        guard let startedAt = attempt.recordingStartedAt,
              startedAt.isFinite else { return nil }
        let stoppedAt = client.monotonicNow()
        guard stoppedAt.isFinite, stoppedAt >= startedAt else { return nil }
        let milliseconds = (stoppedAt - startedAt) * 1_000
        guard milliseconds.isFinite, milliseconds >= 0,
              milliseconds <= Double(Int64.max) else { return nil }
        return Int64(milliseconds.rounded(.toNearestOrAwayFromZero))
    }

    private func scheduleMaximumDuration(for attempt: Attempt) {
        let sleep = client.sleep
        let maximumDurationWatchdog = maximumDurationWatchdog
        attempt.maximumDurationTask = Task { @MainActor [weak self] in
            do {
                try await sleep(maximumDurationWatchdog)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else {
                    return
                }
            }
            guard let self,
                  self.activeAttempt === attempt,
                  self.phase == .recording else {
                return
            }
            _ = self.claimStopAuthority(
                attempt,
                reason: .maximumDuration
            )
        }
    }

    private func makeGeneration() -> UInt64 {
        nextGeneration &+= 1
        if nextGeneration == 0 { nextGeneration = 1 }
        return nextGeneration
    }

    private var maximumDuration: TimeInterval {
        recordingDurationLimit.duration
    }

    private var maximumDurationWatchdog: Duration {
        .seconds(recordingDurationLimit.wholeSeconds)
    }

    private var recorderSafetyDuration: TimeInterval {
        maximumDuration + 1
    }
}

@MainActor
private final class IOSVoiceRecorderCaptureSourceLeaseSystem:
    IOSVoiceRecorderCaptureSourceSystem
{
    private let lease: IOSV1ForegroundVoiceCaptureLease

    init(lease: IOSV1ForegroundVoiceCaptureLease) {
        self.lease = lease
    }

    func withTransientRecordingURL(
        _ body: (URL) throws -> Void
    ) throws {
        try lease.withTransientRecordingURL(body)
    }

    func revalidateRecorderCheckpoint() async throws {
        try lease.revalidateRecorderCheckpoint()
    }

    func beginFinalizing() async throws {
        try await lease.beginFinalizing()
    }

    func completeAfterRecorderClose(
        fallbackDurationMilliseconds: Int64?
    ) async throws
        -> IOSVoiceRecorderCaptureFinalization {
        switch try await lease.completeAfterRecorderClose(
            fallbackDurationMilliseconds: fallbackDurationMilliseconds
        ) {
        case let .completed(capture):
            return .completed(IOSVoiceRecorderCompletedCapture(capture: capture))
        case let .discarded(reason):
            return .discarded(reason)
        }
    }

    func beginDiscardingBeforeRecorderStop() async throws {
        try await lease.beginDiscardingBeforeRecorderStop()
    }

    func finishDiscardAfterRecorderStop() async throws {
        try await lease.finishDiscardAfterRecorderStop()
    }

    func release() { lease.release() }
}

@MainActor
final class IOSVoiceAVAudioRecorderDelegateBridge:
    NSObject,
    AVAudioRecorderDelegate
{
    private let receive: IOSVoiceRecorderClient.EventHandler

    init(
        receive: @escaping IOSVoiceRecorderClient.EventHandler
    ) {
        self.receive = receive
        super.init()
    }

    nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        recorderDidFinish(successfully: flag)
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: Error?
    ) {
        recorderEncodeFailed()
    }

    nonisolated func recorderDidFinish(successfully flag: Bool) {
        enqueue(.finished(successfully: flag))
    }

    nonisolated func recorderEncodeFailed() {
        enqueue(.encodeError)
    }

    private nonisolated func enqueue(_ event: IOSVoiceRecorderEvent) {
        Task { @MainActor [receive] in
            receive(event)
        }
    }
}

@MainActor
private final class IOSVoiceAVAudioRecorder: IOSVoiceAudioRecorder {
    private let recorder: AVAudioRecorder
    private let delegateBridge: IOSVoiceAVAudioRecorderDelegateBridge

    init(
        url: URL,
        settings: IOSVoiceRecorderEncodingSettings,
        receive: @escaping IOSVoiceRecorderClient.EventHandler
    ) throws {
        recorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: settings.formatID,
                AVSampleRateKey: settings.sampleRate,
                AVNumberOfChannelsKey: settings.channelCount,
                AVEncoderAudioQualityKey: settings.encoderAudioQuality,
            ]
        )
        delegateBridge = IOSVoiceAVAudioRecorderDelegateBridge(receive: receive)
        recorder.delegate = delegateBridge
        recorder.isMeteringEnabled = true
    }

    var currentTime: TimeInterval { recorder.currentTime }
    var isRecording: Bool { recorder.isRecording }

    func prepareToRecord() -> Bool { recorder.prepareToRecord() }

    func record(forDuration duration: TimeInterval) -> Bool {
        recorder.record(forDuration: duration)
    }

    func normalizedPowerLevel() -> Double? {
        guard recorder.isRecording else { return nil }
        recorder.updateMeters()
        return IOSVoiceAudioMeter.normalizedLevel(
            decibels: recorder.averagePower(forChannel: 0)
        )
    }

    func stop() { recorder.stop() }
}

extension IOSVoiceRecorderAttemptToken:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    var description: String {
        "IOSVoiceRecorderAttemptToken(<redacted>)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSVoiceRecorderClient:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    var description: String { "IOSVoiceRecorderClient(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSVoiceRecorderCompletedCapture:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    nonisolated var description: String {
        "IOSVoiceRecorderCompletedCapture(<redacted>)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSVoiceRecorderCompletedCaptureHandoff:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    nonisolated var description: String {
        "IOSVoiceRecorderCompletedCaptureHandoff(<redacted>)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSVoiceRecorderStopResult:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    var description: String { "IOSVoiceRecorderStopResult(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSVoiceRecorderTerminalEvent:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    var description: String { "IOSVoiceRecorderTerminalEvent(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSVoiceRecorderTerminalWait:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    nonisolated var description: String {
        "IOSVoiceRecorderTerminalWait(<redacted>)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSVoiceRecorderAdapter:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    nonisolated var description: String {
        "IOSVoiceRecorderAdapter(<redacted>)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}
