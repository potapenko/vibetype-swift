import AppKit

protocol SystemClipboardWriting {
    @discardableResult
    func copyPlainText(_ text: String) -> Bool
}

struct SystemClipboardWriter: SystemClipboardWriting {
    @discardableResult
    func copyPlainText(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }
}

struct TranscriptHistoryClipboardCopyAction {
    private let systemClipboardWriter: any SystemClipboardWriting

    init(systemClipboardWriter: any SystemClipboardWriting = SystemClipboardWriter()) {
        self.systemClipboardWriter = systemClipboardWriter
    }

    func copy(_ entry: TranscriptHistoryEntry) -> TranscriptHistoryClipboardCopyResult {
        if systemClipboardWriter.copyPlainText(entry.transcriptText) {
            return .copied
        }

        return .failed
    }
}

enum TranscriptHistoryClipboardCopyResult: Equatable {
    case copied
    case failed

    var statusText: String {
        switch self {
        case .copied:
            return "Copied history row to system clipboard."
        case .failed:
            return "Could not copy history row to system clipboard."
        }
    }
}
