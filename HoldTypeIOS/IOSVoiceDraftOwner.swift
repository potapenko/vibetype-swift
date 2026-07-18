import Foundation
import Observation
@_spi(HoldTypeIOSCore) import HoldTypePersistence

struct IOSVoiceDraftClient: Sendable {
    let load: @Sendable () async throws -> IOSVoiceDraftRecord
    let accept: @Sendable (
        IOSVoiceDraftSegment,
        IOSVoiceDraftInsertionMode
    ) async throws
        -> IOSVoiceDraftAppendResult
    let replace: @Sendable (
        IOSVoiceDraftRecord,
        IOSVoiceDraftSnapshotToken
    ) async throws -> IOSVoiceDraftMutationResult

    init(repository: IOSVoiceDraftRepository) {
        load = { try await repository.load() }
        accept = { try await repository.accept($0, mode: $1) }
        replace = { try await repository.replace($0, ifCurrent: $1) }
    }

    init(
        load: @escaping @Sendable () async throws -> IOSVoiceDraftRecord,
        accept: @escaping @Sendable (
            IOSVoiceDraftSegment,
            IOSVoiceDraftInsertionMode
        ) async throws
            -> IOSVoiceDraftAppendResult,
        replace: @escaping @Sendable (
            IOSVoiceDraftRecord,
            IOSVoiceDraftSnapshotToken
        ) async throws -> IOSVoiceDraftMutationResult
    ) {
        self.load = load
        self.accept = accept
        self.replace = replace
    }
}

enum IOSVoiceDraftState: Equatable, Sendable {
    case notLoaded
    case ready(IOSVoiceDraftRecord)
    case loadFailed(lastConfirmed: IOSVoiceDraftRecord?)

    var lastConfirmed: IOSVoiceDraftRecord? {
        switch self {
        case .notLoaded:
            nil
        case .ready(let record), .loadFailed(.some(let record)):
            record
        case .loadFailed(lastConfirmed: nil):
            nil
        }
    }
}

enum IOSVoiceDraftOperation: Equatable, Sendable {
    case idle
    case refreshing
    case appending
    case savingEdit
    case clearing
    case undoing
    case redoing
    case transforming
}

struct IOSVoiceDraftTransformationReservation: Equatable, Sendable {
    fileprivate let id: UUID
    fileprivate let record: IOSVoiceDraftRecord

    var text: String { record.text }
}

enum IOSVoiceDraftTransformationCommit: Equatable, Sendable {
    case confirmed(changed: Bool)
    case stale
    case failed
    case unavailable
}

enum IOSVoiceDraftContentChangeKind: Equatable, Sendable {
    case append
    case replace
    case preservePosition
}

struct IOSVoiceDraftContentChange: Equatable, Sendable {
    let revision: Int
    let kind: IOSVoiceDraftContentChangeKind

    static let initial = IOSVoiceDraftContentChange(
        revision: 0,
        kind: .replace
    )
}

enum IOSVoiceDraftNotice: Equatable, Sendable {
    case appendFailed
    case editFailed
    case draftFull
    case clearFailed
    case undoFailed
    case redoFailed
    case draftChanged

    var message: String {
        switch self {
        case .appendFailed:
            "The result is safe in Latest and History, but it couldn't be added to this Draft."
        case .editFailed:
            "The edit couldn't be saved. Your working text remains available to copy or retry."
        case .draftFull:
            "This Draft is full. Copy or clear it before adding another dictation."
        case .clearFailed:
            "The Draft couldn't be cleared. Its confirmed text remains available."
        case .undoFailed:
            "Undo couldn't be saved. The confirmed Draft remains available."
        case .redoFailed:
            "Redo couldn't be saved. The confirmed Draft remains available."
        case .draftChanged:
            "The Draft changed while that action was running. Review it and try again."
        }
    }
}

@MainActor
@Observable
final class IOSVoiceDraftOwner {
    private static let maximumUndoCount = 20

