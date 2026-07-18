//
//  TranscriptionFailureRecoveryStore.swift
//  HoldType
//
//  Created by Codex on 7/7/26.
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

@MainActor
final class TranscriptionFailureRecoveryStore: ObservableObject, TranscriptionFailureRecoveryRecording {
    static let shared = TranscriptionFailureRecoveryStore()
    nonisolated static let defaultRetentionLimit =
        RetentionConfiguration.failedHistoryEntryLimit

    @Published private(set) var failedAttempts: [FailedTranscriptionAttempt] = []

    private let directoryURL: URL
    private let retentionLimit: Int
    private let fileManager: FileManager
    private let now: () -> Date
    private let uuidProvider: () -> UUID
    private let metadataFileName = "Recovery.json"
    private static let savedStateRepairMarkerPrefix = "SavedStateRepair-"
    private static let processingCheckpointMarkerPrefix = "ProcessingCheckpoint-"
    private static let providerDispatchMarkerPrefix = "ProviderDispatch-"
    private var emergencyFallbackAttemptIDs: Set<UUID> = []
    private var pendingOwnedCheckpointFallbacks: [String: FailedTranscriptionAttempt] = [:]

    init(
        directoryURL: URL? = nil,
        retentionLimit: Int = TranscriptionFailureRecoveryStore.defaultRetentionLimit,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        uuidProvider: @escaping () -> UUID = UUID.init
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.retentionLimit = max(1, retentionLimit)
        self.now = now
        self.uuidProvider = uuidProvider
        let restoration = Self.restoreAttempts(
            from: self.directoryURL,
            metadataFileName: metadataFileName,
            retentionLimit: self.retentionLimit,
            fileManager: fileManager
        )
        failedAttempts = restoration.attempts.map { attempt in
            guard attempt.state == .processing else {
                return attempt
            }

            var interruptedAttempt = attempt
            interruptedAttempt.state = .failed
            interruptedAttempt.reason = .processingInterrupted
            return interruptedAttempt
        }
        if restoration.requiresPersistence || failedAttempts != restoration.attempts {
            do {
                try persist(failedAttempts)
                for audioFileURL in restoration.audioFilesOutsideRetention {
                    do {
                        try deleteRecoveryAudio(audioFileURL)
                        if let id = Self.recoveryFileIdentity(
                            fileName: audioFileURL.lastPathComponent
                        ) {
                            try? deleteSavedStateRepairMarker(id: id)
                            try? deleteProcessingCheckpointMarker(id: id)
                            try? deleteProviderDispatchMarker(
                                id: id,
                                afterRemovingAudioAt: audioFileURL
                            )
                        }
                    } catch {
                        // Keep every provider seal while its owned audio still
                        // exists, even when retention pruning cannot unlink it.
                    }
                }
                for markerURL in restoration.repairMarkerURLsToDeleteAfterPersistence {
                    try? deleteSavedStateRepairMarker(markerURL)
                }
                for markerURL in restoration.checkpointMarkerURLsToDeleteAfterPersistence {
                    try? deleteProcessingCheckpointMarker(markerURL)
                }
            } catch {
                // Keep reconstructed rows visible in memory even when the
                // metadata file cannot currently be repaired.
            }
        }
    }

    func recordProcessingCheckpoint(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        completionKind: TranscriptionRecoveryCompletionKind
    ) throws -> FailedTranscriptionAttempt {
        try validateNonemptyAudio(at: audioFileURL)

        let id = uuidProvider()
        let createdAt = now()
        let recoveryAudioURL = try copyAudioForRecovery(
            sourceURL: audioFileURL,
            id: id,
            createdAt: createdAt,
            completionKind: completionKind
        )
        let attempt = FailedTranscriptionAttempt(
            id: id,
            createdAt: createdAt,
            audioFileURL: recoveryAudioURL,
            audioDuration: audioDuration,
            transcriptionModel: settings.resolvedTranscriptionModel,
            languageCode: settings.resolvedLanguageCode,
            completionKind: completionKind,
            state: .processing,
            reason: .other
        )

        let checkpointMarkerWasWritten =
            (try? persistProcessingCheckpointMarker(attempt)) != nil

        do {
            try replaceAttemptsWithRetained([attempt] + failedAttempts)
            if checkpointMarkerWasWritten {
                try? deleteProcessingCheckpointMarker(id: id)
            }
            return attempt
        } catch {
            // Keep the owned non-empty copy as an orphan. Startup
            // reconciliation can reconstruct a bounded retry row even when
            // the metadata write failed during this process.
            pendingOwnedCheckpointFallbacks[
                audioFileURL.standardizedFileURL.path
            ] = attempt
            throw error
        }
    }

    func recordFailedAttempt(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        reason: FailedTranscriptionReason
    ) throws -> FailedTranscriptionAttempt? {
        guard settings.saveTranscriptHistory, reason.shouldRecordFailedAttempt else {
            return nil
        }

        let attempt = try recordProcessingCheckpoint(
            audioFileURL: audioFileURL,
            settings: settings,
            audioDuration: audioDuration,
            completionKind: .standard
        )
        try updateFailedAttempt(id: attempt.id, reason: reason)
        return failedAttempts.first { $0.id == attempt.id }
    }

    func retainEmergencyFallback(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        reason: FailedTranscriptionReason,
        completionKind: TranscriptionRecoveryCompletionKind
    ) -> FailedTranscriptionAttempt? {
        let sourcePath = audioFileURL.standardizedFileURL.path
        if var pendingAttempt = pendingOwnedCheckpointFallbacks.removeValue(
            forKey: sourcePath
        ),
            pendingAttempt.completionKind == completionKind,
            (try? validateNonemptyAudio(at: pendingAttempt.audioFileURL)) != nil {
            pendingAttempt.state = .failed
            pendingAttempt.reason = reason
            pendingAttempt.updatedAt = now()
            // This path exists because durable recovery ownership could not be
            // confirmed. Hiding an older unresolved row here would turn a
            // persistence failure into silent data loss, so keep every
            // in-memory fallback visible until a later durable mutation can
            // apply retention only to terminal saved rows.
            failedAttempts = ([pendingAttempt] + failedAttempts)
                .sorted { $0.updatedAt > $1.updatedAt }
            return pendingAttempt
        }

        guard (try? validateNonemptyAudio(at: audioFileURL)) != nil else {
            return nil
        }

        let attempt = FailedTranscriptionAttempt(
            id: uuidProvider(),
            createdAt: now(),
            audioFileURL: audioFileURL,
            audioDuration: audioDuration,
            transcriptionModel: settings.resolvedTranscriptionModel,
            languageCode: settings.resolvedLanguageCode,
            completionKind: completionKind,
            state: .failed,
            reason: .recoveryOwnershipPersistenceFailed
        )
        emergencyFallbackAttemptIDs.insert(attempt.id)
        failedAttempts = ([attempt] + failedAttempts)
            .sorted { $0.updatedAt > $1.updatedAt }
        return attempt
    }

