import HoldTypeDomain
import HoldTypeOpenAI

enum DictationFailureLogClassifier {
    static func category(for error: Error) -> String {
        if let error = error as? AudioRecorderServiceError {
            return error.operatorLogCategory
        }

        if let error = error as? OpenAITranscriptionServiceError {
            return error.operatorLogCategory
        }

        if let error = error as? OpenAITextCorrectionServiceError {
            return error.operatorLogCategory
        }

        if let error = error as? OpenAITextTranslationServiceError {
            return error.operatorLogCategory
        }

        if let error = error as? TextInsertionServiceError {
            return error.operatorLogCategory
        }

        if let error = error as? RecordingCacheServiceError {
            return error.operatorLogCategory
        }

        if let error = error as? TranslationConfigurationIssue {
            return error.operatorLogCategory
        }

        return "unknown"
    }
}

private extension AudioRecorderServiceError {
    var operatorLogCategory: String {
        switch self {
        case .alreadyRecording:
            return "already_recording"
        case .notRecording:
            return "not_recording"
        case .microphonePermissionDenied:
            return "microphone_permission_denied"
        case .recordingUnavailable:
            return "recording_unavailable"
        case .temporaryFileUnavailable:
            return "temporary_file_unavailable"
        case .startFailed:
            return "start_failed"
        case .stopFailed:
            return "stop_failed"
        case .cancelCleanupFailed:
            return "cancel_cleanup_failed"
        case .missingRecordingFile:
            return "missing_recording_file"
        case .emptyRecording:
            return "empty_recording"
        case .recordingTooShort:
            return "recording_too_short"
        case .recordingTimedOut:
            return "recording_timed_out"
        }
    }
}

private extension OpenAITextCorrectionServiceError {
    var operatorLogCategory: String {
        switch self {
        case .missingAPIKey:
            return "missing_api_key"
        case .apiKeyUnavailable:
            return "api_key_unavailable"
        case .invalidRequest:
            return "invalid_request"
        case .timedOut:
            return "timeout"
        case .networkUnavailable:
            return "network_unavailable"
        case .networkFailure:
            return "network_failure"
        case .cancelled:
            return "cancelled"
        case .invalidAPIKey:
            return "invalid_api_key"
        case .rateLimited:
            return "rate_limited"
        case .providerUnavailable:
            return "provider_unavailable"
        case .badRequest:
            return "bad_request"
        case .providerRejected(let statusCode):
            return "provider_rejected_\(statusCode)"
        case .invalidResponse:
            return "invalid_response"
        case .emptyCorrection:
            return "empty_correction"
        }
    }
}

private extension OpenAITextTranslationServiceError {
    var operatorLogCategory: String {
        switch self {
        case .missingAPIKey:
            return "missing_api_key"
        case .apiKeyUnavailable:
            return "api_key_unavailable"
        case .invalidRequest:
            return "invalid_request"
        case .timedOut:
            return "timeout"
        case .networkUnavailable:
            return "network_unavailable"
        case .networkFailure:
            return "network_failure"
        case .cancelled:
            return "cancelled"
        case .invalidAPIKey:
            return "invalid_api_key"
        case .rateLimited:
            return "rate_limited"
        case .providerUnavailable:
            return "provider_unavailable"
        case .badRequest:
            return "bad_request"
        case .invalidLanguageConfiguration:
            return "invalid_language_configuration"
        case .providerRejected(let statusCode):
            return "provider_rejected_\(statusCode)"
        case .invalidResponse:
            return "invalid_response"
        case .emptyTranslation:
            return "empty_translation"
        }
    }
}

private extension TranslationConfigurationIssue {
    var operatorLogCategory: String {
        switch self {
        case .invalidSourceLanguage:
            return "invalid_translation_source_language"
        case .missingTargetLanguage:
            return "missing_translation_target_language"
        }
    }
}

private extension TextInsertionServiceError {
    var operatorLogCategory: String {
        switch self {
        case .emptyAppClipboardText:
            return "empty_app_clipboard_text"
        case .textEventUnavailable:
            return "text_event_unavailable"
        case .textInsertionFailed:
            return "text_insertion_failed"
        case .textInsertionTimedOut:
            return "text_insertion_timed_out"
        }
    }
}

private extension RecordingCacheServiceError {
    var operatorLogCategory: String {
        switch self {
        case .directoryUnavailable:
            return "directory_unavailable"
        case .listingFailed:
            return "listing_failed"
        case .unsupportedRecordingURL:
            return "unsupported_recording_url"
        case .recordingProtected:
            return "recording_protected"
        case .deleteFailed:
            return "delete_failed"
        case .clearFailed:
            return "clear_failed"
        }
    }
}
