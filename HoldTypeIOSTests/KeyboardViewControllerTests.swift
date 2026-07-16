import Foundation
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct KeyboardViewControllerTests {
    @Test func documentIdentifierAdapterToleratesTemporarilyMissingValue() {
        let object = KeyboardObjectiveCDocumentIdentifierSpy(identifier: nil)

        #expect(
            KeyboardDocumentIdentifierAdapter.load(
                fromObjectiveCObject: object
            ) == nil
        )
    }

    @Test func documentIdentifierAdapterReadsAvailableValue() {
        let identifier = UUID()
        let object = KeyboardObjectiveCDocumentIdentifierSpy(
            identifier: identifier as NSUUID
        )

        #expect(
            KeyboardDocumentIdentifierAdapter.load(
                fromObjectiveCObject: object
            ) == identifier
        )
    }

    @Test func documentIdentifierAdapterReadsTheUIKitDocumentProxy() {
        let identifier = UUID()
        let proxy = KeyboardDocumentProxySpy(documentIdentifier: identifier)

        #expect(
            KeyboardDocumentIdentifierAdapter.load(from: proxy) == identifier
        )
    }

    @Test func documentIdentifierLookupUsesTheDocumentProxy() {
        let harness = KeyboardControllerHarness()
        let controller = harness.makeController()

        controller.loadViewIfNeeded()
        controller.keyboardView.onMicrophoneRequested?()

        #expect(
            harness.documentIdentifierOwnerIDs.contains(
                ObjectIdentifier(harness.proxy)
            )
        )
    }

    @Test func containingAppLaunchUsesTheResponderChain() throws {
        let url = try #require(URL(string: "holdtype://keyboard-handoff/test"))
        let applicationResponder = KeyboardOpenURLResponderSpy()
        let sceneResponder = KeyboardOpenURLResponderSpy(
            nextResponder: applicationResponder
        )
        var completionValues: [Bool] = []

        KeyboardContainingAppLaunchAdapter.open(
            url,
            from: sceneResponder,
            extensionContext: nil
        ) { completionValues.append($0) }

        #expect(sceneResponder.openedURLs.isEmpty)
        #expect(applicationResponder.openedURLs == [url])
        #expect(completionValues == [true])
    }

    @Test func containingAppLaunchFailsWithoutAnAvailableRoute() throws {
        let url = try #require(URL(string: "holdtype://keyboard-handoff/test"))
        var completionValues: [Bool] = []

        KeyboardContainingAppLaunchAdapter.open(
            url,
            from: UIResponder(),
            extensionContext: nil
        ) { completionValues.append($0) }

        #expect(completionValues == [false])
    }

    @Test func latestLoadsWithoutInsertionAndEachTapInsertsOnce() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let latest = try KeyboardBridgeItem.latest(
            resultID: UUID(),
            text: "Latest exact text",
            createdAt: now.addingTimeInterval(-60)
        )
        let harness = KeyboardControllerHarness(
            now: now,
            snapshot: try KeyboardBridgeSnapshot(
                revision: 1,
                publishedAt: now,
                latest: latest
            )
        )
        let controller = harness.makeController()

        controller.loadViewIfNeeded()

        let latestButton = try button(
            "keyboard.brand-stage.latest",
            in: controller.view
        )
        #expect(latestButton.isEnabled)
        #expect(harness.proxy.insertedTexts.isEmpty)

        controller.keyboardView.onLatestRequested?()
        controller.keyboardView.onLatestRequested?()

        #expect(harness.proxy.insertedTexts == [
            "Latest exact text",
            "Latest exact text",
        ])
    }

    @Test func oldHistoryLatestRemainsInsertableWithoutSchedulingExpiry() throws {
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let latest = try KeyboardBridgeItem.latest(
            resultID: UUID(),
            text: "Still available",
            createdAt: createdAt
        )
        let harness = KeyboardControllerHarness(
            now: createdAt.addingTimeInterval(365 * 24 * 60 * 60),
            snapshot: try KeyboardBridgeSnapshot(
                revision: 1,
                publishedAt: createdAt,
                latest: latest
            )
        )
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        controller.keyboardView.onLatestRequested?()

        let latestButton = try button(
            "keyboard.brand-stage.latest",
            in: controller.view
        )
        #expect(latestButton.isEnabled)
        #expect(harness.proxy.insertedTexts == ["Still available"])
        #expect(harness.scheduledExpiryDates.isEmpty)
    }

    @Test func refreshedHistorySnapshotReplacesLatest() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let first = try KeyboardBridgeItem.latest(
            resultID: UUID(),
            text: "First",
            createdAt: now.addingTimeInterval(-60)
        )
        let replacement = try KeyboardBridgeItem.latest(
            resultID: UUID(),
            text: "Replacement",
            createdAt: now
        )
        let harness = KeyboardControllerHarness(
            now: now,
            snapshot: try KeyboardBridgeSnapshot(
                revision: 1,
                publishedAt: now,
                latest: first
            )
        )
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        harness.snapshot = try KeyboardBridgeSnapshot(
            revision: 2,
            publishedAt: now,
            latest: replacement
        )
        controller.textDidChange(nil)
        controller.keyboardView.onLatestRequested?()
        #expect(harness.proxy.insertedTexts == ["Replacement"])
    }

    @Test func editingAndCursorCallbacksRouteToTheDocumentProxy() throws {
        let harness = KeyboardControllerHarness()
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        controller.keyboardView.onQuickInsertRequested?("?")
        controller.keyboardView.onQuickInsertRequested?("🙂")
        controller.keyboardView.onSpaceRequested?()
        controller.keyboardView.onReturnRequested?()
        controller.keyboardView.onCursorStepRequested?(-1)
        controller.keyboardView.onSpaceCursorGesture?(.began, 0)
        controller.keyboardView.onSpaceCursorGesture?(.changed, 13)
        controller.keyboardView.onSpaceCursorGesture?(.ended, 13)
        controller.keyboardView.onDeleteStarted?()
        controller.keyboardView.onDeleteStopped?()

        #expect(harness.proxy.insertedTexts == ["?", "🙂", " ", "\n"])
        #expect(harness.proxy.cursorOffsets == [-1, 1])
        #expect(harness.proxy.deleteBackwardCount == 1)
    }

    @Test func returnTraitsAndInputModeRequirementDrivePresentation() throws {
        let hiddenGlobeHarness = KeyboardControllerHarness(
            inputModeSwitchKeyOverride: false
        )
        hiddenGlobeHarness.proxy.returnKeyType = .send
        hiddenGlobeHarness.proxy.enablesReturnKeyAutomatically = true
        hiddenGlobeHarness.proxy.hasText = false
        let hiddenGlobeController = hiddenGlobeHarness.makeController()
        hiddenGlobeController.loadViewIfNeeded()

        let hiddenGlobe = try button(
            "keyboard.brand-stage.next-keyboard",
            in: hiddenGlobeController.view
        )
        let returnButton = try button(
            "keyboard.brand-stage.return",
            in: hiddenGlobeController.view
        )
        #expect(hiddenGlobe.isHidden)
        #expect(returnButton.configuration?.title == "Send")
        #expect(returnButton.accessibilityLabel == "Send")
        #expect(!returnButton.isEnabled)

        hiddenGlobeHarness.proxy.returnKeyType = .search
        hiddenGlobeHarness.proxy.hasText = true
        hiddenGlobeController.textDidChange(nil)

        #expect(returnButton.configuration?.title == "Search")
        #expect(returnButton.accessibilityLabel == "Search")
        #expect(returnButton.isEnabled)

        let visibleGlobeHarness = KeyboardControllerHarness(
            inputModeSwitchKeyOverride: true
        )
        let visibleGlobeController = visibleGlobeHarness.makeController()
        visibleGlobeController.loadViewIfNeeded()
        let visibleGlobe = try button(
            "keyboard.brand-stage.next-keyboard",
            in: visibleGlobeController.view
        )
        #expect(!visibleGlobe.isHidden)
        #expect(
            !(visibleGlobe.actions(
                forTarget: visibleGlobeController,
                forControlEvent: .allTouchEvents
            ) ?? []).isEmpty
        )
    }

    @Test func missingSessionLaunchesBoundedHandoffFromTheReadyIndicator()
        throws {
        let requestID = UUID()
        let harness = KeyboardControllerHarness(requestID: requestID)
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        #expect(controller.hasDictationKey)
        #expect(statusText(in: controller.view) == "Ready")
        let microphone = try button(
            "keyboard.brand-stage.voice",
            in: controller.view
        )
        #expect(microphone.isEnabled)
        #expect(
            descendant(
                UIButton.self,
                identifier: "keyboard.brand-stage.settings",
                in: controller.view
            ) == nil
        )

        microphone.sendActions(for: .touchUpInside)

        let intent = try #require(harness.savedHandoffIntents.first)
        #expect(harness.savedHandoffIntents.count == 1)
        #expect(intent.requestID == requestID)
        #expect(intent.sourceDocumentID == harness.proxy.documentIdentifier)
        #expect(intent.action == .standard)
        #expect(harness.savedCommands.isEmpty)
        #expect(harness.openedURLs == [
            try #require(
                KeyboardHandoffLaunchRoute(requestID: requestID).url
            ),
        ])
        #expect(statusText(in: controller.view) == "Opening HoldType…")
        #expect(!microphone.isEnabled)
    }

    @Test func appStateDrivesCommandsAndMatchingResultInsertsOnce() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let requestID = UUID()
        let deadline = now.addingTimeInterval(60)
        let harness = KeyboardControllerHarness(
            now: now,
            dictationState: try #require(
                KeyboardDictationStateRecord(
                    requestID: requestID,
                    phase: .ready,
                    publishedAt: now,
                    expiresAt: deadline
                )
            )
        )
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        controller.keyboardView.onMicrophoneRequested?()
        #expect(harness.savedCommands.map(\.kind) == [.start])
        #expect(harness.savedHandoffIntents.isEmpty)
        #expect(harness.openedURLs.isEmpty)

        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                requestID: requestID,
                phase: .listening,
                publishedAt: now,
                expiresAt: deadline
            )
        )
        controller.textDidChange(nil)
        #expect(statusText(in: controller.view) == "Listening…")
        controller.keyboardView.onMicrophoneRequested?()
        #expect(harness.savedCommands.map(\.kind) == [.start, .finish])

        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                requestID: requestID,
                phase: .resultReady,
                result: "Processed keyboard text",
                publishedAt: now,
                expiresAt: deadline
            )
        )
        controller.textDidChange(nil)
        #expect(harness.savedCommands.map(\.kind) == [
            .start,
            .finish,
            .claimDelivery,
        ])
        #expect(harness.proxy.insertedTexts.isEmpty)

        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                requestID: requestID,
                deliveryClaimID: harness.deliveryClaimID,
                phase: .resultReady,
                result: "Processed keyboard text",
                publishedAt: now,
                expiresAt: deadline
            )
        )
        controller.textDidChange(nil)
        controller.textDidChange(nil)

        #expect(harness.proxy.insertedTexts == [
            "Processed keyboard text",
        ])
        #expect(harness.savedCommands.map(\.kind) == [
            .start,
            .finish,
            .claimDelivery,
            .acknowledgeDelivery,
        ])
        #expect(statusText(in: controller.view) == "Ready")
    }

    @Test func automaticVoiceModesApplyOnMicrophoneStartAndGateTranslation() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let requestID = UUID()
        let deadline = now.addingTimeInterval(60)
        let harness = KeyboardControllerHarness(
            now: now,
            dictationState: try #require(
                KeyboardDictationStateRecord(
                    requestID: requestID,
                    phase: .ready,
                    translationAvailable: true,
                    publishedAt: now,
                    expiresAt: deadline
                )
            )
        )
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        controller.keyboardView.onAutomaticVoiceActionChanged?(.translate)
        #expect(harness.savedCommands.isEmpty)
        controller.keyboardView.onMicrophoneRequested?()
        #expect(harness.savedCommands.map(\.action) == [.translate])

        harness.savedCommands.removeAll()
        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                requestID: UUID(),
                phase: .ready,
                translationAvailable: true,
                publishedAt: now,
                expiresAt: deadline
            )
        )
        controller.textDidChange(nil)
        controller.keyboardView.onAutomaticVoiceActionChanged?(.improve)
        controller.keyboardView.onMicrophoneRequested?()
        #expect(harness.savedCommands.map(\.action) == [.improve])

        harness.savedCommands.removeAll()
        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                requestID: UUID(),
                phase: .ready,
                translationAvailable: true,
                publishedAt: now,
                expiresAt: deadline
            )
        )
        controller.textDidChange(nil)
        controller.keyboardView.onAutomaticVoiceActionChanged?(
            .translateAndImprove
        )
        controller.keyboardView.onMicrophoneRequested?()
        #expect(
            harness.savedCommands.map(\.action) == [.translateAndImprove]
        )

        harness.savedCommands.removeAll()
        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                requestID: UUID(),
                phase: .ready,
                translationAvailable: false,
                publishedAt: now,
                expiresAt: deadline
            )
        )
        controller.textDidChange(nil)
        controller.keyboardView.onAutomaticVoiceActionChanged?(.translate)
        #expect(harness.savedCommands.isEmpty)
        #expect(
            harness.openedURLs == [
                URL(string: "holdtype://settings/translation")!,
            ]
        )
    }

    @Test func activeAttemptKeepsItsAutoModeAndLaterSelectionAppliesNext()
        throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let deadline = now.addingTimeInterval(60)
        let sessionID = UUID()
        let harness = KeyboardControllerHarness(
            now: now,
            dictationState: try #require(
                KeyboardDictationStateRecord(
                    sessionID: sessionID,
                    phase: .ready,
                    translationAvailable: true,
                    publishedAt: now,
                    expiresAt: deadline
                )
            )
        )
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        controller.keyboardView.onAutomaticVoiceActionChanged?(.translate)
        controller.keyboardView.onMicrophoneRequested?()
        let firstStart = try #require(harness.savedCommands.first)
        #expect(firstStart.action == .translate)

        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                sessionID: sessionID,
                attemptID: firstStart.attemptID,
                requestID: firstStart.requestID,
                sourceDocumentID: firstStart.sourceDocumentID,
                phase: .listening,
                translationAvailable: true,
                publishedAt: now,
                expiresAt: deadline
            )
        )
        controller.textDidChange(nil)
        controller.keyboardView.onAutomaticVoiceActionChanged?(.improve)

        #expect(harness.savedCommands.map(\.action) == [.translate])

        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                sessionID: sessionID,
                phase: .ready,
                translationAvailable: true,
                publishedAt: now,
                expiresAt: deadline
            )
        )
        controller.textDidChange(nil)
        controller.keyboardView.onMicrophoneRequested?()

        #expect(harness.savedCommands.map(\.action) == [.translate, .improve])
    }

    @Test func hostContextLossSuppressesAutomaticInsertion() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let requestID = UUID()
        let deadline = now.addingTimeInterval(60)
        let harness = KeyboardControllerHarness(
            now: now,
            dictationState: try #require(
                KeyboardDictationStateRecord(
                    requestID: requestID,
                    phase: .ready,
                    publishedAt: now,
                    expiresAt: deadline
                )
            )
        )
        let controller = harness.makeController()
        controller.loadViewIfNeeded()
        controller.keyboardView.onMicrophoneRequested?()
        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                requestID: requestID,
                phase: .listening,
                publishedAt: now,
                expiresAt: deadline
            )
        )
        controller.textDidChange(nil)
        harness.proxy.documentIdentifier = UUID()
        controller.textWillChange(nil)

        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                requestID: requestID,
                phase: .resultReady,
                result: "Latest fallback text",
                publishedAt: now,
                expiresAt: deadline
            )
        )
        controller.textDidChange(nil)

        #expect(harness.proxy.insertedTexts.isEmpty)
        #expect(statusText(in: controller.view) == "Ready")
    }

    @Test func resultFromAnotherRequestNeverInserts() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let requestID = UUID()
        let deadline = now.addingTimeInterval(60)
        let harness = KeyboardControllerHarness(
            now: now,
            dictationState: try #require(
                KeyboardDictationStateRecord(
                    requestID: requestID,
                    phase: .ready,
                    publishedAt: now,
                    expiresAt: deadline
                )
            )
        )
        let controller = harness.makeController()
        controller.loadViewIfNeeded()
        controller.keyboardView.onMicrophoneRequested?()

        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                requestID: UUID(),
                phase: .resultReady,
                result: "Stale result",
                publishedAt: now,
                expiresAt: deadline
            )
        )
        controller.textDidChange(nil)

        #expect(harness.proxy.insertedTexts.isEmpty)
        #expect(statusText(in: controller.view) == "Ready")
    }

    @Test func recreatedExtensionReconnectsByDurableAttemptAndDocument() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let requestID = UUID()
        let deadline = now.addingTimeInterval(60)
        let harness = KeyboardControllerHarness(
            now: now,
            dictationState: try #require(
                KeyboardDictationStateRecord(
                    requestID: requestID,
                    phase: .ready,
                    publishedAt: now,
                    expiresAt: deadline
                )
            )
        )
        let controller = harness.makeController()
        controller.loadViewIfNeeded()
        controller.keyboardView.onMicrophoneRequested?()
        controller.beginAppearanceTransition(false, animated: false)
        controller.endAppearanceTransition()
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()

        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                requestID: requestID,
                phase: .resultReady,
                result: "Latest fallback text",
                publishedAt: now,
                expiresAt: deadline
            )
        )
        controller.textDidChange(nil)

        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                requestID: requestID,
                deliveryClaimID: harness.deliveryClaimID,
                phase: .resultReady,
                result: "Latest fallback text",
                publishedAt: now,
                expiresAt: deadline
            )
        )
        controller.textDidChange(nil)

        #expect(harness.proxy.insertedTexts == ["Latest fallback text"])
        #expect(statusText(in: controller.view) == "Ready")
    }

    @Test func recreatedExtensionNeverReplaysAnotherProcessDeliveryClaim()
        throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let documentID = UUID()
        let grantedToPreviousProcess = UUID()
        let harness = KeyboardControllerHarness(
            now: now,
            dictationState: try #require(
                KeyboardDictationStateRecord(
                    sessionID: UUID(),
                    attemptID: UUID(),
                    requestID: UUID(),
                    sourceDocumentID: documentID,
                    deliveryClaimID: grantedToPreviousProcess,
                    phase: .resultReady,
                    result: "Uncertain previous insertion",
                    publishedAt: now,
                    expiresAt: now.addingTimeInterval(60)
                )
            ),
            requestID: documentID
        )

        let recreatedController = harness.makeController()
        recreatedController.loadViewIfNeeded()
        recreatedController.textDidChange(nil)

        #expect(harness.proxy.insertedTexts.isEmpty)
        #expect(harness.savedCommands.isEmpty)
        #expect(statusText(in: recreatedController.view) == "Ready")
    }

    @Test func newControllerReconnectsToListeningAndFinishesTheSameAttempt()
        throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let sessionID = UUID()
        let attemptID = UUID()
        let requestID = UUID()
        let documentID = UUID()
        let state = try #require(
            KeyboardDictationStateRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: requestID,
                sourceDocumentID: documentID,
                phase: .listening,
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            )
        )
        let harness = KeyboardControllerHarness(
            now: now,
            dictationState: state,
            requestID: documentID
        )

        let recreatedController = harness.makeController()
        recreatedController.loadViewIfNeeded()

        #expect(statusText(in: recreatedController.view) == "Listening…")
        recreatedController.keyboardView.onMicrophoneRequested?()
        let finish = try #require(harness.savedCommands.last)
        #expect(finish.kind == .finish)
        #expect(finish.sessionID == sessionID)
        #expect(finish.attemptID == attemptID)
        #expect(finish.requestID == requestID)
        #expect(finish.sourceDocumentID == documentID)
    }

    @Test func recreatedExtensionUsesConsumedHandoffWhenDocumentIsUnavailable()
        throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let sessionID = UUID()
        let attemptID = UUID()
        let requestID = UUID()
        let sourceDocumentID = UUID()
        let state = try #require(
            KeyboardDictationStateRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: requestID,
                sourceDocumentID: sourceDocumentID,
                phase: .listening,
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            )
        )
        let harness = KeyboardControllerHarness(
            now: now,
            dictationState: state,
            requestID: UUID(),
            consumedHandoffIntent: try #require(
                consumedHandoffIntent(
                    requestID: requestID,
                    sourceDocumentID: sourceDocumentID,
                    now: now
                )
            )
        )
        let recreatedController = harness.makeController()
        recreatedController.loadViewIfNeeded()

        #expect(statusText(in: recreatedController.view) == "Listening…")
        recreatedController.keyboardView.onMicrophoneRequested?()
        let finish = try #require(harness.savedCommands.last)
        #expect(finish.kind == .finish)
        #expect(finish.sessionID == sessionID)
        #expect(finish.attemptID == attemptID)
        #expect(finish.requestID == requestID)
        #expect(finish.sourceDocumentID == sourceDocumentID)
    }

    @Test func consumedHandoffAnchorsReturnedDocumentAndInsertsOnce() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let requestID = UUID()
        let sourceDocumentID = UUID()
        let returnedDocumentID = UUID()
        let harness = KeyboardControllerHarness(
            now: now,
            dictationState: try #require(
                KeyboardDictationStateRecord(
                    sessionID: UUID(),
                    attemptID: UUID(),
                    requestID: requestID,
                    sourceDocumentID: sourceDocumentID,
                    phase: .resultReady,
                    result: "Preserved in Latest",
                    publishedAt: now,
                    expiresAt: now.addingTimeInterval(60)
                )
            ),
            requestID: returnedDocumentID,
            consumedHandoffIntent: try #require(
                consumedHandoffIntent(
                    requestID: requestID,
                    sourceDocumentID: sourceDocumentID,
                    now: now
                )
            )
        )
        let recreatedController = harness.makeController()
        recreatedController.loadViewIfNeeded()

        let claim = try #require(harness.savedCommands.last)
        #expect(claim.kind == .claimDelivery)
        #expect(harness.proxy.insertedTexts.isEmpty)

        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                sessionID: claim.sessionID,
                attemptID: claim.attemptID,
                requestID: requestID,
                sourceDocumentID: sourceDocumentID,
                deliveryClaimID: harness.deliveryClaimID,
                phase: .resultReady,
                result: "Returned document result",
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            )
        )
        recreatedController.textDidChange(nil)

        #expect(harness.proxy.insertedTexts == ["Returned document result"])
        #expect(harness.savedCommands.last?.kind == .acknowledgeDelivery)
    }

    @Test func documentChangeAfterReturnedAnchorPreventsInsertion() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let sessionID = UUID()
        let attemptID = UUID()
        let requestID = UUID()
        let sourceDocumentID = UUID()
        let returnedDocumentID = UUID()
        let harness = KeyboardControllerHarness(
            now: now,
            dictationState: try #require(
                KeyboardDictationStateRecord(
                    sessionID: sessionID,
                    attemptID: attemptID,
                    requestID: requestID,
                    sourceDocumentID: sourceDocumentID,
                    phase: .listening,
                    publishedAt: now,
                    expiresAt: now.addingTimeInterval(60)
                )
            ),
            requestID: returnedDocumentID,
            consumedHandoffIntent: try #require(
                consumedHandoffIntent(
                    requestID: requestID,
                    sourceDocumentID: sourceDocumentID,
                    now: now
                )
            )
        )
        let recreatedController = harness.makeController()
        recreatedController.loadViewIfNeeded()

        harness.currentDocumentIdentifier = UUID()
        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: requestID,
                sourceDocumentID: sourceDocumentID,
                phase: .resultReady,
                result: "Wrong document result",
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            )
        )
        recreatedController.textDidChange(nil)

        #expect(harness.proxy.insertedTexts.isEmpty)
        #expect(harness.savedCommands.isEmpty)
    }

    @Test
    func temporarilyMissingDocumentRetriesBeforeClaimingAndInserting()
        throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let sessionID = UUID()
        let attemptID = UUID()
        let requestID = UUID()
        let documentID = UUID()
        let harness = KeyboardControllerHarness(
            now: now,
            dictationState: try #require(
                KeyboardDictationStateRecord(
                    sessionID: sessionID,
                    attemptID: attemptID,
                    requestID: requestID,
                    sourceDocumentID: documentID,
                    phase: .resultReady,
                    result: "Recovered document result",
                    publishedAt: now,
                    expiresAt: now.addingTimeInterval(60)
                )
            ),
            requestID: documentID,
            consumedHandoffIntent: try #require(
                consumedHandoffIntent(
                    requestID: requestID,
                    sourceDocumentID: documentID,
                    now: now
                )
            )
        )
        harness.currentDocumentIdentifier = nil
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        #expect(harness.savedCommands.isEmpty)
        #expect(
            harness.scheduledDocumentIdentifierRetryActions.count == 1
        )

        harness.currentDocumentIdentifier = documentID
        harness.scheduledDocumentIdentifierRetryActions.removeFirst()()

        let claim = try #require(harness.savedCommands.last)
        #expect(claim.kind == .claimDelivery)
        #expect(claim.deliveryClaimID == harness.deliveryClaimID)
        #expect(harness.proxy.insertedTexts.isEmpty)

        harness.dictationState = try #require(
            KeyboardDictationStateRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: requestID,
                sourceDocumentID: documentID,
                deliveryClaimID: harness.deliveryClaimID,
                phase: .resultReady,
                result: "Recovered document result",
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            )
        )
        controller.textDidChange(nil)

        #expect(harness.proxy.insertedTexts == ["Recovered document result"])
        #expect(harness.savedCommands.last?.kind == .acknowledgeDelivery)
    }

    @Test func changedOrMissingDocumentCannotReconnectOrAutoInsert() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let sessionID = UUID()
        let attemptID = UUID()
        let requestID = UUID()
        let originalDocumentID = UUID()
        let currentDocumentID = UUID()
        let changedDocumentHarness = KeyboardControllerHarness(
            now: now,
            dictationState: try #require(
                KeyboardDictationStateRecord(
                    sessionID: sessionID,
                    attemptID: attemptID,
                    requestID: requestID,
                    sourceDocumentID: originalDocumentID,
                    phase: .listening,
                    publishedAt: now,
                    expiresAt: now.addingTimeInterval(60)
                )
            ),
            requestID: currentDocumentID
        )
        let changedDocumentController = changedDocumentHarness.makeController()
        changedDocumentController.loadViewIfNeeded()

        #expect(statusText(in: changedDocumentController.view) == "Ready")
        changedDocumentController.keyboardView.onMicrophoneRequested?()
        #expect(changedDocumentHarness.savedCommands.isEmpty)
        #expect(changedDocumentHarness.savedHandoffIntents.count == 1)

        let missingDocumentHarness = KeyboardControllerHarness(
            now: now,
            dictationState: try #require(
                KeyboardDictationStateRecord(
                    sessionID: UUID(),
                    attemptID: UUID(),
                    requestID: UUID(),
                    sourceDocumentID: nil,
                    phase: .resultReady,
                    result: "Preserved in Latest",
                    publishedAt: now,
                    expiresAt: now.addingTimeInterval(60)
                )
            )
        )
        let missingDocumentController = missingDocumentHarness.makeController()
        missingDocumentController.loadViewIfNeeded()

        #expect(missingDocumentHarness.proxy.insertedTexts.isEmpty)
        #expect(statusText(in: missingDocumentController.view) == "Ready")
    }

    @Test func expiredReconnectionReturnsToReadyAndNextTapStartsHandoff()
        throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let documentID = UUID()
        let harness = KeyboardControllerHarness(
            now: now,
            dictationState: try #require(
                KeyboardDictationStateRecord(
                    sessionID: UUID(),
                    attemptID: UUID(),
                    requestID: UUID(),
                    sourceDocumentID: documentID,
                    phase: .processing,
                    publishedAt: now,
                    expiresAt: now.addingTimeInterval(60)
                )
            ),
            requestID: documentID
        )
        let controller = harness.makeController()
        controller.loadViewIfNeeded()
        #expect(statusText(in: controller.view) == "Processing…")

        let expire = try #require(harness.scheduledExpiryActions.last)
        expire()
        #expect(statusText(in: controller.view) == "Ready")

        controller.keyboardView.onMicrophoneRequested?()
        #expect(harness.savedHandoffIntents.count == 1)
        #expect(statusText(in: controller.view) == "Opening HoldType…")
    }

    @Test func restrictedModeKeepsEditing() throws {
        let restricted = KeyboardControllerHarness(fullAccessOverride: false)
        let restrictedController = restricted.makeController()
        restrictedController.loadViewIfNeeded()
        restrictedController.keyboardView.onMicrophoneRequested?()
        restrictedController.keyboardView.onQuickInsertRequested?(".")
        restrictedController.keyboardView.onSpaceRequested?()
        restrictedController.keyboardView.onDeleteStarted?()
        restrictedController.keyboardView.onDeleteStopped?()
        restrictedController.keyboardView.onReturnRequested?()

        #expect(
            statusText(in: restrictedController.view)
                == "Full Access required"
        )
        #expect(restricted.openedURLs == [
            URL(string: "holdtype://settings/fullAccess")!,
        ])
        #expect(restricted.savedHandoffIntents.isEmpty)
        #expect(restricted.savedCommands.isEmpty)
        #expect(restricted.proxy.insertedTexts == [".", " ", "\n"])
        #expect(restricted.proxy.deleteBackwardCount == 1)
    }

    @Test func handoffLaunchFailureRestoresRetryableIndicator() async throws {
        let requestID = UUID()
        let harness = KeyboardControllerHarness(
            requestID: requestID,
            openContainingAppSucceeds: false
        )
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        controller.keyboardView.onMicrophoneRequested?()
        await Task.yield()

        #expect(harness.savedHandoffIntents.map(\.requestID) == [requestID])
        #expect(statusText(in: controller.view) == "Couldn’t open HoldType")
        let microphone = try button(
            "keyboard.brand-stage.voice",
            in: controller.view
        )
        #expect(microphone.isEnabled)
    }

    @Test func coldTranslationSelectionIsCarriedByTheHandoffIntent() throws {
        let requestID = UUID()
        let harness = KeyboardControllerHarness(requestID: requestID)
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        controller.keyboardView.onAutomaticVoiceActionChanged?(.translate)
        controller.keyboardView.onMicrophoneRequested?()

        #expect(harness.savedHandoffIntents.map(\.action) == [.translate])
        #expect(harness.openedURLs.count == 1)
    }
}

