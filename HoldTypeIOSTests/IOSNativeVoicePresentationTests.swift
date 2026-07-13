import HoldTypePersistence
import Testing
import UIKit
@testable import HoldTypeIOS

@MainActor
struct IOSNativeVoicePresentationTests {
    @Test func latestResultStatesHaveFiniteNativePresentationAndSymbols() {
        let statuses: [IOSForegroundVoiceLatestResultStatus] = [
            .notLoaded,
            .absent,
            .ready,
            .priorWhileSaving,
            .savingWithoutPrior,
            .expired,
            .clockRollbackAmbiguous,
            .clearing,
            .cleanupPending,
            .unavailable,
        ]

        for status in statuses {
            let resolved = IOSVoiceLatestStatusPresentation.resolve(
                IOSForegroundVoiceLatestResultPresentation(
                    status: status,
                    text: status == .ready ? "result" : nil,
                    notice: nil
                )
            )
            #expect(!resolved.title.isEmpty)
            #expect(!resolved.detail.isEmpty)
            #expect(UIImage(systemName: resolved.systemImage) != nil)
        }

        for notice in [
            IOSForegroundVoiceLatestResultNotice.loadFailed,
            .clearFailed,
            .clearStateUnknown,
            .resultChanged,
        ] {
            let resolved = IOSVoiceLatestStatusPresentation.resolve(
                IOSForegroundVoiceLatestResultPresentation(
                    status: .unavailable,
                    text: nil,
                    notice: notice
                )
            )
            #expect(!resolved.detail.isEmpty)
        }
    }

    @Test func microphoneStatesRemainPassiveAndDistinct() {
        let statuses: [IOSMicrophonePermissionStatus] = [
            .undetermined,
            .denied,
            .granted,
            .unavailable,
        ]
        let values = statuses.map(IOSMicrophonePrivacyPresentation.resolve)

        #expect(values.map(\.title) == [
            "Not Requested",
            "Access Denied",
            "Access Granted",
            "Status Unavailable",
        ])
        for value in values {
            #expect(!value.detail.isEmpty)
            #expect(UIImage(systemName: value.systemImage) != nil)
        }
    }

    @Test func consentStatesExposeOnlyTheirAdmittedAction() {
        let cases: [
            (
                IOSProviderConsentStatus,
                Bool,
                IOSProviderConsentPrivacyAction?
            )
        ] = [
            (.notReviewed, false, .acceptCurrentDisclosure),
            (.acceptedCurrentDisclosure, false, .withdraw),
            (.acceptedCurrentDisclosure, true, .acceptCurrentDisclosure),
            (.reviewRequired, false, .acceptCurrentDisclosure),
            (.withdrawn, false, .acceptCurrentDisclosure),
            (.localDataUnavailable, false, nil),
            (.mutationNotSaved, false, nil),
        ]

        for item in cases {
            let resolved = IOSConsentPrivacyPresentation.resolve(
                IOSProviderConsentPrivacySnapshot(
                    status: item.0,
                    decisionAt: nil,
                    canResetUnreadableData: false,
                    requiresExplicitAcceptance: item.1
                )
            )
            #expect(resolved.action == item.2)
            #expect(!resolved.title.isEmpty)
            #expect(!resolved.detail.isEmpty)
            #expect(UIImage(systemName: resolved.systemImage) != nil)
        }
    }

    @Test func accessibilityAnnouncementCombinesOnlyPresentationCopy() {
        #expect(
            IOSAccessibilityAnnouncement.message(
                title: "Transcribing",
                detail: "Sending the retained recording to OpenAI."
            )
                == "Transcribing. Sending the retained recording to OpenAI."
        )
        #expect(
            IOSAccessibilityAnnouncement.message(
                title: "Latest Result copied",
                detail: ""
            ) == "Latest Result copied"
        )
    }
}
