//
//  RecordingCacheService.swift
//  HoldType
//
//  Created by Codex on 7/6/26.
//

import AppKit
import Foundation
import HoldTypeDomain

struct RecordingCacheItem: Equatable, Identifiable {
    var id: String {
        fileURL.path
    }

    let fileURL: URL
    let byteCount: Int64
    let createdAt: Date

    var fileName: String {
        fileURL.lastPathComponent
    }
}

struct RecordingCacheSummary: Equatable {
    let directoryURL: URL
    let items: [RecordingCacheItem]

    var fileCount: Int {
        items.count
    }

    var totalByteCount: Int64 {
        items.reduce(0) { total, item in
            total + item.byteCount
        }
    }

    var isEmpty: Bool {
        items.isEmpty
    }
}

enum RecordingCacheServiceError: Error, Equatable, LocalizedError {
    case directoryUnavailable
    case listingFailed
    case unsupportedRecordingURL
    case recordingProtected
    case deleteFailed
    case clearFailed

    var errorDescription: String? {
        switch self {
        case .directoryUnavailable:
            return "Recording cache directory could not be prepared."
        case .listingFailed:
            return "Recording cache could not be read."
        case .unsupportedRecordingURL:
            return "Only HoldType recording cache files can be changed."
        case .recordingProtected:
            return "An active or unfinished recording cannot be removed from the cache."
        case .deleteFailed:
            return "Recording cache file could not be deleted."
        case .clearFailed:
            return "Recording cache could not be cleared."
        }
    }
}

protocol RecordingCacheManaging: RecordingCacheLifecycleHandling {
    var directoryURL: URL { get }

    func summary() throws -> RecordingCacheSummary
    func handleCompletedRecording(at fileURL: URL, policy: RecordingCachePolicy) throws
    func applyRetentionPolicy(_ policy: RecordingCachePolicy) throws
    func deleteRecording(at fileURL: URL) throws
    func clearCache() throws
    func revealInFinder(_ fileURL: URL)
}

extension RecordingCacheManaging {
    func handleCompletedRecording(
        _ artifact: AudioRecordingArtifact,
        policy: RecordingCachePolicy
    ) throws {
        try handleCompletedRecording(at: artifact.fileURL, policy: policy)
    }
}

struct RecordingCacheService: RecordingCacheManaging {
    static let shared = RecordingCacheService()

    private static let supportedFileExtensions = Set(["m4a", "wav"])

    let directoryURL: URL

    private let legacyDirectoryURL: URL?
    private let fileManager: FileManager
    private let now: () -> Date
    private let uuidProvider: () -> UUID

    init(
        directoryURL: URL? = nil,
        legacyDirectoryURL: URL? = FileManager.default.temporaryDirectory
            .appendingPathComponent("holdtype-recordings", isDirectory: true),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        uuidProvider: @escaping () -> UUID = UUID.init
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.legacyDirectoryURL = legacyDirectoryURL
        self.now = now
        self.uuidProvider = uuidProvider
    }

    func makeRecordingFileURL() throws -> URL {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw RecordingCacheServiceError.directoryUnavailable
        }

