//
//  TextInsertionService.swift
//  vibetype
//
//  Created by Codex on 6/21/26.
//

import AppKit
import Foundation

protocol PasteEventPosting: Sendable {
    func postPasteShortcut() async throws
}

struct CGEventPasteEventPoster: PasteEventPosting {
    private let keyUpDelay: TimeInterval

    init(keyUpDelay: TimeInterval = 0.008) {
        self.keyUpDelay = keyUpDelay
    }

    func postPasteShortcut() async throws {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        else {
            throw TextInsertionServiceError.pasteEventUnavailable
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
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

struct TextInsertionService {
    static let defaultClipboardSettleDelay: TimeInterval = 0.12
    static let defaultClipboardRestoreDelay: TimeInterval = 0.45
    static let defaultPasteTimeout: TimeInterval = 3

    private let clipboardService: ClipboardService
    private let accessibilityPermissionService: AccessibilityPermissionService
    private let pasteEventPoster: any PasteEventPosting
    private let sleeper: any TextInsertionSleeping
    private let clipboardSettleDelay: TimeInterval
    private let clipboardRestoreDelay: TimeInterval
    private let pasteTimeout: TimeInterval

    init(
        clipboardService: ClipboardService = ClipboardService(),
        accessibilityPermissionService: AccessibilityPermissionService = AccessibilityPermissionService(),
        pasteEventPoster: any PasteEventPosting = CGEventPasteEventPoster(),
        sleeper: any TextInsertionSleeping = TaskTextInsertionSleeper(),
        clipboardSettleDelay: TimeInterval = Self.defaultClipboardSettleDelay,
        clipboardRestoreDelay: TimeInterval = Self.defaultClipboardRestoreDelay,
        pasteTimeout: TimeInterval = Self.defaultPasteTimeout
    ) {
        self.clipboardService = clipboardService
        self.accessibilityPermissionService = accessibilityPermissionService
        self.pasteEventPoster = pasteEventPoster
        self.sleeper = sleeper
        self.clipboardSettleDelay = max(0, clipboardSettleDelay)
        self.clipboardRestoreDelay = max(0, clipboardRestoreDelay)
        self.pasteTimeout = pasteTimeout > 0 ? pasteTimeout : Self.defaultPasteTimeout
    }

    func deliver(_ transcript: String, settings: AppSettings) async throws -> TextInsertionResult {
        if settings.autoPaste {
            return try await pasteOrCopyFallback(
                transcript,
                shouldRestorePreviousClipboard: settings.restoreClipboard
            )
        }

        guard settings.copyToClipboard else {
            return .skipped(reason: .outputDisabled)
        }

        let snapshot = try clipboardService.copyPlainText(transcript)
        return .copiedToClipboard(reason: .autoPasteDisabled, snapshot: snapshot)
    }

    private func pasteOrCopyFallback(
        _ transcript: String,
        shouldRestorePreviousClipboard: Bool
    ) async throws -> TextInsertionResult {
        let snapshot = try clipboardService.copyPlainText(transcript)

        guard accessibilityPermissionService.currentStatus().canPasteIntoActiveApp else {
            return .copiedToClipboard(reason: .accessibilityNotTrusted, snapshot: snapshot)
        }

        do {
            try await sleeper.sleep(seconds: clipboardSettleDelay)
            try await postPasteWithTimeout()
            let restoreStatus = await restorePreviousClipboardIfNeeded(
                from: snapshot,
                enabled: shouldRestorePreviousClipboard
            )
            return .pasted(snapshot: snapshot, restoreStatus: restoreStatus)
        } catch TextInsertionServiceError.pasteTimedOut {
            return .copiedToClipboard(reason: .pasteTimedOut, snapshot: snapshot)
        } catch {
            return .copiedToClipboard(reason: .pasteFailed, snapshot: snapshot)
        }
    }

    private func restorePreviousClipboardIfNeeded(
        from snapshot: ClipboardSnapshot,
        enabled: Bool
    ) async -> TextInsertionRestoreStatus {
        guard enabled else {
            return .disabled
        }

        guard snapshot.canRestorePlainText else {
            return .skippedNoPreviousPlainText
        }

        do {
            try await sleeper.sleep(seconds: clipboardRestoreDelay)
            try clipboardService.restorePlainText(from: snapshot)
            return .restored
        } catch {
            return .failed
        }
    }

    private func postPasteWithTimeout() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await pasteEventPoster.postPasteShortcut()
            }
            group.addTask {
                try await TaskTextInsertionSleeper().sleep(seconds: pasteTimeout)
                throw TextInsertionServiceError.pasteTimedOut
            }

            defer {
                group.cancelAll()
            }

            guard let _ = try await group.next() else {
                throw TextInsertionServiceError.pasteFailed
            }
        }
    }
}

enum TextInsertionResult: Equatable {
    case pasted(snapshot: ClipboardSnapshot, restoreStatus: TextInsertionRestoreStatus)
    case copiedToClipboard(reason: TextInsertionCopyOnlyReason, snapshot: ClipboardSnapshot)
    case skipped(reason: TextInsertionSkipReason)

    var statusText: String {
        switch self {
        case .pasted(_, let restoreStatus):
            return restoreStatus.statusText
        case .copiedToClipboard(let reason, _):
            return reason.statusText
        case .skipped(let reason):
            return reason.statusText
        }
    }
}

enum TextInsertionRestoreStatus: Equatable {
    case disabled
    case skippedNoPreviousPlainText
    case restored
    case failed

    var statusText: String {
        switch self {
        case .disabled, .skippedNoPreviousPlainText:
            return "Transcript pasted."
        case .restored:
            return "Transcript pasted. Previous clipboard restored."
        case .failed:
            return "Transcript pasted, but the previous clipboard could not be restored."
        }
    }
}

enum TextInsertionCopyOnlyReason: Equatable {
    case autoPasteDisabled
    case accessibilityNotTrusted
    case pasteFailed
    case pasteTimedOut

    var statusText: String {
        switch self {
        case .autoPasteDisabled:
            return "Transcript copied."
        case .accessibilityNotTrusted:
            return "Accessibility permission is needed for auto-paste. Transcript copied."
        case .pasteFailed:
            return "Auto-paste failed. Transcript copied."
        case .pasteTimedOut:
            return "Auto-paste timed out. Transcript copied."
        }
    }
}

enum TextInsertionSkipReason: Equatable {
    case outputDisabled

    var statusText: String {
        switch self {
        case .outputDisabled:
            return "Transcript output is disabled."
        }
    }
}

enum TextInsertionServiceError: Error, Equatable, LocalizedError {
    case pasteEventUnavailable
    case pasteFailed
    case pasteTimedOut

    var errorDescription: String? {
        switch self {
        case .pasteEventUnavailable:
            return "Could not create the paste keyboard event."
        case .pasteFailed:
            return "Could not paste into the active app."
        case .pasteTimedOut:
            return "Paste into the active app timed out."
        }
    }
}
