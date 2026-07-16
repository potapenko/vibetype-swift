import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
@_spi(HoldTypeIOSCore) import HoldTypePersistence

nonisolated enum IOSKeyboardSnapshotAcceptancePublication {
    typealias Publish = @Sendable () async -> Void
    typealias AcceptDraft = @Sendable (
        IOSV1AcceptedOutputDeliveryRecord,
        IOSVoiceDraftInsertionMode
    ) async -> Void

    static func apply(
        to resolution: IOSForegroundVoiceProcessingResolution,
        draftInsertionMode: IOSVoiceDraftInsertionMode = .replace,
        acceptDraft: @escaping AcceptDraft = { _, _ in },
        publish: @escaping Publish
    ) async -> IOSForegroundVoiceProcessingResolution {
        if case .acceptance(.resultReady(let record, _)) = resolution {
            await acceptDraft(record, draftInsertionMode)
            await publish()
        }
        return resolution
    }
}

/// One passive process-lifetime Voice graph. Scenes receive its shared
/// controller and registry identities; they never construct platform or
/// persistence owners themselves.
@MainActor
final class IOSForegroundVoiceRuntime {
    struct Factories {
        let makeSceneRegistry: @MainActor () -> IOSVoiceSceneRegistry
        let makePermissionAdapter: @MainActor () ->
            IOSMicrophonePermissionAdapter
        let makePermissionOwner: @MainActor (
            IOSMicrophonePermissionAdapter
        ) -> IOSForegroundVoiceWorkflowPermissionOwner
        let makeAudioAdapter: @MainActor () -> IOSAudioSessionAdapter
        let makeAudioOwner: @MainActor (
            IOSAudioSessionAdapter
        ) -> IOSForegroundVoiceWorkflowAudioOwner
        let makeFeedbackBridge: @MainActor () ->
            IOSForegroundVoiceFeedbackBridge
        let makeFinalizationOwner: @MainActor () ->
            IOSForegroundVoiceWorkflowFinalizationOwner
        let makeRecorderBridge: @MainActor (
            IOSV1ForegroundVoicePersistenceOwner,
            IOSForegroundVoiceFeedbackBridge
        ) -> IOSForegroundVoiceRecorderBridge
        let makeProviderBridge: @MainActor (
            IOSOpenAICredentialCoordinator?,
            IOSForegroundVoiceProcessor?
        ) -> IOSForegroundVoiceProviderBridge
        let makeHistoryPlaybackArbitrator: @MainActor () ->
            any IOSForegroundVoiceHistoryPlaybackArbitrating
        let makeWorkflow: @MainActor (
            IOSForegroundVoiceWorkflowDependencies
        ) -> IOSForegroundVoiceWorkflow
        let makeController: @MainActor (
            IOSForegroundVoiceClient,
            IOSVoiceSceneRegistry
        ) -> IOSForegroundVoiceController

        static let production = Factories(
            makeSceneRegistry: { IOSVoiceSceneRegistry() },
            makePermissionAdapter: {
                IOSMicrophonePermissionAdapter()
            },
            makePermissionOwner: { adapter in
                IOSForegroundVoiceWorkflowPermissionOwner(
                    adapter: adapter
                )
            },
            makeAudioAdapter: { IOSAudioSessionAdapter() },
            makeAudioOwner: { adapter in
                IOSForegroundVoiceWorkflowAudioOwner(adapter: adapter)
            },
            makeFeedbackBridge: {
                IOSForegroundVoiceFeedbackBridge()
            },
            makeFinalizationOwner: {
                IOSForegroundVoiceWorkflowFinalizationOwner()
            },
            makeRecorderBridge: { persistenceOwner, feedbackBridge in
                IOSForegroundVoiceRecorderBridge(
                    persistenceOwner: persistenceOwner,
                    feedback: feedbackBridge
                )
            },
            makeProviderBridge: { credentialCoordinator, processor in
                IOSForegroundVoiceProviderBridge(
                    credentialCoordinator: credentialCoordinator,
                    processor: processor
                )
            },
            makeHistoryPlaybackArbitrator: {
                IOSHistoryAudioPlaybackOwner()
            },
            makeWorkflow: { dependencies in
                IOSForegroundVoiceWorkflow(dependencies: dependencies)
            },
            makeController: { client, registry in
                IOSForegroundVoiceController(
                    client: client,
                    sceneRegistry: registry
                )
            }
        )
    }

