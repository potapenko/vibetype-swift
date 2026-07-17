import Foundation
import HoldTypeDomain
import HoldTypeIOSCore
@_spi(HoldTypeIOSCore) import HoldTypePersistence

struct IOSKeyboardHandoffSupersessionClient: Sendable {
    let retire: @MainActor @Sendable (UUID) async -> Bool

    nonisolated static func passThrough() -> Self {
        Self { _ in true }
    }

    static func live(
        persistenceOwner: IOSV1ForegroundVoicePersistenceOwner
    ) -> Self {
        Self { _ in
            // Complete accepted-output cleanup first. This preserves Latest
            // and History while removing only its obsolete local audio owner.
            _ = await persistenceOwner.recoverContainingAppLifecycle(
                .foregroundOpportunity
            )

            do {
                // Supersession owns session routing only. Any canonical
                // Pending recording is already durable user audio and blocks
                // replacement until it succeeds or the user explicitly
                // discards it.
                if try await persistenceOwner.load() != nil {
                    return false
                }

                switch await persistenceOwner
                    .reconcileCaptureSourcesAtLaunch() {
                case .recoverable, .blocked:
                    return false
                case .discardOnly(let captureAttemptID):
                    // Exact zero-byte capture owns no user effort. It is the
                    // sole automatic cleanup allowed during supersession.
                    try await persistenceOwner.discardCapture(
                        attemptID: captureAttemptID
                    )
                case .empty:
                    break
                }

                guard try await persistenceOwner.load() == nil else {
                    return false
                }
                switch await persistenceOwner
                    .reconcileCaptureSourcesAtLaunch() {
                case .empty:
                    return true
                case .recoverable, .discardOnly, .blocked:
                    return false
                }
            } catch {
                return false
            }
        }
    }
}

nonisolated enum IOSKeyboardHandoffPreflightIssue: Equatable, Sendable {
    case localDataUnavailable
    case transcriptionConfiguration
    case translationConfiguration
    case providerConsent
    case openAICredential
    case microphonePermission
    case microphoneUnavailable

    var title: String {
        switch self {
        case .localDataUnavailable:
            "HoldType data is unavailable"
        case .transcriptionConfiguration:
            "Check transcription settings"
        case .translationConfiguration:
            "Finish translation setup"
        case .providerConsent:
            "Review OpenAI processing"
        case .openAICredential:
            "Add your OpenAI key"
        case .microphonePermission:
            "Allow microphone access"
        case .microphoneUnavailable:
            "Microphone is unavailable"
        }
    }

    var detail: String {
        switch self {
        case .localDataUnavailable:
            "Close this sheet and try again after HoldType can read its local data."
        case .transcriptionConfiguration:
            "Complete the transcription language setup, then start a new keyboard dictation."
        case .translationConfiguration:
            "Choose a valid translation route, then start a new keyboard dictation."
        case .providerConsent:
            "Accept the current OpenAI processing disclosure before starting keyboard dictation."
        case .openAICredential:
            "Save a readable OpenAI API key, then start a new keyboard dictation."
        case .microphonePermission:
            "Allow HoldType to use the microphone, then start a new keyboard dictation."
        case .microphoneUnavailable:
            "HoldType could not access the microphone. Close this sheet and try again."
        }
    }
}

nonisolated enum IOSKeyboardHandoffPreflightResult: Equatable, Sendable {
    case ready
    case blocked(IOSKeyboardHandoffPreflightIssue)
}

struct IOSKeyboardHandoffPreflightClient: Sendable {
    let run: @MainActor @Sendable (
        KeyboardHandoffIntentRecord
    ) async -> IOSKeyboardHandoffPreflightResult

    nonisolated static func passThrough() -> Self {
        Self { _ in .ready }
    }

    @MainActor
    static func live(
        settingsStateOwner: IOSAppSettingsStateOwner?,
        credentialCoordinator: IOSOpenAICredentialCoordinator?,
        providerConsentCoordinator: IOSV1ProviderConsentCoordinator?,
        permission: IOSForegroundVoiceWorkflowPermissionClient
    ) -> Self {
        Self { intent in
            guard let settingsStateOwner,
                  let credentialCoordinator,
                  let providerConsentCoordinator else {
                return .blocked(.localDataUnavailable)
            }

            let settings: IOSAppSettings
            do {
                settings = try await settingsStateOwner
                    .confirmedValueForProviderAction()
            } catch {
                return .blocked(.localDataUnavailable)
            }
            guard !settings.transcriptionConfiguration
                .customLanguageCodeValidation.isInvalid else {
                return .blocked(.transcriptionConfiguration)
            }
            if intent.action.translates,
               !settings.translationConfiguration.isConfigurationReady {
                return .blocked(.translationConfiguration)
            }

            let consent = await providerConsentCoordinator.observe()
            guard consent.status == .acceptedCurrentDisclosure else {
                return .blocked(.providerConsent)
            }

            do {
                let credential = try await credentialCoordinator.resolve(
                    for: .voicePreflight
                )
                guard case .available = credential.resolution else {
                    return .blocked(.openAICredential)
                }
            } catch {
                return .blocked(.openAICredential)
            }

            switch permission.read() {
            case .granted:
                return .ready
            case .undetermined:
                switch await permission.requestIfUndetermined() {
                case .granted:
                    return permission.read() == .granted
                        ? .ready
                        : .blocked(.microphoneUnavailable)
                case .denied:
                    return .blocked(.microphonePermission)
                case .unavailable, .timedOut, .cancelled:
                    return .blocked(.microphoneUnavailable)
                }
            case .denied:
                return .blocked(.microphonePermission)
            case .unavailable:
                return .blocked(.microphoneUnavailable)
            }
        }
    }
}
