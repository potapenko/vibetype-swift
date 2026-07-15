import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

@Suite(.serialized)
struct IOSAcceptedAudioCacheTests {
    @Test func cacheIsOffByDefaultPolicyAndMissingFilesStayUnavailable()
        async throws {
        let fixture = AudioCacheFixture()

        #expect(
            await fixture.cache.cachedAudioFileURLIfAvailable(
                resultID: CacheIDs.first
            ) == nil
        )
        #expect(
            try await fixture.cache.retainAcceptedAudio(
                Data([1, 2, 3]),
                resultID: CacheIDs.first,
                fileExtension: "m4a",
                createdAt: CacheDates.first,
                policy: .deleteImmediately
            ) == nil
        )
        #expect(
            await fixture.cache.cachedAudioFileURLIfAvailable(
                resultID: CacheIDs.first
            ) == nil
        )
    }

    @Test func enabledCacheStoresAcceptedAudioByResultIdentifier()
        async throws {
        let fixture = AudioCacheFixture()

        let url = try #require(
            try await fixture.cache.retainAcceptedAudio(
                Data([1, 2, 3]),
                resultID: CacheIDs.first,
                fileExtension: "m4a",
                createdAt: CacheDates.first,
                policy: .keepLast(10)
            )
        )

        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
        #expect(
            await fixture.cache.cachedAudioFileURLIfAvailable(
                resultID: CacheIDs.first
            ) == url
        )
        #expect(
            try await fixture.cache.retainAcceptedAudio(
                Data([1, 2, 3]),
                resultID: CacheIDs.first,
                fileExtension: "m4a",
                createdAt: CacheDates.first,
                policy: .keepLast(10)
            ) == url
        )
    }

    @Test func defaultIOSPolicyKeepsAudioForEveryHistorySlot() async throws {
        let fixture = AudioCacheFixture()
        let policy = IOSAppSettings.defaultRecordingCachePolicy
        let resultIDs = (0...IOSAcceptedTextHistoryRecord.maximumEntryCount)
            .map { _ in UUID() }

        #expect(
            policy
                == .keepLast(IOSAcceptedTextHistoryRecord.maximumEntryCount)
        )

        for (index, resultID) in resultIDs.enumerated() {
            _ = try await fixture.cache.retainAcceptedAudio(
                Data([UInt8(index)]),
                resultID: resultID,
                fileExtension: "m4a",
                createdAt: Date(timeIntervalSince1970: Double(index + 1)),
                policy: policy
            )
        }

        #expect(
            await fixture.cache.cachedAudioFileURLIfAvailable(
                resultID: resultIDs[0]
            ) == nil
        )
        for resultID in resultIDs.dropFirst() {
            #expect(
                await fixture.cache.cachedAudioFileURLIfAvailable(
                    resultID: resultID
                ) != nil
            )
        }
    }

    @Test func boundedReconciliationIsIdempotentAndPreservesUnmanagedFiles()
        async throws {
        let fixture = AudioCacheFixture()
        let unmanagedURL = fixture.directoryURL.appendingPathComponent(
            "operator-note.txt"
        )

        _ = try await fixture.cache.retainAcceptedAudio(
            Data([1]),
            resultID: CacheIDs.first,
            fileExtension: "m4a",
            createdAt: CacheDates.first,
            policy: .unlimited
        )
        try Data("keep".utf8).write(to: unmanagedURL)
        _ = try await fixture.cache.retainAcceptedAudio(
            Data([2]),
            resultID: CacheIDs.second,
            fileExtension: "wav",
            createdAt: CacheDates.second,
            policy: .unlimited
        )
        _ = try await fixture.cache.retainAcceptedAudio(
            Data([3]),
            resultID: CacheIDs.third,
            fileExtension: "m4a",
            createdAt: CacheDates.third,
            policy: .unlimited
        )
        #expect(
            await fixture.cache.cachedAudioFileURLIfAvailable(
                resultID: CacheIDs.first
            ) != nil
        )
        #expect(
            await fixture.cache.cachedAudioFileURLIfAvailable(
                resultID: CacheIDs.second
            ) != nil
        )
        #expect(
            await fixture.cache.cachedAudioFileURLIfAvailable(
                resultID: CacheIDs.third
            ) != nil
        )

        try await fixture.cache.reconcile(policy: .keepLast(2))
        try await fixture.cache.reconcile(policy: .keepLast(2))

        #expect(
            await fixture.cache.cachedAudioFileURLIfAvailable(
                resultID: CacheIDs.first
            ) == nil
        )
        #expect(
            await fixture.cache.cachedAudioFileURLIfAvailable(
                resultID: CacheIDs.second
            ) != nil
        )
        #expect(
            await fixture.cache.cachedAudioFileURLIfAvailable(
                resultID: CacheIDs.third
            ) != nil
        )
        #expect(try Data(contentsOf: unmanagedURL) == Data("keep".utf8))

        try await fixture.cache.reconcile(policy: .deleteImmediately)
        #expect(
            await fixture.cache.cachedAudioFileURLIfAvailable(
                resultID: CacheIDs.second
            ) == nil
        )
        #expect(
            await fixture.cache.cachedAudioFileURLIfAvailable(
                resultID: CacheIDs.third
            ) == nil
        )
        #expect(try Data(contentsOf: unmanagedURL) == Data("keep".utf8))
    }
}

private final class AudioCacheFixture: @unchecked Sendable {
    let directoryURL: URL
    let cache: IOSAcceptedAudioCache

    init() {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ios-accepted-audio-cache-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        cache = IOSAcceptedAudioCache(directoryURL: directoryURL)
    }

    deinit {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private enum CacheIDs {
    static let first = UUID(
        uuidString: "10000000-0000-0000-0000-000000000001"
    )!
    static let second = UUID(
        uuidString: "20000000-0000-0000-0000-000000000002"
    )!
    static let third = UUID(
        uuidString: "30000000-0000-0000-0000-000000000003"
    )!
}

private enum CacheDates {
    static let first = Date(timeIntervalSince1970: 1_700_000_001)
    static let second = Date(timeIntervalSince1970: 1_700_000_002)
    static let third = Date(timeIntervalSince1970: 1_700_000_003)
}
