import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
@_spi(HoldTypeIOSCore) import HoldTypePersistence

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
            IOSForegroundVoicePersistenceOwner,
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
                IOSNoActiveHistoryPlaybackArbitrator()
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
    let audioAdapter: IOSAudioSessionAdapter
    let audioOwner: IOSForegroundVoiceWorkflowAudioOwner
    let feedbackBridge: IOSForegroundVoiceFeedbackBridge
    let finalizationOwner: IOSForegroundVoiceWorkflowFinalizationOwner
    let recorderBridge: IOSForegroundVoiceRecorderBridge
    let providerBridge: IOSForegroundVoiceProviderBridge
    let historyPlaybackArbitrator:
        any IOSForegroundVoiceHistoryPlaybackArbitrating
    let latestResultOwner: IOSForegroundVoiceLatestResultOwner
    let workflow: IOSForegroundVoiceWorkflow
    let controller: IOSForegroundVoiceController
    let lifecycleCoordinator:
        IOSForegroundVoiceProcessLifecycleCoordinator

    init(
        settingsStateOwner: IOSAppSettingsStateOwner,
        libraryStateOwner: IOSLibraryStateOwner,
        providerConsentCoordinator: IOSProviderConsentCoordinator,
        persistenceOwner: IOSForegroundVoicePersistenceOwner,
        historyCoordinator: IOSAcceptedHistoryCoordinator,
        credentialCoordinator: IOSOpenAICredentialCoordinator?,
        processor: IOSForegroundVoiceProcessor?,
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

        let audioAdapter = factories.makeAudioAdapter()
        self.audioAdapter = audioAdapter
        let audioOwner = factories.makeAudioOwner(audioAdapter)
        self.audioOwner = audioOwner

        let feedbackBridge = factories.makeFeedbackBridge()
        self.feedbackBridge = feedbackBridge
        let finalizationOwner = factories.makeFinalizationOwner()
        self.finalizationOwner = finalizationOwner
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
            persistenceOwner: persistenceOwner
        )
        self.latestResultOwner = latestResultOwner

        let dependencies = IOSForegroundVoiceWorkflowDependencies(
            sceneRegistry: sceneRegistry,
            reconcileCaptureSources: {
                await persistenceOwner.reconcileCaptureSourcesAtLaunch()
            },
            recoverContainingAppLifecycle: { opportunity in
                await historyCoordinator.recoverContainingAppLifecycle(
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
                await providerConsentCoordinator.observe()
            },
            continueConsent: { _, _ in
                // P4D-3 has no scene-owned consent presenter. A missing
                // decision remains blocked without a prompt or side effect.
                nil
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
            makeRecording: { attemptID, outputIntent in
                try await recorderBridge.makeRecording(
                    attemptID: attemptID,
                    outputIntent: outputIntent
                )
            },
            beginFinalization: { onExpiration in
                finalizationOwner.begin(onExpiration: onExpiration)
            },
            process: { request, progress in
                await providerBridge.process(
                    request,
                    progress: progress
                )
            },
            retryLocalRecovery: { authorization, progress in
                await providerBridge.retryLocalRecovery(
                    authorization,
                    progress: progress
                )
            },
            recoverCapture: { capability, configuration in
                try await persistenceOwner.recoverCapture(
                    capability,
                    transcriptionConfiguration: configuration
                )
            },
            discardCapture: { capability in
                try await persistenceOwner.discardCapture(capability)
            },
            discardPending: { expectation in
                try await persistenceOwner.discard(expected: expectation)
            },
            retrySavingResult: { expectation in
                try await persistenceOwner.retrySavingResult(
                    expected: expectation
                )
            },
            sleep: { duration in
                try await Task.sleep(for: duration)
            },
            makeUUID: { UUID() }
        )
        let workflow = factories.makeWorkflow(dependencies)
        self.workflow = workflow
        let controller = factories.makeController(
            workflow.client,
            sceneRegistry
        )
        self.controller = controller
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