private func consumedHandoffIntent(
    requestID: UUID,
    sourceDocumentID: UUID?,
    now: Date
) -> KeyboardHandoffIntentRecord? {
    KeyboardHandoffIntentRecord(
        requestID: requestID,
        sourceDocumentID: sourceDocumentID,
        action: .standard,
        issuedAt: now,
        expiresAt: now.addingTimeInterval(10)
    )?.consuming(at: now.addingTimeInterval(1))
}

@MainActor
private final class KeyboardControllerHarness {
    var now: Date
    var snapshot: KeyboardBridgeSnapshot?
    var dictationState: KeyboardDictationStateRecord?
    var consumedHandoffIntent: KeyboardHandoffIntentRecord?
    let proxy: KeyboardDocumentProxySpy
    let inputModeSwitchKeyOverride: Bool?
    let fullAccessOverride: Bool
    let requestID: UUID
    let deliveryClaimID: UUID
    let openContainingAppSucceeds: Bool
    var savedCommands: [KeyboardDictationCommandRecord] = []
    var savedHandoffIntents: [KeyboardHandoffIntentRecord] = []
    var openedURLs: [URL] = []
    var scheduledExpiryDates: [Date] = []
    var scheduledExpiryActions: [@MainActor () -> Void] = []
    var currentDocumentIdentifier: UUID?
    var documentIdentifierOwnerIDs: [ObjectIdentifier] = []
    var scheduledDocumentIdentifierRetryActions:
        [@MainActor () -> Void] = []
    var scheduledDeliveryObservationActions:
        [@MainActor () -> Void] = []

