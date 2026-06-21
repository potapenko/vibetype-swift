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

    @Test func trustedAutoPasteRestoresPreviousClipboardAfterSuccessfulPasteWhenEnabled() async throws {
        let clipboardClient = FakeTextInsertionClipboardClient(plainText: "previous clipboard")
        let pasteEventPoster = FakePasteEventPoster()
        let sleeper = FakeTextInsertionSleeper()
        let service = makeService(
            clipboardClient: clipboardClient,
            accessibilityIsTrusted: true,
            pasteEventPoster: pasteEventPoster,
            sleeper: sleeper,
            clipboardSettleDelay: 0.12,
            clipboardRestoreDelay: 0.45
        )

        let result = try await service.deliver("hello active app", settings: defaultSettings())

        #expect(
            result == .pasted(
                snapshot: ClipboardSnapshot(plainText: "previous clipboard"),
                restoreStatus: .restored
            )
        )
        #expect(result.statusText == "Transcript pasted. Previous clipboard restored.")
        #expect(clipboardClient.plainText == "previous clipboard")
        #expect(clipboardClient.writtenText == ["hello active app", "previous clipboard"])
        #expect(await pasteEventPoster.postCount() == 1)
        #expect(await sleeper.sleepCalls() == [0.12, 0.45])
    }

    @Test func restoreDisabledLeavesTranscriptOnClipboardAfterSuccessfulPaste() async throws {
        let clipboardClient = FakeTextInsertionClipboardClient(plainText: "previous clipboard")
        let pasteEventPoster = FakePasteEventPoster()
        let service = makeService(
            clipboardClient: clipboardClient,
            accessibilityIsTrusted: true,
            pasteEventPoster: pasteEventPoster
        )
        let settings = makeSettings(
            autoPaste: true,
            copyToClipboard: true,
            restoreClipboard: false
        )

        let result = try await service.deliver("keep transcript", settings: settings)

        #expect(
            result == .pasted(
                snapshot: ClipboardSnapshot(plainText: "previous clipboard"),
                restoreStatus: .disabled
            )
        )
        #expect(result.statusText == "Transcript pasted.")
        #expect(clipboardClient.plainText == "keep transcript")
        #expect(clipboardClient.writtenText == ["keep transcript"])
        #expect(await pasteEventPoster.postCount() == 1)
    }

    @Test func missingPreviousPlainTextSkipsRestoreAndLeavesTranscriptOnClipboard() async throws {
        let clipboardClient = FakeTextInsertionClipboardClient(plainText: nil)
        let pasteEventPoster = FakePasteEventPoster()
        let service = makeService(
            clipboardClient: clipboardClient,
            accessibilityIsTrusted: true,
            pasteEventPoster: pasteEventPoster
        )

        let result = try await service.deliver("no previous text", settings: defaultSettings())

        #expect(
            result == .pasted(
                snapshot: ClipboardSnapshot(plainText: nil),
                restoreStatus: .skippedNoPreviousPlainText
            )
        )
        #expect(result.statusText == "Transcript pasted.")
        #expect(clipboardClient.plainText == "no previous text")
        #expect(clipboardClient.writtenText == ["no previous text"])
        #expect(await pasteEventPoster.postCount() == 1)
    }

    @Test func restoreFailureReportsPastedResultWithoutThrowing() async throws {
        let clipboardClient = FakeTextInsertionClipboardClient(plainText: "previous clipboard")
        clipboardClient.failAfterSuccessfulWriteCount = 1
        let pasteEventPoster = FakePasteEventPoster()
        let service = makeService(
            clipboardClient: clipboardClient,
            accessibilityIsTrusted: true,
            pasteEventPoster: pasteEventPoster
        )

        let result = try await service.deliver("restore failure text", settings: defaultSettings())

        #expect(
            result == .pasted(
                snapshot: ClipboardSnapshot(plainText: "previous clipboard"),
                restoreStatus: .failed
            )
        )
        #expect(result.statusText.contains("could not be restored"))
        #expect(clipboardClient.plainText == "restore failure text")
        #expect(clipboardClient.writtenText == ["restore failure text"])
        #expect(await pasteEventPoster.postCount() == 1)
    }

    @Test func missingAccessibilityFallsBackToCopiedTranscriptWithoutPostingPaste() async throws {
        let clipboardClient = FakeTextInsertionClipboardClient(plainText: "previous clipboard")
        let pasteEventPoster = FakePasteEventPoster()
        let service = makeService(
            clipboardClient: clipboardClient,
            accessibilityIsTrusted: false,
            pasteEventPoster: pasteEventPoster
        )

        let result = try await service.deliver("manual paste text", settings: defaultSettings())

        #expect(
            result == .copiedToClipboard(
                reason: TextInsertionCopyOnlyReason.accessibilityNotTrusted,
                snapshot: ClipboardSnapshot(plainText: "previous clipboard")
            )
        )
        #expect(result.statusText.contains("Accessibility permission"))
        #expect(clipboardClient.plainText == "manual paste text")
        #expect(clipboardClient.writtenText == ["manual paste text"])
        #expect(await pasteEventPoster.postCount() == 0)
    }

    @Test func pasteFailureLeavesTranscriptOnClipboardAsCopyOnlyFallback() async throws {
        let clipboardClient = FakeTextInsertionClipboardClient(plainText: "previous clipboard")
        let pasteEventPoster = FakePasteEventPoster(mode: .throwError)
        let service = makeService(
            clipboardClient: clipboardClient,
            accessibilityIsTrusted: true,
            pasteEventPoster: pasteEventPoster
        )

        let result = try await service.deliver("fallback text", settings: defaultSettings())

        #expect(
            result == .copiedToClipboard(
                reason: TextInsertionCopyOnlyReason.pasteFailed,
                snapshot: ClipboardSnapshot(plainText: "previous clipboard")
            )
        )
        #expect(result.statusText == "Auto-paste failed. Transcript copied.")
        #expect(clipboardClient.plainText == "fallback text")
        #expect(clipboardClient.writtenText == ["fallback text"])
        #expect(await pasteEventPoster.postCount() == 1)
    }

    @Test func pasteTimeoutLeavesTranscriptOnClipboardAsCopyOnlyFallback() async throws {
        let clipboardClient = FakeTextInsertionClipboardClient(plainText: "previous clipboard")
        let pasteEventPoster = FakePasteEventPoster(mode: .neverCompletes)
        let service = makeService(
            clipboardClient: clipboardClient,
            accessibilityIsTrusted: true,
            pasteEventPoster: pasteEventPoster,
            clipboardSettleDelay: 0,
            pasteTimeout: 0.001
        )

        let result = try await service.deliver("timeout fallback", settings: defaultSettings())

        #expect(
            result == .copiedToClipboard(
                reason: TextInsertionCopyOnlyReason.pasteTimedOut,
                snapshot: ClipboardSnapshot(plainText: "previous clipboard")
            )
        )
        #expect(result.statusText == "Auto-paste timed out. Transcript copied.")
        #expect(clipboardClient.plainText == "timeout fallback")
        #expect(clipboardClient.writtenText == ["timeout fallback"])
        #expect(await pasteEventPoster.postCount() == 1)
    }

    @Test func disabledAutoPasteUsesCopySettingWithoutPostingPaste() async throws {
        let clipboardClient = FakeTextInsertionClipboardClient(plainText: nil)
        let pasteEventPoster = FakePasteEventPoster()
        let service = makeService(
            clipboardClient: clipboardClient,
            accessibilityIsTrusted: true,
            pasteEventPoster: pasteEventPoster
        )
        let settings = makeSettings(autoPaste: false, copyToClipboard: true)

        let result = try await service.deliver("copy only", settings: settings)

        #expect(
            result == .copiedToClipboard(
                reason: TextInsertionCopyOnlyReason.autoPasteDisabled,
                snapshot: ClipboardSnapshot(plainText: nil)
            )
        )
        #expect(clipboardClient.plainText == "copy only")
        #expect(await pasteEventPoster.postCount() == 0)
    }

    @Test func disabledAutoPasteAndCopySkipsOutputWithoutReplacingClipboard() async throws {
        let clipboardClient = FakeTextInsertionClipboardClient(plainText: "previous clipboard")
        let service = makeService(clipboardClient: clipboardClient, accessibilityIsTrusted: true)
        let settings = makeSettings(autoPaste: false, copyToClipboard: false)

        let result = try await service.deliver("unused text", settings: settings)

        #expect(result == .skipped(reason: TextInsertionSkipReason.outputDisabled))
        #expect(result.statusText == "Transcript output is disabled.")
        #expect(clipboardClient.plainText == "previous clipboard")
        #expect(clipboardClient.writtenText.isEmpty)
    }

    private func makeService(
        clipboardClient: FakeTextInsertionClipboardClient,
        accessibilityIsTrusted: Bool,
        pasteEventPoster: FakePasteEventPoster = FakePasteEventPoster(),
        sleeper: FakeTextInsertionSleeper = FakeTextInsertionSleeper(),
        clipboardSettleDelay: TimeInterval = 0,
        clipboardRestoreDelay: TimeInterval = 0,
        pasteTimeout: TimeInterval = 1
    ) -> TextInsertionService {
        TextInsertionService(
            clipboardService: ClipboardService(client: clipboardClient),
            accessibilityPermissionService: AccessibilityPermissionService(
                client: FakeTextInsertionAccessibilityPermissionClient(
                    isTrusted: accessibilityIsTrusted
                )
            ),
            pasteEventPoster: pasteEventPoster,
            sleeper: sleeper,
            clipboardSettleDelay: clipboardSettleDelay,
            clipboardRestoreDelay: clipboardRestoreDelay,
            pasteTimeout: pasteTimeout
        )
    }

    private func defaultSettings() -> AppSettings {
        makeSettings(autoPaste: true, copyToClipboard: true, restoreClipboard: true)
    }

    private func makeSettings(
        autoPaste: Bool,
        copyToClipboard: Bool,
        restoreClipboard: Bool = true
    ) -> AppSettings {
        AppSettings(
            transcriptionModel: AppSettings.defaultTranscriptionModel,
            language: .automatic,
            customLanguageCode: "",
            prompt: "",
            autoPaste: autoPaste,
            copyToClipboard: copyToClipboard,
            restoreClipboard: restoreClipboard,
            soundEnabled: true,
            showFloatingIndicator: true,
            saveTranscriptHistory: false
        )
    }
}

