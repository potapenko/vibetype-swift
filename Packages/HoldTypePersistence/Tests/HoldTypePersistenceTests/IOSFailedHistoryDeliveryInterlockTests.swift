import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSFailedHistoryDeliveryInterlockTests {
    @Test func frozenSlotReservationClosesThePreRelationMutationWindow()
        async throws {
        let fixture = try FailedRetryDeliveryInterlockFixture()
        let completion = try await fixture.prepareProviderCompletion()

        try await fixture.context.operationGate.perform { lease in
            let frozen = try await fixture.freezeAcceptingRelation(
                completion,
                operationLeaseAuthorization: lease
            )
            #expect(
                fixture.context.failedHistoryMutationInterlock
                    .hasRetryDeliveryProtection
            )
            #expect(
                !fixture.context.failedHistoryMutationInterlock
                    .hasRetryDeliveryRelation
            )
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                _ = try await fixture.context.deliveryStore.accept(
                    IOSAcceptedOutputDeliveryPreparation(
                        deliveryID: UUID(),
                        sessionID: UUID(),
                        attemptID: UUID(),
                        transcriptID: UUID(),
                        rawAcceptedText: "racing ordinary acceptance",
                        outputIntent: .standard,
                        automaticInsertionPreferenceEnabled: false,
                        keepLatestResult: true,
                        historyWrite: nil
                    )
                )
            }
            #expect(
                try await fixture.context.deliveryStore
                    .releaseFailedRetryFrozenSlotReservation(
                        frozen.proof,
                        dispatchReceipt: completion.dispatchReceipt,
                        operationLeaseAuthorization: lease
                    )
            )
            #expect(
                !fixture.context.failedHistoryMutationInterlock
                    .hasRetryDeliveryProtection
            )
        }
    }

    @Test func acceptingRelationBlocksOrdinaryDeliveryMutations()
        async throws {
        let fixture = try FailedRetryDeliveryInterlockFixture()
        let predecessor = try await fixture.preparePendingPredecessor()
        let completion = try await fixture.prepareProviderCompletion()

        try await fixture.context.operationGate.perform { lease in
            let relation = try await fixture.commitAcceptingRelation(
                completion,
                operationLeaseAuthorization: lease
            )
            #expect(
                fixture.context.failedHistoryMutationInterlock
                    .hasRetryDeliveryRelation
            )

            for mutation in OrdinaryDeliveryMutation.allCases {
                await #expect(
                    throws: IOSAcceptedOutputDeliveryError.commitUncertain
                ) {
                    try await fixture.performOrdinaryMutation(
                        mutation,
                        predecessor: predecessor
                    )
                }
            }

            let observed = try await fixture.context.deliveryStore.load()
            #expect(observed == .active(predecessor.record))
            #expect(
                relation.receipt.frozenSlotProof.frozenSlot
                    == .existing(predecessor.snapshot)
            )
        }
    }

    @Test func exactRelationPermitsRetryAcceptanceAndHistoryOnly()
        async throws {
        let fixture = try FailedRetryDeliveryInterlockFixture()
        let completion = try await fixture.prepareProviderCompletion()

        try await fixture.context.operationGate.perform { lease in
            let relation = try await fixture.commitAcceptingRelation(
                completion,
                operationLeaseAuthorization: lease
            )
            let permit = try await fixture.context.deliveryStore
                .authorizeFailedRetryDeliveryPermit(
                    acceptingOutputReceipt: relation.receipt,
                    operationLeaseAuthorization: lease
                )
            let historyCapture = try #require(
                relation.preparation.historyCapture
            )
            let unrelated = try IOSAcceptedOutputDeliveryPreparation(
                deliveryID: UUID(),
                sessionID: UUID(),
                attemptID: UUID(),
                transcriptID: UUID(),
                rawAcceptedText: "unrelated accepted text",
                outputIntent: relation.preparation.outputIntent,
                automaticInsertionPreferenceEnabled: false,
                keepLatestResult: relation.preparation.keepLatestResult,
                historyCapture: historyCapture
            )
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            ) {
                _ = try await fixture.context.deliveryStore
                    .acceptForHistoryCoordinator(
                        unrelated,
                        operationLeaseAuthorization: lease,
                        failedRetryPermit: permit
                    )
            }
            let foreignStore = IOSAcceptedOutputDeliveryStore(
                applicationSupportDirectoryURL:
                    fixture.applicationSupportDirectoryURL
                        .appendingPathComponent("Foreign", isDirectory: true),
                capabilityOwnerIdentity: fixture.context.ownerIdentity,
                operationGateIdentity: fixture.context.operationGate.identity,
                failedHistoryMutationInterlock:
                    fixture.context.failedHistoryMutationInterlock
            )
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            ) {
                _ = try await foreignStore
                    .authorizeFailedRetryDeliveryPermit(
                        acceptingOutputReceipt: relation.receipt,
                        operationLeaseAuthorization: lease
                    )
            }

            let accepted = try await fixture.context.deliveryStore
                .acceptFailedRetry(
                    relation.preparation,
                    acceptingOutputReceipt: relation.receipt,
                    operationLeaseAuthorization: lease
                )
            let expectation = IOSAcceptedOutputDeliveryExpectation(
                record: accepted.record
            )

            let authorization = try await fixture.context.deliveryStore
                .authorizePendingHistoryWrite(
                    expected: expectation,
                    operationLeaseAuthorization: lease,
                    failedRetryPermit: permit
                )
            let policyReceipt = try #require(
                relation.preparation.historyCapture?.policyReceipt
            )
            let rowReceipt = try await fixture.context.acceptedHistoryStore
                .decideFailedRetryReplay(
                    delivery: authorization,
                    policy: policyReceipt,
                    deliveryPermit: permit
                )

            let terminal = try await fixture.context.deliveryStore
                .commitHistoryWrite(
                    authorization: authorization,
                    rowReceipt: rowReceipt,
                    operationLeaseAuthorization: lease,
                    failedRetryPermit: permit
                )
            #expect(terminal.historyWrite?.state == .committed)
            _ = try await fixture.context.deliveryStore
                .confirmFailedRetryTerminalDelivery(
                    acceptingOutputReceipt: relation.receipt,
                    operationLeaseAuthorization: lease
                )
            #expect(
                fixture.context.failedHistoryMutationInterlock
                    .hasRetryDeliveryRelation
            )
            #expect(permit.provesActiveRelation())
        }
    }

    @Test func storeMintedPermitRejectsSubstitutedCurrentSource()
        async throws {
        let fixture = try FailedRetryDeliveryInterlockFixture()
        let completion = try await fixture.prepareProviderCompletion()

        try await fixture.context.operationGate.perform { lease in
            let relation = try await fixture.commitAcceptingRelation(
                completion,
                operationLeaseAuthorization: lease
            )
            let permit = try await fixture.context.deliveryStore
                .authorizeFailedRetryDeliveryPermit(
                    acceptingOutputReceipt: relation.receipt,
                    operationLeaseAuthorization: lease
                )
            let foreignStore = IOSAcceptedOutputDeliveryStore(
                applicationSupportDirectoryURL:
                    fixture.applicationSupportDirectoryURL,
                capabilityOwnerIdentity: fixture.context.ownerIdentity
            )
            _ = try await foreignStore.accept(
                IOSAcceptedOutputDeliveryPreparation(
                    deliveryID: UUID(),
                    sessionID: UUID(),
                    attemptID: UUID(),
                    transcriptID: UUID(),
                    rawAcceptedText: "substituted current slot",
                    outputIntent: .standard,
                    automaticInsertionPreferenceEnabled: false,
                    keepLatestResult: true,
                    historyWrite: nil
                )
            )

            await #expect(
                throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            ) {
                _ = try await fixture.context.deliveryStore
                    .acceptForHistoryCoordinator(
                        relation.preparation,
                        operationLeaseAuthorization: lease,
                        failedRetryPermit: permit
                    )
            }
        }
    }

    @Test func historyTransitionRejectsChangedRetryProvenance()
        async throws {
        for substitutedRetryID in [UUID?.none, UUID()] {
            let fixture = try FailedRetryDeliveryInterlockFixture()
            let completion = try await fixture.prepareProviderCompletion()

            try await fixture.context.operationGate.perform { lease in
                let relation = try await fixture.commitAcceptingRelation(
                    completion,
                    operationLeaseAuthorization: lease
                )
                let permit = try await fixture.context.deliveryStore
                    .authorizeFailedRetryDeliveryPermit(
                        acceptingOutputReceipt: relation.receipt,
                        operationLeaseAuthorization: lease
                    )
                let acceptance = try await fixture.context.deliveryStore
                    .acceptFailedRetry(
                        relation.preparation,
                        acceptingOutputReceipt: relation.receipt,
                        operationLeaseAuthorization: lease
                    )
                let authorization = try await fixture.context.deliveryStore
                    .authorizePendingHistoryWrite(
                        expected: IOSAcceptedOutputDeliveryExpectation(
                            record: acceptance.record
                        ),
                        operationLeaseAuthorization: lease,
                        failedRetryPermit: permit
                    )
                let policyReceipt = try #require(
                    relation.preparation.historyCapture?.policyReceipt
                )
                let rowReceipt = try await fixture.context
                    .acceptedHistoryStore.decideFailedRetryReplay(
                        delivery: authorization,
                        policy: policyReceipt,
                        deliveryPermit: permit
                    )
                let journal =
                    FoundationIOSAcceptedOutputDeliveryJournalRepository(
                        applicationSupportDirectoryURL:
                            fixture.applicationSupportDirectoryURL,
                        repositoryGuard: fixture.context.repositoryGuard
                    )
                let current = try #require(try journal.load())
                _ = try journal.replace(
                    try terminalRetrySubstitution(
                        acceptance.record,
                        failedRetryID: substitutedRetryID
                    ),
                    expected: current
                )

                await #expect(
                    throws:
                        IOSAcceptedOutputDeliveryError.compareAndSwapFailed
                ) {
                    _ = try await fixture.context.deliveryStore
                        .commitHistoryWrite(
                            authorization: authorization,
                            rowReceipt: rowReceipt,
                            operationLeaseAuthorization: lease,
                            failedRetryPermit: permit
                        )
                }
            }
        }
    }

    @Test func exactForeignAcceptanceCannotForgeRetryProvenance()
        async throws {
        let fixture = try FailedRetryDeliveryInterlockFixture()
        let completion = try await fixture.prepareProviderCompletion()

        try await fixture.context.operationGate.perform { lease in
            let relation = try await fixture.commitAcceptingRelation(
                completion,
                operationLeaseAuthorization: lease
            )
            let foreignStore = IOSAcceptedOutputDeliveryStore(
                applicationSupportDirectoryURL:
                    fixture.applicationSupportDirectoryURL,
                capabilityOwnerIdentity: fixture.context.ownerIdentity
            )
            let foreign = try await foreignStore.accept(
                relation.preparation
            )
            #expect(foreign.failedRetryID == nil)

            await #expect(
                throws: IOSAcceptedOutputDeliveryError.identityCollision
            ) {
                _ = try await fixture.context.deliveryStore
                    .acceptFailedRetry(
                        relation.preparation,
                        acceptingOutputReceipt: relation.receipt,
                        operationLeaseAuthorization: lease
                    )
            }
        }
    }

    @Test func predecessorLineageRequiresOneRevisionAndExactUTF8()
        async throws {
        for variant in InvalidPredecessorLineageVariant.allCases {
            let fixture: FailedRetryDeliveryInterlockFixture
            let predecessor: FailedRetryDeliveryPredecessor
            let completion: IOSFailedHistoryRetryProviderCompletion<String>
            do {
                fixture = try FailedRetryDeliveryInterlockFixture()
                predecessor = try await fixture.preparePendingPredecessor()
                completion = try await fixture.prepareProviderCompletion()
            } catch {
                Issue.record("Lineage setup failed for \(variant).")
                throw error
            }

            do {
                try await fixture.context.operationGate.perform { lease in
                let relation = try await fixture.commitAcceptingRelation(
                    completion,
                    operationLeaseAuthorization: lease
                )
                let permit = try await fixture.context.deliveryStore
                    .authorizeFailedRetryDeliveryPermit(
                        acceptingOutputReceipt: relation.receipt,
                        operationLeaseAuthorization: lease
                    )
                let journal =
                    FoundationIOSAcceptedOutputDeliveryJournalRepository(
                        applicationSupportDirectoryURL:
                            fixture.applicationSupportDirectoryURL,
                        repositoryGuard: fixture.context.repositoryGuard
                    )
                let invalid: IOSAcceptedOutputDeliveryRecord
                do {
                    invalid = try invalidCancelledPredecessor(
                        predecessor.record,
                        variant: variant
                    )
                } catch {
                    Issue.record("Invalid record setup failed for \(variant).")
                    throw error
                }
                do {
                    let current = try #require(try journal.load())
                    _ = try journal.replace(invalid, expected: current)
                } catch {
                    Issue.record("Journal substitution failed for \(variant).")
                    throw error
                }

                await #expect(
                    throws:
                        IOSAcceptedOutputDeliveryError.compareAndSwapFailed
                ) {
                    _ = try await fixture.context.deliveryStore
                        .acceptForHistoryCoordinator(
                            relation.preparation,
                            operationLeaseAuthorization: lease,
                            failedRetryPermit: permit
                        )
                }
                }
            } catch {
                Issue.record("Lineage mutation failed for \(variant).")
                throw error
            }
        }
    }

    @Test func exactCancelledPredecessorRemainsRetryRecoverable()
        async throws {
        let fixture = try FailedRetryDeliveryInterlockFixture()
        let predecessor = try await fixture.preparePendingPredecessor()
        let completion = try await fixture.prepareProviderCompletion()

        try await fixture.context.operationGate.perform { lease in
            let relation = try await fixture.commitAcceptingRelation(
                completion,
                operationLeaseAuthorization: lease
            )
            let journal = FoundationIOSAcceptedOutputDeliveryJournalRepository(
                applicationSupportDirectoryURL:
                    fixture.applicationSupportDirectoryURL,
                repositoryGuard: fixture.context.repositoryGuard
            )
            let current = try #require(try journal.load())
            _ = try journal.replace(
                try exactCancelledPredecessor(predecessor.record),
                expected: current
            )

            _ = try await fixture.context.deliveryStore
                .refreshFailedRetryFrozenSlotProof(
                    from: relation.receipt,
                    operationLeaseAuthorization: lease
                )
            await #expect(
                throws:
                    IOSAcceptedOutputDeliveryError.historyTransferRequired
            ) {
                _ = try await fixture.context.deliveryStore.acceptFailedRetry(
                    relation.preparation,
                    acceptingOutputReceipt: relation.receipt,
                    operationLeaseAuthorization: lease
                )
            }
        }
    }
}

