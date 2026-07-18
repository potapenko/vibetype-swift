//
//  RecordingCacheServiceTests.swift
//  HoldTypeTests
//
//  Created by Codex on 7/6/26.
//

import Foundation
import HoldTypeDomain
import Testing
@testable import HoldType

struct RecordingCacheServiceTests {

    @Test func makesRecordingFileURLInsideCacheDirectory() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let cacheURL = rootURL.appendingPathComponent("Recordings", isDirectory: true)
        let service = RecordingCacheService(
            directoryURL: cacheURL,
            legacyDirectoryURL: nil,
            now: { Date(timeIntervalSince1970: 1_783_333_503) },
            uuidProvider: { UUID(uuidString: "00000000-0000-0000-0000-00000000CAFE")! }
        )

        let fileURL = try service.makeRecordingFileURL()

        #expect(fileURL.deletingLastPathComponent() == cacheURL)
        #expect(fileURL.lastPathComponent.hasPrefix("HoldType-"))
        #expect(fileURL.lastPathComponent.hasSuffix("-00000000.m4a"))
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    @Test func summaryListsManagedAudioFilesNewestFirstAndTotalsSize() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let cacheURL = rootURL.appendingPathComponent("Recordings", isDirectory: true)
        let service = RecordingCacheService(directoryURL: cacheURL, legacyDirectoryURL: nil)
        let olderURL = try writeRecording(named: "older.m4a", bytes: 3, in: cacheURL)
        let newerURL = try writeRecording(named: "newer.wav", bytes: 5, in: cacheURL)
        _ = try writeRecording(named: "ignored.txt", bytes: 20, in: cacheURL)
        try setDates(fileURL: olderURL, timestamp: 10)
        try setDates(fileURL: newerURL, timestamp: 20)

        let summary = try service.summary()