    let sceneRegistry: IOSVoiceSceneRegistry
    let permissionAdapter: IOSMicrophonePermissionAdapter
    let permissionOwner: IOSForegroundVoiceWorkflowPermissionOwner
    let providerConsentPresentationOwner:
        IOSProviderConsentPresentationOwner
    let audioAdapter: IOSAudioSessionAdapter
    let audioOwner: IOSForegroundVoiceWorkflowAudioOwner
    let feedbackBridge: IOSForegroundVoiceFeedbackBridge
    let finalizationOwner: IOSForegroundVoiceWorkflowFinalizationOwner
    let keyboardWarmInputKeeper: IOSKeyboardWarmInputKeeper
    let recorderBridge: IOSForegroundVoiceRecorderBridge
    let providerBridge: IOSForegroundVoiceProviderBridge
    let historyPlaybackArbitrator:
        any IOSForegroundVoiceHistoryPlaybackArbitrating

    var historyAudioPlaybackOwner: IOSHistoryAudioPlaybackOwner? {
        historyPlaybackArbitrator as? IOSHistoryAudioPlaybackOwner
    }
    let latestResultOwner: IOSForegroundVoiceLatestResultOwner
    let voiceDraftOwner: IOSVoiceDraftOwner
    let voiceDraftTextActionOwner: IOSVoiceDraftTextActionOwner
    let workflow: IOSForegroundVoiceWorkflow
    let keyboardDictationSession: IOSKeyboardDictationSessionCoordinator
    let controller: IOSForegroundVoiceController
    let lifecycleCoordinator:
        IOSForegroundVoiceProcessLifecycleCoordinator

