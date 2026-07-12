import HoldTypeDomain
import HoldTypePersistence
import SwiftUI

struct IOSVoiceRecordingSettingsView: View {
    @Environment(IOSAppSettingsStateOwner.self) private var stateOwner

    @State private var session: IOSSettingsEditorSession<
        VoiceSessionPreferences
    >
    @State private var showsDiscardConfirmation = false
    @Binding private var hasUnsavedSceneEditor: Bool

    init(
        preferences: VoiceSessionPreferences,
        hasUnsavedSceneEditor: Binding<Bool> = .constant(false)
    ) {
        _session = State(
            initialValue: IOSSettingsEditorSession(value: preferences)
        )
        _hasUnsavedSceneEditor = hasUnsavedSceneEditor
    }

    var body: some View {
        Form {
            IOSSettingsEditorStatusSection(phase: session.phase)

            Section("Feedback") {
                Toggle(
                    "Play Recording Start and Stop Sounds",
                    isOn: binding(\.audioCuesEnabled)
                )
            }

            Section("Recording") {
                Picker(
                    "Tail after Stop",
                    selection: binding(\.recordingStopTailDuration)
                ) {
                    ForEach(RecordingStopTailDuration.allCases, id: \.self) {
                        duration in
                        Text(duration.iosSettingsDisplayName).tag(duration)
                    }
                }

                Text(
                    "A short tail helps keep final words from being cut off."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                LabeledContent("Maximum Utterance", value: "5 minutes")
                Text("The per-utterance safety limit is fixed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .disabled(session.isSaving)
        .navigationTitle("Voice & Recording")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.settings.voice-recording.screen")
        .onChange(of: durablePreferences, initial: true) { _, value in
            observeDurablePreferences(value)
        }
        .onChange(of: session.isDirty, initial: true) { _, isDirty in
            hasUnsavedSceneEditor = isDirty
        }
        .iosSettingsEditorChrome(
            isDirty: session.isDirty,
            isSaving: session.isSaving,
            canSave: session.isDirty && !session.isSaving,
            phase: session.phase,
            showsDiscardConfirmation: $showsDiscardConfirmation,
            hasUnsavedSceneEditor: $hasUnsavedSceneEditor,
            save: beginSave,
            discard: { session.discard() }
        )
    }

    private var durablePreferences: VoiceSessionPreferences {
        stateOwner.state.durableValue?.voiceSessionPreferences
            ?? session.baseline
    }

    private func binding<Field: Equatable>(
        _ keyPath: WritableKeyPath<VoiceSessionPreferences, Field>
    ) -> Binding<Field> {
        Binding(
            get: { session.draft[keyPath: keyPath] },
            set: { session.set($0, at: keyPath) }
        )
    }

    private func beginSave() {
        guard let candidate = session.beginSave() else { return }
        Task { await commit(candidate) }
    }

    private func observeDurablePreferences(
        _ value: VoiceSessionPreferences
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

    private func commit(_ candidate: VoiceSessionPreferences) async {
        do {
            let state = try await stateOwner.update {
                IOSAppSettingsEditorMutation.applyVoiceAndRecording(
                    candidate,
                    to: &$0
                )
            }
            guard let settings = state.durableValue else {
                commitFailed()
                return
            }
            let returned = settings.voiceSessionPreferences
            session.commitSucceeded(
                returnedDurableValue: returned,
                latestDurableValue: durablePreferences
            )
            iosAnnounceSettingsStatus(
                session.phase == .saved
                    ? "Voice settings saved"
                    : "Voice settings changed elsewhere"
            )
        } catch {
            commitFailed()
        }
    }

    private func commitFailed() {
        session.commitFailed(restoring: durablePreferences)
        iosAnnounceSettingsStatus("Voice settings were not saved")
    }
}
