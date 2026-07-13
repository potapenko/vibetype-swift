import Foundation
import HoldTypeDomain
import Testing
@_spi(HoldTypeIOSCore) @testable import HoldTypePersistence
@testable import HoldTypeIOS

@MainActor
struct IOSForegroundVoiceRecorderBridgeTests {
    @Test
    func factoryStartsExactAttemptAndMapsExplicitStop() async throws {
        let fixture = RecorderBridgeFixture()
        fixture.stopResult = .discarded
        let attemptID = UUID()
        let bridge = fixture.makeBridge()
        let recording = try await bridge.makeRecording(
            attemptID: attemptID,
            outputIntent: .translate
        )
        let observation = recording.observeTerminal { _ in }

        #expect(await recording.start() == .started)
        #expect(recording.isActive)
        #expect(isDiscarded(await recording.stop(.cancelled)))
        #expect(fixture.createdAttemptID == attemptID)
        #expect(fixture.createdOutputIntent == .translate)
        #expect(fixture.stopReasons == [.cancelled])

        observation.cancel()
    }

    @Test
    func immediateTerminalIsBufferedBeforeStartReturnsAndConsumedOnce()
        async throws {
        let fixture = RecorderBridgeFixture()
        fixture.terminalEvent = IOSVoiceRecorderTerminalEvent(
            cause: .maximumDuration,
            result: .invalid(.maximumDurationReached)
        )
        let recording = try await fixture.makeRecording()
        var reasons: [IOSForegroundVoiceWorkflowCaptureStopReason] = []
        let observation = recording.observeTerminal { reasons.append($0) }

        #expect(await recording.start() == .started)
        try await recorderBridgeEventually { !reasons.isEmpty }
        #expect(reasons == [.maximumDuration])
        #expect(
            isInvalid(
                await recording.stop(.maximumDuration),
                reason: .maximumDurationReached
            )
        )
        #expect(fixture.stopReasons.isEmpty)

