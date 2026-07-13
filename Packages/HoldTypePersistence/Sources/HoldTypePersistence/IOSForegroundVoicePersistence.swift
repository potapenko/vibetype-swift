import Foundation
import HoldTypeDomain

/// Opaque foreground History ownership carried between Core and Persistence.
/// The captured value exposes no policy generation or mutable History state.
@_spi(HoldTypeIOSCore)
public enum IOSForegroundVoiceHistoryMode: Equatable, Sendable {
    case appOnly
    case captured(IOSAcceptedOutputHistoryCapture)
}

/// The foreground accepted-output input. Its public initializer remains
/// strictly P4 app-only; Core may carry only a coordinator-minted capture.
public struct IOSForegroundVoiceAcceptedOutputPreparation: Equatable, Sendable {
    let deliveryPreparation: IOSAcceptedOutputDeliveryPreparation

    public var deliveryID: UUID { deliveryPreparation.deliveryID }
    public var sessionID: UUID { deliveryPreparation.sessionID }
    public var attemptID: UUID { deliveryPreparation.attemptID }
    public var transcriptID: UUID { deliveryPreparation.transcriptID }
    public var outputIntent: DictationOutputIntent {
        deliveryPreparation.outputIntent
    }
    public var keepLatestResult: Bool {
        deliveryPreparation.keepLatestResult
    }

    @_spi(HoldTypeIOSCore)
    public var historyMode: IOSForegroundVoiceHistoryMode {
        guard let capture = deliveryPreparation.historyCapture else {
            return .appOnly
        }
        return .captured(capture)
    }

    public init(
        deliveryID: UUID,
        sessionID: UUID,
        attemptID: UUID,
        transcriptID: UUID,
        rawAcceptedText: String,
        outputIntent: DictationOutputIntent,
        keepLatestResult: Bool
    ) throws {
        deliveryPreparation = try IOSAcceptedOutputDeliveryPreparation(
            deliveryID: deliveryID,
            sessionID: sessionID,
            attemptID: attemptID,
            transcriptID: transcriptID,
            rawAcceptedText: rawAcceptedText,
            outputIntent: outputIntent,
            automaticInsertionPreferenceEnabled: false,
            keepLatestResult: keepLatestResult,
            historyWrite: nil
        )
    }

    @_spi(HoldTypeIOSCore)
    public init(
        deliveryID: UUID,
        sessionID: UUID,
        attemptID: UUID,
        transcriptID: UUID,
        rawAcceptedText: String,
        outputIntent: DictationOutputIntent,
        keepLatestResult: Bool,
        historyMode: IOSForegroundVoiceHistoryMode
    ) throws {
        switch historyMode {
        case .appOnly:
            deliveryPreparation = try IOSAcceptedOutputDeliveryPreparation(
                deliveryID: deliveryID,
                sessionID: sessionID,
                attemptID: attemptID,
                transcriptID: transcriptID,
                rawAcceptedText: rawAcceptedText,
                outputIntent: outputIntent,
                automaticInsertionPreferenceEnabled: false,
                keepLatestResult: keepLatestResult,
                historyWrite: nil
            )
        case .captured(let capture):
            deliveryPreparation = try IOSAcceptedOutputDeliveryPreparation(
                deliveryID: deliveryID,
                sessionID: sessionID,
                attemptID: attemptID,
                transcriptID: transcriptID,
                rawAcceptedText: rawAcceptedText,
                outputIntent: outputIntent,
                automaticInsertionPreferenceEnabled: false,
                keepLatestResult: keepLatestResult,
                historyCapture: capture
            )
        }
    }
}

public struct IOSForegroundVoiceSavingResultExpectation: Equatable, Sendable {
    public let deliveryID: UUID
    public let sessionID: UUID
    public let attemptID: UUID
    public let transcriptID: UUID

    init(preparation: IOSAcceptedOutputDeliveryPreparation) {
        deliveryID = preparation.deliveryID
        sessionID = preparation.sessionID
        attemptID = preparation.attemptID
        transcriptID = preparation.transcriptID
    }
}

public enum IOSForegroundVoiceAcceptanceResult: Equatable, Sendable {
    case resultReady(IOSAcceptedOutputDeliveryRecord)
    case savingResult(IOSForegroundVoiceSavingResultExpectation)
    case expired(IOSAcceptedOutputDeliveryExpectation)
    case clockRollbackAmbiguous(IOSAcceptedOutputDeliveryExpectation)
}

public enum IOSForegroundVoiceLatestResultObservation: Equatable, Sendable {
    case absent
    case resultReady(IOSAcceptedOutputDeliveryRecord)
    case savingResult(
        IOSForegroundVoiceSavingResultExpectation,
        priorResult: IOSAcceptedOutputDeliveryRecord?
    )
    case expired(IOSAcceptedOutputDeliveryExpectation)
    case clockRollbackAmbiguous(IOSAcceptedOutputDeliveryExpectation)
    case clearedCleanupPending
}

public enum IOSForegroundVoiceClearResult: Equatable, Sendable {
    case cleared
    case alreadyAbsent
    case clearedCleanupPending
}