private enum InvalidPredecessorLineageVariant: CaseIterable {
    case skippedRevision
    case canonicallyEquivalentText
}

private enum OrdinaryDeliveryMutation: CaseIterable, Sendable {
    case genericAcceptance
    case disableKeepLatest
    case clear
    case expiryRemoval
    case bridgeReservation
    case historyAuthorization
    case historyTransition
    case stagingMaintenance
    case unreadableDiscard
}

private struct FailedRetryDeliveryPredecessor: Sendable {
    let record: IOSAcceptedOutputDeliveryRecord
    let snapshot: IOSAcceptedOutputDeliveryJournalSnapshot
    let authorization: IOSAcceptedOutputDeliveryAuthorization
    let rowReceipt: IOSAcceptedHistoryRowReceipt
}

private struct FailedRetryAcceptingRelation: Sendable {
    let receipt: IOSFailedHistoryRetryAcceptingOutputReceipt
    let preparation: IOSAcceptedOutputDeliveryPreparation
}

private struct FailedRetryFrozenRelation: Sendable {
    let proof: IOSAcceptedOutputDeliveryFrozenSlotProof
    let preparation: IOSAcceptedOutputDeliveryPreparation
}

private final class FailedRetryDeliveryInterlockFixture:
    @unchecked Sendable {
    let parentDirectoryURL: URL
    let applicationSupportDirectoryURL: URL
    let registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry
    let context: IOSAcceptedHistoryCoordinatorProcessContext
    let coordinator: IOSAcceptedHistoryCoordinator

    init() throws {
        parentDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "failed-retry-delivery-interlock-\(UUID().uuidString)",
                isDirectory: true
            )
        applicationSupportDirectoryURL = parentDirectoryURL
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
        try FileManager.default.createDirectory(
            at: applicationSupportDirectoryURL,
            withIntermediateDirectories: true
        )

        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        self.registry = registry
        let context = registry.context(for: applicationSupportDirectoryURL)
        self.context = context
        coordinator = IOSAcceptedHistoryCoordinator(
            policyStore: context.policyStore,
            acceptedHistoryStore: context.acceptedHistoryStore,
            failedHistoryStore: context.failedHistoryStore,
            pendingRecordingStore: context.pendingRecordingStore,
            outboxStore: context.outboxStore,
            deliveryStore: context.deliveryStore,
            operationGate: context.operationGate,
            baselineRecoveryState: context.baselineRecoveryState,
            acceptanceState: context.acceptanceState,
            pendingReplacementState: context.pendingReplacementState,
            outboxWorkerState: context.outboxWorkerState,
            policyCutoverState: context.policyCutoverState,
            failedHistoryTransferState: context.failedHistoryTransferState,
            failedHistoryAudioCleanupState:
                context.failedHistoryAudioCleanupState,
            failedHistoryRetryState: context.failedHistoryRetryState,
            ownerIdentity: context.ownerIdentity,
            repositoryIdentityState: context.repositoryIdentityState,
            repositoryRegistration:
                IOSAcceptedHistoryCoordinatorRepositoryRegistration(
                    registry: registry,
                    context: context,
                    applicationSupportDirectoryURL:
                        applicationSupportDirectoryURL
                )
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: parentDirectoryURL)
    }

    func preparePendingPredecessor()
        async throws -> FailedRetryDeliveryPredecessor {
        let capture = try await coordinator.capture(
            transcriptionModel: "predecessor-model",
            transcriptionLanguageCode: "en",
            durationMilliseconds: 1_000
        )
        let preparation = try IOSAcceptedOutputDeliveryPreparation(
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: UUID(),
            transcriptID: UUID(),
            rawAcceptedText: "prédecessor",
            outputIntent: .standard,
            automaticInsertionPreferenceEnabled: false,
            keepLatestResult: true,
            historyCapture: capture
        )
        let record = try await context.deliveryStore.accept(preparation)
        let authorization = try await context.deliveryStore
            .authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(record: record)
            )
        let rowReceipt = try await context.acceptedHistoryStore.decideUpsert(
            delivery: authorization,
            policy: capture.policyReceipt
        )
        let snapshot = IOSAcceptedOutputDeliveryJournalSnapshot(
            record: record,
            fileRevision: authorization.snapshot.fileRevision
        )
        return FailedRetryDeliveryPredecessor(
            record: record,
            snapshot: snapshot,
            authorization: authorization,
            rowReceipt: rowReceipt
        )
    }

    func prepareProviderCompletion() async throws
        -> IOSFailedHistoryRetryProviderCompletion<String> {
        let row = try await prepareReadyFailure()
        let handoff = try await coordinator.prepareFailedHistoryRetry(
            attemptID: row.attemptID,
            setup: try failedRetryInterlockSetup()
        )
        return try await handoff.execute { _, _ in
            "retry accepted"
        }
    }

    func commitAcceptingRelation(
        _ completion: IOSFailedHistoryRetryProviderCompletion<String>,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> FailedRetryAcceptingRelation {
        let frozen = try await freezeAcceptingRelation(
            completion,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        let dispatchReceipt = completion.dispatchReceipt
        let accepting = try await context.failedHistoryStore
            .prepareRetryAcceptingOutput(
                using: dispatchReceipt,
                providerCompletionClaim: completion.claim,
                frozenSlotProof: frozen.proof,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        let receipt: IOSFailedHistoryRetryAcceptingOutputReceipt
        switch accepting {
        case .commit(let authorization):
            receipt = try await context.failedHistoryStore
                .commitRetryAcceptingOutput(using: authorization)
        case .completed(let completed):
            receipt = completed
        }
        return FailedRetryAcceptingRelation(
            receipt: receipt,
            preparation: frozen.preparation
        )
    }

    func freezeAcceptingRelation(
        _ completion: IOSFailedHistoryRetryProviderCompletion<String>,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> FailedRetryFrozenRelation {
        let dispatchReceipt = completion.dispatchReceipt
        let row = dispatchReceipt.row
        let operation = dispatchReceipt.retryOperation
        let policyReceipt = dispatchReceipt.authorization
            .reservationReceipt.authorization.policyReceipt
        let historyWrite = try IOSAcceptedOutputHistoryWrite(
            policyGeneration: row.policyGeneration,
            transcriptionModel: row.transcriptionModel,
            transcriptionLanguageCode: row.transcriptionLanguageCode,
            durationMilliseconds: row.durationMilliseconds
        )
        let historyCapture = IOSAcceptedOutputHistoryCapture(
            policyReceipt: policyReceipt,
            ownerIdentity: context.ownerIdentity,
            historyWrite: historyWrite
        )
        let preparation = try IOSAcceptedOutputDeliveryPreparation(
            deliveryID: operation.deliveryID,
            sessionID: operation.sessionID,
            attemptID: row.attemptID,
            transcriptID: operation.transcriptID,
            rawAcceptedText: completion.outcome,
            outputIntent: row.outputIntent,
            automaticInsertionPreferenceEnabled: false,
            keepLatestResult: completion.setup.keepLatestResult,
            historyCapture: historyCapture
        )
        let frozenSlotProof = try await context.deliveryStore
            .freezeFailedRetrySlot(
                preparation: preparation,
                dispatchReceipt: dispatchReceipt,
                operationLeaseAuthorization:
                    operationLeaseAuthorization
            )
        return FailedRetryFrozenRelation(
            proof: frozenSlotProof,
            preparation: preparation
        )
    }

    func performOrdinaryMutation(
        _ mutation: OrdinaryDeliveryMutation,
        predecessor: FailedRetryDeliveryPredecessor
    ) async throws {
        let expected = IOSAcceptedOutputDeliveryExpectation(
            record: predecessor.record
        )
        switch mutation {
        case .genericAcceptance:
            _ = try await context.deliveryStore.accept(
                try IOSAcceptedOutputDeliveryPreparation(
                    deliveryID: UUID(),
                    sessionID: UUID(),
                    attemptID: UUID(),
                    transcriptID: UUID(),
                    rawAcceptedText: "ordinary replacement",
                    outputIntent: .standard,
                    automaticInsertionPreferenceEnabled: false,
                    keepLatestResult: true,
                    historyWrite: nil
                )
            )
        case .disableKeepLatest:
            _ = try await context.deliveryStore.disableKeepLatestResult(
                expected: expected
            )
        case .clear:
            _ = try await context.deliveryStore.clear(expected: expected)
        case .expiryRemoval:
            _ = try await context.deliveryStore.removeExpired(
                expected: expected
            )
        case .bridgeReservation:
            _ = try await context.deliveryStore.reserveBridgePublication(
                authorization: predecessor.authorization
            )
        case .historyAuthorization:
            _ = try await context.deliveryStore.authorizePendingHistoryWrite(
                expected: expected
            )
        case .historyTransition:
            _ = try await context.deliveryStore.commitHistoryWrite(
                authorization: predecessor.authorization,
                rowReceipt: predecessor.rowReceipt
            )
        case .stagingMaintenance:
            _ = try await context.deliveryStore.performStagingMaintenance()
        case .unreadableDiscard:
            _ = try await context.deliveryStore.discardUnreadableLocalResult()
        }
    }

    private func prepareReadyFailure() async throws -> IOSFailedHistoryEntry {
        _ = try await coordinator.capture(
            transcriptionModel: "gpt-4o-mini-transcribe",
            transcriptionLanguageCode: "en",
            durationMilliseconds: 1_000
        )
        let attemptID = UUID()
        let sourceURL = parentDirectoryURL.appendingPathComponent(
            "source-\(attemptID.uuidString.lowercased()).wav",
            isDirectory: false
        )
        let audio = makeFailedRetryInterlockWAV()
        try audio.write(to: sourceURL, options: .atomic)
        let pending = try await context.pendingRecordingStore.prepare(
            IOSPendingRecordingPreparation(
                attemptID: attemptID,
                sourceArtifact: AudioRecordingArtifact(
                    fileURL: sourceURL,
                    duration: 1,
                    byteCount: Int64(audio.count)
                ),
                initialState: .awaitingRecovery,
                outputIntent: .standard,
                transcriptionConfiguration: TranscriptionConfiguration(
                    model: "gpt-4o-mini-transcribe",
                    language: .english
                )
            )
        )
        _ = try await coordinator.transferPendingRecordingFailure(
            expected: IOSPendingRecordingCASExpectation(recording: pending),
            failure: IOSFailedHistoryTransferFailure(
                category: .networkUnavailable,
                pipelineStage: .transcription
            )
        )
        let envelope = try #require(
            try await context.failedHistoryStore.load()
        )
        return try #require(envelope.entries.first)
    }
}

private func invalidCancelledPredecessor(
    _ predecessor: IOSAcceptedOutputDeliveryRecord,
    variant: InvalidPredecessorLineageVariant
) throws -> IOSAcceptedOutputDeliveryRecord {
    let marker = try #require(predecessor.historyWrite)
    let revisionIncrement: Int64 = switch variant {
    case .skippedRevision: 2
    case .canonicallyEquivalentText: 1
    }
    let acceptedText: String? = switch variant {
    case .skippedRevision:
        predecessor.acceptedText
    case .canonicallyEquivalentText:
        "pre\u{0301}decessor"
    }
    return try IOSAcceptedOutputDeliveryRecord(
        revision: predecessor.revision + revisionIncrement,
        deliveryID: predecessor.deliveryID,
        sessionID: predecessor.sessionID,
        attemptID: predecessor.attemptID,
        transcriptID: predecessor.transcriptID,
        acceptedText: acceptedText,
        outputIntent: predecessor.outputIntent,
        createdAt: predecessor.createdAt,
        updatedAt: predecessor.updatedAt,
        expiresAt: predecessor.expiresAt,
        deliveryState: predecessor.deliveryState,
        automaticInsertionPreferenceEnabled:
            predecessor.automaticInsertionPreferenceEnabled,
        keepLatestResult: predecessor.keepLatestResult,
        publicationGeneration: predecessor.publicationGeneration,
        historyWrite: try marker.replacingState(.cancelled)
    )
}

private func exactCancelledPredecessor(
    _ predecessor: IOSAcceptedOutputDeliveryRecord
) throws -> IOSAcceptedOutputDeliveryRecord {
    let marker = try #require(predecessor.historyWrite)
    return try IOSAcceptedOutputDeliveryRecord(
        revision: predecessor.revision + 1,
        deliveryID: predecessor.deliveryID,
        sessionID: predecessor.sessionID,
        attemptID: predecessor.attemptID,
        transcriptID: predecessor.transcriptID,
        acceptedText: predecessor.acceptedText,
        outputIntent: predecessor.outputIntent,
        createdAt: predecessor.createdAt,
        updatedAt: predecessor.updatedAt,
        expiresAt: predecessor.expiresAt,
        deliveryState: predecessor.deliveryState,
        automaticInsertionPreferenceEnabled:
            predecessor.automaticInsertionPreferenceEnabled,
        keepLatestResult: predecessor.keepLatestResult,
        publicationGeneration: predecessor.publicationGeneration,
        historyWrite: try marker.replacingState(.cancelled)
    )
}

private func terminalRetrySubstitution(
    _ accepted: IOSAcceptedOutputDeliveryRecord,
    failedRetryID: UUID?
) throws -> IOSAcceptedOutputDeliveryRecord {
    try IOSAcceptedOutputDeliveryRecord(
        revision: accepted.revision + 1,
        deliveryID: accepted.deliveryID,
        sessionID: accepted.sessionID,
        attemptID: accepted.attemptID,
        transcriptID: accepted.transcriptID,
        failedRetryID: failedRetryID,
        acceptedText: accepted.acceptedText,
        outputIntent: accepted.outputIntent,
        createdAt: accepted.createdAt,
        updatedAt: accepted.updatedAt,
        expiresAt: accepted.expiresAt,
        deliveryState: accepted.deliveryState,
        automaticInsertionPreferenceEnabled:
            accepted.automaticInsertionPreferenceEnabled,
        keepLatestResult: accepted.keepLatestResult,
        publicationGeneration: accepted.publicationGeneration,
        historyWrite: try #require(accepted.historyWrite)
            .replacingState(.committed)
    )
}

private func failedRetryInterlockSetup()
    throws -> IOSFailedHistoryRetrySetupSnapshot {
    try IOSFailedHistoryRetrySetupSnapshot(
        credentialEligibility: .available,
        transcriptionConfiguration: .defaults,
        transcriptionPromptComposition: TranscriptionPromptComposition(
            resolvedFreeformPrompt: nil,
            context: nil,
            emojiCommandsConfiguration: .defaults,
            customDictionary: .empty
        ),
        textCorrectionConfiguration: .defaults,
        postProcessingConfiguration: .defaults,
        translationConfiguration: nil,
        keepLatestResult: true
    )
}

private func makeFailedRetryInterlockWAV() -> Data {
    let sampleRate: UInt32 = 8_000
    let channelCount: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let dataByteCount = sampleRate * UInt32(bitsPerSample / 8)
    let byteRate = sampleRate * UInt32(channelCount)
        * UInt32(bitsPerSample / 8)
    let blockAlign = channelCount * (bitsPerSample / 8)

    var data = Data()
    data.append(contentsOf: "RIFF".utf8)
    data.appendFailedRetryInterlockLittleEndian(UInt32(36) + dataByteCount)
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    data.appendFailedRetryInterlockLittleEndian(UInt32(16))
    data.appendFailedRetryInterlockLittleEndian(UInt16(1))
    data.appendFailedRetryInterlockLittleEndian(channelCount)
    data.appendFailedRetryInterlockLittleEndian(sampleRate)
    data.appendFailedRetryInterlockLittleEndian(byteRate)
    data.appendFailedRetryInterlockLittleEndian(blockAlign)
    data.appendFailedRetryInterlockLittleEndian(bitsPerSample)
    data.append(contentsOf: "data".utf8)
    data.appendFailedRetryInterlockLittleEndian(dataByteCount)
    data.append(Data(repeating: 0, count: Int(dataByteCount)))
    return data
}

private extension Data {
    mutating func appendFailedRetryInterlockLittleEndian<
        Value: FixedWidthInteger
    >(_ value: Value) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) {
            append(contentsOf: $0)
        }
    }
}
