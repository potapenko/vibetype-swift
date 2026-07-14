import HoldTypeDomain
import Testing
import UIKit
@testable import HoldTypeIOS

@MainActor
struct IOSVoiceHomePresentationTests {
    @Test func everyControllerActionHasStableNativeCopyAndRole() {
        let actions: [IOSForegroundVoiceAction] = [
            .startStandard,
            .startTranslation,
            .startCorrection,
            .checkAgain,
            .cancelStart,
            .finishUtterance,
            .cancelUtterance,
            .cancelProcessing,
            .recoverRecording,
            .retryPending,
            .discard,
        ]
        let presentations = actions.map(IOSVoiceActionPresentation.resolve)

        #expect(presentations.map(\.title) == [
            "Start Dictation",
            "Translate",
            "Correction",
            "Check Again",
            "Cancel Start",
            "Done",
            "Cancel Utterance",
            "Cancel Processing",
            "Recover Recording",
            "Retry Transcription",
            "Discard Recording",
        ])
        #expect(
            presentations.enumerated().filter {
                $0.element.requiresConfirmation
            }.map(\.offset) == [10]
        )
        #expect(
            Set(presentations.map(\.accessibilityIdentifier)).count == 11
        )
        #expect(presentations[10].prominence == .destructive)
    }

    @Test func activePhasesRemainDistinctAndUnderstandable() {
        let cases: [(VoiceWorkPhase, VoiceAttemptStage?, String, Bool)] = [
            (.arming, nil, "Getting ready…", true),
            (.ready, nil, "Ready to dictate", false),
            (.listening, nil, "Listening", false),
            (
                .finalizing,
                .recordingFinalization,
                "Finishing local recording step…",
                true
            ),
            (.processing, .transcription, "Transcribing…", true),
            (.processing, .postProcessing, "Refining text…", true),
            (.processing, .outputDelivery, "Saving result…", true),
            (.processing, nil, "Processing…", true),
        ]

        for item in cases {
            let resolved = IOSVoiceHomePresentation.resolve(
                voicePresentation(phase: item.0, stage: item.1)
            )
            #expect(resolved.title == item.2)
            #expect(resolved.showsProgress == item.3)
        }
    }

    @Test func primaryActivityUsesListeningThenRecognitionVisuals() {
        #expect(IOSVoiceActivityPhase.resolve(.inactive) == .ready)
        #expect(IOSVoiceActivityPhase.resolve(.arming) == .ready)
        #expect(IOSVoiceActivityPhase.resolve(.ready) == .ready)
        #expect(IOSVoiceActivityPhase.resolve(.listening) == .listening)
        #expect(IOSVoiceActivityPhase.resolve(.finalizing) == .recognizing)
        #expect(IOSVoiceActivityPhase.resolve(.processing) == .recognizing)
    }

    @Test func blockedPrimaryGatesAlwaysExplainTheNextStep() {
        let gates: [IOSVoicePrimaryGate] = [
            .draftLoading,
            .draftUpdating,
            .draftEditing,
            .draftUnavailable,
            .draftFull,
            .voiceChecking,
        ]

        for gate in gates {
            let status = IOSVoiceHomePresentation.primaryGateStatus(gate)
            #expect(status != nil)
            #expect(status?.title.isEmpty == false)
            #expect(status?.detail.isEmpty == false)
        }
        #expect(
            IOSVoiceHomePresentation.primaryGateStatus(.available) == nil
        )
    }

    @Test func deniedMicrophoneRoutesToTheOwningSettingsScreen() {
        let resolved = IOSVoiceHomePresentation.resolve(
            voicePresentation(
                setup: .needsSetup(.microphoneAndPrivacy),
                failure: .microphonePermissionDenied
            )
        )

        #expect(resolved.title == "Microphone access is off")
        #expect(resolved.setupDestination == .microphoneAndPrivacy)
        #expect(resolved.detail.contains("Privacy & Permissions"))
    }

    @Test func unavailableMicrophoneRoutesToPrivacyWithAConcreteNextStep() {
        let resolved = IOSVoiceHomePresentation.resolve(
            voicePresentation(
                setup: .needsSetup(.microphoneAndPrivacy),
                failure: .microphoneUnavailable
            )
        )

        #expect(resolved.title == "Microphone isn't available")
        #expect(resolved.setupDestination == .microphoneAndPrivacy)
        #expect(resolved.detail.contains("audio input"))
    }

    @Test func unreadableCredentialRoutesToOpenAISettings() {
        let resolved = IOSVoiceHomePresentation.resolve(
            voicePresentation(
                setup: .needsSetup(.openAI),
                failure: .credentialUnavailable
            )
        )

        #expect(resolved.title == "OpenAI key needs attention")
        #expect(resolved.setupDestination == .openAI)
        #expect(resolved.detail.contains("OpenAI Settings"))
    }

    @Test func unclassifiedReadinessOffersANonDestructiveRecheck() {
        let resolved = IOSVoiceHomePresentation.resolve(
            voicePresentation(setup: .unavailable)
        )

        #expect(resolved.title == "Voice needs another check")
        #expect(resolved.detail.contains("Check Again"))
        #expect(resolved.tone == .warning)
    }

    @Test func pendingRetryShowsTheBlockingSetupRouteBeforeRetry() {
        let resolved = IOSVoiceHomePresentation.resolve(
            voicePresentation(
                setup: .needsSetup(.openAI),
                failure: .credentialUnavailable,
                recovery: .pendingRetryOrDiscard
            )
        )

        #expect(resolved.title == "OpenAI key needs attention")
        #expect(resolved.setupDestination == .openAI)
    }

    @Test func everySetupDestinationOwnsItsVisibleRecoveryCopy() {
        let destinations: [RecoveryDestination] = [
            .openAI,
            .transcription,
            .translation,
            .keyboard,
            .fullAccess,
            .microphoneAndPrivacy,
        ]

        for destination in destinations {
            let resolved = IOSVoiceHomePresentation.resolve(
                voicePresentation(setup: .needsSetup(destination))
            )
            #expect(resolved.setupDestination == destination)
            #expect(resolved.tone == .warning)
            #expect(!resolved.title.isEmpty)
            #expect(!resolved.detail.isEmpty)
        }
    }

    @Test func dormantFullAccessRecoveryCopyMatchesTheNoAccessContract() {
        let resolved = IOSVoiceHomePresentation.resolve(
            voicePresentation(setup: .needsSetup(.fullAccess))
        )

        #expect(resolved.title == "Full Access required for keyboard voice")
        #expect(
            resolved.detail
                == "Turn on Allow Full Access for keyboard-controlled dictation. Local editing and Latest insertion remain available without it."
        )
    }

    @Test func everyRecoveryRemainsVisibleAndNeverLooksReady() {
        let recoveries: [IOSForegroundVoiceRecovery] = [
            .captureRecoverOrDiscard,
            .captureDiscardOnly,
            .pendingRetryOrDiscard,
            .blocked,
        ]

        for recovery in recoveries {
            let resolved = IOSVoiceHomePresentation.resolve(
                voicePresentation(recovery: recovery)
            )
            #expect(resolved.title != "Ready to dictate")
            #expect(resolved.tone == .warning || resolved.tone == .failure)
        }
    }

    @Test func everyFailureAndOutcomeHasNonEmptyFiniteCopy() {
        let failures: [IOSForegroundVoiceFailure] = [
            .operationFailed,
            .localRecovery,
            .unavailable,
            .credentialUnavailable,
            .microphonePermissionDenied,
            .microphoneUnavailable,
            .microphonePermissionTimedOut,
            .tooShort,
            .maximumDuration,
        ]
        for failure in failures {
            let resolved = IOSVoiceHomePresentation.resolve(
                voicePresentation(failure: failure)
            )
            #expect(!resolved.title.isEmpty)
            #expect(!resolved.detail.isEmpty)
        }

        let outcomes: [VoiceAttemptOutcome] = [
            .resultReady,
            .recoverableFailure,
            .interrupted,
            .expired,
        ]
        for outcome in outcomes {
            let resolved = IOSVoiceHomePresentation.resolve(
                voicePresentation(outcome: outcome)
            )
            #expect(!resolved.title.isEmpty)
            #expect(!resolved.detail.isEmpty)
        }

        let unavailableSession = IOSVoiceHomePresentation.resolve(
            voicePresentation(outcome: .expired)
        )
        #expect(unavailableSession.title == "Voice session unavailable")
        #expect(unavailableSession.tone == .warning)
        #expect(!unavailableSession.detail.contains("Latest Result"))
    }

    @Test func activePhaseThenBlockingSetupOwnTheVisibleNextStep() {
        let active = IOSVoiceHomePresentation.resolve(
            voicePresentation(
                phase: .listening,
                outcome: .recoverableFailure,
                setup: .needsSetup(.openAI),
                failure: .operationFailed,
                recovery: .pendingRetryOrDiscard
            )
        )
        #expect(active.title == "Listening")

        let recovery = IOSVoiceHomePresentation.resolve(
            voicePresentation(
                setup: .needsSetup(.openAI),
                failure: .operationFailed,
                recovery: .pendingRetryOrDiscard
            )
        )
        #expect(recovery.title == "OpenAI setup required")
        #expect(recovery.setupDestination == .openAI)
    }

    @Test func historySaveWarningPreservesReadyResultCopy() {
        let resolved = IOSVoiceHomePresentation.resolve(
            voicePresentation(
                outcome: .resultReady,
                warning: .historySaveFailed
            )
        )

        #expect(resolved.title == "Result ready")
        #expect(
            resolved.detail
                == "Latest Result is ready, but HoldType couldn't save it to History."
        )
        #expect(
            resolved.systemImage ==
                "exclamationmark.arrow.triangle.2.circlepath"
        )
        #expect(resolved.tone == .warning)
        #expect(!resolved.showsProgress)
        #expect(resolved.setupDestination == nil)
    }

    @Test func localCleanupWarningKeepsTheAcceptedResultSafe() {
        let resolved = IOSVoiceHomePresentation.resolve(
            voicePresentation(
                outcome: .resultReady,
                warning: .localCleanupPending
            )
        )

        #expect(resolved.title == "Result ready")
        #expect(
            resolved.detail
                == "Latest Result is safe; HoldType will finish local cleanup automatically."
        )
        #expect(resolved.tone == .warning)
    }

    @Test func everyReferencedSystemImageExistsOnTheDeploymentRuntime() {
        let actions: [IOSForegroundVoiceAction] = [
            .startStandard,
            .startTranslation,
            .startCorrection,
            .checkAgain,
            .cancelStart,
            .finishUtterance,
            .cancelUtterance,
            .cancelProcessing,
            .recoverRecording,
            .retryPending,
            .discard,
        ]
        let statuses = voiceStatusFixtures().map {
            IOSVoiceHomePresentation.resolve($0)
        }
        let names = actions.map {
            IOSVoiceActionPresentation.resolve($0).systemImage
        } + statuses.map(\.systemImage)

        for name in Set(names) {
            #expect(UIImage(systemName: name) != nil)
        }
    }
}

