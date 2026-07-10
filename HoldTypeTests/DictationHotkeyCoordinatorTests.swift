//
//  DictationHotkeyCoordinatorTests.swift
//  HoldTypeTests
//
//  Created by Codex on 6/22/26.
//

import HoldTypeDomain
import Testing
@testable import HoldType

@MainActor
struct DictationHotkeyCoordinatorTests {
    @Test func keyDownStartsThroughSharedRecordingAction() async throws {
        let hotkeyService = FakeGlobalHotkeyService()
        let recordingAction = FakeHotkeyRecordingAction(initialStatus: .idle)
        let coordinator = makeCoordinator(
            hotkeyService: hotkeyService,
            recordingAction: recordingAction
        )

        try coordinator.start()
        hotkeyService.trigger(.keyDown)
        await yieldUntil { recordingAction.performCount == 1 }

        #expect(recordingAction.status == .recording)
        #expect(recordingAction.observedStatuses == [.idle])
        #expect(recordingAction.observedIntents == [.standard])
        #expect(hotkeyService.currentRegistrationStatus == .registered(.defaultDictation))
    }

    @Test func keyUpStopsHotkeyStartedRecordingThroughSameAction() async throws {
        let hotkeyService = FakeGlobalHotkeyService()
        let recordingAction = FakeHotkeyRecordingAction(initialStatus: .idle)
        let coordinator = makeCoordinator(
            hotkeyService: hotkeyService,
            recordingAction: recordingAction
        )

        try coordinator.start()
        hotkeyService.trigger(.keyDown)
        await yieldUntil { recordingAction.status == .recording }
        hotkeyService.trigger(.keyUp)
        await yieldUntil { recordingAction.performCount == 2 }

        #expect(recordingAction.status == .success(transcript: "Hotkey transcript"))
        #expect(recordingAction.observedStatuses == [.idle, .recording])
        #expect(recordingAction.observedIntents == [.standard, .standard])
    }

