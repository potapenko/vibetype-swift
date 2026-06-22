//
//  DictationHotkeyCoordinatorTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/22/26.
//

import Testing
@testable import vibetype

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

    private func makeCoordinator(
        hotkeyService: FakeGlobalHotkeyService,
        recordingAction: FakeHotkeyRecordingAction
    ) -> DictationHotkeyCoordinator {
        DictationHotkeyCoordinator(
            hotkeyService: hotkeyService,
            statusProvider: {
                recordingAction.status
            },
            performRecordingAction: {
                await recordingAction.perform()
            }
        )
    }

    private func yieldUntil(_ condition: () -> Bool) async {
        for _ in 0..<40 {
            if condition() {
                return
            }

            await Task.yield()
        }
    }
}

@MainActor
private final class FakeHotkeyRecordingAction {
    private let beforeStatusChange: (() async -> Void)?

    private(set) var observedStatuses: [DictationStatus] = []
    private(set) var performCount = 0

    var status: DictationStatus

    init(
        initialStatus: DictationStatus,
        beforeStatusChange: (() async -> Void)? = nil
    ) {
        self.status = initialStatus
        self.beforeStatusChange = beforeStatusChange
    }

    func perform() async {
        performCount += 1
        observedStatuses.append(status)
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

    func wait() async {
        if isOpen {
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
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
