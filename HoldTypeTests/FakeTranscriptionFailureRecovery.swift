//
//  FakeTranscriptionFailureRecovery.swift
//  HoldTypeTests
//
//  Created by Codex on 7/18/26.
//

import Foundation
@testable import HoldType

@MainActor
final class FakeTranscriptionFailureRecovery: TranscriptionFailureRecoveryRecording {
    private(set) var failedAttempts: [FailedTranscriptionAttempt]
    private let recordFailedAttemptError: (any Error)?
    private let onRecordFailedAttempt: () -> Void

    init(
        initialAttempts: [FailedTranscriptionAttempt] = [],
        recordFailedAttemptError: (any Error)? = nil,
        onRecordFailedAttempt: @escaping () -> Void = {}
    ) {
        failedAttempts = initialAttempts
        self.recordFailedAttemptError = recordFailedAttemptError
        self.onRecordFailedAttempt = onRecordFailedAttempt
    }

    func recordProcessingCheckpoint(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        completionKind: TranscriptionRecoveryCompletionKind
    ) throws -> FailedTranscriptionAttempt {
        onRecordFailedAttempt()
        if let recordFailedAttemptError {
            throw recordFailedAttemptError
        }

        let attempt = FailedTranscriptionAttempt(
            audioFileURL: audioFileURL,
            audioDuration: audioDuration,
            transcriptionModel: settings.resolvedTranscriptionModel,
            languageCode: settings.resolvedLanguageCode,
            completionKind: completionKind,
            state: .processing,
            reason: .other
        )
        failedAttempts = [attempt] + failedAttempts
        return attempt
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

        let checkpoint = try recordProcessingCheckpoint(
            audioFileURL: audioFileURL,
            settings: settings,
            audioDuration: audioDuration
        )
        try updateFailedAttempt(id: checkpoint.id, reason: reason)
        return failedAttempts.first { $0.id == checkpoint.id }
    }

    func retainEmergencyFallback(
        audioFileURL: URL,
        settings: AppSettings,
        audioDuration: TimeInterval?,
        reason: FailedTranscriptionReason,
        completionKind: TranscriptionRecoveryCompletionKind
    ) -> FailedTranscriptionAttempt? {
        let attempt = FailedTranscriptionAttempt(
            audioFileURL: audioFileURL,
            audioDuration: audioDuration,
            transcriptionModel: settings.resolvedTranscriptionModel,
            languageCode: settings.resolvedLanguageCode,
            completionKind: completionKind,
            state: .failed,
            reason: reason
        )
        failedAttempts = [attempt] + failedAttempts
        return attempt
    }

    func markSaved(
        id: FailedTranscriptionAttempt.ID,
        acceptedTranscriptText: String
    ) throws {
        guard let index = failedAttempts.firstIndex(where: { $0.id == id }),
              failedAttempts[index].completionKind == .maximumDuration,
              failedAttempts[index].state == .processing
                || failedAttempts[index].state == .failed else {
            throw TranscriptionFailureRecoveryError.attemptUnavailable
        }

        failedAttempts[index].state = .saved
        failedAttempts[index].acceptedTranscriptText = acceptedTranscriptText
        failedAttempts[index].updatedAt = Date()
    }

    func markProviderOutcomeUncertain(id: FailedTranscriptionAttempt.ID) {
        guard let index = failedAttempts.firstIndex(where: { $0.id == id }) else {
            return
        }
        failedAttempts[index].state = .failed
        failedAttempts[index].reason = .providerOutcomeUncertain
        failedAttempts[index].updatedAt = Date()
    }

    func markAcceptedHistoryCommitFailed(id: FailedTranscriptionAttempt.ID) {
        guard let index = failedAttempts.firstIndex(where: { $0.id == id }) else {
            return
        }
        failedAttempts[index].state = .failed
        failedAttempts[index].reason = .savedStatePersistenceFailed
        failedAttempts[index].updatedAt = Date()
    }

    func updateFailedAttempt(id: FailedTranscriptionAttempt.ID, reason: FailedTranscriptionReason) throws {
        guard let index = failedAttempts.firstIndex(where: { $0.id == id }) else {
            throw TranscriptionFailureRecoveryError.attemptUnavailable
        }

        let wasFailed = failedAttempts[index].state == .failed
        failedAttempts[index].state = .failed
        failedAttempts[index].reason = reason
        if wasFailed {
            failedAttempts[index].retryCount += 1
        }
        failedAttempts[index].updatedAt = Date()
    }

    @discardableResult
    func removeFailedAttempt(id: FailedTranscriptionAttempt.ID) throws -> Bool {
        let previousCount = failedAttempts.count
        failedAttempts.removeAll { $0.id == id }
        return failedAttempts.count != previousCount
    }

}
