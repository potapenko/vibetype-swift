#if DEBUG
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

    @Test func privacyQualificationObservationsAreDeterministicAndContentFree() {
        let ready = IOSProviderConsentQualificationFixture
            .notReviewedObservation()
        let failure = IOSProviderConsentQualificationFixture
            .localDataUnavailableObservation()
        let accepted = IOSProviderConsentQualificationFixture
            .acceptedObservation()
        let unreadable = IOSProviderConsentQualificationFixture
            .resettableUnreadableObservation()

        #expect(ready.status == .notReviewed)
        #expect(ready.decisionAt == nil)
        #expect(!ready.canResetUnreadableData)
        #expect(failure.status == .localDataUnavailable)
        #expect(accepted.status == .acceptedCurrentDisclosure)
        #expect(
            IOSProviderConsentQualificationFixture
                .isAuthorizationReady(for: accepted)
        )
        #expect(unreadable.status == .localDataUnavailable)
        #expect(unreadable.canResetUnreadableData)
        #expect(
            IOSProviderConsentQualificationFixture
                .hasSameObservationAuthority(ready, as: ready)
        )
        #expect(
            !IOSProviderConsentQualificationFixture
                .isAuthorizationReady(for: ready)
        )
    }
}
#endif
