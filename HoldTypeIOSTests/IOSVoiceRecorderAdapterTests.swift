import AudioToolbox
import AVFAudio
import Foundation
import Testing
@_spi(HoldTypeIOSCore) import HoldTypePersistence
@testable import HoldTypeIOS

@MainActor
struct IOSVoiceRecorderAdapterTests {
    @Test func startUsesScopedURLExactSettingsTwoCheckpointsAndBoundedRecord()
        async throws {
        let fixture = VoiceRecorderFixture()
        fixture.recorder.currentTimeValue = 12.5
        let adapter = fixture.makeAdapter()
        let token = IOSVoiceRecorderAttemptToken()

        #expect(await adapter.start(for: token) == .recording)
        try await recorderEventually {
            fixture.sleep.waiterCount == 1
        }

        #expect(
            fixture.recordingSettings == .foregroundAAC
        )
        #expect(
            fixture.recordingSettings == IOSVoiceRecorderEncodingSettings(
                formatID: kAudioFormatMPEG4AAC,
                sampleRate: 44_100,
                channelCount: 1,
                encoderAudioQuality: AVAudioQuality.high.rawValue
            )
        )
        #expect(fixture.factoryObservedBorrowedURL)
        #expect(!fixture.source.isBorrowingURL)
        #expect(
            Array(fixture.log.calls.prefix(8)) == [
                .withURLBegin,
                .makeRecorder,
                .withURLEnd,
                .checkpoint(1),
                .prepare,
                .checkpoint(2),
                .record(301),
                .sleep(.seconds(300)),
            ]
        )
        #expect(
            fixture.sleep.requestedDurations
                == [IOSVoiceRecorderAdapter.maximumDurationWatchdog]
        )
        #expect(IOSVoiceRecorderAdapter.maximumDuration == 300)
        #expect(IOSVoiceRecorderAdapter.recorderSafetyDuration == 301)
        #expect(adapter.presentationCurrentTime(for: token) == 12.5)
        #expect(adapter.isActivelyRecording(for: token))

        _ = await adapter.stop(for: token, reason: .cancelled)
    }

    @Test func replacementAtEitherRecorderCheckpointStopsAndPreservesSource()
        async {
        for failingCheckpoint in [1, 2] {
            let fixture = VoiceRecorderFixture()
            fixture.source.checkpointFailureAt = failingCheckpoint
            let adapter = fixture.makeAdapter()

            #expect(
                await adapter.start(
                    for: IOSVoiceRecorderAttemptToken()
                ) == .failed(.checkpointFailed)
            )
            #expect(fixture.recorder.stopCount == 1)
            #expect(fixture.source.releaseCount == 1)
            #expect(!fixture.log.calls.contains(.record(301)))
            if failingCheckpoint == 1 {
                #expect(!fixture.log.calls.contains(.prepare))
            } else {
                #expect(fixture.log.calls.contains(.prepare))
            }
        }
    }

    @Test func taskCancellationDuringEitherCheckpointCannotBeginRecording()
        async throws {
        for checkpoint in [1, 2] {
            let fixture = VoiceRecorderFixture()
            fixture.source.suspendedCheckpoint = checkpoint
            let adapter = fixture.makeAdapter()
            let token = IOSVoiceRecorderAttemptToken()
            let startTask = Task {
                await adapter.start(for: token)
            }
            try await recorderEventually {
                fixture.source.suspendedCheckpointCount == checkpoint
            }

            startTask.cancel()
            fixture.source.resumeCheckpoint()
            #expect(await startTask.value == .cancelled)
            #expect(!fixture.log.calls.contains(.record(301)))
            assertOrdered(
                [.beginDiscarding, .stop, .finishDiscard],
                in: fixture.log.calls
            )
            #expect(fixture.recorder.stopCount == 1)
        }
    }

    @Test func armingCancelSurfacesDiscardTransitionAndCompletionFailures()
        async throws {
        let cases: [(
            VoiceRecorderCaptureSourceFixture.FailurePoint,
            IOSVoiceRecorderFailure
        )] = [
            (.beginDiscarding, .captureTransitionFailed),
            (.finishDiscard, .captureCompletionFailed),
        ]

        for (failurePoint, expectedFailure) in cases {
            let fixture = VoiceRecorderFixture()
            fixture.source.suspendedCheckpoint = 1
            fixture.source.failurePoint = failurePoint
            let adapter = fixture.makeAdapter()
            let token = IOSVoiceRecorderAttemptToken()
            let startTask = Task { await adapter.start(for: token) }
            try await recorderEventually {
                fixture.source.suspendedCheckpointCount == 1
            }
            let stopTask = Task {
                await adapter.stop(for: token, reason: .cancelled)
            }
            try await Task.sleep(for: .milliseconds(10))
            fixture.source.resumeCheckpoint()

            #expect(await startTask.value == .failed(expectedFailure))
            #expect(
                (await stopTask.value).preservedFailure == expectedFailure
            )
            #expect(fixture.recorder.stopCount == 1)
            #expect(fixture.source.releaseCount == 1)
        }
    }

    @Test func synchronousDelegateCallbacksDuringArmingFailAndPreserve()
        async {
        enum CallbackPoint {
            case factory
            case prepare
            case record
        }

        for point in [CallbackPoint.factory, .prepare, .record] {
            let fixture = VoiceRecorderFixture()
            switch point {
            case .factory:
                fixture.factoryEvent = .finished(successfully: true)
            case .prepare:
                fixture.recorder.prepareEvent = .finished(
                    successfully: true
                )
            case .record:
                fixture.recorder.recordEvent = .finished(
                    successfully: true
                )
            }
            let adapter = fixture.makeAdapter()

            #expect(
                await adapter.start(
                    for: IOSVoiceRecorderAttemptToken()
                ) == .failed(.recorderEndedUnexpectedly)
            )
            #expect(fixture.recorder.stopCount == 1)
            #expect(fixture.source.releaseCount == 1)
            #expect(!fixture.log.calls.contains(.beginDiscarding))
        }
    }

    @Test func prepareFalseRevalidatesThenDiscardsBeforeStopping() async {
        let fixture = VoiceRecorderFixture()
        fixture.recorder.prepareResult = false
        let adapter = fixture.makeAdapter()

        #expect(
            await adapter.start(
                for: IOSVoiceRecorderAttemptToken()
            ) == .failed(.prepareFailed)
        )
        #expect(fixture.source.checkpointCount == 2)
        assertOrdered(
            [.beginDiscarding, .stop, .finishDiscard],
            in: fixture.log.calls
        )
        #expect(fixture.recorder.stopCount == 1)
        #expect(fixture.source.releaseCount == 0)
    }

    @Test func recordFalseDiscardsBeforeStoppingAndNeverStartsWatchdog()
        async {
        let fixture = VoiceRecorderFixture()
        fixture.recorder.recordResult = false
        let adapter = fixture.makeAdapter()

        #expect(
            await adapter.start(
                for: IOSVoiceRecorderAttemptToken()
            ) == .failed(.recordFailed)
        )
        assertOrdered(
            [.record(301), .beginDiscarding, .stop, .finishDiscard],
            in: fixture.log.calls
        )
        #expect(fixture.sleep.requestedDurations.isEmpty)
        #expect(fixture.recorder.stopCount == 1)
    }

    @Test func doneMarksFinalizingBeforeStopAndUsesCanonicalCaptureFacts()
        async throws {
        let fixture = VoiceRecorderFixture()
        fixture.recorder.currentTimeValue = 99
        fixture.source.completedDurationMilliseconds = 1_234
        fixture.source.completedByteCount = 5_678
        let adapter = fixture.makeAdapter()
        let token = IOSVoiceRecorderAttemptToken()
        #expect(await adapter.start(for: token) == .recording)
        #expect(adapter.presentationCurrentTime(for: token) == 99)

        let result = await adapter.stop(for: token, reason: .done)
        let completed: IOSVoiceRecorderCompletedCapture
        switch result {
        case let .completed(value):
            completed = value
        default:
            Issue.record("Expected a completed capture.")
            return
        }

        #expect(completed.durationMilliseconds == 1_234)
        #expect(completed.byteCount == 5_678)
        assertOrdered(
            [.beginFinalizing, .stop, .complete],
            in: fixture.log.calls
        )
        #expect(fixture.recorder.stopCount == 1)

        let repeated = await adapter.stop(for: token, reason: .cancelled)
        if case let .completed(value) = repeated {
            #expect(value === completed)
        } else {
            Issue.record("Idempotent stop changed its terminal result.")
        }
        #expect(fixture.recorder.stopCount == 1)

        completed.release()
        completed.release()
        #expect(fixture.source.completedReleaseCount == 1)
    }

    @Test func cancelDiscardsBeforeStopAndRepeatedStopIsIdempotent() async {
        let fixture = VoiceRecorderFixture()
        let adapter = fixture.makeAdapter()
        let token = IOSVoiceRecorderAttemptToken()
        #expect(await adapter.start(for: token) == .recording)

        let first = await adapter.stop(for: token, reason: .cancelled)
        let second = await adapter.stop(for: token, reason: .interrupted)
        #expect(first.isDiscarded)
        #expect(second.isDiscarded)
        assertOrdered(
            [.beginDiscarding, .stop, .finishDiscard],
            in: fixture.log.calls
        )
        #expect(
            fixture.log.calls.filter { $0 == .beginDiscarding }.count == 1
        )
        #expect(fixture.recorder.stopCount == 1)
    }

    @Test func invalidFinalizationAndMaximumDurationStayExplicit()
        async throws {
        let invalidFixture = VoiceRecorderFixture()
        invalidFixture.source.finalizationInvalidReason = .tooShort
        let invalidAdapter = invalidFixture.makeAdapter()
        let invalidToken = IOSVoiceRecorderAttemptToken()
        #expect(await invalidAdapter.start(for: invalidToken) == .recording)
        let invalidResult = await invalidAdapter.stop(
            for: invalidToken,
            reason: .done
        )
        #expect(invalidResult.invalidReason == .tooShort)

        let maximumFixture = VoiceRecorderFixture()
        let maximumDiagnostics = VoiceRecorderDiagnosticCapture()
        let maximumAdapter = maximumFixture.makeAdapter(
            diagnose: maximumDiagnostics.record
        )
        let maximumToken = IOSVoiceRecorderAttemptToken()
        #expect(await maximumAdapter.start(for: maximumToken) == .recording)
        try await recorderEventually {
            maximumFixture.sleep.waiterCount == 1
        }
        maximumFixture.sleep.fire()
        try await recorderEventually {
            !maximumAdapter.isActivelyRecording(for: maximumToken)
        }
        let maximumResult = await maximumAdapter.stop(
            for: maximumToken,
            reason: .cancelled
        )
        #expect(maximumResult.invalidReason == .maximumDurationReached)
        assertOrdered(
            [.beginDiscarding, .stop, .finishDiscard],
            in: maximumFixture.log.calls
        )
        maximumFixture.recorder.emit(.finished(successfully: true))
        await Task.yield()
        #expect(maximumFixture.recorder.stopCount == 1)
        #expect(maximumDiagnostics.values.contains(.staleCallbackIgnored))
    }

    @Test func delegateIsAnIndependentAuthorityButLateCallbacksAreStale()
        async throws {
        let fixture = VoiceRecorderFixture()
        let diagnostics = VoiceRecorderDiagnosticCapture()
        let adapter = fixture.makeAdapter(diagnose: diagnostics.record)
        let token = IOSVoiceRecorderAttemptToken()
        #expect(await adapter.start(for: token) == .recording)

        fixture.recorder.emit(.finished(successfully: false))
        try await recorderEventually {
            fixture.source.releaseCount == 1
        }
        let terminal = await adapter.stop(for: token, reason: .cancelled)
        #expect(
            terminal.preservedFailure == .recorderEndedUnexpectedly
        )
        #expect(fixture.recorder.stopCount == 1)
        #expect(!fixture.log.calls.contains(.beginDiscarding))
        fixture.sleep.fire()
        await Task.yield()
        #expect(fixture.source.releaseCount == 1)
        #expect(fixture.recorder.stopCount == 1)

        fixture.recorder.emit(.encodeError)
        await Task.yield()
        #expect(diagnostics.values.contains(.staleCallbackIgnored))
        #expect(
            (await adapter.stop(
                    for: IOSVoiceRecorderAttemptToken(),
                    reason: .cancelled
                )).isStale
        )
    }

    @Test func transitionAndCompletionFailuresStopAndPreserveExactSource()
        async {
        let finalizingFixture = VoiceRecorderFixture()
        finalizingFixture.source.failurePoint = .beginFinalizing
        let finalizingAdapter = finalizingFixture.makeAdapter()
        let finalizingToken = IOSVoiceRecorderAttemptToken()
        #expect(await finalizingAdapter.start(for: finalizingToken) == .recording)
        let finalizingResult = await finalizingAdapter.stop(
            for: finalizingToken,
            reason: .done
        )
        #expect(
            finalizingResult.preservedFailure == .captureTransitionFailed
        )
        assertOrdered(
            [.beginFinalizing, .stop, .release],
            in: finalizingFixture.log.calls
        )

        let completionFixture = VoiceRecorderFixture()
        completionFixture.source.failurePoint = .complete
        let completionAdapter = completionFixture.makeAdapter()
        let completionToken = IOSVoiceRecorderAttemptToken()
        #expect(await completionAdapter.start(for: completionToken) == .recording)
        let completionResult = await completionAdapter.stop(
            for: completionToken,
            reason: .done
        )
        #expect(
            completionResult.preservedFailure == .captureCompletionFailed
        )
        assertOrdered(
            [.beginFinalizing, .stop, .complete, .release],
            in: completionFixture.log.calls
        )

        let discardFixture = VoiceRecorderFixture()
        discardFixture.source.failurePoint = .beginDiscarding
        let discardAdapter = discardFixture.makeAdapter()
        let discardToken = IOSVoiceRecorderAttemptToken()
        #expect(await discardAdapter.start(for: discardToken) == .recording)
        let discardResult = await discardAdapter.stop(
            for: discardToken,
            reason: .cancelled
        )
        #expect(discardResult.preservedFailure == .captureTransitionFailed)
        assertOrdered(
            [.beginDiscarding, .stop, .release],
            in: discardFixture.log.calls
        )
    }

    @Test func publicDescriptionsAndMirrorsStayPayloadFree() async {
        let fixture = VoiceRecorderFixture()
        let adapter = fixture.makeAdapter()
        let token = IOSVoiceRecorderAttemptToken(
            rawValue: UUID(
                uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
            )!
        )
        let result = IOSVoiceRecorderStopResult.preserved(
            .checkpointFailed
        )
        let canary = token.rawValue.uuidString.lowercased()

        for value in [
            String(describing: token),
            String(reflecting: token),
            String(describing: fixture.client),
            String(reflecting: fixture.client),
            String(describing: adapter),
            String(reflecting: adapter),
            String(describing: result),
            String(reflecting: result),
        ] {
            #expect(value.contains("<redacted>"))
            #expect(!value.lowercased().contains(canary))
            #expect(!value.contains("private-recorder-url"))
        }
        #expect(Mirror(reflecting: token).children.isEmpty)
        #expect(Mirror(reflecting: fixture.client).children.isEmpty)
        #expect(Mirror(reflecting: adapter).children.isEmpty)
        #expect(Mirror(reflecting: result).children.isEmpty)
    }
}

