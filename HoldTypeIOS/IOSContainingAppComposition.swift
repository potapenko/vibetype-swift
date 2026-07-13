import Foundation
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
import HoldTypeOpenAI
@_spi(HoldTypeIOSCore) import HoldTypePersistence

enum IOSContainingAppCompositionAvailability: Equatable {
    case ready
    case credentialUnavailable
    case storageUnavailable
    case injected
}

/// One process-owned dependency graph shared by every containing-app scene.
/// Construction is synchronous and passive: it never reads Keychain, contacts
/// a provider, or performs persistence recovery inline.
@MainActor
final class IOSContainingAppComposition {
    struct Factories {
        let resolveApplicationSupportDirectoryURL: @MainActor () throws -> URL
        let resolveApplicationIdentifierAccessGroup: @MainActor () -> String?
        let makeSettingsStateOwner: @MainActor (
            URL
        ) -> IOSAppSettingsStateOwner
        let makeLibraryStateOwner: @MainActor (
            URL
        ) -> IOSLibraryStateOwner
        let makeCredentialCoordinator: @MainActor (
            URL,
            String
        ) throws -> IOSOpenAICredentialCoordinator
        let makeProviderConsentCoordinator: @MainActor (
            URL
        ) -> IOSV1ProviderConsentCoordinator
        let makeForegroundVoicePersistenceOwner: @MainActor (
            URL,
            IOSAcceptedTextHistoryRepository
        ) -> IOSV1ForegroundVoicePersistenceOwner
        let makeTranscriptionUsageRepository: @MainActor (
            URL
        ) -> IOSTranscriptionUsageRepository
        let makeForegroundVoiceProcessor: @MainActor (
            IOSV1ForegroundVoicePersistenceOwner,
            IOSV1ProviderConsentCoordinator,
            IOSTranscriptionUsageRecordingClient,
            IOSOpenAICredentialCoordinator
        ) -> IOSForegroundVoiceProcessor
        var voiceFactories: IOSForegroundVoiceRuntime.Factories = .production

        static let production = Factories(
            resolveApplicationSupportDirectoryURL: {
                try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
            },
            resolveApplicationIdentifierAccessGroup: {
                IOSContainingAppComposition.applicationIdentifierAccessGroup(
                    in: .main
                )
            },
            makeSettingsStateOwner: { applicationSupportDirectoryURL in
                IOSAppSettingsStateOwner(
                    applicationSupportDirectoryURL:
                        applicationSupportDirectoryURL
                )
            },
            makeLibraryStateOwner: { applicationSupportDirectoryURL in
                IOSLibraryStateOwner(
                    applicationSupportDirectoryURL:
                        applicationSupportDirectoryURL
                )
            },
            makeCredentialCoordinator: {
                applicationSupportDirectoryURL,
                applicationIdentifierAccessGroup in
                try IOSOpenAICredentialCoordinator(
                    applicationSupportDirectoryURL:
                        applicationSupportDirectoryURL,
                    applicationIdentifierAccessGroup:
                        applicationIdentifierAccessGroup,
                    keychainAccessMode:
                        .currentProcessDefault()
                )
            },
            makeProviderConsentCoordinator: {
                applicationSupportDirectoryURL in
                IOSV1ProviderConsentCoordinator(
                    applicationSupportDirectoryURL:
                        applicationSupportDirectoryURL
                )
            },
            makeForegroundVoicePersistenceOwner: {
                applicationSupportDirectoryURL,
                acceptedTextHistoryRepository in
                IOSV1ForegroundVoicePersistenceOwner(
                    applicationSupportDirectoryURL:
                        applicationSupportDirectoryURL,
                    acceptedTextHistoryRepository:
                        acceptedTextHistoryRepository
                )
            },
            makeTranscriptionUsageRepository: {
                applicationSupportDirectoryURL in
                IOSTranscriptionUsageRepository(
                    applicationSupportDirectoryURL:
                        applicationSupportDirectoryURL
                )
            },
            makeForegroundVoiceProcessor: {
                persistenceOwner,
                consentCoordinator,
                usageRecordingClient,
                credentialCoordinator in
                IOSForegroundVoiceProcessor(
                    persistenceOwner: persistenceOwner,
                    consentCoordinator: consentCoordinator,
                    usageRecordingClient: usageRecordingClient,
                    credentialCoordinator: credentialCoordinator
                )
            }
        )
    }

