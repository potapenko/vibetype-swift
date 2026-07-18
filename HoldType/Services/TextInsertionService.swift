//
//  TextInsertionService.swift
//  HoldType
//
//  Created by Codex on 6/21/26.
//

import AppKit
import Foundation
import HoldTypeDomain

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

    func deliver(_ request: OutputDeliveryRequest) async throws -> TextInsertionResult {
        let transcript = request.acceptedTranscript.text
        let preferences = request.preferences
        let savedToAppClipboard: Bool
        if preferences.keepLatestResult {
            try await transcriptClipboardStore.save(transcript)
            savedToAppClipboard = true
        } else {
            await transcriptClipboardStore.clear()
            savedToAppClipboard = false
        }

        guard preferences.automaticInsertionPreferenceEnabled else {
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
            return "Inserted transcript into the active app. Paste Last Result is ready."
        case .savedToAppClipboard:
            return "Saved as Last Result. Press Control+Command+V to insert."
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
            return "Paste Last Result is disabled."
        case .outputDisabled:
            return "Automatic insertion and Paste Last Result are disabled."
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
                ? "Accessibility permission is needed to insert text. Saved as Last Result."
                : "Accessibility permission is needed to insert text."
        case .textInsertionFailed:
            return savedToAppClipboard
                ? "Could not insert text into the active app. Saved as Last Result."
                : "Could not insert text into the active app."
        case .textInsertionTimedOut:
            return savedToAppClipboard
                ? "Inserting text into the active app timed out. Saved as Last Result."
                : "Inserting text into the active app timed out."
        }
    }

    var appClipboardPasteStatusText: String {
        switch self {
        case .accessibilityNotTrusted:
            return "Accessibility permission is needed to paste the last result."
        case .textInsertionFailed:
            return "Could not insert the last result into the active app."
        case .textInsertionTimedOut:
            return "Inserting the last result timed out."
        }
    }
}

protocol TextEventPosting: Sendable {
    func postText(_ text: String) async throws
}

struct CGEventTextEventPoster: TextEventPosting {
    private let keyUpDelay: TimeInterval

    init(keyUpDelay: TimeInterval = 0.004) {
        self.keyUpDelay = max(0, keyUpDelay)
    }

    func postText(_ text: String) async throws {
        let utf16Units = try Self.unicodeUnits(for: text)
        try await post(utf16Units)
    }

    static func unicodeUnits(for text: String) throws -> [UInt16] {
        guard !text.isEmpty else {
            throw TextInsertionServiceError.emptyAppClipboardText
        }

        return Array(text.utf16)
    }

    private func post(_ utf16Units: [UInt16]) async throws {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else {
            throw TextInsertionServiceError.textEventUnavailable
        }

        Self.configureTextEvent(keyDown, utf16Units: utf16Units)
        Self.configureTextEvent(keyUp, utf16Units: utf16Units)

        keyDown.post(tap: .cgSessionEventTap)
        try await TaskTextInsertionSleeper().sleep(seconds: keyUpDelay)
        keyUp.post(tap: .cgSessionEventTap)
    }

    static func configureTextEvent(_ event: CGEvent, utf16Units: [UInt16]) {
        event.flags = CGEventFlags()
        utf16Units.withUnsafeBufferPointer { buffer in
            event.keyboardSetUnicodeString(
                stringLength: utf16Units.count,
                unicodeString: buffer.baseAddress
            )
        }
    }
}

struct TaskTextInsertionSleeper {
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
            return "Inserted last result."
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
            return "Paste Last Result is disabled."
        case .appClipboardEmpty:
            return "No last result is available."
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
            return "No last result is available."
        case .textEventUnavailable:
            return "Could not create a text insertion keyboard event."
        case .textInsertionFailed:
            return "Could not insert text into the active app."
        case .textInsertionTimedOut:
            return "Inserting text into the active app timed out."
        }
    }
}
