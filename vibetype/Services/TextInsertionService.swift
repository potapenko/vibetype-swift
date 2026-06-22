//
//  TextInsertionService.swift
//  vibetype
//
//  Created by Codex on 6/21/26.
//

import AppKit
import Foundation

protocol TranscriptClipboardStoring: Sendable {
    func save(_ text: String) async throws
    func clear() async
    func currentText() async -> String?
}

actor AppTranscriptClipboardStore: TranscriptClipboardStoring {
    static let shared = AppTranscriptClipboardStore()

    private var text: String?

    func save(_ text: String) async throws {
        guard !text.isEmpty else {
            throw TextInsertionServiceError.emptyAppClipboardText
        }

        self.text = text
    }

    func clear() async {
        text = nil
    }

    func currentText() async -> String? {
        text
    }
}

struct TextInsertionService {
    private let transcriptClipboardStore: any TranscriptClipboardStoring
    private let activeAppTextInsertionService: ActiveAppTextInsertionService

    init(
        transcriptClipboardStore: any TranscriptClipboardStoring = AppTranscriptClipboardStore.shared,
        accessibilityPermissionService: AccessibilityPermissionService = AccessibilityPermissionService(),
        textEventPoster: any TextEventPosting = CGEventTextEventPoster(),
        insertTimeout: TimeInterval = ActiveAppTextInsertionService.defaultInsertTimeout
    ) {
        self.transcriptClipboardStore = transcriptClipboardStore
        activeAppTextInsertionService = ActiveAppTextInsertionService(
            accessibilityPermissionService: accessibilityPermissionService,
            textEventPoster: textEventPoster,
            insertTimeout: insertTimeout
        )
    }

    func deliver(_ transcript: String, settings: AppSettings) async throws -> TextInsertionResult {
        let savedToAppClipboard: Bool
        if settings.saveTranscriptsToAppClipboard {
            try await transcriptClipboardStore.save(transcript)
            savedToAppClipboard = true
        } else {
            await transcriptClipboardStore.clear()
            savedToAppClipboard = false
        }

        guard settings.automaticallyInsertTranscripts else {
            return savedToAppClipboard
                ? .savedToAppClipboard
                : .skipped(reason: .outputDisabled)
        }

        switch await activeAppTextInsertionService.insert(transcript) {
        case .inserted:
            return savedToAppClipboard ? .insertedAndSavedToAppClipboard : .inserted
        case .failed(let reason):
            return .failed(reason: reason, savedToAppClipboard: savedToAppClipboard)
        }
    }

    func insertRecoveredTranscript(_ transcript: String, settings: AppSettings) async throws -> TextInsertionResult {
        let savedToAppClipboard: Bool
        if settings.saveTranscriptsToAppClipboard {
            try await transcriptClipboardStore.save(transcript)
            savedToAppClipboard = true
        } else {
            savedToAppClipboard = false
        }

        switch await activeAppTextInsertionService.insert(transcript) {
        case .inserted:
            return savedToAppClipboard ? .insertedAndSavedToAppClipboard : .inserted
        case .failed(let reason):
            return .failed(reason: reason, savedToAppClipboard: savedToAppClipboard)
        }
    }
}

enum TextInsertionResult: Equatable {
    case inserted
    case insertedAndSavedToAppClipboard
    case savedToAppClipboard
    case skipped(reason: TextInsertionSkipReason)
    case failed(reason: TextInsertionFailureReason, savedToAppClipboard: Bool)

    var statusText: String {
        switch self {
        case .inserted:
            return "Inserted transcript into the active app."
        case .insertedAndSavedToAppClipboard:
            return "Inserted transcript into the active app. Recovery shortcut is ready."
        case .savedToAppClipboard:
            return "Saved to VibeType Clipboard. Press Control+Command+V to insert."
        case .skipped(let reason):
            return reason.statusText
        case .failed(let reason, let savedToAppClipboard):
            return reason.statusText(savedToAppClipboard: savedToAppClipboard)
        }
    }
}

