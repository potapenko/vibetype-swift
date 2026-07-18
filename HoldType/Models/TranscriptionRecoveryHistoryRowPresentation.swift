struct TranscriptionRecoveryHistoryRowPresentation: Equatable {
    let title: String
    let message: String
    let systemImage: String
    let showsProgress: Bool
    let showsSettings: Bool
    let showsRetry: Bool
    let showsSaveRetry: Bool
    let saveRetryTitle: String

    init(attempt: FailedTranscriptionAttempt) {
        switch attempt.state {
        case .processing:
            title = "Processing"
            message = "Recording saved. Transcription is in progress."
            systemImage = "waveform"
            showsProgress = true
            showsSettings = false
            showsRetry = false
            showsSaveRetry = false
            saveRetryTitle = "Retry Save"
        case .failed:
            if attempt.reason == .savedStatePersistenceFailed {
                title = "Transcribed — save incomplete"
                message = attempt.acceptedTranscriptText ?? attempt.reason.message
            } else if attempt.reason == .postProcessingFailedAfterProviderAcceptance {
                title = "Raw transcription recovered — post-processing failed"
                message = attempt.acceptedTranscriptText ?? attempt.reason.message
            } else if attempt.reason == .recoveryOwnershipPersistenceFailed
                        || attempt.reason == .providerDispatchPersistenceFailed {
                title = "Recording — save incomplete"
                message = attempt.reason.message
            } else {
                title = "Not transcribed"
                message = attempt.reason.message
            }
            systemImage = "exclamationmark.triangle"
            showsProgress = false
            showsSettings = attempt.reason.settingsTarget != nil
            showsRetry = attempt.canRetry
            showsSaveRetry = (
                attempt.reason == .savedStatePersistenceFailed
                    && attempt.acceptedTranscriptText != nil
            ) || attempt.reason == .recoveryOwnershipPersistenceFailed
                || attempt.reason == .providerDispatchPersistenceFailed
                || (
                    attempt.reason == .postProcessingFailedAfterProviderAcceptance
                        && attempt.acceptedTranscriptText != nil
                )
            saveRetryTitle = attempt.reason
                == .postProcessingFailedAfterProviderAcceptance
                ? "Save Raw Transcription"
                : "Retry Save"
        case .saved:
            title = attempt.reason == .postProcessingFailedAfterProviderAcceptance
                ? "Raw transcription saved — post-processing failed"
                : "Saved and transcribed"
            message = attempt.acceptedTranscriptText ?? "Transcription completed."
            systemImage = "checkmark.circle.fill"
            showsProgress = false
            showsSettings = false
            showsRetry = false
            showsSaveRetry = false
            saveRetryTitle = "Retry Save"
        }
    }
}
