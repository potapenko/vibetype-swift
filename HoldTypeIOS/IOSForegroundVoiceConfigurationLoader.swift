import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypePersistence

enum IOSForegroundVoiceConfigurationResolution {
    case available(IOSForegroundVoiceWorkflowConfiguration)
    case settingsUnavailable
    case libraryUnavailable
    case invalid(RecoveryDestination)
}

@MainActor
struct IOSForegroundVoiceConfigurationLoader {
    typealias LoadSettings = @Sendable () async throws -> IOSAppSettings
    typealias LoadLibrary = @Sendable () async throws -> IOSLibraryContent

    private let loadSettings: LoadSettings
    private let loadLibrary: LoadLibrary

    init(
        loadSettings: @escaping LoadSettings,
        loadLibrary: @escaping LoadLibrary
    ) {
        self.loadSettings = loadSettings
        self.loadLibrary = loadLibrary
    }

    func loadKeyboardTranslationAvailability() async -> Bool {
        guard let settings = try? await loadSettings() else {
            return false
        }
        guard !settings.transcriptionConfiguration
            .customLanguageCodeValidation.isInvalid else {
            return false
        }
        return settings.translationConfiguration.isConfigurationReady
    }

    func load(
        _ intent: DictationOutputIntent,
        validateProviderSettings: Bool = true,
        continueIf: @MainActor () -> Bool = { true }
    ) async -> IOSForegroundVoiceConfigurationResolution {
        let settings: IOSAppSettings
        do {
            settings = try await loadSettings()
        } catch {
            return .settingsUnavailable
        }
        guard continueIf() else { return .settingsUnavailable }

        let library: IOSLibraryContent
        do {
            library = try await loadLibrary()
        } catch {
            return .libraryUnavailable
        }
        guard continueIf() else { return .libraryUnavailable }

        let configuration = IOSForegroundVoiceWorkflowConfiguration(
            settings: settings,
            library: library
        )
        if validateProviderSettings,
           let destination = invalidProviderConfigurationDestination(
               intent,
               configuration: configuration
           ) {
            return .invalid(destination)
        }
        return .available(configuration)
    }

    func invalidProviderConfigurationDestination(
        _ intent: DictationOutputIntent,
        configuration: IOSForegroundVoiceWorkflowConfiguration
    ) -> RecoveryDestination? {
        if configuration.settings.transcriptionConfiguration
            .customLanguageCodeValidation.isInvalid {
            return .transcription
        }
        if intent == .translate,
           !configuration.settings.translationConfiguration
            .isConfigurationReady {
            return .translation
        }
        return nil
    }
}