@MainActor
private final class VoiceRecorderFixture {
    let log = VoiceRecorderCallLog()
    let sleep = VoiceRecorderSleepFixture()
    lazy var source = VoiceRecorderCaptureSourceFixture(log: log)
    lazy var recorder = VoiceAudioRecorderFixture(log: log)
    var factoryEvent: IOSVoiceRecorderEvent?
    private(set) var recordingSettings: IOSVoiceRecorderEncodingSettings?
    private(set) var factoryObservedBorrowedURL = false

    lazy var client = IOSVoiceRecorderClient(
        makeRecorder: { [weak self] _, settings, receive in
            guard let self else { throw VoiceRecorderFixtureError() }
            recordingSettings = settings
            factoryObservedBorrowedURL = source.isBorrowingURL
            log.calls.append(.makeRecorder)
            recorder.receive = receive
            if let factoryEvent { receive(factoryEvent) }
            return recorder
        },
        sleep: { [sleep, log] duration in
            log.calls.append(.sleep(duration))
            try await sleep.wait(for: duration)
        }
    )

    func makeAdapter(
        diagnose: @escaping IOSVoiceRecorderAdapter.DiagnosticHandler = { _ in }
    ) -> IOSVoiceRecorderAdapter {
        IOSVoiceRecorderAdapter(
            captureSource: source,
            client: client,
            diagnose: diagnose
        )
    }
}

