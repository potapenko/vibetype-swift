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
public enum IOSV1PendingTextCheckpointStage: String, Equatable, Sendable {
    case transcriptionAccepted
    case correctionInFlight
    case translationReady
    case translationInFlight
    case outputReady

    init(_ stage: IOSVoiceStateTextCheckpointStage) {
        self = Self(rawValue: stage.rawValue) ?? .transcriptionAccepted
    }

    var repositoryValue: IOSVoiceStateTextCheckpointStage {
        IOSVoiceStateTextCheckpointStage(rawValue: rawValue)
            ?? .transcriptionAccepted
    }
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
    public let draftInsertionMode: IOSVoiceDraftInsertionMode
    public let forcesTextCorrection: Bool
    public let transcriptionID: UUID?
    public let transcriptionModel: String
    public let transcriptionLanguageCode: String?
    public let durationMilliseconds: Int64
    public let byteCount: Int64
    public let acceptedAudioRetention: IOSAcceptedAudioRetention
    public let transcriptionReplayBlocked: Bool
    /// Durable normalized transcription accepted before downstream work.
    /// A failed recording with this checkpoint retries post-processing only.
    public let acceptedTranscriptionID: UUID?
    public let acceptedTranscript: String?
    public let textCheckpointStage: IOSV1PendingTextCheckpointStage?
    public let textCheckpointText: String?

    let state: IOSVoiceStatePending

    init(_ state: IOSVoiceStatePending) {
        self.state = state
        attemptID = state.attemptID
        audioRelativeIdentifier = state.audioRelativeIdentifier
        createdAt = state.createdAt
        updatedAt = state.updatedAt
        outputIntent = state.outputIntent
        draftInsertionMode = state.draftInsertionMode
        forcesTextCorrection = state.forcesTextCorrection
        transcriptionModel = state.transcriptionModel
        transcriptionLanguageCode = state.transcriptionLanguageCode
        durationMilliseconds = state.durationMilliseconds
        byteCount = state.byteCount
        acceptedAudioRetention = state.acceptedAudioRetention
        transcriptionReplayBlocked = state.transcriptionReplayBlocked
        acceptedTranscriptionID = state.transcriptionCheckpoint?.operationID
        acceptedTranscript = state.transcriptionCheckpoint?.acceptedTranscript
        textCheckpointStage = state.transcriptionCheckpoint.map {
            IOSV1PendingTextCheckpointStage($0.stage)
        }
        textCheckpointText = state.transcriptionCheckpoint?.text
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

#if DEBUG
    public static func qualificationFixture(
        attemptID: UUID = UUID(),
        outputIntent: DictationOutputIntent = .standard,
        draftInsertionMode: IOSVoiceDraftInsertionMode = .replace,
        forcesTextCorrection: Bool = false,
        phase: IOSV1PendingRecordingPhase = .readyForTranscription,
        transcriptionID: UUID? = nil,
        transcriptionConfiguration: TranscriptionConfiguration = .init(),
        acceptedAudioRetention: IOSAcceptedAudioRetention =
            .recordingCachePolicy,
        transcriptionReplayBlocked: Bool = false,
        acceptedTranscriptionID: UUID? = nil,
        acceptedTranscript: String? = nil,
        textCheckpointStage: IOSV1PendingTextCheckpointStage? = nil,
        textCheckpointText: String? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        durationMilliseconds: Int64 = 1_000,
        byteCount: Int64 = 1_024
    ) throws -> Self {
        let status: IOSVoiceStatePendingStatus
        switch phase {
        case .readyForTranscription:
            guard transcriptionID == nil else {
                throw IOSV1ForegroundVoicePersistenceError.invalidTransition
            }
            status = .ready
        case .failed:
            guard transcriptionID == nil else {
                throw IOSV1ForegroundVoicePersistenceError.invalidTransition
            }
            status = .failed
        case .transcribing, .postProcessing, .outputDelivery:
            guard let transcriptionID else {
                throw IOSV1ForegroundVoicePersistenceError.invalidTransition
            }
            let stage: IOSVoiceStateProcessingStage = switch phase {
            case .transcribing: .transcription
            case .postProcessing: .postProcessing
            case .outputDelivery: .outputDelivery
            default: preconditionFailure("unreachable phase")
            }
            status = .processing(stage, operationID: transcriptionID)
        case .acceptedCleanup:
            throw IOSV1ForegroundVoicePersistenceError.invalidTransition
        }
        let transcriptionCheckpoint: IOSVoiceStateTranscriptionCheckpoint?
        switch (
            acceptedTranscriptionID,
            acceptedTranscript,
            textCheckpointStage,
            textCheckpointText
        ) {
        case (nil, nil, nil, nil):
            transcriptionCheckpoint = nil
        case let (
            .some(operationID),
            .some(acceptedTranscript),
            .some(stage),
            .some(text)
        ):
            transcriptionCheckpoint = try IOSVoiceStateTranscriptionCheckpoint(
                operationID: operationID,
                acceptedTranscript: acceptedTranscript,
                stage: stage.repositoryValue,
                text: text
            )
        default:
            throw IOSV1ForegroundVoicePersistenceError.invalidTransition
        }
        return Self(
            try IOSVoiceStatePending(
                attemptID: attemptID,
                audioRelativeIdentifier:
                    IOSVoiceStateStorageLocation.relativeAudioIdentifier(
                        for: attemptID
                    ),
                createdAt: createdAt,
                updatedAt: createdAt,
                outputIntent: outputIntent,
                draftInsertionMode: draftInsertionMode,
                forcesTextCorrection: forcesTextCorrection,
                transcriptionModel:
                    transcriptionConfiguration.resolvedModel,
                transcriptionLanguageCode:
                    transcriptionConfiguration.resolvedLanguageCode,
                durationMilliseconds: durationMilliseconds,
                byteCount: byteCount,
                acceptedAudioRetention: acceptedAudioRetention,
                transcriptionReplayBlocked: transcriptionReplayBlocked,
                transcriptionCheckpoint: transcriptionCheckpoint,
                status: status
            )
        )
    }
#endif
}

@_spi(HoldTypeIOSCore)
public struct IOSV1PendingRecordingExpectation: Equatable, Sendable {
    public let attemptID: UUID

