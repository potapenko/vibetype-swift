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
                .settings,
            ]
        )
        #expect(
            IOSContainingAppDestination.allCases.map(\.title) == [
                "Voice",
                "Library",
                "History",
                "Settings",
            ]
        )
        #expect(
            IOSContainingAppDestination.allCases.map(\.systemImage) == [
                "mic.fill",
                "books.vertical.fill",
                "clock.arrow.circlepath",
                "gearshape.fill",
            ]
        )
        #expect(
            Set(
                IOSContainingAppDestination.allCases.map(
                    \.accessibilityIdentifier
                )
            ).count == 4
        )
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
                requested: .history,
                hasUnsavedEditor: true
            ) == .confirmDiscard(.history)
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
    }

    @Test func rootRequiresAllConcreteStateOwners() {
        #expect(
            IOSContainingAppRootPresentation.resolve(
                hasSettingsStateOwner: true,
                hasLibraryStateOwner: true,
                hasOpenAISettingsStateOwner: true
            ) == .shell
        )

        for availability in [
            (false, false, false),
            (true, false, true),
            (false, true, true),
            (true, true, false),
        ] {
            #expect(
                IOSContainingAppRootPresentation.resolve(
                    hasSettingsStateOwner: availability.0,
                    hasLibraryStateOwner: availability.1,
                    hasOpenAISettingsStateOwner: availability.2
                ) == .storageUnavailable
            )
        }
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
