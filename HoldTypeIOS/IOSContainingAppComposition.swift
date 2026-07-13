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
        let makeHistoryCoordinator: @MainActor (
            URL
        ) -> IOSAcceptedHistoryCoordinator
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
        let makeFailedHistoryService: @MainActor (
            URL,
            IOSAppSettingsStateOwner,
            IOSLibraryStateOwner,
            IOSOpenAICredentialCoordinator?
        ) -> IOSFailedHistoryService
        let makeProviderConsentCoordinator: @MainActor (
            URL
        ) -> IOSProviderConsentCoordinator
        let makeForegroundVoicePersistenceOwner: @MainActor (
            URL
        ) -> IOSForegroundVoicePersistenceOwner
        let makeTranscriptionUsageRepository: @MainActor (
            URL
        ) -> IOSTranscriptionUsageRepository
        let makeForegroundVoiceProcessor: @MainActor (
            IOSForegroundVoicePersistenceOwner,
            IOSProviderConsentCoordinator,
            IOSTranscriptionUsageRepository,
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
            makeHistoryCoordinator: { applicationSupportDirectoryURL in
                IOSAcceptedHistoryCoordinator(
                    applicationSupportDirectoryURL:
                        applicationSupportDirectoryURL
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
            makeFailedHistoryService: {
                applicationSupportDirectoryURL,
                settingsStateOwner,
                libraryStateOwner,
                credentialCoordinator in
                IOSFailedHistoryService(
                    applicationSupportDirectoryURL:
                        applicationSupportDirectoryURL,
                    loadSettings: {
                        try await settingsStateOwner
                            .confirmedValueForProviderAction()
                    },
                    loadLibrary: {
                        try await libraryStateOwner
                            .confirmedValueForProviderAction()
                    },
                    credentialCoordinator: credentialCoordinator
                )
            },
            makeProviderConsentCoordinator: {
                applicationSupportDirectoryURL in
                IOSProviderConsentCoordinator(
                    applicationSupportDirectoryURL:
                        applicationSupportDirectoryURL
                )
            },
            makeForegroundVoicePersistenceOwner: {
                applicationSupportDirectoryURL in
                IOSForegroundVoicePersistenceOwner(
                    applicationSupportDirectoryURL:
                        applicationSupportDirectoryURL
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
                usageRepository,
                credentialCoordinator in
                IOSForegroundVoiceProcessor(
                    persistenceOwner: persistenceOwner,
                    consentCoordinator: consentCoordinator,
                    usageRepository: usageRepository,
                    credentialCoordinator: credentialCoordinator
                )
            }
        )
    }

    let applicationSupportDirectoryURL: URL?
    let historyCoordinator: IOSAcceptedHistoryCoordinator?
    let settingsStateOwner: IOSAppSettingsStateOwner?
    let libraryStateOwner: IOSLibraryStateOwner?
    let credentialCoordinator: IOSOpenAICredentialCoordinator?
    let openAISettingsStateOwner: IOSOpenAICredentialSettingsStateOwner?
    let failedHistoryService: IOSFailedHistoryService?
    let providerConsentCoordinator: IOSProviderConsentCoordinator?
    let foregroundVoicePersistenceOwner:
        IOSForegroundVoicePersistenceOwner?
    let transcriptionUsageRepository: IOSTranscriptionUsageRepository?
    let foregroundVoiceProcessor: IOSForegroundVoiceProcessor?
    let foregroundVoiceRuntime: IOSForegroundVoiceRuntime?
    let lifecycleScheduler: IOSContainingAppLifecycleScheduler
    let voiceSceneLifecycleBinding: IOSVoiceSceneLifecycleBinding?
    let availability: IOSContainingAppCompositionAvailability

    init(
        factories: Factories? = nil,
        scheduleProviderStartupMaintenance: @MainActor () -> Void = {
            OpenAIProviderStartupMaintenance.schedule()
        },
        scheduleRetryScratchStartupMaintenance: @MainActor () -> Void = {
            IOSFailedHistoryRetryScratchStartupMaintenance.schedule()
        }
    ) {
        let factories = factories ?? .production
        let applicationSupportDirectoryURL: URL
        do {
            applicationSupportDirectoryURL = try factories
                .resolveApplicationSupportDirectoryURL()
        } catch {
            self.applicationSupportDirectoryURL = nil
            historyCoordinator = nil
            settingsStateOwner = nil
            libraryStateOwner = nil
            credentialCoordinator = nil
            openAISettingsStateOwner = nil
            failedHistoryService = nil
            providerConsentCoordinator = nil
            foregroundVoicePersistenceOwner = nil
            transcriptionUsageRepository = nil
            foregroundVoiceProcessor = nil
            foregroundVoiceRuntime = nil
            availability = .storageUnavailable
            lifecycleScheduler = IOSContainingAppLifecycleScheduler { _ in
                .pendingLocalRecovery
            }
            voiceSceneLifecycleBinding = nil
            scheduleStartup(
                scheduleProviderStartupMaintenance:
                    scheduleProviderStartupMaintenance,
                scheduleRetryScratchStartupMaintenance:
                    scheduleRetryScratchStartupMaintenance
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
        let historyCoordinator = factories.makeHistoryCoordinator(
            applicationSupportDirectoryURL
        )
        self.historyCoordinator = historyCoordinator
        let providerConsentCoordinator = factories
            .makeProviderConsentCoordinator(
                applicationSupportDirectoryURL
            )
        self.providerConsentCoordinator = providerConsentCoordinator
        let foregroundVoicePersistenceOwner = factories
            .makeForegroundVoicePersistenceOwner(
                applicationSupportDirectoryURL
            )
        self.foregroundVoicePersistenceOwner =
            foregroundVoicePersistenceOwner
        let transcriptionUsageRepository = factories
            .makeTranscriptionUsageRepository(
                applicationSupportDirectoryURL
            )
        self.transcriptionUsageRepository = transcriptionUsageRepository

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
        failedHistoryService = factories.makeFailedHistoryService(
            applicationSupportDirectoryURL,
            settingsStateOwner,
            libraryStateOwner,
            credentialCoordinator
        )
        let foregroundVoiceProcessor = credentialCoordinator.map {
            factories.makeForegroundVoiceProcessor(
                foregroundVoicePersistenceOwner,
                providerConsentCoordinator,
                transcriptionUsageRepository,
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
            historyCoordinator: historyCoordinator,
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
                scheduleProviderStartupMaintenance,
            scheduleRetryScratchStartupMaintenance:
                scheduleRetryScratchStartupMaintenance
        )
    }

    /// Retains the existing app test seam without constructing production
    /// storage, Keychain, or provider dependencies.
    init(
        scheduleProviderStartupMaintenance: @MainActor () -> Void,
        scheduleRetryScratchStartupMaintenance: @MainActor () -> Void,
        recoverContainingAppLifecycle:
            @escaping IOSContainingAppLifecycleScheduler.Recovery
    ) {
        applicationSupportDirectoryURL = nil
        historyCoordinator = nil
        settingsStateOwner = nil
        libraryStateOwner = nil
        credentialCoordinator = nil
        openAISettingsStateOwner = nil
        failedHistoryService = nil
        providerConsentCoordinator = nil
        foregroundVoicePersistenceOwner = nil
        transcriptionUsageRepository = nil
        foregroundVoiceProcessor = nil
        foregroundVoiceRuntime = nil
        availability = .injected
        lifecycleScheduler = IOSContainingAppLifecycleScheduler(
            recover: recoverContainingAppLifecycle
        )
        voiceSceneLifecycleBinding = nil
        scheduleStartup(
            scheduleProviderStartupMaintenance:
                scheduleProviderStartupMaintenance,
            scheduleRetryScratchStartupMaintenance:
                scheduleRetryScratchStartupMaintenance
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
        scheduleProviderStartupMaintenance: @MainActor () -> Void,
        scheduleRetryScratchStartupMaintenance: @MainActor () -> Void
    ) {
        _ = IOSContainingAppStartup(
            scheduleProviderStartupMaintenance:
                scheduleProviderStartupMaintenance,
            scheduleRetryScratchStartupMaintenance:
                scheduleRetryScratchStartupMaintenance,
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
