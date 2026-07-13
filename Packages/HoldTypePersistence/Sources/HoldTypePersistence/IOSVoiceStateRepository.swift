import CoreFoundation
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

enum IOSVoiceStateProcessingStage: String, Equatable, Sendable {
    case transcription
    case postProcessing
    case outputDelivery
}

struct IOSVoiceStateAcceptedResult: Equatable, Sendable {
    let resultID: UUID
    let sourceAttemptID: UUID
    let text: String
    let createdAt: Date
}

enum IOSVoiceStatePendingStatus: Equatable, Sendable {
    case ready
    case processing(IOSVoiceStateProcessingStage, operationID: UUID)
    case failed
    case acceptedCleanup(IOSVoiceStateAcceptedResult)
}

enum IOSVoiceStateCapturePhase: String, Equatable, Sendable {
    case recording
    case finalizing
    case completed
    case discarding
}

struct IOSVoiceStateCapture: Equatable, Sendable {
    let attemptID: UUID
    let audioRelativeIdentifier: String
    let createdAt: Date
    let outputIntent: DictationOutputIntent
    let phase: IOSVoiceStateCapturePhase
    let durationMilliseconds: Int64?
    let byteCount: Int64?

    init(
        attemptID: UUID,
        audioRelativeIdentifier: String,
        createdAt: Date,
        outputIntent: DictationOutputIntent,
        phase: IOSVoiceStateCapturePhase,
        durationMilliseconds: Int64? = nil,
        byteCount: Int64? = nil
    ) throws {
        let hasCompletion = durationMilliseconds != nil || byteCount != nil
        guard IOSVoiceStateValidation.isCanonicalCaptureAudioIdentifier(
                  audioRelativeIdentifier,
                  attemptID: attemptID
              ),
              IOSVoiceStateValidation.isValidDate(createdAt),
              (phase == .completed) == hasCompletion,
              (durationMilliseconds == nil && byteCount == nil)
                || ((durationMilliseconds ?? 0) > 0
                    && (durationMilliseconds ?? 0) < 300_000
                    && (byteCount ?? 0) > 0
                    && (byteCount ?? 0) < 25_000_000) else {
            throw IOSVoiceStateRepositoryError.invalidRecord
        }
        self.attemptID = attemptID
        self.audioRelativeIdentifier = audioRelativeIdentifier
        self.createdAt = createdAt
        self.outputIntent = outputIntent
        self.phase = phase
        self.durationMilliseconds = durationMilliseconds
        self.byteCount = byteCount
    }

    func replacing(
        phase: IOSVoiceStateCapturePhase,
        durationMilliseconds: Int64? = nil,
        byteCount: Int64? = nil
    ) throws -> Self {
        try Self(
            attemptID: attemptID,
            audioRelativeIdentifier: audioRelativeIdentifier,
            createdAt: createdAt,
            outputIntent: outputIntent,
            phase: phase,
            durationMilliseconds: durationMilliseconds,
            byteCount: byteCount
        )
    }
}

struct IOSVoiceStatePending: Equatable, Sendable {
    let attemptID: UUID
    let audioRelativeIdentifier: String
    let createdAt: Date
    let updatedAt: Date
    let outputIntent: DictationOutputIntent
    let transcriptionModel: String
    let transcriptionLanguageCode: String?
    let durationMilliseconds: Int64
    let byteCount: Int64
    let status: IOSVoiceStatePendingStatus

