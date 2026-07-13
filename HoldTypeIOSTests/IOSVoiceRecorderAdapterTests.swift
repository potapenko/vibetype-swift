import AudioToolbox
import AVFAudio
import Foundation
import HoldTypeDomain
import Testing
@_spi(HoldTypeIOSCore) @testable import HoldTypePersistence
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

    @Test func completedCapabilityIsClaimedOnceAndFailedPreparePreservesIt()
        async throws {
        let fixture = VoiceRecorderFixture()
        let adapter = fixture.makeAdapter()
        let token = IOSVoiceRecorderAttemptToken()
        #expect(await adapter.start(for: token) == .recording)
        guard case let .completed(completed) = await adapter.stop(
            for: token,
            reason: .done
        ) else {
            Issue.record("Expected a completed capture.")
            return
        }

        let handoff = try #require(completed.claimPersistenceHandoff())
        #expect(completed.claimPersistenceHandoff() == nil)
        let persistenceOwner = IOSV1ForegroundVoicePersistenceOwner(
            applicationSupportDirectoryURL: URL(
                fileURLWithPath: "/tmp/holdtype-recorder-handoff-tests",
                isDirectory: true
            )
        )
        await #expect(throws: VoiceRecorderFixtureError.self) {
            _ = try await handoff.preparePending(
                using: persistenceOwner,
                transcriptionConfiguration: .defaults
            )
        }
        #expect(fixture.source.completedPrepareCallCount == 1)
        #expect(fixture.source.completedReleaseCount == 0)

        handoff.release()
        handoff.release()
        completed.release()
        #expect(fixture.source.completedReleaseCount == 1)
    }

    @Test func completedPayloadDropReleasesWhileAdapterRemainsAlive()
        async throws {
        let fixture = VoiceRecorderFixture()
        let adapter = fixture.makeAdapter()
        let token = IOSVoiceRecorderAttemptToken()
        #expect(await adapter.start(for: token) == .recording)

        weak var weakCapture: IOSVoiceRecorderCompletedCapture?
        do {
            let result = await adapter.stop(for: token, reason: .done)
            guard case let .completed(completed) = result else {
                Issue.record("Expected a completed capture.")
                return
            }
            weakCapture = completed
            #expect(fixture.source.completedReleaseCount == 0)
        }

        try await recorderEventually {
            weakCapture == nil
                && fixture.source.completedReleaseCount == 1
        }
        #expect(
            (await adapter.stop(for: token, reason: .done)).isStale
        )
        #expect(String(describing: adapter).contains("<redacted>"))
    }

    @Test func handoffSuccessReleasesExactlyOnceAndCannotBeReused()
        async throws {
        let pending = try makePendingRecording()
        let fixture = CompletedCaptureHandoffFixture(
            prepare: { _, _ in pending }
        )
        let completed = fixture.makeCompletedCapture()
        let handoff = try #require(completed.claimPersistenceHandoff())

        #expect(
            try await handoff.preparePending(
                using: makePassivePersistenceOwner(),
                transcriptionConfiguration: .defaults
            ) == pending
        )
        #expect(fixture.prepareCount == 1)
        #expect(fixture.releaseCount == 1)
        await #expect(
            throws: IOSVoiceRecorderCompletedCaptureHandoffError.unavailable
        ) {
            _ = try await handoff.preparePending(
                using: makePassivePersistenceOwner(),
                transcriptionConfiguration: .defaults
            )
        }
        handoff.release()
        completed.release()
        #expect(fixture.releaseCount == 1)
    }

    @Test func failedHandoffCanRetryAndReleasesOnlyAfterSuccess()
        async throws {
        let pending = try makePendingRecording()
        let fixture = CompletedCaptureHandoffFixture(
            prepare: { _, callCount in
                if callCount == 1 { throw VoiceRecorderFixtureError() }
                return pending
            }
        )
        let completed = fixture.makeCompletedCapture()
        let handoff = try #require(completed.claimPersistenceHandoff())

        await #expect(throws: VoiceRecorderFixtureError.self) {
            _ = try await handoff.preparePending(
                using: makePassivePersistenceOwner(),
                transcriptionConfiguration: .defaults
            )
        }
        #expect(fixture.releaseCount == 0)
        #expect(
            try await handoff.preparePending(
                using: makePassivePersistenceOwner(),
                transcriptionConfiguration: .defaults
            ) == pending
        )
        #expect(fixture.prepareCount == 2)
        #expect(fixture.releaseCount == 1)
    }

    @Test func captureAndClaimedHandoffDropsHaveDistinctOwnership()
        async throws {
        let beforeClaim = CompletedCaptureHandoffFixture()
        var unclaimed: IOSVoiceRecorderCompletedCapture? =
            beforeClaim.makeCompletedCapture()
        weak let weakUnclaimed = unclaimed
        unclaimed = nil
        #expect(weakUnclaimed == nil)
        try await recorderEventually { beforeClaim.releaseCount == 1 }

        let afterClaim = CompletedCaptureHandoffFixture()
        var completed: IOSVoiceRecorderCompletedCapture? =
            afterClaim.makeCompletedCapture()
        var handoff: IOSVoiceRecorderCompletedCaptureHandoff? = try #require(
            completed?.claimPersistenceHandoff()
        )
        weak let weakHandoff = handoff
        completed = nil
        #expect(afterClaim.releaseCount == 0)
        handoff = nil
        #expect(weakHandoff == nil)
        try await recorderEventually { afterClaim.releaseCount == 1 }
    }

    @Test func releaseDuringPrepareConvergesExactlyOnceForSuccessAndFailure()
        async throws {
        for shouldSucceed in [true, false] {
            let latch = CompletedCapturePrepareLatch()
            let pending = try makePendingRecording()
            let fixture = CompletedCaptureHandoffFixture(
                prepare: { _, _ in
                    await latch.wait()
                    if !shouldSucceed { throw VoiceRecorderFixtureError() }
                    return pending
                }
            )
            let completed = fixture.makeCompletedCapture()
            let handoff = try #require(completed.claimPersistenceHandoff())
            let task = Task {
                try await handoff.preparePending(
                    using: makePassivePersistenceOwner(),
                    transcriptionConfiguration: .defaults
                )
            }
            try await recorderEventually { fixture.prepareCount == 1 }

            handoff.release()
            handoff.release()
            #expect(fixture.releaseCount == 0)
            latch.open()
            if shouldSucceed {
                #expect(try await task.value == pending)
            } else {
                await #expect(throws: VoiceRecorderFixtureError.self) {
                    _ = try await task.value
                }
            }
            #expect(fixture.releaseCount == 1)
            await #expect(
                throws: IOSVoiceRecorderCompletedCaptureHandoffError.unavailable
            ) {
                _ = try await handoff.preparePending(
                    using: makePassivePersistenceOwner(),
                    transcriptionConfiguration: .defaults
                )
            }
        }
    }

    @Test func interruptionFinalizesValidPartialAndDiscardsShortPartial()
        async {
        let shortFixture = VoiceRecorderFixture()
        shortFixture.source.finalizationInvalidReason = .tooShort
        let shortAdapter = shortFixture.makeAdapter()
        let shortToken = IOSVoiceRecorderAttemptToken()
        #expect(await shortAdapter.start(for: shortToken) == .recording)
        let short = await shortAdapter.stop(
            for: shortToken,
            reason: .interrupted
        )
        #expect(short.invalidReason == .tooShort)
        assertOrdered(
            [.beginFinalizing, .stop, .complete],
            in: shortFixture.log.calls
        )
        #expect(!shortFixture.log.calls.contains(.beginDiscarding))

        let validFixture = VoiceRecorderFixture()
        validFixture.source.completedDurationMilliseconds = 300
        let validAdapter = validFixture.makeAdapter()
        let validToken = IOSVoiceRecorderAttemptToken()
        #expect(await validAdapter.start(for: validToken) == .recording)
        let valid = await validAdapter.stop(
            for: validToken,
            reason: .interrupted
        )
        guard case let .completed(completed) = valid else {
            Issue.record("Expected a recoverable completed partial.")
            return
        }
        #expect(completed.durationMilliseconds == 300)
        assertOrdered(
            [.beginFinalizing, .stop, .complete],
            in: validFixture.log.calls
        )
        #expect(!validFixture.log.calls.contains(.beginDiscarding))
        completed.release()
        #expect(validFixture.source.completedReleaseCount == 1)
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

    @Test func internalMaximumPublishesOneExplicitTerminalAndCannotRecover()
        async throws {
        let fixture = VoiceRecorderFixture()
        let adapter = fixture.makeAdapter()
        let token = IOSVoiceRecorderAttemptToken()
        #expect(await adapter.start(for: token) == .recording)
        let terminalTask = Task {
            await adapter.waitForTerminal(for: token).value()
        }
        try await recorderEventually { fixture.sleep.waiterCount == 1 }

        fixture.sleep.fire()
        let terminal = await terminalTask.value
        #expect(terminal.cause == .maximumDuration)
        #expect(terminal.result.invalidReason == .maximumDurationReached)
        #expect(
            (await adapter.waitForTerminal(for: token).value()).cause == .stale
        )
        #expect(
            (await adapter.stop(for: token, reason: .done)).invalidReason
                == .maximumDurationReached
        )
        #expect(!fixture.log.calls.contains(.beginFinalizing))
        assertOrdered(
            [.beginDiscarding, .stop, .finishDiscard],
            in: fixture.log.calls
        )
    }

    @Test func maximumWatchdogFailureStopsFailClosedAndDiscardsExactlyOnce()
        async throws {
        let fixture = VoiceRecorderFixture()
        let adapter = fixture.makeAdapter()
        let token = IOSVoiceRecorderAttemptToken()
        #expect(await adapter.start(for: token) == .recording)
        let terminalTask = Task {
            await adapter.waitForTerminal(for: token).value()
        }
        try await recorderEventually { fixture.sleep.waiterCount == 1 }

        fixture.sleep.fail()

        let terminal = await terminalTask.value
        #expect(terminal.cause == .maximumDuration)
        #expect(terminal.result.invalidReason == .maximumDurationReached)
        #expect(fixture.recorder.stopCount == 1)
        #expect(fixture.source.releaseCount == 0)
        #expect(
            fixture.log.calls.filter { $0 == .beginDiscarding }.count == 1
        )
        #expect(fixture.log.calls.filter { $0 == .stop }.count == 1)
        #expect(
            fixture.log.calls.filter { $0 == .finishDiscard }.count == 1
        )
        #expect(!fixture.log.calls.contains(.beginFinalizing))
        #expect(!fixture.log.calls.contains(.complete))
        #expect(
            (await adapter.stop(for: token, reason: .done)).invalidReason
                == .maximumDurationReached
        )
    }

    @Test func delegateTerminalWakesOneWaiterAndRejectsSecondClaim()
        async throws {
        let fixture = VoiceRecorderFixture()
        let adapter = fixture.makeAdapter()
        let token = IOSVoiceRecorderAttemptToken()
        #expect(await adapter.start(for: token) == .recording)
        let first = Task {
            await adapter.waitForTerminal(for: token).value()
        }
        await Task.yield()
        #expect(
            (await adapter.waitForTerminal(for: token).value()).cause == .stale
        )

        fixture.recorder.emit(.encodeError)
        let terminal = await first.value
        #expect(terminal.cause == .recorderEndedUnexpectedly)
        #expect(
            terminal.result.preservedFailure
                == .recorderEndedUnexpectedly
        )
        #expect(
            (await adapter.waitForTerminal(for: token).value()).cause == .stale
        )
    }

    @Test func cancelledTerminalWaitReleasesClaimForReplacement()
        async throws {
        let fixture = VoiceRecorderFixture()
        let adapter = fixture.makeAdapter()
        let token = IOSVoiceRecorderAttemptToken()
        #expect(await adapter.start(for: token) == .recording)
        let cancelledWait = Task {
            await adapter.waitForTerminal(for: token).value()
        }
        await Task.yield()
        #expect(
            (await adapter.waitForTerminal(for: token).value()).cause == .stale
        )

        cancelledWait.cancel()
        #expect((await cancelledWait.value).cause == .stale)

        let replacement = Task {
            await adapter.waitForTerminal(for: token).value()
        }
        await Task.yield()
        #expect(
            (await adapter.waitForTerminal(for: token).value()).cause == .stale
        )
        fixture.recorder.emit(.encodeError)
        let event = await replacement.value
        #expect(event.cause == .recorderEndedUnexpectedly)
        #expect(
            event.result.preservedFailure == .recorderEndedUnexpectedly
        )
    }

    @Test func droppingAdapterResolvesTerminalWaitAndPreservesSource()
        async throws {
        let fixture = VoiceRecorderFixture()
        var adapter: IOSVoiceRecorderAdapter? = fixture.makeAdapter()
        weak let weakAdapter = adapter
        let token = IOSVoiceRecorderAttemptToken()
        #expect(await adapter?.start(for: token) == .recording)
        let terminalWait = try #require(
            adapter?.waitForTerminal(for: token)
        )
        let terminalTask = Task { await terminalWait.value() }
        await Task.yield()
        let duplicate = adapter?.waitForTerminal(for: token)
        #expect((await duplicate?.value())?.cause == .stale)

        adapter = nil
        #expect((await terminalTask.value).cause == .stale)
        #expect(weakAdapter == nil)
        #expect(fixture.recorder.stopCount == 1)
        #expect(fixture.source.releaseCount == 1)
    }

    @Test func droppingUnawaitedTerminalWaitReleasesClaimForReplacement()
        async throws {
        let fixture = VoiceRecorderFixture()
        let adapter = fixture.makeAdapter()
        let token = IOSVoiceRecorderAttemptToken()
        #expect(await adapter.start(for: token) == .recording)

        var abandoned: IOSVoiceRecorderTerminalWait? =
            adapter.waitForTerminal(for: token)
        weak let weakAbandoned = abandoned
        #expect(
            (await adapter.waitForTerminal(for: token).value()).cause == .stale
        )
        abandoned = nil
        #expect(weakAbandoned == nil)
        await Task.yield()

        let replacement = adapter.waitForTerminal(for: token)
        fixture.recorder.emit(.encodeError)
        let event = await replacement.value()
        #expect(event.cause == .recorderEndedUnexpectedly)
        #expect(
            event.result.preservedFailure == .recorderEndedUnexpectedly
        )
    }

    @Test func observedDelegateFailureWinsOverLaterMaximumAndDone()
        async throws {
        let fixture = VoiceRecorderFixture()
        let adapter = fixture.makeAdapter()
        let token = IOSVoiceRecorderAttemptToken()
        #expect(await adapter.start(for: token) == .recording)
        let terminalTask = Task {
            await adapter.waitForTerminal(for: token).value()
        }
        try await recorderEventually { fixture.sleep.waiterCount == 1 }

        fixture.recorder.emit(.finished(successfully: false))
        fixture.sleep.fire()
        let doneTask = Task {
            await adapter.stop(for: token, reason: .done)
        }
        let terminal = await terminalTask.value
        let repeated = await doneTask.value

        #expect(terminal.cause == .recorderEndedUnexpectedly)
        #expect(
            terminal.result.preservedFailure == .recorderEndedUnexpectedly
        )
        #expect(repeated.preservedFailure == .recorderEndedUnexpectedly)
        #expect(!fixture.log.calls.contains(.beginDiscarding))
        #expect(!fixture.log.calls.contains(.beginFinalizing))
        #expect(fixture.recorder.stopCount == 1)
        #expect(
            (await adapter.waitForTerminal(for: token).value()).cause == .stale
        )
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

    @Test func publicDescriptionsAndMirrorsStayPayloadFree() async throws {
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
        let terminal = IOSVoiceRecorderTerminalEvent(
            cause: .failed(.checkpointFailed),
            result: result
        )
        let captureFixture = CompletedCaptureHandoffFixture()
        let completed = captureFixture.makeCompletedCapture()
        let handoff = try #require(completed.claimPersistenceHandoff())
        let terminalWait = adapter.waitForTerminal(
            for: IOSVoiceRecorderAttemptToken()
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
            String(describing: terminal),
            String(reflecting: terminal),
            String(describing: completed),
            String(reflecting: completed),
            String(describing: handoff),
            String(reflecting: handoff),
            String(describing: terminalWait),
            String(reflecting: terminalWait),
        ] {
            #expect(value.contains("<redacted>"))
            #expect(!value.lowercased().contains(canary))
            #expect(!value.contains("private-recorder-url"))
        }
        #expect(Mirror(reflecting: token).children.isEmpty)
        #expect(Mirror(reflecting: fixture.client).children.isEmpty)
        #expect(Mirror(reflecting: adapter).children.isEmpty)
        #expect(Mirror(reflecting: result).children.isEmpty)
        #expect(Mirror(reflecting: terminal).children.isEmpty)
        #expect(Mirror(reflecting: completed).children.isEmpty)
        #expect(Mirror(reflecting: handoff).children.isEmpty)
        #expect(Mirror(reflecting: terminalWait).children.isEmpty)
        handoff.release()
        #expect(captureFixture.releaseCount == 1)
    }
}

