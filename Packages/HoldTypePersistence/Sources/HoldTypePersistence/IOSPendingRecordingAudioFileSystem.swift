import AudioToolbox
import Darwin
import Foundation
import HoldTypeDomain

enum IOSPendingRecordingAudioFileSystemError: Error, Equatable, Sendable {
    case namespaceUnavailable
    case namespaceNotEmpty
    case invalidSource
    case sourceUnavailable
    case sourceChanged
    case invalidDuration
    case destinationConflict
    case writeFailed
    case synchronizationFailed
    case mediaValidationFailed
    case mediaValidationTimedOut
    case operationTimedOut
    case operationCancelled
    case protectedAudioMissing
    case protectedAudioInvalid
    case dataProtectionUnavailable
    case repositoryIdentityConflict
    case removeFailed
}

/// Opaque descriptor-derived proof for one exact failed-History audio cleanup.
/// It exposes neither the protected path nor physical filesystem identities.
struct IOSPendingRecordingProtectedAudioCleanupEvidence: Equatable, Sendable {
    fileprivate enum Disposition: Equatable, Sendable {
        case removed
        case alreadyAbsent
    }

    fileprivate struct PhysicalIdentity: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
    }

    fileprivate let authorization:
        IOSFailedHistoryAudioCleanupAuthorization
    fileprivate let pendingSource:
        IOSPendingRecordingJournalMetadataSnapshot?
    fileprivate let disposition: Disposition
    fileprivate let directoryIdentity: PhysicalIdentity
    fileprivate let removedFileIdentity: PhysicalIdentity?

    fileprivate init(
        authorization:
            IOSPendingRecordingProtectedAudioCleanupAuthorization,
        disposition: Disposition,
        directoryIdentity: PhysicalIdentity,
        removedFileIdentity: PhysicalIdentity?
    ) {
        self.authorization = authorization.cleanupAuthorization
        pendingSource = authorization.inventory.pendingSource
        self.disposition = disposition
        self.directoryIdentity = directoryIdentity
        self.removedFileIdentity = removedFileIdentity
    }

    func provesRemoval(
        of authorization: IOSFailedHistoryAudioCleanupAuthorization
    ) -> Bool {
        authorization.operationLeaseAuthorization.provesActiveLease()
            && self.authorization == authorization
            && disposition == .removed
            && removedFileIdentity != nil
    }

    func provesPreexistingAbsence(
        of authorization: IOSFailedHistoryAudioCleanupAuthorization
    ) -> Bool {
        authorization.operationLeaseAuthorization.provesActiveLease()
            && self.authorization == authorization
            && disposition == .alreadyAbsent
            && removedFileIdentity == nil
    }

    fileprivate func provesSameCleanup(
        as authorization:
            IOSPendingRecordingProtectedAudioCleanupAuthorization
    ) -> Bool {
        let other = authorization.cleanupAuthorization
        return self.authorization.operationID == other.operationID
            && self.authorization.failedSource == other.failedSource
            && self.authorization.tombstone == other.tombstone
            && self.authorization.outcome == other.outcome
            && self.authorization.purpose == other.purpose
            && self.authorization.failedStoreIdentity
                == other.failedStoreIdentity
            && self.authorization.expectedPendingStoreIdentity
                == other.expectedPendingStoreIdentity
            && self.authorization.ownerIdentity == other.ownerIdentity
            && self.authorization.repositoryBinding
                == other.repositoryBinding
            && pendingSource == authorization.inventory.pendingSource
    }

    #if DEBUG
    init(
        testingRemoved authorization:
            IOSFailedHistoryAudioCleanupAuthorization
    ) {
        self.authorization = authorization
        pendingSource = nil
        disposition = .removed
        directoryIdentity = PhysicalIdentity(device: 1, inode: 1)
        removedFileIdentity = PhysicalIdentity(device: 1, inode: 2)
    }

    init(
        testingAlreadyAbsent authorization:
            IOSFailedHistoryAudioCleanupAuthorization
    ) {
        self.authorization = authorization
        pendingSource = nil
        disposition = .alreadyAbsent
        directoryIdentity = PhysicalIdentity(device: 1, inode: 1)
        removedFileIdentity = nil
    }
    #endif
}

extension IOSPendingRecordingProtectedAudioCleanupEvidence:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSPendingRecordingProtectedAudioCleanupEvidence(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Opaque proof that the exact accepted-output audio path was absent on both
/// sides of a successful directory durability barrier. Store/root/lease
/// binding is carried by the authorization rather than by caller assertions.
struct IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence:
    Equatable,
    Sendable {
    fileprivate enum Disposition: Equatable, Sendable {
        case removed
        case alreadyAbsent
    }

    fileprivate let authorization:
        IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization
    fileprivate let disposition: Disposition

    fileprivate init(
        authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization,
        disposition: Disposition
    ) {
        self.authorization = authorization
        self.disposition = disposition
    }

    #if DEBUG
    init(
        testing authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization,
        removed: Bool
    ) {
        self.authorization = authorization
        disposition = removed ? .removed : .alreadyAbsent
    }
    #endif

    func provesAbsence(
        using expected:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization
    ) -> Bool {
        authorization == expected
            && authorization.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: expected.operationLeaseAuthorization
                )
    }

    var provesPreexistingAbsence: Bool {
        disposition == .alreadyAbsent
    }
}

extension IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

protocol IOSPendingRecordingPublishedAudioLease: AnyObject, Sendable {
    var relativeIdentifier: String { get }
    var audioArtifact: AudioRecordingArtifact { get }
    var durationMilliseconds: Int64 { get }

    func revalidate() async throws -> AudioRecordingArtifact
    func read(
        atOffset offset: Int64,
        maximumByteCount: Int
    ) async throws -> Data
    func release()
}

protocol IOSPendingRecordingAudioFileSystem: Sendable {
    #if DEBUG
    func requireEmptyNamespace() async throws
    #endif

    func validateProtectedAudioNamespace(
        _ inventory: IOSProtectedAudioNamespaceInventory
    ) async throws
    func validateProtectedAudioNamespace(
        _ inventory: IOSProtectedAudioNamespaceInventory,
        holding audioLeases: [any IOSPendingRecordingPublishedAudioLease]
    ) async throws
    func reconcileProtectedAudioCleanup(
        using authorization:
            IOSPendingRecordingProtectedAudioCleanupAuthorization
    ) async throws -> IOSPendingRecordingProtectedAudioCleanupEvidence
    func reconcileAcceptedOutputAudioRemoval(
        using authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization
    ) async throws
        -> IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence
    func reconcilePendingAudioRemoval(
        using authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization
    ) async throws
        -> IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence

    #if DEBUG
    func publishProtectedCopy(
        from source: AudioRecordingArtifact,
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat,
        durationMilliseconds: Int64
    ) async throws -> any IOSPendingRecordingPublishedAudioLease
    func publishProtectedCopy(
        from source: AudioRecordingArtifact,
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat,
        durationMilliseconds: Int64,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) async throws -> any IOSPendingRecordingPublishedAudioLease
    #endif
    func publishProtectedCopy(
        from source: AudioRecordingArtifact,
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat,
        durationMilliseconds: Int64,
        inventory: IOSProtectedAudioNamespaceInventory
    ) async throws -> any IOSPendingRecordingPublishedAudioLease

    func validatePublishedAudio(
        relativeIdentifier: String,
        attemptID: UUID,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) async throws -> AudioRecordingArtifact
    func acquireValidatedPublishedAudio(
        relativeIdentifier: String,
        attemptID: UUID,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) async throws -> any IOSPendingRecordingPublishedAudioLease

    func removePublishedAudioIfPresent(
        relativeIdentifier: String,
        attemptID: UUID,
        expectedByteCount: Int64
    ) async throws -> Bool
    func removePublishedAudioIfPresent(
        relativeIdentifier: String,
        attemptID: UUID,
        expectedByteCount: Int64,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) async throws -> Bool
}

extension IOSPendingRecordingAudioFileSystem {
    func reconcilePendingAudioRemoval(
        using authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization
    ) async throws
        -> IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence {
        try await reconcileAcceptedOutputAudioRemoval(using: authorization)
    }

    func reconcileAcceptedOutputAudioRemoval(
        using authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization
    ) async throws
        -> IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence {
        _ = authorization
        throw IOSPendingRecordingAudioFileSystemError.removeFailed
    }

    func validateProtectedAudioNamespace(
        _ inventory: IOSProtectedAudioNamespaceInventory,
        holding audioLeases: [any IOSPendingRecordingPublishedAudioLease]
    ) async throws {
        _ = audioLeases
        try await validateProtectedAudioNamespace(inventory)
    }

    #if DEBUG
    func publishProtectedCopy(
        from source: AudioRecordingArtifact,
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat,
        durationMilliseconds: Int64,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        _ = expectedRepositoryRoot
        return try await publishProtectedCopy(
            from: source,
            attemptID: attemptID,
            format: format,
            durationMilliseconds: durationMilliseconds
        )
    }
    #endif

    func removePublishedAudioIfPresent(
        relativeIdentifier: String,
        attemptID: UUID,
        expectedByteCount: Int64,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) async throws -> Bool {
        _ = expectedRepositoryRoot
        return try await removePublishedAudioIfPresent(
            relativeIdentifier: relativeIdentifier,
            attemptID: attemptID,
            expectedByteCount: expectedByteCount
        )
    }
}

enum IOSPendingRecordingPOSIXResult<Value> {
    case success(Value)
    case failure(Int32)
}

enum IOSPendingRecordingDirectoryEntry: Equatable, Sendable {
    case name(String)
    case invalidName
}