    init(
        attemptID: UUID,
        audioRelativeIdentifier: String,
        createdAt: Date,
        updatedAt: Date,
        outputIntent: DictationOutputIntent,
        transcriptionModel: String,
        transcriptionLanguageCode: String?,
        durationMilliseconds: Int64,
        byteCount: Int64,
        status: IOSVoiceStatePendingStatus
    ) throws {
        guard IOSVoiceStateValidation.isCanonicalRelativeAudioIdentifier(
                  audioRelativeIdentifier,
                  attemptID: attemptID
              ),
              IOSVoiceStateValidation.isValidDate(createdAt),
              IOSVoiceStateValidation.isValidDate(updatedAt),
              updatedAt >= createdAt,
              IOSVoiceStateValidation.isValidModel(transcriptionModel),
              IOSVoiceStateValidation.isValidLanguageCode(
                  transcriptionLanguageCode
              ),
              durationMilliseconds > 0,
              durationMilliseconds < 300_000,
              byteCount > 0,
              byteCount < 25_000_000 else {
            throw IOSVoiceStateRepositoryError.invalidRecord
        }
        if case .acceptedCleanup(let accepted) = status {
            guard accepted.sourceAttemptID == attemptID else {
                throw IOSVoiceStateRepositoryError.invalidRecord
            }
        }

        self.attemptID = attemptID
        self.audioRelativeIdentifier = audioRelativeIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.outputIntent = outputIntent
        self.transcriptionModel = transcriptionModel
        self.transcriptionLanguageCode = transcriptionLanguageCode
        self.durationMilliseconds = durationMilliseconds
        self.byteCount = byteCount
        self.status = status
    }

    func replacing(
        status: IOSVoiceStatePendingStatus,
        updatedAt: Date
    ) throws -> Self {
        try Self(
            attemptID: attemptID,
            audioRelativeIdentifier: audioRelativeIdentifier,
            createdAt: createdAt,
            updatedAt: updatedAt,
            outputIntent: outputIntent,
            transcriptionModel: transcriptionModel,
            transcriptionLanguageCode: transcriptionLanguageCode,
            durationMilliseconds: durationMilliseconds,
            byteCount: byteCount,
            status: status
        )
    }
}

struct IOSVoiceStateLatest: Equatable, Sendable {
    let resultID: UUID
    let sourceAttemptID: UUID
    let text: String
    let createdAt: Date

    init(
        resultID: UUID,
        sourceAttemptID: UUID,
        text: String,
        createdAt: Date
    ) throws {
        guard IOSVoiceStateValidation.isStoredText(text),
              IOSVoiceStateValidation.isValidDate(createdAt) else {
            throw IOSVoiceStateRepositoryError.invalidAcceptedText
        }
        self.resultID = resultID
        self.sourceAttemptID = sourceAttemptID
        self.text = text
        self.createdAt = createdAt
    }
}

struct IOSVoiceStateSnapshot: Equatable, Sendable {
    var capture: IOSVoiceStateCapture?
    var pending: IOSVoiceStatePending?
    var latest: IOSVoiceStateLatest?

    static let empty = Self(capture: nil, pending: nil, latest: nil)
}

enum IOSVoiceStateMutationResult: Equatable, Sendable {
    case changed(IOSVoiceStateSnapshot)
    case unchanged(IOSVoiceStateSnapshot)
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
            transcriptionModel: transcriptionConfiguration.resolvedModel,
            transcriptionLanguageCode:
                transcriptionConfiguration.resolvedLanguageCode,
            durationMilliseconds: durationMilliseconds,
            byteCount: byteCount,
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

