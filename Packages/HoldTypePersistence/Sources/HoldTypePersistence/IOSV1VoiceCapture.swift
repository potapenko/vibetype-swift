import AudioToolbox
import Darwin
import Foundation
import HoldTypeDomain

enum IOSV1VoiceCaptureError: Error, Equatable, Sendable {
    case captureAlreadyExists
    case namespaceUnavailable
    case sourceConflict
    case sourceChanged
    case invalidLeaseState
    case dataProtectionUnavailable
    case mediaValidationFailed
    case mediaValidationTimedOut
    case cleanupUncertain
}

enum IOSV1VoiceCaptureInvalidReason: Equatable, Sendable {
    case empty
    case tooShort
    case maximumDurationReached
    case invalidMedia
}

enum IOSV1VoiceCaptureFinalizationResult: Sendable {
    case completed(IOSV1VoiceCompletedCapture)
    case discarded(IOSV1VoiceCaptureInvalidReason)
}

struct IOSV1VoiceCaptureFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

struct IOSV1VoiceCaptureFileFacts: Equatable, Sendable {
    let identity: IOSV1VoiceCaptureFileIdentity
    let byteCount: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
}

struct IOSV1VoiceCaptureFileHandle: Sendable {
    let attemptID: UUID
    let directoryDescriptor: Int32
    let fileDescriptor: Int32
    let directoryURL: URL
    let fileName: String
    let directoryIdentity: IOSV1VoiceCaptureFileIdentity
    let identity: IOSV1VoiceCaptureFileIdentity

    var fileURL: URL {
        directoryURL.appendingPathComponent(fileName, isDirectory: false)
    }
}

protocol IOSV1VoiceCaptureFileSystem: Sendable {
    func create(
        attemptID: UUID,
        directoryURL: URL,
        fileName: String
    ) throws -> IOSV1VoiceCaptureFileHandle
    func validate(
        _ handle: IOSV1VoiceCaptureFileHandle
    ) throws -> IOSV1VoiceCaptureFileFacts
    func synchronize(_ handle: IOSV1VoiceCaptureFileHandle) throws
    func remove(_ handle: IOSV1VoiceCaptureFileHandle) throws
    func close(_ handle: IOSV1VoiceCaptureFileHandle)
}

protocol IOSV1VoiceCaptureMediaValidating: Sendable {
    func durationMilliseconds(
        fileDescriptor: Int32,
        byteCount: Int64,
        timeoutNanoseconds: UInt64
    ) throws -> Int64
}

struct IOSV1VoiceCaptureMediaValidator: IOSV1VoiceCaptureMediaValidating {
    private static let queue = DispatchQueue(
        label: "app.holdtype.ios-v1-capture-media",
        qos: .userInitiated,
        attributes: .concurrent
    )

    func durationMilliseconds(
        fileDescriptor: Int32,
        byteCount: Int64,
        timeoutNanoseconds: UInt64
    ) throws -> Int64 {
        let boundedTimeout = min(timeoutNanoseconds, 2_000_000_000)
        let duplicate = Darwin.fcntl(fileDescriptor, F_DUPFD_CLOEXEC, 0)
        guard duplicate >= 0 else { throw mapPOSIX(errno) }
        var status = stat()
        guard Darwin.fstat(duplicate, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_size == off_t(byteCount), byteCount > 0 else {
            Darwin.close(duplicate)
            throw IOSV1VoiceCaptureError.mediaValidationFailed
        }
        let context = IOSV1VoiceCaptureAudioContext(
            fileDescriptor: duplicate,
            byteCount: byteCount
        )
        let result = IOSV1VoiceCaptureValidationResult()
        Self.queue.async {
            let value: Result<Int64, IOSV1VoiceCaptureError>
            do {
                let seconds = try context.durationSeconds()
                let milliseconds = seconds * 1_000
                guard milliseconds.isFinite, milliseconds > 0,
                      milliseconds <= Double(Int64.max) else {
                    throw IOSV1VoiceCaptureError.mediaValidationFailed
                }
                value = .success(
                    Int64(milliseconds.rounded(.toNearestOrAwayFromZero))
                )
            } catch let error as IOSV1VoiceCaptureError {
                value = .failure(
                    context.protectedDataFailure
                        ? .dataProtectionUnavailable : error
                )
            } catch {
                value = .failure(.mediaValidationFailed)
            }
            result.complete(value)
        }
        guard let value = result.wait(timeoutNanoseconds: boundedTimeout) else {
            context.cancel()
            throw IOSV1VoiceCaptureError.mediaValidationTimedOut
        }
        return try value.get()
    }

    private func mapPOSIX(_ code: Int32) -> IOSV1VoiceCaptureError {
        code == EACCES || code == EPERM
            ? .dataProtectionUnavailable : .mediaValidationFailed
    }
}

private final class IOSV1VoiceCaptureValidationResult: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var value: Result<Int64, IOSV1VoiceCaptureError>?

