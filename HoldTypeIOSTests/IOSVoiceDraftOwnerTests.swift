import Foundation
@_spi(HoldTypeIOSCore) import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSVoiceDraftOwnerTests {
    @Test func defaultReplacementCreatesOneUndoableAtomicDraft() async throws {
        try await withRepository { repository in
            let owner = IOSVoiceDraftOwner(repository: repository)
            #expect(await owner.refresh())
            let old = try accepted(1, text: "Old")
            let replacement = try accepted(2, text: "New attempt")
            #expect(await owner.appendAccepted(old))
            #expect(!owner.canUndo)
            #expect(owner.contentChange.revision == 2)
            #expect(owner.contentChange.kind == .append)

            #expect(
                await owner.accept(
                    replacement,
                    mode: .replace
                )
            )
            #expect(owner.text == "New attempt")
            #expect(owner.confirmedRecord?.segments.count == 1)
            #expect(owner.contentChange.revision == 3)
            #expect(owner.contentChange.kind == .replace)
            #expect(await owner.undo())
            #expect(owner.text == "Old")
            #expect(owner.contentChange.revision == 4)
            #expect(owner.contentChange.kind == .preservePosition)
        }
    }

    @Test func refreshAppendAndRestartPreserveOnlyTheConfirmedDraft()
        async throws {
        try await withRepository { repository in
            let owner = IOSVoiceDraftOwner(repository: repository)
            #expect(await owner.refresh())
            #expect(owner.text.isEmpty)
            #expect(!owner.canUndo)

            let first = try accepted(1, text: "First paragraph")
            let second = try accepted(2, text: "Second paragraph")
            #expect(await owner.appendAccepted(first))
            #expect(!owner.canUndo)
            #expect(await owner.appendAccepted(first))
            #expect(!owner.canUndo)
            #expect(await owner.appendAccepted(second))
            #expect(owner.canUndo)
            #expect(owner.text == "First paragraph\n\nSecond paragraph")

            let relaunched = IOSVoiceDraftOwner(repository: repository)
            #expect(await relaunched.refresh())
            #expect(relaunched.text == owner.text)
            #expect(!relaunched.canUndo)
            #expect(!relaunched.canRedo)
        }
    }

    @Test func clearCanRestoreTextWithoutMakingBlankRedoable()
        async throws {
        try await withRepository { repository in
            let owner = IOSVoiceDraftOwner(repository: repository)
            #expect(await owner.refresh())
            let first = try accepted(1, text: "One")
            let second = try accepted(2, text: "Two")
            #expect(await owner.appendAccepted(first))
            #expect(await owner.appendAccepted(second))

            #expect(await owner.clear())
            #expect(owner.text.isEmpty)
            #expect(owner.canUndo)
            #expect(await owner.undo())
            #expect(owner.text == "One\n\nTwo")
            #expect(!owner.canRedo)
        }
    }

    @Test func newDictationClearTreatsEmptyAsSuccessAndPreservesUndo()
        async throws {
        try await withRepository { repository in
            let owner = IOSVoiceDraftOwner(repository: repository)
            #expect(await owner.refresh())
            #expect(await owner.clearForNewDictation())
            #expect(owner.text.isEmpty)

            let old = try accepted(1, text: "Old")
            #expect(await owner.appendAccepted(old))
            #expect(await owner.clearForNewDictation())
            #expect(owner.text.isEmpty)
            #expect(owner.canUndo)
            #expect(await owner.undo())
            #expect(owner.text == "Old")
        }
    }

    @Test func meaningfulUndoRedoAndNewBranchHaveSessionLocalSemantics()
        async throws {
        try await withRepository { repository in
            let owner = IOSVoiceDraftOwner(repository: repository)
            #expect(await owner.refresh())
            let first = try accepted(1, text: "One")
            let second = try accepted(2, text: "Two")
            let third = try accepted(3, text: "Three")
            #expect(await owner.appendAccepted(first))
            #expect(await owner.appendAccepted(second))

            #expect(await owner.undo())
            #expect(owner.text == "One")
            #expect(owner.canRedo)
            #expect(await owner.redo())
            #expect(owner.text == "One\n\nTwo")

            #expect(await owner.undo())
            #expect(await owner.appendAccepted(third))
            #expect(owner.text == "One\n\nThree")
            #expect(!owner.canRedo)
        }
    }

    @Test func firstManualTextHasNoEmptyUndoTarget() async throws {
        try await withRepository { repository in
            let owner = IOSVoiceDraftOwner(repository: repository)
            #expect(await owner.refresh())
            #expect(owner.beginEditing())
            owner.updateEditingText("Typed from empty")
            #expect(await owner.finishEditing())

            #expect(owner.text == "Typed from empty")
            #expect(!owner.canUndo)
            #expect(!owner.canRedo)
        }
    }

    @Test func visuallyBlankEditIsCanonicalEmptyAndOnlyRestorable()
        async throws {
        try await withRepository { repository in
            let owner = IOSVoiceDraftOwner(repository: repository)
            #expect(await owner.refresh())
            let first = try accepted(1, text: "One")
            #expect(await owner.appendAccepted(first))
            #expect(owner.beginEditing())
            owner.updateEditingText(" \n\t ")
            #expect(await owner.finishEditing())

            #expect(owner.confirmedRecord == .empty)
            #expect(owner.canUndo)
            #expect(await owner.undo())
            #expect(owner.text == "One")
            #expect(!owner.canRedo)
        }
    }

    @Test func oneEditSessionPersistsExactTextAndCreatesOneUndoSnapshot()
        async throws {
        try await withRepository { repository in
            let owner = IOSVoiceDraftOwner(repository: repository)
            #expect(await owner.refresh())
            let first = try accepted(1, text: "One")
            #expect(await owner.appendAccepted(first))

            #expect(owner.beginEditing())
            owner.updateEditingText("One, edited ✨")
            #expect(owner.visibleText == "One, edited ✨")
            #expect(!owner.canUndo)
            #expect(await owner.persistEditing())
            owner.updateEditingText("One, edited ✨\n\nManual note")
            #expect(await owner.finishEditing())

            #expect(owner.text == "One, edited ✨\n\nManual note")
            #expect(owner.canUndo)
            #expect(await owner.undo())
            #expect(owner.text == "One")
            #expect(await owner.redo())
            #expect(owner.text == "One, edited ✨\n\nManual note")

            let relaunched = IOSVoiceDraftOwner(repository: repository)
            #expect(await relaunched.refresh())
            #expect(relaunched.text == "One, edited ✨\n\nManual note")
            #expect(await relaunched.appendAccepted(first))
            #expect(relaunched.text == "One, edited ✨\n\nManual note")
        }
    }

    @Test func staleEditPreservesWorkingTextAndNeverOverwritesAppend()
        async throws {
        try await withRepository { repository in
            let owner = IOSVoiceDraftOwner(repository: repository)
            #expect(await owner.refresh())
            let first = try accepted(1, text: "One")
            #expect(await owner.appendAccepted(first))
            #expect(owner.beginEditing())
            owner.updateEditingText("My unsaved edit")

            _ = try await repository.append(
                IOSVoiceDraftSegment(
                    resultID: identifier(2),
                    text: "External"
                )
            )

            #expect(!(await owner.finishEditing()))
            #expect(owner.text == "One\n\nExternal")
            #expect(owner.visibleText == "My unsaved edit")
            #expect(owner.notice == .draftChanged)

            owner.updateEditingText("My unsaved edit, continued")
            #expect(!(await owner.persistEditing()))
            #expect(try await repository.load().text == "One\n\nExternal")
            #expect(owner.notice == .draftChanged)

        }
    }

    @Test func finishingWaitsForAnOverlappingDebouncedSave() async throws {
        try await withRepository { repository in
            let client = IOSVoiceDraftClient(
                load: { try await repository.load() },
                accept: { try await repository.accept($0, mode: $1) },
                replace: { record, token in
                    try await Task.sleep(for: .milliseconds(30))
                    return try await repository.replace(
                        record,
                        ifCurrent: token
                    )
                }
            )
            let owner = IOSVoiceDraftOwner(client: client)
            #expect(await owner.refresh())
            #expect(owner.beginEditing())
            owner.updateEditingText("Saved while focus leaves")

            let debounce = Task { @MainActor in
                await owner.persistEditing()
            }
            while owner.operation != .savingEdit { await Task.yield() }

            #expect(await owner.finishEditing())
            #expect(await debounce.value)
            #expect(!owner.isEditing)
            #expect(owner.text == "Saved while focus leaves")
            let persisted = try await repository.load()
            #expect(persisted.text == owner.text)
        }
    }

    @Test func committedVisibleEditCanBeRestoredAfterClear() async throws {
        try await withRepository { repository in
            let owner = IOSVoiceDraftOwner(repository: repository)
            #expect(await owner.refresh())
            #expect(owner.beginEditing())
            owner.updateEditingText("Typed immediately before Clear")

            #expect(await owner.finishEditing())
            #expect(await owner.clear())
            #expect(owner.text.isEmpty)
            #expect(owner.canUndo)

            #expect(await owner.undo())
            #expect(owner.text == "Typed immediately before Clear")
        }
    }

    @Test func failedMutationKeepsLastConfirmedTextAndReportsRecovery()
        async throws {
        try await withRepository { repository in
            _ = try await repository.append(
                IOSVoiceDraftSegment(
                    resultID: identifier(1),
                    text: "Confirmed text"
                )
            )
            let client = IOSVoiceDraftClient(
                load: { try await repository.load() },
                accept: { try await repository.accept($0, mode: $1) },
                replace: { _, _ in throw DraftOwnerTestError.writeFailed }
            )
            let owner = IOSVoiceDraftOwner(client: client)
            #expect(await owner.refresh())

            #expect(!(await owner.clear()))
            #expect(owner.text == "Confirmed text")
            #expect(owner.notice == .clearFailed)
            #expect(owner.operation == .idle)
        }
    }

    @Test func externalChangeRejectsAStaleClearAndRefreshesVisibleDraft()
        async throws {
        try await withRepository { repository in
            let owner = IOSVoiceDraftOwner(repository: repository)
            #expect(await owner.refresh())
            let first = try accepted(1, text: "One")
            #expect(await owner.appendAccepted(first))
            _ = try await repository.append(
                IOSVoiceDraftSegment(resultID: identifier(2), text: "External")
            )

            #expect(!(await owner.clear()))
            #expect(owner.text == "One\n\nExternal")
            #expect(owner.notice == .draftChanged)
            #expect(!owner.canUndo)
            #expect(!owner.canRedo)
        }
    }

    @Test func refreshOfChangedDraftClearsProcessLocalBranches()
        async throws {
        try await withRepository { repository in
            let owner = IOSVoiceDraftOwner(repository: repository)
            #expect(await owner.refresh())
            let first = try accepted(1, text: "One")
            let second = try accepted(2, text: "Two")
            #expect(await owner.appendAccepted(first))
            #expect(await owner.appendAccepted(second))
            #expect(owner.canUndo)

            _ = try await repository.append(
                IOSVoiceDraftSegment(
                    resultID: identifier(3),
                    text: "External"
                )
            )

            #expect(await owner.refresh())
            #expect(owner.text == "One\n\nTwo\n\nExternal")
            #expect(!owner.canUndo)
            #expect(!owner.canRedo)
        }
    }

    @Test func acceptedResultWaitsForAnOverlappingClearInsteadOfBeingLost()
        async throws {
        try await withRepository { repository in
            _ = try await repository.append(
                IOSVoiceDraftSegment(resultID: identifier(1), text: "Old")
            )
            let client = IOSVoiceDraftClient(
                load: { try await repository.load() },
                accept: { try await repository.accept($0, mode: $1) },
                replace: { record, token in
                    try await Task.sleep(for: .milliseconds(30))
                    return try await repository.replace(
                        record,
                        ifCurrent: token
                    )
                }
            )
            let owner = IOSVoiceDraftOwner(client: client)
            #expect(await owner.refresh())
            let accepted = try accepted(2, text: "New")

            let clear = Task { @MainActor in await owner.clear() }
            while owner.operation != .clearing { await Task.yield() }
            let append = Task { @MainActor in
                await owner.appendAccepted(accepted)
            }

            #expect(await clear.value)
            #expect(await append.value)
            #expect(owner.text == "New")
            #expect(try await repository.load().text == "New")
        }
    }

    @Test func transformationReplacesAtomicallyAndCreatesOneUndoSnapshot()
        async throws {
        try await withRepository { repository in
            let owner = IOSVoiceDraftOwner(repository: repository)
            #expect(await owner.refresh())
            #expect(await owner.appendAccepted(try accepted(1, text: "Original")))
            let reservation = try #require(owner.beginTransformation())
            #expect(owner.operation == .transforming)
            #expect(owner.beginTransformation() == nil)

            #expect(
                await owner.commitTransformation(
                    "Improved",
                    reservation: reservation
                ) == .confirmed(changed: true)
            )
            #expect(owner.operation == .idle)
            #expect(owner.text == "Improved")
            #expect(owner.canUndo)
            #expect(await owner.undo())
            #expect(owner.text == "Original")
        }
    }

    @Test func staleTransformationNeverOverwritesNewerDraft() async throws {
        try await withRepository { repository in
            let owner = IOSVoiceDraftOwner(repository: repository)
            #expect(await owner.refresh())
            #expect(await owner.appendAccepted(try accepted(1, text: "Original")))
            let reservation = try #require(owner.beginTransformation())

            _ = try await repository.append(
                IOSVoiceDraftSegment(
                    resultID: identifier(2),
                    text: "External"
                )
            )

            #expect(
                await owner.commitTransformation(
                    "Stale provider result",
                    reservation: reservation
                ) == .stale
            )
            #expect(owner.text == "Original\n\nExternal")
            #expect(owner.notice == .draftChanged)
            #expect(!owner.canUndo)
        }
    }

    private func withRepository(
        operation: (IOSVoiceDraftRepository) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "holdtype-draft-owner-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try await operation(
            IOSVoiceDraftRepository(applicationSupportDirectoryURL: root)
        )
    }

    private func accepted(
        _ index: Int,
        text: String
    ) throws -> IOSV1AcceptedOutputDeliveryRecord {
        try IOSV1AcceptedOutputDeliveryRecord(
            resultID: identifier(index),
            sourceAttemptID: UUID(),
            acceptedText: text,
            createdAt: Date(timeIntervalSince1970: TimeInterval(index))
        )
    }

    private func identifier(_ index: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                index
            )
        )!
    }
}

private enum DraftOwnerTestError: Error {
    case writeFailed
}
