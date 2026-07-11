import Foundation
import HoldTypeDomain

public enum IOSPendingRecordingAudioFormat: CaseIterable, Equatable, Sendable {
    case m4a
    case wav

    var fileExtension: String {
        switch self {
        case .m4a:
            "m4a"
        case .wav:
            "wav"
        }
    }

    init?(sourceURL: URL) {
        switch sourceURL.pathExtension {
        case "m4a":
            self = .m4a
        case "wav":
            self = .wav
        default:
            return nil
        }
    }
}

public enum IOSPendingRecordingPhase: Equatable, Sendable {
    case readyForTranscription
    case awaitingRecovery
    case transcribing
    case postProcessing
    case outputDelivery

    var requiresTranscriptionID: Bool {
        switch self {
        case .readyForTranscription, .awaitingRecovery:
            false
        case .transcribing, .postProcessing, .outputDelivery:
            true
        }
    }
}

public enum IOSPendingRecordingInitialState: Equatable, Sendable {
    case readyForTranscription
    case awaitingRecovery

    var phase: IOSPendingRecordingPhase {
        switch self {
        case .readyForTranscription:
            .readyForTranscription
        case .awaitingRecovery:
            .awaitingRecovery
        }
    }
}

public struct IOSPendingRecordingPreparation: Equatable, Sendable {
    public let attemptID: UUID
    public let sourceArtifact: AudioRecordingArtifact
    public let initialState: IOSPendingRecordingInitialState
    public let outputIntent: DictationOutputIntent
    public let audioFormat: IOSPendingRecordingAudioFormat
    public let transcriptionModel: String
    public let transcriptionLanguageCode: String?
    public let durationMilliseconds: Int64
    public let byteCount: Int64

    public init(
        attemptID: UUID,
        sourceArtifact: AudioRecordingArtifact,
        initialState: IOSPendingRecordingInitialState,
        outputIntent: DictationOutputIntent,
        transcriptionConfiguration: TranscriptionConfiguration
    ) throws {
        guard !transcriptionConfiguration.customLanguageCodeValidation.isInvalid else {
            throw IOSPendingRecordingError.invalidTranscriptionConfiguration
        }
        guard sourceArtifact.fileURL.isFileURL,
              !sourceArtifact.fileURL.path.isEmpty,
              !sourceArtifact.fileURL.path.utf8.contains(0),
              let audioFormat = IOSPendingRecordingAudioFormat(
            sourceURL: sourceArtifact.fileURL
        ) else {
            throw IOSPendingRecordingError.invalidSourceArtifact
        }
        let durationMilliseconds = try IOSPendingRecordingValidation
            .durationMilliseconds(from: sourceArtifact.duration)
        let model = transcriptionConfiguration.resolvedModel
        let languageCode = transcriptionConfiguration.resolvedLanguageCode
        guard IOSPendingRecordingValidation.isValidModel(model),
              IOSPendingRecordingValidation.isValidLanguageCode(languageCode),
              IOSPendingRecordingValidation.isValidByteCount(
                  sourceArtifact.byteCount
              ) else {
            throw IOSPendingRecordingError.invalidSourceArtifact
        }

        self.attemptID = attemptID
        self.sourceArtifact = sourceArtifact
        self.initialState = initialState
        self.outputIntent = outputIntent
        self.audioFormat = audioFormat
        self.transcriptionModel = model
        self.transcriptionLanguageCode = languageCode
        self.durationMilliseconds = durationMilliseconds
        self.byteCount = sourceArtifact.byteCount
    }
}

extension IOSPendingRecordingPreparation: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSPendingRecordingPreparation(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { IOSPendingRecordingRedaction.mirror(of: self) }
}

public struct IOSPendingRecording: Equatable, Sendable {
    public let attemptID: UUID
    public let audioRelativeIdentifier: String
    public let createdAt: Date
    public let updatedAt: Date
    public let phase: IOSPendingRecordingPhase
    public let outputIntent: DictationOutputIntent
    public let transcriptionID: UUID?
    public let transcriptionModel: String
    public let transcriptionLanguageCode: String?
    public let durationMilliseconds: Int64
    public let byteCount: Int64

