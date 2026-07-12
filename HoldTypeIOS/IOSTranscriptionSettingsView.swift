import HoldTypeDomain
import HoldTypePersistence
import SwiftUI

struct IOSTranscriptionSettingsView: View {
    @Environment(IOSAppSettingsStateOwner.self) private var stateOwner

    @State private var session: IOSSettingsEditorSession<
        TranscriptionConfiguration
    >
    @State private var showsDiscardConfirmation = false
    @Binding private var hasUnsavedSceneEditor: Bool

    init(
        configuration: TranscriptionConfiguration,
        hasUnsavedSceneEditor: Binding<Bool> = .constant(false)
    ) {
        _session = State(
            initialValue: IOSSettingsEditorSession(value: configuration)
        )
        _hasUnsavedSceneEditor = hasUnsavedSceneEditor
    }

    var body: some View {
        Form {
            IOSSettingsEditorStatusSection(phase: session.phase)

            Section("Model") {
                TextField("Model ID", text: binding(\.model))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if usesDefaultModel {
                    Label(
                        "Blank uses HoldType’s default transcription model.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Language") {
                NavigationLink {
                    IOSLanguageSelectionView(
                        title: "Dictation Language",
                        options: TranscriptionLanguage.allCases,
                        automaticTitle: "Auto",
                        selection: binding(\.language)
                    )
                } label: {
                    LabeledContent(
                        "Dictation Language",
                        value: IOSLanguageSelectionPresentation.title(
                            for: session.draft.language,
                            automaticTitle: "Auto"
                        )
                    )
                }

                if session.draft.language == .custom {
                    TextField(
                        "Custom language code",
                        text: binding(\.customLanguageCode)
                    )
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityHint(customLanguageCodeAccessibilityHint)

                    customLanguageStatus
                }
            }

            Section("Transcription Prompt") {
                IOSSettingsMultilineField(
                    title: "Prompt",
                    prompt: "Optional vocabulary or style guidance",
                    text: binding(\.freeformPrompt),
                    lineLimit: 3...10
                )

                Text(
                    "The prompt is sent with transcription requests after "
                        + "provider consent. It never enters the keyboard."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .disabled(session.isSaving)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Transcription")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.settings.transcription.screen")
        .onChange(of: durableConfiguration, initial: true) { _, value in
            observeDurableConfiguration(value)
        }
        .onChange(of: customLanguageCodeInputState) {
            oldValue,
            newValue in
            announceCustomLanguageValidation(
                from: oldValue,
                to: newValue
            )
        }
        .onChange(of: session.isDirty, initial: true) { _, isDirty in
            hasUnsavedSceneEditor = isDirty
        }
        .iosSettingsEditorChrome(
            isDirty: session.isDirty,
            isSaving: session.isSaving,
            canSave: canSave,
            phase: session.phase,
            showsDiscardConfirmation: $showsDiscardConfirmation,
            hasUnsavedSceneEditor: $hasUnsavedSceneEditor,
            save: beginSave,
            discard: { session.discard() }
        )
    }

    @ViewBuilder
    private var customLanguageStatus: some View {
        switch session.draft.customLanguageCodeValidation {
        case .notRequired:
            EmptyView()
        case .emptyFallsBackToAutomatic:
            Label(
                "Blank custom code uses Auto.",
                systemImage: "info.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .valid(let normalizedCode):
            Label(
                "Language code: \(normalizedCode)",
                systemImage: "checkmark.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .invalid:
            IOSSettingsWarningLabel(
                "Use two or three letters, such as en or ru.",
                color: .red
            )
            .accessibilityIdentifier(
                "ios.settings.transcription.language-invalid"
            )
        }
    }

    private var durableConfiguration: TranscriptionConfiguration {
        stateOwner.state.durableValue?.transcriptionConfiguration
            ?? session.baseline
    }

    private var usesDefaultModel: Bool {
        session.draft.model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var canSave: Bool {
        session.isDirty
            && !session.isSaving
            && IOSAppSettingsEditorValidation.canSaveTranscription(
                session.draft
            )
    }

    private var customLanguageCodeAccessibilityHint: String {
        switch session.draft.customLanguageCodeValidation {
        case .notRequired:
            return ""
        case .emptyFallsBackToAutomatic:
            return "Blank uses Auto."
        case .valid:
            return "Valid language code."
        case .invalid:
            return "Invalid. Use two or three letters."
        }
    }

    private var customLanguageCodeInputState:
        IOSCustomLanguageCodeInputState? {
        guard session.draft.language == .custom else { return nil }
        return .resolve(session.draft.customLanguageCode)
    }

    private func binding<Field: Equatable>(
        _ keyPath: WritableKeyPath<TranscriptionConfiguration, Field>
    ) -> Binding<Field> {
        Binding(
            get: { session.draft[keyPath: keyPath] },
            set: { session.set($0, at: keyPath) }
        )
    }

    private func beginSave() {
        guard IOSAppSettingsEditorValidation.canSaveTranscription(
            session.draft
        ), let candidate = session.beginSave() else {
            return
        }

        Task { await commit(candidate) }
    }

    private func observeDurableConfiguration(
        _ value: TranscriptionConfiguration
    ) {
        let previousPhase = session.phase
        session.observeDurableValue(value)
        if session.phase == .changedElsewhere,
           previousPhase != .changedElsewhere {
            iosAnnounceSettingsStatus(
                "Settings changed elsewhere. This draft is not saved."
            )
        }
    }

    private func announceCustomLanguageValidation(
        from oldValue: IOSCustomLanguageCodeInputState?,
        to newValue: IOSCustomLanguageCodeInputState?
    ) {
        guard IOSCustomLanguageCodeInputState
            .shouldAnnounceValidityRecovery(from: oldValue, to: newValue)
        else { return }
        iosAnnounceSettingsStatus("Custom language code is valid")
    }

    private func commit(
        _ candidate: TranscriptionConfiguration
    ) async {
        do {
            let state = try await stateOwner.update {
                IOSAppSettingsEditorMutation.applyTranscription(
                    candidate,
                    to: &$0
                )
            }
            guard let value = state.durableValue else {
                commitFailed()
                return
            }
            let returned = value.transcriptionConfiguration
            let latest = durableConfiguration
            session.commitSucceeded(
                returnedDurableValue: returned,
                latestDurableValue: latest
            )
            announceCommitResult(
                saved: session.phase == .saved,
                savedMessage: "Transcription settings saved",
                changedMessage: "Transcription settings changed elsewhere"
            )
        } catch {
            commitFailed()
        }
    }

    private func commitFailed() {
        let durable = stateOwner.state.durableValue?
            .transcriptionConfiguration ?? session.baseline
        session.commitFailed(restoring: durable)
        iosAnnounceSettingsStatus("Transcription settings were not saved")
    }

    private func announceCommitResult(
        saved: Bool,
        savedMessage: String,
        changedMessage: String
    ) {
        iosAnnounceSettingsStatus(saved ? savedMessage : changedMessage)
    }
}
