import Foundation
import Testing
import UIKit
@testable import HoldTypeIOS

@MainActor
struct IOSContainingAppShellTests {
    @Test func destinationsHaveStableOrderPresentationAndFallback() {
        #expect(
            IOSContainingAppDestination.allCases == [
                .voice,
                .library,
                .history,
                .usage,
                .settings,
            ]
        )
        #expect(
            IOSContainingAppDestination.allCases.map(\.title) == [
                "Voice",
                "Rules",
                "History",
                "Usage",
                "Settings",
            ]
        )
        #expect(
            IOSContainingAppDestination.allCases.map(\.systemImage) == [
                "mic.fill",
                "checklist",
                "clock.arrow.circlepath",
                "chart.bar.xaxis",
                "gearshape.fill",
            ]
        )
        #expect(
            Set(
                IOSContainingAppDestination.allCases.map(
                    \.accessibilityIdentifier
                )
            ).count == 5
        )
        #expect(UIImage(systemName: "checklist") != nil)
        #expect(UIImage(systemName: "chart.bar.xaxis") != nil)
        #expect(
            IOSContainingAppDestination.resolve(
                storedRawValue: "library"
            ) == .library
        )
        #expect(
            IOSContainingAppDestination.resolve(
                storedRawValue: "not-a-destination"
            ) == .voice
        )
    }

    @Test func shellLayoutUsesTabsForPhoneAndSplitForPad() {
        #expect(
            IOSContainingAppShellLayout(interfaceIdiom: .phone) == .tabs
        )
        #expect(
            IOSContainingAppShellLayout(interfaceIdiom: .pad) == .split
        )
        #expect(
            IOSContainingAppShellLayout(interfaceIdiom: .unspecified) == .tabs
        )
    }

    @Test func settingsAttentionRoutesOwnInstructionsTargetsAndLaunchURLs() {
        let recoveries: [IOSSettingsAttention] = [
            .openAI,
            .transcription,
            .translation,
            .keyboard,
            .fullAccess,
            .privacyReview,
            .microphonePermission,
        ]

        for recovery in recoveries {
            #expect(!recovery.title.isEmpty)
            #expect(!recovery.detail.isEmpty)
            #expect(UIImage(systemName: recovery.systemImage) != nil)
        }

        #expect(IOSSettingsAttention.openAI.destination == .attention(.openAI))
        #expect(
            IOSSettingsAttention.transcription.destination
                == .attention(.transcription)
        )
        #expect(
            IOSSettingsAttention.translation.destination
                == .attention(.translation)
        )
        #expect(
            IOSSettingsAttention.translation.systemImage
                == "character.bubble"
        )
        #expect(
            IOSSettingsAttention.keyboard.defaultField == .keyboardPractice
        )
        #expect(
            IOSSettingsAttention.fullAccess.defaultField
                == .keyboardSystemSettings
        )
        #expect(
            IOSSettingsAttention.privacyReview.defaultField
                == .privacyProviderConsent
        )
        #expect(
            IOSSettingsAttention.microphonePermission.defaultField
                == .privacyMicrophone
        )
        #expect(
            IOSSettingsAttention.translation.launchURL?.absoluteString
                == "holdtype://settings/translation"
        )
        #expect(
            IOSSettingsAttention(
                launchURL: URL(string: "holdtype://settings/translation")!
            ) == .translation
        )
        #expect(
            IOSSettingsAttention(
                launchURL: URL(string: "other://settings/translation")!
            ) == nil
        )
    }

    @Test func practiceDraftSurvivesRoundTripAndIsSceneLocal() {
        var firstScene = IOSContainingAppSceneDraft()
        let secondScene = IOSContainingAppSceneDraft()
        firstScene.practiceText = "Scene one draft"

        #expect(
            IOSContainingAppDestinationSelectionDecision.resolve(
                current: .voice,
                requested: .settings,
                hasUnsavedEditor: false
            ) == .apply(.settings)
        )
        #expect(
            IOSContainingAppDestinationSelectionDecision.resolve(
                current: .settings,
                requested: .voice,
                hasUnsavedEditor: false
            ) == .apply(.voice)
        )
        #expect(firstScene.practiceText == "Scene one draft")
        #expect(secondScene.practiceText.isEmpty)
    }

    @Test func unsavedEditorRequiresConfirmationBeforeDestinationChange() {
        #expect(
            IOSContainingAppDestinationSelectionDecision.resolve(
                current: .settings,
                requested: .voice,
                hasUnsavedEditor: true
            ) == .confirmDiscard(.voice)
        )
        #expect(
            IOSContainingAppDestinationSelectionDecision.resolve(
                current: .library,
                requested: .usage,
                hasUnsavedEditor: true
            ) == .confirmDiscard(.usage)
        )
        #expect(
            IOSContainingAppDestinationSelectionDecision.resolve(
                current: .library,
                requested: .settings,
                hasUnsavedEditor: false
            ) == .apply(.settings)
        )
        #expect(
            IOSContainingAppDestinationSelectionDecision.resolve(
                current: .settings,
                requested: .settings,
                hasUnsavedEditor: true
            ) == .unchanged
        )
        #expect(
            IOSContainingAppDestinationSelectionDecision.resolve(
                current: .library,
                requested: .history,
                hasUnsavedEditor: false,
                hasBlockingEditorOperation: true
            ) == .blockedByEditorOperation
        )
        #expect(
            IOSContainingAppDestinationSelectionDecision.resolve(
                current: .library,
                requested: .library,
                hasUnsavedEditor: true,
                hasBlockingEditorOperation: true
            ) == .unchanged
        )
    }

    @Test func rootRequiresAllConcreteStateOwners() {
        #expect(
            IOSContainingAppRootPresentation.resolve(
                hasSettingsStateOwner: true,
                hasLibraryStateOwner: true,
                hasOpenAISettingsStateOwner: true,
                hasUsageEstimateStateOwner: true,
                hasAcceptedTextHistoryStateOwner: true
            ) == .shell
        )

        for availability in [
            (false, false, false, false, false),
            (true, false, true, true, true),
            (false, true, true, true, true),
            (true, true, false, true, true),
            (true, true, true, false, true),
            (true, true, true, true, false),
        ] {
            #expect(
                IOSContainingAppRootPresentation.resolve(
                    hasSettingsStateOwner: availability.0,
                    hasLibraryStateOwner: availability.1,
                    hasOpenAISettingsStateOwner: availability.2,
                    hasUsageEstimateStateOwner: availability.3,
                    hasAcceptedTextHistoryStateOwner: availability.4
                ) == .storageUnavailable
        )
    }
    }

    @Test
    func keyboardHandoffWaitsForTheExactActiveScene() {
        #expect(
            IOSKeyboardHandoffSceneDecision.resolve(.background)
                == .waitForActiveScene
        )
        #expect(
            IOSKeyboardHandoffSceneDecision.resolve(.inactive)
                == .waitForActiveScene
        )
        #expect(
            IOSKeyboardHandoffSceneDecision.resolve(.active)
                == .start
        )
    }

    @Test func secureProviderAvailabilityNeverInventsCredentialStatus() {
        #expect(
            IOSSecureProviderAvailability.resolve(
                compositionAvailability: .ready
            ) == .available
        )

        for compositionAvailability in [
            IOSContainingAppCompositionAvailability.credentialUnavailable,
            .storageUnavailable,
            .injected,
        ] {
            #expect(
                IOSSecureProviderAvailability.resolve(
                    compositionAvailability: compositionAvailability
                ) == .unavailable
            )
        }
    }
}