    func markSaved(
        id: FailedTranscriptionAttempt.ID,
        acceptedTranscriptText: String
    ) throws {
        let normalizedText = acceptedTranscriptText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty,
              let index = failedAttempts.firstIndex(where: { $0.id == id }) else {
            throw TranscriptionFailureRecoveryError.saveFailed
        }

        var existingAttempt = failedAttempts[index]
        if existingAttempt.state == .saved {
            guard existingAttempt.acceptedTranscriptText == normalizedText else {
                throw TranscriptionFailureRecoveryError.saveFailed
            }
            return
        }
        let canSaveAcceptedRecovery =
            existingAttempt.completionKind == .maximumDuration
            || (
                existingAttempt.acceptedTranscriptText != nil
                    && (
                        existingAttempt.reason == .savedStatePersistenceFailed
                            || existingAttempt.reason
                                == .postProcessingFailedAfterProviderAcceptance
                    )
            )
        guard canSaveAcceptedRecovery,
              existingAttempt.state == .processing || existingAttempt.state == .failed else {
            throw TranscriptionFailureRecoveryError.attemptUnavailable
        }

        let wasEmergencyFallback = emergencyFallbackAttemptIDs.contains(id)
        if wasEmergencyFallback {
            do {
                existingAttempt = try copyEmergencyAttemptIntoRecovery(existingAttempt)
            } catch {
                var failClosedAttempts = failedAttempts
                failClosedAttempts[index].state = .failed
                failClosedAttempts[index].reason = .savedStatePersistenceFailed
                failClosedAttempts[index].acceptedTranscriptText = normalizedText
                failClosedAttempts[index].updatedAt = now()
                failedAttempts = failClosedAttempts.sorted { lhs, rhs in
                    lhs.updatedAt > rhs.updatedAt
                }
                throw error
            }
        }

        let preservesRawProviderTranscript =
            existingAttempt.reason == .postProcessingFailedAfterProviderAcceptance
            || (
                existingAttempt.completionKind == .standard
                    && existingAttempt.acceptedTranscriptText != nil
            )
        var updatedAttempts = failedAttempts
        updatedAttempts[index] = existingAttempt
        updatedAttempts[index].state = .saved
        updatedAttempts[index].reason = preservesRawProviderTranscript
            ? .postProcessingFailedAfterProviderAcceptance
            : .other
        updatedAttempts[index].acceptedTranscriptText = normalizedText
        updatedAttempts[index].updatedAt = now()
        updatedAttempts = updatedAttempts.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
        let updatedAttempt = updatedAttempts.first { $0.id == id }
        let repairMarkerWasWritten = updatedAttempt.map {
            (try? persistSavedStateRepairMarker($0)) != nil
        } ?? false

        // Persist first so observers never see a saved row that cannot survive
        // relaunch. The recovery audio remains untouched if this write fails.
        do {
            try replaceAttemptsWithRetained(updatedAttempts)
            emergencyFallbackAttemptIDs.remove(id)
            if repairMarkerWasWritten {
                try? deleteSavedStateRepairMarker(id: id)
            }
            try? deleteProcessingCheckpointMarker(id: id)
        } catch {
            var recoverableAttempts = failedAttempts
            recoverableAttempts[index] = existingAttempt
            recoverableAttempts[index].state = .failed
            recoverableAttempts[index].reason = preservesRawProviderTranscript
                ? .postProcessingFailedAfterProviderAcceptance
                : .savedStatePersistenceFailed
            recoverableAttempts[index].acceptedTranscriptText = normalizedText
            recoverableAttempts[index].updatedAt = updatedAttempts.first {
                $0.id == id
            }?.updatedAt ?? recoverableAttempts[index].updatedAt
            failedAttempts = recoverableAttempts.sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
            if wasEmergencyFallback {
                emergencyFallbackAttemptIDs.remove(id)
            }
            if !repairMarkerWasWritten,
               let recoverableAttempt = failedAttempts.first(where: { $0.id == id }) {
                try? persistSavedStateRepairMarker(recoverableAttempt)
            }
            throw error
        }
    }

    func repairLocalRecovery(id: FailedTranscriptionAttempt.ID) throws {
        guard let index = failedAttempts.firstIndex(where: { $0.id == id }),
              failedAttempts[index].state == .failed else {
            throw TranscriptionFailureRecoveryError.attemptUnavailable
        }

        switch failedAttempts[index].reason {
        case .recoveryOwnershipPersistenceFailed:
            let repairedAttempt = try copyEmergencyAttemptIntoRecovery(
                failedAttempts[index]
            )
            var updatedAttempts = failedAttempts
            updatedAttempts[index] = repairedAttempt
            updatedAttempts[index].reason = .processingInterrupted
            updatedAttempts[index].updatedAt = now()
            updatedAttempts = updatedAttempts.sorted { $0.updatedAt > $1.updatedAt }
            let repaired = updatedAttempts.first { $0.id == id }
            let markerWasWritten = repaired.map {
                (try? persistProcessingCheckpointMarker($0)) != nil
            } ?? false
            let metadataWasWritten = (try? persist(updatedAttempts)) != nil
            guard markerWasWritten || metadataWasWritten else {
                // The owned copy is intentionally left in place for startup
                // reconciliation, while the playable original remains the
                // fail-closed in-memory attempt. Do not expose provider retry
                // until at least one ownership record is durable.
                throw TranscriptionFailureRecoveryError.saveFailed
            }
            if metadataWasWritten, markerWasWritten {
                try? deleteProcessingCheckpointMarker(id: id)
            }
            failedAttempts = updatedAttempts
            emergencyFallbackAttemptIDs.remove(id)

        case .providerDispatchPersistenceFailed:
            var updatedAttempts = failedAttempts
            updatedAttempts[index].reason = .processingInterrupted
            updatedAttempts[index].updatedAt = now()
            updatedAttempts = updatedAttempts.sorted { $0.updatedAt > $1.updatedAt }
            try persist(updatedAttempts)
            failedAttempts = updatedAttempts

        default:
            throw TranscriptionFailureRecoveryError.attemptUnavailable
        }
    }

