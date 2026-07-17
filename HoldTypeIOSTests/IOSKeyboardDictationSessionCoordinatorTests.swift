import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypePersistence
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

        harness.workflow.emit(.listening(.defaultValue))
        try await eventually {
            owner.presentation?.phase == .listening
        }

        #expect(harness.states.map(\.phase) == [.ready, .listening])
        #expect(harness.workflow.runRequestIDs == [harness.sessionID])
        #expect(harness.states.last?.requestID == intent.requestID)

        harness.workflow.emit(.processing)
        try await eventually {
            owner.presentation?.phase == .processing
        }
        #expect(harness.states.map(\.phase) == [
            .ready,
            .listening,
            .processing,
        ])

        harness.workflow.resolve(.accepted("Accepted handoff"))
        try await eventually { coordinator.presentation == .resultReady }
        #expect(owner.presentation == nil)
    }

    @Test
    func handoffClosePreservesCaptureAfterRecorderStarts() async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        let owner = IOSKeyboardHandoffPresentationOwner(session: coordinator)
        let intent = harness.intent()
        await owner.start(intent)
        try await eventually {
            harness.workflow.runRequestIDs == [harness.sessionID]
        }
        harness.workflow.emit(.listening(.defaultValue))
        try await eventually {
            owner.presentation?.phase == .listening
        }

        let cancellation = Task { @MainActor in
            await owner.cancelActiveHandoff()
        }
        try await eventually {
            harness.workflow.interruptRequestIDs == [harness.sessionID]
        }
        #expect(owner.presentation?.phase == .listening)

        harness.workflow.resolve(.failed)
        await cancellation.value

        #expect(owner.presentation == nil)
        #expect(coordinator.presentation == .failed("Try Again"))
        #expect(harness.states.map(\.phase) == [
            .ready,
            .listening,
            .failed,
        ])
        #expect(harness.workflow.cancelRequestIDs.isEmpty)
    }

    @Test
    func failedHandoffDismissesButIdleExpiryCannotCancelActiveAttempt()
        async throws {
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
        expiredHarness.workflow.emit(.listening(.defaultValue))
        try await eventually {
            expiredOwner.presentation?.phase == .listening
        }

        expiredHarness.expireSession()

        #expect(expiredOwner.presentation?.phase == .listening)
        #expect(expiredCoordinator.presentation == .listening(
            expiredHarness.listeningDeadline
        ))
        #expect(expiredHarness.states.map(\.phase) == [
            .ready,
            .listening,
        ])
        #expect(expiredHarness.workflow.cancelRequestIDs.isEmpty)

        expiredHarness.workflow.emit(.processing)
        try await eventually {
            expiredOwner.presentation?.phase == .processing
        }
        expiredHarness.expireSession()
        #expect(expiredOwner.presentation?.phase == .processing)
        #expect(expiredCoordinator.presentation == .processing)
        #expect(expiredHarness.workflow.cancelRequestIDs.isEmpty)

        expiredHarness.workflow.resolve(.accepted("Preserved result"))
        try await eventually { expiredOwner.presentation == nil }
        #expect(expiredCoordinator.presentation == .resultReady)
    }

    @Test
    func idleWarmSessionStillExpiresAfterSixtySeconds() async {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()

        await coordinator.startSession()
        harness.expireSession()

        #expect(coordinator.presentation == .stopped)
        #expect(harness.states.map(\.phase) == [.ready, .unavailable])
        #expect(harness.workflow.endWarmSessionCount == 1)
    }

    @Test
    func staleDirectStartNeverStartsSessionOrReportsSheetFailure() async {
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
    func blockedPreflightStaysInsideSheetAndNeverStartsWorkflow() async {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        let owner = IOSKeyboardHandoffPresentationOwner(
            session: coordinator,
            preflight: IOSKeyboardHandoffPreflightClient { _ in
                .blocked(.openAICredential)
            }
        )

        await owner.start(harness.intent())

        #expect(owner.presentation?.phase == .blocked)
        #expect(owner.presentation?.issue == .openAICredential)
        #expect(harness.workflow.runRequestIDs.isEmpty)
        #expect(harness.states.isEmpty)

        owner.cancelFromSheet()
        try? await Task.sleep(for: .milliseconds(10))
        #expect(owner.presentation == nil)
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
            harness.workflow.interruptRequestIDs == [harness.sessionID]
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
    func coordinatorRejectsFreshHandoffWhileListeningWithoutRetiringAudio()
        async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        let first = harness.intent()

        let firstStarted = await coordinator.startHandoff(first) { _, _ in }
        #expect(firstStarted)
        try await eventually {
            harness.workflow.runRequestIDs == [harness.sessionID]
        }
        harness.workflow.emit(.listening(.defaultValue))
        try await eventually {
            coordinator.presentation == .listening(
                harness.listeningDeadline
            )
        }

        let second = harness.intent(requestID: UUID())
        let secondStarted = await coordinator.startHandoff(second) { _, _ in }

        #expect(!secondStarted)
        #expect(harness.workflow.cancelRequestIDs.isEmpty)
        #expect(harness.retiredAttemptIDs.isEmpty)
        #expect(harness.workflow.runRequestIDs == [harness.sessionID])
        #expect(harness.states.map(\.phase) == [.ready, .listening])
        #expect(harness.states.last?.requestID == first.requestID)
        #expect(coordinator.presentation == .listening(
            harness.listeningDeadline
        ))

        harness.workflow.resolve(.cancelled)
    }

    @Test
    func retainedCaptureBlocksSupersessionBeforeListeningPublication()
        async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        let first = harness.intent()

        #expect(await coordinator.startHandoff(first) { _, _ in })
        try await eventually {
            harness.workflow.runRequestIDs == [harness.sessionID]
        }
        harness.workflow.retainedCaptureRequestIDs.insert(harness.sessionID)

        let secondStarted = await coordinator.startHandoff(
            harness.intent(requestID: UUID())
        ) { _, _ in }

        #expect(!secondStarted)
        #expect(harness.workflow.interruptRequestIDs.isEmpty)
        #expect(harness.workflow.cancelRequestIDs.isEmpty)
        #expect(harness.retiredAttemptIDs.isEmpty)
        #expect(harness.workflow.runRequestIDs == [harness.sessionID])

        harness.workflow.resolve(.failed)
    }

    @Test
    func listeningStatePublicationFailureDoesNotStopRetainedWorkflow()
        async throws {
        let harness = KeyboardSessionHarness()
        harness.failingStatePhases = [.listening]
        let coordinator = harness.makeCoordinator()

        #expect(await coordinator.startHandoff(harness.intent()) { _, _ in })
        try await eventually {
            harness.workflow.runRequestIDs == [harness.sessionID]
        }
        harness.workflow.emit(.listening(.defaultValue))
        try await eventually {
            coordinator.presentation == .listening(harness.listeningDeadline)
        }
        #expect(harness.workflow.interruptRequestIDs.isEmpty)
        #expect(harness.workflow.cancelRequestIDs.isEmpty)

        harness.workflow.resolve(.accepted("Survived publication failure"))
        try await eventually {
            coordinator.presentation == .resultReady
        }

        #expect(harness.states.map(\.phase) == [.ready, .resultReady])
        #expect(harness.states.last?.result == "Survived publication failure")
    }

    @Test
    func microphoneTapInAnotherHostRevealsExistingListeningCapture()
        async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        let owner = IOSKeyboardHandoffPresentationOwner(
            session: coordinator,
            preflight: IOSKeyboardHandoffPreflightClient {
                [weak harness] intent in
                harness?.preflightRequestIDs.append(intent.requestID)
                return .ready
            }
        )
        let firstDocumentID = UUID()
        let secondDocumentID = UUID()
        let first = harness.intent(sourceDocumentID: firstDocumentID)

        await owner.start(first)
        try await eventually {
            harness.workflow.runRequestIDs == [harness.sessionID]
        }
        harness.workflow.emit(.listening(.defaultValue))
        try await eventually { owner.presentation?.phase == .listening }

        let second = harness.intent(
            requestID: UUID(),
            sourceDocumentID: secondDocumentID
        )
        await owner.start(second)

        #expect(owner.presentation?.phase == .listening)
        #expect(coordinator.presentation == .listening(
            harness.listeningDeadline
        ))
        #expect(harness.workflow.cancelRequestIDs.isEmpty)
        #expect(harness.retiredAttemptIDs.isEmpty)
        #expect(harness.workflow.runRequestIDs == [harness.sessionID])
        #expect(harness.preflightRequestIDs == [first.requestID])
        #expect(harness.states.last?.requestID == first.requestID)
        #expect(harness.states.last?.sourceDocumentID == firstDocumentID)
        #expect(harness.states.last?.sourceDocumentID != secondDocumentID)

        harness.workflow.resolve(.cancelled)
        try await eventually { owner.presentation == nil }
    }

    @Test
    func failedPendingStaysInSheetAndFreshTapStartsNoSecondCapture()
        async throws {
        let harness = KeyboardSessionHarness()
        let pending = KeyboardPendingRecordingHarness()
        let coordinator = harness.makeCoordinator()
        let owner = IOSKeyboardHandoffPresentationOwner(
            session: coordinator,
            pendingRecordingOwner: pending.owner
        )
        let first = harness.intent()

        await owner.start(first)
        try await eventually {
            harness.workflow.runRequestIDs == [harness.sessionID]
        }
        _ = try #require(harness.states.last?.attemptID)
        pending.observation = try keyboardPendingObservation(phase: .failed)
        harness.workflow.resolve(.failed)
        try await eventually {
            owner.presentation?.phase == .savedRecording
        }

        let second = harness.intent(requestID: UUID())
        await owner.start(second)

        #expect(harness.retiredAttemptIDs.isEmpty)
        #expect(owner.presentation?.phase == .savedRecording)
        #expect(harness.workflow.runRequestIDs == [harness.sessionID])
        #expect(pending.loadCount >= 2)

        owner.cancelFromSheet()
        try await eventually { owner.presentation == nil }
        #expect(pending.observation != nil)
        try await eventually { pending.stopCount == 1 }
    }

    @Test
    func failedCompletedCaptureStaysInSheetWithoutPendingPromotion()
        async throws {
        let harness = KeyboardSessionHarness()
        let saved = KeyboardPendingRecordingHarness()
        saved.completedCapture = try IOSV1CompletedCaptureRecoveryObservation
            .qualificationFixture(
                durationMilliseconds: 30_000,
                byteCount: 4_096
            )
        let coordinator = harness.makeCoordinator()
        let owner = IOSKeyboardHandoffPresentationOwner(
            session: coordinator,
            pendingRecordingOwner: saved.owner
        )

        await owner.start(harness.intent())
        try await eventually {
            owner.presentation?.phase == .savedRecording
        }

        #expect(harness.workflow.runRequestIDs.isEmpty)
        #expect(saved.owner.card?.status == .ready)
        #expect(saved.owner.card?.isPlayable == true)
    }

    @Test
    func freshHandoffCannotSupersedeProcessingAttempt() async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        let owner = IOSKeyboardHandoffPresentationOwner(
            session: coordinator,
            waitBeforeStartRetry: {}
        )
        await owner.start(harness.intent())
        try await eventually {
            harness.workflow.runRequestIDs == [harness.sessionID]
        }
        harness.workflow.emit(.processing)
        try await eventually { owner.presentation?.phase == .processing }

        await owner.start(harness.intent(requestID: UUID()))

        #expect(harness.workflow.cancelRequestIDs.isEmpty)
        #expect(harness.retiredAttemptIDs.isEmpty)
        #expect(harness.workflow.runRequestIDs == [harness.sessionID])
        harness.workflow.resolve(.accepted("Preserved processing result"))
    }

    @Test
    func freshHandoffWithExistingPendingOpensRecoveryWithoutPreflightOrCapture()
        async throws {
        let harness = KeyboardSessionHarness()
        let pending = KeyboardPendingRecordingHarness()
        pending.observation = try keyboardPendingObservation(
            phase: .readyForTranscription
        )
        let coordinator = harness.makeCoordinator()
        let owner = IOSKeyboardHandoffPresentationOwner(
            session: coordinator,
            pendingRecordingOwner: pending.owner,
            waitBeforeStartRetry: {}
        )

        await owner.start(harness.intent())

        #expect(owner.presentation?.phase == .savedRecording)
        #expect(harness.workflow.runRequestIDs.isEmpty)
        #expect(harness.states.isEmpty)
        #expect(harness.retiredAttemptIDs.isEmpty)
        #expect(pending.loadCount == 1)
    }

    @Test
    func unconfirmedSavedRecordingLoadBlocksAdmissionUntilAbsenceIsConfirmed()
        async {
        let harness = KeyboardSessionHarness()
        let pending = KeyboardPendingRecordingHarness()
        pending.loadFails = true
        let coordinator = harness.makeCoordinator()
        let owner = IOSKeyboardHandoffPresentationOwner(
            session: coordinator,
            preflight: IOSKeyboardHandoffPreflightClient {
                [weak harness] intent in
                harness?.preflightRequestIDs.append(intent.requestID)
                return .ready
            },
            pendingRecordingOwner: pending.owner
        )

        await owner.start(harness.intent())

        #expect(owner.presentation?.phase == .savedRecording)
        #expect(pending.owner.state == .loadFailed(lastConfirmed: nil))
        #expect(pending.owner.shouldPresentSavedRecording)
        #expect(!pending.owner.isConfirmedAbsent)
        #expect(harness.preflightRequestIDs.isEmpty)
        #expect(harness.workflow.runRequestIDs.isEmpty)

        owner.savedRecordingDidResolve()
        #expect(owner.presentation?.phase == .savedRecording)

        pending.loadFails = false
        #expect(await pending.owner.refresh())
        owner.savedRecordingDidResolve()
        #expect(owner.presentation == nil)
    }

    @Test
    func unconfirmedLoadAfterSupersessionRetryKeepsRecoverySheetVisible()
        async throws {
        let harness = KeyboardSessionHarness()
        let pending = KeyboardPendingRecordingHarness()
        pending.failLoadAtOrAfter = 2
        let coordinator = harness.makeCoordinator()
        let original = harness.intent()
        let originalStarted = await coordinator.startHandoff(original) {
            _, _ in
        }
        #expect(originalStarted)
        try await eventually {
            harness.workflow.runRequestIDs == [harness.sessionID]
        }
        harness.supersessionResults = [false]

        let owner = IOSKeyboardHandoffPresentationOwner(
            session: coordinator,
            pendingRecordingOwner: pending.owner,
            waitBeforeStartRetry: {}
        )
        let replacement = Task { @MainActor in
            await owner.start(harness.intent(requestID: UUID()))
        }
        try await eventually {
            harness.workflow.interruptRequestIDs == [harness.sessionID]
        }
        harness.workflow.resolve(.cancelled)
        await replacement.value

        #expect(owner.presentation?.phase == .savedRecording)
        #expect(pending.owner.state == .loadFailed(lastConfirmed: nil))
        #expect(!pending.owner.isConfirmedAbsent)
        #expect(harness.retiredAttemptIDs == [harness.sessionID])
        #expect(harness.workflow.runRequestIDs == [harness.sessionID])

        owner.savedRecordingDidResolve()
        #expect(owner.presentation?.phase == .savedRecording)
    }

    @Test
    func freshHandoffWaitsForAnOlderSheetCloseWithoutBeingCleared()
        async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        let owner = IOSKeyboardHandoffPresentationOwner(session: coordinator)
        await owner.start(harness.intent())
        try await eventually {
            harness.workflow.runRequestIDs == [harness.sessionID]
        }
        harness.workflow.emit(.listening(.defaultValue))
        try await eventually { owner.presentation?.phase == .listening }

        owner.cancelFromSheet()
        try await eventually {
            harness.workflow.interruptRequestIDs == [harness.sessionID]
        }

        let replacement = Task { @MainActor in
            await owner.start(harness.intent(requestID: UUID()))
        }
        await Task.yield()
        #expect(owner.presentation?.phase == .starting)

        harness.workflow.resolve(.cancelled)
        await replacement.value
        try await eventually {
            harness.workflow.runRequestIDs == [
                harness.sessionID,
                harness.sessionID,
            ]
        }
        #expect(owner.presentation?.phase == .starting)

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
    func listeningStateUsesTheFrozenOneOrFifteenMinuteLimit() async throws {
        for (minutes, expectedLifetime) in [(1, 62.0), (15, 902.0)] {
            let harness = KeyboardSessionHarness()
            let coordinator = harness.makeCoordinator()
            await coordinator.startSession()
            let requestID = UUID()

            harness.command = harness.command(.start, requestID: requestID)
            coordinator.receiveCurrentCommand()
            try await eventually {
                harness.workflow.runRequestIDs == [requestID]
            }

            let limit = RecordingDurationLimit(minutes: minutes)
            harness.workflow.emit(.listening(limit))
            try await eventually {
                harness.states.last?.phase == .listening
            }

            let expectedDeadline = harness.now.addingTimeInterval(
                expectedLifetime
            )
            #expect(harness.states.last?.expiresAt == expectedDeadline)
            #expect(coordinator.presentation == .listening(expectedDeadline))

            harness.workflow.resolve(.cancelled)
            try await eventually { coordinator.presentation == .stopped }
        }
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

        harness.workflow.emit(.listening(.defaultValue))
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
        harness.workflow.emit(.listening(.defaultValue))
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
        harness.workflow.emit(.listening(.defaultValue))
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
    func finishStatePublicationFailureDoesNotCancelProviderAuthority()
        async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        await coordinator.startSession()
        let requestID = UUID()

        harness.command = harness.command(.start, requestID: requestID)
        coordinator.receiveCurrentCommand()
        try await eventually { harness.workflow.runRequestIDs == [requestID] }
        harness.workflow.emit(.listening(.defaultValue))
        harness.failingStatePhases = [.processing]
        harness.command = harness.command(.finish, requestID: requestID)
        coordinator.receiveCurrentCommand()

        #expect(coordinator.presentation == .processing)
        #expect(harness.workflow.finishRequestIDs == [requestID])
        #expect(harness.workflow.interruptRequestIDs.isEmpty)
        #expect(harness.workflow.cancelRequestIDs.isEmpty)

        harness.workflow.resolve(.accepted("Accepted despite projection"))
        try await eventually { coordinator.presentation == .resultReady }
        #expect(harness.states.map(\.phase) == [
            .ready,
            .listening,
            .resultReady,
        ])
    }

    @Test
    func stopSessionDuringListeningPreservesInsteadOfCancelling() async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        await coordinator.startSession()
        let requestID = UUID()

        harness.command = harness.command(.start, requestID: requestID)
        coordinator.receiveCurrentCommand()
        try await eventually { harness.workflow.runRequestIDs == [requestID] }
        harness.workflow.emit(.listening(.defaultValue))
        try await eventually {
            coordinator.presentation == .listening(harness.listeningDeadline)
        }

        coordinator.stopSession()

        #expect(harness.workflow.stopSessionRequestIDs == [requestID])
        #expect(harness.workflow.cancelRequestIDs.isEmpty)
        #expect(coordinator.presentation == .listening(
            harness.listeningDeadline
        ))

        harness.workflow.resolve(.interruptedSaved)
        try await eventually {
            coordinator.presentation == .failed(
                "Recording interrupted — saved to History"
            )
        }
        #expect(harness.states.last?.phase == .failed)
    }

    @Test
    func ambiguousTranscriptionShowsSavedNoticeWithoutTryAgain() async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        await coordinator.startSession()
        let requestID = UUID()

        harness.command = harness.command(.start, requestID: requestID)
        coordinator.receiveCurrentCommand()
        try await eventually { harness.workflow.runRequestIDs == [requestID] }
        harness.workflow.emit(.listening(.defaultValue))
        harness.command = harness.command(.finish, requestID: requestID)
        coordinator.receiveCurrentCommand()
        try await eventually { coordinator.presentation == .processing }

        harness.workflow.resolve(.transcriptionUncertainSaved)
        try await eventually {
            coordinator.presentation == .failed(
                "Transcription outcome uncertain — recording saved to History"
            )
        }
        #expect(harness.states.last?.phase == .failed)
    }

    @Test
    func stopSessionDuringProcessingDoesNotCancelProviderResult() async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        await coordinator.startSession()
        let requestID = UUID()

        harness.command = harness.command(.start, requestID: requestID)
        coordinator.receiveCurrentCommand()
        try await eventually { harness.workflow.runRequestIDs == [requestID] }
        harness.workflow.emit(.listening(.defaultValue))
        harness.command = harness.command(.finish, requestID: requestID)
        coordinator.receiveCurrentCommand()
        try await eventually { coordinator.presentation == .processing }

        coordinator.stopSession()

        #expect(harness.workflow.stopSessionRequestIDs == [requestID])
        #expect(harness.workflow.cancelRequestIDs.isEmpty)
        // The finalization/provider background assertion remains active until
        // the workflow resolves; Stop Session only disarms warm reuse.
        #expect(harness.endedBackgroundTaskIDs == [harness.backgroundTaskID])
        harness.workflow.resolve(.accepted("Preserved after Stop Session"))
        try await eventually { coordinator.presentation == .resultReady }
        #expect(harness.states.last?.result == "Preserved after Stop Session")
    }

    @Test
    func stopSessionFromResultReadyTearsDownProjectionImmediately()
        async throws {
        let harness = KeyboardSessionHarness()
        let coordinator = harness.makeCoordinator()
        await coordinator.startSession()
        let requestID = UUID()

        harness.command = harness.command(.start, requestID: requestID)
        coordinator.receiveCurrentCommand()
        try await eventually { harness.workflow.runRequestIDs == [requestID] }
        harness.workflow.emit(.listening(.defaultValue))
        harness.command = harness.command(.finish, requestID: requestID)
        coordinator.receiveCurrentCommand()
        harness.workflow.resolve(.accepted("Already durable in Latest"))
        try await eventually { coordinator.presentation == .resultReady }

        coordinator.stopSession()

        #expect(coordinator.presentation == .stopped)
        #expect(harness.states.last?.phase == .unavailable)
        #expect(harness.workflow.stopSessionRequestIDs == [requestID])
        #expect(harness.workflow.cancelRequestIDs.isEmpty)
    }

    @Test
    func productionSupersessionNeverDiscardsPositiveRawCapture()
        async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "holdtype-keyboard-supersession-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = IOSV1ForegroundVoicePersistenceOwner(
            applicationSupportDirectoryURL: root
        )
        let attemptID = UUID()
        let lease = try await persistence.createCapture(
            attemptID: attemptID,
            outputIntent: .standard
        )
        try lease.withTransientRecordingURL { url in
            let handle = try FileHandle(forWritingTo: url)
            try handle.write(contentsOf: Data([1, 2, 3, 4]))
            try handle.close()
        }
        lease.release()

        let retired = await IOSKeyboardHandoffSupersessionClient.live(
            persistenceOwner: persistence
        ).retire(UUID())

        #expect(!retired)
        #expect(
            await persistence.reconcileCaptureSourcesAtLaunch()
                == .recoverable(attemptID: attemptID)
        )
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
        harness.workflow.emit(.listening(.defaultValue))
        harness.command = harness.command(.finish, requestID: requestID)
        coordinator.receiveCurrentCommand()
        harness.workflow.resolve(.accepted("Exactly once"))
        try await eventually { coordinator.presentation == .resultReady }

        #expect(harness.endedBackgroundTaskIDs == [
            harness.backgroundTaskID,
            harness.backgroundTaskID,
        ])

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
        #expect(harness.endedBackgroundTaskIDs == [
            harness.backgroundTaskID,
            harness.backgroundTaskID,
        ])

        let nextRequestID = UUID()
        harness.command = harness.command(.start, requestID: nextRequestID)
        coordinator.receiveCurrentCommand()
        try await eventually {
            harness.workflow.runRequestIDs == [requestID, nextRequestID]
        }
        harness.workflow.resolve(.cancelled)

        coordinator.stopSession()
        #expect(harness.endedBackgroundTaskIDs == [
            harness.backgroundTaskID,
            harness.backgroundTaskID,
            harness.backgroundTaskID,
        ])
        #expect(harness.workflow.endWarmSessionCount == 1)
    }
}