    let recording: IOSV1PendingRecording

    public init(recording: IOSV1PendingRecording) {
        self.recording = recording
        attemptID = recording.attemptID
    }
}

@_spi(HoldTypeIOSCore)
public struct IOSV1PendingRecordingObservation: Equatable, Sendable {
    public let recording: IOSV1PendingRecording
    public let availability: IOSV1PendingRecordingAvailability

    public var expectation: IOSV1PendingRecordingExpectation {
        IOSV1PendingRecordingExpectation(recording: recording)
    }

    public init(
        recording: IOSV1PendingRecording,
        availability: IOSV1PendingRecordingAvailability
    ) {
        self.recording = recording
        self.availability = availability
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
    public let attemptID: UUID
    public let transcriptID: UUID
    public let acceptedText: String
    public let outputIntent: DictationOutputIntent

    public init(
        deliveryID: UUID,
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

/// One descriptor-validated completed capture that still owns local recovery
/// because its source-to-Pending promotion has not committed. The transient
/// source path never crosses this boundary.
@_spi(HoldTypeIOSCore)
public struct IOSV1CompletedCaptureRecoveryObservation: Equatable, Sendable {
    public let attemptID: UUID
    public let recordingDurationLimit: RecordingDurationLimit
    public let durationMilliseconds: Int64
    public let byteCount: Int64
    public let availability: IOSV1PendingRecordingAvailability

    fileprivate let capture: IOSVoiceStateCapture

    fileprivate init(
        capture: IOSVoiceStateCapture,
        availability: IOSV1PendingRecordingAvailability
    ) {
        attemptID = capture.attemptID
        recordingDurationLimit = capture.recordingDurationLimit
        durationMilliseconds = capture.durationMilliseconds ?? 0
        byteCount = capture.byteCount ?? 0
        self.availability = availability
        self.capture = capture
    }

#if DEBUG
    public static func qualificationFixture(
        attemptID: UUID = UUID(),
        recordingDurationLimit: RecordingDurationLimit = .default,
        durationMilliseconds: Int64 = 1_000,
        byteCount: Int64 = 1_024,
        availability: IOSV1PendingRecordingAvailability = .available
    ) throws -> Self {
        Self(
            capture: try IOSVoiceStateCapture(
                attemptID: attemptID,
                audioRelativeIdentifier:
                    IOSVoiceStateStorageLocation.relativeAudioIdentifier(
                        for: attemptID
                    ),
                createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                outputIntent: .standard,
                recordingDurationLimit: recordingDurationLimit,
                phase: .completed,
                durationMilliseconds: durationMilliseconds,
                byteCount: byteCount
            ),
            availability: availability
        )
    }
#endif
}

@_spi(HoldTypeIOSCore)
public struct IOSV1CompletedCaptureRecoveryExpectation: Equatable, Sendable {
    public let attemptID: UUID
    public let recordingDurationLimit: RecordingDurationLimit
    public let durationMilliseconds: Int64

    fileprivate let capture: IOSVoiceStateCapture

    public init(recording: IOSV1CompletedCaptureRecoveryObservation) {
        attemptID = recording.attemptID
        recordingDurationLimit = recording.recordingDurationLimit
        durationMilliseconds = recording.durationMilliseconds
        capture = recording.capture
    }
}

@_spi(HoldTypeIOSCore)
public enum IOSV1SavedRecordingObservation: Equatable, Sendable {
    case pending(IOSV1PendingRecordingObservation)
    case completedCapture(IOSV1CompletedCaptureRecoveryObservation)
}

@_spi(HoldTypeIOSCore)
public enum IOSV1SavedRecordingExpectation: Equatable, Sendable {
    case pending(IOSV1PendingRecordingExpectation)
    case completedCapture(IOSV1CompletedCaptureRecoveryExpectation)
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

    public func completeAfterRecorderClose(
        fallbackDurationMilliseconds: Int64? = nil
    ) async throws
        -> IOSV1ForegroundVoiceCaptureFinalizationResult {
        switch try await lease.completeAfterRecorderClose(
            fallbackDurationMilliseconds: fallbackDurationMilliseconds
        ) {
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
    public var recordingDurationLimit: RecordingDurationLimit {
        completed.recordingDurationLimit
    }
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

/// One exact, descriptor-validated Pending recording prepared for local
/// playback. The protected source URL never crosses the persistence boundary.
@_spi(HoldTypeIOSCore)
public final class IOSV1PendingRecordingPlaybackAudio: @unchecked Sendable {
    public let format: IOSV1PendingRecordingAudioFormat

    private let data: Data

    fileprivate convenience init(
        recording: IOSV1PendingRecording,
        data: Data
    ) {
        self.init(
            audioRelativeIdentifier: recording.audioRelativeIdentifier,
            data: data
        )
    }

    fileprivate init(
        audioRelativeIdentifier: String,
        data: Data
    ) {
        format = audioRelativeIdentifier.hasSuffix(".wav") ? .wav : .m4a
        self.data = data
    }

    public func withAudioData<Result>(
        _ body: (Data) throws -> Result
    ) rethrows -> Result {
        try body(data)
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
    private let acceptedAudioCache: IOSAcceptedAudioCache
    private let audioFileSystem: any IOSV1ForegroundVoiceAudioFileSystem
    private let captureMediaValidator: any IOSV1VoiceCaptureMediaValidating
    private let recordingCachePolicy:
        @Sendable () async -> RecordingCachePolicy
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
        acceptedAudioCache = IOSAcceptedAudioCache(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        audioFileSystem = IOSV1ForegroundVoiceDarwinAudioFileSystem(
            directoryURL: IOSVoiceStateStorageLocation.directoryURL(
                in: applicationSupportDirectoryURL
            )
        )
        captureMediaValidator = IOSV1VoiceCaptureMediaValidator()
        recordingCachePolicy = { .deleteImmediately }
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
        acceptedAudioCache = IOSAcceptedAudioCache(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        audioFileSystem = IOSV1ForegroundVoiceDarwinAudioFileSystem(
            directoryURL: IOSVoiceStateStorageLocation.directoryURL(
                in: applicationSupportDirectoryURL
            )
        )
        captureMediaValidator = IOSV1VoiceCaptureMediaValidator()
        recordingCachePolicy = { .deleteImmediately }
        now = { Date() }
    }

    public init(
        applicationSupportDirectoryURL: URL,
        acceptedTextHistoryRepository: IOSAcceptedTextHistoryRepository,
        acceptedAudioCache: IOSAcceptedAudioCache,
        recordingCachePolicy: @escaping @Sendable () async
            -> RecordingCachePolicy
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
        self.acceptedAudioCache = acceptedAudioCache
        audioFileSystem = IOSV1ForegroundVoiceDarwinAudioFileSystem(
            directoryURL: IOSVoiceStateStorageLocation.directoryURL(
                in: applicationSupportDirectoryURL
            )
        )
        captureMediaValidator = IOSV1VoiceCaptureMediaValidator()
        self.recordingCachePolicy = recordingCachePolicy
        now = { Date() }
    }

    init(
        repository: IOSVoiceStateRepository,
        captureOwner: IOSV1VoiceCaptureOwner,
        historyRepository: IOSAcceptedTextHistoryRepository,
        acceptedAudioCache: IOSAcceptedAudioCache,
        audioFileSystem: any IOSV1ForegroundVoiceAudioFileSystem,
        captureMediaValidator: any IOSV1VoiceCaptureMediaValidating,
        recordingCachePolicy: @escaping @Sendable () async
            -> RecordingCachePolicy = { .deleteImmediately },
        now: @escaping @Sendable () -> Date
    ) {
        self.repository = repository
        self.captureOwner = captureOwner
        self.historyRepository = historyRepository
        self.acceptedAudioCache = acceptedAudioCache
        self.audioFileSystem = audioFileSystem
        self.captureMediaValidator = captureMediaValidator
        self.recordingCachePolicy = recordingCachePolicy
        self.now = now
    }

    public func createCapture(
        attemptID: UUID,
        outputIntent: DictationOutputIntent,
        draftInsertionMode: IOSVoiceDraftInsertionMode = .replace,
        forcesTextCorrection: Bool = false,
        recordingDurationLimit: RecordingDurationLimit = .default
    ) async throws -> IOSV1ForegroundVoiceCaptureLease {
        await acquireOperation()
        defer { releaseOperation() }
        let lease = try await captureOwner.createCapture(
            attemptID: attemptID,
            outputIntent: outputIntent,
            draftInsertionMode: draftInsertionMode,
            forcesTextCorrection: forcesTextCorrection,
            recordingDurationLimit: recordingDurationLimit,
            createdAt: now()
        )
        return IOSV1ForegroundVoiceCaptureLease(
            ownerID: ownerID,
            lease: lease
        )
    }

    public func prepareCompletedCapture(
        _ capture: IOSV1ForegroundVoiceCompletedCapture,
        transcriptionConfiguration: TranscriptionConfiguration,
        acceptedAudioRetention: IOSAcceptedAudioRetention =
            .recordingCachePolicy
    ) async throws -> IOSV1PendingRecording {
        await acquireOperation()
        defer { releaseOperation() }
        guard capture.ownerID == ownerID else {
            throw IOSV1ForegroundVoicePersistenceError.invalidTransition
        }
        let resolvedRetention = IOSAcceptedAudioRetention.resolved(
            requested: acceptedAudioRetention,
            finalizedDurationMilliseconds: capture.durationMilliseconds,
            recordingDurationLimit: capture.recordingDurationLimit
        )
        let promoted: IOSV1PendingRecording
        do {
            promoted = IOSV1PendingRecording(
                try await capture.completed.promote(
                    transcriptionConfiguration: transcriptionConfiguration,
                    acceptedAudioRetention: resolvedRetention
                )
            )
        } catch {
            throw mapRepositoryError(error)
        }
        // The atomic promotion has already committed when `promote` returns.
        // APFS can transiently fail the store's deliberately strict snapshot
        // re-read immediately after rename, so verify the canonical row with a
        // small bounded retry instead of reporting a false local failure.
        var canonical: IOSV1PendingRecording?
        var lastLoadError: Error?
        for attempt in 0..<3 {
            do {
                canonical = try await loadUnlocked()?.recording
                lastLoadError = nil
                break
            } catch {
                lastLoadError = error
                if attempt < 2 {
                    await Task.yield()
                }
            }
        }
        if let lastLoadError {
            throw lastLoadError
        }
        guard let canonical,
              canonical.attemptID == promoted.attemptID,
              canonical.audioRelativeIdentifier
                == promoted.audioRelativeIdentifier,
              canonical.phase == .readyForTranscription,
              canonical.outputIntent == promoted.outputIntent,
              canonical.draftInsertionMode == promoted.draftInsertionMode,
              canonical.forcesTextCorrection
                == promoted.forcesTextCorrection,
              canonical.transcriptionID == nil,
              canonical.transcriptionModel == promoted.transcriptionModel,
              canonical.transcriptionLanguageCode
                == promoted.transcriptionLanguageCode,
              canonical.durationMilliseconds
                == promoted.durationMilliseconds,
              canonical.byteCount == promoted.byteCount,
              canonical.acceptedAudioRetention
                == promoted.acceptedAudioRetention else {
            throw IOSV1ForegroundVoicePersistenceError.localPersistence
        }
        return canonical
    }

    /// Repairs only a raw capture left behind by process loss. The caller must
    /// invoke this at process launch, before ordinary passive reconciliation.
    /// Validation is descriptor-bound and bounded; this method never starts a
    /// provider request and never deletes an invalid or uncertain source.
    public func repairOrphanedCaptureAtProcessLaunch() async
        -> IOSV1ForegroundVoiceCaptureRecoveryObservation? {
        await acquireOperation()
        defer { releaseOperation() }
        return await repairInterruptedCaptureUnlocked(
            reportsAlreadyCompletedCapture: false
        )
    }

    /// Repairs a capture after the live owner has proved that its recorder is
    /// closed and will no longer write. Unlike launch-only recovery, callers
    /// may use this immediately after an involuntary or internal stop so the
    /// positive-byte source becomes a provider-free Saved Recording in the
    /// current process. This method never starts provider work and never
    /// deletes source bytes.
    public func repairInterruptedCaptureAfterRecorderStops() async
        -> IOSV1ForegroundVoiceCaptureRecoveryObservation? {
        await acquireOperation()
        defer { releaseOperation() }
        return await repairInterruptedCaptureUnlocked(
            reportsAlreadyCompletedCapture: true
        )
    }

    private func repairInterruptedCaptureUnlocked(
        reportsAlreadyCompletedCapture: Bool
    ) async -> IOSV1ForegroundVoiceCaptureRecoveryObservation? {
        do {
            let snapshot = try await repository.load()
            guard let capture = snapshot.capture else { return nil }
            switch capture.phase {
            case .recording, .finalizing:
                break
            case .completed:
                guard reportsAlreadyCompletedCapture else { return nil }
                return availability(for: capture) == .available
                    ? .recoverable(attemptID: capture.attemptID)
                    : .blocked
            case .discarding:
                return nil
            }
            let handle: IOSV1ForegroundVoiceAudioHandle
            do {
                guard let opened = try audioFileSystem.openPendingAudio(
                    attemptID: capture.attemptID,
                    relativeIdentifier: capture.audioRelativeIdentifier,
                    expectedByteCount: nil
                ) else {
                    // A missing path does not prove that the canonical source
                    // is an exact zero-byte recording. Keep the durable claim
                    // blocked so a handoff preflight cannot turn uncertainty
                    // into destructive authority.
                    return .blocked
                }
                handle = opened
            } catch IOSV1ForegroundVoicePersistenceError.audioInvalid {
                // A path/identity/shape failure can still hide positive bytes.
                // Only descriptor-proven absence or a successfully opened
                // exact zero-byte source is safe to classify as Discard-only.
                return .blocked
            } catch {
                return .blocked
            }
            defer { audioFileSystem.close(handle) }
            guard handle.byteCount > 0 else {
                return .discardOnly(attemptID: capture.attemptID)
            }
            guard handle.byteCount
                    < IOSV1VoiceCaptureOwner.maximumAudioByteCount else {
                return .blocked
            }
            let duration: Int64
            do {
                let measured = try captureMediaValidator.durationMilliseconds(
                    fileDescriptor: handle.fileDescriptor,
                    byteCount: handle.byteCount,
                    timeoutNanoseconds:
                        IOSV1VoiceCaptureOwner
                            .mediaValidationTimeoutNanoseconds
                )
                duration = measured >= 300
                    && measured <= capture.recordingDurationLimit
                        .maximumFinalizedMediaDurationMilliseconds
                    ? measured : 0
            } catch IOSV1VoiceCaptureError.mediaValidationFailed {
                duration = 0
            } catch IOSV1VoiceCaptureError.mediaValidationTimedOut {
                duration = 0
            } catch {
                return .blocked
            }
            guard try audioFileSystem.read(
                handle,
                atOffset: 0,
                maximumByteCount: 1
            ).count == 1 else {
                return .blocked
            }
            if capture.phase == .recording {
                _ = try await repository.transitionCapture(
                    attemptID: capture.attemptID,
                    to: .finalizing
                )
            }
            _ = try await repository.completeCapture(
                attemptID: capture.attemptID,
                durationMilliseconds: duration,
                byteCount: handle.byteCount
            )
            return .recoverable(attemptID: capture.attemptID)
        } catch {
            return .blocked
        }
    }

    /// Reconciles local capture ownership after process loss. Positive bytes
    /// from Recording or Finalizing are descriptor-validated and promoted to
    /// a provider-free Completed capture. Only an opened exact zero-byte
    /// source is classified Discard-only; uncertainty remains blocked.
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
                return await repairInterruptedCaptureUnlocked(
                    reportsAlreadyCompletedCapture: false
                ) ?? .empty
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
                    acceptedAudioRetention: Self.recoveredAudioRetention(
                        durationMilliseconds:
                            capture.durationMilliseconds ?? 0,
                        recordingDurationLimit:
                            capture.recordingDurationLimit
                    ),
                    initialStatus: .failed
                )
            )
        } catch { throw mapRepositoryError(error) }
    }

    /// Promotes only the exact completed source represented by the current
    /// saved-recording card. A stale UI token cannot recover a replacement.
    public func recoverCapture(
        expected: IOSV1CompletedCaptureRecoveryExpectation,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSV1PendingRecording {
        await acquireOperation()
        defer { releaseOperation() }
        _ = try await requireCompletedCapture(expected)
        do {
            return IOSV1PendingRecording(
                try await repository.promoteCapture(
                    attemptID: expected.attemptID,
                    transcriptionConfiguration: transcriptionConfiguration,
                    acceptedAudioRetention: Self.recoveredAudioRetention(
                        durationMilliseconds:
                            expected.durationMilliseconds,
                        recordingDurationLimit:
                            expected.recordingDurationLimit
                    ),
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

    /// Discards only the exact completed source represented by the current
    /// saved-recording card.
    public func discardCapture(
        expected: IOSV1CompletedCaptureRecoveryExpectation
    ) async throws {
        await acquireOperation()
        defer { releaseOperation() }
        let capture = try await requireCompletedCapture(expected)
        try await discardCaptureUnlocked(capture)
    }

    public func load() async throws -> IOSV1PendingRecordingObservation? {
        await acquireOperation()
        defer { releaseOperation() }
        return try await loadUnlocked()
    }

    /// Loads the single canonical local recording owner. Pending wins once its
    /// atomic promotion commits; otherwise a completed capture remains visible
    /// and recoverable without inventing a second recorder or file owner.
    public func loadSavedRecording() async throws
        -> IOSV1SavedRecordingObservation? {
        await acquireOperation()
        defer { releaseOperation() }
        let snapshot: IOSVoiceStateSnapshot
        do { snapshot = try await repository.load() }
        catch { throw mapRepositoryError(error) }
        if let pending = snapshot.pending {
            let recording = IOSV1PendingRecording(pending)
            return .pending(
                IOSV1PendingRecordingObservation(
                    recording: recording,
                    availability: availability(for: recording)
                )
            )
        }
        guard let capture = snapshot.capture,
              capture.phase == .completed,
              capture.durationMilliseconds != nil,
              capture.byteCount != nil else {
            return nil
        }
        return .completedCapture(
            IOSV1CompletedCaptureRecoveryObservation(
                capture: capture,
                availability: availability(for: capture)
            )
        )
    }

    /// Reads the exact current Pending audio for local playback without
    /// exposing its protected path. Admission is expectation-bound and does
    /// not change phase or authorize provider work.
    public func preparePendingPlaybackAudio(
        expected: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1PendingRecordingPlaybackAudio {
        await acquireOperation()
        defer { releaseOperation() }
        let recording = try await requirePending(expected)
        guard recording.phase != .acceptedCleanup,
              recording.byteCount > 0,
              recording.byteCount < 25_000_000 else {
            throw IOSV1ForegroundVoicePersistenceError.audioInvalid
        }
        guard let handle = try audioFileSystem.openPendingAudio(
            attemptID: recording.attemptID,
            relativeIdentifier: recording.audioRelativeIdentifier,
            expectedByteCount: recording.byteCount
        ) else {
            throw IOSV1ForegroundVoicePersistenceError.audioMissing
        }
        defer { audioFileSystem.close(handle) }

        var data = Data()
        data.reserveCapacity(Int(recording.byteCount))
        var offset: Int64 = 0
        while offset < recording.byteCount {
            try Task.checkCancellation()
            let part = try audioFileSystem.read(
                handle,
                atOffset: offset,
                maximumByteCount:
                    IOSV1PendingTranscriptionAudio.maximumReadByteCount
            )
            guard !part.isEmpty else {
                throw IOSV1ForegroundVoicePersistenceError.audioInvalid
            }
            data.append(part)
            offset += Int64(part.count)
        }
        guard Int64(data.count) == recording.byteCount else {
            throw IOSV1ForegroundVoicePersistenceError.audioInvalid
        }
        return IOSV1PendingRecordingPlaybackAudio(
            recording: recording,
            data: data
        )
    }

    /// Reads the exact completed capture for local playback before Pending
    /// promotion succeeds. This is read-only and never authorizes provider
    /// work.
    public func prepareCompletedCapturePlaybackAudio(
        expected: IOSV1CompletedCaptureRecoveryExpectation
    ) async throws -> IOSV1PendingRecordingPlaybackAudio {
        await acquireOperation()
        defer { releaseOperation() }
        let capture = try await requireCompletedCapture(expected)
        guard let byteCount = capture.byteCount,
              capture.durationMilliseconds != nil,
              byteCount > 0, byteCount < 25_000_000 else {
            throw IOSV1ForegroundVoicePersistenceError.audioInvalid
        }
        guard let handle = try audioFileSystem.openPendingAudio(
            attemptID: capture.attemptID,
            relativeIdentifier: capture.audioRelativeIdentifier,
            expectedByteCount: byteCount
        ) else {
            throw IOSV1ForegroundVoicePersistenceError.audioMissing
        }
        defer { audioFileSystem.close(handle) }

        let data = try readPlaybackData(
            handle: handle,
            expectedByteCount: byteCount
        )
        return IOSV1PendingRecordingPlaybackAudio(
            audioRelativeIdentifier: capture.audioRelativeIdentifier,
            data: data
        )
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
        return try await makeDispatch(
            for: state,
            permitsUnknownDuration: false
        )
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
        return try await makeDispatch(
            for: state,
            permitsUnknownDuration: true
        )
    }

    /// Persists the consent-consumed normalized transcript before correction,
    /// translation, local post-processing, or output delivery may start.
    public func checkpointTranscription(
        expected: IOSV1PendingRecordingExpectation,
        acceptedTranscript: String
    ) async throws -> IOSV1PendingRecording {
        await acquireOperation()
        defer { releaseOperation() }
        let current = try await requirePending(expected)
        guard current.phase == .transcribing,
              let transcriptionID = current.transcriptionID else {
            throw IOSV1ForegroundVoicePersistenceError.invalidTransition
        }
        do {
            return IOSV1PendingRecording(
                try await repository.checkpointTranscription(
                    attemptID: current.attemptID,
                    operationID: transcriptionID,
                    text: acceptedTranscript
                )
            )
        } catch { throw mapRepositoryError(error) }
    }

    public func checkpointPostProcessing(
        expected: IOSV1PendingRecordingExpectation,
        stage: IOSV1PendingTextCheckpointStage,
        text: String
    ) async throws -> IOSV1PendingRecording {
        await acquireOperation()
        defer { releaseOperation() }
        let current = try await requirePending(expected)
        guard current.phase == .postProcessing,
              let operationID = current.transcriptionID,
              current.textCheckpointStage != nil else {
            throw IOSV1ForegroundVoicePersistenceError.invalidTransition
        }
        do {
            return IOSV1PendingRecording(
                try await repository.checkpointPostProcessing(
                    attemptID: current.attemptID,
                    operationID: operationID,
                    stage: stage.repositoryValue,
                    text: text
                )
            )
        } catch { throw mapRepositoryError(error) }
    }

    /// Starts only the downstream pipeline from a durable accepted transcript.
    /// This path cannot create an audio reader or transcription dispatch.
    public func retryPostProcessing(
        expected: IOSV1PendingRecordingExpectation,
        operationID: UUID
    ) async throws -> IOSV1PendingRecording {
        await acquireOperation()
        defer { releaseOperation() }
        let current = try await requirePending(expected)
        guard current.phase == .failed,
              current.acceptedTranscriptionID != nil,
              current.acceptedTranscript != nil else {
            throw IOSV1ForegroundVoicePersistenceError.invalidTransition
        }
        do {
            return IOSV1PendingRecording(
                try await repository.beginPostProcessingRetry(
                    attemptID: current.attemptID,
                    operationID: operationID
                )
            )
        } catch { throw mapRepositoryError(error) }
    }

    public func markOutputDelivery(
        expected: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1PendingRecording {
        try await advance(expected, to: .outputDelivery)
    }

    public func markFailed(
        expected: IOSV1PendingRecordingExpectation,
        transcriptionReplayBlocked: Bool = false
    ) async throws -> IOSV1PendingRecording {
        await acquireOperation()
        defer { releaseOperation() }
        _ = try await requirePending(expected)
        do {
            return IOSV1PendingRecording(
                try await repository.markFailed(
                    attemptID: expected.attemptID,
                    transcriptionReplayBlocked: transcriptionReplayBlocked
                )
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
        guard notice != .historyWriteFailed else {
            // Latest and acceptedCleanup are the durable repair marker until
            // History commits. Never unlink the last playable audio owner on
            // a failed History write.
            return .resultReady(record, notice: notice)
        }
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
            if notice != .historyWriteFailed {
                do {
                    try await finishAcceptedCleanup(
                        pending: IOSV1PendingRecording(state),
                        record: record
                    )
                } catch {
                    notice = Self.addCleanupNotice(to: notice)
                }
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

    public func recoverContainingAppLifecycle(
        _ opportunity: IOSV1ContainingAppRecoveryOpportunity
    ) async -> IOSV1ContainingAppRecoveryDisposition {
        await acquireOperation()
        defer { releaseOperation() }
        do {
            let snapshot: IOSVoiceStateSnapshot
            switch opportunity {
            case .processLaunch:
                snapshot = try await repository.reconcileAfterLaunch()
            case .foregroundOpportunity:
                snapshot = try await repository.load()
            }
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
                guard await appendHistory(record) != .historyWriteFailed else {
                    return .pendingLocalRecovery
                }
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

    private func requireCompletedCapture(
        _ expected: IOSV1CompletedCaptureRecoveryExpectation
    ) async throws -> IOSVoiceStateCapture {
        let snapshot: IOSVoiceStateSnapshot
        do { snapshot = try await repository.load() }
        catch { throw mapRepositoryError(error) }
        guard let capture = snapshot.capture,
              snapshot.pending == nil,
              capture.phase == .completed,
              capture == expected.capture else {
            throw IOSV1ForegroundVoicePersistenceError.stalePending
        }
        return capture
    }

    private func readPlaybackData(
        handle: IOSV1ForegroundVoiceAudioHandle,
        expectedByteCount: Int64
    ) throws -> Data {
        var data = Data()
        data.reserveCapacity(Int(expectedByteCount))
        var offset: Int64 = 0
        while offset < expectedByteCount {
            try Task.checkCancellation()
            let part = try audioFileSystem.read(
                handle,
                atOffset: offset,
                maximumByteCount:
                    IOSV1PendingTranscriptionAudio.maximumReadByteCount
            )
            guard !part.isEmpty else {
                throw IOSV1ForegroundVoicePersistenceError.audioInvalid
            }
            data.append(part)
            offset += Int64(part.count)
        }
        guard Int64(data.count) == expectedByteCount else {
            throw IOSV1ForegroundVoicePersistenceError.audioInvalid
        }
        return data
    }

    private func makeDispatch(
        for state: IOSVoiceStatePending,
        permitsUnknownDuration: Bool
    ) async throws -> IOSV1ForegroundVoiceTranscriptionDispatch {
        let recording = IOSV1PendingRecording(state)
        do {
            let hasAdmissibleDuration = recording.durationMilliseconds > 0
                && recording.durationMilliseconds
                    <= RecordingDurationLimit
                        .maximumSupportedFinalizedMediaDurationMilliseconds
            let isExplicitUnknownDurationAttempt = permitsUnknownDuration
                && recording.durationMilliseconds == 0
            guard hasAdmissibleDuration
                    || isExplicitUnknownDurationAttempt else {
                throw IOSV1ForegroundVoicePersistenceError.audioInvalid
            }
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

    private func availability(
        for capture: IOSVoiceStateCapture
    ) -> IOSV1PendingRecordingAvailability {
        guard capture.phase == .completed,
              let byteCount = capture.byteCount else {
            return .invalid
        }
        do {
            guard let handle = try audioFileSystem.openPendingAudio(
                attemptID: capture.attemptID,
                relativeIdentifier: capture.audioRelativeIdentifier,
                expectedByteCount: byteCount
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
        try await retainAcceptedAudioIfNeeded(
            pending: pending,
            record: record
        )
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

    private func retainAcceptedAudioIfNeeded(
        pending: IOSV1PendingRecording,
        record: IOSV1AcceptedOutputDeliveryRecord
    ) async throws {
        let policy = (await recordingCachePolicy()).normalized
        let mustSaveRecording = pending.acceptedAudioRetention
            == .savedFiveMinute
        guard mustSaveRecording || policy.keepsRecordings else {
            do {
                try await acceptedAudioCache.reconcile(policy: policy)
            } catch is IOSAcceptedAudioCacheError {
                // Recording Cache is optional and cannot invalidate acceptance.
            }
            return
        }
        let fileExtension = pending.audioRelativeIdentifier.hasSuffix(".wav")
            ? "wav" : "m4a"
        if mustSaveRecording {
            do {
                if try await acceptedAudioCache.savedAudioFileURLIfAvailable(
                    resultID: record.resultID,
                    fileExtension: fileExtension,
                    byteCount: pending.byteCount
                ) != nil {
                    // The exact bounded Saved Recording already owns these
                    // bytes. A prior pass may have unlinked Pending before its
                    // final metadata write failed. Reconciliation is still a
                    // required part of publish: the first write may have
                    // succeeded before pruning an older entry failed.
                    try await acceptedAudioCache.reconcile(policy: policy)
                    guard try await acceptedAudioCache
                        .savedAudioFileURLIfAvailable(
                            resultID: record.resultID,
                            fileExtension: fileExtension,
                            byteCount: pending.byteCount
                        ) != nil else {
                        throw IOSAcceptedAudioCacheError.storageUnavailable
                    }
                    return
                }
            } catch is IOSAcceptedAudioCacheError {
                throw IOSV1ForegroundVoicePersistenceError.localPersistence
            }
        }
        guard let handle = try audioFileSystem.openPendingAudio(
            attemptID: pending.attemptID,
            relativeIdentifier: pending.audioRelativeIdentifier,
            expectedByteCount: pending.byteCount
        ) else {
            if mustSaveRecording {
                throw IOSV1ForegroundVoicePersistenceError.audioMissing
            }
            do {
                try await acceptedAudioCache.reconcile(policy: policy)
            } catch is IOSAcceptedAudioCacheError {
                // A missing optional cache never owns Pending cleanup.
            }
            return
        }
        defer { audioFileSystem.close(handle) }

        var data = Data()
        data.reserveCapacity(Int(handle.byteCount))
        var offset: Int64 = 0
        while offset < handle.byteCount {
            let part = try audioFileSystem.read(
                handle,
                atOffset: offset,
                maximumByteCount:
                    IOSV1PendingTranscriptionAudio.maximumReadByteCount
            )
            guard !part.isEmpty else {
                throw IOSV1ForegroundVoicePersistenceError.audioInvalid
            }
            data.append(part)
            offset += Int64(part.count)
        }
        guard Int64(data.count) == handle.byteCount else {
            throw IOSV1ForegroundVoicePersistenceError.audioInvalid
        }
        do {
            _ = try await acceptedAudioCache.retainAcceptedAudio(
                data,
                resultID: record.resultID,
                fileExtension: fileExtension,
                createdAt: record.createdAt,
                policy: policy,
                retention: pending.acceptedAudioRetention
            )
        } catch is IOSAcceptedAudioCacheError {
            if mustSaveRecording {
                throw IOSV1ForegroundVoicePersistenceError.localPersistence
            }
            // Optional policy-managed playback cannot invalidate acceptance.
        }
    }

    private static func recoveredAudioRetention(
        durationMilliseconds: Int64,
        recordingDurationLimit: RecordingDurationLimit
    ) -> IOSAcceptedAudioRetention {
        // Unknown recovery may be the exact limit-ended recording whose media
        // metadata probe failed. Preserve it conservatively after acceptance;
        // bounded Saved Recordings, not an optional cache policy, owns it.
        if durationMilliseconds == 0 { return .savedFiveMinute }
        return IOSAcceptedAudioRetention.resolved(
            requested: .recordingCachePolicy,
            finalizedDurationMilliseconds: durationMilliseconds,
            recordingDurationLimit: recordingDurationLimit
        )
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