    func recordProviderAccepted(
        id: FailedTranscriptionAttempt.ID,
        acceptedTranscriptText: String
    ) {
        let normalizedText = acceptedTranscriptText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty,
              let index = failedAttempts.firstIndex(where: { $0.id == id }),
              failedAttempts[index].state != .saved,
              failedAttempts[index].audioFileURL.standardizedFileURL
                .deletingLastPathComponent() == directoryURL.standardizedFileURL,
              Self.recoveryFileIdentity(
                  fileName: failedAttempts[index].audioFileURL.lastPathComponent
              ) == id,
              (try? validateNonemptyAudio(at: failedAttempts[index].audioFileURL)) != nil else {
            return
        }

        var failClosedAttempts = failedAttempts
        failClosedAttempts[index].reason = .savedStatePersistenceFailed
        failClosedAttempts[index].acceptedTranscriptText = normalizedText
        failClosedAttempts[index].updatedAt = now()
        failClosedAttempts = failClosedAttempts.sorted { $0.updatedAt > $1.updatedAt }
        failedAttempts = failClosedAttempts
        if let failClosedAttempt = failedAttempts.first(where: { $0.id == id }) {
            try? persistSavedStateRepairMarker(failClosedAttempt)
        }
    }

    func markAcceptedHistoryCommitFailed(id: FailedTranscriptionAttempt.ID) {
        guard let index = failedAttempts.firstIndex(where: { $0.id == id }),
              failedAttempts[index].state != .saved,
              failedAttempts[index].acceptedTranscriptText != nil else {
            return
        }

        var failClosedAttempts = failedAttempts
        failClosedAttempts[index].state = .failed
        failClosedAttempts[index].reason = .savedStatePersistenceFailed
        failClosedAttempts[index].updatedAt = now()
        failClosedAttempts = failClosedAttempts.sorted { $0.updatedAt > $1.updatedAt }
        if let failClosedAttempt = failClosedAttempts.first(where: { $0.id == id }) {
            // Preserve the provider-accepted text even if the canonical
            // metadata write is the component currently failing. The repair
            // marker and provider dispatch seal block a second paid request.
            try? persistSavedStateRepairMarker(failClosedAttempt)
        }
        try? persist(failClosedAttempts)
        failedAttempts = failClosedAttempts
    }

    func markProviderOutcomeUncertain(id: FailedTranscriptionAttempt.ID) {
        guard let index = failedAttempts.firstIndex(where: { $0.id == id }),
              failedAttempts[index].state != .saved,
              failedAttempts[index].acceptedTranscriptText == nil else {
            return
        }

        var uncertainAttempts = failedAttempts
        uncertainAttempts[index].state = .failed
        uncertainAttempts[index].reason = .providerOutcomeUncertain
        uncertainAttempts[index].updatedAt = now()
        uncertainAttempts = uncertainAttempts.sorted { $0.updatedAt > $1.updatedAt }
        // Keep the provider-dispatch marker for the full lifetime of the
        // retained audio. It is the durable proof that retry may double-submit.
        try? persist(uncertainAttempts)
        failedAttempts = uncertainAttempts
    }

    func sealProviderDispatch(id: FailedTranscriptionAttempt.ID) throws {
        guard let index = failedAttempts.firstIndex(where: { $0.id == id }),
              failedAttempts[index].state == .processing
                || failedAttempts[index].canRetry,
              !emergencyFallbackAttemptIDs.contains(id) else {
            throw TranscriptionFailureRecoveryError.attemptUnavailable
        }

        do {
            try persistProviderDispatchMarker(failedAttempts[index])
        } catch {
            var failClosedAttempts = failedAttempts
            failClosedAttempts[index].state = .failed
            failClosedAttempts[index].reason = .providerDispatchPersistenceFailed
            failClosedAttempts[index].updatedAt = now()
            failClosedAttempts = failClosedAttempts.sorted { $0.updatedAt > $1.updatedAt }
            try? persist(failClosedAttempts)
            failedAttempts = failClosedAttempts
            throw error
        }
    }

    func updateFailedAttempt(id: FailedTranscriptionAttempt.ID, reason: FailedTranscriptionReason) throws {
        guard let index = failedAttempts.firstIndex(where: { $0.id == id }) else {
            throw TranscriptionFailureRecoveryError.attemptUnavailable
        }

        // A successfully transcribed retained recording is terminal even
        // while downstream processing or local metadata still needs repair.
        // Preserve the accepted provider text and never clear its dispatch
        // seal merely because a later translation or formatting stage failed.
        guard failedAttempts[index].state != .saved else {
            return
        }
        if failedAttempts[index].reason == .savedStatePersistenceFailed {
            var failClosedAttempts = failedAttempts
            failClosedAttempts[index].state = .failed
            failClosedAttempts[index].reason =
                .postProcessingFailedAfterProviderAcceptance
            failClosedAttempts[index].updatedAt = now()
            failClosedAttempts = failClosedAttempts.sorted { $0.updatedAt > $1.updatedAt }
            if let failClosedAttempt = failClosedAttempts.first(where: { $0.id == id }) {
                try? persistSavedStateRepairMarker(failClosedAttempt)
            }
            try? persist(failClosedAttempts)
            failedAttempts = failClosedAttempts
            return
        }
        guard failedAttempts[index].reason != .recoveryOwnershipPersistenceFailed,
              failedAttempts[index].reason != .providerDispatchPersistenceFailed,
              failedAttempts[index].reason != .providerOutcomeUncertain,
              failedAttempts[index].reason
                != .postProcessingFailedAfterProviderAcceptance else {
            return
        }

        var updatedAttempts = failedAttempts
        let wasFailed = updatedAttempts[index].state == .failed
        updatedAttempts[index].state = .failed
        updatedAttempts[index].reason = reason
        if wasFailed {
            updatedAttempts[index].retryCount += 1
        }
        updatedAttempts[index].updatedAt = now()
        updatedAttempts = updatedAttempts.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
        if emergencyFallbackAttemptIDs.contains(id) {
            failedAttempts = updatedAttempts
            return
        }
        try persist(updatedAttempts)
        failedAttempts = updatedAttempts
        try? deleteProcessingCheckpointMarker(id: id)
        try? deleteProviderDispatchMarker(id: id)
    }

    @discardableResult
    func removeFailedAttempt(id: FailedTranscriptionAttempt.ID) throws -> Bool {
        guard let attempt = failedAttempts.first(where: { $0.id == id }) else {
            return false
        }

        if emergencyFallbackAttemptIDs.contains(id) {
            do {
                try deleteExactRegularAudio(attempt.audioFileURL)
            } catch {
                throw TranscriptionFailureRecoveryError.deleteFailed
            }

            emergencyFallbackAttemptIDs.remove(id)
            failedAttempts.removeAll { $0.id == id }
            return true
        }

        let retainedAttempts = failedAttempts.filter { $0.id != id }
        do {
            try persist(retainedAttempts)
        } catch {
            throw TranscriptionFailureRecoveryError.deleteFailed
        }

        do {
            try deleteRecoveryAudio(attempt.audioFileURL)
        } catch {
            // The audio is still present, so restore its row. If this rollback
            // cannot be persisted, launch reconciliation will reconstruct the
            // same app-owned Recording-* artifact.
            try? persist(failedAttempts)
            throw TranscriptionFailureRecoveryError.deleteFailed
        }

        // The dispatch seal is the final fail-closed evidence that this audio
        // may already have reached the provider. Keep it until the exact
        // recovery artifact is gone: if unlink and metadata rollback both
        // fail, relaunch must restore an uncertain non-retryable row instead
        // of reconstructing the orphan as a fresh retry.
        try? deleteSavedStateRepairMarker(id: attempt.id)
        try? deleteProcessingCheckpointMarker(id: attempt.id)
        try? deleteProviderDispatchMarker(
            id: attempt.id,
            afterRemovingAudioAt: attempt.audioFileURL
        )
        failedAttempts = retainedAttempts
        return true
    }