    @discardableResult
    func beginProcessing(
        attemptID: UUID,
        operationID: UUID,
        stage: IOSVoiceStateProcessingStage = .transcription,
        allowFailed: Bool
    ) throws -> IOSVoiceStatePending {
        var snapshot = try load()
        let pending = try requirePending(attemptID, in: snapshot)
        switch pending.status {
        case .ready where !allowFailed,
             .failed where allowFailed:
            break
        case .ready, .failed, .processing, .acceptedCleanup:
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        let updated = try pending.replacing(
            status: .processing(stage, operationID: operationID),
            updatedAt: mutationDate(after: pending.updatedAt)
        )
        snapshot.pending = updated
        try replace(snapshot)
        return updated
    }

    @discardableResult
    func advanceProcessing(
        attemptID: UUID,
        operationID: UUID,
        to stage: IOSVoiceStateProcessingStage
    ) throws -> IOSVoiceStatePending {
        var snapshot = try load()
        let pending = try requirePending(attemptID, in: snapshot)
        guard case .processing(_, let currentOperationID) = pending.status,
              currentOperationID == operationID else {
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        let updated = try pending.replacing(
            status: .processing(stage, operationID: operationID),
            updatedAt: mutationDate(after: pending.updatedAt)
        )
        snapshot.pending = updated
        try replace(snapshot)
        return updated
    }

    @discardableResult
    func markFailed(
        attemptID: UUID
    ) throws -> IOSVoiceStatePending {
        var snapshot = try load()
        let pending = try requirePending(attemptID, in: snapshot)
        switch pending.status {
        case .ready, .processing, .failed:
            break
        case .acceptedCleanup:
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        if pending.status == .failed { return pending }
        let updated = try pending.replacing(
            status: .failed,
            updatedAt: mutationDate(after: pending.updatedAt)
        )
        snapshot.pending = updated
        try replace(snapshot)
        return updated
    }

    /// Commits Latest and the accepted-cleanup owner in one atomic replacement.
    @discardableResult
    func commitAccepted(
        attemptID: UUID,
        resultID: UUID,
        text: String,
        createdAt: Date
    ) throws -> IOSVoiceStateAcceptedResult {
        var snapshot = try load()
        let pending = try requirePending(attemptID, in: snapshot)
        let latest = try IOSVoiceStateLatest(
            resultID: resultID,
            sourceAttemptID: attemptID,
            text: text,
            createdAt: createdAt
        )
        let accepted = IOSVoiceStateAcceptedResult(
            resultID: resultID,
            sourceAttemptID: attemptID,
            text: latest.text,
            createdAt: latest.createdAt
        )
        if case .acceptedCleanup(let current) = pending.status {
            guard current == accepted, snapshot.latest == latest else {
                throw IOSVoiceStateRepositoryError.invalidTransition
            }
            return current
        }
        guard case .processing(.outputDelivery, _) = pending.status else {
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        snapshot.latest = latest
        snapshot.pending = try pending.replacing(
            status: .acceptedCleanup(accepted),
            updatedAt: mutationDate(after: pending.updatedAt)
        )
        try replace(snapshot)
        return accepted
    }

    @discardableResult
    func finishAcceptedCleanup(
        attemptID: UUID,
        resultID: UUID
    ) throws -> IOSVoiceStateMutationResult {
        var snapshot = try load()
        guard let pending = snapshot.pending else {
            return .unchanged(snapshot)
        }
        guard pending.attemptID == attemptID,
              case .acceptedCleanup(let accepted) = pending.status,
              accepted.resultID == resultID else {
            throw IOSVoiceStateRepositoryError.stalePending
        }
        snapshot.pending = nil
        try replace(snapshot)
        return .changed(snapshot)
    }

    @discardableResult
    func discardPending(
        attemptID: UUID
    ) throws -> IOSVoiceStateMutationResult {
        var snapshot = try load()
        guard let pending = snapshot.pending else {
            return .unchanged(snapshot)
        }
        guard pending.attemptID == attemptID else {
            throw IOSVoiceStateRepositoryError.stalePending
        }
        guard case .acceptedCleanup = pending.status else {
            snapshot.pending = nil
            try replace(snapshot)
            return .changed(snapshot)
        }
        throw IOSVoiceStateRepositoryError.invalidTransition
    }

    @discardableResult
    func clearLatest(
        resultID: UUID
    ) throws -> IOSVoiceStateMutationResult {
        var snapshot = try load()
        guard let latest = snapshot.latest else {
            return .unchanged(snapshot)
        }
        guard latest.resultID == resultID else {
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        snapshot.latest = nil
        try replace(snapshot)
        return .changed(snapshot)
    }

    /// Relaunch performs only local state repair; it never owns provider work.
    @discardableResult
    func reconcileAfterLaunch() throws -> IOSVoiceStateSnapshot {
        var snapshot = try load()
        guard let pending = snapshot.pending,
              case .processing = pending.status else {
            return snapshot
        }
        snapshot.pending = try pending.replacing(
            status: .failed,
            updatedAt: mutationDate(after: pending.updatedAt)
        )
        try replace(snapshot)
        return snapshot
    }

    private func requirePending(
        _ attemptID: UUID,
        in snapshot: IOSVoiceStateSnapshot
    ) throws -> IOSVoiceStatePending {
        guard let pending = snapshot.pending,
              pending.attemptID == attemptID else {
            throw IOSVoiceStateRepositoryError.stalePending
        }
        return pending
    }

    private func mutationDate(after prior: Date) -> Date {
        let candidate = now()
        return candidate >= prior ? candidate : prior
    }

    private func replace(_ snapshot: IOSVoiceStateSnapshot) throws {
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

enum IOSVoiceStateStorageLocation {
    static let rootDirectoryName = "HoldType"
    static let voiceStateDirectoryName = "VoiceState"
    static let recordFileName = "ios-v1-voice-state.json"
    static let audioFilePrefix = "pending-v1-"

    static func directoryURL(in applicationSupportDirectoryURL: URL) -> URL {
        applicationSupportDirectoryURL
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
            .appendingPathComponent(voiceStateDirectoryName, isDirectory: true)
    }

    static func fileURL(in applicationSupportDirectoryURL: URL) -> URL {
        directoryURL(in: applicationSupportDirectoryURL)
            .appendingPathComponent(recordFileName, isDirectory: false)
    }

    static func relativeAudioIdentifier(
        for attemptID: UUID,
        extension fileExtension: String = "m4a"
    ) -> String {
        voiceStateDirectoryName + "/" + audioFilePrefix
            + attemptID.uuidString.lowercased() + "." + fileExtension
    }

    static func audioFileURL(
        for attemptID: UUID,
        extension fileExtension: String = "m4a",
        in applicationSupportDirectoryURL: URL
    ) -> URL {
        directoryURL(in: applicationSupportDirectoryURL)
            .appendingPathComponent(
                audioFilePrefix + attemptID.uuidString.lowercased()
                    + "." + fileExtension,
                isDirectory: false
            )
    }
}

private enum IOSVoiceStateValidation {
    static func isCanonicalCaptureAudioIdentifier(
        _ value: String,
        attemptID: UUID
    ) -> Bool {
        isCanonicalRelativeAudioIdentifier(value, attemptID: attemptID)
    }

    static func isCanonicalRelativeAudioIdentifier(
        _ value: String,
        attemptID: UUID
    ) -> Bool {
        value == IOSVoiceStateStorageLocation.relativeAudioIdentifier(
            for: attemptID
        ) || value == IOSVoiceStateStorageLocation.relativeAudioIdentifier(
            for: attemptID,
            extension: "wav"
        )
    }

    static func isValidDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite
            && date.timeIntervalSince1970 >= 0
    }

    static func isValidModel(_ model: String) -> Bool {
        !model.isEmpty && model.utf8.count <= 256
            && model == model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidLanguageCode(_ code: String?) -> Bool {
        guard let code else { return true }
        guard code.count == 2 || code.count == 3 else { return false }
        return code.unicodeScalars.allSatisfy {
            $0.isASCII && (97...122).contains($0.value)
        }
    }

    static func isStoredText(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 1_000_000
            && text == text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func milliseconds(from date: Date) throws -> Int64 {
        guard isValidDate(date) else {
            throw IOSVoiceStateRepositoryError.invalidRecord
        }
        let value = date.timeIntervalSince1970 * 1_000
        guard value.isFinite,
              value >= 0,
              value <= Double(Int64.max) else {
            throw IOSVoiceStateRepositoryError.invalidRecord
        }
        return Int64(value.rounded(.toNearestOrAwayFromZero))
    }

    static func date(from milliseconds: Int64) throws -> Date {
        guard milliseconds >= 0 else {
            throw IOSVoiceStateRepositoryError.invalidRecord
        }
        let date = Date(
            timeIntervalSince1970: Double(milliseconds) / 1_000
        )
        guard try self.milliseconds(from: date) == milliseconds else {
            throw IOSVoiceStateRepositoryError.invalidRecord
        }
        return date
    }
}

private enum IOSVoiceStateWireCodec {
    private static let schemaVersion = 1
    private static let rootKeys: Set<String> = [
        "schemaVersion", "capture", "pending", "latest",
    ]
    private static let captureKeys: Set<String> = [
        "attemptID", "audioRelativeIdentifier", "createdAtMilliseconds",
        "outputIntent", "phase", "durationMilliseconds", "byteCount",
    ]
    private static let pendingKeys: Set<String> = [
        "attemptID", "audioRelativeIdentifier", "createdAtMilliseconds",
        "updatedAtMilliseconds", "outputIntent", "transcriptionModel",
        "transcriptionLanguageCode", "durationMilliseconds", "byteCount",
        "status",
    ]
    private static let statusKeys: Set<String> = [
        "kind", "stage", "operationID", "accepted",
    ]
    private static let resultKeys: Set<String> = [
        "resultID", "sourceAttemptID", "text", "createdAtMilliseconds",
    ]

    static func encode(_ snapshot: IOSVoiceStateSnapshot) throws -> Data {
        let wire = try RecordWire(
            schemaVersion: schemaVersion,
            capture: snapshot.capture.map(CaptureWire.init),
            pending: snapshot.pending.map(PendingWire.init),
            latest: snapshot.latest.map(ResultWire.init)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(wire)
        } catch {
            throw IOSVoiceStateRepositoryError.writeFailed
        }
    }

    static func decode(
        _ data: Data,
        maximumInputByteCount: Int
    ) throws -> IOSVoiceStateSnapshot {
        do {
            try BoundedJSONMemberValidator.validate(
                data,
                limits: .metadataFile(
                    maximumInputByteCount: maximumInputByteCount
                )
            )
        } catch BoundedJSONMemberValidationError.inputTooLarge {
            throw IOSVoiceStateRepositoryError.sourceTooLarge
        } catch {
            throw IOSVoiceStateRepositoryError.malformedData
        }

        let object: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            ) as? [String: Any] else {
                throw IOSVoiceStateRepositoryError.malformedData
            }
            object = decoded
        } catch let error as IOSVoiceStateRepositoryError {
            throw error
        } catch {
            throw IOSVoiceStateRepositoryError.malformedData
        }
        guard Set(object.keys) == rootKeys else {
            throw IOSVoiceStateRepositoryError.invalidRecord
        }
        let version = try integer(object["schemaVersion"])
        guard version == schemaVersion else {
            throw IOSVoiceStateRepositoryError.unsupportedSchemaVersion
        }
        try validateOptionalObject(
            object["capture"],
            keys: captureKeys
        )
        try validateOptionalObject(
            object["pending"],
            keys: pendingKeys,
            nested: { pending in
                try validateOptionalObject(
                    pending["status"],
                    keys: statusKeys,
                    nested: { status in
                        try validateOptionalObject(
                            status["accepted"],
                            keys: resultKeys
                        )
                    }
                )
            }
        )
        try validateOptionalObject(object["latest"], keys: resultKeys)

        let decoder = JSONDecoder()
        let wire: RecordWire
        do {
            wire = try decoder.decode(RecordWire.self, from: data)
        } catch {
            throw IOSVoiceStateRepositoryError.invalidRecord
        }
        guard wire.schemaVersion == schemaVersion else {
            throw IOSVoiceStateRepositoryError.unsupportedSchemaVersion
        }
        do {
            let snapshot = IOSVoiceStateSnapshot(
                capture: try wire.capture?.value(),
                pending: try wire.pending?.value(),
                latest: try wire.latest?.latestValue()
            )
            guard snapshot.capture == nil || snapshot.pending == nil else {
                throw IOSVoiceStateRepositoryError.invalidRecord
            }
            return snapshot
        } catch let error as IOSVoiceStateRepositoryError {
            throw error
        } catch {
            throw IOSVoiceStateRepositoryError.invalidRecord
        }
    }

    private static func validateOptionalObject(
        _ value: Any?,
        keys: Set<String>,
        nested: (([String: Any]) throws -> Void)? = nil
    ) throws {
        guard let value, !(value is NSNull) else { return }
        guard let object = value as? [String: Any],
              Set(object.keys) == keys else {
            throw IOSVoiceStateRepositoryError.invalidRecord
        }
        try nested?(object)
    }

    private static func integer(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: number.objCType)),
              let integer = Int(number.stringValue) else {
            throw IOSVoiceStateRepositoryError.invalidRecord
        }
        return integer
    }

    private struct RecordWire: Codable {
        let schemaVersion: Int
        let capture: CaptureWire?
        let pending: PendingWire?
        let latest: ResultWire?

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case capture
            case pending
            case latest
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            if let capture {
                try container.encode(capture, forKey: .capture)
            } else {
                try container.encodeNil(forKey: .capture)
            }
            if let pending {
                try container.encode(pending, forKey: .pending)
            } else {
                try container.encodeNil(forKey: .pending)
            }
            if let latest {
                try container.encode(latest, forKey: .latest)
            } else {
                try container.encodeNil(forKey: .latest)
            }
        }
    }

    private struct CaptureWire: Codable {
        let attemptID: String
        let audioRelativeIdentifier: String
        let createdAtMilliseconds: Int64
        let outputIntent: String
        let phase: String
        let durationMilliseconds: Int64?
        let byteCount: Int64?

        init(_ capture: IOSVoiceStateCapture) throws {
            attemptID = capture.attemptID.uuidString
            audioRelativeIdentifier = capture.audioRelativeIdentifier
            createdAtMilliseconds = try IOSVoiceStateValidation.milliseconds(
                from: capture.createdAt
            )
            outputIntent = capture.outputIntent.rawValue
            phase = capture.phase.rawValue
            durationMilliseconds = capture.durationMilliseconds
            byteCount = capture.byteCount
        }

        func value() throws -> IOSVoiceStateCapture {
            guard let identifier = UUID(uuidString: attemptID),
                  identifier.uuidString == attemptID,
                  let output = DictationOutputIntent(rawValue: outputIntent),
                  let phase = IOSVoiceStateCapturePhase(rawValue: phase) else {
                throw IOSVoiceStateRepositoryError.invalidRecord
            }
            return try IOSVoiceStateCapture(
                attemptID: identifier,
                audioRelativeIdentifier: audioRelativeIdentifier,
                createdAt: IOSVoiceStateValidation.date(
                    from: createdAtMilliseconds
                ),
                outputIntent: output,
                phase: phase,
                durationMilliseconds: durationMilliseconds,
                byteCount: byteCount
            )
        }

        private enum CodingKeys: String, CodingKey {
            case attemptID
            case audioRelativeIdentifier
            case createdAtMilliseconds
            case outputIntent
            case phase
            case durationMilliseconds
            case byteCount
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(attemptID, forKey: .attemptID)
            try container.encode(
                audioRelativeIdentifier,
                forKey: .audioRelativeIdentifier
            )
            try container.encode(
                createdAtMilliseconds,
                forKey: .createdAtMilliseconds
            )
            try container.encode(outputIntent, forKey: .outputIntent)
            try container.encode(phase, forKey: .phase)
            if let durationMilliseconds {
                try container.encode(
                    durationMilliseconds,
                    forKey: .durationMilliseconds
                )
            } else {
                try container.encodeNil(forKey: .durationMilliseconds)
            }
            if let byteCount {
                try container.encode(byteCount, forKey: .byteCount)
            } else {
                try container.encodeNil(forKey: .byteCount)
            }
        }
    }

    private struct PendingWire: Codable {
        let attemptID: String
        let audioRelativeIdentifier: String
        let createdAtMilliseconds: Int64
        let updatedAtMilliseconds: Int64
        let outputIntent: String
        let transcriptionModel: String
        let transcriptionLanguageCode: String?
        let durationMilliseconds: Int64
        let byteCount: Int64
        let status: StatusWire

        private enum CodingKeys: String, CodingKey {
            case attemptID
            case audioRelativeIdentifier
            case createdAtMilliseconds
            case updatedAtMilliseconds
            case outputIntent
            case transcriptionModel
            case transcriptionLanguageCode
            case durationMilliseconds
            case byteCount
            case status
        }

        init(_ pending: IOSVoiceStatePending) throws {
            attemptID = pending.attemptID.uuidString
            audioRelativeIdentifier = pending.audioRelativeIdentifier
            createdAtMilliseconds = try IOSVoiceStateValidation.milliseconds(
                from: pending.createdAt
            )
            updatedAtMilliseconds = try IOSVoiceStateValidation.milliseconds(
                from: pending.updatedAt
            )
            outputIntent = pending.outputIntent.rawValue
            transcriptionModel = pending.transcriptionModel
            transcriptionLanguageCode = pending.transcriptionLanguageCode
            durationMilliseconds = pending.durationMilliseconds
            byteCount = pending.byteCount
            status = try StatusWire(pending.status)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(attemptID, forKey: .attemptID)
            try container.encode(
                audioRelativeIdentifier,
                forKey: .audioRelativeIdentifier
            )
            try container.encode(
                createdAtMilliseconds,
                forKey: .createdAtMilliseconds
            )
            try container.encode(
                updatedAtMilliseconds,
                forKey: .updatedAtMilliseconds
            )
            try container.encode(outputIntent, forKey: .outputIntent)
            try container.encode(
                transcriptionModel,
                forKey: .transcriptionModel
            )
            if let transcriptionLanguageCode {
                try container.encode(
                    transcriptionLanguageCode,
                    forKey: .transcriptionLanguageCode
                )
            } else {
                try container.encodeNil(forKey: .transcriptionLanguageCode)
            }
            try container.encode(
                durationMilliseconds,
                forKey: .durationMilliseconds
            )
            try container.encode(byteCount, forKey: .byteCount)
            try container.encode(status, forKey: .status)
        }

        func value() throws -> IOSVoiceStatePending {
            guard let attemptID = UUID(uuidString: attemptID),
                  attemptID.uuidString == self.attemptID,
                  let outputIntent = DictationOutputIntent(
                      rawValue: outputIntent
                  ) else {
                throw IOSVoiceStateRepositoryError.invalidRecord
            }
            return try IOSVoiceStatePending(
                attemptID: attemptID,
                audioRelativeIdentifier: audioRelativeIdentifier,
                createdAt: IOSVoiceStateValidation.date(
                    from: createdAtMilliseconds
                ),
                updatedAt: IOSVoiceStateValidation.date(
                    from: updatedAtMilliseconds
                ),
                outputIntent: outputIntent,
                transcriptionModel: transcriptionModel,
                transcriptionLanguageCode: transcriptionLanguageCode,
                durationMilliseconds: durationMilliseconds,
                byteCount: byteCount,
                status: try status.value(attemptID: attemptID)
            )
        }
    }

    private struct StatusWire: Codable {
        let kind: String
        let stage: String?
        let operationID: String?
        let accepted: ResultWire?

        private enum CodingKeys: String, CodingKey {
            case kind
            case stage
            case operationID
            case accepted
        }

        init(_ status: IOSVoiceStatePendingStatus) throws {
            switch status {
            case .ready:
                kind = "ready"
                stage = nil
                operationID = nil
                accepted = nil
            case .processing(let stageValue, let identifier):
                kind = "processing"
                stage = stageValue.rawValue
                operationID = identifier.uuidString
                accepted = nil
            case .failed:
                kind = "failed"
                stage = nil
                operationID = nil
                accepted = nil
            case .acceptedCleanup(let result):
                kind = "acceptedCleanup"
                stage = nil
                operationID = nil
                accepted = try ResultWire(result)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            if let stage {
                try container.encode(stage, forKey: .stage)
            } else {
                try container.encodeNil(forKey: .stage)
            }
            if let operationID {
                try container.encode(operationID, forKey: .operationID)
            } else {
                try container.encodeNil(forKey: .operationID)
            }
            if let accepted {
                try container.encode(accepted, forKey: .accepted)
            } else {
                try container.encodeNil(forKey: .accepted)
            }
        }

        func value(attemptID: UUID) throws -> IOSVoiceStatePendingStatus {
            switch kind {
            case "ready":
                guard stage == nil, operationID == nil, accepted == nil else {
                    throw IOSVoiceStateRepositoryError.invalidRecord
                }
                return .ready
            case "processing":
                guard let stage,
                      let processingStage = IOSVoiceStateProcessingStage(
                          rawValue: stage
                      ),
                      let operationID,
                      let identifier = UUID(uuidString: operationID),
                      identifier.uuidString == operationID,
                      accepted == nil else {
                    throw IOSVoiceStateRepositoryError.invalidRecord
                }
                return .processing(processingStage, operationID: identifier)
            case "failed":
                guard stage == nil, operationID == nil, accepted == nil else {
                    throw IOSVoiceStateRepositoryError.invalidRecord
                }
                return .failed
            case "acceptedCleanup":
                guard stage == nil, operationID == nil,
                      let accepted else {
                    throw IOSVoiceStateRepositoryError.invalidRecord
                }
                let result = try accepted.acceptedValue()
                guard result.sourceAttemptID == attemptID else {
                    throw IOSVoiceStateRepositoryError.invalidRecord
                }
                return .acceptedCleanup(result)
            default:
                throw IOSVoiceStateRepositoryError.invalidRecord
            }
        }
    }

    private struct ResultWire: Codable {
        let resultID: String
        let sourceAttemptID: String
        let text: String
        let createdAtMilliseconds: Int64

        init(_ latest: IOSVoiceStateLatest) throws {
            resultID = latest.resultID.uuidString
            sourceAttemptID = latest.sourceAttemptID.uuidString
            text = latest.text
            createdAtMilliseconds = try IOSVoiceStateValidation.milliseconds(
                from: latest.createdAt
            )
        }

        init(_ result: IOSVoiceStateAcceptedResult) throws {
            resultID = result.resultID.uuidString
            sourceAttemptID = result.sourceAttemptID.uuidString
            text = result.text
            createdAtMilliseconds = try IOSVoiceStateValidation.milliseconds(
                from: result.createdAt
            )
        }

        func latestValue() throws -> IOSVoiceStateLatest {
            let values = try commonValues()
            return try IOSVoiceStateLatest(
                resultID: values.resultID,
                sourceAttemptID: values.sourceAttemptID,
                text: text,
                createdAt: values.createdAt
            )
        }

        func acceptedValue() throws -> IOSVoiceStateAcceptedResult {
            let values = try commonValues()
            guard IOSVoiceStateValidation.isStoredText(text) else {
                throw IOSVoiceStateRepositoryError.invalidAcceptedText
            }
            return IOSVoiceStateAcceptedResult(
                resultID: values.resultID,
                sourceAttemptID: values.sourceAttemptID,
                text: text,
                createdAt: values.createdAt
            )
        }

        private func commonValues() throws -> (
            resultID: UUID,
            sourceAttemptID: UUID,
            createdAt: Date
        ) {
            guard let resultID = UUID(uuidString: resultID),
                  resultID.uuidString == self.resultID,
                  let sourceAttemptID = UUID(uuidString: sourceAttemptID),
                  sourceAttemptID.uuidString == self.sourceAttemptID else {
                throw IOSVoiceStateRepositoryError.invalidRecord
            }
            return (
                resultID,
                sourceAttemptID,
                try IOSVoiceStateValidation.date(
                    from: createdAtMilliseconds
                )
            )
        }
    }
}

extension IOSVoiceStatePending: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSVoiceStatePending(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSVoiceStateLatest: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSVoiceStateLatest(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
