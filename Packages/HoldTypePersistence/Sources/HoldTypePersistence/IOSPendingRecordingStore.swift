import Foundation
import HoldTypeDomain

protocol IOSPendingRecordingDestinationInspecting: Sendable {
    func hasCanonicalDestination(
        attemptID: UUID,
        transcriptionID: UUID
    ) throws -> Bool
}

private struct ClosureIOSPendingRecordingDestinationInspector:
    IOSPendingRecordingDestinationInspecting {
    let canonicalDestinationExists: @Sendable (UUID, UUID) throws -> Bool

    func hasCanonicalDestination(
        attemptID: UUID,
        transcriptionID: UUID
    ) throws -> Bool {
        try canonicalDestinationExists(attemptID, transcriptionID)
    }
}

private struct UnconfiguredIOSPendingRecordingDestinationInspector:
    IOSPendingRecordingDestinationInspecting {
    func hasCanonicalDestination(
        attemptID: UUID,
        transcriptionID: UUID
    ) throws -> Bool {
        throw IOSPendingRecordingError.invalidTransition
    }
}

private struct IOSPendingRecordingDispatchIdentity: Hashable, Sendable {
    let attemptID: UUID
    let transcriptionID: UUID
}

final class IOSPendingRecordingLiveOwnerRegistry: @unchecked Sendable {
    static let shared = IOSPendingRecordingLiveOwnerRegistry()

    private let lock = NSLock()
    private var identities: Set<IOSPendingRecordingDispatchIdentity> = []
    private var retiredIdentities: [UUID: Set<UUID>] = [:]

    func register(attemptID: UUID, transcriptionID: UUID) {
        _ = lock.withLock {
            identities.insert(
                IOSPendingRecordingDispatchIdentity(
                    attemptID: attemptID,
                    transcriptionID: transcriptionID
                )
            )
        }
    }

    func contains(attemptID: UUID, transcriptionID: UUID) -> Bool {
        lock.withLock {
            identities.contains(
                IOSPendingRecordingDispatchIdentity(
                    attemptID: attemptID,
                    transcriptionID: transcriptionID
                )
            )
        }
    }

    func hasLiveOwner(attemptID: UUID) -> Bool {
        lock.withLock {
            identities.contains { $0.attemptID == attemptID }
        }
    }

    func isRetired(attemptID: UUID, transcriptionID: UUID) -> Bool {
        lock.withLock {
            retiredIdentities[attemptID]?.contains(transcriptionID) == true
        }
    }

    func retire(attemptID: UUID, transcriptionID: UUID) {
        lock.withLock {
            _ = identities.remove(
                IOSPendingRecordingDispatchIdentity(
                    attemptID: attemptID,
                    transcriptionID: transcriptionID
                )
            )
            _ = retiredIdentities[attemptID, default: []].insert(
                transcriptionID
            )
        }
    }

    func clearRetired(attemptID: UUID) {
        lock.withLock {
            _ = retiredIdentities.removeValue(forKey: attemptID)
        }
    }
}

