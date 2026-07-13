#if DEBUG
import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

struct IOSUIQualificationRouteTests {
    @Test func qualificationIsOptInAndRejectsUnknownValues() {
        #expect(IOSUIQualificationRoute.resolve(environment: [:]) == nil)
        #expect(
            IOSUIQualificationRoute.resolve(
                environment: [
                    IOSUIQualificationRoute.environmentKey: "unknown",
                ]
            ) == nil
        )
    }

    @Test func everyQualificationRouteRoundTripsThroughLaunchEnvironment() {
        for route in IOSUIQualificationRoute.allCases {
            #expect(
                IOSUIQualificationRoute.resolve(
                    environment: [
                        IOSUIQualificationRoute.environmentKey: route.rawValue,
                    ]
                ) == route
            )
        }
    }

    @Test func usageQualificationRoutesAndScenariosAreDeterministic() {
        let routes: [IOSUIQualificationRoute] = [
            .usageEmpty,
            .usageKnown,
            .usageMixed,
            .usageUnknown,
            .usageLoadFailure,
            .usageWriteWarning,
            .usageResetFailure,
        ]
        #expect(
            routes.map(\.rawValue) == [
                "usage-empty",
                "usage-known",
                "usage-mixed",
                "usage-unknown",
                "usage-load-failure",
                "usage-write-warning",
                "usage-reset-failure",
            ]
        )
        #expect(routes.compactMap(\.usageScenario).count == routes.count)

        #expect(IOSUIQualificationUsageScenario.empty.summary.isEmpty)
        let known = IOSUIQualificationUsageScenario.known.summary
        #expect(known.totalEstimatedCostUSD != nil)
        #expect(!known.hasUnpricedUsage)
        let mixed = IOSUIQualificationUsageScenario.mixed.summary
        #expect(mixed.totalEstimatedCostUSD != nil)
        #expect(mixed.hasUnpricedUsage)
        let unknown = IOSUIQualificationUsageScenario.unknown.summary
        #expect(unknown.totalEstimatedCostUSD == nil)
        #expect(unknown.hasUnpricedUsage)
        #expect(
            IOSUIQualificationUsageScenario.loadFailure.hasLoadFailure
        )
        #expect(
            IOSUIQualificationUsageScenario.writeWarning.hasWriteWarning
        )
        #expect(
            IOSUIQualificationUsageScenario.resetFailure.hasResetFailure
        )
    }

    @Test func usageQualificationWriteTokensAreOrderedAndRedacted() {
        let first = IOSTranscriptionUsageQualificationFixture
            .writeToken(revision: 1)
        let second = IOSTranscriptionUsageQualificationFixture
            .writeToken(revision: 2)

        #expect(first < second)
        #expect(String(describing: first).contains("redacted"))
        #expect(!String(reflecting: first).contains("revision"))
        #expect(first.customMirror.children.isEmpty)
    }

    @Test func privacyQualificationObservationsAreDeterministicAndContentFree() {
        let ready = IOSV1ProviderConsentQualificationFixture
            .notReviewedObservation()
        let failure = IOSV1ProviderConsentQualificationFixture
            .localDataUnavailableObservation()
        let accepted = IOSV1ProviderConsentQualificationFixture
            .acceptedObservation()
        let unreadable = IOSV1ProviderConsentQualificationFixture
            .resettableUnreadableObservation()

        #expect(ready.status == .notReviewed)
        #expect(ready.decisionAt == nil)
        #expect(!ready.canResetUnreadableData)
        #expect(failure.status == .localDataUnavailable)
        #expect(accepted.status == .acceptedCurrentDisclosure)
        #expect(
            IOSV1ProviderConsentQualificationFixture
                .isAuthorizationReady(for: accepted)
        )
        #expect(unreadable.status == .localDataUnavailable)
        #expect(unreadable.canResetUnreadableData)
        #expect(
            IOSV1ProviderConsentQualificationFixture
                .hasSameObservationAuthority(ready, as: ready)
        )
        #expect(
            !IOSV1ProviderConsentQualificationFixture
                .isAuthorizationReady(for: ready)
        )
    }
}
#endif