private struct VoiceRecorderFixtureError: Error {}

@MainActor
private final class VoiceRecorderCallLog {
    enum Call: Equatable {
        case withURLBegin
        case makeRecorder
        case withURLEnd
        case checkpoint(Int)
        case prepare
        case record(TimeInterval)
        case sleep(Duration)
        case recordingStateRead
        case beginFinalizing
        case complete
        case beginDiscarding
        case stop
        case finishDiscard
        case release
    }

    var calls: [Call] = []
}

@MainActor
private final class VoiceRecorderCaptureSourceFixture:
    IOSVoiceRecorderCaptureSourceSystem
{
    enum FailurePoint: Equatable {
        case beginFinalizing
        case complete
        case beginDiscarding
        case finishDiscard
    }

    private let log: VoiceRecorderCallLog
    private(set) var isBorrowingURL = false
    private(set) var checkpointCount = 0
    private(set) var suspendedCheckpointCount: Int?
    private(set) var releaseCount = 0
    private(set) var completedReleaseCount = 0
    var checkpointFailureAt: Int?
    var suspendedCheckpoint: Int?
    var failurePoint: FailurePoint?
    var finalizationInvalidReason: IOSForegroundVoiceCaptureInvalidReason?
    var completedDurationMilliseconds: Int64 = 1_000
    var completedByteCount: Int64 = 2_000
    private var checkpointContinuation: CheckedContinuation<Void, Never>?

    init(log: VoiceRecorderCallLog) {
        self.log = log
    }

    func withTransientRecordingURL(
        _ body: (URL) throws -> Void
    ) throws {
        log.calls.append(.withURLBegin)
        isBorrowingURL = true
        defer {
            isBorrowingURL = false
            log.calls.append(.withURLEnd)
        }
        try body(
            URL(fileURLWithPath: "/private/private-recorder-url.m4a")
        )
    }

    func revalidateRecorderCheckpoint() async throws {
        checkpointCount += 1
        log.calls.append(.checkpoint(checkpointCount))
        if suspendedCheckpoint == checkpointCount {
            suspendedCheckpointCount = checkpointCount
            await withCheckedContinuation { continuation in
                checkpointContinuation = continuation
            }
        }
        if checkpointFailureAt == checkpointCount {
            throw VoiceRecorderFixtureError()
        }
    }

    func resumeCheckpoint() {
        let continuation = checkpointContinuation
        checkpointContinuation = nil
        continuation?.resume()
    }

    func beginFinalizing() async throws {
        log.calls.append(.beginFinalizing)
        if failurePoint == .beginFinalizing {
            throw VoiceRecorderFixtureError()
        }
    }

    func completeAfterRecorderClose() async throws
        -> IOSVoiceRecorderCaptureFinalization {
        log.calls.append(.complete)
        if failurePoint == .complete { throw VoiceRecorderFixtureError() }
        if let finalizationInvalidReason {
            return .discarded(finalizationInvalidReason)
        }
        return .completed(
            IOSVoiceRecorderCompletedCapture(
                durationMilliseconds: completedDurationMilliseconds,
                byteCount: completedByteCount,
                release: { [weak self] in
                    self?.completedReleaseCount += 1
                }
            )
        )
    }

    func beginDiscardingBeforeRecorderStop() async throws {
        log.calls.append(.beginDiscarding)
        if failurePoint == .beginDiscarding {
            throw VoiceRecorderFixtureError()
        }
    }

    func finishDiscardAfterRecorderStop() async throws {
        log.calls.append(.finishDiscard)
        if failurePoint == .finishDiscard {
            throw VoiceRecorderFixtureError()
        }
    }

    func release() {
        releaseCount += 1
        log.calls.append(.release)
    }
}

