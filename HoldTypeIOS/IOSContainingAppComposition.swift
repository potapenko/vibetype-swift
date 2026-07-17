import Foundation
import HoldTypeDomain
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
            IOSAcceptedTextHistoryRepository,
            IOSAcceptedAudioCache,
            @escaping @Sendable () async -> RecordingCachePolicy
        ) -> IOSV1ForegroundVoicePersistenceOwner
        let makeTranscriptionUsageRepository: @MainActor (
            URL
        ) -> IOSTranscriptionUsageRepository
        var makeVoiceDraftRepository: @MainActor (
            URL
        ) -> IOSVoiceDraftRepository = {
            IOSVoiceDraftRepository(applicationSupportDirectoryURL: $0)
        }
        let makeForegroundVoiceProcessor: @MainActor (
            IOSV1ForegroundVoicePersistenceOwner,
            IOSV1ProviderConsentCoordinator,
            IOSTranscriptionUsageRecordingClient,
            IOSOpenAICredentialCoordinator
        ) -> IOSForegroundVoiceProcessor
        var voiceFactories: IOSForegroundVoiceRuntime.Factories = .production
        var makeKeyboardSnapshotPublisher: @MainActor (
            IOSAcceptedTextHistoryRepository
        ) -> IOSKeyboardSnapshotPublisher? = { _ in nil }

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
                acceptedTextHistoryRepository,
                acceptedAudioCache,
                recordingCachePolicy in
                IOSV1ForegroundVoicePersistenceOwner(
                    applicationSupportDirectoryURL:
                        applicationSupportDirectoryURL,
                    acceptedTextHistoryRepository:
                        acceptedTextHistoryRepository,
                    acceptedAudioCache: acceptedAudioCache,
                    recordingCachePolicy: recordingCachePolicy
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
            },
            makeKeyboardSnapshotPublisher: {
                historyRepository in
                let store = try? KeyboardBridgeStore.appGroup()
                _ = try? store?.replaceLegacySnapshotIfNeeded()
                return IOSKeyboardSnapshotPublisher(
                    store: store,
                    loadHistory: {
                        try await historyRepository.load()
                    }
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
    let acceptedAudioCache: IOSAcceptedAudioCache?
    let acceptedTextHistoryStateOwner:
        IOSAcceptedTextHistoryStateOwner?
    let voiceDraftRepository: IOSVoiceDraftRepository?
    let voiceDraftOwner: IOSVoiceDraftOwner?
    let foregroundVoicePersistenceOwner:
        IOSV1ForegroundVoicePersistenceOwner?
    let keyboardSnapshotPublisher: IOSKeyboardSnapshotPublisher?
    let transcriptionUsageRepository: IOSTranscriptionUsageRepository?
    let usageEstimateStateOwner: IOSUsageEstimateStateOwner?
    let foregroundVoiceProcessor: IOSForegroundVoiceProcessor?
    let foregroundVoiceRuntime: IOSForegroundVoiceRuntime?
    let historyPlaybackActions: IOSHistoryPlaybackActions?
    let pendingRecordingHistoryStateOwner:
        IOSPendingRecordingHistoryStateOwner?
    let recordingCacheLifecycleActions:
        IOSRecordingCacheLifecycleActions?
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
            acceptedAudioCache = nil
            acceptedTextHistoryStateOwner = nil
            voiceDraftRepository = nil
            voiceDraftOwner = nil
            foregroundVoicePersistenceOwner = nil
            keyboardSnapshotPublisher = nil
            transcriptionUsageRepository = nil
            usageEstimateStateOwner = nil
            foregroundVoiceProcessor = nil
            foregroundVoiceRuntime = nil
            historyPlaybackActions = nil
            pendingRecordingHistoryStateOwner = nil
            recordingCacheLifecycleActions = nil
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
        let acceptedAudioCache = IOSAcceptedAudioCache(
            applicationSupportDirectoryURL:
                applicationSupportDirectoryURL
        )
        self.acceptedAudioCache = acceptedAudioCache
        let loadRecordingCachePolicy: @Sendable () async
            -> RecordingCachePolicy = {
            do {
                return try await settingsStateOwner
                    .confirmedValueForProviderAction()
                    .recordingCachePolicy
                    .normalized
            } catch {
                return .deleteImmediately
            }
        }
        let foregroundVoicePersistenceOwner = factories
            .makeForegroundVoicePersistenceOwner(
                applicationSupportDirectoryURL,
                acceptedTextHistoryRepository,
                acceptedAudioCache,
                loadRecordingCachePolicy
            )
        self.foregroundVoicePersistenceOwner =
            foregroundVoicePersistenceOwner
        let keyboardSnapshotPublisher = factories
            .makeKeyboardSnapshotPublisher(
                acceptedTextHistoryRepository
            )
        self.keyboardSnapshotPublisher = keyboardSnapshotPublisher
        let publishKeyboardSnapshot: @Sendable () async -> Bool = {
            guard let keyboardSnapshotPublisher else { return true }
            return await keyboardSnapshotPublisher.publishCurrent()
        }
        let acceptedTextHistoryStateOwner =
            IOSAcceptedTextHistoryStateOwner(
                repository: acceptedTextHistoryRepository,
                publishKeyboardSnapshot: publishKeyboardSnapshot
            )
        self.acceptedTextHistoryStateOwner =
            acceptedTextHistoryStateOwner
        let voiceDraftRepository = factories.makeVoiceDraftRepository(
            applicationSupportDirectoryURL
        )
        self.voiceDraftRepository = voiceDraftRepository
        let voiceDraftOwner = IOSVoiceDraftOwner(
            repository: voiceDraftRepository
        )
        self.voiceDraftOwner = voiceDraftOwner
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
            voiceDraftOwner: voiceDraftOwner,
            credentialCoordinator: credentialCoordinator,
            processor: foregroundVoiceProcessor,
            publishKeyboardSnapshot: publishKeyboardSnapshot,
            refreshAcceptedHistory: {
                await acceptedTextHistoryStateOwner
                    .refreshPresentationAfterAcceptedResult()
            },
            factories: factories.voiceFactories
        )
        self.foregroundVoiceRuntime = foregroundVoiceRuntime
        let historyAudioPlaybackOwner = foregroundVoiceRuntime
            .historyAudioPlaybackOwner
        historyPlaybackActions = historyAudioPlaybackOwner
            .map {
                IOSHistoryPlaybackActions(
                    cache: acceptedAudioCache,
                    loadPolicy: loadRecordingCachePolicy,
                    player: $0
                )
            }
        pendingRecordingHistoryStateOwner =
            IOSPendingRecordingHistoryStateOwner(
                actions: IOSPendingRecordingHistoryActions(
                    persistenceOwner: foregroundVoicePersistenceOwner,
                    savedRecordingClient:
                        foregroundVoiceRuntime.workflow.savedRecordingClient,
                    player: historyAudioPlaybackOwner
                )
            )
        let recordingCacheLifecycleActions =
            IOSRecordingCacheLifecycleActions(
                cache: acceptedAudioCache,
                player: historyAudioPlaybackOwner
            )
        self.recordingCacheLifecycleActions =
            recordingCacheLifecycleActions
        let lifecycleScheduler = IOSContainingAppLifecycleScheduler {
            opportunity in
            let disposition = await foregroundVoiceRuntime
                .lifecycleCoordinator
                .recover(opportunity)
            if let policy = try? await settingsStateOwner
                .confirmedValueForProviderAction()
                .recordingCachePolicy
                .normalized {
                _ = await recordingCacheLifecycleActions.reconcile(
                    policy: policy
                )
            }
            await foregroundVoiceRuntime.latestResultOwner
                .refreshKeyboardProjection()
            return disposition
        }
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
        acceptedAudioCache = nil
        acceptedTextHistoryStateOwner = nil
        voiceDraftRepository = nil
        voiceDraftOwner = nil
        foregroundVoicePersistenceOwner = nil
        keyboardSnapshotPublisher = nil
        transcriptionUsageRepository = nil
        usageEstimateStateOwner = nil
        foregroundVoiceProcessor = nil
        foregroundVoiceRuntime = nil
        historyPlaybackActions = nil
        pendingRecordingHistoryStateOwner = nil
        recordingCacheLifecycleActions = nil
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
