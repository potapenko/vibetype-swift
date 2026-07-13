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
            .cancelStart,
            .finishUtterance,
            .cancelUtterance,
            .cancelProcessing,
            .recoverRecording,
            .retryPending,
            .discard,
            .retrySavingResult,
            .retryLocalCheckpoint,
        ]
        let presentations = actions.map(IOSVoiceActionPresentation.resolve)

        #expect(presentations.map(\.title) == [
            "Start Dictation",
            "Translate",
            "Cancel Start",
            "Done",
            "Cancel Utterance",
            "Cancel Processing",
            "Recover Recording",
            "Retry Transcription",
            "Discard Recording",
            "Retry Saving Result",
            "Retry Local Checkpoint",
        ])
        #expect(
            presentations.enumerated().filter {
                $0.element.requiresConfirmation
            }.map(\.offset) == [8]
        )
        #expect(
            Set(presentations.map(\.accessibilityIdentifier)).count == 11
        )
        #expect(presentations[8].prominence == .destructive)
    }

    @Test func activePhasesRemainDistinctAndUnderstandable() {
        let cases: [(VoiceWorkPhase, VoiceAttemptStage?, String, Bool)] = [
            (.arming, nil, "Getting ready…", true),
            (.ready, nil, "Voice unavailable", false),
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

    @Test func everyRecoveryRemainsVisibleAndNeverLooksReady() {
        let recoveries: [IOSForegroundVoiceRecovery] = [
            .captureRecoverOrDiscard,
            .captureRecoverOnly,
            .captureDiscardOnly,
            .pendingRetryOrDiscard,
            .savingResult,
            .localCheckpoint(.transcription),
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

    @Test func activePhaseAndRecoveryDominateStaleSecondaryAxes() {
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
        #expect(recovery.title == "Recording ready to retry")
        #expect(recovery.setupDestination == nil)
    }

    @Test func everyReferencedSystemImageExistsOnTheDeploymentRuntime() {
        let actions: [IOSForegroundVoiceAction] = [
            .startStandard,
            .startTranslation,
            .cancelStart,
            .finishUtterance,
            .cancelUtterance,
            .cancelProcessing,
            .recoverRecording,
            .retryPending,
            .discard,
            .retrySavingResult,
            .retryLocalCheckpoint,
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
    recovery: IOSForegroundVoiceRecovery = .none
) -> IOSForegroundVoicePresentation {
    IOSForegroundVoicePresentation(
        phase: phase,
        stage: stage,
        outcome: outcome,
        setup: setup,
        failure: failure,
        recovery: recovery,
        availableActions: [],
        latestAvailability: .absent
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
        .captureRecoverOnly,
        .captureDiscardOnly,
        .pendingRetryOrDiscard,
        .savingResult,
        .localCheckpoint(.transcription),
        .blocked,
    ].map { voicePresentation(recovery: $0) }
    values += [
        IOSForegroundVoiceFailure.operationFailed,
        .localRecovery,
        .unavailable,
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
    return values
}