    let applicationSupportDirectoryURL: URL?
    let settingsStateOwner: IOSAppSettingsStateOwner?
    let libraryStateOwner: IOSLibraryStateOwner?
    let credentialCoordinator: IOSOpenAICredentialCoordinator?
    let openAISettingsStateOwner: IOSOpenAICredentialSettingsStateOwner?
    let providerConsentCoordinator: IOSV1ProviderConsentCoordinator?
    let acceptedTextHistoryRepository:
        IOSAcceptedTextHistoryRepository?
    let acceptedTextHistoryStateOwner:
        IOSAcceptedTextHistoryStateOwner?
    let foregroundVoicePersistenceOwner:
        IOSV1ForegroundVoicePersistenceOwner?
    let transcriptionUsageRepository: IOSTranscriptionUsageRepository?
    let usageEstimateStateOwner: IOSUsageEstimateStateOwner?
    let foregroundVoiceProcessor: IOSForegroundVoiceProcessor?
    let foregroundVoiceRuntime: IOSForegroundVoiceRuntime?
    let lifecycleScheduler: IOSContainingAppLifecycleScheduler
    let voiceSceneLifecycleBinding: IOSVoiceSceneLifecycleBinding?
    let availability: IOSContainingAppCompositionAvailability

    init(
        factories: Factories? = nil,
        scheduleProviderStartupMaintenance: @MainActor () -> Void = {
            OpenAIProviderStartupMaintenance.schedule()
        }
    ) {
        let factories = factories ?? .production
        let applicationSupportDirectoryURL: URL
        do {
            applicationSupportDirectoryURL = try factories
                .resolveApplicationSupportDirectoryURL()
        } catch {
            self.applicationSupportDirectoryURL = nil
            settingsStateOwner = nil
            libraryStateOwner = nil
            credentialCoordinator = nil
            openAISettingsStateOwner = nil
            providerConsentCoordinator = nil
            acceptedTextHistoryRepository = nil
            acceptedTextHistoryStateOwner = nil
            foregroundVoicePersistenceOwner = nil
            transcriptionUsageRepository = nil
            usageEstimateStateOwner = nil
            foregroundVoiceProcessor = nil
            foregroundVoiceRuntime = nil
            availability = .storageUnavailable
            lifecycleScheduler = IOSContainingAppLifecycleScheduler { _ in
                .pendingLocalRecovery
            }
            voiceSceneLifecycleBinding = nil
            scheduleStartup(
                scheduleProviderStartupMaintenance:
                    scheduleProviderStartupMaintenance
            )
            return
        }

        self.applicationSupportDirectoryURL =
            applicationSupportDirectoryURL
        let settingsStateOwner = factories.makeSettingsStateOwner(
            applicationSupportDirectoryURL
        )
        self.settingsStateOwner = settingsStateOwner
        let libraryStateOwner = factories.makeLibraryStateOwner(
            applicationSupportDirectoryURL
        )
        self.libraryStateOwner = libraryStateOwner
        let providerConsentCoordinator = factories
            .makeProviderConsentCoordinator(
                applicationSupportDirectoryURL
            )
        self.providerConsentCoordinator = providerConsentCoordinator
        let acceptedTextHistoryRepository =
            IOSAcceptedTextHistoryRepository(
                applicationSupportDirectoryURL:
                    applicationSupportDirectoryURL
            )
        self.acceptedTextHistoryRepository =
            acceptedTextHistoryRepository
        acceptedTextHistoryStateOwner =
            IOSAcceptedTextHistoryStateOwner(
                repository: acceptedTextHistoryRepository
            )
        let foregroundVoicePersistenceOwner = factories
            .makeForegroundVoicePersistenceOwner(
                applicationSupportDirectoryURL,
                acceptedTextHistoryRepository
            )
        self.foregroundVoicePersistenceOwner =
            foregroundVoicePersistenceOwner
        let transcriptionUsageRepository = factories
            .makeTranscriptionUsageRepository(
                applicationSupportDirectoryURL
            )
        self.transcriptionUsageRepository = transcriptionUsageRepository
        let usageEstimateStateOwner = IOSUsageEstimateStateOwner(
            repository: transcriptionUsageRepository
        )
        self.usageEstimateStateOwner = usageEstimateStateOwner
        let usageRecordingClient = IOSTranscriptionUsageRecordingClient(
            repository: transcriptionUsageRepository,
            reportFailure: { token in
                await usageEstimateStateOwner.reportWriteFailure(token)
            }
        )

        let credentialCoordinator: IOSOpenAICredentialCoordinator?
        if let applicationIdentifierAccessGroup = factories
            .resolveApplicationIdentifierAccessGroup() {
            credentialCoordinator = try? factories.makeCredentialCoordinator(
                applicationSupportDirectoryURL,
                applicationIdentifierAccessGroup
            )
        } else {
            credentialCoordinator = nil
        }
        self.credentialCoordinator = credentialCoordinator
        openAISettingsStateOwner = IOSOpenAICredentialSettingsStateOwner(
            client: credentialCoordinator.map {
                IOSOpenAICredentialSettingsClient(coordinator: $0)
            }
        )
        let foregroundVoiceProcessor = credentialCoordinator.map {
            factories.makeForegroundVoiceProcessor(
                foregroundVoicePersistenceOwner,
                providerConsentCoordinator,
                usageRecordingClient,
                $0
            )
        }
        self.foregroundVoiceProcessor = foregroundVoiceProcessor
        availability = credentialCoordinator == nil
            ? .credentialUnavailable
            : .ready
        let foregroundVoiceRuntime = IOSForegroundVoiceRuntime(
            settingsStateOwner: settingsStateOwner,
            libraryStateOwner: libraryStateOwner,
            providerConsentCoordinator: providerConsentCoordinator,
            persistenceOwner: foregroundVoicePersistenceOwner,
            credentialCoordinator: credentialCoordinator,
            processor: foregroundVoiceProcessor,
            factories: factories.voiceFactories
        )
        self.foregroundVoiceRuntime = foregroundVoiceRuntime
        let lifecycleScheduler = IOSContainingAppLifecycleScheduler(
            recover: foregroundVoiceRuntime.lifecycleCoordinator
                .schedulerRecovery
        )
        self.lifecycleScheduler = lifecycleScheduler
        voiceSceneLifecycleBinding = IOSVoiceSceneLifecycleBinding(
            registry: foregroundVoiceRuntime.sceneRegistry,
            scheduler: lifecycleScheduler
        )
        scheduleStartup(
            scheduleProviderStartupMaintenance:
                scheduleProviderStartupMaintenance
        )
    }