struct IOSVoiceRecorderCrossExecutorLifetimeTests {
    @Test func activeAdapterDeinitHopsToMainActorAndPreservesAttempt()
        async throws {
        let setup = try await makeActiveAdapterDropSetup()
        let terminalTask = Task {
            await setup.terminalWait.value()
        }

        await dropLastReferenceOffMain(setup.adapter)

        #expect((await terminalTask.value).cause == .stale)
        try await crossExecutorEventually {
            await MainActor.run {
                setup.fixture.recorder.stopCount == 1
                    && setup.fixture.source.releaseCount == 1
            }
        }
        await MainActor.run {
            #expect(setup.fixture.recorder.stopCount == 1)
            #expect(setup.fixture.source.releaseCount == 1)
        }
    }

    @Test func handleDeinitHopsToMainActorExactlyOnce() async throws {
        let completed = await MainActor.run {
            let probe = CrossExecutorReleaseProbe()
            let value = IOSVoiceRecorderCompletedCapture(
                durationMilliseconds: 1_000,
                byteCount: 2_000,
                release: { probe.record() }
            )
            return (probe, CrossExecutorDropBox(value))
        }
        let handoff = await MainActor.run {
            let probe = CrossExecutorReleaseProbe()
            let value = IOSVoiceRecorderCompletedCaptureHandoff(
                preparePending: { _, _ in
                    throw IOSVoiceRecorderCompletedCaptureHandoffError
                        .unavailable
                },
                release: { probe.record() }
            )
            return (probe, CrossExecutorDropBox(value))
        }
        let terminalWait = await MainActor.run {
            let probe = CrossExecutorReleaseProbe()
            let value = IOSVoiceRecorderTerminalWait(
                wait: { .stale },
                cancel: { probe.record() }
            )
            return (probe, CrossExecutorDropBox(value))
        }

        await dropLastReferenceOffMain(completed.1)
        await dropLastReferenceOffMain(handoff.1)
        await dropLastReferenceOffMain(terminalWait.1)

        try await crossExecutorEventually {
            await MainActor.run {
                completed.0.count == 1
                    && handoff.0.count == 1
                    && terminalWait.0.count == 1
            }
        }
        await MainActor.run {
            #expect(completed.0.count == 1)
            #expect(handoff.0.count == 1)
            #expect(terminalWait.0.count == 1)
        }
    }

