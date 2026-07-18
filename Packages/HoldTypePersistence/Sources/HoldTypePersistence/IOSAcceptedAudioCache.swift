import Foundation
import HoldTypeDomain

public enum IOSAcceptedAudioCacheError: Error, Equatable, Sendable {
    case invalidAudio
    case identifierCollision
    case staleSavedRecording
    case storageUnavailable
}

/// Selects whether accepted audio follows the user's optional Recording Cache
/// policy or remains a bounded Saved Recording after the configured boundary.
public enum IOSAcceptedAudioRetention: String, Equatable, Sendable {
    case recordingCachePolicy
    case savedFiveMinute

    private static func savedRecordingMinimumDurationMilliseconds(
        for recordingDurationLimit: RecordingDurationLimit
    ) -> Int64 {
        Int64(recordingDurationLimit.wholeSeconds) * 1_000 - 500
    }

    public static func resolved(
        requested: Self,
        finalizedDurationMilliseconds: Int64,
        recordingDurationLimit: RecordingDurationLimit
    ) -> Self {
        if requested == .savedFiveMinute
            || finalizedDurationMilliseconds
                >= savedRecordingMinimumDurationMilliseconds(
                    for: recordingDurationLimit
                ) {
            return .savedFiveMinute
        }
        return .recordingCachePolicy
    }
}

/// Content-free identity for one completed limit-ended Saved Recording.
public struct IOSSavedAcceptedRecording: Equatable, Identifiable, Sendable {
    public let resultID: UUID
    public let createdAt: Date

    public var id: UUID { resultID }

    public init(resultID: UUID, createdAt: Date) {
        self.resultID = resultID
        self.createdAt = createdAt
    }
}

public enum IOSSavedAcceptedRecordingDiscardResult: Equatable, Sendable {
    case discarded
    case alreadyAbsent
}

