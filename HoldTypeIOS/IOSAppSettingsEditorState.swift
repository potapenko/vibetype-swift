import Foundation
import HoldTypeDomain
import HoldTypePersistence

enum IOSGeneralSettingsDestination: String, CaseIterable, Hashable {
    case transcription
    case writingCorrection = "writing-correction"
    case translation
    case voiceRecording = "voice-recording"

    var title: String {
        switch self {
        case .transcription: "Transcription"
        case .writingCorrection: "Writing & Correction"
        case .translation: "Translation"
        case .voiceRecording: "Voice & Recording"
        }
    }

    var systemImage: String {
        switch self {
        case .transcription: "waveform.and.mic"
        case .writingCorrection: "text.badge.checkmark"
        case .translation: "character.bubble"
        case .voiceRecording: "mic.badge.plus"
        }
    }

    var rowAccessibilityIdentifier: String {
        "ios.settings.\(rawValue).row"
    }
}

enum IOSSettingsEditorPhase: Equatable {
    case idle
    case pending
    case saving
    case saved
    case validationBlocked
    case saveFailed
    case changedElsewhere
}

enum IOSCustomLanguageCodeInputState: Equatable {
    case empty
    case valid
    case invalid

    nonisolated static func resolve(_ code: String) -> Self {
        let trimmed = code.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return .empty }
        return TranscriptionLanguage.isWellFormedCustomLanguageCode(trimmed)
            ? .valid
            : .invalid
    }

    nonisolated static func shouldAnnounceValidityRecovery(
        from oldValue: Self?,
        to newValue: Self?
    ) -> Bool {
        switch (oldValue, newValue) {
        case (.some(.invalid), .some(.valid)):
            true
        default:
            false
        }
    }
}

struct IOSSettingsEditorSession<Value: Equatable> {
    private(set) var baseline: Value
    private(set) var draft: Value
    private(set) var phase = IOSSettingsEditorPhase.idle
    private var inFlightCandidate: Value?

    init(value: Value) {
        baseline = value
        draft = value
    }

    var isDirty: Bool { draft != baseline }
    var isSaving: Bool { inFlightCandidate != nil }

    @discardableResult
    mutating func set<Field: Equatable>(
        _ value: Field,
        at keyPath: WritableKeyPath<Value, Field>
    ) -> Bool {
        guard draft[keyPath: keyPath] != value else { return false }
        draft[keyPath: keyPath] = value
        if draft == baseline {
            phase = .idle
        } else {
            phase = .pending
        }
        return true
    }

    mutating func beginSave() -> Value? {
        guard isDirty,
              !isSaving,
              phase != .validationBlocked,
              phase != .saveFailed,
              phase != .changedElsewhere else {
            return nil
        }
        inFlightCandidate = draft
        phase = .saving
        return draft
    }

    mutating func commitSucceeded(
        returnedDurableValue: Value,
        latestDurableValue: Value
    ) {
        let savedCandidate = inFlightCandidate
        inFlightCandidate = nil

        if draft == latestDurableValue {
            baseline = latestDurableValue
            draft = latestDurableValue
            phase = .saved
        } else if draft == savedCandidate,
                  latestDurableValue == returnedDurableValue {
            baseline = latestDurableValue
            draft = latestDurableValue
            phase = .saved
        } else if draft == savedCandidate {
            baseline = latestDurableValue
            phase = .changedElsewhere
        } else {
            baseline = latestDurableValue
            phase = .pending
        }
    }

    mutating func commitFailed(restoring durableValue: Value) {
        inFlightCandidate = nil
        baseline = durableValue
        phase = draft == baseline ? .idle : .saveFailed
    }

    mutating func markValidationBlocked() {
        guard isDirty else {
            phase = .idle
            return
        }
        phase = .validationBlocked
    }

    mutating func retry() {
        guard isDirty, !isSaving else { return }
        phase = .pending
    }

