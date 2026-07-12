import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSFailedHistoryRetryAcceptanceStoreTests {
    @Test func frozenSlotProofAllowsOnlyMissingOrWhollyUnrelatedSlots()
        async throws {
        let fixture = try RetryAcceptanceStoreFixture(namespace: "freeze")
        let row = try failedHistoryTestEntry(index: 40)
        try fixture.install(row: row, revision: 4)
        let dispatched = try await fixture.reserveAndDispatch(row: row)
        let preparation = try fixture.deliveryPreparation(
            for: dispatched.dispatch
        )

        try await fixture.gate.perform { lease in
            let missing = try await fixture.deliveryStore
                .freezeFailedRetrySlot(
                    preparation: preparation,
                    dispatchReceipt: dispatched.dispatch,
                    operationLeaseAuthorization: lease
                )
            #expect(missing.frozenSlot == .missing)
            #expect(
                try await fixture.deliveryStore
                    .releaseFailedRetryFrozenSlotReservation(
                        missing,
                        dispatchReceipt: dispatched.dispatch,
                        operationLeaseAuthorization: lease
                    )
            )

            let unrelated = try fixture.deliveryRecord(index: 401)
            fixture.deliveryJournal.install(unrelated)
            let existing = try await fixture.deliveryStore
                .freezeFailedRetrySlot(
                    preparation: preparation,
                    dispatchReceipt: dispatched.dispatch,
                    operationLeaseAuthorization: lease
                )
            guard case .existing(let snapshot) = existing.frozenSlot else {
                Issue.record("Expected the wholly unrelated slot to be frozen")
                return
            }
            #expect(snapshot.record == unrelated)
            #expect(
                try await fixture.deliveryStore
                    .releaseFailedRetryFrozenSlotReservation(
                        existing,
                        dispatchReceipt: dispatched.dispatch,
                        operationLeaseAuthorization: lease
                    )
            )

            fixture.deliveryJournal.install(
                try fixture.deliveryRecord(
                    index: 402,
                    deliveryID: preparation.deliveryID
                )
            )
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.identityCollision
            ) {
                _ = try await fixture.deliveryStore.freezeFailedRetrySlot(
                    preparation: preparation,
                    dispatchReceipt: dispatched.dispatch,
                    operationLeaseAuthorization: lease
                )
            }
        }
    }

    @Test func acceptingOutputPreservesExactRowAndRetainsDeliveryRelation()
        async throws {
        let fixture = try RetryAcceptanceStoreFixture(namespace: "accepting")
        let row = try failedHistoryTestEntry(
            index: 41,
            failureCategory: .rateLimited,
            pipelineStage: .translation,
            retryCount: 3,
            outputIntent: .translate
        )
        try fixture.install(row: row, revision: 9)
        let dispatched = try await fixture.reserveAndDispatch(row: row)
        let completion = try await retryAcceptanceProviderCompletionClaim(
            state: fixture.failedStore.retryLiveOwnerState,
            registration: dispatched.registration
        )
        let preparation = try fixture.deliveryPreparation(
            for: dispatched.dispatch,
            acceptedText: "Exact accepted bytes"
        )

        let receipt = try await fixture.gate.perform { lease in
            let proof = try await fixture.deliveryStore.freezeFailedRetrySlot(
                preparation: preparation,
                dispatchReceipt: dispatched.dispatch,
                operationLeaseAuthorization: lease
            )
            let prepared = try await fixture.failedStore
                .prepareRetryAcceptingOutput(
                    using: dispatched.dispatch,
                    providerCompletionClaim: completion,
                    frozenSlotProof: proof,
                    operationLeaseAuthorization: lease
                )
            let authorization = try retryAcceptingOutputAuthorization(prepared)
            expectRetryRowPreserved(
                source: dispatched.dispatch.row,
                target: authorization.acceptingRow
            )
            #expect(
                authorization.providerDispatchedOperation.state
                    == .providerDispatched
            )
            #expect(authorization.acceptingOperation.state == .acceptingOutput)

            let receipt = try await fixture.failedStore
                .commitRetryAcceptingOutput(using: authorization)
            expectRetryRowPreserved(
                source: dispatched.dispatch.row,
                target: receipt.row
            )
            #expect(receipt.retryOperation.state == .acceptingOutput)
            #expect(fixture.mutationInterlock.hasRetryDeliveryRelation)
            #expect(
                fixture.mutationInterlock.permitsRetryDeliveryRelation(
                    receipt.relationKey,
                    freezeReservation: receipt.frozenSlotProof
                        .freezeReservation,
                    operationLeaseAuthorization: lease
                )
            )
            let forgedReservation =
                IOSFailedHistoryRetryDeliveryFreezeReservation(
                    reservationID:
                        IOSFailedHistoryRetryDeliveryFreezeReservationID(),
                    relationKey: receipt.relationKey,
                    operationLeaseAuthorization: lease
                )
            #expect(
                !fixture.mutationInterlock.permitsRetryDeliveryRelation(
                    receipt.relationKey,
                    freezeReservation: forgedReservation,
                    operationLeaseAuthorization: lease
                )
            )
            #expect(
                fixture.mutationInterlock.refreshRetryDeliveryFreeze(
                    forgedReservation,
                    operationLeaseAuthorization: lease
                ) == nil
            )

            let accepted = try await fixture.deliveryStore.acceptFailedRetry(
                preparation,
                acceptingOutputReceipt: receipt,
                operationLeaseAuthorization: lease
            )
            #expect(accepted.record.deliveryID == preparation.deliveryID)
            #expect(accepted.record.sessionID == preparation.sessionID)
            #expect(accepted.record.attemptID == preparation.attemptID)
            #expect(accepted.record.transcriptID == preparation.transcriptID)
            #expect(accepted.record.acceptedText == preparation.acceptedText)
            #expect(accepted.provenance == .failedRetry(receipt.relationKey))
            return receipt
        }

        let durable = try #require(try await fixture.failedStore.load())
        #expect(durable.entries == [receipt.row])
        #expect(receipt.row.updatedAt == dispatched.dispatch.row.updatedAt)
        #expect(fixture.mutationInterlock.hasRetryDeliveryRelation)
    }

    @Test func terminalDeliveryMovesRowToTombstoneWithoutDeletingAudio()
        async throws {
        let fixture = try RetryAcceptanceStoreFixture(namespace: "success")
        let row = try failedHistoryTestEntry(
            index: 42,
            retryCount: 5,
            outputIntent: .translate,
            byteCount: 8_192
        )
        try fixture.install(row: row, revision: 20)
        let dispatched = try await fixture.reserveAndDispatch(row: row)
        let audioURL = try fixture.installAudio(for: dispatched.dispatch.row)
        let completion = try await retryAcceptanceProviderCompletionClaim(
            state: fixture.failedStore.retryLiveOwnerState,
            registration: dispatched.registration
        )
        let preparation = try fixture.deliveryPreparation(
            for: dispatched.dispatch,
            acceptedText: "Delivered retry text"
        )

        let success = try await fixture.gate.perform { lease in
            let frozenProof = try await fixture.deliveryStore
                .freezeFailedRetrySlot(
                    preparation: preparation,
                    dispatchReceipt: dispatched.dispatch,
                    operationLeaseAuthorization: lease
                )
            let acceptingPreparation = try await fixture.failedStore
                .prepareRetryAcceptingOutput(
                    using: dispatched.dispatch,
                    providerCompletionClaim: completion,
                    frozenSlotProof: frozenProof,
                    operationLeaseAuthorization: lease
                )
            let acceptingAuthorization = try retryAcceptingOutputAuthorization(
                acceptingPreparation
            )
            let acceptingReceipt = try await fixture.failedStore
                .commitRetryAcceptingOutput(using: acceptingAuthorization)
            let deliveryPermit = try await fixture.deliveryStore
                .authorizeFailedRetryDeliveryPermit(
                    acceptingOutputReceipt: acceptingReceipt,
                    operationLeaseAuthorization: lease
                )
            let acceptance = try await fixture.deliveryStore.acceptFailedRetry(
                preparation,
                acceptingOutputReceipt: acceptingReceipt,
                operationLeaseAuthorization: lease
            )
            fixture.deliveryJournal.install(
                try fixture.terminalRecord(from: acceptance.record)
            )
            let terminalProof = try await fixture.deliveryStore
                .confirmFailedRetryTerminalDelivery(
                    acceptingOutputReceipt: acceptingReceipt,
                    operationLeaseAuthorization: lease
                )
            let successPreparation = try await fixture.failedStore
                .prepareRetrySuccess(
                    using: acceptingReceipt,
                    terminalDeliveryProof: terminalProof,
                    operationLeaseAuthorization: lease
                )
            let successAuthorization = try retrySuccessAuthorization(
                successPreparation
            )
            let successReceipt = try await fixture.failedStore
                .commitRetrySuccess(using: successAuthorization)

            #expect(
                await fixture.failedStore.retryLiveOwnerState
                    .consumeProviderSuccess(using: successReceipt)
            )
            #expect(!deliveryPermit.provesActiveRelation())
            expectRedactedCapability(frozenProof)
            expectRedactedCapability(frozenProof.frozenSlot)
            expectRedactedCapability(frozenProof.freezeReservation)
            expectRedactedCapability(
                frozenProof.freezeReservation.reservationID
            )
            expectRedactedCapability(acceptingPreparation)
            expectRedactedCapability(acceptingAuthorization)
            expectRedactedCapability(acceptingReceipt)
            expectRedactedCapability(acceptingReceipt.relationKey)
            expectRedactedCapability(deliveryPermit)
            expectRedactedCapability(terminalProof)
            expectRedactedCapability(successPreparation)
            expectRedactedCapability(successAuthorization)
            expectRedactedCapability(successReceipt)
            return successReceipt
        }

        let durable = try #require(try await fixture.failedStore.load())
        #expect(durable.entries.isEmpty)
        #expect(durable.audioCleanup == [success.tombstone])
        #expect(success.tombstone.attemptID == dispatched.dispatch.row.attemptID)
        #expect(
            success.tombstone.audioRelativeIdentifier
                == dispatched.dispatch.row.audioRelativeIdentifier
        )
        #expect(success.tombstone.byteCount == dispatched.dispatch.row.byteCount)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(!fixture.mutationInterlock.isBlocked)
        #expect(!fixture.mutationInterlock.hasRetryDeliveryRelation)
        #expect(
            await fixture.failedStore.retryLiveOwnerState.hasLiveOwner() == false
        )

        requireFailedHistorySendable(
            IOSAcceptedOutputDeliveryFrozenSlotProof.self
        )
        requireFailedHistorySendable(
            IOSFailedHistoryRetryDeliveryFreezeReservation.self
        )
        requireFailedHistorySendable(
            IOSFailedHistoryRetryDeliveryFreezeReservationID.self
        )
        requireFailedHistorySendable(
            IOSFailedHistoryRetryAcceptingOutputPreparation.self
        )
        requireFailedHistorySendable(
            IOSFailedHistoryRetryAcceptingOutputAuthorization.self
        )
        requireFailedHistorySendable(
            IOSFailedHistoryRetryAcceptingOutputReceipt.self
        )
        requireFailedHistorySendable(
            IOSFailedHistoryRetryTerminalDeliveryProof.self
        )
        requireFailedHistorySendable(
            IOSFailedHistoryRetrySuccessPreparation.self
        )
        requireFailedHistorySendable(
            IOSFailedHistoryRetrySuccessAuthorization.self
        )
        requireFailedHistorySendable(
            IOSFailedHistoryRetrySuccessReceipt.self
        )
    }

    @Test func createConflictCannotAdoptAnUntaggedExactRecord()
        async throws {
        let fixture = try RetryAcceptanceStoreFixture(
            namespace: "untagged-create-race"
        )
        let row = try failedHistoryTestEntry(index: 421)
        try fixture.install(row: row, revision: 21)
        let dispatched = try await fixture.reserveAndDispatch(row: row)
        let completion = try await retryAcceptanceProviderCompletionClaim(
            state: fixture.failedStore.retryLiveOwnerState,
            registration: dispatched.registration
        )
        let preparation = try fixture.deliveryPreparation(
            for: dispatched.dispatch,
            acceptedText: "Race-identical accepted bytes"
        )

        try await fixture.gate.perform { lease in
            let proof = try await fixture.deliveryStore
                .freezeFailedRetrySlot(
                    preparation: preparation,
                    dispatchReceipt: dispatched.dispatch,
                    operationLeaseAuthorization: lease
                )
            let accepting = try retryAcceptingOutputAuthorization(
                try await fixture.failedStore.prepareRetryAcceptingOutput(
                    using: dispatched.dispatch,
                    providerCompletionClaim: completion,
                    frozenSlotProof: proof,
                    operationLeaseAuthorization: lease
                )
            )
            let receipt = try await fixture.failedStore
                .commitRetryAcceptingOutput(using: accepting)
            fixture.deliveryJournal.raceNextCreate(
                with: try fixture.untaggedRecord(for: preparation)
            )

            await #expect(
                throws: IOSAcceptedOutputDeliveryError.identityCollision
            ) {
                _ = try await fixture.deliveryStore.acceptFailedRetry(
                    preparation,
                    acceptingOutputReceipt: receipt,
                    operationLeaseAuthorization: lease
                )
            }
            #expect(
                try fixture.deliveryJournal.load()?.record.failedRetryID
                    == nil
            )
            #expect(fixture.mutationInterlock.hasRetryDeliveryRelation)
        }
    }

    @Test func activeRetryRelationCompletesHistoryAndSuccessAfterExpiry()
        async throws {
        let fixture = try RetryAcceptanceStoreFixture(
            namespace: "protected-expiry"
        )
        let row = try failedHistoryTestEntry(index: 422)
        try fixture.install(row: row, revision: 22)
        let dispatched = try await fixture.reserveAndDispatch(row: row)
        let completion = try await retryAcceptanceProviderCompletionClaim(
            state: fixture.failedStore.retryLiveOwnerState,
            registration: dispatched.registration
        )
        let operation = dispatched.dispatch.retryOperation
        let policyReceipt = dispatched.dispatch.authorization
            .reservationReceipt.authorization.policyReceipt
        let marker = try IOSAcceptedOutputHistoryWrite(
            policyGeneration: dispatched.dispatch.row.policyGeneration,
            transcriptionModel: dispatched.dispatch.row.transcriptionModel,
            transcriptionLanguageCode:
                dispatched.dispatch.row.transcriptionLanguageCode,
            durationMilliseconds:
                dispatched.dispatch.row.durationMilliseconds
        )
        let preparation = try IOSAcceptedOutputDeliveryPreparation(
            deliveryID: operation.deliveryID,
            sessionID: operation.sessionID,
            attemptID: dispatched.dispatch.row.attemptID,
            transcriptID: operation.transcriptID,
            rawAcceptedText: "Expiry-protected accepted bytes",
            outputIntent: dispatched.dispatch.row.outputIntent,
            automaticInsertionPreferenceEnabled: false,
            keepLatestResult: true,
            historyCapture: IOSAcceptedOutputHistoryCapture(
                policyReceipt: policyReceipt,
                ownerIdentity: fixture.ownerIdentity,
                historyWrite: marker
            )
        )

        try await fixture.gate.perform { lease in
            let proof = try await fixture.deliveryStore
                .freezeFailedRetrySlot(
                    preparation: preparation,
                    dispatchReceipt: dispatched.dispatch,
                    operationLeaseAuthorization: lease
                )
            let accepting = try retryAcceptingOutputAuthorization(
                try await fixture.failedStore.prepareRetryAcceptingOutput(
                    using: dispatched.dispatch,
                    providerCompletionClaim: completion,
                    frozenSlotProof: proof,
                    operationLeaseAuthorization: lease
                )
            )
            let receipt = try await fixture.failedStore
                .commitRetryAcceptingOutput(using: accepting)
            let permit = try await fixture.deliveryStore
                .authorizeFailedRetryDeliveryPermit(
                    acceptingOutputReceipt: receipt,
                    operationLeaseAuthorization: lease
                )
            let acceptance = try await fixture.deliveryStore
                .acceptFailedRetry(
                    preparation,
                    acceptingOutputReceipt: receipt,
                    operationLeaseAuthorization: lease
                )

            fixture.clock.advance(by: 86_401)
            let deliveryAuthorization = try await fixture.deliveryStore
                .authorizePendingHistoryWrite(
                    expected: IOSAcceptedOutputDeliveryExpectation(
                        record: acceptance.record
                    ),
                    operationLeaseAuthorization: lease,
                    failedRetryPermit: permit
                )
            let rowReceipt = try await fixture.acceptedHistoryStore
                .decideFailedRetryReplay(
                    delivery: deliveryAuthorization,
                    policy: policyReceipt,
                    deliveryPermit: permit
                )
            let terminal = try await fixture.deliveryStore
                .commitHistoryWrite(
                    authorization: deliveryAuthorization,
                    rowReceipt: rowReceipt,
                    operationLeaseAuthorization: lease,
                    failedRetryPermit: permit
                )
            #expect(terminal.updatedAt == terminal.expiresAt)

            let replay = try await fixture.deliveryStore.acceptFailedRetry(
                preparation,
                acceptingOutputReceipt: receipt,
                operationLeaseAuthorization: lease
            )
            #expect(replay.record.historyWrite?.state == .committed)
            let terminalProof = try await fixture.deliveryStore
                .confirmFailedRetryTerminalDelivery(
                    acceptingOutputReceipt: receipt,
                    operationLeaseAuthorization: lease
                )
            let success = try retrySuccessAuthorization(
                try await fixture.failedStore.prepareRetrySuccess(
                    using: receipt,
                    terminalDeliveryProof: terminalProof,
                    operationLeaseAuthorization: lease
                )
            )
            _ = try await fixture.failedStore.commitRetrySuccess(
                using: success
            )
            #expect(!fixture.mutationInterlock.hasRetryDeliveryProtection)
        }
    }

    @Test func acceptingOutputCommitUncertaintyReconcilesInvisibleAndVisible()
        async throws {
        for outcomeVisible in [false, true] {
            let fixture = try RetryAcceptanceStoreFixture(
                namespace: outcomeVisible
                    ? "accepting-visible"
                    : "accepting-invisible"
            )
            let row = try failedHistoryTestEntry(
                index: outcomeVisible ? 44 : 43,
                retryCount: 7
            )
            try fixture.install(row: row, revision: 30)
            let dispatched = try await fixture.reserveAndDispatch(row: row)
            let completion = try await retryAcceptanceProviderCompletionClaim(
                state: fixture.failedStore.retryLiveOwnerState,
                registration: dispatched.registration
            )
            let deliveryPreparation = try fixture.deliveryPreparation(
                for: dispatched.dispatch
            )

            let receipt = try await fixture.gate.perform { lease in
                let proof = try await fixture.deliveryStore
                    .freezeFailedRetrySlot(
                        preparation: deliveryPreparation,
                        dispatchReceipt: dispatched.dispatch,
                        operationLeaseAuthorization: lease
                    )
                let firstPreparation = try await fixture.failedStore
                    .prepareRetryAcceptingOutput(
                        using: dispatched.dispatch,
                        providerCompletionClaim: completion,
                        frozenSlotProof: proof,
                        operationLeaseAuthorization: lease
                    )
                let first = try retryAcceptingOutputAuthorization(
                    firstPreparation
                )
                fixture.failedFileSystem.replaceFailure = .init(
                    error: .commitUncertain,
                    commitBeforeThrowing: outcomeVisible
                )

                await #expect(throws: IOSFailedHistoryError.commitUncertain) {
                    _ = try await fixture.failedStore
                        .commitRetryAcceptingOutput(using: first)
                }
                #expect(fixture.mutationInterlock.isBlocked)
                #expect(fixture.mutationInterlock.hasRetryDeliveryRelation)

                let retried = try await fixture.failedStore
                    .prepareRetryAcceptingOutput(
                        using: dispatched.dispatch,
                        providerCompletionClaim: completion,
                        frozenSlotProof: proof,
                        operationLeaseAuthorization: lease
                    )
                let receipt: IOSFailedHistoryRetryAcceptingOutputReceipt
                switch retried {
                case .commit(let refreshed):
                    #expect(!outcomeVisible)
                    #expect(refreshed.outcome == first.outcome)
                    #expect(refreshed.acceptingRow == first.acceptingRow)
                    receipt = try await fixture.failedStore
                        .commitRetryAcceptingOutput(using: refreshed)
                case .completed(let completed):
                    #expect(outcomeVisible)
                    #expect(completed.authorization.outcome == first.outcome)
                    #expect(completed.row == first.acceptingRow)
                    receipt = completed
                }
                expectRetryRowPreserved(
                    source: dispatched.dispatch.row,
                    target: receipt.row
                )
                #expect(receipt.row.updatedAt == dispatched.dispatch.row.updatedAt)
                #expect(
                    fixture.mutationInterlock.permitsRetryDeliveryRelation(
                        receipt.relationKey,
                        freezeReservation: receipt.frozenSlotProof
                            .freezeReservation,
                        operationLeaseAuthorization: lease
                    )
                )
                _ = try await fixture.deliveryStore.acceptFailedRetry(
                    deliveryPreparation,
                    acceptingOutputReceipt: receipt,
                    operationLeaseAuthorization: lease
                )
                return receipt
            }

            let durable = try #require(try await fixture.failedStore.load())
            #expect(durable.entries == [receipt.row])
            #expect(receipt.retryOperation.state == .acceptingOutput)
        }
    }

    @Test func successCommitUncertaintyReconcilesInvisibleAndVisible()
        async throws {
        for outcomeVisible in [false, true] {
            let fixture = try RetryAcceptanceStoreFixture(
                namespace: outcomeVisible
                    ? "success-visible"
                    : "success-invisible"
            )
            let row = try failedHistoryTestEntry(
                index: outcomeVisible ? 46 : 45,
                retryCount: 9,
                byteCount: 16_384
            )
            try fixture.install(row: row, revision: 40)
            let dispatched = try await fixture.reserveAndDispatch(row: row)
            let audioURL = try fixture.installAudio(for: dispatched.dispatch.row)
            let completion = try await retryAcceptanceProviderCompletionClaim(
                state: fixture.failedStore.retryLiveOwnerState,
                registration: dispatched.registration
            )
            let deliveryPreparation = try fixture.deliveryPreparation(
                for: dispatched.dispatch,
                acceptedText: "Uncertain success bytes"
            )

            let receipt = try await fixture.gate.perform { lease in
                let frozenProof = try await fixture.deliveryStore
                    .freezeFailedRetrySlot(
                        preparation: deliveryPreparation,
                        dispatchReceipt: dispatched.dispatch,
                        operationLeaseAuthorization: lease
                    )
                let accepting = try retryAcceptingOutputAuthorization(
                    try await fixture.failedStore.prepareRetryAcceptingOutput(
                        using: dispatched.dispatch,
                        providerCompletionClaim: completion,
                        frozenSlotProof: frozenProof,
                        operationLeaseAuthorization: lease
                    )
                )
                let acceptingReceipt = try await fixture.failedStore
                    .commitRetryAcceptingOutput(using: accepting)
                let acceptance = try await fixture.deliveryStore
                    .acceptFailedRetry(
                        deliveryPreparation,
                        acceptingOutputReceipt: acceptingReceipt,
                        operationLeaseAuthorization: lease
                    )
                fixture.deliveryJournal.install(
                    try fixture.terminalRecord(from: acceptance.record)
                )
                let terminalProof = try await fixture.deliveryStore
                    .confirmFailedRetryTerminalDelivery(
                        acceptingOutputReceipt: acceptingReceipt,
                        operationLeaseAuthorization: lease
                    )
                let firstPreparation = try await fixture.failedStore
                    .prepareRetrySuccess(
                        using: acceptingReceipt,
                        terminalDeliveryProof: terminalProof,
                        operationLeaseAuthorization: lease
                    )
                let first = try retrySuccessAuthorization(firstPreparation)
                fixture.failedFileSystem.replaceFailure = .init(
                    error: .commitUncertain,
                    commitBeforeThrowing: outcomeVisible
                )

                await #expect(throws: IOSFailedHistoryError.commitUncertain) {
                    _ = try await fixture.failedStore
                        .commitRetrySuccess(using: first)
                }
                #expect(fixture.mutationInterlock.isBlocked)
                #expect(fixture.mutationInterlock.hasRetryDeliveryRelation)
                #expect(FileManager.default.fileExists(atPath: audioURL.path))

                let retried = try await fixture.failedStore.prepareRetrySuccess(
                    using: acceptingReceipt,
                    terminalDeliveryProof: terminalProof,
                    operationLeaseAuthorization: lease
                )
                let receipt: IOSFailedHistoryRetrySuccessReceipt
                switch retried {
                case .commit(let refreshed):
                    #expect(!outcomeVisible)
                    #expect(refreshed.outcome == first.outcome)
                    #expect(refreshed.tombstone == first.tombstone)
                    receipt = try await fixture.failedStore
                        .commitRetrySuccess(using: refreshed)
                case .completed(let completed):
                    #expect(outcomeVisible)
                    #expect(completed.authorization.outcome == first.outcome)
                    #expect(completed.tombstone == first.tombstone)
                    receipt = completed
                }
                #expect(
                    await fixture.failedStore.retryLiveOwnerState
                        .consumeProviderSuccess(using: receipt)
                )
                return receipt
            }

            let durable = try #require(try await fixture.failedStore.load())
            #expect(durable.entries.isEmpty)
            #expect(durable.audioCleanup == [receipt.tombstone])
            #expect(FileManager.default.fileExists(atPath: audioURL.path))
            #expect(!fixture.mutationInterlock.isBlocked)
            #expect(!fixture.mutationInterlock.hasRetryDeliveryRelation)
        }
    }
}

