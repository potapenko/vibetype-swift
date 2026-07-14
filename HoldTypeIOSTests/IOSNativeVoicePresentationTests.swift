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
            .clearing,
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

        let failedEmptyProjection = IOSVoiceLatestStatusPresentation.resolve(
            IOSForegroundVoiceLatestResultPresentation(
                status: .absent,
                text: nil,
                notice: nil,
                keyboardProjectionUpdateFailed: true
            )
        )
        #expect(
            failedEmptyProjection.detail
                == "The keyboard copy couldn't be refreshed; an older item may remain until it expires."
        )
        #expect(failedEmptyProjection.tone == .failure)
        #expect(
            IOSVoiceLatestStatusPresentation.sectionIsVisible(
                for: IOSForegroundVoiceLatestResultPresentation(
                    status: .absent,
                    text: nil,
                    notice: nil,
                    keyboardProjectionUpdateFailed: true
                )
            )
        )
        #expect(
            !IOSVoiceLatestStatusPresentation.sectionIsVisible(
                for: IOSForegroundVoiceLatestResultPresentation(
                    status: .absent,
                    text: nil,
                    notice: nil
                )
            )
        )
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
                IOSV1ProviderConsentStatus,
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

    @Test func accessibilityAnnouncementSuppressesIdenticalTransitions() {
        #expect(
            IOSAccessibilityAnnouncement.transitionMessage(
                oldTitle: "Listening",
                oldDetail: "Tap Stop when you finish.",
                newTitle: "Listening",
                newDetail: "Tap Stop when you finish."
            ) == nil
        )
    }

    @Test func accessibilityAnnouncementDescribesChangedTransitions() {
        #expect(
            IOSAccessibilityAnnouncement.transitionMessage(
                oldTitle: "Listening",
                oldDetail: "Tap Stop when you finish.",
                newTitle: "Transcribing",
                newDetail: "Sending the retained recording to OpenAI."
            )
                == "Transcribing. Sending the retained recording to OpenAI."
        )
    }

    @Test func elapsedTimeUsesSpokenUnitsForAccessibility() {
        #expect(
            IOSAccessibilityAnnouncement.spokenElapsedTime(totalSeconds: -1)
                == "0 seconds"
        )
        #expect(
            IOSAccessibilityAnnouncement.spokenElapsedTime(totalSeconds: 1)
                == "1 second"
        )
        #expect(
            IOSAccessibilityAnnouncement.spokenElapsedTime(totalSeconds: 65)
                == "1 minute, 5 seconds"
        )
        #expect(
            IOSAccessibilityAnnouncement.spokenElapsedTime(totalSeconds: 120)
                == "2 minutes"
        )
    }

    @Test func accessibilityAnnouncementCoalescingPrefersContent() {
        let status = IOSAccessibilityAnnouncementCandidate(
            message: "Ready to dictate",
            priority: .status
        )
        let content = IOSAccessibilityAnnouncementCandidate(
            message: "Latest Result available",
            priority: .content
        )
        let passive = IOSAccessibilityAnnouncementCandidate(
            message: "No Latest Result",
            priority: .passive
        )

        #expect(
            IOSAccessibilityAnnouncementCandidate.preferred(
                current: status,
                incoming: content
            ) == content
        )
        #expect(
            IOSAccessibilityAnnouncementCandidate.preferred(
                current: content,
                incoming: passive
            ) == content
        )
    }
}
