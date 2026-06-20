//
//  ClipboardServiceTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/20/26.
//

import Testing
@testable import vibetype

struct ClipboardServiceTests {

    @Test func copiesPlainTextAndReturnsPreviousTextSnapshot() throws {
        let client = FakeClipboardClient(plainText: "previous clipboard")
        let service = ClipboardService(client: client)

        let snapshot = try service.copyPlainText("new transcript")

        #expect(snapshot.plainText == "previous clipboard")
        #expect(snapshot.canRestorePlainText == true)
        #expect(client.plainText == "new transcript")
        #expect(client.writtenText == ["new transcript"])
    }

    @Test func capturesMissingPlainTextAsEmptySnapshot() throws {
        let client = FakeClipboardClient(plainText: nil)
        let service = ClipboardService(client: client)

        let snapshot = try service.copyPlainText("new transcript")

        #expect(snapshot.plainText == nil)
        #expect(snapshot.canRestorePlainText == false)
        #expect(client.plainText == "new transcript")
    }

    @Test func rejectsEmptyTranscriptWithoutReplacingClipboard() {
        let client = FakeClipboardClient(plainText: "previous clipboard")
        let service = ClipboardService(client: client)

        #expect(throws: ClipboardServiceError.emptyText) {
            try service.copyPlainText("")
        }
        #expect(client.plainText == "previous clipboard")
        #expect(client.writtenText.isEmpty)
    }

    @Test func restoresPreviousPlainTextWhenAvailable() throws {
        let client = FakeClipboardClient(plainText: "current clipboard")
        let service = ClipboardService(client: client)
        let snapshot = ClipboardSnapshot(plainText: "previous clipboard")

        try service.restorePlainText(from: snapshot)

        #expect(client.plainText == "previous clipboard")
        #expect(client.writtenText == ["previous clipboard"])
    }
}

private final class FakeClipboardClient: ClipboardClient {
    private(set) var writtenText: [String] = []
    var plainText: String?
    var shouldFailWrites = false

    init(plainText: String?) {
        self.plainText = plainText
    }

    func currentPlainText() -> String? {
        plainText
    }

    @discardableResult
    func replacePlainText(_ text: String) -> Bool {
        guard !shouldFailWrites else {
            return false
        }

        plainText = text
        writtenText.append(text)
        return true
    }
}
