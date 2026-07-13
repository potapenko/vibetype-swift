import Foundation
@_spi(HoldTypeIOSCore) import HoldTypePersistence

/// Rebuilds the keyboard's bounded App Group cache from canonical app-owned
/// state. This actor is the cache's only writer; it owns no durable state of
/// its own.
actor IOSKeyboardSnapshotPublisher {
    typealias LatestLoader = @Sendable () async throws
        -> IOSV1ForegroundVoiceLatestResultObservation

    private let store: KeyboardBridgeStore?
    private let loadLatest: LatestLoader

    private var operationIsActive = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(
        store: KeyboardBridgeStore?,
        loadLatest: @escaping LatestLoader
    ) {
        self.store = store
        self.loadLatest = loadLatest
    }

    /// Publishes one replacement snapshot. Failure leaves canonical app state
    /// untouched and never reports an unavailable or invalid cache as current.
    func publishCurrent(at publishedAt: Date = Date()) async -> Bool {
        await acquireOperation()
        defer { releaseOperation() }

        guard let store else {
            return false
        }

        do {
            try Task.checkCancellation()
            let latest = try await loadLatest()
            try Task.checkCancellation()

            let revision = try store.nextRevision()
            let projection = try Self.makeSnapshot(
                revision: revision,
                publishedAt: publishedAt,
                latest: latest
            )
            try store.save(projection.snapshot)
            return projection.representsCanonicalLatest
        } catch {
            return false
        }
    }

    private static func makeSnapshot(
        revision: UInt64,
        publishedAt: Date,
        latest: IOSV1ForegroundVoiceLatestResultObservation
    ) throws -> (
        snapshot: KeyboardBridgeSnapshot,
        representsCanonicalLatest: Bool
    ) {
        let latestItem: KeyboardBridgeItem?
        let representsCanonicalLatest: Bool
        switch latest {
        case .absent:
            latestItem = nil
            representsCanonicalLatest = true
        case .resultReady(let record):
            do {
                let candidate = try KeyboardBridgeItem.latest(
                    resultID: record.resultID,
                    text: record.acceptedText,
                    createdAt: record.createdAt
                )
                latestItem = candidate.expiresAt > publishedAt
                    ? candidate
                    : nil
                representsCanonicalLatest = true
            } catch is KeyboardBridgeItem.ValidationError {
                // Never leave a previous result presented as Latest when the
                // current canonical result is unsafe to share.
                latestItem = nil
                representsCanonicalLatest = false
            }
        }

        return try (
            KeyboardBridgeSnapshot(
                revision: revision,
                publishedAt: publishedAt,
                latest: latestItem
            ),
            representsCanonicalLatest
        )
    }

    private func acquireOperation() async {
        guard operationIsActive else {
            operationIsActive = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func releaseOperation() {
        guard !waiters.isEmpty else {
            operationIsActive = false
            return
        }

        waiters.removeFirst().resume()
    }
}
