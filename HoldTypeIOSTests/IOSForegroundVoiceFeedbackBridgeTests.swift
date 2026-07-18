import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSForegroundVoiceFeedbackBridgeTests {
    @Test
    func doneRetainsOneTokenUntilExplicitSuccessBoundary() async {
        let fixture = FeedbackBridgeFixture()
        let bridge = fixture.makeBridge()

        #expect(await bridge.playStartBoundary(audioCuesEnabled: true))
        guard let handle = requireFeedbackHandle(bridge) else { return }
        #expect(bridge.retainedCaptureDidBegin(for: handle))
        await bridge.recorderDidClose(.done, for: handle)
        #expect(fixture.closeCalls.isEmpty)
        #expect(bridge.hasActiveAttempt)

        await bridge.playStopBoundary(audioCuesEnabled: true)
        #expect(fixture.closeCalls.count == 1)
        #expect(fixture.closeCalls.first?.disposition == .success)
        #expect(fixture.closeCalls.first?.preferences == .p4(
            audioCuesEnabled: true
        ))
        #expect(!bridge.hasActiveAttempt)

        await bridge.playStopBoundary(audioCuesEnabled: true)
        #expect(fixture.closeCalls.count == 1)
    }

    @Test
    func cancelAndInterruptionNeverProduceSuccessFeedback() async {
        for reason in [
            IOSForegroundVoiceWorkflowCaptureStopReason.cancelled,
            .interrupted,
        ] {
            let fixture = FeedbackBridgeFixture()
            let bridge = fixture.makeBridge()
            #expect(await bridge.playStartBoundary(audioCuesEnabled: false))
            guard let handle = requireFeedbackHandle(bridge) else { return }
            #expect(bridge.retainedCaptureDidBegin(for: handle))

            await bridge.recorderDidClose(reason, for: handle)
            await bridge.playStopBoundary(audioCuesEnabled: false)

            #expect(fixture.closeCalls.count == 1)
            #expect(fixture.closeCalls.first?.disposition != .success)
            #expect(!bridge.hasActiveAttempt)
        }
    }

    @Test
    func maximumDurationProducesTerminalFeedbackOnlyAfterRecorderClose() async {
        let fixture = FeedbackBridgeFixture()
        let bridge = fixture.makeBridge()

        #expect(await bridge.playStartBoundary(audioCuesEnabled: true))
        guard let handle = requireFeedbackHandle(bridge) else { return }
        #expect(bridge.retainedCaptureDidBegin(for: handle))
        #expect(fixture.closeCalls.isEmpty)

        await bridge.recorderDidClose(.maximumDuration, for: handle)

        #expect(fixture.closeCalls.count == 1)
        #expect(fixture.closeCalls.first?.disposition == .success)
        #expect(!bridge.hasActiveAttempt)
    }

    @Test
    func limitWarningUsesFrozenCuePreferenceOnlyForCurrentCapture() async {
        let fixture = FeedbackBridgeFixture()
        var received: [(VoiceSessionWarning, Bool)] = []
        let bridge = fixture.makeBridge { warning, audioCuesEnabled in
            received.append((warning, audioCuesEnabled))
        }
        let warning = VoiceSessionWarningSchedule(
            limit: .default
        ).warnings[0]

        #expect(await bridge.playStartBoundary(audioCuesEnabled: false))
        guard let handle = requireFeedbackHandle(bridge) else { return }
        bridge.playLimitWarning(warning, for: handle)
        #expect(received.isEmpty)

        #expect(bridge.retainedCaptureDidBegin(for: handle))
        bridge.playLimitWarning(warning, for: handle)
        #expect(received.count == 1)
        #expect(received.first?.0 == warning)
        #expect(received.first?.1 == false)

        await bridge.recorderDidClose(.cancelled, for: handle)
        bridge.playLimitWarning(warning, for: handle)
        #expect(received.count == 1)
    }

    @Test
    func cueFailureAndTimeoutRemainEligibleForFrozenRevalidation() async {
        for result in [
            IOSVoiceBoundaryStartResult.cueUnavailable,
            .cueFailed,
            .timedOut,
        ] {
            let fixture = FeedbackBridgeFixture()
            fixture.startResult = result
            let bridge = fixture.makeBridge()

            #expect(await bridge.playStartBoundary(audioCuesEnabled: true))
            guard let handle = requireFeedbackHandle(bridge) else { return }
            #expect(bridge.retainedCaptureDidBegin(for: handle))
            await bridge.recorderDidClose(.cancelled, for: handle)
            #expect(!bridge.hasActiveAttempt)
        }
    }

    @Test
    func recorderConstructionFailureAbandonsReadyTokenExactlyOnce() async {
        let fixture = FeedbackBridgeFixture()
        let bridge = fixture.makeBridge()
        #expect(await bridge.playStartBoundary(audioCuesEnabled: true))
        guard let handle = requireFeedbackHandle(bridge) else { return }

        bridge.retainedCaptureDidNotBegin(for: handle)
        bridge.retainedCaptureDidNotBegin(for: handle)

        #expect(fixture.abandonedTokens.count == 1)
        #expect(!bridge.hasActiveAttempt)
    }

    @Test
    func cancelledStartRetiresTokenAndLaterStartUsesFreshToken() async {
        let fixture = FeedbackBridgeFixture()
        let first = IOSVoiceBoundaryFeedbackToken()
        let second = IOSVoiceBoundaryFeedbackToken()
        fixture.tokens = [first, second]
        let bridge = fixture.makeBridge()

        #expect(await bridge.playStartBoundary(audioCuesEnabled: true))
        guard let firstHandle = requireFeedbackHandle(bridge) else { return }
        bridge.cancelStartBoundary()
        #expect(await bridge.playStartBoundary(audioCuesEnabled: true))
        guard let secondHandle = requireFeedbackHandle(bridge) else { return }
        bridge.retainedCaptureDidNotBegin(for: secondHandle)

        #expect(fixture.startTokens == [first, second])
        #expect(fixture.abandonedTokens == [first, second])
        #expect(firstHandle != secondHandle)
        #expect(!bridge.hasActiveAttempt)
    }

    @Test
    func nextStartRetiresDoneTokenWhenWorkflowSkippedSuccessBoundary()
        async {
        let fixture = FeedbackBridgeFixture()
        let first = IOSVoiceBoundaryFeedbackToken()
        let second = IOSVoiceBoundaryFeedbackToken()
        fixture.tokens = [first, second]
        let bridge = fixture.makeBridge()

        #expect(await bridge.playStartBoundary(audioCuesEnabled: true))
        guard let firstHandle = requireFeedbackHandle(bridge) else { return }
        #expect(bridge.retainedCaptureDidBegin(for: firstHandle))
        await bridge.recorderDidClose(.done, for: firstHandle)

        #expect(await bridge.playStartBoundary(audioCuesEnabled: false))
        guard let secondHandle = requireFeedbackHandle(bridge) else { return }
        #expect(fixture.startTokens == [first, second])
        #expect(fixture.closeCalls.count == 1)
        #expect(fixture.closeCalls.first?.token == first)
        #expect(fixture.closeCalls.first?.disposition == .interrupted)
        #expect(fixture.closeCalls.first?.preferences == .p4(
            audioCuesEnabled: true
        ))

        bridge.retainedCaptureDidNotBegin(for: secondHandle)
        #expect(!bridge.hasActiveAttempt)
    }

    @Test
    func staleOldRecorderCloseCannotConsumeNewCaptureToken() async {
        let fixture = FeedbackBridgeFixture()
        let bridge = fixture.makeBridge()

        #expect(await bridge.playStartBoundary(audioCuesEnabled: true))
        guard let firstHandle = requireFeedbackHandle(bridge) else { return }
        #expect(bridge.retainedCaptureDidBegin(for: firstHandle))
        await bridge.recorderDidClose(.cancelled, for: firstHandle)

        #expect(await bridge.playStartBoundary(audioCuesEnabled: true))
        guard let secondHandle = requireFeedbackHandle(bridge) else { return }
        #expect(bridge.retainedCaptureDidBegin(for: secondHandle))
        await bridge.recorderDidClose(.interrupted, for: firstHandle)
        #expect(bridge.hasActiveAttempt)
        await bridge.recorderDidClose(.done, for: secondHandle)
        await bridge.playStopBoundary(audioCuesEnabled: true)

        #expect(firstHandle != secondHandle)
        #expect(fixture.closeCalls.map(\.disposition) == [
            .cancelled,
            .success,
        ])
        #expect(!bridge.hasActiveAttempt)
    }

    @Test
    func descriptionsAndMirrorsAreRedacted() {
        let fixture = FeedbackBridgeFixture()
        let bridge = fixture.makeBridge()
        let handle = IOSForegroundVoiceFeedbackAttemptHandle()

        #expect(String(describing: bridge).contains("<redacted>"))
        #expect(String(reflecting: bridge).contains("<redacted>"))
        #expect(Mirror(reflecting: bridge).children.isEmpty)
        #expect(String(describing: fixture.driver).contains("<redacted>"))
        #expect(Mirror(reflecting: fixture.driver).children.isEmpty)
        #expect(String(describing: handle).contains("<redacted>"))
        #expect(String(reflecting: handle).contains("<redacted>"))
        #expect(Mirror(reflecting: handle).children.isEmpty)
    }
}

