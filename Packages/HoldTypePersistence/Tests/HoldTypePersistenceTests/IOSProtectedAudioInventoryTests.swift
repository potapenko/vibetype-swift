import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSProtectedAudioInventoryTests {
    @Test func exactPendingJournalRetirementAliasCountsOnce()
        async throws {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let root = try makeInventoryTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let context = registry.context(for: root)
        let row = try failedHistoryTestEntry(
            index: 80,
            ownershipState: .pendingJournalRetirement
        )
        let matchingPending = try pendingRecording(matching: row)
        let matchingSnapshot = try metadataSnapshot(
            for: matchingPending
        )
        let unrelatedSnapshot = try metadataSnapshot(
            for: pendingRecording(index: 81)
        )
        let mismatchedSnapshot = try metadataSnapshot(
            for: pendingRecording(
                matching: row,
                transcriptionModel: "different-model"
            )
        )

        try await context.operationGate.perform { lease in
            _ = try await context.failedHistoryStore
                .mutateExactForTesting(
                    IOSFailedHistoryEnvelope(
                        revision: 1,
                        entries: [row],
                        audioCleanup: []
                    ),
                    operationLeaseAuthorization: lease
                )
            let failedInventory = try await context.failedHistoryStore
                .sealProtectedAudioInventory(
                    expectedPendingStoreIdentity:
                        context.pendingRecordingStoreIdentity,
                    operationLeaseAuthorization: lease
                )
            let inventory = try #require(
                IOSProtectedAudioNamespaceInventory(
                    testingFailedInventory: failedInventory,
                    pendingSource: matchingSnapshot
                )
            )

            #expect(inventory.artifacts == failedInventory.artifacts)
            #expect(inventory.artifacts.count == 1)
            #expect(inventory.pendingSource == matchingSnapshot)
            #expect(inventory.pendingAliasesPendingJournalRetirement)
            #expect(
                inventory.failedStoreIdentity
                    == failedInventory.failedStoreIdentity
            )
            #expect(
                inventory.expectedPendingStoreIdentity
                    == failedInventory.expectedPendingStoreIdentity
            )
            #expect(inventory.ownerIdentity == failedInventory.ownerIdentity)
            #expect(
                inventory.repositoryBinding
                    == failedInventory.repositoryBinding
            )
            #expect(
                inventory.operationLeaseAuthorization
                    .provesSameActiveLease(as: lease)
            )
            #expect(
                String(describing: inventory)
                    == "IOSProtectedAudioNamespaceInventory(redacted)"
            )
            #expect(inventory.customMirror.children.isEmpty)

            #expect(
                IOSProtectedAudioNamespaceInventory(
                    testingFailedInventory: failedInventory,
                    pendingSource: nil
                ) == nil
            )
            #expect(
                IOSProtectedAudioNamespaceInventory(
                    testingFailedInventory: failedInventory,
                    pendingSource: unrelatedSnapshot
                ) == nil
            )
            #expect(
                IOSProtectedAudioNamespaceInventory(
                    testingFailedInventory: failedInventory,
                    pendingSource: mismatchedSnapshot
                ) == nil
            )
        }
    }

    @Test func partialAndNonPJRNamespaceCollisionsFailClosed()
        async throws {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let root = try makeInventoryTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let context = registry.context(for: root)
        let pending = try pendingRecording(index: 90)
        let snapshot = try metadataSnapshot(for: pending)
        let foreignAttemptID = failedHistoryTestUUID(
            namespace: 0x51,
            index: 90
        )
        let sameAttemptDifferentPath =
            IOSPendingRecordingStorageLocation.relativeAudioIdentifier(
                for: pending.attemptID,
                format: .wav
            )

        try await context.operationGate.perform { lease in
            func failedInventory(
                _ artifacts: [
                    IOSFailedHistoryProtectedAudioInventory.Artifact
                ]
            ) -> IOSFailedHistoryProtectedAudioInventory {
                IOSFailedHistoryProtectedAudioInventory(
                    testingRepositoryBinding: context.repositoryBinding,
                    operationLeaseAuthorization: lease,
                    artifacts: artifacts
                )
            }

            let sameAttemptOnly = failedInventory([
                .row(
                    attemptID: pending.attemptID,
                    relativeIdentifier: sameAttemptDifferentPath,
                    durationMilliseconds: pending.durationMilliseconds,
                    byteCount: pending.byteCount
                ),
            ])
            #expect(
                IOSProtectedAudioNamespaceInventory(
                    testingFailedInventory: sameAttemptOnly,
                    pendingSource: snapshot
                ) == nil
            )

            let samePathOnly = failedInventory([
                .row(
                    attemptID: foreignAttemptID,
                    relativeIdentifier: pending.audioRelativeIdentifier,
                    durationMilliseconds: pending.durationMilliseconds,
                    byteCount: pending.byteCount
                ),
            ])
            #expect(
                IOSProtectedAudioNamespaceInventory(
                    testingFailedInventory: samePathOnly,
                    pendingSource: snapshot
                ) == nil
            )

            let tombstoneCollision = failedInventory([
                .tombstone(
                    attemptID: pending.attemptID,
                    relativeIdentifier: pending.audioRelativeIdentifier,
                    byteCount: pending.byteCount
                ),
            ])
            #expect(
                IOSProtectedAudioNamespaceInventory(
                    testingFailedInventory: tombstoneCollision,
                    pendingSource: snapshot
                ) == nil
            )

            let readyRowCollision = failedInventory([
                .row(
                    attemptID: pending.attemptID,
                    relativeIdentifier: pending.audioRelativeIdentifier,
                    durationMilliseconds: pending.durationMilliseconds,
                    byteCount: pending.byteCount
                ),
            ])
            #expect(
                IOSProtectedAudioNamespaceInventory(
                    testingFailedInventory: readyRowCollision,
                    pendingSource: snapshot
                ) == nil
            )

            let duplicateOwnership = failedInventory([
                .row(
                    attemptID: pending.attemptID,
                    relativeIdentifier: pending.audioRelativeIdentifier,
                    durationMilliseconds: pending.durationMilliseconds,
                    byteCount: pending.byteCount
                ),
                .tombstone(
                    attemptID: pending.attemptID,
                    relativeIdentifier: sameAttemptDifferentPath,
                    byteCount: pending.byteCount
                ),
            ])
            #expect(
                IOSProtectedAudioNamespaceInventory(
                    testingFailedInventory: duplicateOwnership,
                    pendingSource: nil
                ) == nil
            )
        }
    }

    @Test func namespaceInventoryIsBoundedToElevenUniqueArtifacts()
        async throws {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let root = try makeInventoryTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let context = registry.context(for: root)
        let pending = try pendingRecording(index: 110)
        let snapshot = try metadataSnapshot(for: pending)

        try await context.operationGate.perform { lease in
            func artifacts(_ count: Int) -> [
                IOSFailedHistoryProtectedAudioInventory.Artifact
            ] {
                (0..<count).map { index in
                    let attemptID = failedHistoryTestUUID(
                        namespace: 0x61,
                        index: index
                    )
                    return .row(
                        attemptID: attemptID,
                        relativeIdentifier:
                            IOSPendingRecordingStorageLocation
                                .relativeAudioIdentifier(
                                    for: attemptID,
                                    format: .m4a
                                ),
                        durationMilliseconds: 1_000,
                        byteCount: 4_096
                    )
                }
            }

            let ten = IOSFailedHistoryProtectedAudioInventory(
                testingRepositoryBinding: context.repositoryBinding,
                operationLeaseAuthorization: lease,
                artifacts: artifacts(10)
            )
            let accepted = try #require(
                IOSProtectedAudioNamespaceInventory(
                    testingFailedInventory: ten,
                    pendingSource: snapshot
                )
            )
            #expect(accepted.artifacts.count == 11)
            #expect(!accepted.pendingAliasesPendingJournalRetirement)

            let eleven = IOSFailedHistoryProtectedAudioInventory(
                testingRepositoryBinding: context.repositoryBinding,
                operationLeaseAuthorization: lease,
                artifacts: artifacts(11)
            )
            #expect(
                IOSProtectedAudioNamespaceInventory(
                    testingFailedInventory: eleven,
                    pendingSource: snapshot
                ) == nil
            )
        }
    }
}

