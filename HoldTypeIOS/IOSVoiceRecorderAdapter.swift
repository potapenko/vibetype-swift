import AudioToolbox
import AVFAudio
import Foundation
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

nonisolated enum IOSVoiceRecorderDiagnostic: String, Equatable, Sendable {
    case recorderCreated = "voice recorder created"
    case checkpointValidated = "voice recorder checkpoint validated"
    case retainedCaptureBegan = "retained capture began"
    case recorderStopped = "voice recorder stopped"
    case sourcePreserved = "voice capture source preserved"
    case sourceDiscarded = "voice capture source discarded"
    case sourceCompleted = "voice capture source completed"
    case staleCallbackIgnored = "stale recorder callback ignored"
    case operationFailed = "voice recorder operation failed"
}

@MainActor
final class IOSVoiceRecorderCompletedCapture: @unchecked Sendable {
    let durationMilliseconds: Int64
    let byteCount: Int64

    private let releaseAction: @MainActor @Sendable () -> Void
    private var wasReleased = false

    init(
        durationMilliseconds: Int64,
        byteCount: Int64,
        release: @escaping @MainActor @Sendable () -> Void
    ) {
        self.durationMilliseconds = durationMilliseconds
        self.byteCount = byteCount
        releaseAction = release
    }

    func release() {
        guard !wasReleased else { return }
        wasReleased = true
        releaseAction()
    }
}

nonisolated enum IOSVoiceRecorderStopResult: Sendable {
    case completed(IOSVoiceRecorderCompletedCapture)
    case invalid(IOSForegroundVoiceCaptureInvalidReason)
    case discarded
    case preserved(IOSVoiceRecorderFailure)
    case stale
}

@MainActor
protocol IOSVoiceAudioRecorder: AnyObject {
    var currentTime: TimeInterval { get }
    var isRecording: Bool { get }

    func prepareToRecord() -> Bool
    func record(forDuration duration: TimeInterval) -> Bool
    func stop()
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

    let makeRecorder: MakeRecorder
    let sleep: Sleep

    init(
        makeRecorder: @escaping MakeRecorder,
        sleep: @escaping Sleep
    ) {
        self.makeRecorder = makeRecorder
        self.sleep = sleep
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
    func completeAfterRecorderClose() async throws
        -> IOSVoiceRecorderCaptureFinalization
    func beginDiscardingBeforeRecorderStop() async throws
    func finishDiscardAfterRecorderStop() async throws
    func release()
}

nonisolated enum IOSVoiceRecorderCaptureFinalization: Sendable {
    case completed(IOSVoiceRecorderCompletedCapture)
    case discarded(IOSForegroundVoiceCaptureInvalidReason)
}

/// Fail-closed candidate around AVAudioRecorder. It owns recorder lifetime but
/// never exposes or stores the capture source URL outside the lease callback.
@MainActor
final class IOSVoiceRecorderAdapter {
    typealias DiagnosticHandler = @MainActor @Sendable (
        IOSVoiceRecorderDiagnostic
    ) -> Void

    nonisolated static let maximumDuration: TimeInterval = 300
    nonisolated static let maximumDurationWatchdog: Duration = .seconds(300)
    nonisolated static let recorderSafetyDuration: TimeInterval = 301

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
        case discardFailure(IOSVoiceRecorderFailure)
    }

    private final class Attempt {
        let token: IOSVoiceRecorderAttemptToken
        let generation: UInt64
        var recorder: (any IOSVoiceAudioRecorder)?
        var deferredRecorderEvent: IOSVoiceRecorderEvent?
        var pendingStopReason: InternalStopReason?
        var stopTask: Task<IOSVoiceRecorderStopResult, Never>?
        var stopWaiters: [
            CheckedContinuation<IOSVoiceRecorderStopResult, Never>
        ] = []
        var maximumDurationTask: Task<Void, Never>?
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

