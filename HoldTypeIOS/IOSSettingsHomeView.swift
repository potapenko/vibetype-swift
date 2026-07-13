import HoldTypeDomain
import HoldTypeIOSCore
import HoldTypePersistence
import SwiftUI

struct IOSSettingsHomeView: View {
    @Environment(IOSAppSettingsStateOwner.self) private var stateOwner
    @State private var isLoading = false
    @Binding var openAIEditorDraft: IOSOpenAICredentialEditorDraft
    @Binding var hasUnsavedGeneralSettings: Bool
    let foregroundVoiceRuntimeAvailable: Bool

    var body: some View {
        Group {
            switch stateOwner.state {
            case .notLoaded:
                IOSDestinationLoadingView(title: "Loading Settings")
            case .loadFailed:
                IOSDestinationLoadFailureView(
                    title: "Settings Unavailable",
                    description:
                        "HoldType couldn’t read your settings. Defaults were "
                        + "not substituted for the unreadable record.",
                    isRetrying: isLoading,
                    retry: retryLoad
                )
            case .ready(let settings):
                IOSSettingsSummaryList(
                    settings: settings,
                    showsSaveFailure: false,
                    openAIEditorDraft: $openAIEditorDraft,
                    hasUnsavedGeneralSettings:
                        $hasUnsavedGeneralSettings,
                    foregroundVoiceRuntimeAvailable:
                        foregroundVoiceRuntimeAvailable
                )
            case .saveFailed(let lastDurableValue):
                IOSSettingsSummaryList(
                    settings: lastDurableValue,
                    showsSaveFailure: true,
                    openAIEditorDraft: $openAIEditorDraft,
                    hasUnsavedGeneralSettings:
                        $hasUnsavedGeneralSettings,
                    foregroundVoiceRuntimeAvailable:
                        foregroundVoiceRuntimeAvailable
                )
            }
        }
        .navigationTitle("Settings")
        .accessibilityIdentifier(
            IOSContainingAppDestination.settings.accessibilityIdentifier
        )
        .navigationDestination(for: IOSSettingsRoute.self) { route in
            settingsDestination(route)
        }
        .task {
            guard case .notLoaded = stateOwner.state else { return }
            await load()
        }
    }

    private func retryLoad() {
        Task { await load() }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        _ = try? await stateOwner.load()
    }

    @ViewBuilder
    private func settingsDestination(_ route: IOSSettingsRoute) -> some View {
        switch route {
        case .privacyAndPermissions:
            if foregroundVoiceRuntimeAvailable {
                IOSPrivacyPermissionsView()
            } else {
                ContentUnavailableView(
                    "Privacy Status Unavailable",
                    systemImage: "hand.raised.slash",
                    description: Text(
                        "Foreground Voice is unavailable in this build."
                    )
                )
            }
        case .openAI:
            IOSOpenAISettingsView(editorDraft: $openAIEditorDraft)
        case .general(let destination):
            if let settings = currentSettings {
                generalSettingsDestination(destination, settings: settings)
            } else {
                IOSDestinationLoadingView(title: "Loading Settings")
            }
        }
    }

    @ViewBuilder
    private func generalSettingsDestination(
        _ destination: IOSGeneralSettingsDestination,
        settings: IOSAppSettings
    ) -> some View {
        switch destination {
        case .transcription:
            IOSTranscriptionSettingsView(
                configuration: settings.transcriptionConfiguration,
                hasUnsavedSceneEditor: $hasUnsavedGeneralSettings
            )
        case .writingCorrection:
            IOSWritingCorrectionSettingsView(
                configuration: settings.textCorrectionConfiguration,
                localTextCleanupEnabled: settings.localTextCleanupEnabled,
                hasUnsavedSceneEditor: $hasUnsavedGeneralSettings
            )
        case .translation:
            IOSTranslationSettingsView(
                configuration: settings.translationConfiguration,
                hasUnsavedSceneEditor: $hasUnsavedGeneralSettings
            )
        case .voiceRecording:
            IOSVoiceRecordingSettingsView(
                preferences: settings.voiceSessionPreferences,
                hasUnsavedSceneEditor: $hasUnsavedGeneralSettings
            )
        }
    }

    private var currentSettings: IOSAppSettings? {
        switch stateOwner.state {
        case .ready(let settings):
            settings
        case .saveFailed(let lastDurableValue):
            lastDurableValue
        case .notLoaded, .loadFailed:
            nil
        }
    }
}

private struct IOSSettingsSummaryList: View {
    @Environment(IOSOpenAICredentialSettingsStateOwner.self)
    private var openAISettingsStateOwner

    let settings: IOSAppSettings
    let showsSaveFailure: Bool
    @Binding var openAIEditorDraft: IOSOpenAICredentialEditorDraft
    @Binding var hasUnsavedGeneralSettings: Bool
    let foregroundVoiceRuntimeAvailable: Bool

