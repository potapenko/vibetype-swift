import Foundation
@_spi(HoldTypeIOSCore) @testable import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSForegroundVoiceLatestResultOwnerTests {
    @Test func constructionIsPassiveAndEveryDurableStateMapsWithoutIdentity()
        async throws {
        let record = try latestResultRecord(text: "exact accepted text")
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(record)),
                .value(.absent),
            ]
        )
        let owner = latestResultOwner(probe: probe)

        #expect(owner.presentation == .initial)
        #expect(owner.clearCommand == nil)
        let passiveSnapshot = await probe.snapshot()
        #expect(passiveSnapshot == .init(loads: 0, clears: []))

        _ = try await owner.loadForVoiceWorkflow()
        #expect(
            owner.presentation == IOSForegroundVoiceLatestResultPresentation(
                status: .ready,
                text: "exact accepted text",
                notice: nil
            )
        )
        #expect(owner.clearCommand != nil)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.presentation.status == .absent)
        #expect(owner.clearCommand == nil)
        let mappedSnapshot = await probe.snapshot()
        #expect(
            mappedSnapshot == .init(
                loads: 2,
                clears: [],
                maximumConcurrentCalls: 1
            )
        )
    }

    @Test func staleClearCommandCannotClearAReplacement() async throws {
        let old = try latestResultRecord(text: "old")
        let replacement = try latestResultRecord(text: "replacement")
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(old)),
                .value(.resultReady(replacement)),
            ]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        let stale = try #require(owner.clearCommand)
        _ = try await owner.loadForVoiceWorkflow()

        #expect(owner.clear(stale) == .stale)
        #expect(owner.presentation.text == "replacement")
        let snapshot = await probe.snapshot()
        #expect(snapshot.clears.isEmpty)
    }

    @Test func contentCommandAdmitsReadyAndRetainedClearingText()
        async throws {
        let record = try latestResultRecord(text: "exact visible result")
        let mappedProbe = LatestResultClientProbe(
            loads: [.value(.resultReady(record))]
        )
        let mappedOwner = latestResultOwner(probe: mappedProbe)

        _ = try await mappedOwner.loadForVoiceWorkflow()
        let readyCommand = try #require(mappedOwner.contentCommand)
        #expect(
            mappedOwner.content(for: readyCommand) == "exact visible result"
        )

        let clearStarted = LatestResultTestGate()
        let clearRelease = LatestResultTestGate()
        let clearingProbe = LatestResultClientProbe(
            loads: [.value(.resultReady(record))],
            clears: [.value(.cleared)],
            clearStarted: clearStarted,
            clearRelease: clearRelease
        )
        let clearingOwner = latestResultOwner(probe: clearingProbe)
        _ = try await clearingOwner.loadForVoiceWorkflow()
        let beforeClear = try #require(clearingOwner.contentCommand)
        let clear = try #require(clearingOwner.clearCommand)

        #expect(clearingOwner.clear(clear) == .accepted)
        #expect(clearingOwner.content(for: beforeClear) == nil)
        let clearingCommand = try #require(clearingOwner.contentCommand)
        #expect(
            clearingOwner.content(for: clearingCommand)
                == "exact visible result"
        )

        await clearStarted.wait()
        await clearRelease.open()
        await clearingOwner.waitUntilClearIsIdle()
        #expect(clearingOwner.contentCommand == nil)
        #expect(clearingOwner.content(for: clearingCommand) == nil)
    }

    @Test func contentCommandIsUnavailableForEveryContentFreeState()
        async throws {
        let probe = LatestResultClientProbe(
            loads: [
                .value(.absent),
                .failure,
            ]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.presentation.status == .absent)
        #expect(owner.contentCommand == nil)

        await #expect(
            throws: IOSForegroundVoiceLatestResultOwnerError.self
        ) {
            _ = try await owner.loadForVoiceWorkflow()
        }
        #expect(owner.presentation.status == .unavailable)
        #expect(owner.contentCommand == nil)
    }

    @Test func staleContentCommandCannotReadAReplacementOrClearedResult()
        async throws {
        let old = try latestResultRecord(text: "old visible result")
        let replacement = try latestResultRecord(text: "replacement result")
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(old)),
                .value(.resultReady(replacement)),
            ],
            clears: [.value(.cleared)]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        let oldCommand = try #require(owner.contentCommand)
        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.content(for: oldCommand) == nil)

        let replacementCommand = try #require(owner.contentCommand)
        #expect(owner.content(for: replacementCommand) == "replacement result")
        #expect(
            owner.clear(try #require(owner.clearCommand)) == .accepted
        )
        let clearingCommand = try #require(owner.contentCommand)
        await owner.waitUntilClearIsIdle()

        #expect(owner.content(for: replacementCommand) == nil)
        #expect(owner.content(for: clearingCommand) == nil)
        #expect(owner.contentCommand == nil)
    }

    @Test func confirmedClearUsesExactExpectationAndPublishesAbsent()
        async throws {
        let record = try latestResultRecord(text: "clear me")
        let expected = IOSV1AcceptedOutputDeliveryExpectation(record: record)
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record))],
            clears: [.value(.cleared)]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        let command = try #require(owner.clearCommand)
        #expect(owner.clear(command) == .accepted)
        #expect(owner.presentation.status == .clearing)
        #expect(owner.presentation.text == "clear me")
        #expect(owner.clearCommand == nil)

        await owner.waitUntilClearIsIdle()

        #expect(owner.presentation.status == .absent)
        #expect(owner.presentation.text == nil)
        #expect(owner.clearCommand == nil)
        let snapshot = await probe.snapshot()
        #expect(snapshot.clears == [expected])
    }

    @Test func confirmedAbsenceRepublishesKeyboardAndReportsProjectionFailure()
        async throws {
        let record = try latestResultRecord(text: "clear projection")
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record))],
            clears: [.value(.cleared)]
        )
        let projection = LatestKeyboardProjectionProbe(results: [false])
        let owner = latestResultOwner(
            probe: probe,
            publishKeyboardSnapshot: { await projection.publish() }
        )

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await owner.waitUntilClearIsIdle()

        #expect(owner.presentation.status == .absent)
        #expect(owner.presentation.notice == nil)
        #expect(owner.presentation.keyboardProjectionUpdateFailed)
        #expect(await projection.callCount == 1)
    }

    @Test func failedProjectionRefreshIsReportedAfterLatestLoads()
        async throws {
        let record = try latestResultRecord(text: "accepted before refresh")
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record))]
        )
        let projection = LatestKeyboardProjectionProbe(results: [false])
        let owner = latestResultOwner(
            probe: probe,
            publishKeyboardSnapshot: { await projection.publish() }
        )

        await owner.refreshKeyboardProjection()
        #expect(owner.presentation == .initial)

        _ = try await owner.loadForVoiceWorkflow()

        #expect(owner.presentation.status == .ready)
        #expect(owner.presentation.text == "accepted before refresh")
        #expect(owner.presentation.notice == nil)
        #expect(owner.presentation.keyboardProjectionUpdateFailed)
        #expect(await projection.callCount == 1)
    }

    @Test func successfulProjectionRefreshClearsTheFailureNotice()
        async throws {
        let record = try latestResultRecord(text: "refresh retry")
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record))]
        )
        let projection = LatestKeyboardProjectionProbe(
            results: [false, true]
        )
        let owner = latestResultOwner(
            probe: probe,
            publishKeyboardSnapshot: { await projection.publish() }
        )

        _ = try await owner.loadForVoiceWorkflow()
        await owner.refreshKeyboardProjection()
        #expect(owner.presentation.keyboardProjectionUpdateFailed)

        await owner.refreshKeyboardProjection()

        #expect(owner.presentation.status == .ready)
        #expect(owner.presentation.text == "refresh retry")
        #expect(owner.presentation.notice == nil)
        #expect(!owner.presentation.keyboardProjectionUpdateFailed)
        #expect(await projection.callCount == 2)
    }

    @Test func projectionWarningRefreshPreservesVisibleCommands()
        async throws {
        let record = try latestResultRecord(text: "stable command target")
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record))]
        )
        let projection = LatestKeyboardProjectionProbe(
            results: [false, true]
        )
        let owner = latestResultOwner(
            probe: probe,
            publishKeyboardSnapshot: { await projection.publish() }
        )

        _ = try await owner.loadForVoiceWorkflow()
        let clearCommand = try #require(owner.clearCommand)
        let contentCommand = try #require(owner.contentCommand)

        await owner.refreshKeyboardProjection()
        #expect(owner.presentation.keyboardProjectionUpdateFailed)
        #expect(owner.clearCommand == clearCommand)
        #expect(owner.content(for: contentCommand) == "stable command target")

        await owner.refreshKeyboardProjection()
        #expect(!owner.presentation.keyboardProjectionUpdateFailed)
        #expect(owner.clearCommand == clearCommand)
        #expect(owner.content(for: contentCommand) == "stable command target")
    }

    @Test func projectionFailureNeverReplacesOrClearsAClearFailure()
        async throws {
        let record = try latestResultRecord(text: "clear remains primary")
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(record)),
                .value(.resultReady(record)),
            ],
            clears: [.failure]
        )
        let projection = LatestKeyboardProjectionProbe(
            results: [false, true]
        )
        let owner = latestResultOwner(
            probe: probe,
            publishKeyboardSnapshot: { await projection.publish() }
        )

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await owner.waitUntilClearIsIdle()
        #expect(owner.presentation.notice == .clearFailed)

        await owner.refreshKeyboardProjection()
        #expect(owner.presentation.notice == .clearFailed)
        #expect(owner.presentation.keyboardProjectionUpdateFailed)

        await owner.refreshKeyboardProjection()
        #expect(owner.presentation.notice == .clearFailed)
        #expect(!owner.presentation.keyboardProjectionUpdateFailed)
        #expect(await projection.callCount == 2)
    }

    @Test func failedClearWithoutPublicationPreservesPendingProjectionFailure()
        async throws {
        let record = try latestResultRecord(text: "pending cache failure")
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(record)),
                .value(.resultReady(record)),
            ],
            clears: [.failure]
        )
        let projection = LatestKeyboardProjectionProbe(results: [false])
        let owner = latestResultOwner(
            probe: probe,
            publishKeyboardSnapshot: { await projection.publish() }
        )

        _ = try await owner.loadForVoiceWorkflow()
        await owner.refreshKeyboardProjection()
        #expect(owner.presentation.keyboardProjectionUpdateFailed)

        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await owner.waitUntilClearIsIdle()

        #expect(owner.presentation.notice == .clearFailed)
        #expect(owner.presentation.keyboardProjectionUpdateFailed)
        #expect(await projection.callCount == 1)
    }

    @Test func canonicalLoadFailureRetainsThePendingProjectionFailure()
        async throws {
        let record = try latestResultRecord(text: "latent cache failure")
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(record)),
                .failure,
                .value(.resultReady(record)),
            ]
        )
        let projection = LatestKeyboardProjectionProbe(results: [false])
        let owner = latestResultOwner(
            probe: probe,
            publishKeyboardSnapshot: { await projection.publish() }
        )

        _ = try await owner.loadForVoiceWorkflow()
        await owner.refreshKeyboardProjection()
        await #expect(
            throws: IOSForegroundVoiceLatestResultOwnerError.self
        ) {
            _ = try await owner.loadForVoiceWorkflow()
        }

        #expect(owner.presentation.status == .unavailable)
        #expect(owner.presentation.notice == .loadFailed)
        #expect(owner.presentation.keyboardProjectionUpdateFailed)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.presentation.status == .ready)
        #expect(owner.presentation.notice == nil)
        #expect(owner.presentation.keyboardProjectionUpdateFailed)
    }

    @Test func clearAndRefreshShareOneOrderedProjectionPublicationLane()
        async throws {
        let record = try latestResultRecord(text: "serialized projection")
        let firstStarted = LatestResultTestGate()
        let firstRelease = LatestResultTestGate()
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record))],
            clears: [.value(.cleared)]
        )
        let projection = LatestKeyboardProjectionProbe(
            results: [false, true],
            firstPublishStarted: firstStarted,
            firstPublishRelease: firstRelease
        )
        let owner = latestResultOwner(
            probe: probe,
            publishKeyboardSnapshot: { await projection.publish() }
        )

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await firstStarted.wait()

        var refreshReachedOwner = false
        let refresh = Task { @MainActor in
            refreshReachedOwner = true
            await owner.refreshKeyboardProjection()
        }
        while !refreshReachedOwner { await Task.yield() }
        #expect(await projection.callCount == 1)

        await firstRelease.open()
        await owner.waitUntilClearIsIdle()
        await refresh.value

        let snapshot = await projection.snapshot()
        #expect(snapshot.callCount == 2)
        #expect(snapshot.maximumConcurrentCalls == 1)
        #expect(owner.presentation.status == .absent)
        #expect(!owner.presentation.keyboardProjectionUpdateFailed)
    }

    @Test func reconciledAbsenceRepublishesKeyboardButRetainedResultDoesNot()
        async throws {
        let record = try latestResultRecord(text: "reconcile projection")
        let absenceProbe = LatestResultClientProbe(
            loads: [.value(.resultReady(record)), .value(.absent)],
            clears: [.failure]
        )
        let absenceProjection = LatestKeyboardProjectionProbe(results: [true])
        let absenceOwner = latestResultOwner(
            probe: absenceProbe,
            publishKeyboardSnapshot: {
                await absenceProjection.publish()
            }
        )
        _ = try await absenceOwner.loadForVoiceWorkflow()
        #expect(
            absenceOwner.clear(try #require(absenceOwner.clearCommand))
                == .accepted
        )
        await absenceOwner.waitUntilClearIsIdle()
        #expect(absenceOwner.presentation.status == .absent)
        #expect(await absenceProjection.callCount == 1)

        let retainedProbe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(record)),
                .value(.resultReady(record)),
            ],
            clears: [.failure]
        )
        let retainedProjection = LatestKeyboardProjectionProbe(results: [true])
        let retainedOwner = latestResultOwner(
            probe: retainedProbe,
            publishKeyboardSnapshot: {
                await retainedProjection.publish()
            }
        )
        _ = try await retainedOwner.loadForVoiceWorkflow()
        #expect(
            retainedOwner.clear(try #require(retainedOwner.clearCommand))
                == .accepted
        )
        await retainedOwner.waitUntilClearIsIdle()
        #expect(retainedOwner.presentation.status == .ready)
        #expect(await retainedProjection.callCount == 0)
    }

    @Test func failedClearReconcilesSameRecordAndKeepsItRetryable()
        async throws {
        let record = try latestResultRecord(text: "still durable")
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(record)),
                .value(.resultReady(record)),
            ],
            clears: [.failure]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await owner.waitUntilClearIsIdle()

        #expect(owner.presentation.status == .ready)
        #expect(owner.presentation.text == "still durable")
        #expect(owner.presentation.notice == .clearFailed)
        #expect(owner.clearCommand != nil)
    }

    @Test func failedClearPublishesNewerReplacementWithoutRetryingIt()
        async throws {
        let old = try latestResultRecord(text: "old selected result")
        let replacement = try latestResultRecord(text: "new durable result")
        let oldExpectation = IOSV1AcceptedOutputDeliveryExpectation(record: old)
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(old)),
                .value(.resultReady(replacement)),
            ],
            clears: [.failure]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await owner.waitUntilClearIsIdle()

        #expect(owner.presentation.status == .ready)
        #expect(owner.presentation.text == "new durable result")
        #expect(owner.presentation.notice == .resultChanged)
        let snapshot = await probe.snapshot()
        #expect(snapshot.clears == [oldExpectation])
    }

    @Test func unknownClearOutcomeHidesUnconfirmedText() async throws {
        let record = try latestResultRecord(text: "recoverable text")
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record)), .failure],
            clears: [.failure]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await owner.waitUntilClearIsIdle()

        #expect(owner.presentation.status == .unavailable)
        #expect(owner.presentation.text == nil)
        #expect(owner.presentation.notice == .clearStateUnknown)
        #expect(owner.clearCommand == nil)
    }

    @Test func genericLoadFailureHidesPreviouslyPublishedText() async throws {
        let record = try latestResultRecord(text: "previously confirmed")
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record)), .failure]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        await #expect(
            throws: IOSForegroundVoiceLatestResultOwnerError.self
        ) {
            _ = try await owner.loadForVoiceWorkflow()
        }

        #expect(owner.presentation.status == .unavailable)
        #expect(owner.presentation.text == nil)
        #expect(owner.presentation.notice == .loadFailed)
        #expect(owner.clearCommand == nil)
    }

    @Test func admittedClearOutlivesCallerAndSerializesACompetingLoad()
        async throws {
        let record = try latestResultRecord(text: "owned until tombstone")
        let clearStarted = LatestResultTestGate()
        let clearRelease = LatestResultTestGate()
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record)), .value(.absent)],
            clears: [.value(.cleared)],
            clearStarted: clearStarted,
            clearRelease: clearRelease
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await clearStarted.wait()

        let competingLoad = Task { @MainActor in
            try await owner.loadForVoiceWorkflow()
        }
        await Task.yield()
        let blockedSnapshot = await probe.snapshot()
        #expect(blockedSnapshot.loads == 1)
        #expect(blockedSnapshot.maximumConcurrentCalls == 1)

        await clearRelease.open()
        await owner.waitUntilClearIsIdle()
        _ = try await competingLoad.value

        #expect(owner.presentation.status == .absent)
        #expect(owner.presentation.text == nil)
        let finalSnapshot = await probe.snapshot()
        #expect(finalSnapshot.maximumConcurrentCalls == 1)
    }

    @Test func cancelledLoadDoesNotErasePreviouslyPublishedResult()
        async throws {
        let record = try latestResultRecord(text: "do not erase")
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record)), .cancelled]
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        await #expect(throws: CancellationError.self) {
            _ = try await owner.loadForVoiceWorkflow()
        }

        #expect(owner.presentation.status == .ready)
        #expect(owner.presentation.text == "do not erase")
        #expect(owner.presentation.notice == nil)
    }

    @Test func newerQueuedLoadReplacesAnOlderOverlappingPublication()
        async throws {
        let old = try latestResultRecord(text: "old load")
        let replacement = try latestResultRecord(text: "newer queued load")
        let firstLoadStarted = LatestResultTestGate()
        let firstLoadRelease = LatestResultTestGate()
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(old)),
                .value(.resultReady(replacement)),
            ],
            firstLoadStarted: firstLoadStarted,
            firstLoadRelease: firstLoadRelease
        )
        let owner = latestResultOwner(probe: probe)

        let first = Task { @MainActor in
            try await owner.loadForVoiceWorkflow()
        }
        await firstLoadStarted.wait()
        let second = Task { @MainActor in
            try await owner.loadForVoiceWorkflow()
        }
        await Task.yield()
        await firstLoadRelease.open()
        _ = try await first.value
        _ = try await second.value

        #expect(owner.presentation.status == .ready)
        #expect(owner.presentation.text == "newer queued load")
        #expect(owner.clearCommand != nil)
    }

    @Test func postClearQueuedLoadCanPublishAReplacement() async throws {
        let old = try latestResultRecord(text: "clear target")
        let replacement = try latestResultRecord(text: "post-clear replacement")
        let clearStarted = LatestResultTestGate()
        let clearRelease = LatestResultTestGate()
        let probe = LatestResultClientProbe(
            loads: [
                .value(.resultReady(old)),
                .value(.resultReady(replacement)),
            ],
            clears: [.value(.cleared)],
            clearStarted: clearStarted,
            clearRelease: clearRelease
        )
        let owner = latestResultOwner(probe: probe)

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await clearStarted.wait()
        let replacementLoad = Task { @MainActor in
            try await owner.loadForVoiceWorkflow()
        }
        await Task.yield()
        await clearRelease.open()
        await owner.waitUntilClearIsIdle()
        _ = try await replacementLoad.value

        #expect(owner.presentation.status == .ready)
        #expect(owner.presentation.text == "post-clear replacement")
        #expect(owner.clearCommand != nil)
    }

    @Test func olderFailureCannotReplaceANewerSuccessfulPublication()
        async throws {
        let replacement = try latestResultRecord(text: "newer success")
        let firstPublicationStarted = LatestResultTestGate()
        let firstPublicationRelease = LatestResultTestGate()
        let probe = LatestResultClientProbe(
            loads: [.failure, .value(.resultReady(replacement))]
        )
        let owner = latestResultOwner(
            probe: probe,
            beforePublishing: { sequence in
                guard sequence == 1 else { return }
                await firstPublicationStarted.open()
                await firstPublicationRelease.wait()
            }
        )

        let olderFailure = Task { @MainActor in
            try await owner.loadForVoiceWorkflow()
        }
        await firstPublicationStarted.wait()
        _ = try await owner.loadForVoiceWorkflow()
        await firstPublicationRelease.open()
        await #expect(
            throws: IOSForegroundVoiceLatestResultOwnerError.self
        ) {
            _ = try await olderFailure.value
        }

        #expect(owner.presentation.status == .ready)
        #expect(owner.presentation.text == "newer success")
        #expect(owner.presentation.notice == nil)
        #expect(owner.clearCommand != nil)
    }

    @Test func newerQueuedFailureCannotBeOverwrittenByClearCompletion()
        async throws {
        let record = try latestResultRecord(text: "clear target")
        let clearPublicationStarted = LatestResultTestGate()
        let clearPublicationRelease = LatestResultTestGate()
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record)), .failure],
            clears: [.value(.cleared)]
        )
        let owner = latestResultOwner(
            probe: probe,
            beforePublishing: { sequence in
                guard sequence == 2 else { return }
                await clearPublicationStarted.open()
                await clearPublicationRelease.wait()
            }
        )

        _ = try await owner.loadForVoiceWorkflow()
        #expect(owner.clear(try #require(owner.clearCommand)) == .accepted)
        await clearPublicationStarted.wait()
        await #expect(
            throws: IOSForegroundVoiceLatestResultOwnerError.self
        ) {
            _ = try await owner.loadForVoiceWorkflow()
        }
        await clearPublicationRelease.open()
        await owner.waitUntilClearIsIdle()

        #expect(owner.presentation.status == .unavailable)
        #expect(owner.presentation.text == nil)
        #expect(owner.presentation.notice == .loadFailed)
        #expect(owner.clearCommand == nil)
    }

    @Test func textBearingValuesAndCommandsAreReflectionRedacted()
        async throws {
        let secret = "TRANSCRIPT-SENTINEL-DO-NOT-REFLECT"
        let record = try latestResultRecord(text: secret)
        let probe = LatestResultClientProbe(
            loads: [.value(.resultReady(record))]
        )
        let owner = latestResultOwner(probe: probe)
        _ = try await owner.loadForVoiceWorkflow()
        let clearCommand = try #require(owner.clearCommand)
        let contentCommand = try #require(owner.contentCommand)

        for rendered in [
            String(describing: owner),
            String(reflecting: owner),
            String(describing: owner.presentation),
            String(reflecting: owner.presentation),
            String(describing: clearCommand),
            String(reflecting: clearCommand),
            String(describing: contentCommand),
            String(reflecting: contentCommand),
        ] {
            #expect(!rendered.contains(secret))
            #expect(rendered.localizedCaseInsensitiveContains("redacted"))
        }
        #expect(Mirror(reflecting: owner).children.isEmpty)
        #expect(Mirror(reflecting: owner.presentation).children.isEmpty)
        #expect(Mirror(reflecting: clearCommand).children.isEmpty)
        #expect(Mirror(reflecting: contentCommand).children.isEmpty)
    }
}

