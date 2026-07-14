import Foundation
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct KeyboardViewControllerTests {
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

    @Test func expiredLatestTapDoesNotInsertAndDisablesLatest() throws {
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let latest = try KeyboardBridgeItem.latest(
            resultID: UUID(),
            text: "Expired at tap",
            createdAt: createdAt
        )
        let harness = KeyboardControllerHarness(
            now: latest.expiresAt.addingTimeInterval(-0.001),
            snapshot: try KeyboardBridgeSnapshot(
                revision: 1,
                publishedAt: createdAt,
                latest: latest
            )
        )
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        harness.now = latest.expiresAt
        controller.keyboardView.onLatestRequested?()

        let latestButton = try button(
            "keyboard.brand-stage.latest",
            in: controller.view
        )
        #expect(!latestButton.isEnabled)
        #expect(harness.proxy.insertedTexts.isEmpty)
    }

    @Test func scheduledExpiryDisablesOnlyTheCurrentLatest() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let latest = try KeyboardBridgeItem.latest(
            resultID: UUID(),
            text: "Soon unavailable",
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

        #expect(harness.scheduledExpiryDates == [latest.expiresAt])
        let expiryAction = try #require(harness.scheduledExpiryActions.first)
        expiryAction()

        let latestButton = try button(
            "keyboard.brand-stage.latest",
            in: controller.view
        )
        #expect(!latestButton.isEnabled)
        controller.keyboardView.onLatestRequested?()
        #expect(harness.proxy.insertedTexts.isEmpty)
    }

    @Test func staleExpiryCannotClearAReplacementLatest() throws {
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
        let staleExpiry = try #require(
            harness.scheduledExpiryActions.first
        )

        harness.snapshot = try KeyboardBridgeSnapshot(
            revision: 2,
            publishedAt: now,
            latest: replacement
        )
        controller.textDidChange(nil)
        staleExpiry()
        controller.keyboardView.onLatestRequested?()

        let latestButton = try button(
            "keyboard.brand-stage.latest",
            in: controller.view
        )
        #expect(latestButton.isEnabled)
        #expect(harness.proxy.insertedTexts == ["Replacement"])
    }

    @Test func editingAndCursorCallbacksRouteToTheDocumentProxy() throws {
        let harness = KeyboardControllerHarness()
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        controller.keyboardView.onPunctuationRequested?("?")
        controller.keyboardView.onSpaceRequested?()
        controller.keyboardView.onReturnRequested?()
        controller.keyboardView.onCursorStepRequested?(-1)
        controller.keyboardView.onSpaceCursorGesture?(.began, 0)
        controller.keyboardView.onSpaceCursorGesture?(.changed, 13)
        controller.keyboardView.onSpaceCursorGesture?(.ended, 13)
        controller.keyboardView.onDeleteStarted?()
        controller.keyboardView.onDeleteStopped?()

        #expect(harness.proxy.insertedTexts == ["?", " ", "\n"])
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

    @Test func missingSessionShowsCompleteRecoveryWithoutADeadSettingsAction()
        throws {
        let harness = KeyboardControllerHarness()
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        #expect(controller.hasDictationKey)
        #expect(statusText(in: controller.view) == "Session not running")
        #expect(
            descendant(
                UIButton.self,
                identifier: "keyboard.brand-stage.settings",
                in: controller.view
            ) == nil
        )
        #expect(
            descendant(
                UILabel.self,
                identifier: "keyboard.brand-stage.recovery-detail",
                in: controller.view
            )?.text
                == "Open HoldType → Voice → Keyboard Dictation Session → Start Keyboard Session. Then return here."
        )
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
        controller.textDidChange(nil)

        #expect(harness.proxy.insertedTexts == [
            "Processed keyboard text",
        ])
        #expect(statusText(in: controller.view) == "Session not running")
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
        #expect(statusText(in: controller.view) == "Session not running")
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
        #expect(statusText(in: controller.view) == "Session not running")
    }

    @Test func extensionLifetimeLossSuppressesAutomaticInsertion() throws {
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

        #expect(harness.proxy.insertedTexts.isEmpty)
        #expect(statusText(in: controller.view) == "Session not running")
    }

    @Test func cancelDoesNotInsertAndRestrictedModeKeepsEditing() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let requestID = UUID()
        let harness = KeyboardControllerHarness(
            now: now,
            dictationState: try #require(
                KeyboardDictationStateRecord(
                    requestID: requestID,
                    phase: .ready,
                    publishedAt: now,
                    expiresAt: now.addingTimeInterval(60)
                )
            )
        )
        let controller = harness.makeController()
        controller.loadViewIfNeeded()
        controller.keyboardView.onMicrophoneRequested?()
        controller.keyboardView.onCancelRequested?()

        #expect(harness.savedCommands.map(\.kind) == [.start, .cancel])
        #expect(harness.proxy.insertedTexts.isEmpty)

        let restricted = KeyboardControllerHarness(fullAccessOverride: false)
        let restrictedController = restricted.makeController()
        restrictedController.loadViewIfNeeded()
        restrictedController.keyboardView.onPunctuationRequested?(".")
        restrictedController.keyboardView.onSpaceRequested?()
        restrictedController.keyboardView.onDeleteStarted?()
        restrictedController.keyboardView.onDeleteStopped?()
        restrictedController.keyboardView.onReturnRequested?()

        #expect(
            statusText(in: restrictedController.view)
                == "Full Access required"
        )
        #expect(
            descendant(
                UILabel.self,
                identifier: "keyboard.brand-stage.recovery-detail",
                in: restrictedController.view
            )?.text?.contains("iPhone Settings → General → Keyboard") == true
        )
        #expect(
            descendant(
                UILabel.self,
                identifier: "keyboard.brand-stage.recovery-shortcut",
                in: restrictedController.view
            )?.text == "Shortcut: hold 🌐 → Keyboard Settings."
        )
        #expect(restricted.proxy.insertedTexts == [".", " ", "\n"])
        #expect(restricted.proxy.deleteBackwardCount == 1)
    }
}