private func retryAcceptingOutputAuthorization(
    _ preparation: IOSFailedHistoryRetryAcceptingOutputPreparation
) throws -> IOSFailedHistoryRetryAcceptingOutputAuthorization {
    guard case .commit(let authorization) = preparation else {
        throw IOSFailedHistoryError.invalidTransition
    }
    return authorization
}

private func retrySuccessAuthorization(
    _ preparation: IOSFailedHistoryRetrySuccessPreparation
) throws -> IOSFailedHistoryRetrySuccessAuthorization {
    guard case .commit(let authorization) = preparation else {
        throw IOSFailedHistoryError.invalidTransition
    }
    return authorization
}

private func retryAcceptanceReservationAuthorization(
    _ preparation: IOSFailedHistoryRetryReservationPreparation
) throws -> IOSFailedHistoryRetryReservationAuthorization {
    guard case .commit(let authorization) = preparation else {
        throw IOSFailedHistoryError.invalidTransition
    }
    return authorization
}

private func retryAcceptanceDispatchAuthorization(
    _ preparation: IOSFailedHistoryRetryDispatchPreparation
) throws -> IOSFailedHistoryRetryDispatchAuthorization {
    guard case .commit(let authorization) = preparation else {
        throw IOSFailedHistoryError.invalidTransition
    }
    return authorization
}