    func complete(_ value: Result<Int64, IOSV1VoiceCaptureError>) {
        let accepted = lock.withLock {
            guard self.value == nil else { return false }
            self.value = value
            return true
        }
        if accepted { semaphore.signal() }
    }

    func wait(timeoutNanoseconds: UInt64)
        -> Result<Int64, IOSV1VoiceCaptureError>? {
        let timeout = DispatchTime.now() + .nanoseconds(Int(timeoutNanoseconds))
        guard semaphore.wait(timeout: timeout) == .success else { return nil }
        return lock.withLock { value }
    }
}

private final class IOSV1VoiceCaptureAudioContext: @unchecked Sendable {
    private let fileDescriptor: Int32
    private let byteCount: Int64
    private let lock = NSLock()
    private var cancelled = false
    private var readError: Int32?

    init(fileDescriptor: Int32, byteCount: Int64) {
        self.fileDescriptor = fileDescriptor
        self.byteCount = byteCount
    }

    var protectedDataFailure: Bool {
        lock.withLock { readError == EACCES || readError == EPERM }
    }

    var size: Int64 { byteCount }

    func cancel() { lock.withLock { cancelled = true } }

    func durationSeconds() throws -> Float64 {
        var audioFile: AudioFileID?
        guard AudioFileOpenWithCallbacks(
            Unmanaged.passUnretained(self).toOpaque(),
            iosV1VoiceCaptureRead,
            nil,
            iosV1VoiceCaptureSize,
            nil,
            kAudioFileM4AType,
            &audioFile
        ) == noErr, let audioFile else {
            throw IOSV1VoiceCaptureError.mediaValidationFailed
        }
        defer { AudioFileClose(audioFile) }
        var type: AudioFileTypeID = 0
        var typeSize = UInt32(MemoryLayout.size(ofValue: type))
        guard AudioFileGetProperty(
            audioFile, kAudioFilePropertyFileFormat, &typeSize, &type
        ) == noErr, type == kAudioFileM4AType else {
            throw IOSV1VoiceCaptureError.mediaValidationFailed
        }
        var extended: ExtAudioFileRef?
        guard ExtAudioFileWrapAudioFileID(audioFile, false, &extended) == noErr,
              let extended else {
            throw IOSV1VoiceCaptureError.mediaValidationFailed
        }
        defer { ExtAudioFileDispose(extended) }
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout.size(ofValue: format))
        var frames: Int64 = 0
        var frameSize = UInt32(MemoryLayout.size(ofValue: frames))
        guard ExtAudioFileGetProperty(
            extended, kExtAudioFileProperty_FileDataFormat,
            &formatSize, &format
        ) == noErr,
        ExtAudioFileGetProperty(
            extended, kExtAudioFileProperty_FileLengthFrames,
            &frameSize, &frames
        ) == noErr,
        format.mChannelsPerFrame > 0, format.mSampleRate.isFinite,
        format.mSampleRate > 0, frames > 0 else {
            throw IOSV1VoiceCaptureError.mediaValidationFailed
        }
        return Float64(frames) / format.mSampleRate
    }

    func read(
        position: Int64,
        count: UInt32,
        buffer: UnsafeMutableRawPointer,
        actual: UnsafeMutablePointer<UInt32>
    ) -> OSStatus {
        actual.pointee = 0
        guard !lock.withLock({ cancelled }), position >= 0,
              position <= byteCount else { return OSStatus(ECANCELED) }
        let length = min(Int64(count), byteCount - position)
        guard length > 0 else { return noErr }
        for retry in 0...8 {
            let value = Darwin.pread(
                fileDescriptor, buffer, Int(length), off_t(position)
            )
            if value >= 0 {
                actual.pointee = UInt32(value)
                return noErr
            }
            let code = errno
            if code == EINTR, retry < 8 { continue }
            lock.withLock { if readError == nil { readError = code } }
            return OSStatus(code)
        }
        return OSStatus(EINTR)
    }

    deinit { Darwin.close(fileDescriptor) }
}