    private(set) var state = IOSVoiceDraftState.notLoaded
    private(set) var operation = IOSVoiceDraftOperation.idle
    private(set) var notice: IOSVoiceDraftNotice?
    private(set) var editingText: String?
    private(set) var contentChange = IOSVoiceDraftContentChange.initial

    @ObservationIgnored
    private let client: IOSVoiceDraftClient
    @ObservationIgnored
    private var undoStack: [IOSVoiceDraftRecord] = []
    @ObservationIgnored
    private var redoStack: [IOSVoiceDraftRecord] = []
    @ObservationIgnored
    private var editBaseline: IOSVoiceDraftRecord?
    @ObservationIgnored
    private var editHasConflict = false
    @ObservationIgnored
    private var activeTransformationID: UUID?

    init(client: IOSVoiceDraftClient) {
        self.client = client
    }

    convenience init(repository: IOSVoiceDraftRepository) {
        self.init(client: IOSVoiceDraftClient(repository: repository))
    }

    var confirmedRecord: IOSVoiceDraftRecord? { state.lastConfirmed }
    var text: String { confirmedRecord?.text ?? "" }
    var visibleText: String { editingText ?? text }
    var isEditing: Bool { editingText != nil }
    var isLoaded: Bool { confirmedRecord != nil }
    var isAvailableForMutation: Bool {
        if case .ready = state, !isEditing, operation == .idle { return true }
        return false
    }
    var isFull: Bool { confirmedRecord?.isFull == true }
    var canUndo: Bool {
        !isEditing && !undoStack.isEmpty && operation == .idle
    }
    var canRedo: Bool {
        !isEditing && !redoStack.isEmpty && operation == .idle
    }
    var isBusy: Bool { operation != .idle }

    @discardableResult
    func refresh() async -> Bool {
        guard begin(.refreshing) else { return false }
        let previous = state.lastConfirmed
        do {
            let record = try await client.load()
            guard complete() else { return false }
            if let previous, previous != record {
                undoStack.removeAll()
                redoStack.removeAll()
            }
            state = .ready(record)
            markContentChange(.replace)
            notice = nil
            return true
        } catch is CancellationError {
            _ = complete()
            return false
        } catch {
            guard complete() else { return false }
            state = .loadFailed(lastConfirmed: previous)
            return false
        }
    }

    @discardableResult
    func accept(
        _ accepted: IOSV1AcceptedOutputDeliveryRecord,
        mode: IOSVoiceDraftInsertionMode
    ) async -> Bool {
        guard await beginAcceptedAppend() else { return false }
        let previous = state.lastConfirmed
        let segment: IOSVoiceDraftSegment
        do {
            segment = try IOSVoiceDraftSegment(
                resultID: accepted.resultID,
                text: accepted.acceptedText
            )
        } catch {
            _ = complete()
            notice = .appendFailed
            return false
        }

        do {
            let result = try await client.accept(segment, mode)
            guard complete() else { return false }
            switch result {
            case .inserted(let record):
                if let previous { recordUndo(previous) }
                redoStack.removeAll()
                state = .ready(record)
                markContentChange(
                    mode == .append ? .append : .replace
                )
                notice = nil
                return true
            case .duplicate(let record):
                state = .ready(record)
                notice = nil
                return true
            case .full(let record):
                state = .ready(record)
                notice = .draftFull
                return false
            }
        } catch is CancellationError {
            _ = complete()
            return false
        } catch {
            guard complete() else { return false }
            if let previous { state = .ready(previous) }
            notice = .appendFailed
            return false
        }
    }

    @discardableResult
    func appendAccepted(
        _ accepted: IOSV1AcceptedOutputDeliveryRecord
    ) async -> Bool {
        await accept(accepted, mode: .append)
    }

    @discardableResult
    func beginEditing() -> Bool {
        guard editingText == nil,
              operation == .idle,
              case .ready(let current) = state else {
            return false
        }
        editBaseline = current
        editHasConflict = false
        editingText = current.text
        notice = nil
        return true
    }

    func updateEditingText(_ text: String) {
        guard editingText != nil else { return }
        editingText = text
        if !editHasConflict { notice = nil }
    }

