import CoreFoundation
import Foundation
import HoldTypeDomain

private let iosAppSettingsCurrentSchemaVersion = 3

enum IOSAppSettingsWireCodec {
    private static let supportedSchemaVersions: Set<Int> = [
        1,
        2,
        iosAppSettingsCurrentSchemaVersion,
    ]
    private static let rootFields: Set<String> = [
        "schemaVersion",
        "transcription",
        "textCorrection",
        "localTextCleanupEnabled",
        "translation",
        "recordingCache",
        // Tolerated only so V1 settings decode after the always-on Latest cutover.
        "keepLatestResult",
        "voice",
    ]
    private static let transcriptionFields: Set<String> = [
        "model",
        "language",
        "customLanguageCode",
        "prompt",
    ]
    private static let textCorrectionFields: Set<String> = [
        "isEnabled",
        "modelPreset",
        "customModel",
        "prompt",
    ]
    private static let translationFields: Set<String> = [
        "actionPreferenceEnabled",
        "sourceMode",
        "sourceLanguage",
        "customSourceLanguageCode",
        "targetLanguage",
        "customTargetLanguageCode",
        "model",
        "prompt",
    ]
    private static let legacyVoiceFields: Set<String> = [
        "audioCuesEnabled",
        "recordingStopTailDuration",
    ]
    private static let voiceFields = legacyVoiceFields.union([
        "recordingDurationLimitMinutes",
    ])
    private static let recordingCacheFields: Set<String> = [
        "mode",
        "retainedRecordingLimit",
    ]

