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

    @Test func settingsSuccessUsesOnlyThePublicSystemURL() async throws {
        let harness = KeyboardControllerHarness(
            synchronousSettingsResult: true
        )
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        controller.keyboardView.onSettingsRequested?()
        await Task.yield()

        #expect(harness.openedSettingsURLs.map(\.absoluteString) == [
            UIApplication.openSettingsURLString,
        ])
        #expect(statusText(in: controller.view) == "Ready")
        #expect(harness.scheduledStatusReset == nil)
    }

    @Test func settingsFailureShowsBriefStatusThenReturnsToReady() async throws {
        let harness = KeyboardControllerHarness()
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        controller.keyboardView.onSettingsRequested?()

        #expect(harness.openedSettingsURLs.map(\.absoluteString) == [
            UIApplication.openSettingsURLString,
        ])
        let completion = try #require(harness.settingsCompletion)
        completion(false)
        try await eventually {
            statusText(in: controller.view) == "Open Settings"
        }

        #expect(harness.scheduledStatusDuration == 1.6)
        let reset = try #require(harness.scheduledStatusReset)
        reset.perform()

        #expect(statusText(in: controller.view) == "Ready")
    }

    @Test func synchronousSettingsFailureUsesTheSameBriefStatus() async throws {
        let harness = KeyboardControllerHarness(
            synchronousSettingsResult: false
        )
        let controller = harness.makeController()
        controller.loadViewIfNeeded()

        controller.keyboardView.onSettingsRequested?()
        try await eventually {
            statusText(in: controller.view) == "Open Settings"
        }

        #expect(harness.openedSettingsURLs.map(\.absoluteString) == [
            UIApplication.openSettingsURLString,
        ])
        #expect(harness.scheduledStatusDuration == 1.6)
    }
}

@MainActor
private final class KeyboardControllerHarness {
    var now: Date
    var snapshot: KeyboardBridgeSnapshot?
    let proxy = KeyboardDocumentProxySpy()
    let inputModeSwitchKeyOverride: Bool?
    let synchronousSettingsResult: Bool?
    var openedSettingsURLs: [URL] = []
    var settingsCompletion: ((Bool) -> Void)?
    var scheduledStatusDuration: TimeInterval?
    var scheduledStatusReset: DispatchWorkItem?
    var scheduledExpiryDates: [Date] = []
    var scheduledExpiryActions: [@MainActor () -> Void] = []

    init(
        now: Date = Date(timeIntervalSince1970: 1_750_000_000),
        snapshot: KeyboardBridgeSnapshot? = nil,
        inputModeSwitchKeyOverride: Bool? = true,
        synchronousSettingsResult: Bool? = nil
    ) {
        self.now = now
        self.snapshot = snapshot
        self.inputModeSwitchKeyOverride = inputModeSwitchKeyOverride
        self.synchronousSettingsResult = synchronousSettingsResult
    }

    func makeController() -> KeyboardViewController {
        KeyboardViewController(
            dependencies: KeyboardViewControllerDependencies(
                loadSnapshot: { [self] in snapshot },
                now: { [self] in now },
                documentProxyOverride: proxy,
                settingsOpener: { [self] url, completion in
                    openedSettingsURLs.append(url)
                    if let synchronousSettingsResult {
                        completion(synchronousSettingsResult)
                    } else {
                        settingsCompletion = completion
                    }
                },
                inputModeSwitchKeyOverride: inputModeSwitchKeyOverride,
                scheduleStatusReset: { [self] duration, workItem in
                    scheduledStatusDuration = duration
                    scheduledStatusReset = workItem
                },
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
        UILabel.self,
        identifier: "keyboard.brand-stage.status",
        in: root
    )?.text
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

private enum KeyboardControllerTestError: Error {
    case timedOut
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else {
            throw KeyboardControllerTestError.timedOut
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}