    @discardableResult
    func persistEditing() async -> Bool {
        guard let editingText,
              let current = confirmedRecord,
              !editHasConflict else {
            return false
        }
        let updated: IOSVoiceDraftRecord
        do {
            updated = try current.replacingText(editingText)
        } catch {
            notice = .editFailed
            return false
        }
        guard updated != current else { return true }
        guard begin(.savingEdit) else { return false }
        do {
            let result = try await client.replace(
                updated,
                IOSVoiceDraftSnapshotToken(record: current)
            )
            guard complete() else { return false }
            switch result {
            case .confirmed(let record):
                state = .ready(record)
                notice = nil
                return true
            case .stale(let record):
                state = .ready(record)
                undoStack.removeAll()
                redoStack.removeAll()
                editHasConflict = true
                notice = .draftChanged
                return false
            }
        } catch is CancellationError {
            _ = complete()
            return false
        } catch {
            guard complete() else { return false }
            state = .ready(current)
            notice = .editFailed
            return false
        }
    }

    @discardableResult
    func finishEditing() async -> Bool {
        while operation == .savingEdit {
            guard !Task.isCancelled else { return false }
            await Task.yield()
        }
        guard let baseline = editBaseline,
              editingText != nil else {
            return true
        }
        guard await persistEditing(),
              let current = confirmedRecord else {
            return false
        }
        editingText = nil
        editBaseline = nil
        editHasConflict = false
        if current != baseline {
            recordUndo(baseline)
            redoStack.removeAll()
        }
        return true
    }

    func beginTransformation()
        -> IOSVoiceDraftTransformationReservation? {
        guard let current = confirmedRecord,
              current.hasMeaningfulText,
              begin(.transforming) else {
            return nil
        }
        let id = UUID()
        activeTransformationID = id
        notice = nil
        return IOSVoiceDraftTransformationReservation(
            id: id,
            record: current
        )
    }

    func commitTransformation(
        _ text: String,
        reservation: IOSVoiceDraftTransformationReservation
    ) async -> IOSVoiceDraftTransformationCommit {
        guard operation == .transforming,
              activeTransformationID == reservation.id,
              confirmedRecord == reservation.record else {
            return .unavailable
        }
        let updated: IOSVoiceDraftRecord
        do {
            updated = try reservation.record.replacingText(text)
        } catch {
            finishTransformation(reservation)
            notice = .editFailed
            return .failed
        }
        guard updated != reservation.record else {
            finishTransformation(reservation)
            notice = nil
            return .confirmed(changed: false)
        }

        do {
            let result = try await client.replace(
                updated,
                IOSVoiceDraftSnapshotToken(record: reservation.record)
            )
            guard operation == .transforming,
                  activeTransformationID == reservation.id else {
                return .unavailable
            }
            finishTransformation(reservation)
            switch result {
            case .confirmed(let record):
                state = .ready(record)
                recordUndo(reservation.record)
                redoStack.removeAll()
                markContentChange(.replace)
                notice = nil
                return .confirmed(changed: true)
            case .stale(let record):
                state = .ready(record)
                undoStack.removeAll()
                redoStack.removeAll()
                notice = .draftChanged
                return .stale
            }
        } catch is CancellationError {
            finishTransformation(reservation)
            return .failed
        } catch {
            guard operation == .transforming,
                  activeTransformationID == reservation.id else {
                return .unavailable
            }
            finishTransformation(reservation)
            state = .ready(reservation.record)
            notice = .editFailed
            return .failed
        }
    }

    func cancelTransformation(
        _ reservation: IOSVoiceDraftTransformationReservation
    ) {
        guard operation == .transforming,
              activeTransformationID == reservation.id else {
            return
        }
        finishTransformation(reservation)
    }

    @discardableResult
    func clear() async -> Bool {
        guard !isEditing else { return false }
        guard let current = confirmedRecord,
              !current.isEmpty else {
            return false
        }
        return await replaceCurrent(
            with: .empty,
            operation: .clearing,
            failureNotice: .clearFailed,
            onSuccess: {
                self.recordUndo(current)
                self.redoStack.removeAll()
                self.markContentChange(.replace)
            }
        )
    }

