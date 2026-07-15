import Foundation
import Testing
import UIKit
@testable import HoldTypeIOS

@MainActor
struct IOSKeyboardDictationSessionCoordinatorTests {
    @Test
    func freshHandoffStartsOneAttemptAndSheetTracksRecorder() async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        let owner = IOSKeyboardHandoffPresentationOwner(session: coordinator)
        let intent = harness.intent(action: .translateAndImprove)

        await owner.start(intent)

        #expect(owner.presentation?.phase == .starting)
        try await eventually {
            harness.workflow.runRequestIDs == [harness.sessionID]
        }
        #expect(harness.workflow.runActions == [.translateAndImprove])
        #expect(harness.states.map(\.phase) == [.ready])

        harness.workflow.emit(.listening)
        try await eventually {
            owner.presentation?.phase == .listening
        }

        #expect(harness.states.map(\.phase) == [.ready, .listening])
        #expect(harness.workflow.runRequestIDs == [harness.sessionID])
        #expect(harness.states.last?.requestID == intent.requestID)

        harness.workflow.emit(.processing)
        try await eventually { owner.presentation == nil }
        #expect(harness.states.map(\.phase) == [
            .ready,
            .listening,
            .processing,
        ])

        harness.workflow.resolve(.accepted("Accepted handoff"))
        try await eventually { coordinator.presentation == .resultReady }
    }

    @Test
    func handoffCloseWaitsForSharedCaptureCancellation() async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        let owner = IOSKeyboardHandoffPresentationOwner(session: coordinator)
        let intent = harness.intent()
        await owner.start(intent)
        try await eventually {
            harness.workflow.runRequestIDs == [harness.sessionID]
        }
        harness.workflow.emit(.listening)
        try await eventually {
            owner.presentation?.phase == .listening
        }

        let cancellation = Task { @MainActor in
            await owner.cancelActiveHandoff()
        }
        try await eventually {
            harness.workflow.cancelRequestIDs == [harness.sessionID]
        }
        #expect(owner.presentation?.phase == .listening)

        harness.workflow.resolve(.cancelled)
        await cancellation.value

        #expect(owner.presentation == nil)
        #expect(coordinator.presentation == .stopped)
        #expect(harness.states.map(\.phase) == [
            .ready,
            .listening,
            .unavailable,
        ])
    }

    @Test
    func failedAndExpiredHandoffsDismissTheSheet() async throws {
        let failedHarness = KeyboardSessionHarness()
        let failedCoordinator = failedHarness.makeCoordinator()
        let failedOwner = IOSKeyboardHandoffPresentationOwner(
            session: failedCoordinator
        )
        let failedIntent = failedHarness.intent()
        await failedOwner.start(failedIntent)
        try await eventually {
            failedHarness.workflow.runRequestIDs == [failedHarness.sessionID]
        }
        failedHarness.workflow.resolve(.failed)
        try await eventually { failedOwner.presentation == nil }
        #expect(failedHarness.states.map(\.phase) == [.ready, .failed])

        let expiredHarness = KeyboardSessionHarness()
        let expiredCoordinator = expiredHarness.makeCoordinator()
        let expiredOwner = IOSKeyboardHandoffPresentationOwner(
            session: expiredCoordinator
        )
        let expiredIntent = expiredHarness.intent()
        await expiredOwner.start(expiredIntent)
        try await eventually {
            expiredHarness.workflow.runRequestIDs == [expiredHarness.sessionID]
        }
        expiredHarness.workflow.emit(.listening)
        try await eventually {
            expiredOwner.presentation?.phase == .listening
        }

        expiredHarness.expireSession()

        #expect(expiredOwner.presentation == nil)
        #expect(expiredCoordinator.presentation == .stopped)
        #expect(expiredHarness.states.map(\.phase) == [
            .ready,
            .listening,
            .unavailable,
        ])
        expiredHarness.workflow.resolve(.cancelled)
    }

    @Test
    func staleHandoffNeverStartsSessionOrSheet() async {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        let owner = IOSKeyboardHandoffPresentationOwner(session: coordinator)
        let intent = harness.intent(
            issuedAt: harness.now.addingTimeInterval(-10),
            expiresAt: harness.now
        )

        await owner.start(intent)

        #expect(owner.presentation == nil)
        #expect(harness.workflow.runRequestIDs.isEmpty)
        #expect(harness.states.isEmpty)
    }

    @Test
    func newerHandoffSupersedesArmingWorkWithoutDuplicateCapture() async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        let owner = IOSKeyboardHandoffPresentationOwner(session: coordinator)
        let first = harness.intent()
        await owner.start(first)
        try await eventually {
            harness.workflow.runRequestIDs == [harness.sessionID]
        }

        let second = harness.intent(requestID: UUID(), action: .improve)
        let replacement = Task { @MainActor in
            await owner.start(second)
        }
        try await eventually {
            harness.workflow.cancelRequestIDs == [harness.sessionID]
        }
        harness.workflow.resolve(.cancelled)
        await replacement.value
        try await eventually {
            harness.workflow.runRequestIDs == [
                harness.sessionID,
                harness.sessionID,
            ]
        }

        #expect(owner.presentation?.phase == .starting)
        #expect(harness.workflow.runActions == [.standard, .improve])
        harness.workflow.resolve(.cancelled)
        try await eventually { owner.presentation == nil }
    }

    @Test
    func closeDuringArmingInvalidatesLatePreparation() async throws {
        let harness = KeyboardSessionHarness()
        harness.workflow.suspendsTranslationAvailability = true
        let coordinator = harness.makeCoordinator()
        let owner = IOSKeyboardHandoffPresentationOwner(session: coordinator)
        let intent = harness.intent()

        let start = Task { @MainActor in
            await owner.start(intent)
        }
        try await eventually {
            harness.workflow.translationAvailabilityLoadCount == 1
        }
        #expect(owner.presentation?.phase == .starting)

        await owner.cancelActiveHandoff()
        harness.workflow.releaseTranslationAvailability()
        await start.value

        #expect(owner.presentation == nil)
        #expect(harness.workflow.runRequestIDs.isEmpty)
        #expect(harness.states.map(\.phase) == [.unavailable])
        #expect(coordinator.presentation == .stopped)
    }

    @Test
    func startFinishPublishesAcceptedResultOnce() async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        await coordinator.startSession()
        let requestID = UUID()

        harness.command = harness.command(
            .start,
            requestID: requestID,
            action: .translateAndImprove
        )
        coordinator.receiveCurrentCommand()
        coordinator.receiveCurrentCommand()
        try await eventually { harness.workflow.runRequestIDs == [requestID] }

        harness.workflow.emit(.listening)
        harness.command = harness.command(.finish, requestID: requestID)
        coordinator.receiveCurrentCommand()
        harness.workflow.resolve(.accepted("Processed keyboard text"))
        try await eventually { coordinator.presentation == .resultReady }

        #expect(harness.workflow.finishRequestIDs == [requestID])
        #expect(harness.workflow.runActions == [.translateAndImprove])
        #expect(harness.states.map(\.phase) == [
            .ready,
            .listening,
            .processing,
            .resultReady,
        ])
        #expect(harness.states.last?.result == "Processed keyboard text")
        #expect(harness.states.allSatisfy { $0.translationAvailable })
        #expect(harness.postCount == 4)
    }

    @Test
    func cancelStopsMatchingWorkflowWithoutResult() async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        await coordinator.startSession()
        let requestID = UUID()

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
        let requestID = UUID()

        harness.command = harness.command(
            .start,
            requestID: requestID,
            issuedAt: harness.now.addingTimeInterval(-6)
        )
        coordinator.receiveCurrentCommand()
        harness.command = harness.command(
            .start,
            requestID: UUID(),
            sessionID: UUID()
        )
        coordinator.receiveCurrentCommand()
        await Task.yield()

        #expect(harness.workflow.runRequestIDs.isEmpty)
        #expect(harness.states.map(\.phase) == [.ready])
    }

    @Test
    func unavailableTranslationStartDoesNotClaimTheWarmSession() async throws {
        let harness = KeyboardSessionHarness()
        harness.workflow.translationAvailable = false
        let coordinator = harness.makeCoordinator()
        await coordinator.startSession()

        harness.command = harness.command(
            .start,
            requestID: UUID(),
            action: .translate
        )
        coordinator.receiveCurrentCommand()
        await Task.yield()

        let standardRequestID = UUID()
        harness.command = harness.command(
            .start,
            requestID: standardRequestID
        )
        coordinator.receiveCurrentCommand()
        try await eventually {
            harness.workflow.runRequestIDs == [standardRequestID]
        }

        #expect(harness.states.map(\.phase) == [.ready])
        harness.workflow.resolve(.cancelled)
    }

    @Test
    func providerFailurePublishesFailureWithoutTransientResult() async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        await coordinator.startSession()
        let requestID = UUID()

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

    @Test
    func deliveryClaimIsExclusiveAndAcknowledgementReusesWarmSession()
        async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        await coordinator.startSession()
        let requestID = UUID()

        harness.command = harness.command(.start, requestID: requestID)
        coordinator.receiveCurrentCommand()
        try await eventually { harness.workflow.runRequestIDs == [requestID] }
        harness.workflow.emit(.listening)
        harness.command = harness.command(.finish, requestID: requestID)
        coordinator.receiveCurrentCommand()
        harness.workflow.resolve(.accepted("Exactly once"))
        try await eventually { coordinator.presentation == .resultReady }

        let claimID = UUID()
        harness.command = harness.command(
            .claimDelivery,
            requestID: requestID,
            deliveryClaimID: claimID
        )
        coordinator.receiveCurrentCommand()
        #expect(harness.states.last?.deliveryClaimID == claimID)
        #expect(harness.states.last?.result == "Exactly once")

        let stateCountAfterClaim = harness.states.count
        harness.command = harness.command(
            .claimDelivery,
            requestID: requestID,
            deliveryClaimID: UUID()
        )
        coordinator.receiveCurrentCommand()
        #expect(harness.states.count == stateCountAfterClaim)

        harness.command = harness.command(
            .acknowledgeDelivery,
            requestID: requestID,
            deliveryClaimID: claimID
        )
        coordinator.receiveCurrentCommand()

        #expect(harness.states.last?.phase == .ready)
        #expect(harness.states.last?.hasActiveAttempt == false)
        #expect(harness.states.last?.result == nil)
        #expect(coordinator.presentation == .ready(harness.sessionDeadline))

        let nextRequestID = UUID()
        harness.command = harness.command(.start, requestID: nextRequestID)
        coordinator.receiveCurrentCommand()
        try await eventually {
            harness.workflow.runRequestIDs == [requestID, nextRequestID]
        }
        harness.workflow.resolve(.cancelled)
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
    var expiryAction: (@MainActor () -> Void)?

    var sessionDeadline: Date {
        now.addingTimeInterval(
            KeyboardDictationBridgeConfiguration.sessionLifetime
        )
    }

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
                scheduleExpiry: { [weak self] _, action in
                    self?.expiryAction = action
                    return nil
                },
                now: { [weak self] in self?.now ?? .distantPast },
                makeUUID: { [weak self] in self?.sessionID ?? UUID() }
            )
        )
    }

    func command(
        _ kind: HoldTypeIOS.KeyboardDictationCommandKind,
        requestID: UUID,
        action: HoldTypeIOS.KeyboardVoiceAction = .standard,
        deliveryClaimID: UUID? = nil,
        issuedAt: Date? = nil,
        sessionID: UUID? = nil
    ) -> HoldTypeIOS.KeyboardDictationCommandRecord {
        let issuedAt = issuedAt ?? now
        return HoldTypeIOS.KeyboardDictationCommandRecord(
            sessionID: sessionID ?? self.sessionID,
            attemptID: requestID,
            requestID: requestID,
            sourceDocumentID: nil,
            deliveryClaimID: deliveryClaimID,
            kind: kind,
            action: action,
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(5)
        )!
    }

    func intent(
        requestID: UUID = UUID(),
        action: HoldTypeIOS.KeyboardVoiceAction = .standard,
        issuedAt: Date? = nil,
        expiresAt: Date? = nil
    ) -> HoldTypeIOS.KeyboardHandoffIntentRecord {
        let issuedAt = issuedAt ?? now
        return HoldTypeIOS.KeyboardHandoffIntentRecord(
            requestID: requestID,
            sourceDocumentID: UUID(),
            action: action,
            issuedAt: issuedAt,
            expiresAt: expiresAt
                ?? issuedAt.addingTimeInterval(
                    KeyboardHandoffIntentConfiguration.lifetime
                )
        )!
    }

    func expireSession() {
        expiryAction?()
    }
}