    init(
        now: Date = Date(timeIntervalSince1970: 1_750_000_000),
        snapshot: KeyboardBridgeSnapshot? = nil,
        dictationState: KeyboardDictationStateRecord? = nil,
        inputModeSwitchKeyOverride: Bool? = true,
        fullAccessOverride: Bool = true,
        requestID: UUID? = nil,
        consumedHandoffIntent: KeyboardHandoffIntentRecord? = nil,
        openContainingAppSucceeds: Bool = true
    ) {
        self.now = now
        self.snapshot = snapshot
        self.dictationState = dictationState
        self.inputModeSwitchKeyOverride = inputModeSwitchKeyOverride
        self.fullAccessOverride = fullAccessOverride
        self.consumedHandoffIntent = consumedHandoffIntent
        let resolvedRequestID = requestID
            ?? dictationState?.sessionID
            ?? UUID()
        self.requestID = resolvedRequestID
        currentDocumentIdentifier = resolvedRequestID
        deliveryClaimID = UUID()
        proxy = KeyboardDocumentProxySpy(
            documentIdentifier: resolvedRequestID
        )
        self.openContainingAppSucceeds = openContainingAppSucceeds
    }

    func makeController() -> KeyboardViewController {
        KeyboardViewController(
            dependencies: KeyboardViewControllerDependencies(
                loadSnapshot: { [self] in snapshot },
                loadDictationState: { [self] in dictationState },
                loadConsumedHandoffIntent: { [self] in
                    consumedHandoffIntent
                },
                saveDictationCommand: { [self] command in
                    savedCommands.append(command)
                },
                saveHandoffIntent: { [self] intent in
                    savedHandoffIntents.append(intent)
                },
                observeDictationState: { _ in nil },
                now: { [self] in now },
                makeRequestID: { [self] in requestID },
                makeAttemptID: { [self] in requestID },
                makeDeliveryClaimID: { [self] in deliveryClaimID },
                documentProxyOverride: proxy,
                loadDocumentIdentifier: { [self] documentProxy in
                    documentIdentifierOwnerIDs.append(
                        ObjectIdentifier(documentProxy as AnyObject)
                    )
                    return currentDocumentIdentifier
                },
                inputModeSwitchKeyOverride: inputModeSwitchKeyOverride,
                fullAccessOverride: fullAccessOverride,
                scheduleLatestExpiry: { [self] date, action in
                    scheduledExpiryDates.append(date)
                    scheduledExpiryActions.append(action)
                    return nil
                },
                scheduleDocumentIdentifierRetry: { [self] action in
                    scheduledDocumentIdentifierRetryActions.append(action)
                    return nil
                },
                scheduleDeliveryObservation: { [self] action in
                    scheduledDeliveryObservationActions.append(action)
                    return nil
                },
                openContainingAppOverride: { [self] url, completion in
                    openedURLs.append(url)
                    completion(openContainingAppSucceeds)
                },
                recordDiagnostic: { _ in }
            )
        )
    }
}