private nonisolated enum LatestResultProbeError: Error {
    case failed
}

private nonisolated enum LatestResultLoadStep: Sendable {
    case value(IOSV1ForegroundVoiceLatestResultObservation)
    case failure
    case cancelled
}

private nonisolated enum LatestResultClearStep: Sendable {
    case value(IOSV1ForegroundVoiceClearResult)
    case failure
}

private actor LatestResultClientProbe {
    nonisolated struct Snapshot: Equatable, Sendable {
        let loads: Int
        let clears: [IOSV1AcceptedOutputDeliveryExpectation]
        var maximumConcurrentCalls: Int = 0
    }

    private var loadSteps: [LatestResultLoadStep]
    private var clearSteps: [LatestResultClearStep]
    private let clearStarted: LatestResultTestGate?
    private let clearRelease: LatestResultTestGate?
    private let firstLoadStarted: LatestResultTestGate?
    private let firstLoadRelease: LatestResultTestGate?
    private var loadCount = 0
    private var clearExpectations: [IOSV1AcceptedOutputDeliveryExpectation] = []
    private var activeCalls = 0
    private var maximumConcurrentCalls = 0

    init(
        loads: [LatestResultLoadStep],
        clears: [LatestResultClearStep] = [],
        clearStarted: LatestResultTestGate? = nil,
        clearRelease: LatestResultTestGate? = nil,
        firstLoadStarted: LatestResultTestGate? = nil,
        firstLoadRelease: LatestResultTestGate? = nil
    ) {
        loadSteps = loads
        clearSteps = clears
        self.clearStarted = clearStarted
        self.clearRelease = clearRelease
        self.firstLoadStarted = firstLoadStarted
        self.firstLoadRelease = firstLoadRelease
    }

    func load() async throws -> IOSV1ForegroundVoiceLatestResultObservation {
        beginCall()
        defer { endCall() }
        let index = loadCount
        loadCount += 1
        if index == 0 {
            await firstLoadStarted?.open()
            await firstLoadRelease?.wait()
        }
        guard !loadSteps.isEmpty else { throw LatestResultProbeError.failed }
        switch loadSteps.removeFirst() {
        case .value(let observation):
            return observation
        case .failure:
            throw LatestResultProbeError.failed
        case .cancelled:
            throw CancellationError()
        }
    }

    func clear(
        _ expected: IOSV1AcceptedOutputDeliveryExpectation
    ) async throws -> IOSV1ForegroundVoiceClearResult {
        beginCall()
        defer { endCall() }
        clearExpectations.append(expected)
        await clearStarted?.open()
        await clearRelease?.wait()
        guard !clearSteps.isEmpty else { throw LatestResultProbeError.failed }
        switch clearSteps.removeFirst() {
        case .value(let result):
            return result
        case .failure:
            throw LatestResultProbeError.failed
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(
            loads: loadCount,
            clears: clearExpectations,
            maximumConcurrentCalls: maximumConcurrentCalls
        )
    }

    private func beginCall() {
        activeCalls += 1
        maximumConcurrentCalls = max(maximumConcurrentCalls, activeCalls)
    }

    private func endCall() {
        activeCalls -= 1
    }
}

private actor LatestResultTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

private actor LatestKeyboardProjectionProbe {
    nonisolated struct Snapshot: Equatable, Sendable {
        let callCount: Int
        let maximumConcurrentCalls: Int
    }

    private var results: [Bool]
    private let firstPublishStarted: LatestResultTestGate?
    private let firstPublishRelease: LatestResultTestGate?
    private(set) var callCount = 0
    private var activeCalls = 0
    private var maximumConcurrentCalls = 0

    init(
        results: [Bool],
        firstPublishStarted: LatestResultTestGate? = nil,
        firstPublishRelease: LatestResultTestGate? = nil
    ) {
        self.results = results
        self.firstPublishStarted = firstPublishStarted
        self.firstPublishRelease = firstPublishRelease
    }

    func publish() async -> Bool {
        activeCalls += 1
        maximumConcurrentCalls = max(maximumConcurrentCalls, activeCalls)
        defer { activeCalls -= 1 }

        let isFirstCall = callCount == 0
        callCount += 1
        if isFirstCall {
            await firstPublishStarted?.open()
            await firstPublishRelease?.wait()
        }
        return results.isEmpty ? true : results.removeFirst()
    }

    func snapshot() -> Snapshot {
        Snapshot(
            callCount: callCount,
            maximumConcurrentCalls: maximumConcurrentCalls
        )
    }
}

@MainActor
private func latestResultOwner(
    probe: LatestResultClientProbe,
    beforePublishing: @escaping
        IOSForegroundVoiceLatestResultOwner.BeforePublishing = { _ in },
    publishKeyboardSnapshot: @escaping
        IOSForegroundVoiceLatestResultOwner.PublishKeyboardSnapshot = {
            true
        }
) -> IOSForegroundVoiceLatestResultOwner {
    IOSForegroundVoiceLatestResultOwner(
        load: { try await probe.load() },
        clear: { try await probe.clear($0) },
        beforePublishing: beforePublishing,
        publishKeyboardSnapshot: publishKeyboardSnapshot
    )
}

private func latestResultRecord(
    text: String
) throws -> IOSV1AcceptedOutputDeliveryRecord {
    let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    return try IOSV1AcceptedOutputDeliveryRecord(
        resultID: UUID(),
        sourceAttemptID: UUID(),
        acceptedText: text,
        createdAt: createdAt
    )
}