    func clear() {
        let attemptsToDelete = failedAttempts
        guard (try? persist([])) != nil else {
            return
        }

        failedAttempts = []
        let emergencyAttemptIDs = emergencyFallbackAttemptIDs
        emergencyFallbackAttemptIDs.removeAll()
        for attempt in attemptsToDelete {
            if emergencyAttemptIDs.contains(attempt.id) {
                try? deleteExactRegularAudio(attempt.audioFileURL)
            } else {
                do {
                    try deleteRecoveryAudio(attempt.audioFileURL)
                    try? deleteSavedStateRepairMarker(id: attempt.id)
                    try? deleteProcessingCheckpointMarker(id: attempt.id)
                    try? deleteProviderDispatchMarker(
                        id: attempt.id,
                        afterRemovingAudioAt: attempt.audioFileURL
                    )
                } catch {
                    // Leave the lifetime dispatch seal beside any audio that
                    // could not be removed.
                }
            }
        }
    }

    private func validateNonemptyAudio(at fileURL: URL) throws {
        guard Self.regularNonemptyFile(at: fileURL, fileManager: fileManager) != nil else {
            throw TranscriptionFailureRecoveryError.audioUnavailable
        }
    }

    private func copyAudioForRecovery(
        sourceURL: URL,
        id: UUID,
        createdAt: Date,
        completionKind: TranscriptionRecoveryCompletionKind
    ) throws -> URL {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw TranscriptionFailureRecoveryError.directoryUnavailable
        }