/// Owns the one app-private pending recording transaction for the app process.
public actor IOSPendingRecordingStore {
    private static let processOperationGate = IOSPendingRecordingOperationGate()

    private struct ActiveDispatchIdentity: Equatable, Sendable {
        let attemptID: UUID
        let transcriptionID: UUID
    }

    private let journal: any IOSPendingRecordingJournalStoring
    private let audioFileSystem: any IOSPendingRecordingAudioFileSystem
    private let destinationInspector: any IOSPendingRecordingDestinationInspecting
    private let operationGate: IOSPendingRecordingOperationGate
    private let liveOwnerRegistry: IOSPendingRecordingLiveOwnerRegistry
    private let now: @Sendable () -> Date

    private var activeDispatchIdentity: ActiveDispatchIdentity?
    private var activeDispatchAuthorization: IOSPendingTranscriptionAuthorization?

    public init(applicationSupportDirectoryURL: URL) {
        journal = FoundationIOSPendingRecordingJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        audioFileSystem = FoundationIOSPendingRecordingAudioFileSystem(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        destinationInspector = UnconfiguredIOSPendingRecordingDestinationInspector()
        operationGate = Self.processOperationGate
        liveOwnerRegistry = .shared
        now = { Date() }
    }

    public init(
        applicationSupportDirectoryURL: URL,
        canonicalDestinationExists:
            @escaping @Sendable (UUID, UUID) throws -> Bool
    ) {
        journal = FoundationIOSPendingRecordingJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        audioFileSystem = FoundationIOSPendingRecordingAudioFileSystem(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        destinationInspector = ClosureIOSPendingRecordingDestinationInspector(
            canonicalDestinationExists: canonicalDestinationExists
        )
        operationGate = Self.processOperationGate
        liveOwnerRegistry = .shared
        now = { Date() }
    }

    init(
        journal: any IOSPendingRecordingJournalStoring,
        audioFileSystem: any IOSPendingRecordingAudioFileSystem,
        destinationInspector: any IOSPendingRecordingDestinationInspecting =
            UnconfiguredIOSPendingRecordingDestinationInspector(),
        operationGate: IOSPendingRecordingOperationGate =
            IOSPendingRecordingStore.processOperationGate,
        liveOwnerRegistry: IOSPendingRecordingLiveOwnerRegistry =
            IOSPendingRecordingLiveOwnerRegistry(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.journal = journal
        self.audioFileSystem = audioFileSystem
        self.destinationInspector = destinationInspector
        self.operationGate = operationGate
        self.liveOwnerRegistry = liveOwnerRegistry
        self.now = now
    }

    public func prepare(
        _ preparation: IOSPendingRecordingPreparation
    ) async throws -> IOSPendingRecording {
        try await performExclusiveOperation { [self] in
            try await performPrepare(preparation)
        }
    }

    public func load() async throws -> IOSPendingRecordingObservation? {
        try await performExclusiveOperation { [self] in
            try await performLoad()
        }
    }

    public func beginTranscription(
        expected: IOSPendingRecordingCASExpectation,
        transcriptionID: UUID
    ) async throws -> IOSPendingTranscriptionHandoff {
        try await performExclusiveOperation { [self] in
            try await performBeginTranscription(
                expected: expected,
                transcriptionID: transcriptionID
            )
        }
    }

    public func retryTranscription(
        expected: IOSPendingRecordingCASExpectation,
        transcriptionID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSPendingTranscriptionHandoff {
        try await performExclusiveOperation { [self] in
            try await performRetryTranscription(
                expected: expected,
                transcriptionID: transcriptionID,
                transcriptionConfiguration: transcriptionConfiguration
            )
        }
    }

    public func markPostProcessing(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await performExclusiveOperation { [self] in
            try await performAdvance(
                expected: expected,
                source: .transcribing,
                destination: .postProcessing
            )
        }
    }

    public func markOutputDelivery(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await performExclusiveOperation { [self] in
            try await performAdvance(
                expected: expected,
                source: .postProcessing,
                destination: .outputDelivery
            )
        }
    }

    public func markAwaitingRecovery(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await performExclusiveOperation { [self] in
            try await performMarkAwaitingRecovery(expected: expected)
        }
    }

    /// Converts an uncertain pre-destination phase into explicit recovery.
    /// The containing-app composition root must call this only after relaunch.
    public func recoverAfterProcessLoss(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await performExclusiveOperation { [self] in
            try await performRecoverAfterProcessLoss(expected: expected)
        }
    }

    public func discard(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecordingDiscardResult {
        try await performExclusiveOperation { [self] in
            try await performDiscard(expected: expected)
        }
    }
}

private extension IOSPendingRecordingStore {
    func performExclusiveOperation<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            return try await operationGate.perform(operation)
        } catch IOSPendingRecordingOperationGate.AcquisitionError.cancelledBeforeLease {
            throw IOSPendingRecordingError.cancelledBeforeOperation
        } catch IOSPendingRecordingOperationGate.AcquisitionError.reentrantOperation {
            throw IOSPendingRecordingError.reentrantOperation
        }
    }

    func performPrepare(
        _ preparation: IOSPendingRecordingPreparation
    ) async throws -> IOSPendingRecording {
        guard try journal.load() == nil else {
            throw IOSPendingRecordingError.pendingSlotOccupied
        }
        do {
            try await audioFileSystem.requireEmptyNamespace()
        } catch {
            throw mapAudioError(error, operation: .inspect)
        }

        let lease: any IOSPendingRecordingPublishedAudioLease
        do {
            lease = try await audioFileSystem.publishProtectedCopy(
                from: preparation.sourceArtifact,
                attemptID: preparation.attemptID,
                format: preparation.audioFormat,
                durationMilliseconds: preparation.durationMilliseconds
            )
        } catch {
            throw mapAudioError(error, operation: .publish)
        }
        defer { lease.release() }

        let timestamp = try canonicalNow(after: nil)
        let recording = try IOSPendingRecording(
            attemptID: preparation.attemptID,
            audioRelativeIdentifier: lease.relativeIdentifier,
            createdAt: timestamp,
            updatedAt: timestamp,
            phase: preparation.initialState.phase,
            outputIntent: preparation.outputIntent,
            transcriptionID: nil,
            transcriptionModel: preparation.transcriptionModel,
            transcriptionLanguageCode: preparation.transcriptionLanguageCode,
            durationMilliseconds: lease.durationMilliseconds,
            byteCount: lease.audioArtifact.byteCount
        )

        do {
            _ = try await lease.revalidate()
        } catch {
            throw mapAudioError(error, operation: .validate)
        }
        do {
            try journal.create(recording)
        } catch let error as IOSPendingRecordingError {
            throw error
        } catch {
            throw IOSPendingRecordingError.journalWriteFailed
        }
        do {
            _ = try await lease.revalidate()
        } catch {
            throw mapAudioError(error, operation: .validate)
        }
        return recording
    }

    func performLoad() async throws -> IOSPendingRecordingObservation? {
        guard let recording = try journal.load() else {
            do {
                try await audioFileSystem.requireEmptyNamespace()
                return nil
            } catch {
                throw mapAudioError(error, operation: .inspect)
            }
        }

        let availability: IOSPendingRecordingAvailability
        do {
            _ = try await validatedAudio(for: recording)
            availability = .available
        } catch IOSPendingRecordingError.dataProtectionUnavailable {
            availability = .temporarilyUnavailable
        } catch IOSPendingRecordingError.linkedAudioMissing {
            availability = .missing
        } catch {
            availability = .invalid
        }
        return IOSPendingRecordingObservation(
            recording: recording,
            availability: availability
        )
    }

    func performBeginTranscription(
        expected: IOSPendingRecordingCASExpectation,
        transcriptionID: UUID
    ) async throws -> IOSPendingTranscriptionHandoff {
        let current = try requireCurrent(expected: expected)
        guard current.phase == .readyForTranscription,
              current.transcriptionID == nil else {
            if current.phase == .transcribing,
               current.transcriptionID == transcriptionID {
                throw IOSPendingRecordingError.dispatchAlreadyCommitted
            }
            throw IOSPendingRecordingError.invalidTransition
        }

        _ = try await validatedAudio(for: current)
        let updated = try replacing(
            current,
            phase: .transcribing,
            transcriptionID: transcriptionID,
            transcriptionModel: current.transcriptionModel,
            transcriptionLanguageCode: current.transcriptionLanguageCode
        )
        try journal.replace(updated, expected: current)
        liveOwnerRegistry.register(
            attemptID: updated.attemptID,
            transcriptionID: transcriptionID
        )
        let authorization = IOSPendingTranscriptionAuthorization()
        activeDispatchIdentity = ActiveDispatchIdentity(
            attemptID: updated.attemptID,
            transcriptionID: transcriptionID
        )
        activeDispatchAuthorization = authorization
        let artifact = try await validateCommittedHandoffOrRecover(updated)
        return IOSPendingTranscriptionHandoff(
            dispatch: IOSPendingTranscriptionDispatch(
                recording: updated,
                audioArtifact: artifact
            ),
            authorization: authorization
        )
    }

    func performRetryTranscription(
        expected: IOSPendingRecordingCASExpectation,
        transcriptionID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSPendingTranscriptionHandoff {
        let current = try requireCurrent(expected: expected)
        guard current.phase == .awaitingRecovery,
              current.transcriptionID == nil,
              !liveOwnerRegistry.hasLiveOwner(attemptID: current.attemptID),
              !liveOwnerRegistry.isRetired(
                  attemptID: current.attemptID,
                  transcriptionID: transcriptionID
              ) else {
            if current.phase == .transcribing,
               current.transcriptionID == transcriptionID {
                throw IOSPendingRecordingError.dispatchAlreadyCommitted
            }
            throw IOSPendingRecordingError.invalidTransition
        }

        let model = transcriptionConfiguration.resolvedModel
        let languageCode = transcriptionConfiguration.resolvedLanguageCode
        guard !transcriptionConfiguration.customLanguageCodeValidation.isInvalid,
              IOSPendingRecordingValidation.isValidModel(model),
              IOSPendingRecordingValidation.isValidLanguageCode(languageCode) else {
            throw IOSPendingRecordingError.invalidTranscriptionConfiguration
        }

        _ = try await validatedAudio(for: current)
        let updated = try replacing(
            current,
            phase: .transcribing,
            transcriptionID: transcriptionID,
            transcriptionModel: model,
            transcriptionLanguageCode: languageCode
        )
        try journal.replace(updated, expected: current)
        liveOwnerRegistry.register(
            attemptID: updated.attemptID,
            transcriptionID: transcriptionID
        )
        let authorization = IOSPendingTranscriptionAuthorization()
        activeDispatchIdentity = ActiveDispatchIdentity(
            attemptID: updated.attemptID,
            transcriptionID: transcriptionID
        )
        activeDispatchAuthorization = authorization
        let artifact = try await validateCommittedHandoffOrRecover(updated)
        return IOSPendingTranscriptionHandoff(
            dispatch: IOSPendingTranscriptionDispatch(
                recording: updated,
                audioArtifact: artifact
            ),
            authorization: authorization
        )
    }

    func performAdvance(
        expected: IOSPendingRecordingCASExpectation,
        source: IOSPendingRecordingPhase,
        destination: IOSPendingRecordingPhase
    ) throws -> IOSPendingRecording {
        let current = try requireCurrent(expected: expected)
        if current.phase == destination {
            try confirmJournalDurability(current)
            return current
        }
        guard current.phase == source,
              let transcriptionID = current.transcriptionID,
              activeDispatchIdentity == ActiveDispatchIdentity(
                  attemptID: current.attemptID,
                  transcriptionID: transcriptionID
              ) else {
            throw IOSPendingRecordingError.invalidTransition
        }

        let updated = try replacing(
            current,
            phase: destination,
            transcriptionID: transcriptionID,
            transcriptionModel: current.transcriptionModel,
            transcriptionLanguageCode: current.transcriptionLanguageCode
        )
        try journal.replace(updated, expected: current)
        return updated
    }

    func performMarkAwaitingRecovery(
        expected: IOSPendingRecordingCASExpectation
    ) throws -> IOSPendingRecording {
        let current = try requireCurrent(expected: expected)
        if current.phase == .awaitingRecovery {
            try confirmJournalDurability(current)
            if activeDispatchIdentity?.attemptID == current.attemptID {
                retireActiveDispatchIfOwned(attemptID: current.attemptID)
            }
            return current
        }
        guard current.phase == .transcribing || current.phase == .postProcessing,
              let transcriptionID = current.transcriptionID,
              activeDispatchIdentity == ActiveDispatchIdentity(
                  attemptID: current.attemptID,
                  transcriptionID: transcriptionID
              ) else {
            throw IOSPendingRecordingError.invalidTransition
        }

        let updated = try replacing(
            current,
            phase: .awaitingRecovery,
            transcriptionID: nil,
            transcriptionModel: current.transcriptionModel,
            transcriptionLanguageCode: current.transcriptionLanguageCode
        )
        // This is the linearization point against a concurrent handoff
        // execute: no provider operation may start after cancellation begins.
        activeDispatchAuthorization?.retireAndCancel()
        try journal.replace(updated, expected: current)
        liveOwnerRegistry.retire(
            attemptID: current.attemptID,
            transcriptionID: transcriptionID
        )
        activeDispatchAuthorization = nil
        activeDispatchIdentity = nil
        return updated
    }

    func retireActiveDispatchIfOwned(attemptID: UUID) {
        guard let activeDispatchIdentity,
              activeDispatchIdentity.attemptID == attemptID else {
            return
        }
        liveOwnerRegistry.retire(
            attemptID: activeDispatchIdentity.attemptID,
            transcriptionID: activeDispatchIdentity.transcriptionID
        )
        activeDispatchAuthorization?.retireAndCancel()
        activeDispatchAuthorization = nil
        self.activeDispatchIdentity = nil
    }

    func performRecoverAfterProcessLoss(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        let current = try requireCurrent(expected: expected)
        if current.phase == .awaitingRecovery {
            try confirmJournalDurability(current)
            return current
        }
        guard current.phase == .transcribing
                || current.phase == .postProcessing
                || current.phase == .outputDelivery,
              let transcriptionID = current.transcriptionID,
              activeDispatchIdentity == nil,
              !liveOwnerRegistry.contains(
                  attemptID: current.attemptID,
                  transcriptionID: transcriptionID
              ) else {
            throw IOSPendingRecordingError.invalidTransition
        }
        let hasCanonicalDestination: Bool
        do {
            hasCanonicalDestination = try destinationInspector
                .hasCanonicalDestination(
                    attemptID: current.attemptID,
                    transcriptionID: transcriptionID
                )
        } catch {
            throw IOSPendingRecordingError.destinationInspectionFailed
        }
        guard !hasCanonicalDestination else {
            throw IOSPendingRecordingError.invalidTransition
        }

        let updated = try replacing(
            current,
            phase: .awaitingRecovery,
            transcriptionID: nil,
            transcriptionModel: current.transcriptionModel,
            transcriptionLanguageCode: current.transcriptionLanguageCode
        )
        liveOwnerRegistry.retire(
            attemptID: current.attemptID,
            transcriptionID: transcriptionID
        )
        try journal.replace(updated, expected: current)
        return updated
    }

    func performDiscard(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecordingDiscardResult {
        guard let current = try journal.load() else {
            liveOwnerRegistry.clearRetired(attemptID: expected.attemptID)
            return .alreadyAbsent
        }
        try requireExpectation(expected, matches: current)
        guard current.phase == .readyForTranscription
                || current.phase == .awaitingRecovery,
              activeDispatchIdentity == nil,
              !liveOwnerRegistry.hasLiveOwner(attemptID: current.attemptID) else {
            throw IOSPendingRecordingError.invalidTransition
        }

        do {
            _ = try await audioFileSystem.removePublishedAudioIfPresent(
                relativeIdentifier: current.audioRelativeIdentifier,
                attemptID: current.attemptID,
                expectedByteCount: current.byteCount
            )
        } catch {
            throw mapAudioError(error, operation: .remove)
        }

        do {
            _ = try journal.remove(expected: current)
        } catch let error as IOSPendingRecordingError {
            throw error
        } catch {
            throw IOSPendingRecordingError.journalRemoveFailed
        }
        liveOwnerRegistry.clearRetired(attemptID: current.attemptID)
        return .discarded
    }

    func requireCurrent(
        expected: IOSPendingRecordingCASExpectation
    ) throws -> IOSPendingRecording {
        guard let current = try journal.load() else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        try requireExpectation(expected, matches: current)
        return current
    }

    func requireExpectation(
        _ expected: IOSPendingRecordingCASExpectation,
        matches current: IOSPendingRecording
    ) throws {
        guard expected == IOSPendingRecordingCASExpectation(recording: current) else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
    }

    func validatedAudio(
        for recording: IOSPendingRecording
    ) async throws -> AudioRecordingArtifact {
        do {
            return try await audioFileSystem.validatePublishedAudio(
                relativeIdentifier: recording.audioRelativeIdentifier,
                attemptID: recording.attemptID,
                durationMilliseconds: recording.durationMilliseconds,
                byteCount: recording.byteCount
            )
        } catch {
            throw mapAudioError(error, operation: .validate)
        }
    }

    func validateCommittedHandoffOrRecover(
        _ recording: IOSPendingRecording
    ) async throws -> AudioRecordingArtifact {
        do {
            return try await validatedAudio(for: recording)
        } catch {
            let validationError = error
            _ = try performMarkAwaitingRecovery(
                expected: IOSPendingRecordingCASExpectation(recording: recording)
            )
            throw validationError
        }
    }

    func replacing(
        _ current: IOSPendingRecording,
        phase: IOSPendingRecordingPhase,
        transcriptionID: UUID?,
        transcriptionModel: String,
        transcriptionLanguageCode: String?
    ) throws -> IOSPendingRecording {
        try IOSPendingRecording(
            attemptID: current.attemptID,
            audioRelativeIdentifier: current.audioRelativeIdentifier,
            createdAt: current.createdAt,
            updatedAt: canonicalNow(after: current.updatedAt),
            phase: phase,
            outputIntent: current.outputIntent,
            transcriptionID: transcriptionID,
            transcriptionModel: transcriptionModel,
            transcriptionLanguageCode: transcriptionLanguageCode,
            durationMilliseconds: current.durationMilliseconds,
            byteCount: current.byteCount
        )
    }

    func canonicalNow(after priorDate: Date?) throws -> Date {
        let candidate = try IOSPendingRecordingTimestampCodec.canonicalDate(from: now())
        guard let priorDate, candidate < priorDate else {
            return candidate
        }
        return priorDate
    }

    func confirmJournalDurability(
        _ recording: IOSPendingRecording
    ) throws {
        // Another Store actor may have observed a post-rename failure from the
        // actor that wrote these bytes. Rewriting every same-phase result makes
        // durability confirmation process-independent and keeps side effects
        // behind a successful directory synchronization.
        try journal.replace(recording, expected: recording)
    }
}

private extension IOSPendingRecordingStore {
    enum AudioOperation {
        case inspect
        case publish
        case validate
        case remove
    }

    func mapAudioError(
        _ error: Error,
        operation: AudioOperation
    ) -> IOSPendingRecordingError {
        guard let error = error as? IOSPendingRecordingAudioFileSystemError else {
            switch operation {
            case .inspect:
                return .orphanedAudio
            case .publish:
                return .audioPublicationFailed
            case .validate:
                return .linkedAudioInvalid
            case .remove:
                return .audioRemoveFailed
            }
        }

        switch error {
        case .namespaceNotEmpty:
            return .orphanedAudio
        case .namespaceUnavailable:
            switch operation {
            case .inspect:
                return .journalUnreadable
            case .publish:
                return .audioPublicationFailed
            case .validate:
                return .linkedAudioInvalid
            case .remove:
                return .audioRemoveFailed
            }
        case .sourceUnavailable:
            return .sourceUnavailable
        case .invalidSource:
            return .invalidSourceArtifact
        case .sourceChanged:
            return .sourceChanged
        case .invalidDuration:
            return .mediaValidationFailed
        case .destinationConflict:
            return .protectedAudioConflict
        case .writeFailed, .synchronizationFailed:
            return operation == .remove ? .audioRemoveFailed : .audioPublicationFailed
        case .mediaValidationFailed:
            return .mediaValidationFailed
        case .mediaValidationTimedOut:
            return .mediaValidationTimedOut
        case .operationTimedOut:
            return operation == .publish
                ? .audioPublicationTimedOut
                : .dataProtectionUnavailable
        case .operationCancelled:
            return operation == .publish
                ? .audioPublicationFailed
                : .dataProtectionUnavailable
        case .protectedAudioMissing:
            return .linkedAudioMissing
        case .protectedAudioInvalid:
            return .linkedAudioInvalid
        case .dataProtectionUnavailable:
            return .dataProtectionUnavailable
        case .removeFailed:
            return .audioRemoveFailed
        }
    }
}
