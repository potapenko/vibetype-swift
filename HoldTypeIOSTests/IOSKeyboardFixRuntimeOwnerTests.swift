import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSKeyboardFixRuntimeOwnerTests {
    @Test func coldFixURLStartsObserverPublishesMetadataAndProcessesRequest()
        async throws {
        let request = try makeProcessorTestRequest()
        let bridge = IOSKeyboardFixTestBridgeProbe(request: request)
        let observer = IOSKeyboardFixRuntimeObservationProbe()
        let metadata = IOSKeyboardFixRuntimeMetadataProbe()
        let owner = IOSKeyboardFixRuntimeOwner(
            processor: makeKeyboardFixProcessor(
                bridge: bridge.client,
                now: request.issuedAt.addingTimeInterval(1),
                execute: { _ in "Updated selection" }
            ),
            metadataPublisher: metadata.publisher,
            requestObservation: observer.client
        )
        let url = try #require(
            KeyboardFixLaunchRoute(requestID: request.requestID).url
        )

        #expect(owner.handleLaunchURL(url))
        await owner.waitUntilIdle()

        #expect(observer.startCount == 1)
        #expect(metadata.snapshots.count == 1)
        #expect(bridge.consumedCount == 1)
        #expect(bridge.results.map(\.phase) == [.processing, .succeeded])
        owner.stop()
        #expect(observer.stopCount == 1)
    }

    @Test func activeSceneRecoversPendingRequestWithoutDarwinSignal()
        async throws {
        let request = try makeProcessorTestRequest()
        let bridge = IOSKeyboardFixTestBridgeProbe(request: request)
        let observer = IOSKeyboardFixRuntimeObservationProbe()
        let metadata = IOSKeyboardFixRuntimeMetadataProbe()
        let owner = IOSKeyboardFixRuntimeOwner(
            processor: makeKeyboardFixProcessor(
                bridge: bridge.client,
                now: request.issuedAt.addingTimeInterval(1),
                execute: { _ in "Recovered output" }
            ),
            metadataPublisher: metadata.publisher,
            requestObservation: observer.client
        )

        owner.handleSceneActivity(.active)
        await owner.waitUntilIdle()

        #expect(bridge.consumedCount == 1)
        #expect(bridge.results.last?.outputText == "Recovered output")
    }

    @Test func unrelatedURLIsInert() async throws {
        let request = try makeProcessorTestRequest()
        let bridge = IOSKeyboardFixTestBridgeProbe(request: request)
        let observer = IOSKeyboardFixRuntimeObservationProbe()
        let metadata = IOSKeyboardFixRuntimeMetadataProbe()
        let owner = IOSKeyboardFixRuntimeOwner(
            processor: makeKeyboardFixProcessor(
                bridge: bridge.client,
                now: request.issuedAt.addingTimeInterval(1),
                execute: { _ in "Must not run" }
            ),
            metadataPublisher: metadata.publisher,
            requestObservation: observer.client
        )
        let url = try #require(URL(string: "holdtype://history"))

        #expect(owner.handleLaunchURL(url) == false)
        await owner.waitUntilIdle()

        #expect(observer.startCount == 0)
        #expect(metadata.snapshots.isEmpty)
        #expect(bridge.consumedCount == 0)
    }
}

private final class IOSKeyboardFixRuntimeObservationProbe:
    @unchecked Sendable {
    private let lock = NSLock()
    private var startCountStorage = 0
    private var stopCountStorage = 0

    var client: IOSKeyboardFixRequestObservationClient {
        IOSKeyboardFixRequestObservationClient(
            start: { [self] _ in
                lock.withLock {
                    startCountStorage += 1
                }
            },
            stop: { [self] in
                lock.withLock {
                    stopCountStorage += 1
                }
            }
        )
    }

    var startCount: Int {
        lock.withLock { startCountStorage }
    }

    var stopCount: Int {
        lock.withLock { stopCountStorage }
    }
}

private final class IOSKeyboardFixRuntimeMetadataProbe:
    @unchecked Sendable {
    private let lock = NSLock()
    private var revision: UInt64 = 1
    private var snapshotsStorage:
        [HoldTypeIOS.KeyboardFixMetadataSnapshot] = []

    var publisher: IOSKeyboardFixMetadataPublisher {
        IOSKeyboardFixMetadataPublisher(
            loadCatalog: { .defaults },
            store: IOSKeyboardFixMetadataStoreClient(
                nextRevision: { [self] in
                    lock.withLock {
                        defer { revision += 1 }
                        return revision
                    }
                },
                publish: { [self] snapshot in
                    lock.withLock {
                        snapshotsStorage.append(snapshot)
                    }
                }
            )
        )
    }

    var snapshots: [HoldTypeIOS.KeyboardFixMetadataSnapshot] {
        lock.withLock { snapshotsStorage }
    }
}
