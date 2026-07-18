import Foundation
import HoldTypePersistence
import Observation

struct IOSAcceptedTextHistoryClient: Sendable {
    let load: @Sendable () async throws -> IOSAcceptedTextHistoryRecord
    let delete: @Sendable (UUID) async throws -> IOSAcceptedTextHistoryRecord
    let clearAll: @Sendable (IOSAcceptedTextHistorySnapshotToken) async throws
        -> IOSAcceptedTextHistoryMutationResult
    let setEnabled: @Sendable (
        Bool,
        IOSAcceptedTextHistorySnapshotToken
    ) async throws -> IOSAcceptedTextHistoryMutationResult

    init(repository: IOSAcceptedTextHistoryRepository) {
        load = { try await repository.load() }
        delete = { try await repository.delete(resultID: $0) }
        clearAll = { try await repository.clearAll(ifCurrent: $0) }
        setEnabled = {
            try await repository.setEnabled($0, ifCurrent: $1)
        }
    }

    init(
        load: @escaping @Sendable () async throws
            -> IOSAcceptedTextHistoryRecord,
        delete: @escaping @Sendable (UUID) async throws
            -> IOSAcceptedTextHistoryRecord,
        clearAll: @escaping @Sendable (
            IOSAcceptedTextHistorySnapshotToken
        ) async throws -> IOSAcceptedTextHistoryMutationResult,
        setEnabled: @escaping @Sendable (
            Bool,
            IOSAcceptedTextHistorySnapshotToken
        ) async throws -> IOSAcceptedTextHistoryMutationResult
    ) {
        self.load = load
        self.delete = delete
        self.clearAll = clearAll
        self.setEnabled = setEnabled
    }
}

enum IOSAcceptedTextHistoryState: Equatable, Sendable {
    case notLoaded
    case ready(IOSAcceptedTextHistoryRecord)
    case loadFailed(lastConfirmed: IOSAcceptedTextHistoryRecord?)

    var lastConfirmed: IOSAcceptedTextHistoryRecord? {
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

enum IOSAcceptedTextHistoryHomePresentation: Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case disabled
        case empty
        case entries
    }

    case loading
    case unavailable
    case history(
        record: IOSAcceptedTextHistoryRecord,
        content: Content,
        isStale: Bool
    )

    static func resolve(
        _ state: IOSAcceptedTextHistoryState
    ) -> Self {
        switch state {
        case .notLoaded:
            return .loading
        case .loadFailed(lastConfirmed: nil):
            return .unavailable
        case .ready(let record):
            return history(record: record, isStale: false)
        case .loadFailed(lastConfirmed: .some(let record)):
            return history(record: record, isStale: true)
        }
    }

    private static func history(
        record: IOSAcceptedTextHistoryRecord,
        isStale: Bool
    ) -> Self {
        let content: Content
        if !record.isEnabled {
            content = .disabled
        } else if record.entries.isEmpty {
            content = .empty
        } else {
            content = .entries
        }
        return .history(
            record: record,
            content: content,
            isStale: isStale
        )
    }
}

enum IOSAcceptedTextHistoryOperation: Equatable, Sendable {
    case idle
    case refreshing
    case deleting(UUID)
    case clearing
    case settingEnabled(Bool)
}

enum IOSAcceptedTextHistoryNotice: Equatable, Sendable {
    case deleteFailed
    case clearFailed
    case enableFailed
    case disableFailed
    case historyChanged

    var message: String {
        switch self {
        case .deleteFailed:
            "That History entry couldn't be deleted. Nothing was removed."
        case .clearFailed:
            "History couldn't be cleared. The confirmed entries remain available."
        case .enableFailed:
            "Save History couldn't be turned on. Its previous setting remains active."
        case .disableFailed:
            "Save History couldn't be turned off. Its previous setting and entries remain active."
        case .historyChanged:
            "History changed while the confirmation was open. Review it and try again."
        }
    }
}

@MainActor
@Observable
final class IOSAcceptedTextHistoryStateOwner {
    typealias PublishKeyboardSnapshot = @Sendable () async -> Bool

    private(set) var state = IOSAcceptedTextHistoryState.notLoaded
    private(set) var operation = IOSAcceptedTextHistoryOperation.idle
    private(set) var notice: IOSAcceptedTextHistoryNotice?

    @ObservationIgnored
    private let client: IOSAcceptedTextHistoryClient
    @ObservationIgnored
    private let publishKeyboardSnapshot: PublishKeyboardSnapshot
    @ObservationIgnored
    private var presentationRefreshIsPending = false

