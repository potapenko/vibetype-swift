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

enum FailedTranscriptionReason: Equatable {
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
             .other:
            return nil
        }
    }

    var canRetry: Bool {
        switch self {
        case .cancelled, .invalidRecording:
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

struct FailedTranscriptionAttempt: Equatable, Identifiable {
    typealias ID = UUID

    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    let audioFileURL: URL
    let audioDuration: TimeInterval?
    let transcriptionModel: String
    let languageCode: String?
    var reason: FailedTranscriptionReason
    var retryCount: Int

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        audioFileURL: URL,
        audioDuration: TimeInterval?,
        transcriptionModel: String,
        languageCode: String?,
        reason: FailedTranscriptionReason,
        retryCount: Int = 0
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
        self.reason = reason
        self.retryCount = max(0, retryCount)
    }
}

@MainActor
protocol TranscriptionFailureRecoveryRecording: AnyObject {
    var failedAttempts: [FailedTranscriptionAttempt] { get }

    func recordFailedAttempt(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        reason: FailedTranscriptionReason
    ) throws -> FailedTranscriptionAttempt?
    func updateFailedAttempt(id: FailedTranscriptionAttempt.ID, reason: FailedTranscriptionReason) throws
    func removeFailedAttempt(id: FailedTranscriptionAttempt.ID)
    func clear()
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

        guard fileManager.fileExists(atPath: audioFileURL.path) else {
            throw TranscriptionFailureRecoveryError.audioUnavailable
        }

        let id = uuidProvider()
        let createdAt = now()
        let recoveryAudioURL = try moveAudioForRecovery(
            sourceURL: audioFileURL,
            id: id,
            createdAt: createdAt
        )
        let attempt = FailedTranscriptionAttempt(
            id: id,
            createdAt: createdAt,
            audioFileURL: recoveryAudioURL,
            audioDuration: audioDuration,
            transcriptionModel: settings.resolvedTranscriptionModel,
            languageCode: settings.resolvedLanguageCode,
            reason: reason
        )

        failedAttempts = try retainedFailedAttempts([attempt] + failedAttempts)
        return attempt
    }

    func updateFailedAttempt(id: FailedTranscriptionAttempt.ID, reason: FailedTranscriptionReason) throws {
        guard let index = failedAttempts.firstIndex(where: { $0.id == id }) else {
            throw TranscriptionFailureRecoveryError.attemptUnavailable
        }

        failedAttempts[index].reason = reason
        failedAttempts[index].retryCount += 1
        failedAttempts[index].updatedAt = now()
        failedAttempts = failedAttempts.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    func removeFailedAttempt(id: FailedTranscriptionAttempt.ID) {
        guard let attempt = failedAttempts.first(where: { $0.id == id }) else {
            return
        }

        try? deleteRecoveryAudio(attempt.audioFileURL)
        failedAttempts.removeAll { $0.id == id }
    }

    func clear() {
        for attempt in failedAttempts {
            try? deleteRecoveryAudio(attempt.audioFileURL)
        }
        failedAttempts = []
    }

    private func moveAudioForRecovery(sourceURL: URL, id: UUID, createdAt: Date) throws -> URL {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw TranscriptionFailureRecoveryError.directoryUnavailable
        }

        let destinationURL = directoryURL
            .appendingPathComponent("Failed-\(Self.fileTimestamp(from: createdAt))-\(id.uuidString.lowercased())")
            .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension)

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                return destinationURL
            } catch {
                throw TranscriptionFailureRecoveryError.saveFailed
            }
        }
    }

    private func retainedFailedAttempts(
        _ attempts: [FailedTranscriptionAttempt]
    ) throws -> [FailedTranscriptionAttempt] {
        let newestFirstAttempts = attempts.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }

        let retainedAttempts = Array(newestFirstAttempts.prefix(retentionLimit))
        for attempt in newestFirstAttempts.dropFirst(retentionLimit) {
            try deleteRecoveryAudio(attempt.audioFileURL)
        }

        return retainedAttempts
    }

    private func deleteRecoveryAudio(_ fileURL: URL) throws {
        guard fileURL.standardizedFileURL.path.hasPrefix(directoryURL.standardizedFileURL.path + "/") else {
            throw TranscriptionFailureRecoveryError.deleteFailed
        }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw TranscriptionFailureRecoveryError.deleteFailed
        }
    }

    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        let cachesRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        return cachesRoot
            .appendingPathComponent("HoldType", isDirectory: true)
            .appendingPathComponent("FailedTranscriptionRecovery", isDirectory: true)
    }

    private static func fileTimestamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
