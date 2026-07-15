import HoldTypeDomain

/// The app-only, non-secret settings owned by the iOS containing app.
public struct IOSAppSettings: Equatable, Sendable {
    public static let defaultRecordingCachePolicy: RecordingCachePolicy =
        .keepLast(RetentionConfiguration.acceptedHistoryEntryLimit)
    public static let defaults = IOSAppSettings()

    public var transcriptionConfiguration: TranscriptionConfiguration
    public var textCorrectionConfiguration: TextCorrectionConfiguration
    public var localTextCleanupEnabled: Bool
    public var translationConfiguration: TranslationConfiguration
    public var voiceSessionPreferences: VoiceSessionPreferences
    public var recordingCachePolicy: RecordingCachePolicy

    public init(
        transcriptionConfiguration: TranscriptionConfiguration = .defaults,
        textCorrectionConfiguration: TextCorrectionConfiguration = .defaults,
        localTextCleanupEnabled: Bool = true,
        translationConfiguration: TranslationConfiguration = .defaults,
        voiceSessionPreferences: VoiceSessionPreferences = .defaults,
        recordingCachePolicy: RecordingCachePolicy =
            IOSAppSettings.defaultRecordingCachePolicy
    ) {
        self.transcriptionConfiguration = transcriptionConfiguration
        self.textCorrectionConfiguration = textCorrectionConfiguration
        self.localTextCleanupEnabled = localTextCleanupEnabled
        self.translationConfiguration = translationConfiguration
        self.voiceSessionPreferences = voiceSessionPreferences
        self.recordingCachePolicy = recordingCachePolicy
    }
}

extension IOSAppSettings: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { "IOSAppSettings(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
