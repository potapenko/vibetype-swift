import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
@_spi(HoldTypeIOSCore) import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSContainingAppCompositionTests {
    @Test func processCompositionBuildsDependenciesOnceAndSharesThemAcrossScenes()
        async throws {
        let root = try compositionTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let expectedAccessGroup = "TESTTEAMID.app.holdtype.HoldType.ios"
        var events: [String] = []
        var providerScheduleCount = 0
        var providerConsentFactoryCount = 0
        var foregroundPersistenceFactoryCount = 0
        var usageRepositoryFactoryCount = 0
        var foregroundProcessorFactoryCount = 0
        var capturedCredentialCoordinator:
            IOSOpenAICredentialCoordinator?
        var capturedSettingsStateOwner: IOSAppSettingsStateOwner?
        var capturedLibraryStateOwner: IOSLibraryStateOwner?
        var capturedProviderConsentCoordinator:
            IOSV1ProviderConsentCoordinator?
        var capturedAcceptedTextHistoryRepository:
            IOSAcceptedTextHistoryRepository?
        var capturedUsageRepository: IOSTranscriptionUsageRepository?
        var capturedForegroundUsageClient:
            IOSTranscriptionUsageRecordingClient?
        var capturedForegroundProcessor: IOSForegroundVoiceProcessor?

        let composition = IOSContainingAppComposition(
            factories: IOSContainingAppComposition.Factories(
                resolveApplicationSupportDirectoryURL: {
                    events.append("root")
                    return root
                },
                resolveApplicationIdentifierAccessGroup: {
                    events.append("access-group")
                    return expectedAccessGroup
                },
                makeSettingsStateOwner: { resolvedRoot in
                    events.append("settings")
                    let owner = IOSAppSettingsStateOwner(
                        applicationSupportDirectoryURL: resolvedRoot
                    )
                    capturedSettingsStateOwner = owner
                    return owner
                },
                makeLibraryStateOwner: { resolvedRoot in
                    events.append("library")
                    let owner = IOSLibraryStateOwner(
                        applicationSupportDirectoryURL: resolvedRoot
                    )
                    capturedLibraryStateOwner = owner
                    return owner
                },
                makeCredentialCoordinator: {
                    resolvedRoot,
                    accessGroup in
                    events.append("credential")
                    #expect(resolvedRoot == root)
                    #expect(accessGroup == expectedAccessGroup)
                    let coordinator = try IOSOpenAICredentialCoordinator(
                        applicationSupportDirectoryURL: resolvedRoot,
                        applicationIdentifierAccessGroup: accessGroup
                    )
                    capturedCredentialCoordinator = coordinator
                    return coordinator
                },
                makeProviderConsentCoordinator: { resolvedRoot in
                    events.append("provider-consent")
                    providerConsentFactoryCount += 1
                    let coordinator = IOSV1ProviderConsentCoordinator(
                        applicationSupportDirectoryURL: resolvedRoot
                    )
                    capturedProviderConsentCoordinator = coordinator
                    return coordinator
                },
                makeForegroundVoicePersistenceOwner: {
                    resolvedRoot,
                    acceptedTextHistoryRepository in
                    events.append("foreground-persistence")
                    foregroundPersistenceFactoryCount += 1
                    capturedAcceptedTextHistoryRepository =
                        acceptedTextHistoryRepository
                    return IOSV1ForegroundVoicePersistenceOwner(
                        applicationSupportDirectoryURL: resolvedRoot,
                        acceptedTextHistoryRepository:
                            acceptedTextHistoryRepository
                    )
                },
                makeTranscriptionUsageRepository: { resolvedRoot in
                    events.append("usage")
                    usageRepositoryFactoryCount += 1
                    let repository = IOSTranscriptionUsageRepository(
                        applicationSupportDirectoryURL: resolvedRoot
                    )
                    capturedUsageRepository = repository
                    return repository
                },
                makeForegroundVoiceProcessor: {
                    persistenceOwner,
                    consentCoordinator,
                    usageRecordingClient,
                    credentialCoordinator in
                    events.append("foreground-processor")
                    foregroundProcessorFactoryCount += 1
                    #expect(
                        consentCoordinator
                            === capturedProviderConsentCoordinator
                    )
                    #expect(
                        credentialCoordinator
                            === capturedCredentialCoordinator
                    )
                    capturedForegroundUsageClient = usageRecordingClient
                    let processor = IOSForegroundVoiceProcessor(
                        persistenceOwner: persistenceOwner,
                        consentCoordinator: consentCoordinator,
                        usageRecordingClient: usageRecordingClient,
                        credentialCoordinator: credentialCoordinator
                    )
                    capturedForegroundProcessor = processor
                    return processor
                }
            ),
            scheduleProviderStartupMaintenance: {
                providerScheduleCount += 1
            }
        )

        let app = HoldTypeIOSApp(composition: composition)
        let firstScene = rootView(for: app.composition)
        let secondScene = rootView(for: app.composition)

        #expect(
            events == [
                "root",
                "settings",
                "library",
                "provider-consent",
                "foreground-persistence",
                "usage",
                "access-group",
                "credential",
                "foreground-processor",
            ]
        )
        #expect(providerScheduleCount == 1)
        #expect(composition.availability == .ready)
        #expect(
            composition.settingsStateOwner
                === capturedSettingsStateOwner
        )
        #expect(
            composition.libraryStateOwner
                === capturedLibraryStateOwner
        )
        #expect(composition.settingsStateOwner?.state == .notLoaded)
        #expect(composition.libraryStateOwner?.state == .notLoaded)
        #expect(
            composition.credentialCoordinator
                === capturedCredentialCoordinator
        )
        #expect(composition.openAISettingsStateOwner != nil)
        #expect(
            composition.openAISettingsStateOwner?.state == .notLoaded
        )
        #expect(providerConsentFactoryCount == 1)
        #expect(foregroundPersistenceFactoryCount == 1)
        #expect(usageRepositoryFactoryCount == 1)
        #expect(foregroundProcessorFactoryCount == 1)
        #expect(
            composition.providerConsentCoordinator
                === capturedProviderConsentCoordinator
        )
        #expect(composition.foregroundVoicePersistenceOwner != nil)
        #expect(
            composition.acceptedTextHistoryRepository ===
                capturedAcceptedTextHistoryRepository
        )
        #expect(composition.acceptedTextHistoryStateOwner != nil)
        #expect(
            composition.acceptedTextHistoryStateOwner?.state == .notLoaded
        )
        #expect(
            composition.transcriptionUsageRepository
                === capturedUsageRepository
        )
        #expect(composition.usageEstimateStateOwner != nil)
        let usageRepository = try #require(capturedUsageRepository)
        let foregroundUsageClient = try #require(
            capturedForegroundUsageClient
        )
        #expect(foregroundUsageClient.isBacked(by: usageRepository))
        #expect(
            composition.foregroundVoiceProcessor
                === capturedForegroundProcessor
        )
        let voiceRuntime = try #require(
            composition.foregroundVoiceRuntime
        )
        #expect(composition.voiceSceneLifecycleBinding != nil)
        #expect(voiceRuntime.sceneRegistry.activeEventSubscriptionCount == 1)
        #expect(voiceRuntime.sceneRegistry.snapshot.registeredSceneCount == 0)
        #expect(
            voiceRuntime.controller.sceneRegistry
                === voiceRuntime.sceneRegistry
        )
        let firstVoiceController = voiceRuntime.controller
        let secondVoiceController = composition.foregroundVoiceRuntime?
            .controller
        #expect(firstVoiceController === secondVoiceController)
        _ = voiceRuntime.sceneRegistry.registerScene(
            initialActivity: .active
        )
        _ = voiceRuntime.sceneRegistry.registerScene(
            initialActivity: .background
        )
        #expect(voiceRuntime.sceneRegistry.snapshot.registeredSceneCount == 2)
        #expect(firstScene.presentation == .shell)
        #expect(secondScene.presentation == .shell)
        #expect(
            firstScene.settingsStateOwner
                === secondScene.settingsStateOwner
        )
        #expect(
            firstScene.libraryStateOwner
                === secondScene.libraryStateOwner
        )
        #expect(
            firstScene.openAISettingsStateOwner
                === secondScene.openAISettingsStateOwner
        )
        #expect(
            firstScene.usageEstimateStateOwner
                === secondScene.usageEstimateStateOwner
        )
        #expect(firstScene.settingsStateOwner === capturedSettingsStateOwner)
        #expect(firstScene.libraryStateOwner === capturedLibraryStateOwner)
        #expect(
            firstScene.openAISettingsStateOwner
                === composition.openAISettingsStateOwner
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: IOSAppSettingsStorageLocation.fileURL(in: root).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: IOSLibraryStorageLocation.fileURL(in: root).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("HoldType", isDirectory: true)
                    .appendingPathComponent(
                        "ios-v1-provider-consent.json",
                        isDirectory: false
                    ).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: IOSTranscriptionUsageStorageLocation
                    .fileURL(in: root).path
            )
        )

        let usageOwner = try #require(composition.usageEstimateStateOwner)
        let usageFileURL = IOSTranscriptionUsageStorageLocation.fileURL(
            in: root
        )
        try FileManager.default.createDirectory(
            at: usageFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: usageFileURL)
        await foregroundUsageClient.record(
            try SuccessfulTranscriptionUsage(
                transcriptionID: UUID(),
                model: "gpt-4o-transcribe",
                audioDuration: 60
            )
        )
        #expect(usageOwner.notice == .writeFailed)
        #expect(!(await usageOwner.refresh()))
        #expect(await usageOwner.reset())
        #expect(usageOwner.notice == nil)

        try Data("still-not-json".utf8).write(to: usageFileURL)
        await foregroundUsageClient.record(
            try SuccessfulTranscriptionUsage(
                transcriptionID: UUID(),
                model: "gpt-4o-transcribe",
                audioDuration: 90
            )
        )
        #expect(usageOwner.notice == .writeFailed)

        await composition.lifecycleScheduler.waitUntilIdle()
        let markerURL = IOSCredentialPresenceMarkerStorageLocation.fileURL(
            in: root
        )
        #expect(!FileManager.default.fileExists(atPath: markerURL.path))
    }

    @Test func missingAccessGroupKeepsAppAvailableWithoutCredential()
        async throws {
        let root = try compositionTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var credentialFactoryCalls = 0
        var providerConsentFactoryCalls = 0
        var foregroundPersistenceFactoryCalls = 0
        var usageRepositoryFactoryCalls = 0
        var foregroundProcessorFactoryCalls = 0

        let composition = IOSContainingAppComposition(
            factories: IOSContainingAppComposition.Factories(
                resolveApplicationSupportDirectoryURL: { root },
                resolveApplicationIdentifierAccessGroup: { nil },
                makeSettingsStateOwner: {
                    IOSAppSettingsStateOwner(
                        applicationSupportDirectoryURL: $0
                    )
                },
                makeLibraryStateOwner: {
                    IOSLibraryStateOwner(
                        applicationSupportDirectoryURL: $0
                    )
                },
                makeCredentialCoordinator: { _, _ in
                    credentialFactoryCalls += 1
                    throw CompositionFixtureError.unexpectedFactoryCall
                },
                makeProviderConsentCoordinator: { resolvedRoot in
                    providerConsentFactoryCalls += 1
                    return IOSV1ProviderConsentCoordinator(
                        applicationSupportDirectoryURL: resolvedRoot
                    )
                },
                makeForegroundVoicePersistenceOwner: {
                    resolvedRoot,
                    acceptedTextHistoryRepository in
                    foregroundPersistenceFactoryCalls += 1
                    return IOSV1ForegroundVoicePersistenceOwner(
                        applicationSupportDirectoryURL: resolvedRoot,
                        acceptedTextHistoryRepository:
                            acceptedTextHistoryRepository
                    )
                },
                makeTranscriptionUsageRepository: { resolvedRoot in
                    usageRepositoryFactoryCalls += 1
                    return IOSTranscriptionUsageRepository(
                        applicationSupportDirectoryURL: resolvedRoot
                    )
                },
                makeForegroundVoiceProcessor: { _, _, _, _ in
                    foregroundProcessorFactoryCalls += 1
                    preconditionFailure(
                        "Processor must not be constructed without credentials."
                    )
                }
            ),
            scheduleProviderStartupMaintenance: {}
        )
        let rootPresentation = rootView(for: composition)

        await composition.lifecycleScheduler.waitUntilIdle()
        #expect(composition.availability == .credentialUnavailable)
        #expect(rootPresentation.presentation == .shell)
        #expect(composition.settingsStateOwner != nil)
        #expect(composition.libraryStateOwner != nil)
        #expect(composition.settingsStateOwner?.state == .ready(.defaults))
        #expect(composition.libraryStateOwner?.state == .ready(.defaults))
        #expect(composition.credentialCoordinator == nil)
        #expect(
            composition.openAISettingsStateOwner?.state == .unavailable
        )
        #expect(composition.providerConsentCoordinator != nil)
        #expect(composition.foregroundVoicePersistenceOwner != nil)
        #expect(composition.transcriptionUsageRepository != nil)
        #expect(composition.usageEstimateStateOwner != nil)
        #expect(composition.foregroundVoiceProcessor == nil)
        let voiceRuntime = try #require(
            composition.foregroundVoiceRuntime
        )
        #expect(composition.voiceSceneLifecycleBinding != nil)
        #expect(voiceRuntime.sceneRegistry.activeEventSubscriptionCount == 1)
        guard case .unavailable = await voiceRuntime.providerBridge
                .resolveCredential() else {
            Issue.record("Expected unavailable Voice credential owner.")
            return
        }
        #expect(
            voiceRuntime.controller.sceneRegistry
                === voiceRuntime.sceneRegistry
        )
        #expect(credentialFactoryCalls == 0)
        #expect(providerConsentFactoryCalls == 1)
        #expect(foregroundPersistenceFactoryCalls == 1)
        #expect(usageRepositoryFactoryCalls == 1)
        #expect(foregroundProcessorFactoryCalls == 0)

        #expect(
            !FileManager.default.fileExists(
                atPath: IOSCredentialPresenceMarkerStorageLocation
                    .fileURL(in: root).path
            )
        )
    }

    @Test func invalidAccessGroupKeepsAppAvailableWithoutCredential()
        async throws {
        let root = try compositionTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var credentialFactoryCalls = 0
        var providerConsentFactoryCalls = 0
        var foregroundPersistenceFactoryCalls = 0
        var usageRepositoryFactoryCalls = 0
        var foregroundProcessorFactoryCalls = 0

        let composition = IOSContainingAppComposition(
            factories: IOSContainingAppComposition.Factories(
                resolveApplicationSupportDirectoryURL: { root },
                resolveApplicationIdentifierAccessGroup: {
                    "group.app.holdtype.HoldType.shared"
                },
                makeSettingsStateOwner: {
                    IOSAppSettingsStateOwner(
                        applicationSupportDirectoryURL: $0
                    )
                },
                makeLibraryStateOwner: {
                    IOSLibraryStateOwner(
                        applicationSupportDirectoryURL: $0
                    )
                },
                makeCredentialCoordinator: { resolvedRoot, accessGroup in
                    credentialFactoryCalls += 1
                    return try IOSOpenAICredentialCoordinator(
                        applicationSupportDirectoryURL: resolvedRoot,
                        applicationIdentifierAccessGroup: accessGroup
                    )
                },
                makeProviderConsentCoordinator: { resolvedRoot in
                    providerConsentFactoryCalls += 1
                    return IOSV1ProviderConsentCoordinator(
                        applicationSupportDirectoryURL: resolvedRoot
                    )
                },
                makeForegroundVoicePersistenceOwner: {
                    resolvedRoot,
                    acceptedTextHistoryRepository in
                    foregroundPersistenceFactoryCalls += 1
                    return IOSV1ForegroundVoicePersistenceOwner(
                        applicationSupportDirectoryURL: resolvedRoot,
                        acceptedTextHistoryRepository:
                            acceptedTextHistoryRepository
                    )
                },
                makeTranscriptionUsageRepository: { resolvedRoot in
                    usageRepositoryFactoryCalls += 1
                    return IOSTranscriptionUsageRepository(
                        applicationSupportDirectoryURL: resolvedRoot
                    )
                },
                makeForegroundVoiceProcessor: { _, _, _, _ in
                    foregroundProcessorFactoryCalls += 1
                    preconditionFailure(
                        "Processor must not be constructed without credentials."
                    )
                }
            ),
            scheduleProviderStartupMaintenance: {}
        )

        await composition.lifecycleScheduler.waitUntilIdle()
        #expect(credentialFactoryCalls == 1)
        #expect(composition.availability == .credentialUnavailable)
        #expect(composition.settingsStateOwner != nil)
        #expect(composition.libraryStateOwner != nil)
        #expect(composition.settingsStateOwner?.state == .ready(.defaults))
        #expect(composition.libraryStateOwner?.state == .ready(.defaults))
        #expect(composition.credentialCoordinator == nil)
        #expect(
            composition.openAISettingsStateOwner?.state == .unavailable
        )
        #expect(composition.providerConsentCoordinator != nil)
        #expect(composition.foregroundVoicePersistenceOwner != nil)
        #expect(composition.transcriptionUsageRepository != nil)
        #expect(composition.usageEstimateStateOwner != nil)
        #expect(composition.foregroundVoiceProcessor == nil)
        #expect(composition.foregroundVoiceRuntime != nil)
        #expect(composition.voiceSceneLifecycleBinding != nil)
        #expect(providerConsentFactoryCalls == 1)
        #expect(foregroundPersistenceFactoryCalls == 1)
        #expect(usageRepositoryFactoryCalls == 1)
        #expect(foregroundProcessorFactoryCalls == 0)
        #expect(
            !FileManager.default.fileExists(
                atPath: IOSCredentialPresenceMarkerStorageLocation
                    .fileURL(in: root).path
            )
        )
    }

    @Test func storageRootFailureKeepsAppLaunchableAndRecoveryPending()
        async {
        var settingsFactoryCalls = 0
        var libraryFactoryCalls = 0
        var credentialFactoryCalls = 0
        var providerConsentFactoryCalls = 0
        var foregroundPersistenceFactoryCalls = 0
        var usageRepositoryFactoryCalls = 0
        var foregroundProcessorFactoryCalls = 0
        var providerScheduleCount = 0

        let composition = IOSContainingAppComposition(
            factories: IOSContainingAppComposition.Factories(
                resolveApplicationSupportDirectoryURL: {
                    throw CompositionFixtureError.storageUnavailable
                },
                resolveApplicationIdentifierAccessGroup: {
                    Issue.record("Access group must not be read without storage.")
                    return nil
                },
                makeSettingsStateOwner: { _ in
                    settingsFactoryCalls += 1
                    preconditionFailure("Settings must not be constructed.")
                },
                makeLibraryStateOwner: { _ in
                    libraryFactoryCalls += 1
                    preconditionFailure("Library must not be constructed.")
                },
                makeCredentialCoordinator: { _, _ in
                    credentialFactoryCalls += 1
                    throw CompositionFixtureError.unexpectedFactoryCall
                },
                makeProviderConsentCoordinator: { _ in
                    providerConsentFactoryCalls += 1
                    preconditionFailure(
                        "Consent must not be constructed."
                    )
                },
                makeForegroundVoicePersistenceOwner: { _, _ in
                    foregroundPersistenceFactoryCalls += 1
                    preconditionFailure(
                        "Foreground persistence must not be constructed."
                    )
                },
                makeTranscriptionUsageRepository: { _ in
                    usageRepositoryFactoryCalls += 1
                    preconditionFailure(
                        "Usage repository must not be constructed."
                    )
                },
                makeForegroundVoiceProcessor: { _, _, _, _ in
                    foregroundProcessorFactoryCalls += 1
                    preconditionFailure(
                        "Foreground processor must not be constructed."
                    )
                }
            ),
            scheduleProviderStartupMaintenance: {
                providerScheduleCount += 1
            }
        )
        let app = HoldTypeIOSApp(composition: composition)
        let root = rootView(for: app.composition)

        await composition.lifecycleScheduler.waitUntilIdle()
        #expect(root.presentation == .storageUnavailable)
        #expect(root.settingsStateOwner == nil)
        #expect(root.libraryStateOwner == nil)
        #expect(root.openAISettingsStateOwner == nil)
        #expect(root.usageEstimateStateOwner == nil)
        #expect(composition.availability == .storageUnavailable)
        #expect(composition.applicationSupportDirectoryURL == nil)
        #expect(composition.settingsStateOwner == nil)
        #expect(composition.libraryStateOwner == nil)
        #expect(composition.credentialCoordinator == nil)
        #expect(composition.openAISettingsStateOwner == nil)
        #expect(composition.providerConsentCoordinator == nil)
        #expect(composition.acceptedTextHistoryRepository == nil)
        #expect(composition.acceptedTextHistoryStateOwner == nil)
        #expect(composition.foregroundVoicePersistenceOwner == nil)
        #expect(composition.transcriptionUsageRepository == nil)
        #expect(composition.usageEstimateStateOwner == nil)
        #expect(composition.foregroundVoiceProcessor == nil)
        #expect(composition.foregroundVoiceRuntime == nil)
        #expect(composition.voiceSceneLifecycleBinding == nil)
        #expect(
            composition.lifecycleScheduler.latestDisposition
                == .pendingLocalRecovery
        )
        #expect(settingsFactoryCalls == 0)
        #expect(libraryFactoryCalls == 0)
        #expect(credentialFactoryCalls == 0)
        #expect(providerConsentFactoryCalls == 0)
        #expect(foregroundPersistenceFactoryCalls == 0)
        #expect(usageRepositoryFactoryCalls == 0)
        #expect(foregroundProcessorFactoryCalls == 0)
        #expect(providerScheduleCount == 1)
    }

    @Test func providerOnlyTestInjectionStaysPassive() async {
        var providerScheduleCount = 0

        let app = HoldTypeIOSApp(scheduleProviderStartupMaintenance: {
            providerScheduleCount += 1
        })

        await app.composition.lifecycleScheduler.waitUntilIdle()
        #expect(providerScheduleCount == 1)
        #expect(app.composition.availability == .injected)
        #expect(app.composition.applicationSupportDirectoryURL == nil)
        #expect(app.composition.settingsStateOwner == nil)
        #expect(app.composition.libraryStateOwner == nil)
        #expect(app.composition.credentialCoordinator == nil)
        #expect(app.composition.openAISettingsStateOwner == nil)
        #expect(app.composition.providerConsentCoordinator == nil)
        #expect(app.composition.acceptedTextHistoryRepository == nil)
        #expect(app.composition.acceptedTextHistoryStateOwner == nil)
        #expect(app.composition.foregroundVoicePersistenceOwner == nil)
        #expect(app.composition.transcriptionUsageRepository == nil)
        #expect(app.composition.usageEstimateStateOwner == nil)
        #expect(app.composition.foregroundVoiceProcessor == nil)
        #expect(app.composition.foregroundVoiceRuntime == nil)
        #expect(app.composition.voiceSceneLifecycleBinding == nil)
        #expect(app.composition.lifecycleScheduler.latestDisposition == .complete)
    }

    @Test func hostedAppInfoPlistContainsResolvedContainingAppAccessGroup() {
        let key = OpenAIAPIKeyKeychainStorage
            .applicationIdentifierAccessGroupInfoKey
        let value = IOSContainingAppComposition
            .applicationIdentifierAccessGroup(in: .main)

        #expect(key == "HoldTypeApplicationIdentifierAccessGroup")
        #expect(value != nil)
        #expect(value?.contains("$(") == false)
        #expect(
            value == "app.holdtype.HoldType.ios"
                || value?.hasSuffix(".app.holdtype.HoldType.ios") == true
        )
        #expect(value != "group.app.holdtype.HoldType.shared")
    }
}

private enum CompositionFixtureError: Error {
    case storageUnavailable
    case unexpectedFactoryCall
}

private func compositionTemporaryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ios-containing-app-composition-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    return root
}

@MainActor
private func rootView(
    for composition: IOSContainingAppComposition
) -> HoldTypeIOSRootView {
    HoldTypeIOSRootView(
        settingsStateOwner: composition.settingsStateOwner,
        libraryStateOwner: composition.libraryStateOwner,
        openAISettingsStateOwner:
            composition.openAISettingsStateOwner,
        usageEstimateStateOwner:
            composition.usageEstimateStateOwner,
        acceptedTextHistoryStateOwner:
            composition.acceptedTextHistoryStateOwner,
        secureProviderAvailability: .resolve(
            compositionAvailability: composition.availability
        )
    )
}