private let iosV1VoiceCaptureRead: AudioFile_ReadProc = {
    data, position, count, buffer, actual in
    Unmanaged<IOSV1VoiceCaptureAudioContext>.fromOpaque(data)
        .takeUnretainedValue().read(
            position: position, count: count, buffer: buffer, actual: actual
        )
}

private let iosV1VoiceCaptureSize: AudioFile_GetSizeProc = { data in
    Unmanaged<IOSV1VoiceCaptureAudioContext>.fromOpaque(data)
        .takeUnretainedValue().size
}

actor IOSV1VoiceCaptureOwner {
    static let mediaValidationTimeoutNanoseconds: UInt64 = 2_000_000_000
    static let maximumAudioByteCount: Int64 = 25_000_000

    private let repository: IOSVoiceStateRepository
    private let directoryURL: URL
    private let fileSystem: any IOSV1VoiceCaptureFileSystem
    private let mediaValidator: any IOSV1VoiceCaptureMediaValidating
    private weak var liveLease: IOSV1VoiceCaptureLease?

    init(
        repository: IOSVoiceStateRepository,
        directoryURL: URL,
        fileSystem: any IOSV1VoiceCaptureFileSystem,
        mediaValidator: any IOSV1VoiceCaptureMediaValidating
    ) {
        self.repository = repository
        self.directoryURL = directoryURL
        self.fileSystem = fileSystem
        self.mediaValidator = mediaValidator
    }

    func createCapture(
        attemptID: UUID,
        outputIntent: DictationOutputIntent,
        draftInsertionMode: IOSVoiceDraftInsertionMode = .replace,
        forcesTextCorrection: Bool = false,
        recordingDurationLimit: RecordingDurationLimit = .default,
        createdAt: Date = Date()
    ) async throws -> IOSV1VoiceCaptureLease {
        if let liveLease, liveLease.isOpen {
            throw IOSV1VoiceCaptureError.captureAlreadyExists
        }
        let relativeIdentifier = IOSVoiceStateStorageLocation
            .relativeAudioIdentifier(for: attemptID)
        let fileName = IOSVoiceStateStorageLocation.audioFileURL(
            for: attemptID,
            in: directoryURL.deletingLastPathComponent()
                .deletingLastPathComponent()
        ).lastPathComponent
        let handle = try fileSystem.create(
            attemptID: attemptID,
            directoryURL: directoryURL,
            fileName: fileName
        )
        do {
            let record = try IOSVoiceStateCapture(
                attemptID: attemptID,
                audioRelativeIdentifier: relativeIdentifier,
                createdAt: createdAt,
                outputIntent: outputIntent,
                draftInsertionMode: draftInsertionMode,
                forcesTextCorrection: forcesTextCorrection,
                recordingDurationLimit: recordingDurationLimit,
                phase: .recording
            )
            _ = try await repository.installCapture(record)
        } catch {
            do {
                try fileSystem.remove(handle)
            } catch {
                fileSystem.close(handle)
                throw IOSV1VoiceCaptureError.cleanupUncertain
            }
            fileSystem.close(handle)
            throw error
        }
        let lease = IOSV1VoiceCaptureLease(
            repository: repository,
            handle: handle,
            fileSystem: fileSystem,
            mediaValidator: mediaValidator,
            recordingDurationLimit: recordingDurationLimit
        )
        liveLease = lease
        return lease
    }
}

final class IOSV1VoiceCaptureLease: @unchecked Sendable {
    private enum Phase { case recording, finalizing, completed, discarding }
    private struct State {
        var phase = Phase.recording
        var operationInFlight = false
        var releaseRequested = false
        var closed = false
    }

    private let lock = NSLock()
    private let repository: IOSVoiceStateRepository
    private let handle: IOSV1VoiceCaptureFileHandle
    private let fileSystem: any IOSV1VoiceCaptureFileSystem
    private let mediaValidator: any IOSV1VoiceCaptureMediaValidating
    private let recordingDurationLimit: RecordingDurationLimit
    private var state = State()

    init(
        repository: IOSVoiceStateRepository,
        handle: IOSV1VoiceCaptureFileHandle,
        fileSystem: any IOSV1VoiceCaptureFileSystem,
        mediaValidator: any IOSV1VoiceCaptureMediaValidating,
        recordingDurationLimit: RecordingDurationLimit = .default
    ) {
        self.repository = repository
        self.handle = handle
        self.fileSystem = fileSystem
        self.mediaValidator = mediaValidator
        self.recordingDurationLimit = recordingDurationLimit
    }