protocol IOSPendingRecordingPOSIXAdapter: Sendable {
    func effectiveUserID() -> IOSPendingRecordingPOSIXResult<uid_t>
    func openPath(_ path: String, flags: Int32, mode: mode_t?)
        -> IOSPendingRecordingPOSIXResult<Int32>
    func openAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32,
        mode: mode_t?
    ) -> IOSPendingRecordingPOSIXResult<Int32>
    func makeDirectoryAt(
        directoryDescriptor: Int32,
        name: String,
        mode: mode_t
    ) -> IOSPendingRecordingPOSIXResult<Void>
    func status(of fileDescriptor: Int32) -> IOSPendingRecordingPOSIXResult<stat>
    func statusAtPath(_ path: String) -> IOSPendingRecordingPOSIXResult<stat>
    func statusAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<stat>
    func read(
        fileDescriptor: Int32,
        buffer: UnsafeMutableRawPointer,
        byteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<Int>
    func readAt(
        fileDescriptor: Int32,
        buffer: UnsafeMutableRawPointer,
        byteCount: Int,
        offset: Int64
    ) -> IOSPendingRecordingPOSIXResult<Int>
    func write(
        fileDescriptor: Int32,
        buffer: UnsafeRawPointer,
        byteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<Int>
    func synchronize(fileDescriptor: Int32) -> IOSPendingRecordingPOSIXResult<Void>
    func changeMode(fileDescriptor: Int32, mode: mode_t)
        -> IOSPendingRecordingPOSIXResult<Void>
    func lock(fileDescriptor: Int32, operation: Int32)
        -> IOSPendingRecordingPOSIXResult<Void>
    func setExtendedAttribute(
        fileDescriptor: Int32,
        name: String,
        value: [UInt8],
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void>
    func extendedAttribute(
        fileDescriptor: Int32,
        name: String,
        maximumByteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<[UInt8]>
    func setProtectionClass(fileDescriptor: Int32, protectionClass: Int32)
        -> IOSPendingRecordingPOSIXResult<Void>
    func protectionClass(fileDescriptor: Int32)
        -> IOSPendingRecordingPOSIXResult<Int32>
    func publishExclusively(
        directoryDescriptor: Int32,
        temporaryName: String,
        finalName: String
    ) -> IOSPendingRecordingPOSIXResult<Void>
    func unlinkAt(directoryDescriptor: Int32, name: String)
        -> IOSPendingRecordingPOSIXResult<Void>
    func openDirectoryStream(fileDescriptor: Int32)
        -> IOSPendingRecordingPOSIXResult<UnsafeMutablePointer<DIR>>
    func nextDirectoryEntry(stream: UnsafeMutablePointer<DIR>)
        -> IOSPendingRecordingPOSIXResult<IOSPendingRecordingDirectoryEntry?>
    func closeFile(_ fileDescriptor: Int32)
    func closeDirectoryStream(_ stream: UnsafeMutablePointer<DIR>)
}

extension IOSPendingRecordingPOSIXAdapter {
    func readAt(
        fileDescriptor: Int32,
        buffer: UnsafeMutableRawPointer,
        byteCount: Int,
        offset: Int64
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        let result = Darwin.pread(
            fileDescriptor,
            buffer,
            byteCount,
            off_t(offset)
        )
        return result >= 0 ? .success(result) : .failure(errno)
    }
}

struct DarwinIOSPendingRecordingPOSIXAdapter: IOSPendingRecordingPOSIXAdapter {
    func effectiveUserID() -> IOSPendingRecordingPOSIXResult<uid_t> {
        .success(Darwin.geteuid())
    }

    func openPath(
        _ path: String,
        flags: Int32,
        mode: mode_t?
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        let result = path.withCString { path in
            if let mode {
                return Darwin.open(path, flags, mode)
            }
            return Darwin.open(path, flags)
        }
        return result >= 0 ? .success(result) : .failure(errno)
    }

    func openAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32,
        mode: mode_t?
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        let result = name.withCString { name in
            if let mode {
                return Darwin.openat(directoryDescriptor, name, flags, mode)
            }
            return Darwin.openat(directoryDescriptor, name, flags)
        }
        return result >= 0 ? .success(result) : .failure(errno)
    }

    func makeDirectoryAt(
        directoryDescriptor: Int32,
        name: String,
        mode: mode_t
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        let result = name.withCString { Darwin.mkdirat(directoryDescriptor, $0, mode) }
        return result == 0 ? .success(()) : .failure(errno)
    }

    func status(of fileDescriptor: Int32) -> IOSPendingRecordingPOSIXResult<stat> {
        var value = stat()
        return Darwin.fstat(fileDescriptor, &value) == 0
            ? .success(value)
            : .failure(errno)
    }

    func statusAtPath(_ path: String) -> IOSPendingRecordingPOSIXResult<stat> {
        var value = stat()
        let result = path.withCString { Darwin.lstat($0, &value) }
        return result == 0 ? .success(value) : .failure(errno)
    }

    func statusAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<stat> {
        var value = stat()
        let result = name.withCString {
            Darwin.fstatat(directoryDescriptor, $0, &value, flags)
        }
        return result == 0 ? .success(value) : .failure(errno)
    }

    func read(
        fileDescriptor: Int32,
        buffer: UnsafeMutableRawPointer,
        byteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        let result = Darwin.read(fileDescriptor, buffer, byteCount)
        return result >= 0 ? .success(result) : .failure(errno)
    }

    func readAt(
        fileDescriptor: Int32,
        buffer: UnsafeMutableRawPointer,
        byteCount: Int,
        offset: Int64
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        let result = Darwin.pread(
            fileDescriptor,
            buffer,
            byteCount,
            off_t(offset)
        )
        return result >= 0 ? .success(result) : .failure(errno)
    }

    func write(
        fileDescriptor: Int32,
        buffer: UnsafeRawPointer,
        byteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        let result = Darwin.write(fileDescriptor, buffer, byteCount)
        return result >= 0 ? .success(result) : .failure(errno)
    }

    func synchronize(fileDescriptor: Int32) -> IOSPendingRecordingPOSIXResult<Void> {
        Darwin.fsync(fileDescriptor) == 0 ? .success(()) : .failure(errno)
    }

    func changeMode(
        fileDescriptor: Int32,
        mode: mode_t
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        Darwin.fchmod(fileDescriptor, mode) == 0 ? .success(()) : .failure(errno)
    }

    func lock(
        fileDescriptor: Int32,
        operation: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        flock(fileDescriptor, operation) == 0 ? .success(()) : .failure(errno)
    }

    func setExtendedAttribute(
        fileDescriptor: Int32,
        name: String,
        value: [UInt8],
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        let result = name.withCString { name in
            value.withUnsafeBytes {
                Darwin.fsetxattr(
                    fileDescriptor,
                    name,
                    $0.baseAddress,
                    $0.count,
                    0,
                    flags
                )
            }
        }
        return result == 0 ? .success(()) : .failure(errno)
    }

    func extendedAttribute(
        fileDescriptor: Int32,
        name: String,
        maximumByteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<[UInt8]> {
        var bytes = [UInt8](repeating: 0, count: maximumByteCount)
        let result = name.withCString { name in
            bytes.withUnsafeMutableBytes {
                Darwin.fgetxattr(
                    fileDescriptor,
                    name,
                    $0.baseAddress,
                    $0.count,
                    0,
                    0
                )
            }
        }
        guard result >= 0 else { return .failure(errno) }
        return .success(Array(bytes.prefix(result)))
    }

    func setProtectionClass(
        fileDescriptor: Int32,
        protectionClass: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        Darwin.fcntl(fileDescriptor, F_SETPROTECTIONCLASS, protectionClass) == 0
            ? .success(())
            : .failure(errno)
    }

    func protectionClass(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        let result = Darwin.fcntl(fileDescriptor, F_GETPROTECTIONCLASS)
        return result >= 0 ? .success(result) : .failure(errno)
    }

    func publishExclusively(
        directoryDescriptor: Int32,
        temporaryName: String,
        finalName: String
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        let result = temporaryName.withCString { temporaryName in
            finalName.withCString { finalName in
                Darwin.renameatx_np(
                    directoryDescriptor,
                    temporaryName,
                    directoryDescriptor,
                    finalName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        return result == 0 ? .success(()) : .failure(errno)
    }

    func unlinkAt(
        directoryDescriptor: Int32,
        name: String
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        let result = name.withCString { Darwin.unlinkat(directoryDescriptor, $0, 0) }
        return result == 0 ? .success(()) : .failure(errno)
    }

    func openDirectoryStream(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<UnsafeMutablePointer<DIR>> {
        guard let stream = Darwin.fdopendir(fileDescriptor) else {
            return .failure(errno)
        }
        return .success(stream)
    }

    func nextDirectoryEntry(
        stream: UnsafeMutablePointer<DIR>
    ) -> IOSPendingRecordingPOSIXResult<IOSPendingRecordingDirectoryEntry?> {
        errno = 0
        guard let entry = Darwin.readdir(stream) else {
            return errno == 0 ? .success(nil) : .failure(errno)
        }
        let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: Int(entry.pointee.d_namlen) + 1
            ) { String(validatingCString: $0) }
        }
        return .success(name.map(IOSPendingRecordingDirectoryEntry.name) ?? .invalidName)
    }

    func closeFile(_ fileDescriptor: Int32) {
        Darwin.close(fileDescriptor)
    }

    func closeDirectoryStream(_ stream: UnsafeMutablePointer<DIR>) {
        Darwin.closedir(stream)
    }
}

protocol IOSPendingRecordingMediaValidating: Sendable {
    func durationMilliseconds(
        forFileDescriptor fileDescriptor: Int32,
        byteCount: Int64,
        format: IOSPendingRecordingAudioFormat,
        timeoutNanoseconds: UInt64
    ) throws -> Int64
}

struct AudioToolboxIOSPendingRecordingMediaValidator:
    IOSPendingRecordingMediaValidating {
    private static let workerQueue = DispatchQueue(
        label: "app.holdtype.pending-recording-media-validation",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private let workerGate: AudioToolboxMediaValidationWorkerGate

    init(
        workerGate: AudioToolboxMediaValidationWorkerGate =
            AudioToolboxMediaValidationWorkerGate(),
        beforeDurationLoad: @escaping @Sendable () -> Void = {},
        onDuplicatedDescriptorClosed: @escaping @Sendable () -> Void = {}
    ) {
        self.workerGate = workerGate
        self.beforeDurationLoad = beforeDurationLoad
        self.onDuplicatedDescriptorClosed = onDuplicatedDescriptorClosed
    }

    func durationMilliseconds(
        forFileDescriptor fileDescriptor: Int32,
        byteCount: Int64,
        format: IOSPendingRecordingAudioFormat,
        timeoutNanoseconds: UInt64
    ) throws -> Int64 {
        guard workerGate.begin() else {
            throw IOSPendingRecordingAudioFileSystemError.mediaValidationTimedOut
        }
        let duplicatedDescriptor = Darwin.fcntl(
            fileDescriptor,
            F_DUPFD_CLOEXEC,
            0
        )
        guard duplicatedDescriptor >= 0 else {
            workerGate.finish()
            throw mediaValidationError(forPOSIXError: errno)
        }
        var status = stat()
        guard Darwin.fstat(duplicatedDescriptor, &status) == 0 else {
            let errorCode = errno
            Darwin.close(duplicatedDescriptor)
            workerGate.finish()
            throw mediaValidationError(forPOSIXError: errorCode)
        }
        guard status.st_mode & S_IFMT == S_IFREG,
              status.st_size == off_t(byteCount),
              byteCount > 0 else {
            Darwin.close(duplicatedDescriptor)
            workerGate.finish()
            throw IOSPendingRecordingAudioFileSystemError.mediaValidationFailed
        }
        let context = DescriptorAudioFileContext(
            fileDescriptor: duplicatedDescriptor,
            byteCount: Int64(status.st_size),
            onClose: onDuplicatedDescriptorClosed
        )
        let result = LockedMediaValidationResult()
        Self.workerQueue.async {
            let validationResult:
                Result<Int64, IOSPendingRecordingAudioFileSystemError>
            do {
                beforeDurationLoad()
                let seconds = try context.durationSeconds(
                    fileTypeHint: format.audioFileTypeHint
                )
                guard seconds.isFinite, seconds > 0 else {
                    throw IOSPendingRecordingAudioFileSystemError
                        .mediaValidationFailed
                }
                let scaled = seconds * 1_000
                guard scaled.isFinite,
                      scaled >= Double(Int64.min),
                      scaled <= Double(Int64.max) else {
                    throw IOSPendingRecordingAudioFileSystemError
                        .mediaValidationFailed
                }
                validationResult = .success(
                    Int64(scaled.rounded(.toNearestOrAwayFromZero))
                )
            } catch {
                validationResult = .failure(
                    context.protectedDataFailure
                        ? .dataProtectionUnavailable
                        : (error as? IOSPendingRecordingAudioFileSystemError)
                            ?? .mediaValidationFailed
                )
            }
            workerGate.finish()
            result.complete(validationResult)
        }

        let waitResult = result.wait(timeoutNanoseconds: timeoutNanoseconds)
        guard let waitResult else {
            context.cancel()
            throw IOSPendingRecordingAudioFileSystemError.mediaValidationTimedOut
        }
        return try waitResult.get()
    }

    private func mediaValidationError(
        forPOSIXError errorCode: Int32
    ) -> IOSPendingRecordingAudioFileSystemError {
        errorCode == EACCES || errorCode == EPERM
            ? .dataProtectionUnavailable
            : .mediaValidationFailed
    }

    private let beforeDurationLoad: @Sendable () -> Void
    private let onDuplicatedDescriptorClosed: @Sendable () -> Void
}

final class AudioToolboxMediaValidationWorkerGate:
    @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = false

    func begin() -> Bool {
        lock.withLock {
            guard !inFlight else { return false }
            inFlight = true
            return true
        }
    }

    func finish() {
        lock.withLock { inFlight = false }
    }
}

private extension IOSPendingRecordingAudioFormat {
    var audioFileTypeHint: AudioFileTypeID {
        switch self {
        case .m4a:
            kAudioFileM4AType
        case .wav:
            kAudioFileWAVEType
        }
    }
}

private final class DescriptorAudioFileContext: @unchecked Sendable {
    private let fileDescriptor: Int32
    fileprivate let byteCount: Int64
    private let lock = NSLock()
    private var storedReadError: Int32?
    private var cancelled = false
    private let onClose: @Sendable () -> Void

    init(
        fileDescriptor: Int32,
        byteCount: Int64,
        onClose: @escaping @Sendable () -> Void
    ) {
        self.fileDescriptor = fileDescriptor
        self.byteCount = byteCount
        self.onClose = onClose
    }

    var protectedDataFailure: Bool {
        lock.withLock {
            storedReadError == EACCES || storedReadError == EPERM
        }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    func durationSeconds(fileTypeHint: AudioFileTypeID) throws -> Float64 {
        var audioFile: AudioFileID?
        let openStatus = AudioFileOpenWithCallbacks(
            Unmanaged.passUnretained(self).toOpaque(),
            descriptorAudioFileRead,
            nil,
            descriptorAudioFileGetSize,
            nil,
            fileTypeHint,
            &audioFile
        )
        guard openStatus == noErr, let audioFile else {
            throw IOSPendingRecordingAudioFileSystemError.mediaValidationFailed
        }
        defer { AudioFileClose(audioFile) }

        var actualFileType: AudioFileTypeID = 0
        var actualFileTypeSize = UInt32(
            MemoryLayout.size(ofValue: actualFileType)
        )
        guard AudioFileGetProperty(
            audioFile,
            kAudioFilePropertyFileFormat,
            &actualFileTypeSize,
            &actualFileType
        ) == noErr,
        actualFileType == fileTypeHint else {
            throw IOSPendingRecordingAudioFileSystemError.mediaValidationFailed
        }

        var extendedAudioFile: ExtAudioFileRef?
        guard ExtAudioFileWrapAudioFileID(
            audioFile,
            false,
            &extendedAudioFile
        ) == noErr,
        let extendedAudioFile else {
            throw IOSPendingRecordingAudioFileSystemError.mediaValidationFailed
        }
        defer { ExtAudioFileDispose(extendedAudioFile) }

        var dataFormat = AudioStreamBasicDescription()
        var dataFormatSize = UInt32(MemoryLayout.size(ofValue: dataFormat))
        guard ExtAudioFileGetProperty(
            extendedAudioFile,
            kExtAudioFileProperty_FileDataFormat,
            &dataFormatSize,
            &dataFormat
        ) == noErr,
        dataFormat.mChannelsPerFrame > 0,
        dataFormat.mSampleRate.isFinite,
        dataFormat.mSampleRate > 0 else {
            throw IOSPendingRecordingAudioFileSystemError.mediaValidationFailed
        }

        var frameCount: Int64 = 0
        var frameCountSize = UInt32(MemoryLayout.size(ofValue: frameCount))
        guard ExtAudioFileGetProperty(
            extendedAudioFile,
            kExtAudioFileProperty_FileLengthFrames,
            &frameCountSize,
            &frameCount
        ) == noErr,
        frameCount > 0 else {
            throw IOSPendingRecordingAudioFileSystemError.mediaValidationFailed
        }
        return Float64(frameCount) / dataFormat.mSampleRate
    }

    fileprivate func read(
        position: Int64,
        requestedByteCount: UInt32,
        buffer: UnsafeMutableRawPointer,
        actualByteCount: UnsafeMutablePointer<UInt32>
    ) -> OSStatus {
        actualByteCount.pointee = 0
        guard !lock.withLock({ cancelled }) else {
            return OSStatus(ECANCELED)
        }
        guard position >= 0, position <= byteCount else {
            return OSStatus(EINVAL)
        }
        let remaining = byteCount - position
        let boundedCount = min(Int64(requestedByteCount), remaining)
        guard boundedCount > 0 else { return noErr }

        var interruptedRetryCount = 0
        while true {
            let result = Darwin.pread(
                fileDescriptor,
                buffer,
                Int(boundedCount),
                off_t(position)
            )
            if result >= 0 {
                actualByteCount.pointee = UInt32(result)
                return noErr
            }
            let errorCode = errno
            if errorCode == EINTR, interruptedRetryCount < 8 {
                interruptedRetryCount += 1
                continue
            }
            lock.withLock {
                if storedReadError == nil {
                    storedReadError = errorCode
                }
            }
            return OSStatus(errorCode)
        }
    }

    deinit {
        Darwin.close(fileDescriptor)
        onClose()
    }
}

private let descriptorAudioFileRead: AudioFile_ReadProc = {
    clientData,
    position,
    requestedByteCount,
    buffer,
    actualByteCount in
    return Unmanaged<DescriptorAudioFileContext>
        .fromOpaque(clientData)
        .takeUnretainedValue()
        .read(
            position: position,
            requestedByteCount: requestedByteCount,
            buffer: buffer,
            actualByteCount: actualByteCount
        )
}

private let descriptorAudioFileGetSize: AudioFile_GetSizeProc = {
    clientData in
    return Unmanaged<DescriptorAudioFileContext>
        .fromOpaque(clientData)
        .takeUnretainedValue()
        .byteCount
}

private final class LockedMediaValidationResult: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var result: Result<Int64, IOSPendingRecordingAudioFileSystemError>?

    func complete(
        _ result: Result<Int64, IOSPendingRecordingAudioFileSystemError>
    ) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        lock.unlock()
        semaphore.signal()
    }

    func wait(
        timeoutNanoseconds: UInt64
    ) -> Result<Int64, IOSPendingRecordingAudioFileSystemError>? {
        let timeout = DispatchTime.now() + .nanoseconds(
            Int(min(timeoutNanoseconds, UInt64(Int.max)))
        )
        guard semaphore.wait(timeout: timeout) == .success else { return nil }
        return lock.withLock { result }
    }
}

final class FoundationIOSPendingRecordingAudioFileSystem:
    IOSPendingRecordingAudioFileSystem,
    @unchecked Sendable {
    static let maximumAudioByteCount: Int64 = 25_000_000
    static let maximumTransferByteCount = 64 * 1_024
    static let maximumInterruptedRetryCount = 8
    static let maximumProtectedAudioFinalCount = 11
    static let copyDeadlineNanoseconds: UInt64 = 10_000_000_000
    static let mediaValidationDeadlineNanoseconds: UInt64 = 2_000_000_000
    static let maximumDurationDeltaMilliseconds: Int64 = 250

    private static let audioMarkerName =
        "com.holdtype.ios.pending-recording-audio"
    private static let audioMarkerValue = Array("v1".utf8)
    private static let completeProtectionClass: Int32 = 1
    private static let backupExclusionAttributeName =
        "com.apple.metadata:com_apple_backup_excludeItem"
    private static let backupExclusionAttributeValue: [UInt8] = [
        0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30,
        0x5F, 0x10, 0x11, 0x63, 0x6F, 0x6D, 0x2E, 0x61,
        0x70, 0x70, 0x6C, 0x65, 0x2E, 0x62, 0x61, 0x63,
        0x6B, 0x75, 0x70, 0x64, 0x08, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x1C,
    ]

    private let applicationSupportDirectoryURL: URL
    fileprivate let adapter: any IOSPendingRecordingPOSIXAdapter
    private let mediaValidator: any IOSPendingRecordingMediaValidating
    private let monotonicClock: @Sendable () -> UInt64?
    private let queue: DispatchQueue
    private let configuredExpectedRepositoryRoot:
        IOSPersistenceRepositoryRootIdentity?
    private let onRepositoryIdentityMismatch: @Sendable () -> Void
    private let audioRemovalIntentStore:
        any IOSPendingRecordingAudioRemovalIntentStoring
    /// Accessed only by `queue`. A post-unlink failure keeps the exact opened
    /// descriptors alive so same-process recovery cannot accept a recreated
    /// pathname as the removed inode.
    private var retainedProtectedAudioCleanup:
        RetainedProtectedAudioCleanup?
    /// A timeout can win the continuation race after queued work has already
    /// produced evidence. Preserve that exact result for the matching retry.
    private var lateProtectedAudioCleanupEvidence:
        IOSPendingRecordingProtectedAudioCleanupEvidence?
    /// Accepted-output removal keeps the exact pre-unlink inode and directory
    /// open across an uncertain boundary. A retry may unlink again only while
    /// that same inode still owns the pathname; a recreated path is preserved.
    private var retainedAcceptedOutputAudioRemoval:
        RetainedAcceptedOutputAudioRemoval?
    /// A timeout may win after the queued operation already produced evidence.
    /// Rebind that completed intent to the next active root lease only after a
    /// fresh absence barrier.
    private var lateAcceptedOutputAudioRemovalEvidence:
        IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence?

    init(
        applicationSupportDirectoryURL: URL,
        adapter: any IOSPendingRecordingPOSIXAdapter =
            DarwinIOSPendingRecordingPOSIXAdapter(),
        mediaValidator: any IOSPendingRecordingMediaValidating =
            AudioToolboxIOSPendingRecordingMediaValidator(),
        monotonicClock: @escaping @Sendable () -> UInt64? = {
            systemPendingRecordingMonotonicNanoseconds()
        },
        expectedRepositoryRoot:
            IOSPersistenceRepositoryRootIdentity? = nil,
        onRepositoryIdentityMismatch:
            @escaping @Sendable () -> Void = {},
        audioRemovalIntentStore:
            (any IOSPendingRecordingAudioRemovalIntentStoring)? = nil,
        queue: DispatchQueue = DispatchQueue(
            label: "app.holdtype.pending-recording-audio",
            qos: .utility
        )
    ) {
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
        self.adapter = adapter
        self.mediaValidator = mediaValidator
        self.monotonicClock = monotonicClock
        configuredExpectedRepositoryRoot = expectedRepositoryRoot
        self.onRepositoryIdentityMismatch =
            onRepositoryIdentityMismatch
        self.audioRemovalIntentStore = audioRemovalIntentStore
            ?? FoundationIOSPendingRecordingAudioRemovalIntentRepository(
                applicationSupportDirectoryURL:
                    applicationSupportDirectoryURL,
                expectedRepositoryRoot: expectedRepositoryRoot,
                onRepositoryIdentityMismatch:
                    onRepositoryIdentityMismatch
            )
        self.queue = queue
    }

    deinit {
        if let retainedProtectedAudioCleanup {
            adapter.closeFile(retainedProtectedAudioCleanup.fileDescriptor)
            adapter.closeFile(
                retainedProtectedAudioCleanup.directory.descriptor
            )
        }
        if let retainedAcceptedOutputAudioRemoval {
            adapter.closeFile(
                retainedAcceptedOutputAudioRemoval.fileDescriptor
            )
            adapter.closeFile(
                retainedAcceptedOutputAudioRemoval.directory.descriptor
            )
        }
    }

    func reconcileProtectedAudioCleanup(
        using authorization:
            IOSPendingRecordingProtectedAudioCleanupAuthorization
    ) async throws -> IOSPendingRecordingProtectedAudioCleanupEvidence {
        try await runQueued(
            deadlineNanoseconds: Self.copyDeadlineNanoseconds,
            onLateValue: { [self] evidence in
                lateProtectedAudioCleanupEvidence = evidence
            }
        ) { control in
            try self.reconcileProtectedAudioCleanupSynchronously(
                using: authorization,
                control: control
            )
        }
    }

    func reconcileAcceptedOutputAudioRemoval(
        using authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization
    ) async throws
        -> IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence {
        try await runQueued(
            deadlineNanoseconds: Self.copyDeadlineNanoseconds,
            onLateValue: { [self] evidence in
                lateAcceptedOutputAudioRemovalEvidence = evidence
            }
        ) { control in
            try self.reconcilePendingAudioRemovalSynchronously(
                using: authorization,
                control: control
            )
        }
    }

    func reconcilePendingAudioRemoval(
        using authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization
    ) async throws
        -> IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence {
        try await reconcileAcceptedOutputAudioRemoval(using: authorization)
    }

    #if DEBUG
    func requireEmptyNamespace() async throws {
        try await runQueued(deadlineNanoseconds: Self.copyDeadlineNanoseconds) { control in
            guard let directory = try self.openPendingDirectory(
                createIfMissing: false,
                control: control
            ) else {
                return
            }
            defer { self.adapter.closeFile(directory.descriptor) }
            try self.requireNoEntries(in: directory, control: control)
        }
    }
    #endif

    func validateProtectedAudioNamespace(
        _ inventory: IOSProtectedAudioNamespaceInventory
    ) async throws {
        try await runQueued(
            deadlineNanoseconds: Self.copyDeadlineNanoseconds
        ) { control in
            let expectations = try self.protectedAudioExpectations(
                for: inventory
            )
            try self.requireInventoryAuthority(
                inventory,
                control: control
            )
            guard let directory = try self.openPendingDirectory(
                createIfMissing: false,
                expectedRepositoryRoot:
                    inventory.repositoryBinding.physicalRootIdentity,
                control: control
            ) else {
                guard expectations.isEmpty else {
                    throw IOSPendingRecordingAudioFileSystemError
                        .protectedAudioMissing
                }
                try self.requireInventoryAuthority(
                    inventory,
                    control: control
                )
                return
            }
            defer { self.adapter.closeFile(directory.descriptor) }
            try self.validateProtectedAudioNamespace(
                expectations,
                in: directory,
                inventory: inventory,
                control: control
            )
        }
    }

    func validateProtectedAudioNamespace(
        _ inventory: IOSProtectedAudioNamespaceInventory,
        holding audioLeases: [any IOSPendingRecordingPublishedAudioLease]
    ) async throws {
        guard !audioLeases.isEmpty else {
            try await validateProtectedAudioNamespace(inventory)
            return
        }
        guard audioLeases.count <= Self.maximumProtectedAudioFinalCount,
              Set(audioLeases.map { ObjectIdentifier($0) }).count
                == audioLeases.count else {
            throw IOSPendingRecordingAudioFileSystemError
                .protectedAudioInvalid
        }

        var heldOperations: [HeldProtectedAudioLeaseOperation] = []
        do {
            for audioLease in audioLeases {
                guard let audioLease = audioLease as?
                        POSIXIOSPendingRecordingPublishedAudioLease else {
                    throw IOSPendingRecordingAudioFileSystemError
                        .protectedAudioInvalid
                }
                heldOperations.append(
                    try audioLease.beginNamespaceValidation(
                        expectedFileSystem: self
                    )
                )
            }
        } catch {
            heldOperations.forEach { $0.finish() }
            throw error
        }
        let activeHeldOperations = heldOperations

        try await runQueued(
            deadlineNanoseconds: Self.copyDeadlineNanoseconds,
            onOperationFinished: {
                activeHeldOperations.forEach { $0.finish() }
            }
        ) { control in
            let expectations = try self.protectedAudioExpectations(
                for: inventory
            )
            let heldExpectations = try activeHeldOperations.map { operation in
                guard let expectation = expectations.first(where: {
                    $0.relativeIdentifier == operation.relativeIdentifier
                }),
                expectation.durationMilliseconds
                    == operation.durationMilliseconds,
                expectation.byteCount == operation.byteCount,
                let expectedFileURL = IOSPendingRecordingStorageLocation
                    .audioFileURL(
                        forRelativeIdentifier:
                            expectation.relativeIdentifier,
                        in: self.applicationSupportDirectoryURL
                    ),
                expectedFileURL == operation.fileURL else {
                    throw IOSPendingRecordingAudioFileSystemError
                        .protectedAudioInvalid
                }
                return HeldProtectedAudioExpectation(
                    expectation: expectation,
                    descriptor: operation.fileDescriptor,
                    identity: operation.identity,
                    name: operation.fileURL.lastPathComponent
                )
            }
            guard Set(heldExpectations.map {
                $0.expectation.relativeIdentifier
            }).count == heldExpectations.count else {
                throw IOSPendingRecordingAudioFileSystemError
                    .protectedAudioInvalid
            }
            try self.requireInventoryAuthority(
                inventory,
                control: control
            )
            guard let directory = try self.openPendingDirectory(
                createIfMissing: false,
                expectedRepositoryRoot:
                    inventory.repositoryBinding.physicalRootIdentity,
                control: control
            ) else {
                throw IOSPendingRecordingAudioFileSystemError
                    .protectedAudioMissing
            }
            defer { self.adapter.closeFile(directory.descriptor) }
            try self.validateProtectedAudioNamespace(
                expectations,
                in: directory,
                inventory: inventory,
                control: control,
                heldAudio: heldExpectations
            )
        }
    }

    #if DEBUG
    func publishProtectedCopy(
        from source: AudioRecordingArtifact,
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat,
        durationMilliseconds: Int64
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        try await publishProtectedCopy(
            from: source,
            attemptID: attemptID,
            format: format,
            durationMilliseconds: durationMilliseconds,
            expectedRepositoryRoot: nil
        )
    }

    func publishProtectedCopy(
        from source: AudioRecordingArtifact,
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat,
        durationMilliseconds: Int64,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        try await runQueued(
            deadlineNanoseconds: Self.copyDeadlineNanoseconds,
            onLateValue: { $0.release() }
        ) { control in
            try self.publishProtectedCopySynchronously(
                from: source,
                attemptID: attemptID,
                format: format,
                durationMilliseconds: durationMilliseconds,
                expectedRepositoryRoot: expectedRepositoryRoot,
                inventory: nil,
                control: control
            )
        }
    }
    #endif

    func publishProtectedCopy(
        from source: AudioRecordingArtifact,
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat,
        durationMilliseconds: Int64,
        inventory: IOSProtectedAudioNamespaceInventory
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        try await runQueued(
            deadlineNanoseconds: Self.copyDeadlineNanoseconds,
            onLateValue: { $0.release() }
        ) { control in
            try self.publishProtectedCopySynchronously(
                from: source,
                attemptID: attemptID,
                format: format,
                durationMilliseconds: durationMilliseconds,
                expectedRepositoryRoot:
                    inventory.repositoryBinding.physicalRootIdentity,
                inventory: inventory,
                control: control
            )
        }
    }

    func validatePublishedAudio(
        relativeIdentifier: String,
        attemptID: UUID,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) async throws -> AudioRecordingArtifact {
        let lease = try await acquireValidatedPublishedAudio(
            relativeIdentifier: relativeIdentifier,
            attemptID: attemptID,
            durationMilliseconds: durationMilliseconds,
            byteCount: byteCount
        )
        defer { lease.release() }
        return lease.audioArtifact
    }

    func acquireValidatedPublishedAudio(
        relativeIdentifier: String,
        attemptID: UUID,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        try await runQueued(
            deadlineNanoseconds: Self.copyDeadlineNanoseconds,
            onLateValue: { $0.release() }
        ) { control in
            let opened = try self.openValidatedPublishedAudio(
                relativeIdentifier: relativeIdentifier,
                attemptID: attemptID,
                durationMilliseconds: durationMilliseconds,
                byteCount: byteCount,
                control: control
            )
            return POSIXIOSPendingRecordingPublishedAudioLease(
                fileSystem: self,
                relativeIdentifier: relativeIdentifier,
                fileURL: opened.artifact.fileURL,
                directoryDescriptor: opened.directoryDescriptor,
                fileDescriptor: opened.fileDescriptor,
                identity: opened.identity,
                byteCount: byteCount,
                durationMilliseconds: durationMilliseconds
            )
        }
    }

    func removePublishedAudioIfPresent(
        relativeIdentifier: String,
        attemptID: UUID,
        expectedByteCount: Int64
    ) async throws -> Bool {
        try await removePublishedAudioIfPresent(
            relativeIdentifier: relativeIdentifier,
            attemptID: attemptID,
            expectedByteCount: expectedByteCount,
            expectedRepositoryRoot: nil
        )
    }

    func removePublishedAudioIfPresent(
        relativeIdentifier: String,
        attemptID: UUID,
        expectedByteCount: Int64,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) async throws -> Bool {
        try await runQueued(deadlineNanoseconds: Self.copyDeadlineNanoseconds) { control in
            try self.removePublishedAudioSynchronously(
                relativeIdentifier: relativeIdentifier,
                attemptID: attemptID,
                expectedByteCount: expectedByteCount,
                expectedRepositoryRoot: expectedRepositoryRoot,
                control: control
            )
        }
    }

    private func runQueued<Value: Sendable>(
        deadlineNanoseconds: UInt64,
        onLateValue: @escaping @Sendable (Value) -> Void = { _ in },
        onOperationFinished: @escaping @Sendable () -> Void = {},
        operation: @escaping @Sendable (PendingRecordingOperationControl) throws -> Value
    ) async throws -> Value {
        let control: PendingRecordingOperationControl
        do {
            control = try PendingRecordingOperationControl(
                timeoutNanoseconds: deadlineNanoseconds,
                monotonicClock: monotonicClock
            )
        } catch {
            onOperationFinished()
            throw error
        }
        let completion = PendingRecordingOperationCompletion<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                queue.async {
                    defer { onOperationFinished() }
                    do {
                        let value = try operation(control)
                        guard completion.resolve(.success(value)) else {
                            onLateValue(value)
                            return
                        }
                    } catch {
                        _ = completion.resolve(.failure(error))
                    }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + .nanoseconds(
                        Int(min(deadlineNanoseconds, UInt64(Int.max)))
                    )
                ) {
                    control.expire()
                    _ = completion.resolve(
                        .failure(
                            IOSPendingRecordingAudioFileSystemError.operationTimedOut
                        )
                    )
                }
            }
        } onCancel: {
            control.cancel()
            _ = completion.resolve(
                .failure(IOSPendingRecordingAudioFileSystemError.operationCancelled)
            )
        }
    }
}

fileprivate extension FoundationIOSPendingRecordingAudioFileSystem {
    struct DirectoryHandle: @unchecked Sendable {
        let descriptor: Int32
        let effectiveUserID: uid_t
        let identity: FileIdentity
    }

    struct OpenedPublishedAudio {
        let directoryDescriptor: Int32
        let fileDescriptor: Int32
        let identity: FileIdentity
        let artifact: AudioRecordingArtifact
    }

    struct ProtectedAudioExpectation: Equatable, Sendable {
        let attemptID: UUID
        let relativeIdentifier: String
        let durationMilliseconds: Int64?
        let byteCount: Int64
    }

    struct HeldProtectedAudioExpectation {
        let expectation: ProtectedAudioExpectation
        let descriptor: Int32
        let identity: FileIdentity
        let name: String
    }

    struct HeldProtectedAudioLeaseOperation: @unchecked Sendable {
        let relativeIdentifier: String
        let fileURL: URL
        let fileDescriptor: Int32
        let identity: FileIdentity
        let durationMilliseconds: Int64
        let byteCount: Int64
        let finish: @Sendable () -> Void
    }

    struct OpenedProtectedAudioCleanupTarget {
        let descriptor: Int32
        let identity: FileIdentity
        let name: String
    }

    struct RetainedProtectedAudioCleanup {
        let authorization:
            IOSPendingRecordingProtectedAudioCleanupAuthorization
        let directory: DirectoryHandle
        let fileDescriptor: Int32
        let fileIdentity: FileIdentity
        let targetExpectation: ProtectedAudioExpectation
        let targetName: String
    }

    struct RetainedAcceptedOutputAudioRemoval {
        let authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization
        let durableIntent: IOSPendingRecordingAudioRemovalIntent
        let directory: DirectoryHandle
        let fileDescriptor: Int32
        let fileIdentity: FileIdentity
        let targetName: String
    }

    enum RetainedProtectedAudioLinkState: Equatable {
        case present
        case absent
    }

    func protectedAudioExpectations(
        for inventory: IOSProtectedAudioNamespaceInventory
    ) throws -> [ProtectedAudioExpectation] {
        guard inventory.artifacts.count
                <= Self.maximumProtectedAudioFinalCount else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceNotEmpty
        }
        let expectations = inventory.artifacts.map { artifact in
            switch artifact {
            case .row(
                let attemptID,
                let relativeIdentifier,
                let durationMilliseconds,
                let byteCount
            ):
                ProtectedAudioExpectation(
                    attemptID: attemptID,
                    relativeIdentifier: relativeIdentifier,
                    durationMilliseconds: durationMilliseconds,
                    byteCount: byteCount
                )
            case .tombstone(
                let attemptID,
                let relativeIdentifier,
                let byteCount
            ):
                ProtectedAudioExpectation(
                    attemptID: attemptID,
                    relativeIdentifier: relativeIdentifier,
                    durationMilliseconds: nil,
                    byteCount: byteCount
                )
            }
        }
        let attemptIDs = expectations.map(\.attemptID)
        let relativeIdentifiers = expectations.map(\.relativeIdentifier)
        guard Set(attemptIDs).count == expectations.count,
              Set(relativeIdentifiers).count == expectations.count,
              expectations.allSatisfy({ expectation in
                  guard expectation.byteCount > 0,
                        expectation.byteCount < Self.maximumAudioByteCount,
                        let parsed = IOSPendingRecordingStorageLocation
                            .parseRelativeAudioIdentifier(
                                expectation.relativeIdentifier
                            ),
                        parsed.attemptID == expectation.attemptID,
                        let fileURL = IOSPendingRecordingStorageLocation
                            .audioFileURL(
                                forRelativeIdentifier:
                                    expectation.relativeIdentifier,
                                in: applicationSupportDirectoryURL
                            ),
                        expectation.relativeIdentifier
                            == expectedRelativeIdentifier(
                                attemptID: expectation.attemptID,
                                fileExtension: fileURL.pathExtension
                            ) else {
                      return false
                  }
                  guard let duration = expectation.durationMilliseconds else {
                      return true
                  }
                  return duration > 0 && duration < 300_000
              }) else {
            throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        }
        return expectations
    }

    func reconcileProtectedAudioCleanupSynchronously(
        using authorization:
            IOSPendingRecordingProtectedAudioCleanupAuthorization,
        control: PendingRecordingOperationControl
    ) throws -> IOSPendingRecordingProtectedAudioCleanupEvidence {
        try requireProtectedAudioCleanupAuthority(
            authorization,
            control: control
        )

        if retainedProtectedAudioCleanup != nil {
            return try finishRetainedProtectedAudioCleanup(
                using: authorization,
                control: control
            )
        }
        if lateProtectedAudioCleanupEvidence != nil {
            return try reconcileLateProtectedAudioCleanupEvidence(
                using: authorization,
                control: control
            )
        }

        let cleanup = try protectedAudioCleanupExpectations(
            for: authorization
        )
        guard let directory = try openPendingDirectory(
            createIfMissing: false,
            expectedRepositoryRoot: authorization.inventory
                .repositoryBinding.physicalRootIdentity,
            control: control
        ) else {
            // An absent directory has no exact directory identity to bind to
            // the cleanup receipt. Preserve the tombstone for later recovery.
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
        var ownsDirectory = true
        defer {
            if ownsDirectory {
                adapter.closeFile(directory.descriptor)
            }
        }

        let allNames = try expectedProtectedAudioNames(
            cleanup.all,
            failure: .protectedAudioInvalid
        )
        let remainingNames = try expectedProtectedAudioNames(
            cleanup.remaining,
            failure: .protectedAudioInvalid
        )
        let observedNames = try protectedAudioFinalNames(
            in: directory,
            control: control
        )
        if observedNames == remainingNames {
            return try provePreexistingProtectedAudioAbsence(
                using: authorization,
                cleanup: cleanup,
                directory: directory,
                control: control
            )
        }
        guard observedNames == allNames else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceNotEmpty
        }

        let target = try openLockedProtectedAudioCleanupTarget(
            cleanup.target,
            in: directory,
            control: control
        )
        var ownsTarget = true
        defer {
            if ownsTarget {
                adapter.closeFile(target.descriptor)
            }
        }
        let heldTarget = HeldProtectedAudioExpectation(
            expectation: cleanup.target,
            descriptor: target.descriptor,
            identity: target.identity,
            name: target.name
        )
        try validateProtectedAudioNamespace(
            cleanup.all,
            in: directory,
            inventory: authorization.inventory,
            control: control,
            heldAudio: [heldTarget]
        )
        try validateHeldProtectedAudioExpectation(
            heldTarget,
            in: directory,
            control: control
        )
        try requireProtectedAudioCleanupAuthority(
            authorization,
            control: control
        )
        try validatePendingDirectoryPath(directory, control: control)
        retainedProtectedAudioCleanup = RetainedProtectedAudioCleanup(
            authorization: authorization,
            directory: directory,
            fileDescriptor: target.descriptor,
            fileIdentity: target.identity,
            targetExpectation: cleanup.target,
            targetName: target.name
        )
        ownsDirectory = false
        ownsTarget = false
        try attemptRetainedProtectedAudioUnlink(control: control)
        return try finishRetainedProtectedAudioCleanup(
            using: authorization,
            control: control
        )
    }

    func protectedAudioCleanupExpectations(
        for authorization:
            IOSPendingRecordingProtectedAudioCleanupAuthorization
    ) throws -> (
        all: [ProtectedAudioExpectation],
        target: ProtectedAudioExpectation,
        remaining: [ProtectedAudioExpectation]
    ) {
        let all = try protectedAudioExpectations(
            for: authorization.inventory
        )
        let tombstone = authorization.cleanupAuthorization.tombstone
        let candidates = all.filter {
            $0.attemptID == tombstone.attemptID
                && $0.relativeIdentifier
                    == tombstone.audioRelativeIdentifier
                && $0.durationMilliseconds == nil
                && $0.byteCount == tombstone.byteCount
        }
        guard candidates.count == 1, let target = candidates.first else {
            throw IOSPendingRecordingAudioFileSystemError
                .protectedAudioInvalid
        }
        let remaining = all.filter { $0 != target }
        guard remaining.count + 1 == all.count else {
            throw IOSPendingRecordingAudioFileSystemError
                .protectedAudioInvalid
        }
        return (all, target, remaining)
    }

    func requireProtectedAudioCleanupAuthority(
        _ authorization:
            IOSPendingRecordingProtectedAudioCleanupAuthorization,
        control: PendingRecordingOperationControl
    ) throws {
        let cleanup = authorization.cleanupAuthorization
        guard cleanup.operationLeaseAuthorization.provesActiveLease(),
              cleanup.failedInventory
                == authorization.inventory.failedInventory,
              cleanup.failedSource
                == authorization.inventory.failedInventory.failedSource,
              cleanup.failedStoreIdentity
                == authorization.inventory.failedStoreIdentity,
              cleanup.expectedPendingStoreIdentity
                == authorization.inventory.expectedPendingStoreIdentity,
              cleanup.ownerIdentity == authorization.inventory.ownerIdentity,
              cleanup.repositoryBinding
                == authorization.inventory.repositoryBinding,
              cleanup.operationLeaseAuthorization.provesSameActiveLease(
                  as: authorization.inventory
                      .operationLeaseAuthorization
              ) else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
        try requireInventoryAuthority(
            authorization.inventory,
            control: control
        )
        _ = try protectedAudioCleanupExpectations(for: authorization)
    }

    func expectedProtectedAudioNames(
        _ expectations: [ProtectedAudioExpectation],
        failure: IOSPendingRecordingAudioFileSystemError
    ) throws -> Set<String> {
        let names = try expectations.map { expectation in
            guard let fileURL = IOSPendingRecordingStorageLocation.audioFileURL(
                forRelativeIdentifier: expectation.relativeIdentifier,
                in: applicationSupportDirectoryURL
            ) else {
                throw failure
            }
            return fileURL.lastPathComponent
        }
        guard Set(names).count == names.count else { throw failure }
        return Set(names)
    }

    func openLockedProtectedAudioCleanupTarget(
        _ expectation: ProtectedAudioExpectation,
        in directory: DirectoryHandle,
        control: PendingRecordingOperationControl
    ) throws -> OpenedProtectedAudioCleanupTarget {
        guard expectation.durationMilliseconds == nil,
              let fileURL = IOSPendingRecordingStorageLocation.audioFileURL(
                  forRelativeIdentifier: expectation.relativeIdentifier,
                  in: applicationSupportDirectoryURL
              ) else {
            throw IOSPendingRecordingAudioFileSystemError
                .protectedAudioInvalid
        }
        let name = fileURL.lastPathComponent
        try validatePendingDirectoryPath(directory, control: control)
        let pathResult = try call(control: control) {
            adapter.statusAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }
        if case .failure(let errorCode) = pathResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        }
        guard case .success(let pathStatus) = pathResult else {
            throw IOSPendingRecordingAudioFileSystemError
                .protectedAudioInvalid
        }
        let openResult = try call(control: control) {
            adapter.openAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
                mode: nil
            )
        }
        if case .failure(let errorCode) = openResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        }
        guard case .success(let descriptor) = openResult else {
            throw IOSPendingRecordingAudioFileSystemError
                .protectedAudioInvalid
        }
        do {
            let descriptorStatus = try status(
                descriptor: descriptor,
                control: control,
                failure: .protectedAudioInvalid
            )
            let identity = FileIdentity(descriptorStatus)
            guard isExactOwnedAudioStatus(
                descriptorStatus,
                effectiveUserID: directory.effectiveUserID,
                expectedByteCount: expectation.byteCount
            ),
            isExactOwnedAudioStatus(
                pathStatus,
                effectiveUserID: directory.effectiveUserID,
                expectedByteCount: expectation.byteCount
            ),
            FileSnapshot(descriptorStatus) == FileSnapshot(pathStatus) else {
                throw IOSPendingRecordingAudioFileSystemError
                    .protectedAudioInvalid
            }
            try validateExactConfiguration(
                descriptor: descriptor,
                control: control
            )
            try requireSuccess(
                control: control,
                failure: .protectedAudioInvalid
            ) {
                adapter.lock(
                    fileDescriptor: descriptor,
                    operation: LOCK_EX | LOCK_NB
                )
            }
            try validateOwnedAudio(
                descriptor: descriptor,
                name: name,
                directory: directory,
                expectedIdentity: identity,
                expectedByteCount: expectation.byteCount,
                control: control
            )
            return OpenedProtectedAudioCleanupTarget(
                descriptor: descriptor,
                identity: identity,
                name: name
            )
        } catch {
            adapter.closeFile(descriptor)
            throw error
        }
    }

    func provePreexistingProtectedAudioAbsence(
        using authorization:
            IOSPendingRecordingProtectedAudioCleanupAuthorization,
        cleanup: (
            all: [ProtectedAudioExpectation],
            target: ProtectedAudioExpectation,
            remaining: [ProtectedAudioExpectation]
        ),
        directory: DirectoryHandle,
        control: PendingRecordingOperationControl
    ) throws -> IOSPendingRecordingProtectedAudioCleanupEvidence {
        try validateProtectedAudioCleanupAbsence(
            using: authorization,
            target: cleanup.target,
            remaining: cleanup.remaining,
            directory: directory,
            control: control
        )
        return IOSPendingRecordingProtectedAudioCleanupEvidence(
            authorization: authorization,
            disposition: .alreadyAbsent,
            directoryIdentity: physicalIdentity(directory.identity),
            removedFileIdentity: nil
        )
    }

    func finishRetainedProtectedAudioCleanup(
        using authorization:
            IOSPendingRecordingProtectedAudioCleanupAuthorization,
        control: PendingRecordingOperationControl
    ) throws -> IOSPendingRecordingProtectedAudioCleanupEvidence {
        guard let retained = retainedProtectedAudioCleanup,
              retained.authorization.provesSameCleanup(
                  as: authorization
              ) else {
            throw IOSPendingRecordingAudioFileSystemError
                .protectedAudioInvalid
        }
        try requireProtectedAudioCleanupAuthority(
            authorization,
            control: control
        )
        let cleanup = try protectedAudioCleanupExpectations(
            for: authorization
        )
        guard cleanup.target == retained.targetExpectation else {
            throw IOSPendingRecordingAudioFileSystemError
                .protectedAudioInvalid
        }
        try validatePendingDirectoryPath(
            retained.directory,
            control: control
        )
        switch try retainedProtectedAudioLinkState(
            retained,
            control: control
        ) {
        case .present:
            try attemptRetainedProtectedAudioUnlink(control: control)
        case .absent:
            break
        }
        let confirmedRetained = try requireRetainedProtectedAudioCleanup()
        try validateUnlinkedProtectedAudioCleanupTarget(
            confirmedRetained,
            control: control
        )
        try validateProtectedAudioCleanupAbsence(
            using: authorization,
            target: cleanup.target,
            remaining: cleanup.remaining,
            directory: confirmedRetained.directory,
            control: control
        )
        try validateUnlinkedProtectedAudioCleanupTarget(
            confirmedRetained,
            control: control
        )
        let evidence = IOSPendingRecordingProtectedAudioCleanupEvidence(
            authorization: authorization,
            disposition: .removed,
            directoryIdentity: physicalIdentity(
                confirmedRetained.directory.identity
            ),
            removedFileIdentity: physicalIdentity(
                confirmedRetained.fileIdentity
            )
        )
        retainedProtectedAudioCleanup = nil
        adapter.closeFile(confirmedRetained.fileDescriptor)
        adapter.closeFile(confirmedRetained.directory.descriptor)
        return evidence
    }

    func reconcileLateProtectedAudioCleanupEvidence(
        using authorization:
            IOSPendingRecordingProtectedAudioCleanupAuthorization,
        control: PendingRecordingOperationControl
    ) throws -> IOSPendingRecordingProtectedAudioCleanupEvidence {
        guard let lateEvidence = lateProtectedAudioCleanupEvidence,
              lateEvidence.provesSameCleanup(as: authorization) else {
            throw IOSPendingRecordingAudioFileSystemError
                .protectedAudioInvalid
        }
        try requireProtectedAudioCleanupAuthority(
            authorization,
            control: control
        )
        let cleanup = try protectedAudioCleanupExpectations(
            for: authorization
        )
        guard let directory = try openPendingDirectory(
            createIfMissing: false,
            expectedRepositoryRoot: authorization.inventory
                .repositoryBinding.physicalRootIdentity,
            control: control
        ) else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
        defer { adapter.closeFile(directory.descriptor) }
        guard physicalIdentity(directory.identity)
                == lateEvidence.directoryIdentity else {
            throw IOSPendingRecordingAudioFileSystemError
                .protectedAudioInvalid
        }
        try validateProtectedAudioCleanupAbsence(
            using: authorization,
            target: cleanup.target,
            remaining: cleanup.remaining,
            directory: directory,
            control: control
        )
        let evidence = IOSPendingRecordingProtectedAudioCleanupEvidence(
            authorization: authorization,
            disposition: lateEvidence.disposition,
            directoryIdentity: lateEvidence.directoryIdentity,
            removedFileIdentity: lateEvidence.removedFileIdentity
        )
        lateProtectedAudioCleanupEvidence = nil
        return evidence
    }

    func validateProtectedAudioCleanupAbsence(
        using authorization:
            IOSPendingRecordingProtectedAudioCleanupAuthorization,
        target: ProtectedAudioExpectation,
        remaining: [ProtectedAudioExpectation],
        directory: DirectoryHandle,
        control: PendingRecordingOperationControl
    ) throws {
        guard let targetURL = IOSPendingRecordingStorageLocation.audioFileURL(
            forRelativeIdentifier: target.relativeIdentifier,
            in: applicationSupportDirectoryURL
        ) else {
            throw IOSPendingRecordingAudioFileSystemError
                .protectedAudioInvalid
        }
        let targetName = targetURL.lastPathComponent
        try requireMissingAfterRemoval(
            name: targetName,
            directoryDescriptor: directory.descriptor,
            control: control
        )
        try validateProtectedAudioNamespace(
            remaining,
            in: directory,
            inventory: authorization.inventory,
            control: control
        )
        try synchronize(
            directory.descriptor,
            control: control,
            failure: .removeFailed
        )
        try requireMissingAfterRemoval(
            name: targetName,
            directoryDescriptor: directory.descriptor,
            control: control
        )
        try validateProtectedAudioNamespace(
            remaining,
            in: directory,
            inventory: authorization.inventory,
            control: control
        )
        try requireMissingAfterRemoval(
            name: targetName,
            directoryDescriptor: directory.descriptor,
            control: control
        )
        try requireProtectedAudioCleanupAuthority(
            authorization,
            control: control
        )
    }

    func requireRetainedProtectedAudioCleanup()
        throws -> RetainedProtectedAudioCleanup {
        guard let retainedProtectedAudioCleanup else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        return retainedProtectedAudioCleanup
    }

    func attemptRetainedProtectedAudioUnlink(
        control: PendingRecordingOperationControl
    ) throws {
        let retained = try requireRetainedProtectedAudioCleanup()
        try control.checkpoint()
        try validatePendingDirectoryPath(
            retained.directory,
            control: control
        )
        guard try retainedProtectedAudioLinkState(
            retained,
            control: control
        ) == .present else {
            return
        }

        // Do not use the generic EINTR-retrying syscall wrapper here. POSIX
        // does not give this workflow a conditional-unlink primitive, so any
        // returned error can be boundary-ambiguous. The retained descriptor,
        // directory, and pre-unlink identity stay authoritative for retry.
        let result = adapter.unlinkAt(
            directoryDescriptor: retained.directory.descriptor,
            name: retained.targetName
        )
        switch result {
        case .success:
            return
        case .failure(let errorCode) where isDataProtectionFailure(errorCode):
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        case .failure:
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
    }

    func retainedProtectedAudioLinkState(
        _ retained: RetainedProtectedAudioCleanup,
        control: PendingRecordingOperationControl
    ) throws -> RetainedProtectedAudioLinkState {
        let descriptorStatus = try status(
            descriptor: retained.fileDescriptor,
            control: control,
            failure: .removeFailed
        )
        guard descriptorStatus.st_mode & S_IFMT == S_IFREG,
              descriptorStatus.st_uid
                == retained.directory.effectiveUserID,
              descriptorStatus.st_mode & mode_t(0o7777)
                == mode_t(0o600),
              descriptorStatus.st_size
                == off_t(retained.targetExpectation.byteCount),
              FileIdentity(descriptorStatus) == retained.fileIdentity else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        do {
            try validateExactConfiguration(
                descriptor: retained.fileDescriptor,
                control: control
            )
        } catch IOSPendingRecordingAudioFileSystemError
            .dataProtectionUnavailable {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        } catch {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }

        let pathResult = try call(control: control) {
            adapter.statusAt(
                directoryDescriptor: retained.directory.descriptor,
                name: retained.targetName,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }
        if case .failure(let errorCode) = pathResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        }
        if descriptorStatus.st_nlink == 0,
           case .failure(ENOENT) = pathResult {
            return .absent
        }
        guard descriptorStatus.st_nlink == 1,
              case .success(let pathStatus) = pathResult,
              isExactOwnedAudioStatus(
                  pathStatus,
                  effectiveUserID: retained.directory.effectiveUserID,
                  expectedByteCount:
                    retained.targetExpectation.byteCount
              ),
              FileSnapshot(pathStatus) == FileSnapshot(descriptorStatus)
        else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        return .present
    }

    func validateUnlinkedProtectedAudioCleanupTarget(
        _ retained: RetainedProtectedAudioCleanup,
        control: PendingRecordingOperationControl
    ) throws {
        let status = try status(
            descriptor: retained.fileDescriptor,
            control: control,
            failure: .removeFailed
        )
        guard status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == retained.directory.effectiveUserID,
              status.st_nlink == 0,
              status.st_mode & mode_t(0o7777) == mode_t(0o600),
              status.st_size
                == off_t(retained.targetExpectation.byteCount),
              FileIdentity(status) == retained.fileIdentity else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        do {
            try validateExactConfiguration(
                descriptor: retained.fileDescriptor,
                control: control
            )
        } catch IOSPendingRecordingAudioFileSystemError
            .dataProtectionUnavailable {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        } catch {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
    }

    func physicalIdentity(
        _ identity: FileIdentity
    ) -> IOSPendingRecordingProtectedAudioCleanupEvidence.PhysicalIdentity {
        IOSPendingRecordingProtectedAudioCleanupEvidence.PhysicalIdentity(
            device: identity.device,
            inode: identity.inode
        )
    }

    func requireInventoryAuthority(
        _ inventory: IOSProtectedAudioNamespaceInventory,
        control: PendingRecordingOperationControl
    ) throws {
        try control.checkpoint()
        guard inventory.operationLeaseAuthorization.provesActiveLease() else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
        guard let expectedRoot = inventory.repositoryBinding
                .physicalRootIdentity else {
            onRepositoryIdentityMismatch()
            throw IOSPendingRecordingAudioFileSystemError
                .repositoryIdentityConflict
        }
        let result = try call(control: control) {
            adapter.statusAtPath(applicationSupportDirectoryURL.path)
        }
        if case .failure(let errorCode) = result,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        }
        guard case .success(let status) = result,
              status.st_mode & S_IFMT == S_IFDIR,
              expectedRoot.matches(status) else {
            onRepositoryIdentityMismatch()
            throw IOSPendingRecordingAudioFileSystemError
                .repositoryIdentityConflict
        }
        guard inventory.operationLeaseAuthorization.provesActiveLease() else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
    }

    func validateProtectedAudioNamespace(
        _ expectations: [ProtectedAudioExpectation],
        in directory: DirectoryHandle,
        inventory: IOSProtectedAudioNamespaceInventory,
        control: PendingRecordingOperationControl,
        heldAudio: [HeldProtectedAudioExpectation] = []
    ) throws {
        guard expectations.count <= Self.maximumProtectedAudioFinalCount else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceNotEmpty
        }
        try requireInventoryAuthority(inventory, control: control)
        try validatePendingDirectoryPath(directory, control: control)
        let expectedNames = try Set(expectations.map { expectation in
            guard let fileURL = IOSPendingRecordingStorageLocation.audioFileURL(
                forRelativeIdentifier: expectation.relativeIdentifier,
                in: applicationSupportDirectoryURL
            ) else {
                throw IOSPendingRecordingAudioFileSystemError
                    .protectedAudioInvalid
            }
            return fileURL.lastPathComponent
        })
        guard expectedNames.count == expectations.count,
              try protectedAudioFinalNames(
                  in: directory,
                  control: control
              ) == expectedNames else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceNotEmpty
        }
        for expectation in expectations {
            if let heldAudio = heldAudio.first(where: {
                $0.expectation == expectation
            }) {
                try validateHeldProtectedAudioExpectation(
                    heldAudio,
                    in: directory,
                    control: control
                )
            } else {
                try validateProtectedAudioExpectation(
                    expectation,
                    in: directory,
                    control: control
                )
            }
        }
        guard try protectedAudioFinalNames(
            in: directory,
            control: control
        ) == expectedNames else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceNotEmpty
        }
        try validatePendingDirectoryPath(directory, control: control)
        try requireInventoryAuthority(inventory, control: control)
    }

    func protectedAudioFinalNames(
        in directory: DirectoryHandle,
        control: PendingRecordingOperationControl
    ) throws -> Set<String> {
        try validatePendingDirectoryPath(directory, control: control)
        let duplicateResult = try call(control: control) {
            adapter.openAt(
                directoryDescriptor: directory.descriptor,
                name: ".",
                flags: O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW,
                mode: nil
            )
        }
        if case .failure(let errorCode) = duplicateResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        }
        guard case .success(let duplicateDescriptor) = duplicateResult else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
        var ownsDuplicateDescriptor = true
        defer {
            if ownsDuplicateDescriptor {
                adapter.closeFile(duplicateDescriptor)
            }
        }
        let streamResult = try call(control: control) {
            adapter.openDirectoryStream(fileDescriptor: duplicateDescriptor)
        }
        if case .failure(let errorCode) = streamResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        }
        guard case .success(let stream) = streamResult else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
        ownsDuplicateDescriptor = false
        defer { adapter.closeDirectoryStream(stream) }

        var names = Set<String>()
        var finalCount = 0
        while true {
            let entryResult = try call(control: control) {
                adapter.nextDirectoryEntry(stream: stream)
            }
            if case .failure(let errorCode) = entryResult,
               isDataProtectionFailure(errorCode) {
                throw IOSPendingRecordingAudioFileSystemError
                    .dataProtectionUnavailable
            }
            guard case .success(let entry) = entryResult else {
                throw IOSPendingRecordingAudioFileSystemError
                    .namespaceUnavailable
            }
            guard let entry else { break }
            switch entry {
            case .name("."), .name(".."):
                continue
            case .name(let name):
                finalCount += 1
                guard finalCount <= Self.maximumProtectedAudioFinalCount,
                      names.insert(name).inserted else {
                    throw IOSPendingRecordingAudioFileSystemError
                        .namespaceNotEmpty
                }
            case .invalidName:
                throw IOSPendingRecordingAudioFileSystemError.namespaceNotEmpty
            }
        }
        try validatePendingDirectoryPath(directory, control: control)
        return names
    }

    func validateProtectedAudioExpectation(
        _ expectation: ProtectedAudioExpectation,
        in directory: DirectoryHandle,
        control: PendingRecordingOperationControl
    ) throws {
        guard let fileURL = IOSPendingRecordingStorageLocation.audioFileURL(
            forRelativeIdentifier: expectation.relativeIdentifier,
            in: applicationSupportDirectoryURL
        ) else {
            throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        }
        try validatePendingDirectoryPath(directory, control: control)
        let name = fileURL.lastPathComponent
        let pathResult = try call(control: control) {
            adapter.statusAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }
        if case .failure(let errorCode) = pathResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        }
        guard case .success(let pathStatus) = pathResult else {
            if case .failure(ENOENT) = pathResult {
                throw IOSPendingRecordingAudioFileSystemError
                    .protectedAudioMissing
            }
            throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        }
        let openResult = try call(control: control) {
            adapter.openAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
                mode: nil
            )
        }
        if case .failure(let errorCode) = openResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        }
        guard case .success(let descriptor) = openResult else {
            if case .failure(ENOENT) = openResult {
                throw IOSPendingRecordingAudioFileSystemError
                    .protectedAudioMissing
            }
            throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        }
        defer { adapter.closeFile(descriptor) }

        let descriptorStatus = try status(
            descriptor: descriptor,
            control: control,
            failure: .protectedAudioInvalid
        )
        guard isExactOwnedAudioStatus(
            descriptorStatus,
            effectiveUserID: directory.effectiveUserID,
            expectedByteCount: expectation.byteCount
        ), isExactOwnedAudioStatus(
            pathStatus,
            effectiveUserID: directory.effectiveUserID,
            expectedByteCount: expectation.byteCount
        ), FileSnapshot(descriptorStatus) == FileSnapshot(pathStatus) else {
            throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        }
        try validateExactConfiguration(descriptor: descriptor, control: control)
        try requireSuccess(control: control, failure: .protectedAudioInvalid) {
            adapter.lock(
                fileDescriptor: descriptor,
                operation: LOCK_EX | LOCK_NB
            )
        }
        if let expectedDuration = expectation.durationMilliseconds {
            guard let format = IOSPendingRecordingAudioFormat(
                sourceURL: fileURL
            ) else {
                throw IOSPendingRecordingAudioFileSystemError
                    .protectedAudioInvalid
            }
            let duration = try validatedMediaDuration(
                forFileDescriptor: descriptor,
                byteCount: expectation.byteCount,
                format: format
            )
            try validateMediaDuration(
                duration,
                expectedDuration: expectedDuration
            )
        }
        let finalDescriptorStatus = try status(
            descriptor: descriptor,
            control: control,
            failure: .protectedAudioInvalid
        )
        let finalPathResult = try call(control: control) {
            adapter.statusAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }
        if case .failure(let errorCode) = finalPathResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        }
        guard case .success(let finalPathStatus) = finalPathResult,
              FileSnapshot(finalDescriptorStatus)
                == FileSnapshot(descriptorStatus),
              FileSnapshot(finalPathStatus) == FileSnapshot(descriptorStatus)
        else {
            throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        }
        try validateExactConfiguration(descriptor: descriptor, control: control)
        try validatePendingDirectoryPath(directory, control: control)
    }

    func validateHeldProtectedAudioExpectation(
        _ held: HeldProtectedAudioExpectation,
        in directory: DirectoryHandle,
        control: PendingRecordingOperationControl
    ) throws {
        try validateOwnedAudio(
            descriptor: held.descriptor,
            name: held.name,
            directory: directory,
            expectedIdentity: held.identity,
            expectedByteCount: held.expectation.byteCount,
            control: control
        )
        if let expectedDuration = held.expectation.durationMilliseconds {
            guard let fileURL = IOSPendingRecordingStorageLocation.audioFileURL(
                forRelativeIdentifier: held.expectation.relativeIdentifier,
                in: applicationSupportDirectoryURL
            ), let format = IOSPendingRecordingAudioFormat(
                sourceURL: fileURL
            ) else {
                throw IOSPendingRecordingAudioFileSystemError
                    .protectedAudioInvalid
            }
            let duration = try validatedMediaDuration(
                forFileDescriptor: held.descriptor,
                byteCount: held.expectation.byteCount,
                format: format
            )
            try validateMediaDuration(
                duration,
                expectedDuration: expectedDuration
            )
        }
        try validateOwnedAudio(
            descriptor: held.descriptor,
            name: held.name,
            directory: directory,
            expectedIdentity: held.identity,
            expectedByteCount: held.expectation.byteCount,
            control: control
        )
    }

    func publishProtectedCopySynchronously(
        from source: AudioRecordingArtifact,
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat,
        durationMilliseconds: Int64,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        inventory: IOSProtectedAudioNamespaceInventory?,
        control: PendingRecordingOperationControl
    ) throws -> any IOSPendingRecordingPublishedAudioLease {
        guard durationMilliseconds > 0, durationMilliseconds < 300_000,
              canonicalDurationMilliseconds(source.duration) == durationMilliseconds,
              source.byteCount > 0,
              source.byteCount < Self.maximumAudioByteCount,
              source.fileURL.pathExtension == fileExtension(for: format) else {
            throw IOSPendingRecordingAudioFileSystemError.invalidSource
        }

        let inventoryExpectations: [ProtectedAudioExpectation]
        if let inventory {
            inventoryExpectations = try protectedAudioExpectations(
                for: inventory
            )
            try requireInventoryAuthority(inventory, control: control)
        } else {
            inventoryExpectations = []
        }

        let sourceDescriptor = try openValidatedSource(
            source,
            control: control
        )
        defer { adapter.closeFile(sourceDescriptor.descriptor) }

        guard let directory = try openPendingDirectory(
            createIfMissing: true,
            expectedRepositoryRoot: expectedRepositoryRoot,
            control: control
        ) else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
        var directoryIsOwnedByLease = false
        defer {
            if !directoryIsOwnedByLease {
                adapter.closeFile(directory.descriptor)
            }
        }
        if let inventory {
            try validateProtectedAudioNamespace(
                inventoryExpectations,
                in: directory,
                inventory: inventory,
                control: control
            )
        }

        let relativeIdentifier =
            IOSPendingRecordingStorageLocation.relativeAudioIdentifier(
                for: attemptID,
                format: format
            )
        guard let finalURL =
                IOSPendingRecordingStorageLocation.audioFileURL(
                    forRelativeIdentifier: relativeIdentifier,
                    in: applicationSupportDirectoryURL
                ) else {
            throw IOSPendingRecordingAudioFileSystemError.invalidSource
        }
        let finalName = finalURL.lastPathComponent
        let temporaryName = [
            ".recording-staging-v1-",
            UUID().uuidString.lowercased(),
            ".",
            fileExtension(for: format),
        ].joined()
        let temporaryDescriptor = try createExclusiveTemporaryFile(
            named: temporaryName,
            in: directory,
            control: control
        )
        var descriptorIsOwnedByLease = false
        var didPublish = false
        var capturedTemporaryIdentity: FileIdentity?
        defer {
            if !descriptorIsOwnedByLease {
                adapter.closeFile(temporaryDescriptor)
            }
            if !didPublish, let capturedTemporaryIdentity {
                unlinkOwnedTemporaryIfPresent(
                    name: temporaryName,
                    identity: capturedTemporaryIdentity,
                    directoryDescriptor: directory.descriptor,
                    control: control
                )
            }
        }
        let temporaryIdentity = try statusSnapshot(
            descriptor: temporaryDescriptor,
            control: control,
            failure: .writeFailed
        ).identity
        capturedTemporaryIdentity = temporaryIdentity

        try configureTemporaryFile(
            descriptor: temporaryDescriptor,
            name: temporaryName,
            directory: directory,
            expectedIdentity: temporaryIdentity,
            control: control
        )
        try copySource(
            sourceDescriptor: sourceDescriptor.descriptor,
            destinationDescriptor: temporaryDescriptor,
            expectedByteCount: source.byteCount,
            control: control
        )
        try validateSourceUnchanged(
            sourceDescriptor,
            control: control
        )
        try validateOwnedAudio(
            descriptor: temporaryDescriptor,
            name: temporaryName,
            directory: directory,
            expectedIdentity: temporaryIdentity,
            expectedByteCount: source.byteCount,
            control: control
        )
        try synchronize(
            temporaryDescriptor,
            control: control,
            failure: .synchronizationFailed
        )
        try validateOwnedAudio(
            descriptor: temporaryDescriptor,
            name: temporaryName,
            directory: directory,
            expectedIdentity: temporaryIdentity,
            expectedByteCount: source.byteCount,
            control: control
        )

        try control.checkpoint()
        let mediaDuration = try validatedMediaDuration(
            forFileDescriptor: temporaryDescriptor,
            byteCount: source.byteCount,
            format: format
        )
        try validateMediaDuration(
            mediaDuration,
            expectedDuration: durationMilliseconds
        )
        try control.checkpoint()
        try validateOwnedAudio(
            descriptor: temporaryDescriptor,
            name: temporaryName,
            directory: directory,
            expectedIdentity: temporaryIdentity,
            expectedByteCount: source.byteCount,
            control: control
        )
        try requireMissingFinal(
            name: finalName,
            directoryDescriptor: directory.descriptor,
            control: control
        )
        try validateOwnedAudio(
            descriptor: temporaryDescriptor,
            name: temporaryName,
            directory: directory,
            expectedIdentity: temporaryIdentity,
            expectedByteCount: source.byteCount,
            control: control
        )
        if let inventory {
            try requireInventoryAuthority(inventory, control: control)
        }
        try publish(
            temporaryName: temporaryName,
            finalName: finalName,
            directory: directory,
            control: control
        )
        didPublish = true
        try validateOwnedAudio(
            descriptor: temporaryDescriptor,
            name: finalName,
            directory: directory,
            expectedIdentity: temporaryIdentity,
            expectedByteCount: source.byteCount,
            control: control
        )
        try synchronize(
            directory.descriptor,
            control: control,
            failure: .synchronizationFailed
        )
        try validateOwnedAudio(
            descriptor: temporaryDescriptor,
            name: finalName,
            directory: directory,
            expectedIdentity: temporaryIdentity,
            expectedByteCount: source.byteCount,
            control: control
        )
        if let inventory {
            let publishedExpectation = ProtectedAudioExpectation(
                attemptID: attemptID,
                relativeIdentifier: relativeIdentifier,
                durationMilliseconds: durationMilliseconds,
                byteCount: source.byteCount
            )
            try validateProtectedAudioNamespace(
                inventoryExpectations + [publishedExpectation],
                in: directory,
                inventory: inventory,
                control: control,
                heldAudio: [HeldProtectedAudioExpectation(
                    expectation: publishedExpectation,
                    descriptor: temporaryDescriptor,
                    identity: temporaryIdentity,
                    name: finalName
                )]
            )
            try validateOwnedAudio(
                descriptor: temporaryDescriptor,
                name: finalName,
                directory: directory,
                expectedIdentity: temporaryIdentity,
                expectedByteCount: source.byteCount,
                control: control
            )
        }

        descriptorIsOwnedByLease = true
        directoryIsOwnedByLease = true
        return POSIXIOSPendingRecordingPublishedAudioLease(
            fileSystem: self,
            relativeIdentifier: relativeIdentifier,
            fileURL: finalURL,
            directoryDescriptor: directory.descriptor,
            fileDescriptor: temporaryDescriptor,
            identity: temporaryIdentity,
            byteCount: source.byteCount,
            durationMilliseconds: durationMilliseconds
        )
    }

    func openValidatedSource(
        _ source: AudioRecordingArtifact,
        control: PendingRecordingOperationControl
    ) throws -> SourceHandle {
        guard source.fileURL.isFileURL,
              !source.fileURL.path.isEmpty,
              !source.fileURL.path.utf8.contains(0) else {
            throw IOSPendingRecordingAudioFileSystemError.invalidSource
        }
        let pathResult = try call(control: control) {
            adapter.statusAtPath(source.fileURL.path)
        }
        if case .failure(let errorCode) = pathResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(let pathStatus) = pathResult else {
            throw IOSPendingRecordingAudioFileSystemError.sourceUnavailable
        }
        let effectiveUserID = try readEffectiveUserID(control: control)
        try validateSourceStatus(
            pathStatus,
            effectiveUserID: effectiveUserID,
            expectedByteCount: source.byteCount
        )

        let openResult = try call(control: control) {
            adapter.openPath(
                source.fileURL.path,
                flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
                mode: nil
            )
        }
        if case .failure(let errorCode) = openResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(let descriptor) = openResult else {
            throw IOSPendingRecordingAudioFileSystemError.sourceUnavailable
        }
        do {
            let descriptorStatus = try status(
                descriptor: descriptor,
                control: control,
                failure: .sourceUnavailable
            )
            try validateSourceStatus(
                descriptorStatus,
                effectiveUserID: effectiveUserID,
                expectedByteCount: source.byteCount
            )
            let snapshot = FileSnapshot(descriptorStatus)
            guard snapshot == FileSnapshot(pathStatus) else {
                throw IOSPendingRecordingAudioFileSystemError.invalidSource
            }
            return SourceHandle(
                descriptor: descriptor,
                fileURL: source.fileURL,
                snapshot: snapshot
            )
        } catch {
            adapter.closeFile(descriptor)
            throw error
        }
    }

    func openPendingDirectory(
        createIfMissing: Bool,
        expectedRepositoryRoot:
            IOSPersistenceRepositoryRootIdentity? = nil,
        control: PendingRecordingOperationControl
    ) throws -> DirectoryHandle? {
        let requiredRepositoryRoot = try requiredRepositoryRoot(
            operationExpectedRoot: expectedRepositoryRoot
        )
        guard applicationSupportDirectoryURL.isFileURL,
              !applicationSupportDirectoryURL.path.isEmpty,
              !applicationSupportDirectoryURL.path.utf8.contains(0) else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
        let openRoot = try call(control: control) {
            adapter.openPath(
                applicationSupportDirectoryURL.path,
                flags: O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW,
                mode: nil
            )
        }
        if case .failure(let errorCode) = openRoot,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(let applicationSupportDescriptor) = openRoot else {
            if case .failure(ENOENT) = openRoot,
               !createIfMissing,
               requiredRepositoryRoot == nil {
                return nil
            }
            if case .failure(let errorCode) = openRoot,
               requiredRepositoryRoot != nil,
               errorCode == ENOENT
                    || errorCode == ELOOP
                    || errorCode == ENOTDIR {
                onRepositoryIdentityMismatch()
                throw IOSPendingRecordingAudioFileSystemError
                    .repositoryIdentityConflict
            }
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
        var currentDescriptor = applicationSupportDescriptor
        var ownsCurrent = true
        defer {
            if ownsCurrent { adapter.closeFile(currentDescriptor) }
        }
        let effectiveUserID = try readEffectiveUserID(control: control)
        let applicationSupportStatus = try status(
            descriptor: applicationSupportDescriptor,
            control: control,
            failure: .namespaceUnavailable
        )
        guard requiredRepositoryRoot?.matches(applicationSupportStatus)
                ?? true else {
            onRepositoryIdentityMismatch()
            throw IOSPendingRecordingAudioFileSystemError
                .repositoryIdentityConflict
        }

        for component in [
            IOSPendingRecordingStorageLocation.rootDirectoryName,
            IOSPendingRecordingStorageLocation.recordingsDirectoryName,
            IOSPendingRecordingStorageLocation.pendingDirectoryName,
        ] {
            let next = try openChildDirectory(
                named: component,
                in: currentDescriptor,
                createIfMissing: createIfMissing,
                effectiveUserID: effectiveUserID,
                control: control
            )
            guard let next else { return nil }
            adapter.closeFile(currentDescriptor)
            currentDescriptor = next
        }

        let pendingStatus = try status(
            descriptor: currentDescriptor,
            control: control,
            failure: .namespaceUnavailable
        )
        guard pendingStatus.st_mode & S_IFMT == S_IFDIR,
              pendingStatus.st_uid == effectiveUserID,
              pendingStatus.st_mode & mode_t(0o7777) == mode_t(0o700) else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
        ownsCurrent = false
        return DirectoryHandle(
            descriptor: currentDescriptor,
            effectiveUserID: effectiveUserID,
            identity: FileIdentity(pendingStatus)
        )
    }

    func openChildDirectory(
        named name: String,
        in directoryDescriptor: Int32,
        createIfMissing: Bool,
        effectiveUserID: uid_t,
        control: PendingRecordingOperationControl
    ) throws -> Int32? {
        func open() throws -> IOSPendingRecordingPOSIXResult<Int32> {
            try call(control: control) {
                adapter.openAt(
                    directoryDescriptor: directoryDescriptor,
                    name: name,
                    flags: O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW,
                    mode: nil
                )
            }
        }

        var result = try open()
        var createdDirectory = false
        if case .failure(ENOENT) = result, createIfMissing {
            let makeResult = try call(control: control) {
                adapter.makeDirectoryAt(
                    directoryDescriptor: directoryDescriptor,
                    name: name,
                    mode: mode_t(0o700)
                )
            }
            switch makeResult {
            case .success:
                createdDirectory = true
                result = try open()
            case .failure(EEXIST):
                result = try open()
            case .failure(let errorCode)
                where isDataProtectionFailure(errorCode):
                throw IOSPendingRecordingAudioFileSystemError
                    .dataProtectionUnavailable
            case .failure:
                throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
            }
        }
        switch result {
        case .success(let descriptor):
            do {
                let value = try status(
                    descriptor: descriptor,
                    control: control,
                    failure: .namespaceUnavailable
                )
                guard value.st_mode & S_IFMT == S_IFDIR,
                      value.st_uid == effectiveUserID else {
                    throw IOSPendingRecordingAudioFileSystemError
                        .namespaceUnavailable
                }
                if createdDirectory {
                    try requireSuccess(
                        control: control,
                        failure: .namespaceUnavailable
                    ) {
                        adapter.changeMode(
                            fileDescriptor: descriptor,
                            mode: mode_t(0o700)
                        )
                    }
                    let configured = try status(
                        descriptor: descriptor,
                        control: control,
                        failure: .namespaceUnavailable
                    )
                    let pathResult = try call(control: control) {
                        adapter.statusAt(
                            directoryDescriptor: directoryDescriptor,
                            name: name,
                            flags: AT_SYMLINK_NOFOLLOW
                        )
                    }
                    guard case .success(let pathStatus) = pathResult,
                          configured.st_mode & S_IFMT == S_IFDIR,
                          configured.st_uid == effectiveUserID,
                          configured.st_mode & mode_t(0o7777) == mode_t(0o700),
                          FileIdentity(configured) == FileIdentity(pathStatus) else {
                        throw IOSPendingRecordingAudioFileSystemError
                            .namespaceUnavailable
                    }
                    try synchronize(
                        descriptor,
                        control: control,
                        failure: .synchronizationFailed
                    )
                    try synchronize(
                        directoryDescriptor,
                        control: control,
                        failure: .synchronizationFailed
                    )
                }
                return descriptor
            } catch {
                adapter.closeFile(descriptor)
                throw error
            }
        case .failure(ENOENT) where !createIfMissing:
            return nil
        case .failure(let errorCode) where isDataProtectionFailure(errorCode):
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        case .failure:
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
    }

    func requireNoEntries(
        in directory: DirectoryHandle,
        control: PendingRecordingOperationControl
    ) throws {
        try validatePendingDirectoryPath(directory, control: control)
        let duplicateResult = try call(control: control) {
            adapter.openAt(
                directoryDescriptor: directory.descriptor,
                name: ".",
                flags: O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW,
                mode: nil
            )
        }
        if case .failure(let errorCode) = duplicateResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(let duplicateDescriptor) = duplicateResult else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
        var duplicateDescriptorIsOwned = true
        defer {
            if duplicateDescriptorIsOwned {
                adapter.closeFile(duplicateDescriptor)
            }
        }
        let streamResult = try call(control: control) {
            adapter.openDirectoryStream(fileDescriptor: duplicateDescriptor)
        }
        if case .failure(let errorCode) = streamResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(let stream) = streamResult else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
        duplicateDescriptorIsOwned = false
        defer { adapter.closeDirectoryStream(stream) }

        while true {
            let entryResult = try call(control: control) {
                adapter.nextDirectoryEntry(stream: stream)
            }
            if case .failure(let errorCode) = entryResult,
               isDataProtectionFailure(errorCode) {
                throw IOSPendingRecordingAudioFileSystemError
                    .dataProtectionUnavailable
            }
            guard case .success(let entry) = entryResult else {
                throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
            }
            guard let entry else {
                try validatePendingDirectoryPath(directory, control: control)
                return
            }
            switch entry {
            case .name("."), .name(".."):
                continue
            case .name, .invalidName:
                throw IOSPendingRecordingAudioFileSystemError.namespaceNotEmpty
            }
        }
    }

    func createExclusiveTemporaryFile(
        named name: String,
        in directory: DirectoryHandle,
        control: PendingRecordingOperationControl
    ) throws -> Int32 {
        let result = try call(control: control) {
            adapter.openAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode: mode_t(0o600)
            )
        }
        if case .failure(let errorCode) = result,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(let descriptor) = result else {
            throw IOSPendingRecordingAudioFileSystemError.writeFailed
        }
        return descriptor
    }

    func configureTemporaryFile(
        descriptor: Int32,
        name: String,
        directory: DirectoryHandle,
        expectedIdentity: FileIdentity,
        control: PendingRecordingOperationControl
    ) throws {
        try requireSuccess(control: control, failure: .writeFailed) {
            adapter.changeMode(fileDescriptor: descriptor, mode: mode_t(0o600))
        }
        try requireSuccess(control: control, failure: .writeFailed) {
            adapter.lock(fileDescriptor: descriptor, operation: LOCK_EX | LOCK_NB)
        }
        try requireSuccess(control: control, failure: .writeFailed) {
            adapter.setExtendedAttribute(
                fileDescriptor: descriptor,
                name: Self.audioMarkerName,
                value: Self.audioMarkerValue,
                flags: XATTR_CREATE
            )
        }
        try requireSuccess(control: control, failure: .dataProtectionUnavailable) {
            adapter.setProtectionClass(
                fileDescriptor: descriptor,
                protectionClass: Self.completeProtectionClass
            )
        }
        try requireSuccess(control: control, failure: .dataProtectionUnavailable) {
            adapter.setExtendedAttribute(
                fileDescriptor: descriptor,
                name: Self.backupExclusionAttributeName,
                value: Self.backupExclusionAttributeValue,
                flags: XATTR_CREATE
            )
        }
        try validateOwnedAudio(
            descriptor: descriptor,
            name: name,
            directory: directory,
            expectedIdentity: expectedIdentity,
            expectedByteCount: 0,
            control: control
        )
    }

    func copySource(
        sourceDescriptor: Int32,
        destinationDescriptor: Int32,
        expectedByteCount: Int64,
        control: PendingRecordingOperationControl
    ) throws {
        var buffer = [UInt8](repeating: 0, count: Self.maximumTransferByteCount)
        var copiedByteCount: Int64 = 0
        while copiedByteCount < expectedByteCount {
            let remaining = expectedByteCount - copiedByteCount
            let requested = min(buffer.count, Int(remaining))
            let readCount = try buffer.withUnsafeMutableBytes { bytes in
                try transferCount(
                    control: control,
                    failure: .sourceUnavailable
                ) {
                    adapter.read(
                        fileDescriptor: sourceDescriptor,
                        buffer: bytes.baseAddress!,
                        byteCount: requested
                    )
                }
            }
            guard readCount > 0 else {
                throw IOSPendingRecordingAudioFileSystemError.sourceChanged
            }
            guard readCount <= requested else {
                throw IOSPendingRecordingAudioFileSystemError.sourceChanged
            }

            var written = 0
            while written < readCount {
                let writeCount = try buffer.withUnsafeBytes { bytes in
                    try transferCount(
                        control: control,
                        failure: .writeFailed
                    ) {
                        adapter.write(
                            fileDescriptor: destinationDescriptor,
                            buffer: bytes.baseAddress!.advanced(by: written),
                            byteCount: readCount - written
                        )
                    }
                }
                guard writeCount > 0 else {
                    throw IOSPendingRecordingAudioFileSystemError.writeFailed
                }
                guard writeCount <= readCount - written else {
                    throw IOSPendingRecordingAudioFileSystemError.writeFailed
                }
                written += writeCount
            }
            copiedByteCount += Int64(readCount)
        }

        var extraByte: UInt8 = 0
        let extraCount = try withUnsafeMutableBytes(of: &extraByte) { bytes in
            try transferCount(control: control, failure: .sourceChanged) {
                adapter.read(
                    fileDescriptor: sourceDescriptor,
                    buffer: bytes.baseAddress!,
                    byteCount: 1
                )
            }
        }
        guard extraCount == 0 else {
            throw IOSPendingRecordingAudioFileSystemError.sourceChanged
        }
    }

    func validateSourceUnchanged(
        _ source: SourceHandle,
        control: PendingRecordingOperationControl
    ) throws {
        let descriptorStatus = try status(
            descriptor: source.descriptor,
            control: control,
            failure: .sourceChanged
        )
        let pathResult = try call(control: control) {
            adapter.statusAtPath(source.fileURL.path)
        }
        if case .failure(let errorCode) = pathResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(let pathStatus) = pathResult,
              FileSnapshot(descriptorStatus) == source.snapshot,
              FileSnapshot(pathStatus) == source.snapshot else {
            throw IOSPendingRecordingAudioFileSystemError.sourceChanged
        }
    }

    func validateOwnedAudio(
        descriptor: Int32,
        name: String,
        directory: DirectoryHandle,
        expectedIdentity: FileIdentity,
        expectedByteCount: Int64,
        control: PendingRecordingOperationControl
    ) throws {
        try validatePendingDirectoryPath(directory, control: control)
        let descriptorStatus = try status(
            descriptor: descriptor,
            control: control,
            failure: .protectedAudioInvalid
        )
        let pathResult = try call(control: control) {
            adapter.statusAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }
        if case .failure(let errorCode) = pathResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(let pathStatus) = pathResult,
              isExactOwnedAudioStatus(
                descriptorStatus,
                effectiveUserID: directory.effectiveUserID,
                expectedByteCount: expectedByteCount
              ),
              isExactOwnedAudioStatus(
                pathStatus,
                effectiveUserID: directory.effectiveUserID,
                expectedByteCount: expectedByteCount
              ),
              FileIdentity(descriptorStatus) == expectedIdentity,
              FileIdentity(pathStatus) == expectedIdentity else {
            throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        }
        try validateExactConfiguration(descriptor: descriptor, control: control)
    }

    func validateExactConfiguration(
        descriptor: Int32,
        control: PendingRecordingOperationControl
    ) throws {
        let markerResult = try call(control: control) {
            adapter.extendedAttribute(
                fileDescriptor: descriptor,
                name: Self.audioMarkerName,
                maximumByteCount: Self.audioMarkerValue.count + 1
            )
        }
        if case .failure(let errorCode) = markerResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(Self.audioMarkerValue) = markerResult else {
            throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        }
        let protectionResult = try call(control: control) {
            adapter.protectionClass(fileDescriptor: descriptor)
        }
        if case .failure(let errorCode) = protectionResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(Self.completeProtectionClass) = protectionResult else {
            throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        }
        let backupResult = try call(control: control) {
            adapter.extendedAttribute(
                fileDescriptor: descriptor,
                name: Self.backupExclusionAttributeName,
                maximumByteCount: Self.backupExclusionAttributeValue.count + 1
            )
        }
        if case .failure(let errorCode) = backupResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(Self.backupExclusionAttributeValue) = backupResult else {
            throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        }
    }

    func requireMissingFinal(
        name: String,
        directoryDescriptor: Int32,
        control: PendingRecordingOperationControl
    ) throws {
        let result = try call(control: control) {
            adapter.statusAt(
                directoryDescriptor: directoryDescriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }
        if case .failure(let errorCode) = result,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .failure(ENOENT) = result else {
            throw IOSPendingRecordingAudioFileSystemError.destinationConflict
        }
    }

    func publish(
        temporaryName: String,
        finalName: String,
        directory: DirectoryHandle,
        control: PendingRecordingOperationControl
    ) throws {
        try validatePendingDirectoryPath(directory, control: control)
        try requireSuccess(control: control, failure: .destinationConflict) {
            adapter.publishExclusively(
                directoryDescriptor: directory.descriptor,
                temporaryName: temporaryName,
                finalName: finalName
            )
        }
        try validatePendingDirectoryPath(directory, control: control)
    }

    func openValidatedPublishedAudio(
        relativeIdentifier: String,
        attemptID: UUID,
        durationMilliseconds: Int64,
        byteCount: Int64,
        control: PendingRecordingOperationControl
    ) throws -> OpenedPublishedAudio {
        guard durationMilliseconds > 0, durationMilliseconds < 300_000,
              byteCount > 0, byteCount < Self.maximumAudioByteCount,
              let parsedURL = IOSPendingRecordingStorageLocation.audioFileURL(
                forRelativeIdentifier: relativeIdentifier,
                in: applicationSupportDirectoryURL
              ),
              relativeIdentifier == expectedRelativeIdentifier(
                attemptID: attemptID,
                fileExtension: parsedURL.pathExtension
              ) else {
            throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        }
        guard let directory = try openPendingDirectory(
            createIfMissing: false,
            control: control
        ) else {
            throw IOSPendingRecordingAudioFileSystemError.protectedAudioMissing
        }
        var closeDirectory = true
        defer { if closeDirectory { adapter.closeFile(directory.descriptor) } }
        try validatePendingDirectoryPath(directory, control: control)

        let name = parsedURL.lastPathComponent
        let pathResult = try call(control: control) {
            adapter.statusAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }
        if case .failure(let errorCode) = pathResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(let pathStatus) = pathResult else {
            if case .failure(ENOENT) = pathResult {
                throw IOSPendingRecordingAudioFileSystemError.protectedAudioMissing
            }
            throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        }
        let openResult = try call(control: control) {
            adapter.openAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
                mode: nil
            )
        }
        if case .failure(let errorCode) = openResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(let fileDescriptor) = openResult else {
            throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        }
        do {
            let descriptorStatus = try status(
                descriptor: fileDescriptor,
                control: control,
                failure: .protectedAudioInvalid
            )
            guard isExactOwnedAudioStatus(
                descriptorStatus,
                effectiveUserID: directory.effectiveUserID,
                expectedByteCount: byteCount
            ),
            isExactOwnedAudioStatus(
                pathStatus,
                effectiveUserID: directory.effectiveUserID,
                expectedByteCount: byteCount
            ),
            FileSnapshot(descriptorStatus) == FileSnapshot(pathStatus) else {
                throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
            }
            try validateExactConfiguration(descriptor: fileDescriptor, control: control)
            try requireSuccess(control: control, failure: .protectedAudioInvalid) {
                adapter.lock(fileDescriptor: fileDescriptor, operation: LOCK_EX | LOCK_NB)
            }
            try control.checkpoint()
            guard let format = IOSPendingRecordingAudioFormat(
                sourceURL: parsedURL
            ) else {
                throw IOSPendingRecordingAudioFileSystemError
                    .protectedAudioInvalid
            }
            let mediaDuration = try validatedMediaDuration(
                forFileDescriptor: fileDescriptor,
                byteCount: byteCount,
                format: format
            )
            try validateMediaDuration(
                mediaDuration,
                expectedDuration: durationMilliseconds
            )
            try control.checkpoint()
            let finalDescriptorStatus = try status(
                descriptor: fileDescriptor,
                control: control,
                failure: .protectedAudioInvalid
            )
            let finalPathResult = try call(control: control) {
                adapter.statusAt(
                    directoryDescriptor: directory.descriptor,
                    name: name,
                    flags: AT_SYMLINK_NOFOLLOW
                )
            }
            if case .failure(let errorCode) = finalPathResult,
               isDataProtectionFailure(errorCode) {
                throw IOSPendingRecordingAudioFileSystemError
                    .dataProtectionUnavailable
            }
            guard case .success(let finalPathStatus) = finalPathResult,
                  FileSnapshot(finalDescriptorStatus) == FileSnapshot(descriptorStatus),
                  FileSnapshot(finalPathStatus) == FileSnapshot(descriptorStatus) else {
                throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
            }
            try validateExactConfiguration(
                descriptor: fileDescriptor,
                control: control
            )

            closeDirectory = false
            return OpenedPublishedAudio(
                directoryDescriptor: directory.descriptor,
                fileDescriptor: fileDescriptor,
                identity: FileIdentity(descriptorStatus),
                artifact: AudioRecordingArtifact(
                    fileURL: parsedURL,
                    duration: TimeInterval(durationMilliseconds) / 1_000,
                    byteCount: byteCount
                )
            )
        } catch {
            adapter.closeFile(fileDescriptor)
            throw error
        }
    }

    func reconcilePendingAudioRemovalSynchronously(
        using authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization,
        control: PendingRecordingOperationControl
    ) throws -> IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence {
        try requireAcceptedOutputAudioRemovalAuthority(
            authorization,
            control: control
        )
        if retainedAcceptedOutputAudioRemoval != nil {
            return try finishRetainedAcceptedOutputAudioRemoval(
                using: authorization,
                control: control
            )
        }
        if lateAcceptedOutputAudioRemovalEvidence != nil {
            return try reconcileLateAcceptedOutputAudioRemovalEvidence(
                using: authorization,
                control: control
            )
        }

        let expectation = try acceptedOutputAudioExpectation(
            authorization
        )
        guard let directory = try openPendingDirectory(
            createIfMissing: false,
            expectedRepositoryRoot: authorization.expectedRepositoryRoot,
            control: control
        ) else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
        var ownsDirectory = true
        defer {
            if ownsDirectory {
                adapter.closeFile(directory.descriptor)
            }
        }
        try validatePendingDirectoryPath(directory, control: control)
        let name = try acceptedOutputAudioName(expectation)
        let pathResult = try call(control: control) {
            adapter.statusAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }
        if case .failure(let errorCode) = pathResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        }
        if case .failure(ENOENT) = pathResult {
            try proveAcceptedOutputAudioAbsent(
                using: authorization,
                directory: directory,
                control: control
            )
            return IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence(
                authorization: authorization,
                disposition: .alreadyAbsent
            )
        }
        guard case .success = pathResult else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }

        let target: OpenedProtectedAudioCleanupTarget
        do {
            target = try openLockedProtectedAudioCleanupTarget(
                expectation,
                in: directory,
                control: control
            )
        } catch IOSPendingRecordingAudioFileSystemError
            .dataProtectionUnavailable {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        } catch {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        var ownsTarget = true
        defer {
            if ownsTarget {
                adapter.closeFile(target.descriptor)
            }
        }
        try requireAcceptedOutputAudioRemovalAuthority(
            authorization,
            control: control
        )
        let durableIntent = try confirmDurableAudioRemovalIntent(
            authorization,
            target: target,
            control: control
        )
        retainedAcceptedOutputAudioRemoval =
            RetainedAcceptedOutputAudioRemoval(
                authorization: authorization,
                durableIntent: durableIntent,
                directory: directory,
                fileDescriptor: target.descriptor,
                fileIdentity: target.identity,
                targetName: target.name
            )
        ownsDirectory = false
        ownsTarget = false
        try attemptRetainedAcceptedOutputAudioUnlink(control: control)
        return try finishRetainedAcceptedOutputAudioRemoval(
            using: authorization,
            control: control
        )
    }

    func proveAcceptedOutputAudioAbsent(
        using authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization,
        control: PendingRecordingOperationControl
    ) throws {
        try requireAcceptedOutputAudioRemovalAuthority(
            authorization,
            control: control
        )
        guard let fileURL = IOSPendingRecordingStorageLocation.audioFileURL(
            forRelativeIdentifier: authorization.audioRelativeIdentifier,
            in: applicationSupportDirectoryURL
        ), authorization.audioRelativeIdentifier == expectedRelativeIdentifier(
            attemptID: authorization.attemptID,
            fileExtension: fileURL.pathExtension
        ), let directory = try openPendingDirectory(
            createIfMissing: false,
            expectedRepositoryRoot: authorization.expectedRepositoryRoot,
            control: control
        ) else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
        defer { adapter.closeFile(directory.descriptor) }
        _ = fileURL
        try proveAcceptedOutputAudioAbsent(
            using: authorization,
            directory: directory,
            control: control
        )
    }

    func proveAcceptedOutputAudioAbsent(
        using authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization,
        directory: DirectoryHandle,
        control: PendingRecordingOperationControl
    ) throws {
        let expectation = try acceptedOutputAudioExpectation(authorization)
        let name = try acceptedOutputAudioName(expectation)
        try validatePendingDirectoryPath(directory, control: control)
        try requireMissingAfterRemoval(
            name: name,
            directoryDescriptor: directory.descriptor,
            control: control
        )
        try synchronize(
            directory.descriptor,
            control: control,
            failure: .removeFailed
        )
        try requireMissingAfterRemoval(
            name: name,
            directoryDescriptor: directory.descriptor,
            control: control
        )
        try validatePendingDirectoryPath(directory, control: control)
        try requireAcceptedOutputAudioRemovalAuthority(
            authorization,
            control: control
        )
    }

    func requireAcceptedOutputAudioRemovalAuthority(
        _ authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization,
        control: PendingRecordingOperationControl
    ) throws {
        try control.checkpoint()
        guard authorization.operationLeaseAuthorization.provesActiveLease(),
              authorization.recording.attemptID == authorization.attemptID,
              authorization.recording.audioRelativeIdentifier
                == authorization.audioRelativeIdentifier,
              authorization.recording.byteCount == authorization.byteCount,
              authorization.byteCount > 0,
              authorization.byteCount < Self.maximumAudioByteCount else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
    }

    func confirmDurableAudioRemovalIntent(
        _ authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization,
        target: OpenedProtectedAudioCleanupTarget,
        control: PendingRecordingOperationControl
    ) throws -> IOSPendingRecordingAudioRemovalIntent {
        try control.checkpoint()
        let targetStatus = try status(
            descriptor: target.descriptor,
            control: control,
            failure: .removeFailed
        )
        guard FileIdentity(targetStatus) == target.identity,
              targetStatus.st_nlink == 1,
              let intended = IOSPendingRecordingAudioRemovalIntent(
                  purpose: authorization.purpose,
                  recording: authorization.recording,
                  physicalSnapshot:
                    IOSPendingRecordingAudioRemovalPhysicalSnapshot(
                        targetStatus
                    )
              ) else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        let existing = try audioRemovalIntentStore.load(
            expected: authorization.recording,
            expectedRepositoryRoot: authorization.expectedRepositoryRoot
        )
        if let existing {
            guard existing.intent == intended else {
                throw IOSPendingRecordingAudioFileSystemError.removeFailed
            }
        } else {
            guard authorization.mayCreateDurableIntent else {
                throw IOSPendingRecordingAudioFileSystemError.removeFailed
            }
        }
        let confirmed = try audioRemovalIntentStore.commit(
            intended,
            expected: authorization.recording,
            expectedRepositoryRoot: authorization.expectedRepositoryRoot
        )
        guard confirmed.intent == intended else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        try control.checkpoint()
        let finalStatus = try status(
            descriptor: target.descriptor,
            control: control,
            failure: .removeFailed
        )
        guard IOSPendingRecordingAudioRemovalPhysicalSnapshot(finalStatus)
                == intended.physicalSnapshot else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        return intended
    }

    func acceptedOutputAudioExpectation(
        _ authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization
    ) throws -> ProtectedAudioExpectation {
        let expectation = ProtectedAudioExpectation(
            attemptID: authorization.attemptID,
            relativeIdentifier: authorization.audioRelativeIdentifier,
            durationMilliseconds: nil,
            byteCount: authorization.byteCount
        )
        _ = try acceptedOutputAudioName(expectation)
        return expectation
    }

    func acceptedOutputAudioName(
        _ expectation: ProtectedAudioExpectation
    ) throws -> String {
        guard expectation.durationMilliseconds == nil,
              expectation.byteCount > 0,
              expectation.byteCount < Self.maximumAudioByteCount,
              let fileURL = IOSPendingRecordingStorageLocation.audioFileURL(
                  forRelativeIdentifier: expectation.relativeIdentifier,
                  in: applicationSupportDirectoryURL
              ), expectation.relativeIdentifier == expectedRelativeIdentifier(
                  attemptID: expectation.attemptID,
                  fileExtension: fileURL.pathExtension
              ) else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        return fileURL.lastPathComponent
    }

    func finishRetainedAcceptedOutputAudioRemoval(
        using authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization,
        control: PendingRecordingOperationControl
    ) throws -> IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence {
        guard let retained = retainedAcceptedOutputAudioRemoval,
              retained.authorization.provesSameRemovalIntent(
                  as: authorization
              ) else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        try requireAcceptedOutputAudioRemovalAuthority(
            authorization,
            control: control
        )
        try validatePendingDirectoryPath(
            retained.directory,
            control: control
        )
        switch try retainedAcceptedOutputAudioLinkState(
            retained,
            control: control
        ) {
        case .present:
            try attemptRetainedAcceptedOutputAudioUnlink(control: control)
        case .absent:
            break
        }
        let confirmed = try requireRetainedAcceptedOutputAudioRemoval()
        try validateUnlinkedAcceptedOutputAudioRemovalTarget(
            confirmed,
            control: control
        )
        try proveAcceptedOutputAudioAbsent(
            using: authorization,
            directory: confirmed.directory,
            control: control
        )
        try validateUnlinkedAcceptedOutputAudioRemovalTarget(
            confirmed,
            control: control
        )
        let evidence = IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence(
            authorization: authorization,
            disposition: .removed
        )
        retainedAcceptedOutputAudioRemoval = nil
        adapter.closeFile(confirmed.fileDescriptor)
        adapter.closeFile(confirmed.directory.descriptor)
        return evidence
    }

    func reconcileLateAcceptedOutputAudioRemovalEvidence(
        using authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization,
        control: PendingRecordingOperationControl
    ) throws -> IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence {
        guard let lateEvidence = lateAcceptedOutputAudioRemovalEvidence,
              lateEvidence.authorization.provesSameRemovalIntent(
                  as: authorization
              ) else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        try requireAcceptedOutputAudioRemovalAuthority(
            authorization,
            control: control
        )
        try proveAcceptedOutputAudioAbsent(
            using: authorization,
            control: control
        )
        let evidence = IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence(
            authorization: authorization,
            disposition: lateEvidence.disposition
        )
        lateAcceptedOutputAudioRemovalEvidence = nil
        return evidence
    }

    func requireRetainedAcceptedOutputAudioRemoval()
        throws -> RetainedAcceptedOutputAudioRemoval {
        guard let retainedAcceptedOutputAudioRemoval else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        return retainedAcceptedOutputAudioRemoval
    }

    func attemptRetainedAcceptedOutputAudioUnlink(
        control: PendingRecordingOperationControl
    ) throws {
        let retained = try requireRetainedAcceptedOutputAudioRemoval()
        try control.checkpoint()
        try validatePendingDirectoryPath(
            retained.directory,
            control: control
        )
        guard try retainedAcceptedOutputAudioLinkState(
            retained,
            control: control
        ) == .present else {
            return
        }

        // A returned error may follow a committed unlink. Keep the descriptor
        // and never use the generic EINTR retry loop at this mutation boundary.
        let result = adapter.unlinkAt(
            directoryDescriptor: retained.directory.descriptor,
            name: retained.targetName
        )
        switch result {
        case .success:
            return
        case .failure(let errorCode) where isDataProtectionFailure(errorCode):
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        case .failure:
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
    }

    func retainedAcceptedOutputAudioLinkState(
        _ retained: RetainedAcceptedOutputAudioRemoval,
        control: PendingRecordingOperationControl
    ) throws -> RetainedProtectedAudioLinkState {
        let status = try status(
            descriptor: retained.fileDescriptor,
            control: control,
            failure: .removeFailed
        )
        guard status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == retained.directory.effectiveUserID,
              status.st_mode & mode_t(0o7777) == mode_t(0o600),
              status.st_size == off_t(retained.authorization.byteCount),
              FileIdentity(status) == retained.fileIdentity else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        do {
            try validateExactConfiguration(
                descriptor: retained.fileDescriptor,
                control: control
            )
        } catch IOSPendingRecordingAudioFileSystemError
            .dataProtectionUnavailable {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        } catch {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        let pathResult = try call(control: control) {
            adapter.statusAt(
                directoryDescriptor: retained.directory.descriptor,
                name: retained.targetName,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }
        if case .failure(let errorCode) = pathResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        }
        if status.st_nlink == 0, case .failure(ENOENT) = pathResult {
            return .absent
        }
        guard status.st_nlink == 1,
              IOSPendingRecordingAudioRemovalPhysicalSnapshot(status)
                == retained.durableIntent.physicalSnapshot,
              case .success(let pathStatus) = pathResult,
              isExactOwnedAudioStatus(
                  pathStatus,
                  effectiveUserID: retained.directory.effectiveUserID,
                  expectedByteCount: retained.authorization.byteCount
              ), FileSnapshot(pathStatus) == FileSnapshot(status) else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        return .present
    }

    func validateUnlinkedAcceptedOutputAudioRemovalTarget(
        _ retained: RetainedAcceptedOutputAudioRemoval,
        control: PendingRecordingOperationControl
    ) throws {
        let status = try status(
            descriptor: retained.fileDescriptor,
            control: control,
            failure: .removeFailed
        )
        guard status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == retained.directory.effectiveUserID,
              status.st_nlink == 0,
              status.st_mode & mode_t(0o7777) == mode_t(0o600),
              status.st_size == off_t(retained.authorization.byteCount),
              FileIdentity(status) == retained.fileIdentity else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        do {
            try validateExactConfiguration(
                descriptor: retained.fileDescriptor,
                control: control
            )
        } catch IOSPendingRecordingAudioFileSystemError
            .dataProtectionUnavailable {
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        } catch {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
    }

    func removePublishedAudioSynchronously(
        relativeIdentifier: String,
        attemptID: UUID,
        expectedByteCount: Int64,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        control: PendingRecordingOperationControl
    ) throws -> Bool {
        guard expectedByteCount > 0,
              expectedByteCount < Self.maximumAudioByteCount,
              let fileURL = IOSPendingRecordingStorageLocation.audioFileURL(
                forRelativeIdentifier: relativeIdentifier,
                in: applicationSupportDirectoryURL
              ),
              relativeIdentifier == expectedRelativeIdentifier(
                attemptID: attemptID,
                fileExtension: fileURL.pathExtension
              ) else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        guard let directory = try openPendingDirectory(
            createIfMissing: false,
            expectedRepositoryRoot: expectedRepositoryRoot,
            control: control
        ) else {
            return false
        }
        defer { adapter.closeFile(directory.descriptor) }
        try validatePendingDirectoryPath(directory, control: control)
        let name = fileURL.lastPathComponent
        let pathResult = try call(control: control) {
            adapter.statusAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }
        if case .failure(let errorCode) = pathResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(let pathStatus) = pathResult else {
            if case .failure(ENOENT) = pathResult { return false }
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        let openResult = try call(control: control) {
            adapter.openAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
                mode: nil
            )
        }
        if case .failure(let errorCode) = openResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(let descriptor) = openResult else {
            if case .failure(ENOENT) = openResult { return false }
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        defer { adapter.closeFile(descriptor) }
        let descriptorStatus = try status(
            descriptor: descriptor,
            control: control,
            failure: .removeFailed
        )
        guard isExactOwnedAudioStatus(
            descriptorStatus,
            effectiveUserID: directory.effectiveUserID,
            expectedByteCount: expectedByteCount
        ),
        isExactOwnedAudioStatus(
            pathStatus,
            effectiveUserID: directory.effectiveUserID,
            expectedByteCount: expectedByteCount
        ),
        FileSnapshot(descriptorStatus) == FileSnapshot(pathStatus) else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        try validateExactConfiguration(descriptor: descriptor, control: control)
        try requireSuccess(control: control, failure: .removeFailed) {
            adapter.lock(fileDescriptor: descriptor, operation: LOCK_EX | LOCK_NB)
        }
        let finalDescriptorStatus = try status(
            descriptor: descriptor,
            control: control,
            failure: .removeFailed
        )
        let finalPathResult = try call(control: control) {
            adapter.statusAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }
        if case .failure(let errorCode) = finalPathResult,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(let finalPathStatus) = finalPathResult,
              FileSnapshot(finalDescriptorStatus) == FileSnapshot(descriptorStatus),
              FileSnapshot(finalPathStatus) == FileSnapshot(descriptorStatus) else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        do {
            try validateExactConfiguration(descriptor: descriptor, control: control)
        } catch IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        } catch {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        try validatePendingDirectoryPath(directory, control: control)
        try requireSuccess(control: control, failure: .removeFailed) {
            adapter.unlinkAt(directoryDescriptor: directory.descriptor, name: name)
        }
        try validatePendingDirectoryPath(directory, control: control)
        try requireMissingAfterRemoval(
            name: name,
            directoryDescriptor: directory.descriptor,
            control: control
        )
        try synchronize(
            directory.descriptor,
            control: control,
            failure: .removeFailed
        )
        try validatePendingDirectoryPath(directory, control: control)
        try requireMissingAfterRemoval(
            name: name,
            directoryDescriptor: directory.descriptor,
            control: control
        )
        return true
    }

    func revalidateLease(
        relativeIdentifier: String,
        fileURL: URL,
        directoryDescriptor: Int32,
        fileDescriptor: Int32,
        identity: FileIdentity,
        format: IOSPendingRecordingAudioFormat,
        byteCount: Int64,
        durationMilliseconds: Int64,
        onOperationFinished: @escaping @Sendable () -> Void
    ) async throws -> AudioRecordingArtifact {
        try await runQueued(
            deadlineNanoseconds: Self.copyDeadlineNanoseconds,
            onOperationFinished: onOperationFinished
        ) { control in
            guard IOSPendingRecordingStorageLocation.audioFileURL(
                forRelativeIdentifier: relativeIdentifier,
                in: self.applicationSupportDirectoryURL
            ) == fileURL else {
                throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
            }
            let directory = DirectoryHandle(
                descriptor: directoryDescriptor,
                effectiveUserID: try self.readEffectiveUserID(control: control),
                identity: FileIdentity(
                    try self.status(
                        descriptor: directoryDescriptor,
                        control: control,
                        failure: .protectedAudioInvalid
                    )
                )
            )
            try self.validateOwnedAudio(
                descriptor: fileDescriptor,
                name: fileURL.lastPathComponent,
                directory: directory,
                expectedIdentity: identity,
                expectedByteCount: byteCount,
                control: control
            )
            try control.checkpoint()
            let mediaDuration = try self.validatedMediaDuration(
                forFileDescriptor: fileDescriptor,
                byteCount: byteCount,
                format: format
            )
            try self.validateMediaDuration(
                mediaDuration,
                expectedDuration: durationMilliseconds
            )
            try self.validateOwnedAudio(
                descriptor: fileDescriptor,
                name: fileURL.lastPathComponent,
                directory: directory,
                expectedIdentity: identity,
                expectedByteCount: byteCount,
                control: control
            )
            return AudioRecordingArtifact(
                fileURL: fileURL,
                duration: TimeInterval(durationMilliseconds) / 1_000,
                byteCount: byteCount
            )
        }
    }

    func readLease(
        relativeIdentifier: String,
        fileURL: URL,
        directoryDescriptor: Int32,
        fileDescriptor: Int32,
        identity: FileIdentity,
        byteCount: Int64,
        offset: Int64,
        maximumByteCount: Int,
        onOperationFinished: @escaping @Sendable () -> Void
    ) async throws -> Data {
        try await runQueued(
            deadlineNanoseconds: Self.copyDeadlineNanoseconds,
            onOperationFinished: onOperationFinished
        ) { control in
            guard offset >= 0,
                  offset <= byteCount,
                  maximumByteCount > 0,
                  maximumByteCount <= Self.maximumTransferByteCount,
                  IOSPendingRecordingStorageLocation.audioFileURL(
                    forRelativeIdentifier: relativeIdentifier,
                    in: self.applicationSupportDirectoryURL
                  ) == fileURL else {
                throw IOSPendingRecordingAudioFileSystemError
                    .protectedAudioInvalid
            }
            let remainingByteCount = byteCount - offset
            let requestedByteCount = min(
                maximumByteCount,
                Int(remainingByteCount)
            )
            guard requestedByteCount > 0 else { return Data() }

            let directory = DirectoryHandle(
                descriptor: directoryDescriptor,
                effectiveUserID: try self.readEffectiveUserID(control: control),
                identity: FileIdentity(
                    try self.status(
                        descriptor: directoryDescriptor,
                        control: control,
                        failure: .protectedAudioInvalid
                    )
                )
            )
            try self.validateOwnedAudio(
                descriptor: fileDescriptor,
                name: fileURL.lastPathComponent,
                directory: directory,
                expectedIdentity: identity,
                expectedByteCount: byteCount,
                control: control
            )
            var data = Data(count: requestedByteCount)
            let actualByteCount = try data.withUnsafeMutableBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return 0 }
                return try self.transferCount(
                    control: control,
                    failure: .protectedAudioInvalid
                ) {
                    self.adapter.readAt(
                        fileDescriptor: fileDescriptor,
                        buffer: baseAddress,
                        byteCount: requestedByteCount,
                        offset: offset
                    )
                }
            }
            guard actualByteCount > 0,
                  actualByteCount <= requestedByteCount else {
                throw IOSPendingRecordingAudioFileSystemError
                    .protectedAudioInvalid
            }
            if actualByteCount < data.count {
                data.removeSubrange(actualByteCount..<data.count)
            }
            try self.validateOwnedAudio(
                descriptor: fileDescriptor,
                name: fileURL.lastPathComponent,
                directory: directory,
                expectedIdentity: identity,
                expectedByteCount: byteCount,
                control: control
            )
            return data
        }
    }

    func validateMediaDuration(
        _ actualDuration: Int64,
        expectedDuration: Int64
    ) throws {
        let delta = actualDuration.subtractingReportingOverflow(expectedDuration)
        guard actualDuration > 0,
              actualDuration < 300_000,
              !delta.overflow,
              delta.partialValue != Int64.min,
              abs(delta.partialValue) <= Self.maximumDurationDeltaMilliseconds else {
            throw IOSPendingRecordingAudioFileSystemError.mediaValidationFailed
        }
    }

    func validatedMediaDuration(
        forFileDescriptor fileDescriptor: Int32,
        byteCount: Int64,
        format: IOSPendingRecordingAudioFormat
    ) throws -> Int64 {
        do {
            return try mediaValidator.durationMilliseconds(
                forFileDescriptor: fileDescriptor,
                byteCount: byteCount,
                format: format,
                timeoutNanoseconds: Self.mediaValidationDeadlineNanoseconds
            )
        } catch IOSPendingRecordingAudioFileSystemError.mediaValidationTimedOut {
            throw IOSPendingRecordingAudioFileSystemError.mediaValidationTimedOut
        } catch IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        } catch {
            throw IOSPendingRecordingAudioFileSystemError.mediaValidationFailed
        }
    }

    func canonicalDurationMilliseconds(_ duration: TimeInterval) -> Int64? {
        guard duration.isFinite, duration > 0 else { return nil }
        let milliseconds = duration * 1_000
        guard milliseconds.isFinite,
              milliseconds >= Double(Int64.min),
              milliseconds <= Double(Int64.max) else {
            return nil
        }
        return Int64(milliseconds.rounded(.toNearestOrAwayFromZero))
    }

    func expectedRelativeIdentifier(
        attemptID: UUID,
        fileExtension: String
    ) -> String? {
        let format: IOSPendingRecordingAudioFormat
        switch fileExtension {
        case "m4a":
            format = .m4a
        case "wav":
            format = .wav
        default:
            return nil
        }
        return IOSPendingRecordingStorageLocation.relativeAudioIdentifier(
            for: attemptID,
            format: format
        )
    }

    func fileExtension(for format: IOSPendingRecordingAudioFormat) -> String {
        switch format {
        case .m4a: "m4a"
        case .wav: "wav"
        }
    }
}

