import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
import HoldTypePersistence

nonisolated enum IOSKeyboardFixProductionFactory {
    @MainActor
    static func makeRuntimeOwner(
        catalogRepository: TextFixCatalogRepository,
        settingsStateOwner: IOSAppSettingsStateOwner,
        consentCoordinator: IOSV1ProviderConsentCoordinator,
        credentialCoordinator: IOSOpenAICredentialCoordinator?,
        foregroundVoiceProcessor: IOSForegroundVoiceProcessor?
    ) -> IOSKeyboardFixRuntimeOwner? {
        guard let store = try? KeyboardFixBridgeStore.appGroup() else {
            return nil
        }

        let metadataPublisher = IOSKeyboardFixMetadataPublisher(
            loadCatalog: {
                try await catalogRepository.load()
            },
            store: IOSKeyboardFixMetadataStoreClient(store: store)
        )
        let backgroundTaskRegistry =
            IOSKeyboardFixBackgroundTaskRegistry.production()
        let processor = IOSKeyboardFixProcessor(
            bridge: IOSKeyboardFixBridgeClient(store: store),
            catalog: IOSKeyboardFixCatalogClient(
                load: {
                    try await catalogRepository.load()
                }
            ),
            settings: IOSKeyboardFixProductionClients.makeSettingsClient(
                owner: settingsStateOwner
            ),
            consent: IOSKeyboardFixProductionClients.makeConsentClient(
                coordinator: consentCoordinator
            ),
            credential: IOSKeyboardFixProductionClients
                .makeCredentialClient(
                    coordinator: credentialCoordinator
                ),
            executor: IOSKeyboardFixProductionClients.makeExecutionClient(
                settingsOwner: settingsStateOwner,
                consentCoordinator: consentCoordinator,
                credentialCoordinator: credentialCoordinator,
                processor: foregroundVoiceProcessor
            ),
            backgroundTask: backgroundTaskRegistry.client,
            signals: IOSKeyboardFixProductionClients.resultSignalClient
        )
        return IOSKeyboardFixRuntimeOwner(
            processor: processor,
            metadataPublisher: metadataPublisher,
            requestObservation: .production(),
            backgroundTaskRegistry: backgroundTaskRegistry
        )
    }
}
