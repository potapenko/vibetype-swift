//
//  ClipboardService.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import AppKit
import Foundation

struct ClipboardSnapshot: Equatable {
    let plainText: String?

    var canRestorePlainText: Bool {
        plainText != nil
    }
}

protocol ClipboardClient {
    func currentPlainText() -> String?

    @discardableResult
    func replacePlainText(_ text: String) -> Bool
}

struct PasteboardClipboardClient: ClipboardClient {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func currentPlainText() -> String? {
        pasteboard.string(forType: .string)
    }

    @discardableResult
    func replacePlainText(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

struct ClipboardService {
    private let client: ClipboardClient

    init(client: ClipboardClient = PasteboardClipboardClient()) {
        self.client = client
    }

    @discardableResult
    func copyPlainText(_ text: String) throws -> ClipboardSnapshot {
        guard !text.isEmpty else {
            throw ClipboardServiceError.emptyText
        }

        let snapshot = ClipboardSnapshot(plainText: client.currentPlainText())
        guard client.replacePlainText(text) else {
            throw ClipboardServiceError.copyFailed
        }

        return snapshot
    }

    func restorePlainText(from snapshot: ClipboardSnapshot) throws {
        guard let text = snapshot.plainText else {
            return
        }

        guard client.replacePlainText(text) else {
            throw ClipboardServiceError.restoreFailed
        }
    }
}

enum ClipboardServiceError: Error, Equatable, LocalizedError {
    case emptyText
    case copyFailed
    case restoreFailed

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "No transcript is available to copy."
        case .copyFailed:
            return "Could not copy the transcript to the clipboard."
        case .restoreFailed:
            return "Could not restore the previous clipboard text."
        }
    }
}
