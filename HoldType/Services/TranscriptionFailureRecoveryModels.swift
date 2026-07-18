//
//  TranscriptionFailureRecoveryModels.swift
//  HoldType
//
//  Created by Codex on 7/18/26.
//

import Combine
import Foundation
import HoldTypeDomain
import HoldTypeOpenAI

enum FailedTranscriptionReason: Codable, Equatable {
    case missingAPIKey
    case apiKeyUnavailable
    case invalidAPIKey
    case invalidRecording
    case invalidRequest
    case timedOut
    case networkUnavailable
    case networkFailure
    case cancelled
    case rateLimited
    case providerUnavailable
    case badRequest
    case providerRejected(statusCode: Int)
    case invalidResponse
    case emptyTranscript
    case dictionaryEcho
    case contextEcho
    case processingInterrupted
    case recoveryOwnershipPersistenceFailed
    case providerDispatchPersistenceFailed
    case providerOutcomeUncertain
    case postProcessingFailedAfterProviderAcceptance
    case savedStatePersistenceFailed
    case other

    init(error: Error) {
        if let error = error as? OpenAITranscriptionServiceError {
            self = Self(error)
            return
        }

        self = .other
    }

    private init(_ error: OpenAITranscriptionServiceError) {
        switch error {
        case .missingAPIKey:
            self = .missingAPIKey
        case .apiKeyUnavailable:
            self = .apiKeyUnavailable
        case .invalidAPIKey:
            self = .invalidAPIKey
        case .invalidRecording(.invalidCustomLanguageCode):
            // The audio is intact; fixing the language setting makes this
            // saved recording retryable.
            self = .invalidRequest
        case .invalidRecording:
            self = .invalidRecording
        case .invalidRequest:
            self = .invalidRequest
        case .multipartMetadataTooLarge:
            self = .badRequest
        case .timedOut:
            self = .timedOut
        case .networkUnavailable:
            self = .networkUnavailable
        case .networkFailure:
            self = .networkFailure
        case .cancelled:
            self = .cancelled
        case .rateLimited:
            self = .rateLimited
        case .providerUnavailable:
            self = .providerUnavailable
        case .badRequest:
            self = .badRequest
        case .providerRejected(let statusCode):
            self = .providerRejected(statusCode: statusCode)
        case .invalidResponse:
            self = .invalidResponse
        case .emptyTranscript:
            self = .emptyTranscript
        case .dictionaryEcho:
            self = .dictionaryEcho
        case .contextEcho:
            self = .contextEcho
        }
    }

    var title: String {
        switch self {
        case .missingAPIKey:
            return "API key missing"
        case .apiKeyUnavailable:
            return "API key could not be read"
        case .invalidAPIKey:
            return "API key rejected"
        case .invalidRecording:
            return "Recording unavailable"
        case .invalidRequest:
            return "Request failed"
        case .timedOut:
            return "Timed out"
        case .networkUnavailable:
            return "Network unavailable"
        case .networkFailure:
            return "Network failed"
        case .cancelled:
            return "Cancelled"
        case .rateLimited:
            return "Rate limited"
        case .providerUnavailable:
            return "OpenAI unavailable"
        case .badRequest:
            return "Settings need attention"
        case .providerRejected:
            return "Request rejected"
        case .invalidResponse:
            return "Unreadable response"
        case .emptyTranscript:
            return "No text detected"
        case .dictionaryEcho:
            return "Only dictionary hints detected"
        case .contextEcho:
            return "Only nearby context detected"
        case .processingInterrupted:
            return "Processing interrupted"
        case .recoveryOwnershipPersistenceFailed:
            return "Recording save incomplete"
        case .providerDispatchPersistenceFailed:
            return "Retry preparation incomplete"
        case .providerOutcomeUncertain:
            return "Transcription outcome uncertain"
        case .postProcessingFailedAfterProviderAcceptance:
            return "Raw transcription recovered"
        case .savedStatePersistenceFailed:
            return "Saved result incomplete"
        case .other:
            return "Transcription failed"
        }
    }

