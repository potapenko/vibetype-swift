import HoldTypePersistence
import Testing
import UIKit
@testable import HoldTypeIOS

@MainActor
struct IOSNativeVoicePresentationTests {
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
        #expect(values.map(\.detail) == [
            "Asked the first time you start dictation.",
            "Allow microphone access in System Settings before recording.",
            "Used only while you record.",
            "HoldType couldn’t read microphone access.",
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
            (.acceptedCurrentDisclosure, false, nil),
            (.acceptedCurrentDisclosure, true, .acceptCurrentDisclosure),
            (.reviewRequired, false, .acceptCurrentDisclosure),
            (.withdrawn, false, .acceptCurrentDisclosure),
            (.localDataUnavailable, false, nil),
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
            #expect(!resolved.detail.contains("provider authority"))
            #expect(!resolved.detail.contains("durable"))
        }
    }

    @Test func privacyAttentionClearsOnlyAfterCurrentConsentIsAuthorized() {
        let target = IOSSettingsAttentionTarget(.privacyReview)

        for status in [
            IOSV1ProviderConsentStatus.notReviewed,
            .reviewRequired,
            .withdrawn,
            .localDataUnavailable,
        ] {
            #expect(
                IOSPrivacySettingsAttentionResolver.activeTarget(
                    target,
                    privacyState: privacyState(status: status),
                    microphoneStatus: .granted
                ) == target
            )
        }

        #expect(
            IOSPrivacySettingsAttentionResolver.activeTarget(
                target,
                privacyState: privacyState(
                    status: .acceptedCurrentDisclosure,
                    requiresExplicitAcceptance: true
                ),
                microphoneStatus: .granted
            ) == target
        )
        #expect(
            IOSPrivacySettingsAttentionResolver.activeTarget(
                target,
                privacyState: privacyState(
                    status: .acceptedCurrentDisclosure
                ),
                microphoneStatus: .granted
            ) == nil
        )
    }

    @Test func microphoneAttentionClearsOnlyAfterAccessIsGranted() {
        let target = IOSSettingsAttentionTarget(.microphonePermission)

        for status in [
            IOSMicrophonePermissionStatus.undetermined,
            .denied,
            .unavailable,
        ] {
            #expect(
                IOSPrivacySettingsAttentionResolver.activeTarget(
                    target,
                    privacyState: .notLoaded,
                    microphoneStatus: status
                ) == target
            )
        }

        #expect(
            IOSPrivacySettingsAttentionResolver.activeTarget(
                target,
                privacyState: .notLoaded,
                microphoneStatus: .granted
            ) == nil
        )
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

    private func privacyState(
        status: IOSV1ProviderConsentStatus,
        requiresExplicitAcceptance: Bool = false
    ) -> IOSProviderConsentPrivacyState {
        .ready(
            IOSProviderConsentPrivacySnapshot(
                status: status,
                decisionAt: nil,
                canResetUnreadableData: false,
                requiresExplicitAcceptance: requiresExplicitAcceptance
            )
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
        #expect(
            IOSAccessibilityAnnouncementCandidate.preferred(
                current: status,
                incoming: content
            ) == content
        )
        #expect(
            IOSAccessibilityAnnouncementCandidate.preferred(
                current: content,
                incoming: status
            ) == content
        )
    }
}
