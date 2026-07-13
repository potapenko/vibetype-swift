import Darwin
import Foundation
import HoldTypeDomain

@_spi(HoldTypeIOSCore)
public enum IOSV1PendingRecordingPhase: Equatable, Sendable {
    case readyForTranscription
    case failed
    case transcribing
    case postProcessing
    case outputDelivery
    case acceptedCleanup
}

@_spi(HoldTypeIOSCore)
public enum IOSV1PendingRecordingAvailability: Equatable, Sendable {
    case available
    case temporarilyUnavailable
    case missing
    case invalid
}

@_spi(HoldTypeIOSCore)
public struct IOSV1PendingRecording: Equatable, Sendable {
    public let attemptID: UUID
    public let audioRelativeIdentifier: String
    public let createdAt: Date
    public let updatedAt: Date
    public let phase: IOSV1PendingRecordingPhase
    public let outputIntent: DictationOutputIntent
    public let transcriptionID: UUID?
    public let transcriptionModel: String
    public let transcriptionLanguageCode: String?
    public let durationMilliseconds: Int64
    public let byteCount: Int64

    let state: IOSVoiceStatePending

    init(_ state: IOSVoiceStatePending) {
        self.state = state
        attemptID = state.attemptID
        audioRelativeIdentifier = state.audioRelativeIdentifier
        createdAt = state.createdAt
        updatedAt = state.updatedAt
        outputIntent = state.outputIntent
        transcriptionModel = state.transcriptionModel
        transcriptionLanguageCode = state.transcriptionLanguageCode
        durationMilliseconds = state.durationMilliseconds
        byteCount = state.byteCount
        switch state.status {
        case .ready:
            phase = .readyForTranscription
            transcriptionID = nil
        case .failed:
            phase = .failed
            transcriptionID = nil
        case .processing(let stage, let operationID):
            transcriptionID = operationID
            switch stage {
            case .transcription: phase = .transcribing
            case .postProcessing: phase = .postProcessing
            case .outputDelivery: phase = .outputDelivery
            }
        case .acceptedCleanup:
            phase = .acceptedCleanup
            transcriptionID = nil
        }
    }
}

@_spi(HoldTypeIOSCore)
public struct IOSV1PendingRecordingExpectation: Equatable, Sendable {
    public let attemptID: UUID
    public let phase: IOSV1PendingRecordingPhase
    public let transcriptionID: UUID?

    let recording: IOSV1PendingRecording

    public init(recording: IOSV1PendingRecording) {
        self.recording = recording
        attemptID = recording.attemptID
        phase = recording.phase
        transcriptionID = recording.transcriptionID
    }
}

@_spi(HoldTypeIOSCore)
public struct IOSV1PendingRecordingObservation: Equatable, Sendable {
    public let recording: IOSV1PendingRecording
    public let availability: IOSV1PendingRecordingAvailability

    public var expectation: IOSV1PendingRecordingExpectation {
        IOSV1PendingRecordingExpectation(recording: recording)
    }
}

@_spi(HoldTypeIOSCore)
public enum IOSV1PendingRecordingDiscardResult: Equatable, Sendable {
    case discarded
    case alreadyAbsent
}

@_spi(HoldTypeIOSCore)
public enum IOSV1PendingRecordingAudioFormat: Equatable, Sendable {
    case m4a
    case wav
}

@_spi(HoldTypeIOSCore)
public enum IOSV1ForegroundVoicePersistenceError:
    Error,
    Equatable,
    Sendable {
    case stalePending
    case invalidTransition
    case invalidAcceptedOutput
    case audioMissing
    case audioTemporarilyUnavailable
    case audioInvalid
    case cleanupUncertain
    case dispatchAlreadyExecuted
    case invalidAudioRead
    case localPersistence
}

@_spi(HoldTypeIOSCore)
public struct IOSV1ForegroundVoiceAcceptedOutputPreparation:
    Equatable,
    Sendable {
    public let deliveryID: UUID
    public let sessionID: UUID
    public let attemptID: UUID
    public let transcriptID: UUID
    public let acceptedText: String
    public let outputIntent: DictationOutputIntent

    public init(
        deliveryID: UUID,
        sessionID: UUID,
        attemptID: UUID,
        transcriptID: UUID,
        rawAcceptedText: String,
        outputIntent: DictationOutputIntent
    ) throws {
        guard !rawAcceptedText.isEmpty,
              rawAcceptedText.utf8.count <= 1_000_000,
              rawAcceptedText == rawAcceptedText.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ) else {
            throw IOSV1ForegroundVoicePersistenceError.invalidAcceptedOutput
        }
        self.deliveryID = deliveryID
        self.sessionID = sessionID
        self.attemptID = attemptID
        self.transcriptID = transcriptID
        acceptedText = rawAcceptedText
        self.outputIntent = outputIntent
    }
}

@_spi(HoldTypeIOSCore)
public struct IOSV1AcceptedOutputDeliveryRecord: Equatable, Sendable {
    public let resultID: UUID
    public let sourceAttemptID: UUID
    public let acceptedText: String
    public let createdAt: Date

    public var deliveryID: UUID { resultID }
    public var attemptID: UUID { sourceAttemptID }

