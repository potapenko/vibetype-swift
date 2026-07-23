import Foundation
import HoldTypeDomain

nonisolated struct IOSKeyboardFixMetadataStoreClient: Sendable {
    let nextRevision: @Sendable () throws -> UInt64
    let publish: @Sendable (KeyboardFixMetadataSnapshot) throws -> Void

    init(
        nextRevision: @escaping @Sendable () throws -> UInt64,
        publish: @escaping @Sendable (
            KeyboardFixMetadataSnapshot
        ) throws -> Void
    ) {
        self.nextRevision = nextRevision
        self.publish = publish
    }

    init(store: KeyboardFixBridgeStore) {
        let box = IOSKeyboardFixMetadataStoreBox(store: store)
        self.init(
            nextRevision: {
                try box.store.nextMetadataRevision()
            },
            publish: {
                try box.store.publishMetadata($0)
            }
        )
    }
}

private nonisolated final class IOSKeyboardFixMetadataStoreBox:
    @unchecked Sendable {
    let store: KeyboardFixBridgeStore

    init(store: KeyboardFixBridgeStore) {
        self.store = store
    }
}

/// Serializes prompt-free projection of the canonical app-private Fix catalog.
actor IOSKeyboardFixMetadataPublisher {
    typealias LoadCatalog = @Sendable () async throws -> TextFixCatalog

    private let loadCatalog: LoadCatalog
    private let store: IOSKeyboardFixMetadataStoreClient
    private let now: @Sendable () -> Date

    init(
        loadCatalog: @escaping LoadCatalog,
        store: IOSKeyboardFixMetadataStoreClient,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.loadCatalog = loadCatalog
        self.store = store
        self.now = now
    }

    @discardableResult
    func publishCurrent() async -> Bool {
        do {
            let catalog = try await loadCatalog()
            guard let actions = Self.project(catalog),
                  let snapshot = KeyboardFixMetadataSnapshot(
                      revision: try store.nextRevision(),
                      publishedAt: now(),
                      actions: actions
                  )
            else {
                return false
            }
            try store.publish(snapshot)
            return true
        } catch {
            return false
        }
    }

    nonisolated static func project(
        _ catalog: TextFixCatalog
    ) -> [KeyboardFixMetadataAction]? {
        let actions = catalog.actions.enumerated().compactMap {
            index,
            action -> KeyboardFixMetadataAction? in
            guard let kind = KeyboardFixActionKind(
                rawValue: action.kind.rawValue
            ),
            let icon = KeyboardFixIconToken(
                rawValue: action.icon.rawValue
            )
            else {
                return nil
            }
            return KeyboardFixMetadataAction(
                identifier: action.id,
                kind: kind,
                title: action.title,
                icon: icon,
                order: index,
                isEnabled: action.isEnabled
            )
        }
        return actions.count == catalog.actions.count ? actions : nil
    }
}

nonisolated extension IOSKeyboardFixMetadataPublisher:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSKeyboardFixMetadataPublisher(redacted)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}
