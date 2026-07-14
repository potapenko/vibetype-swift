import Foundation
import HoldTypeDomain
import Testing
@_spi(HoldTypeIOSCore) @testable import HoldTypePersistence
@testable import HoldTypeIOS

@MainActor
struct IOSKeyboardSnapshotPublisherTests {
    @Test func productionContainerQualificationSeedsCanonicalLatest()
        async throws {
        let environment = ProcessInfo.processInfo.environment
        let usesProductionContainers = environment["HOLDTYPE_AUTOMATION"] == "1"
            && environment[
                "HOLDTYPE_AUTOMATION_SEED_KEYBOARD_LATEST"
            ] == "1"
        let temporaryRoot = usesProductionContainers ? nil : FileManager
            .default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            if let temporaryRoot {
                try? FileManager.default.removeItem(at: temporaryRoot)
            }
        }
        let applicationSupportDirectoryURL: URL
        let publisherStore: HoldTypeIOS.KeyboardBridgeStore
        let readerStore: KeyboardBridgeStore
        if usesProductionContainers {
            applicationSupportDirectoryURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            publisherStore = try HoldTypeIOS.KeyboardBridgeStore.appGroup()
            readerStore = try KeyboardBridgeStore.appGroup()
        } else {
            let temporaryRoot = try #require(temporaryRoot)
            applicationSupportDirectoryURL = temporaryRoot
                .appendingPathComponent("app-support", isDirectory: true)
            let bridgeDirectoryURL = temporaryRoot.appendingPathComponent(
                "app-group",
                isDirectory: true
            )
            publisherStore = HoldTypeIOS.KeyboardBridgeStore(
                directoryURL: bridgeDirectoryURL,
                writingOptions: .atomic
            )
            readerStore = KeyboardBridgeStore(
                directoryURL: bridgeDirectoryURL,
                writingOptions: .atomic
            )
        }
        let historyRepository = IOSAcceptedTextHistoryRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        if usesProductionContainers {
            let existingHistory = try await historyRepository.load()
            guard existingHistory == .enabledEmpty else {
                Issue.record(
                    "Qualification seeding requires an empty compact History."
                )
                return
            }
        }
        let persistenceOwner = IOSV1ForegroundVoicePersistenceOwner(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            acceptedTextHistoryRepository: historyRepository
        )
        let existingLatest = try await persistenceOwner.loadLatestResult()
        let existingPending = try await persistenceOwner.load()
        guard existingLatest == .absent, existingPending == nil else {
            Issue.record(
                "Qualification seeding requires an empty canonical Voice state."
            )
            return
        }