        let recordingPrefix = completionKind == .maximumDuration
            ? "Recording-Max-"
            : "Recording-"
        let destinationURL = directoryURL
            .appendingPathComponent("\(recordingPrefix)\(Self.fileTimestamp(from: createdAt))-\(id.uuidString.lowercased())")
            .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension)

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            throw TranscriptionFailureRecoveryError.saveFailed
        }
    }

    private func copyEmergencyAttemptIntoRecovery(
        _ attempt: FailedTranscriptionAttempt
    ) throws -> FailedTranscriptionAttempt {
        let recoveryAudioURL = try copyAudioForRecovery(
            sourceURL: attempt.audioFileURL,
            id: attempt.id,
            createdAt: attempt.createdAt,
            completionKind: attempt.completionKind
        )
        return FailedTranscriptionAttempt(
            id: attempt.id,
            createdAt: attempt.createdAt,
            updatedAt: attempt.updatedAt,
            audioFileURL: recoveryAudioURL,
            audioDuration: attempt.audioDuration,
            transcriptionModel: attempt.transcriptionModel,
            languageCode: attempt.languageCode,
            completionKind: attempt.completionKind,
            state: attempt.state,
            reason: attempt.reason,
            retryCount: attempt.retryCount,
            acceptedTranscriptText: attempt.acceptedTranscriptText
        )
    }

    private func replaceAttemptsWithRetained(
        _ attempts: [FailedTranscriptionAttempt]
    ) throws {
        let selection = Self.retentionSelection(
            attempts,
            retentionLimit: retentionLimit
        )
        try persist(selection.retained)
        failedAttempts = selection.retained

        for attempt in selection.evicted {
            do {
                try deleteRecoveryAudio(attempt.audioFileURL)
                try? deleteSavedStateRepairMarker(id: attempt.id)
                try? deleteProcessingCheckpointMarker(id: attempt.id)
                try? deleteProviderDispatchMarker(
                    id: attempt.id,
                    afterRemovingAudioAt: attempt.audioFileURL
                )
            } catch {
                // Retention never consumes the fail-closed dispatch evidence
                // while its owned provider audio remains on disk.
            }
        }
    }

    /// Count-based retention may reclaim only terminal saved recordings.
    /// Processing, failed, repair-pending, and outcome-uncertain attempts all
    /// remain unresolved and therefore stay visible until explicit deletion or
    /// a successful terminal transition. When unresolved rows consume the
    /// configured budget, terminal saved rows yield first and the total may
    /// temporarily exceed the budget rather than losing recoverable audio.
    private static func retentionSelection(
        _ attempts: [FailedTranscriptionAttempt],
        retentionLimit: Int
    ) -> (
        retained: [FailedTranscriptionAttempt],
        evicted: [FailedTranscriptionAttempt]
    ) {
        let newestFirst = attempts.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
        let unresolved = newestFirst.filter { $0.state != .saved }
        let savedBudget = max(0, retentionLimit - unresolved.count)
        let retainedSaved = Array(
            newestFirst.lazy.filter { $0.state == .saved }.prefix(savedBudget)
        )
        let retainedPaths = Set(
            (unresolved + retainedSaved).map {
                $0.audioFileURL.standardizedFileURL.path
            }
        )
        return (
            retained: newestFirst.filter {
                retainedPaths.contains(
                    $0.audioFileURL.standardizedFileURL.path
                )
            },
            evicted: newestFirst.filter {
                !retainedPaths.contains(
                    $0.audioFileURL.standardizedFileURL.path
                )
            }
        )
    }

    private func persist(_ attempts: [FailedTranscriptionAttempt]) throws {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let records = attempts.map(PersistedRecoveryAttempt.init)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            try encoder.encode(records).write(to: metadataURL, options: .atomic)
        } catch {
            throw TranscriptionFailureRecoveryError.saveFailed
        }
    }

    private func persistSavedStateRepairMarker(
        _ attempt: FailedTranscriptionAttempt
    ) throws {
        guard attempt.audioFileURL.standardizedFileURL.deletingLastPathComponent()
                == directoryURL.standardizedFileURL,
              Self.recoveryFileIdentity(fileName: attempt.audioFileURL.lastPathComponent)
                == attempt.id,
              attempt.acceptedTranscriptText != nil else {
            throw TranscriptionFailureRecoveryError.saveFailed
        }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            try encoder.encode(PersistedSavedStateRepairMarker(attempt))
                .write(to: savedStateRepairMarkerURL(id: attempt.id), options: .atomic)
        } catch {
            throw TranscriptionFailureRecoveryError.saveFailed
        }
    }

    private func persistProcessingCheckpointMarker(
        _ attempt: FailedTranscriptionAttempt
    ) throws {
        guard attempt.audioFileURL.standardizedFileURL.deletingLastPathComponent()
                == directoryURL.standardizedFileURL,
              Self.recoveryFileIdentity(fileName: attempt.audioFileURL.lastPathComponent)
                == attempt.id else {
            throw TranscriptionFailureRecoveryError.saveFailed
        }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            try encoder.encode(PersistedProcessingCheckpointMarker(attempt))
                .write(to: processingCheckpointMarkerURL(id: attempt.id), options: .atomic)
        } catch {
            throw TranscriptionFailureRecoveryError.saveFailed
        }
    }

    private func persistProviderDispatchMarker(
        _ attempt: FailedTranscriptionAttempt
    ) throws {
        guard attempt.audioFileURL.standardizedFileURL.deletingLastPathComponent()
                == directoryURL.standardizedFileURL,
              Self.recoveryFileIdentity(fileName: attempt.audioFileURL.lastPathComponent)
                == attempt.id else {
            throw TranscriptionFailureRecoveryError.saveFailed
        }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            try encoder.encode(PersistedProcessingCheckpointMarker(attempt))
                .write(to: providerDispatchMarkerURL(id: attempt.id), options: .atomic)
        } catch {
            throw TranscriptionFailureRecoveryError.saveFailed
        }
    }

    private func deleteSavedStateRepairMarker(id: UUID) throws {
        try deleteSavedStateRepairMarker(savedStateRepairMarkerURL(id: id))
    }

    private func deleteSavedStateRepairMarker(_ markerURL: URL) throws {
        guard markerURL.standardizedFileURL.deletingLastPathComponent()
                == directoryURL.standardizedFileURL,
              Self.savedStateRepairMarkerIdentity(fileName: markerURL.lastPathComponent) != nil else {
            throw TranscriptionFailureRecoveryError.deleteFailed
        }
        try deleteExactRegularAudio(markerURL)
    }

    private func deleteProcessingCheckpointMarker(id: UUID) throws {
        try deleteProcessingCheckpointMarker(processingCheckpointMarkerURL(id: id))
    }

    private func deleteProcessingCheckpointMarker(_ markerURL: URL) throws {
        guard markerURL.standardizedFileURL.deletingLastPathComponent()
                == directoryURL.standardizedFileURL,
              Self.processingCheckpointMarkerIdentity(
                  fileName: markerURL.lastPathComponent
              ) != nil else {
            throw TranscriptionFailureRecoveryError.deleteFailed
        }
        try deleteExactRegularAudio(markerURL)
    }

    private func deleteProviderDispatchMarker(id: UUID) throws {
        try deleteProviderDispatchMarker(providerDispatchMarkerURL(id: id))
    }

    private func deleteProviderDispatchMarker(
        id: UUID,
        afterRemovingAudioAt audioFileURL: URL
    ) throws {
        guard !fileManager.fileExists(atPath: audioFileURL.path),
              Self.recoveryFileIdentity(
                  fileName: audioFileURL.lastPathComponent
              ) == id,
              !Self.ownedRecoveryAudioFiles(
                  in: directoryURL,
                  fileManager: fileManager
              ).contains(where: { $0.id == id }) else {
            return
        }

        let markerURL = providerDispatchMarkerURL(id: id)
        guard Self.regularNonemptyFile(
            at: markerURL,
            fileManager: fileManager
        ) != nil else {
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let data = try? Data(contentsOf: markerURL),
              let marker = try? decoder.decode(
                  PersistedProcessingCheckpointMarker.self,
                  from: data
              ),
              marker.id == id,
              marker.audioFileName == audioFileURL.lastPathComponent else {
            return
        }

        try deleteProviderDispatchMarker(markerURL)
    }

    private func deleteProviderDispatchMarker(_ markerURL: URL) throws {
        guard markerURL.standardizedFileURL.deletingLastPathComponent()
                == directoryURL.standardizedFileURL,
              Self.providerDispatchMarkerIdentity(
                  fileName: markerURL.lastPathComponent
              ) != nil else {
            throw TranscriptionFailureRecoveryError.deleteFailed
        }
        try deleteExactRegularAudio(markerURL)
    }

    private func savedStateRepairMarkerURL(id: UUID) -> URL {
        directoryURL.appendingPathComponent(
            "\(Self.savedStateRepairMarkerPrefix)\(id.uuidString.lowercased()).json",
            isDirectory: false
        )
    }

    private func processingCheckpointMarkerURL(id: UUID) -> URL {
        directoryURL.appendingPathComponent(
            "\(Self.processingCheckpointMarkerPrefix)\(id.uuidString.lowercased()).json",
            isDirectory: false
        )
    }

    private func providerDispatchMarkerURL(id: UUID) -> URL {
        directoryURL.appendingPathComponent(
            "\(Self.providerDispatchMarkerPrefix)\(id.uuidString.lowercased()).json",
            isDirectory: false
        )
    }

    private var metadataURL: URL {
        directoryURL.appendingPathComponent(metadataFileName, isDirectory: false)
    }

    private func deleteRecoveryAudio(_ fileURL: URL) throws {
        guard fileURL.standardizedFileURL.deletingLastPathComponent() == directoryURL.standardizedFileURL,
              Self.recoveryFileIdentity(fileName: fileURL.lastPathComponent) != nil else {
            throw TranscriptionFailureRecoveryError.deleteFailed
        }

        try deleteExactRegularAudio(fileURL)
    }

    private func deleteExactRegularAudio(_ fileURL: URL) throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        guard Self.regularFile(at: fileURL, fileManager: fileManager) != nil else {
            throw TranscriptionFailureRecoveryError.deleteFailed
        }

        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw TranscriptionFailureRecoveryError.deleteFailed
        }
    }

    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        let applicationSupportRoot = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
            ?? fileManager.temporaryDirectory

        return applicationSupportRoot
            .appendingPathComponent("HoldType", isDirectory: true)
            .appendingPathComponent("TranscriptionRecovery", isDirectory: true)
    }

    private static func fileTimestamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func restoreAttempts(
        from directoryURL: URL,
        metadataFileName: String,
        retentionLimit: Int,
        fileManager: FileManager
    ) -> RecoveryRestoration {
        let metadataURL = directoryURL.appendingPathComponent(metadataFileName, isDirectory: false)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let metadataExists = fileManager.fileExists(atPath: metadataURL.path)
        let decodedRecords = (try? Data(contentsOf: metadataURL)).flatMap {
            try? decoder.decode([PersistedRecoveryAttempt].self, from: $0)
        }
        let records = decodedRecords ?? []

        let ownedAudioFiles = ownedRecoveryAudioFiles(
            in: directoryURL,
            fileManager: fileManager
        )
        let ownedAudioByName = Dictionary(
            uniqueKeysWithValues: ownedAudioFiles.map { ($0.url.lastPathComponent, $0) }
        )
        var repairMarkerIDs = Set<UUID>()
        let repairMarkers = savedStateRepairMarkers(
            in: directoryURL,
            fileManager: fileManager
        ).filter { ownedMarker in
            let marker = ownedMarker.marker
            guard let ownedAudio = ownedAudioByName[marker.audioFileName],
                  ownedAudio.id == marker.id,
                  repairMarkerIDs.insert(marker.id).inserted else {
                return false
            }
            return true
        }
        let repairMarkerByID = Dictionary(
            uniqueKeysWithValues: repairMarkers.map { ($0.marker.id, $0) }
        )
        var checkpointMarkerIDs = Set<UUID>()
        let checkpointMarkers = processingCheckpointMarkers(
            in: directoryURL,
            fileManager: fileManager
        ).filter { ownedMarker in
            let marker = ownedMarker.marker
            guard let ownedAudio = ownedAudioByName[marker.audioFileName],
                  ownedAudio.id == marker.id,
                  checkpointMarkerIDs.insert(marker.id).inserted else {
                return false
            }
            return true
        }
        let checkpointMarkerByID = Dictionary(
            uniqueKeysWithValues: checkpointMarkers.map { ($0.marker.id, $0) }
        )
        var dispatchMarkerIDs = Set<UUID>()
        let dispatchMarkers = providerDispatchMarkers(
            in: directoryURL,
            fileManager: fileManager
        ).filter { ownedMarker in
            let marker = ownedMarker.marker
            guard let ownedAudio = ownedAudioByName[marker.audioFileName],
                  ownedAudio.id == marker.id,
                  dispatchMarkerIDs.insert(marker.id).inserted else {
                return false
            }
            return true
        }
        let dispatchMarkerByID = Dictionary(
            uniqueKeysWithValues: dispatchMarkers.map { ($0.marker.id, $0) }
        )
        var referencedAudioFileNames = Set<String>()
        var requiresPersistence = (metadataExists && decodedRecords == nil)
            || !repairMarkers.isEmpty
            || !checkpointMarkers.isEmpty
            || !dispatchMarkers.isEmpty

        let restoredRecords = records.compactMap { record -> FailedTranscriptionAttempt? in
            guard record.audioFileName == URL(fileURLWithPath: record.audioFileName).lastPathComponent,
                  let ownedAudio = ownedAudioByName[record.audioFileName],
                  ownedAudio.id == record.id,
                  referencedAudioFileNames.insert(record.audioFileName).inserted else {
                requiresPersistence = true
                return nil
            }

            let restoredAttempt = record.attempt(audioFileURL: ownedAudio.url)
            guard restoredAttempt.state != .saved else {
                return restoredAttempt
            }
            if let repairMarker = repairMarkerByID[record.id] {
                return repairMarker.marker.failedAttempt(
                    audioFileURL: ownedAudio.url,
                    fallback: restoredAttempt
                )
            }
            if let dispatchMarker = dispatchMarkerByID[record.id] {
                return dispatchMarker.marker.uncertainAttempt(
                    audioFileURL: ownedAudio.url,
                    fallback: restoredAttempt
                )
            }
            return restoredAttempt
        }

        let defaultSettings = AppSettings.defaults
        let reconstructedAttempts = ownedAudioFiles.compactMap { ownedAudio -> FailedTranscriptionAttempt? in
            guard !referencedAudioFileNames.contains(ownedAudio.url.lastPathComponent) else {
                return nil
            }

            requiresPersistence = true
            if let repairMarker = repairMarkerByID[ownedAudio.id] {
                return repairMarker.marker.failedAttempt(
                    audioFileURL: ownedAudio.url,
                    fallback: nil
                )
            }
            if let dispatchMarker = dispatchMarkerByID[ownedAudio.id] {
                return dispatchMarker.marker.uncertainAttempt(
                    audioFileURL: ownedAudio.url,
                    fallback: nil
                )
            }
            if let checkpointMarker = checkpointMarkerByID[ownedAudio.id] {
                return checkpointMarker.marker.attempt(audioFileURL: ownedAudio.url)
            }
            return FailedTranscriptionAttempt(
                id: ownedAudio.id,
                createdAt: ownedAudio.createdAt,
                updatedAt: ownedAudio.updatedAt,
                audioFileURL: ownedAudio.url,
                audioDuration: nil,
                transcriptionModel: defaultSettings.resolvedTranscriptionModel,
                languageCode: defaultSettings.resolvedLanguageCode,
                completionKind: ownedAudio.completionKind,
                state: .failed,
                reason: .processingInterrupted
            )
        }

        var retainedIDs = Set<UUID>()
        let newestUniqueAttempts = (restoredRecords + reconstructedAttempts)
            .sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
            .filter { retainedIDs.insert($0.id).inserted }
        let retention = retentionSelection(
            newestUniqueAttempts,
            retentionLimit: retentionLimit
        )
        let retainedAttempts = retention.retained
        if retainedAttempts.count != newestUniqueAttempts.count || records.count != restoredRecords.count {
            requiresPersistence = true
        }

        let retainedAudioFileNames = Set(retainedAttempts.map { $0.audioFileURL.lastPathComponent })
        let audioFilesOutsideRetention = ownedAudioFiles
            .map(\.url)
            .filter { !retainedAudioFileNames.contains($0.lastPathComponent) }

        if !metadataExists, !retainedAttempts.isEmpty {
            requiresPersistence = true
        }

        return RecoveryRestoration(
            attempts: retainedAttempts,
            audioFilesOutsideRetention: audioFilesOutsideRetention,
            repairMarkerURLsToDeleteAfterPersistence: repairMarkers.map(\.url),
            checkpointMarkerURLsToDeleteAfterPersistence: checkpointMarkers.map(\.url),
            requiresPersistence: requiresPersistence
        )
    }

    private static func ownedRecoveryAudioFiles(
        in directoryURL: URL,
        fileManager: FileManager
    ) -> [OwnedRecoveryAudioFile] {
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
        ]
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: resourceKeys,
            options: []
        ) else {
            return []
        }

        return fileURLs.compactMap { fileURL in
            guard let identity = recoveryFileDescriptor(
                fileName: fileURL.lastPathComponent
            ),
                  let attributes = regularNonemptyFile(at: fileURL, fileManager: fileManager) else {
                return nil
            }

            let createdAt = attributes.creationDate ?? attributes.contentModificationDate ?? .distantPast
            let updatedAt = attributes.contentModificationDate ?? createdAt
            return OwnedRecoveryAudioFile(
                id: identity.id,
                url: fileURL,
                createdAt: createdAt,
                updatedAt: updatedAt,
                completionKind: identity.completionKind
            )
        }
    }

    private static func savedStateRepairMarkers(
        in directoryURL: URL,
        fileManager: FileManager
    ) -> [OwnedSavedStateRepairMarker] {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return fileURLs.compactMap { markerURL in
            guard let markerID = savedStateRepairMarkerIdentity(
                fileName: markerURL.lastPathComponent
            ),
                regularNonemptyFile(at: markerURL, fileManager: fileManager) != nil,
                let data = try? Data(contentsOf: markerURL),
                let marker = try? decoder.decode(
                    PersistedSavedStateRepairMarker.self,
                    from: data
                ),
                marker.id == markerID,
                marker.audioFileName
                    == URL(fileURLWithPath: marker.audioFileName).lastPathComponent,
                !marker.acceptedTranscriptText
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return OwnedSavedStateRepairMarker(url: markerURL, marker: marker)
        }
    }

    private static func processingCheckpointMarkers(
        in directoryURL: URL,
        fileManager: FileManager
    ) -> [OwnedProcessingCheckpointMarker] {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return fileURLs.compactMap { markerURL in
            guard let markerID = processingCheckpointMarkerIdentity(
                fileName: markerURL.lastPathComponent
            ),
                regularNonemptyFile(at: markerURL, fileManager: fileManager) != nil,
                let data = try? Data(contentsOf: markerURL),
                let marker = try? decoder.decode(
                    PersistedProcessingCheckpointMarker.self,
                    from: data
                ),
                marker.id == markerID,
                marker.audioFileName
                    == URL(fileURLWithPath: marker.audioFileName).lastPathComponent else {
                return nil
            }
            return OwnedProcessingCheckpointMarker(url: markerURL, marker: marker)
        }
    }

    private static func providerDispatchMarkers(
        in directoryURL: URL,
        fileManager: FileManager
    ) -> [OwnedProviderDispatchMarker] {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return fileURLs.compactMap { markerURL in
            guard let markerID = providerDispatchMarkerIdentity(
                fileName: markerURL.lastPathComponent
            ),
                regularNonemptyFile(at: markerURL, fileManager: fileManager) != nil,
                let data = try? Data(contentsOf: markerURL),
                let marker = try? decoder.decode(
                    PersistedProcessingCheckpointMarker.self,
                    from: data
                ),
                marker.id == markerID,
                marker.audioFileName
                    == URL(fileURLWithPath: marker.audioFileName).lastPathComponent else {
                return nil
            }
            return OwnedProviderDispatchMarker(url: markerURL, marker: marker)
        }
    }

    private static func recoveryFileIdentity(fileName: String) -> UUID? {
        recoveryFileDescriptor(fileName: fileName)?.id
    }

    private static func recoveryFileDescriptor(
        fileName: String
    ) -> RecoveryFileDescriptor? {
        let fileURL = URL(fileURLWithPath: fileName)
        guard fileURL.lastPathComponent == fileName,
              !fileURL.pathExtension.isEmpty else {
            return nil
        }

        let stem = fileURL.deletingPathExtension().lastPathComponent
        let prefix: String
        let completionKind: TranscriptionRecoveryCompletionKind
        if stem.hasPrefix("Recording-Max-") {
            prefix = "Recording-Max-"
            completionKind = .maximumDuration
        } else {
            prefix = "Recording-"
            completionKind = .standard
        }
        guard stem.hasPrefix(prefix), stem.count == prefix.count + 15 + 1 + 36 else {
            return nil
        }

        let timestampStart = stem.index(stem.startIndex, offsetBy: prefix.count)
        let timestampEnd = stem.index(timestampStart, offsetBy: 15)
        let timestamp = stem[timestampStart..<timestampEnd]
        guard timestamp[timestamp.index(timestamp.startIndex, offsetBy: 8)] == "-",
              timestamp.enumerated().allSatisfy({ offset, character in
                  offset == 8 ? character == "-" : character.isNumber
              }),
              stem[timestampEnd] == "-" else {
            return nil
        }

        let uuidStart = stem.index(after: timestampEnd)
        guard let id = UUID(uuidString: String(stem[uuidStart...])) else {
            return nil
        }
        return RecoveryFileDescriptor(id: id, completionKind: completionKind)
    }

    private static func savedStateRepairMarkerIdentity(fileName: String) -> UUID? {
        let fileURL = URL(fileURLWithPath: fileName)
        guard fileURL.lastPathComponent == fileName,
              fileURL.pathExtension.lowercased() == "json" else {
            return nil
        }

        let stem = fileURL.deletingPathExtension().lastPathComponent
        guard stem.hasPrefix(savedStateRepairMarkerPrefix) else {
            return nil
        }
        guard let id = UUID(
            uuidString: String(stem.dropFirst(savedStateRepairMarkerPrefix.count))
        ),
            fileName == "\(savedStateRepairMarkerPrefix)\(id.uuidString.lowercased()).json" else {
            return nil
        }
        return id
    }

    private static func processingCheckpointMarkerIdentity(fileName: String) -> UUID? {
        markerIdentity(
            fileName: fileName,
            prefix: processingCheckpointMarkerPrefix
        )
    }

    private static func providerDispatchMarkerIdentity(fileName: String) -> UUID? {
        markerIdentity(
            fileName: fileName,
            prefix: providerDispatchMarkerPrefix
        )
    }

    private static func markerIdentity(fileName: String, prefix: String) -> UUID? {
        let fileURL = URL(fileURLWithPath: fileName)
        guard fileURL.lastPathComponent == fileName,
              fileURL.pathExtension == "json" else {
            return nil
        }

        let stem = fileURL.deletingPathExtension().lastPathComponent
        guard stem.hasPrefix(prefix),
              let id = UUID(uuidString: String(stem.dropFirst(prefix.count))),
              fileName == "\(prefix)\(id.uuidString.lowercased()).json" else {
            return nil
        }
        return id
    }

    private static func regularNonemptyFile(
        at fileURL: URL,
        fileManager: FileManager
    ) -> URLResourceValues? {
        guard let values = regularFile(at: fileURL, fileManager: fileManager),
              let fileSize = values.fileSize,
              fileSize > 0 else {
            return nil
        }

        return values
    }

    private static func regularFile(
        at fileURL: URL,
        fileManager: FileManager
    ) -> URLResourceValues? {
        guard fileManager.fileExists(atPath: fileURL.path),
              let values = try? fileURL.resourceValues(forKeys: [
                  .isRegularFileKey,
                  .isSymbolicLinkKey,
                  .fileSizeKey,
                  .creationDateKey,
                  .contentModificationDateKey,
              ]),
              values.isSymbolicLink != true,
              values.isRegularFile == true else {
            return nil
        }

        return values
    }
}