    init(
        attemptID: UUID,
        audioRelativeIdentifier: String,
        createdAt: Date,
        updatedAt: Date,
        phase: IOSPendingRecordingPhase,
        outputIntent: DictationOutputIntent,
        transcriptionID: UUID?,
        transcriptionModel: String,
        transcriptionLanguageCode: String?,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) throws {
        guard createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt >= createdAt,
              phase.requiresTranscriptionID == (transcriptionID != nil),
              IOSPendingRecordingValidation.isValidModel(transcriptionModel),
              IOSPendingRecordingValidation.isValidLanguageCode(
                  transcriptionLanguageCode
              ),
              IOSPendingRecordingValidation.isValidDurationMilliseconds(
                  durationMilliseconds
              ),
              IOSPendingRecordingValidation.isValidByteCount(byteCount),
              let parsed = IOSPendingRecordingStorageLocation
                  .parseRelativeAudioIdentifier(audioRelativeIdentifier),
              parsed.attemptID == attemptID else {
            throw IOSPendingRecordingError.invalidJournal
        }

        self.attemptID = attemptID
        self.audioRelativeIdentifier = audioRelativeIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.phase = phase
        self.outputIntent = outputIntent
        self.transcriptionID = transcriptionID
        self.transcriptionModel = transcriptionModel
        self.transcriptionLanguageCode = transcriptionLanguageCode
        self.durationMilliseconds = durationMilliseconds
        self.byteCount = byteCount
    }

    var audioFormat: IOSPendingRecordingAudioFormat {
        // Construction validates this exact grammar.
        audioRelativeIdentifier.hasSuffix(".m4a") ? .m4a : .wav
    }
}

extension IOSPendingRecording: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSPendingRecording(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { IOSPendingRecordingRedaction.mirror(of: self) }
}

public struct IOSPendingRecordingCASExpectation: Equatable, Sendable {
    public let attemptID: UUID
    public let phase: IOSPendingRecordingPhase
    public let transcriptionID: UUID?

    public init(recording: IOSPendingRecording) {
        attemptID = recording.attemptID
        phase = recording.phase
        transcriptionID = recording.transcriptionID
    }
}

extension IOSPendingRecordingCASExpectation: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSPendingRecordingCASExpectation(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { IOSPendingRecordingRedaction.mirror(of: self) }
}

public enum IOSPendingRecordingAvailability: Equatable, Sendable {
    case available
    case temporarilyUnavailable
    case missing
    case invalid
}

public struct IOSPendingRecordingObservation: Equatable, Sendable {
    public let recording: IOSPendingRecording
    public let availability: IOSPendingRecordingAvailability

    init(
        recording: IOSPendingRecording,
        availability: IOSPendingRecordingAvailability
    ) {
        self.recording = recording
        self.availability = availability
    }

    public var expectation: IOSPendingRecordingCASExpectation {
        IOSPendingRecordingCASExpectation(recording: recording)
    }
}

public enum IOSPendingRecordingDiscardResult: Equatable, Sendable {
    case discarded
    case alreadyAbsent
}

extension IOSPendingRecordingObservation: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSPendingRecordingObservation(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { IOSPendingRecordingRedaction.mirror(of: self) }
}

struct IOSPendingTranscriptionDispatch: Equatable, Sendable {
    let recording: IOSPendingRecording
    let audioArtifact: AudioRecordingArtifact

    init(
        recording: IOSPendingRecording,
        audioArtifact: AudioRecordingArtifact
    ) {
        self.recording = recording
        self.audioArtifact = audioArtifact
    }
}

extension IOSPendingTranscriptionDispatch: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSPendingTranscriptionDispatch(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { IOSPendingRecordingRedaction.mirror(of: self) }
}

/// Containing-app provider boundary for one registered pending transcription.
/// Implementations must issue at most one request and honor task cancellation.
public protocol IOSPendingTranscriptionExecutor: Sendable {
    func transcribe(
        recording: IOSPendingRecording,
        audioArtifact: AudioRecordingArtifact
    ) async throws -> String
}

/// One process-local dispatch authorization. It cannot be reconstructed from disk.
public final class IOSPendingTranscriptionHandoff: @unchecked Sendable {
    private let dispatch: IOSPendingTranscriptionDispatch
    private let authorization: IOSPendingTranscriptionAuthorization

