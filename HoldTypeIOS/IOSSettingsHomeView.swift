import HoldTypeDomain
import HoldTypePersistence
import SwiftUI

struct IOSSettingsHomeView: View {
    @Environment(IOSAppSettingsStateOwner.self) private var stateOwner
    @State private var isLoading = false

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
                    showsSaveFailure: false
                )
            case .saveFailed(let lastDurableValue):
                IOSSettingsSummaryList(
                    settings: lastDurableValue,
                    showsSaveFailure: true
                )
            }
        }
        .navigationTitle("Settings")
        .accessibilityIdentifier(
            IOSContainingAppDestination.settings.accessibilityIdentifier
        )
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
}

private struct IOSSettingsSummaryList: View {
    let settings: IOSAppSettings
    let showsSaveFailure: Bool

    var body: some View {
        List {
            if showsSaveFailure {
                IOSSaveFailureSection(subject: "Settings")
            }

            Section("Saved Transcription Configuration") {
                LabeledContent(
                    "Model",
                    value: settings.transcriptionConfiguration.resolvedModel
                )
                LabeledContent(
                    "Language",
                    value: transcriptionLanguageName(
                        settings.transcriptionConfiguration
                    )
                )
            }

            Section("Saved Writing Preferences") {
                LabeledContent(
                    "Local cleanup",
                    value: preferenceName(settings.localTextCleanupEnabled)
                )
                LabeledContent(
                    "OpenAI correction",
                    value: preferenceName(
                        settings.textCorrectionConfiguration.isEnabled
                    )
                )
                LabeledContent(
                    "Translate action",
                    value: translationPreferenceName(settings)
                )
            }

            Section("Voice & Result Behavior") {
                LabeledContent(
                    "Recording sounds",
                    value: preferenceName(
                        settings.voiceSessionPreferences.audioCuesEnabled
                    )
                )
                LabeledContent(
                    "Stop tail",
                    value: stopTailName(
                        settings.voiceSessionPreferences
                            .recordingStopTailDuration
                    )
                )
                LabeledContent(
                    "Keep latest result",
                    value: preferenceName(settings.keepLatestResult)
                )
                LabeledContent("Maximum utterance", value: "5 minutes")
            }

            Section {
                Text(
                    "Prompts and complete settings stay in HoldType’s private "
                    + "storage and are never copied into the keyboard extension."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func transcriptionLanguageName(
        _ configuration: TranscriptionConfiguration
    ) -> String {
        switch configuration.language {
        case .automatic:
            return "Automatic"
        case .custom:
            switch configuration.customLanguageCodeValidation {
            case .emptyFallsBackToAutomatic:
                return "Automatic (empty custom code)"
            case .invalid:
                return "Needs attention"
            case .valid(let normalizedCode):
                return "Custom (\(normalizedCode))"
            case .notRequired:
                return "Custom"
            }
        default:
            return configuration.language.rawValue.capitalized
        }
    }

    private func preferenceName(_ isEnabled: Bool) -> String {
        isEnabled ? "Preference on" : "Preference off"
    }

    private func translationPreferenceName(
        _ settings: IOSAppSettings
    ) -> String {
        let configuration = settings.translationConfiguration
        guard configuration.actionPreferenceEnabled else {
            return "Preference off"
        }
        return configuration.isConfigurationReady
            ? "Configured"
            : "Needs setup"
    }

    private func stopTailName(
        _ duration: RecordingStopTailDuration
    ) -> String {
        switch duration {
        case .off:
            return "Off"
        case .milliseconds500:
            return "0.5 seconds"
        case .seconds1:
            return "1 second"
        case .seconds1_5:
            return "1.5 seconds"
        case .seconds2:
            return "2 seconds"
        }
    }
}