private struct RecoveryRestoration {
    let attempts: [FailedTranscriptionAttempt]
    let audioFilesOutsideRetention: [URL]
    let repairMarkerURLsToDeleteAfterPersistence: [URL]
    let checkpointMarkerURLsToDeleteAfterPersistence: [URL]
    let requiresPersistence: Bool
}

private struct OwnedRecoveryAudioFile {
    let id: UUID
    let url: URL
    let createdAt: Date
    let updatedAt: Date
    let completionKind: TranscriptionRecoveryCompletionKind
}

private struct RecoveryFileDescriptor {
    let id: UUID
    let completionKind: TranscriptionRecoveryCompletionKind
}

private struct OwnedSavedStateRepairMarker {
    let url: URL
    let marker: PersistedSavedStateRepairMarker
}

private struct OwnedProcessingCheckpointMarker {
    let url: URL
    let marker: PersistedProcessingCheckpointMarker
}

private struct OwnedProviderDispatchMarker {
    let url: URL
    let marker: PersistedProcessingCheckpointMarker
}

private struct PersistedProcessingCheckpointMarker: Codable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let audioFileName: String
    let audioDuration: TimeInterval?
    let transcriptionModel: String
    let languageCode: String?
    let completionKind: TranscriptionRecoveryCompletionKind

    init(_ attempt: FailedTranscriptionAttempt) {
        id = attempt.id
        createdAt = attempt.createdAt
        updatedAt = attempt.updatedAt
        audioFileName = attempt.audioFileURL.lastPathComponent
        audioDuration = attempt.audioDuration
        transcriptionModel = attempt.transcriptionModel
        languageCode = attempt.languageCode
        completionKind = attempt.completionKind
    }

    func attempt(audioFileURL: URL) -> FailedTranscriptionAttempt {
        return FailedTranscriptionAttempt(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            audioFileURL: audioFileURL,
            audioDuration: audioDuration,
            transcriptionModel: transcriptionModel,
            languageCode: languageCode,
            completionKind: completionKind,
            state: .processing,
            reason: .other
        )
    }

    func uncertainAttempt(
        audioFileURL: URL,
        fallback: FailedTranscriptionAttempt?
    ) -> FailedTranscriptionAttempt {
        FailedTranscriptionAttempt(
            id: id,
            createdAt: fallback?.createdAt ?? createdAt,
            updatedAt: max(fallback?.updatedAt ?? updatedAt, updatedAt),
            audioFileURL: audioFileURL,
            audioDuration: fallback?.audioDuration ?? audioDuration,
            transcriptionModel: fallback?.transcriptionModel ?? transcriptionModel,
            languageCode: fallback?.languageCode ?? languageCode,
            completionKind: fallback?.completionKind ?? completionKind,
            state: .failed,
            reason: .providerOutcomeUncertain,
            retryCount: fallback?.retryCount ?? 0
        )
    }
}