enum TextInsertionSkipReason: Equatable {
    case appClipboardDisabled
    case outputDisabled

    var statusText: String {
        switch self {
        case .appClipboardDisabled:
            return "VibeType Clipboard is disabled."
        case .outputDisabled:
            return "Automatic insertion and VibeType Clipboard are disabled."
        }
    }
}

enum TextInsertionFailureReason: Equatable {
    case accessibilityNotTrusted
    case textInsertionFailed
    case textInsertionTimedOut

    func statusText(savedToAppClipboard: Bool) -> String {
        switch self {
        case .accessibilityNotTrusted:
            return savedToAppClipboard
                ? "Accessibility permission is needed to insert text. Saved to VibeType Clipboard."
                : "Accessibility permission is needed to insert text."
        case .textInsertionFailed:
            return savedToAppClipboard
                ? "Could not insert text into the active app. Saved to VibeType Clipboard."
                : "Could not insert text into the active app."
        case .textInsertionTimedOut:
            return savedToAppClipboard
                ? "Inserting text into the active app timed out. Saved to VibeType Clipboard."
                : "Inserting text into the active app timed out."
        }
    }

    var appClipboardPasteStatusText: String {
        switch self {
        case .accessibilityNotTrusted:
            return "Accessibility permission is needed to paste from VibeType Clipboard."
        case .textInsertionFailed:
            return "Could not insert VibeType Clipboard text into the active app."
        case .textInsertionTimedOut:
            return "Inserting VibeType Clipboard text timed out."
        }
    }
}

protocol TextEventPosting: Sendable {
    func postText(_ text: String) async throws
}

struct CGEventTextEventPoster: TextEventPosting {
    private let keyUpDelay: TimeInterval
    private let characterDelay: TimeInterval

    init(keyUpDelay: TimeInterval = 0.004, characterDelay: TimeInterval = 0.001) {
        self.keyUpDelay = max(0, keyUpDelay)
        self.characterDelay = max(0, characterDelay)
    }

    func postText(_ text: String) async throws {
        guard !text.isEmpty else {
            throw TextInsertionServiceError.emptyAppClipboardText
        }

        for character in text {
            try await post(character)

            if characterDelay > 0 {
                try await TaskTextInsertionSleeper().sleep(seconds: characterDelay)
            }
        }
    }

    private func post(_ character: Character) async throws {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else {
            throw TextInsertionServiceError.textEventUnavailable
        }

        let utf16Units = Array(String(character).utf16)
        utf16Units.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(
                stringLength: utf16Units.count,
                unicodeString: buffer.baseAddress
            )
            keyUp.keyboardSetUnicodeString(
                stringLength: utf16Units.count,
                unicodeString: buffer.baseAddress
            )
        }

        keyDown.post(tap: .cgSessionEventTap)
        try await TaskTextInsertionSleeper().sleep(seconds: keyUpDelay)
        keyUp.post(tap: .cgSessionEventTap)
    }
}

protocol TextInsertionSleeping {
    func sleep(seconds: TimeInterval) async throws
}