private final class FakeTextInsertionClipboardClient: ClipboardClient {
    private(set) var writtenText: [String] = []
    var plainText: String?
    var failAfterSuccessfulWriteCount: Int?

    init(plainText: String?) {
        self.plainText = plainText
    }

    func currentPlainText() -> String? {
        plainText
    }

    @discardableResult
    func replacePlainText(_ text: String) -> Bool {
        if let failAfterSuccessfulWriteCount, writtenText.count >= failAfterSuccessfulWriteCount {
            return false
        }

        plainText = text
        writtenText.append(text)
        return true
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

private actor FakePasteEventPoster: PasteEventPosting {
    enum Mode {
        case succeed
        case throwError
        case neverCompletes
    }

    private let mode: Mode
    private var count = 0

    init(mode: Mode = .succeed) {
        self.mode = mode
    }

    func postPasteShortcut() async throws {
        count += 1

        switch mode {
        case .succeed:
            return
        case .throwError:
            throw TextInsertionServiceError.pasteEventUnavailable
        case .neverCompletes:
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
    }

    func postCount() -> Int {
        count
    }
}

private actor FakeTextInsertionSleeper: TextInsertionSleeping {
    private var calls: [TimeInterval] = []

    func sleep(seconds: TimeInterval) async throws {
        calls.append(seconds)
    }

    func sleepCalls() -> [TimeInterval] {
        calls
    }
}