    init(
        dispatch: IOSPendingTranscriptionDispatch,
        authorization: IOSPendingTranscriptionAuthorization =
            IOSPendingTranscriptionAuthorization()
    ) {
        self.dispatch = dispatch
        self.authorization = authorization
    }

    /// Runs one provider operation only after its cancellable task is registered.
    /// No detached provider-capable dispatch escapes this boundary.
    public func execute(
        using executor: any IOSPendingTranscriptionExecutor
    ) async throws -> String {
        guard let reservation = authorization.reserve() else {
            throw IOSPendingRecordingError.dispatchAlreadyCommitted
        }
        guard !Task.isCancelled else {
            authorization.cancel(reservation)
            throw CancellationError()
        }

        let task = Task<String, Error> { [dispatch] in
            try await reservation.waitForLaunch()
            try Task.checkCancellation()
            return try await executor.transcribe(
                recording: dispatch.recording,
                audioArtifact: dispatch.audioArtifact
            )
        }
        guard authorization.activate(
            reservation,
            cancellation: { task.cancel() }
        ) else {
            task.cancel()
            reservation.cancel()
            _ = await task.result
            throw IOSPendingRecordingError.dispatchAlreadyCommitted
        }

        if Task.isCancelled {
            authorization.cancel(reservation)
        } else {
            reservation.launch()
        }

        return try await withTaskCancellationHandler {
            let result = await task.result
            guard authorization.finish(reservation) else {
                throw CancellationError()
            }
            return try result.get()
        } onCancel: {
            authorization.cancel(reservation)
        }
    }
}

final class IOSPendingTranscriptionReservation: @unchecked Sendable {
    private enum PermitState {
        case pending
        case waiting(CheckedContinuation<Void, Error>)
        case launched
        case cancelled
    }

    private let lock = NSLock()
    private var state = PermitState.pending

    func waitForLaunch() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let immediateResult: Result<Void, Error>? = lock.withLock {
                switch state {
                case .pending:
                    state = .waiting(continuation)
                    return nil
                case .waiting:
                    preconditionFailure("Launch permit has only one waiter")
                case .launched:
                    return .success(())
                case .cancelled:
                    return .failure(CancellationError())
                }
            }
            if let immediateResult {
                continuation.resume(with: immediateResult)
            }
        }
    }

    func launch() {
        let continuation: CheckedContinuation<Void, Error>? = lock.withLock {
            switch state {
            case .pending:
                state = .launched
                return nil
            case .waiting(let continuation):
                state = .launched
                return continuation
            case .launched, .cancelled:
                return nil
            }
        }
        continuation?.resume()
    }

    func cancel() {
        let continuation: CheckedContinuation<Void, Error>? = lock.withLock {
            switch state {
            case .pending:
                state = .cancelled
                return nil
            case .waiting(let continuation):
                state = .cancelled
                return continuation
            case .launched, .cancelled:
                return nil
            }
        }
        continuation?.resume(throwing: CancellationError())
    }
}

final class IOSPendingTranscriptionAuthorization: @unchecked Sendable {
    private enum State {
        case available
        case reserved(IOSPendingTranscriptionReservation)
        case running(
            IOSPendingTranscriptionReservation,
            cancellation: @Sendable () -> Void
        )
        case retired
    }

    private let lock = NSLock()
    private var state = State.available

    func reserve() -> IOSPendingTranscriptionReservation? {
        lock.withLock {
            guard case .available = state else {
                return nil
            }
            let reservation = IOSPendingTranscriptionReservation()
            state = .reserved(reservation)
            return reservation
        }
    }

    func activate(
        _ reservation: IOSPendingTranscriptionReservation,
        cancellation: @escaping @Sendable () -> Void
    ) -> Bool {
        lock.withLock {
            guard case .reserved(let current) = state,
                  current === reservation else {
                return false
            }
            state = .running(reservation, cancellation: cancellation)
            return true
        }
    }

    func finish(_ reservation: IOSPendingTranscriptionReservation) -> Bool {
        lock.withLock {
            if case .running(let current, _) = state,
               current === reservation {
                state = .retired
                return true
            }
            return false
        }
    }

