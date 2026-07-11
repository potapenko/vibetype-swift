import Foundation
import HoldTypeDomain

/// The complete durable identity shared by an awaiting-recovery Pending record
/// and its failed-History row. It intentionally excludes Pending `updatedAt`,
/// which is not persisted by the failed row.
struct IOSFailedHistoryPendingMatchIdentity: Sendable {
    let attemptID: UUID
    let createdAt: Date
    let audioRelativeIdentifier: String
    let outputIntent: DictationOutputIntent
    let transcriptionModel: String
    let transcriptionLanguageCode: String?
    let durationMilliseconds: Int64
    let byteCount: Int64

    init?(pending recording: IOSPendingRecording) {
        guard recording.phase == .awaitingRecovery,
              recording.transcriptionID == nil else {
            return nil
        }
        self.init(
            attemptID: recording.attemptID,
            createdAt: recording.createdAt,
            audioRelativeIdentifier: recording.audioRelativeIdentifier,
            outputIntent: recording.outputIntent,
            transcriptionModel: recording.transcriptionModel,
            transcriptionLanguageCode:
                recording.transcriptionLanguageCode,
            durationMilliseconds: recording.durationMilliseconds,
            byteCount: recording.byteCount
        )
    }

    init?(failedRow row: IOSFailedHistoryEntry) {
        guard row.ownershipState == .pendingJournalRetirement,
              row.retryCount == 0,
              row.retryOperation == nil else {
            return nil
        }
        self.init(
            attemptID: row.attemptID,
            createdAt: row.createdAt,
            audioRelativeIdentifier: row.audioRelativeIdentifier,
            outputIntent: row.outputIntent,
            transcriptionModel: row.transcriptionModel,
            transcriptionLanguageCode: row.transcriptionLanguageCode,
            durationMilliseconds: row.durationMilliseconds,
            byteCount: row.byteCount
        )
    }

    private init(
        attemptID: UUID,
        createdAt: Date,
        audioRelativeIdentifier: String,
        outputIntent: DictationOutputIntent,
        transcriptionModel: String,
        transcriptionLanguageCode: String?,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) {
        self.attemptID = attemptID
        self.createdAt = createdAt
        self.audioRelativeIdentifier = audioRelativeIdentifier
        self.outputIntent = outputIntent
        self.transcriptionModel = transcriptionModel
        self.transcriptionLanguageCode = transcriptionLanguageCode
        self.durationMilliseconds = durationMilliseconds
        self.byteCount = byteCount
    }
}

extension IOSFailedHistoryPendingMatchIdentity: Equatable {
    static func == (
        lhs: IOSFailedHistoryPendingMatchIdentity,
        rhs: IOSFailedHistoryPendingMatchIdentity
    ) -> Bool {
        lhs.attemptID == rhs.attemptID
            && lhs.createdAt == rhs.createdAt
            && lhs.audioRelativeIdentifier == rhs.audioRelativeIdentifier
            && lhs.outputIntent == rhs.outputIntent
            && IOSAcceptedOutputDeliveryValidation.bytesEqual(
                lhs.transcriptionModel,
                rhs.transcriptionModel
            )
            && IOSAcceptedOutputDeliveryValidation.optionalBytesEqual(
                lhs.transcriptionLanguageCode,
                rhs.transcriptionLanguageCode
            )
            && lhs.durationMilliseconds == rhs.durationMilliseconds
            && lhs.byteCount == rhs.byteCount
    }
}

