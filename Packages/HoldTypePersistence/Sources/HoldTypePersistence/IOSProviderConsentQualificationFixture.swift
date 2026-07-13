#if DEBUG
import Foundation

/// DEBUG-only, content-free consent observations for rendered-state
/// qualification. Release builds cannot import or construct these fixtures.
@_spi(HoldTypeIOSCore)
public enum IOSProviderConsentQualificationFixture {
    private static let ownerIdentity = IOSProviderConsentOwnerIdentity()
    private static let gateFence = IOSProviderConsentObservationFence()

    public static func notReviewedObservation()
        -> IOSProviderConsentObservation {
        IOSProviderConsentObservation(
            status: .notReviewed,
            decisionAt: nil,
            canResetUnreadableData: false,
            ownerIdentity: ownerIdentity,
            source: .absent,
            gateFence: gateFence
        )
    }

    public static func localDataUnavailableObservation()
        -> IOSProviderConsentObservation {
        IOSProviderConsentObservation(
            status: .localDataUnavailable,
            decisionAt: nil,
            canResetUnreadableData: false,
            ownerIdentity: ownerIdentity,
            source: .unavailable,
            gateFence: gateFence
        )
    }

    public static func acceptedObservation()
        -> IOSProviderConsentObservation {
        let decisionAt = Date(timeIntervalSince1970: 1_767_225_600)
        let record = IOSProviderConsentRecord(
            epochID: UUID(),
            revision: 1,
            disclosureVersion: IOSProviderConsentCoordinator
                .currentDisclosureVersion,
            state: .accepted,
            decisionAt: decisionAt
        )
        return IOSProviderConsentObservation(
            status: .acceptedCurrentDisclosure,
            decisionAt: decisionAt,
            canResetUnreadableData: false,
            ownerIdentity: ownerIdentity,
            source: .snapshot(
                IOSProviderConsentJournalSnapshot(
                    content: .readable(record),
                    testingRevision: 1
                )
            ),
            gateFence: gateFence
        )
    }

    public static func resettableUnreadableObservation()
        -> IOSProviderConsentObservation {
        IOSProviderConsentObservation(
            status: .localDataUnavailable,
            decisionAt: nil,
            canResetUnreadableData: true,
            ownerIdentity: ownerIdentity,
            source: .snapshot(
                IOSProviderConsentJournalSnapshot(
                    content: .unreadable,
                    testingRevision: 2
                )
            ),
            gateFence: gateFence
        )
    }

    public static func isAuthorizationReady(
        for observation: IOSProviderConsentObservation
    ) -> Bool {
        observation.status == .acceptedCurrentDisclosure
    }

    public static func hasSameObservationAuthority(
        _ candidate: IOSProviderConsentObservation,
        as current: IOSProviderConsentObservation
    ) -> Bool {
        guard let candidateFence = candidate.gateFence,
              let currentFence = current.gateFence else {
            return false
        }
        return candidate.ownerIdentity == current.ownerIdentity
            && candidate.source == current.source
            && candidateFence == currentFence
    }
}
#endif