    @Test func finishDelegatePayloadHopsFromOffMainToMainActor()
        async throws {
        let setup = await MainActor.run {
            let probe = CrossExecutorRecorderEventProbe()
            let bridge = IOSVoiceAVAudioRecorderDelegateBridge(
                receive: probe.record
            )
            return (probe, bridge)
        }

        await Task.detached {
            setup.1.recorderDidFinish(successfully: false)
        }.value

        try await crossExecutorEventually {
            await MainActor.run {
                setup.0.events == [.finished(successfully: false)]
            }
        }
        await MainActor.run {
            #expect(setup.0.events == [.finished(successfully: false)])
        }
    }

    @Test func encodeDelegatePayloadHopsFromOffMainToMainActor()
        async throws {
        let setup = await MainActor.run {
            let probe = CrossExecutorRecorderEventProbe()
            let bridge = IOSVoiceAVAudioRecorderDelegateBridge(
                receive: probe.record
            )
            return (probe, bridge)
        }

        await Task.detached {
            setup.1.recorderEncodeFailed()
        }.value

        try await crossExecutorEventually {
            await MainActor.run {
                setup.0.events == [.encodeError]
            }
        }
        await MainActor.run {
            #expect(setup.0.events == [.encodeError])
        }
    }
}

private struct CrossExecutorAdapterDropSetup: Sendable {
    let fixture: VoiceRecorderFixture
    let adapter: CrossExecutorDropBox<IOSVoiceRecorderAdapter>
    let terminalWait: IOSVoiceRecorderTerminalWait
}