    var message: String {
        switch self {
        case .missingAPIKey:
            return "No OpenAI API key is available for transcription."
        case .apiKeyUnavailable:
            return "HoldType could not read the saved OpenAI API key. The recording was not transcribed."
        case .invalidAPIKey:
            return "OpenAI rejected the saved API key. The recording was not transcribed."
        case .invalidRecording:
            return "The recording could not be prepared for transcription."
        case .invalidRequest:
            return "The transcription request could not be prepared."
        case .timedOut:
            return "Transcription timed out. You can retry this recording."
        case .networkUnavailable:
            return "The network is unavailable. You can retry when connected."
        case .networkFailure:
            return "The transcription request failed. You can retry this recording."
        case .cancelled:
            return "Transcription was cancelled."
        case .rateLimited:
            return "OpenAI rate limits were reached. Retry later."
        case .providerUnavailable:
            return "OpenAI is unavailable. Retry later."
        case .badRequest:
            return "Transcription settings or recording format need attention."
        case .providerRejected:
            return "OpenAI rejected the transcription request."
        case .invalidResponse:
            return "OpenAI returned an unreadable response. You can retry this recording."
        case .emptyTranscript:
            return "No speech text was detected. You can retry this recording."
        case .dictionaryEcho:
            return "Only dictionary hints were detected. You can retry after adjusting settings."
        case .contextEcho:
            return "Only nearby context was detected. You can retry after adjusting settings."
        case .processingInterrupted:
            return "The app stopped while processing this saved recording. You can retry transcription."
        case .recoveryOwnershipPersistenceFailed:
            return "Save this playable recording locally before retrying transcription."
        case .providerDispatchPersistenceFailed:
            return "The recording must be prepared locally before transcription can retry."
        case .providerOutcomeUncertain:
            return "The provider request may have completed. The recording is playable, but it cannot be uploaded again."
        case .postProcessingFailedAfterProviderAcceptance:
            return "Transcription succeeded, but downstream processing failed. The raw transcription is preserved locally."
        case .savedStatePersistenceFailed:
            return "Transcription succeeded, but the saved result could not be written. Retry saving it locally."
        case .other:
            return "Transcription failed. You can retry this recording."
        }
    }

    var settingsTarget: SettingsNavigationItem? {
        switch self {
        case .missingAPIKey, .apiKeyUnavailable, .invalidAPIKey:
            return .openAI
        case .invalidRecording, .invalidRequest, .badRequest, .dictionaryEcho, .contextEcho:
            return .transcription
        case .timedOut,
             .networkUnavailable,
             .networkFailure,
             .cancelled,
             .rateLimited,
             .providerUnavailable,
             .providerRejected,
             .invalidResponse,
             .emptyTranscript,
             .processingInterrupted,
             .recoveryOwnershipPersistenceFailed,
             .providerDispatchPersistenceFailed,
             .providerOutcomeUncertain,
             .postProcessingFailedAfterProviderAcceptance,
             .savedStatePersistenceFailed,
             .other:
            return nil
        }
    }

    var canRetry: Bool {
        switch self {
        case .cancelled,
             .invalidRecording,
             .recoveryOwnershipPersistenceFailed,
             .providerDispatchPersistenceFailed,
             .providerOutcomeUncertain,
             .postProcessingFailedAfterProviderAcceptance,
             .savedStatePersistenceFailed:
            return false
        default:
            return true
        }
    }

    var shouldRecordFailedAttempt: Bool {
        switch self {
        case .missingAPIKey, .cancelled, .invalidRecording:
            return false
        default:
            return true
        }
    }
}

enum TranscriptionRecoveryState: String, Codable, Equatable {
    case processing
    case failed
    case saved
}

enum TranscriptionRecoveryCompletionKind: String, Codable, Equatable {
    case standard
    case maximumDuration
}