@MainActor
private final class KeyboardObjectiveCDocumentIdentifierSpy: NSObject {
    @objc dynamic let documentIdentifier: NSUUID?

    init(identifier: NSUUID?) {
        documentIdentifier = identifier
        super.init()
    }
}

@MainActor
final class KeyboardOpenURLResponderSpy: UIResponder {
    private(set) var openedURLs: [URL] = []
    private let chainedResponder: UIResponder?

    init(nextResponder: UIResponder? = nil) {
        chainedResponder = nextResponder
        super.init()
    }

    override var next: UIResponder? {
        chainedResponder
    }

    @objc(openURL:options:completionHandler:)
    func openURL(
        _ url: URL,
        options: NSDictionary,
        completionHandler: ((Bool) -> Void)?
    ) {
        openedURLs.append(url)
        completionHandler?(true)
    }
}

@MainActor
private final class KeyboardDocumentProxySpy: NSObject, UITextDocumentProxy {
    var insertedTexts: [String] = []
    var deleteBackwardCount = 0
    var cursorOffsets: [Int] = []
    var hasText = false
    var returnKeyType: UIReturnKeyType = .default
    var enablesReturnKeyAutomatically = false
    var documentContextBeforeInput: String?
    var documentContextAfterInput: String?
    var selectedText: String?
    var documentInputMode: UITextInputMode?
    var documentIdentifier: UUID