fileprivate extension FoundationIOSPendingRecordingAudioFileSystem {
    struct SourceHandle {
        let descriptor: Int32
        let fileURL: URL
        let snapshot: FileSnapshot
    }

    struct FileIdentity: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t

        init(_ value: stat) {
            device = value.st_dev
            inode = value.st_ino
        }
    }

    struct FileSnapshot: Equatable, Sendable {
        let identity: FileIdentity
        let byteCount: off_t
        let modificationSeconds: time_t
        let modificationNanoseconds: Int
        let statusChangeSeconds: time_t
        let statusChangeNanoseconds: Int

        init(_ value: stat) {
            identity = FileIdentity(value)
            byteCount = value.st_size
            modificationSeconds = value.st_mtimespec.tv_sec
            modificationNanoseconds = value.st_mtimespec.tv_nsec
            statusChangeSeconds = value.st_ctimespec.tv_sec
            statusChangeNanoseconds = value.st_ctimespec.tv_nsec
        }
    }

    func requiredRepositoryRoot(
        operationExpectedRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPersistenceRepositoryRootIdentity? {
        if let operationExpectedRoot,
           let configuredExpectedRepositoryRoot,
           operationExpectedRoot != configuredExpectedRepositoryRoot {
            onRepositoryIdentityMismatch()
            throw IOSPendingRecordingAudioFileSystemError
                .repositoryIdentityConflict
        }
        return operationExpectedRoot ?? configuredExpectedRepositoryRoot
    }

    func readEffectiveUserID(
        control: PendingRecordingOperationControl
    ) throws -> uid_t {
        let result = try call(control: control) { adapter.effectiveUserID() }
        guard case .success(let value) = result else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
        return value
    }

    func status(
        descriptor: Int32,
        control: PendingRecordingOperationControl,
        failure: IOSPendingRecordingAudioFileSystemError
    ) throws -> stat {
        let result = try call(control: control) {
            adapter.status(of: descriptor)
        }
        switch result {
        case .success(let value):
            return value
        case .failure(let errorCode) where isDataProtectionFailure(errorCode):
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        case .failure:
            throw failure
        }
    }

    func statusSnapshot(
        descriptor: Int32,
        control: PendingRecordingOperationControl,
        failure: IOSPendingRecordingAudioFileSystemError
    ) throws -> FileSnapshot {
        FileSnapshot(
            try status(
                descriptor: descriptor,
                control: control,
                failure: failure
            )
        )
    }

    func validateSourceStatus(
        _ value: stat,
        effectiveUserID: uid_t,
        expectedByteCount: Int64
    ) throws {
        guard value.st_mode & S_IFMT == S_IFREG,
              value.st_uid == effectiveUserID,
              value.st_nlink == 1,
              value.st_size == off_t(expectedByteCount) else {
            throw IOSPendingRecordingAudioFileSystemError.invalidSource
        }
    }

    func isExactOwnedAudioStatus(
        _ value: stat,
        effectiveUserID: uid_t,
        expectedByteCount: Int64
    ) -> Bool {
        value.st_mode & S_IFMT == S_IFREG
            && value.st_uid == effectiveUserID
            && value.st_nlink == 1
            && value.st_mode & mode_t(0o7777) == mode_t(0o600)
            && value.st_size == off_t(expectedByteCount)
    }

    func isDataProtectionFailure(_ errorCode: Int32) -> Bool {
        errorCode == EACCES || errorCode == EPERM
    }

    func validatePendingDirectoryPath(
        _ directory: DirectoryHandle,
        control: PendingRecordingOperationControl
    ) throws {
        let result = try call(control: control) {
            adapter.statusAtPath(
                IOSPendingRecordingStorageLocation.audioDirectoryURL(
                    in: applicationSupportDirectoryURL
                ).path
            )
        }
        if case .failure(let errorCode) = result,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .success(let value) = result,
              value.st_mode & S_IFMT == S_IFDIR,
              value.st_uid == directory.effectiveUserID,
              value.st_mode & mode_t(0o7777) == mode_t(0o700),
              FileIdentity(value) == directory.identity else {
            if configuredExpectedRepositoryRoot != nil {
                onRepositoryIdentityMismatch()
                throw IOSPendingRecordingAudioFileSystemError
                    .repositoryIdentityConflict
            }
            throw IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        }
    }

    func call<Value>(
        control: PendingRecordingOperationControl,
        operation: () -> IOSPendingRecordingPOSIXResult<Value>
    ) throws -> IOSPendingRecordingPOSIXResult<Value> {
        var interruptedRetryCount = 0
        while true {
            try control.checkpoint()
            let result = operation()
            if case .failure(EINTR) = result,
               interruptedRetryCount < Self.maximumInterruptedRetryCount {
                interruptedRetryCount += 1
                continue
            }
            return result
        }
    }

    func transferCount(
        control: PendingRecordingOperationControl,
        failure: IOSPendingRecordingAudioFileSystemError,
        operation: () -> IOSPendingRecordingPOSIXResult<Int>
    ) throws -> Int {
        let result = try call(control: control, operation: operation)
        switch result {
        case .success(let count):
            return count
        case .failure(let errorCode) where isDataProtectionFailure(errorCode):
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        case .failure:
            throw failure
        }
    }

    func requireSuccess(
        control: PendingRecordingOperationControl,
        failure: IOSPendingRecordingAudioFileSystemError,
        operation: () -> IOSPendingRecordingPOSIXResult<Void>
    ) throws {
        let result = try call(control: control, operation: operation)
        switch result {
        case .success:
            return
        case .failure(let errorCode) where isDataProtectionFailure(errorCode):
            throw IOSPendingRecordingAudioFileSystemError
                .dataProtectionUnavailable
        case .failure:
            throw failure
        }
    }

    func synchronize(
        _ descriptor: Int32,
        control: PendingRecordingOperationControl,
        failure: IOSPendingRecordingAudioFileSystemError
    ) throws {
        try requireSuccess(control: control, failure: failure) {
            adapter.synchronize(fileDescriptor: descriptor)
        }
    }

    func unlinkOwnedTemporaryIfPresent(
        name: String,
        identity: FileIdentity,
        directoryDescriptor: Int32,
        control: PendingRecordingOperationControl
    ) {
        guard let statusResult = try? call(control: control, operation: {
            adapter.statusAt(
                directoryDescriptor: directoryDescriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }), case .success(let status) = statusResult,
              FileIdentity(status) == identity else {
            return
        }
        _ = try? call(control: control) {
            adapter.unlinkAt(directoryDescriptor: directoryDescriptor, name: name)
        }
    }

    func requireMissingAfterRemoval(
        name: String,
        directoryDescriptor: Int32,
        control: PendingRecordingOperationControl
    ) throws {
        let result = try call(control: control) {
            adapter.statusAt(
                directoryDescriptor: directoryDescriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }
        if case .failure(let errorCode) = result,
           isDataProtectionFailure(errorCode) {
            throw IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        }
        guard case .failure(ENOENT) = result else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
    }
}

private final class POSIXIOSPendingRecordingPublishedAudioLease:
    IOSPendingRecordingPublishedAudioLease,
    @unchecked Sendable {
    private struct State {
        var directoryDescriptor: Int32?
        var fileDescriptor: Int32?
        var activeOperationCount = 0
        var releaseRequested = false
    }

    let relativeIdentifier: String
    let audioArtifact: AudioRecordingArtifact
    let durationMilliseconds: Int64

    private let fileSystem: FoundationIOSPendingRecordingAudioFileSystem
    private let fileURL: URL
    private let format: IOSPendingRecordingAudioFormat
    private let identity: FoundationIOSPendingRecordingAudioFileSystem.FileIdentity
    private let byteCount: Int64
    private let lock = NSLock()
    private var state: State

    init(
        fileSystem: FoundationIOSPendingRecordingAudioFileSystem,
        relativeIdentifier: String,
        fileURL: URL,
        directoryDescriptor: Int32,
        fileDescriptor: Int32,
        identity: FoundationIOSPendingRecordingAudioFileSystem.FileIdentity,
        byteCount: Int64,
        durationMilliseconds: Int64
    ) {
        self.fileSystem = fileSystem
        self.relativeIdentifier = relativeIdentifier
        self.fileURL = fileURL
        guard let format = IOSPendingRecordingAudioFormat(
            sourceURL: fileURL
        ) else {
            preconditionFailure("A pending audio lease requires a supported format.")
        }
        self.format = format
        self.identity = identity
        self.byteCount = byteCount
        self.durationMilliseconds = durationMilliseconds
        audioArtifact = AudioRecordingArtifact(
            fileURL: fileURL,
            duration: TimeInterval(durationMilliseconds) / 1_000,
            byteCount: byteCount
        )
        state = State(
            directoryDescriptor: directoryDescriptor,
            fileDescriptor: fileDescriptor
        )
    }

    func revalidate() async throws -> AudioRecordingArtifact {
        let descriptors = try beginOperation()
        return try await fileSystem.revalidateLease(
            relativeIdentifier: relativeIdentifier,
            fileURL: fileURL,
            directoryDescriptor: descriptors.0,
            fileDescriptor: descriptors.1,
            identity: identity,
            format: format,
            byteCount: byteCount,
            durationMilliseconds: durationMilliseconds,
            onOperationFinished: { [self] in finishOperation() }
        )
    }

    func read(
        atOffset offset: Int64,
        maximumByteCount: Int
    ) async throws -> Data {
        let descriptors = try beginOperation()
        return try await fileSystem.readLease(
            relativeIdentifier: relativeIdentifier,
            fileURL: fileURL,
            directoryDescriptor: descriptors.0,
            fileDescriptor: descriptors.1,
            identity: identity,
            byteCount: byteCount,
            offset: offset,
            maximumByteCount: maximumByteCount,
            onOperationFinished: { [self] in finishOperation() }
        )
    }

    func beginNamespaceValidation(
        expectedFileSystem: FoundationIOSPendingRecordingAudioFileSystem
    ) throws -> FoundationIOSPendingRecordingAudioFileSystem
        .HeldProtectedAudioLeaseOperation {
        guard fileSystem === expectedFileSystem else {
            throw IOSPendingRecordingAudioFileSystemError
                .protectedAudioInvalid
        }
        let descriptors = try beginOperation()
        return FoundationIOSPendingRecordingAudioFileSystem
            .HeldProtectedAudioLeaseOperation(
                relativeIdentifier: relativeIdentifier,
                fileURL: fileURL,
                fileDescriptor: descriptors.1,
                identity: identity,
                durationMilliseconds: durationMilliseconds,
                byteCount: byteCount,
                finish: { [self] in finishOperation() }
            )
    }

    func release() {
        let descriptors = lock.withLock { () -> (Int32?, Int32?) in
            guard !state.releaseRequested else { return (nil, nil) }
            state.releaseRequested = true
            guard state.activeOperationCount == 0 else {
                return (nil, nil)
            }
            return takeDescriptorsForClose()
        }
        close(descriptors)
    }

    private func beginOperation() throws -> (Int32, Int32) {
        try lock.withLock {
            guard !state.releaseRequested,
                  let directoryDescriptor = state.directoryDescriptor,
                  let fileDescriptor = state.fileDescriptor else {
                throw IOSPendingRecordingAudioFileSystemError
                    .protectedAudioInvalid
            }
            state.activeOperationCount += 1
            return (directoryDescriptor, fileDescriptor)
        }
    }

    private func finishOperation() {
        let descriptors = lock.withLock { () -> (Int32?, Int32?) in
            guard state.activeOperationCount > 0 else {
                assertionFailure("A pending-recording lease operation must be active.")
                return (nil, nil)
            }
            state.activeOperationCount -= 1
            guard state.activeOperationCount == 0,
                  state.releaseRequested else {
                return (nil, nil)
            }
            return takeDescriptorsForClose()
        }
        close(descriptors)
    }

    private func takeDescriptorsForClose() -> (Int32?, Int32?) {
        let descriptors = (state.directoryDescriptor, state.fileDescriptor)
        state.directoryDescriptor = nil
        state.fileDescriptor = nil
        return descriptors
    }

    private func close(_ descriptors: (Int32?, Int32?)) {
        if let fileDescriptor = descriptors.1 {
            fileSystem.adapter.closeFile(fileDescriptor)
        }
        if let directoryDescriptor = descriptors.0 {
            fileSystem.adapter.closeFile(directoryDescriptor)
        }
    }

    deinit {
        release()
    }
}

private final class PendingRecordingOperationControl: @unchecked Sendable {
    private enum TerminalState {
        case active
        case cancelled
        case expired
    }

    private let lock = NSLock()
    private let timeoutNanoseconds: UInt64
    private let startNanoseconds: UInt64
    private let monotonicClock: @Sendable () -> UInt64?
    private var terminalState = TerminalState.active

    init(
        timeoutNanoseconds: UInt64,
        monotonicClock: @escaping @Sendable () -> UInt64?
    ) throws {
        guard let startNanoseconds = monotonicClock() else {
            throw IOSPendingRecordingAudioFileSystemError.operationTimedOut
        }
        self.timeoutNanoseconds = timeoutNanoseconds
        self.startNanoseconds = startNanoseconds
        self.monotonicClock = monotonicClock
    }

    func cancel() {
        lock.withLock {
            if case .active = terminalState {
                terminalState = .cancelled
            }
        }
    }

    func expire() {
        lock.withLock {
            if case .active = terminalState {
                terminalState = .expired
            }
        }
    }

    func checkpoint() throws {
        switch lock.withLock({ terminalState }) {
        case .cancelled:
            throw IOSPendingRecordingAudioFileSystemError.operationCancelled
        case .expired:
            throw IOSPendingRecordingAudioFileSystemError.operationTimedOut
        case .active:
            break
        }
        guard let current = monotonicClock(),
              current >= startNanoseconds,
              current - startNanoseconds < timeoutNanoseconds else {
            throw IOSPendingRecordingAudioFileSystemError.operationTimedOut
        }
    }
}

private final class PendingRecordingOperationCompletion<Value: Sendable>:
    @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var pendingResult: Result<Value, any Error>?
    private var isResolved = false

    func install(_ continuation: CheckedContinuation<Value, any Error>) {
        let result = lock.withLock { () -> Result<Value, any Error>? in
            if let pendingResult {
                self.pendingResult = nil
                return pendingResult
            }
            self.continuation = continuation
            return nil
        }
        if let result {
            continuation.resume(with: result)
        }
    }

    @discardableResult
    func resolve(_ result: Result<Value, any Error>) -> Bool {
        let resolution = lock.withLock {
            () -> (Bool, CheckedContinuation<Value, any Error>?) in
            guard !isResolved else { return (false, nil) }
            isResolved = true
            guard let continuation else {
                pendingResult = result
                return (true, nil)
            }
            self.continuation = nil
            return (true, continuation)
        }
        if let continuation = resolution.1 {
            continuation.resume(with: result)
        }
        return resolution.0
    }
}

private func systemPendingRecordingMonotonicNanoseconds() -> UInt64? {
    var value = timespec()
    guard Darwin.clock_gettime(CLOCK_MONOTONIC, &value) == 0,
          value.tv_sec >= 0,
          value.tv_nsec >= 0 else {
        return nil
    }
    let seconds = UInt64(value.tv_sec).multipliedReportingOverflow(
        by: 1_000_000_000
    )
    guard !seconds.overflow else { return nil }
    let total = seconds.partialValue.addingReportingOverflow(UInt64(value.tv_nsec))
    return total.overflow ? nil : total.partialValue
}