    init(
        client: IOSAcceptedTextHistoryClient,
        publishKeyboardSnapshot: @escaping PublishKeyboardSnapshot = { true }
    ) {
        self.client = client
        self.publishKeyboardSnapshot = publishKeyboardSnapshot
    }

    convenience init(
        repository: IOSAcceptedTextHistoryRepository,
        publishKeyboardSnapshot: @escaping PublishKeyboardSnapshot = { true }
    ) {
        self.init(
            client: IOSAcceptedTextHistoryClient(repository: repository),
            publishKeyboardSnapshot: publishKeyboardSnapshot
        )
    }

    var confirmedRecord: IOSAcceptedTextHistoryRecord? {
        state.lastConfirmed
    }

    var isBusy: Bool { operation != .idle }

    @discardableResult
    func refresh() async -> Bool {
        await refresh(publishKeyboardSnapshotOnSuccess: true)
    }

    /// Reloads the observable History presentation after acceptance without
    /// duplicating the runtime-owned keyboard snapshot publication. If a
    /// user-initiated History operation is already active, one later reload
    /// coalesces all acceptance notifications received during that operation.
    func refreshPresentationAfterAcceptedResult() async {
        guard operation == .idle else {
            presentationRefreshIsPending = true
            return
        }
        _ = await refresh(publishKeyboardSnapshotOnSuccess: false)
    }

    private func refresh(
        publishKeyboardSnapshotOnSuccess: Bool
    ) async -> Bool {
        guard begin(.refreshing) else { return false }
        let previous = state.lastConfirmed
        do {
            let record = try await client.load()
            guard complete() else { return false }
            state = .ready(record)
            notice = nil
            if publishKeyboardSnapshotOnSuccess {
                _ = await publishKeyboardSnapshot()
            }
            return true
        } catch is CancellationError {
            _ = complete()
            return false
        } catch {
            guard complete() else { return false }
            state = .loadFailed(lastConfirmed: previous)
            notice = nil
            return false
        }
    }

    @discardableResult
    func delete(resultID: UUID) async -> Bool {
        await mutate(
            operation: .deleting(resultID),
            failureNotice: .deleteFailed
        ) {
            .confirmed(try await self.client.delete(resultID))
        }
    }

    @discardableResult
    func clearAll(
        ifCurrent expected: IOSAcceptedTextHistorySnapshotToken
    ) async -> Bool {
        await mutate(
            operation: .clearing,
            failureNotice: .clearFailed,
            perform: { try await self.client.clearAll(expected) }
        )
    }

    @discardableResult
    func setEnabled(
        _ isEnabled: Bool,
        ifCurrent expected: IOSAcceptedTextHistorySnapshotToken
    ) async -> Bool {
        await mutate(
            operation: .settingEnabled(isEnabled),
            failureNotice: isEnabled ? .enableFailed : .disableFailed
        ) {
            try await self.client.setEnabled(isEnabled, expected)
        }
    }

    func dismissNotice() {
        notice = nil
    }

    private func mutate(
        operation: IOSAcceptedTextHistoryOperation,
        failureNotice: IOSAcceptedTextHistoryNotice,
        perform: @escaping @Sendable () async throws
            -> IOSAcceptedTextHistoryMutationResult
    ) async -> Bool {
        guard let previous = state.lastConfirmed,
              begin(operation) else {
            return false
        }
        do {
            let result = try await perform()
            guard complete() else { return false }
            switch result {
            case .confirmed(let record):
                state = .ready(record)
                notice = nil
                _ = await publishKeyboardSnapshot()
                return true
            case .stale(let record):
                state = .ready(record)
                notice = .historyChanged
                _ = await publishKeyboardSnapshot()
                return false
            }
        } catch is CancellationError {
            guard complete() else { return false }
            state = .ready(previous)
            return false
        } catch {
            guard complete() else { return false }
            state = .ready(previous)
            notice = failureNotice
            return false
        }
    }

    private func begin(
        _ requestedOperation: IOSAcceptedTextHistoryOperation
    ) -> Bool {
        guard operation == .idle else { return false }
        operation = requestedOperation
        return true
    }

    @discardableResult
    private func complete() -> Bool {
        guard operation != .idle else { return false }
        operation = .idle
        if presentationRefreshIsPending {
            presentationRefreshIsPending = false
            Task { @MainActor [weak self] in
                await self?.refreshPresentationAfterAcceptedResult()
            }
        }
        return true
    }
}
