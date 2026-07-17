//
//  FloatingIndicatorPresentationTests.swift
//  HoldTypeTests
//
//  Created by Codex on 6/21/26.
//

import Foundation
import HoldTypeDomain
import Testing
@testable import HoldType

struct FloatingIndicatorPresentationTests {

    @Test func hidesIdleStatus() {
        let presentation = FloatingIndicatorPresentation.presentation(
            for: .idle,
            settings: .defaults
        )

        #expect(presentation == nil)
    }

    @Test func mapsRecordingStateToVisibleIndicator() {
        let recording = FloatingIndicatorPresentation.presentation(
            for: .recording,
            settings: .defaults
        )

        #expect(recording?.phase == .recording)
        #expect(recording?.title == "Recording")
        #expect(recording?.countdown == nil)
    }

    @Test func recordingCountdownIsVisibleAndAccessible() {
        let countdown = VoiceSessionCountdown(
            remainingWholeSeconds: 10,
            urgency: .red
        )
        let recording = FloatingIndicatorPresentation.presentation(
            for: .recording,
            settings: .defaults,
            recordingCountdown: countdown
        )

        #expect(recording?.countdown == countdown)
        #expect(recording?.accessibilityLabel == "HoldType Recording, 10 seconds remaining")
    }

    @Test func mapsTranscribingStateToVisibleIndicator() {
        let transcribing = FloatingIndicatorPresentation.presentation(
            for: .transcribing,
            settings: .defaults
        )

        #expect(transcribing?.phase == .transcribing)
        #expect(transcribing?.title == "Transcribing")
    }

    @Test func hidesTerminalStates() {
        #expect(FloatingIndicatorPresentation.presentation(for: .success(transcript: "Done"), settings: .defaults) == nil)
        #expect(FloatingIndicatorPresentation.presentation(for: .failure(message: "Error"), settings: .defaults) == nil)
    }

    @Test func disabledSettingSuppressesActiveIndicators() {
        var settings = AppSettings.defaults
        settings.showFloatingIndicator = false

        #expect(FloatingIndicatorPresentation.presentation(for: .recording, settings: settings) == nil)
        #expect(FloatingIndicatorPresentation.presentation(for: .transcribing, settings: settings) == nil)
    }

    @MainActor
    @Test func coordinatorPresentsRuntimeStatusOnStartAndHidesOnStop() {
        let presenter = FakeFloatingIndicatorPresenter()
        let runtime = makeRuntime(initialStatus: .recording)
        let coordinator = FloatingIndicatorCoordinator(
            dictationRuntime: runtime,
            appSettingsStore: AppSettingsStore(userDefaults: makeUserDefaults()),
            presenter: presenter
        )

        coordinator.start()

        #expect(presenter.lastPresentation?.phase == .recording)

        coordinator.stop()

        #expect(presenter.hideCount == 1)
    }

    @MainActor
    @Test func coordinatorRespondsToIndicatorSettingChanges() async {
        let userDefaults = makeUserDefaults()
        let appSettingsStore = AppSettingsStore(userDefaults: userDefaults)
        let presenter = FakeFloatingIndicatorPresenter()
        let runtime = makeRuntime(initialStatus: .recording)
        let coordinator = FloatingIndicatorCoordinator(
            dictationRuntime: runtime,
            appSettingsStore: appSettingsStore,
            presenter: presenter
        )

        coordinator.start()
        #expect(presenter.lastPresentation?.phase == .recording)

        var settings = AppSettings.defaults
        settings.showFloatingIndicator = false
        appSettingsStore.save(settings)

        await yieldUntil { presenter.lastPresentation == nil }

        #expect(presenter.lastPresentation == nil)

        coordinator.stop()
    }

    @MainActor
    @Test func coordinatorDoesNotRedeliverEquivalentPresentation() async {
        let presenter = FakeFloatingIndicatorPresenter()
        let runtime = makeRuntime(initialStatus: .recording)
        let coordinator = FloatingIndicatorCoordinator(
            dictationRuntime: runtime,
            appSettingsStore: AppSettingsStore(userDefaults: makeUserDefaults()),
            presenter: presenter
        )

        coordinator.start()
        await yieldSeveralTimes()

        #expect(presenter.presentations.count == 1)
        #expect(presenter.lastPresentation?.phase == .recording)

        coordinator.stop()
    }

    @MainActor
    @Test func hostingModelKeepsAnimationIdentityForCountdownUpdates() {
        let model = FloatingIndicatorHostingModel(
            presentation: FloatingIndicatorPresentation(
                phase: .recording,
                title: "Recording"
            )
        )
        let initialIdentity = model.state.animationIdentity

        model.update(
            with: FloatingIndicatorPresentation(
                phase: .recording,
                title: "Recording",
                countdown: VoiceSessionCountdown(
                    remainingWholeSeconds: 60,
                    urgency: .amber
                )
            ),
            restartsAnimation: false
        )

        #expect(model.state.animationIdentity == initialIdentity)
        #expect(model.state.presentation.countdown?.remainingWholeSeconds == 60)

        model.update(
            with: FloatingIndicatorPresentation(
                phase: .transcribing,
                title: "Transcribing"
            ),
            restartsAnimation: false
        )

        #expect(model.state.animationIdentity == initialIdentity + 1)
        #expect(model.state.presentation.phase == .transcribing)
    }

    @MainActor
    @Test func panelControllerKeepsHostingViewAcrossVisibleUpdates() {
        let controller = FloatingIndicatorPanelController()
        defer { controller.hide() }

        controller.update(
            with: FloatingIndicatorPresentation(
                phase: .recording,
                title: "Recording"
            )
        )
        let initialHostingViewIdentity = controller.hostingViewIdentity

        controller.update(
            with: FloatingIndicatorPresentation(
                phase: .recording,
                title: "Recording",
                countdown: VoiceSessionCountdown(
                    remainingWholeSeconds: 60,
                    urgency: .amber
                )
            )
        )
        #expect(initialHostingViewIdentity != nil)
        #expect(controller.hostingViewIdentity == initialHostingViewIdentity)

        controller.update(
            with: FloatingIndicatorPresentation(
                phase: .transcribing,
                title: "Transcribing"
            )
        )
        #expect(controller.hostingViewIdentity == initialHostingViewIdentity)
    }

    @MainActor
    private func makeRuntime(initialStatus: DictationStatus) -> DictationRuntime {
        let controller = DictationSessionController(initialStatus: initialStatus)
        return DictationRuntime(
            controller: controller,
            appSettingsStore: AppSettingsStore(userDefaults: makeUserDefaults()),
            hotkeyService: FakeGlobalHotkeyService()
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let userDefaults = UserDefaults(
            suiteName: "holdtype.FloatingIndicatorPresentationTests.\(UUID().uuidString)"
        )
        #expect(userDefaults != nil)
        return userDefaults!
    }

    @MainActor
    private func yieldUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<40 {
            if condition() {
                return
            }

            await Task.yield()
        }
    }

    @MainActor
    private func yieldSeveralTimes() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }
}

@MainActor
private final class FakeFloatingIndicatorPresenter: FloatingIndicatorPresenting {
    private(set) var presentations: [FloatingIndicatorPresentation?] = []
    private(set) var hideCount = 0

    var lastPresentation: FloatingIndicatorPresentation? {
        presentations.last ?? nil
    }

    func update(with presentation: FloatingIndicatorPresentation?) {
        presentations.append(presentation)
    }

    func hide() {
        hideCount += 1
    }
}
