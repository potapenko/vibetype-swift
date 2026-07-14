import HoldTypeDomain
import HoldTypePersistence
import SwiftUI

struct IOSVoiceRecordingSettingsView: View {
    @Environment(IOSAppSettingsStateOwner.self) private var stateOwner

    @State private var session: IOSSettingsEditorSession<
        IOSVoiceRecordingSettingsDraft
    >
    @State private var showsDiscardConfirmation = false
    @State private var showsCacheReconciliationFailure = false
    @Binding private var hasUnsavedSceneEditor: Bool
    private let reconcileRecordingCache: (
        RecordingCachePolicy
    ) async -> Bool

    init(
        preferences: VoiceSessionPreferences,
        recordingCachePolicy: RecordingCachePolicy,
        hasUnsavedSceneEditor: Binding<Bool> = .constant(false),
        reconcileRecordingCache: @escaping (
            RecordingCachePolicy
        ) async -> Bool = { _ in true }
    ) {
        _session = State(
            initialValue: IOSSettingsEditorSession(
                value: IOSVoiceRecordingSettingsDraft(
                    preferences: preferences,
                    recordingCachePolicy: recordingCachePolicy.normalized
                )
            )
        )
        _hasUnsavedSceneEditor = hasUnsavedSceneEditor
        self.reconcileRecordingCache = reconcileRecordingCache
    }

    var body: some View {
        Form {
            IOSSettingsEditorStatusSection(phase: session.phase)

            Section("Feedback") {
                Toggle(
                    "Play Recording Start and Stop Sounds",
                    isOn: binding(\.preferences.audioCuesEnabled)
                )
            }

            Section("Recording") {
                Picker(
                    "Tail after Stop",
                    selection: binding(
                        \.preferences.recordingStopTailDuration
                    )
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

            Section("Recording Cache") {
                Toggle(
                    "Keep completed recordings",
                    isOn: recordingCacheEnabledBinding
                )

                Text(recordingCacheDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if session.draft.recordingCachePolicy.keepsRecordings {
                    Picker(
                        "Retention",
                        selection: recordingCacheRetentionModeBinding
                    ) {
                        Text("Keep Last")
                            .tag(IOSRecordingCacheRetentionMode.keepLast)
                        Text("Unlimited")
                            .tag(IOSRecordingCacheRetentionMode.unlimited)
                    }
                    .pickerStyle(.segmented)

                    if case .keepLast = session.draft.recordingCachePolicy.normalized {
                        Stepper(
                            "Keep last \(recordingCacheRetainedLimit) recordings",
                            value: recordingCacheRetainedLimitBinding,
                            in: 1...RecordingCachePolicy
                                .maximumRetainedRecordingLimit
                        )
                    } else {
                        Label(
                            "Unlimited cache can keep growing until it is cleared.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                }
            }
        }
        .disabled(session.isSaving)
        .navigationTitle("Voice & Recording")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.settings.voice-recording.screen")
        .onChange(of: durableDraft, initial: true) { _, value in
            observeDurableDraft(value)
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
        .alert(
            "Recording Cache Update Failed",
            isPresented: $showsCacheReconciliationFailure
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "Your setting was saved. HoldType will retry the cache update after the next recording."
            )
        }
    }

    private var durableDraft: IOSVoiceRecordingSettingsDraft {
        guard let settings = stateOwner.state.durableValue else {
            return session.baseline
        }
        return IOSVoiceRecordingSettingsDraft(
            preferences: settings.voiceSessionPreferences,
            recordingCachePolicy: settings.recordingCachePolicy.normalized
        )
    }

    private func binding<Field: Equatable>(
        _ keyPath: WritableKeyPath<IOSVoiceRecordingSettingsDraft, Field>
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

    private var recordingCacheEnabledBinding: Binding<Bool> {
        Binding(
            get: { session.draft.recordingCachePolicy.keepsRecordings },
            set: { isEnabled in
                session.set(
                    IOSRecordingCachePolicyEditor
                        .policyAfterSettingEnabled(isEnabled),
                    at: \.recordingCachePolicy
                )
            }
        )
    }

    private var recordingCacheRetentionModeBinding: Binding<
        IOSRecordingCacheRetentionMode
    > {
        Binding(
            get: {
                session.draft.recordingCachePolicy.iosSettingsRetentionMode
            },
            set: { mode in
                session.set(
                    IOSRecordingCachePolicyEditor
                        .policyAfterSelectingRetention(
                            mode,
                            currentPolicy: session.draft.recordingCachePolicy
                        ),
                    at: \.recordingCachePolicy
                )
            }
        )
    }

    private var recordingCacheRetainedLimitBinding: Binding<Int> {
        Binding(
            get: { recordingCacheRetainedLimit },
            set: { count in
                session.set(.keepLast(count), at: \.recordingCachePolicy)
            }
        )
    }

    private var recordingCacheRetainedLimit: Int {
        session.draft.recordingCachePolicy.retainedRecordingLimit
    }

    private var recordingCacheDescription: String {
        switch session.draft.recordingCachePolicy.normalized {
        case .deleteImmediately:
            "HoldType deletes each completed recording after the attempt finishes."
        case .keepLast(let count):
            "HoldType keeps the last \(count) completed recordings for playback in History."
        case .unlimited:
            "HoldType keeps completed recordings for History playback until the cache is cleared."
        }
    }

    private func observeDurableDraft(
        _ value: IOSVoiceRecordingSettingsDraft
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

    private func commit(_ candidate: IOSVoiceRecordingSettingsDraft) async {
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
            let returned = IOSVoiceRecordingSettingsDraft(
                preferences: settings.voiceSessionPreferences,
                recordingCachePolicy: settings.recordingCachePolicy.normalized
            )
            session.commitSucceeded(
                returnedDurableValue: returned,
                latestDurableValue: durableDraft
            )
            if !(await reconcileRecordingCache(
                settings.recordingCachePolicy
            )) {
                showsCacheReconciliationFailure = true
            }
            iosAnnounceSettingsStatus(
                session.phase == .saved
                    ? "Voice and recording settings saved"
                    : "Voice and recording settings changed elsewhere"
            )
        } catch {
            commitFailed()
        }
    }

    private func commitFailed() {
        session.commitFailed(restoring: durableDraft)
        iosAnnounceSettingsStatus("Voice and recording settings were not saved")
    }
}