@MainActor
private func makeActiveAdapterDropSetup() async throws
    -> CrossExecutorAdapterDropSetup {
    let fixture = VoiceRecorderFixture()
    let adapter = fixture.makeAdapter()
    let token = IOSVoiceRecorderAttemptToken()
    guard await adapter.start(for: token) == .recording else {
        throw VoiceRecorderFixtureError()
    }
    return CrossExecutorAdapterDropSetup(
        fixture: fixture,
        adapter: CrossExecutorDropBox(adapter),
        terminalWait: adapter.waitForTerminal(for: token)
    )
}

@MainActor
private final class CrossExecutorReleaseProbe {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

@MainActor
private final class CrossExecutorRecorderEventProbe {
    private(set) var events: [IOSVoiceRecorderEvent] = []

    func record(_ event: IOSVoiceRecorderEvent) {
        events.append(event)
    }
}

private final class CrossExecutorDropBox<Value: Sendable>:
    @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    init(_ value: Value) {
        self.value = value
    }

    func take() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        let value = value
        self.value = nil
        return value
    }
}

private func dropLastReferenceOffMain<Value: Sendable>(
    _ box: CrossExecutorDropBox<Value>
) async {
    await Task.detached {
        let value = box.take()
        withExtendedLifetime(value) {}
    }.value
}