    mutating func observeDurableValue(_ durableValue: Value) {
        guard durableValue != baseline else { return }

        if isSaving {
            baseline = durableValue
            return
        }

        if !isDirty || draft == durableValue {
            baseline = durableValue
            draft = durableValue
            phase = .idle
        } else {
            baseline = durableValue
            phase = .changedElsewhere
        }
    }

    mutating func discard() {
        inFlightCandidate = nil
        draft = baseline
        phase = .idle
    }
}

extension IOSSettingsEditorSession: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSSettingsEditorSession(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSWritingCorrectionSettingsDraft: Equatable, Sendable {
    var configuration: TextCorrectionConfiguration
    var localTextCleanupEnabled: Bool
}

struct IOSVoiceRecordingSettingsDraft: Equatable, Sendable {
    var preferences: VoiceSessionPreferences
    var recordingCachePolicy: RecordingCachePolicy
}

enum IOSRecordingCacheRetentionMode: String, CaseIterable, Hashable {
    case keepLast
    case unlimited
}

enum IOSRecordingCachePolicyEditor {
    nonisolated static let enabledPolicy: RecordingCachePolicy =
        .keepLast(RetentionConfiguration.acceptedHistoryEntryLimit)

    nonisolated static func policyAfterSettingEnabled(
        _ isEnabled: Bool
    ) -> RecordingCachePolicy {
        isEnabled
            ? enabledPolicy
            : .deleteImmediately
    }

    nonisolated static func policyAfterSelectingRetention(
        _ mode: IOSRecordingCacheRetentionMode,
        currentPolicy: RecordingCachePolicy
    ) -> RecordingCachePolicy {
        switch mode {
        case .keepLast:
            switch currentPolicy.normalized {
            case .keepLast(let count):
                .keepLast(count)
            case .deleteImmediately, .unlimited:
                enabledPolicy
            }
        case .unlimited:
            .unlimited
        }
    }
}

extension IOSWritingCorrectionSettingsDraft: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSWritingCorrectionSettingsDraft(redacted)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSAppSettingsEditorValidation {
    static func canSaveTranscription(
        _ configuration: TranscriptionConfiguration
    ) -> Bool {
        guard configuration.language == .custom else { return true }
        return !configuration.customLanguageCodeValidation.isInvalid
    }

    static func canSaveTranslation(
        _ configuration: TranslationConfiguration
    ) -> Bool {
        isEmptyOrValidCustomCode(
            configuration.customSourceLanguageCode,
            when: configuration.sourceMode == .override
                && configuration.sourceLanguage == .custom
        ) && isEmptyOrValidCustomCode(
            configuration.customTargetLanguageCode,
            when: configuration.targetLanguage == .custom
        )
    }

    private static func isEmptyOrValidCustomCode(
        _ code: String,
        when isSelected: Bool
    ) -> Bool {
        guard isSelected else { return true }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            || TranscriptionLanguage.isWellFormedCustomLanguageCode(trimmed)
    }
}

enum IOSAppSettingsEditorMutation {
    nonisolated static func applyTranscription(
        _ configuration: TranscriptionConfiguration,
        to settings: inout IOSAppSettings
    ) {
        settings.transcriptionConfiguration = configuration
    }

    nonisolated static func applyWritingAndCorrection(
        _ draft: IOSWritingCorrectionSettingsDraft,
        to settings: inout IOSAppSettings
    ) {
        settings.textCorrectionConfiguration = draft.configuration
        settings.localTextCleanupEnabled = draft.localTextCleanupEnabled
    }

    nonisolated static func setLocalTextCleanupEnabled(
        _ isEnabled: Bool,
        in settings: inout IOSAppSettings
    ) {
        settings.localTextCleanupEnabled = isEnabled
    }

    nonisolated static func applyTranslation(
        _ configuration: TranslationConfiguration,
        to settings: inout IOSAppSettings
    ) {
        settings.translationConfiguration = configuration
    }

    nonisolated static func applyVoiceAndRecording(
        _ draft: IOSVoiceRecordingSettingsDraft,
        to settings: inout IOSAppSettings
    ) {
        settings.voiceSessionPreferences = draft.preferences
        settings.recordingCachePolicy = draft.recordingCachePolicy.normalized
    }
}

extension IOSAppSettingsState {
    var durableValue: IOSAppSettings? {
        switch self {
        case .notLoaded, .loadFailed:
            nil
        case .ready(let value), .saveFailed(let value):
            value
        }
    }
}

extension TranscriptionLanguage {
    static var iosTranslationCases: [Self] {
        allCases.filter { $0 != .automatic }
    }

    nonisolated var iosSettingsDisplayName: String {
        guard let languageCode else {
            return iosSettingsLanguageName
        }
        return "\(iosSettingsLanguageName) (\(languageCode))"
    }

    nonisolated var iosSettingsLanguageName: String {
        switch self {
        case .automatic: "Auto"
        case .english: "English"
        case .spanish: "Spanish"
        case .french: "French"
        case .german: "German"
        case .italian: "Italian"
        case .portuguese: "Portuguese"
        case .dutch: "Dutch"
        case .polish: "Polish"
        case .russian: "Russian"
        case .ukrainian: "Ukrainian"
        case .turkish: "Turkish"
        case .arabic: "Arabic"
        case .hebrew: "Hebrew"
        case .hindi: "Hindi"
        case .chinese: "Chinese"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .vietnamese: "Vietnamese"
        case .indonesian: "Indonesian"
        case .thai: "Thai"
        case .swedish: "Swedish"
        case .danish: "Danish"
        case .finnish: "Finnish"
        case .czech: "Czech"
        case .greek: "Greek"
        case .romanian: "Romanian"
        case .hungarian: "Hungarian"
        case .custom: "Custom"
        }
    }
}

extension TextCorrectionModelPreset {
    var iosSettingsDisplayName: String {
        switch self {
        case .quality: "Quality"
        case .balanced: "Balanced"
        case .fast: "Fast"
        case .custom: "Custom"
        }
    }

    var iosSettingsDetail: String {
        switch self {
        case .quality: "Highest quality correction"
        case .balanced: "Lower cost than Quality"
        case .fast: "Lower latency and cost"
        case .custom: "Use a model ID you enter"
        }
    }
}

extension TranslationSourceMode {
    var iosSettingsDisplayName: String {
        switch self {
        case .sameAsTranscription: "Same as Transcription"
        case .override: "Override Source"
        }
    }
}

extension RecordingStopTailDuration {
    var iosSettingsDisplayName: String {
        switch self {
        case .off: "Off"
        case .milliseconds500: "0.5 seconds"
        case .seconds1: "1 second"
        case .seconds1_5: "1.5 seconds"
        case .seconds2: "2 seconds"
        }
    }
}

extension RecordingCachePolicy {
    nonisolated var iosSettingsSummary: String {
        switch normalized {
        case .deleteImmediately:
            "Cache off"
        case .keepLast(let count):
            "Cache last \(count)"
        case .unlimited:
            "Cache unlimited"
        }
    }

    nonisolated var iosSettingsRetentionMode: IOSRecordingCacheRetentionMode {
        self == .unlimited ? .unlimited : .keepLast
    }
}

enum IOSProviderInstructionsPresentation {
    static func displayedValue(
        storedValue: String,
        defaultValue: String
    ) -> String {
        let trimmed = storedValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty || storedValue == defaultValue
            ? ""
            : storedValue
    }

    static func storedValue(
        from displayedValue: String,
        defaultValue: String
    ) -> String {
        displayedValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty ? defaultValue : displayedValue
    }

    static func usesStandardBehavior(
        storedValue: String,
        defaultValue: String
    ) -> Bool {
        displayedValue(
            storedValue: storedValue,
            defaultValue: defaultValue
        ).isEmpty
    }
}