public enum IOSForegroundVoicePersistenceError: Error, Equatable, Sendable {
    case cancelledBeforeOperation
    case reentrantOperation
    case repositoryIdentityConflict
    case localRecoveryPending
    case invalidPendingOwner
    case noSavingResult
    case savingResultIdentityMismatch
    case savingResultPending
}

struct IOSForegroundVoicePersistenceWork: Equatable, Sendable {
    enum RetirementOrigin: Equatable, Sendable {
        case liveProcess
        case processLoss
    }

    let preparation: IOSAcceptedOutputDeliveryPreparation
    let pendingRecording: IOSPendingRecording
    let retirementOrigin: RetirementOrigin

    var expectation: IOSForegroundVoiceSavingResultExpectation {
        IOSForegroundVoiceSavingResultExpectation(preparation: preparation)
    }

    func matches(
        _ expectation: IOSForegroundVoiceSavingResultExpectation
    ) -> Bool {
        self.expectation == expectation
    }
}

actor IOSForegroundVoicePersistenceOperationState {
    private var work: IOSForegroundVoicePersistenceWork?
    private var retirementCompleted = false

    func begin(
        _ candidate: IOSForegroundVoicePersistenceWork
    ) throws -> IOSForegroundVoicePersistenceWork {
        if let work {
            guard work == candidate else {
                throw IOSForegroundVoicePersistenceError
                    .savingResultIdentityMismatch
            }
            return work
        }
        work = candidate
        retirementCompleted = false
        return candidate
    }

    func current() -> IOSForegroundVoicePersistenceWork? { work }

    func hasCompletedRetirement(
        matching expectation: IOSForegroundVoiceSavingResultExpectation
    ) throws -> Bool {
        guard let work else { return false }
        guard work.matches(expectation) else {
            throw IOSForegroundVoicePersistenceError
                .savingResultIdentityMismatch
        }
        return retirementCompleted
    }

    func markRetirementCompleted(
        matching expectation: IOSForegroundVoiceSavingResultExpectation
    ) throws {
        guard let work, work.matches(expectation) else {
            throw IOSForegroundVoicePersistenceError
                .savingResultIdentityMismatch
        }
        retirementCompleted = true
    }

    func clear(
        matching expectation: IOSForegroundVoiceSavingResultExpectation
    ) throws {
        guard let work else { return }
        guard work.matches(expectation) else {
            throw IOSForegroundVoicePersistenceError
                .savingResultIdentityMismatch
        }
        self.work = nil
        retirementCompleted = false
    }
}

struct IOSForegroundVoiceAcceptedDestinationAuthorization: Sendable {
    let record: IOSAcceptedOutputDeliveryRecord
    let snapshot: IOSAcceptedOutputDeliveryJournalSnapshot
    let storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    func provesDestination(
        for recording: IOSPendingRecording,
        storeIdentity expectedStoreIdentity:
            IOSAcceptedOutputDeliveryStoreIdentity,
        ownerIdentity expectedOwnerIdentity:
            IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization expectedLease:
            IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        record == snapshot.record
            && storeIdentity == expectedStoreIdentity
            && operationLeaseAuthorization.provesSameActiveLease(
                as: expectedLease
            )
            && ownerIdentity == expectedOwnerIdentity
            && record.isExactForegroundVoiceDestination(for: recording)
    }
}

/// Exact current-process proof that the accepted-History coordinator already
/// committed the mandatory foreground destination for one captured attempt.
/// Unlike the P4 authorization, this proof never performs an identical
/// delivery rewrite because a retained History recovery capability may still
/// be bound to the current physical snapshot. This is current-process
/// authority only; relaunch retirement continues through canonical destination
/// evidence instead of reconstructing a captured capability.
struct IOSForegroundVoiceCapturedDestinationAuthorization: Sendable {
    let record: IOSAcceptedOutputDeliveryRecord
    let snapshot: IOSAcceptedOutputDeliveryJournalSnapshot
    let preparation: IOSAcceptedOutputDeliveryPreparation
    let storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    func provesDestination(
        for recording: IOSPendingRecording,
        storeIdentity expectedStoreIdentity:
            IOSAcceptedOutputDeliveryStoreIdentity,
        ownerIdentity expectedOwnerIdentity:
            IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization expectedLease:
            IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        record == snapshot.record
            && storeIdentity == expectedStoreIdentity
            && operationLeaseAuthorization.provesSameActiveLease(
                as: expectedLease
            )
            && ownerIdentity == expectedOwnerIdentity
            && preparation.historyCapture?.ownerIdentity == ownerIdentity
            && preparation.historyCapture?.policyReceipt
                .capabilityOwnerIdentity == ownerIdentity
            && record.isExactForegroundVoiceCapturedDestination(
                for: recording,
                preparation: preparation
            )
    }
}

