import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypeIOS

struct IOSKeyboardFixMetadataPublisherTests {
    @Test func publishesOrderedPromptFreeProjectionWithMonotonicRevision()
        async throws {
        let promptSecret = "PROMPT-MUST-STAY-APP-PRIVATE-4192"
        let custom = try TextFixAction(
            id: "user.concise",
            kind: .customPrompt,
            title: "Concise",
            icon: .makeShorter,
            prompt: promptSecret,
            isEnabled: false
        )
        let catalog = try TextFixCatalog(
            actions: Array(TextFixCatalog.defaults.actions.prefix(2))
                + [custom]
        )
        let store = IOSKeyboardFixMetadataStoreProbe(firstRevision: 17)
        let publishedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let publisher = IOSKeyboardFixMetadataPublisher(
            loadCatalog: { catalog },
            store: store.client,
            now: { publishedAt }
        )

        #expect(await publisher.publishCurrent())
        #expect(await publisher.publishCurrent())

        let snapshots = store.snapshots
        #expect(snapshots.map(\.revision) == [17, 18])
        #expect(snapshots.allSatisfy { $0.publishedAt == publishedAt })
        let actions = try #require(snapshots.last?.actions)
        #expect(actions.map(\.identifier) == [
            TextFixAction.translateIdentifier,
            TextFixAction.fixIdentifier,
            custom.id,
        ])
        #expect(actions.map(\.order) == [0, 1, 2])
        #expect(actions.last?.kind == .customPrompt)
        #expect(actions.last?.icon == .makeShorter)
        #expect(actions.last?.isEnabled == false)
        #expect(!String(reflecting: snapshots).contains(promptSecret))
    }

    @Test func catalogFailureLeavesPublishedMetadataUnchanged() async {
        let store = IOSKeyboardFixMetadataStoreProbe(firstRevision: 1)
        let publisher = IOSKeyboardFixMetadataPublisher(
            loadCatalog: {
                throw IOSKeyboardFixMetadataPublisherTestError.loadFailed
            },
            store: store.client
        )

        #expect(await publisher.publishCurrent() == false)
        #expect(store.snapshots.isEmpty)
    }
}

private enum IOSKeyboardFixMetadataPublisherTestError: Error {
    case loadFailed
}

private final class IOSKeyboardFixMetadataStoreProbe:
    @unchecked Sendable {
    private let lock = NSLock()
    private var nextRevisionStorage: UInt64
    private var snapshotsStorage:
        [HoldTypeIOS.KeyboardFixMetadataSnapshot] = []

    init(firstRevision: UInt64) {
        nextRevisionStorage = firstRevision
    }

    var client: IOSKeyboardFixMetadataStoreClient {
        IOSKeyboardFixMetadataStoreClient(
            nextRevision: { [self] in
                lock.withLock {
                    defer { nextRevisionStorage += 1 }
                    return nextRevisionStorage
                }
            },
            publish: { [self] snapshot in
                lock.withLock {
                    snapshotsStorage.append(snapshot)
                }
            }
        )
    }

    var snapshots: [HoldTypeIOS.KeyboardFixMetadataSnapshot] {
        lock.withLock { snapshotsStorage }
    }
}
