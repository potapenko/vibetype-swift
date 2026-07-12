import HoldTypeDomain
import HoldTypePersistence
import SwiftUI

struct IOSTranslationSettingsView: View {
    @Environment(IOSAppSettingsStateOwner.self) private var stateOwner

    @State private var session: IOSSettingsEditorSession<
        TranslationConfiguration
    >
    @State private var showsDiscardConfirmation = false
    @Binding private var hasUnsavedSceneEditor: Bool

    init(
        configuration: TranslationConfiguration,
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

            Section("Translate Action") {
                Toggle(
                    "Show Translate Voice Action",
                    isOn: binding(\.actionPreferenceEnabled)
                )
                Text(
                    "A configured Translate action runs after transcription "
                        + "and optional correction."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Languages") {
                Picker("Source", selection: binding(\.sourceMode)) {
                    ForEach(TranslationSourceMode.allCases, id: \.self) {
                        mode in
                        Text(mode.iosSettingsDisplayName).tag(mode)
                    }
                }

                if configuration.sourceMode == .override {
                    NavigationLink {
                        IOSLanguageSelectionView(
                            title: "Source Language",
                            options: [TranscriptionLanguage.automatic]
                                + TranscriptionLanguage
                                    .iosTranslationCases,
                            automaticTitle: "Choose Source",
                            selection: binding(\.sourceLanguage)
                        )
                    } label: {
                        LabeledContent(
                            "Source Language",
                            value: IOSLanguageSelectionPresentation.title(
                                for: configuration.sourceLanguage,
                                automaticTitle: "Choose Source"
                            )
                        )
                    }

                    if configuration.sourceLanguage == .custom {
                        customCodeField(
                            title: "Custom Source Code",
                            text: binding(\.customSourceLanguageCode),
                            value: configuration.customSourceLanguageCode
                        )
                    }
                }

                NavigationLink {
                    IOSLanguageSelectionView(
                        title: "Target Language",
                        options: [TranscriptionLanguage.automatic]
                            + TranscriptionLanguage.iosTranslationCases,
                        automaticTitle: "Choose Target",
                        selection: binding(\.targetLanguage)
                    )
                } label: {
                    LabeledContent(
                        "Target Language",
                        value: IOSLanguageSelectionPresentation.title(
                            for: configuration.targetLanguage,
                            automaticTitle: "Choose Target"
                        )
                    )
                }

                if configuration.targetLanguage == .custom {
                    customCodeField(
                        title: "Custom Target Code",
                        text: binding(\.customTargetLanguageCode),
                        value: configuration.customTargetLanguageCode
                    )
                }

                routeStatus
            }

            Section("OpenAI Translation") {
                TextField("Model ID", text: binding(\.model))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if usesDefaultModel {
                    Label(
                        "Blank uses HoldType’s default translation model.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                IOSSettingsMultilineField(
                    title: "Prompt",
                    prompt: "Translation instructions",
                    text: binding(\.prompt),
                    lineLimit: 6...14
                )

                Button {
                    resetPrompt()
                } label: {
                    Label("Reset Standard Prompt", systemImage: "arrow.counterclockwise")
                }
                .disabled(configuration.isPromptDefault)

                Text(
                    "The model and prompt stay editable while the action is "
                        + "off. Reset changes only this unsaved draft."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .disabled(session.isSaving)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Translation")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.settings.translation.screen")
        .onChange(of: durableConfiguration, initial: true) { _, value in
            observeDurableConfiguration(value)
        }
        .onChange(of: sourceCodeInputState) { oldValue, newValue in
            announceCustomCodeTransition(
                from: oldValue,
                to: newValue,
                role: "Source"
            )
        }
        .onChange(of: targetCodeInputState) { oldValue, newValue in
            announceCustomCodeTransition(
                from: oldValue,
                to: newValue,
                role: "Target"
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

    private var configuration: TranslationConfiguration { session.draft }

    private var durableConfiguration: TranslationConfiguration {
        stateOwner.state.durableValue?.translationConfiguration
            ?? session.baseline
    }

    private var usesDefaultModel: Bool {
        configuration.model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var canSave: Bool {
        session.isDirty
            && !session.isSaving
            && IOSAppSettingsEditorValidation.canSaveTranslation(
                configuration
            )
    }

    private var sourceCodeInputState: IOSCustomLanguageCodeInputState? {
        guard configuration.sourceMode == .override,
              configuration.sourceLanguage == .custom else {
            return nil
        }
        return .resolve(configuration.customSourceLanguageCode)
    }

    private var targetCodeInputState: IOSCustomLanguageCodeInputState? {
        guard configuration.targetLanguage == .custom else { return nil }
        return .resolve(configuration.customTargetLanguageCode)
    }

    @ViewBuilder
    private var routeStatus: some View {
        switch configuration.routeConfigurationIssue {
        case .invalidSourceLanguage:
            IOSSettingsWarningLabel(
                "Choose a valid source override or use Same as Transcription.",
                color: .orange
            )
        case .missingTargetLanguage:
            IOSSettingsWarningLabel(
                "Choose a target language to make Translate available.",
                color: .orange
            )
        case nil:
            Label(routeDescription, systemImage: "arrow.right.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var routeDescription: String {
        let target = configuration.resolvedTargetLanguageCode ?? "target"
        let source = configuration.sourceMode == .sameAsTranscription
            ? "transcription"
            : configuration.sourceLanguage.apiLanguageCode(
                customCode: configuration.customSourceLanguageCode
            ) ?? "source"
        return "Translation route: \(source) → \(target)"
    }

    @ViewBuilder
    private func customCodeField(
        title: String,
        text: Binding<String>,
        value: String
    ) -> some View {
        TextField(title, text: text)
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityHint(customCodeAccessibilityHint(for: value))

        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if trimmed.isEmpty {
            Label(
                "Enter two or three letters to complete this route.",
                systemImage: "info.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else if TranscriptionLanguage
            .isWellFormedCustomLanguageCode(trimmed) {
            Label(
                "Language code: \(trimmed.lowercased())",
                systemImage: "checkmark.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
            IOSSettingsWarningLabel(
                "Use two or three letters, such as es or ja.",
                color: .red
            )
            .accessibilityIdentifier(
                "ios.settings.translation.language-invalid"
            )
        }
    }

    private func binding<Field: Equatable>(
        _ keyPath: WritableKeyPath<TranslationConfiguration, Field>
    ) -> Binding<Field> {
        Binding(
            get: { session.draft[keyPath: keyPath] },
            set: { session.set($0, at: keyPath) }
        )
    }

    private func resetPrompt() {
        var updated = configuration
        updated.resetPrompt()
        session.set(updated.prompt, at: \.prompt)
        iosAnnounceSettingsStatus(
            "Standard translation prompt restored in draft. Not saved."
        )
    }

    private func customCodeAccessibilityHint(for code: String) -> String {
        switch IOSCustomLanguageCodeInputState.resolve(code) {
        case .empty:
            return "Empty. Enter two or three letters to complete the route."
        case .valid:
            return "Valid language code."
        case .invalid:
            return "Invalid. Use two or three letters."
        }
    }

    private func observeDurableConfiguration(
        _ value: TranslationConfiguration
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

    private func announceCustomCodeTransition(
        from oldValue: IOSCustomLanguageCodeInputState?,
        to newValue: IOSCustomLanguageCodeInputState?,
        role: String
    ) {
        guard IOSCustomLanguageCodeInputState
            .shouldAnnounceValidityRecovery(from: oldValue, to: newValue)
        else { return }
        iosAnnounceSettingsStatus("\(role) language code is valid")
    }

    private func beginSave() {
        guard IOSAppSettingsEditorValidation.canSaveTranslation(
            session.draft
        ), let candidate = session.beginSave() else {
            return
        }
        Task { await commit(candidate) }
    }

    private func commit(_ candidate: TranslationConfiguration) async {
        do {
            let state = try await stateOwner.update {
                IOSAppSettingsEditorMutation.applyTranslation(
                    candidate,
                    to: &$0
                )
            }
            guard let settings = state.durableValue else {
                commitFailed()
                return
            }
            let returned = settings.translationConfiguration
            session.commitSucceeded(
                returnedDurableValue: returned,
                latestDurableValue: durableConfiguration
            )
            iosAnnounceSettingsStatus(
                session.phase == .saved
                    ? "Translation settings saved"
                    : "Translation settings changed elsewhere"
            )
        } catch {
            commitFailed()
        }
    }

    private func commitFailed() {
        session.commitFailed(restoring: durableConfiguration)
        iosAnnounceSettingsStatus("Translation settings were not saved")
    }
}
