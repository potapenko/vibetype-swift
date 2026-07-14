import HoldTypeDomain

enum IOSVoiceStatusTone: Equatable, Sendable {
    case neutral
    case active
    case success
    case warning
    case failure
}

struct IOSVoiceStatusPresentation: Equatable, Sendable {
    let title: String
    let detail: String
    let systemImage: String
    let tone: IOSVoiceStatusTone
    let showsProgress: Bool
    let setupDestination: RecoveryDestination?
}

enum IOSVoicePrimaryGate: Equatable, Sendable {
    case available
    case draftLoading
    case draftUpdating
    case draftEditing
    case draftUnavailable
    case draftFull
    case voiceChecking
}

enum IOSVoiceActionProminence: Equatable, Sendable {
    case primary
    case secondary
    case destructive
}

struct IOSVoiceActionPresentation: Equatable, Sendable {
    let title: String
    let systemImage: String
    let prominence: IOSVoiceActionProminence
    let requiresConfirmation: Bool
    let accessibilityIdentifier: String

    static func resolve(
        _ action: IOSForegroundVoiceAction
    ) -> IOSVoiceActionPresentation {
        switch action {
        case .startStandard:
            makeAction(
                action,
                title: "Start Dictation",
                image: "mic.fill",
                prominence: .primary
            )
        case .startTranslation:
            makeAction(
                action,
                title: "Translate",
                image: "character.book.closed",
                prominence: .secondary
            )
        case .startCorrection:
            makeAction(
                action,
                title: "Correction",
                image: "wand.and.stars",
                prominence: .secondary
            )
        case .cancelStart:
            makeAction(
                action,
                title: "Cancel Start",
                image: "xmark",
                prominence: .secondary
            )
        case .finishUtterance:
            makeAction(
                action,
                title: "Done",
                image: "checkmark",
                prominence: .primary
            )
        case .cancelUtterance:
            makeAction(
                action,
                title: "Cancel Utterance",
                image: "xmark",
                prominence: .secondary
            )
        case .cancelProcessing:
            makeAction(
                action,
                title: "Cancel Processing",
                image: "xmark",
                prominence: .secondary
            )
        case .recoverRecording:
            makeAction(
                action,
                title: "Recover Recording",
                image: "arrow.clockwise",
                prominence: .primary
            )
        case .retryPending:
            makeAction(
                action,
                title: "Retry Transcription",
                image: "arrow.clockwise",
                prominence: .primary
            )
        case .discard:
            makeAction(
                action,
                title: "Discard Recording",
                image: "trash",
                prominence: .destructive,
                requiresConfirmation: true
            )
        }
    }

    private static func makeAction(
        _ action: IOSForegroundVoiceAction,
        title: String,
        image: String,
        prominence: IOSVoiceActionProminence,
        requiresConfirmation: Bool = false
    ) -> IOSVoiceActionPresentation {
        IOSVoiceActionPresentation(
            title: title,
            systemImage: image,
            prominence: prominence,
            requiresConfirmation: requiresConfirmation,
            accessibilityIdentifier:
                "ios.voice.action.\(accessibilityName(for: action))"
        )
    }

    private static func accessibilityName(
        for action: IOSForegroundVoiceAction
    ) -> String {
        switch action {
        case .startStandard: "start-standard"
        case .startTranslation: "start-translation"
        case .startCorrection: "start-correction"
        case .cancelStart: "cancel-start"
        case .finishUtterance: "finish-utterance"
        case .cancelUtterance: "cancel-utterance"
        case .cancelProcessing: "cancel-processing"
        case .recoverRecording: "recover-recording"
        case .retryPending: "retry-pending"
        case .discard: "discard"
        }
    }
}

enum IOSVoiceHomePresentation {
    static func resolve(
        _ presentation: IOSForegroundVoicePresentation
    ) -> IOSVoiceStatusPresentation {
        switch presentation.phase {
        case .inactive:
            resolveInactive(presentation)
        case .arming:
            status(
                "Getting ready…",
                detail: "Checking setup and microphone access.",
                image: "mic.badge.plus",
                tone: .active,
                showsProgress: true
            )
        case .ready:
            status(
                "Voice unavailable",
                detail: "This Voice state is not available in one-shot mode.",
                image: "exclamationmark.triangle",
                tone: .warning
            )
        case .listening:
            status(
                "Listening",
                detail: "Tap Done when you finish speaking.",
                image: "waveform",
                tone: .active
            )
        case .finalizing:
            status(
                "Finishing local recording step…",
                detail: "HoldType is updating the protected local recording.",
                image: "waveform",
                tone: .active,
                showsProgress: true
            )
        case .processing:
            resolveProcessing(stage: presentation.stage)
        }
    }

