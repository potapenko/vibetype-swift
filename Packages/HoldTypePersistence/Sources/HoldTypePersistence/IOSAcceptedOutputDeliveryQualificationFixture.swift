#if DEBUG
import Foundation
import HoldTypeDomain

/// A DEBUG-only constructor for rendered-state qualification. Production code
/// cannot import or construct this fixture in Release builds.
@_spi(HoldTypeIOSCore)
public enum IOSAcceptedOutputDeliveryQualificationFixture {
    public static func activeRecord(
        text: String
    ) -> IOSAcceptedOutputDeliveryRecord {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let expiresAt = Date(
            timeIntervalSince1970:
                createdAt.timeIntervalSince1970
                    + TimeInterval(
                        IOSAcceptedOutputDeliveryValidation
                            .lifetimeMilliseconds
                    ) / 1_000
        )
        do {
            return try IOSAcceptedOutputDeliveryRecord(
                revision: 1,
                deliveryID: UUID(),
                sessionID: UUID(),
                attemptID: UUID(),
                transcriptID: UUID(),
                acceptedText: text,
                outputIntent: .standard,
                createdAt: createdAt,
                updatedAt: createdAt,
                expiresAt: expiresAt,
                deliveryState: .pending,
                automaticInsertionPreferenceEnabled: false,
                keepLatestResult: true,
                publicationGeneration: 0,
                historyWrite: nil
            )
        } catch {
            fatalError(
                "Invalid accepted-output qualification fixture: \(error)"
            )
        }
    }
}
#endif