extension IOSFailedHistoryPendingMatchIdentity:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryPendingMatchIdentity(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Store-minted, descriptor-backed Pending source captured before policy work.
/// It owns the audio lease until one exact transfer preparation takes it.
final class IOSPendingFailedHistoryTransferSource: @unchecked Sendable {
    let pendingSnapshot: IOSPendingRecordingJournalMetadataSnapshot
    let pendingStoreIdentity: IOSPendingRecordingStoreIdentity
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    private let audioLease: any IOSPendingRecordingPublishedAudioLease
    private let lock = NSLock()
    private var ownershipTransferred = false
    private var released = false

    init?(
        mint: IOSPendingFailedHistoryTransferSourceMint,
        pendingSnapshot: IOSPendingRecordingJournalMetadataSnapshot,
        audioLease: any IOSPendingRecordingPublishedAudioLease,
        pendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        let recording = pendingSnapshot.recording
        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil,
              IOSFailedHistoryPendingMatchIdentity(pending: recording) != nil,
              audioLease.relativeIdentifier
                == recording.audioRelativeIdentifier,
              audioLease.durationMilliseconds
                == recording.durationMilliseconds,
              audioLease.audioArtifact.byteCount == recording.byteCount else {
            return nil
        }
        self.pendingSnapshot = pendingSnapshot
        self.audioLease = audioLease
        self.pendingStoreIdentity = pendingStoreIdentity
        self.failedStoreIdentity = failedStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    deinit {
        releaseAudioLease()
    }

    var audioMetadataMatchesPendingSnapshot: Bool {
        let isAuthorized = lock.withLock {
            !released
                && !ownershipTransferred
                && operationLeaseAuthorization.provesActiveLease()
        }
        guard isAuthorized else { return false }
        let recording = pendingSnapshot.recording
        return audioLease.relativeIdentifier
                == recording.audioRelativeIdentifier
            && audioLease.durationMilliseconds
                == recording.durationMilliseconds
            && audioLease.audioArtifact.byteCount == recording.byteCount
    }

    func revalidateAudio() async throws {
        guard audioMetadataMatchesPendingSnapshot else {
            throw IOSPendingRecordingError.linkedAudioInvalid
        }
        let artifact = try await audioLease.revalidate()
        guard audioMetadataMatchesPendingSnapshot,
              artifact.byteCount == pendingSnapshot.recording.byteCount else {
            throw IOSPendingRecordingError.linkedAudioInvalid
        }
    }

    fileprivate func takeAudioLease(
        mint: IOSPendingFailedHistoryTransferPreparationMint
    ) -> (any IOSPendingRecordingPublishedAudioLease)? {
        _ = mint
        return lock.withLock {
            guard !released,
                  !ownershipTransferred,
                  operationLeaseAuthorization.provesActiveLease() else {
                return nil
            }
            ownershipTransferred = true
            return audioLease
        }
    }

    func releaseAudioLease() {
        let shouldRelease = lock.withLock {
            guard !released, !ownershipTransferred else { return false }
            released = true
            return true
        }
        if shouldRelease {
            audioLease.release()
        }
    }
}

extension IOSPendingFailedHistoryTransferSource:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSPendingFailedHistoryTransferSource(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Descriptor-backed, process-local preparation retained only across the
/// failed-row commit. Equality is intentionally not an authority mechanism.
final class IOSPendingFailedHistoryTransferPreparation: @unchecked Sendable {
    let pendingSnapshot: IOSPendingRecordingJournalMetadataSnapshot
    let intendedRow: IOSFailedHistoryEntry
    let pendingStoreIdentity: IOSPendingRecordingStoreIdentity
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity

    private let audioLease: any IOSPendingRecordingPublishedAudioLease
    private let releaseLock = NSLock()
    private var didReleaseAudioLease = false
    private var currentRepositoryBinding:
        IOSAcceptedHistoryCoordinatorRepositoryBinding
    private var currentOperationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization
    private var currentPolicyReceipt: IOSHistoryPolicyReceipt

    init?(
        mint: IOSPendingFailedHistoryTransferPreparationMint,
        source: IOSPendingFailedHistoryTransferSource,
        intendedRow: IOSFailedHistoryEntry,
        policyReceipt: IOSHistoryPolicyReceipt
    ) {
        guard source.operationLeaseAuthorization.provesActiveLease(),
              policyReceipt.state.historyEnabled,
              policyReceipt.state.policyGeneration
                == intendedRow.policyGeneration,
              policyReceipt.capabilityOwnerIdentity
                == source.ownerIdentity,
              IOSFailedHistoryPendingMatchIdentity(
                  pending: source.pendingSnapshot.recording
              ) == IOSFailedHistoryPendingMatchIdentity(
                  failedRow: intendedRow
              ),
              source.audioMetadataMatchesPendingSnapshot,
              let audioLease = source.takeAudioLease(mint: mint) else {
            return nil
        }
        pendingSnapshot = source.pendingSnapshot
        self.intendedRow = intendedRow
        self.audioLease = audioLease
        pendingStoreIdentity = source.pendingStoreIdentity
        failedStoreIdentity = source.failedStoreIdentity
        ownerIdentity = source.ownerIdentity
        currentRepositoryBinding = source.repositoryBinding
        currentOperationLeaseAuthorization =
            source.operationLeaseAuthorization
        currentPolicyReceipt = policyReceipt
    }

    #if DEBUG
    init?(
        mint: IOSPendingFailedHistoryTransferPreparationMint,
        pendingSnapshot: IOSPendingRecordingJournalMetadataSnapshot,
        intendedRow: IOSFailedHistoryEntry,
        audioLease: any IOSPendingRecordingPublishedAudioLease,
        pendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        policyReceipt: IOSHistoryPolicyReceipt
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil,
              policyReceipt.state.historyEnabled,
              policyReceipt.state.policyGeneration
                == intendedRow.policyGeneration,
              policyReceipt.capabilityOwnerIdentity == ownerIdentity,
              IOSFailedHistoryPendingMatchIdentity(
                  pending: pendingSnapshot.recording
              ) == IOSFailedHistoryPendingMatchIdentity(
                  failedRow: intendedRow
              ),
              audioLease.relativeIdentifier
                == pendingSnapshot.recording.audioRelativeIdentifier,
              audioLease.durationMilliseconds
                == pendingSnapshot.recording.durationMilliseconds,
              audioLease.audioArtifact.byteCount
                == pendingSnapshot.recording.byteCount else {
            return nil
        }
        self.pendingSnapshot = pendingSnapshot
        self.intendedRow = intendedRow
        self.audioLease = audioLease
        self.pendingStoreIdentity = pendingStoreIdentity
        self.failedStoreIdentity = failedStoreIdentity
        self.ownerIdentity = ownerIdentity
        currentRepositoryBinding = repositoryBinding
        currentOperationLeaseAuthorization = operationLeaseAuthorization
        currentPolicyReceipt = policyReceipt
    }
    #endif

    deinit {
        releaseAudioLease()
    }

    var repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding {
        releaseLock.withLock { currentRepositoryBinding }
    }

    var operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization {
        releaseLock.withLock { currentOperationLeaseAuthorization }
    }

    var policyReceipt: IOSHistoryPolicyReceipt {
        releaseLock.withLock { currentPolicyReceipt }
    }

    var audioMetadataMatchesPendingSnapshot: Bool {
        let isAuthorized = releaseLock.withLock {
            !didReleaseAudioLease
                && currentOperationLeaseAuthorization.provesActiveLease()
        }
        guard isAuthorized else {
            return false
        }
        let recording = pendingSnapshot.recording
        return audioLease.relativeIdentifier
                == recording.audioRelativeIdentifier
            && audioLease.durationMilliseconds
                == recording.durationMilliseconds
            && audioLease.audioArtifact.byteCount == recording.byteCount
    }

    func revalidateAudio() async throws {
        let initialAuthorization = operationLeaseAuthorization
        guard initialAuthorization.provesActiveLease(),
              !releaseLock.withLock({ didReleaseAudioLease }) else {
            throw IOSPendingRecordingError.linkedAudioInvalid
        }
        let artifact = try await audioLease.revalidate()
        guard operationLeaseAuthorization.provesSameActiveLease(
                  as: initialAuthorization
              ),
              !releaseLock.withLock({ didReleaseAudioLease }),
              audioMetadataMatchesPendingSnapshot,
              artifact.byteCount == pendingSnapshot.recording.byteCount else {
            throw IOSPendingRecordingError.linkedAudioInvalid
        }
    }

    func refresh(
        mint: IOSPendingFailedHistoryTransferPreparationMint,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        policyReceipt: IOSHistoryPolicyReceipt
    ) -> Bool {
        _ = mint
        return releaseLock.withLock {
            guard !didReleaseAudioLease,
                  operationLeaseAuthorization.provesActiveLease(),
                  repositoryBinding == currentRepositoryBinding,
                  repositoryBinding.physicalRootIdentity != nil,
                  policyReceipt == currentPolicyReceipt,
                  policyReceipt.capabilityOwnerIdentity == ownerIdentity else {
                return false
            }
            currentRepositoryBinding = repositoryBinding
            currentOperationLeaseAuthorization =
                operationLeaseAuthorization
            currentPolicyReceipt = policyReceipt
            return true
        }
    }

    func releaseAudioLease() {
        let shouldRelease = releaseLock.withLock {
            guard !didReleaseAudioLease else { return false }
            didReleaseAudioLease = true
            return true
        }
        if shouldRelease {
            audioLease.release()
        }
    }
}

extension IOSPendingFailedHistoryTransferPreparation: Equatable {
    static func == (
        lhs: IOSPendingFailedHistoryTransferPreparation,
        rhs: IOSPendingFailedHistoryTransferPreparation
    ) -> Bool {
        lhs === rhs
    }
}

extension IOSPendingFailedHistoryTransferPreparation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSPendingFailedHistoryTransferPreparation(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Failed-store proof that the exact prepared append did not commit. It is the
/// only authority that may release a retained descriptor after the old gate
/// lease has expired.
struct IOSFailedHistoryPendingRowAbsenceProof: Equatable, Sendable {
    let preparation: IOSPendingFailedHistoryTransferPreparation
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryPendingRowAbsenceProofMint,
        preparation: IOSPendingFailedHistoryTransferPreparation,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil,
              preparation.failedStoreIdentity == failedStoreIdentity,
              preparation.pendingStoreIdentity
                == expectedPendingStoreIdentity,
              preparation.ownerIdentity == ownerIdentity,
              preparation.repositoryBinding == repositoryBinding else {
            return nil
        }
        self.preparation = preparation
        self.failedStoreIdentity = failedStoreIdentity
        self.expectedPendingStoreIdentity = expectedPendingStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

extension IOSFailedHistoryPendingRowAbsenceProof:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryPendingRowAbsenceProof(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Failed-store authority for removing only the redundant Pending metadata.
/// A committed origin retains the exact pre-row Pending physical snapshot;
/// relaunch intentionally does not invent one.
struct IOSFailedHistoryPendingMetadataRetirementAuthority:
    Equatable,
    Sendable {
    enum Origin: Equatable, Sendable {
        case committed(IOSPendingRecordingJournalMetadataSnapshot)
        case relaunched
        case readyOutcomeConfirmation
    }

    let failedSource: IOSFailedHistoryJournalSnapshot
    let row: IOSFailedHistoryEntry
    let origin: Origin
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryMetadataRetirementAuthorityMint,
        failedSource: IOSFailedHistoryJournalSnapshot,
        row: IOSFailedHistoryEntry,
        origin: Origin,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil,
              failedSource.envelope.entries.contains(row),
              let rowIdentity = IOSFailedHistoryPendingMatchIdentity(
                  failedRow: row
              ) else {
            return nil
        }
        if case .committed(let pendingSource) = origin {
            guard IOSFailedHistoryPendingMatchIdentity(
                pending: pendingSource.recording
            ) == rowIdentity else {
                return nil
            }
        }

        self.failedSource = failedSource
        self.row = row
        self.origin = origin
        self.failedStoreIdentity = failedStoreIdentity
        self.expectedPendingStoreIdentity = expectedPendingStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

extension IOSFailedHistoryPendingMetadataRetirementAuthority:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryPendingMetadataRetirementAuthority(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    func identifiesSameTransfer(
        as other: IOSFailedHistoryPendingMetadataRetirementAuthority
    ) -> Bool {
        row == other.row
            && failedStoreIdentity == other.failedStoreIdentity
            && expectedPendingStoreIdentity
                == other.expectedPendingStoreIdentity
            && ownerIdentity == other.ownerIdentity
            && repositoryBinding == other.repositoryBinding
    }
}

/// Exact present-source authorization retained across metadata-removal
/// uncertainty so a semantically equal replacement is never resampled.
struct IOSPendingRecordingMetadataRemovalAuthorization:
    Equatable,
    Sendable {
    let authority: IOSFailedHistoryPendingMetadataRetirementAuthority
    let source: IOSPendingRecordingJournalMetadataSnapshot

    init?(
        mint: IOSPendingRecordingMetadataRemovalAuthorizationMint,
        authority: IOSFailedHistoryPendingMetadataRetirementAuthority,
        source: IOSPendingRecordingJournalMetadataSnapshot
    ) {
        _ = mint
        guard authority.operationLeaseAuthorization.provesActiveLease(),
              IOSFailedHistoryPendingMatchIdentity(
                  pending: source.recording
              ) == IOSFailedHistoryPendingMatchIdentity(
                  failedRow: authority.row
              ) else {
            return nil
        }
        if case .committed(let expectedSource) = authority.origin {
            guard source == expectedSource else { return nil }
        }
        self.authority = authority
        self.source = source
    }
}

extension IOSPendingRecordingMetadataRemovalAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSPendingRecordingMetadataRemovalAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSPendingRecordingMetadataRetirementStep: Equatable, Sendable {
    case removalAuthorized(IOSPendingRecordingMetadataRemovalAuthorization)
    case absenceConfirmed(IOSPendingRecordingMetadataAbsenceReceipt)
}

extension IOSPendingRecordingMetadataRetirementStep:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSPendingRecordingMetadataRetirementStep(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Pending-store proof that the one canonical journal path is durably absent.
/// The low-level evidence remains opaque and path-typed.
struct IOSPendingRecordingMetadataAbsenceReceipt: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case removed(
            source: IOSPendingRecordingJournalMetadataSnapshot,
            evidence: IOSPendingRecordingJournalMetadataAbsenceEvidence
        )
        case alreadyAbsent(
            evidence: IOSPendingRecordingJournalMetadataAbsenceEvidence
        )

        func provesRemoval(
            of source: IOSPendingRecordingJournalMetadataSnapshot
        ) -> Bool {
            guard case .removed(
                let recordedSource,
                let evidence
            ) = self else {
                return false
            }
            return recordedSource == source
                && evidence.provesRemoval(of: source)
        }

        var provesPreexistingAbsence: Bool {
            guard case .alreadyAbsent(let evidence) = self else {
                return false
            }
            return evidence.provesPreexistingAbsence
        }
    }

    let issuerStoreIdentity: IOSPendingRecordingStoreIdentity
    let authority: IOSFailedHistoryPendingMetadataRetirementAuthority
    let outcome: Outcome

    init?(
        mint: IOSPendingRecordingMetadataAbsenceReceiptMint,
        issuerStoreIdentity: IOSPendingRecordingStoreIdentity,
        authority: IOSFailedHistoryPendingMetadataRetirementAuthority,
        outcome: Outcome
    ) {
        _ = mint
        guard issuerStoreIdentity
                == authority.expectedPendingStoreIdentity,
              authority.operationLeaseAuthorization.provesActiveLease(),
              let expectedRoot = authority.repositoryBinding
                .physicalRootIdentity else {
            return nil
        }

        let evidence: IOSPendingRecordingJournalMetadataAbsenceEvidence
        switch outcome {
        case .removed(let source, let removedEvidence):
            guard authority.origin != .readyOutcomeConfirmation else {
                return nil
            }
            guard removedEvidence.provesRemoval(of: source),
                  IOSFailedHistoryPendingMatchIdentity(
                      pending: source.recording
                  ) == IOSFailedHistoryPendingMatchIdentity(
                      failedRow: authority.row
                  ) else {
                return nil
            }
            if case .committed(let expectedSource) = authority.origin {
                guard source == expectedSource else { return nil }
            }
            evidence = removedEvidence
        case .alreadyAbsent(let absenceEvidence):
            guard absenceEvidence.provesPreexistingAbsence else {
                return nil
            }
            evidence = absenceEvidence
        }
        guard evidence.provesCanonicalPendingRecordingPath,
              evidence.binding.repositoryRoot == expectedRoot else {
            return nil
        }

        self.issuerStoreIdentity = issuerStoreIdentity
        self.authority = authority
        self.outcome = outcome
    }

    var evidence: IOSPendingRecordingJournalMetadataAbsenceEvidence {
        switch outcome {
        case .removed(_, let evidence), .alreadyAbsent(let evidence):
            evidence
        }
    }
}

extension IOSPendingRecordingMetadataAbsenceReceipt:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSPendingRecordingMetadataAbsenceReceipt(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Immediate proof used by ordinary Pending APIs before they may regain
/// provider or audio-removal authority.
struct IOSFailedHistoryPendingOwnershipKey: Equatable, Sendable {
    let attemptID: UUID
    let audioRelativeIdentifier: String

    init(recording: IOSPendingRecording) {
        attemptID = recording.attemptID
        audioRelativeIdentifier = recording.audioRelativeIdentifier
    }
}

extension IOSFailedHistoryPendingOwnershipKey:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryPendingOwnershipKey(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSFailedHistoryPendingOwnershipAbsenceProof: Equatable, Sendable {
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let pendingKey: IOSFailedHistoryPendingOwnershipKey
    let failedSource: IOSFailedHistoryJournalSnapshot?
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryPendingOwnershipAbsenceProofMint,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        pendingKey: IOSFailedHistoryPendingOwnershipKey,
        failedSource: IOSFailedHistoryJournalSnapshot?,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil else {
            return nil
        }
        self.failedStoreIdentity = failedStoreIdentity
        self.expectedPendingStoreIdentity = expectedPendingStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.pendingKey = pendingKey
        self.failedSource = failedSource
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

extension IOSFailedHistoryPendingOwnershipAbsenceProof:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryPendingOwnershipAbsenceProof(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

protocol IOSPendingRecordingFailedOwnershipInspecting: Sendable {
    var failedStoreIdentity: IOSFailedHistoryStoreIdentity { get }

    func sealProtectedAudioInventory(
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryProtectedAudioInventory

    func revalidateProtectedAudioInventory(
        _ inventory: IOSFailedHistoryProtectedAudioInventory,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws

    func provePendingOwnershipAbsent(
        for pendingKey: IOSFailedHistoryPendingOwnershipKey,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryPendingOwnershipAbsenceProof
}

struct IOSFailedHistoryTransferRecoveryInspection: Equatable, Sendable {
    let failedSource: IOSFailedHistoryJournalSnapshot?
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        mint: IOSFailedHistoryTransferRecoveryInspectionMint,
        failedSource: IOSFailedHistoryJournalSnapshot?,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        _ = mint
        guard operationLeaseAuthorization.provesActiveLease(),
              repositoryBinding.physicalRootIdentity != nil,
              failedSource?.envelope.entries.contains(where: {
                  $0.ownershipState == .pendingJournalRetirement
              }) != true else {
            return nil
        }
        self.failedSource = failedSource
        self.failedStoreIdentity = failedStoreIdentity
        self.expectedPendingStoreIdentity = expectedPendingStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }
}

extension IOSFailedHistoryTransferRecoveryInspection:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryTransferRecoveryInspection(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSFailedHistoryTransferRecoveryDirective: Equatable, Sendable {
    case retirePendingMetadata(
        IOSFailedHistoryPendingMetadataRetirementAuthority
    )
    case verifyTerminal(IOSFailedHistoryTransferRecoveryInspection)
}

extension IOSFailedHistoryTransferRecoveryDirective:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryTransferRecoveryDirective(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSFailedHistoryTransferFailure: Equatable, Sendable {
    let category: IOSFailedHistoryFailureCategory
    let pipelineStage: IOSFailedHistoryPipelineStage
}

extension IOSFailedHistoryTransferFailure:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSFailedHistoryTransferFailure(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSFailedHistoryTransferResult: Equatable, Sendable {
    case transferred
    case reconciled
    case noWork
}

extension IOSFailedHistoryTransferResult:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSFailedHistoryTransferResult(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSFailedHistoryTransferSemanticPhase: Equatable, Sendable {
    case committingRow(IOSPendingFailedHistoryTransferPreparation)
    case observingPendingMetadata(
        IOSFailedHistoryPendingMetadataRetirementAuthority
    )
    case removingPendingMetadata(
        IOSPendingRecordingMetadataRemovalAuthorization
    )
    case committingReady(IOSPendingRecordingMetadataAbsenceReceipt)
}

extension IOSFailedHistoryTransferSemanticPhase:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryTransferSemanticPhase(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

fileprivate struct IOSFailedHistoryTransferStateMutationAuthorization {
    fileprivate init() {}
}

actor IOSFailedHistoryTransferOperationState {
    private var phase: IOSFailedHistoryTransferSemanticPhase?

    func current() -> IOSFailedHistoryTransferSemanticPhase? { phase }

    fileprivate func begin(
        _ preparation: IOSPendingFailedHistoryTransferPreparation,
        authorization: IOSFailedHistoryTransferStateMutationAuthorization
    ) -> Bool {
        _ = authorization
        guard phase == nil,
              preparation.operationLeaseAuthorization
                .provesActiveLease() else {
            return false
        }
        phase = .committingRow(preparation)
        return true
    }

    fileprivate func beginReconciliation(
        _ authority:
            IOSFailedHistoryPendingMetadataRetirementAuthority,
        authorization: IOSFailedHistoryTransferStateMutationAuthorization
    ) -> Bool {
        _ = authorization
        guard phase == nil,
              authority.operationLeaseAuthorization.provesActiveLease() else {
            return false
        }
        phase = .observingPendingMetadata(authority)
        return true
    }

    fileprivate func recordRowCommitted(
        _ authority: IOSFailedHistoryPendingMetadataRetirementAuthority,
        from preparation: IOSPendingFailedHistoryTransferPreparation,
        authorization: IOSFailedHistoryTransferStateMutationAuthorization
    ) -> Bool {
        _ = authorization
        guard phase == .committingRow(preparation),
              authority.row == preparation.intendedRow,
              authority.origin
                == .committed(preparation.pendingSnapshot),
              authority.expectedPendingStoreIdentity
                == preparation.pendingStoreIdentity,
              authority.failedStoreIdentity
                == preparation.failedStoreIdentity,
              authority.ownerIdentity == preparation.ownerIdentity,
              authority.repositoryBinding
                == preparation.repositoryBinding,
              authority.operationLeaseAuthorization.provesSameActiveLease(
                  as: preparation.operationLeaseAuthorization
              ) else {
            return false
        }
        phase = .observingPendingMetadata(authority)
        preparation.releaseAudioLease()
        return true
    }

    fileprivate func recordMetadataRemovalAuthorized(
        _ removalAuthorization:
            IOSPendingRecordingMetadataRemovalAuthorization,
        authorization: IOSFailedHistoryTransferStateMutationAuthorization
    ) -> Bool {
        _ = authorization
        guard phase
                == .observingPendingMetadata(
                    removalAuthorization.authority
                ),
              removalAuthorization.authority
                .operationLeaseAuthorization.provesActiveLease() else {
            return false
        }
        phase = .removingPendingMetadata(removalAuthorization)
        return true
    }

    fileprivate func refreshObservedAuthority(
        _ refreshed:
            IOSFailedHistoryPendingMetadataRetirementAuthority,
        authorization: IOSFailedHistoryTransferStateMutationAuthorization
    ) -> Bool {
        _ = authorization
        guard case .observingPendingMetadata(let retained) = phase,
              retained.identifiesSameTransfer(as: refreshed),
              retained.origin == refreshed.origin,
              refreshed.operationLeaseAuthorization.provesActiveLease() else {
            return false
        }
        phase = .observingPendingMetadata(refreshed)
        return true
    }

    fileprivate func refreshMetadataRemovalAuthorization(
        _ refreshed: IOSPendingRecordingMetadataRemovalAuthorization,
        authorization: IOSFailedHistoryTransferStateMutationAuthorization
    ) -> Bool {
        _ = authorization
        guard case .removingPendingMetadata(let retained) = phase,
              retained.source == refreshed.source,
              retained.authority.identifiesSameTransfer(
                  as: refreshed.authority
              ),
              refreshed.authority.operationLeaseAuthorization
                .provesActiveLease() else {
            return false
        }
        phase = .removingPendingMetadata(refreshed)
        return true
    }

    fileprivate func recordMetadataAbsent(
        _ receipt: IOSPendingRecordingMetadataAbsenceReceipt,
        authorization: IOSFailedHistoryTransferStateMutationAuthorization
    ) -> Bool {
        _ = authorization
        guard receipt.authority.operationLeaseAuthorization
                .provesActiveLease() else {
            return false
        }
        let matchesCurrentPhase: Bool = switch phase {
        case .observingPendingMetadata(let authority):
            authority == receipt.authority
                && receipt.outcome.provesPreexistingAbsence
        case .removingPendingMetadata(let removalAuthorization):
            removalAuthorization.authority == receipt.authority
                && (receipt.outcome.provesRemoval(
                    of: removalAuthorization.source
                ) || receipt.outcome.provesPreexistingAbsence)
        default:
            false
        }
        guard matchesCurrentPhase else {
            return false
        }
        phase = .committingReady(receipt)
        return true
    }

    fileprivate func recordRemovalAbsenceAfterAuthorityRefresh(
        _ receipt: IOSPendingRecordingMetadataAbsenceReceipt,
        authorization: IOSFailedHistoryTransferStateMutationAuthorization
    ) -> Bool {
        _ = authorization
        guard case .removingPendingMetadata(let retained) = phase,
              retained.authority.identifiesSameTransfer(
                  as: receipt.authority
              ),
              receipt.authority.operationLeaseAuthorization
                .provesActiveLease(),
              receipt.outcome.provesPreexistingAbsence else {
            return false
        }
        phase = .committingReady(receipt)
        return true
    }

    fileprivate func abandonBeforeRowCommit(
        using proof: IOSFailedHistoryPendingRowAbsenceProof,
        authorization: IOSFailedHistoryTransferStateMutationAuthorization
    ) -> Bool {
        _ = authorization
        guard phase == .committingRow(proof.preparation),
              proof.operationLeaseAuthorization
                .provesActiveLease() else {
            return false
        }
        proof.preparation.releaseAudioLease()
        phase = nil
        return true
    }

    fileprivate func clearCompleted(
        _ receipt: IOSPendingRecordingMetadataAbsenceReceipt,
        authorization: IOSFailedHistoryTransferStateMutationAuthorization
    ) -> Bool {
        _ = authorization
        guard phase == .committingReady(receipt),
              receipt.authority.operationLeaseAuthorization
                .provesActiveLease() else {
            return false
        }
        phase = nil
        return true
    }

    fileprivate func refreshReadyReceipt(
        _ refreshed: IOSPendingRecordingMetadataAbsenceReceipt,
        authorization: IOSFailedHistoryTransferStateMutationAuthorization
    ) -> Bool {
        _ = authorization
        guard case .committingReady(let retained) = phase,
              retained.authority.identifiesSameTransfer(
                  as: refreshed.authority
              ),
              refreshed.authority.operationLeaseAuthorization
                .provesActiveLease(),
              retained.evidence.binding.repositoryRoot
                == refreshed.evidence.binding.repositoryRoot,
              retained.evidence.provesCanonicalPendingRecordingPath,
              refreshed.evidence.provesCanonicalPendingRecordingPath else {
            return false
        }
        phase = .committingReady(refreshed)
        return true
    }
}

extension IOSAcceptedHistoryCoordinator {
    func transferPendingRecordingFailure(
        expected: IOSPendingRecordingCASExpectation,
        failure: IOSFailedHistoryTransferFailure
    ) async throws -> IOSFailedHistoryTransferResult {
        guard let pendingRecordingStore else {
            throw IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        }
        let policyStore = policyStore
        let failedHistoryStore = failedHistoryStore
        let deliveryStore = deliveryStore
        let operationGate = operationGate
        let transferState = failedHistoryTransferState
        let baselineRecoveryState = baselineRecoveryState
        let acceptanceState = acceptanceState
        let pendingReplacementState = pendingReplacementState
        let outboxWorkerState = outboxWorkerState
        let policyCutoverState = policyCutoverState
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration

        do {
            return try await operationGate.perform { authorization in
                let repositoryBinding = repositoryRegistration?.revalidate()
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                do {
                    guard await baselineRecoveryState.value() == false,
                          await acceptanceState.current() == nil,
                          await pendingReplacementState.current() == nil,
                          await outboxWorkerState.current() == nil,
                          await policyCutoverState.current() == nil,
                          await deliveryStore
                            .hasUncertainAcceptanceForHistoryCoordinator()
                            == false,
                          await deliveryStore
                            .hasRetainedHistoryWorkForPolicyCutover()
                            == false else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                    if await transferState.current() != nil {
                        return try await Self.resumeFailedHistoryTransfer(
                            pendingStore: pendingRecordingStore,
                            failedStore: failedHistoryStore,
                            transferState: transferState,
                            operationLeaseAuthorization: authorization,
                            completionResult: .reconciled
                        )
                    }

                    switch try await failedHistoryStore
                        .inspectTransferRecovery(
                            operationLeaseAuthorization: authorization
                        ) {
                    case .retirePendingMetadata(let authority):
                        guard await transferState.beginReconciliation(
                            authority,
                            authorization:
                                IOSFailedHistoryTransferStateMutationAuthorization()
                        ) else {
                            throw IOSAcceptedHistoryCoordinatorError
                                .localRecoveryPending
                        }
                        return try await Self.resumeFailedHistoryTransfer(
                            pendingStore: pendingRecordingStore,
                            failedStore: failedHistoryStore,
                            transferState: transferState,
                            operationLeaseAuthorization: authorization,
                            completionResult: .reconciled
                        )
                    case .verifyTerminal(let inspection):
                        try await pendingRecordingStore
                            .verifyTransferRecoveryTerminal(
                                using: inspection,
                                operationLeaseAuthorization: authorization
                            )
                    }

                    let source = try await pendingRecordingStore
                        .prepareFailedHistoryTransferSource(
                            expected: expected,
                            failedStoreIdentity:
                                failedHistoryStore.storeIdentity,
                            operationLeaseAuthorization: authorization
                        )
                    defer { source.releaseAudioLease() }

                    guard let policy = try await policyStore.load() else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                    guard policy.historyEnabled else {
                        return .noWork
                    }
                    let policyReceipt = try await policyStore.confirm(
                        expected: IOSHistoryPolicyExpectation(state: policy)
                    )
                    guard policyReceipt.state.historyEnabled else {
                        return .noWork
                    }
                    let preparation = try await pendingRecordingStore
                        .sealFailedHistoryTransfer(
                            source,
                            failure: failure,
                            transferDate: Date(),
                            policyReceipt: policyReceipt,
                            operationLeaseAuthorization: authorization
                        )
                    guard await transferState.begin(
                        preparation,
                        authorization:
                            IOSFailedHistoryTransferStateMutationAuthorization()
                    ) else {
                        preparation.releaseAudioLease()
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                    let result = try await Self.resumeFailedHistoryTransfer(
                        pendingStore: pendingRecordingStore,
                        failedStore: failedHistoryStore,
                        transferState: transferState,
                        operationLeaseAuthorization: authorization,
                        completionResult: .transferred
                    )
                    if let repositoryBinding {
                        _ = repositoryRegistration?.revalidate(
                            expectedBinding: repositoryBinding
                        )
                    }
                    guard !repositoryIdentityState.isConflicted else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .repositoryIdentityConflict
                    }
                    return result
                } catch {
                    if let repositoryBinding {
                        _ = repositoryRegistration?.revalidate(
                            expectedBinding: repositoryBinding
                        )
                    }
                    if repositoryIdentityState.isConflicted {
                        throw IOSAcceptedHistoryCoordinatorError
                            .repositoryIdentityConflict
                    }
                    throw error
                }
            }
        } catch IOSPersistenceOperationGate.AcquisitionError
            .cancelledBeforeLease {
            throw IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError
            .reentrantOperation {
            throw IOSAcceptedHistoryCoordinatorError.reentrantOperation
        }
    }

    func reconcileFailedHistoryTransfer()
        async throws -> IOSFailedHistoryTransferResult {
        guard let pendingRecordingStore else {
            throw IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        }
        let failedHistoryStore = failedHistoryStore
        let deliveryStore = deliveryStore
        let transferState = failedHistoryTransferState
        let baselineRecoveryState = baselineRecoveryState
        let acceptanceState = acceptanceState
        let pendingReplacementState = pendingReplacementState
        let outboxWorkerState = outboxWorkerState
        let policyCutoverState = policyCutoverState
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration

        do {
            return try await operationGate.perform { authorization in
                let repositoryBinding = repositoryRegistration?.revalidate()
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                do {
                    guard await baselineRecoveryState.value() == false,
                          await acceptanceState.current() == nil,
                          await pendingReplacementState.current() == nil,
                          await outboxWorkerState.current() == nil,
                          await policyCutoverState.current() == nil,
                          await deliveryStore
                            .hasUncertainAcceptanceForHistoryCoordinator()
                            == false,
                          await deliveryStore
                            .hasRetainedHistoryWorkForPolicyCutover()
                            == false else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                    let result: IOSFailedHistoryTransferResult
                    if await transferState.current() != nil {
                        result = try await Self.resumeFailedHistoryTransfer(
                            pendingStore: pendingRecordingStore,
                            failedStore: failedHistoryStore,
                            transferState: transferState,
                            operationLeaseAuthorization: authorization,
                            completionResult: .reconciled
                        )
                    } else {
                        switch try await failedHistoryStore
                            .inspectTransferRecovery(
                                operationLeaseAuthorization: authorization
                            ) {
                        case .retirePendingMetadata(let authority):
                            guard await transferState.beginReconciliation(
                                authority,
                                authorization:
                                    IOSFailedHistoryTransferStateMutationAuthorization()
                            ) else {
                                throw IOSAcceptedHistoryCoordinatorError
                                    .localRecoveryPending
                            }
                            result = try await Self.resumeFailedHistoryTransfer(
                                pendingStore: pendingRecordingStore,
                                failedStore: failedHistoryStore,
                                transferState: transferState,
                                operationLeaseAuthorization: authorization,
                                completionResult: .reconciled
                            )
                        case .verifyTerminal(let inspection):
                            try await pendingRecordingStore
                                .verifyTransferRecoveryTerminal(
                                    using: inspection,
                                    operationLeaseAuthorization: authorization
                                )
                            result = .noWork
                        }
                    }
                    if let repositoryBinding {
                        _ = repositoryRegistration?.revalidate(
                            expectedBinding: repositoryBinding
                        )
                    }
                    guard !repositoryIdentityState.isConflicted else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .repositoryIdentityConflict
                    }
                    return result
                } catch {
                    if let repositoryBinding {
                        _ = repositoryRegistration?.revalidate(
                            expectedBinding: repositoryBinding
                        )
                    }
                    if repositoryIdentityState.isConflicted {
                        throw IOSAcceptedHistoryCoordinatorError
                            .repositoryIdentityConflict
                    }
                    throw error
                }
            }
        } catch IOSPersistenceOperationGate.AcquisitionError
            .cancelledBeforeLease {
            throw IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError
            .reentrantOperation {
            throw IOSAcceptedHistoryCoordinatorError.reentrantOperation
        }
    }

    fileprivate static func resumeFailedHistoryTransfer(
        pendingStore: IOSPendingRecordingStore,
        failedStore: IOSFailedHistoryStore,
        transferState: IOSFailedHistoryTransferOperationState,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        completionResult: IOSFailedHistoryTransferResult
    ) async throws -> IOSFailedHistoryTransferResult {
        let stateAuthorization =
            IOSFailedHistoryTransferStateMutationAuthorization()

        while let phase = await transferState.current() {
            switch phase {
            case .committingRow(let preparation):
                if !preparation.operationLeaseAuthorization
                    .provesSameActiveLease(
                        as: operationLeaseAuthorization
                    ) {
                    try await pendingStore.refreshFailedHistoryTransfer(
                        preparation,
                        policyReceipt: preparation.policyReceipt,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                }
                do {
                    let authority: IOSFailedHistoryPendingMetadataRetirementAuthority
                    if failedStore.mutationInterlock.isBlocked {
                        authority = try await failedStore
                            .reconcilePendingJournalRetirementCommit(
                                operationLeaseAuthorization:
                                    operationLeaseAuthorization
                            )
                    } else {
                        authority = try await failedStore
                            .commitPendingJournalRetirement(preparation)
                    }
                    guard await transferState.recordRowCommitted(
                        authority,
                        from: preparation,
                        authorization: stateAuthorization
                    ) else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                } catch {
                    if let proof = try? await failedStore
                        .provePendingJournalRetirementAppendAbsent(
                            for: preparation,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ), await transferState.abandonBeforeRowCommit(
                            using: proof,
                            authorization: stateAuthorization
                        ) {
                        throw error
                    }
                    throw error
                }

            case .observingPendingMetadata(let retainedAuthority):
                let authority: IOSFailedHistoryPendingMetadataRetirementAuthority
                if retainedAuthority.operationLeaseAuthorization
                    .provesSameActiveLease(
                        as: operationLeaseAuthorization
                    ) {
                    authority = retainedAuthority
                } else {
                    let refreshed = try await failedStore
                        .refreshPendingMetadataRetirementAuthority(
                            retainedAuthority,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        )
                    guard retainedAuthority.identifiesSameTransfer(
                        as: refreshed
                    ), await transferState.refreshObservedAuthority(
                            refreshed,
                            authorization: stateAuthorization
                        ) else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                    authority = refreshed
                }
                switch try await pendingStore.preparePendingMetadataRetirement(
                    using: authority,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) {
                case .removalAuthorized(let removalAuthorization):
                    guard await transferState
                        .recordMetadataRemovalAuthorized(
                            removalAuthorization,
                            authorization: stateAuthorization
                        ) else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                case .absenceConfirmed(let receipt):
                    guard await transferState.recordMetadataAbsent(
                        receipt,
                        authorization: stateAuthorization
                    ) else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                }

            case .removingPendingMetadata(let retainedRemoval):
                if retainedRemoval.authority.operationLeaseAuthorization
                    .provesSameActiveLease(
                        as: operationLeaseAuthorization
                    ) {
                    let receipt = try await pendingStore.retirePendingMetadata(
                        using: retainedRemoval,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    )
                    guard await transferState.recordMetadataAbsent(
                        receipt,
                        authorization: stateAuthorization
                    ) else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                } else {
                    guard case .retirePendingMetadata(let refreshedAuthority) =
                        try await failedStore.inspectTransferRecovery(
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ) else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                    switch try await pendingStore
                        .reconcilePendingMetadataRemoval(
                            retainedRemoval,
                            using: refreshedAuthority,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ) {
                    case .removalAuthorized(let refreshedRemoval):
                        guard await transferState
                            .refreshMetadataRemovalAuthorization(
                                refreshedRemoval,
                                authorization: stateAuthorization
                            ) else {
                            throw IOSAcceptedHistoryCoordinatorError
                                .localRecoveryPending
                        }
                    case .absenceConfirmed(let receipt):
                        guard await transferState
                            .recordRemovalAbsenceAfterAuthorityRefresh(
                                receipt,
                                authorization: stateAuthorization
                            ) else {
                            throw IOSAcceptedHistoryCoordinatorError
                                .localRecoveryPending
                        }
                    }
                }

            case .committingReady(let retainedReceipt):
                let receipt: IOSPendingRecordingMetadataAbsenceReceipt
                if retainedReceipt.authority.operationLeaseAuthorization
                    .provesSameActiveLease(
                        as: operationLeaseAuthorization
                    ) {
                    receipt = retainedReceipt
                } else {
                    let refreshedAuthority:
                        IOSFailedHistoryPendingMetadataRetirementAuthority
                    if failedStore.mutationInterlock.isBlocked {
                        refreshedAuthority = try await failedStore
                            .classifyReadyCommitUncertainty(
                                operationLeaseAuthorization:
                                    operationLeaseAuthorization
                            ).authority
                    } else {
                        guard case .retirePendingMetadata(let authority) =
                            try await failedStore.inspectTransferRecovery(
                                operationLeaseAuthorization:
                                    operationLeaseAuthorization
                            ) else {
                            throw IOSAcceptedHistoryCoordinatorError
                                .localRecoveryPending
                        }
                        refreshedAuthority = authority
                    }
                    guard case .absenceConfirmed(let refreshedReceipt) =
                        try await pendingStore.preparePendingMetadataRetirement(
                            using: refreshedAuthority,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ), await transferState.refreshReadyReceipt(
                            refreshedReceipt,
                            authorization: stateAuthorization
                        ) else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                    receipt = refreshedReceipt
                }
                try await failedStore.commitReady(using: receipt)
                guard await transferState.clearCompleted(
                    receipt,
                    authorization: stateAuthorization
                ) else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
            }
        }
        return completionResult
    }
}