    public init(
        resultID: UUID,
        sourceAttemptID: UUID,
        acceptedText: String,
        createdAt: Date
    ) throws {
        guard !acceptedText.isEmpty,
              acceptedText.utf8.count <= 1_000_000,
              acceptedText == acceptedText.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ) else {
            throw IOSV1ForegroundVoicePersistenceError.invalidAcceptedOutput
        }
        self.resultID = resultID
        self.sourceAttemptID = sourceAttemptID
        self.acceptedText = acceptedText
        self.createdAt = createdAt
    }

    init(_ latest: IOSVoiceStateLatest) {
        resultID = latest.resultID
        sourceAttemptID = latest.sourceAttemptID
        acceptedText = latest.text
        createdAt = latest.createdAt
    }

    init(_ accepted: IOSVoiceStateAcceptedResult) {
        resultID = accepted.resultID
        sourceAttemptID = accepted.sourceAttemptID
        acceptedText = accepted.text
        createdAt = accepted.createdAt
    }
}

@_spi(HoldTypeIOSCore)
public struct IOSV1AcceptedOutputDeliveryExpectation: Equatable, Sendable {
    public let resultID: UUID
    public let sourceAttemptID: UUID

    public init(record: IOSV1AcceptedOutputDeliveryRecord) {
        resultID = record.resultID
        sourceAttemptID = record.sourceAttemptID
    }
}

@_spi(HoldTypeIOSCore)
public enum IOSV1ForegroundVoiceAcceptanceNotice: Equatable, Sendable {
    case historyWriteFailed
    case localCleanupPending
    case historyWriteFailedAndLocalCleanupPending
}

@_spi(HoldTypeIOSCore)
public enum IOSV1ForegroundVoiceAcceptanceResult: Equatable, Sendable {
    case resultReady(
        IOSV1AcceptedOutputDeliveryRecord,
        notice: IOSV1ForegroundVoiceAcceptanceNotice? = nil
    )
}

@_spi(HoldTypeIOSCore)
public enum IOSV1ForegroundVoiceLatestResultObservation: Equatable, Sendable {
    case absent
    case resultReady(IOSV1AcceptedOutputDeliveryRecord)
}

@_spi(HoldTypeIOSCore)
public enum IOSV1ForegroundVoiceClearResult: Equatable, Sendable {
    case cleared
    case alreadyAbsent
}

@_spi(HoldTypeIOSCore)
public enum IOSV1ContainingAppRecoveryOpportunity: Equatable, Sendable {
    case processLaunch
    case foregroundOpportunity
}

@_spi(HoldTypeIOSCore)
public enum IOSV1ContainingAppRecoveryDisposition: Equatable, Sendable {
    case complete
    case pendingLocalRecovery
}

@_spi(HoldTypeIOSCore)
public enum IOSV1ForegroundVoiceCaptureInvalidReason: Equatable, Sendable {
    case tooShort
    case empty
    case maximumDurationReached
    case invalidMedia
}

@_spi(HoldTypeIOSCore)
public enum IOSV1ForegroundVoiceCaptureFinalizationResult: Sendable {
    case completed(IOSV1ForegroundVoiceCompletedCapture)
    case discarded(IOSV1ForegroundVoiceCaptureInvalidReason)
}

@_spi(HoldTypeIOSCore)
public enum IOSV1ForegroundVoiceCaptureRecoveryObservation:
    Equatable,
    Sendable {
    case empty
    case recoverable(attemptID: UUID)
    case discardOnly(attemptID: UUID)
    case blocked
}

@_spi(HoldTypeIOSCore)
public final class IOSV1ForegroundVoiceCaptureLease: @unchecked Sendable {
    private let ownerID: UUID
    private let lease: IOSV1VoiceCaptureLease

    init(ownerID: UUID, lease: IOSV1VoiceCaptureLease) {
        self.ownerID = ownerID
        self.lease = lease
    }

    public func withTransientRecordingURL(
        _ body: (URL) throws -> Void
    ) throws {
        try lease.withTransientRecordingURL(body)
    }

    public func revalidateRecorderCheckpoint() throws {
        try lease.revalidateRecorderCheckpoint()
    }

    public func beginFinalizing() async throws {
        try await lease.beginFinalizing()
    }

    public func completeAfterRecorderClose() async throws
        -> IOSV1ForegroundVoiceCaptureFinalizationResult {
        switch try await lease.completeAfterRecorderClose() {
        case .completed(let completed):
            return .completed(
                IOSV1ForegroundVoiceCompletedCapture(
                    ownerID: ownerID,
                    completed: completed
                )
            )
        case .discarded(let reason):
            let mapped: IOSV1ForegroundVoiceCaptureInvalidReason =
                switch reason {
                case .tooShort: .tooShort
                case .empty: .empty
                case .maximumDurationReached: .maximumDurationReached
                case .invalidMedia: .invalidMedia
                }
            return .discarded(mapped)
        }
    }

    public func beginDiscardingBeforeRecorderStop() async throws {
        try await lease.beginDiscardingBeforeRecorderStop()
    }

    public func finishDiscardAfterRecorderStop() async throws {
        try await lease.finishDiscardAfterRecorderStop()
    }

    public func release() { lease.release() }
}

@_spi(HoldTypeIOSCore)
public final class IOSV1ForegroundVoiceCompletedCapture: @unchecked Sendable {
    public var attemptID: UUID { completed.attemptID }
    public var durationMilliseconds: Int64 { completed.durationMilliseconds }
    public var byteCount: Int64 { completed.byteCount }

    fileprivate let ownerID: UUID
    fileprivate let completed: IOSV1VoiceCompletedCapture

    fileprivate init(ownerID: UUID, completed: IOSV1VoiceCompletedCapture) {
        self.ownerID = ownerID
        self.completed = completed
    }