    /// Retains the existing app test seam without constructing production
    /// storage, Keychain, or provider dependencies.
    init(
        scheduleProviderStartupMaintenance: @MainActor () -> Void,
        recoverContainingAppLifecycle:
            @escaping IOSContainingAppLifecycleScheduler.Recovery
    ) {
        applicationSupportDirectoryURL = nil
        settingsStateOwner = nil
        libraryStateOwner = nil
        credentialCoordinator = nil
        openAISettingsStateOwner = nil
        providerConsentCoordinator = nil
        acceptedTextHistoryRepository = nil
        acceptedTextHistoryStateOwner = nil
        foregroundVoicePersistenceOwner = nil
        transcriptionUsageRepository = nil
        usageEstimateStateOwner = nil
        foregroundVoiceProcessor = nil
        foregroundVoiceRuntime = nil
        availability = .injected
        lifecycleScheduler = IOSContainingAppLifecycleScheduler(
            recover: recoverContainingAppLifecycle
        )
        voiceSceneLifecycleBinding = nil
        scheduleStartup(
            scheduleProviderStartupMaintenance:
                scheduleProviderStartupMaintenance
        )
    }

    static func applicationIdentifierAccessGroup(
        in bundle: Bundle
    ) -> String? {
        bundle.object(
            forInfoDictionaryKey:
                OpenAIAPIKeyKeychainStorage
                    .applicationIdentifierAccessGroupInfoKey
        ) as? String
    }

    private func scheduleStartup(
        scheduleProviderStartupMaintenance: @MainActor () -> Void
    ) {
        _ = IOSContainingAppStartup(
            scheduleProviderStartupMaintenance:
                scheduleProviderStartupMaintenance,
            scheduleContainingAppRecovery: {
                lifecycleScheduler.scheduleProcessLaunch()
            }
        )
    }
}

extension IOSContainingAppComposition:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    nonisolated var description: String {
        "IOSContainingAppComposition(<redacted>)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSContainingAppCompositionAvailability:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSContainingAppCompositionAvailability(redacted)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
