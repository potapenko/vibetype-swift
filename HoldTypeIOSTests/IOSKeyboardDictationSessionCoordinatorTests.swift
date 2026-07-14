import Foundation
import Testing
import UIKit
@testable import HoldTypeIOS

@MainActor
struct IOSKeyboardDictationSessionCoordinatorTests {
    @Test
    func startFinishPublishesAcceptedResultOnce() async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        await coordinator.startSession()
        let requestID = try #require(harness.states.last?.requestID)

        harness.command = harness.command(.start, requestID: requestID)
        coordinator.receiveCurrentCommand()
        coordinator.receiveCurrentCommand()
        try await eventually { harness.workflow.runRequestIDs == [requestID] }

        harness.workflow.emit(.listening)
        harness.command = harness.command(.finish, requestID: requestID)
        coordinator.receiveCurrentCommand()
        harness.workflow.resolve(.accepted("Processed keyboard text"))
        try await eventually { coordinator.presentation == .resultReady }

        #expect(harness.workflow.finishRequestIDs == [requestID])
        #expect(harness.states.map(\.phase) == [
            .ready,
            .listening,
            .processing,
            .resultReady,
        ])
        #expect(harness.states.last?.result == "Processed keyboard text")
        #expect(harness.postCount == 4)
    }

    @Test
    func cancelStopsMatchingWorkflowWithoutResult() async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        await coordinator.startSession()
        let requestID = try #require(harness.states.last?.requestID)

        harness.command = harness.command(.start, requestID: requestID)
        coordinator.receiveCurrentCommand()
        try await eventually { harness.workflow.runRequestIDs == [requestID] }
        harness.workflow.emit(.listening)
        harness.command = harness.command(.cancel, requestID: requestID)
        coordinator.receiveCurrentCommand()
        harness.workflow.resolve(.cancelled)
        await Task.yield()

        #expect(harness.workflow.cancelRequestIDs == [requestID])
        #expect(harness.states.map(\.phase) == [
            .ready,
            .listening,
            .unavailable,
        ])
        #expect(harness.states.allSatisfy { $0.result == nil })
        #expect(coordinator.presentation == .stopped)
    }

    @Test
    func staleAndWrongRequestCommandsNeverReachWorkflow() async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        await coordinator.startSession()
        let requestID = try #require(harness.states.last?.requestID)

        harness.command = harness.command(
            .start,
            requestID: requestID,
            issuedAt: harness.now.addingTimeInterval(-6)
        )
        coordinator.receiveCurrentCommand()
        harness.command = harness.command(.start, requestID: UUID())
        coordinator.receiveCurrentCommand()
        await Task.yield()

        #expect(harness.workflow.runRequestIDs.isEmpty)
        #expect(harness.states.map(\.phase) == [.ready])
    }

    @Test
    func providerFailurePublishesFailureWithoutTransientResult() async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        await coordinator.startSession()
        let requestID = try #require(harness.states.last?.requestID)

        harness.command = harness.command(.start, requestID: requestID)
        coordinator.receiveCurrentCommand()
        try await eventually { harness.workflow.runRequestIDs == [requestID] }
        harness.workflow.emit(.listening)
        harness.command = harness.command(.finish, requestID: requestID)
        coordinator.receiveCurrentCommand()
        harness.workflow.resolve(.failed)
        try await eventually {
            coordinator.presentation == .failed("Try Again")
        }

        #expect(harness.states.last?.phase == .failed)
        #expect(harness.states.allSatisfy { $0.result == nil })
        #expect(harness.workflow.finishRequestIDs == [requestID])
    }
}

@MainActor
private final class KeyboardSessionHarness {
    let workflow = KeyboardWorkflowHarness()
    let sessionID = UUID()
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var command: HoldTypeIOS.KeyboardDictationCommandRecord?
    var states: [HoldTypeIOS.KeyboardDictationStateRecord] = []
    var postCount = 0

    func makeCoordinator() -> IOSKeyboardDictationSessionCoordinator {
        IOSKeyboardDictationSessionCoordinator(
            dependencies: IOSKeyboardDictationSessionDependencies(
                workflow: workflow.client,
                permission: IOSForegroundVoiceWorkflowPermissionClient(
                    read: { .granted },
                    requestIfUndetermined: { .granted }
                ),
                loadCommand: { [weak self] date in
                    guard let command = self?.command,
                          command.isValid(at: date) else {
                        return nil
                    }
                    return command
                },
                saveState: { [weak self] state in
                    self?.states.append(state)
                },
                postStateChanged: { [weak self] in self?.postCount += 1 },
                applicationIsActive: { true },
                beginBackgroundTask: { _ in .invalid },
                endBackgroundTask: { _ in },
                scheduleExpiry: { _, _ in nil },
                now: { [weak self] in self?.now ?? .distantPast },
                makeUUID: { [weak self] in self?.sessionID ?? UUID() }
            )
        )
    }

    func command(
        _ kind: HoldTypeIOS.KeyboardDictationCommandKind,
        requestID: UUID,
        issuedAt: Date? = nil
    ) -> HoldTypeIOS.KeyboardDictationCommandRecord {
        let issuedAt = issuedAt ?? now
        return HoldTypeIOS.KeyboardDictationCommandRecord(
            requestID: requestID,
            kind: kind,
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(5)
        )!
    }
}

@MainActor
private final class KeyboardWorkflowHarness {
    private var progress: IOSKeyboardDictationWorkflowClient.Progress?
    private var continuation:
        CheckedContinuation<IOSKeyboardDictationWorkflowResolution, Never>?
    private(set) var runRequestIDs: [UUID] = []
    private(set) var finishRequestIDs: [UUID] = []
    private(set) var cancelRequestIDs: [UUID] = []

    var client: IOSKeyboardDictationWorkflowClient {
        IOSKeyboardDictationWorkflowClient(
            run: { [weak self] requestID, progress in
                guard let self else { return .failed }
                return await self.run(requestID, progress: progress)
            },
            finish: { [weak self] requestID in
                self?.finishRequestIDs.append(requestID)
                return self?.runRequestIDs.last == requestID
            },
            cancel: { [weak self] requestID in
                self?.cancelRequestIDs.append(requestID)
                return self?.runRequestIDs.last == requestID
            }
        )
    }

    func emit(_ value: IOSKeyboardDictationWorkflowProgress) {
        progress?(value)
    }

    func resolve(_ value: IOSKeyboardDictationWorkflowResolution) {
        continuation?.resume(returning: value)
        continuation = nil
        progress = nil
    }

    private func run(
        _ requestID: UUID,
        progress: @escaping IOSKeyboardDictationWorkflowClient.Progress
    ) async -> IOSKeyboardDictationWorkflowResolution {
        runRequestIDs.append(requestID)
        self.progress = progress
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}

@MainActor
private func eventually(
    _ predicate: @escaping @MainActor () -> Bool
) async throws {
    for _ in 0..<100 {
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Condition did not become true")
}