@MainActor
private final class KeyboardSessionHarness {
    let workflow = KeyboardWorkflowHarness()
    let sessionID = UUID()
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var command: HoldTypeIOS.KeyboardDictationCommandRecord?
    var states: [HoldTypeIOS.KeyboardDictationStateRecord] = []
    var persistedState: HoldTypeIOS.KeyboardDictationStateRecord?
    var retiredAttemptIDs: [UUID] = []
    var supersessionResults: [Bool] = []
    var preflightRequestIDs: [UUID] = []
    var failingStatePhases: Set<HoldTypeIOS.KeyboardDictationStatePhase> = []
    var postCount = 0
    var expiryAction: (@MainActor () -> Void)?
    let backgroundTaskID = UIBackgroundTaskIdentifier(rawValue: 42)
    var endedBackgroundTaskIDs: [UIBackgroundTaskIdentifier] = []

    var sessionDeadline: Date {
        now.addingTimeInterval(
            KeyboardDictationBridgeConfiguration.sessionLifetime
        )
    }

    var listeningDeadline: Date {
        now.addingTimeInterval(
            RecordingDurationLimit.defaultValue.duration + 2
        )
    }

    func makeCoordinator() -> IOSKeyboardDictationSessionCoordinator {
        IOSKeyboardDictationSessionCoordinator(
            dependencies: IOSKeyboardDictationSessionDependencies(
                workflow: workflow.client,
                supersession: IOSKeyboardHandoffSupersessionClient {
                    [weak self] attemptID in
                    self?.retiredAttemptIDs.append(attemptID)
                    guard let self,
                          !self.supersessionResults.isEmpty else {
                        return true
                    }
                    return self.supersessionResults.removeFirst()
                },
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
                loadState: { [weak self] _ in self?.persistedState },
                saveState: { [weak self] state in
                    if self?.failingStatePhases.contains(state.phase) == true {
                        throw KeyboardDictationBridgeStoreError.writeFailed
                    }
                    self?.states.append(state)
                    self?.persistedState = state
                },
                postStateChanged: { [weak self] in self?.postCount += 1 },
                applicationIsActive: { true },
                beginBackgroundTask: { [weak self] _ in
                    self?.backgroundTaskID ?? .invalid
                },
                endBackgroundTask: { [weak self] identifier in
                    self?.endedBackgroundTaskIDs.append(identifier)
                },
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
        sourceDocumentID: UUID? = UUID(),
        issuedAt: Date? = nil,
        expiresAt: Date? = nil
    ) -> HoldTypeIOS.KeyboardHandoffIntentRecord {
        let issuedAt = issuedAt ?? now
        return HoldTypeIOS.KeyboardHandoffIntentRecord(
            requestID: requestID,
            sourceDocumentID: sourceDocumentID,
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
    private(set) var interruptRequestIDs: [UUID] = []
    private(set) var stopSessionRequestIDs: [UUID?] = []
    private(set) var endWarmSessionCount = 0
    var retainedCaptureRequestIDs: Set<UUID> = []
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
            interrupt: { [weak self] requestID in
                self?.interruptRequestIDs.append(requestID)
                return self?.runRequestIDs.last == requestID
            },
            stopSession: { [weak self] requestID in
                self?.stopSessionRequestIDs.append(requestID)
                self?.endWarmSessionCount += 1
            },
            ownsRetainedCapture: { [weak self] requestID in
                self?.retainedCaptureRequestIDs.contains(requestID) == true
            },
            endWarmSession: { [weak self] in
                self?.endWarmSessionCount += 1
            },
            loadTranslationAvailability: { [weak self] in
                await self?.loadTranslationAvailability() ?? false
            }
        )
    }

    func emit(_ value: IOSKeyboardDictationWorkflowProgress) {
        if case .listening = value,
           let requestID = runRequestIDs.last {
            retainedCaptureRequestIDs.insert(requestID)
        }
        progress?(value)
    }

    func resolve(_ value: IOSKeyboardDictationWorkflowResolution) {
        continuation?.resume(returning: value)
        continuation = nil
        progress = nil
        if let requestID = runRequestIDs.last {
            retainedCaptureRequestIDs.remove(requestID)
        }
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
private final class KeyboardPendingRecordingHarness {
    var observation: IOSV1PendingRecordingObservation?
    var completedCapture: IOSV1CompletedCaptureRecoveryObservation?
    var loadFails = false
    var failLoadAtOrAfter: Int?
    private(set) var loadCount = 0
    private(set) var stopCount = 0

    lazy var owner = IOSPendingRecordingHistoryStateOwner(
        actions: IOSPendingRecordingHistoryActions(
            load: { [weak self] in
                self?.loadCount += 1
                if self?.loadFails == true
                    || self?.failLoadAtOrAfter.map({ threshold in
                        (self?.loadCount ?? 0) >= threshold
                    }) == true {
                    throw KeyboardPendingRecordingLoadFailure()
                }
                if let completedCapture = self?.completedCapture {
                    return .completedCapture(completedCapture)
                }
                return self?.observation.map {
                    .pending($0)
                }
            },
            stop: { [weak self] in
                self?.stopCount += 1
            }
        )
    )
}

private struct KeyboardPendingRecordingLoadFailure: Error {}

@MainActor
private func keyboardPendingObservation(
    phase: IOSV1PendingRecordingPhase
) throws -> IOSV1PendingRecordingObservation {
    IOSV1PendingRecordingObservation(
        recording: try IOSV1PendingRecording.qualificationFixture(
            phase: phase,
            transcriptionID: phase == .transcribing ? UUID() : nil,
            durationMilliseconds: 30_000,
            byteCount: 4_096
        ),
        availability: .available
    )
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