        observation.cancel()
    }

    @Test
    func completedCaptureTransfersPendingExactlyOnce() async throws {
        let fixture = RecorderBridgeFixture()
        let pending = try makeRecorderBridgePending()
        var prepareCount = 0
        var releaseCount = 0
        fixture.stopResult = .completed(
            IOSVoiceRecorderCompletedCapture(
                durationMilliseconds: 1_000,
                byteCount: 2_000,
                preparePending: { _, _ in
                    prepareCount += 1
                    return pending
                },
                release: { releaseCount += 1 }
            )
        )
        let recording = try await fixture.makeRecording()
        let observation = recording.observeTerminal { _ in }
        #expect(await recording.start() == .started)

        let result = await recording.stop(.done)
        guard case .completed(let handoff) = result else {
            Issue.record("Expected completed workflow handoff")
            return
        }
        let prepared = try await handoff.preparePending(
            transcriptionConfiguration: TranscriptionConfiguration()
        )
        #expect(prepared == pending)
        await #expect(throws: Error.self) {
            try await handoff.preparePending(
                transcriptionConfiguration: TranscriptionConfiguration()
            )
        }
        handoff.release()
        #expect(prepareCount == 1)
        #expect(releaseCount == 1)

        observation.cancel()
    }

    @Test
    func terminalResumeBeforeStopReturnCannotConsumeCompletedHandoff()
        async throws {
        let terminalGate = RecorderBridgeGate()
        let observerGate = RecorderBridgeGate()
        var releaseCount = 0
        let capture = IOSVoiceRecorderCompletedCapture(
            durationMilliseconds: 1_000,
            byteCount: 2_000,
            release: { releaseCount += 1 }
        )
        let event = IOSVoiceRecorderTerminalEvent(
            cause: .done,
            result: .completed(capture)
        )
        let driver = IOSForegroundVoiceRecorderBridgeDriver(
            start: { _ in .recording },
            stop: { _, _ in
                terminalGate.open()
                await observerGate.wait()
                return .completed(capture)
            },
            waitForTerminal: { _ in
                IOSVoiceRecorderTerminalWait(
                    wait: {
                        await terminalGate.wait()
                        return event
                    }
                )
            },
            isActivelyRecording: { _ in true }
        )
        let bridge = IOSForegroundVoiceRecorderBridge(
            makeDriver: { _, _ in driver },
            preparePending: { handoff, configuration in
                try await handoff.preparePending(
                    using: IOSV1ForegroundVoicePersistenceOwner(
                        applicationSupportDirectoryURL: URL(
                            fileURLWithPath: "/tmp/holdtype-recorder-bridge",
                            isDirectory: true
                        )
                    ),
                    transcriptionConfiguration: configuration
                )
            }
        )
        let recording = try await bridge.makeRecording(
            attemptID: UUID(),
            outputIntent: .standard
        )
        let observation = recording.observeTerminal { _ in
            observerGate.open()
        }
        #expect(await recording.start() == .started)

        guard case .completed(let handoff) = await recording.stop(.done) else {
            Issue.record("Expected completed workflow handoff")
            return
        }
        handoff.release()
        #expect(releaseCount == 1)

        observation.cancel()
    }

    @Test
    func failedPendingPreparationReleasesCompletedSourceExactlyOnce()
        async throws {
        let fixture = RecorderBridgeFixture()
        var releaseCount = 0
        fixture.stopResult = .completed(
            IOSVoiceRecorderCompletedCapture(
                durationMilliseconds: 1_000,
                byteCount: 2_000,
                preparePending: { _, _ in throw RecorderBridgeError.failed },
                release: { releaseCount += 1 }
            )
        )
        let recording = try await fixture.makeRecording()
        let observation = recording.observeTerminal { _ in }
        #expect(await recording.start() == .started)
        guard case .completed(let handoff) = await recording.stop(.done) else {
            Issue.record("Expected completed workflow handoff")
            return
        }

        await #expect(throws: RecorderBridgeError.failed) {
            try await handoff.preparePending(
                transcriptionConfiguration: TranscriptionConfiguration()
            )
        }
        handoff.release()
        handoff.release()
        #expect(releaseCount == 1)

        observation.cancel()
    }

    @Test
    func ordinaryDiscardAndInvalidArtifactRemainDistinct() async throws {
        let discardedFixture = RecorderBridgeFixture()
        discardedFixture.stopResult = .discarded
        let discarded = try await discardedFixture.makeRecording()
        let discardedObservation = discarded.observeTerminal { _ in }
        #expect(await discarded.start() == .started)
        #expect(isDiscarded(await discarded.stop(.cancelled)))
        discardedObservation.cancel()

        let invalidFixture = RecorderBridgeFixture()
        invalidFixture.stopResult = .invalid(.tooShort)
        let invalid = try await invalidFixture.makeRecording()
        let invalidObservation = invalid.observeTerminal { _ in }
        #expect(await invalid.start() == .started)
        #expect(
            isInvalid(await invalid.stop(.done), reason: .tooShort)
        )
        invalidObservation.cancel()
    }

    @Test
    func recorderLifecycleForwardsRetainedBeginAndClosedCancelToFeedback()
        async throws {
        var retainedBeginCount = 0
        var closeDispositions:
            [IOSVoiceBoundaryRecorderCloseDisposition] = []
        let feedback = IOSForegroundVoiceFeedbackBridge(
            driver: IOSForegroundVoiceFeedbackBridgeDriver(
                prepareStartBoundary: { _, _ in .completed },
                cancelStart: { _, _ in },
                retainedCaptureDidBegin: { _ in
                    retainedBeginCount += 1
                    return true
                },
                abandonReadyBoundary: { _ in true },
                recorderDidClose: { _, disposition, _ in
                    closeDispositions.append(disposition)
                    return .feedbackSkipped
                },
                cancelSuccessFeedback: { _ in }
            )
        )
        #expect(await feedback.playStartBoundary(audioCuesEnabled: false))
        let fixture = RecorderBridgeFixture()
        fixture.stopResult = .discarded
        let recording = try await fixture.makeBridge(feedback: feedback)
            .makeRecording(
                attemptID: UUID(),
                outputIntent: .standard
            )
        let observation = recording.observeTerminal { _ in }

        #expect(await recording.start() == .started)
        #expect(retainedBeginCount == 1)
        #expect(isDiscarded(await recording.stop(.cancelled)))
        #expect(closeDispositions == [.cancelled])
        #expect(!feedback.hasActiveAttempt)

        observation.cancel()
    }

    @Test
    func authoritativeInterruptedTerminalOverridesRequestedDoneFeedback()
        async throws {
        var closeDispositions:
            [IOSVoiceBoundaryRecorderCloseDisposition] = []
        let feedback = IOSForegroundVoiceFeedbackBridge(
            driver: IOSForegroundVoiceFeedbackBridgeDriver(
                prepareStartBoundary: { _, _ in .completed },
                cancelStart: { _, _ in },
                retainedCaptureDidBegin: { _ in true },
                abandonReadyBoundary: { _ in true },
                recorderDidClose: { _, disposition, _ in
                    closeDispositions.append(disposition)
                    return .feedbackSkipped
                },
                cancelSuccessFeedback: { _ in }
            )
        )
        #expect(await feedback.playStartBoundary(audioCuesEnabled: true))
        let terminalGate = RecorderBridgeGate()
        let stopReturnedGate = RecorderBridgeGate()
        let terminalResult = IOSVoiceRecorderStopResult.preserved(
            .recorderEndedUnexpectedly
        )
        let driver = IOSForegroundVoiceRecorderBridgeDriver(
            start: { _ in .recording },
            stop: { _, _ in
                stopReturnedGate.open()
                return terminalResult
            },
            waitForTerminal: { _ in
                IOSVoiceRecorderTerminalWait(
                    wait: {
                        await terminalGate.wait()
                        return IOSVoiceRecorderTerminalEvent(
                            cause: .interrupted,
                            result: terminalResult
                        )
                    }
                )
            },
            isActivelyRecording: { _ in true }
        )
        let bridge = IOSForegroundVoiceRecorderBridge(
            makeDriver: { _, _ in driver },
            preparePending: { _, _ in throw RecorderBridgeError.failed },
            feedback: feedback
        )
        let recording = try await bridge.makeRecording(
            attemptID: UUID(),
            outputIntent: .standard
        )
        let observation = recording.observeTerminal { _ in }
        #expect(await recording.start() == .started)

        let stopTask = Task { await recording.stop(.done) }
        await stopReturnedGate.wait()
        terminalGate.open()
        #expect(isPreserved(await stopTask.value))
        await feedback.playStopBoundary(audioCuesEnabled: true)
        #expect(closeDispositions == [.interrupted])
        #expect(!feedback.hasActiveAttempt)

        observation.cancel()
    }

    @Test
    func adapterStartCancellationAndFailureMapWithoutStartingCapture()
        async throws {
        let cases: [(
            IOSVoiceRecorderStartResult,
            IOSForegroundVoiceWorkflowRecordingStartResult
        )] = [
            (.cancelled, .cancelled),
            (.busy, .failed),
            (.failed(.prepareFailed), .failed),
        ]
        for (adapterResult, expected) in cases {
            let fixture = RecorderBridgeFixture()
            fixture.startResult = adapterResult
            fixture.isActive = false
            let recording = try await fixture.makeRecording()
            let observation = recording.observeTerminal { _ in }

            #expect(await recording.start() == expected)
            #expect(!recording.isActive)

            observation.cancel()
        }
    }

    @Test
    func descriptionsAndMirrorsDoNotExposeAttemptIdentity() async throws {
        let fixture = RecorderBridgeFixture()
        let bridge = fixture.makeBridge()
        _ = try await bridge.makeRecording(
            attemptID: UUID(),
            outputIntent: .standard
        )

        #expect(String(describing: bridge).contains("<redacted>"))
        #expect(String(reflecting: bridge).contains("<redacted>"))
        #expect(Mirror(reflecting: bridge).children.isEmpty)
        #expect(String(describing: fixture.driver).contains("<redacted>"))
        #expect(Mirror(reflecting: fixture.driver).children.isEmpty)
    }
}