@MainActor
private final class KeyboardWorkflowHarness {
    private var progress: IOSKeyboardDictationWorkflowClient.Progress?
    private var continuation:
        CheckedContinuation<IOSKeyboardDictationWorkflowResolution, Never>?
    private(set) var runRequestIDs: [UUID] = []
    private(set) var runActions: [HoldTypeIOS.KeyboardVoiceAction] = []
    private(set) var finishRequestIDs: [UUID] = []
    private(set) var cancelRequestIDs: [UUID] = []
    var translationAvailable = true
    var suspendsTranslationAvailability = false
    private(set) var translationAvailabilityLoadCount = 0
    private var translationAvailabilityContinuation:
        CheckedContinuation<Bool, Never>?

    var client: IOSKeyboardDictationWorkflowClient {
        IOSKeyboardDictationWorkflowClient(
            run: { [weak self] requestID, action, progress in
                guard let self else { return .failed }
                return await self.run(
                    requestID,
                    action: action,
                    progress: progress
                )
            },
            finish: { [weak self] requestID in
                self?.finishRequestIDs.append(requestID)
                return self?.runRequestIDs.last == requestID
            },
            cancel: { [weak self] requestID in
                self?.cancelRequestIDs.append(requestID)
                return self?.runRequestIDs.last == requestID
            },
            loadTranslationAvailability: { [weak self] in
                await self?.loadTranslationAvailability() ?? false
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

    func releaseTranslationAvailability(_ value: Bool = true) {
        translationAvailabilityContinuation?.resume(returning: value)
        translationAvailabilityContinuation = nil
    }

    private func loadTranslationAvailability() async -> Bool {
        translationAvailabilityLoadCount += 1
        guard suspendsTranslationAvailability else {
            return translationAvailable
        }
        return await withCheckedContinuation { continuation in
            translationAvailabilityContinuation = continuation
        }
    }

    private func run(
        _ requestID: UUID,
        action: HoldTypeIOS.KeyboardVoiceAction,
        progress: @escaping IOSKeyboardDictationWorkflowClient.Progress
    ) async -> IOSKeyboardDictationWorkflowResolution {
        runRequestIDs.append(requestID)
        runActions.append(action)
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
