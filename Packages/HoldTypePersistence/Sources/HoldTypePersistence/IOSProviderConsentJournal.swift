import Darwin
import Foundation

enum IOSProviderConsentJournalError: Error, Equatable, Sendable {
    case staleRevision
    case localDataUnavailable
    case mutationNotSaved
    case commitUncertain
}

extension IOSProviderConsentJournalError:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSProviderConsentJournalError(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSProviderConsentJournalContent: Equatable, Sendable {
    case readable(IOSProviderConsentRecord)
    case unreadable
}

extension IOSProviderConsentJournalContent:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSProviderConsentJournalContent(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSProviderConsentJournalSnapshot: Equatable, Sendable {
    let content: IOSProviderConsentJournalContent
    let fileRevision: IOSStrictProtectedRecordFileRevision

    #if DEBUG
    init(content: IOSProviderConsentJournalContent, testingRevision: UInt64) {
        self.content = content
        fileRevision = IOSStrictProtectedRecordFileRevision(
            testingToken: testingRevision
        )
    }
    #endif

    init(
        content: IOSProviderConsentJournalContent,
        fileRevision: IOSStrictProtectedRecordFileRevision
    ) {
        self.content = content
        self.fileRevision = fileRevision
    }
}

extension IOSProviderConsentJournalSnapshot:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSProviderConsentJournalSnapshot(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

protocol IOSProviderConsentJournalStoring: Sendable {
    func load() throws -> IOSProviderConsentJournalSnapshot?
    func withProviderAdmissionLease<Result>(
        _ operation: (
            IOSProviderConsentJournalSnapshot?
        ) throws -> Result
    ) throws -> Result
    func create(_ record: IOSProviderConsentRecord) throws
        -> IOSProviderConsentJournalSnapshot
    func replace(
        _ record: IOSProviderConsentRecord,
        expected: IOSProviderConsentJournalSnapshot
    ) throws -> IOSProviderConsentJournalSnapshot
    func removeUnreadable(
        expected: IOSProviderConsentJournalSnapshot
    ) throws
    func synchronizeDirectory() throws
}

final class IOSProviderConsentRepositoryAdmissionGuard:
    @unchecked Sendable {
    // Provider-consent repository access is process-owned. A non-recursive
    // lease prevents a mutation from reentering between the admission read and
    // the decisive gate transition.
    private let lock = NSLock()

    func withLease<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

struct FoundationIOSProviderConsentJournalRepository:
    IOSProviderConsentJournalStoring,
    Sendable {
    private static let repositoryAdmissionGuard =
        IOSProviderConsentRepositoryAdmissionGuard()

    private let fileSystem: any IOSStrictProtectedRecordFileSystem
    private let directorySynchronization: @Sendable () throws -> Void
    private let repositoryRevalidation: @Sendable () throws -> Void
    private let onRepositoryUnavailable: @Sendable () -> Void

    init(
        applicationSupportDirectoryURL: URL,
        repositoryGuard:
            IOSAcceptedHistoryCoordinatorRepositoryGuard? = nil,
        onRepositoryUnavailable:
            @escaping @Sendable () -> Void = {}
    ) {
        let markRepositoryIdentityMismatch: @Sendable () -> Void = {
            repositoryGuard?.invalidate()
        }
        fileSystem = FoundationIOSStrictProtectedRecordFileSystem(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            configuration: .providerConsent,
            adapter: IOSProviderConsentBackupEligiblePOSIXAdapter(),
            expectedRepositoryRoot:
                repositoryGuard?.expectedPhysicalRootIdentity,
            onRepositoryIdentityMismatch:
                markRepositoryIdentityMismatch
        )
        let synchronizer = IOSProviderConsentDirectorySynchronizer(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            expectedRepositoryRoot:
                repositoryGuard?.expectedPhysicalRootIdentity
        )
        let revalidate: @Sendable () throws -> Void = {
            _ = try repositoryGuard?.revalidate()
        }
        directorySynchronization = {
            do {
                try revalidate()
                try synchronizer.synchronize()
                try revalidate()
            } catch {
                _ = try? repositoryGuard?.revalidate()
                throw error
            }
        }
        repositoryRevalidation = revalidate
        self.onRepositoryUnavailable = onRepositoryUnavailable
    }

    init(
        fileSystem: any IOSStrictProtectedRecordFileSystem,
        directorySynchronization: @escaping @Sendable () throws -> Void
    ) {
        self.fileSystem = fileSystem
        self.directorySynchronization = directorySynchronization
        repositoryRevalidation = {}
        onRepositoryUnavailable = {}
    }

    func load() throws -> IOSProviderConsentJournalSnapshot? {
        try Self.repositoryAdmissionGuard.withLease {
            try loadWithoutAdmissionLease()
        }
    }

    func withProviderAdmissionLease<Result>(
        _ operation: (
            IOSProviderConsentJournalSnapshot?
        ) throws -> Result
    ) throws -> Result {
        try Self.repositoryAdmissionGuard.withLease {
            try operation(try loadWithoutAdmissionLease())
        }
    }

    private func loadWithoutAdmissionLease() throws
        -> IOSProviderConsentJournalSnapshot? {
        try revalidateRepository(or: .localDataUnavailable)
        let file: IOSStrictProtectedRecordFile
        do {
            guard let value = try fileSystem.readFileIfPresent() else {
                try revalidateRepository(or: .localDataUnavailable)
                return nil
            }
            file = value
        } catch IOSStrictProtectedRecordFileSystemError.sourceTooLarge,
                IOSStrictProtectedRecordFileSystemError.invalidFile {
            let snapshot = try loadOpaqueSnapshot()
            try revalidateRepository(or: .localDataUnavailable)
            return snapshot
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable,
                IOSStrictProtectedRecordFileSystemError.repositoryIdentityConflict {
            onRepositoryUnavailable()
            throw IOSProviderConsentJournalError.localDataUnavailable
        } catch {
            onRepositoryUnavailable()
            throw IOSProviderConsentJournalError.localDataUnavailable
        }

        let content: IOSProviderConsentJournalContent
        do {
            content = .readable(try IOSProviderConsentWireCodec.decode(file.data))
        } catch {
            // Future or malformed bytes remain physically untouched and resettable
            // only through the exact revision captured by this observation.
            content = .unreadable
        }
        let snapshot = IOSProviderConsentJournalSnapshot(
            content: content,
            fileRevision: file.revision
        )
        try revalidateRepository(or: .localDataUnavailable)
        return snapshot
    }

    func create(_ record: IOSProviderConsentRecord) throws
        -> IOSProviderConsentJournalSnapshot {
        try Self.repositoryAdmissionGuard.withLease {
            try createWithoutAdmissionLease(record)
        }
    }

    private func createWithoutAdmissionLease(
        _ record: IOSProviderConsentRecord
    ) throws -> IOSProviderConsentJournalSnapshot {
        try revalidateRepository(or: .localDataUnavailable)
        let data = try encode(record)
        do {
            let revision = try fileSystem.createFile(with: data)
            let snapshot = IOSProviderConsentJournalSnapshot(
                content: .readable(record),
                fileRevision: revision
            )
            try revalidateRepository(or: .commitUncertain)
            return snapshot
        } catch IOSStrictProtectedRecordFileSystemError.destinationConflict {
            throw IOSProviderConsentJournalError.staleRevision
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable,
                IOSStrictProtectedRecordFileSystemError.repositoryIdentityConflict {
            onRepositoryUnavailable()
            throw IOSProviderConsentJournalError.localDataUnavailable
        } catch IOSStrictProtectedRecordFileSystemError.commitUncertain,
                IOSStrictProtectedRecordFileSystemError.synchronizationFailed {
            throw IOSProviderConsentJournalError.commitUncertain
        } catch let error as IOSProviderConsentJournalError {
            throw error
        } catch {
            throw IOSProviderConsentJournalError.mutationNotSaved
        }
    }

    func replace(
        _ record: IOSProviderConsentRecord,
        expected: IOSProviderConsentJournalSnapshot
    ) throws -> IOSProviderConsentJournalSnapshot {
        try Self.repositoryAdmissionGuard.withLease {
            try replaceWithoutAdmissionLease(
                record,
                expected: expected
            )
        }
    }

    private func replaceWithoutAdmissionLease(
        _ record: IOSProviderConsentRecord,
        expected: IOSProviderConsentJournalSnapshot
    ) throws -> IOSProviderConsentJournalSnapshot {
        guard case .readable = expected.content else {
            throw IOSProviderConsentJournalError.staleRevision
        }
        try revalidateRepository(or: .localDataUnavailable)
        let data = try encode(record)
        do {
            let revision = try fileSystem.replaceFile(
                with: data,
                expected: expected.fileRevision
            )
            let snapshot = IOSProviderConsentJournalSnapshot(
                content: .readable(record),
                fileRevision: revision
            )
            try revalidateRepository(or: .commitUncertain)
            return snapshot
        } catch IOSStrictProtectedRecordFileSystemError.staleRevision,
                IOSStrictProtectedRecordFileSystemError.missing {
            throw IOSProviderConsentJournalError.staleRevision
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable,
                IOSStrictProtectedRecordFileSystemError.repositoryIdentityConflict {
            onRepositoryUnavailable()
            throw IOSProviderConsentJournalError.localDataUnavailable
        } catch IOSStrictProtectedRecordFileSystemError.commitUncertain,
                IOSStrictProtectedRecordFileSystemError.synchronizationFailed {
            throw IOSProviderConsentJournalError.commitUncertain
        } catch let error as IOSProviderConsentJournalError {
            throw error
        } catch {
            throw IOSProviderConsentJournalError.mutationNotSaved
        }
    }

    func removeUnreadable(
        expected: IOSProviderConsentJournalSnapshot
    ) throws {
        try Self.repositoryAdmissionGuard.withLease {
            try removeUnreadableWithoutAdmissionLease(expected: expected)
        }
    }

    private func removeUnreadableWithoutAdmissionLease(
        expected: IOSProviderConsentJournalSnapshot
    ) throws {
        guard expected.content == .unreadable else {
            throw IOSProviderConsentJournalError.staleRevision
        }
        try revalidateRepository(or: .localDataUnavailable)
        do {
            try fileSystem.removeOpaqueFile(expected: expected.fileRevision)
            try revalidateRepository(or: .commitUncertain)
        } catch IOSStrictProtectedRecordFileSystemError.staleRevision,
                IOSStrictProtectedRecordFileSystemError.missing {
            throw IOSProviderConsentJournalError.staleRevision
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable,
                IOSStrictProtectedRecordFileSystemError.repositoryIdentityConflict {
            onRepositoryUnavailable()
            throw IOSProviderConsentJournalError.localDataUnavailable
        } catch IOSStrictProtectedRecordFileSystemError.commitUncertain,
                IOSStrictProtectedRecordFileSystemError.synchronizationFailed {
            throw IOSProviderConsentJournalError.commitUncertain
        } catch let error as IOSProviderConsentJournalError {
            throw error
        } catch {
            throw IOSProviderConsentJournalError.mutationNotSaved
        }
    }

    func synchronizeDirectory() throws {
        try Self.repositoryAdmissionGuard.withLease {
            try synchronizeDirectoryWithoutAdmissionLease()
        }
    }

    private func synchronizeDirectoryWithoutAdmissionLease() throws {
        do {
            try directorySynchronization()
        } catch {
            onRepositoryUnavailable()
            throw IOSProviderConsentJournalError.commitUncertain
        }
    }

    private func revalidateRepository(
        or mappedError: IOSProviderConsentJournalError
    ) throws {
        do {
            try repositoryRevalidation()
        } catch {
            onRepositoryUnavailable()
            throw mappedError
        }
    }

    private func loadOpaqueSnapshot() throws
        -> IOSProviderConsentJournalSnapshot? {
        do {
            guard let revision = try fileSystem
                .readOpaqueFileRevisionIfPresent() else {
                return nil
            }
            return IOSProviderConsentJournalSnapshot(
                content: .unreadable,
                fileRevision: revision
            )
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable,
                IOSStrictProtectedRecordFileSystemError.repositoryIdentityConflict {
            onRepositoryUnavailable()
            throw IOSProviderConsentJournalError.localDataUnavailable
        } catch {
            onRepositoryUnavailable()
            throw IOSProviderConsentJournalError.localDataUnavailable
        }
    }

    private func encode(_ record: IOSProviderConsentRecord) throws -> Data {
        do {
            return try IOSProviderConsentWireCodec.encode(record)
        } catch {
            throw IOSProviderConsentJournalError.mutationNotSaved
        }
    }
}

/// The shared strict-record writer predates this record and normally excludes
/// files from backup. Consent is a user decision, so this adapter makes that
/// one historical xattr hook assert absence while retaining every other strict
/// protection, identity, locking, and durability check.
struct IOSProviderConsentBackupEligiblePOSIXAdapter:
    IOSPendingRecordingPOSIXAdapter,
    Sendable {
    private static let backupExclusionAttributeName =
        "com.apple.metadata:com_apple_backup_excludeItem"
    private static let syntheticExpectedValue: [UInt8] = [
        0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30,
        0x5F, 0x10, 0x11, 0x63, 0x6F, 0x6D, 0x2E, 0x61,
        0x70, 0x70, 0x6C, 0x65, 0x2E, 0x62, 0x61, 0x63,
        0x6B, 0x75, 0x70, 0x64, 0x08, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x1C,
    ]

    private let base = DarwinIOSPendingRecordingPOSIXAdapter()

    func effectiveUserID() -> IOSPendingRecordingPOSIXResult<uid_t> {
        base.effectiveUserID()
    }

    func openPath(
        _ path: String,
        flags: Int32,
        mode: mode_t?
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        base.openPath(path, flags: flags, mode: mode)
    }

    func openAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32,
        mode: mode_t?
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        base.openAt(
            directoryDescriptor: directoryDescriptor,
            name: name,
            flags: flags,
            mode: mode
        )
    }

    func makeDirectoryAt(
        directoryDescriptor: Int32,
        name: String,
        mode: mode_t
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.makeDirectoryAt(
            directoryDescriptor: directoryDescriptor,
            name: name,
            mode: mode
        )
    }

    func status(of fileDescriptor: Int32) -> IOSPendingRecordingPOSIXResult<stat> {
        base.status(of: fileDescriptor)
    }

    func statusAtPath(_ path: String) -> IOSPendingRecordingPOSIXResult<stat> {
        base.statusAtPath(path)
    }

    func statusAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<stat> {
        base.statusAt(
            directoryDescriptor: directoryDescriptor,
            name: name,
            flags: flags
        )
    }

    func read(
        fileDescriptor: Int32,
        buffer: UnsafeMutableRawPointer,
        byteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        base.read(
            fileDescriptor: fileDescriptor,
            buffer: buffer,
            byteCount: byteCount
        )
    }

    func write(
        fileDescriptor: Int32,
        buffer: UnsafeRawPointer,
        byteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        base.write(
            fileDescriptor: fileDescriptor,
            buffer: buffer,
            byteCount: byteCount
        )
    }

    func synchronize(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.synchronize(fileDescriptor: fileDescriptor)
    }

    func changeMode(
        fileDescriptor: Int32,
        mode: mode_t
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.changeMode(fileDescriptor: fileDescriptor, mode: mode)
    }

    func lock(
        fileDescriptor: Int32,
        operation: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.lock(fileDescriptor: fileDescriptor, operation: operation)
    }

    func setExtendedAttribute(
        fileDescriptor: Int32,
        name: String,
        value: [UInt8],
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        guard name == Self.backupExclusionAttributeName else {
            return base.setExtendedAttribute(
                fileDescriptor: fileDescriptor,
                name: name,
                value: value,
                flags: flags
            )
        }
        let result = name.withCString {
            Darwin.fremovexattr(fileDescriptor, $0, 0)
        }
        return result == 0 || errno == ENOATTR
            ? .success(())
            : .failure(errno)
    }

    func extendedAttribute(
        fileDescriptor: Int32,
        name: String,
        maximumByteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<[UInt8]> {
        if name == Self.backupExclusionAttributeName,
           maximumByteCount > Self.syntheticExpectedValue.count {
            var byte: UInt8 = 0
            let result = name.withCString {
                Darwin.fgetxattr(
                    fileDescriptor,
                    $0,
                    &byte,
                    1,
                    0,
                    0
                )
            }
            if result < 0, errno == ENOATTR {
                return .success(Self.syntheticExpectedValue)
            }
            return .failure(result >= 0 ? EEXIST : errno)
        }
        return base.extendedAttribute(
            fileDescriptor: fileDescriptor,
            name: name,
            maximumByteCount: maximumByteCount
        )
    }

    func setProtectionClass(
        fileDescriptor: Int32,
        protectionClass: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.setProtectionClass(
            fileDescriptor: fileDescriptor,
            protectionClass: protectionClass
        )
    }

    func protectionClass(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        base.protectionClass(fileDescriptor: fileDescriptor)
    }

    func publishExclusively(
        directoryDescriptor: Int32,
        temporaryName: String,
        finalName: String
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.publishExclusively(
            directoryDescriptor: directoryDescriptor,
            temporaryName: temporaryName,
            finalName: finalName
        )
    }

    func unlinkAt(
        directoryDescriptor: Int32,
        name: String
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.unlinkAt(
            directoryDescriptor: directoryDescriptor,
            name: name
        )
    }

    func openDirectoryStream(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<UnsafeMutablePointer<DIR>> {
        base.openDirectoryStream(fileDescriptor: fileDescriptor)
    }

    func nextDirectoryEntry(
        stream: UnsafeMutablePointer<DIR>
    ) -> IOSPendingRecordingPOSIXResult<IOSPendingRecordingDirectoryEntry?> {
        base.nextDirectoryEntry(stream: stream)
    }

    func closeFile(_ fileDescriptor: Int32) {
        base.closeFile(fileDescriptor)
    }

    func closeDirectoryStream(_ stream: UnsafeMutablePointer<DIR>) {
        base.closeDirectoryStream(stream)
    }
}

private struct IOSProviderConsentDirectorySynchronizer: Sendable {
    private static let maximumInterruptedRetryCount = 8

    let applicationSupportDirectoryURL: URL
    let expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?

    func synchronize() throws {
        guard applicationSupportDirectoryURL.isFileURL,
              !applicationSupportDirectoryURL.path.isEmpty,
              !applicationSupportDirectoryURL.path.utf8.contains(0) else {
            throw IOSProviderConsentJournalError.commitUncertain
        }

        let parent = try openDirectory(path: applicationSupportDirectoryURL.path)
        defer { Darwin.close(parent) }
        try validateRepositoryRoot(descriptor: parent)
        let directory = try openDirectory(
            named: IOSProviderConsentStorageLocation.directoryName,
            parent: parent
        )
        defer { Darwin.close(directory) }

        let before = try directoryIdentity(descriptor: directory)
        try validateDirectoryPath(
            named: IOSProviderConsentStorageLocation.directoryName,
            parent: parent,
            expected: before
        )
        try synchronizeDirectory(directory)
        let after = try directoryIdentity(descriptor: directory)
        guard after == before else {
            throw IOSProviderConsentJournalError.commitUncertain
        }
        try validateDirectoryPath(
            named: IOSProviderConsentStorageLocation.directoryName,
            parent: parent,
            expected: after
        )
        try validateRepositoryRoot(descriptor: parent)
    }

    private func openDirectory(path: String) throws -> Int32 {
        let descriptor = path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw IOSProviderConsentJournalError.commitUncertain
        }
        return descriptor
    }

    private func openDirectory(named name: String, parent: Int32) throws -> Int32 {
        let descriptor = name.withCString {
            Darwin.openat(
                parent,
                $0,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard descriptor >= 0 else {
            throw IOSProviderConsentJournalError.commitUncertain
        }
        return descriptor
    }

    private func directoryIdentity(descriptor: Int32) throws -> Identity {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              status.st_uid == Darwin.geteuid(),
              status.st_mode & mode_t(0o7777) == mode_t(0o700) else {
            throw IOSProviderConsentJournalError.commitUncertain
        }
        return Identity(device: status.st_dev, inode: status.st_ino)
    }

    private func validateRepositoryRoot(descriptor: Int32) throws {
        guard let expectedRepositoryRoot else { return }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              expectedRepositoryRoot.matches(status) else {
            throw IOSProviderConsentJournalError.commitUncertain
        }
    }

    private func validateDirectoryPath(
        named name: String,
        parent: Int32,
        expected: Identity
    ) throws {
        var status = stat()
        let result = name.withCString {
            Darwin.fstatat(parent, $0, &status, AT_SYMLINK_NOFOLLOW)
        }
        guard result == 0,
              status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              status.st_uid == Darwin.geteuid(),
              status.st_mode & mode_t(0o7777) == mode_t(0o700),
              Identity(device: status.st_dev, inode: status.st_ino) == expected else {
            throw IOSProviderConsentJournalError.commitUncertain
        }
    }

    private func synchronizeDirectory(_ descriptor: Int32) throws {
        var interruptedCount = 0
        while true {
            guard Darwin.fsync(descriptor) != 0 else { return }
            if errno == EINTR,
               interruptedCount < Self.maximumInterruptedRetryCount {
                interruptedCount += 1
                continue
            }
            throw IOSProviderConsentJournalError.commitUncertain
        }
    }

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }
}