struct IOSForegroundVoiceNoDestinationAuthorization: Sendable {
    let preparation: IOSAcceptedOutputDeliveryPreparation
    let pendingRecording: IOSPendingRecording
    let storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    func provesAbsence(
        for recording: IOSPendingRecording,
        storeIdentity expectedStoreIdentity:
            IOSAcceptedOutputDeliveryStoreIdentity,
        ownerIdentity expectedOwnerIdentity:
            IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization expectedLease:
            IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        storeIdentity == expectedStoreIdentity
            && operationLeaseAuthorization.provesSameActiveLease(
                as: expectedLease
            )
            && ownerIdentity == expectedOwnerIdentity
            && pendingRecording == recording
            && preparation.attemptID == recording.attemptID
            && preparation.transcriptID == recording.transcriptionID
            && preparation.outputIntent == recording.outputIntent
    }
}

struct IOSForegroundVoicePendingAudioRemovalAuthorization: Sendable {
    let recording: IOSPendingRecording
    let storeIdentity: IOSPendingRecordingStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    func provesRemoval(
        for candidate: IOSPendingRecording,
        storeIdentity expectedStoreIdentity: IOSPendingRecordingStoreIdentity,
        ownerIdentity expectedOwnerIdentity:
            IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization expectedLease:
            IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        recording == candidate
            && storeIdentity == expectedStoreIdentity
            && ownerIdentity == expectedOwnerIdentity
            && operationLeaseAuthorization.provesSameActiveLease(
                as: expectedLease
            )
    }
}

extension IOSAcceptedOutputDeliveryRecord {
    var isForegroundVoiceAppOnlyRecord: Bool {
        failedRetryID == nil
            && publicationGeneration == 0
            && !automaticInsertionPreferenceEnabled
            && historyWrite == nil
            && (deliveryState == .pending || deliveryState == .discarded)
    }

    func isExactForegroundVoiceDestination(
        for recording: IOSPendingRecording
    ) -> Bool {
        isForegroundVoiceAppOnlyRecord
            && deliveryState == .pending
            && acceptedText != nil
            && attemptID == recording.attemptID
            && transcriptID == recording.transcriptionID
            && outputIntent == recording.outputIntent
    }

    func isExactForegroundVoiceCapturedDestination(
        for recording: IOSPendingRecording,
        preparation: IOSAcceptedOutputDeliveryPreparation
    ) -> Bool {
        guard preparation.historyCapture != nil,
              !preparation.automaticInsertionPreferenceEnabled,
              preparation.attemptID == recording.attemptID,
              preparation.transcriptID == recording.transcriptionID,
              preparation.outputIntent == recording.outputIntent,
              recording.phase == .outputDelivery,
              failedRetryID == nil,
              publicationGeneration == 0,
              !automaticInsertionPreferenceEnabled,
              deliveryState == .pending,
              keepLatestResult == preparation.keepLatestResult,
              hasSameAcceptance(as: preparation) else {
            return false
        }
        guard let historyWrite else {
            return preparation.historyWrite == nil
        }
        return IOSAcceptedOutputDeliveryValidation.bytesEqual(
            historyWrite.transcriptionModel,
            recording.transcriptionModel
        )
            && historyWrite.transcriptionLanguageCode
                == recording.transcriptionLanguageCode
            && historyWrite.durationMilliseconds
                == recording.durationMilliseconds
    }

    func foregroundVoicePreparation()
        throws -> IOSAcceptedOutputDeliveryPreparation {
        guard isForegroundVoiceAppOnlyRecord,
              deliveryState == .pending,
              let acceptedText else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        return try IOSAcceptedOutputDeliveryPreparation(
            deliveryID: deliveryID,
            sessionID: sessionID,
            attemptID: attemptID,
            transcriptID: transcriptID,
            rawAcceptedText: acceptedText,
            outputIntent: outputIntent,
            automaticInsertionPreferenceEnabled: false,
            keepLatestResult: keepLatestResult,
            historyWrite: nil
        )
    }
}

private extension IOSAcceptedOutputDeliveryExpectation {
    func matchesForegroundVoiceIdentity(
        _ preparation: IOSAcceptedOutputDeliveryPreparation
    ) -> Bool {
        deliveryID == preparation.deliveryID
            && sessionID == preparation.sessionID
            && attemptID == preparation.attemptID
            && transcriptID == preparation.transcriptID
            && failedRetryID == nil
    }

    func overlapsPendingIdentity(
        _ recording: IOSPendingRecording
    ) -> Bool {
        attemptID == recording.attemptID
            || recording.transcriptionID.map { transcriptID == $0 } == true
    }
}

private extension IOSAcceptedOutputDeliveryObservation {
    func overlapsPendingIdentity(
        _ recording: IOSPendingRecording
    ) -> Bool {
        switch self {
        case .active(let record):
            IOSAcceptedOutputDeliveryExpectation(record: record)
                .overlapsPendingIdentity(recording)
        case .expired(let expectation),
             .clockRollbackAmbiguous(let expectation):
            expectation.overlapsPendingIdentity(recording)
        }
    }
}