private func retryAcceptanceProviderCompletionClaim(
    state: IOSFailedHistoryRetryLiveOwnerState,
    registration: IOSFailedHistoryRetryProviderRegistration
) async throws -> IOSFailedHistoryRetryProviderCompletionClaim {
    let launch = try #require(await state.claimProviderLaunch(registration))
    #expect(launch.installRunningCancellation {})
    #expect(launch.launch())
    let terminal = try #require(await state.claimProviderCompletion(launch))
    guard case .completion(let completion) = terminal else {
        throw IOSFailedHistoryError.invalidTransition
    }
    #expect(await state.retainedProviderCompletion(registration) == completion)
    return completion
}

private func expectRetryRowPreserved(
    source: IOSFailedHistoryEntry,
    target: IOSFailedHistoryEntry
) {
    #expect(target.attemptID == source.attemptID)
    #expect(target.createdAt == source.createdAt)
    #expect(target.updatedAt == source.updatedAt)
    #expect(target.policyGeneration == source.policyGeneration)
    #expect(target.failureCategory == source.failureCategory)
    #expect(target.pipelineStage == source.pipelineStage)
    #expect(target.retryCount == source.retryCount)
    #expect(target.outputIntent == source.outputIntent)
    #expect(target.transcriptionModel == source.transcriptionModel)
    #expect(
        target.transcriptionLanguageCode == source.transcriptionLanguageCode
    )
    #expect(target.durationMilliseconds == source.durationMilliseconds)
    #expect(target.byteCount == source.byteCount)
    #expect(
        target.audioRelativeIdentifier == source.audioRelativeIdentifier
    )
    #expect(target.ownershipState == source.ownershipState)
    #expect(target.retryOperation?.retryID == source.retryOperation?.retryID)
    #expect(
        target.retryOperation?.transcriptionID
            == source.retryOperation?.transcriptionID
    )
    #expect(
        target.retryOperation?.deliveryID == source.retryOperation?.deliveryID
    )
    #expect(target.retryOperation?.sessionID == source.retryOperation?.sessionID)
    #expect(
        target.retryOperation?.transcriptID
            == source.retryOperation?.transcriptID
    )
    #expect(target.retryOperation?.createdAt == source.retryOperation?.createdAt)
}

