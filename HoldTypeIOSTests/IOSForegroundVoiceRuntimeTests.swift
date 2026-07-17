import Foundation
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
@_spi(HoldTypeIOSCore) import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSForegroundVoiceRuntimeTests {
    @Test func onlyAcceptancePublishesAndProjectionFailureDoesNotChangeIt()
        async throws {
        let publication = IOSVoiceRuntimeKeyboardPublicationProbe(
            result: false
        )
        let historyRefresh = IOSVoiceRuntimeHistoryRefreshProbe()
        let draft = IOSVoiceRuntimeDraftAcceptanceProbe()
        let record = try IOSV1AcceptedOutputDeliveryRecord(
            resultID: UUID(),
            sourceAttemptID: UUID(),
            acceptedText: "Accepted without projection coupling",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let acceptance = IOSForegroundVoiceProcessingResolution.acceptance(
            .resultReady(record)
        )

        let preserved = await IOSKeyboardSnapshotAcceptancePublication.apply(
            to: acceptance,
            draftInsertionMode: .append,
            acceptDraft: { await draft.accept($0, mode: $1) },
            refreshAcceptedHistory: {
                await historyRefresh.refresh()
            },
            publish: { _ = await publication.publish() }
        )
        #expect(preserved == acceptance)
        #expect(await publication.callCount == 1)
        #expect(await historyRefresh.callCount == 1)
        #expect(await draft.records == [record])
        #expect(await draft.modes == [.append])

        let notStarted = IOSForegroundVoiceProcessingResolution.notStarted(
            .providerUnavailable
        )
        let unchanged = await IOSKeyboardSnapshotAcceptancePublication.apply(
            to: notStarted,
            acceptDraft: { await draft.accept($0, mode: $1) },
            refreshAcceptedHistory: {
                await historyRefresh.refresh()
            },
            publish: { _ = await publication.publish() }
        )
        #expect(unchanged == notStarted)
        #expect(await publication.callCount == 1)
        #expect(await historyRefresh.callCount == 1)
        #expect(await draft.records == [record])
    }

    @Test func constructionBuildsOnePassiveGraphForEveryScene() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "holdtype-voice-runtime-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let loads = IOSVoiceRuntimeLoadProbe()
        let settingsStateOwner = IOSAppSettingsStateOwner(
            load: {
                await loads.recordSettingsLoad()
                return .defaults
            },
            commit: { $0 }
        )
        let libraryStateOwner = IOSLibraryStateOwner(
            load: {
                await loads.recordLibraryLoad()
                return .defaults
            },
            commit: { $0 }
        )
        let consentCoordinator = IOSV1ProviderConsentCoordinator(
            applicationSupportDirectoryURL: root
        )
        let persistenceOwner = IOSV1ForegroundVoicePersistenceOwner(
            applicationSupportDirectoryURL: root
        )
        let factories = IOSVoiceRuntimeFactoryProbe()

        let runtime = IOSForegroundVoiceRuntime(
            settingsStateOwner: settingsStateOwner,
            libraryStateOwner: libraryStateOwner,
            providerConsentCoordinator: consentCoordinator,
            persistenceOwner: persistenceOwner,
            voiceDraftOwner: IOSVoiceDraftOwner(
                repository: IOSVoiceDraftRepository(
                    applicationSupportDirectoryURL: root
                )
            ),
            credentialCoordinator: nil,
            processor: nil,
            factories: factories.value
        )

        #expect(
            factories.events == [
                "scene-registry",
                "permission-adapter",
                "permission-owner",
                "audio-adapter",
                "audio-owner",
                "feedback",
                "finalization",
                "recorder",
                "provider",
                "history-playback",
                "workflow",
                "controller"
            ]
        )
        #expect(factories.workflowRegistry === runtime.sceneRegistry)
        #expect(factories.controllerRegistry === runtime.sceneRegistry)
        #expect(runtime.controller.sceneRegistry === runtime.sceneRegistry)
        #expect(factories.platformEffectCount == 0)
        #expect(await loads.snapshot() == .init(settings: 0, library: 0))
        #expect(settingsStateOwner.snapshot() == .notLoaded)
        #expect(libraryStateOwner.snapshot() == .notLoaded)

        let firstController = runtime.controller
        let firstScene = runtime.sceneRegistry.registerScene(
            initialActivity: .active
        )
        let secondController = runtime.controller
        _ = runtime.sceneRegistry.registerScene(
            initialActivity: .background
        )
        #expect(firstController === secondController)
        #expect(runtime.sceneRegistry.snapshot.registeredSceneCount == 2)

        let dependencies = try #require(factories.dependencies)
        #expect(
            await persistenceOwner.reconcileCaptureSourcesAtLaunch() == .empty
        )
        #expect(
            await dependencies.recoverContainingAppLifecycle(
                .foregroundOpportunity
            )
                == .complete
        )
        #expect(
            await dependencies.recoverContainingAppLifecycle(.processLaunch)
                == .complete
        )
        #expect(try await dependencies.loadPending() == nil)
        #expect(try await persistenceOwner.loadLatestResult() == .absent)
        #expect(try await dependencies.loadLatest() == .absent)
        let lease = try #require(firstScene.acquireStartLease())
        let consent = await dependencies.observeConsent()
        let continuation = Task { @MainActor in
            await dependencies.continueConsent(lease, consent)
        }
        for _ in 0..<100 where runtime.providerConsentPresentationOwner
            .voicePrompt == nil {
            await Task.yield()
        }
        let prompt = try #require(
            runtime.providerConsentPresentationOwner.voicePrompt
        )
        let capability = try #require(
            firstScene.promptDecisionCapability()
        )
        runtime.providerConsentPresentationOwner.dismissVoicePrompt(
            prompt.id,
            from: capability
        )
        #expect(await continuation.value == nil)
        #expect(lease.finish())
        #expect(factories.platformEffectCount == 0)

        guard case .unavailable = await runtime.providerBridge
                .resolveCredential() else {
            Issue.record("Expected missing credentials to remain unavailable.")
            return
        }
        #expect(factories.platformEffectCount == 0)
    }
}