/// Canonical P4 app-only accepted-output and PendingRecording transaction.
/// It performs no History, outbox, bridge, or keyboard operation.
public struct IOSForegroundVoicePersistence: Sendable {
    private let operationGate: IOSPersistenceOperationGate
    private let pendingRecordingStore: IOSPendingRecordingStore
    private let deliveryStore: IOSAcceptedOutputDeliveryStore
    private let state: IOSForegroundVoicePersistenceOperationState
    private let productionContext:
        IOSAcceptedHistoryCoordinatorProcessContext?
    private let repositoryRegistration:
        IOSAcceptedHistoryCoordinatorRepositoryRegistration?

    public init(applicationSupportDirectoryURL: URL) {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry
            .shared
        let context = registry.context(for: applicationSupportDirectoryURL)
        self.init(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            registry: registry,
            context: context
        )
    }

    init(
        applicationSupportDirectoryURL: URL,
        registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry,
        context: IOSAcceptedHistoryCoordinatorProcessContext
    ) {
        operationGate = context.operationGate
        pendingRecordingStore = context.pendingRecordingStore
        deliveryStore = context.deliveryStore
        state = context.foregroundVoicePersistenceState
        productionContext = context
        repositoryRegistration =
            IOSAcceptedHistoryCoordinatorRepositoryRegistration(
                registry: registry,
                context: context,
                applicationSupportDirectoryURL:
                    applicationSupportDirectoryURL
            )
    }

    init(
        operationGate: IOSPersistenceOperationGate,
        pendingRecordingStore: IOSPendingRecordingStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        state: IOSForegroundVoicePersistenceOperationState =
            IOSForegroundVoicePersistenceOperationState()
    ) {
        self.operationGate = operationGate
        self.pendingRecordingStore = pendingRecordingStore
        self.deliveryStore = deliveryStore
        self.state = state
        productionContext = nil
        repositoryRegistration = nil
    }

    public func accept(
        _ preparation: IOSForegroundVoiceAcceptedOutputPreparation,
        expectedPending: IOSPendingRecordingCASExpectation
    ) async throws -> IOSForegroundVoiceAcceptanceResult {
        guard preparation.historyMode == .appOnly else {
            throw IOSAcceptedOutputDeliveryError.invalidPreparation
        }
        return try await performRootOperation { lease in
            let pending = try await requireOutputDeliveryPending(
                expected: expectedPending,
                preparation: preparation.deliveryPreparation,
                operationLeaseAuthorization: lease
            )
            let work = try await state.begin(
                IOSForegroundVoicePersistenceWork(
                    preparation: preparation.deliveryPreparation,
                    pendingRecording: pending,
                    retirementOrigin: .liveProcess
                )
            )
            do {
                return try await resume(
                    work,
                    operationLeaseAuthorization: lease
                )
            } catch {
                return try await resolveResumeFailure(
                    error,
                    work: work,
                    operationLeaseAuthorization: lease
                )
            }
        }
    }

    public func retrySavingResult(
        expected: IOSForegroundVoiceSavingResultExpectation
    ) async throws -> IOSForegroundVoiceAcceptanceResult {
        try await performRootOperation { lease in
            guard let work = await state.current() else {
                throw IOSForegroundVoicePersistenceError.noSavingResult
            }
            guard work.matches(expected) else {
                throw IOSForegroundVoicePersistenceError
                    .savingResultIdentityMismatch
            }
            do {
                return try await resume(
                    work,
                    operationLeaseAuthorization: lease
                )
            } catch {
                return try await resolveResumeFailure(
                    error,
                    work: work,
                    operationLeaseAuthorization: lease
                )
            }
        }
    }

    public func recoverRecordingFromSavingResult(
        expected: IOSForegroundVoiceSavingResultExpectation
    ) async throws -> IOSPendingRecording {
        try await performRootOperation { lease in
            guard let work = await state.current() else {
                throw IOSForegroundVoicePersistenceError.noSavingResult
            }
            guard work.matches(expected) else {
                throw IOSForegroundVoicePersistenceError
                    .savingResultIdentityMismatch
            }
            let absence = try await deliveryStore
                .proveForegroundVoiceDestinationAbsent(
                    preparation: work.preparation,
                    pendingRecording: work.pendingRecording,
                    operationLeaseAuthorization: lease
                )
            let recovered = try await pendingRecordingStore
                .moveForegroundVoiceOutputToRecovery(
                    expectedSource: work.pendingRecording,
                    absenceAuthorization: absence,
                    deliveryStoreIdentity: deliveryStore.storeIdentity,
                    operationLeaseAuthorization: lease
                )
            try await state.clear(matching: work.expectation)
            return recovered
        }
    }

