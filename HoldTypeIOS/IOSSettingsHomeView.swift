import HoldTypeDomain
import HoldTypeIOSCore
import HoldTypePersistence
import SwiftUI

struct IOSSettingsHomeView: View {
    @Environment(IOSAppSettingsStateOwner.self) private var stateOwner
    @State private var isLoading = false
    @Binding var openAIEditorDraft: IOSOpenAICredentialEditorDraft
    @Binding var practiceText: String
    let foregroundVoiceRuntimeAvailable: Bool
    let reconcileRecordingCache: (RecordingCachePolicy) async -> Bool

    init(
        openAIEditorDraft: Binding<IOSOpenAICredentialEditorDraft>,
        practiceText: Binding<String>,
        foregroundVoiceRuntimeAvailable: Bool,
        reconcileRecordingCache: @escaping (
            RecordingCachePolicy
        ) async -> Bool = { _ in true }
    ) {
        _openAIEditorDraft = openAIEditorDraft
        _practiceText = practiceText
        self.foregroundVoiceRuntimeAvailable =
            foregroundVoiceRuntimeAvailable
        self.reconcileRecordingCache = reconcileRecordingCache
    }

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
                    foregroundVoiceRuntimeAvailable:
                        foregroundVoiceRuntimeAvailable
                )
            case .saveFailed(let lastDurableValue):
                IOSSettingsSummaryList(
                    settings: lastDurableValue,
                    showsSaveFailure: true,
                    openAIEditorDraft: $openAIEditorDraft,
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
        case .diagnostics:
            IOSDiagnosticsView()
        case .keyboardSetup:
            IOSKeyboardSetupView(practiceText: $practiceText)
        case .openAI:
            IOSOpenAISettingsView(editorDraft: $openAIEditorDraft)
        case .general(let destination):
            if let settings = currentSettings {
                generalSettingsDestination(destination, settings: settings)
            } else {
                IOSDestinationLoadingView(title: "Loading Settings")
            }
        case .attention(let attention):
            attentionDestination(attention)
        }
    }

    @ViewBuilder
    private func attentionDestination(
        _ attention: IOSSettingsAttention
    ) -> some View {
        switch attention {
        case .openAI:
            IOSOpenAISettingsView(
                editorDraft: $openAIEditorDraft,
                attentionTarget: IOSSettingsAttentionTarget(attention)
            )
        case .transcription, .translation:
            if let settings = currentSettings {
                let destination: IOSGeneralSettingsDestination =
                    attention == .transcription
                        ? .transcription
                        : .translation
                generalSettingsDestination(
                    destination,
                    settings: settings,
                    attentionTarget: attentionTarget(
                        attention,
                        settings: settings
                    )
                )
            } else {
                IOSDestinationLoadingView(title: "Loading Settings")
            }
        case .keyboard, .fullAccess:
            IOSKeyboardSetupView(
                practiceText: $practiceText,
                attentionTarget: IOSSettingsAttentionTarget(attention)
            )
        case .privacyReview, .microphonePermission:
            if foregroundVoiceRuntimeAvailable {
                IOSPrivacyPermissionsView(
                    attentionTarget: IOSSettingsAttentionTarget(attention)
                )
            } else {
                ContentUnavailableView(
                    "Privacy Status Unavailable",
                    systemImage: "hand.raised.slash",
                    description: Text(
                        "Foreground Voice is unavailable in this build."
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func generalSettingsDestination(
        _ destination: IOSGeneralSettingsDestination,
        settings: IOSAppSettings,
        attentionTarget: IOSSettingsAttentionTarget? = nil
    ) -> some View {
        switch destination {
        case .transcription:
            IOSTranscriptionSettingsView(
                configuration: settings.transcriptionConfiguration,
                attentionTarget: attentionTarget
            )
        case .writingCorrection:
            IOSWritingCorrectionSettingsView(
                configuration: settings.textCorrectionConfiguration,
                localTextCleanupEnabled: settings.localTextCleanupEnabled,
                attentionTarget: attentionTarget
            )
        case .translation:
            IOSTranslationSettingsView(
                configuration: settings.translationConfiguration,
                attentionTarget: attentionTarget
            )
        case .voiceRecording:
            IOSVoiceRecordingSettingsView(
                preferences: settings.voiceSessionPreferences,
                recordingCachePolicy: settings.recordingCachePolicy,
                attentionTarget: attentionTarget,
                reconcileRecordingCache: reconcileRecordingCache
            )
        }
    }

    private func attentionTarget(
        _ attention: IOSSettingsAttention,
        settings: IOSAppSettings
    ) -> IOSSettingsAttentionTarget {
        switch attention {
        case .transcription:
            let configuration = settings.transcriptionConfiguration
            let field: IOSSettingsField = configuration.language == .custom
                && configuration.customLanguageCodeValidation.isInvalid
                ? .transcriptionCustomLanguage
                : .transcriptionLanguage
            return IOSSettingsAttentionTarget(attention, field: field)
        case .translation:
            let configuration = settings.translationConfiguration
            let field: IOSSettingsField
            switch configuration.routeConfigurationIssue {
            case .invalidSourceLanguage:
                field = configuration.sourceLanguage == .custom
                    ? .translationCustomSource
                    : .translationSourceLanguage
            case .missingTargetLanguage:
                field = configuration.targetLanguage == .custom
                    ? .translationCustomTarget
                    : .translationTargetLanguage
            case nil:
                field = .translationTargetLanguage
            }
            return IOSSettingsAttentionTarget(attention, field: field)
        default:
            return IOSSettingsAttentionTarget(attention)
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
                NavigationLink(value: IOSSettingsRoute.keyboardSetup) {
                    IOSSettingsDestinationLabel(
                        title: "Keyboard & Full Access",
                        summary: "Setup, verification, and practice",
                        systemImage: "keyboard.badge.ellipsis"
                    )
                }
                .accessibilityIdentifier("ios.settings.keyboard-setup.row")

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

            Section("Development") {
                NavigationLink(value: IOSSettingsRoute.diagnostics) {
                    IOSSettingsDestinationLabel(
                        title: "Diagnostics & Support",
                        summary: "Logs, crash data, and export",
                        systemImage: "wrench.and.screwdriver"
                    )
                }
                .accessibilityIdentifier(
                    "ios.settings.diagnostics.row"
                )
            }

        }
    }

    private var transcriptionSummary: String {
        transcriptionLanguageName(settings.transcriptionConfiguration)
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
        return cues
            + " · Finish buffer "
            + tail
            + " · "
            + settings.recordingCachePolicy.iosSettingsSummary
    }

    private var openAISummary: String {
        switch openAISettingsStateOwner.state {
        case .unavailable:
            return "Saved key unavailable"
        case .notLoaded:
            return "Open to check your key"
        case .ready(let status):
            return IOSOpenAICredentialPresentation(status: status)
                .settingsSummary
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