@MainActor
private final class KeyboardControllerHarness {
    var now: Date
    var snapshot: KeyboardBridgeSnapshot?
    var dictationState: KeyboardDictationStateRecord?
    let proxy = KeyboardDocumentProxySpy()
    let inputModeSwitchKeyOverride: Bool?
    let fullAccessOverride: Bool
    var savedCommands: [KeyboardDictationCommandRecord] = []
    var scheduledExpiryDates: [Date] = []
    var scheduledExpiryActions: [@MainActor () -> Void] = []

    init(
        now: Date = Date(timeIntervalSince1970: 1_750_000_000),
        snapshot: KeyboardBridgeSnapshot? = nil,
        dictationState: KeyboardDictationStateRecord? = nil,
        inputModeSwitchKeyOverride: Bool? = true,
        fullAccessOverride: Bool = true
    ) {
        self.now = now
        self.snapshot = snapshot
        self.dictationState = dictationState
        self.inputModeSwitchKeyOverride = inputModeSwitchKeyOverride
        self.fullAccessOverride = fullAccessOverride
    }

    func makeController() -> KeyboardViewController {
        KeyboardViewController(
            dependencies: KeyboardViewControllerDependencies(
                loadSnapshot: { [self] in snapshot },
                loadDictationState: { [self] in dictationState },
                saveDictationCommand: { [self] command in
                    savedCommands.append(command)
                },
                observeDictationState: { _ in nil },
                now: { [self] in now },
                documentProxyOverride: proxy,
                inputModeSwitchKeyOverride: inputModeSwitchKeyOverride,
                fullAccessOverride: fullAccessOverride,
                scheduleLatestExpiry: { [self] date, action in
                    scheduledExpiryDates.append(date)
                    scheduledExpiryActions.append(action)
                    return nil
                }
            )
        )
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
    let documentIdentifier = UUID()

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
