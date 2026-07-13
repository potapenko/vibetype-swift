import Foundation
import HoldTypeDomain

/// The exact durable `transcribing` owner and its one-shot provider handoff.
/// It exposes no store, path, descriptor, or reusable provider authority.
@_spi(HoldTypeIOSCore)
public struct IOSForegroundVoiceTranscriptionDispatch: Sendable {
    public let recording: IOSPendingRecording

    private let handoff: IOSPendingTranscriptionHandoff

    init(_ commit: IOSPendingTranscriptionCommit) {
        recording = commit.recording
        handoff = commit.handoff
    }

    public var expectation: IOSPendingRecordingCASExpectation {
        IOSPendingRecordingCASExpectation(recording: recording)
    }

    public func execute(
        using executor: any IOSPendingTranscriptionExecutor
    ) async throws -> String {
        try await handoff.execute(using: executor)
    }
}

extension IOSForegroundVoiceTranscriptionDispatch:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSForegroundVoiceTranscriptionDispatch(redacted)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Process-owned Persistence boundary for one foreground attempt lifetime.
/// Every operation is routed through the exact canonical Pending actor and the
/// matching app-only or coordinator-captured accepted-output transaction from
/// one physical-root process context.
@_spi(HoldTypeIOSCore)
public struct IOSForegroundVoicePersistenceOwner: Sendable {
    private let pendingRecordingStore: IOSPendingRecordingStore
    private let acceptedOutputPersistence: IOSForegroundVoicePersistence
    private let captureSourceOwner: IOSForegroundVoiceCaptureSourceOwner?

    public init(applicationSupportDirectoryURL: URL) {
        self.init(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            registry: .shared
        )
    }

    init(
        applicationSupportDirectoryURL: URL,
        registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry
    ) {
        let context = registry.context(for: applicationSupportDirectoryURL)
        pendingRecordingStore = context.pendingRecordingStore
        captureSourceOwner = context.foregroundVoiceCaptureSourceOwner
        acceptedOutputPersistence = IOSForegroundVoicePersistence(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            registry: registry,
            context: context
        )
    }

    init(
        pendingRecordingStore: IOSPendingRecordingStore,
        acceptedOutputPersistence: IOSForegroundVoicePersistence
    ) {
        self.pendingRecordingStore = pendingRecordingStore
        self.acceptedOutputPersistence = acceptedOutputPersistence
        captureSourceOwner = nil
    }

    public func createCapture(
        attemptID: UUID,
        outputIntent: DictationOutputIntent
    ) async throws -> IOSForegroundVoiceCaptureSourceLease {
        guard let captureSourceOwner else {
            throw IOSForegroundVoiceCaptureSourceError.namespaceUnavailable
        }
        return try await captureSourceOwner.createCapture(
            attemptID: attemptID,
            outputIntent: outputIntent
        )
    }

    public func reconcileCaptureSourcesAtLaunch() async
        -> IOSForegroundVoiceCaptureRecoveryObservation {
        guard let captureSourceOwner else {
            return IOSForegroundVoiceCaptureRecoveryObservation(
                status: .blockedUnknown,
                examinedEntryCount: 0,
                removedEntryCount: 0,
                removedLogicalByteCount: 0
            )
        }
        return await pendingRecordingStore.reconcileCaptureSourcesAtLaunch(
            owner: captureSourceOwner
        )
    }

    #if DEBUG
    /// Legacy fixture-only path. Production Voice code cannot compile against
    /// ordinary path-based preparation.
    public func prepare(
        _ preparation: IOSPendingRecordingPreparation
    ) async throws -> IOSPendingRecording {
        try await pendingRecordingStore.prepare(preparation)
    }
    #endif

