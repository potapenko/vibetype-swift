import Foundation

/// One exact Failed-History view of the app-private protected-audio namespace.
/// The Failed store is the only production issuer; consumers may inspect the
/// canonical artifacts but cannot construct an inventory from paths or rows.
struct IOSFailedHistoryProtectedAudioInventory: Equatable, Sendable {
    enum Artifact: Equatable, Sendable {
        case row(
            attemptID: UUID,
            relativeIdentifier: String,
            durationMilliseconds: Int64,
            byteCount: Int64
        )
        case tombstone(
            attemptID: UUID,
            relativeIdentifier: String,
            byteCount: Int64
        )
    }

    let failedSource: IOSFailedHistoryJournalSnapshot?
    let failedStoreIdentity: IOSFailedHistoryStoreIdentity
    let expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization
    let artifacts: [Artifact]
    let hasPendingJournalRetirement: Bool

    init?(
        mint: IOSFailedHistoryProtectedAudioInventoryMint,
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
              repositoryBinding.physicalRootIdentity != nil else {
            return nil
        }

        self.failedSource = failedSource
        self.failedStoreIdentity = failedStoreIdentity
        self.expectedPendingStoreIdentity = expectedPendingStoreIdentity
        self.ownerIdentity = ownerIdentity
        self.repositoryBinding = repositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
        artifacts = Self.canonicalArtifacts(from: failedSource)
        hasPendingJournalRetirement = failedSource?.envelope.entries
            .contains(where: {
                $0.ownershipState == .pendingJournalRetirement
            }) == true
    }

    #if DEBUG
    /// Narrow seam for descriptor-level inventory tests. Production callers
    /// can obtain this capability only from `IOSFailedHistoryStore`.
    init(
        testingRepositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        artifacts: [Artifact]
    ) {
        failedSource = nil
        failedStoreIdentity = IOSFailedHistoryStoreIdentity()
        expectedPendingStoreIdentity = IOSPendingRecordingStoreIdentity()
        ownerIdentity = IOSAcceptedHistoryCapabilityOwnerIdentity()
        repositoryBinding = testingRepositoryBinding
        self.operationLeaseAuthorization = operationLeaseAuthorization
        self.artifacts = artifacts
        hasPendingJournalRetirement = false
    }
    #endif

    private static func canonicalArtifacts(
        from source: IOSFailedHistoryJournalSnapshot?
    ) -> [Artifact] {
        guard let envelope = source?.envelope else { return [] }
        return envelope.entries.map {
            .row(
                attemptID: $0.attemptID,
                relativeIdentifier: $0.audioRelativeIdentifier,
                durationMilliseconds: $0.durationMilliseconds,
                byteCount: $0.byteCount
            )
        } + envelope.audioCleanup.map {
            .tombstone(
                attemptID: $0.attemptID,
                relativeIdentifier: $0.audioRelativeIdentifier,
                byteCount: $0.byteCount
            )
        }
    }
}