    static func encode(_ settings: IOSAppSettings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            return try encoder.encode(
                IOSAppSettingsWireV2(
                    settings: settings,
                    schemaVersion: iosAppSettingsCurrentSchemaVersion
                )
            )
        } catch {
            throw IOSAppSettingsRepositoryError.encodingFailed
        }
    }

    static func decode(
        _ data: Data,
        maximumInputByteCount: Int
    ) throws -> IOSAppSettings {
        do {
            try BoundedJSONMemberValidator.validate(
                data,
                limits: .metadataFile(
                    maximumInputByteCount: maximumInputByteCount
                )
            )
        } catch let error as BoundedJSONMemberValidationError {
            switch error {
            case .inputTooLarge:
                throw IOSAppSettingsRepositoryError.sourceTooLarge
            case .malformedJSON,
                 .duplicateObjectMember,
                 .resourceLimitExceeded:
                throw IOSAppSettingsRepositoryError.malformedData
            }
        } catch {
            throw IOSAppSettingsRepositoryError.malformedData
        }

        let rootValue: Any

        do {
            rootValue = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw IOSAppSettingsRepositoryError.malformedData
        }

        guard let rootObject = rootValue as? [String: Any] else {
            throw IOSAppSettingsRepositoryError.topLevelNotObject
        }

        let root = WireObjectReader(object: rootObject, path: "$")
        guard rootObject.keys.contains("schemaVersion") else {
            throw IOSAppSettingsRepositoryError.missingSchemaVersion
        }
        let schemaVersion = try root.integer("schemaVersion")
        guard supportedSchemaVersions.contains(schemaVersion) else {
            throw IOSAppSettingsRepositoryError.unsupportedSchemaVersion
        }

        try root.rejectUnexpectedFields(allowing: rootFields)

        return IOSAppSettings(
            transcriptionConfiguration: try decodeTranscription(from: root),
            textCorrectionConfiguration: try decodeTextCorrection(from: root),
            localTextCleanupEnabled: try root.boolean(
                "localTextCleanupEnabled",
                defaultValue: IOSAppSettings.defaults.localTextCleanupEnabled
            ),
            translationConfiguration: try decodeTranslation(from: root),
            voiceSessionPreferences: try decodeVoice(
                from: root,
                schemaVersion: schemaVersion
            ),
            recordingCachePolicy: try decodeRecordingCache(from: root)
        )
    }

    private static func decodeTranscription(
        from root: WireObjectReader
    ) throws -> TranscriptionConfiguration {
        let defaults = IOSAppSettings.defaults.transcriptionConfiguration
        guard let reader = try root.object("transcription") else {
            return defaults
        }
        try reader.rejectUnexpectedFields(allowing: transcriptionFields)

        return TranscriptionConfiguration(
            model: try reader.string("model", defaultValue: defaults.model),
            language: try reader.enumeration(
                "language",
                defaultValue: defaults.language
            ),
            customLanguageCode: try reader.string(
                "customLanguageCode",
                defaultValue: defaults.customLanguageCode
            ),
            freeformPrompt: try reader.string(
                "prompt",
                defaultValue: defaults.freeformPrompt
            )
        )
    }

    private static func decodeTextCorrection(
        from root: WireObjectReader
    ) throws -> TextCorrectionConfiguration {
        let defaults = IOSAppSettings.defaults.textCorrectionConfiguration
        guard let reader = try root.object("textCorrection") else {
            return defaults
        }
        try reader.rejectUnexpectedFields(allowing: textCorrectionFields)

        return TextCorrectionConfiguration(
            isEnabled: try reader.boolean(
                "isEnabled",
                defaultValue: defaults.isEnabled
            ),
            modelPreset: try reader.enumeration(
                "modelPreset",
                defaultValue: defaults.modelPreset
            ),
            customModel: try reader.string(
                "customModel",
                defaultValue: defaults.customModel
            ),
            prompt: try reader.string("prompt", defaultValue: defaults.prompt)
        )
    }

    private static func decodeTranslation(
        from root: WireObjectReader
    ) throws -> TranslationConfiguration {
        let defaults = IOSAppSettings.defaults.translationConfiguration
        guard let reader = try root.object("translation") else {
            return defaults
        }
        try reader.rejectUnexpectedFields(allowing: translationFields)
        // iOS v1 used to persist a global Translate action preference. Keep
        // validating the legacy field when present so malformed settings do
        // not become silently acceptable, but inline surfaces now own the
        // user's choice to translate.
        _ = try reader.boolean(
            "actionPreferenceEnabled",
            defaultValue: true
        )

        return TranslationConfiguration(
            actionPreferenceEnabled: true,
            sourceMode: try reader.enumeration(
                "sourceMode",
                defaultValue: defaults.sourceMode
            ),
            sourceLanguage: try reader.enumeration(
                "sourceLanguage",
                defaultValue: defaults.sourceLanguage
            ),
            customSourceLanguageCode: try reader.string(
                "customSourceLanguageCode",
                defaultValue: defaults.customSourceLanguageCode
            ),
            targetLanguage: try reader.enumeration(
                "targetLanguage",
                defaultValue: defaults.targetLanguage
            ),
            customTargetLanguageCode: try reader.string(
                "customTargetLanguageCode",
                defaultValue: defaults.customTargetLanguageCode
            ),
            model: try reader.string("model", defaultValue: defaults.model),
            prompt: try reader.string("prompt", defaultValue: defaults.prompt)
        )
    }

    private static func decodeVoice(
        from root: WireObjectReader,
        schemaVersion: Int
    ) throws -> VoiceSessionPreferences {
        let defaults = IOSAppSettings.defaults.voiceSessionPreferences
        guard let reader = try root.object("voice") else {
            return defaults
        }
        try reader.rejectUnexpectedFields(
            allowing: schemaVersion >= 3 ? voiceFields : legacyVoiceFields
        )

        let recordingDurationLimit: RecordingDurationLimit
        if schemaVersion >= 3 {
            recordingDurationLimit = RecordingDurationLimit(
                clampingMinutes: try reader.integer(
                    "recordingDurationLimitMinutes",
                    defaultValue: defaults.recordingDurationLimit.minutes
                )
            )
        } else {
            recordingDurationLimit = defaults.recordingDurationLimit
        }

        return VoiceSessionPreferences(
            audioCuesEnabled: try reader.boolean(
                "audioCuesEnabled",
                defaultValue: defaults.audioCuesEnabled
            ),
            recordingStopTailDuration: try reader.enumeration(
                "recordingStopTailDuration",
                defaultValue: defaults.recordingStopTailDuration
            ),
            recordingDurationLimit: recordingDurationLimit
        )
    }

    private static func decodeRecordingCache(
        from root: WireObjectReader
    ) throws -> RecordingCachePolicy {
        let defaults = IOSAppSettings.defaultRecordingCachePolicy.normalized
        guard let reader = try root.object("recordingCache") else {
            return defaults
        }
        try reader.rejectUnexpectedFields(allowing: recordingCacheFields)

        let defaultMode: RecordingCachePolicyModeWireV1
        switch defaults {
        case .deleteImmediately:
            defaultMode = .deleteImmediately
        case .keepLast:
            defaultMode = .keepLast
        case .unlimited:
            defaultMode = .unlimited
        }
        let mode = try reader.enumeration(
            "mode",
            defaultValue: defaultMode
        )
        let retainedRecordingLimit = try reader.integer(
            "retainedRecordingLimit",
            defaultValue: defaults.retainedRecordingLimit
        )

        switch mode {
        case .deleteImmediately:
            return .deleteImmediately
        case .keepLast:
            return .keepLast(
                RecordingCachePolicy.normalizedRetainedRecordingLimit(
                    retainedRecordingLimit
                )
            )
        case .unlimited:
            return .unlimited
        }
    }
}