    init(
        settingsStateOwner: IOSAppSettingsStateOwner,
        libraryStateOwner: IOSLibraryStateOwner,
        providerConsentCoordinator: IOSV1ProviderConsentCoordinator,
        persistenceOwner: IOSV1ForegroundVoicePersistenceOwner,
        voiceDraftOwner: IOSVoiceDraftOwner,
        credentialCoordinator: IOSOpenAICredentialCoordinator?,
        processor: IOSForegroundVoiceProcessor?,
        publishKeyboardSnapshot: @escaping @Sendable () async -> Bool = {
            true
        },
        factories: Factories
    ) {
        let sceneRegistry = factories.makeSceneRegistry()
        self.sceneRegistry = sceneRegistry

        let permissionAdapter = factories.makePermissionAdapter()
        self.permissionAdapter = permissionAdapter
        let permissionOwner = factories.makePermissionOwner(
            permissionAdapter
        )
        self.permissionOwner = permissionOwner
        let providerConsentPresentationOwner =
            IOSProviderConsentPresentationOwner(
                coordinator: providerConsentCoordinator,
                sceneRegistry: sceneRegistry,
                permissionAdapter: permissionAdapter
            )
        self.providerConsentPresentationOwner =
            providerConsentPresentationOwner

        let audioAdapter = factories.makeAudioAdapter()
        self.audioAdapter = audioAdapter
        let audioOwner = factories.makeAudioOwner(audioAdapter)
        self.audioOwner = audioOwner

        let feedbackBridge = factories.makeFeedbackBridge()
        self.feedbackBridge = feedbackBridge
        let finalizationOwner = factories.makeFinalizationOwner()
        self.finalizationOwner = finalizationOwner
        let keyboardWarmInputKeeper = IOSKeyboardWarmInputKeeper()
        self.keyboardWarmInputKeeper = keyboardWarmInputKeeper
        let recorderBridge = factories.makeRecorderBridge(
            persistenceOwner,
            feedbackBridge
        )
        self.recorderBridge = recorderBridge
        let providerBridge = factories.makeProviderBridge(
            credentialCoordinator,
            processor
        )
        self.providerBridge = providerBridge
        let historyPlaybackArbitrator = factories
            .makeHistoryPlaybackArbitrator()
        self.historyPlaybackArbitrator = historyPlaybackArbitrator
        let latestResultOwner = IOSForegroundVoiceLatestResultOwner(
            persistenceOwner: persistenceOwner,
            publishKeyboardSnapshot: publishKeyboardSnapshot
        )
        self.latestResultOwner = latestResultOwner
        self.voiceDraftOwner = voiceDraftOwner
        voiceDraftTextActionOwner = IOSVoiceDraftTextActionOwner(
            draftOwner: voiceDraftOwner,
            client: IOSVoiceDraftTextActionClient(
                settingsStateOwner: settingsStateOwner,
                consentOwner: providerConsentPresentationOwner,
                credentialCoordinator: credentialCoordinator,
                processor: processor
            )
        )

        let dependencies = IOSForegroundVoiceWorkflowDependencies(
            sceneRegistry: sceneRegistry,
            reconcileCaptureSources: {
                await persistenceOwner.reconcileCaptureSourcesAtLaunch()
            },
            recoverContainingAppLifecycle: { opportunity in
                await persistenceOwner.recoverContainingAppLifecycle(
                    opportunity
                )
            },
            loadPending: {
                try await persistenceOwner.load()
            },
            loadLatest: {
                try await latestResultOwner.loadForVoiceWorkflow()
            },
            loadSettings: {
                try await settingsStateOwner
                    .confirmedValueForProviderAction()
            },
            loadLibrary: {
                try await libraryStateOwner
                    .confirmedValueForProviderAction()
            },
            observeConsent: {
                await providerConsentPresentationOwner
                    .observeForVoicePreflight()
            },
            continueConsent: { lease, observation in
                await providerConsentPresentationOwner.continueVoiceStart(
                    lease: lease,
                    observation: observation
                )
            },
            revalidateConsent: { observation in
                providerConsentCoordinator.makeAuthorization(
                    from: observation
                ) != nil
            },
            resolveCredential: {
                await providerBridge.resolveCredential()
            },
            revalidateCredential: { proof in
                await providerBridge.revalidateCredential(proof)
            },
            permission: permissionOwner.client,
            stopHistoryPlayback: {
                await historyPlaybackArbitrator.stopAndDeactivate()
            },
            prepareDraftForNewDictation: {
                await voiceDraftOwner.clearForNewDictation()
            },
            activateAudio: {
                try audioOwner.activate()
            },
            playStartBoundary: { audioCuesEnabled in
                await feedbackBridge.playStartBoundary(
                    audioCuesEnabled: audioCuesEnabled
                )
            },
            cancelStartBoundary: {
                feedbackBridge.cancelStartBoundary()
            },
            playStopBoundary: { audioCuesEnabled in
                await feedbackBridge.playStopBoundary(
                    audioCuesEnabled: audioCuesEnabled
                )
            },
            beginKeyboardWarmInput: {
                try keyboardWarmInputKeeper.startIfNeeded()
            },
            endKeyboardWarmInput: {
                keyboardWarmInputKeeper.stop()
            },
            makeRecording: {
                attemptID,
                outputIntent,
                draftInsertionMode,
                forcesTextCorrection in
                try await recorderBridge.makeRecording(
                    attemptID: attemptID,
                    outputIntent: outputIntent,
                    draftInsertionMode: draftInsertionMode,
                    forcesTextCorrection: forcesTextCorrection
                )
            },
            beginFinalization: { onExpiration in
                finalizationOwner.begin(onExpiration: onExpiration)
            },
            process: { request, progress in
                let resolution = await providerBridge.process(
                    request,
                    progress: progress
                )
                return await IOSKeyboardSnapshotAcceptancePublication.apply(
                    to: resolution,
                    draftInsertionMode: request.draftInsertionMode,
                    acceptDraft: { record, mode in
                        _ = await voiceDraftOwner.accept(record, mode: mode)
                    },
                    publish: {
                        await latestResultOwner.refreshKeyboardProjection()
                    }
                )
            },
            recoverCapture: { attemptID, configuration in
                try await persistenceOwner.recoverCapture(
                    attemptID: attemptID,
                    transcriptionConfiguration: configuration
                )
            },
            discardCapture: { attemptID in
                try await persistenceOwner.discardCapture(
                    attemptID: attemptID
                )
            },
            discardPending: { expectation in
                try await persistenceOwner.discard(expected: expectation)
            },
            sleep: { duration in
                try await Task.sleep(for: duration)
            },
            makeUUID: { UUID() },
            recordDiagnostic: { event in
                IOSRuntimeDiagnosticsStore.app.record(event)
            }
        )
        let workflow = factories.makeWorkflow(dependencies)
        self.workflow = workflow
        keyboardDictationSession = IOSKeyboardDictationSessionCoordinator(
            workflow: workflow.keyboardDictationClient,
            supersession: .live(persistenceOwner: persistenceOwner),
            permission: permissionOwner.client
        )
        let controller = factories.makeController(
            workflow.client,
            sceneRegistry
        )
        self.controller = controller
        providerConsentPresentationOwner.bindVoiceInvalidation {
            [weak controller] in
            controller?.providerConsentDidInvalidate()
        }
        lifecycleCoordinator = IOSForegroundVoiceProcessLifecycleCoordinator(
            workflow: workflow,
            controller: controller
        )
    }
}

extension IOSForegroundVoiceRuntime:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSForegroundVoiceRuntime(<redacted>)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}
