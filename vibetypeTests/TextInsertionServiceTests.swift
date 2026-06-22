//
//  TextInsertionServiceTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/21/26.
//

import Foundation
import Testing
@testable import vibetype

struct TextInsertionServiceTests {

    @Test func enabledOutputSavesTranscriptToAppClipboard() async throws {
        let store = FakeTranscriptClipboardStore()
        let service = TextInsertionService(transcriptClipboardStore: store)

        let result = try await service.deliver(
            "hello active app",
            settings: makeSettings(saveTranscriptsToAppClipboard: true)
        )

        #expect(result == .savedToAppClipboard)
        #expect(result.statusText.contains("VibeType Clipboard"))
        #expect(await store.currentText() == "hello active app")
        #expect(await store.savedTexts() == ["hello active app"])
        #expect(await store.clearCount() == 0)
    }

    @Test func disabledOutputClearsAppClipboardAndSkipsSystemClipboardFallback() async throws {
        let store = FakeTranscriptClipboardStore(initialText: "previous transcript")
        let service = TextInsertionService(transcriptClipboardStore: store)

        let result = try await service.deliver(
            "unused text",
            settings: makeSettings(saveTranscriptsToAppClipboard: false)
        )

        #expect(result == .skipped(reason: .appClipboardDisabled))
        #expect(result.statusText == "VibeType Clipboard is disabled.")
        #expect(await store.currentText() == nil)
        #expect(await store.savedTexts().isEmpty)
        #expect(await store.clearCount() == 1)
    }

    @Test func pasteShortcutInsertsCurrentAppClipboardTextWhenTrustedAndEnabled() async {
        let store = FakeTranscriptClipboardStore(initialText: "stored transcript")
        let poster = FakeTextEventPoster()
        let service = makePasteService(
            store: store,
            accessibilityIsTrusted: true,
            textEventPoster: poster
        )

        let result = await service.pasteFromAppClipboard(
            settings: makeSettings(saveTranscriptsToAppClipboard: true)
        )

        #expect(result == .inserted)
        #expect(result.statusText == "Inserted from VibeType Clipboard.")
        #expect(await poster.postedTexts() == ["stored transcript"])
    }

    @Test func pasteShortcutSkipsWhenAppClipboardSettingIsDisabled() async {
        let store = FakeTranscriptClipboardStore(initialText: "stored transcript")
        let poster = FakeTextEventPoster()
        let service = makePasteService(
            store: store,
            accessibilityIsTrusted: true,
            textEventPoster: poster
        )

        let result = await service.pasteFromAppClipboard(
            settings: makeSettings(saveTranscriptsToAppClipboard: false)
        )

        #expect(result == .skipped(reason: .appClipboardDisabled))
        #expect(await poster.postedTexts().isEmpty)
    }

    @Test func pasteShortcutSkipsWhenAppClipboardIsEmpty() async {
        let store = FakeTranscriptClipboardStore()
        let poster = FakeTextEventPoster()
        let service = makePasteService(
            store: store,
            accessibilityIsTrusted: true,
            textEventPoster: poster
        )

        let result = await service.pasteFromAppClipboard(
            settings: makeSettings(saveTranscriptsToAppClipboard: true)
        )

        #expect(result == .skipped(reason: .appClipboardEmpty))
        #expect(result.statusText == "No VibeType Clipboard text is available.")
        #expect(await poster.postedTexts().isEmpty)
    }

    @Test func pasteShortcutDoesNotUseFallbackWhenAccessibilityIsMissing() async {
        let store = FakeTranscriptClipboardStore(initialText: "stored transcript")
        let poster = FakeTextEventPoster()
        let service = makePasteService(
            store: store,
            accessibilityIsTrusted: false,
            textEventPoster: poster
        )

        let result = await service.pasteFromAppClipboard(
            settings: makeSettings(saveTranscriptsToAppClipboard: true)
        )

        #expect(result == .failed(reason: .accessibilityNotTrusted))
        #expect(result.statusText.contains("Accessibility permission"))
        #expect(await store.currentText() == "stored transcript")
        #expect(await poster.postedTexts().isEmpty)
    }