private struct WireObjectReader {
    let object: [String: Any]
    let path: String

    func rejectUnexpectedFields(allowing allowedFields: Set<String>) throws {
        guard Set(object.keys).isSubset(of: allowedFields) else {
            throw IOSAppSettingsRepositoryError.unexpectedFields(path: path)
        }
    }

    func object(_ key: String) throws -> WireObjectReader? {
        guard let value = object[key] else {
            return nil
        }
        guard let nestedObject = value as? [String: Any] else {
            throw IOSAppSettingsRepositoryError.invalidValueType(path: valuePath(key))
        }

        return WireObjectReader(object: nestedObject, path: valuePath(key))
    }

    func string(_ key: String, defaultValue: String) throws -> String {
        guard let value = object[key] else {
            return defaultValue
        }
        guard let string = value as? String else {
            throw IOSAppSettingsRepositoryError.invalidValueType(path: valuePath(key))
        }
        return string
    }

    func boolean(_ key: String, defaultValue: Bool) throws -> Bool {
        guard let value = object[key] else {
            return defaultValue
        }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw IOSAppSettingsRepositoryError.invalidValueType(path: valuePath(key))
        }
        return number.boolValue
    }

    func integer(_ key: String) throws -> Int {
        guard let value = object[key],
              let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !Self.isFloatingPointNumber(number),
              let integer = Int(number.stringValue) else {
            throw IOSAppSettingsRepositoryError.invalidValueType(path: valuePath(key))
        }
        return integer
    }

    func integer(_ key: String, defaultValue: Int) throws -> Int {
        guard object.keys.contains(key) else {
            return defaultValue
        }
        return try integer(key)
    }

    func enumeration<Value>(
        _ key: String,
        defaultValue: Value
    ) throws -> Value where Value: RawRepresentable, Value.RawValue == String {
        guard let value = object[key] else {
            return defaultValue
        }
        guard let rawValue = value as? String else {
            throw IOSAppSettingsRepositoryError.invalidValueType(path: valuePath(key))
        }
        guard let enumeration = Value(rawValue: rawValue) else {
            throw IOSAppSettingsRepositoryError.unknownEnumValue(path: valuePath(key))
        }
        return enumeration
    }

    private func valuePath(_ key: String) -> String {
        path == "$" ? key : "\(path).\(key)"
    }

    private static func isFloatingPointNumber(_ number: NSNumber) -> Bool {
        let typeEncoding = String(cString: number.objCType)
        return typeEncoding == "f" || typeEncoding == "d"
    }
}
