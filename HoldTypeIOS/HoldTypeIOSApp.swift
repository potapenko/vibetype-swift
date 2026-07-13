//
//  HoldTypeIOSApp.swift
//  HoldType-iOS
//
//  Created by Codex on 6/21/26.
//

import HoldTypePersistence
import SwiftUI

@main
struct HoldTypeIOSApp: App {
    let composition: IOSContainingAppComposition

    init() {
        composition = IOSContainingAppComposition()
    }

    init(scheduleProviderStartupMaintenance: @MainActor () -> Void) {
        self.init(
            scheduleProviderStartupMaintenance:
                scheduleProviderStartupMaintenance,
            scheduleRetryScratchStartupMaintenance: {},
            recoverContainingAppLifecycle: { _ in .complete }
        )
    }

    init(
        scheduleProviderStartupMaintenance: @MainActor () -> Void,
        scheduleRetryScratchStartupMaintenance: @MainActor () -> Void = {},
        recoverContainingAppLifecycle:
            @escaping IOSContainingAppLifecycleScheduler.Recovery
    ) {
        composition = IOSContainingAppComposition(
            scheduleProviderStartupMaintenance:
                scheduleProviderStartupMaintenance,
            scheduleRetryScratchStartupMaintenance:
                scheduleRetryScratchStartupMaintenance,
            recoverContainingAppLifecycle:
                recoverContainingAppLifecycle
        )
    }

    init(composition: IOSContainingAppComposition) {
        self.composition = composition
    }

    var body: some Scene {
        WindowGroup {
            IOSContainingAppSceneHost(composition: composition)
        }
    }
}

struct HoldTypeIOSRootView: View {
    let settingsStateOwner: IOSAppSettingsStateOwner?
    let libraryStateOwner: IOSLibraryStateOwner?
    let openAISettingsStateOwner:
        IOSOpenAICredentialSettingsStateOwner?
    let secureProviderAvailability: IOSSecureProviderAvailability
    let foregroundVoiceRuntimeAvailable: Bool
    let layout: IOSContainingAppShellLayout

    init(
        settingsStateOwner: IOSAppSettingsStateOwner?,
        libraryStateOwner: IOSLibraryStateOwner?,
        openAISettingsStateOwner:
            IOSOpenAICredentialSettingsStateOwner?,
        secureProviderAvailability: IOSSecureProviderAvailability,
        foregroundVoiceRuntimeAvailable: Bool = false,
        layout: IOSContainingAppShellLayout = .current
    ) {
        self.settingsStateOwner = settingsStateOwner
        self.libraryStateOwner = libraryStateOwner
        self.openAISettingsStateOwner = openAISettingsStateOwner
        self.secureProviderAvailability = secureProviderAvailability
        self.foregroundVoiceRuntimeAvailable =
            foregroundVoiceRuntimeAvailable
        self.layout = layout
    }

    var presentation: IOSContainingAppRootPresentation {
        .resolve(
            hasSettingsStateOwner:
                settingsStateOwner != nil,
            hasLibraryStateOwner:
                libraryStateOwner != nil,
            hasOpenAISettingsStateOwner:
                openAISettingsStateOwner != nil
        )
    }

    var body: some View {
        if let settingsStateOwner,
           let libraryStateOwner,
           let openAISettingsStateOwner {
            IOSContainingAppShell(
                secureProviderAvailability: secureProviderAvailability,
                foregroundVoiceRuntimeAvailable:
                    foregroundVoiceRuntimeAvailable,
                layout: layout
            )
                .environment(settingsStateOwner)
                .environment(libraryStateOwner)
                .environment(openAISettingsStateOwner)
        } else {
            IOSContainingAppStorageUnavailableView()
        }
    }
}

#Preview("Storage unavailable") {
    IOSContainingAppStorageUnavailableView()
}