    var body: some View {
        List {
            if showsSaveFailure {
                IOSSaveFailureSection(subject: "Settings")
            }

            Section("OpenAI") {
                NavigationLink(value: IOSSettingsRoute.openAI) {
                    IOSSettingsDestinationLabel(
                        title: "API Key",
                        summary: openAISummary,
                        systemImage: "key"
                    )
                }
                .accessibilityIdentifier("ios.settings.openai.row")
            }

            Section("Language & Writing") {
                NavigationLink(
                    value: IOSSettingsRoute.general(.transcription)
                ) {
                    IOSSettingsDestinationLabel(
                        title: IOSGeneralSettingsDestination
                            .transcription.title,
                        summary: transcriptionSummary,
                        systemImage: IOSGeneralSettingsDestination
                            .transcription.systemImage
                    )
                }
                .accessibilityIdentifier(
                    IOSGeneralSettingsDestination.transcription
                        .rowAccessibilityIdentifier
                )

                NavigationLink(
                    value: IOSSettingsRoute.general(.writingCorrection)
                ) {
                    IOSSettingsDestinationLabel(
                        title: IOSGeneralSettingsDestination
                            .writingCorrection.title,
                        summary: writingSummary,
                        systemImage: IOSGeneralSettingsDestination
                            .writingCorrection.systemImage
                    )
                }
                .accessibilityIdentifier(
                    IOSGeneralSettingsDestination.writingCorrection
                        .rowAccessibilityIdentifier
                )

                NavigationLink(
                    value: IOSSettingsRoute.general(.translation)
                ) {
                    IOSSettingsDestinationLabel(
                        title: IOSGeneralSettingsDestination.translation.title,
                        summary: translationPreferenceName(settings),
                        systemImage: IOSGeneralSettingsDestination.translation
                            .systemImage
                    )
                }
                .accessibilityIdentifier(
                    IOSGeneralSettingsDestination.translation
                        .rowAccessibilityIdentifier
                )
            }

            Section("Voice") {
                NavigationLink(
                    value: IOSSettingsRoute.general(.voiceRecording)
                ) {
                    IOSSettingsDestinationLabel(
                        title: IOSGeneralSettingsDestination
                            .voiceRecording.title,
                        summary: voiceSummary,
                        systemImage: IOSGeneralSettingsDestination
                            .voiceRecording.systemImage
                    )
                }
                .accessibilityIdentifier(
                    IOSGeneralSettingsDestination.voiceRecording
                        .rowAccessibilityIdentifier
                )

                LabeledContent("Maximum Utterance", value: "5 minutes")
            }

            if foregroundVoiceRuntimeAvailable {
                Section("Privacy") {
                    NavigationLink(
                        value: IOSSettingsRoute.privacyAndPermissions
                    ) {
                        IOSSettingsDestinationLabel(
                            title: "Privacy & Permissions",
                            summary:
                                "Microphone access and OpenAI processing consent",
                            systemImage: "hand.raised"
                        )
                    }
                    .accessibilityIdentifier(
                        "ios.settings.privacy-permissions.row"
                    )
                }
            }

            Section {
                Text(
                    "Prompts and complete settings stay in HoldType’s private "
                        + "storage and are never copied into the keyboard "
                        + "extension."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var transcriptionSummary: String {
        let configuration = settings.transcriptionConfiguration
        return transcriptionLanguageName(configuration)
            + " · "
            + IOSSettingsModelPresentation.summary(
                rawModel: configuration.model,
                defaultModel: TranscriptionConfiguration.defaultModel
            )
    }

    private var writingSummary: String {
        let correction = settings.textCorrectionConfiguration.isEnabled
            ? "Correction on"
            : "Correction off"
        let cleanup = settings.localTextCleanupEnabled
            ? "Cleanup on"
            : "Cleanup off"
        return correction + " · " + cleanup
    }

    private var voiceSummary: String {
        let cues = settings.voiceSessionPreferences.audioCuesEnabled
            ? "Sounds on"
            : "Sounds off"
        let tail = stopTailName(
            settings.voiceSessionPreferences.recordingStopTailDuration
        )
        return cues + " · Tail " + tail
    }

    private var openAISummary: String {
        switch openAISettingsStateOwner.state {
        case .unavailable:
            return "Secure storage unavailable"
        case .notLoaded:
            return "Open to view saved-key status"
        case .ready(let status):
            return status.primary.settingsSummary
        }
    }

    private func transcriptionLanguageName(
        _ configuration: TranscriptionConfiguration
    ) -> String {
        switch configuration.language {
        case .automatic:
            return "Auto"
        case .custom:
            switch configuration.customLanguageCodeValidation {
            case .emptyFallsBackToAutomatic:
                return "Auto (empty custom code)"
            case .invalid:
                return "Custom needs attention"
            case .valid(let normalizedCode):
                return "Custom (\(normalizedCode))"
            case .notRequired:
                return "Custom"
            }
        default:
            return configuration.language.iosSettingsLanguageName
        }
    }

    private func translationPreferenceName(
        _ settings: IOSAppSettings
    ) -> String {
        let configuration = settings.translationConfiguration
        guard configuration.actionPreferenceEnabled else {
            return "Action off"
        }
        return configuration.isConfigurationReady
            ? "Configured"
            : "Needs setup"
    }

    private func stopTailName(
        _ duration: RecordingStopTailDuration
    ) -> String {
        duration.iosSettingsDisplayName
    }
}

private struct IOSSettingsDestinationLabel: View {
    let title: String
    let summary: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

private extension IOSOpenAICredentialPrimaryStatus {
    var settingsSummary: String {
        switch self {
        case .notConfigured:
            "Not configured"
        case .notCheckedInThisProcess:
            "Not checked in this process"
        case .savedLastKnown:
            "Saved, last known"
        case .availableInThisProcess:
            "Available in this process"
        case .unavailableWhileLocked:
            "Unavailable while locked"
        case .providerRejected:
            "Provider rejected"
        }
    }
}