private func voicePresentation(
    phase: VoiceWorkPhase = .inactive,
    stage: VoiceAttemptStage? = nil,
    outcome: VoiceAttemptOutcome? = nil,
    setup: IOSForegroundVoiceSetup = .ready,
    failure: IOSForegroundVoiceFailure? = nil,
    recovery: IOSForegroundVoiceRecovery = .none,
    warning: IOSForegroundVoiceWarning? = nil
) -> IOSForegroundVoicePresentation {
    IOSForegroundVoicePresentation(
        phase: phase,
        stage: stage,
        outcome: outcome,
        setup: setup,
        failure: failure,
        recovery: recovery,
        availableActions: [],
        latestAvailability: .absent,
        warning: warning
    )
}

private func voiceStatusFixtures() -> [IOSForegroundVoicePresentation] {
    var values: [IOSForegroundVoicePresentation] = [
        voicePresentation(setup: .unknown),
        voicePresentation(setup: .unavailable),
        voicePresentation(),
    ]
    values += [
        VoiceWorkPhase.arming,
        .ready,
        .listening,
        .finalizing,
        .processing,
    ].map { voicePresentation(phase: $0) }
    values += [
        VoiceAttemptStage.recordingFinalization,
        .transcription,
        .postProcessing,
        .outputDelivery,
    ].map { voicePresentation(phase: .processing, stage: $0) }
    values += [
        RecoveryDestination.openAI,
        .transcription,
        .translation,
        .keyboard,
        .fullAccess,
        .microphoneAndPrivacy,
    ].map { voicePresentation(setup: .needsSetup($0)) }
    values += [
        IOSForegroundVoiceRecovery.captureRecoverOrDiscard,
        .captureDiscardOnly,
        .pendingRetryOrDiscard,
        .blocked,
    ].map { voicePresentation(recovery: $0) }
    values += [
        IOSForegroundVoiceFailure.operationFailed,
        .localRecovery,
        .unavailable,
        .credentialUnavailable,
        .microphonePermissionDenied,
        .microphoneUnavailable,
        .microphonePermissionTimedOut,
        .tooShort,
        .maximumDuration,
    ].map { voicePresentation(failure: $0) }
    values += [
        VoiceAttemptOutcome.resultReady,
        .recoverableFailure,
        .interrupted,
        .expired,
    ].map { voicePresentation(outcome: $0) }
    values.append(
        voicePresentation(
            outcome: .resultReady,
            warning: .historySaveFailed
        )
    )
    return values
}