    public func loadLatestResult()
        async throws -> IOSForegroundVoiceLatestResultObservation {
        try await performRootOperation { lease in
            let retainedWork = await state.current()
            let pending = try await pendingRecordingStore
                .loadForContainingAppBoundary(
                    operationLeaseAuthorization: lease
            )
            if let retainedWork {
                if try await state.hasCompletedRetirement(
                    matching: retainedWork.expectation
                ) {
                    do {
                        _ = try await pendingRecordingStore
                            .proveForegroundVoicePendingJournalAbsent(
                                operationLeaseAuthorization: lease
                            )
                        let completed = try await loadCompletedResult(
                            for: retainedWork,
                            operationLeaseAuthorization: lease
                        )
                        try await state.clear(
                            matching: retainedWork.expectation
                        )
                        switch completed {
                        case .resultReady(let record):
                            return .resultReady(record)
                        case .expired(let expectation):
                            return .expired(expectation)
                        case .clockRollbackAmbiguous(let expectation):
                            return .clockRollbackAmbiguous(expectation)
                        case .savingResult:
                            throw IOSForegroundVoicePersistenceError
                                .savingResultPending
                        }
                    } catch {
                        return .savingResult(
                            retainedWork.expectation,
                            priorResult: nil
                        )
                    }
                }
                let delivery: IOSAcceptedOutputDeliveryObservation?
                do {
                    delivery = try await deliveryStore
                        .loadForegroundVoiceLatestResultWhileSaving(
                            preparation: retainedWork.preparation,
                            operationLeaseAuthorization: lease
                        )
                } catch let error
                    where isRetryableSavingFailure(error) {
                    return .savingResult(
                        retainedWork.expectation,
                        priorResult: nil
                    )
                }
                let priorResult: IOSAcceptedOutputDeliveryRecord?
                if case .active(let record)? = delivery,
                   record.deliveryState != .discarded,
                   record.acceptedText != nil,
                   !record.hasSameAcceptance(
                       as: retainedWork.preparation
                   ) {
                    priorResult = record
                } else {
                    priorResult = nil
                }
                return .savingResult(
                    retainedWork.expectation,
                    priorResult: priorResult
                )
            }
            if let pending,
               pending.recording.phase == .outputDelivery,
               let destination = try await deliveryStore
                .confirmForegroundVoiceDestinationIfPresent(
                    pendingRecording: pending.recording,
                    operationLeaseAuthorization: lease
                ) {
                let preparation = try destination.record
                    .foregroundVoicePreparation()
                let recoveredWork = try await state.begin(
                    IOSForegroundVoicePersistenceWork(
                        preparation: preparation,
                        pendingRecording: pending.recording,
                        retirementOrigin: .processLoss
                    )
                )
                return .savingResult(
                    recoveredWork.expectation,
                    priorResult: nil
                )
            }
            if pending == nil {
                _ = try await pendingRecordingStore
                    .proveForegroundVoicePendingJournalAbsent(
                        operationLeaseAuthorization: lease
                    )
            }
            let delivery: IOSAcceptedOutputDeliveryObservation?
            do {
                delivery = try await deliveryStore
                    .loadForegroundVoiceLatestResult(
                        operationLeaseAuthorization: lease
                    )
            } catch IOSAcceptedOutputDeliveryError.removalCommitUncertain {
                return .clearedCleanupPending
            }
            guard let delivery else {
                return await deliveryStore
                    .hasForegroundVoiceCleanupPending()
                    ? .clearedCleanupPending
                    : .absent
            }
            if let pending,
               delivery.overlapsPendingIdentity(pending.recording) {
                throw IOSForegroundVoicePersistenceError.invalidPendingOwner
            }
            switch delivery {
            case .active(let record):
                if record.deliveryState == .discarded {
                    return .clearedCleanupPending
                }
                return .resultReady(record)
            case .expired(let expectation):
                return .expired(expectation)
            case .clockRollbackAmbiguous(let expectation):
                return .clockRollbackAmbiguous(expectation)
            }
        }
    }

    func reconcileAcceptance(
        matching preparation: IOSForegroundVoiceAcceptedOutputPreparation
    ) async throws -> IOSForegroundVoiceAcceptanceResult? {
        let before = await state.current()
        let observation = try await loadLatestResult()
        let after = await state.current()
        let hasExactWork = [before, after].contains { work in
            work?.preparation.reconcilesForegroundVoiceAcceptance(
                preparation.deliveryPreparation
            ) == true
        }
        switch observation {
        case .resultReady(let record):
            guard record.isForegroundVoiceAppOnlyRecord,
                  (!record.keepLatestResult
                    || preparation.keepLatestResult),
                  record.hasSameAcceptance(
                      as: preparation.deliveryPreparation
                  ) else { return nil }
            return .resultReady(record)
        case .savingResult(let expectation, _):
            guard hasExactWork,
                  expectation.matches(preparation) else { return nil }
            return .savingResult(expectation)
        case .expired(let expectation):
            guard hasExactWork,
                  expectation.matches(preparation) else { return nil }
            return .expired(expectation)
        case .clockRollbackAmbiguous(let expectation):
            guard hasExactWork,
                  expectation.matches(preparation) else { return nil }
            return .clockRollbackAmbiguous(expectation)
        case .absent, .clearedCleanupPending:
            return nil
        }
    }