private struct PersistedSavedStateRepairMarker: Codable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let audioFileName: String
    let audioDuration: TimeInterval?
    let transcriptionModel: String
    let languageCode: String?
    let completionKind: TranscriptionRecoveryCompletionKind?
    let acceptedTranscriptText: String
    let reason: FailedTranscriptionReason?

    init(_ attempt: FailedTranscriptionAttempt) {
        id = attempt.id
        createdAt = attempt.createdAt
        updatedAt = attempt.updatedAt
        audioFileName = attempt.audioFileURL.lastPathComponent
        audioDuration = attempt.audioDuration
        transcriptionModel = attempt.transcriptionModel
        languageCode = attempt.languageCode
        completionKind = attempt.completionKind
        acceptedTranscriptText = attempt.acceptedTranscriptText ?? ""
        reason = attempt.state == .saved
            ? (
                attempt.reason == .postProcessingFailedAfterProviderAcceptance
                    ? .postProcessingFailedAfterProviderAcceptance
                    : .savedStatePersistenceFailed
            )
            : attempt.reason
    }

    func failedAttempt(
        audioFileURL: URL,
        fallback: FailedTranscriptionAttempt?
    ) -> FailedTranscriptionAttempt {
        // Once the main index has durably recorded that OpenAI accepted the
        // audio and a downstream stage failed, an older repair marker must
        // not downgrade that truthful terminal state on relaunch. This can
        // happen when the marker rewrite fails but Recovery.json succeeds.
        let restoredReason = fallback?.reason
            == .postProcessingFailedAfterProviderAcceptance
            ? .postProcessingFailedAfterProviderAcceptance
            : reason ?? .savedStatePersistenceFailed
        return FailedTranscriptionAttempt(
            id: id,
            createdAt: fallback?.createdAt ?? createdAt,
            updatedAt: max(fallback?.updatedAt ?? updatedAt, updatedAt),
            audioFileURL: audioFileURL,
            audioDuration: fallback?.audioDuration ?? audioDuration,
            transcriptionModel: fallback?.transcriptionModel ?? transcriptionModel,
            languageCode: fallback?.languageCode ?? languageCode,
            completionKind: fallback?.completionKind
                ?? completionKind
                ?? .maximumDuration,
            state: .failed,
            reason: restoredReason,
            retryCount: fallback?.retryCount ?? 0,
            acceptedTranscriptText: acceptedTranscriptText
        )
    }
}

