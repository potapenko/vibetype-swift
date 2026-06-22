//
//  SpecialClipboardHotkeyServiceTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/22/26.
//

import Foundation
import Testing
@testable import vibetype

@MainActor
struct SpecialClipboardHotkeyServiceTests {

    @Test func coordinatorRegistersShortcutWhenAppClipboardIsEnabled() async throws {
        let (settingsStore, defaults, suiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        settingsStore.save(makeSettings(saveTranscriptsToAppClipboard: true))

        let hotkeyService = FakeSpecialClipboardHotkeyService()
        let store = FakeCoordinatorTranscriptClipboardStore(initialText: "stored transcript")
        let poster = FakeCoordinatorTextEventPoster()
        let coordinator = makeCoordinator(
            hotkeyService: hotkeyService,
            settingsStore: settingsStore,
            transcriptClipboardStore: store,
            textEventPoster: poster
        )

        coordinator.start()
        defer { coordinator.stop() }

        #expect(hotkeyService.startCount == 1)
        #expect(hotkeyService.isListening)

        hotkeyService.trigger()

        #expect(try await waitForPostedTexts(from: poster) == ["stored transcript"])
        await yieldUntil { coordinator.lastStatusText != nil }
        #expect(coordinator.lastStatusText == "Inserted from VibeType Clipboard.")
    }

    @Test func coordinatorDoesNotRegisterShortcutWhenAppClipboardIsDisabled() async {
        let (settingsStore, defaults, suiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        settingsStore.save(makeSettings(saveTranscriptsToAppClipboard: false))

        let hotkeyService = FakeSpecialClipboardHotkeyService()
        let store = FakeCoordinatorTranscriptClipboardStore(initialText: "stored transcript")
        let poster = FakeCoordinatorTextEventPoster()
        let coordinator = makeCoordinator(
            hotkeyService: hotkeyService,
            settingsStore: settingsStore,
            transcriptClipboardStore: store,
            textEventPoster: poster
        )

        coordinator.start()
        defer { coordinator.stop() }
        await yieldUntil { await store.currentText() == nil }

        #expect(hotkeyService.startCount == 0)
        #expect(hotkeyService.stopCount >= 1)
        #expect(hotkeyService.isListening == false)
        #expect(await store.currentText() == nil)
        #expect(await poster.postedTexts().isEmpty)
        #expect(coordinator.lastStatusText == "VibeType Clipboard is disabled.")
    }

    private func makeCoordinator(
        hotkeyService: FakeSpecialClipboardHotkeyService,
        settingsStore: AppSettingsStore,
        transcriptClipboardStore: FakeCoordinatorTranscriptClipboardStore,
        textEventPoster: FakeCoordinatorTextEventPoster
    ) -> SpecialClipboardHotkeyCoordinator {
        SpecialClipboardHotkeyCoordinator(
            hotkeyService: hotkeyService,
            pasteService: SpecialClipboardPasteService(
                transcriptClipboardStore: transcriptClipboardStore,
                accessibilityPermissionService: AccessibilityPermissionService(
                    client: FakeCoordinatorAccessibilityPermissionClient(isTrusted: true)
                ),
                textEventPoster: textEventPoster
            ),
            settingsStore: settingsStore,
            transcriptClipboardStore: transcriptClipboardStore
        )
    }

    private func makeSettingsStore() -> (AppSettingsStore, UserDefaults, String) {
        let suiteName = "vibetype.SpecialClipboardHotkeyServiceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated UserDefaults suite")
            return (AppSettingsStore(userDefaults: .standard), .standard, suiteName)
        }

        defaults.removePersistentDomain(forName: suiteName)
        return (AppSettingsStore(userDefaults: defaults), defaults, suiteName)
    }

    private func makeSettings(saveTranscriptsToAppClipboard: Bool) -> AppSettings {
        var settings = AppSettings.defaults
        settings.saveTranscriptsToAppClipboard = saveTranscriptsToAppClipboard
        return settings
    }

    private func waitForPostedTexts(
        from poster: FakeCoordinatorTextEventPoster,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws -> [String] {
        try await withThrowingTaskGroup(of: [String].self) { group in
            group.addTask {
                await poster.waitForPostedTexts()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw WaitForPostedTextsTimeout()
            }

            guard let result = try await group.next() else {
                return []
            }

            group.cancelAll()
            return result
        }
    }

    private func yieldUntil(_ condition: () async -> Bool) async {
        for _ in 0..<20 {
            if await condition() {
                return
            }

            await Task.yield()
        }
    }
}

private struct WaitForPostedTextsTimeout: Error {}

private final class FakeSpecialClipboardHotkeyService: SpecialClipboardHotkeyListening {
    let shortcut = GlobalHotkeyShortcut.appClipboardPaste

    private var handler: (() -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var isListening = false

    func start(handler: @escaping () -> Void) throws {
        startCount += 1
        isListening = true
        self.handler = handler
    }

    func stop() {
        stopCount += 1
        isListening = false
        handler = nil
    }

    func trigger() {
        handler?()
    }
}

private actor FakeCoordinatorTranscriptClipboardStore: TranscriptClipboardStoring {
    private var text: String?

    init(initialText: String? = nil) {
        self.text = initialText
    }

    func save(_ text: String) async throws {
        self.text = text
    }

    func clear() async {
        text = nil
    }

    func currentText() async -> String? {
        text
    }
}

private final class FakeCoordinatorAccessibilityPermissionClient: AccessibilityPermissionClient {
    private let isTrusted: Bool

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func isProcessTrusted(promptIfNeeded: Bool) -> Bool {
        isTrusted
    }

    func openAccessibilitySettings() -> Bool {
        false
    }
}

private actor FakeCoordinatorTextEventPoster: TextEventPosting {
    private var texts: [String] = []
    private var continuations: [CheckedContinuation<[String], Never>] = []

    func postText(_ text: String) async throws {
        texts.append(text)

        let currentTexts = texts
        let waitingContinuations = continuations
        continuations.removeAll()

        for continuation in waitingContinuations {
            continuation.resume(returning: currentTexts)
        }
    }

    func postedTexts() async -> [String] {
        texts
    }

    func waitForPostedTexts() async -> [String] {
        if !texts.isEmpty {
            return texts
        }

        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}
