import CoreFoundation
import Foundation

enum IOSVoiceStateWireCodec {
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
}
