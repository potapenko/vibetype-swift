import HoldTypeDomain

struct IOSAppSettingsWireV2: Encodable {
    private let schemaVersion: Int
    private let transcription: TranscriptionWireV1
    private let textCorrection: TextCorrectionWireV1
    private let localTextCleanupEnabled: Bool
    private let translation: TranslationWireV1
    private let voice: VoiceWireV1
    private let recordingCache: RecordingCacheWireV1

    init(settings: IOSAppSettings, schemaVersion: Int) {
        self.schemaVersion = schemaVersion
        transcription = TranscriptionWireV1(
            model: settings.transcriptionConfiguration.model,
            language: settings.transcriptionConfiguration.language.rawValue,
            customLanguageCode: settings.transcriptionConfiguration.customLanguageCode,
            prompt: settings.transcriptionConfiguration.freeformPrompt
        )
        textCorrection = TextCorrectionWireV1(
            isEnabled: settings.textCorrectionConfiguration.isEnabled,
            modelPreset: settings.textCorrectionConfiguration.modelPreset.rawValue,
            customModel: settings.textCorrectionConfiguration.customModel,
            prompt: settings.textCorrectionConfiguration.prompt
        )
        localTextCleanupEnabled = settings.localTextCleanupEnabled
        translation = TranslationWireV1(
            sourceMode: settings.translationConfiguration.sourceMode.rawValue,
            sourceLanguage: settings.translationConfiguration.sourceLanguage.rawValue,
            customSourceLanguageCode:
                settings.translationConfiguration.customSourceLanguageCode,
            targetLanguage: settings.translationConfiguration.targetLanguage.rawValue,
            customTargetLanguageCode:
                settings.translationConfiguration.customTargetLanguageCode,
            model: settings.translationConfiguration.model,
            prompt: settings.translationConfiguration.prompt
        )
        voice = VoiceWireV1(
            audioCuesEnabled: settings.voiceSessionPreferences.audioCuesEnabled,
            recordingStopTailDuration:
                settings.voiceSessionPreferences.recordingStopTailDuration.rawValue,
            recordingDurationLimitMinutes:
                settings.voiceSessionPreferences.recordingDurationLimit.minutes
        )
        recordingCache = RecordingCacheWireV1(
            policy: settings.recordingCachePolicy
        )
    }
}

private struct TranscriptionWireV1: Encodable {
    let model: String
    let language: String
    let customLanguageCode: String
    let prompt: String
}

private struct TextCorrectionWireV1: Encodable {
    let isEnabled: Bool
    let modelPreset: String
    let customModel: String
    let prompt: String
}

private struct TranslationWireV1: Encodable {
    let sourceMode: String
    let sourceLanguage: String
    let customSourceLanguageCode: String
    let targetLanguage: String
    let customTargetLanguageCode: String
    let model: String
    let prompt: String
}

private struct VoiceWireV1: Encodable {
    let audioCuesEnabled: Bool
    let recordingStopTailDuration: String
    let recordingDurationLimitMinutes: Int
}

enum RecordingCachePolicyModeWireV1: String, Encodable {
    case deleteImmediately
    case keepLast
    case unlimited
}

private struct RecordingCacheWireV1: Encodable {
    let mode: RecordingCachePolicyModeWireV1
    let retainedRecordingLimit: Int

    init(policy: RecordingCachePolicy) {
        retainedRecordingLimit = policy.retainedRecordingLimit

        switch policy.normalized {
        case .deleteImmediately:
            mode = .deleteImmediately
        case .keepLast:
            mode = .keepLast
        case .unlimited:
            mode = .unlimited
        }
    }
}
