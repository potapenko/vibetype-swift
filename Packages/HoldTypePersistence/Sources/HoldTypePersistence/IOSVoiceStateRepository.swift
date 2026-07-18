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

private enum IOSVoiceStateWireCodec {
    private static let schemaVersion = 5
    private static let rootKeys: Set<String> = [
        "schemaVersion", "capture", "pending", "latest",
    ]
    private static let captureV1Keys: Set<String> = [
        "attemptID", "audioRelativeIdentifier", "createdAtMilliseconds",
        "outputIntent", "phase", "durationMilliseconds", "byteCount",
    ]
    private static let captureV2Keys = captureV1Keys.union([
        "draftInsertionMode", "forcesTextCorrection",
    ])
    private static let captureKeys = captureV2Keys.union([
        "recordingDurationLimitMinutes",
    ])
    private static let pendingV1Keys: Set<String> = [
        "attemptID", "audioRelativeIdentifier", "createdAtMilliseconds",
        "updatedAtMilliseconds", "outputIntent", "transcriptionModel",
        "transcriptionLanguageCode", "durationMilliseconds", "byteCount",
        "status",
    ]
    private static let pendingV2Keys = pendingV1Keys.union([
        "draftInsertionMode", "forcesTextCorrection",
    ])
    private static let pendingV3Keys = pendingV2Keys.union([
        "acceptedAudioRetention",
    ])
    private static let pendingKeys = pendingV3Keys.union([
        "acceptedTranscriptionID", "acceptedTranscript", "checkpointStage",
        "checkpointText", "transcriptionReplayBlocked",
    ])
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
        guard (1...schemaVersion).contains(version) else {
            throw IOSVoiceStateRepositoryError.unsupportedSchemaVersion
        }
        let captureValidationKeys: Set<String> = switch version {
        case 1: captureV1Keys
        case 2...4: captureV2Keys
        default: captureKeys
        }
        try validateOptionalObject(
            object["capture"],
            keys: captureValidationKeys
        )
        let pendingValidationKeys: Set<String> = switch version {
        case 1: pendingV1Keys
        case 2: pendingV2Keys
        case 3: pendingV3Keys
        default: pendingKeys
        }
        try validateOptionalObject(
            object["pending"],
            keys: pendingValidationKeys,
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
        guard (1...schemaVersion).contains(wire.schemaVersion) else {
            throw IOSVoiceStateRepositoryError.unsupportedSchemaVersion
        }
        do {
            let snapshot = IOSVoiceStateSnapshot(
                capture: try wire.capture?.value(
                    schemaVersion: wire.schemaVersion
                ),
                pending: try wire.pending?.value(
                    schemaVersion: wire.schemaVersion
                ),
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
        let draftInsertionMode: String?
        let forcesTextCorrection: Bool?
        let recordingDurationLimitMinutes: Int?
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
            draftInsertionMode = capture.draftInsertionMode.rawValue
            forcesTextCorrection = capture.forcesTextCorrection
            recordingDurationLimitMinutes = capture.recordingDurationLimit.minutes
            phase = capture.phase.rawValue
            durationMilliseconds = capture.durationMilliseconds
            byteCount = capture.byteCount
        }

        func value(schemaVersion: Int) throws -> IOSVoiceStateCapture {
            guard let identifier = UUID(uuidString: attemptID),
                  identifier.uuidString == attemptID,
                  let output = DictationOutputIntent(rawValue: outputIntent),
                  let phase = IOSVoiceStateCapturePhase(rawValue: phase) else {
                throw IOSVoiceStateRepositoryError.invalidRecord
            }
            let insertionMode: IOSVoiceDraftInsertionMode
            let correction: Bool
            if schemaVersion == 1 {
                insertionMode = .append
                correction = false
            } else {
                guard let rawMode = draftInsertionMode,
                      let mode = IOSVoiceDraftInsertionMode(
                          rawValue: rawMode
                      ),
                      let forcesTextCorrection else {
                    throw IOSVoiceStateRepositoryError.invalidRecord
                }
                insertionMode = mode
                correction = forcesTextCorrection
            }
            let recordingDurationLimit: RecordingDurationLimit
            if schemaVersion < 5 {
                recordingDurationLimit = .default
            } else {
                guard
                    let recordingDurationLimitMinutes,
                    let value = RecordingDurationLimit(
                        validatingMinutes: recordingDurationLimitMinutes
                    )
                else {
                    throw IOSVoiceStateRepositoryError.invalidRecord
                }
                recordingDurationLimit = value
            }
            return try IOSVoiceStateCapture(
                attemptID: identifier,
                audioRelativeIdentifier: audioRelativeIdentifier,
                createdAt: IOSVoiceStateValidation.date(
                    from: createdAtMilliseconds
                ),
                outputIntent: output,
                draftInsertionMode: insertionMode,
                forcesTextCorrection: correction,
                recordingDurationLimit: recordingDurationLimit,
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
            case draftInsertionMode
            case forcesTextCorrection
            case recordingDurationLimitMinutes
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
            try container.encode(
                draftInsertionMode,
                forKey: .draftInsertionMode
            )
            try container.encode(
                forcesTextCorrection,
                forKey: .forcesTextCorrection
            )
            try container.encode(
                recordingDurationLimitMinutes,
                forKey: .recordingDurationLimitMinutes
            )
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
        let draftInsertionMode: String?
        let forcesTextCorrection: Bool?
        let transcriptionModel: String
        let transcriptionLanguageCode: String?
        let durationMilliseconds: Int64
        let byteCount: Int64
        let acceptedAudioRetention: String?
        let acceptedTranscriptionID: String?
        let acceptedTranscript: String?
        let checkpointStage: String?
        let checkpointText: String?
        let transcriptionReplayBlocked: Bool?
        let status: StatusWire

        private enum CodingKeys: String, CodingKey {
            case attemptID
            case audioRelativeIdentifier
            case createdAtMilliseconds
            case updatedAtMilliseconds
            case outputIntent
            case draftInsertionMode
            case forcesTextCorrection
            case transcriptionModel
            case transcriptionLanguageCode
            case durationMilliseconds
            case byteCount
            case acceptedAudioRetention
            case acceptedTranscriptionID
            case acceptedTranscript
            case checkpointStage
            case checkpointText
            case transcriptionReplayBlocked
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
            draftInsertionMode = pending.draftInsertionMode.rawValue
            forcesTextCorrection = pending.forcesTextCorrection
            transcriptionModel = pending.transcriptionModel
            transcriptionLanguageCode = pending.transcriptionLanguageCode
            durationMilliseconds = pending.durationMilliseconds
            byteCount = pending.byteCount
            acceptedAudioRetention = pending.acceptedAudioRetention.rawValue
            acceptedTranscriptionID = pending.transcriptionCheckpoint?
                .operationID.uuidString
            acceptedTranscript = pending.transcriptionCheckpoint?
                .acceptedTranscript
            checkpointStage = pending.transcriptionCheckpoint?.stage.rawValue
            checkpointText = pending.transcriptionCheckpoint?.text
            transcriptionReplayBlocked = pending.transcriptionReplayBlocked
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
                draftInsertionMode,
                forKey: .draftInsertionMode
            )
            try container.encode(
                forcesTextCorrection,
                forKey: .forcesTextCorrection
            )
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
            try container.encode(
                acceptedAudioRetention,
                forKey: .acceptedAudioRetention
            )
            if let acceptedTranscriptionID {
                try container.encode(
                    acceptedTranscriptionID,
                    forKey: .acceptedTranscriptionID
                )
            } else {
                try container.encodeNil(forKey: .acceptedTranscriptionID)
            }
            if let acceptedTranscript {
                try container.encode(
                    acceptedTranscript,
                    forKey: .acceptedTranscript
                )
            } else {
                try container.encodeNil(forKey: .acceptedTranscript)
            }
            if let checkpointStage {
                try container.encode(
                    checkpointStage,
                    forKey: .checkpointStage
                )
            } else {
                try container.encodeNil(forKey: .checkpointStage)
            }
            if let checkpointText {
                try container.encode(checkpointText, forKey: .checkpointText)
            } else {
                try container.encodeNil(forKey: .checkpointText)
            }
            try container.encode(
                transcriptionReplayBlocked,
                forKey: .transcriptionReplayBlocked
            )
            try container.encode(status, forKey: .status)
        }

        func value(schemaVersion: Int) throws -> IOSVoiceStatePending {
            guard let attemptID = UUID(uuidString: attemptID),
                  attemptID.uuidString == self.attemptID,
                  let outputIntent = DictationOutputIntent(
                      rawValue: outputIntent
                  ) else {
                throw IOSVoiceStateRepositoryError.invalidRecord
            }
            let insertionMode: IOSVoiceDraftInsertionMode
            let correction: Bool
            let retention: IOSAcceptedAudioRetention
            if schemaVersion == 1 {
                insertionMode = .append
                correction = false
            } else {
                guard let rawMode = draftInsertionMode,
                      let mode = IOSVoiceDraftInsertionMode(
                          rawValue: rawMode
                      ),
                      let forcesTextCorrection else {
                    throw IOSVoiceStateRepositoryError.invalidRecord
                }
                insertionMode = mode
                correction = forcesTextCorrection
            }
            if schemaVersion < 3 {
                retention = .recordingCachePolicy
            } else {
                guard let rawRetention = acceptedAudioRetention,
                      let decodedRetention = IOSAcceptedAudioRetention(
                          rawValue: rawRetention
                      ) else {
                    throw IOSVoiceStateRepositoryError.invalidRecord
                }
                retention = decodedRetention
            }
            let checkpoint: IOSVoiceStateTranscriptionCheckpoint?
            let replayBlocked: Bool
            if schemaVersion < 4 {
                checkpoint = nil
                replayBlocked = false
            } else {
                guard let transcriptionReplayBlocked else {
                    throw IOSVoiceStateRepositoryError.invalidRecord
                }
                replayBlocked = transcriptionReplayBlocked
                switch (
                    acceptedTranscriptionID,
                    acceptedTranscript,
                    checkpointStage,
                    checkpointText
                ) {
                case (nil, nil, nil, nil):
                    checkpoint = nil
                case (
                    .some(let rawIdentifier),
                    .some(let acceptedTranscript),
                    .some(let rawStage),
                    .some(let text)
                ):
                    guard let identifier = UUID(uuidString: rawIdentifier),
                          identifier.uuidString == rawIdentifier,
                          let stage = IOSVoiceStateTextCheckpointStage(
                              rawValue: rawStage
                          ) else {
                        throw IOSVoiceStateRepositoryError.invalidRecord
                    }
                    checkpoint = try IOSVoiceStateTranscriptionCheckpoint(
                        operationID: identifier,
                        acceptedTranscript: acceptedTranscript,
                        stage: stage,
                        text: text
                    )
                default:
                    throw IOSVoiceStateRepositoryError.invalidRecord
                }
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
                draftInsertionMode: insertionMode,
                forcesTextCorrection: correction,
                transcriptionModel: transcriptionModel,
                transcriptionLanguageCode: transcriptionLanguageCode,
                durationMilliseconds: durationMilliseconds,
                byteCount: byteCount,
                acceptedAudioRetention: retention,
                transcriptionReplayBlocked: replayBlocked,
                transcriptionCheckpoint: checkpoint,
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