private enum RecorderBridgeError: Error {
    case failed
}

@MainActor
private final class RecorderBridgeGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

@MainActor
private final class RecorderBridgeFixture {
    var startResult = IOSVoiceRecorderStartResult.recording
    var stopResult = IOSVoiceRecorderStopResult.discarded
    var terminalEvent: IOSVoiceRecorderTerminalEvent?
    var isActive = true
    private(set) var createdAttemptID: UUID?
    private(set) var createdOutputIntent: DictationOutputIntent?
    private(set) var stopReasons: [IOSVoiceRecorderStopReason] = []

    lazy var driver = IOSForegroundVoiceRecorderBridgeDriver(
        start: { [weak self] _ in self?.startResult ?? .cancelled },
        stop: { [weak self] _, reason in
            guard let self else { return .stale }
            stopReasons.append(reason)
            isActive = false
            return stopResult
        },
        waitForTerminal: { [weak self] _ in
            IOSVoiceRecorderTerminalWait(
                wait: { self?.terminalEvent ?? .stale }
            )
        },
        isActivelyRecording: { [weak self] _ in self?.isActive == true }
    )

    func makeBridge(
        feedback: IOSForegroundVoiceFeedbackBridge? = nil
    ) -> IOSForegroundVoiceRecorderBridge {
        IOSForegroundVoiceRecorderBridge(
            makeDriver: { [weak self] attemptID, outputIntent in
                guard let self else { throw RecorderBridgeError.failed }
                createdAttemptID = attemptID
                createdOutputIntent = outputIntent
                return driver
            },
            preparePending: { handoff, configuration in
                try await handoff.preparePending(
                    using: IOSV1ForegroundVoicePersistenceOwner(
                        applicationSupportDirectoryURL: URL(
                            fileURLWithPath: "/tmp/holdtype-recorder-bridge",
                            isDirectory: true
                        )
                    ),
                    transcriptionConfiguration: configuration
                )
            },
            feedback: feedback
        )
    }

