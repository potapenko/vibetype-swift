import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
@_spi(HoldTypeIOSCore) import HoldTypePersistence

nonisolated enum IOSKeyboardFixProductionClients {
    @MainActor
    static func makeSettingsClient(
        owner: IOSAppSettingsStateOwner
    ) -> IOSKeyboardFixSettingsClient {
        IOSKeyboardFixSettingsClient { action in
            let settings = try await owner.confirmedValueForProviderAction()
            if action.kind == .translate,
               !settings.translationConfiguration.isConfigurationReady {
                return .translationUnavailable
            }
            return .ready
        }
    }

    static func makeConsentClient(
        coordinator: IOSV1ProviderConsentCoordinator
    ) -> IOSKeyboardFixConsentV4Client {
        IOSKeyboardFixConsentV4Client {
            let observation = await coordinator.observe()
            return coordinator.makeAuthorization(from: observation) != nil
        }
    }

    static func makeCredentialClient(
        coordinator: IOSOpenAICredentialCoordinator?
    ) -> IOSKeyboardFixCredentialClient {
        IOSKeyboardFixCredentialClient {
            guard let coordinator else { return false }
            let outcome = try await coordinator.resolve(
                for: .voicePreflight
            )
            guard case .available = outcome.resolution else {
                return false
            }
            return true
        }
    }

    @MainActor
    static func makeExecutionClient(
        settingsOwner: IOSAppSettingsStateOwner,
        consentCoordinator: IOSV1ProviderConsentCoordinator,
        credentialCoordinator: IOSOpenAICredentialCoordinator?,
        processor: IOSForegroundVoiceProcessor?
    ) -> IOSKeyboardFixExecutionClient {
        IOSKeyboardFixExecutionClient { input in
            guard let credentialCoordinator, let processor else {
                throw IOSKeyboardFixExecutionFailure
                    .credentialUnavailable
            }

            let settings: IOSAppSettings
            do {
                settings = try await settingsOwner
                    .confirmedValueForProviderAction()
            } catch {
                throw IOSKeyboardFixExecutionFailure.persistenceFailed
            }

            let consentObservation = await consentCoordinator.observe()
            guard consentCoordinator.makeAuthorization(
                from: consentObservation
            ) != nil else {
                throw IOSKeyboardFixExecutionFailure.consentRequired
            }

            let credential: IOSResolvedOpenAICredential
            do {
                let outcome = try await credentialCoordinator.resolve(
                    for: .voicePreflight
                )
                guard case .available(let value) = outcome.resolution else {
                    throw IOSKeyboardFixExecutionFailure
                        .credentialUnavailable
                }
                credential = value
            } catch let failure as IOSKeyboardFixExecutionFailure {
                throw failure
            } catch is CancellationError {
                throw IOSKeyboardFixExecutionFailure.cancelled
            } catch {
                throw IOSKeyboardFixExecutionFailure
                    .credentialUnavailable
            }

            let resolution = await processor.processDraftTextFix(
                IOSVoiceDraftTextFixRequest(
                    action: input.action,
                    text: input.sourceText,
                    settings: settings,
                    credential: credential,
                    consentObservation: consentObservation
                )
            )
            return try output(
                from: resolution,
                action: input.action
            )
        }
    }

    static var resultSignalClient: IOSKeyboardFixSignalClient {
        IOSKeyboardFixSignalClient { signal in
            switch signal {
            case .processing, .terminal, .expired:
                KeyboardFixBridgeSignal.postResultChanged()
            case .cancellationAcknowledged:
                KeyboardFixBridgeSignal.postCancellationChanged()
            case .bridgeUnavailable, .rejectedWhileBusy:
                break
            }
        }
    }

    static func output(
        from resolution: IOSVoiceDraftTextActionResolution,
        action: TextFixAction
    ) throws -> String {
        switch resolution {
        case .success(let output):
            return output
        case .failure(let failure):
            throw executionFailure(from: failure, action: action)
        }
    }

    static func executionFailure(
        from failure: IOSVoiceDraftTextActionFailure,
        action: TextFixAction
    ) -> IOSKeyboardFixExecutionFailure {
        switch failure {
        case .busy:
            .actionUnavailable
        case .invalidText, .sourceTooLarge, .invalidResponse:
            .invalidOutput
        case .invalidConfiguration where action.kind == .translate:
            .translationUnavailable
        case .invalidConfiguration:
            .actionUnavailable
        case .credentialUnavailable:
            .credentialUnavailable
        case .consentUnavailable:
            .consentRequired
        case .networkUnavailable, .providerUnavailable:
            .providerFailed
        case .timedOut:
            .timedOut
        case .draftChanged, .saveFailed:
            .persistenceFailed
        case .cancelled:
            .cancelled
        }
    }
}