    var isOpen: Bool {
        lock.withLock { !state.closed && !state.releaseRequested }
    }

    func withTransientRecordingURL(_ body: (URL) throws -> Void) throws {
        try begin(allowed: [.recording])
        defer { finish() }
        _ = try fileSystem.validate(handle)
        try body(handle.fileURL)
    }

    func revalidateRecorderCheckpoint() throws {
        try begin(allowed: [.recording])
        defer { finish() }
        _ = try fileSystem.validate(handle)
    }

    func beginFinalizing() async throws {
        try begin(allowed: [.recording])
        do {
            _ = try await repository.transitionCapture(
                attemptID: handle.attemptID,
                to: .finalizing
            )
            finish(phase: .finalizing)
        } catch {
            finish()
            throw error
        }
    }

    func completeAfterRecorderClose(
        fallbackDurationMilliseconds: Int64? = nil
    ) async throws
        -> IOSV1VoiceCaptureFinalizationResult {
        try begin(allowed: [.finalizing])
        do {
            try fileSystem.synchronize(handle)
            let before = try fileSystem.validate(handle)
            guard before.byteCount > 0 else {
                return try await discardInvalid(.empty)
            }
            guard before.byteCount
                    < IOSV1VoiceCaptureOwner.maximumAudioByteCount else {
                // A bounded reader cannot safely admit this source, but byte
                // count alone is never authority to destroy the only capture.
                // Leave finalizing ownership intact for explicit Discard.
                finish()
                throw IOSV1VoiceCaptureError.mediaValidationFailed
            }
            let maximumDuration = recordingDurationLimit
                .maximumFinalizedMediaDurationMilliseconds
            let monotonicFallback = fallbackDurationMilliseconds
                .flatMap { $0 >= 300 ? min($0, maximumDuration) : nil } ?? 0
            let duration: Int64
            do {
                let measured = try mediaValidator.durationMilliseconds(
                    fileDescriptor: handle.fileDescriptor,
                    byteCount: before.byteCount,
                    timeoutNanoseconds:
                        IOSV1VoiceCaptureOwner.mediaValidationTimeoutNanoseconds
                )
                // Zero is the durable unknown/suspect marker. A bogus short
                // probe must not destroy a non-empty finalized recording.
                duration = measured >= 300 && measured <= maximumDuration
                    ? measured : monotonicFallback
            } catch IOSV1VoiceCaptureError.mediaValidationFailed {
                duration = monotonicFallback
            } catch IOSV1VoiceCaptureError.mediaValidationTimedOut {
                duration = monotonicFallback
            } catch {
                finish()
                throw error
            }
            let after = try fileSystem.validate(handle)
            guard before == after else {
                finish()
                throw IOSV1VoiceCaptureError.sourceChanged
            }
            // The recorder requests its stop at the configured limit, but a
            // delayed callback can make the monotonic fallback larger. Clamp that
            // fallback to the finalized-media tolerance. An abnormal media
            // probe without a trustworthy fallback becomes duration 0, so the
            // source remains recoverable instead of being deleted here.
            _ = try await repository.completeCapture(
                attemptID: handle.attemptID,
                durationMilliseconds: duration,
                byteCount: after.byteCount
            )
            finish(phase: .completed)
            return .completed(
                IOSV1VoiceCompletedCapture(
                    repository: repository,
                    lease: self,
                    attemptID: handle.attemptID,
                    recordingDurationLimit: recordingDurationLimit,
                    durationMilliseconds: duration,
                    byteCount: after.byteCount
                )
            )
        } catch {
            if lock.withLock({ state.operationInFlight }) { finish() }
            throw error
        }
    }

    func beginDiscardingBeforeRecorderStop() async throws {
        try begin(allowed: [.recording, .finalizing, .completed])
        do {
            _ = try await repository.transitionCapture(
                attemptID: handle.attemptID,
                to: .discarding
            )
            finish(phase: .discarding)
        } catch {
            finish()
            throw error
        }
    }

    func finishDiscardAfterRecorderStop() async throws {
        try begin(allowed: [.discarding])
        do {
            try fileSystem.remove(handle)
            _ = try await repository.clearCapture(attemptID: handle.attemptID)
            finish(release: true)
        } catch {
            finish()
            throw error
        }
    }

    func release() {
        let shouldClose = lock.withLock {
            state.releaseRequested = true
            guard !state.operationInFlight, !state.closed else { return false }
            state.closed = true
            return true
        }
        if shouldClose { fileSystem.close(handle) }
    }