private func crossExecutorEventually(
    _ predicate: @escaping @Sendable () async -> Bool
) async throws {
    for _ in 0..<300 {
        if await predicate() { return }
        await Task.yield()
    }
    throw IOSVoiceRecorderCrossExecutorTestTimeout()
}

private struct IOSVoiceRecorderCrossExecutorTestTimeout: Error {}

@MainActor
private final class CompletedCaptureHandoffFixture {
    typealias Prepare = @MainActor @Sendable (
        TranscriptionConfiguration,
        Int
    ) async throws -> IOSV1PendingRecording

    private let prepare: Prepare
    private(set) var prepareCount = 0
    private(set) var releaseCount = 0

    init(
        prepare: @escaping Prepare = { _, _ in
            throw VoiceRecorderFixtureError()
        }
    ) {
        self.prepare = prepare
    }

    func makeCompletedCapture() -> IOSVoiceRecorderCompletedCapture {
        IOSVoiceRecorderCompletedCapture(
            durationMilliseconds: 1_000,
            byteCount: 2_000,
            preparePending: { [weak self] _, configuration in
                guard let self else { throw VoiceRecorderFixtureError() }
                prepareCount += 1
                return try await prepare(configuration, prepareCount)
            },
            release: { [weak self] in
                self?.releaseCount += 1
            }
        )
    }
}

@MainActor
private final class CompletedCapturePrepareLatch {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

@MainActor
private func makePassivePersistenceOwner()
    -> IOSV1ForegroundVoicePersistenceOwner {
    IOSV1ForegroundVoicePersistenceOwner(
        applicationSupportDirectoryURL: URL(
            fileURLWithPath: "/tmp/holdtype-recorder-handoff-tests",
            isDirectory: true
        )
    )
}

private func makePendingRecording() throws -> IOSV1PendingRecording {
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
    private(set) var completedPrepareCallCount = 0
    var checkpointFailureAt: Int?
    var suspendedCheckpoint: Int?
    var failurePoint: FailurePoint?
    var finalizationInvalidReason: IOSV1ForegroundVoiceCaptureInvalidReason?
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
                preparePending: { [weak self] _, _ in
                    self?.completedPrepareCallCount += 1
                    throw VoiceRecorderFixtureError()
                },
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

    func fail() {
        let waiters = waiters.values
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.continuation.resume(throwing: VoiceRecorderFixtureError())
        }
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
    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }

    var isDiscarded: Bool {
        if case .discarded = self { return true }
        return false
    }

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }

    var invalidReason: IOSV1ForegroundVoiceCaptureInvalidReason? {
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