struct TaskTextInsertionSleeper: TextInsertionSleeping {
    func sleep(seconds: TimeInterval) async throws {
        guard seconds > 0 else {
            return
        }

        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

struct ActiveAppTextInsertionService {
    static let defaultInsertTimeout: TimeInterval = 5

    private let accessibilityPermissionService: AccessibilityPermissionService
    private let textEventPoster: any TextEventPosting
    private let insertTimeout: TimeInterval

    init(
        accessibilityPermissionService: AccessibilityPermissionService = AccessibilityPermissionService(),
        textEventPoster: any TextEventPosting = CGEventTextEventPoster(),
        insertTimeout: TimeInterval = Self.defaultInsertTimeout
    ) {
        self.accessibilityPermissionService = accessibilityPermissionService
        self.textEventPoster = textEventPoster
        self.insertTimeout = insertTimeout > 0 ? insertTimeout : Self.defaultInsertTimeout
    }

    func insert(_ text: String) async -> ActiveAppTextInsertionResult {
        guard accessibilityPermissionService.currentStatus().canInsertTextIntoActiveApp else {
            return .failed(reason: .accessibilityNotTrusted)
        }

        do {
            try await postTextWithTimeout(text)
            return .inserted
        } catch TextInsertionServiceError.textInsertionTimedOut {
            return .failed(reason: .textInsertionTimedOut)
        } catch {
            return .failed(reason: .textInsertionFailed)
        }
    }

    private func postTextWithTimeout(_ text: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await textEventPoster.postText(text)
            }
            group.addTask {
                try await TaskTextInsertionSleeper().sleep(seconds: insertTimeout)
                throw TextInsertionServiceError.textInsertionTimedOut
            }

            defer {
                group.cancelAll()
            }

            guard let _ = try await group.next() else {
                throw TextInsertionServiceError.textInsertionFailed
            }
        }
    }
}

enum ActiveAppTextInsertionResult: Equatable {
    case inserted
    case failed(reason: TextInsertionFailureReason)
}

struct SpecialClipboardPasteService {
    static let defaultInsertTimeout = ActiveAppTextInsertionService.defaultInsertTimeout

    private let transcriptClipboardStore: any TranscriptClipboardStoring
    private let activeAppTextInsertionService: ActiveAppTextInsertionService

    init(
        transcriptClipboardStore: any TranscriptClipboardStoring = AppTranscriptClipboardStore.shared,
        accessibilityPermissionService: AccessibilityPermissionService = AccessibilityPermissionService(),
        textEventPoster: any TextEventPosting = CGEventTextEventPoster(),
        insertTimeout: TimeInterval = Self.defaultInsertTimeout
    ) {
        self.transcriptClipboardStore = transcriptClipboardStore
        activeAppTextInsertionService = ActiveAppTextInsertionService(
            accessibilityPermissionService: accessibilityPermissionService,
            textEventPoster: textEventPoster,
            insertTimeout: insertTimeout
        )
    }

    func pasteFromAppClipboard(settings: AppSettings) async -> SpecialClipboardPasteResult {
        guard settings.saveTranscriptsToAppClipboard else {
            return .skipped(reason: .appClipboardDisabled)
        }

        guard let text = await transcriptClipboardStore.currentText(), !text.isEmpty else {
            return .skipped(reason: .appClipboardEmpty)
        }

        switch await activeAppTextInsertionService.insert(text) {
        case .inserted:
            return .inserted
        case .failed(let reason):
            return .failed(reason: reason)
        }
    }
}

enum SpecialClipboardPasteResult: Equatable {
    case inserted
    case skipped(reason: SpecialClipboardPasteSkipReason)
    case failed(reason: TextInsertionFailureReason)

    var statusText: String {
        switch self {
        case .inserted:
            return "Inserted from VibeType Clipboard."
        case .skipped(let reason):
            return reason.statusText
        case .failed(let reason):
            return reason.appClipboardPasteStatusText
        }
    }
}

enum SpecialClipboardPasteSkipReason: Equatable {
    case appClipboardDisabled
    case appClipboardEmpty

    var statusText: String {
        switch self {
        case .appClipboardDisabled:
            return "VibeType Clipboard is disabled."
        case .appClipboardEmpty:
            return "No VibeType Clipboard text is available."
        }
    }
}

enum TextInsertionServiceError: Error, Equatable, LocalizedError {
    case emptyAppClipboardText
    case textEventUnavailable
    case textInsertionFailed
    case textInsertionTimedOut

    var errorDescription: String? {
        switch self {
        case .emptyAppClipboardText:
            return "No VibeType Clipboard text is available."
        case .textEventUnavailable:
            return "Could not create a text insertion keyboard event."
        case .textInsertionFailed:
            return "Could not insert text into the active app."
        case .textInsertionTimedOut:
            return "Inserting text into the active app timed out."
        }
    }
}