    @discardableResult
    func clearForNewDictation() async -> Bool {
        guard isAvailableForMutation,
              let current = confirmedRecord else {
            return false
        }
        guard current.hasMeaningfulText else { return true }
        return await clear()
    }

    @discardableResult
    func undo() async -> Bool {
        guard let current = confirmedRecord,
              let target = undoStack.last else {
            return false
        }
        return await replaceCurrent(
            with: target,
            operation: .undoing,
            failureNotice: .undoFailed,
            onSuccess: {
                _ = self.undoStack.popLast()
                self.recordRedo(current)
                self.markContentChange(.preservePosition)
            }
        )
    }

    @discardableResult
    func redo() async -> Bool {
        guard let current = confirmedRecord,
              let target = redoStack.last else {
            return false
        }
        return await replaceCurrent(
            with: target,
            operation: .redoing,
            failureNotice: .redoFailed,
            onSuccess: {
                _ = self.redoStack.popLast()
                self.recordUndo(current)
                self.markContentChange(.preservePosition)
            }
        )
    }

    func dismissNotice() {
        notice = nil
    }

    private func replaceCurrent(
        with updated: IOSVoiceDraftRecord,
        operation: IOSVoiceDraftOperation,
        failureNotice: IOSVoiceDraftNotice,
        onSuccess: @escaping () -> Void
    ) async -> Bool {
        guard let current = confirmedRecord,
              begin(operation) else {
            return false
        }
        do {
            let result = try await client.replace(
                updated,
                IOSVoiceDraftSnapshotToken(record: current)
            )
            guard complete() else { return false }
            switch result {
            case .confirmed(let record):
                state = .ready(record)
                notice = nil
                onSuccess()
                return true
            case .stale(let record):
                state = .ready(record)
                undoStack.removeAll()
                redoStack.removeAll()
                notice = .draftChanged
                return false
            }
        } catch is CancellationError {
            _ = complete()
            return false
        } catch {
            guard complete() else { return false }
            state = .ready(current)
            notice = failureNotice
            return false
        }
    }

    private func recordUndo(_ record: IOSVoiceDraftRecord) {
        recordMeaningful(record, in: &undoStack)
    }

    private func recordRedo(_ record: IOSVoiceDraftRecord) {
        recordMeaningful(record, in: &redoStack)
    }

    private func recordMeaningful(
        _ record: IOSVoiceDraftRecord,
        in stack: inout [IOSVoiceDraftRecord]
    ) {
        guard record.hasMeaningfulText, stack.last != record else { return }
        stack.append(record)
        trim(&stack)
    }

    private func markContentChange(_ kind: IOSVoiceDraftContentChangeKind) {
        contentChange = IOSVoiceDraftContentChange(
            revision: contentChange.revision + 1,
            kind: kind
        )
    }

    private func trim(_ stack: inout [IOSVoiceDraftRecord]) {
        if stack.count > Self.maximumUndoCount {
            stack.removeFirst(stack.count - Self.maximumUndoCount)
        }
    }

    private func begin(_ requested: IOSVoiceDraftOperation) -> Bool {
        guard operation == .idle else { return false }
        operation = requested
        return true
    }

    private func finishTransformation(
        _ reservation: IOSVoiceDraftTransformationReservation
    ) {
        guard activeTransformationID == reservation.id else { return }
        activeTransformationID = nil
        _ = complete()
    }

    private func beginAcceptedAppend() async -> Bool {
        guard !isEditing else { return false }
        while !begin(.appending) {
            guard !isEditing else { return false }
            guard !Task.isCancelled else { return false }
            await Task.yield()
        }
        return true
    }

    @discardableResult
    private func complete() -> Bool {
        guard operation != .idle else { return false }
        operation = .idle
        return true
    }
}

extension IOSVoiceDraftOwner: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    nonisolated var description: String { "IOSVoiceDraftOwner(<redacted>)" }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}