private struct PersistedRecoveryAttempt: Codable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let audioFileName: String
    let audioDuration: TimeInterval?
    let transcriptionModel: String
    let languageCode: String?
    let completionKind: TranscriptionRecoveryCompletionKind?
    let state: TranscriptionRecoveryState
    let reason: FailedTranscriptionReason
    let retryCount: Int
    let acceptedTranscriptText: String?

    init(_ attempt: FailedTranscriptionAttempt) {
        id = attempt.id
        createdAt = attempt.createdAt
        updatedAt = attempt.updatedAt
        audioFileName = attempt.audioFileURL.lastPathComponent
        audioDuration = attempt.audioDuration
        transcriptionModel = attempt.transcriptionModel
        languageCode = attempt.languageCode
        completionKind = attempt.completionKind
        state = attempt.state
        reason = attempt.reason
        retryCount = attempt.retryCount
        acceptedTranscriptText = attempt.acceptedTranscriptText
    }

    func attempt(audioFileURL: URL) -> FailedTranscriptionAttempt {
        FailedTranscriptionAttempt(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            audioFileURL: audioFileURL,
            audioDuration: audioDuration,
            transcriptionModel: transcriptionModel,
            languageCode: languageCode,
            completionKind: completionKind ?? .standard,
            state: state,
            reason: reason,
            retryCount: retryCount,
            acceptedTranscriptText: acceptedTranscriptText
        )
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