/// App-private accepted recording files, independent from text History.
public actor IOSAcceptedAudioCache {
    public static let maximumAudioByteCount = 25_000_000
    public static let maximumSavedRecordingCount =
        RetentionConfiguration.failedHistoryEntryLimit

    private static let filePolicy = ProtectedAtomicMetadataFilePolicy(
        maximumByteCount: maximumAudioByteCount,
        fileProtection: .complete,
        excludesFromBackup: true
    )

    private let directoryURL: URL
    private let fileSystem: any ProtectedAtomicMetadataFileSystem

    public init(applicationSupportDirectoryURL: URL) {
        directoryURL = applicationSupportDirectoryURL
            .appendingPathComponent("HoldType", isDirectory: true)
            .appendingPathComponent("RecordingCache", isDirectory: true)
        fileSystem = FoundationProtectedAtomicMetadataFileSystem()
    }

    init(
        directoryURL: URL,
        fileSystem: any ProtectedAtomicMetadataFileSystem =
            FoundationProtectedAtomicMetadataFileSystem()
    ) {
        self.directoryURL = directoryURL
        self.fileSystem = fileSystem
    }

    /// Returns only a regular, non-empty cache file owned by this cache.
    public func cachedAudioFileURLIfAvailable(resultID: UUID) -> URL? {
        let matches = (try? managedFiles())?.filter {
            $0.resultID == resultID
        } ?? []
        guard matches.count == 1 else { return nil }
        return matches[0].url
    }

    /// Resolves only the independently retained copy that can prove a prior
    /// limit-ended publish completed before Pending cleanup was interrupted.
    /// Result identity alone is insufficient: the managed namespace, media
    /// extension, and exact byte count must all still match Pending metadata.
    func savedAudioFileURLIfAvailable(
        resultID: UUID,
        fileExtension: String,
        byteCount: Int64
    ) throws -> URL? {
        guard Self.isAllowedFileExtension(fileExtension),
              byteCount > 0,
              byteCount <= Self.maximumAudioByteCount else {
            throw IOSAcceptedAudioCacheError.invalidAudio
        }
        let matches = try managedFiles().filter {
            $0.retention == .savedFiveMinute
                && $0.resultID == resultID
        }
        guard matches.count <= 1 else {
            throw IOSAcceptedAudioCacheError.identifierCollision
        }
        guard let match = matches.first else { return nil }
        guard match.fileExtension == fileExtension,
              match.byteCount == byteCount else {
            throw IOSAcceptedAudioCacheError.identifierCollision
        }
        return match.url
    }

    /// Returns independently retained limit-ended recordings newest first.
    /// Text History and Recording Cache settings do not own this list.
    public func savedRecordings() throws -> [IOSSavedAcceptedRecording] {
        try managedFiles()
            .filter { $0.retention == .savedFiveMinute }
            .sorted(by: Self.isNewer)
            .map {
                IOSSavedAcceptedRecording(
                    resultID: $0.resultID,
                    createdAt: $0.modificationDate
                )
            }
    }

    /// Resolves only the exact Saved Recording represented by the caller's
    /// current snapshot. A stale row cannot play a replacement file.
    public func savedAudioFileURL(
        ifCurrent expected: IOSSavedAcceptedRecording
    ) throws -> URL? {
        let matches = try managedFiles().filter {
            $0.retention == .savedFiveMinute
                && $0.resultID == expected.resultID
        }
        guard !matches.isEmpty else { return nil }
        guard matches.count == 1,
              matches[0].modificationDate == expected.createdAt else {
            throw IOSAcceptedAudioCacheError.staleSavedRecording
        }
        return matches[0].url
    }

    /// Removes only the exact Saved Recording represented by the caller's
    /// current snapshot. Ordinary Recording Cache audio is never touched.
    public func discardSavedRecording(
        ifCurrent expected: IOSSavedAcceptedRecording
    ) throws -> IOSSavedAcceptedRecordingDiscardResult {
        guard let fileURL = try savedAudioFileURL(ifCurrent: expected) else {
            return .alreadyAbsent
        }
        do {
            try fileSystem.removeFileIfPresent(at: fileURL)
            return .discarded
        } catch {
            throw IOSAcceptedAudioCacheError.storageUnavailable
        }
    }

    /// Applies policy only to ordinary accepted cache entries. Saved
    /// limit-ended recordings remain independently playable.
    public func playableAudioFileURL(
        resultID: UUID,
        policy: RecordingCachePolicy
    ) throws -> URL? {
        let matches = try managedFiles().filter { $0.resultID == resultID }
        guard matches.count <= 1 else {
            throw IOSAcceptedAudioCacheError.identifierCollision
        }
        guard let match = matches.first else { return nil }
        if match.retention == .recordingCachePolicy,
           !policy.normalized.keepsRecordings {
            return nil
        }
        return match.url
    }

    /// Applies the current cache policy without inspecting or changing History.
    public func reconcile(policy: RecordingCachePolicy) throws {
        try reconcileUnlocked(policy: policy.normalized)
    }

    @discardableResult
    func retainAcceptedAudio(
        _ data: Data,
        resultID: UUID,
        fileExtension: String,
        createdAt: Date,
        policy: RecordingCachePolicy,
        retention: IOSAcceptedAudioRetention = .recordingCachePolicy
    ) throws -> URL? {
        let policy = policy.normalized
        guard retention == .savedFiveMinute || policy.keepsRecordings else {
            return nil
        }
        guard !data.isEmpty,
              data.count <= Self.maximumAudioByteCount,
              Self.isAllowedFileExtension(fileExtension),
              createdAt.timeIntervalSince1970.isFinite,
              createdAt.timeIntervalSince1970 >= 0 else {
            throw IOSAcceptedAudioCacheError.invalidAudio
        }

        let existing = try managedFiles().filter {
            $0.resultID == resultID
        }
        let destination = fileURL(
            resultID: resultID,
            fileExtension: fileExtension,
            retention: retention
        )
        if let existingFile = existing.first {
            let existingData = try? fileSystem.readFileIfPresent(
                at: existingFile.url,
                policy: Self.filePolicy
            )
            guard existing.count == 1,
                  existingFile.url.lastPathComponent
                    == destination.lastPathComponent,
                  existingFile.retention == retention,
                  existingData == data else {
                throw IOSAcceptedAudioCacheError.identifierCollision
            }
            try applyCreationDate(createdAt, to: existingFile.url)
            try reconcileUnlocked(policy: policy)
            return try cachedAudioFileURLIfAvailableUnlocked(
                resultID: resultID
            )
        }

        do {
            try fileSystem.replaceFileAtomically(
                at: destination,
                with: data,
                policy: Self.filePolicy
            )
            try applyCreationDate(createdAt, to: destination)
            try reconcileUnlocked(policy: policy)
            return try cachedAudioFileURLIfAvailableUnlocked(
                resultID: resultID
            )
        } catch let error as IOSAcceptedAudioCacheError {
            throw error
        } catch {
            throw IOSAcceptedAudioCacheError.storageUnavailable
        }
    }

    private func reconcileUnlocked(
        policy: RecordingCachePolicy
    ) throws {
        let files = try managedFiles().sorted(by: Self.isNewer)
        let policyManagedFiles = files.filter {
            $0.retention == .recordingCachePolicy
        }
        let savedFiles = files.filter { $0.retention == .savedFiveMinute }
        let retainedPolicyManagedCount: Int
        switch policy {
        case .deleteImmediately:
            retainedPolicyManagedCount = 0
        case .keepLast(let count):
            retainedPolicyManagedCount = count
        case .unlimited:
            retainedPolicyManagedCount = policyManagedFiles.count
        }

        let filesToRemove = Array(
            policyManagedFiles.dropFirst(retainedPolicyManagedCount)
        ) + Array(
            savedFiles.dropFirst(Self.maximumSavedRecordingCount)
        )
        for file in filesToRemove {
            do {
                try fileSystem.removeFileIfPresent(at: file.url)
            } catch {
                throw IOSAcceptedAudioCacheError.storageUnavailable
            }
        }
    }

    private func cachedAudioFileURLIfAvailableUnlocked(
        resultID: UUID
    ) throws -> URL? {
        let matches = try managedFiles().filter {
            $0.resultID == resultID
        }
        guard matches.count == 1 else { return nil }
        return matches[0].url
    }

    private func managedFiles() throws -> [ManagedFile] {
        guard FileManager.default.fileExists(atPath: directoryURL.path)
        else { return [] }
        guard let directoryValues = try? directoryURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ),
        directoryValues.isDirectory == true,
        directoryValues.isSymbolicLink != true else {
            throw IOSAcceptedAudioCacheError.storageUnavailable
        }
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .fileSizeKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw IOSAcceptedAudioCacheError.storageUnavailable
        }

        return urls.compactMap { url in
            guard let identity = Self.managedIdentity(
                fileName: url.lastPathComponent
            ),
            let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            (values.fileSize ?? 0) > 0 else { return nil }
            return ManagedFile(
                resultID: identity.resultID,
                retention: identity.retention,
                url: url,
                fileExtension: identity.fileExtension,
                byteCount: Int64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate
                    ?? .distantPast
            )
        }
    }

    private func fileURL(
        resultID: UUID,
        fileExtension: String,
        retention: IOSAcceptedAudioRetention
    ) -> URL {
        let prefix = switch retention {
        case .recordingCachePolicy: Self.filePrefix
        case .savedFiveMinute: Self.savedFilePrefix
        }
        return directoryURL.appendingPathComponent(
            prefix + resultID.uuidString.lowercased()
                + "." + fileExtension,
            isDirectory: false
        )
    }

    private func applyCreationDate(_ date: Date, to url: URL) throws {
        do {
            try FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: url.path
            )
        } catch {
            throw IOSAcceptedAudioCacheError.storageUnavailable
        }
    }

    private static func managedIdentity(
        fileName: String
    ) -> (
        resultID: UUID,
        fileExtension: String,
        retention: IOSAcceptedAudioRetention
    )? {
        let retention: IOSAcceptedAudioRetention
        let prefix: String
        if fileName.hasPrefix(filePrefix) {
            retention = .recordingCachePolicy
            prefix = filePrefix
        } else if fileName.hasPrefix(savedFilePrefix) {
            retention = .savedFiveMinute
            prefix = savedFilePrefix
        } else {
            return nil
        }
        guard let dot = fileName.lastIndex(of: ".") else { return nil }
        let idStart = fileName.index(
            fileName.startIndex,
            offsetBy: prefix.count
        )
        let rawID = String(fileName[idStart..<dot])
        let fileExtension = String(fileName[fileName.index(after: dot)...])
        guard isAllowedFileExtension(fileExtension),
              let resultID = UUID(uuidString: rawID),
              rawID == resultID.uuidString.lowercased() else { return nil }
        return (resultID, fileExtension, retention)
    }

    private static func isNewer(_ lhs: ManagedFile, _ rhs: ManagedFile)
        -> Bool {
        if lhs.modificationDate != rhs.modificationDate {
            return lhs.modificationDate > rhs.modificationDate
        }
        return lhs.url.lastPathComponent < rhs.url.lastPathComponent
    }

    private static let filePrefix = "accepted-v1-"
    private static let savedFilePrefix = "saved-v1-"
    private static func isAllowedFileExtension(_ value: String) -> Bool {
        value == "m4a" || value == "wav"
    }

    private struct ManagedFile {
        let resultID: UUID
        let retention: IOSAcceptedAudioRetention
        let url: URL
        let fileExtension: String
        let byteCount: Int64
        let modificationDate: Date
    }
}