    private let captureSource: any IOSVoiceRecorderCaptureSourceSystem
    private let client: IOSVoiceRecorderClient
    private let diagnose: DiagnosticHandler
    private var phase = Phase.idle
    private var activeAttempt: Attempt?
    private var nextGeneration: UInt64 = 0
    private var lastTerminal: (
        token: IOSVoiceRecorderAttemptToken,
        result: IOSVoiceRecorderStopResult
    )?

    convenience init(
        lease: IOSForegroundVoiceCaptureSourceLease,
        client: IOSVoiceRecorderClient = .live,
        diagnose: @escaping DiagnosticHandler = { _ in }
    ) {
        self.init(
            captureSource: IOSVoiceRecorderCaptureSourceLeaseSystem(
                lease: lease
            ),
            client: client,
            diagnose: diagnose
        )
    }

    init(
        captureSource: any IOSVoiceRecorderCaptureSourceSystem,
        client: IOSVoiceRecorderClient,
        diagnose: @escaping DiagnosticHandler = { _ in }
    ) {
        self.captureSource = captureSource
        self.client = client
        self.diagnose = diagnose
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
                failure: .recorderCreationFailed,
                preserveSource: true
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
                failure: .checkpointFailed,
                preserveSource: true
            )
        }
        markTaskCancellationIfNeeded(attempt)
        if let result = await finishPendingArmingStopIfNeeded(attempt) {
            return result
        }

        guard let recorder = attempt.recorder else {
            return await failStart(
                attempt,
                failure: .recorderCreationFailed,
                preserveSource: true
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
                failure: .checkpointFailed,
                preserveSource: true
            )
        }
        markTaskCancellationIfNeeded(attempt)
        if let result = await finishPendingArmingStopIfNeeded(attempt) {
            return result
        }
        guard prepared else {
            return await failStart(
                attempt,
                failure: .prepareFailed,
                preserveSource: false
            )
        }

        let didRecord = recorder.record(
            forDuration: Self.recorderSafetyDuration
        )
        markTaskCancellationIfNeeded(attempt)
        if let result = await finishPendingArmingStopIfNeeded(attempt) {
            return result
        }
        guard didRecord else {
            return await failStart(
                attempt,
                failure: .recordFailed,
                preserveSource: false
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
                return lastTerminal.result
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

    func presentationCurrentTime(
        for token: IOSVoiceRecorderAttemptToken
    ) -> TimeInterval? {
        guard phase == .recording,
              let attempt = activeAttempt,
              attempt.token == token,
              let recorder = attempt.recorder else {
            return nil
        }
        let value = recorder.currentTime
        guard value.isFinite, value >= 0 else { return nil }
        return min(value, Self.maximumDuration)
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

    private func failStart(
        _ attempt: Attempt,
        failure: IOSVoiceRecorderFailure,
        preserveSource: Bool
    ) async -> IOSVoiceRecorderStartResult {
        let reason: InternalStopReason = preserveSource
            ? .preserveFailure(failure)
            : .discardFailure(failure)
        let result = await beginStop(attempt, reason: reason)
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
        case let .preserveFailure(failure),
             let .discardFailure(failure):
            effectiveReason = reason
            startResult = .failed(failure)
        case .recorderEnded:
            effectiveReason = .recorderEnded
            startResult = .failed(.recorderEndedUnexpectedly)
        case .done, .cancelled, .interrupted, .maximumDuration:
            effectiveReason = .cancelled
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
        attempt.pendingStopReason = .cancelled
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
                attempt.pendingStopReason = .cancelled
            }
        case .recording:
            Task { @MainActor [weak self] in
                _ = await self?.beginStop(
                    attempt,
                    reason: .cancelled
                )
            }
        case .idle, .stopping:
            break
        }
    }

    private func beginStop(
        _ attempt: Attempt,
        reason: InternalStopReason
    ) async -> IOSVoiceRecorderStopResult {
        if let task = attempt.stopTask { return await task.value }
        guard activeAttempt === attempt else {
            return terminalResult(for: attempt.token)
        }

        phase = .stopping
        attempt.maximumDurationTask?.cancel()
        attempt.maximumDurationTask = nil
        let task = Task { @MainActor [self, attempt] in
            let result = await executeStop(attempt, reason: reason)
            finishAttempt(attempt, result: result)
            return result
        }
        attempt.stopTask = task
        return await task.value
    }

    private func executeStop(
        _ attempt: Attempt,
        reason: InternalStopReason
    ) async -> IOSVoiceRecorderStopResult {
        switch reason {
        case .done:
            return await finalizeCompletedAttempt(attempt)
        case .preserveFailure(let failure):
            stopRecorder(attempt)
            preserveSource(attempt)
            return .preserved(failure)
        case .recorderEnded:
            stopRecorder(attempt)
            preserveSource(attempt)
            return .preserved(.recorderEndedUnexpectedly)
        case .cancelled, .interrupted, .maximumDuration,
             .discardFailure:
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
                .completeAfterRecorderClose()
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
             .preserveFailure, .discardFailure:
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
        activeAttempt = nil
        phase = .idle
        lastTerminal = (attempt.token, result)
        let waiters = attempt.stopWaiters
        attempt.stopWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: result) }
    }

