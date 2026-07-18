import Foundation
import HoldTypeDomain

extension IOSVoiceStateRepository {
    @discardableResult
    func beginProcessing(
        attemptID: UUID,
        operationID: UUID,
        stage: IOSVoiceStateProcessingStage = .transcription,
        allowFailed: Bool
    ) throws -> IOSVoiceStatePending {
        var snapshot = try load()
        let pending = try requirePending(attemptID, in: snapshot)
        switch pending.status {
        case .ready where !allowFailed,
             .failed where allowFailed
                && pending.transcriptionCheckpoint == nil
                && !pending.transcriptionReplayBlocked:
            break
        case .ready, .failed, .processing, .acceptedCleanup:
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        let updated = try pending.replacing(
            status: .processing(stage, operationID: operationID),
            updatedAt: mutationDate(after: pending.updatedAt)
        )
        snapshot.pending = updated
        try replace(snapshot)
        return updated
    }

    @discardableResult
    func beginRetry(
        attemptID: UUID,
        operationID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration
    ) throws -> IOSVoiceStatePending {
        var snapshot = try load()
        let pending = try requirePending(attemptID, in: snapshot)
        guard pending.status == .failed,
              pending.transcriptionCheckpoint == nil,
              !pending.transcriptionReplayBlocked else {
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        let updated = try pending.replacing(
            transcriptionConfiguration: transcriptionConfiguration,
            status: .processing(
                .transcription,
                operationID: operationID
            ),
            updatedAt: mutationDate(after: pending.updatedAt)
        )
        snapshot.pending = updated
        try replace(snapshot)
        return updated
    }

    /// Starts a fresh downstream attempt from the already accepted durable
    /// transcript. It never changes transcription settings or creates audio
    /// provider authority.
    @discardableResult
    func beginPostProcessingRetry(
        attemptID: UUID,
        operationID: UUID
    ) throws -> IOSVoiceStatePending {
        var snapshot = try load()
        let pending = try requirePending(attemptID, in: snapshot)
        guard pending.status == .failed,
              let checkpoint = pending.transcriptionCheckpoint,
              checkpoint.stage != .translationInFlight else {
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        let updated = try pending.replacing(
            status: .processing(
                .postProcessing,
                operationID: operationID
            ),
            updatedAt: mutationDate(after: pending.updatedAt)
        )
        snapshot.pending = updated
        try replace(snapshot)
        return updated
    }

    /// Atomically persists the normalized transcription before any downstream
    /// stage. Repeating the exact confirmed transition is idempotent.
    @discardableResult
    func checkpointTranscription(
        attemptID: UUID,
        operationID: UUID,
        text: String
    ) throws -> IOSVoiceStatePending {
        var snapshot = try load()
        let pending = try requirePending(attemptID, in: snapshot)
        let checkpoint = try IOSVoiceStateTranscriptionCheckpoint(
            operationID: operationID,
            acceptedTranscript: text
        )
        if case .processing(.postProcessing, let currentOperationID) =
            pending.status,
           currentOperationID == operationID,
           pending.transcriptionCheckpoint == checkpoint {
            return pending
        }
        guard case .processing(.transcription, let currentOperationID) =
                pending.status,
              currentOperationID == operationID,
              pending.transcriptionCheckpoint == nil else {
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        let updated = try pending.replacing(
            status: .processing(
                .postProcessing,
                operationID: operationID
            ),
            transcriptionCheckpoint: checkpoint,
            updatedAt: mutationDate(after: pending.updatedAt)
        )
        snapshot.pending = updated
        try replace(snapshot)
        return updated
    }

    /// Advances the exact durable text boundary without changing the original
    /// transcription/usage identity. Every accepted text is validated before
    /// the atomic replacement, and exact repeats are idempotent.
    @discardableResult
    func checkpointPostProcessing(
        attemptID: UUID,
        operationID: UUID,
        stage: IOSVoiceStateTextCheckpointStage,
        text: String
    ) throws -> IOSVoiceStatePending {
        var snapshot = try load()
        let pending = try requirePending(attemptID, in: snapshot)
        guard case .processing(.postProcessing, let currentOperationID) =
                pending.status,
              currentOperationID == operationID,
              let current = pending.transcriptionCheckpoint else {
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        let checkpoint = try current.advancing(to: stage, text: text)
        if checkpoint == current { return pending }
        let updated = try pending.replacing(
            status: pending.status,
            transcriptionCheckpoint: checkpoint,
            updatedAt: mutationDate(after: pending.updatedAt)
        )
        snapshot.pending = updated
        try replace(snapshot)
        return updated
    }

    @discardableResult
    func advanceProcessing(
        attemptID: UUID,
        operationID: UUID,
        to stage: IOSVoiceStateProcessingStage
    ) throws -> IOSVoiceStatePending {
        var snapshot = try load()
        let pending = try requirePending(attemptID, in: snapshot)
        guard case .processing(
                  let currentStage,
                  let currentOperationID
              ) = pending.status,
              currentOperationID == operationID,
              (currentStage, stage) == (.transcription, .postProcessing)
                || (currentStage, stage) == (.postProcessing, .outputDelivery)
                || currentStage == stage else {
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        if stage == .outputDelivery,
           let checkpoint = pending.transcriptionCheckpoint,
           checkpoint.stage != .outputReady {
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        let updated = try pending.replacing(
            status: .processing(stage, operationID: operationID),
            updatedAt: mutationDate(after: pending.updatedAt)
        )
        snapshot.pending = updated
        try replace(snapshot)
        return updated
    }

    @discardableResult
    func markFailed(
        attemptID: UUID,
        transcriptionReplayBlocked: Bool = false
    ) throws -> IOSVoiceStatePending {
        var snapshot = try load()
        let pending = try requirePending(attemptID, in: snapshot)
        switch pending.status {
        case .ready, .processing, .failed:
            break
        case .acceptedCleanup:
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        let blocksReplay = pending.transcriptionReplayBlocked
            || transcriptionReplayBlocked
        if pending.status == .failed,
           pending.transcriptionReplayBlocked == blocksReplay {
            return pending
        }
        let updated = try pending.replacing(
            status: .failed,
            transcriptionReplayBlocked: blocksReplay,
            updatedAt: mutationDate(after: pending.updatedAt)
        )
        snapshot.pending = updated
        try replace(snapshot)
        return updated
    }

    /// Commits Latest and the accepted-cleanup owner in one atomic replacement.
    @discardableResult
    func commitAccepted(
        attemptID: UUID,
        resultID: UUID,
        text: String,
        createdAt: Date
    ) throws -> IOSVoiceStateAcceptedResult {
        var snapshot = try load()
        let pending = try requirePending(attemptID, in: snapshot)
        let latest = try IOSVoiceStateLatest(
            resultID: resultID,
            sourceAttemptID: attemptID,
            text: text,
            createdAt: createdAt
        )
        let accepted = IOSVoiceStateAcceptedResult(
            resultID: resultID,
            sourceAttemptID: attemptID,
            text: latest.text,
            createdAt: latest.createdAt
        )
        if case .acceptedCleanup(let current) = pending.status {
            guard current == accepted, snapshot.latest == latest else {
                throw IOSVoiceStateRepositoryError.invalidTransition
            }
            return current
        }
        guard case .processing(.outputDelivery, _) = pending.status else {
            throw IOSVoiceStateRepositoryError.invalidTransition
        }
        snapshot.latest = latest
        snapshot.pending = try pending.replacing(
            status: .acceptedCleanup(accepted),
            updatedAt: mutationDate(after: pending.updatedAt)
        )
        try replace(snapshot)
        return accepted
    }

    @discardableResult
    func finishAcceptedCleanup(
        attemptID: UUID,
        resultID: UUID
    ) throws -> IOSVoiceStateMutationResult {
        var snapshot = try load()
        guard let pending = snapshot.pending else {
            return .unchanged(snapshot)
        }
        guard pending.attemptID == attemptID,
              case .acceptedCleanup(let accepted) = pending.status,
              accepted.resultID == resultID else {
            throw IOSVoiceStateRepositoryError.stalePending
        }
        snapshot.pending = nil
        try replace(snapshot)
        return .changed(snapshot)
    }

    @discardableResult
    func discardPending(
        attemptID: UUID
    ) throws -> IOSVoiceStateMutationResult {
        var snapshot = try load()
        guard let pending = snapshot.pending else {
            return .unchanged(snapshot)
        }
        guard pending.attemptID == attemptID else {
            throw IOSVoiceStateRepositoryError.stalePending
        }
        guard case .acceptedCleanup = pending.status else {
            snapshot.pending = nil
            try replace(snapshot)
            return .changed(snapshot)
        }
        throw IOSVoiceStateRepositoryError.invalidTransition
    }

    /// Relaunch performs only local state repair; it never owns provider work.
    @discardableResult
    func reconcileAfterLaunch() throws -> IOSVoiceStateSnapshot {
        var snapshot = try load()
        guard let pending = snapshot.pending,
              case .processing = pending.status else {
            return snapshot
        }
        let blocksReplay = pending.transcriptionCheckpoint == nil
        snapshot.pending = try pending.replacing(
            status: .failed,
            transcriptionReplayBlocked: blocksReplay,
            updatedAt: mutationDate(after: pending.updatedAt)
        )
        try replace(snapshot)
        return snapshot
    }

    private func requirePending(
        _ attemptID: UUID,
        in snapshot: IOSVoiceStateSnapshot
    ) throws -> IOSVoiceStatePending {
        guard let pending = snapshot.pending,
              pending.attemptID == attemptID else {
            throw IOSVoiceStateRepositoryError.stalePending
        }
        return pending
    }
}