    private static func resolveInactive(
        _ presentation: IOSForegroundVoicePresentation
    ) -> IOSVoiceStatusPresentation {
        if presentation.recovery != .none {
            return recoveryStatus(
                presentation.recovery,
                outcome: presentation.outcome
            )
        }
        switch presentation.setup {
        case .unknown:
            return status(
                "Checking Voice…",
                detail: "Reconciling protected local work.",
                image: "mic",
                tone: .neutral,
                showsProgress: true
            )
        case .unavailable:
            return status(
                "Voice unavailable",
                detail: "Voice setup could not be read safely.",
                image: "exclamationmark.triangle",
                tone: .failure
            )
        case .needsSetup(let destination):
            return setupStatus(
                destination,
                failure: presentation.failure
            )
        case .ready:
            break
        }

        if let failure = presentation.failure {
            return failureStatus(failure)
        }
        if let warning = presentation.warning {
            return warningStatus(warning)
        }
        if let outcome = presentation.outcome {
            return outcomeStatus(outcome)
        }
        return status(
            "Ready to dictate",
            detail: "Record in HoldType and keep the result under your control.",
            image: "mic.fill",
            tone: .neutral
        )
    }

    private static func resolveProcessing(
        stage: VoiceAttemptStage?
    ) -> IOSVoiceStatusPresentation {
        switch stage {
        case .recordingFinalization:
            status(
                "Finishing local recording step…",
                detail: "HoldType is updating the protected local recording.",
                image: "waveform",
                tone: .active,
                showsProgress: true
            )
        case .transcription:
            status(
                "Transcribing…",
                detail: "OpenAI is transcribing the protected recording.",
                image: "text.bubble",
                tone: .active,
                showsProgress: true
            )
        case .postProcessing:
            status(
                "Refining text…",
                detail: "Applying the selected writing and language settings.",
                image: "text.badge.checkmark",
                tone: .active,
                showsProgress: true
            )
        case .outputDelivery:
            status(
                "Saving result…",
                detail: "Confirming the app-private Latest Result.",
                image: "checkmark.circle",
                tone: .active,
                showsProgress: true
            )
        case nil:
            status(
                "Processing…",
                detail: "Finishing the current Voice action.",
                image: "ellipsis.circle",
                tone: .active,
                showsProgress: true
            )
        }
    }

    private static func setupStatus(
        _ destination: RecoveryDestination,
        failure: IOSForegroundVoiceFailure?
    ) -> IOSVoiceStatusPresentation {
        if destination == .microphoneAndPrivacy,
           failure == .microphonePermissionDenied {
            return status(
                "Microphone access is off",
                detail: "Open Privacy & Permissions to allow recording, then return to Voice.",
                image: "mic.slash",
                tone: .warning,
                setupDestination: destination
            )
        }

        let copy: (String, String, String)
        switch destination {
        case .openAI:
            copy = (
                "OpenAI setup required",
                "Add or repair the API key before starting.",
                "key"
            )
        case .transcription:
            copy = (
                "Transcription setup required",
                "Review the transcription language and model.",
                "waveform.and.mic"
            )
        case .translation:
            copy = (
                "Translation setup required",
                "Choose a valid translation target before using Translate.",
                "character.book.closed"
            )
        case .keyboard:
            copy = (
                "Keyboard setup required",
                "Finish the keyboard setup and verify it in the practice field.",
                "keyboard"
            )
        case .fullAccess:
            copy = (
                "Full Access required for keyboard voice",
                "Turn on Allow Full Access for keyboard-controlled dictation. Local editing and Latest insertion remain available without it.",
                "keyboard.badge.ellipsis"
            )
        case .microphoneAndPrivacy:
            copy = (
                "Privacy review required",
                "Review microphone access and OpenAI processing consent.",
                "hand.raised"
            )
        }
        return status(
            copy.0,
            detail: copy.1,
            image: copy.2,
            tone: .warning,
            setupDestination: destination
        )
    }

    static func primaryGateStatus(
        _ gate: IOSVoicePrimaryGate
    ) -> IOSVoiceStatusPresentation? {
        switch gate {
        case .available:
            nil
        case .draftLoading:
            status(
                "Preparing your Draft…",
                detail: "HoldType is loading the text area before enabling dictation.",
                image: "doc.text",
                tone: .neutral,
                showsProgress: true
            )
        case .draftUpdating:
            status(
                "Saving your Draft…",
                detail: "Dictation will be available as soon as the current text is safe.",
                image: "doc.badge.clock",
                tone: .neutral,
                showsProgress: true
            )
        case .draftEditing:
            status(
                "Finish editing to dictate",
                detail: "Tap Done on the keyboard, then start a new dictation.",
                image: "keyboard",
                tone: .neutral
            )
        case .draftUnavailable:
            status(
                "Draft needs attention",
                detail: "Reload the protected Draft before adding another dictation.",
                image: "doc.badge.exclamationmark",
                tone: .failure
            )
        case .draftFull:
            status(
                "Draft is full",
                detail: "Copy or clear the Draft above before adding another dictation.",
                image: "doc.badge.ellipsis",
                tone: .warning
            )
        case .voiceChecking:
            status(
                "Checking Voice…",
                detail: "HoldType is confirming setup before enabling dictation.",
                image: "mic",
                tone: .neutral,
                showsProgress: true
            )
        }
    }