    @Test func translationIntentCarriesFromKeyDownToKeyUp() async throws {
        let hotkeyService = FakeGlobalHotkeyService()
        let recordingAction = FakeHotkeyRecordingAction(initialStatus: .idle)
        let coordinator = makeCoordinator(
            hotkeyService: hotkeyService,
            recordingAction: recordingAction
        )

        try coordinator.start()
        hotkeyService.trigger(.keyDown(outputIntent: .translate))
        await yieldUntil { recordingAction.status == .recording }
        hotkeyService.trigger(.keyUp())
        await yieldUntil { recordingAction.performCount == 2 }

        #expect(recordingAction.status == .success(transcript: "Hotkey transcript"))
        #expect(
            recordingAction.observedIntents == [
                .translate,
                .translate,
            ]
        )
    }

    @Test func outputIntentChangePromotesActiveHotkeyRecording() async throws {
        let hotkeyService = FakeGlobalHotkeyService()
        let eventLogger = FakeDictationEventLogger()
        let recordingAction = FakeHotkeyRecordingAction(initialStatus: .idle)
        let coordinator = makeCoordinator(
            hotkeyService: hotkeyService,
            recordingAction: recordingAction,
            eventLogger: eventLogger
        )

        try coordinator.start()
        hotkeyService.trigger(.keyDown)
        await yieldUntil { recordingAction.status == .recording }
        hotkeyService.trigger(.outputIntentChanged(to: .translate))
        await yieldUntil {
            eventLogger.events.contains(.hotkeyEvent(action: .outputIntentChanged, intent: .translate))
        }
        hotkeyService.trigger(.keyUp)
        await yieldUntil { recordingAction.performCount == 2 }

        #expect(recordingAction.status == .success(transcript: "Hotkey transcript"))
        #expect(recordingAction.observedIntents == [.standard, .translate])
    }

    @Test func outputIntentChangeDuringInFlightStartPromotesDeferredStop() async throws {
        let gate = AsyncHotkeyGate()
        let hotkeyService = FakeGlobalHotkeyService()
        let eventLogger = FakeDictationEventLogger()
        let recordingAction = FakeHotkeyRecordingAction(
            initialStatus: .idle,
            beforeStatusChange: {
                await gate.wait()
            }
        )
        let coordinator = makeCoordinator(
            hotkeyService: hotkeyService,
            recordingAction: recordingAction,
            eventLogger: eventLogger
        )

        try coordinator.start()
        hotkeyService.trigger(.keyDown)
        await yieldUntil { recordingAction.performCount == 1 }

        hotkeyService.trigger(.outputIntentChanged(to: .translate))
        await yieldUntil {
            eventLogger.events.contains(.hotkeyEvent(action: .outputIntentChanged, intent: .translate))
        }
        hotkeyService.trigger(.keyUp)
        await yieldUntil { eventLogger.events.contains(.hotkeyStopDeferred) }

        #expect(recordingAction.performCount == 1)

        await gate.open()
        await yieldUntil { recordingAction.performCount == 2 }

        #expect(recordingAction.status == .success(transcript: "Hotkey transcript"))
        #expect(recordingAction.observedStatuses == [.idle, .recording])
        #expect(recordingAction.observedIntents == [.standard, .translate])
    }

    @Test func repeatedKeyDownWhilePressedDoesNotCreateParallelRecordingActions() async throws {
        let hotkeyService = FakeGlobalHotkeyService()
        let recordingAction = FakeHotkeyRecordingAction(initialStatus: .idle)
        let coordinator = makeCoordinator(
            hotkeyService: hotkeyService,
            recordingAction: recordingAction
        )

        try coordinator.start()
        hotkeyService.trigger(.keyDown)
        await yieldUntil { recordingAction.performCount == 1 }
        hotkeyService.trigger(.keyDown)
        await Task.yield()

        #expect(recordingAction.status == .recording)
        #expect(recordingAction.performCount == 1)
    }

    @Test func transcribingStateRejectsHotkeyStart() async throws {
        let hotkeyService = FakeGlobalHotkeyService()
        let recordingAction = FakeHotkeyRecordingAction(initialStatus: .transcribing)
        let coordinator = makeCoordinator(
            hotkeyService: hotkeyService,
            recordingAction: recordingAction
        )

        try coordinator.start()
        hotkeyService.trigger(.keyDown)
        await Task.yield()

        #expect(recordingAction.status == .transcribing)
        #expect(recordingAction.performCount == 0)
    }

    @Test func keyEventsWhileRecordingActionIsRunningAreIgnored() async throws {
        let gate = AsyncHotkeyGate()
        let hotkeyService = FakeGlobalHotkeyService()
        let recordingAction = FakeHotkeyRecordingAction(
            initialStatus: .idle,
            beforeStatusChange: {
                await gate.wait()
            }
        )
        let coordinator = makeCoordinator(
            hotkeyService: hotkeyService,
            recordingAction: recordingAction
        )

        try coordinator.start()
        hotkeyService.trigger(.keyDown)
        await yieldUntil { recordingAction.performCount == 1 }
        hotkeyService.trigger(.keyDown)
        await Task.yield()

        #expect(recordingAction.performCount == 1)

        await gate.open()
        await yieldUntil { recordingAction.status == .recording }

        #expect(recordingAction.performCount == 1)
    }

    @Test func keyUpDuringInFlightStartStopsRecordingAfterStartCompletes() async throws {
        let gate = AsyncHotkeyGate()
        let hotkeyService = FakeGlobalHotkeyService()
        let eventLogger = FakeDictationEventLogger()
        let recordingAction = FakeHotkeyRecordingAction(
            initialStatus: .idle,
            beforeStatusChange: {
                await gate.wait()
            }
        )
        let coordinator = makeCoordinator(
            hotkeyService: hotkeyService,
            recordingAction: recordingAction,
            eventLogger: eventLogger
        )

        try coordinator.start()
        let startTask = Task { @MainActor in
            await coordinator.handle(.keyDown())
        }
        await gate.waitUntilWaiterIsSuspended()

        #expect(recordingAction.performCount == 1)

        await coordinator.handle(.keyUp())

        #expect(eventLogger.events.contains(.hotkeyStopDeferred))
        #expect(recordingAction.performCount == 1)

        await gate.open()
        await startTask.value

        #expect(recordingAction.status == .success(transcript: "Hotkey transcript"))
        #expect(recordingAction.observedStatuses == [.idle, .recording])
        #expect(recordingAction.observedIntents == [.standard, .standard])
    }

    private func makeCoordinator(
        hotkeyService: FakeGlobalHotkeyService,
        recordingAction: FakeHotkeyRecordingAction,
        eventLogger: any DictationEventLogging = FakeDictationEventLogger()
    ) -> DictationHotkeyCoordinator {
        DictationHotkeyCoordinator(
            hotkeyService: hotkeyService,
            statusProvider: {
                recordingAction.status
            },
            performRecordingAction: { intent in
                await recordingAction.perform(intent: intent)
            },
            eventLogger: eventLogger
        )
    }

    private func yieldUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() {
                return
            }

            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private final class FakeDictationEventLogger: DictationEventLogging {
    private(set) var events: [DictationLogEvent] = []

    func record(_ event: DictationLogEvent) {
        events.append(event)
    }
}

@MainActor
private final class FakeHotkeyRecordingAction {
    private let beforeStatusChange: (() async -> Void)?

    private(set) var observedStatuses: [DictationStatus] = []
    private(set) var observedIntents: [DictationOutputIntent] = []
    private(set) var performCount = 0

    var status: DictationStatus

    init(
        initialStatus: DictationStatus,
        beforeStatusChange: (() async -> Void)? = nil
    ) {
        self.status = initialStatus
        self.beforeStatusChange = beforeStatusChange
    }

    func perform(intent: DictationOutputIntent) async {
        performCount += 1
        observedStatuses.append(status)
        observedIntents.append(intent)
        await beforeStatusChange?()

        switch status {
        case .idle, .success, .failure:
            status = .recording
        case .recording:
            status = .success(transcript: "Hotkey transcript")
        case .transcribing:
            break
        }
    }
}

private actor AsyncHotkeyGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var waiterObservationContinuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen {
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
            let observations = waiterObservationContinuations
            waiterObservationContinuations.removeAll()
            for observation in observations {
                observation.resume()
            }
        }
    }

    func waitUntilWaiterIsSuspended() async {
        if !continuations.isEmpty {
            return
        }

        await withCheckedContinuation { continuation in
            waiterObservationContinuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let waitingContinuations = continuations
        continuations.removeAll()

        for continuation in waitingContinuations {
            continuation.resume()
        }
    }
}