private func expectRedactedCapability<Value>(_ value: Value) {
    #expect(String(describing: value).contains("redacted"))
    #expect(Mirror(reflecting: value).children.isEmpty)
}

private final class RetryAcceptanceStoreFixture: @unchecked Sendable {
    let clock: RetryAcceptanceClock
    let gate: IOSPersistenceOperationGate
    let ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    let pendingStoreIdentity = IOSPendingRecordingStoreIdentity()
    let mutationInterlock = IOSFailedHistoryMutationInterlock()
    let failedFileSystem = FailedHistoryFakeFileSystem()
    let deliveryJournal = RetryAcceptanceDeliveryJournal()
    let failedStore: IOSFailedHistoryStore
    let deliveryStore: IOSAcceptedOutputDeliveryStore
    let acceptedHistoryStore: IOSAcceptedHistoryStore
    private let rootURL: URL

    init(namespace: String) throws {
        clock = RetryAcceptanceClock(
            try failedHistoryTestDate(offsetMilliseconds: 25_000)
        )
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "failed-retry-acceptance-\(namespace)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: false
        )
        let context = IOSAcceptedHistoryCoordinatorProcessContextRegistry.shared
            .context(for: rootURL)
        gate = context.operationGate
        ownerIdentity = context.ownerIdentity
        failedStore = IOSFailedHistoryStore(
            journal: FoundationIOSFailedHistoryJournalRepository(
                fileSystem: failedFileSystem
            ),
            capabilityOwnerIdentity: ownerIdentity,
            operationGateIdentity: gate.identity,
            expectedPendingStoreIdentity: pendingStoreIdentity,
            repositoryGuard: context.repositoryGuard,
            mutationInterlock: mutationInterlock,
            now: { [clock] in clock.value() }
        )
        deliveryStore = IOSAcceptedOutputDeliveryStore(
            journal: deliveryJournal,
            now: { [clock] in clock.value() },
            monotonicNowNanoseconds: { 1_000_000 },
            capabilityOwnerIdentity: ownerIdentity,
            operationGateIdentity: gate.identity,
            failedHistoryMutationInterlock: mutationInterlock
        )
        acceptedHistoryStore = IOSAcceptedHistoryStore(
            journal: RetryAcceptanceAcceptedHistoryJournal(),
            now: { [clock] in clock.value() },
            capabilityOwnerIdentity: ownerIdentity
        )
        guard let physicalRootIdentity = context.repositoryBinding
                .physicalRootIdentity,
              failedStore.retryLiveOwnerState.bindProviderRegistration(
                  failedStoreIdentity: failedStore.storeIdentity,
                  ownerIdentity: ownerIdentity,
                  physicalRootIdentity: physicalRootIdentity
              ) else {
            throw IOSFailedHistoryError.repositoryIdentityConflict
        }
    }

    deinit { try? FileManager.default.removeItem(at: rootURL) }

    func install(
        row: IOSFailedHistoryEntry,
        revision: Int64,
        cleanup: [IOSFailedHistoryAudioCleanup] = []
    ) throws {
        failedFileSystem.install(
            try IOSFailedHistoryWireCodec.encode(
                IOSFailedHistoryEnvelope(
                    revision: revision,
                    entries: [row],
                    audioCleanup: cleanup
                )
            )
        )
        failedFileSystem.resetEvents()
    }

    func reserveAndDispatch(
        row: IOSFailedHistoryEntry
    ) async throws -> (
        dispatch: IOSFailedHistoryRetryDispatchReceipt,
        registration: IOSFailedHistoryRetryProviderRegistration
    ) {
        let policy = try await policyReceipt()
        return try await gate.perform { lease in
            let reservation = try retryAcceptanceReservationAuthorization(
                try await self.failedStore.prepareRetryReservation(
                    attemptID: row.attemptID,
                    transcriptionConfiguration: TranscriptionConfiguration(
                        model: "retry-acceptance-model",
                        language: .german
                    ),
                    using: policy,
                    operationLeaseAuthorization: lease
                )
            )
            let reservationReceipt = try await self.failedStore
                .commitRetryReservation(
                    using: reservation,
                    validatedAudio: try #require(
                        IOSFailedHistoryRetryAudioValidationReceipt(
                            testingAuthorization: reservation
                        )
                    )
                )
            let dispatch = try retryAcceptanceDispatchAuthorization(
                try await self.failedStore.prepareRetryDispatch(
                    using: reservationReceipt,
                    operationLeaseAuthorization: lease
                )
            )
            let dispatchReceipt = try await self.failedStore
                .commitRetryDispatch(using: dispatch)
            let registration = try #require(
                await self.failedStore.retryLiveOwnerState.registerLiveOwner(
                    dispatchReceipt.liveOwnerToken
                )
            )
            return (dispatchReceipt, registration)
        }
    }

    func deliveryPreparation(
        for dispatch: IOSFailedHistoryRetryDispatchReceipt,
        acceptedText: String = "Retry accepted text"
    ) throws -> IOSAcceptedOutputDeliveryPreparation {
        try IOSAcceptedOutputDeliveryPreparation(
            deliveryID: dispatch.retryOperation.deliveryID,
            sessionID: dispatch.retryOperation.sessionID,
            attemptID: dispatch.row.attemptID,
            transcriptID: dispatch.retryOperation.transcriptID,
            rawAcceptedText: acceptedText,
            outputIntent: dispatch.row.outputIntent,
            automaticInsertionPreferenceEnabled: false,
            keepLatestResult: true,
            historyWrite: try IOSAcceptedOutputHistoryWrite(
                policyGeneration: dispatch.row.policyGeneration,
                transcriptionModel: dispatch.row.transcriptionModel,
                transcriptionLanguageCode:
                    dispatch.row.transcriptionLanguageCode,
                durationMilliseconds: dispatch.row.durationMilliseconds
            )
        )
    }

    func deliveryRecord(
        index: Int,
        deliveryID: UUID? = nil
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        let createdAt = try failedHistoryTestDate(
            offsetMilliseconds: Int64(100_000 + index)
        )
        let expiresAt = try failedHistoryTestDate(
            offsetMilliseconds: Int64(86_500_000 + index)
        )
        return try IOSAcceptedOutputDeliveryRecord(
            revision: 1,
            deliveryID: deliveryID
                ?? failedHistoryTestUUID(namespace: 0x70, index: index),
            sessionID: failedHistoryTestUUID(namespace: 0x71, index: index),
            attemptID: failedHistoryTestUUID(namespace: 0x72, index: index),
            transcriptID: failedHistoryTestUUID(namespace: 0x73, index: index),
            acceptedText: "Existing delivery \(index)",
            outputIntent: .standard,
            createdAt: createdAt,
            updatedAt: createdAt,
            expiresAt: expiresAt,
            deliveryState: .pending,
            automaticInsertionPreferenceEnabled: false,
            keepLatestResult: true,
            publicationGeneration: 0,
            historyWrite: nil
        )
    }

    func terminalRecord(
        from accepted: IOSAcceptedOutputDeliveryRecord
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        try IOSAcceptedOutputDeliveryRecord(
            revision: accepted.revision + 1,
            deliveryID: accepted.deliveryID,
            sessionID: accepted.sessionID,
            attemptID: accepted.attemptID,
            transcriptID: accepted.transcriptID,
            failedRetryID: accepted.failedRetryID,
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

    func untaggedRecord(
        for preparation: IOSAcceptedOutputDeliveryPreparation
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        let createdAt = clock.value()
        return try IOSAcceptedOutputDeliveryRecord(
            revision: 1,
            deliveryID: preparation.deliveryID,
            sessionID: preparation.sessionID,
            attemptID: preparation.attemptID,
            transcriptID: preparation.transcriptID,
            acceptedText: preparation.acceptedText,
            outputIntent: preparation.outputIntent,
            createdAt: createdAt,
            updatedAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(86_400),
            deliveryState: .pending,
            automaticInsertionPreferenceEnabled:
                preparation.automaticInsertionPreferenceEnabled,
            keepLatestResult: preparation.keepLatestResult,
            publicationGeneration: 0,
            historyWrite: preparation.historyWrite
        )
    }

    func installAudio(for row: IOSFailedHistoryEntry) throws -> URL {
        let url = rootURL.appendingPathComponent(row.audioRelativeIdentifier)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x5a, count: Int(row.byteCount)).write(to: url)
        return url
    }

    private func policyReceipt() async throws -> IOSHistoryPolicyReceipt {
        let state = try IOSHistoryPolicyState(
            revision: 1,
            historyEnabled: true,
            policyGeneration: 1
        )
        return try await IOSHistoryPolicyStore(
            journal: RetryAcceptancePolicyJournal(state: state),
            capabilityOwnerIdentity: ownerIdentity
        ).confirm(expected: IOSHistoryPolicyExpectation(state: state))
    }
}