    func cancel(_ reservation: IOSPendingTranscriptionReservation) {
        let cancellation: (@Sendable () -> Void)? = lock.withLock {
            switch state {
            case .reserved(let current) where current === reservation:
                state = .retired
                return { reservation.cancel() }
            case .running(let current, let cancel) where current === reservation:
                state = .retired
                return {
                    reservation.cancel()
                    cancel()
                }
            case .available, .reserved, .running, .retired:
                return nil
            }
        }
        cancellation?()
    }

    func retireAndCancel() {
        let cancellation: (@Sendable () -> Void)? = lock.withLock {
            switch state {
            case .available:
                state = .retired
                return nil
            case .reserved(let reservation):
                state = .retired
                return { reservation.cancel() }
            case .running(let reservation, let cancel):
                state = .retired
                return {
                    reservation.cancel()
                    cancel()
                }
            case .retired:
                return nil
            }
        }
        cancellation?()
    }
}

extension IOSPendingTranscriptionHandoff: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSPendingTranscriptionHandoff(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { IOSPendingRecordingRedaction.mirror(of: self) }
}

public enum IOSPendingRecordingError: Error, Equatable, Sendable {
    case cancelledBeforeOperation
    case reentrantOperation
    case pendingSlotOccupied
    case orphanedAudio
    case journalUnreadable
    case journalTooLarge
    case journalMalformed
    case unsupportedJournalVersion
    case invalidJournal
    case invalidSourceArtifact
    case invalidTranscriptionConfiguration
    case sourceUnavailable
    case sourceChanged
    case protectedAudioConflict
    case audioPublicationFailed
    case audioPublicationTimedOut
    case mediaValidationFailed
    case mediaValidationTimedOut
    case dataProtectionUnavailable
    case linkedAudioMissing
    case linkedAudioInvalid
    case journalWriteFailed
    case journalCommitUncertain
    case audioRemoveFailed
    case journalRemoveFailed
    case compareAndSwapFailed
    case invalidTransition
    case dispatchAlreadyCommitted
    case destinationInspectionFailed
}

extension IOSPendingRecordingError: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSPendingRecordingError(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { IOSPendingRecordingRedaction.mirror(of: self) }
}

enum IOSPendingRecordingValidation {
    static let maximumAudioByteCountExclusive: Int64 = 25_000_000
    static let maximumDurationMillisecondsExclusive: Int64 = 300_000
    static let maximumModelByteCount =
        IOSAcceptedOutputDeliveryValidation.maximumModelByteCount

    static func durationMilliseconds(from duration: TimeInterval) throws -> Int64 {
        guard duration.isFinite,
              duration > 0,
              duration < TimeInterval(maximumDurationMillisecondsExclusive) / 1_000 else {
            throw IOSPendingRecordingError.invalidSourceArtifact
        }
        let milliseconds = duration * 1_000
        guard milliseconds.isFinite,
              milliseconds >= TimeInterval(Int64.min),
              milliseconds <= TimeInterval(Int64.max) else {
            throw IOSPendingRecordingError.invalidSourceArtifact
        }
        let rounded = Int64(milliseconds.rounded(.toNearestOrAwayFromZero))
        guard isValidDurationMilliseconds(rounded) else {
            throw IOSPendingRecordingError.invalidSourceArtifact
        }
        return rounded
    }

    static func isValidDurationMilliseconds(_ value: Int64) -> Bool {
        value > 0 && value < maximumDurationMillisecondsExclusive
    }

    static func isValidByteCount(_ value: Int64) -> Bool {
        value > 0 && value < maximumAudioByteCountExclusive
    }

    static func isValidModel(_ value: String) -> Bool {
        guard let normalized = IOSAcceptedOutputDeliveryValidation
            .normalizedMetadataText(value) else {
            return false
        }
        return value.utf8.count <= maximumModelByteCount
            && IOSAcceptedOutputDeliveryValidation.bytesEqual(
                normalized,
                value
            )
    }

    static func isValidLanguageCode(_ value: String?) -> Bool {
        guard let value else {
            return true
        }
        guard value.count == 2 || value.count == 3 else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (97...122).contains(scalar.value)
        }
    }
}

private enum IOSPendingRecordingRedaction {
    static func mirror(of value: Any) -> Mirror {
        Mirror(value, children: ["state": "redacted"])
    }
}