@MainActor
private final class VoiceAudioRecorderFixture: IOSVoiceAudioRecorder {
    private let log: VoiceRecorderCallLog
    var receive: IOSVoiceRecorderClient.EventHandler?
    var prepareResult = true
    var recordResult = true
    var prepareEvent: IOSVoiceRecorderEvent?
    var recordEvent: IOSVoiceRecorderEvent?
    var currentTimeValue: TimeInterval = 0
    private(set) var stopCount = 0
    private var recording = false

    init(log: VoiceRecorderCallLog) {
        self.log = log
    }

    var currentTime: TimeInterval { currentTimeValue }

    var isRecording: Bool {
        log.calls.append(.recordingStateRead)
        return recording
    }

    func prepareToRecord() -> Bool {
        log.calls.append(.prepare)
        if let prepareEvent { receive?(prepareEvent) }
        return prepareResult
    }

    func record(forDuration duration: TimeInterval) -> Bool {
        log.calls.append(.record(duration))
        recording = recordResult
        if let recordEvent { receive?(recordEvent) }
        return recordResult
    }

    func stop() {
        stopCount += 1
        recording = false
        log.calls.append(.stop)
    }

    func emit(_ event: IOSVoiceRecorderEvent) {
        receive?(event)
    }
}

@MainActor
private final class VoiceRecorderSleepFixture {
    private struct Waiter {
        let continuation: CheckedContinuation<Void, Error>
    }

