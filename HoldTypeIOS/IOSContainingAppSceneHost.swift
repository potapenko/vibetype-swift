import SwiftUI

/// Per-window lifecycle shell. The process composition stays shared while the
/// Voice scene facade remains tied to one exact SwiftUI scene identity.
struct IOSContainingAppSceneHost: View {
    let composition: IOSContainingAppComposition

    var body: some View {
        if let runtime = composition.foregroundVoiceRuntime {
            IOSRegisteredContainingAppSceneHost(
                composition: composition,
                runtime: runtime
            )
        } else {
            rootView
        }
    }

    private var rootView: HoldTypeIOSRootView {
        HoldTypeIOSRootView(composition: composition)
    }
}

private struct IOSRegisteredContainingAppSceneHost: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var voiceSceneOwner: IOSForegroundVoiceSceneHostOwner
    @State private var keyboardHandoffPresentationOwner:
        IOSKeyboardHandoffPresentationOwner

    let composition: IOSContainingAppComposition
    let runtime: IOSForegroundVoiceRuntime

    init(
        composition: IOSContainingAppComposition,
        runtime: IOSForegroundVoiceRuntime
    ) {
        self.composition = composition
        self.runtime = runtime
        _voiceSceneOwner = State(
            initialValue: IOSForegroundVoiceSceneHostOwner(runtime: runtime)
        )
        _keyboardHandoffPresentationOwner = State(
            initialValue: IOSKeyboardHandoffPresentationOwner(
                session: runtime.keyboardDictationSession,
                preflight: .live(
                    settingsStateOwner: composition.settingsStateOwner,
                    credentialCoordinator: composition.credentialCoordinator,
                    providerConsentCoordinator:
                        composition.providerConsentCoordinator,
                    permission: runtime.permissionOwner.client
                ),
                pendingRecordingOwner:
                    composition.pendingRecordingHistoryStateOwner
            )
        )
    }

    var body: some View {
        HoldTypeIOSRootView(
            composition: composition,
            keyboardHandoffPresentationOwner:
                keyboardHandoffPresentationOwner
        )
            .environment(runtime.controller)
            .environment(voiceSceneOwner)
            .environment(runtime.voiceDraftOwner)
            .environment(runtime.voiceFixesCatalogOwner)
            .environment(runtime.voiceDraftTextActionOwner)
            .environment(runtime.providerConsentPresentationOwner)
            .environment(runtime.keyboardDictationSession)
            .onChange(of: scenePhase, initial: true) { _, newPhase in
                voiceSceneOwner.registerOrUpdateActivity(
                    IOSVoiceSceneActivity(newPhase)
                )
                composition.keyboardFixRuntimeOwner?.handleSceneActivity(
                    IOSVoiceSceneActivity(newPhase)
                )
            }
            .onOpenURL { url in
                composition.keyboardFixRuntimeOwner?.handleLaunchURL(url)
            }
            .onDisappear {
                voiceSceneOwner.unregister()
            }
    }
}

private extension HoldTypeIOSRootView {
    init(
        composition: IOSContainingAppComposition,
        keyboardHandoffPresentationOwner:
            IOSKeyboardHandoffPresentationOwner? = nil
    ) {
        self.init(
            settingsStateOwner: composition.settingsStateOwner,
            libraryStateOwner: composition.libraryStateOwner,
            openAISettingsStateOwner:
                composition.openAISettingsStateOwner,
            usageEstimateStateOwner:
                composition.usageEstimateStateOwner,
            acceptedTextHistoryStateOwner:
                composition.acceptedTextHistoryStateOwner,
            foregroundVoiceRuntimeAvailable:
                composition.foregroundVoiceRuntime != nil,
            historyPlaybackActions:
                composition.historyPlaybackActions,
            pendingRecordingHistoryStateOwner:
                composition.pendingRecordingHistoryStateOwner,
            recordingCacheLifecycleActions:
                composition.recordingCacheLifecycleActions,
            keyboardHandoffPresentationOwner:
                keyboardHandoffPresentationOwner
        )
    }
}

extension IOSVoiceSceneActivity {
    init(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            self = .active
        case .inactive:
            self = .inactive
        case .background:
            self = .background
        @unknown default:
            self = .background
        }
    }
}