    public func clearLatestResult(
        expected: IOSAcceptedOutputDeliveryExpectation
    ) async throws -> IOSForegroundVoiceClearResult {
        try await performRootOperation { lease in
            if let retainedWork = await state.current(),
               retainedWork.pendingRecording.attemptID
                == expected.attemptID,
               retainedWork.pendingRecording.transcriptionID
                == expected.transcriptID {
                throw IOSForegroundVoicePersistenceError
                    .savingResultPending
            }
            let pending = try await pendingRecordingStore
                .loadForContainingAppBoundary(
                    operationLeaseAuthorization: lease
                )
            if let pending,
               expected.overlapsPendingIdentity(pending.recording) {
                guard pending.recording.phase == .outputDelivery,
                      let destination = try await deliveryStore
                        .confirmForegroundVoiceDestinationIfPresent(
                            pendingRecording: pending.recording,
                            operationLeaseAuthorization: lease
                        ),
                      IOSAcceptedOutputDeliveryExpectation(
                          record: destination.record
                      ) == expected else {
                    throw IOSForegroundVoicePersistenceError
                        .invalidPendingOwner
                }
                throw IOSForegroundVoicePersistenceError.savingResultPending
            }
            if pending == nil {
                _ = try await pendingRecordingStore
                    .proveForegroundVoicePendingJournalAbsent(
                        operationLeaseAuthorization: lease
                    )
            }
            return try await deliveryStore.clearForegroundVoiceLatestResult(
                expected: expected,
                operationLeaseAuthorization: lease
            )
        }
    }

    /// Retries only physical cleanup for an already-cleared P4 result. It has
    /// no text or identity input and cannot clear an active result.
    public func retryLatestResultCleanup()
        async throws -> IOSForegroundVoiceClearResult {
        try await performRootOperation { lease in
            try await deliveryStore
                .retryForegroundVoiceLatestResultCleanup(
                    operationLeaseAuthorization: lease
                )
        }
    }

    private func resume(
        _ work: IOSForegroundVoicePersistenceWork,
        operationLeaseAuthorization lease:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSForegroundVoiceAcceptanceResult {
        if try await state.hasCompletedRetirement(
            matching: work.expectation
        ) {
            let result = try await loadCompletedResult(
                for: work,
                operationLeaseAuthorization: lease
            )
            try await state.clear(matching: work.expectation)
            return result
        }
        let firstDestination: IOSForegroundVoiceAcceptedDestinationAuthorization
        if let existing = try await deliveryStore
            .resumeForegroundVoiceDestinationIfPresent(
                preparation: work.preparation,
                pendingRecording: work.pendingRecording,
                operationLeaseAuthorization: lease
            ) {
            firstDestination = existing
        } else {
            let record = try await deliveryStore.acceptForegroundVoiceOutput(
                work.preparation,
                pendingRecording: work.pendingRecording,
                operationLeaseAuthorization: lease
            )
            firstDestination = try await deliveryStore
                .confirmForegroundVoiceDestination(
                    expected: IOSAcceptedOutputDeliveryExpectation(
                        record: record
                    ),
                    pendingRecording: work.pendingRecording,
                    operationLeaseAuthorization: lease
                )
        }
        let audioRemoval: IOSForegroundVoicePendingAudioRemovalAuthorization
        switch work.retirementOrigin {
        case .liveProcess:
            audioRemoval = try await pendingRecordingStore
                .removeForegroundVoiceAcceptedOutputAudio(
                    expected: work.pendingRecording,
                    destinationAuthorization: firstDestination,
                    deliveryStoreIdentity: deliveryStore.storeIdentity,
                    operationLeaseAuthorization: lease
                )
        case .processLoss:
            audioRemoval = try await pendingRecordingStore
                .removeForegroundVoiceAcceptedOutputAudioAfterProcessLoss(
                    expected: work.pendingRecording,
                    destinationAuthorization: firstDestination,
                    deliveryStoreIdentity: deliveryStore.storeIdentity,
                    operationLeaseAuthorization: lease
                )
        }
        let confirmedDestination = try await deliveryStore
            .confirmForegroundVoiceDestination(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: firstDestination.record
                ),
                pendingRecording: work.pendingRecording,
                operationLeaseAuthorization: lease
            )
        try await pendingRecordingStore
            .retireForegroundVoiceAcceptedOutputJournal(
                expected: work.pendingRecording,
                destinationAuthorization: confirmedDestination,
                audioRemovalAuthorization: audioRemoval,
                deliveryStoreIdentity: deliveryStore.storeIdentity,
                operationLeaseAuthorization: lease
            )
        try await state.markRetirementCompleted(
            matching: work.expectation
        )
        let result = try await loadCompletedResult(
            for: work,
            operationLeaseAuthorization: lease
        )
        try await state.clear(matching: work.expectation)
        return result
    }