private actor IOSVoiceRuntimeDraftAcceptanceProbe {
    private(set) var records: [IOSV1AcceptedOutputDeliveryRecord] = []
    private(set) var modes: [IOSVoiceDraftInsertionMode] = []

    func accept(
        _ record: IOSV1AcceptedOutputDeliveryRecord,
        mode: IOSVoiceDraftInsertionMode
    ) {
        records.append(record)
        modes.append(mode)
    }
}

private actor IOSVoiceRuntimeHistoryRefreshProbe {
    private(set) var callCount = 0

    func refresh() {
        callCount += 1
    }
}

private actor IOSVoiceRuntimeKeyboardPublicationProbe {
    private let result: Bool
    private(set) var callCount = 0

    init(result: Bool) {
        self.result = result
    }

    func publish() -> Bool {
        callCount += 1
        return result
    }
}

private actor IOSVoiceRuntimeLoadProbe {
    struct Snapshot: Equatable {
        let settings: Int
        let library: Int
    }

    private var settings = 0
    private var library = 0

    func recordSettingsLoad() { settings += 1 }
    func recordLibraryLoad() { library += 1 }
    func snapshot() -> Snapshot {
        Snapshot(settings: settings, library: library)
    }
}

@MainActor
private final class IOSVoiceRuntimeFactoryProbe {
    var events: [String] = []
    var dependencies: IOSForegroundVoiceWorkflowDependencies?
    var workflowRegistry: IOSVoiceSceneRegistry?
    var controllerRegistry: IOSVoiceSceneRegistry?
    var permissionEffects = 0
    var audioEffects = 0
    var historyPlaybackEffects = 0

    var platformEffectCount: Int {
        permissionEffects + audioEffects + historyPlaybackEffects
    }

