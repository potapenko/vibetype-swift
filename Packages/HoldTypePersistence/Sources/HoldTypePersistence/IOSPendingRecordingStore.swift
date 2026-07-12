import Foundation
import HoldTypeDomain

struct IOSPendingRecordingMetadataRetirementAuthorization:
    Equatable,
    Sendable {
    private enum Identity: Equatable, Sendable {
        case production(UUID)
        #if DEBUG
        case testing(UInt64)
        #endif
    }

    private let identity: Identity

    /// Production authority is minted only inside the Pending store file.
    fileprivate init() {
        identity = .production(UUID())
    }

    #if DEBUG
    /// Narrow deterministic seam for journal boundary tests.
    init(testingToken: UInt64) {
        identity = .testing(testingToken)
    }
    #endif
}

extension IOSPendingRecordingMetadataRetirementAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSPendingRecordingMetadataRetirementAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Store-minted authority for one exact foreground accepted-output audio
/// retirement. The filesystem consumes it only while the root operation lease
/// is active and returns directory-durable absence evidence for these exact
/// identifiers.
struct IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization:
    Equatable,
    Sendable {
    enum Purpose: UInt8, Equatable, Sendable {
        case acceptedOutput = 1
        case discard = 2
    }

    let purpose: Purpose
    let recording: IOSPendingRecording
    let attemptID: UUID
    let audioRelativeIdentifier: String
    let byteCount: Int64
    let mayCreateDurableIntent: Bool
    let expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    let expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    fileprivate init?(
        recording: IOSPendingRecording,
        purpose: Purpose = .acceptedOutput,
        mayCreateDurableIntent: Bool = true,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        let phaseIsEligible = switch purpose {
        case .acceptedOutput:
            recording.phase == .outputDelivery
        case .discard:
            recording.phase == .readyForTranscription
                || recording.phase == .awaitingRecovery
        }
        guard phaseIsEligible,
              operationLeaseAuthorization.provesActiveLease() else {
            return nil
        }
        self.purpose = purpose
        self.recording = recording
        attemptID = recording.attemptID
        audioRelativeIdentifier = recording.audioRelativeIdentifier
        byteCount = recording.byteCount
        self.mayCreateDurableIntent = mayCreateDurableIntent
        self.expectedRepositoryRoot = expectedRepositoryRoot
        self.expectedPendingStoreIdentity = expectedPendingStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    #if DEBUG
    init?(
        testing recording: IOSPendingRecording,
        purpose: Purpose = .acceptedOutput,
        mayCreateDurableIntent: Bool = true,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity? = nil,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity =
            IOSPendingRecordingStoreIdentity(),
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
            IOSAcceptedHistoryCapabilityOwnerIdentity(),
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        self.init(
            recording: recording,
            purpose: purpose,
            mayCreateDurableIntent: mayCreateDurableIntent,
            expectedRepositoryRoot: expectedRepositoryRoot,
            expectedPendingStoreIdentity: expectedPendingStoreIdentity,
            ownerIdentity: ownerIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }
    #endif

    func proves(
        recording: IOSPendingRecording,
        purpose expectedPurpose: Purpose = .acceptedOutput,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization expectedLease:
            IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        purpose == expectedPurpose
            && operationLeaseAuthorization.provesSameActiveLease(
                as: expectedLease
            )
            && attemptID == recording.attemptID
            && self.recording == recording
            && audioRelativeIdentifier == recording.audioRelativeIdentifier
            && byteCount == recording.byteCount
            && self.expectedRepositoryRoot == expectedRepositoryRoot
            && self.expectedPendingStoreIdentity
                == expectedPendingStoreIdentity
            && self.ownerIdentity == ownerIdentity
    }

    func provesSameRemovalIntent(
        as other: IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization
    ) -> Bool {
        attemptID == other.attemptID
            && purpose == other.purpose
            && recording == other.recording
            && audioRelativeIdentifier == other.audioRelativeIdentifier
            && byteCount == other.byteCount
            && expectedRepositoryRoot == other.expectedRepositoryRoot
            && expectedPendingStoreIdentity
                == other.expectedPendingStoreIdentity
            && ownerIdentity == other.ownerIdentity
    }
}

extension IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// One exact process-loss admission for accepted-output Pending retirement.
/// The store mints it only after proving that no process-local dispatch owner
/// survived and binds every later cleanup step to the same physical root and
/// active root-operation lease.
struct IOSPendingRecordingProcessLossAcceptedOutputRetirementAuthorization:
    Equatable,
    Sendable {
    fileprivate let recording: IOSPendingRecording
    fileprivate let expectedRepositoryRoot:
        IOSPersistenceRepositoryRootIdentity?
    fileprivate let issuerStoreIdentity: IOSPendingRecordingStoreIdentity
    fileprivate let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    fileprivate let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    fileprivate init?(
        recording: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        issuerStoreIdentity: IOSPendingRecordingStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        guard recording.phase == .outputDelivery,
              recording.transcriptionID != nil,
              operationLeaseAuthorization.provesActiveLease() else {
            return nil
        }
        self.recording = recording
        self.expectedRepositoryRoot = expectedRepositoryRoot
        self.issuerStoreIdentity = issuerStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    fileprivate func proves(
        recording expected: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        issuerStoreIdentity expectedStoreIdentity:
            IOSPendingRecordingStoreIdentity,
        ownerIdentity expectedOwnerIdentity:
            IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization expectedLease:
            IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        recording == expected
            && self.expectedRepositoryRoot == expectedRepositoryRoot
            && issuerStoreIdentity == expectedStoreIdentity
            && ownerIdentity == expectedOwnerIdentity
            && operationLeaseAuthorization.provesSameActiveLease(
                as: expectedLease
            )
    }
}

extension IOSPendingRecordingProcessLossAcceptedOutputRetirementAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSPendingRecordingProcessLossAcceptedOutputRetirementAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Content-free proof that the canonical Pending journal was absent on both
/// sides of a successful directory durability barrier. The foreground facade
/// consumes this only while the issuing root-operation lease is still active.
struct IOSForegroundVoicePendingJournalAbsenceAuthorization:
    Equatable,
    Sendable {
    private let evidence: IOSPendingRecordingJournalMetadataAbsenceEvidence
    private let expectedRepositoryRoot:
        IOSPersistenceRepositoryRootIdentity?
    private let issuerStoreIdentity: IOSPendingRecordingStoreIdentity
    private let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    private let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    fileprivate init?(
        evidence: IOSPendingRecordingJournalMetadataAbsenceEvidence,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        issuerStoreIdentity: IOSPendingRecordingStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        guard operationLeaseAuthorization.provesActiveLease(),
              evidence.provesPreexistingAbsence,
              evidence.provesCanonicalPendingRecordingPath,
              expectedRepositoryRoot.map({
                  evidence.binding.repositoryRoot == $0
              }) ?? true else {
            return nil
        }
        self.evidence = evidence
        self.expectedRepositoryRoot = expectedRepositoryRoot
        self.issuerStoreIdentity = issuerStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    func provesAbsence(
        issuerStoreIdentity expectedStoreIdentity:
            IOSPendingRecordingStoreIdentity,
        ownerIdentity expectedOwnerIdentity:
            IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization expectedLease:
            IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        issuerStoreIdentity == expectedStoreIdentity
            && ownerIdentity == expectedOwnerIdentity
            && operationLeaseAuthorization.provesSameActiveLease(
                as: expectedLease
            )
            && evidence.provesPreexistingAbsence
            && evidence.provesCanonicalPendingRecordingPath
            && (expectedRepositoryRoot.map({
                evidence.binding.repositoryRoot == $0
            }) ?? true)
    }
}

extension IOSForegroundVoicePendingJournalAbsenceAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSForegroundVoicePendingJournalAbsenceAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Store-level proof that the exact foreground Pending journal is durably
/// absent. It wraps the descriptor-derived C4.2B evidence and binds it to the
/// issuing store, physical root, owner, and active root-operation lease.
struct IOSPendingRecordingAcceptedOutputJournalAbsenceEvidence:
    Equatable,
    Sendable {
    private let recording: IOSPendingRecording
    private let evidence: IOSPendingRecordingJournalMetadataAbsenceEvidence
    private let expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    private let issuerStoreIdentity: IOSPendingRecordingStoreIdentity
    private let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    private let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        recording: IOSPendingRecording,
        source: IOSPendingRecordingJournalMetadataSnapshot?,
        evidence: IOSPendingRecordingJournalMetadataAbsenceEvidence,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        issuerStoreIdentity: IOSPendingRecordingStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        guard operationLeaseAuthorization.provesActiveLease(),
              evidence.provesCanonicalPendingRecordingPath,
              expectedRepositoryRoot.map({
                  evidence.binding.repositoryRoot == $0
              }) ?? true else {
            return nil
        }
        if let source {
            guard source.recording == recording,
                  evidence.provesRemoval(of: source) else {
                return nil
            }
        } else {
            guard evidence.provesPreexistingAbsence else { return nil }
        }
        self.recording = recording
        self.evidence = evidence
        self.expectedRepositoryRoot = expectedRepositoryRoot
        self.issuerStoreIdentity = issuerStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    func provesAbsence(
        of expected: IOSPendingRecording,
        issuerStoreIdentity expectedStoreIdentity:
            IOSPendingRecordingStoreIdentity,
        ownerIdentity expectedOwnerIdentity:
            IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization expectedLease:
            IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        recording == expected
            && issuerStoreIdentity == expectedStoreIdentity
            && ownerIdentity == expectedOwnerIdentity
            && operationLeaseAuthorization.provesSameActiveLease(
                as: expectedLease
            )
            && evidence.provesCanonicalPendingRecordingPath
            && (expectedRepositoryRoot.map({
                evidence.binding.repositoryRoot == $0
            }) ?? true)
    }
}

extension IOSPendingRecordingAcceptedOutputJournalAbsenceEvidence:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSPendingRecordingAcceptedOutputJournalAbsenceEvidence(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSPendingFailedHistoryTransferPreparationMint: Sendable {
    fileprivate init() {}

    #if DEBUG
    init(testingToken: Void) { _ = testingToken }
    #endif
}

struct IOSPendingFailedHistoryTransferSourceMint: Sendable {
    fileprivate init() {}

    #if DEBUG
    init(testingToken: Void) { _ = testingToken }
    #endif
}

struct IOSPendingRecordingMetadataAbsenceReceiptMint: Sendable {
    fileprivate init() {}

    #if DEBUG
    init(testingToken: Void) { _ = testingToken }
    #endif
}

struct IOSPendingRecordingMetadataRemovalAuthorizationMint: Sendable {
    fileprivate init() {}

    #if DEBUG
    init(testingToken: Void) { _ = testingToken }
    #endif
}

struct IOSProtectedAudioNamespaceInventoryMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryValidatedRowAudioMint: Sendable {
    fileprivate init() {}
}

struct IOSPendingRecordingHeldAudioLeaseMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryRetryAudioSourceMint: Sendable {
    fileprivate init() {}
}

struct IOSFailedHistoryAudioCleanupReceiptMint: Sendable {
    fileprivate init() {}

    #if DEBUG
    init(testingToken: Void) { _ = testingToken }
    #endif
}

struct IOSPendingRecordingProtectedAudioCleanupAuthorization:
    Equatable,
    Sendable {
    let cleanupAuthorization: IOSFailedHistoryAudioCleanupAuthorization
    let inventory: IOSProtectedAudioNamespaceInventory

    fileprivate init?(
        cleanupAuthorization:
            IOSFailedHistoryAudioCleanupAuthorization,
        inventory: IOSProtectedAudioNamespaceInventory
    ) {
        guard cleanupAuthorization.operationLeaseAuthorization
                .provesActiveLease(),
              cleanupAuthorization.failedInventory
                == inventory.failedInventory,
              cleanupAuthorization.failedStoreIdentity
                == inventory.failedStoreIdentity,
              cleanupAuthorization.expectedPendingStoreIdentity
                == inventory.expectedPendingStoreIdentity,
              cleanupAuthorization.ownerIdentity == inventory.ownerIdentity,
              cleanupAuthorization.repositoryBinding
                == inventory.repositoryBinding,
              cleanupAuthorization.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: inventory.operationLeaseAuthorization
                ),
              inventory.artifacts.contains(where: { artifact in
                  guard case .tombstone(
                      let attemptID,
                      let relativeIdentifier,
                      let byteCount
                  ) = artifact else {
                      return false
                  }
                  return attemptID
                          == cleanupAuthorization.tombstone.attemptID
                      && relativeIdentifier
                          == cleanupAuthorization.tombstone
                              .audioRelativeIdentifier
                      && byteCount
                          == cleanupAuthorization.tombstone.byteCount
              }) else {
            return nil
        }
        self.cleanupAuthorization = cleanupAuthorization
        self.inventory = inventory
    }

    #if DEBUG
    init?(
        testing cleanupAuthorization:
            IOSFailedHistoryAudioCleanupAuthorization,
        inventory: IOSProtectedAudioNamespaceInventory
    ) {
        self.init(
            cleanupAuthorization: cleanupAuthorization,
            inventory: inventory
        )
    }
    #endif

    func provesSameCleanup(
        as other: IOSPendingRecordingProtectedAudioCleanupAuthorization
    ) -> Bool {
        cleanupAuthorization.operationID
                == other.cleanupAuthorization.operationID
            && cleanupAuthorization.failedSource
                == other.cleanupAuthorization.failedSource
            && cleanupAuthorization.tombstone
                == other.cleanupAuthorization.tombstone
            && cleanupAuthorization.outcome
                == other.cleanupAuthorization.outcome
            && cleanupAuthorization.purpose
                == other.cleanupAuthorization.purpose
            && cleanupAuthorization.failedStoreIdentity
                == other.cleanupAuthorization.failedStoreIdentity
            && cleanupAuthorization.expectedPendingStoreIdentity
                == other.cleanupAuthorization.expectedPendingStoreIdentity
            && cleanupAuthorization.ownerIdentity
                == other.cleanupAuthorization.ownerIdentity
            && cleanupAuthorization.repositoryBinding
                == other.cleanupAuthorization.repositoryBinding
            && inventory.pendingSource == other.inventory.pendingSource
    }
}

extension IOSPendingRecordingProtectedAudioCleanupAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSPendingRecordingProtectedAudioCleanupAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSPendingRecordingStoreIdentity: Equatable, Sendable {
    private let value = UUID()
}

extension IOSPendingRecordingStoreIdentity: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSPendingRecordingStoreIdentity(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSPendingRecordingCanonicalDestinationDisposition: Equatable, Sendable {
    case exactDestination
    case provenAbsent
}

/// A destination answer is useful to process-loss recovery only while it is
/// bound to the same Pending value, physical repository root, Store owner, and
/// live root-operation lease that will consume it.
private struct IOSPendingRecordingCanonicalDestinationEvidence:
    Equatable,
    Sendable {
    let disposition: IOSPendingRecordingCanonicalDestinationDisposition
    private let recording: IOSPendingRecording
    private let expectedRepositoryRoot:
        IOSPersistenceRepositoryRootIdentity?
    private let issuerStoreIdentity: IOSPendingRecordingStoreIdentity
    private let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    private let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    init?(
        disposition: IOSPendingRecordingCanonicalDestinationDisposition,
        recording: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        issuerStoreIdentity: IOSPendingRecordingStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        guard recording.transcriptionID != nil,
              operationLeaseAuthorization.provesActiveLease() else {
            return nil
        }
        self.disposition = disposition
        self.recording = recording
        self.expectedRepositoryRoot = expectedRepositoryRoot
        self.issuerStoreIdentity = issuerStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    func proves(
        recording expected: IOSPendingRecording,
        expectedRepositoryRoot:
            IOSPersistenceRepositoryRootIdentity?,
        issuerStoreIdentity expectedStoreIdentity:
            IOSPendingRecordingStoreIdentity,
        ownerIdentity expectedOwnerIdentity:
            IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization expectedLease:
            IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        recording == expected
            && self.expectedRepositoryRoot == expectedRepositoryRoot
            && issuerStoreIdentity == expectedStoreIdentity
            && ownerIdentity == expectedOwnerIdentity
            && operationLeaseAuthorization.provesSameActiveLease(
                as: expectedLease
            )
    }
}

protocol IOSPendingRecordingDestinationInspecting: Sendable {
    func inspectCanonicalDestination(
        for recording: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingCanonicalDestinationDisposition
}

private struct ClosureIOSPendingRecordingDestinationInspector:
    IOSPendingRecordingDestinationInspecting {
    let canonicalDestinationExists: @Sendable (UUID, UUID) throws -> Bool

    func inspectCanonicalDestination(
        for recording: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingCanonicalDestinationDisposition {
        _ = expectedRepositoryRoot
        guard let transcriptionID = recording.transcriptionID else {
            throw IOSPendingRecordingError.invalidTransition
        }
        return try canonicalDestinationExists(
            recording.attemptID,
            transcriptionID
        ) ? .exactDestination : .provenAbsent
    }
}

struct IOSPendingRecordingProductionDestinationInspector:
    IOSPendingRecordingDestinationInspecting {
    private let acceptedOutputDeliveryJournal:
        FoundationIOSAcceptedOutputDeliveryJournalRepository
    private let configuredExpectedRepositoryRoot:
        IOSPersistenceRepositoryRootIdentity?

    init(
        applicationSupportDirectoryURL: URL,
        repositoryGuard: IOSAcceptedHistoryCoordinatorRepositoryGuard
    ) {
        acceptedOutputDeliveryJournal =
            FoundationIOSAcceptedOutputDeliveryJournalRepository(
                applicationSupportDirectoryURL:
                    applicationSupportDirectoryURL,
                repositoryGuard: repositoryGuard
            )
        configuredExpectedRepositoryRoot =
            repositoryGuard.expectedPhysicalRootIdentity
    }

    func inspectCanonicalDestination(
        for recording: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingCanonicalDestinationDisposition {
        guard expectedRepositoryRoot == configuredExpectedRepositoryRoot,
              let transcriptionID = recording.transcriptionID else {
            throw IOSPendingRecordingError.invalidTransition
        }
        guard let snapshot = try acceptedOutputDeliveryJournal.load() else {
            try acceptedOutputDeliveryJournal.confirmCanonicalAbsence()
            return .provenAbsent
        }
        let delivery = snapshot.record
        let attemptMatches = delivery.attemptID == recording.attemptID
        let transcriptMatches = delivery.transcriptID == transcriptionID
        if attemptMatches || transcriptMatches {
            guard attemptMatches,
                  transcriptMatches,
                  delivery.failedRetryID == nil,
                  delivery.outputIntent == recording.outputIntent,
                  delivery.historyWrite.map({ historyWrite in
                      IOSAcceptedOutputDeliveryValidation.bytesEqual(
                          historyWrite.transcriptionModel,
                          recording.transcriptionModel
                      )
                          && historyWrite.transcriptionLanguageCode
                              == recording.transcriptionLanguageCode
                          && historyWrite.durationMilliseconds
                              == recording.durationMilliseconds
                  }) ?? true else {
                throw IOSPendingRecordingError.invalidTransition
            }
        }

        // An identical CAS rewrite confirms both a visible exact destination
        // and a visible unrelated record on the configured durable path. A
        // plain read is not sufficient process-loss evidence.
        _ = try acceptedOutputDeliveryJournal.replace(
            delivery,
            expected: snapshot
        )
        guard attemptMatches else { return .provenAbsent }
        guard delivery.deliveryState != .discarded,
              delivery.acceptedText != nil else {
            return .provenAbsent
        }
        return .exactDestination
    }
}

private struct UnconfiguredIOSPendingRecordingDestinationInspector:
    IOSPendingRecordingDestinationInspecting {
    func inspectCanonicalDestination(
        for recording: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingCanonicalDestinationDisposition {
        _ = recording
        _ = expectedRepositoryRoot
        throw IOSPendingRecordingError.invalidTransition
    }
}

enum IOSPendingRecordingContainingAppRecoveryResolution: Equatable, Sendable {
    case awaitingRecovery
    case completedAcceptedOutput
}

private struct IOSPendingRecordingDispatchIdentity: Hashable, Sendable {
    let attemptID: UUID
    let transcriptionID: UUID
}

#if DEBUG
/// Unit-test-only sentinel used by the raw fake-backed Store initializer.
/// Production initializers always require the root-owned Failed store.
private struct IOSPendingRecordingUnconfiguredFailedOwnershipInspector:
    IOSPendingRecordingFailedOwnershipInspecting {
    let failedStoreIdentity = IOSFailedHistoryStoreIdentity()

    func sealProtectedAudioInventory(
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryProtectedAudioInventory {
        _ = expectedPendingStoreIdentity
        _ = operationLeaseAuthorization
        throw IOSFailedHistoryError.compareAndSwapFailed
    }

    func revalidateProtectedAudioInventory(
        _ inventory: IOSFailedHistoryProtectedAudioInventory,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws {
        _ = inventory
        _ = operationLeaseAuthorization
        throw IOSFailedHistoryError.compareAndSwapFailed
    }

    func provePendingOwnershipAbsent(
        for pendingKey: IOSFailedHistoryPendingOwnershipKey,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryPendingOwnershipAbsenceProof {
        _ = pendingKey
        _ = expectedPendingStoreIdentity
        _ = operationLeaseAuthorization
        throw IOSFailedHistoryError.compareAndSwapFailed
    }
}
#endif

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

    func hasLiveOwner() -> Bool {
        lock.withLock { !identities.isEmpty }
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
    private struct ActiveDispatchIdentity: Equatable, Sendable {
        let attemptID: UUID
        let transcriptionID: UUID
    }

    nonisolated let capabilityOwnerIdentity:
        IOSAcceptedHistoryCapabilityOwnerIdentity
    nonisolated let storeIdentity: IOSPendingRecordingStoreIdentity
    private nonisolated let operationGateBinding:
        IOSPersistenceOperationGateBinding
    private let journal: any IOSPendingRecordingJournalStoring
    private let audioFileSystem: any IOSPendingRecordingAudioFileSystem
    private let destinationInspector: any IOSPendingRecordingDestinationInspecting
    private let operationGate: IOSPersistenceOperationGate
    private let liveOwnerRegistry: IOSPendingRecordingLiveOwnerRegistry
    nonisolated let failedHistoryRetryState:
        IOSFailedHistoryRetryLiveOwnerState
    private let repositoryGuard:
        IOSAcceptedHistoryCoordinatorRepositoryGuard?
    private let failedHistoryMutationInterlock:
        IOSFailedHistoryMutationInterlock
    private let failedOwnershipInspector:
        any IOSPendingRecordingFailedOwnershipInspecting
    nonisolated let expectedFailedStoreIdentity:
        IOSFailedHistoryStoreIdentity
    #if DEBUG
    private let bypassFailedOwnershipInspectionForTesting: Bool
    #endif

    nonisolated var failedMutationInterlock:
        IOSFailedHistoryMutationInterlock {
        failedHistoryMutationInterlock
    }
    private let now: @Sendable () -> Date

    private var activeDispatchIdentity: ActiveDispatchIdentity?
    private var activeDispatchAuthorization: IOSPendingTranscriptionAuthorization?

    public init(applicationSupportDirectoryURL: URL) {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry
            .shared
        let context = registry.context(for: applicationSupportDirectoryURL)
        let operationGate = context.operationGate
        let repositoryGuard = IOSAcceptedHistoryCoordinatorRepositoryGuard(
            expectedBinding: context.repositoryBinding,
            repositoryIdentityState: context.repositoryIdentityState
        )
        let repositoryGuardAccepted = repositoryGuard.bind(
            IOSAcceptedHistoryCoordinatorRepositoryRegistration(
                registry: registry,
                context: context,
                applicationSupportDirectoryURL:
                    applicationSupportDirectoryURL
            )
        )
        journal = FoundationIOSPendingRecordingJournalRepository(
            applicationSupportDirectoryURL:
                context.applicationSupportDirectoryURL,
            repositoryGuard: repositoryGuard
        )
        audioFileSystem = FoundationIOSPendingRecordingAudioFileSystem(
            applicationSupportDirectoryURL:
                context.applicationSupportDirectoryURL,
            mediaValidator: AudioToolboxIOSPendingRecordingMediaValidator(
                workerGate:
                    context.pendingRecordingMediaValidationWorkerGate
            ),
            expectedRepositoryRoot:
                repositoryGuard.expectedPhysicalRootIdentity,
            onRepositoryIdentityMismatch: {
                repositoryGuard.invalidate()
            }
        )
        destinationInspector =
            IOSPendingRecordingProductionDestinationInspector(
                applicationSupportDirectoryURL:
                    context.applicationSupportDirectoryURL,
                repositoryGuard: repositoryGuard
            )
        self.operationGate = operationGate
        liveOwnerRegistry = context.pendingRecordingLiveOwnerRegistry
        failedHistoryRetryState = context.failedHistoryRetryState
        now = { Date() }
        capabilityOwnerIdentity = context.ownerIdentity
        storeIdentity = context.pendingRecordingStoreIdentity
        operationGateBinding = IOSPersistenceOperationGateBinding(
            identity: operationGate.identity
        )
        self.repositoryGuard = repositoryGuard
        failedHistoryMutationInterlock =
            context.failedHistoryMutationInterlock
        failedOwnershipInspector = context.failedHistoryStore
        expectedFailedStoreIdentity = context.failedHistoryStore.storeIdentity
        #if DEBUG
        bypassFailedOwnershipInspectionForTesting = false
        #endif
        if !repositoryGuardAccepted {
            context.repositoryIdentityState.markConflicted()
        }
    }

    init(
        applicationSupportDirectoryURL: URL,
        canonicalDestinationExists:
            @escaping @Sendable (UUID, UUID) throws -> Bool
    ) {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry
            .shared
        let context = registry.context(for: applicationSupportDirectoryURL)
        let operationGate = context.operationGate
        let repositoryGuard = IOSAcceptedHistoryCoordinatorRepositoryGuard(
            expectedBinding: context.repositoryBinding,
            repositoryIdentityState: context.repositoryIdentityState
        )
        let repositoryGuardAccepted = repositoryGuard.bind(
            IOSAcceptedHistoryCoordinatorRepositoryRegistration(
                registry: registry,
                context: context,
                applicationSupportDirectoryURL:
                    applicationSupportDirectoryURL
            )
        )
        journal = FoundationIOSPendingRecordingJournalRepository(
            applicationSupportDirectoryURL:
                context.applicationSupportDirectoryURL,
            repositoryGuard: repositoryGuard
        )
        audioFileSystem = FoundationIOSPendingRecordingAudioFileSystem(
            applicationSupportDirectoryURL:
                context.applicationSupportDirectoryURL,
            mediaValidator: AudioToolboxIOSPendingRecordingMediaValidator(
                workerGate:
                    context.pendingRecordingMediaValidationWorkerGate
            ),
            expectedRepositoryRoot:
                repositoryGuard.expectedPhysicalRootIdentity,
            onRepositoryIdentityMismatch: {
                repositoryGuard.invalidate()
            }
        )
        destinationInspector = ClosureIOSPendingRecordingDestinationInspector(
            canonicalDestinationExists: canonicalDestinationExists
        )
        self.operationGate = operationGate
        liveOwnerRegistry = context.pendingRecordingLiveOwnerRegistry
        failedHistoryRetryState = context.failedHistoryRetryState
        now = { Date() }
        capabilityOwnerIdentity = context.ownerIdentity
        storeIdentity = context.pendingRecordingStoreIdentity
        operationGateBinding = IOSPersistenceOperationGateBinding(
            identity: operationGate.identity
        )
        self.repositoryGuard = repositoryGuard
        failedHistoryMutationInterlock =
            context.failedHistoryMutationInterlock
        failedOwnershipInspector = context.failedHistoryStore
        expectedFailedStoreIdentity = context.failedHistoryStore.storeIdentity
        #if DEBUG
        bypassFailedOwnershipInspectionForTesting = false
        #endif
        if !repositoryGuardAccepted {
            context.repositoryIdentityState.markConflicted()
        }
    }

    init(
        applicationSupportDirectoryURL: URL,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        storeIdentity: IOSPendingRecordingStoreIdentity,
        operationGate: IOSPersistenceOperationGate,
        liveOwnerRegistry: IOSPendingRecordingLiveOwnerRegistry,
        // Production passes the physical-root context's canonical state. The
        // default preserves isolated internal test/injection construction.
        failedHistoryRetryState: IOSFailedHistoryRetryLiveOwnerState =
            IOSFailedHistoryRetryLiveOwnerState(),
        mediaValidationWorkerGate:
            AudioToolboxMediaValidationWorkerGate,
        repositoryGuard: IOSAcceptedHistoryCoordinatorRepositoryGuard,
        failedHistoryMutationInterlock:
            IOSFailedHistoryMutationInterlock,
        failedOwnershipInspector:
            any IOSPendingRecordingFailedOwnershipInspecting
    ) {
        journal = FoundationIOSPendingRecordingJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            repositoryGuard: repositoryGuard
        )
        audioFileSystem = FoundationIOSPendingRecordingAudioFileSystem(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            mediaValidator: AudioToolboxIOSPendingRecordingMediaValidator(
                workerGate: mediaValidationWorkerGate
            ),
            expectedRepositoryRoot:
                repositoryGuard.expectedPhysicalRootIdentity,
            onRepositoryIdentityMismatch: {
                repositoryGuard.invalidate()
            }
        )
        destinationInspector =
            IOSPendingRecordingProductionDestinationInspector(
                applicationSupportDirectoryURL:
                    applicationSupportDirectoryURL,
                repositoryGuard: repositoryGuard
            )
        self.operationGate = operationGate
        self.liveOwnerRegistry = liveOwnerRegistry
        self.failedHistoryRetryState = failedHistoryRetryState
        now = { Date() }
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        self.storeIdentity = storeIdentity
        operationGateBinding = IOSPersistenceOperationGateBinding(
            identity: operationGate.identity
        )
        self.repositoryGuard = repositoryGuard
        self.failedHistoryMutationInterlock =
            failedHistoryMutationInterlock
        self.failedOwnershipInspector = failedOwnershipInspector
        expectedFailedStoreIdentity =
            failedOwnershipInspector.failedStoreIdentity
        #if DEBUG
        bypassFailedOwnershipInspectionForTesting = false
        #endif
    }

    #if DEBUG
    init(
        journal: any IOSPendingRecordingJournalStoring,
        audioFileSystem: any IOSPendingRecordingAudioFileSystem,
        destinationInspector: any IOSPendingRecordingDestinationInspecting =
            UnconfiguredIOSPendingRecordingDestinationInspector(),
        operationGate: IOSPersistenceOperationGate =
            IOSPersistenceOperationGate(),
        liveOwnerRegistry: IOSPendingRecordingLiveOwnerRegistry =
            IOSPendingRecordingLiveOwnerRegistry(),
        failedHistoryRetryState: IOSFailedHistoryRetryLiveOwnerState =
            IOSFailedHistoryRetryLiveOwnerState(),
        capabilityOwnerIdentity:
            IOSAcceptedHistoryCapabilityOwnerIdentity =
                IOSAcceptedHistoryCapabilityOwnerIdentity(),
        storeIdentity: IOSPendingRecordingStoreIdentity =
            IOSPendingRecordingStoreIdentity(),
        repositoryGuard:
            IOSAcceptedHistoryCoordinatorRepositoryGuard? = nil,
        failedHistoryMutationInterlock:
            IOSFailedHistoryMutationInterlock =
                IOSFailedHistoryMutationInterlock(),
        failedOwnershipInspector:
            (any IOSPendingRecordingFailedOwnershipInspecting)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.journal = journal
        self.audioFileSystem = audioFileSystem
        self.destinationInspector = destinationInspector
        self.operationGate = operationGate
        self.liveOwnerRegistry = liveOwnerRegistry
        self.failedHistoryRetryState = failedHistoryRetryState
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        self.storeIdentity = storeIdentity
        self.now = now
        operationGateBinding = IOSPersistenceOperationGateBinding(
            identity: operationGate.identity
        )
        self.repositoryGuard = repositoryGuard
        self.failedHistoryMutationInterlock =
            failedHistoryMutationInterlock
        let resolvedInspector = failedOwnershipInspector
            ?? IOSPendingRecordingUnconfiguredFailedOwnershipInspector()
        self.failedOwnershipInspector = resolvedInspector
        expectedFailedStoreIdentity = resolvedInspector.failedStoreIdentity
        bypassFailedOwnershipInspectionForTesting =
            failedOwnershipInspector == nil
    }
    #endif

    nonisolated func bindOperationGateIdentity(
        _ identity: IOSPersistenceOperationGateIdentity
    ) -> Bool {
        operationGateBinding.bind(identity)
    }

    public func prepare(
        _ preparation: IOSPendingRecordingPreparation
    ) async throws -> IOSPendingRecording {
        try await performExclusiveOperation { [self] authorization in
            try await performPrepare(
                preparation,
                operationLeaseAuthorization: authorization
            )
        }
    }

    public func load() async throws -> IOSPendingRecordingObservation? {
        try await performExclusiveOperation { [self] authorization in
            try await performLoad(
                operationLeaseAuthorization: authorization
            )
        }
    }

    /// Coordinator-only read that consumes the already active shared root
    /// lease instead of attempting a reentrant gate acquisition.
    func loadForContainingAppBoundary(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingRecordingObservation? {
        try await performLoad(
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    public func beginTranscription(
        expected: IOSPendingRecordingCASExpectation,
        transcriptionID: UUID
    ) async throws -> IOSPendingTranscriptionHandoff {
        try await performExclusiveOperation { [self] authorization in
            try await performBeginTranscription(
                expected: expected,
                transcriptionID: transcriptionID,
                operationLeaseAuthorization: authorization
            )
        }
    }

    public func retryTranscription(
        expected: IOSPendingRecordingCASExpectation,
        transcriptionID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSPendingTranscriptionHandoff {
        try await performExclusiveOperation { [self] authorization in
            try await performRetryTranscription(
                expected: expected,
                transcriptionID: transcriptionID,
                transcriptionConfiguration: transcriptionConfiguration,
                operationLeaseAuthorization: authorization
            )
        }
    }

    public func markPostProcessing(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await performExclusiveOperation { [self] authorization in
            try await performAdvance(
                expected: expected,
                source: .transcribing,
                destination: .postProcessing,
                operationLeaseAuthorization: authorization
            )
        }
    }

    public func markOutputDelivery(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await performExclusiveOperation { [self] authorization in
            try await performAdvance(
                expected: expected,
                source: .postProcessing,
                destination: .outputDelivery,
                operationLeaseAuthorization: authorization
            )
        }
    }

    public func markAwaitingRecovery(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await performExclusiveOperation { [self] authorization in
            try await performMarkAwaitingRecovery(
                expected: expected,
                operationLeaseAuthorization: authorization
            )
        }
    }

    /// Converts an uncertain pre-destination phase into explicit recovery.
    /// The containing-app composition root must call this only after relaunch.
    public func recoverAfterProcessLoss(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording {
        try await performExclusiveOperation { [self] authorization in
            try await performRecoverAfterProcessLoss(
                expected: expected,
                operationLeaseAuthorization: authorization
            )
        }
    }

    func recoverContainingAppAfterProcessLoss(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecordingContainingAppRecoveryResolution {
        try await performExclusiveOperation { [self] authorization in
            try await performContainingAppRecoveryAfterProcessLoss(
                expected: expected,
                operationLeaseAuthorization: authorization
            )
        }
    }

    func completeAcceptedOutputForContainingAppLaunchIfPresent()
        async throws -> Bool {
        try await performExclusiveOperation { [self] authorization in
            try await performAcceptedOutputLaunchCompletionIfPresent(
                operationLeaseAuthorization: authorization
            )
        }
    }

    func completeAcceptedOutputForContainingAppLaunchIfPresent(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> Bool {
        try await performAcceptedOutputLaunchCompletionIfPresent(
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func removeForegroundVoiceAcceptedOutputAudio(
        expected: IOSPendingRecording,
        destinationAuthorization:
            IOSForegroundVoiceAcceptedDestinationAuthorization,
        deliveryStoreIdentity:
            IOSAcceptedOutputDeliveryStoreIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSForegroundVoicePendingAudioRemovalAuthorization {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              expected.phase == .outputDelivery,
              destinationAuthorization.provesDestination(
                  for: expected,
                  storeIdentity: deliveryStoreIdentity,
                  ownerIdentity: capabilityOwnerIdentity,
                  operationLeaseAuthorization:
                      operationLeaseAuthorization
              ) else {
            throw IOSPendingRecordingError.invalidTransition
        }
        let current = try performRepositoryBoundary { _ in
            try journal.load()
        }
        if let current {
            guard current == expected else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
            try retireForegroundVoiceDispatch(for: current)
        } else {
            guard let transcriptionID = expected.transcriptionID,
                  activeDispatchIdentity == nil,
                  liveOwnerRegistry.isRetired(
                      attemptID: expected.attemptID,
                      transcriptionID: transcriptionID
                  ) else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
        }
        return try await performForegroundVoiceAcceptedOutputAudioRemoval(
            expected: expected,
            processLossAuthorization: nil,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    /// Explicit relaunch-only path. A surviving live process owner prevents
    /// admission; a fresh process may retire only the exact destination-bound
    /// outputDelivery owner under the current root lease.
    func removeForegroundVoiceAcceptedOutputAudioAfterProcessLoss(
        expected: IOSPendingRecording,
        destinationAuthorization:
            IOSForegroundVoiceAcceptedDestinationAuthorization,
        deliveryStoreIdentity:
            IOSAcceptedOutputDeliveryStoreIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSForegroundVoicePendingAudioRemovalAuthorization {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              destinationAuthorization.provesDestination(
                  for: expected,
                  storeIdentity: deliveryStoreIdentity,
                  ownerIdentity: capabilityOwnerIdentity,
                  operationLeaseAuthorization:
                      operationLeaseAuthorization
              ), let current = try performRepositoryBoundary({ _ in
                  try journal.load()
              }), current == expected else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        let processLossAuthorization = try
            prepareProcessLossAcceptedOutputRetirement(
                current,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        return try await performForegroundVoiceAcceptedOutputAudioRemoval(
            expected: current,
            processLossAuthorization: processLossAuthorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    /// Proves the content-free canonical Pending-journal absence checkpoint
    /// that a foreground facade needs before exposing a delivery as ready when
    /// no Pending value can be loaded after relaunch.
    func proveForegroundVoicePendingJournalAbsent(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSForegroundVoicePendingJournalAbsenceAuthorization {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              activeDispatchIdentity == nil,
              activeDispatchAuthorization == nil,
              !liveOwnerRegistry.hasLiveOwner() else {
            throw IOSPendingRecordingError.invalidTransition
        }
        let journalAuthorization =
            IOSPendingRecordingMetadataRetirementAuthorization()
        return try performRepositoryBoundary { expectedRoot in
            guard try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            ) == nil else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
            let evidence = try journal.proveMetadataAbsent(
                expectedRepositoryRoot: expectedRoot,
                authorization: journalAuthorization
            )
            guard let authorization =
                    IOSForegroundVoicePendingJournalAbsenceAuthorization(
                        evidence: evidence,
                        expectedRepositoryRoot: expectedRoot,
                        issuerStoreIdentity: storeIdentity,
                        ownerIdentity: capabilityOwnerIdentity,
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    ) else {
                throw IOSPendingRecordingError.journalCommitUncertain
            }
            return authorization
        }
    }

    func retireForegroundVoiceAcceptedOutputJournal(
        expected: IOSPendingRecording,
        destinationAuthorization:
            IOSForegroundVoiceAcceptedDestinationAuthorization,
        audioRemovalAuthorization:
            IOSForegroundVoicePendingAudioRemovalAuthorization,
        deliveryStoreIdentity:
            IOSAcceptedOutputDeliveryStoreIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              expected.phase == .outputDelivery,
              destinationAuthorization.provesDestination(
                  for: expected,
                  storeIdentity: deliveryStoreIdentity,
                  ownerIdentity: capabilityOwnerIdentity,
                  operationLeaseAuthorization:
                      operationLeaseAuthorization
              ),
              audioRemovalAuthorization.provesRemoval(
                  for: expected,
                  storeIdentity: storeIdentity,
                  ownerIdentity: capabilityOwnerIdentity,
                  operationLeaseAuthorization:
                      operationLeaseAuthorization
              ),
              activeDispatchIdentity == nil,
              let transcriptionID = expected.transcriptionID,
              liveOwnerRegistry.isRetired(
                  attemptID: expected.attemptID,
                  transcriptionID: transcriptionID
              ) else {
            throw IOSPendingRecordingError.invalidTransition
        }
        try await performForegroundVoiceAcceptedOutputJournalRetirement(
            expected: expected,
            audioRemovalAuthorization: audioRemovalAuthorization,
            processLossAuthorization: nil,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    private func performForegroundVoiceAcceptedOutputAudioRemoval(
        expected: IOSPendingRecording,
        processLossAuthorization:
            IOSPendingRecordingProcessLossAcceptedOutputRetirementAuthorization?,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSForegroundVoicePendingAudioRemovalAuthorization {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              expected.phase == .outputDelivery,
              activeDispatchIdentity == nil,
              let transcriptionID = expected.transcriptionID,
              liveOwnerRegistry.isRetired(
                  attemptID: expected.attemptID,
                  transcriptionID: transcriptionID
              ) else {
            throw IOSPendingRecordingError.invalidTransition
        }
        let current = try performRepositoryBoundary { _ in
            try journal.load()
        }
        if let current {
            guard current == expected else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
        }
        if let processLossAuthorization {
            let expectedRoot = try currentRepositoryBinding()?
                .physicalRootIdentity
            guard processLossAuthorization.proves(
                recording: expected,
                expectedRepositoryRoot: expectedRoot,
                issuerStoreIdentity: storeIdentity,
                ownerIdentity: capabilityOwnerIdentity,
                operationLeaseAuthorization: operationLeaseAuthorization
            ) else {
                throw IOSPendingRecordingError.invalidTransition
            }
        }
        try await requireFailedOwnershipAbsent(
            for: expected,
            operationLeaseAuthorization: operationLeaseAuthorization
        )

        do {
            _ = try await performRepositoryBoundary { expectedRoot in
                guard let removalAuthorization =
                        IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization(
                            recording: expected,
                            purpose: .acceptedOutput,
                            mayCreateDurableIntent: current != nil,
                            expectedRepositoryRoot: expectedRoot,
                            expectedPendingStoreIdentity: storeIdentity,
                            ownerIdentity: capabilityOwnerIdentity,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ) else {
                    throw IOSPendingRecordingAudioFileSystemError.removeFailed
                }
                let evidence = try await audioFileSystem
                    .reconcileAcceptedOutputAudioRemoval(
                        using: removalAuthorization
                    )
                guard evidence.provesAbsence(using: removalAuthorization),
                      removalAuthorization.proves(
                          recording: expected,
                          purpose: .acceptedOutput,
                          expectedRepositoryRoot: expectedRoot,
                          expectedPendingStoreIdentity: storeIdentity,
                          ownerIdentity: capabilityOwnerIdentity,
                          operationLeaseAuthorization:
                              operationLeaseAuthorization
                      ) else {
                    throw IOSPendingRecordingAudioFileSystemError.removeFailed
                }
                return evidence
            }
        } catch IOSPendingRecordingError.repositoryIdentityConflict {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        } catch {
            throw mapAudioError(error, operation: .remove)
        }
        if let current {
            guard try requireCurrent(
                expected: IOSPendingRecordingCASExpectation(
                    recording: current
                )
            ) == current else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
        } else {
            guard try performRepositoryBoundary({ _ in
                try journal.load()
            }) == nil else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
        }
        return IOSForegroundVoicePendingAudioRemovalAuthorization(
            recording: expected,
            storeIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    private func performForegroundVoiceAcceptedOutputJournalRetirement(
        expected: IOSPendingRecording,
        audioRemovalAuthorization:
            IOSForegroundVoicePendingAudioRemovalAuthorization,
        processLossAuthorization:
            IOSPendingRecordingProcessLossAcceptedOutputRetirementAuthorization?,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              expected.phase == .outputDelivery,
              audioRemovalAuthorization.provesRemoval(
                  for: expected,
                  storeIdentity: storeIdentity,
                  ownerIdentity: capabilityOwnerIdentity,
                  operationLeaseAuthorization:
                      operationLeaseAuthorization
              ),
              activeDispatchIdentity == nil,
              let transcriptionID = expected.transcriptionID,
              liveOwnerRegistry.isRetired(
                  attemptID: expected.attemptID,
                  transcriptionID: transcriptionID
              ) else {
            throw IOSPendingRecordingError.invalidTransition
        }
        if let processLossAuthorization {
            let expectedRoot = try currentRepositoryBinding()?
                .physicalRootIdentity
            guard processLossAuthorization.proves(
                recording: expected,
                expectedRepositoryRoot: expectedRoot,
                issuerStoreIdentity: storeIdentity,
                ownerIdentity: capabilityOwnerIdentity,
                operationLeaseAuthorization: operationLeaseAuthorization
            ) else {
                throw IOSPendingRecordingError.invalidTransition
            }
        }
        try await requireFailedOwnershipAbsent(
            for: expected,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let journalAuthorization =
            IOSPendingRecordingMetadataRetirementAuthorization()
        let durableAbsence:
            IOSPendingRecordingAcceptedOutputJournalAbsenceEvidence
        do {
            durableAbsence = try performRepositoryBoundary { expectedRoot in
                let source = try journal.loadMetadataSnapshot(
                    authorization: journalAuthorization
                )
                let evidence:
                    IOSPendingRecordingJournalMetadataAbsenceEvidence
                if let source {
                    guard source.recording == expected else {
                        throw IOSPendingRecordingError.compareAndSwapFailed
                    }
                    evidence = try journal.removeMetadata(
                        expected: source,
                        expectedRepositoryRoot: expectedRoot,
                        authorization: journalAuthorization
                    )
                    guard evidence.provesRemoval(of: source) else {
                        throw IOSPendingRecordingError.journalCommitUncertain
                    }
                } else {
                    evidence = try journal.proveMetadataAbsent(
                        expectedRepositoryRoot: expectedRoot,
                        authorization: journalAuthorization
                    )
                    guard evidence.provesPreexistingAbsence else {
                        throw IOSPendingRecordingError.journalCommitUncertain
                    }
                }
                guard let durableAbsence =
                        IOSPendingRecordingAcceptedOutputJournalAbsenceEvidence(
                            recording: expected,
                            source: source,
                            evidence: evidence,
                            expectedRepositoryRoot: expectedRoot,
                            issuerStoreIdentity: storeIdentity,
                            ownerIdentity: capabilityOwnerIdentity,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ) else {
                    throw IOSPendingRecordingError.journalCommitUncertain
                }
                return durableAbsence
            }
        } catch let error as IOSPendingRecordingError {
            throw error
        } catch {
            throw IOSPendingRecordingError.journalRemoveFailed
        }
        guard durableAbsence.provesAbsence(
            of: expected,
            issuerStoreIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSPendingRecordingError.journalCommitUncertain
        }
        liveOwnerRegistry.clearRetired(attemptID: expected.attemptID)
    }

    private func prepareProcessLossAcceptedOutputRetirement(
        _ current: IOSPendingRecording,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws
        -> IOSPendingRecordingProcessLossAcceptedOutputRetirementAuthorization {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              current.phase == .outputDelivery,
              let transcriptionID = current.transcriptionID,
              activeDispatchIdentity == nil,
              activeDispatchAuthorization == nil,
              !liveOwnerRegistry.hasLiveOwner(attemptID: current.attemptID)
        else {
            throw IOSPendingRecordingError.invalidTransition
        }
        let expectedRoot = try currentRepositoryBinding()?.physicalRootIdentity
        guard let authorization =
                IOSPendingRecordingProcessLossAcceptedOutputRetirementAuthorization(
                    recording: current,
                    expectedRepositoryRoot: expectedRoot,
                    issuerStoreIdentity: storeIdentity,
                    ownerIdentity: capabilityOwnerIdentity,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            throw IOSPendingRecordingError.invalidTransition
        }
        liveOwnerRegistry.retire(
            attemptID: current.attemptID,
            transcriptionID: transcriptionID
        )
        return authorization
    }

    func moveForegroundVoiceOutputToRecovery(
        expectedSource: IOSPendingRecording,
        absenceAuthorization:
            IOSForegroundVoiceNoDestinationAuthorization,
        deliveryStoreIdentity:
            IOSAcceptedOutputDeliveryStoreIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingRecording {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              absenceAuthorization.provesAbsence(
                  for: expectedSource,
                  storeIdentity: deliveryStoreIdentity,
                  ownerIdentity: capabilityOwnerIdentity,
                  operationLeaseAuthorization:
                      operationLeaseAuthorization
              ),
              let current = try performRepositoryBoundary({ _ in
                  try journal.load()
              }) else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        if isForegroundVoiceRecovery(
            current,
            derivedFrom: expectedSource
        ) {
            try confirmJournalDurability(current)
            return current
        }
        guard current == expectedSource,
              current.phase == .outputDelivery,
              absenceAuthorization.provesAbsence(
                  for: current,
                  storeIdentity: deliveryStoreIdentity,
                  ownerIdentity: capabilityOwnerIdentity,
                  operationLeaseAuthorization:
                      operationLeaseAuthorization
              ) else {
            throw IOSPendingRecordingError.invalidTransition
        }
        try await requireFailedOwnershipAbsent(
            for: current,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        _ = try await validatedAudio(for: current)
        try retireForegroundVoiceDispatch(for: current)

        let updated = try replacing(
            current,
            phase: .awaitingRecovery,
            transcriptionID: nil,
            transcriptionModel: current.transcriptionModel,
            transcriptionLanguageCode: current.transcriptionLanguageCode
        )
        try performRepositoryBoundary { expectedRoot in
            try journal.replace(
                updated,
                expected: current,
                expectedRepositoryRoot: expectedRoot
            )
        }
        return updated
    }

    public func discard(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecordingDiscardResult {
        try await performExclusiveOperation { [self] authorization in
            try await performDiscard(
                expected: expected,
                operationLeaseAuthorization: authorization
            )
        }
    }

    func prepareFailedHistoryTransferSource(
        expected: IOSPendingRecordingCASExpectation,
        failedStoreIdentity: IOSFailedHistoryStoreIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingFailedHistoryTransferSource {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              !failedHistoryMutationInterlock.isBlocked,
              failedStoreIdentity == expectedFailedStoreIdentity,
              let repositoryBinding = try currentRepositoryBinding() else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        let journalAuthorization =
            IOSPendingRecordingMetadataRetirementAuthorization()
        let snapshot = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            )
        }
        guard let snapshot else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        try requireExpectation(expected, matches: snapshot.recording)
        guard snapshot.recording.phase == .awaitingRecovery,
              snapshot.recording.transcriptionID == nil,
              activeDispatchIdentity == nil,
              !liveOwnerRegistry.hasLiveOwner(
                  attemptID: snapshot.recording.attemptID
              ) else {
            throw IOSPendingRecordingError.invalidTransition
        }

        let protectedAudioInventory =
            try await sealProtectedAudioNamespaceInventory(
                pendingSource: snapshot,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        try await validateProtectedAudioNamespace(
            protectedAudioInventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )

        let audioLease: any IOSPendingRecordingPublishedAudioLease
        do {
            audioLease = try await performRepositoryBoundary { _ in
                try await audioFileSystem.acquireValidatedPublishedAudio(
                    relativeIdentifier:
                        snapshot.recording.audioRelativeIdentifier,
                    attemptID: snapshot.recording.attemptID,
                    durationMilliseconds:
                        snapshot.recording.durationMilliseconds,
                    byteCount: snapshot.recording.byteCount
                )
            }
        } catch IOSPendingRecordingError.repositoryIdentityConflict {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        } catch {
            throw mapAudioError(error, operation: .validate)
        }
        var shouldReleaseAudio = true
        defer {
            if shouldReleaseAudio {
                audioLease.release()
            }
        }

        let confirmedSnapshot = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            )
        }
        try await revalidateProtectedAudioNamespaceInventory(
            protectedAudioInventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard confirmedSnapshot == snapshot,
              operationGateBinding.proves(
                  operationLeaseAuthorization
              ),
              let source = IOSPendingFailedHistoryTransferSource(
                    mint: IOSPendingFailedHistoryTransferSourceMint(),
                    pendingSnapshot: snapshot,
                    audioLease: audioLease,
                    pendingStoreIdentity: storeIdentity,
                    failedStoreIdentity: failedStoreIdentity,
                    ownerIdentity: capabilityOwnerIdentity,
                    repositoryBinding: repositoryBinding,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        try await source.revalidateAudio()
        shouldReleaseAudio = false
        return source
    }

    func sealFailedHistoryTransfer(
        _ source: IOSPendingFailedHistoryTransferSource,
        failure: IOSFailedHistoryTransferFailure,
        transferDate: Date,
        policyReceipt: IOSHistoryPolicyReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingFailedHistoryTransferPreparation {
        let repositoryBinding = try currentRepositoryBinding()
        guard operationGateBinding.proves(operationLeaseAuthorization),
              source.operationLeaseAuthorization.provesSameActiveLease(
                  as: operationLeaseAuthorization
              ),
              source.pendingStoreIdentity == storeIdentity,
              source.failedStoreIdentity == expectedFailedStoreIdentity,
              source.ownerIdentity == capabilityOwnerIdentity,
              source.repositoryBinding == repositoryBinding,
              policyReceipt.capabilityOwnerIdentity
                == capabilityOwnerIdentity,
              policyReceipt.state.historyEnabled else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        let journalAuthorization =
            IOSPendingRecordingMetadataRetirementAuthorization()
        let current = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            )
        }
        guard current == source.pendingSnapshot,
              !liveOwnerRegistry.hasLiveOwner(
                  attemptID: source.pendingSnapshot.recording.attemptID
              ) else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        try await source.revalidateAudio()

        let recording = source.pendingSnapshot.recording
        let canonicalTransferDate = try IOSFailedHistoryTimestampCodec
            .canonicalDate(from: transferDate)
        let intendedRow = try IOSFailedHistoryEntry(
            attemptID: recording.attemptID,
            createdAt: recording.createdAt,
            updatedAt: max(recording.createdAt, canonicalTransferDate),
            policyGeneration: policyReceipt.state.policyGeneration,
            failureCategory: failure.category,
            pipelineStage: failure.pipelineStage,
            retryCount: 0,
            outputIntent: recording.outputIntent,
            transcriptionModel: recording.transcriptionModel,
            transcriptionLanguageCode:
                recording.transcriptionLanguageCode,
            durationMilliseconds: recording.durationMilliseconds,
            byteCount: recording.byteCount,
            audioRelativeIdentifier: recording.audioRelativeIdentifier,
            ownershipState: .pendingJournalRetirement,
            retryOperation: nil
        )
        guard let preparation =
                IOSPendingFailedHistoryTransferPreparation(
                    mint:
                        IOSPendingFailedHistoryTransferPreparationMint(),
                    source: source,
                    intendedRow: intendedRow,
                    policyReceipt: policyReceipt
                ) else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        try await preparation.revalidateAudio()
        return preparation
    }

    func refreshFailedHistoryTransfer(
        _ preparation: IOSPendingFailedHistoryTransferPreparation,
        policyReceipt: IOSHistoryPolicyReceipt,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws {
        guard preparation.pendingStoreIdentity == storeIdentity,
              preparation.ownerIdentity == capabilityOwnerIdentity,
              operationGateBinding.proves(operationLeaseAuthorization),
              let repositoryBinding = try currentRepositoryBinding(),
              preparation.refresh(
                  mint: IOSPendingFailedHistoryTransferPreparationMint(),
                  repositoryBinding: repositoryBinding,
                  operationLeaseAuthorization:
                      operationLeaseAuthorization,
                  policyReceipt: policyReceipt
              ) else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        let journalAuthorization =
            IOSPendingRecordingMetadataRetirementAuthorization()
        let current = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            )
        }
        guard current == preparation.pendingSnapshot,
              !liveOwnerRegistry.hasLiveOwner(
                  attemptID: current?.recording.attemptID
                    ?? preparation.pendingSnapshot.recording.attemptID
              ) else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        try await preparation.revalidateAudio()
    }

    func verifyTransferRecoveryTerminal(
        using inspection: IOSFailedHistoryTransferRecoveryInspection,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              inspection.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              inspection.expectedPendingStoreIdentity == storeIdentity,
              inspection.failedStoreIdentity
                == expectedFailedStoreIdentity,
              inspection.ownerIdentity == capabilityOwnerIdentity,
              inspection.failedSource?.envelope.entries.contains(where: {
                  $0.ownershipState == .pendingJournalRetirement
              }) != true,
              let repositoryGuard else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        let currentBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
        do {
            currentBinding = try repositoryGuard.revalidate(
                expectedBinding: inspection.repositoryBinding
            )
        } catch {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        }
        guard currentBinding == inspection.repositoryBinding else {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        }

        let journalAuthorization =
            IOSPendingRecordingMetadataRetirementAuthorization()
        let snapshot = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            )
        }
        guard let snapshot else {
            let evidence = try performRepositoryBoundary { expectedRoot in
                try journal.proveMetadataAbsent(
                    expectedRepositoryRoot: expectedRoot,
                    authorization: journalAuthorization
                )
            }
            guard evidence.provesPreexistingAbsence,
                  evidence.provesCanonicalPendingRecordingPath,
                  evidence.binding.repositoryRoot
                    == inspection.repositoryBinding
                        .physicalRootIdentity else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
            return
        }

        guard let failedSource = inspection.failedSource else { return }
        let key = IOSFailedHistoryPendingOwnershipKey(
            recording: snapshot.recording
        )
        let rowCollision = failedSource.envelope.entries.contains {
            $0.attemptID == key.attemptID
                || $0.audioRelativeIdentifier
                    == key.audioRelativeIdentifier
        }
        let cleanupCollision = failedSource.envelope.audioCleanup.contains {
            $0.attemptID == key.attemptID
                || $0.audioRelativeIdentifier
                    == key.audioRelativeIdentifier
        }
        guard !rowCollision, !cleanupCollision else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
    }

    func preparePendingMetadataRetirement(
        using authority:
            IOSFailedHistoryPendingMetadataRetirementAuthority,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingRecordingMetadataRetirementStep {
        let repositoryBinding = try requireMetadataRetirementAuthority(
            authority,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let journalAuthorization =
            IOSPendingRecordingMetadataRetirementAuthorization()
        let snapshot = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            )
        }
        if let snapshot {
            guard authority.origin != .readyOutcomeConfirmation,
                  IOSFailedHistoryPendingMatchIdentity(
                      pending: snapshot.recording
                  ) == IOSFailedHistoryPendingMatchIdentity(
                      failedRow: authority.row
                  ),
                  activeDispatchIdentity == nil,
                  !liveOwnerRegistry.hasLiveOwner(
                      attemptID: snapshot.recording.attemptID
                  ) else {
                throw IOSPendingRecordingError.localRecoveryPending
            }
            if case .committed(let expectedSource) = authority.origin {
                guard snapshot == expectedSource else {
                    throw IOSPendingRecordingError.compareAndSwapFailed
                }
            }
            let inventory = try await sealProtectedAudioNamespaceInventory(
                pendingSource: snapshot,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
            guard inventory.failedInventory.failedSource
                    == authority.failedSource,
                  inventory.pendingAliasesPendingJournalRetirement else {
                throw IOSPendingRecordingError.localRecoveryPending
            }
            try await validateProtectedAudioNamespace(
                inventory,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
            guard let removalAuthorization =
                IOSPendingRecordingMetadataRemovalAuthorization(
                    mint:
                        IOSPendingRecordingMetadataRemovalAuthorizationMint(),
                    authority: authority,
                    source: snapshot
                ) else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
            return .removalAuthorized(removalAuthorization)
        }

        let evidence = try performRepositoryBoundary { expectedRoot in
            try journal.proveMetadataAbsent(
                expectedRepositoryRoot: expectedRoot,
                authorization: journalAuthorization
            )
        }
        guard evidence.binding.repositoryRoot
                == repositoryBinding.physicalRootIdentity,
              let receipt = IOSPendingRecordingMetadataAbsenceReceipt(
                  mint: IOSPendingRecordingMetadataAbsenceReceiptMint(),
                  issuerStoreIdentity: storeIdentity,
                  authority: authority,
                  outcome: .alreadyAbsent(evidence: evidence)
              ) else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        return .absenceConfirmed(receipt)
    }

    func retirePendingMetadata(
        using removalAuthorization:
            IOSPendingRecordingMetadataRemovalAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSPendingRecordingMetadataAbsenceReceipt {
        _ = try requireMetadataRetirementAuthority(
            removalAuthorization.authority,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let journalAuthorization =
            IOSPendingRecordingMetadataRetirementAuthorization()
        let evidence = try performRepositoryBoundary { expectedRoot in
            try journal.removeMetadata(
                expected: removalAuthorization.source,
                expectedRepositoryRoot: expectedRoot,
                authorization: journalAuthorization
            )
        }
        guard let receipt = IOSPendingRecordingMetadataAbsenceReceipt(
            mint: IOSPendingRecordingMetadataAbsenceReceiptMint(),
            issuerStoreIdentity: storeIdentity,
            authority: removalAuthorization.authority,
            outcome: .removed(
                source: removalAuthorization.source,
                evidence: evidence
            )
        ) else {
            throw IOSPendingRecordingError.journalCommitUncertain
        }
        return receipt
    }

    func reconcilePendingMetadataRemoval(
        _ retained:
            IOSPendingRecordingMetadataRemovalAuthorization,
        using refreshedAuthority:
            IOSFailedHistoryPendingMetadataRetirementAuthority,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingRecordingMetadataRetirementStep {
        _ = try requireMetadataRetirementAuthority(
            refreshedAuthority,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard retained.authority.row == refreshedAuthority.row,
              retained.authority.failedStoreIdentity
                == refreshedAuthority.failedStoreIdentity,
              retained.authority.expectedPendingStoreIdentity
                == refreshedAuthority.expectedPendingStoreIdentity,
              retained.authority.ownerIdentity
                == refreshedAuthority.ownerIdentity,
              retained.authority.repositoryBinding
                == refreshedAuthority.repositoryBinding else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        let journalAuthorization =
            IOSPendingRecordingMetadataRetirementAuthorization()
        let current = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            )
        }
        if let current {
            guard refreshedAuthority.origin
                    != .readyOutcomeConfirmation,
                  current == retained.source,
                  let refreshedRemoval =
                    IOSPendingRecordingMetadataRemovalAuthorization(
                        mint:
                            IOSPendingRecordingMetadataRemovalAuthorizationMint(),
                        authority: refreshedAuthority,
                        source: current
                    ) else {
                throw IOSPendingRecordingError.localRecoveryPending
            }
            let inventory = try await sealProtectedAudioNamespaceInventory(
                pendingSource: current,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
            guard inventory.failedInventory.failedSource
                    == refreshedAuthority.failedSource,
                  inventory.pendingAliasesPendingJournalRetirement else {
                throw IOSPendingRecordingError.localRecoveryPending
            }
            try await validateProtectedAudioNamespace(
                inventory,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
            return .removalAuthorized(refreshedRemoval)
        }

        let evidence = try performRepositoryBoundary { expectedRoot in
            try journal.proveMetadataAbsent(
                expectedRepositoryRoot: expectedRoot,
                authorization: journalAuthorization
            )
        }
        guard let receipt = IOSPendingRecordingMetadataAbsenceReceipt(
            mint: IOSPendingRecordingMetadataAbsenceReceiptMint(),
            issuerStoreIdentity: storeIdentity,
            authority: refreshedAuthority,
            outcome: .alreadyAbsent(evidence: evidence)
        ) else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        return .absenceConfirmed(receipt)
    }

    func acquireValidatedFailedHistoryRowAudio(
        using authorization:
            IOSFailedHistoryRowAudioValidationAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryValidatedRowAudio {
        try requireFailedHistoryRowAudioValidationAuthority(
            authorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        )

        let journalAuthorization =
            IOSPendingRecordingMetadataRetirementAuthorization()
        let pendingSource = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            )
        }
        try requirePendingSource(
            pendingSource,
            for: authorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let heldPendingAudioLease:
            (any IOSPendingRecordingPublishedAudioLease)?
        switch authorization.purpose {
        case .delete, .policyCutover:
            heldPendingAudioLease = nil
        case .retention(let preparation):
            guard let audioLease = preparation
                .audioLeaseForNamespaceValidation(
                    mint: IOSPendingRecordingHeldAudioLeaseMint(),
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                ) else {
                throw IOSPendingRecordingError.localRecoveryPending
            }
            heldPendingAudioLease = audioLease
        }
        guard let inventory = IOSProtectedAudioNamespaceInventory(
            mint: IOSProtectedAudioNamespaceInventoryMint(),
            failedInventory: authorization.failedInventory,
            pendingSource: pendingSource
        ) else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        try requireProtectedAudioNamespaceInventoryAuthority(
            inventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        do {
            try await audioFileSystem.validateProtectedAudioNamespace(
                inventory,
                holding: heldPendingAudioLease.map { [$0] } ?? []
            )
        } catch {
            throw mapAudioError(error, operation: .inspect)
        }
        try requireHeldPendingAudioLease(
            heldPendingAudioLease,
            for: authorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireFailedHistoryRowAudioValidationAuthority(
            authorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let postInventoryPendingSource = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            )
        }
        guard postInventoryPendingSource == pendingSource else {
            throw IOSPendingRecordingError.localRecoveryPending
        }

        let audioLease: any IOSPendingRecordingPublishedAudioLease
        do {
            audioLease = try await performRepositoryBoundary { _ in
                try await audioFileSystem.acquireValidatedPublishedAudio(
                    relativeIdentifier:
                        authorization.candidate.audioRelativeIdentifier,
                    attemptID: authorization.candidate.attemptID,
                    durationMilliseconds:
                        authorization.candidate.durationMilliseconds,
                    byteCount: authorization.candidate.byteCount
                )
            }
        } catch IOSPendingRecordingError.repositoryIdentityConflict {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        } catch {
            throw mapAudioError(error, operation: .validate)
        }
        var shouldReleaseAudio = true
        defer {
            if shouldReleaseAudio { audioLease.release() }
        }

        do {
            try await audioFileSystem.validateProtectedAudioNamespace(
                inventory,
                holding: (heldPendingAudioLease.map { [$0] } ?? [])
                    + [audioLease]
            )
        } catch {
            throw mapAudioError(error, operation: .inspect)
        }
        try requireHeldPendingAudioLease(
            heldPendingAudioLease,
            for: authorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        )

        try requireFailedHistoryRowAudioValidationAuthority(
            authorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let finalPendingSource = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            )
        }
        guard finalPendingSource == pendingSource,
              let validated = IOSFailedHistoryValidatedRowAudio(
                  mint: IOSFailedHistoryValidatedRowAudioMint(),
                  authorization: authorization,
                  audioLease: audioLease
              ) else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        shouldReleaseAudio = false
        return validated
    }

    func acquireValidatedFailedHistoryRetryAudio(
        using authorization:
            IOSFailedHistoryRetryReservationAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryRetryAudioSource {
        try requireNoPendingProviderOwner()
        try requireFailedHistoryRetryAudioAuthority(
            authorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        )

        let journalAuthorization =
            IOSPendingRecordingMetadataRetirementAuthorization()
        let pendingSource = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            )
        }
        guard let inventory = IOSProtectedAudioNamespaceInventory(
            mint: IOSProtectedAudioNamespaceInventoryMint(),
            failedInventory: authorization.failedInventory,
            pendingSource: pendingSource
        ) else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        try requireProtectedAudioNamespaceInventoryAuthority(
            inventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        do {
            try await audioFileSystem.validateProtectedAudioNamespace(
                inventory
            )
        } catch {
            throw mapAudioError(error, operation: .inspect)
        }
        try requireNoPendingProviderOwner()
        try await revalidateProtectedAudioNamespaceInventory(
            inventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireFailedHistoryRetryAudioAuthority(
            authorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        )

        let audioLease: any IOSPendingRecordingPublishedAudioLease
        do {
            audioLease = try await performRepositoryBoundary { _ in
                try await audioFileSystem.acquireValidatedPublishedAudio(
                    relativeIdentifier:
                        authorization.candidate.audioRelativeIdentifier,
                    attemptID: authorization.candidate.attemptID,
                    durationMilliseconds:
                        authorization.candidate.durationMilliseconds,
                    byteCount: authorization.candidate.byteCount
                )
            }
        } catch IOSPendingRecordingError.repositoryIdentityConflict {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        } catch {
            throw mapAudioError(error, operation: .validate)
        }
        var shouldReleaseAudio = true
        defer {
            if shouldReleaseAudio { audioLease.release() }
        }

        do {
            try await audioFileSystem.validateProtectedAudioNamespace(
                inventory,
                holding: [audioLease]
            )
        } catch {
            throw mapAudioError(error, operation: .inspect)
        }
        try requireNoPendingProviderOwner()
        try await revalidateProtectedAudioNamespaceInventory(
            inventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try requireFailedHistoryRetryAudioAuthority(
            authorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let finalPendingSource = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            )
        }
        guard finalPendingSource == pendingSource else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        try requireNoPendingProviderOwner()
        try requireFailedHistoryRetryAudioAuthority(
            authorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard let source = IOSFailedHistoryRetryAudioSource(
            mint: IOSFailedHistoryRetryAudioSourceMint(),
            reservationAuthorization: authorization,
            pendingStoreIdentity: storeIdentity,
            failedStoreIdentity: expectedFailedStoreIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            repositoryBinding: authorization.repositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization,
            audioLease: audioLease
        ) else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        shouldReleaseAudio = false
        return source
    }

    func reconcileFailedHistoryAudioCleanup(
        using authorization:
            IOSFailedHistoryAudioCleanupAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryAudioCleanupReceipt {
        try requireFailedHistoryAudioCleanupAuthority(
            authorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let journalAuthorization =
            IOSPendingRecordingMetadataRetirementAuthorization()
        let pendingSource = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            )
        }
        guard let inventory = IOSProtectedAudioNamespaceInventory(
            mint: IOSProtectedAudioNamespaceInventoryMint(),
            failedInventory: authorization.failedInventory,
            pendingSource: pendingSource
        ) else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        try requireProtectedAudioNamespaceInventoryAuthority(
            inventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard let fileAuthorization =
                IOSPendingRecordingProtectedAudioCleanupAuthorization(
                    cleanupAuthorization: authorization,
                    inventory: inventory
                ) else {
            throw IOSPendingRecordingError.localRecoveryPending
        }

        let evidence: IOSPendingRecordingProtectedAudioCleanupEvidence
        do {
            evidence = try await audioFileSystem
                .reconcileProtectedAudioCleanup(using: fileAuthorization)
        } catch {
            throw mapAudioError(error, operation: .remove)
        }

        try requireFailedHistoryAudioCleanupAuthority(
            authorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let finalPendingSource = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            )
        }
        guard finalPendingSource == pendingSource else {
            throw IOSPendingRecordingError.localRecoveryPending
        }

        let outcome: IOSFailedHistoryAudioCleanupReceipt.Outcome
        if evidence.provesRemoval(of: authorization) {
            outcome = .removed(evidence: evidence)
        } else if evidence.provesPreexistingAbsence(of: authorization) {
            outcome = .alreadyAbsent(evidence: evidence)
        } else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        guard let receipt = IOSFailedHistoryAudioCleanupReceipt(
            mint: IOSFailedHistoryAudioCleanupReceiptMint(),
            issuerStoreIdentity: storeIdentity,
            authorization: authorization,
            outcome: outcome
        ) else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        return receipt
    }
}

private extension IOSPendingRecordingStore {
    func requireFailedHistoryAudioCleanupAuthority(
        _ authorization:
            IOSFailedHistoryAudioCleanupAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws {
        try requireProtectedAudioInventoryAuthority(
            authorization.failedInventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard operationGateBinding.proves(operationLeaseAuthorization),
              failedHistoryMutationInterlock.hasRetainedAudioCleanup(
                  using: authorization,
                  operationLeaseAuthorization:
                    operationLeaseAuthorization
              ),
              authorization.failedStoreIdentity
                == expectedFailedStoreIdentity,
              authorization.expectedPendingStoreIdentity == storeIdentity,
              authorization.ownerIdentity == capabilityOwnerIdentity,
              authorization.failedSource
                == authorization.failedInventory.failedSource,
              authorization.repositoryBinding
                == authorization.failedInventory.repositoryBinding,
              authorization.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              authorization.failedSource.envelope.audioCleanup
                .contains(authorization.tombstone),
              !authorization.outcome.audioCleanup
                .contains(authorization.tombstone) else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
    }

    func requireHeldPendingAudioLease(
        _ heldAudioLease:
            (any IOSPendingRecordingPublishedAudioLease)?,
        for authorization:
            IOSFailedHistoryRowAudioValidationAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws {
        switch authorization.purpose {
        case .delete, .policyCutover:
            guard heldAudioLease == nil else {
                throw IOSPendingRecordingError.localRecoveryPending
            }
        case .retention(let preparation):
            guard let heldAudioLease,
                  let currentAudioLease = preparation
                    .audioLeaseForNamespaceValidation(
                        mint: IOSPendingRecordingHeldAudioLeaseMint(),
                        operationLeaseAuthorization:
                            operationLeaseAuthorization
                    ),
                  ObjectIdentifier(heldAudioLease)
                    == ObjectIdentifier(currentAudioLease) else {
                throw IOSPendingRecordingError.localRecoveryPending
            }
        }
    }

    func requireNoPendingProviderOwner() throws {
        guard activeDispatchIdentity == nil,
              activeDispatchAuthorization == nil,
              !liveOwnerRegistry.hasLiveOwner() else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
    }

    func requireFailedHistoryRetryAudioAuthority(
        _ authorization:
            IOSFailedHistoryRetryReservationAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws {
        try requireProtectedAudioInventoryAuthority(
            authorization.failedInventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard operationGateBinding.proves(operationLeaseAuthorization),
              !failedHistoryMutationInterlock.isBlocked,
              authorization.failedStoreIdentity
                == expectedFailedStoreIdentity,
              authorization.expectedPendingStoreIdentity == storeIdentity,
              authorization.ownerIdentity == capabilityOwnerIdentity,
              authorization.failedInventory.failedSource
                == authorization.failedSource,
              authorization.failedInventory.failedStoreIdentity
                == authorization.failedStoreIdentity,
              authorization.failedInventory.expectedPendingStoreIdentity
                == authorization.expectedPendingStoreIdentity,
              authorization.failedInventory.ownerIdentity
                == authorization.ownerIdentity,
              authorization.failedInventory.repositoryBinding
                == authorization.repositoryBinding,
              authorization.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ),
              authorization.failedSource.envelope.entries
                .contains(authorization.candidate),
              authorization.candidate.ownershipState == .ready,
              authorization.candidate.retryOperation == nil,
              authorization.failedSource.envelope.entries.allSatisfy({
                  $0.retryOperation == nil
              }) else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
    }

    func requireFailedHistoryRowAudioValidationAuthority(
        _ authorization:
            IOSFailedHistoryRowAudioValidationAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws {
        try requireProtectedAudioInventoryAuthority(
            authorization.failedInventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard operationGateBinding.proves(operationLeaseAuthorization),
              authorization.failedStoreIdentity
                == expectedFailedStoreIdentity,
              authorization.expectedPendingStoreIdentity == storeIdentity,
              authorization.ownerIdentity == capabilityOwnerIdentity,
              authorization.repositoryBinding
                == authorization.failedInventory.repositoryBinding,
              authorization.failedSource
                == authorization.failedInventory.failedSource,
              authorization.operationLeaseAuthorization
                .provesSameActiveLease(
                    as: operationLeaseAuthorization
                ) else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
    }

    func requirePendingSource(
        _ pendingSource:
            IOSPendingRecordingJournalMetadataSnapshot?,
        for authorization:
            IOSFailedHistoryRowAudioValidationAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws {
        switch authorization.purpose {
        case .delete, .policyCutover:
            return
        case .retention(let preparation):
            guard preparation.pendingSnapshot == pendingSource,
                  preparation.pendingStoreIdentity == storeIdentity,
                  preparation.failedStoreIdentity
                    == expectedFailedStoreIdentity,
                  preparation.ownerIdentity == capabilityOwnerIdentity,
                  preparation.repositoryBinding
                    == authorization.repositoryBinding,
                  preparation.operationLeaseAuthorization
                    .provesSameActiveLease(
                        as: operationLeaseAuthorization
                    ) else {
                throw IOSPendingRecordingError.localRecoveryPending
            }
        }
    }

    func requireMetadataRetirementAuthority(
        _ authority:
            IOSFailedHistoryPendingMetadataRetirementAuthority,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSAcceptedHistoryCoordinatorRepositoryBinding {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              authority.expectedPendingStoreIdentity == storeIdentity,
              authority.failedStoreIdentity == expectedFailedStoreIdentity,
              authority.ownerIdentity == capabilityOwnerIdentity,
              authority.operationLeaseAuthorization.provesSameActiveLease(
                  as: operationLeaseAuthorization
              ),
              authority.failedSource.envelope.entries.contains(
                  authority.row
              ),
              IOSFailedHistoryPendingMatchIdentity(
                  failedRow: authority.row
              ) != nil,
              let repositoryGuard else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        do {
            let current = try repositoryGuard.revalidate(
                expectedBinding: authority.repositoryBinding
            )
            guard current == authority.repositoryBinding else {
                throw IOSPendingRecordingError.repositoryIdentityConflict
            }
            return current
        } catch IOSPendingRecordingError.repositoryIdentityConflict {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        } catch {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        }
    }

    func performExclusiveOperation<Value: Sendable>(
        _ operation: @escaping @Sendable (
            IOSPersistenceOperationLeaseAuthorization
        ) async throws -> Value
    ) async throws -> Value {
        let repositoryGuard = repositoryGuard
        let failedHistoryMutationInterlock =
            failedHistoryMutationInterlock
        do {
            return try await operationGate.perform { authorization in
                guard !failedHistoryMutationInterlock.isBlocked else {
                    throw IOSPendingRecordingError.localRecoveryPending
                }
                let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding?
                do {
                    repositoryBinding = try repositoryGuard?.revalidate()
                } catch {
                    throw IOSPendingRecordingError.repositoryIdentityConflict
                }
                do {
                    let value = try await operation(authorization)
                    if let repositoryBinding {
                        _ = try repositoryGuard?.revalidate(
                            expectedBinding: repositoryBinding
                        )
                    }
                    return value
                } catch {
                    if let repositoryBinding {
                        do {
                            _ = try repositoryGuard?.revalidate(
                                expectedBinding: repositoryBinding
                            )
                        } catch {
                            throw IOSPendingRecordingError
                                .repositoryIdentityConflict
                        }
                    }
                    throw error
                }
            }
        } catch IOSPendingRecordingOperationGate.AcquisitionError.cancelledBeforeLease {
            throw IOSPendingRecordingError.cancelledBeforeOperation
        } catch IOSPendingRecordingOperationGate.AcquisitionError.reentrantOperation {
            throw IOSPendingRecordingError.reentrantOperation
        }
    }

    func performPrepare(
        _ preparation: IOSPendingRecordingPreparation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingRecording {
        if let current = try journal.load() {
            try await requireFailedOwnershipAbsent(
                for: current,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
            throw IOSPendingRecordingError.pendingSlotOccupied
        }

        let protectedAudioInventory:
            IOSProtectedAudioNamespaceInventory?
        #if DEBUG
        if bypassFailedOwnershipInspectionForTesting {
            protectedAudioInventory = nil
            do {
                try await audioFileSystem.requireEmptyNamespace()
            } catch {
                throw mapAudioError(error, operation: .inspect)
            }
        } else {
            let inventory = try await sealProtectedAudioNamespaceInventory(
                pendingSource: nil,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
            protectedAudioInventory = inventory
            try await validateProtectedAudioNamespace(
                inventory,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        }
        #else
        let inventory = try await sealProtectedAudioNamespaceInventory(
            pendingSource: nil,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        protectedAudioInventory = inventory
        try await validateProtectedAudioNamespace(
            inventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        #endif

        let lease: any IOSPendingRecordingPublishedAudioLease
        do {
            #if DEBUG
            if let protectedAudioInventory {
                lease = try await audioFileSystem.publishProtectedCopy(
                    from: preparation.sourceArtifact,
                    attemptID: preparation.attemptID,
                    format: preparation.audioFormat,
                    durationMilliseconds: preparation.durationMilliseconds,
                    inventory: protectedAudioInventory
                )
            } else {
                lease = try await performRepositoryBoundary { expectedRoot in
                    try await audioFileSystem.publishProtectedCopy(
                        from: preparation.sourceArtifact,
                        attemptID: preparation.attemptID,
                        format: preparation.audioFormat,
                        durationMilliseconds:
                            preparation.durationMilliseconds,
                        expectedRepositoryRoot: expectedRoot
                    )
                }
            }
            #else
            guard let protectedAudioInventory else {
                throw IOSPendingRecordingError.localRecoveryPending
            }
            lease = try await audioFileSystem.publishProtectedCopy(
                from: preparation.sourceArtifact,
                attemptID: preparation.attemptID,
                format: preparation.audioFormat,
                durationMilliseconds: preparation.durationMilliseconds,
                inventory: protectedAudioInventory
            )
            #endif
        } catch let error as IOSPendingRecordingError {
            throw error
        } catch {
            throw mapAudioError(error, operation: .publish)
        }
        defer { lease.release() }
        if let protectedAudioInventory {
            try await revalidateProtectedAudioNamespaceInventory(
                protectedAudioInventory,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        }

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
        if let protectedAudioInventory {
            try await revalidateProtectedAudioNamespaceInventory(
                protectedAudioInventory,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        }
        do {
            try performRepositoryBoundary { expectedRoot in
                try journal.create(
                    recording,
                    expectedRepositoryRoot: expectedRoot
                )
            }
        } catch let error as IOSPendingRecordingError {
            throw error
        } catch {
            throw IOSPendingRecordingError.journalWriteFailed
        }
        if let protectedAudioInventory {
            try await revalidateFailedProtectedAudioInventory(
                protectedAudioInventory.failedInventory,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        }
        do {
            _ = try await lease.revalidate()
        } catch {
            throw mapAudioError(error, operation: .validate)
        }
        return recording
    }

    func performLoad(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingRecordingObservation? {
        guard let recording = try journal.load() else {
            #if DEBUG
            if bypassFailedOwnershipInspectionForTesting {
                do {
                    try await audioFileSystem.requireEmptyNamespace()
                    return nil
                } catch {
                    throw mapAudioError(error, operation: .inspect)
                }
            }
            #endif

            let protectedAudioInventory =
                try await sealProtectedAudioNamespaceInventory(
                    pendingSource: nil,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
            do {
                try await audioFileSystem.validateProtectedAudioNamespace(
                    protectedAudioInventory
                )
                try await revalidateProtectedAudioNamespaceInventory(
                    protectedAudioInventory,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
                return nil
            } catch {
                if let error = error as? IOSPendingRecordingError {
                    throw error
                }
                throw mapAudioError(error, operation: .inspect)
            }
        }

        try await requireFailedOwnershipAbsent(
            for: recording,
            operationLeaseAuthorization: operationLeaseAuthorization
        )

        #if DEBUG
        if !bypassFailedOwnershipInspectionForTesting {
            try await validateCurrentProtectedAudioNamespace(
                recording: recording,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        }
        #else
        try await validateCurrentProtectedAudioNamespace(
            recording: recording,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        #endif

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
        transcriptionID: UUID,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingTranscriptionHandoff {
        guard await failedHistoryRetryState.hasLiveOwner() == false else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        let current = try requireCurrent(expected: expected)
        try await requireFailedOwnershipAbsent(
            for: current,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
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
        try performRepositoryBoundary { expectedRoot in
            try journal.replace(
                updated,
                expected: current,
                expectedRepositoryRoot: expectedRoot
            )
        }
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
        let lease = try await acquireCommittedHandoffOrRecover(
            updated,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        return IOSPendingTranscriptionHandoff(
            dispatch: IOSPendingTranscriptionDispatch(
                recording: updated,
                audio: IOSPendingTranscriptionAudio(lease: lease)
            ),
            authorization: authorization
        )
    }

    func performRetryTranscription(
        expected: IOSPendingRecordingCASExpectation,
        transcriptionID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingTranscriptionHandoff {
        guard await failedHistoryRetryState.hasLiveOwner() == false else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        let current = try requireCurrent(expected: expected)
        try await requireFailedOwnershipAbsent(
            for: current,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
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
        try performRepositoryBoundary { expectedRoot in
            try journal.replace(
                updated,
                expected: current,
                expectedRepositoryRoot: expectedRoot
            )
        }
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
        let lease = try await acquireCommittedHandoffOrRecover(
            updated,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        return IOSPendingTranscriptionHandoff(
            dispatch: IOSPendingTranscriptionDispatch(
                recording: updated,
                audio: IOSPendingTranscriptionAudio(lease: lease)
            ),
            authorization: authorization
        )
    }

    func performAdvance(
        expected: IOSPendingRecordingCASExpectation,
        source: IOSPendingRecordingPhase,
        destination: IOSPendingRecordingPhase,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingRecording {
        let current = try requireCurrent(expected: expected)
        try await requireFailedOwnershipAbsent(
            for: current,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
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
        try performRepositoryBoundary { expectedRoot in
            try journal.replace(
                updated,
                expected: current,
                expectedRepositoryRoot: expectedRoot
            )
        }
        return updated
    }

    func performMarkAwaitingRecovery(
        expected: IOSPendingRecordingCASExpectation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingRecording {
        let current = try requireCurrent(expected: expected)
        try await requireFailedOwnershipAbsent(
            for: current,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
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
        try performRepositoryBoundary { expectedRoot in
            try journal.replace(
                updated,
                expected: current,
                expectedRepositoryRoot: expectedRoot
            )
        }
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

    private func retireForegroundVoiceDispatch(
        for recording: IOSPendingRecording
    ) throws {
        guard let transcriptionID = recording.transcriptionID else {
            throw IOSPendingRecordingError.invalidTransition
        }
        let expectedIdentity = ActiveDispatchIdentity(
            attemptID: recording.attemptID,
            transcriptionID: transcriptionID
        )
        if activeDispatchIdentity == expectedIdentity {
            liveOwnerRegistry.retire(
                attemptID: recording.attemptID,
                transcriptionID: transcriptionID
            )
            activeDispatchAuthorization?.retireAndCancel()
            activeDispatchAuthorization = nil
            activeDispatchIdentity = nil
            return
        }
        guard activeDispatchIdentity == nil,
              liveOwnerRegistry.isRetired(
                  attemptID: recording.attemptID,
                  transcriptionID: transcriptionID
              ) else {
            throw IOSPendingRecordingError.invalidTransition
        }
    }

    private func isForegroundVoiceRecovery(
        _ candidate: IOSPendingRecording,
        derivedFrom source: IOSPendingRecording
    ) -> Bool {
        candidate.attemptID == source.attemptID
            && candidate.audioRelativeIdentifier
                == source.audioRelativeIdentifier
            && candidate.createdAt == source.createdAt
            && candidate.updatedAt >= source.updatedAt
            && candidate.phase == .awaitingRecovery
            && candidate.outputIntent == source.outputIntent
            && candidate.transcriptionID == nil
            && candidate.transcriptionModel == source.transcriptionModel
            && candidate.transcriptionLanguageCode
                == source.transcriptionLanguageCode
            && candidate.durationMilliseconds
                == source.durationMilliseconds
            && candidate.byteCount == source.byteCount
    }

    func performRecoverAfterProcessLoss(
        expected: IOSPendingRecordingCASExpectation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingRecording {
        let resolution = try await performProcessLossRecovery(
            expected: expected,
            mayCompleteAcceptedOutput: false,
            validateAudioBeforeAwaitingRecovery: false,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard case .awaitingRecovery(let recording) = resolution else {
            throw IOSPendingRecordingError.invalidTransition
        }
        return recording
    }

    func performContainingAppRecoveryAfterProcessLoss(
        expected: IOSPendingRecordingCASExpectation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingRecordingContainingAppRecoveryResolution {
        switch try await performProcessLossRecovery(
            expected: expected,
            mayCompleteAcceptedOutput: true,
            validateAudioBeforeAwaitingRecovery: true,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) {
        case .awaitingRecovery:
            return .awaitingRecovery
        case .completedAcceptedOutput:
            return .completedAcceptedOutput
        }
    }

    private enum ProcessLossRecoveryResolution: Sendable {
        case awaitingRecovery(IOSPendingRecording)
        case completedAcceptedOutput
    }

    private func canonicalDestinationEvidence(
        for recording: IOSPendingRecording,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSPendingRecordingCanonicalDestinationEvidence {
        guard operationGateBinding.proves(operationLeaseAuthorization) else {
            throw IOSPendingRecordingError.destinationInspectionFailed
        }
        do {
            return try performRepositoryBoundary { expectedRoot in
                let disposition = try destinationInspector
                    .inspectCanonicalDestination(
                        for: recording,
                        expectedRepositoryRoot: expectedRoot
                    )
                guard let evidence =
                        IOSPendingRecordingCanonicalDestinationEvidence(
                            disposition: disposition,
                            recording: recording,
                            expectedRepositoryRoot: expectedRoot,
                            issuerStoreIdentity: storeIdentity,
                            ownerIdentity: capabilityOwnerIdentity,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ), evidence.proves(
                            recording: recording,
                            expectedRepositoryRoot: expectedRoot,
                            issuerStoreIdentity: storeIdentity,
                            ownerIdentity: capabilityOwnerIdentity,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ) else {
                    throw IOSPendingRecordingError
                        .destinationInspectionFailed
                }
                return evidence
            }
        } catch IOSPendingRecordingError.repositoryIdentityConflict {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        } catch {
            throw IOSPendingRecordingError.destinationInspectionFailed
        }
    }

    private func performProcessLossRecovery(
        expected: IOSPendingRecordingCASExpectation,
        mayCompleteAcceptedOutput: Bool,
        validateAudioBeforeAwaitingRecovery: Bool,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> ProcessLossRecoveryResolution {
        let current = try requireCurrent(expected: expected)
        try await requireFailedOwnershipAbsent(
            for: current,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        if current.phase == .awaitingRecovery {
            try confirmJournalDurability(current)
            return .awaitingRecovery(current)
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
        let destinationEvidence = try canonicalDestinationEvidence(
            for: current,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let destinationEvidenceRoot = try currentRepositoryBinding()?
            .physicalRootIdentity
        guard destinationEvidence.proves(
            recording: current,
            expectedRepositoryRoot: destinationEvidenceRoot,
            issuerStoreIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSPendingRecordingError.destinationInspectionFailed
        }
        if destinationEvidence.disposition == .exactDestination {
            guard mayCompleteAcceptedOutput,
                  current.phase == .outputDelivery else {
                throw IOSPendingRecordingError.invalidTransition
            }
            try await performCompletedAcceptedOutputRetirement(
                current,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
            return .completedAcceptedOutput
        }

        if validateAudioBeforeAwaitingRecovery {
            do {
                _ = try await performRepositoryBoundary { _ in
                    try await audioFileSystem.validatePublishedAudio(
                        relativeIdentifier:
                            current.audioRelativeIdentifier,
                        attemptID: current.attemptID,
                        durationMilliseconds:
                            current.durationMilliseconds,
                        byteCount: current.byteCount
                    )
                }
            } catch IOSPendingRecordingError.repositoryIdentityConflict {
                throw IOSPendingRecordingError.repositoryIdentityConflict
            } catch {
                throw mapAudioError(error, operation: .validate)
            }
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
        try performRepositoryBoundary { expectedRoot in
            try journal.replace(
                updated,
                expected: current,
                expectedRepositoryRoot: expectedRoot
            )
        }
        return .awaitingRecovery(updated)
    }

    private func performCompletedAcceptedOutputRetirement(
        _ current: IOSPendingRecording,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws {
        guard current.phase == .outputDelivery,
              operationGateBinding.proves(
                  operationLeaseAuthorization
              ) else {
            throw IOSPendingRecordingError.invalidTransition
        }
        let processLossAuthorization = try
            prepareProcessLossAcceptedOutputRetirement(
                current,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        let audioRemovalAuthorization = try await
            performForegroundVoiceAcceptedOutputAudioRemoval(
                expected: current,
                processLossAuthorization: processLossAuthorization,
                operationLeaseAuthorization: operationLeaseAuthorization
            )

        let destinationEvidence = try canonicalDestinationEvidence(
            for: current,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let destinationEvidenceRoot = try currentRepositoryBinding()?
            .physicalRootIdentity
        guard destinationEvidence.disposition == .exactDestination,
              destinationEvidence.proves(
                  recording: current,
                  expectedRepositoryRoot: destinationEvidenceRoot,
                  issuerStoreIdentity: storeIdentity,
                  ownerIdentity: capabilityOwnerIdentity,
                  operationLeaseAuthorization:
                      operationLeaseAuthorization
              ),
              operationGateBinding.proves(
                  operationLeaseAuthorization
              ) else {
            throw IOSPendingRecordingError.destinationInspectionFailed
        }

        try await performForegroundVoiceAcceptedOutputJournalRetirement(
            expected: current,
            audioRemovalAuthorization: audioRemovalAuthorization,
            processLossAuthorization: processLossAuthorization,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func performAcceptedOutputLaunchCompletionIfPresent(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> Bool {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              let current = try performRepositoryBoundary({ _ in
                  try journal.load()
              }),
              current.phase == .outputDelivery,
              let transcriptionID = current.transcriptionID else {
            return false
        }
        try await requireFailedOwnershipAbsent(
            for: current,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard activeDispatchIdentity == nil,
              !liveOwnerRegistry.contains(
                  attemptID: current.attemptID,
                  transcriptionID: transcriptionID
              ) else {
            throw IOSPendingRecordingError.invalidTransition
        }

        let destinationEvidence = try canonicalDestinationEvidence(
            for: current,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let destinationEvidenceRoot = try currentRepositoryBinding()?
            .physicalRootIdentity
        guard destinationEvidence.proves(
            recording: current,
            expectedRepositoryRoot: destinationEvidenceRoot,
            issuerStoreIdentity: storeIdentity,
            ownerIdentity: capabilityOwnerIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization
        ) else {
            throw IOSPendingRecordingError.destinationInspectionFailed
        }
        guard destinationEvidence.disposition == .exactDestination else {
            return false
        }
        try await performCompletedAcceptedOutputRetirement(
            current,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        return true
    }

    func performDiscard(
        expected: IOSPendingRecordingCASExpectation,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSPendingRecordingDiscardResult {
        guard operationGateBinding.proves(operationLeaseAuthorization) else {
            throw IOSPendingRecordingError.invalidTransition
        }
        let journalAuthorization =
            IOSPendingRecordingMetadataRetirementAuthorization()
        let initialSnapshot = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(
                authorization: journalAuthorization
            )
        }
        guard let initialSnapshot else {
            let initialAbsenceAuthorization = try performRepositoryBoundary {
                expectedRoot in
                let evidence = try journal.proveMetadataAbsent(
                    expectedRepositoryRoot: expectedRoot,
                    authorization: journalAuthorization
                )
                guard let authorization =
                        IOSForegroundVoicePendingJournalAbsenceAuthorization(
                            evidence: evidence,
                            expectedRepositoryRoot: expectedRoot,
                            issuerStoreIdentity: storeIdentity,
                            ownerIdentity: capabilityOwnerIdentity,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ) else {
                    throw IOSPendingRecordingError.journalCommitUncertain
                }
                return authorization
            }
            guard initialAbsenceAuthorization.provesAbsence(
                issuerStoreIdentity: storeIdentity,
                ownerIdentity: capabilityOwnerIdentity,
                operationLeaseAuthorization: operationLeaseAuthorization
            ) else {
                throw IOSPendingRecordingError.journalCommitUncertain
            }
            #if DEBUG
            if bypassFailedOwnershipInspectionForTesting {
                do {
                    try await audioFileSystem.requireEmptyNamespace()
                } catch {
                    throw mapAudioError(error, operation: .inspect)
                }
            } else {
                let inventory = try await sealProtectedAudioNamespaceInventory(
                    pendingSource: nil,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
                try await validateProtectedAudioNamespace(
                    inventory,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
            }
            #else
            let inventory = try await sealProtectedAudioNamespaceInventory(
                pendingSource: nil,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
            try await validateProtectedAudioNamespace(
                inventory,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
            #endif

            // The namespace proof includes asynchronous failed-inventory work.
            // Re-prove the canonical Pending path after it completes before
            // claiming that both durable resources are absent.
            let finalAbsenceAuthorization = try performRepositoryBoundary {
                expectedRoot in
                let evidence = try journal.proveMetadataAbsent(
                    expectedRepositoryRoot: expectedRoot,
                    authorization: journalAuthorization
                )
                guard let authorization =
                        IOSForegroundVoicePendingJournalAbsenceAuthorization(
                            evidence: evidence,
                            expectedRepositoryRoot: expectedRoot,
                            issuerStoreIdentity: storeIdentity,
                            ownerIdentity: capabilityOwnerIdentity,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ) else {
                    throw IOSPendingRecordingError.journalCommitUncertain
                }
                return authorization
            }
            guard finalAbsenceAuthorization.provesAbsence(
                issuerStoreIdentity: storeIdentity,
                ownerIdentity: capabilityOwnerIdentity,
                operationLeaseAuthorization: operationLeaseAuthorization
            ) else {
                throw IOSPendingRecordingError.journalCommitUncertain
            }
            liveOwnerRegistry.clearRetired(attemptID: expected.attemptID)
            return .alreadyAbsent
        }
        let current = initialSnapshot.recording
        try requireExpectation(expected, matches: current)
        try await requireFailedOwnershipAbsent(
            for: current,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard current.phase == .readyForTranscription
                || current.phase == .awaitingRecovery,
              activeDispatchIdentity == nil,
              !liveOwnerRegistry.hasLiveOwner(attemptID: current.attemptID) else {
            throw IOSPendingRecordingError.invalidTransition
        }

        do {
            _ = try await performRepositoryBoundary { expectedRoot in
                guard let removalAuthorization =
                        IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization(
                            recording: current,
                            purpose: .discard,
                            mayCreateDurableIntent: true,
                            expectedRepositoryRoot: expectedRoot,
                            expectedPendingStoreIdentity: storeIdentity,
                            ownerIdentity: capabilityOwnerIdentity,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ) else {
                    throw IOSPendingRecordingAudioFileSystemError.removeFailed
                }
                let evidence = try await audioFileSystem
                    .reconcilePendingAudioRemoval(
                        using: removalAuthorization
                    )
                guard evidence.provesAbsence(using: removalAuthorization),
                      removalAuthorization.proves(
                          recording: current,
                          purpose: .discard,
                          expectedRepositoryRoot: expectedRoot,
                          expectedPendingStoreIdentity: storeIdentity,
                          ownerIdentity: capabilityOwnerIdentity,
                          operationLeaseAuthorization:
                              operationLeaseAuthorization
                      ) else {
                    throw IOSPendingRecordingAudioFileSystemError.removeFailed
                }
                return evidence
            }
        } catch IOSPendingRecordingError.repositoryIdentityConflict {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        } catch {
            throw mapAudioError(error, operation: .remove)
        }

        do {
            let durableAbsence = try performRepositoryBoundary {
                expectedRoot in
                guard let source = try journal.loadMetadataSnapshot(
                    authorization: journalAuthorization
                ), source.recording == current else {
                    throw IOSPendingRecordingError.compareAndSwapFailed
                }
                let evidence = try journal.removeMetadata(
                    expected: source,
                    expectedRepositoryRoot: expectedRoot,
                    authorization: journalAuthorization
                )
                guard evidence.provesRemoval(of: source),
                      let durableAbsence =
                        IOSPendingRecordingAcceptedOutputJournalAbsenceEvidence(
                            recording: current,
                            source: source,
                            evidence: evidence,
                            expectedRepositoryRoot: expectedRoot,
                            issuerStoreIdentity: storeIdentity,
                            ownerIdentity: capabilityOwnerIdentity,
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ) else {
                    throw IOSPendingRecordingError.journalCommitUncertain
                }
                return durableAbsence
            }
            guard durableAbsence.provesAbsence(
                of: current,
                issuerStoreIdentity: storeIdentity,
                ownerIdentity: capabilityOwnerIdentity,
                operationLeaseAuthorization: operationLeaseAuthorization
            ) else {
                throw IOSPendingRecordingError.journalCommitUncertain
            }
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

    func sealFailedProtectedAudioInventory(
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryProtectedAudioInventory {
        guard operationGateBinding.proves(operationLeaseAuthorization) else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        let inventory: IOSFailedHistoryProtectedAudioInventory
        do {
            inventory = try await failedOwnershipInspector
                .sealProtectedAudioInventory(
                    expectedPendingStoreIdentity: storeIdentity,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
        } catch IOSFailedHistoryError.repositoryIdentityConflict {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        } catch {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        try requireProtectedAudioInventoryAuthority(
            inventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        return inventory
    }

    func validateCurrentProtectedAudioNamespace(
        recording: IOSPendingRecording,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws {
        let authorization = IOSPendingRecordingMetadataRetirementAuthorization()
        let snapshot = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(authorization: authorization)
        }
        guard let snapshot, snapshot.recording == recording else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        let inventory = try await sealProtectedAudioNamespaceInventory(
            pendingSource: snapshot,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try await validateProtectedAudioNamespace(
            inventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func sealProtectedAudioNamespaceInventory(
        pendingSource: IOSPendingRecordingJournalMetadataSnapshot?,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSProtectedAudioNamespaceInventory {
        let failedInventory = try await sealFailedProtectedAudioInventory(
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard let inventory = IOSProtectedAudioNamespaceInventory(
            mint: IOSProtectedAudioNamespaceInventoryMint(),
            failedInventory: failedInventory,
            pendingSource: pendingSource
        ) else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        try requireProtectedAudioNamespaceInventoryAuthority(
            inventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        return inventory
    }

    func revalidateFailedProtectedAudioInventory(
        _ inventory: IOSFailedHistoryProtectedAudioInventory,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws {
        try requireProtectedAudioInventoryAuthority(
            inventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        do {
            try await failedOwnershipInspector
                .revalidateProtectedAudioInventory(
                    inventory,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
        } catch IOSFailedHistoryError.repositoryIdentityConflict {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        } catch {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        try requireProtectedAudioInventoryAuthority(
            inventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func revalidateProtectedAudioNamespaceInventory(
        _ inventory: IOSProtectedAudioNamespaceInventory,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws {
        try requireProtectedAudioNamespaceInventoryAuthority(
            inventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        try await revalidateFailedProtectedAudioInventory(
            inventory.failedInventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let authorization = IOSPendingRecordingMetadataRetirementAuthorization()
        let current = try performRepositoryBoundary { _ in
            try journal.loadMetadataSnapshot(authorization: authorization)
        }
        guard current == inventory.pendingSource else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        try requireProtectedAudioNamespaceInventoryAuthority(
            inventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func validateProtectedAudioNamespace(
        _ inventory: IOSProtectedAudioNamespaceInventory,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws {
        do {
            try await audioFileSystem.validateProtectedAudioNamespace(
                inventory
            )
        } catch {
            throw mapAudioError(error, operation: .inspect)
        }
        try await revalidateProtectedAudioNamespaceInventory(
            inventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func requireProtectedAudioInventoryAuthority(
        _ inventory: IOSFailedHistoryProtectedAudioInventory,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws {
        guard operationGateBinding.proves(operationLeaseAuthorization),
              inventory.failedStoreIdentity == expectedFailedStoreIdentity,
              inventory.expectedPendingStoreIdentity == storeIdentity,
              inventory.ownerIdentity == capabilityOwnerIdentity,
              inventory.operationLeaseAuthorization.provesSameActiveLease(
                  as: operationLeaseAuthorization
              ),
              let repositoryGuard else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        do {
            let current = try repositoryGuard.revalidate(
                expectedBinding: inventory.repositoryBinding
            )
            guard current == inventory.repositoryBinding else {
                throw IOSPendingRecordingError.repositoryIdentityConflict
            }
        } catch IOSPendingRecordingError.repositoryIdentityConflict {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        } catch {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        }
    }

    func requireProtectedAudioNamespaceInventoryAuthority(
        _ inventory: IOSProtectedAudioNamespaceInventory,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws {
        try requireProtectedAudioInventoryAuthority(
            inventory.failedInventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        guard inventory.operationLeaseAuthorization.provesSameActiveLease(
                  as: operationLeaseAuthorization
              ),
              inventory.expectedPendingStoreIdentity == storeIdentity,
              inventory.failedStoreIdentity == expectedFailedStoreIdentity,
              inventory.ownerIdentity == capabilityOwnerIdentity else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
    }

    func requireExpectation(
        _ expected: IOSPendingRecordingCASExpectation,
        matches current: IOSPendingRecording
    ) throws {
        guard expected == IOSPendingRecordingCASExpectation(recording: current) else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
    }

    func requireFailedOwnershipAbsent(
        for recording: IOSPendingRecording,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws {
        #if DEBUG
        if bypassFailedOwnershipInspectionForTesting { return }
        #endif
        guard operationGateBinding.proves(operationLeaseAuthorization) else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        let pendingKey = IOSFailedHistoryPendingOwnershipKey(
            recording: recording
        )
        let proof: IOSFailedHistoryPendingOwnershipAbsenceProof
        do {
            proof = try await failedOwnershipInspector
                .provePendingOwnershipAbsent(
                    for: pendingKey,
                    expectedPendingStoreIdentity: storeIdentity,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
        } catch IOSFailedHistoryError.repositoryIdentityConflict {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        } catch {
            throw IOSPendingRecordingError.localRecoveryPending
        }

        guard proof.failedStoreIdentity == expectedFailedStoreIdentity,
              proof.expectedPendingStoreIdentity == storeIdentity,
              proof.ownerIdentity == capabilityOwnerIdentity,
              proof.pendingKey == pendingKey,
              proof.operationLeaseAuthorization.provesSameActiveLease(
                  as: operationLeaseAuthorization
              ),
              let repositoryGuard else {
            throw IOSPendingRecordingError.localRecoveryPending
        }
        let currentBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
        do {
            currentBinding = try repositoryGuard.revalidate(
                expectedBinding: proof.repositoryBinding
            )
        } catch {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        }
        guard currentBinding == proof.repositoryBinding else {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        }
        if let failedSource = proof.failedSource {
            guard !failedSource.envelope.entries.contains(where: {
                $0.ownershipState == .pendingJournalRetirement
            }) else {
                throw IOSPendingRecordingError.localRecoveryPending
            }
            let hasCollision = failedSource.envelope.entries.contains {
                $0.attemptID == pendingKey.attemptID
                    || $0.audioRelativeIdentifier
                        == pendingKey.audioRelativeIdentifier
            } || failedSource.envelope.audioCleanup.contains {
                $0.attemptID == pendingKey.attemptID
                    || $0.audioRelativeIdentifier
                        == pendingKey.audioRelativeIdentifier
            }
            guard !hasCollision else {
                throw IOSPendingRecordingError.localRecoveryPending
            }
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

    func acquireCommittedHandoffOrRecover(
        _ recording: IOSPendingRecording,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        do {
            return try await audioFileSystem.acquireValidatedPublishedAudio(
                relativeIdentifier: recording.audioRelativeIdentifier,
                attemptID: recording.attemptID,
                durationMilliseconds: recording.durationMilliseconds,
                byteCount: recording.byteCount
            )
        } catch {
            let validationError = error
            _ = try await performMarkAwaitingRecovery(
                expected: IOSPendingRecordingCASExpectation(
                    recording: recording
                ),
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
            throw mapAudioError(validationError, operation: .validate)
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
        try performRepositoryBoundary { expectedRoot in
            try journal.replace(
                recording,
                expected: recording,
                expectedRepositoryRoot: expectedRoot
            )
        }
    }

    func performRepositoryBoundary<Value: Sendable>(
        _ operation: @Sendable (
            IOSPersistenceRepositoryRootIdentity?
        ) throws -> Value
    ) throws -> Value {
        let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding?
        do {
            repositoryBinding = try repositoryGuard?.revalidate()
        } catch {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        }
        do {
            let value = try operation(
                repositoryBinding?.physicalRootIdentity
            )
            if let repositoryBinding {
                _ = try repositoryGuard?.revalidate(
                    expectedBinding: repositoryBinding
                )
            }
            return value
        } catch {
            if let repositoryBinding {
                do {
                    _ = try repositoryGuard?.revalidate(
                        expectedBinding: repositoryBinding
                    )
                } catch {
                    throw IOSPendingRecordingError.repositoryIdentityConflict
                }
            }
            throw error
        }
    }

    func performRepositoryBoundary<Value: Sendable>(
        _ operation: @Sendable (
            IOSPersistenceRepositoryRootIdentity?
        ) async throws -> Value
    ) async throws -> Value {
        let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding?
        do {
            repositoryBinding = try repositoryGuard?.revalidate()
        } catch {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        }
        do {
            let value = try await operation(
                repositoryBinding?.physicalRootIdentity
            )
            if let repositoryBinding {
                _ = try repositoryGuard?.revalidate(
                    expectedBinding: repositoryBinding
                )
            }
            return value
        } catch {
            if let repositoryBinding {
                do {
                    _ = try repositoryGuard?.revalidate(
                        expectedBinding: repositoryBinding
                    )
                } catch {
                    throw IOSPendingRecordingError.repositoryIdentityConflict
                }
            }
            throw error
        }
    }

    func currentRepositoryBinding()
        throws -> IOSAcceptedHistoryCoordinatorRepositoryBinding? {
        do {
            return try repositoryGuard?.revalidate()
        } catch {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        }
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
        case .repositoryIdentityConflict:
            return .repositoryIdentityConflict
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