    public func release() { completed.release() }
}

struct IOSV1ForegroundVoiceAudioHandle: Sendable {
    let attemptID: UUID
    let directoryDescriptor: Int32
    let fileDescriptor: Int32
    let fileName: String
    let directoryDevice: UInt64
    let directoryInode: UInt64
    let fileDevice: UInt64
    let fileInode: UInt64
    let byteCount: Int64
}

protocol IOSV1ForegroundVoiceAudioFileSystem: Sendable {
    func openPendingAudio(
        attemptID: UUID,
        relativeIdentifier: String,
        expectedByteCount: Int64?
    ) throws -> IOSV1ForegroundVoiceAudioHandle?
    func read(
        _ handle: IOSV1ForegroundVoiceAudioHandle,
        atOffset offset: Int64,
        maximumByteCount: Int
    ) throws -> Data
    func unlink(_ handle: IOSV1ForegroundVoiceAudioHandle) throws
    func close(_ handle: IOSV1ForegroundVoiceAudioHandle)
}

struct IOSV1ForegroundVoiceDarwinAudioFileSystem:
    IOSV1ForegroundVoiceAudioFileSystem {
    let directoryURL: URL

    func openPendingAudio(
        attemptID: UUID,
        relativeIdentifier: String,
        expectedByteCount: Int64?
    ) throws -> IOSV1ForegroundVoiceAudioHandle? {
        let m4a = IOSVoiceStateStorageLocation.relativeAudioIdentifier(
            for: attemptID
        )
        let wav = IOSVoiceStateStorageLocation.relativeAudioIdentifier(
            for: attemptID,
            extension: "wav"
        )
        guard relativeIdentifier == m4a || relativeIdentifier == wav,
              expectedByteCount.map({ $0 > 0 }) != false else {
            throw IOSV1ForegroundVoicePersistenceError.audioInvalid
        }
        let fileName = String(relativeIdentifier.split(separator: "/").last!)
        let directory = Darwin.open(
            directoryURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard directory >= 0 else {
            if errno == ENOENT { return nil }
            throw openError(errno)
        }
        let file = fileName.withCString {
            Darwin.openat(
                directory,
                $0,
                O_RDONLY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard file >= 0 else {
            let code = errno
            Darwin.close(directory)
            if code == ENOENT { return nil }
            throw openError(code)
        }
        do {
            let handle = try makeHandle(
                attemptID: attemptID,
                directory: directory,
                file: file,
                fileName: fileName,
                expectedByteCount: expectedByteCount
            )
            try validate(handle)
            return handle
        } catch {
            Darwin.close(file)
            Darwin.close(directory)
            throw error
        }
    }

    func read(
        _ handle: IOSV1ForegroundVoiceAudioHandle,
        atOffset offset: Int64,
        maximumByteCount: Int
    ) throws -> Data {
        try validate(handle)
        let requested = min(
            Int64(maximumByteCount),
            handle.byteCount - offset
        )
        guard requested > 0 else { return Data() }
        var data = Data(count: Int(requested))
        var result: Int = -1
        for retry in 0...8 {
            result = data.withUnsafeMutableBytes { buffer in
                Darwin.pread(
                    handle.fileDescriptor,
                    buffer.baseAddress,
                    buffer.count,
                    off_t(offset)
                )
            }
            if result >= 0 { break }
            if errno != EINTR || retry == 8 { break }
        }
        guard result >= 0 else {
            throw IOSV1ForegroundVoicePersistenceError.audioInvalid
        }
        data.removeSubrange(result..<data.count)
        return data
    }

    func unlink(_ handle: IOSV1ForegroundVoiceAudioHandle) throws {
        try validate(handle)
        let result = handle.fileName.withCString {
            Darwin.unlinkat(handle.directoryDescriptor, $0, 0)
        }
        guard result == 0 else {
            throw IOSV1ForegroundVoicePersistenceError.cleanupUncertain
        }
        var status = stat()
        guard Darwin.fstat(handle.fileDescriptor, &status) == 0,
              status.st_nlink == 0,
              Darwin.fsync(handle.directoryDescriptor) == 0 else {
            throw IOSV1ForegroundVoicePersistenceError.cleanupUncertain
        }
    }

    func close(_ handle: IOSV1ForegroundVoiceAudioHandle) {
        Darwin.close(handle.fileDescriptor)
        Darwin.close(handle.directoryDescriptor)
    }

    private func makeHandle(
        attemptID: UUID,
        directory: Int32,
        file: Int32,
        fileName: String,
        expectedByteCount: Int64?
    ) throws -> IOSV1ForegroundVoiceAudioHandle {
        var directoryStatus = stat()
        var fileStatus = stat()
        guard Darwin.fstat(directory, &directoryStatus) == 0,
              Darwin.fstat(file, &fileStatus) == 0,
              directoryStatus.st_mode & S_IFMT == S_IFDIR,
              fileStatus.st_mode & S_IFMT == S_IFREG,
              fileStatus.st_mode & mode_t(0o777) == mode_t(0o600),
              fileStatus.st_nlink == 1,
              expectedByteCount.map({
                  Int64(fileStatus.st_size) == $0
              }) != false else {
            throw IOSV1ForegroundVoicePersistenceError.audioInvalid
        }
        return IOSV1ForegroundVoiceAudioHandle(
            attemptID: attemptID,
            directoryDescriptor: directory,
            fileDescriptor: file,
            fileName: fileName,
            directoryDevice: UInt64(directoryStatus.st_dev),
            directoryInode: UInt64(directoryStatus.st_ino),
            fileDevice: UInt64(fileStatus.st_dev),
            fileInode: UInt64(fileStatus.st_ino),
            byteCount: Int64(fileStatus.st_size)
        )
    }

    private func validate(
        _ handle: IOSV1ForegroundVoiceAudioHandle
    ) throws {
        var directoryStatus = stat()
        var directoryPathStatus = stat()
        var fileStatus = stat()
        var pathStatus = stat()
        guard Darwin.fstat(
                  handle.directoryDescriptor,
                  &directoryStatus
              ) == 0,
              Darwin.lstat(directoryURL.path, &directoryPathStatus) == 0,
              directoryStatus.st_mode & S_IFMT == S_IFDIR,
              UInt64(directoryStatus.st_dev) == handle.directoryDevice,
              UInt64(directoryStatus.st_ino) == handle.directoryInode,
              directoryStatus.st_dev == directoryPathStatus.st_dev,
              directoryStatus.st_ino == directoryPathStatus.st_ino,
              Darwin.fstat(handle.fileDescriptor, &fileStatus) == 0,
              handle.fileName.withCString({
                  Darwin.fstatat(
                      handle.directoryDescriptor,
                      $0,
                      &pathStatus,
                      AT_SYMLINK_NOFOLLOW
                  )
              }) == 0,
              fileStatus.st_mode & S_IFMT == S_IFREG,
              fileStatus.st_mode & mode_t(0o777) == mode_t(0o600),
              fileStatus.st_nlink == 1,
              UInt64(fileStatus.st_dev) == handle.fileDevice,
              UInt64(fileStatus.st_ino) == handle.fileInode,
              fileStatus.st_dev == pathStatus.st_dev,
              fileStatus.st_ino == pathStatus.st_ino,
              Int64(fileStatus.st_size) == handle.byteCount else {
            throw IOSV1ForegroundVoicePersistenceError.audioInvalid
        }
    }

    private func openError(_ code: Int32) -> Error {
        if code == EACCES || code == EPERM {
            return IOSV1ForegroundVoicePersistenceError
                .audioTemporarilyUnavailable
        }
        return IOSV1ForegroundVoicePersistenceError.audioInvalid
    }
}

@_spi(HoldTypeIOSCore)
public final class IOSV1PendingTranscriptionAudio: @unchecked Sendable {
    public static let maximumReadByteCount = 64 * 1_024

    public let format: IOSV1PendingRecordingAudioFormat
    public let durationMilliseconds: Int64
    public let byteCount: Int64

    private let lock = NSLock()
    private let fileSystem: any IOSV1ForegroundVoiceAudioFileSystem
    private var handle: IOSV1ForegroundVoiceAudioHandle?
    private var activeReadCount = 0
    private var invalidated = false

    init(
        recording: IOSV1PendingRecording,
        handle: IOSV1ForegroundVoiceAudioHandle,
        fileSystem: any IOSV1ForegroundVoiceAudioFileSystem
    ) {
        format = recording.audioRelativeIdentifier.hasSuffix(".wav")
            ? .wav : .m4a
        durationMilliseconds = recording.durationMilliseconds
        byteCount = recording.byteCount
        self.handle = handle
        self.fileSystem = fileSystem
    }

    public func read(
        atOffset offset: Int64,
        maximumByteCount: Int = IOSV1PendingTranscriptionAudio
            .maximumReadByteCount
    ) async throws -> Data {
        guard offset >= 0, offset <= byteCount,
              maximumByteCount > 0,
              maximumByteCount <= Self.maximumReadByteCount else {
            throw IOSV1ForegroundVoicePersistenceError.invalidAudioRead
        }
        try Task.checkCancellation()
        let active = try lock.withLock {
            guard !invalidated, let handle else {
                throw IOSV1ForegroundVoicePersistenceError
                    .dispatchAlreadyExecuted
            }
            activeReadCount += 1
            return handle
        }
        defer { finishRead() }
        let data = try fileSystem.read(
            active,
            atOffset: offset,
            maximumByteCount: maximumByteCount
        )
        try Task.checkCancellation()
        return data
    }

    fileprivate func invalidate() {
        let closing = lock.withLock {
            invalidated = true
            return takeClosableHandle()
        }
        if let closing { fileSystem.close(closing) }
    }

    private func finishRead() {
        let closing = lock.withLock {
            activeReadCount -= 1
            return takeClosableHandle()
        }
        if let closing { fileSystem.close(closing) }
    }

    private func takeClosableHandle() -> IOSV1ForegroundVoiceAudioHandle? {
        guard invalidated, activeReadCount == 0 else { return nil }
        defer { handle = nil }
        return handle
    }

    deinit {
        if let handle { fileSystem.close(handle) }
    }
}

@_spi(HoldTypeIOSCore)
public protocol IOSV1PendingTranscriptionExecutor: Sendable {
    func transcribe(
        recording: IOSV1PendingRecording,
        audio: IOSV1PendingTranscriptionAudio
    ) async throws -> String
}

private final class IOSV1ForegroundVoiceDispatchAdmission:
    @unchecked Sendable {
    private let lock = NSLock()
    private var admitted = false

    func admit() -> Bool {
        lock.withLock {
            guard !admitted else { return false }
            admitted = true
            return true
        }
    }
}

@_spi(HoldTypeIOSCore)
public struct IOSV1ForegroundVoiceTranscriptionDispatch: Sendable {
    public let recording: IOSV1PendingRecording

    private let audio: IOSV1PendingTranscriptionAudio
    private let admission = IOSV1ForegroundVoiceDispatchAdmission()

    init(
        recording: IOSV1PendingRecording,
        audio: IOSV1PendingTranscriptionAudio
    ) {
        self.recording = recording
        self.audio = audio
    }

    public var expectation: IOSV1PendingRecordingExpectation {
        IOSV1PendingRecordingExpectation(recording: recording)
    }

    public func execute(
        using executor: any IOSV1PendingTranscriptionExecutor
    ) async throws -> String {
        guard admission.admit() else {
            throw IOSV1ForegroundVoicePersistenceError
                .dispatchAlreadyExecuted
        }
        defer { audio.invalidate() }
        try Task.checkCancellation()
        return try await executor.transcribe(
            recording: recording,
            audio: audio
        )
    }
}

@_spi(HoldTypeIOSCore)
public actor IOSV1ForegroundVoicePersistenceOwner {
    private let ownerID = UUID()
    private let repository: IOSVoiceStateRepository
    private let captureOwner: IOSV1VoiceCaptureOwner
    private let historyRepository: IOSAcceptedTextHistoryRepository
    private let audioFileSystem: any IOSV1ForegroundVoiceAudioFileSystem
    private let now: @Sendable () -> Date

    private var operationActive = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    public init(applicationSupportDirectoryURL: URL) {
        let repository = IOSVoiceStateRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        self.repository = repository
        captureOwner = IOSV1VoiceCaptureOwner(
            repository: repository,
            directoryURL: IOSVoiceStateStorageLocation.directoryURL(
                in: applicationSupportDirectoryURL
            ),
            fileSystem: IOSV1VoiceCaptureDarwinFileSystem(),
            mediaValidator: IOSV1VoiceCaptureMediaValidator()
        )
        historyRepository = IOSAcceptedTextHistoryRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        audioFileSystem = IOSV1ForegroundVoiceDarwinAudioFileSystem(
            directoryURL: IOSVoiceStateStorageLocation.directoryURL(
                in: applicationSupportDirectoryURL
            )
        )
        now = { Date() }
    }

    public init(
        applicationSupportDirectoryURL: URL,
        acceptedTextHistoryRepository: IOSAcceptedTextHistoryRepository
    ) {
        let repository = IOSVoiceStateRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        self.repository = repository
        captureOwner = IOSV1VoiceCaptureOwner(
            repository: repository,
            directoryURL: IOSVoiceStateStorageLocation.directoryURL(
                in: applicationSupportDirectoryURL
            ),
            fileSystem: IOSV1VoiceCaptureDarwinFileSystem(),
            mediaValidator: IOSV1VoiceCaptureMediaValidator()
        )
        historyRepository = acceptedTextHistoryRepository
        audioFileSystem = IOSV1ForegroundVoiceDarwinAudioFileSystem(
            directoryURL: IOSVoiceStateStorageLocation.directoryURL(
                in: applicationSupportDirectoryURL
            )
        )
        now = { Date() }
    }

    init(
        repository: IOSVoiceStateRepository,
        captureOwner: IOSV1VoiceCaptureOwner,
        historyRepository: IOSAcceptedTextHistoryRepository,
        audioFileSystem: any IOSV1ForegroundVoiceAudioFileSystem,
        now: @escaping @Sendable () -> Date
    ) {
        self.repository = repository
        self.captureOwner = captureOwner
        self.historyRepository = historyRepository
        self.audioFileSystem = audioFileSystem
        self.now = now
    }

    public func createCapture(
        attemptID: UUID,
        outputIntent: DictationOutputIntent
    ) async throws -> IOSV1ForegroundVoiceCaptureLease {
        await acquireOperation()
        defer { releaseOperation() }
        let lease = try await captureOwner.createCapture(
            attemptID: attemptID,
            outputIntent: outputIntent,
            createdAt: now()
        )
        return IOSV1ForegroundVoiceCaptureLease(
            ownerID: ownerID,
            lease: lease
        )
    }

    public func prepareCompletedCapture(
        _ capture: IOSV1ForegroundVoiceCompletedCapture,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSV1PendingRecording {
        await acquireOperation()
        defer { releaseOperation() }
        guard capture.ownerID == ownerID else {
            throw IOSV1ForegroundVoicePersistenceError.invalidTransition
        }
        return IOSV1PendingRecording(
            try await capture.completed.promote(
                transcriptionConfiguration: transcriptionConfiguration
            )
        )
    }

    /// Classifies only local capture ownership after process loss. It never
    /// starts provider work or treats an unfinished recorder file as valid.
    public func reconcileCaptureSourcesAtLaunch() async
        -> IOSV1ForegroundVoiceCaptureRecoveryObservation {
        await acquireOperation()
        defer { releaseOperation() }
        do {
            let snapshot = try await repository.load()
            guard let capture = snapshot.capture else { return .empty }
            switch capture.phase {
            case .completed:
                guard let byteCount = capture.byteCount,
                      let handle = try audioFileSystem.openPendingAudio(
                          attemptID: capture.attemptID,
                          relativeIdentifier: capture.audioRelativeIdentifier,
                          expectedByteCount: byteCount
                      ) else { return .blocked }
                audioFileSystem.close(handle)
                return .recoverable(attemptID: capture.attemptID)
            case .recording, .finalizing:
                return .discardOnly(attemptID: capture.attemptID)
            case .discarding:
                try await discardCaptureUnlocked(capture)
                return .empty
            }
        } catch {
            return .blocked
        }
    }

    /// Converts a validated completed capture to failed Pending. A later
    /// explicit Retry is the only operation that may start a provider call.
    public func recoverCapture(
        attemptID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSV1PendingRecording {
        await acquireOperation()
        defer { releaseOperation() }
        let snapshot: IOSVoiceStateSnapshot
        do { snapshot = try await repository.load() }
        catch { throw mapRepositoryError(error) }
        guard let capture = snapshot.capture,
              capture.attemptID == attemptID,
              capture.phase == .completed,
              let byteCount = capture.byteCount,
              let handle = try audioFileSystem.openPendingAudio(
                  attemptID: capture.attemptID,
                  relativeIdentifier: capture.audioRelativeIdentifier,
                  expectedByteCount: byteCount
              ) else {
            throw IOSV1ForegroundVoicePersistenceError.invalidTransition
        }
        audioFileSystem.close(handle)
        do {
            return IOSV1PendingRecording(
                try await repository.promoteCapture(
                    attemptID: attemptID,
                    transcriptionConfiguration: transcriptionConfiguration,
                    initialStatus: .failed
                )
            )
        } catch { throw mapRepositoryError(error) }
    }

    public func discardCapture(attemptID: UUID) async throws {
        await acquireOperation()
        defer { releaseOperation() }
        let snapshot: IOSVoiceStateSnapshot
        do { snapshot = try await repository.load() }
        catch { throw mapRepositoryError(error) }
        guard let capture = snapshot.capture else { return }
        guard capture.attemptID == attemptID else {
            throw IOSV1ForegroundVoicePersistenceError.stalePending
        }
        try await discardCaptureUnlocked(capture)
    }

    public func load() async throws -> IOSV1PendingRecordingObservation? {
        await acquireOperation()
        defer { releaseOperation() }
        return try await loadUnlocked()
    }

    public func beginTranscription(
        expected: IOSV1PendingRecordingExpectation,
        transcriptionID: UUID
    ) async throws -> IOSV1ForegroundVoiceTranscriptionDispatch {
        await acquireOperation()
        defer { releaseOperation() }
        _ = try await requirePending(expected)
        let state: IOSVoiceStatePending
        do {
            state = try await repository.beginProcessing(
                attemptID: expected.attemptID,
                operationID: transcriptionID,
                allowFailed: false
            )
        } catch { throw mapRepositoryError(error) }
        return try await makeDispatch(for: state)
    }

    public func retryTranscription(
        expected: IOSV1PendingRecordingExpectation,
        transcriptionID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSV1ForegroundVoiceTranscriptionDispatch {
        await acquireOperation()
        defer { releaseOperation() }
        _ = try await requirePending(expected)
        let state: IOSVoiceStatePending
        do {
            state = try await repository.beginRetry(
                attemptID: expected.attemptID,
                operationID: transcriptionID,
                transcriptionConfiguration: transcriptionConfiguration
            )
        } catch { throw mapRepositoryError(error) }
        return try await makeDispatch(for: state)
    }

    public func markPostProcessing(
        expected: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1PendingRecording {
        try await advance(expected, to: .postProcessing)
    }

    public func markOutputDelivery(
        expected: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1PendingRecording {
        try await advance(expected, to: .outputDelivery)
    }

    public func markFailed(
        expected: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1PendingRecording {
        await acquireOperation()
        defer { releaseOperation() }
        _ = try await requirePending(expected)
        do {
            return IOSV1PendingRecording(
                try await repository.markFailed(attemptID: expected.attemptID)
            )
        } catch { throw mapRepositoryError(error) }
    }

    public func discard(
        expected: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1PendingRecordingDiscardResult {
        await acquireOperation()
        defer { releaseOperation() }
        let snapshot: IOSVoiceStateSnapshot
        do { snapshot = try await repository.load() }
        catch { throw mapRepositoryError(error) }
        guard let current = snapshot.pending else { return .alreadyAbsent }
        let pending = IOSV1PendingRecording(current)
        guard expected.recording == pending else {
            throw IOSV1ForegroundVoicePersistenceError.stalePending
        }
        guard pending.phase != .acceptedCleanup else {
            throw IOSV1ForegroundVoicePersistenceError.invalidTransition
        }
        try unlinkAudio(for: pending, allowMissing: true)
        do {
            _ = try await repository.discardPending(
                attemptID: pending.attemptID
            )
        } catch { throw mapRepositoryError(error) }
        return .discarded
    }

    public func accept(
        _ preparation: IOSV1ForegroundVoiceAcceptedOutputPreparation,
        expectedPending: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1ForegroundVoiceAcceptanceResult {
        await acquireOperation()
        defer { releaseOperation() }
        let pending = try await requirePending(expectedPending)
        guard pending.phase == .outputDelivery,
              pending.transcriptionID == preparation.transcriptID,
              pending.attemptID == preparation.attemptID,
              pending.outputIntent == preparation.outputIntent else {
            throw IOSV1ForegroundVoicePersistenceError.invalidTransition
        }
        let accepted: IOSVoiceStateAcceptedResult
        do {
            accepted = try await repository.commitAccepted(
                attemptID: pending.attemptID,
                resultID: preparation.deliveryID,
                text: preparation.acceptedText,
                createdAt: now()
            )
        } catch { throw mapRepositoryError(error) }
        let record = IOSV1AcceptedOutputDeliveryRecord(accepted)
        var notice = await appendHistory(record)
        do {
            try await finishAcceptedCleanup(pending: pending, record: record)
        } catch {
            notice = Self.addCleanupNotice(to: notice)
        }
        return .resultReady(record, notice: notice)
    }

    public func reconcileAcceptance(
        matching preparation: IOSV1ForegroundVoiceAcceptedOutputPreparation
    ) async throws -> IOSV1ForegroundVoiceAcceptanceResult? {
        await acquireOperation()
        defer { releaseOperation() }
        let snapshot: IOSVoiceStateSnapshot
        do { snapshot = try await repository.load() }
        catch { throw mapRepositoryError(error) }
        guard let latest = snapshot.latest,
              latest.resultID == preparation.deliveryID,
              latest.sourceAttemptID == preparation.attemptID,
              latest.text.utf8.elementsEqual(
                  preparation.acceptedText.utf8
              ) else { return nil }
        let record = IOSV1AcceptedOutputDeliveryRecord(latest)
        var notice: IOSV1ForegroundVoiceAcceptanceNotice?
        if let state = snapshot.pending,
           case .acceptedCleanup(let accepted) = state.status,
           accepted.resultID == record.resultID,
           accepted.sourceAttemptID == record.sourceAttemptID {
            notice = await appendHistory(record)
            do {
                try await finishAcceptedCleanup(
                    pending: IOSV1PendingRecording(state),
                    record: record
                )
            } catch {
                notice = Self.addCleanupNotice(to: notice)
            }
        }
        return .resultReady(record, notice: notice)
    }

    public func loadLatestResult() async throws
        -> IOSV1ForegroundVoiceLatestResultObservation {
        await acquireOperation()
        defer { releaseOperation() }
        do {
            guard let latest = try await repository.load().latest else {
                return .absent
            }
            return .resultReady(IOSV1AcceptedOutputDeliveryRecord(latest))
        } catch { throw mapRepositoryError(error) }
    }

    public func clearLatestResult(
        expected: IOSV1AcceptedOutputDeliveryExpectation
    ) async throws -> IOSV1ForegroundVoiceClearResult {
        await acquireOperation()
        defer { releaseOperation() }
        let snapshot: IOSVoiceStateSnapshot
        do { snapshot = try await repository.load() }
        catch { throw mapRepositoryError(error) }
        guard let latest = snapshot.latest else { return .alreadyAbsent }
        guard latest.resultID == expected.resultID,
              latest.sourceAttemptID == expected.sourceAttemptID else {
            throw IOSV1ForegroundVoicePersistenceError.invalidTransition
        }
        do {
            _ = try await repository.clearLatest(resultID: latest.resultID)
        } catch { throw mapRepositoryError(error) }
        return .cleared
    }

    public func recoverContainingAppLifecycle(
        _ opportunity: IOSV1ContainingAppRecoveryOpportunity
    ) async -> IOSV1ContainingAppRecoveryDisposition {
        guard opportunity == .processLaunch else { return .complete }
        await acquireOperation()
        defer { releaseOperation() }
        do {
            let snapshot = try await repository.reconcileAfterLaunch()
            guard snapshot.capture == nil else {
                return .pendingLocalRecovery
            }
            if let state = snapshot.pending,
               case .acceptedCleanup(let accepted) = state.status {
                guard let latest = snapshot.latest,
                      latest.resultID == accepted.resultID,
                      latest.sourceAttemptID == accepted.sourceAttemptID,
                      latest.text.utf8.elementsEqual(accepted.text.utf8) else {
                    return .pendingLocalRecovery
                }
                let record = IOSV1AcceptedOutputDeliveryRecord(latest)
                _ = await appendHistory(record)
                try await finishAcceptedCleanup(
                    pending: IOSV1PendingRecording(state),
                    record: record
                )
                return .complete
            }
            guard let pending = snapshot.pending else { return .complete }
            return availability(for: IOSV1PendingRecording(pending))
                == .available ? .complete : .pendingLocalRecovery
        } catch {
            return .pendingLocalRecovery
        }
    }

    private func advance(
        _ expected: IOSV1PendingRecordingExpectation,
        to stage: IOSVoiceStateProcessingStage
    ) async throws -> IOSV1PendingRecording {
        await acquireOperation()
        defer { releaseOperation() }
        let pending = try await requirePending(expected)
        guard let operationID = pending.transcriptionID else {
            throw IOSV1ForegroundVoicePersistenceError.invalidTransition
        }
        do {
            return IOSV1PendingRecording(
                try await repository.advanceProcessing(
                    attemptID: pending.attemptID,
                    operationID: operationID,
                    to: stage
                )
            )
        } catch { throw mapRepositoryError(error) }
    }

    private func loadUnlocked() async throws
        -> IOSV1PendingRecordingObservation? {
        let snapshot: IOSVoiceStateSnapshot
        do { snapshot = try await repository.load() }
        catch { throw mapRepositoryError(error) }
        guard let state = snapshot.pending else { return nil }
        let recording = IOSV1PendingRecording(state)
        return IOSV1PendingRecordingObservation(
            recording: recording,
            availability: availability(for: recording)
        )
    }

    private func requirePending(
        _ expected: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1PendingRecording {
        let snapshot: IOSVoiceStateSnapshot
        do { snapshot = try await repository.load() }
        catch { throw mapRepositoryError(error) }
        guard let state = snapshot.pending else {
            throw IOSV1ForegroundVoicePersistenceError.stalePending
        }
        let current = IOSV1PendingRecording(state)
        guard current == expected.recording else {
            throw IOSV1ForegroundVoicePersistenceError.stalePending
        }
        return current
    }

    private func makeDispatch(
        for state: IOSVoiceStatePending
    ) async throws -> IOSV1ForegroundVoiceTranscriptionDispatch {
        let recording = IOSV1PendingRecording(state)
        do {
            guard let handle = try audioFileSystem.openPendingAudio(
                attemptID: recording.attemptID,
                relativeIdentifier: recording.audioRelativeIdentifier,
                expectedByteCount: recording.byteCount
            ) else {
                _ = try? await repository.markFailed(
                    attemptID: recording.attemptID
                )
                throw IOSV1ForegroundVoicePersistenceError.audioMissing
            }
            return IOSV1ForegroundVoiceTranscriptionDispatch(
                recording: recording,
                audio: IOSV1PendingTranscriptionAudio(
                    recording: recording,
                    handle: handle,
                    fileSystem: audioFileSystem
                )
            )
        } catch {
            _ = try? await repository.markFailed(
                attemptID: recording.attemptID
            )
            throw error
        }
    }

    private func availability(
        for recording: IOSV1PendingRecording
    ) -> IOSV1PendingRecordingAvailability {
        do {
            guard let handle = try audioFileSystem.openPendingAudio(
                attemptID: recording.attemptID,
                relativeIdentifier: recording.audioRelativeIdentifier,
                expectedByteCount: recording.byteCount
            ) else { return .missing }
            audioFileSystem.close(handle)
            return .available
        } catch IOSV1ForegroundVoicePersistenceError
            .audioTemporarilyUnavailable {
            return .temporarilyUnavailable
        } catch {
            return .invalid
        }
    }

    private func appendHistory(
        _ record: IOSV1AcceptedOutputDeliveryRecord
    ) async -> IOSV1ForegroundVoiceAcceptanceNotice? {
        do {
            _ = try await historyRepository.append(
                IOSAcceptedTextHistoryEntry(
                    resultID: record.resultID,
                    text: record.acceptedText,
                    createdAt: record.createdAt
                )
            )
            return nil
        } catch {
            return .historyWriteFailed
        }
    }

    private func finishAcceptedCleanup(
        pending: IOSV1PendingRecording,
        record: IOSV1AcceptedOutputDeliveryRecord
    ) async throws {
        try unlinkAudio(for: pending, allowMissing: true)
        do {
            _ = try await repository.finishAcceptedCleanup(
                attemptID: pending.attemptID,
                resultID: record.resultID
            )
        } catch { throw mapRepositoryError(error) }
    }

    private static func addCleanupNotice(
        to notice: IOSV1ForegroundVoiceAcceptanceNotice?
    ) -> IOSV1ForegroundVoiceAcceptanceNotice {
        switch notice {
        case .historyWriteFailed:
            return .historyWriteFailedAndLocalCleanupPending
        case .historyWriteFailedAndLocalCleanupPending:
            return .historyWriteFailedAndLocalCleanupPending
        case .localCleanupPending, nil:
            return .localCleanupPending
        }
    }

    private func discardCaptureUnlocked(
        _ capture: IOSVoiceStateCapture
    ) async throws {
        let discarding: IOSVoiceStateCapture
        do {
            discarding = try await repository.transitionCapture(
                attemptID: capture.attemptID,
                to: .discarding
            )
        } catch { throw mapRepositoryError(error) }
        if let handle = try audioFileSystem.openPendingAudio(
            attemptID: discarding.attemptID,
            relativeIdentifier: discarding.audioRelativeIdentifier,
            expectedByteCount: discarding.byteCount
        ) {
            defer { audioFileSystem.close(handle) }
            try audioFileSystem.unlink(handle)
        }
        do {
            _ = try await repository.clearCapture(
                attemptID: discarding.attemptID
            )
        } catch { throw mapRepositoryError(error) }
    }

    private func unlinkAudio(
        for pending: IOSV1PendingRecording,
        allowMissing: Bool
    ) throws {
        guard let handle = try audioFileSystem.openPendingAudio(
            attemptID: pending.attemptID,
            relativeIdentifier: pending.audioRelativeIdentifier,
            expectedByteCount: pending.byteCount
        ) else {
            if allowMissing { return }
            throw IOSV1ForegroundVoicePersistenceError.audioMissing
        }
        defer { audioFileSystem.close(handle) }
        try audioFileSystem.unlink(handle)
    }

    private func mapRepositoryError(_ error: Error) -> Error {
        guard let error = error as? IOSVoiceStateRepositoryError else {
            return error
        }
        switch error {
        case .stalePending: return IOSV1ForegroundVoicePersistenceError.stalePending
        case .invalidTransition, .pendingSlotOccupied:
            return IOSV1ForegroundVoicePersistenceError.invalidTransition
        case .invalidAcceptedText:
            return IOSV1ForegroundVoicePersistenceError.invalidAcceptedOutput
        case .readFailed, .sourceTooLarge, .malformedData,
             .unsupportedSchemaVersion, .invalidRecord, .writeFailed:
            return IOSV1ForegroundVoicePersistenceError.localPersistence
        }
    }

    private func acquireOperation() async {
        guard operationActive else {
            operationActive = true
            return
        }
        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func releaseOperation() {
        guard !operationWaiters.isEmpty else {
            operationActive = false
            return
        }
        operationWaiters.removeFirst().resume()
    }
}

extension IOSV1PendingRecording: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSV1PendingRecording(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSV1AcceptedOutputDeliveryRecord: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "IOSV1AcceptedOutputDeliveryRecord(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