    private func discardInvalid(
        _ reason: IOSV1VoiceCaptureInvalidReason
    ) async throws -> IOSV1VoiceCaptureFinalizationResult {
        _ = try await repository.transitionCapture(
            attemptID: handle.attemptID,
            to: .discarding
        )
        try fileSystem.remove(handle)
        _ = try await repository.clearCapture(attemptID: handle.attemptID)
        finish(phase: .discarding, release: true)
        return .discarded(reason)
    }

    private func begin(allowed: Set<Phase>) throws {
        try lock.withLock {
            guard !state.closed, !state.releaseRequested,
                  !state.operationInFlight, allowed.contains(state.phase) else {
                throw IOSV1VoiceCaptureError.invalidLeaseState
            }
            state.operationInFlight = true
        }
    }

    private func finish(
        phase: Phase? = nil,
        release: Bool = false
    ) {
        let shouldClose = lock.withLock {
            if let phase { state.phase = phase }
            state.operationInFlight = false
            state.releaseRequested = state.releaseRequested || release
            guard state.releaseRequested, !state.closed else { return false }
            state.closed = true
            return true
        }
        if shouldClose { fileSystem.close(handle) }
    }

    deinit { release() }
}

final class IOSV1VoiceCompletedCapture: @unchecked Sendable {
    let attemptID: UUID
    let recordingDurationLimit: RecordingDurationLimit
    let durationMilliseconds: Int64
    let byteCount: Int64
    private let repository: IOSVoiceStateRepository
    private let lease: IOSV1VoiceCaptureLease

    fileprivate init(
        repository: IOSVoiceStateRepository,
        lease: IOSV1VoiceCaptureLease,
        attemptID: UUID,
        recordingDurationLimit: RecordingDurationLimit,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) {
        self.repository = repository
        self.lease = lease
        self.attemptID = attemptID
        self.recordingDurationLimit = recordingDurationLimit
        self.durationMilliseconds = durationMilliseconds
        self.byteCount = byteCount
    }

    func promote(
        transcriptionConfiguration: TranscriptionConfiguration,
        acceptedAudioRetention: IOSAcceptedAudioRetention =
            .recordingCachePolicy,
        initialStatus: IOSVoiceStatePendingStatus = .ready
    ) async throws -> IOSVoiceStatePending {
        let pending = try await repository.promoteCapture(
            attemptID: attemptID,
            transcriptionConfiguration: transcriptionConfiguration,
            acceptedAudioRetention: acceptedAudioRetention,
            initialStatus: initialStatus
        )
        lease.release()
        return pending
    }

    func release() { lease.release() }
    deinit { release() }
}