private final class RetryAcceptanceClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ current: Date) {
        self.current = current
    }

    func value() -> Date {
        lock.withLock { current }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }
}

private final class RetryAcceptanceAcceptedHistoryJournal:
    IOSAcceptedHistoryJournalStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: IOSAcceptedHistoryJournalSnapshot?
    private var nextToken: UInt64 = 1

    func load() throws -> IOSAcceptedHistoryJournalSnapshot? {
        lock.withLock { snapshot }
    }

    func create(
        _ envelope: IOSAcceptedHistoryEnvelope,
        authorization: IOSAcceptedHistoryJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryJournalSnapshot {
        _ = authorization
        return try lock.withLock {
            guard snapshot == nil else {
                throw IOSAcceptedHistoryError.slotOccupied
            }
            let created = IOSAcceptedHistoryJournalSnapshot(
                envelope: envelope,
                fileRevision: makeRevisionLocked()
            )
            snapshot = created
            return created
        }
    }

    func replace(
        _ envelope: IOSAcceptedHistoryEnvelope,
        expected: IOSAcceptedHistoryJournalSnapshot,
        authorization: IOSAcceptedHistoryJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryJournalSnapshot {
        _ = authorization
        return try lock.withLock {
            guard snapshot?.fileRevision == expected.fileRevision else {
                throw IOSAcceptedHistoryError.compareAndSwapFailed
            }
            let replacement = IOSAcceptedHistoryJournalSnapshot(
                envelope: envelope,
                fileRevision: makeRevisionLocked()
            )
            snapshot = replacement
            return replacement
        }
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        _ = now
        return .empty
    }

    private func makeRevisionLocked()
        -> IOSStrictProtectedRecordFileRevision {
        defer { nextToken += 1 }
        return IOSStrictProtectedRecordFileRevision(testingToken: nextToken)
    }
}

private final class RetryAcceptanceDeliveryJournal:
    IOSAcceptedOutputDeliveryJournalStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: IOSAcceptedOutputDeliveryJournalSnapshot?
    private var nextToken: UInt64 = 1
    private var racedCreateRecord: IOSAcceptedOutputDeliveryRecord?

    func install(_ record: IOSAcceptedOutputDeliveryRecord) {
        lock.withLock {
            snapshot = IOSAcceptedOutputDeliveryJournalSnapshot(
                record: record,
                fileRevision: makeRevisionLocked()
            )
        }
    }

    func raceNextCreate(with record: IOSAcceptedOutputDeliveryRecord) {
        lock.withLock { racedCreateRecord = record }
    }

    func load() throws -> IOSAcceptedOutputDeliveryJournalSnapshot? {
        lock.withLock { snapshot }
    }

    func loadOpaque() throws -> IOSAcceptedOutputDeliveryOpaqueSnapshot? {
        nil
    }

    func create(
        _ record: IOSAcceptedOutputDeliveryRecord
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        try lock.withLock {
            if let racedCreateRecord {
                snapshot = IOSAcceptedOutputDeliveryJournalSnapshot(
                    record: racedCreateRecord,
                    fileRevision: makeRevisionLocked()
                )
                self.racedCreateRecord = nil
                throw IOSAcceptedOutputDeliveryError.slotOccupied
            }
            guard snapshot == nil else {
                throw IOSAcceptedOutputDeliveryError.slotOccupied
            }
            let created = IOSAcceptedOutputDeliveryJournalSnapshot(
                record: record,
                fileRevision: makeRevisionLocked()
            )
            snapshot = created
            return created
        }
    }

    func replace(
        _ record: IOSAcceptedOutputDeliveryRecord,
        expected: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        try lock.withLock {
            guard snapshot?.fileRevision == expected.fileRevision else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            let replacement = IOSAcceptedOutputDeliveryJournalSnapshot(
                record: record,
                fileRevision: makeRevisionLocked()
            )
            snapshot = replacement
            return replacement
        }
    }

    func remove(
        expected: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws {
        try lock.withLock {
            guard snapshot?.fileRevision == expected.fileRevision else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            snapshot = nil
        }
    }

    func removeOpaque(
        expected: IOSAcceptedOutputDeliveryOpaqueSnapshot
    ) throws {
        _ = expected
        throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        _ = now
        return .empty
    }

    private func makeRevisionLocked()
        -> IOSStrictProtectedRecordFileRevision {
        defer { nextToken += 1 }
        return IOSStrictProtectedRecordFileRevision(testingToken: nextToken)
    }
}

private final class RetryAcceptancePolicyJournal:
    IOSHistoryPolicyJournalStoring,
    @unchecked Sendable {
    private var snapshot: IOSHistoryPolicyJournalSnapshot

    init(state: IOSHistoryPolicyState) {
        snapshot = IOSHistoryPolicyJournalSnapshot(
            state: state,
            fileRevision: IOSStrictProtectedRecordFileRevision(testingToken: 1)
        )
    }

    func load() throws -> IOSHistoryPolicyJournalSnapshot? { snapshot }

    func replace(
        _ state: IOSHistoryPolicyState,
        expected: IOSHistoryPolicyJournalSnapshot
    ) throws -> IOSHistoryPolicyJournalSnapshot {
        guard snapshot == expected else {
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }
        snapshot = IOSHistoryPolicyJournalSnapshot(
            state: state,
            fileRevision: IOSStrictProtectedRecordFileRevision(testingToken: 2)
        )
        return snapshot
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        _ = now
        return .empty
    }
}