extension IOSFailedHistoryProtectedAudioInventory.Artifact:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryProtectedAudioInventory.Artifact(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryProtectedAudioInventory:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryProtectedAudioInventory(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// One exact, capability-derived view of every metadata-owned final file in
/// the protected pending-audio namespace. Production construction is confined
/// to the Pending store; callers cannot supply filenames or ownership arrays.
struct IOSProtectedAudioNamespaceInventory: Equatable, Sendable {
    typealias Artifact = IOSFailedHistoryProtectedAudioInventory.Artifact

    let failedInventory: IOSFailedHistoryProtectedAudioInventory
    let pendingSource: IOSPendingRecordingJournalMetadataSnapshot?
    let artifacts: [Artifact]
    let pendingAliasesPendingJournalRetirement: Bool

    var failedStoreIdentity: IOSFailedHistoryStoreIdentity {
        failedInventory.failedStoreIdentity
    }

    var expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity {
        failedInventory.expectedPendingStoreIdentity
    }

    var ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity {
        failedInventory.ownerIdentity
    }

    var repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding {
        failedInventory.repositoryBinding
    }

    var operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization {
        failedInventory.operationLeaseAuthorization
    }

    init?(
        mint: IOSProtectedAudioNamespaceInventoryMint,
        failedInventory: IOSFailedHistoryProtectedAudioInventory,
        pendingSource: IOSPendingRecordingJournalMetadataSnapshot?
    ) {
        _ = mint
        guard let combined = Self.combine(
            failedInventory: failedInventory,
            pendingSource: pendingSource
        ) else {
            return nil
        }
        self.failedInventory = failedInventory
        self.pendingSource = pendingSource
        artifacts = combined.artifacts
        pendingAliasesPendingJournalRetirement = combined.pendingAliases
    }

    #if DEBUG
    /// Exercises the production ownership-combination rules without making the
    /// Pending store's production mint available to tests.
    init?(
        testingFailedInventory:
            IOSFailedHistoryProtectedAudioInventory,
        pendingSource: IOSPendingRecordingJournalMetadataSnapshot?
    ) {
        guard let combined = Self.combine(
            failedInventory: testingFailedInventory,
            pendingSource: pendingSource
        ) else {
            return nil
        }
        failedInventory = testingFailedInventory
        self.pendingSource = pendingSource
        artifacts = combined.artifacts
        pendingAliasesPendingJournalRetirement = combined.pendingAliases
    }

    /// Narrow descriptor-filesystem seam. It deliberately preserves malformed
    /// artifact sets so the filesystem can prove that it rejects them.
    init(
        testingRepositoryBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization,
        artifacts: [Artifact]
    ) {
        failedInventory = IOSFailedHistoryProtectedAudioInventory(
            testingRepositoryBinding: testingRepositoryBinding,
            operationLeaseAuthorization: operationLeaseAuthorization,
            artifacts: artifacts
        )
        pendingSource = nil
        self.artifacts = artifacts
        pendingAliasesPendingJournalRetirement = false
    }
    #endif
}

private extension IOSProtectedAudioNamespaceInventory {
    struct CombinedArtifacts {
        let artifacts: [Artifact]
        let pendingAliases: Bool
    }

    struct ArtifactOwnership: Equatable {
        let attemptID: UUID
        let relativeIdentifier: String
    }

    static let maximumUniqueArtifactCount = 11

    static func combine(
        failedInventory: IOSFailedHistoryProtectedAudioInventory,
        pendingSource: IOSPendingRecordingJournalMetadataSnapshot?
    ) -> CombinedArtifacts? {
        guard failedInventory.operationLeaseAuthorization
                .provesActiveLease(),
              failedInventory.repositoryBinding.physicalRootIdentity != nil,
              failedInventory.artifacts.count
                <= maximumUniqueArtifactCount,
              hasUniqueOwnership(failedInventory.artifacts) else {
            return nil
        }

        let pendingJournalRetirementRows = failedInventory.failedSource?
            .envelope.entries.filter {
                $0.ownershipState == .pendingJournalRetirement
            } ?? []
        guard pendingJournalRetirementRows.count <= 1,
              failedInventory.hasPendingJournalRetirement
                == !pendingJournalRetirementRows.isEmpty else {
            return nil
        }

        guard let pendingSource else {
            guard pendingJournalRetirementRows.isEmpty else { return nil }
            return CombinedArtifacts(
                artifacts: failedInventory.artifacts,
                pendingAliases: false
            )
        }

        let pending = pendingSource.recording
        let pendingOwnership = ArtifactOwnership(
            attemptID: pending.attemptID,
            relativeIdentifier: pending.audioRelativeIdentifier
        )
        let collisions = failedInventory.artifacts.filter {
            let ownership = ownership(of: $0)
            return ownership.attemptID == pendingOwnership.attemptID
                || ownership.relativeIdentifier
                    == pendingOwnership.relativeIdentifier
        }

        if collisions.isEmpty {
            guard pendingJournalRetirementRows.isEmpty else { return nil }
            let combined = failedInventory.artifacts + [
                Artifact.row(
                    attemptID: pending.attemptID,
                    relativeIdentifier: pending.audioRelativeIdentifier,
                    durationMilliseconds: pending.durationMilliseconds,
                    byteCount: pending.byteCount
                ),
            ]
            guard combined.count <= maximumUniqueArtifactCount else {
                return nil
            }
            return CombinedArtifacts(
                artifacts: combined,
                pendingAliases: false
            )
        }

        guard collisions.count == 1,
              case .row(
                  let failedAttemptID,
                  let failedRelativeIdentifier,
                  _,
                  _
              ) = collisions[0],
              failedAttemptID == pendingOwnership.attemptID,
              failedRelativeIdentifier
                == pendingOwnership.relativeIdentifier,
              pendingJournalRetirementRows.count == 1,
              let failedRow = pendingJournalRetirementRows.first,
              failedRow.attemptID == pendingOwnership.attemptID,
              failedRow.audioRelativeIdentifier
                == pendingOwnership.relativeIdentifier,
              let pendingIdentity = IOSFailedHistoryPendingMatchIdentity(
                  pending: pending
              ),
              let failedIdentity = IOSFailedHistoryPendingMatchIdentity(
                  failedRow: failedRow
              ),
              pendingIdentity == failedIdentity else {
            return nil
        }
        return CombinedArtifacts(
            artifacts: failedInventory.artifacts,
            pendingAliases: true
        )
    }

    static func hasUniqueOwnership(_ artifacts: [Artifact]) -> Bool {
        let ownership = artifacts.map(ownership(of:))
        return Set(ownership.map(\.attemptID)).count == ownership.count
            && Set(ownership.map(\.relativeIdentifier)).count
                == ownership.count
    }

    static func ownership(of artifact: Artifact) -> ArtifactOwnership {
        switch artifact {
        case .row(let attemptID, let relativeIdentifier, _, _),
                .tombstone(let attemptID, let relativeIdentifier, _):
            ArtifactOwnership(
                attemptID: attemptID,
                relativeIdentifier: relativeIdentifier
            )
        }
    }
}

extension IOSProtectedAudioNamespaceInventory:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSProtectedAudioNamespaceInventory(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