    private func loadCompletedResult(
        for work: IOSForegroundVoicePersistenceWork,
        operationLeaseAuthorization lease:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSForegroundVoiceAcceptanceResult {
        let completion = try await deliveryStore
            .loadForegroundVoiceLatestResult(
                operationLeaseAuthorization: lease
            )
        switch completion {
        case .active(let record)?
            where record.hasSameAcceptance(as: work.preparation)
                && record.isForegroundVoiceAppOnlyRecord
                && record.deliveryState != .discarded:
            return .resultReady(record)
        case .expired(let expectation)?
            where expectation.matchesForegroundVoiceIdentity(
                work.preparation
            ):
            return .expired(expectation)
        case .clockRollbackAmbiguous(let expectation)?
            where expectation.matchesForegroundVoiceIdentity(
                work.preparation
            ):
            return .clockRollbackAmbiguous(expectation)
        case .none, .active, .expired, .clockRollbackAmbiguous:
            throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        }
    }

    private func resolveResumeFailure(
        _ error: Error,
        work: IOSForegroundVoicePersistenceWork,
        operationLeaseAuthorization lease:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSForegroundVoiceAcceptanceResult {
        if try await state.hasCompletedRetirement(
            matching: work.expectation
        ) {
            return .savingResult(work.expectation)
        }
        if await shouldRetainSavingWork(
            after: error,
            work: work,
            operationLeaseAuthorization: lease
        ) {
            return .savingResult(work.expectation)
        }
        try await state.clear(matching: work.expectation)
        throw error
    }

    private func shouldRetainSavingWork(
        after error: Error,
        work: IOSForegroundVoicePersistenceWork,
        operationLeaseAuthorization lease:
            IOSPersistenceOperationLeaseAuthorization
    ) async -> Bool {
        if isRetryableSavingFailure(error) {
            return true
        }
        do {
            if try await deliveryStore
                .resumeForegroundVoiceDestinationIfPresent(
                    preparation: work.preparation,
                    pendingRecording: work.pendingRecording,
                    operationLeaseAuthorization: lease
                ) != nil {
                return true
            }
        } catch {
            if isRetryableSavingFailure(error) {
                return true
            }
        }
        do {
            guard let pending = try await pendingRecordingStore
                .loadForContainingAppBoundary(
                    operationLeaseAuthorization: lease
                ) else {
                return false
            }
            return pending.recording == work.pendingRecording
                && pending.recording.phase == .outputDelivery
        } catch {
            return isRetryableSavingFailure(error)
        }
    }

    private func isRetryableSavingFailure(_ error: Error) -> Bool {
        if let error = error as? IOSAcceptedOutputDeliveryError {
            switch error {
            case .readFailed,
                 .writeFailed,
                 .dataProtectionUnavailable,
                 .commitUncertain,
                 .removeFailed,
                 .removalCommitUncertain,
                 .expired,
                 .clockRollbackAmbiguous:
                return true
            case .invalidPreparation,
                 .invalidRecord,
                 .sourceTooLarge,
                 .malformedData,
                 .unsupportedSchemaVersion,
                 .slotOccupied,
                 .compareAndSwapFailed,
                 .identityCollision,
                 .invalidTransition,
                 .revisionOverflow,
                 .historyTransferRequired,
                 .bridgeRevocationRequired:
                return false
            }
        }
        if let error = error as? IOSPendingRecordingError {
            switch error {
            case .dataProtectionUnavailable,
                 .journalWriteFailed,
                 .journalCommitUncertain,
                 .audioRemoveFailed,
                 .journalRemoveFailed,
                 .destinationInspectionFailed:
                return true
            case .cancelledBeforeOperation,
                 .reentrantOperation,
                 .repositoryIdentityConflict,
                 .localRecoveryPending,
                 .pendingSlotOccupied,
                 .orphanedAudio,
                 .journalUnreadable,
                 .journalTooLarge,
                 .journalMalformed,
                 .unsupportedJournalVersion,
                 .invalidJournal,
                 .invalidSourceArtifact,
                 .invalidTranscriptionConfiguration,
                 .sourceUnavailable,
                 .sourceChanged,
                 .protectedAudioConflict,
                 .audioPublicationFailed,
                 .audioPublicationTimedOut,
                 .mediaValidationFailed,
                 .mediaValidationTimedOut,
                 .linkedAudioMissing,
                 .linkedAudioInvalid,
                 .compareAndSwapFailed,
                 .invalidTransition,
                 .dispatchAlreadyCommitted:
                return false
            }
        }
        return false
    }

    private func requireOutputDeliveryPending(
        expected: IOSPendingRecordingCASExpectation,
        preparation: IOSAcceptedOutputDeliveryPreparation,
        operationLeaseAuthorization lease:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingRecording {
        guard let observation = try await pendingRecordingStore
            .loadForContainingAppBoundary(
                operationLeaseAuthorization: lease
            ) else {
            throw IOSForegroundVoicePersistenceError.invalidPendingOwner
        }
        let recording = observation.recording
        guard observation.availability == .available,
              IOSPendingRecordingCASExpectation(recording: recording)
                == expected,
              recording.phase == .outputDelivery,
              recording.attemptID == preparation.attemptID,
              recording.transcriptionID == preparation.transcriptID,
              recording.outputIntent == preparation.outputIntent else {
            throw IOSForegroundVoicePersistenceError.invalidPendingOwner
        }
        return recording
    }

    private func performRootOperation<Value: Sendable>(
        _ operation: @escaping @Sendable (
            IOSPersistenceOperationLeaseAuthorization
        ) async throws -> Value
    ) async throws -> Value {
        do {
            return try await operationGate.perform { lease in
                let repositoryBinding = try await beginProductionAdmission(
                    operationLeaseAuthorization: lease
                )
                do {
                    let value = try await operation(lease)
                    try finishProductionAdmission(
                        expectedBinding: repositoryBinding
                    )
                    return value
                } catch {
                    try finishProductionAdmission(
                        expectedBinding: repositoryBinding
                    )
                    throw error
                }
            }
        } catch IOSPersistenceOperationGate.AcquisitionError
            .cancelledBeforeLease {
            throw IOSForegroundVoicePersistenceError
                .cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError
            .reentrantOperation {
            throw IOSForegroundVoicePersistenceError.reentrantOperation
        }
    }

    private func beginProductionAdmission(
        operationLeaseAuthorization lease:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSAcceptedHistoryCoordinatorRepositoryBinding? {
        guard let context else { return nil }
        guard await context.failedHistoryRetryState.hasLiveOwner() == false,
              !context.failedHistoryMutationInterlock.isBlocked,
              await context.baselineRecoveryState.value() == false,
              await context.acceptanceState.current() == nil,
              await context.pendingReplacementState.current() == nil,
              await context.outboxWorkerState.current() == nil,
              await context.policyCutoverState.current() == nil,
              await context.failedHistoryTransferState.current() == nil,
              await context.failedHistoryAudioCleanupState.current() == nil,
              try await context.failedHistoryStore
                .hasPendingJournalRetirement(
                    operationLeaseAuthorization: lease
                ) == false else {
            throw IOSForegroundVoicePersistenceError.localRecoveryPending
        }
        let binding = repositoryRegistration?.revalidate()
        guard !context.repositoryIdentityState.isConflicted else {
            throw IOSForegroundVoicePersistenceError
                .repositoryIdentityConflict
        }
        return binding
    }

    private func finishProductionAdmission(
        expectedBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding?
    ) throws {
        guard let context, let expectedBinding else { return }
        let current = repositoryRegistration?.revalidate(
            expectedBinding: expectedBinding
        )
        guard current == expectedBinding,
              !context.repositoryIdentityState.isConflicted else {
            throw IOSForegroundVoicePersistenceError
                .repositoryIdentityConflict
        }
    }
}

private extension IOSAcceptedOutputDeliveryPreparation {
    func reconcilesForegroundVoiceAcceptance(
        _ candidate: IOSAcceptedOutputDeliveryPreparation
    ) -> Bool {
        failedRetrySafeIdentityMatches(candidate)
            && IOSAcceptedOutputDeliveryValidation.bytesEqual(
                acceptedText,
                candidate.acceptedText
            )
            && outputIntent == candidate.outputIntent
            && !automaticInsertionPreferenceEnabled
            && !candidate.automaticInsertionPreferenceEnabled
            && historyWrite == nil
            && candidate.historyWrite == nil
            && (!keepLatestResult || candidate.keepLatestResult)
    }

    func failedRetrySafeIdentityMatches(
        _ candidate: IOSAcceptedOutputDeliveryPreparation
    ) -> Bool {
        deliveryID == candidate.deliveryID
            && sessionID == candidate.sessionID
            && attemptID == candidate.attemptID
            && transcriptID == candidate.transcriptID
    }
}

private extension IOSForegroundVoiceSavingResultExpectation {
    func matches(
        _ preparation: IOSForegroundVoiceAcceptedOutputPreparation
    ) -> Bool {
        deliveryID == preparation.deliveryID
            && sessionID == preparation.sessionID
            && attemptID == preparation.attemptID
            && transcriptID == preparation.transcriptID
    }
}

private extension IOSAcceptedOutputDeliveryExpectation {
    func matches(
        _ preparation: IOSForegroundVoiceAcceptedOutputPreparation
    ) -> Bool {
        deliveryID == preparation.deliveryID
            && sessionID == preparation.sessionID
            && attemptID == preparation.attemptID
            && transcriptID == preparation.transcriptID
    }
}

private extension IOSForegroundVoicePersistence {
    var context: IOSAcceptedHistoryCoordinatorProcessContext? {
        productionContext
    }
}

extension IOSForegroundVoiceHistoryMode:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSForegroundVoiceHistoryMode(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceAcceptedOutputPreparation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSForegroundVoiceAcceptedOutputPreparation(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceSavingResultExpectation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSForegroundVoiceSavingResultExpectation(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceAcceptanceResult:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSForegroundVoiceAcceptanceResult(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceLatestResultObservation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSForegroundVoiceLatestResultObservation(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceClearResult:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSForegroundVoiceClearResult(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoicePersistenceError:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSForegroundVoicePersistenceError(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoicePersistenceWork:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSForegroundVoicePersistenceWork(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceAcceptedDestinationAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSForegroundVoiceAcceptedDestinationAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceCapturedDestinationAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSForegroundVoiceCapturedDestinationAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceNoDestinationAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSForegroundVoiceNoDestinationAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoicePendingAudioRemovalAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSForegroundVoicePendingAudioRemovalAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoicePersistence:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSForegroundVoicePersistence(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