@MainActor
private func requireFeedbackHandle(
    _ bridge: IOSForegroundVoiceFeedbackBridge
) -> IOSForegroundVoiceFeedbackAttemptHandle? {
    guard let handle = bridge.recorderAttemptHandle else {
        Issue.record("Expected current feedback attempt handle")
        return nil
    }
    return handle
}

@MainActor
private final class FeedbackBridgeFixture {
    struct CloseCall {
        let token: IOSVoiceBoundaryFeedbackToken
        let disposition: IOSVoiceBoundaryRecorderCloseDisposition
        let preferences: IOSVoiceBoundaryFeedbackPreferences
    }

    var startResult = IOSVoiceBoundaryStartResult.completed
    var tokens: [IOSVoiceBoundaryFeedbackToken] = []
    private(set) var startTokens: [IOSVoiceBoundaryFeedbackToken] = []
    private(set) var abandonedTokens: [IOSVoiceBoundaryFeedbackToken] = []
    private(set) var closeCalls: [CloseCall] = []
    lazy var driver = IOSForegroundVoiceFeedbackBridgeDriver(
        prepareStartBoundary: { [weak self] token, _ in
            guard let self else { return .interrupted }
            startTokens.append(token)
            return startResult
        },
        cancelStart: { _, _ in },
        retainedCaptureDidBegin: { _ in true },
        abandonReadyBoundary: { [weak self] token in
            self?.abandonedTokens.append(token)
            return true
        },
        recorderDidClose: { [weak self] token, disposition, preferences in
            self?.closeCalls.append(
                CloseCall(
                    token: token,
                    disposition: disposition,
                    preferences: preferences
                )
            )
            return disposition == .success
                ? .feedbackCompleted
                : .feedbackSkipped
        }
    )

    func makeBridge(
        playLimitWarningFeedback: @escaping
            IOSForegroundVoiceFeedbackBridge.PlayLimitWarning = { _, _ in }
    ) -> IOSForegroundVoiceFeedbackBridge {
        IOSForegroundVoiceFeedbackBridge(
            driver: driver,
            makeToken: { [weak self] in
                guard let self, !tokens.isEmpty else {
                    return IOSVoiceBoundaryFeedbackToken()
                }
                return tokens.removeFirst()
            },
            playLimitWarningFeedback: playLimitWarningFeedback
        )
    }
}