        #expect(summary.items.map(\.fileName) == ["newer.wav", "older.m4a"])
        #expect(summary.totalByteCount == 8)
        #expect(summary.fileCount == 2)
    }

    @Test func keepLastPolicyPrunesOldestManagedRecordings() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let cacheURL = rootURL.appendingPathComponent("Recordings", isDirectory: true)
        let service = RecordingCacheService(directoryURL: cacheURL, legacyDirectoryURL: nil)
        let oldestURL = try writeRecording(named: "oldest.m4a", bytes: 1, in: cacheURL)
        let middleURL = try writeRecording(named: "middle.m4a", bytes: 1, in: cacheURL)
        let newestURL = try writeRecording(named: "newest.m4a", bytes: 1, in: cacheURL)
        try setDates(fileURL: oldestURL, timestamp: 10)
        try setDates(fileURL: middleURL, timestamp: 20)
        try setDates(fileURL: newestURL, timestamp: 30)

        try service.handleCompletedRecording(at: newestURL, policy: .keepLast(2))

        #expect(FileManager.default.fileExists(atPath: oldestURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: middleURL.path))
        #expect(FileManager.default.fileExists(atPath: newestURL.path))
    }

    @Test func unlimitedPolicyDoesNotPruneManagedRecordings() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let cacheURL = rootURL.appendingPathComponent("Recordings", isDirectory: true)
        let service = RecordingCacheService(directoryURL: cacheURL, legacyDirectoryURL: nil)
        let firstURL = try writeRecording(named: "first.m4a", bytes: 1, in: cacheURL)
        let secondURL = try writeRecording(named: "second.m4a", bytes: 1, in: cacheURL)

        try service.handleCompletedRecording(at: secondURL, policy: .unlimited)

        #expect(FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path))
    }

    @Test func deleteImmediatelyPolicyDeletesCompletedManagedRecording() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let cacheURL = rootURL.appendingPathComponent("Recordings", isDirectory: true)
        let service = RecordingCacheService(directoryURL: cacheURL, legacyDirectoryURL: nil)
        let fileURL = try writeRecording(named: "recording.m4a", bytes: 1, in: cacheURL)

        try service.handleCompletedRecording(at: fileURL, policy: .deleteImmediately)

        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test func lifecycleAdapterForwardsArtifactURLAndRawPolicy() throws {
        let manager = RecordingCacheManagingSpy()
        let lifecycle: any RecordingCacheLifecycleHandling = manager
        let artifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/holdtype-cache-adapter.m4a"),
            duration: 8.5,
            byteCount: 32_768
        )

        try lifecycle.handleCompletedRecording(artifact, policy: .keepLast(0))

        #expect(manager.completedRecordingCalls == [
            .init(fileURL: artifact.fileURL, policy: .keepLast(0))
        ])
    }

    @Test func rejectsDeletingUnmanagedRecordingPath() throws {
        let rootURL = try makeTemporaryDirectory()
        let outsideURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        defer { try? FileManager.default.removeItem(at: outsideURL) }

        let cacheURL = rootURL.appendingPathComponent("Recordings", isDirectory: true)
        let service = RecordingCacheService(directoryURL: cacheURL, legacyDirectoryURL: nil)
        let outsideRecordingURL = try writeRecording(named: "outside.m4a", bytes: 1, in: outsideURL)

        #expect(throws: RecordingCacheServiceError.unsupportedRecordingURL) {
            try service.deleteRecording(at: outsideRecordingURL)
        }
        #expect(FileManager.default.fileExists(atPath: outsideRecordingURL.path))
    }

    @Test func clearCacheDeletesManagedAudioFilesOnly() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let cacheURL = rootURL.appendingPathComponent("Recordings", isDirectory: true)
        let service = RecordingCacheService(directoryURL: cacheURL, legacyDirectoryURL: nil)
        let audioURL = try writeRecording(named: "recording.m4a", bytes: 1, in: cacheURL)
        let textURL = try writeRecording(named: "note.txt", bytes: 1, in: cacheURL)

        try service.clearCache()

        #expect(FileManager.default.fileExists(atPath: audioURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: textURL.path))
    }

    @MainActor
    @Test func activeCaptureIsExcludedFromEveryCacheMutation() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let cacheURL = rootURL.appendingPathComponent("Recordings", isDirectory: true)
        let service = RecordingCacheService(directoryURL: cacheURL, legacyDirectoryURL: nil)
        let journal = RecordingCaptureJournal(directoryURL: cacheURL)
        let lease = try journal.prepareCapture(
            settings: .defaults,
            maximumDuration: 300
        )
        let contents = Data("active capture".utf8)
        try contents.write(to: lease.audioFileURL)
        _ = try writeRecording(
            named: "ordinary.m4a",
            bytes: 1,
            in: cacheURL
        )

        #expect(try service.summary().items.map(\.fileName) == ["ordinary.m4a"])
        #expect(throws: RecordingCacheServiceError.recordingProtected) {
            try service.handleCompletedRecording(
                at: lease.audioFileURL,
                policy: .deleteImmediately
            )
        }
        #expect(throws: RecordingCacheServiceError.recordingProtected) {
            try service.deleteRecording(at: lease.audioFileURL)
        }

        try service.applyRetentionPolicy(.keepLast(0))
        #expect(FileManager.default.fileExists(atPath: lease.audioFileURL.path))
        #expect(try Data(contentsOf: lease.audioFileURL) == contents)

        try service.clearCache()
        #expect(FileManager.default.fileExists(atPath: lease.audioFileURL.path))
        #expect(try Data(contentsOf: lease.audioFileURL) == contents)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("holdtype-recording-cache-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func writeRecording(named fileName: String, bytes: Int, in directoryURL: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent(fileName)
        try Data(repeating: 0x01, count: bytes).write(to: fileURL)
        return fileURL
    }

    private func setDates(fileURL: URL, timestamp: TimeInterval) throws {
        let date = Date(timeIntervalSince1970: timestamp)
        try FileManager.default.setAttributes(
            [
                .creationDate: date,
                .modificationDate: date,
            ],
            ofItemAtPath: fileURL.path
        )
    }
}

private final class RecordingCacheManagingSpy: RecordingCacheManaging {
    struct CompletedRecordingCall: Equatable {
        let fileURL: URL
        let policy: RecordingCachePolicy
    }

    let directoryURL = URL(fileURLWithPath: "/tmp/holdtype-cache-manager-spy", isDirectory: true)
    private(set) var completedRecordingCalls: [CompletedRecordingCall] = []

    func summary() throws -> RecordingCacheSummary {
        RecordingCacheSummary(directoryURL: directoryURL, items: [])
    }

    func handleCompletedRecording(at fileURL: URL, policy: RecordingCachePolicy) throws {
        completedRecordingCalls.append(.init(fileURL: fileURL, policy: policy))
    }

    func applyRetentionPolicy(_ policy: RecordingCachePolicy) throws {}

    func deleteRecording(at fileURL: URL) throws {}

    func clearCache() throws {}

    func revealInFinder(_ fileURL: URL) {}
}