        let timestamp = Self.fileTimestamp(from: now())
        let uuidPrefix = String(uuidProvider().uuidString.prefix(8)).lowercased()
        return directoryURL
            .appendingPathComponent("HoldType-\(timestamp)-\(uuidPrefix)")
            .appendingPathExtension("m4a")
    }

    func summary() throws -> RecordingCacheSummary {
        do {
            let items = try managedDirectoryURLs
                .flatMap { directoryURL in
                    try recordingItems(in: directoryURL)
                }
                .sorted { lhs, rhs in
                    lhs.createdAt > rhs.createdAt
                }

            return RecordingCacheSummary(directoryURL: directoryURL, items: items)
        } catch let error as RecordingCacheServiceError {
            throw error
        } catch {
            throw RecordingCacheServiceError.listingFailed
        }
    }

    func handleCompletedRecording(at fileURL: URL, policy: RecordingCachePolicy) throws {
        guard isManagedRecordingFileURL(fileURL) else {
            return
        }
        guard !RecordingCaptureJournal.isProtectedCaptureFileURL(fileURL) else {
            throw RecordingCacheServiceError.recordingProtected
        }

        switch policy.normalized {
        case .deleteImmediately:
            try deleteRecording(at: fileURL)
        case .keepLast(let count):
            try pruneRecordings(keepingMostRecent: count)
            notifyCacheDidChange()
        case .unlimited:
            notifyCacheDidChange()
        }
    }

    func applyRetentionPolicy(_ policy: RecordingCachePolicy) throws {
        switch policy.normalized {
        case .deleteImmediately, .unlimited:
            return
        case .keepLast(let count):
            try pruneRecordings(keepingMostRecent: count)
            notifyCacheDidChange()
        }
    }

    func deleteRecording(at fileURL: URL) throws {
        guard isManagedRecordingFileURL(fileURL) else {
            throw RecordingCacheServiceError.unsupportedRecordingURL
        }
        guard !RecordingCaptureJournal.isProtectedCaptureFileURL(fileURL) else {
            throw RecordingCacheServiceError.recordingProtected
        }

        let path = fileURL.path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return
        }

        guard !isDirectory.boolValue else {
            throw RecordingCacheServiceError.unsupportedRecordingURL
        }

        do {
            try fileManager.removeItem(at: fileURL)
            notifyCacheDidChange()
        } catch {
            throw RecordingCacheServiceError.deleteFailed
        }
    }

    func clearCache() throws {
        do {
            for item in try summary().items {
                try deleteRecording(at: item.fileURL)
            }
            notifyCacheDidChange()
        } catch let error as RecordingCacheServiceError {
            if error == .deleteFailed {
                throw RecordingCacheServiceError.clearFailed
            }

            throw error
        } catch {
            throw RecordingCacheServiceError.clearFailed
        }
    }

    func revealInFinder(_ fileURL: URL) {
        if fileURL == directoryURL {
            NSWorkspace.shared.open(directoryURL)
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private var managedDirectoryURLs: [URL] {
        [directoryURL, legacyDirectoryURL].compactMap { $0 }
    }

    private func recordingItems(in directoryURL: URL) throws -> [RecordingCacheItem] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
            return []
        }

        guard isDirectory.boolValue else {
            throw RecordingCacheServiceError.listingFailed
        }

        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return fileURLs.compactMap { fileURL in
            guard Self.supportedFileExtensions.contains(fileURL.pathExtension.lowercased()),
                  isManagedRecordingFileURL(fileURL),
                  !RecordingCaptureJournal.isProtectedCaptureFileURL(fileURL) else {
                return nil
            }

            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]
            ),
                values.isRegularFile == true else {
                return nil
            }

            return RecordingCacheItem(
                fileURL: fileURL,
                byteCount: Int64(values.fileSize ?? 0),
                createdAt: values.creationDate ?? values.contentModificationDate ?? .distantPast
            )
        }
    }

    private func pruneRecordings(keepingMostRecent count: Int) throws {
        let retainedCount = RecordingCachePolicy.normalizedRetainedRecordingLimit(count)
        let items = try summary().items

        guard items.count > retainedCount else {
            return
        }

        for item in items.dropFirst(retainedCount) {
            try deleteRecording(at: item.fileURL)
        }
    }

    private func isManagedRecordingFileURL(_ fileURL: URL) -> Bool {
        guard Self.supportedFileExtensions.contains(fileURL.pathExtension.lowercased()) else {
            return false
        }

        let standardizedPath = fileURL.standardizedFileURL.path
        return managedDirectoryURLs.contains { directoryURL in
            let directoryPath = directoryURL.standardizedFileURL.path
            return standardizedPath.hasPrefix(directoryPath + "/")
        }
    }

    private func notifyCacheDidChange() {
        NotificationCenter.default.post(name: .recordingCacheDidChange, object: nil)
    }

    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        let cachesRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        return cachesRoot
            .appendingPathComponent("HoldType", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    private static func fileTimestamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

extension Notification.Name {
    static let recordingCacheDidChange = Notification.Name("holdtype.recordingCacheDidChange")
}