    private var waiters: [UUID: Waiter] = [:]
    private(set) var requestedDurations: [Duration] = []

    var waiterCount: Int { waiters.count }

    func wait(for duration: Duration) async throws {
        requestedDurations.append(duration)
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[id] = Waiter(continuation: continuation)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel(id)
            }
        }
    }

    func fire() {
        let waiters = waiters.values
        self.waiters.removeAll()
        for waiter in waiters { waiter.continuation.resume() }
    }

    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.continuation.resume(
            throwing: CancellationError()
        )
    }
}

@MainActor
private final class VoiceRecorderDiagnosticCapture {
    private(set) var values: [IOSVoiceRecorderDiagnostic] = []

    func record(_ value: IOSVoiceRecorderDiagnostic) {
        values.append(value)
    }
}

private extension IOSVoiceRecorderStopResult {
    var isDiscarded: Bool {
        if case .discarded = self { return true }
        return false
    }

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }

    var invalidReason: IOSForegroundVoiceCaptureInvalidReason? {
        if case let .invalid(reason) = self { return reason }
        return nil
    }

    var preservedFailure: IOSVoiceRecorderFailure? {
        if case let .preserved(failure) = self { return failure }
        return nil
    }
}

@MainActor
private func assertOrdered(
    _ expected: [VoiceRecorderCallLog.Call],
    in calls: [VoiceRecorderCallLog.Call]
) {
    var lowerBound = calls.startIndex
    for value in expected {
        guard let index = calls[lowerBound...].firstIndex(of: value) else {
            Issue.record("Missing expected recorder call: \(value)")
            return
        }
        lowerBound = calls.index(after: index)
    }
}

@MainActor
private func recorderEventually(
    _ predicate: @escaping @MainActor @Sendable () -> Bool
) async throws {
    for _ in 0..<100 {
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for recorder state.")
}