    public func prepareCompletedCapture(
        _ capture: IOSForegroundVoiceCompletedCapture,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSPendingRecording {
        try await pendingRecordingStore.prepareCompletedCapture(
            capture,
            transcriptionConfiguration: transcriptionConfiguration
        )
    }

    public func recoverCapture(
        _ capability: IOSForegroundVoiceCaptureRecoveryCapability,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSForegroundVoiceCaptureRecoveryResult {
        try await pendingRecordingStore.recoverCapture(
            capability,
            transcriptionConfiguration: transcriptionConfiguration
        )
    }

    public func discardCapture(
        _ capability: IOSForegroundVoiceCaptureRecoveryCapability
    ) async throws {
        try await pendingRecordingStore.discardCapture(capability)
    }

    public func load() async throws -> IOSPendingRecordingObservation? {
        try await pendingRecordingStore.load()
    }

    public func beginTranscription(
        expected: IOSPendingRecordingCASExpectation,
        transcriptionID: UUID
    ) async throws -> IOSForegroundVoiceTranscriptionDispatch {
        let commit = try await pendingRecordingStore
            .beginTranscriptionCommit(
                expected: expected,
                transcriptionID: transcriptionID
            )
        return IOSForegroundVoiceTranscriptionDispatch(commit)
    }

    public func retryTranscription(
        expected: IOSPendingRecordingCASExpectation,
        transcriptionID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSForegroundVoiceTranscriptionDispatch {
        let commit = try await pendingRecordingStore
            .retryTranscriptionCommit(
                expected: expected,
                transcriptionID: transcriptionID,
                transcriptionConfiguration: transcriptionConfiguration
            )
        return IOSForegroundVoiceTranscriptionDispatch(commit)
    }

    public func markPostProcessing(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await pendingRecordingStore.markPostProcessing(expected: expected)
    }

    public func markOutputDelivery(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await pendingRecordingStore.markOutputDelivery(expected: expected)
    }

    public func markAwaitingRecovery(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await pendingRecordingStore.markAwaitingRecovery(expected: expected)
    }

    public func recoverAfterProcessLoss(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await pendingRecordingStore.recoverAfterProcessLoss(
            expected: expected
        )
    }

    public func discard(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecordingDiscardResult {
        try await pendingRecordingStore.discard(expected: expected)
    }

    public func accept(
        _ preparation: IOSForegroundVoiceAcceptedOutputPreparation,
        expectedPending: IOSPendingRecordingCASExpectation
    ) async throws -> IOSForegroundVoiceAcceptanceResult {
        switch preparation.historyMode {
        case .appOnly:
            try await acceptedOutputPersistence.accept(
                preparation,
                expectedPending: expectedPending
            )
        case .captured:
            try await acceptedOutputPersistence.acceptCapturedHistory(
                preparation,
                expectedPending: expectedPending
            )
        }
    }

    public func retrySavingResult(
        expected: IOSForegroundVoiceSavingResultExpectation
    ) async throws -> IOSForegroundVoiceAcceptanceResult {
        try await acceptedOutputPersistence.retrySavingResult(
            expected: expected
        )
    }

    public func recoverRecordingFromSavingResult(
        expected: IOSForegroundVoiceSavingResultExpectation
    ) async throws -> IOSPendingRecording {
        try await acceptedOutputPersistence.recoverRecordingFromSavingResult(
            expected: expected
        )
    }

    public func loadLatestResult()
        async throws -> IOSForegroundVoiceLatestResultObservation {
        try await acceptedOutputPersistence.loadLatestResult()
    }

    /// Reconciles an uncertain app-only acceptance without letting a caller
    /// weaken Persistence's exact destination and accepted-bytes invariants.
    public func reconcileAcceptance(
        matching preparation: IOSForegroundVoiceAcceptedOutputPreparation
    ) async throws -> IOSForegroundVoiceAcceptanceResult? {
        try await acceptedOutputPersistence.reconcileAcceptance(
            matching: preparation
        )
    }

    public func clearLatestResult(
        expected: IOSAcceptedOutputDeliveryExpectation
    ) async throws -> IOSForegroundVoiceClearResult {
        try await acceptedOutputPersistence.clearLatestResult(
            expected: expected
        )
    }

    public func retryLatestResultCleanup()
        async throws -> IOSForegroundVoiceClearResult {
        try await acceptedOutputPersistence.retryLatestResultCleanup()
    }
}

extension IOSForegroundVoicePersistenceOwner:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSForegroundVoicePersistenceOwner(redacted)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
