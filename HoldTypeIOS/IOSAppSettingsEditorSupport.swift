import HoldTypeDomain
import HoldTypePersistence
import SwiftUI
import UIKit

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

enum IOSSettingsModelPresentation {
    nonisolated static func summary(
        rawModel: String,
        defaultModel: String
    ) -> String {
        let trimmed = rawModel.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty || trimmed == defaultModel
            ? "Default model"
            : "Custom model"
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

struct IOSSettingsEditorStatusSection: View {
    let phase: IOSSettingsEditorPhase
    var retry: () -> Void = {}
    var useSavedValue: () -> Void = {}

    @ViewBuilder
    var body: some View {
        switch phase {
        case .idle, .pending, .saved:
            EmptyView()
        case .saving:
            Section {
                ProgressView("Saving…")
                    .accessibilityIdentifier("ios.settings.editor.saving")
            }
        case .validationBlocked:
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Changes Not Applied")
                            .font(.headline)
                        Text("Fix the highlighted value to save automatically.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }
                .accessibilityIdentifier(
                    "ios.settings.editor.validation-blocked"
                )
            }
        case .saveFailed:
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Not Saved")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(
                            "Your changes are still here. Try again or use the saved value."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                .accessibilityIdentifier(
                    "ios.settings.editor.save-failed"
                )

                Button("Try Again", action: retry)
                Button("Use Saved Value", action: useSavedValue)
            }
        case .changedElsewhere:
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings Changed Elsewhere")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(
                            "Choose whether to apply your changes or use the newer saved value."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                }
                .accessibilityIdentifier(
                    "ios.settings.editor.changed-elsewhere"
                )

                Button("Try Again", action: retry)
                Button("Use Saved Value", action: useSavedValue)
            }
        }
    }
}

private struct IOSSettingsEditorPersistentStatus: View {
    let phase: IOSSettingsEditorPhase

    @ViewBuilder
    var body: some View {
        switch phase {
        case .saveFailed:
            statusLabel(
                "Not Saved",
                systemImage: "exclamationmark.triangle.fill",
                color: .red,
                identifier: "ios.settings.editor.persistent-save-failed"
            )
        case .changedElsewhere:
            statusLabel(
                "Changed Elsewhere",
                systemImage: "arrow.triangle.2.circlepath",
                color: .orange,
                identifier: "ios.settings.editor.persistent-changed"
            )
        case .validationBlocked:
            statusLabel(
                "Changes Not Applied",
                systemImage: "exclamationmark.circle.fill",
                color: .orange,
                identifier: "ios.settings.editor.persistent-validation"
            )
        case .idle, .pending, .saving, .saved:
            EmptyView()
        }
    }

    private func statusLabel(
        _ title: String,
        systemImage: String,
        color: Color,
        identifier: String
    ) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
            .accessibilityIdentifier(identifier)
    }
}

struct IOSSettingsWarningLabel: View {
    let title: String
    let color: Color

    init(_ title: String, color: Color) {
        self.title = title
        self.color = color
    }

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(color)
        }
        .font(.footnote)
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

struct IOSSettingsMultilineField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let lineLimit: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
            TextField(
                prompt,
                text: $text,
                axis: .vertical
            )
            .lineLimit(lineLimit)
            .accessibilityLabel(title)
        }
    }
}

struct IOSSettingsAttentionTarget: Hashable, Sendable {
    let attention: IOSSettingsAttention
    let field: IOSSettingsField

    init(
        _ attention: IOSSettingsAttention,
        field: IOSSettingsField? = nil
    ) {
        self.attention = attention
        self.field = field ?? attention.defaultField
    }

}

struct IOSSettingsForm<Content: View>: View {
    let attentionTarget: IOSSettingsAttentionTarget?
    private let content: Content

    init(
        attentionTarget: IOSSettingsAttentionTarget? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.attentionTarget = attentionTarget
        self.content = content()
    }

    var body: some View {
        IOSSettingsAttentionScrollView(attentionTarget: attentionTarget) {
            Form {
                content
            }
        }
    }
}

struct IOSSettingsAttentionScrollView<Content: View>: View {
    let attentionTarget: IOSSettingsAttentionTarget?
    private let content: Content

    init(
        attentionTarget: IOSSettingsAttentionTarget? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.attentionTarget = attentionTarget
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            content
            .task(id: attentionTarget) {
                guard let attentionTarget else { return }
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(attentionTarget.field, anchor: .center)
                }
                await Task.yield()
                UIAccessibility.post(
                    notification: .layoutChanged,
                    argument: nil
                )
                iosAnnounceSettingsStatus(
                    attentionTarget.attention.title
                        + ". "
                        + attentionTarget.attention.detail
                )
            }
        }
    }
}

private struct IOSSettingsFieldModifier: ViewModifier {
    let field: IOSSettingsField
    let attentionTarget: IOSSettingsAttentionTarget?

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if attentionTarget?.field == field,
               let attention = attentionTarget?.attention {
                IOSSettingsAttentionCallout(attention: attention)
            }
        }
        .id(field)
    }
}

private struct IOSSettingsAttentionCallout: View {
    let attention: IOSSettingsAttention

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(attention.title)
                    .font(.subheadline.weight(.semibold))
                Text(attention.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
            "ios.settings.attention.\(attention.rawValue)"
        )
    }
}

private struct IOSSettingsAutosaveChrome: ViewModifier {
    let phase: IOSSettingsEditorPhase

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                IOSSettingsEditorPersistentStatus(phase: phase)
            }
    }
}

extension View {
    func iosSettingsField(
        _ field: IOSSettingsField,
        attentionTarget: IOSSettingsAttentionTarget? = nil
    ) -> some View {
        modifier(
            IOSSettingsFieldModifier(
                field: field,
                attentionTarget: attentionTarget
            )
        )
    }

    func iosSettingsAutosaveChrome(
        phase: IOSSettingsEditorPhase
    ) -> some View {
        modifier(IOSSettingsAutosaveChrome(phase: phase))
    }
}

@MainActor
func iosAnnounceSettingsStatus(_ message: String) {
    UIAccessibility.post(
        notification: .announcement,
        argument: message
    )
}