    private static func warningStatus(
        _ warning: IOSForegroundVoiceWarning
    ) -> IOSVoiceStatusPresentation {
        switch warning {
        case .historySaveFailed:
            status(
                "Result ready",
                detail: "Latest Result is ready, but HoldType couldn't save it to History.",
                image: "exclamationmark.arrow.triangle.2.circlepath",
                tone: .warning
            )
        case .localCleanupPending:
            status(
                "Result ready",
                detail: "Latest Result is safe; HoldType will finish local cleanup automatically.",
                image: "checkmark.circle",
                tone: .warning
            )
        }
    }

    private static func recoveryStatus(
        _ recovery: IOSForegroundVoiceRecovery,
        outcome: VoiceAttemptOutcome?
    ) -> IOSVoiceStatusPresentation {
        let prefix = outcome == .interrupted ? "Recording interrupted. " : ""
        switch recovery {
        case .none:
            return outcomeStatus(outcome ?? .recoverableFailure)
        case .captureRecoverOrDiscard:
            return status(
                "Recording needs attention",
                detail: prefix + "Recover it for Retry or discard it.",
                image: "waveform.badge.exclamationmark",
                tone: .warning
            )
        case .captureDiscardOnly:
            return status(
                "Incomplete recording",
                detail: prefix + "It cannot be recovered and may be discarded.",
                image: "waveform.slash",
                tone: .warning
            )
        case .pendingRetryOrDiscard:
            return status(
                "Recording ready to retry",
                detail: "Retry the protected recording or discard it.",
                image: "arrow.clockwise",
                tone: .warning
            )
        case .blocked:
            return status(
                "Local recovery blocked",
                detail: "HoldType preserved the local work but cannot act safely yet.",
                image: "lock.trianglebadge.exclamationmark",
                tone: .failure
            )
        }
    }

    private static func failureStatus(
        _ failure: IOSForegroundVoiceFailure
    ) -> IOSVoiceStatusPresentation {
        let copy: (String, String, String, IOSVoiceStatusTone)
        switch failure {
        case .operationFailed:
            copy = (
                "Voice action failed",
                "The current action ended without changing a prior result.",
                "exclamationmark.circle",
                .failure
            )
        case .localRecovery:
            copy = (
                "Local recovery needs attention",
                "Protected local work was preserved for a later retry.",
                "externaldrive.badge.exclamationmark",
                .warning
            )
        case .unavailable:
            copy = (
                "Voice unavailable",
                "A required local service is unavailable.",
                "exclamationmark.triangle",
                .failure
            )
        case .microphonePermissionDenied:
            copy = (
                "Microphone access denied",
                "Allow microphone access in System Settings to record.",
                "mic.slash",
                .warning
            )
        case .microphoneUnavailable:
            copy = (
                "Microphone unavailable",
                "No usable microphone input is currently available.",
                "mic.slash",
                .failure
            )
        case .microphonePermissionTimedOut:
            copy = (
                "Microphone request timed out",
                "Nothing was recorded. Start again when HoldType is active.",
                "clock.badge.exclamationmark",
                .warning
            )
        case .tooShort:
            copy = (
                "Recording too short",
                "Speak a little longer, then tap Done.",
                "waveform",
                .neutral
            )
        case .maximumDuration:
            copy = (
                "Maximum duration reached",
                "The five-minute recording limit ended this attempt.",
                "timer",
                .warning
            )
        }
        return status(
            copy.0,
            detail: copy.1,
            image: copy.2,
            tone: copy.3
        )
    }

    private static func outcomeStatus(
        _ outcome: VoiceAttemptOutcome
    ) -> IOSVoiceStatusPresentation {
        switch outcome {
        case .resultReady:
            status(
                "Result ready",
                detail: "Review the app-private Latest Result below.",
                image: "checkmark.circle.fill",
                tone: .success
            )
        case .recoverableFailure:
            status(
                "Recovery available",
                detail: "Use the available recovery action to continue safely.",
                image: "arrow.clockwise.circle",
                tone: .warning
            )
        case .interrupted:
            status(
                "Recording interrupted",
                detail: "A required foreground or audio condition changed.",
                image: "exclamationmark.circle",
                tone: .warning
            )
        case .expired:
            status(
                "Voice session unavailable",
                detail: "This session state is not available in one-shot dictation.",
                image: "exclamationmark.triangle",
                tone: .warning
            )
        }
    }

    private static func status(
        _ title: String,
        detail: String,
        image: String,
        tone: IOSVoiceStatusTone,
        showsProgress: Bool = false,
        setupDestination: RecoveryDestination? = nil
    ) -> IOSVoiceStatusPresentation {
        IOSVoiceStatusPresentation(
            title: title,
            detail: detail,
            systemImage: image,
            tone: tone,
            showsProgress: showsProgress,
            setupDestination: setupDestination
        )
    }
}