    @Test func pasteShortcutReportsInsertionFailureAndKeepsAppClipboardText() async {
        let store = FakeTranscriptClipboardStore(initialText: "stored transcript")
        let poster = FakeTextEventPoster(mode: .throwError)
        let service = makePasteService(
            store: store,
            accessibilityIsTrusted: true,
            textEventPoster: poster
        )

        let result = await service.pasteFromAppClipboard(
            settings: makeSettings(saveTranscriptsToAppClipboard: true)
        )

        #expect(result == .failed(reason: .textInsertionFailed))
        #expect(await store.currentText() == "stored transcript")
        #expect(await poster.postedTexts() == ["stored transcript"])
    }

    @Test func pasteShortcutReportsTimeoutAndKeepsAppClipboardText() async {
        let store = FakeTranscriptClipboardStore(initialText: "stored transcript")
        let poster = FakeTextEventPoster(mode: .neverCompletes)
        let service = makePasteService(
            store: store,
            accessibilityIsTrusted: true,
            textEventPoster: poster,
            insertTimeout: 0.001
        )

        let result = await service.pasteFromAppClipboard(
            settings: makeSettings(saveTranscriptsToAppClipboard: true)
        )

        #expect(result == .failed(reason: .textInsertionTimedOut))
        #expect(await store.currentText() == "stored transcript")
        #expect(await poster.postedTexts() == ["stored transcript"])
    }

    private func makePasteService(
        store: FakeTranscriptClipboardStore,
        accessibilityIsTrusted: Bool,
        textEventPoster: FakeTextEventPoster,
        insertTimeout: TimeInterval = 1
    ) -> SpecialClipboardPasteService {
        SpecialClipboardPasteService(
            transcriptClipboardStore: store,
            accessibilityPermissionService: AccessibilityPermissionService(
                client: FakeTextInsertionAccessibilityPermissionClient(
                    isTrusted: accessibilityIsTrusted
                )
            ),
            textEventPoster: textEventPoster,
            insertTimeout: insertTimeout
        )
    }

    private func makeSettings(saveTranscriptsToAppClipboard: Bool) -> AppSettings {
        AppSettings(
            transcriptionModel: AppSettings.defaultTranscriptionModel,
            language: .automatic,
            customLanguageCode: "",
            prompt: "",
            saveTranscriptsToAppClipboard: saveTranscriptsToAppClipboard,
            soundEnabled: true,
            showFloatingIndicator: true,
            saveTranscriptHistory: false
        )
    }
}

private actor FakeTranscriptClipboardStore: TranscriptClipboardStoring {
    private var text: String?
    private var recordedSaveTexts: [String] = []
    private var recordedClearCount = 0

    init(initialText: String? = nil) {
        self.text = initialText
    }

    func save(_ text: String) async throws {
        self.text = text
        recordedSaveTexts.append(text)
    }

    func clear() async {
        text = nil
        recordedClearCount += 1
    }

    func currentText() async -> String? {
        text
    }

    func savedTexts() async -> [String] {
        recordedSaveTexts
    }

    func clearCount() async -> Int {
        recordedClearCount
    }
}

private final class FakeTextInsertionAccessibilityPermissionClient: AccessibilityPermissionClient {
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

private actor FakeTextEventPoster: TextEventPosting {
    enum Mode {
        case succeed
        case throwError
        case neverCompletes
    }

    private let mode: Mode
    private var texts: [String] = []

    init(mode: Mode = .succeed) {
        self.mode = mode
    }

    func postText(_ text: String) async throws {
        texts.append(text)

        switch mode {
        case .succeed:
            return
        case .throwError:
            throw TextInsertionServiceError.textEventUnavailable
        case .neverCompletes:
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
    }

    func postedTexts() async -> [String] {
        texts
    }
}