    lazy var value = IOSForegroundVoiceRuntime.Factories(
        makeSceneRegistry: { [unowned self] in
            events.append("scene-registry")
            return IOSVoiceSceneRegistry()
        },
        makePermissionAdapter: { [unowned self] in
            events.append("permission-adapter")
            return IOSMicrophonePermissionAdapter(
                client: IOSMicrophonePermissionClient(
                    read: { [unowned self] in
                        permissionEffects += 1
                        return .denied
                    },
                    request: { [unowned self] in
                        permissionEffects += 1
                    }
                )
            )
        },
        makePermissionOwner: { [unowned self] adapter in
            events.append("permission-owner")
            return IOSForegroundVoiceWorkflowPermissionOwner(
                adapter: adapter
            )
        },
        makeAudioAdapter: { [unowned self] in
            events.append("audio-adapter")
            return IOSAudioSessionAdapter(
                system: IOSVoiceRuntimeAudioSystem(probe: self)
            )
        },
        makeAudioOwner: { [unowned self] adapter in
            events.append("audio-owner")
            return IOSForegroundVoiceWorkflowAudioOwner(adapter: adapter)
        },
        makeFeedbackBridge: { [unowned self] in
            events.append("feedback")
            return IOSForegroundVoiceFeedbackBridge()
        },
        makeFinalizationOwner: { [unowned self] in
            events.append("finalization")
            return IOSForegroundVoiceWorkflowFinalizationOwner()
        },
        makeRecorderBridge: { [unowned self] persistence, feedback in
            events.append("recorder")
            return IOSForegroundVoiceRecorderBridge(
                persistenceOwner: persistence,
                feedback: feedback
            )
        },
        makeProviderBridge: { [unowned self] credential, processor in
            events.append("provider")
            #expect(credential == nil)
            #expect(processor == nil)
            return IOSForegroundVoiceProviderBridge(
                credentialCoordinator: credential,
                processor: processor
            )
        },
        makeHistoryPlaybackArbitrator: { [unowned self] in
            events.append("history-playback")
            return IOSVoiceRuntimeHistoryPlaybackProbe(owner: self)
        },
        makeWorkflow: { [unowned self] dependencies in
            events.append("workflow")
            self.dependencies = dependencies
            workflowRegistry = dependencies.sceneRegistry
            return IOSForegroundVoiceWorkflow(dependencies: dependencies)
        },
        makeController: { [unowned self] client, registry in
            events.append("controller")
            controllerRegistry = registry
            return IOSForegroundVoiceController(
                client: client,
                sceneRegistry: registry
            )
        }
    )
}

@MainActor
private final class IOSVoiceRuntimeAudioSystem: IOSAudioSessionSystem {
    private unowned let probe: IOSVoiceRuntimeFactoryProbe

    init(probe: IOSVoiceRuntimeFactoryProbe) {
        self.probe = probe
    }

    func setCategory(_ configuration: IOSAudioSessionConfiguration) throws {
        _ = configuration
        probe.audioEffects += 1
    }

    func setAllowsHapticsAndSystemSoundsDuringRecording(
        _ allowed: Bool
    ) throws {
        _ = allowed
        probe.audioEffects += 1
    }

    func setActive(_ request: IOSAudioSessionActivationRequest) throws {
        _ = request
        probe.audioEffects += 1
    }

    func currentState() -> IOSAudioSessionCurrentState {
        probe.audioEffects += 1
        return IOSAudioSessionCurrentState(
            inputPorts: [],
            isInputAvailable: false,
            isInputMuted: false,
            sampleRate: 0,
            inputNumberOfChannels: 0
        )
    }

    func installEventObserver(
        _ receive: @escaping @MainActor @Sendable (
            IOSAudioSessionSystemEvent
        ) -> Void
    ) -> any IOSAudioSessionSystemObservation {
        _ = receive
        probe.audioEffects += 1
        return IOSVoiceRuntimeAudioObservation(probe: probe)
    }
}

@MainActor
private final class IOSVoiceRuntimeAudioObservation:
    IOSAudioSessionSystemObservation {
    private unowned let probe: IOSVoiceRuntimeFactoryProbe

    init(probe: IOSVoiceRuntimeFactoryProbe) {
        self.probe = probe
    }

    func cancel() { probe.audioEffects += 1 }
}

@MainActor
private final class IOSVoiceRuntimeHistoryPlaybackProbe:
    IOSForegroundVoiceHistoryPlaybackArbitrating {
    private unowned let owner: IOSVoiceRuntimeFactoryProbe

    init(owner: IOSVoiceRuntimeFactoryProbe) {
        self.owner = owner
    }

    func stopAndDeactivate() async -> Bool {
        owner.historyPlaybackEffects += 1
        return true
    }
}
