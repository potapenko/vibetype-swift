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
    }

    var body: some View {
        HoldTypeIOSRootView(composition: composition)
            .environment(runtime.controller)
            .environment(voiceSceneOwner)
            .onChange(of: scenePhase, initial: true) { _, newPhase in
                voiceSceneOwner.registerOrUpdateActivity(
                    IOSVoiceSceneActivity(newPhase)
                )
            }
            .onDisappear {
                voiceSceneOwner.unregister()
            }
    }
}

private extension HoldTypeIOSRootView {
    init(composition: IOSContainingAppComposition) {
        self.init(
            settingsStateOwner: composition.settingsStateOwner,
            libraryStateOwner: composition.libraryStateOwner,
            openAISettingsStateOwner:
                composition.openAISettingsStateOwner,
            secureProviderAvailability: .resolve(
                compositionAvailability: composition.availability
            )
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