struct FailedTranscriptionAttempt: Equatable, Identifiable {
    typealias ID = UUID

    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    let audioFileURL: URL
    let audioDuration: TimeInterval?
    let transcriptionModel: String
    let languageCode: String?
    let completionKind: TranscriptionRecoveryCompletionKind
    var state: TranscriptionRecoveryState
    var reason: FailedTranscriptionReason
    var retryCount: Int
    var acceptedTranscriptText: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        audioFileURL: URL,
        audioDuration: TimeInterval?,
        transcriptionModel: String,
        languageCode: String?,
        completionKind: TranscriptionRecoveryCompletionKind = .standard,
        state: TranscriptionRecoveryState = .failed,
        reason: FailedTranscriptionReason,
        retryCount: Int = 0,
        acceptedTranscriptText: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.audioFileURL = audioFileURL
        self.audioDuration = audioDuration
        self.transcriptionModel = transcriptionModel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.languageCode = languageCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        self.completionKind = completionKind
        self.state = state
        self.reason = reason
        self.retryCount = max(0, retryCount)
        self.acceptedTranscriptText = acceptedTranscriptText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }

    var canRetry: Bool {
        state == .failed && reason.canRetry
    }

    var canDelete: Bool {
        state != .processing
    }
}

@MainActor
protocol TranscriptionFailureRecoveryRecording: AnyObject {
    var failedAttempts: [FailedTranscriptionAttempt] { get }

    func recordProcessingCheckpoint(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        completionKind: TranscriptionRecoveryCompletionKind
    ) throws -> FailedTranscriptionAttempt
    func recordFailedAttempt(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        reason: FailedTranscriptionReason
    ) throws -> FailedTranscriptionAttempt?
    func retainEmergencyFallback(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        reason: FailedTranscriptionReason,
        completionKind: TranscriptionRecoveryCompletionKind
    ) -> FailedTranscriptionAttempt?
    func markSaved(id: FailedTranscriptionAttempt.ID, acceptedTranscriptText: String) throws
    func sealProviderDispatch(id: FailedTranscriptionAttempt.ID) throws
    func markProviderOutcomeUncertain(id: FailedTranscriptionAttempt.ID)
    func recordProviderAccepted(
        id: FailedTranscriptionAttempt.ID,
        acceptedTranscriptText: String
    )
    func markAcceptedHistoryCommitFailed(id: FailedTranscriptionAttempt.ID)
    func updateFailedAttempt(id: FailedTranscriptionAttempt.ID, reason: FailedTranscriptionReason) throws
    @discardableResult
    func removeFailedAttempt(id: FailedTranscriptionAttempt.ID) throws -> Bool
}

extension TranscriptionFailureRecoveryRecording {
    func recordProcessingCheckpoint(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?
    ) throws -> FailedTranscriptionAttempt {
        try recordProcessingCheckpoint(
            audioFileURL: audioFileURL,
            settings: settings,
            audioDuration: audioDuration,
            completionKind: .standard
        )
    }

    func retainEmergencyFallback(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        reason: FailedTranscriptionReason
    ) -> FailedTranscriptionAttempt? {
        retainEmergencyFallback(
            audioFileURL: audioFileURL,
            settings: settings,
            audioDuration: audioDuration,
            reason: reason,
            completionKind: .standard
        )
    }

    func retainEmergencyFallback(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        reason: FailedTranscriptionReason,
        completionKind: TranscriptionRecoveryCompletionKind
    ) -> FailedTranscriptionAttempt? {
        nil
    }

    func markSaved(
        id: FailedTranscriptionAttempt.ID,
        acceptedTranscriptText: String
    ) throws {
        throw TranscriptionFailureRecoveryError.saveFailed
    }

    func sealProviderDispatch(id: FailedTranscriptionAttempt.ID) throws {}

    func markProviderOutcomeUncertain(id: FailedTranscriptionAttempt.ID) {}

    func recordProviderAccepted(
        id: FailedTranscriptionAttempt.ID,
        acceptedTranscriptText: String
    ) {}

    func markAcceptedHistoryCommitFailed(id: FailedTranscriptionAttempt.ID) {}
}

enum TranscriptionFailureRecoveryError: Error, Equatable, LocalizedError {
    case directoryUnavailable
    case audioUnavailable
    case saveFailed
    case deleteFailed
    case attemptUnavailable

    var errorDescription: String? {
        switch self {
        case .directoryUnavailable:
            return "Failed transcription recovery could not be prepared."
        case .audioUnavailable:
            return "The failed recording is no longer available."
        case .saveFailed:
            return "The failed recording could not be saved for retry."
        case .deleteFailed:
            return "The failed recording could not be removed."
        case .attemptUnavailable:
            return "The failed transcription attempt is no longer available."
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