struct IOSV1VoiceCaptureDarwinFileSystem: IOSV1VoiceCaptureFileSystem {
    func create(
        attemptID: UUID,
        directoryURL: URL,
        fileName: String
    ) throws -> IOSV1VoiceCaptureFileHandle {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [
                .posixPermissions: NSNumber(value: Int16(0o700)),
                .protectionKey: FileProtectionType.complete,
            ]
        )
        var directoryResourceValues = URLResourceValues()
        directoryResourceValues.isExcludedFromBackup = true
        var protectedDirectoryURL = directoryURL
        try protectedDirectoryURL.setResourceValues(directoryResourceValues)
        let directory = Darwin.open(
            directoryURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard directory >= 0 else {
            throw IOSV1VoiceCaptureError.namespaceUnavailable
        }
        let file = fileName.withCString {
            Darwin.openat(
                directory,
                $0,
                O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
        }
        guard file >= 0 else {
            Darwin.close(directory)
            throw IOSV1VoiceCaptureError.sourceConflict
        }
        do {
            guard flock(file, LOCK_EX | LOCK_NB) == 0,
                  Darwin.fchmod(file, mode_t(0o600)) == 0 else {
                throw IOSV1VoiceCaptureError.sourceConflict
            }
            var fileURL = directoryURL.appendingPathComponent(fileName)
            try FileManager.default.setAttributes(
                [
                    .posixPermissions: NSNumber(value: Int16(0o600)),
                    .protectionKey: FileProtectionType.complete,
                ],
                ofItemAtPath: fileURL.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try fileURL.setResourceValues(values)
            guard Darwin.fsync(file) == 0, Darwin.fsync(directory) == 0 else {
                throw IOSV1VoiceCaptureError.dataProtectionUnavailable
            }
            let directoryIdentity = try identity(directory, type: S_IFDIR)
            let identity = try identity(file, type: S_IFREG)
            let handle = IOSV1VoiceCaptureFileHandle(
                attemptID: attemptID,
                directoryDescriptor: directory,
                fileDescriptor: file,
                directoryURL: directoryURL,
                fileName: fileName,
                directoryIdentity: directoryIdentity,
                identity: identity
            )
            _ = try validate(handle)
            return handle
        } catch {
            Darwin.close(file)
            Darwin.close(directory)
            throw error
        }
    }

    func validate(
        _ handle: IOSV1VoiceCaptureFileHandle
    ) throws -> IOSV1VoiceCaptureFileFacts {
        var directoryStatus = stat()
        var directoryPathStatus = stat()
        var descriptorStatus = stat()
        var pathStatus = stat()
        guard Darwin.fstat(handle.directoryDescriptor, &directoryStatus) == 0,
              Darwin.lstat(handle.directoryURL.path, &directoryPathStatus) == 0,
              directoryStatus.st_mode & S_IFMT == S_IFDIR,
              directoryStatus.st_dev == directoryPathStatus.st_dev,
              directoryStatus.st_ino == directoryPathStatus.st_ino,
              IOSV1VoiceCaptureFileIdentity(
                  device: UInt64(directoryStatus.st_dev),
                  inode: UInt64(directoryStatus.st_ino)
              ) == handle.directoryIdentity,
              Darwin.fstat(handle.fileDescriptor, &descriptorStatus) == 0,
              handle.fileName.withCString({
                  Darwin.fstatat(
                      handle.directoryDescriptor,
                      $0,
                      &pathStatus,
                      AT_SYMLINK_NOFOLLOW
                  )
              }) == 0,
              descriptorStatus.st_mode & S_IFMT == S_IFREG,
              descriptorStatus.st_mode & mode_t(0o777) == mode_t(0o600),
              descriptorStatus.st_nlink == 1,
              descriptorStatus.st_dev == pathStatus.st_dev,
              descriptorStatus.st_ino == pathStatus.st_ino,
              IOSV1VoiceCaptureFileIdentity(
                  device: UInt64(descriptorStatus.st_dev),
                  inode: UInt64(descriptorStatus.st_ino)
              ) == handle.identity else {
            throw IOSV1VoiceCaptureError.sourceChanged
        }
        return IOSV1VoiceCaptureFileFacts(
            identity: handle.identity,
            byteCount: Int64(descriptorStatus.st_size),
            modificationSeconds: Int64(descriptorStatus.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(descriptorStatus.st_mtimespec.tv_nsec)
        )
    }

    func synchronize(_ handle: IOSV1VoiceCaptureFileHandle) throws {
        guard Darwin.fsync(handle.fileDescriptor) == 0 else {
            throw IOSV1VoiceCaptureError.sourceChanged
        }
    }

    func remove(_ handle: IOSV1VoiceCaptureFileHandle) throws {
        var before = stat()
        guard Darwin.fstat(handle.fileDescriptor, &before) == 0 else {
            throw IOSV1VoiceCaptureError.cleanupUncertain
        }
        if before.st_nlink == 0 {
            guard Darwin.fsync(handle.directoryDescriptor) == 0 else {
                throw IOSV1VoiceCaptureError.cleanupUncertain
            }
            return
        }
        _ = try validate(handle)
        let result = handle.fileName.withCString {
            Darwin.unlinkat(handle.directoryDescriptor, $0, 0)
        }
        guard result == 0 else {
            throw IOSV1VoiceCaptureError.cleanupUncertain
        }
        var status = stat()
        guard Darwin.fstat(handle.fileDescriptor, &status) == 0,
              status.st_nlink == 0,
              Darwin.fsync(handle.directoryDescriptor) == 0 else {
            throw IOSV1VoiceCaptureError.cleanupUncertain
        }
    }

    func close(_ handle: IOSV1VoiceCaptureFileHandle) {
        Darwin.close(handle.fileDescriptor)
        Darwin.close(handle.directoryDescriptor)
    }

    private func identity(_ descriptor: Int32, type: mode_t) throws
        -> IOSV1VoiceCaptureFileIdentity {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == type else {
            throw IOSV1VoiceCaptureError.sourceChanged
        }
        return IOSV1VoiceCaptureFileIdentity(
            device: UInt64(status.st_dev),
            inode: UInt64(status.st_ino)
        )
    }
}

extension IOSV1VoiceCaptureError: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSV1VoiceCaptureError(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