        let attemptID = try #require(
            UUID(uuidString: "8D6148F8-7D2C-446A-A407-E7DC092B23F4")
        )
        let transcriptID = try #require(
            UUID(uuidString: "58AD706F-0C9F-41DF-A2A8-AF80A97B7467")
        )
        let deliveryID = try #require(
            UUID(uuidString: "1B53FA50-53D7-453D-A88D-33E01C72750D")
        )
        let acceptedText = "HoldType canonical Latest qualification"
        let createdAt = Date(
            timeIntervalSince1970: floor(Date().timeIntervalSince1970)
        )
        let pending = try IOSV1PendingRecording.qualificationFixture(
            attemptID: attemptID,
            outputIntent: .standard,
            phase: .outputDelivery,
            transcriptionID: transcriptID,
            createdAt: createdAt,
            durationMilliseconds: 1_000,
            byteCount: 1_024
        )
        let repository = IOSVoiceStateRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        _ = try await repository.installPending(pending.state)
        let preparation = try IOSV1ForegroundVoiceAcceptedOutputPreparation(
            deliveryID: deliveryID,
            sessionID: UUID(),
            attemptID: attemptID,
            transcriptID: transcriptID,
            rawAcceptedText: acceptedText,
            outputIntent: .standard
        )
        let acceptance = try await persistenceOwner.accept(
            preparation,
            expectedPending: IOSV1PendingRecordingExpectation(
                recording: pending
            )
        )
        guard case .resultReady(let accepted, _) = acceptance else {
            Issue.record("Expected a canonical accepted result.")
            return
        }
        #expect(try await persistenceOwner.load() == nil)
        guard case .resultReady(let canonical) = try await persistenceOwner
            .loadLatestResult() else {
            Issue.record("Expected persisted canonical Latest.")
            return
        }
        #expect(canonical.resultID == accepted.resultID)
        #expect(canonical.sourceAttemptID == accepted.sourceAttemptID)
        #expect(canonical.acceptedText == accepted.acceptedText)
        let persistedHistory = try await historyRepository.load()
        #expect(persistedHistory.entries.count == 1)
        #expect(persistedHistory.entries.first?.resultID == canonical.resultID)
        #expect(persistedHistory.entries.first?.text == acceptedText)

        let publisher = IOSKeyboardSnapshotPublisher(
            store: publisherStore,
            loadLatest: {
                try await persistenceOwner.loadLatestResult()
            }
        )
        #expect(await publisher.publishCurrent())

        let snapshot = try #require(try readerStore.load())
        #expect(snapshot.schemaVersion == 3)
        #expect(snapshot.latest?.resultID == canonical.resultID)
        #expect(snapshot.latest?.text == acceptedText)
        #expect(snapshot.latest?.createdAt == canonical.createdAt)
        #expect(
            abs(
                (snapshot.latest?.expiresAt.timeIntervalSince(
                    canonical.createdAt
                ) ?? 0) - KeyboardBridgeConfiguration.latestLifetime
            ) <= 0.001
        )
        #expect(snapshot.latestForInsertion() != nil)
    }

    @Test func publishesExactLatestWithSourceBasedExpiry() async throws {
        let fixture = try PublisherStoreFixture()
        defer { fixture.remove() }

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let latest = try publisherLatestRecord(
            text: "Exact line one\n\tExact line two 😀",
            createdAt: now.addingTimeInterval(-30)
        )
        let source = PublisherSource(latest: .resultReady(latest))
        let publisher = makePublisher(fixture: fixture, source: source)

        #expect(await publisher.publishCurrent(at: now))
        let snapshot = try #require(try fixture.readerStore.load())

        #expect(snapshot.revision == 1)
        #expect(snapshot.publishedAt == now)
        #expect(snapshot.latest?.resultID == latest.resultID)
        #expect(snapshot.latest?.text == latest.acceptedText)
        #expect(snapshot.latest?.createdAt == latest.createdAt)
        #expect(
            snapshot.latest?.expiresAt == latest.createdAt.addingTimeInterval(
                KeyboardBridgeConfiguration.latestLifetime
            )
        )
    }

    @Test func republishingExpiredLatestOmitsItsTextFromSharedStorage()
        async throws {
        let fixture = try PublisherStoreFixture()
        defer { fixture.remove() }

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let latest = try publisherLatestRecord(
            text: "Already expired",
            createdAt: now.addingTimeInterval(
                -(KeyboardBridgeConfiguration.latestLifetime + 1)
            )
        )
        let source = PublisherSource(latest: .resultReady(latest))
        let publisher = makePublisher(fixture: fixture, source: source)

        #expect(await publisher.publishCurrent(at: now))
        let snapshot = try #require(try fixture.readerStore.load())

        #expect(snapshot.latest == nil)
        #expect(snapshot.latestForInsertion(at: now) == nil)
    }

    @Test func unprojectableLatestReplacesPreviousSharedTextWithEmptySnapshot()
        async throws {
        let fixture = try PublisherStoreFixture()
        defer { fixture.remove() }

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let source = PublisherSource(
            latest: .resultReady(
                try publisherLatestRecord(text: "Valid", createdAt: now)
            )
        )
        let publisher = makePublisher(fixture: fixture, source: source)

        #expect(await publisher.publishCurrent(at: now))
        let lastValid = try #require(try fixture.readerStore.load())
        #expect(lastValid.latest?.text == "Valid")

        let oversized = try publisherLatestRecord(
            text: String(
                repeating: "x",
                count: KeyboardBridgeConfiguration.maximumTextUTF8Bytes + 1
            ),
            createdAt: now
        )
        await source.setLatest(.resultReady(oversized))
        #expect(!(await publisher.publishCurrent(at: now.addingTimeInterval(1))))
        let cleared = try #require(try fixture.readerStore.load())
        #expect(cleared.revision == lastValid.revision + 1)
        #expect(cleared.latest == nil)
    }

    @Test func canonicalLoadFailurePreservesLastKnownSnapshot()
        async throws {
        let fixture = try PublisherStoreFixture()
        defer { fixture.remove() }

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let source = PublisherSource(
            latest: .resultReady(
                try publisherLatestRecord(text: "Valid", createdAt: now)
            )
        )
        let publisher = makePublisher(fixture: fixture, source: source)

        #expect(await publisher.publishCurrent(at: now))
        let lastKnown = try #require(try fixture.readerStore.load())

        await source.failNextLatestLoad()
        #expect(!(await publisher.publishCurrent(at: now.addingTimeInterval(1))))
        #expect(try fixture.readerStore.load() == lastKnown)
    }

    @Test func unavailableReadAndWriteBoundariesReturnFalse() async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let source = PublisherSource(latest: .absent)
        let unavailable = IOSKeyboardSnapshotPublisher(
            store: nil,
            loadLatest: { try await source.loadLatest() }
        )

        #expect(!(await unavailable.publishCurrent(at: now)))
        #expect(await source.latestLoadCount == 0)

        let corrupt = try PublisherStoreFixture()
        defer { corrupt.remove() }
        try corrupt.write(Data("not-json".utf8))
        let corruptPublisher = makePublisher(fixture: corrupt, source: source)
        #expect(await corruptPublisher.publishCurrent(at: now))
        let repaired = try #require(try corrupt.readerStore.load())
        #expect(repaired.revision == 1)
        #expect(repaired.latest == nil)

        let blockedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: blockedRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: blockedRoot) }
        let blockedDirectory = blockedRoot.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: blockedDirectory)
        let blockedPublisher = IOSKeyboardSnapshotPublisher(
            store: HoldTypeIOS.KeyboardBridgeStore(
                directoryURL: blockedDirectory,
                writingOptions: .atomic
            ),
            loadLatest: { try await source.loadLatest() }
        )
        #expect(!(await blockedPublisher.publishCurrent(at: now)))

        try corrupt.write(Data("{\"revision\":3,\"schemaVersion\":99}".utf8))
        #expect(!(await corruptPublisher.publishCurrent(at: now)))
    }

    @Test func concurrentRequestsSerializeWholePublicationsAndIncreaseRevision()
        async throws {
        let fixture = try PublisherStoreFixture()
        defer { fixture.remove() }

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let source = BlockingPublisherSource(
            latest: .resultReady(
                try publisherLatestRecord(text: "Latest", createdAt: now)
            )
        )
        let publisher = IOSKeyboardSnapshotPublisher(
            store: fixture.publisherStore,
            loadLatest: { await source.loadLatest() }
        )

        let first = Task {
            await publisher.publishCurrent(at: now)
        }
        await source.waitUntilFirstLatestLoadStarts()

        let second = Task {
            await publisher.publishCurrent(at: now.addingTimeInterval(1))
        }
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(await source.latestLoadCount == 1)
        await source.releaseFirstLatestLoad()
        #expect(await first.value)
        #expect(await second.value)

        #expect(
            await source.events == [
                "latest-1-start",
                "latest-1-finish",
                "latest-2-start",
                "latest-2-finish",
            ]
        )
        let snapshot = try #require(try fixture.readerStore.load())
        #expect(snapshot.revision == 2)
        #expect(snapshot.publishedAt == now.addingTimeInterval(1))
    }
}