    private func terminalResult(
        for token: IOSVoiceRecorderAttemptToken
    ) -> IOSVoiceRecorderStopResult {
        guard let lastTerminal, lastTerminal.token == token else {
            return .stale
        }
        return lastTerminal.result
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
            Task { @MainActor [weak self] in
                _ = await self?.beginStop(
                    attempt,
                    reason: .recorderEnded
                )
            }
        case .stopping:
            break
        case .idle:
            diagnose(.staleCallbackIgnored)
        }
    }

    private func scheduleMaximumDuration(for attempt: Attempt) {
        let sleep = client.sleep
        attempt.maximumDurationTask = Task { @MainActor [weak self] in
            do {
                try await sleep(Self.maximumDurationWatchdog)
            } catch {
                return
            }
            guard let self,
                  self.activeAttempt === attempt,
                  self.phase == .recording else {
                return
            }
            _ = await self.beginStop(
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
}

@MainActor
private final class IOSVoiceRecorderCaptureSourceLeaseSystem:
    IOSVoiceRecorderCaptureSourceSystem
{
    private let lease: IOSForegroundVoiceCaptureSourceLease

    init(lease: IOSForegroundVoiceCaptureSourceLease) {
        self.lease = lease
    }

    func withTransientRecordingURL(
        _ body: (URL) throws -> Void
    ) throws {
        try lease.withTransientRecordingURL(body)
    }

    func revalidateRecorderCheckpoint() async throws {
        try await lease.revalidateRecorderCheckpoint()
    }

    func beginFinalizing() async throws {
        try await lease.beginFinalizing()
    }

    func completeAfterRecorderClose() async throws
        -> IOSVoiceRecorderCaptureFinalization {
        switch try await lease.completeAfterRecorderClose() {
        case let .completed(capture):
            return .completed(
                IOSVoiceRecorderCompletedCapture(
                    durationMilliseconds: capture.durationMilliseconds,
                    byteCount: capture.byteCount,
                    release: capture.release
                )
            )
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
private final class IOSVoiceAVAudioRecorder:
    NSObject,
    @preconcurrency AVAudioRecorderDelegate,
    IOSVoiceAudioRecorder
{
    private let recorder: AVAudioRecorder
    private let receive: IOSVoiceRecorderClient.EventHandler

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
        self.receive = receive
        super.init()
        recorder.delegate = self
    }

    var currentTime: TimeInterval { recorder.currentTime }
    var isRecording: Bool { recorder.isRecording }

    func prepareToRecord() -> Bool { recorder.prepareToRecord() }

    func record(forDuration duration: TimeInterval) -> Bool {
        recorder.record(forDuration: duration)
    }

    func stop() { recorder.stop() }

    func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        receive(.finished(successfully: flag))
    }

    func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: Error?
    ) {
        receive(.encodeError)
    }
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

extension IOSVoiceRecorderStopResult:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    var description: String { "IOSVoiceRecorderStopResult(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
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
