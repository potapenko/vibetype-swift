import Foundation
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
import HoldTypePersistence
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
        var retryScratchScheduleCount = 0
        var capturedCredentialCoordinator:
            IOSOpenAICredentialCoordinator?
        var capturedSettingsStateOwner: IOSAppSettingsStateOwner?
        var capturedLibraryStateOwner: IOSLibraryStateOwner?

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
                makeHistoryCoordinator: { resolvedRoot in
                    events.append("history")
                    #expect(resolvedRoot == root)
                    #expect(
                        FileManager.default.fileExists(
                            atPath: resolvedRoot.path
                        )
                    )
                    return IOSAcceptedHistoryCoordinator(
                        applicationSupportDirectoryURL: resolvedRoot
                    )
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
                makeFailedHistoryService: {
                    resolvedRoot,
                    settingsStateOwner,
                    libraryStateOwner,
                    credentialCoordinator in
                    events.append("failed-history")
                    #expect(resolvedRoot == root)
                    #expect(
                        credentialCoordinator
                            === capturedCredentialCoordinator
                    )
                    #expect(
                        settingsStateOwner
                            === capturedSettingsStateOwner
                    )
                    #expect(
                        libraryStateOwner
                            === capturedLibraryStateOwner
                    )
                    return IOSFailedHistoryService(
                        applicationSupportDirectoryURL: resolvedRoot,
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
                }
            ),
            scheduleProviderStartupMaintenance: {
                providerScheduleCount += 1
            },
            scheduleRetryScratchStartupMaintenance: {
                retryScratchScheduleCount += 1
            }
        )

        let app = HoldTypeIOSApp(composition: composition)
        let firstScene = HoldTypeIOSRootView(
            composition: app.composition
        )
        let secondScene = HoldTypeIOSRootView(
            composition: app.composition
        )

        #expect(
            events == [
                "root",
                "settings",
                "library",
                "history",
                "access-group",
                "credential",
                "failed-history",
            ]
        )
        #expect(providerScheduleCount == 1)
        #expect(retryScratchScheduleCount == 1)
        #expect(composition.availability == .ready)
        #expect(composition.historyCoordinator != nil)
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
        #expect(composition.failedHistoryService != nil)
        #expect(firstScene.composition === composition)
        #expect(secondScene.composition === composition)
        #expect(firstScene.presentation == .shell)
        #expect(secondScene.presentation == .shell)
        #expect(
            firstScene.composition.settingsStateOwner
                === secondScene.composition.settingsStateOwner
        )
        #expect(
            firstScene.composition.libraryStateOwner
                === secondScene.composition.libraryStateOwner
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

        await composition.lifecycleScheduler.waitUntilIdle()
        let markerURL = IOSCredentialPresenceMarkerStorageLocation.fileURL(
            in: root
        )
        #expect(!FileManager.default.fileExists(atPath: markerURL.path))
    }

    @Test func missingAccessGroupKeepsProviderFreeHistoryAvailable()
        async throws {
        let root = try compositionTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var credentialFactoryCalls = 0
        var serviceCredentialWasNil = false

        let composition = IOSContainingAppComposition(
            factories: IOSContainingAppComposition.Factories(
                resolveApplicationSupportDirectoryURL: { root },
                resolveApplicationIdentifierAccessGroup: { nil },
                makeHistoryCoordinator: {
                    IOSAcceptedHistoryCoordinator(
                        applicationSupportDirectoryURL: $0
                    )
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
                makeCredentialCoordinator: { _, _ in
                    credentialFactoryCalls += 1
                    throw CompositionFixtureError.unexpectedFactoryCall
                },
                makeFailedHistoryService: {
                    resolvedRoot,
                    settingsStateOwner,
                    libraryStateOwner,
                    coordinator in
                    serviceCredentialWasNil = coordinator == nil
                    return IOSFailedHistoryService(
                        applicationSupportDirectoryURL: resolvedRoot,
                        loadSettings: {
                            try await settingsStateOwner
                                .confirmedValueForProviderAction()
                        },
                        loadLibrary: {
                            try await libraryStateOwner
                                .confirmedValueForProviderAction()
                        },
                        credentialCoordinator: coordinator
                    )
                }
            ),
            scheduleProviderStartupMaintenance: {},
            scheduleRetryScratchStartupMaintenance: {}
        )
        let rootView = HoldTypeIOSRootView(composition: composition)

        await composition.lifecycleScheduler.waitUntilIdle()
        #expect(composition.availability == .credentialUnavailable)
        #expect(rootView.presentation == .shell)
        #expect(composition.historyCoordinator != nil)
        #expect(composition.settingsStateOwner != nil)
        #expect(composition.libraryStateOwner != nil)
        #expect(composition.settingsStateOwner?.state == .notLoaded)
        #expect(composition.libraryStateOwner?.state == .notLoaded)
        #expect(composition.credentialCoordinator == nil)
        #expect(composition.failedHistoryService != nil)
        #expect(credentialFactoryCalls == 0)
        #expect(serviceCredentialWasNil)

        let service = try #require(composition.failedHistoryService)
        #expect(await service.loadFailedHistory() == .available([]))
        #expect(
            !FileManager.default.fileExists(
                atPath: IOSCredentialPresenceMarkerStorageLocation
                    .fileURL(in: root).path
            )
        )
    }

    @Test func invalidAccessGroupDegradesRetryWithoutPoisoningStorage()
        async throws {
        let root = try compositionTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var credentialFactoryCalls = 0
        var serviceCredentialWasNil = false

        let composition = IOSContainingAppComposition(
            factories: IOSContainingAppComposition.Factories(
                resolveApplicationSupportDirectoryURL: { root },
                resolveApplicationIdentifierAccessGroup: {
                    "group.app.holdtype.HoldType.shared"
                },
                makeHistoryCoordinator: {
                    IOSAcceptedHistoryCoordinator(
                        applicationSupportDirectoryURL: $0
                    )
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
                makeFailedHistoryService: {
                    resolvedRoot,
                    settingsStateOwner,
                    libraryStateOwner,
                    coordinator in
                    serviceCredentialWasNil = coordinator == nil
                    return IOSFailedHistoryService(
                        applicationSupportDirectoryURL: resolvedRoot,
                        loadSettings: {
                            try await settingsStateOwner
                                .confirmedValueForProviderAction()
                        },
                        loadLibrary: {
                            try await libraryStateOwner
                                .confirmedValueForProviderAction()
                        },
                        credentialCoordinator: coordinator
                    )
                }
            ),
            scheduleProviderStartupMaintenance: {},
            scheduleRetryScratchStartupMaintenance: {}
        )

        await composition.lifecycleScheduler.waitUntilIdle()
        #expect(credentialFactoryCalls == 1)
        #expect(serviceCredentialWasNil)
        #expect(composition.availability == .credentialUnavailable)
        #expect(composition.historyCoordinator != nil)
        #expect(composition.settingsStateOwner != nil)
        #expect(composition.libraryStateOwner != nil)
        #expect(composition.settingsStateOwner?.state == .notLoaded)
        #expect(composition.libraryStateOwner?.state == .notLoaded)
        #expect(composition.credentialCoordinator == nil)
        let service = try #require(composition.failedHistoryService)
        #expect(await service.loadFailedHistory() == .available([]))
        #expect(
            !FileManager.default.fileExists(
                atPath: IOSCredentialPresenceMarkerStorageLocation
                    .fileURL(in: root).path
            )
        )
    }

    @Test func storageRootFailureKeepsAppLaunchableAndRecoveryPending()
        async {
        var historyFactoryCalls = 0
        var settingsFactoryCalls = 0
        var libraryFactoryCalls = 0
        var credentialFactoryCalls = 0
        var serviceFactoryCalls = 0
        var providerScheduleCount = 0
        var retryScratchScheduleCount = 0

        let composition = IOSContainingAppComposition(
            factories: IOSContainingAppComposition.Factories(
                resolveApplicationSupportDirectoryURL: {
                    throw CompositionFixtureError.storageUnavailable
                },
                resolveApplicationIdentifierAccessGroup: {
                    Issue.record("Access group must not be read without storage.")
                    return nil
                },
                makeHistoryCoordinator: { _ in
                    historyFactoryCalls += 1
                    preconditionFailure("History must not be constructed.")
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
                makeFailedHistoryService: { _, _, _, _ in
                    serviceFactoryCalls += 1
                    preconditionFailure("Service must not be constructed.")
                }
            ),
            scheduleProviderStartupMaintenance: {
                providerScheduleCount += 1
            },
            scheduleRetryScratchStartupMaintenance: {
                retryScratchScheduleCount += 1
            }
        )
        let app = HoldTypeIOSApp(composition: composition)
        let root = HoldTypeIOSRootView(composition: app.composition)

        await composition.lifecycleScheduler.waitUntilIdle()
        #expect(root.composition === composition)
        #expect(root.presentation == .storageUnavailable)
        #expect(composition.availability == .storageUnavailable)
        #expect(composition.applicationSupportDirectoryURL == nil)
        #expect(composition.historyCoordinator == nil)
        #expect(composition.settingsStateOwner == nil)
        #expect(composition.libraryStateOwner == nil)
        #expect(composition.credentialCoordinator == nil)
        #expect(composition.failedHistoryService == nil)
        #expect(
            composition.lifecycleScheduler.latestDisposition
                == .pendingLocalRecovery
        )
        #expect(historyFactoryCalls == 0)
        #expect(settingsFactoryCalls == 0)
        #expect(libraryFactoryCalls == 0)
        #expect(credentialFactoryCalls == 0)
        #expect(serviceFactoryCalls == 0)
        #expect(providerScheduleCount == 1)
        #expect(retryScratchScheduleCount == 1)
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
        #expect(app.composition.historyCoordinator == nil)
        #expect(app.composition.settingsStateOwner == nil)
        #expect(app.composition.libraryStateOwner == nil)
        #expect(app.composition.credentialCoordinator == nil)
        #expect(app.composition.failedHistoryService == nil)
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
            value?.hasSuffix(".app.holdtype.HoldType.ios") == true
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