private enum PublisherTestError: Error {
    case injected
}

private actor PublisherSource {
    private var latest: IOSV1ForegroundVoiceLatestResultObservation
    private var shouldFailNextLatestLoad = false
    private(set) var latestLoadCount = 0

    init(latest: IOSV1ForegroundVoiceLatestResultObservation) {
        self.latest = latest
    }

    func loadLatest() throws -> IOSV1ForegroundVoiceLatestResultObservation {
        latestLoadCount += 1
        if shouldFailNextLatestLoad {
            shouldFailNextLatestLoad = false
            throw PublisherTestError.injected
        }
        return latest
    }

    func setLatest(_ latest: IOSV1ForegroundVoiceLatestResultObservation) {
        self.latest = latest
    }

    func failNextLatestLoad() {
        shouldFailNextLatestLoad = true
    }
}

private actor BlockingPublisherSource {
    private let latest: IOSV1ForegroundVoiceLatestResultObservation
    private var firstLatestLoadStarted = false
    private var firstLatestLoadRelease: CheckedContinuation<Void, Never>?
    private var firstLatestLoadStartWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var latestLoadCount = 0
    private(set) var events: [String] = []

    init(latest: IOSV1ForegroundVoiceLatestResultObservation) {
        self.latest = latest
    }

    func loadLatest() async -> IOSV1ForegroundVoiceLatestResultObservation {
        latestLoadCount += 1
        let call = latestLoadCount
        events.append("latest-\(call)-start")

        if call == 1 {
            firstLatestLoadStarted = true
            firstLatestLoadStartWaiters.forEach { $0.resume() }
            firstLatestLoadStartWaiters.removeAll()
            await withCheckedContinuation { continuation in
                firstLatestLoadRelease = continuation
            }
        }

        events.append("latest-\(call)-finish")
        return latest
    }

    func waitUntilFirstLatestLoadStarts() async {
        guard !firstLatestLoadStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            firstLatestLoadStartWaiters.append(continuation)
        }
    }

    func releaseFirstLatestLoad() {
        firstLatestLoadRelease?.resume()
        firstLatestLoadRelease = nil
    }
}

@MainActor
private struct PublisherStoreFixture {
    let directoryURL: URL
    let publisherStore: HoldTypeIOS.KeyboardBridgeStore
    let readerStore: KeyboardBridgeStore

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        publisherStore = HoldTypeIOS.KeyboardBridgeStore(
            directoryURL: directoryURL,
            writingOptions: .atomic
        )
        readerStore = KeyboardBridgeStore(
            directoryURL: directoryURL,
            writingOptions: .atomic
        )
    }

    func write(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try data.write(to: snapshotURL, options: .atomic)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private var snapshotURL: URL {
        directoryURL.appendingPathComponent(
            KeyboardBridgeConfiguration.snapshotFilename,
            isDirectory: false
        )
    }
}

@MainActor
private func makePublisher(
    fixture: PublisherStoreFixture,
    source: PublisherSource
) -> IOSKeyboardSnapshotPublisher {
    IOSKeyboardSnapshotPublisher(
        store: fixture.publisherStore,
        loadLatest: { try await source.loadLatest() }
    )
}

private func publisherLatestRecord(
    text: String,
    createdAt: Date
) throws -> IOSV1AcceptedOutputDeliveryRecord {
    try IOSV1AcceptedOutputDeliveryRecord(
        resultID: UUID(),
        sourceAttemptID: UUID(),
        acceptedText: text,
        createdAt: createdAt
    )
}
