//
//  HoldTypeIOSApp.swift
//  HoldType-iOS
//
//  Created by Codex on 6/21/26.
//

@_spi(HoldTypeIOSCore) import HoldTypePersistence
import SwiftUI

@main
struct HoldTypeIOSApp: App {
    let composition: IOSContainingAppComposition

    init() {
        #if DEBUG
        if IOSUIQualificationRoute.current != nil {
            composition = IOSContainingAppComposition(
                scheduleProviderStartupMaintenance: {},
                recoverContainingAppLifecycle: { _ in .complete }
            )
            return
        }
        #endif
        composition = IOSContainingAppComposition()
    }

    init(scheduleProviderStartupMaintenance: @MainActor () -> Void) {
        self.init(
            scheduleProviderStartupMaintenance:
                scheduleProviderStartupMaintenance,
            recoverContainingAppLifecycle: { _ in .complete }
        )
    }

    init(
        scheduleProviderStartupMaintenance: @MainActor () -> Void,
        recoverContainingAppLifecycle:
            @escaping IOSContainingAppLifecycleScheduler.Recovery
    ) {
        composition = IOSContainingAppComposition(
            scheduleProviderStartupMaintenance:
                scheduleProviderStartupMaintenance,
            recoverContainingAppLifecycle:
                recoverContainingAppLifecycle
        )
    }

    init(composition: IOSContainingAppComposition) {
        self.composition = composition
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let qualificationRoute = IOSUIQualificationRoute.current {
                IOSUIQualificationRootView(route: qualificationRoute)
            } else {
                IOSContainingAppSceneHost(composition: composition)
            }
            #else
            IOSContainingAppSceneHost(composition: composition)
            #endif
        }
    }
}

struct HoldTypeIOSRootView: View {
    let settingsStateOwner: IOSAppSettingsStateOwner?
    let libraryStateOwner: IOSLibraryStateOwner?
    let openAISettingsStateOwner:
        IOSOpenAICredentialSettingsStateOwner?
    let usageEstimateStateOwner: IOSUsageEstimateStateOwner?
    let acceptedTextHistoryStateOwner:
        IOSAcceptedTextHistoryStateOwner?
    let secureProviderAvailability: IOSSecureProviderAvailability
    let foregroundVoiceRuntimeAvailable: Bool
    let historyPlaybackActions: IOSHistoryPlaybackActions?
    let layout: IOSContainingAppShellLayout

    init(
        settingsStateOwner: IOSAppSettingsStateOwner?,
        libraryStateOwner: IOSLibraryStateOwner?,
        openAISettingsStateOwner:
            IOSOpenAICredentialSettingsStateOwner?,
        usageEstimateStateOwner: IOSUsageEstimateStateOwner?,
        acceptedTextHistoryStateOwner:
            IOSAcceptedTextHistoryStateOwner?,
        secureProviderAvailability: IOSSecureProviderAvailability,
        foregroundVoiceRuntimeAvailable: Bool = false,
        historyPlaybackActions: IOSHistoryPlaybackActions? = nil,
        layout: IOSContainingAppShellLayout = .current
    ) {
        self.settingsStateOwner = settingsStateOwner
        self.libraryStateOwner = libraryStateOwner
        self.openAISettingsStateOwner = openAISettingsStateOwner
        self.usageEstimateStateOwner = usageEstimateStateOwner
        self.acceptedTextHistoryStateOwner =
            acceptedTextHistoryStateOwner
        self.secureProviderAvailability = secureProviderAvailability
        self.foregroundVoiceRuntimeAvailable =
            foregroundVoiceRuntimeAvailable
        self.historyPlaybackActions = historyPlaybackActions
        self.layout = layout
    }

    var presentation: IOSContainingAppRootPresentation {
        .resolve(
            hasSettingsStateOwner:
                settingsStateOwner != nil,
            hasLibraryStateOwner:
                libraryStateOwner != nil,
            hasOpenAISettingsStateOwner:
                openAISettingsStateOwner != nil,
            hasUsageEstimateStateOwner:
                usageEstimateStateOwner != nil,
            hasAcceptedTextHistoryStateOwner:
                acceptedTextHistoryStateOwner != nil
        )
    }

    var body: some View {
        if let settingsStateOwner,
           let libraryStateOwner,
           let openAISettingsStateOwner,
           let usageEstimateStateOwner,
           let acceptedTextHistoryStateOwner {
            IOSContainingAppShell(
                secureProviderAvailability: secureProviderAvailability,
                foregroundVoiceRuntimeAvailable:
                    foregroundVoiceRuntimeAvailable,
                historyPlaybackActions: historyPlaybackActions,
                layout: layout
            )
                .environment(settingsStateOwner)
                .environment(libraryStateOwner)
                .environment(openAISettingsStateOwner)
                .environment(usageEstimateStateOwner)
                .environment(acceptedTextHistoryStateOwner)
        } else {
            IOSContainingAppStorageUnavailableView()
        }
    }
}

#Preview("Storage unavailable") {
    IOSContainingAppStorageUnavailableView()
}
