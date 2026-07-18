import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
import HoldTypePersistence
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
        #expect(presentations[1].systemImage == "character.bubble")
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

    @Test func draftTextActionsExposeProviderOnlyProcessingCopy() {
        let translation = IOSVoiceDraftTextActionPresentation.resolve(
            .translate
        )
        let correction = IOSVoiceDraftTextActionPresentation.resolve(
            .correct
        )

        #expect(translation.title == "Translate")
        #expect(translation.processingStatus.title == "Translating…")
        #expect(translation.processingStatus.showsProgress)
        #expect(correction.title == "Correction")
        #expect(correction.processingStatus.title == "Improving…")
        #expect(correction.processingStatus.tone == .active)
        #expect(
            translation.accessibilityIdentifier
                != correction.accessibilityIdentifier
        )
    }

    @Test func primaryActivityUsesListeningThenRecognitionVisuals() {
        #expect(IOSVoiceActivityPhase.resolve(.inactive) == .ready)
        #expect(IOSVoiceActivityPhase.resolve(.arming) == .ready)
        #expect(IOSVoiceActivityPhase.resolve(.ready) == .ready)
        #expect(IOSVoiceActivityPhase.resolve(.listening) == .listening)
        #expect(IOSVoiceActivityPhase.resolve(.finalizing) == .recognizing)
        #expect(IOSVoiceActivityPhase.resolve(.processing) == .recognizing)
    }

    @Test func cancellationActionsStayOutOfTheVisibleStatusLayout() {
        let cancellationActions: [IOSForegroundVoiceAction] = [
            .cancelStart,
            .cancelUtterance,
            .cancelProcessing,
        ]
        let visibleRecoveryActions: [IOSForegroundVoiceAction] = [
            .checkAgain,
            .recoverRecording,
            .retryPending,
            .discard,
        ]

        for action in cancellationActions {
            #expect(IOSVoiceHomeActionPlacement.isCancellation(action))
            #expect(
                !IOSVoiceHomeActionPlacement.isVisibleStatusAction(action)
            )
        }
        for action in visibleRecoveryActions {
            #expect(!IOSVoiceHomeActionPlacement.isCancellation(action))
            #expect(
                IOSVoiceHomeActionPlacement.isVisibleStatusAction(action)
            )
        }
    }

    @Test func clearDraftAppearsOnlyForTextAndDisablesDuringVoiceWork() {
        let empty = IOSVoiceDraftClearPresentation.resolve(
            visibleText: "",
            voicePhase: .inactive,
            draftIsBusy: false
        )
        #expect(!empty.isVisible)
        #expect(!empty.isEnabled)

        let available = IOSVoiceDraftClearPresentation.resolve(
            visibleText: "Visible Draft",
            voicePhase: .inactive,
            draftIsBusy: false
        )
        #expect(available.isVisible)
        #expect(available.isEnabled)

        let ready = IOSVoiceDraftClearPresentation.resolve(
            visibleText: "Visible Draft",
            voicePhase: .ready,
            draftIsBusy: false
        )
        #expect(ready.isVisible)
        #expect(ready.isEnabled)

        for phase in [
            VoiceWorkPhase.arming,
            .listening,
            .finalizing,
            .processing,
        ] {
            let active = IOSVoiceDraftClearPresentation.resolve(
                visibleText: "Visible Draft",
                voicePhase: phase,
                draftIsBusy: false
            )
            #expect(active.isVisible)
            #expect(!active.isEnabled)
        }

        let updating = IOSVoiceDraftClearPresentation.resolve(
            visibleText: "Visible Draft",
            voicePhase: .inactive,
            draftIsBusy: true
        )
        #expect(updating.isVisible)
        #expect(!updating.isEnabled)
    }

    @Test func replaceHidesConfirmedDraftWhileAwaitingNewText() throws {
        let phases: [(VoiceWorkPhase, VoiceAttemptStage?)] = [
            (.arming, nil),
            (.listening, nil),
            (.finalizing, .recordingFinalization),
            (.processing, .transcription),
            (.processing, .postProcessing),
            (.processing, .outputDelivery),
        ]

        for (phase, stage) in phases {
            let resolved = try #require(
                IOSVoiceDraftPendingResultPresentation.resolve(
                    voicePresentation(
                        phase: phase,
                        stage: stage,
                        activeDraftInsertionMode: .replace
                    )
                )
            )
            #expect(resolved.hidesConfirmedText)
            #expect(!resolved.title.isEmpty)
            #expect(resolved.detail.contains("appear here"))
            #expect(!resolved.accessibilityAnnouncement.isEmpty)
        }
    }

    @Test func appendKeepsConfirmedDraftVisibleAndPromisesTextBelow() throws {
        let listening = try #require(
            IOSVoiceDraftPendingResultPresentation.resolve(
                voicePresentation(
                    phase: .listening,
                    activeDraftInsertionMode: .append
                )
            )
        )
        #expect(!listening.hidesConfirmedText)
        #expect(listening.title == "Listening")
        #expect(
            listening.detail
                == "New text will be added below when you finish."
        )

        let processing = try #require(
            IOSVoiceDraftPendingResultPresentation.resolve(
                voicePresentation(
                    phase: .processing,
                    stage: .transcription,
                    activeDraftInsertionMode: .append
                )
            )
        )
        #expect(processing.title == "Transcribing…")
        #expect(processing.detail == "Your result will be added below.")
    }

    @Test func terminalVoiceStateRestoresNormalDraftPresentation() {
        for outcome in [
            VoiceAttemptOutcome.resultReady,
            .recoverableFailure,
            .interrupted,
        ] {
            #expect(
                IOSVoiceDraftPendingResultPresentation.resolve(
                    voicePresentation(
                        outcome: outcome,
                        failure: outcome == .resultReady
                            ? nil
                            : .operationFailed
                    )
                ) == nil
            )
        }
    }

    @Test func draftActionFeedbackIsAccessibilityOnly() {
        #expect(
            IOSVoiceDraftAccessibilityFeedback.copyAnnouncement
                == "Current Draft copied"
        )
        #expect(
            IOSVoiceDraftAccessibilityFeedback.clearAnnouncement
                == "Draft cleared. Undo is available."
        )
    }

    @Test func activityCenterDependsOnlyOnTheVoiceStageBounds() {
        let phoneStage = CGSize(width: 398, height: 426)
        let compactStage = CGSize(width: 320, height: 300)

        #expect(
            IOSVoiceStagePlacement.activityCenter(in: phoneStage)
                == CGPoint(x: 199, y: 213)
        )
        #expect(
            IOSVoiceStagePlacement.activityCenter(in: compactStage)
                == CGPoint(x: 160, y: 150)
        )
        #expect(
            IOSVoiceStagePlacement.cancellationCenter(in: phoneStage)
                == CGPoint(x: 277, y: 291)
        )
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
            .draftClearFailed,
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
        ]
        for outcome in outcomes {
            let resolved = IOSVoiceHomePresentation.resolve(
                voicePresentation(outcome: outcome)
            )
            #expect(!resolved.title.isEmpty)
            #expect(!resolved.detail.isEmpty)
        }

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
        } + [
            IOSVoiceDraftTextActionPresentation.resolve(.translate)
                .systemImage,
            IOSVoiceDraftTextActionPresentation.resolve(.correct)
                .systemImage,
        ] + statuses.map(\.systemImage) + [
            "xmark.circle",
        ]

        for name in Set(names) {
            #expect(UIImage(systemName: name) != nil)
        }
    }
}

private func voicePresentation(
    phase: VoiceWorkPhase = .inactive,
    stage: VoiceAttemptStage? = nil,
    outcome: VoiceAttemptOutcome? = nil,
    activeDraftInsertionMode: IOSVoiceDraftInsertionMode? = nil,
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
        activeDraftInsertionMode: activeDraftInsertionMode,
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
        .draftClearFailed,
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
    ].map { voicePresentation(outcome: $0) }
    values.append(
        voicePresentation(
            outcome: .resultReady,
            warning: .historySaveFailed
        )
    )
    return values
}