    init(documentIdentifier: UUID = UUID()) {
        self.documentIdentifier = documentIdentifier
    }

    func insertText(_ text: String) {
        insertedTexts.append(text)
    }

    func deleteBackward() {
        deleteBackwardCount += 1
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        cursorOffsets.append(offset)
    }

    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}

    func unmarkText() {}
}

private extension KeyboardDictationStateRecord {
    init?(
        requestID: UUID,
        deliveryClaimID: UUID? = nil,
        phase: KeyboardDictationStatePhase,
        translationAvailable: Bool = false,
        result: String? = nil,
        publishedAt: Date,
        expiresAt: Date
    ) {
        let hasAttempt = phase != .ready
        self.init(
            sessionID: requestID,
            attemptID: hasAttempt ? requestID : nil,
            requestID: hasAttempt ? requestID : nil,
            sourceDocumentID: hasAttempt ? requestID : nil,
            deliveryClaimID: deliveryClaimID,
            phase: phase,
            translationAvailable: translationAvailable,
            result: result,
            publishedAt: publishedAt,
            expiresAt: expiresAt
        )
    }
}

@MainActor
private func button(
    _ identifier: String,
    in root: UIView
) throws -> UIButton {
    try #require(descendant(UIButton.self, identifier: identifier, in: root))
}

@MainActor
private func statusText(in root: UIView) -> String? {
    descendant(
        UIView.self,
        identifier: "keyboard.brand-stage.stage",
        in: root
    )?.accessibilityValue
}

@MainActor
private func descendant<View: UIView>(
    _ type: View.Type,
    identifier: String,
    in root: UIView
) -> View? {
    if let match = root as? View,
       root.accessibilityIdentifier == identifier {
        return match
    }

    for subview in root.subviews {
        if let match = descendant(
            type,
            identifier: identifier,
            in: subview
        ) {
            return match
        }
    }
    return nil
}
