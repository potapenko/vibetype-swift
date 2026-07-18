import Foundation
import HoldTypeDomain

enum IOSVoiceStateRepositoryError: Error, Equatable, Sendable {
    case readFailed
    case sourceTooLarge
    case malformedData
    case unsupportedSchemaVersion
    case invalidRecord
    case pendingSlotOccupied
    case stalePending
    case invalidTransition
    case invalidAcceptedText
    case writeFailed
}

/// One bounded atomic owner for the V1.1 Pending and Latest Result metadata.
/// Audio ownership is represented by the exact relative identifier, while the
/// capture/audio boundary owns descriptor validation and physical removal.
actor IOSVoiceStateRepository {
    static let maximumByteCount = 256 * 1_024

    private static let filePolicy = ProtectedAtomicMetadataFilePolicy(
        maximumByteCount: maximumByteCount,
        fileProtection: .complete,
        excludesFromBackup: true
    )

    private let fileURL: URL
    private let fileSystem: any ProtectedAtomicMetadataFileSystem
    private let now: @Sendable () -> Date

    init(applicationSupportDirectoryURL: URL) {
        fileURL = IOSVoiceStateStorageLocation.fileURL(
            in: applicationSupportDirectoryURL
        )
        fileSystem = FoundationProtectedAtomicMetadataFileSystem()
        now = { Date() }
    }

    init(
        fileURL: URL,
        fileSystem: any ProtectedAtomicMetadataFileSystem =
            FoundationProtectedAtomicMetadataFileSystem(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.fileSystem = fileSystem
        self.now = now
    }

    func load() throws -> IOSVoiceStateSnapshot {
        let data: Data?
        do {
            data = try fileSystem.readFileIfPresent(
                at: fileURL,
                policy: Self.filePolicy
            )
        } catch ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded {
            throw IOSVoiceStateRepositoryError.sourceTooLarge
        } catch {
            throw IOSVoiceStateRepositoryError.readFailed
        }
        guard let data else { return .empty }
        return try IOSVoiceStateWireCodec.decode(
            data,
            maximumInputByteCount: Self.maximumByteCount
        )
    }

    @discardableResult
    func installPending(
        _ pending: IOSVoiceStatePending
    ) throws -> IOSVoiceStateSnapshot {
        var snapshot = try load()
        guard snapshot.capture == nil, snapshot.pending == nil else {
            throw IOSVoiceStateRepositoryError.pendingSlotOccupied
        }
        snapshot.pending = pending
        try replace(snapshot)
        return snapshot
    }

    @discardableResult
    func installCapture(
        _ capture: IOSVoiceStateCapture
    ) throws -> IOSVoiceStateSnapshot {
        var snapshot = try load()
        guard snapshot.capture == nil, snapshot.pending == nil else {
            throw IOSVoiceStateRepositoryError.pendingSlotOccupied
        }
        snapshot.capture = capture
        try replace(snapshot)
        return snapshot
    }

    @discardableResult
    func transitionCapture(
        attemptID: UUID,
        to phase: IOSVoiceStateCapturePhase
    ) throws -> IOSVoiceStateCapture {
        var snapshot = try load()
        guard let capture = snapshot.capture,
              capture.attemptID == attemptID else {
            throw IOSVoiceStateRepositoryError.stalePending
        }
        let isAllowed: Bool
        switch (capture.phase, phase) {
        case (.recording, .finalizing),
             (.recording, .discarding),
             (.finalizing, .discarding),
             (.completed, .discarding):
            isAllowed = true
        default:
            isAllowed = capture.phase == phase
        }
        guard isAllowed else {
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        if capture.phase == phase { return capture }
        let updated = try capture.replacing(phase: phase)
        snapshot.capture = updated
        try replace(snapshot)
        return updated
    }

    @discardableResult
    func completeCapture(
        attemptID: UUID,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) throws -> IOSVoiceStateCapture {
        var snapshot = try load()
        guard let capture = snapshot.capture,
              capture.attemptID == attemptID,
              capture.phase == .finalizing else {
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        let completed = try capture.replacing(
            phase: .completed,
            durationMilliseconds: durationMilliseconds,
            byteCount: byteCount
        )
        snapshot.capture = completed
        try replace(snapshot)
        return completed
    }

    @discardableResult
    func promoteCapture(
        attemptID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration,
        acceptedAudioRetention: IOSAcceptedAudioRetention =
            .recordingCachePolicy,
        initialStatus: IOSVoiceStatePendingStatus = .ready
    ) throws -> IOSVoiceStatePending {
        var snapshot = try load()
        guard snapshot.pending == nil,
              let capture = snapshot.capture,
              capture.attemptID == attemptID,
              capture.phase == .completed,
              let durationMilliseconds = capture.durationMilliseconds,
              let byteCount = capture.byteCount,
              !transcriptionConfiguration.customLanguageCodeValidation
                .isInvalid else {
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        switch initialStatus {
        case .ready, .failed:
            break
        case .processing, .acceptedCleanup:
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        let pending = try IOSVoiceStatePending(
            attemptID: capture.attemptID,
            audioRelativeIdentifier: capture.audioRelativeIdentifier,
            createdAt: capture.createdAt,
            updatedAt: mutationDate(after: capture.createdAt),
            outputIntent: capture.outputIntent,
            draftInsertionMode: capture.draftInsertionMode,
            forcesTextCorrection: capture.forcesTextCorrection,
            transcriptionModel: transcriptionConfiguration.resolvedModel,
            transcriptionLanguageCode:
                transcriptionConfiguration.resolvedLanguageCode,
            durationMilliseconds: durationMilliseconds,
            byteCount: byteCount,
            acceptedAudioRetention: acceptedAudioRetention,
            status: initialStatus
        )
        snapshot.capture = nil
        snapshot.pending = pending
        try replace(snapshot)
        return pending
    }

    @discardableResult
    func clearCapture(
        attemptID: UUID
    ) throws -> IOSVoiceStateMutationResult {
        var snapshot = try load()
        guard let capture = snapshot.capture else {
            return .unchanged(snapshot)
        }
        guard capture.attemptID == attemptID else {
            throw IOSVoiceStateRepositoryError.stalePending
        }
        guard capture.phase == .discarding else {
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        snapshot.capture = nil
        try replace(snapshot)
        return .changed(snapshot)
    }

    func mutationDate(after prior: Date) -> Date {
        let candidate = now()
        return candidate >= prior ? candidate : prior
    }

    func replace(_ snapshot: IOSVoiceStateSnapshot) throws {
        let data = try IOSVoiceStateWireCodec.encode(snapshot)
        guard data.count <= Self.maximumByteCount else {
            throw IOSVoiceStateRepositoryError.writeFailed
        }
        do {
            try fileSystem.replaceFileAtomically(
                at: fileURL,
                with: data,
                policy: Self.filePolicy
            )
        } catch {
            throw IOSVoiceStateRepositoryError.writeFailed
        }
    }
}