    func makeRecording() async throws
        -> IOSForegroundVoiceWorkflowRecording {
        try await makeBridge().makeRecording(
            attemptID: UUID(),
            outputIntent: .standard
        )
    }
}

private func isDiscarded(
    _ result: IOSForegroundVoiceWorkflowCaptureStopResult
) -> Bool {
    if case .discarded = result { return true }
    return false
}

private func isInvalid(
    _ result: IOSForegroundVoiceWorkflowCaptureStopResult,
    reason: IOSV1ForegroundVoiceCaptureInvalidReason
) -> Bool {
    if case .invalid(let actual) = result { return actual == reason }
    return false
}

private func isPreserved(
    _ result: IOSForegroundVoiceWorkflowCaptureStopResult
) -> Bool {
    if case .preserved = result { return true }
    return false
}

private func makeRecorderBridgePending() throws -> IOSV1PendingRecording {
    let attemptID = UUID()
    let now = Date(timeIntervalSinceReferenceDate: 1_000)
    let state = try IOSVoiceStatePending(
        attemptID: attemptID,
        audioRelativeIdentifier: IOSVoiceStateStorageLocation
            .relativeAudioIdentifier(for: attemptID),
        createdAt: now,
        updatedAt: now,
        outputIntent: .standard,
        transcriptionModel: TranscriptionConfiguration.defaultModel,
        transcriptionLanguageCode: nil,
        durationMilliseconds: 1_000,
        byteCount: 2_000,
        status: .ready
    )
    return IOSV1PendingRecording(state)
}

@MainActor
private func recorderBridgeEventually(
    _ condition: @MainActor () -> Bool
) async throws {
    for _ in 0..<100 where !condition() {
        await Task.yield()
    }
    guard condition() else { throw RecorderBridgeError.failed }
}