private func makeInventoryTestDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "protected-audio-inventory-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: false
    )
    return root
}

private func pendingRecording(
    index: Int
) throws -> IOSPendingRecording {
    let attemptID = failedHistoryTestUUID(namespace: 0x41, index: index)
    return try IOSPendingRecording(
        attemptID: attemptID,
        audioRelativeIdentifier:
            IOSPendingRecordingStorageLocation.relativeAudioIdentifier(
                for: attemptID,
                format: .m4a
            ),
        createdAt: try failedHistoryTestDate(
            offsetMilliseconds: Int64(index * 10)
        ),
        updatedAt: try failedHistoryTestDate(
            offsetMilliseconds: Int64(index * 10 + 2)
        ),
        phase: .readyForTranscription,
        outputIntent: .standard,
        transcriptionID: nil,
        transcriptionModel: "gpt-4o-mini-transcribe",
        transcriptionLanguageCode: "en",
        durationMilliseconds: 1_250,
        byteCount: 4_096
    )
}

private func pendingRecording(
    matching row: IOSFailedHistoryEntry,
    transcriptionModel: String? = nil
) throws -> IOSPendingRecording {
    try IOSPendingRecording(
        attemptID: row.attemptID,
        audioRelativeIdentifier: row.audioRelativeIdentifier,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        phase: .awaitingRecovery,
        outputIntent: row.outputIntent,
        transcriptionID: nil,
        transcriptionModel:
            transcriptionModel ?? row.transcriptionModel,
        transcriptionLanguageCode: row.transcriptionLanguageCode,
        durationMilliseconds: row.durationMilliseconds,
        byteCount: row.byteCount
    )
}

private func metadataSnapshot(
    for recording: IOSPendingRecording
) throws -> IOSPendingRecordingJournalMetadataSnapshot {
    let root = try makeInventoryTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FoundationIOSPendingRecordingJournalRepository(
        applicationSupportDirectoryURL: root
    )
    try repository.create(recording)
    return try #require(
        try repository.loadMetadataSnapshot(
            authorization:
                IOSPendingRecordingMetadataRetirementAuthorization(
                    testingToken: 1
                )
        )
    )
}
