import Foundation
import HoldTypeDomain
import Testing
@_spi(HoldTypeIOSCore) @testable import HoldTypePersistence

struct IOSForegroundVoicePersistenceTests {
    @Test func namedPreparationSealsTheAppOnlyPolicyAndRedactsText()
        throws {
        let preparation = try makeForegroundPreparation(
            rawAcceptedText: "  accepted text  "
        )

        #expect(preparation.deliveryPreparation.acceptedText == "accepted text")
        #expect(
            !preparation.deliveryPreparation
                .automaticInsertionPreferenceEnabled
        )
        #expect(preparation.deliveryPreparation.historyWrite == nil)
        #expect(preparation.deliveryPreparation.historyCapture == nil)
        #expect(preparation.historyMode == .appOnly)
        #expect(
            String(describing: preparation)
                == "IOSForegroundVoiceAcceptedOutputPreparation(redacted)"
        )
        #expect(preparation.customMirror.children.isEmpty)
    }

    @Test func capturedPreparationPropagatesEnabledAndDisabledHistoryCaptures()
        async throws {
        let captures = try await makeForegroundHistoryCaptures()
        let enabledMode = IOSForegroundVoiceHistoryMode.captured(
            captures.enabled
        )
        let enabled = try IOSForegroundVoiceAcceptedOutputPreparation(
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: UUID(),
            transcriptID: UUID(),
            rawAcceptedText: "MODE-SECRET-TEXT",
            outputIntent: .standard,
            keepLatestResult: true,
            historyMode: enabledMode
        )
        #expect(enabled.historyMode == enabledMode)
        #expect(enabled.deliveryPreparation.historyCapture == captures.enabled)
        #expect(enabled.deliveryPreparation.historyWrite != nil)
        #expect(
            !enabled.deliveryPreparation
                .automaticInsertionPreferenceEnabled
        )

        let disabledMode = IOSForegroundVoiceHistoryMode.captured(
            captures.disabled
        )
        let disabled = try IOSForegroundVoiceAcceptedOutputPreparation(
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: UUID(),
            transcriptID: UUID(),
            rawAcceptedText: "accepted",
            outputIntent: .translate,
            keepLatestResult: false,
            historyMode: disabledMode
        )
        #expect(disabled.historyMode == disabledMode)
        #expect(
            disabled.deliveryPreparation.historyCapture == captures.disabled
        )
        #expect(disabled.deliveryPreparation.historyWrite == nil)

        func requireSendable<Value: Sendable>(_ value: Value) -> Value {
            value
        }
        #expect(requireSendable(enabledMode) == enabledMode)
        let rendered = String(describing: enabledMode)
            + String(reflecting: enabledMode)
            + String(describing: Mirror(reflecting: enabledMode))
        #expect(rendered.contains("redacted"))
        #expect(!rendered.contains("MODE-SECRET"))
        #expect(enabledMode.customMirror.children.isEmpty)
        let erasedMode: Any = enabledMode
        #expect(!(erasedMode is any Codable))
    }

    @Test func p4FacadeRejectsCapturedPreparationBeforeDurableMutation()
        async throws {
        let capture = try await makeForegroundHistoryCaptures().enabled
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try IOSForegroundVoiceAcceptedOutputPreparation(
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: output.attemptID,
            transcriptID: try #require(output.transcriptionID),
            rawAcceptedText: "captured accepted text",
            outputIntent: output.outputIntent,
            keepLatestResult: true,
            historyMode: .captured(capture)
        )

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.invalidPreparation
        ) {
            _ = try await fixture.facade.accept(
                preparation,
                expectedPending: IOSPendingRecordingCASExpectation(
                    recording: output
                )
            )
        }
        #expect(await fixture.state.current() == nil)
        #expect(fixture.deliveryJournal.createCallCount == 0)
        #expect(fixture.deliveryJournal.record == nil)
        #expect(fixture.pendingJournal.recording == output)
        #expect(fixture.pendingJournal.removeCallCount == 0)
        #expect(fixture.audio.isPresent)
    }

    @Test func processOwnerAcceptsCapturedHistoryAndRetiresPendingAtomically()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try await fixture.capturedPreparation(
            for: output,
            historyEnabled: true
        )
        let owner = IOSForegroundVoicePersistenceOwner(
            pendingRecordingStore: fixture.pendingStore,
            acceptedOutputPersistence: fixture.facade
        )

        let record = try await owner.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireHistoryRecoveryPending()

        #expect(record.historyWrite?.state == .pending)
        #expect(fixture.capturedHistoryClient.callCount == 1)
        #expect(await fixture.state.current() == nil)
        #expect(fixture.pendingJournal.recording == nil)
        #expect(!fixture.audio.isPresent)
        #expect(
            try await owner.loadLatestResult() == .resultReady(record)
        )
    }

    @Test func processOwnerAcceptsCapturedDisabledHistoryAsReadyResult()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try await fixture.capturedPreparation(
            for: output,
            historyEnabled: false
        )
        let owner = IOSForegroundVoicePersistenceOwner(
            pendingRecordingStore: fixture.pendingStore,
            acceptedOutputPersistence: fixture.facade
        )

        let record = try await owner.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireReady()

        #expect(record.historyWrite == nil)
        #expect(fixture.capturedHistoryClient.callCount == 1)
        #expect(await fixture.state.current() == nil)
        #expect(fixture.pendingJournal.recording == nil)
        #expect(!fixture.audio.isPresent)
    }

    @Test func capturedAudioFailureRetriesRetirementWithoutReacceptingHistory()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try await fixture.capturedPreparation(
            for: output,
            historyEnabled: true
        )
        let owner = IOSForegroundVoicePersistenceOwner(
            pendingRecordingStore: fixture.pendingStore,
            acceptedOutputPersistence: fixture.facade
        )
        fixture.audio.failNextRemove = .removeFailed

        let saving = try await owner.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireSaving()
        #expect(fixture.capturedHistoryClient.callCount == 1)
        #expect(await fixture.state.current() != nil)

        _ = try await owner.retrySavingResult(
            expected: saving
        ).requireHistoryRecoveryPending()
        #expect(fixture.capturedHistoryClient.callCount == 1)
        #expect(await fixture.state.current() == nil)
        #expect(fixture.pendingJournal.recording == nil)
        #expect(!fixture.audio.isPresent)
    }

    @Test func capturedJournalFailureRetriesWithoutReacceptingHistory()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try await fixture.capturedPreparation(
            for: output,
            historyEnabled: true
        )
        let owner = IOSForegroundVoicePersistenceOwner(
            pendingRecordingStore: fixture.pendingStore,
            acceptedOutputPersistence: fixture.facade
        )
        fixture.pendingJournal.failNextRemove(
            .journalRemoveFailed,
            commitBeforeThrowing: false
        )

        let saving = try await owner.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireSaving()
        #expect(fixture.capturedHistoryClient.callCount == 1)
        #expect(await fixture.state.current() != nil)

        _ = try await owner.retrySavingResult(
            expected: saving
        ).requireHistoryRecoveryPending()
        #expect(fixture.capturedHistoryClient.callCount == 1)
        #expect(await fixture.state.current() == nil)
        #expect(fixture.pendingJournal.recording == nil)
        #expect(!fixture.audio.isPresent)
    }

    @Test func capturedRetryAfterJournalRetirementUsesRetainedDestinationOnly()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try await fixture.capturedPreparation(
            for: output,
            historyEnabled: true
        )
        let owner = IOSForegroundVoicePersistenceOwner(
            pendingRecordingStore: fixture.pendingStore,
            acceptedOutputPersistence: fixture.facade
        )
        fixture.pendingJournal.onSuccessfulMetadataRemoval = {
            [deliveryJournal = fixture.deliveryJournal] in
            deliveryJournal.failNextLoad(.readFailed)
        }

        let saving = try await owner.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireSaving()
        #expect(fixture.pendingJournal.recording == nil)
        #expect(!fixture.audio.isPresent)
        #expect(fixture.capturedHistoryClient.callCount == 1)
        #expect(
            try await fixture.state.hasCompletedRetirement(
                matching: saving
            )
        )

        _ = try await owner.retrySavingResult(
            expected: saving
        ).requireHistoryRecoveryPending()
        #expect(fixture.capturedHistoryClient.callCount == 1)
        #expect(await fixture.state.current() == nil)
    }

    @Test func capturedSavingResultCannotRollBackAnAcceptedDestination()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try await fixture.capturedPreparation(
            for: output,
            historyEnabled: true
        )
        let owner = IOSForegroundVoicePersistenceOwner(
            pendingRecordingStore: fixture.pendingStore,
            acceptedOutputPersistence: fixture.facade
        )
        fixture.audio.failNextRemove = .removeFailed
        let saving = try await owner.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireSaving()

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.invalidPreparation
        ) {
            _ = try await owner.recoverRecordingFromSavingResult(
                expected: saving
            )
        }
        #expect(await fixture.state.current() != nil)
        #expect(fixture.pendingJournal.recording == output)
        #expect(fixture.capturedHistoryClient.callCount == 1)
    }

    @Test func capturedHistoryDestinationRetiresPendingWithoutDeliveryRewrite()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try await fixture.capturedPreparation(
            for: output,
            historyEnabled: true
        )

        try await fixture.operationGate.perform { lease in
            let accepted = try await fixture.deliveryStore
                .acceptForHistoryCoordinator(
                    preparation.deliveryPreparation,
                    operationLeaseAuthorization: lease
                ).record
            let acceptance = IOSAcceptedHistoryAcceptanceResult(
                deliveryRecord: accepted,
                resolution: .pendingLocalRecovery
            )
            let replacementCount = fixture.deliveryJournal
                .replacementCallCount
            let firstDestination = try await fixture.deliveryStore
                .authorizeForegroundVoiceCapturedDestination(
                    acceptance: acceptance,
                    preparation: preparation.deliveryPreparation,
                    pendingRecording: output,
                    operationLeaseAuthorization: lease
                )

            #expect(
                firstDestination.description
                    == "IOSForegroundVoiceCapturedDestinationAuthorization(redacted)"
            )
            #expect(firstDestination.customMirror.children.isEmpty)
            #expect(
                fixture.deliveryJournal.replacementCallCount
                    == replacementCount
            )
            let audioRemoval = try await fixture.pendingStore
                .removeForegroundVoiceCapturedAcceptedOutputAudio(
                    expected: output,
                    destinationAuthorization: firstDestination,
                    deliveryStoreIdentity: fixture.deliveryStore.storeIdentity,
                    operationLeaseAuthorization: lease
                )
            let secondDestination = try await fixture.deliveryStore
                .authorizeForegroundVoiceCapturedDestination(
                    acceptance: acceptance,
                    preparation: preparation.deliveryPreparation,
                    pendingRecording: output,
                    operationLeaseAuthorization: lease
                )
            #expect(
                fixture.deliveryJournal.replacementCallCount
                    == replacementCount
            )
            try await fixture.pendingStore
                .retireForegroundVoiceCapturedAcceptedOutputJournal(
                    expected: output,
                    destinationAuthorization: secondDestination,
                    audioRemovalAuthorization: audioRemoval,
                    deliveryStoreIdentity: fixture.deliveryStore.storeIdentity,
                    operationLeaseAuthorization: lease
                )
        }

        #expect(fixture.deliveryJournal.record?.historyWrite?.state == .pending)
        #expect(fixture.pendingJournal.recording == nil)
        #expect(!fixture.audio.isPresent)
    }

    @Test func capturedDisabledDestinationRemainsCaptureBoundAndRetiresPending()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try await fixture.capturedPreparation(
            for: output,
            historyEnabled: false
        )

        try await fixture.operationGate.perform { lease in
            let accepted = try await fixture.deliveryStore
                .acceptForHistoryCoordinator(
                    preparation.deliveryPreparation,
                    operationLeaseAuthorization: lease
                ).record
            #expect(accepted.historyWrite == nil)
            let acceptance = IOSAcceptedHistoryAcceptanceResult(
                deliveryRecord: accepted,
                resolution: .notRequested
            )
            let destination = try await fixture.deliveryStore
                .authorizeForegroundVoiceCapturedDestination(
                    acceptance: acceptance,
                    preparation: preparation.deliveryPreparation,
                    pendingRecording: output,
                    operationLeaseAuthorization: lease
                )
            let audioRemoval = try await fixture.pendingStore
                .removeForegroundVoiceCapturedAcceptedOutputAudio(
                    expected: output,
                    destinationAuthorization: destination,
                    deliveryStoreIdentity: fixture.deliveryStore.storeIdentity,
                    operationLeaseAuthorization: lease
                )
            let revalidated = try await fixture.deliveryStore
                .authorizeForegroundVoiceCapturedDestination(
                    acceptance: acceptance,
                    preparation: preparation.deliveryPreparation,
                    pendingRecording: output,
                    operationLeaseAuthorization: lease
                )
            try await fixture.pendingStore
                .retireForegroundVoiceCapturedAcceptedOutputJournal(
                    expected: output,
                    destinationAuthorization: revalidated,
                    audioRemovalAuthorization: audioRemoval,
                    deliveryStoreIdentity: fixture.deliveryStore.storeIdentity,
                    operationLeaseAuthorization: lease
                )
        }

        #expect(fixture.pendingJournal.recording == nil)
        #expect(!fixture.audio.isPresent)
    }

    @Test func capturedDestinationAuthorizationRejectsResolutionAndMetadataDrift()
        async throws {
        let resolutionFixture = ForegroundVoicePersistenceFixture()
        let resolutionOutput = try await resolutionFixture.makeOutputDelivery()
        let resolutionPreparation = try await resolutionFixture
            .capturedPreparation(
                for: resolutionOutput,
                historyEnabled: true
            )
        try await resolutionFixture.operationGate.perform { lease in
            let accepted = try await resolutionFixture.deliveryStore
                .acceptForHistoryCoordinator(
                    resolutionPreparation.deliveryPreparation,
                    operationLeaseAuthorization: lease
                ).record
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.invalidTransition
            ) {
                _ = try await resolutionFixture.deliveryStore
                    .authorizeForegroundVoiceCapturedDestination(
                        acceptance: IOSAcceptedHistoryAcceptanceResult(
                            deliveryRecord: accepted,
                            resolution: .committed
                        ),
                        preparation:
                            resolutionPreparation.deliveryPreparation,
                        pendingRecording: resolutionOutput,
                        operationLeaseAuthorization: lease
                    )
            }
        }

        let metadataFixture = ForegroundVoicePersistenceFixture()
        let metadataOutput = try await metadataFixture.makeOutputDelivery()
        let metadataPreparation = try await metadataFixture
            .capturedPreparation(
                for: metadataOutput,
                historyEnabled: true,
                transcriptionModel: "different-model"
            )
        try await metadataFixture.operationGate.perform { lease in
            let accepted = try await metadataFixture.deliveryStore
                .acceptForHistoryCoordinator(
                    metadataPreparation.deliveryPreparation,
                    operationLeaseAuthorization: lease
                ).record
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.invalidTransition
            ) {
                _ = try await metadataFixture.deliveryStore
                    .authorizeForegroundVoiceCapturedDestination(
                        acceptance: IOSAcceptedHistoryAcceptanceResult(
                            deliveryRecord: accepted,
                            resolution: .pendingLocalRecovery
                        ),
                        preparation: metadataPreparation.deliveryPreparation,
                        pendingRecording: metadataOutput,
                        operationLeaseAuthorization: lease
                    )
            }
        }
    }

    @Test func pendingRecoveryAllowsMarkerAdvanceButRejectsAcceptanceDrift()
        async throws {
        let advancedFixture = ForegroundVoicePersistenceFixture()
        let advancedOutput = try await advancedFixture.makeOutputDelivery()
        let advancedPreparation = try await advancedFixture
            .capturedPreparation(
                for: advancedOutput,
                historyEnabled: true
            )
        try await advancedFixture.operationGate.perform { lease in
            let pending = try await advancedFixture.deliveryStore
                .acceptForHistoryCoordinator(
                    advancedPreparation.deliveryPreparation,
                    operationLeaseAuthorization: lease
                ).record
            _ = try advancedFixture.deliveryJournal.replaceCurrentForTesting(
                historyState: .committed
            )
            let replacementCount = advancedFixture.deliveryJournal
                .replacementCallCount
            let destination = try await advancedFixture.deliveryStore
                .authorizeForegroundVoiceCapturedDestination(
                    acceptance: IOSAcceptedHistoryAcceptanceResult(
                        deliveryRecord: pending,
                        resolution: .pendingLocalRecovery
                    ),
                    preparation: advancedPreparation.deliveryPreparation,
                    pendingRecording: advancedOutput,
                    operationLeaseAuthorization: lease
                )
            #expect(destination.record.historyWrite?.state == .committed)
            #expect(
                advancedFixture.deliveryJournal.replacementCallCount
                    == replacementCount
            )
        }

        let collisionFixture = ForegroundVoicePersistenceFixture()
        let collisionOutput = try await collisionFixture.makeOutputDelivery()
        let collisionPreparation = try await collisionFixture
            .capturedPreparation(
                for: collisionOutput,
                historyEnabled: true
            )
        try await collisionFixture.operationGate.perform { lease in
            let pending = try await collisionFixture.deliveryStore
                .acceptForHistoryCoordinator(
                    collisionPreparation.deliveryPreparation,
                    operationLeaseAuthorization: lease
                ).record
            let colliding = try collisionFixture.deliveryJournal
                .replaceCurrentForTesting(
                    acceptedText: "colliding text"
                )
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.invalidTransition
            ) {
                _ = try await collisionFixture.deliveryStore
                    .authorizeForegroundVoiceCapturedDestination(
                        acceptance: IOSAcceptedHistoryAcceptanceResult(
                            deliveryRecord: pending,
                            resolution: .pendingLocalRecovery
                        ),
                        preparation: collisionPreparation.deliveryPreparation,
                        pendingRecording: collisionOutput,
                        operationLeaseAuthorization: lease
                    )
            }
            collisionFixture.deliveryJournal.installCurrentForTesting(
                pending
            )
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.invalidTransition
            ) {
                _ = try await collisionFixture.deliveryStore
                    .authorizeForegroundVoiceCapturedDestination(
                        acceptance: IOSAcceptedHistoryAcceptanceResult(
                            deliveryRecord: colliding,
                            resolution: .pendingLocalRecovery
                        ),
                        preparation: collisionPreparation.deliveryPreparation,
                        pendingRecording: collisionOutput,
                        operationLeaseAuthorization: lease
                    )
            }
        }

        let unrelatedFixture = ForegroundVoicePersistenceFixture()
        let unrelatedOutput = try await unrelatedFixture.makeOutputDelivery()
        let unrelatedPreparation = try await unrelatedFixture
            .capturedPreparation(
                for: unrelatedOutput,
                historyEnabled: true
            )
        try await unrelatedFixture.operationGate.perform { lease in
            let pending = try await unrelatedFixture.deliveryStore
                .acceptForHistoryCoordinator(
                    unrelatedPreparation.deliveryPreparation,
                    operationLeaseAuthorization: lease
                ).record
            _ = try unrelatedFixture.deliveryJournal.replaceCurrentForTesting(
                attemptID: UUID(),
                transcriptID: UUID()
            )
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.invalidTransition
            ) {
                _ = try await unrelatedFixture.deliveryStore
                    .authorizeForegroundVoiceCapturedDestination(
                        acceptance: IOSAcceptedHistoryAcceptanceResult(
                            deliveryRecord: pending,
                            resolution: .pendingLocalRecovery
                        ),
                        preparation: unrelatedPreparation.deliveryPreparation,
                        pendingRecording: unrelatedOutput,
                        operationLeaseAuthorization: lease
                    )
            }
        }

        let terminalFixture = ForegroundVoicePersistenceFixture()
        let terminalOutput = try await terminalFixture.makeOutputDelivery()
        let terminalPreparation = try await terminalFixture
            .capturedPreparation(
                for: terminalOutput,
                historyEnabled: true
            )
        try await terminalFixture.operationGate.perform { lease in
            _ = try await terminalFixture.deliveryStore
                .acceptForHistoryCoordinator(
                    terminalPreparation.deliveryPreparation,
                    operationLeaseAuthorization: lease
                )
            let committed = try terminalFixture.deliveryJournal
                .replaceCurrentForTesting(historyState: .committed)
            _ = try terminalFixture.deliveryJournal.replaceCurrentForTesting(
                historyState: .cancelled
            )
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.invalidTransition
            ) {
                _ = try await terminalFixture.deliveryStore
                    .authorizeForegroundVoiceCapturedDestination(
                        acceptance: IOSAcceptedHistoryAcceptanceResult(
                            deliveryRecord: committed,
                            resolution: .committed
                        ),
                        preparation: terminalPreparation.deliveryPreparation,
                        pendingRecording: terminalOutput,
                        operationLeaseAuthorization: lease
                    )
            }
        }
    }

    @Test func happyPathCommitsGenerationZeroThenRetiresExactPending()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try fixture.preparation(for: output)

        let result = try await fixture.facade.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        )
        let record = try result.requireReady()

        #expect(record.deliveryState == .pending)
        #expect(record.publicationGeneration == 0)
        #expect(!record.automaticInsertionPreferenceEnabled)
        #expect(record.historyWrite == nil)
        #expect(record.failedRetryID == nil)
        #expect(fixture.pendingJournal.recording == nil)
        #expect(!fixture.audio.isPresent)
        #expect(fixture.executor.callCount == 1)
        #expect(
            try await fixture.facade.loadLatestResult()
                == .resultReady(record)
        )
    }

    @Test func processOwnerKeepsTheExactPendingActorAcrossProviderStages()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let owner = IOSForegroundVoicePersistenceOwner(
            pendingRecordingStore: fixture.pendingStore,
            acceptedOutputPersistence: fixture.facade
        )
        let attemptID = UUID()
        let transcriptionID = UUID()
        let prepared = try await owner.prepare(
            IOSPendingRecordingPreparation(
                attemptID: attemptID,
                sourceArtifact: AudioRecordingArtifact(
                    fileURL: URL(fileURLWithPath: "/runtime/owner.m4a"),
                    duration: 1.25,
                    byteCount: 32
                ),
                initialState: .readyForTranscription,
                outputIntent: .standard,
                transcriptionConfiguration: .defaults
            )
        )

        let dispatch = try await owner.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: transcriptionID
        )
        #expect(dispatch.recording == fixture.pendingJournal.recording)
        #expect(dispatch.recording.attemptID == attemptID)
        #expect(dispatch.recording.transcriptionID == transcriptionID)
        #expect(
            try await dispatch.execute(using: fixture.executor)
                == "provider result"
        )

        let postProcessing = try await owner.markPostProcessing(
            expected: dispatch.expectation
        )
        let outputDelivery = try await owner.markOutputDelivery(
            expected: IOSPendingRecordingCASExpectation(
                recording: postProcessing
            )
        )
        let result = try await owner.accept(
            try fixture.preparation(for: outputDelivery),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: outputDelivery
            )
        )

        _ = try result.requireReady()
        #expect(fixture.pendingJournal.recording == nil)
        #expect(fixture.executor.callCount == 1)
    }

    @Test func readyLoadRequiresDurablePendingJournalAbsenceProof()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let record = try await fixture.facade.accept(
            try fixture.preparation(for: output),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireReady()
        fixture.pendingJournal.failNextAbsenceProof(
            .journalCommitUncertain
        )

        await #expect(throws: IOSPendingRecordingError.journalCommitUncertain) {
            _ = try await fixture.facade.loadLatestResult()
        }
        #expect(
            try await fixture.facade.loadLatestResult()
                == .resultReady(record)
        )
    }

    @Test func invisibleDeliveryFailureBecomesSavingAndRetriesWithoutProvider()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try fixture.preparation(for: output)
        fixture.deliveryJournal.failNextCreate(
            .writeFailed,
            commitBeforeThrowing: false
        )

        let first = try await fixture.facade.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        )
        let saving = try first.requireSaving()
        #expect(fixture.pendingJournal.recording == output)
        #expect(fixture.audio.isPresent)
        #expect(fixture.deliveryJournal.record == nil)
        #expect(
            try await fixture.facade.loadLatestResult()
                == .savingResult(saving, priorResult: nil)
        )

        let retried = try await fixture.facade.retrySavingResult(
            expected: saving
        )
        _ = try retried.requireReady()
        #expect(fixture.executor.callCount == 1)
        #expect(fixture.pendingJournal.recording == nil)
        #expect(!fixture.audio.isPresent)
    }

    @Test func visibleUncertainDeliveryCommitReconcilesIdenticalBytes()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try fixture.preparation(for: output)
        fixture.deliveryJournal.failNextCreate(
            .commitUncertain,
            commitBeforeThrowing: true
        )

        let first = try await fixture.facade.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        )
        let saving = try first.requireSaving()
        #expect(fixture.deliveryJournal.record?.acceptedText == "accepted")
        #expect(fixture.pendingJournal.recording == output)

        let retried = try await fixture.facade.retrySavingResult(
            expected: saving
        )
        _ = try retried.requireReady()
        #expect(fixture.deliveryJournal.createCallCount == 1)
        #expect(fixture.executor.callCount == 1)
    }

    @Test func audioRemovalFailureCannotFallBackToProviderRecovery()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try fixture.preparation(for: output)
        fixture.audio.failNextRemove = .removeFailed

        let first = try await fixture.facade.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        )
        let saving = try first.requireSaving()
        #expect(fixture.pendingJournal.recording == output)
        #expect(fixture.deliveryJournal.record?.acceptedText == "accepted")

        await #expect(throws: IOSAcceptedOutputDeliveryError.invalidTransition) {
            _ = try await fixture.facade
                .recoverRecordingFromSavingResult(expected: saving)
        }

        _ = try await fixture.facade.retrySavingResult(expected: saving)
            .requireReady()
        #expect(fixture.executor.callCount == 1)
    }

    @Test func journalRetirementFailureRetriesOnlyLocalCheckpoints()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try fixture.preparation(for: output)
        fixture.pendingJournal.failNextRemove(
            .journalRemoveFailed,
            commitBeforeThrowing: false
        )

        let first = try await fixture.facade.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        )
        let saving = try first.requireSaving()
        #expect(fixture.pendingJournal.recording == output)
        #expect(!fixture.audio.isPresent)

        _ = try await fixture.facade.retrySavingResult(expected: saving)
            .requireReady()
        #expect(fixture.pendingJournal.removeCallCount == 2)
        #expect(fixture.executor.callCount == 1)
    }

    @Test func processSharedStateLetsAnotherSceneRetryTheSameWork()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        fixture.audio.failNextRemove = .removeFailed
        let saving = try await fixture.facade.accept(
            try fixture.preparation(for: output),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireSaving()

        let secondSceneFacade = fixture.makeAdditionalFacade()
        _ = try await secondSceneFacade.retrySavingResult(
            expected: saving
        ).requireReady()
        #expect(fixture.pendingJournal.recording == nil)
        #expect(fixture.executor.callCount == 1)
    }

    @Test func uncertainJournalRemovalThatAlreadyCommittedReconcilesAbsence()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try fixture.preparation(for: output)
        fixture.pendingJournal.failNextRemove(
            .journalRemoveFailed,
            commitBeforeThrowing: true
        )

        let first = try await fixture.facade.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        )
        let saving = try first.requireSaving()
        #expect(fixture.pendingJournal.recording == nil)
        #expect(!fixture.audio.isPresent)

        _ = try await fixture.facade.retrySavingResult(expected: saving)
            .requireReady()
        #expect(fixture.executor.callCount == 1)
    }

    @Test func uncertainJournalUnlinkNeedsADurableAbsenceBarrierBeforeReady()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try fixture.preparation(for: output)
        fixture.pendingJournal.failNextRemove(
            .journalCommitUncertain,
            commitBeforeThrowing: true
        )

        let saving = try await fixture.facade.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireSaving()
        #expect(fixture.pendingJournal.recording == nil)
        #expect(!fixture.audio.isPresent)

        fixture.pendingJournal.failNextAbsenceProof(
            .journalCommitUncertain
        )
        #expect(
            try await fixture.facade.retrySavingResult(expected: saving)
                == .savingResult(saving)
        )
        #expect(
            try await fixture.facade.loadLatestResult()
                == .savingResult(saving, priorResult: nil)
        )

        _ = try await fixture.facade.retrySavingResult(expected: saving)
            .requireReady()
        #expect(fixture.executor.callCount == 1)
    }

    @Test func exactNoDestinationRecoveryMovesOutputToAwaitingRecovery()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try fixture.preparation(for: output)
        fixture.deliveryJournal.failNextCreate(
            .commitUncertain,
            commitBeforeThrowing: false
        )

        let first = try await fixture.facade.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        )
        let saving = try first.requireSaving()
        let recovered = try await fixture.facade
            .recoverRecordingFromSavingResult(expected: saving)

        #expect(recovered.phase == .awaitingRecovery)
        #expect(recovered.transcriptionID == nil)
        #expect(recovered.attemptID == output.attemptID)
        #expect(recovered.audioRelativeIdentifier == output.audioRelativeIdentifier)
        #expect(fixture.audio.isPresent)
        #expect(fixture.deliveryJournal.record == nil)
        #expect(fixture.executor.callCount == 1)
        await #expect(throws: IOSForegroundVoicePersistenceError.noSavingResult) {
            _ = try await fixture.facade.retrySavingResult(expected: saving)
        }
    }

    @Test func noDestinationRecoveryPreservesLegitimateRetryIdentityReuse()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let sessionID = UUID()
        let attemptID = UUID()
        let firstOutput = try await fixture.makeOutputDelivery(
            attemptID: attemptID,
            transcriptionID: UUID()
        )
        let first = try await fixture.facade.accept(
            try makeForegroundPreparation(
                sessionID: sessionID,
                attemptID: attemptID,
                transcriptID: try #require(firstOutput.transcriptionID),
                rawAcceptedText: "first"
            ),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: firstOutput
            )
        ).requireReady()

        let secondOutput = try await fixture.makeOutputDelivery(
            attemptID: attemptID,
            transcriptionID: UUID()
        )
        let secondPreparation = try makeForegroundPreparation(
            sessionID: sessionID,
            attemptID: attemptID,
            transcriptID: try #require(secondOutput.transcriptionID),
            rawAcceptedText: "second"
        )
        fixture.deliveryJournal.failNextReplace(
            .commitUncertain,
            commitBeforeThrowing: false
        )
        let saving = try await fixture.facade.accept(
            secondPreparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: secondOutput
            )
        ).requireSaving()

        let recovered = try await fixture.facade
            .recoverRecordingFromSavingResult(expected: saving)
        #expect(recovered.phase == .awaitingRecovery)
        #expect(fixture.deliveryJournal.record == first)
        #expect(fixture.audio.isPresent)
        #expect(fixture.executor.callCount == 2)
    }

    @Test func recoveryReconcilesAVisibleUncertainAwaitingRecoveryCommit()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try fixture.preparation(for: output)
        fixture.deliveryJournal.failNextCreate(
            .writeFailed,
            commitBeforeThrowing: false
        )
        let first = try await fixture.facade.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        )
        let saving = try first.requireSaving()
        fixture.pendingJournal.failNextReplace(
            .journalCommitUncertain,
            commitBeforeThrowing: true
        )

        await #expect(throws: IOSPendingRecordingError.journalCommitUncertain) {
            _ = try await fixture.facade
                .recoverRecordingFromSavingResult(expected: saving)
        }
        #expect(fixture.pendingJournal.recording?.phase == .awaitingRecovery)

        let recovered = try await fixture.facade
            .recoverRecordingFromSavingResult(expected: saving)
        #expect(recovered.phase == .awaitingRecovery)
        #expect(recovered.transcriptionID == nil)
    }

    @Test func loadAndCASClearExposeOnlyTheAppOnlyLatestResult()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try fixture.preparation(for: output)
        let accepted = try await fixture.facade.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireReady()

        let stale = try IOSAcceptedOutputDeliveryRecord(
            revision: accepted.revision + 1,
            deliveryID: accepted.deliveryID,
            sessionID: accepted.sessionID,
            attemptID: accepted.attemptID,
            transcriptID: accepted.transcriptID,
            acceptedText: accepted.acceptedText,
            outputIntent: accepted.outputIntent,
            createdAt: accepted.createdAt,
            updatedAt: accepted.updatedAt,
            expiresAt: accepted.expiresAt,
            deliveryState: accepted.deliveryState,
            automaticInsertionPreferenceEnabled: false,
            keepLatestResult: accepted.keepLatestResult,
            publicationGeneration: 0,
            historyWrite: nil
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            _ = try await fixture.facade.clearLatestResult(
                expected: IOSAcceptedOutputDeliveryExpectation(record: stale)
            )
        }

        #expect(
            try await fixture.facade.clearLatestResult(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: accepted
                )
            ) == .cleared
        )
        #expect(try await fixture.facade.loadLatestResult() == .absent)
    }

    @Test func confirmedClearTombstoneHidesTextWhileCleanupRetries()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let accepted = try await fixture.facade.accept(
            try fixture.preparation(for: output),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireReady()
        fixture.deliveryJournal.removeError = .removeFailed

        #expect(
            try await fixture.facade.clearLatestResult(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: accepted
                )
            ) == .clearedCleanupPending
        )
        #expect(fixture.deliveryJournal.record?.deliveryState == .discarded)
        #expect(fixture.deliveryJournal.record?.acceptedText == nil)
        #expect(
            try await fixture.facade.loadLatestResult()
                == .clearedCleanupPending
        )

        fixture.deliveryJournal.removeError = nil
        let relaunched = fixture.makeRelaunchedFacade()
        #expect(
            try await relaunched.retryLatestResultCleanup() == .cleared
        )
        #expect(try await relaunched.loadLatestResult() == .absent)
    }

    @Test func uncertainUnlinkRequiresAnAbsenceBarrierOnCleanupRetry()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let accepted = try await fixture.facade.accept(
            try fixture.preparation(for: output),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireReady()
        fixture.deliveryJournal.removeError = .removalCommitUncertain
        fixture.deliveryJournal.removeCommitsBeforeThrowing = true
        fixture.deliveryJournal.confirmAbsenceError =
            .removalCommitUncertain

        #expect(
            try await fixture.facade.clearLatestResult(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: accepted
                )
            ) == .clearedCleanupPending
        )
        #expect(fixture.deliveryJournal.record == nil)
        let relaunched = fixture.makeFreshDeliveryStoreFacade()
        #expect(
            try await relaunched.loadLatestResult()
                == .clearedCleanupPending
        )
        #expect(
            try await relaunched.retryLatestResultCleanup()
                == .clearedCleanupPending
        )

        fixture.deliveryJournal.confirmAbsenceError = nil
        #expect(
            try await relaunched.retryLatestResultCleanup()
                == .alreadyAbsent
        )
    }

    @Test func clearIsBlockedUntilExactPendingRetirementFinishes()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let preparation = try fixture.preparation(for: output)
        fixture.audio.failNextRemove = .removeFailed
        let saving = try await fixture.facade.accept(
            preparation,
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireSaving()
        let delivery = try #require(fixture.deliveryJournal.record)

        await #expect(
            throws: IOSForegroundVoicePersistenceError.savingResultPending
        ) {
            _ = try await fixture.facade.clearLatestResult(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: delivery
                )
            )
        }
        _ = try await fixture.facade.retrySavingResult(expected: saving)
            .requireReady()
    }

    @Test func clearRequiresDurablePendingAbsenceWhenLookupIsNil()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let accepted = try await fixture.facade.accept(
            try fixture.preparation(for: output),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireReady()
        fixture.pendingJournal.failNextAbsenceProof(
            .journalCommitUncertain
        )

        await #expect(
            throws: IOSPendingRecordingError.journalCommitUncertain
        ) {
            _ = try await fixture.facade.clearLatestResult(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: accepted
                )
            )
        }
        #expect(fixture.deliveryJournal.record == accepted)
        #expect(
            try await fixture.facade.loadLatestResult()
                == .resultReady(accepted)
        )
    }

    @Test func wrongPhaseDestinationOverlapBlocksLoadAndClear()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let accepted = try await fixture.facade.accept(
            try fixture.preparation(for: output),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireReady()
        fixture.pendingJournal.seed(
            try IOSPendingRecording(
                attemptID: output.attemptID,
                audioRelativeIdentifier: output.audioRelativeIdentifier,
                createdAt: output.createdAt,
                updatedAt: output.updatedAt,
                phase: .postProcessing,
                outputIntent: output.outputIntent,
                transcriptionID: output.transcriptionID,
                transcriptionModel: output.transcriptionModel,
                transcriptionLanguageCode:
                    output.transcriptionLanguageCode,
                durationMilliseconds: output.durationMilliseconds,
                byteCount: output.byteCount
            )
        )

        await #expect(
            throws: IOSForegroundVoicePersistenceError.invalidPendingOwner
        ) {
            _ = try await fixture.facade.loadLatestResult()
        }
        await #expect(
            throws: IOSForegroundVoicePersistenceError.invalidPendingOwner
        ) {
            _ = try await fixture.facade.clearLatestResult(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: accepted
                )
            )
        }
        #expect(fixture.deliveryJournal.record == accepted)
    }

    @Test func partialOutputDeliveryOverlapBlocksLoadAndClear()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        let accepted = try await fixture.facade.accept(
            try fixture.preparation(for: output),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireReady()
        let conflictingIntent: DictationOutputIntent =
            output.outputIntent == .standard ? .translate : .standard
        fixture.pendingJournal.seed(
            try IOSPendingRecording(
                attemptID: output.attemptID,
                audioRelativeIdentifier: output.audioRelativeIdentifier,
                createdAt: output.createdAt,
                updatedAt: output.updatedAt,
                phase: .outputDelivery,
                outputIntent: conflictingIntent,
                transcriptionID: output.transcriptionID,
                transcriptionModel: output.transcriptionModel,
                transcriptionLanguageCode:
                    output.transcriptionLanguageCode,
                durationMilliseconds: output.durationMilliseconds,
                byteCount: output.byteCount
            )
        )

        await #expect(
            throws: IOSForegroundVoicePersistenceError.invalidPendingOwner
        ) {
            _ = try await fixture.facade.loadLatestResult()
        }
        await #expect(
            throws: IOSForegroundVoicePersistenceError.invalidPendingOwner
        ) {
            _ = try await fixture.facade.clearLatestResult(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: accepted
                )
            )
        }
        #expect(fixture.deliveryJournal.record == accepted)
    }

    @Test func replacementIsAtomicAndKeepsOnlyTheNewP4Result()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let firstOutput = try await fixture.makeOutputDelivery()
        let first = try await fixture.facade.accept(
            try fixture.preparation(
                for: firstOutput,
                acceptedText: "first"
            ),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: firstOutput
            )
        ).requireReady()

        let secondOutput = try await fixture.makeOutputDelivery()
        let second = try await fixture.facade.accept(
            try fixture.preparation(
                for: secondOutput,
                acceptedText: "second"
            ),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: secondOutput
            )
        ).requireReady()

        #expect(first.deliveryID != second.deliveryID)
        #expect(second.acceptedText == "second")
        #expect(fixture.deliveryJournal.record == second)
        #expect(!fixture.deliveryJournal.replacedWithDiscardedBeforeLatest)
        #expect(fixture.executor.callCount == 2)
    }

    @Test func failedReplacementKeepsPriorResultVisibleAndClearable()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let firstOutput = try await fixture.makeOutputDelivery()
        let first = try await fixture.facade.accept(
            try fixture.preparation(
                for: firstOutput,
                acceptedText: "first"
            ),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: firstOutput
            )
        ).requireReady()

        let secondOutput = try await fixture.makeOutputDelivery()
        fixture.deliveryJournal.failNextReplace(
            .writeFailed,
            commitBeforeThrowing: false
        )
        let saving = try await fixture.facade.accept(
            try fixture.preparation(
                for: secondOutput,
                acceptedText: "second"
            ),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: secondOutput
            )
        ).requireSaving()

        #expect(
            try await fixture.facade.loadLatestResult()
                == .savingResult(saving, priorResult: first)
        )
        #expect(
            try await fixture.facade.clearLatestResult(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: first
                )
            ) == .cleared
        )
        let second = try await fixture.facade.retrySavingResult(
            expected: saving
        ).requireReady()
        #expect(second.acceptedText == "second")
    }

    @Test func uncertainReplacementShowsPriorButBlocksItsClear()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let firstOutput = try await fixture.makeOutputDelivery()
        let first = try await fixture.facade.accept(
            try fixture.preparation(
                for: firstOutput,
                acceptedText: "first"
            ),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: firstOutput
            )
        ).requireReady()

        let secondOutput = try await fixture.makeOutputDelivery()
        fixture.deliveryJournal.failNextReplace(
            .commitUncertain,
            commitBeforeThrowing: false
        )
        let saving = try await fixture.facade.accept(
            try fixture.preparation(
                for: secondOutput,
                acceptedText: "second"
            ),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: secondOutput
            )
        ).requireSaving()

        #expect(
            try await fixture.facade.loadLatestResult()
                == .savingResult(saving, priorResult: first)
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.commitUncertain
        ) {
            _ = try await fixture.facade.clearLatestResult(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: first
                )
            )
        }
    }

    @Test func clearedPredecessorNeverReappearsAsPriorSavingText()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let firstOutput = try await fixture.makeOutputDelivery()
        let first = try await fixture.facade.accept(
            try fixture.preparation(for: firstOutput),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: firstOutput
            )
        ).requireReady()

        let secondOutput = try await fixture.makeOutputDelivery()
        fixture.deliveryJournal.failNextReplace(
            .writeFailed,
            commitBeforeThrowing: false
        )
        let saving = try await fixture.facade.accept(
            try fixture.preparation(
                for: secondOutput,
                acceptedText: "second"
            ),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: secondOutput
            )
        ).requireSaving()
        fixture.deliveryJournal.removeError = .removeFailed

        #expect(
            try await fixture.facade.clearLatestResult(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: first
                )
            ) == .clearedCleanupPending
        )
        #expect(
            try await fixture.facade.loadLatestResult()
                == .savingResult(saving, priorResult: nil)
        )
    }

    @Test func realIdentityCollisionRetainsBlockedRecoveryCapability()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let firstOutput = try await fixture.makeOutputDelivery()
        let first = try await fixture.facade.accept(
            try fixture.preparation(for: firstOutput),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: firstOutput
            )
        ).requireReady()

        let secondOutput = try await fixture.makeOutputDelivery()
        let saving = try await fixture.facade.accept(
            try makeForegroundPreparation(
                deliveryID: first.deliveryID,
                sessionID: UUID(),
                attemptID: secondOutput.attemptID,
                transcriptID: try #require(
                    secondOutput.transcriptionID
                ),
                rawAcceptedText: "second"
            ),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: secondOutput
            )
        ).requireSaving()

        #expect(await fixture.state.current() != nil)
        #expect(fixture.deliveryJournal.record == first)
        #expect(
            try await fixture.facade.loadLatestResult()
                == .savingResult(saving, priorResult: first)
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.identityCollision) {
            _ = try await fixture.facade
                .recoverRecordingFromSavingResult(expected: saving)
        }
        #expect(await fixture.state.current() != nil)
    }

    @Test func finalDeliveryReadFailureRetriesAfterRetirementWithoutRestart()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        fixture.pendingJournal.onSuccessfulMetadataRemoval = {
            fixture.deliveryJournal.failNextLoad(.readFailed)
        }

        let saving = try await fixture.facade.accept(
            try fixture.preparation(for: output),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireSaving()
        #expect(fixture.pendingJournal.recording == nil)
        #expect(!fixture.audio.isPresent)

        let record = try await fixture.facade.retrySavingResult(
            expected: saving
        ).requireReady()
        #expect(record.acceptedText == "accepted")
        #expect(fixture.pendingJournal.removeCallCount == 1)
        #expect(fixture.executor.callCount == 1)
    }

    @Test func finalDeliveryReadFailureSelfHealsThroughLatestLoad()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        fixture.pendingJournal.onSuccessfulMetadataRemoval = {
            fixture.deliveryJournal.failNextLoad(.readFailed)
        }
        let saving = try await fixture.facade.accept(
            try fixture.preparation(for: output),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireSaving()

        guard case .resultReady(let record) = try await fixture.facade
            .loadLatestResult() else {
            throw ForegroundVoiceTestError.unexpectedResult
        }
        #expect(record.acceptedText == "accepted")
        await #expect(throws: IOSForegroundVoicePersistenceError.noSavingResult) {
            _ = try await fixture.facade.retrySavingResult(expected: saving)
        }
        #expect(fixture.pendingJournal.removeCallCount == 1)
    }

    @Test func missingFinalDeliveryCannotEraseCompletedRetirementState()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        fixture.pendingJournal.onSuccessfulMetadataRemoval = {
            fixture.deliveryJournal.removeCurrentRecordForTesting()
        }

        let saving = try await fixture.facade.accept(
            try fixture.preparation(for: output),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireSaving()
        #expect(fixture.pendingJournal.recording == nil)
        #expect(!fixture.audio.isPresent)
        #expect(
            try await fixture.facade.retrySavingResult(expected: saving)
                == .savingResult(saving)
        )
        #expect(
            try await fixture.facade.loadLatestResult()
                == .savingResult(saving, priorResult: nil)
        )
        #expect(await fixture.state.current() != nil)
        #expect(fixture.pendingJournal.removeCallCount == 1)
        #expect(fixture.executor.callCount == 1)
    }

    @Test func expiryAfterDestinationCommitResumesOnlyLocalCleanup()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        fixture.audio.failNextRemove = .removeFailed
        let saving = try await fixture.facade.accept(
            try fixture.preparation(for: output),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireSaving()
        fixture.clock.date = Date(timeIntervalSince1970: 1_800_086_500)

        let result = try await fixture.facade.retrySavingResult(
            expected: saving
        )
        guard case .expired = result else {
            throw ForegroundVoiceTestError.unexpectedResult
        }
        #expect(fixture.executor.callCount == 1)
        #expect(fixture.pendingJournal.recording == nil)
    }

    @Test func rollbackAfterDestinationCommitResumesOnlyLocalCleanup()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        fixture.audio.failNextRemove = .removeFailed
        let saving = try await fixture.facade.accept(
            try fixture.preparation(for: output),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireSaving()
        fixture.clock.date = Date(timeIntervalSince1970: 1_799_999_000)

        let result = try await fixture.facade.retrySavingResult(
            expected: saving
        )
        guard case .clockRollbackAmbiguous = result else {
            throw ForegroundVoiceTestError.unexpectedResult
        }
        #expect(fixture.executor.callCount == 1)
        #expect(fixture.pendingJournal.recording == nil)
    }

    @Test func rollbackBeforeReplacementKeepsExactSavingWork()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let firstOutput = try await fixture.makeOutputDelivery()
        _ = try await fixture.facade.accept(
            try fixture.preparation(for: firstOutput),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: firstOutput
            )
        ).requireReady()
        let secondOutput = try await fixture.makeOutputDelivery()
        fixture.clock.date = Date(timeIntervalSince1970: 1_799_999_000)

        let saving = try await fixture.facade.accept(
            try fixture.preparation(
                for: secondOutput,
                acceptedText: "second"
            ),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: secondOutput
            )
        ).requireSaving()
        #expect(
            try await fixture.facade.loadLatestResult()
                == .savingResult(saving, priorResult: nil)
        )
        #expect(await fixture.state.current() != nil)

        fixture.clock.date = Date(timeIntervalSince1970: 1_800_000_000)
        let second = try await fixture.facade.retrySavingResult(
            expected: saving
        ).requireReady()
        #expect(second.acceptedText == "second")
        #expect(fixture.executor.callCount == 2)
    }

    @Test func relaunchRehydratesSavingWorkFromExactDestination()
        async throws {
        let fixture = ForegroundVoicePersistenceFixture()
        let output = try await fixture.makeOutputDelivery()
        fixture.audio.failNextRemove = .removeFailed
        _ = try await fixture.facade.accept(
            try fixture.preparation(for: output),
            expectedPending: IOSPendingRecordingCASExpectation(
                recording: output
            )
        ).requireSaving()

        let relaunched = fixture.makeRelaunchedFacade()
        let observation = try await relaunched.loadLatestResult()
        guard case .savingResult(let saving, priorResult: nil) = observation else {
            throw ForegroundVoiceTestError.unexpectedResult
        }
        _ = try await relaunched.retrySavingResult(
            expected: saving
        ).requireReady()
        #expect(fixture.pendingJournal.recording == nil)
        #expect(fixture.executor.callCount == 1)
    }

    @Test func resultAndErrorsAreContentFreeInDescriptions() throws {
        let preparation = try makeForegroundPreparation(
            rawAcceptedText: "P4-SENSITIVE-CANARY"
        )
        let expectation = IOSForegroundVoiceSavingResultExpectation(
            preparation: preparation.deliveryPreparation
        )
        let result = IOSForegroundVoiceAcceptanceResult.savingResult(
            expectation
        )

        #expect(!String(describing: expectation).contains("P4-SENSITIVE"))
        #expect(!String(reflecting: result).contains("P4-SENSITIVE"))
        #expect(result.customMirror.children.isEmpty)
        let fixture = ForegroundVoicePersistenceFixture()
        #expect(
            String(describing: fixture.facade)
                == "IOSForegroundVoicePersistence(redacted)"
        )
        #expect(fixture.facade.customMirror.children.isEmpty)
        #expect(
            String(describing: IOSForegroundVoicePersistenceError
                .localRecoveryPending)
                == "IOSForegroundVoicePersistenceError(redacted)"
        )
    }
}

private extension IOSForegroundVoiceAcceptanceResult {
    func requireReady() throws -> IOSAcceptedOutputDeliveryRecord {
        guard case .resultReady(let record) = self else {
            throw ForegroundVoiceTestError.unexpectedResult
        }
        return record
    }

    func requireSaving() throws
        -> IOSForegroundVoiceSavingResultExpectation {
        guard case .savingResult(let expectation) = self else {
            throw ForegroundVoiceTestError.unexpectedResult
        }
        return expectation
    }

    func requireHistoryRecoveryPending() throws
        -> IOSAcceptedOutputDeliveryRecord {
        guard case .acceptedHistoryRecoveryPending(let record) = self else {
            throw ForegroundVoiceTestError.unexpectedResult
        }
        return record
    }
}

private enum ForegroundVoiceTestError: Error {
    case unexpectedResult
}

private func makeForegroundPreparation(
    deliveryID: UUID = UUID(),
    sessionID: UUID = UUID(),
    attemptID: UUID = UUID(),
    transcriptID: UUID = UUID(),
    rawAcceptedText: String = "accepted",
    outputIntent: DictationOutputIntent = .standard
) throws -> IOSForegroundVoiceAcceptedOutputPreparation {
    try IOSForegroundVoiceAcceptedOutputPreparation(
        deliveryID: deliveryID,
        sessionID: sessionID,
        attemptID: attemptID,
        transcriptID: transcriptID,
        rawAcceptedText: rawAcceptedText,
        outputIntent: outputIntent,
        keepLatestResult: true
    )
}

private func makeForegroundHistoryCaptures() async throws -> (
    enabled: IOSAcceptedOutputHistoryCapture,
    disabled: IOSAcceptedOutputHistoryCapture
) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ios-foreground-history-mode-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let coordinator = IOSAcceptedHistoryCoordinator(
        applicationSupportDirectoryURL: root,
        registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry()
    )
    let enabled = try await coordinator.capture(
        transcriptionModel: "MODE-SECRET-MODEL",
        transcriptionLanguageCode: "en",
        durationMilliseconds: 1_250
    )
    _ = try await coordinator.setHistoryEnabled(false)
    let disabled = try await coordinator.capture(
        transcriptionModel: "MODE-SECRET-MODEL",
        transcriptionLanguageCode: "en",
        durationMilliseconds: 1_250
    )
    return (enabled, disabled)
}

private final class ForegroundVoicePersistenceFixture: @unchecked Sendable {
    let operationGate = IOSPersistenceOperationGate()
    let ownerIdentity = IOSAcceptedHistoryCapabilityOwnerIdentity()
    let pendingJournal = ForegroundVoicePendingJournal()
    let audio = ForegroundVoiceAudioFileSystem()
    let deliveryJournal = ForegroundVoiceDeliveryJournal()
    let executor = ForegroundVoiceExecutor()
    let capturedHistoryClient = ForegroundVoiceCapturedHistoryClient()
    let state = IOSForegroundVoicePersistenceOperationState()
    let clock = ForegroundVoiceClock(
        date: Date(timeIntervalSince1970: 1_800_000_000)
    )
    lazy var pendingStore = IOSPendingRecordingStore(
        journal: pendingJournal,
        audioFileSystem: audio,
        operationGate: operationGate,
        capabilityOwnerIdentity: ownerIdentity,
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    lazy var deliveryStore = IOSAcceptedOutputDeliveryStore(
        journal: deliveryJournal,
        now: { [clock] in clock.date },
        monotonicNowNanoseconds: { 0 },
        capabilityOwnerIdentity: ownerIdentity,
        operationGateIdentity: operationGate.identity
    )
    lazy var facade = IOSForegroundVoicePersistence(
        operationGate: operationGate,
        pendingRecordingStore: pendingStore,
        deliveryStore: deliveryStore,
        capturedHistoryAcceptance: {
            [capturedHistoryClient, deliveryStore] preparation, lease in
            try await capturedHistoryClient.accept(
                preparation,
                deliveryStore: deliveryStore,
                operationLeaseAuthorization: lease
            )
        },
        state: state
    )

    private var sequence: UInt8 = 1

    func makeOutputDelivery(
        outputIntent: DictationOutputIntent = .standard,
        attemptID suppliedAttemptID: UUID? = nil,
        transcriptionID suppliedTranscriptionID: UUID? = nil
    ) async throws -> IOSPendingRecording {
        let value = sequence
        sequence &+= 1
        let attemptID = suppliedAttemptID ?? UUID(
            uuid: (
                value, 0, 0, 0, 0, 0x40, 0x40, 0x40,
                0x80, 0, 0, 0, 0, 0, 0, value
            )
        )
        let transcriptionID = suppliedTranscriptionID ?? UUID(
            uuid: (
                value, 1, 0, 0, 0, 0x40, 0x40, 0x40,
                0x80, 0, 0, 0, 0, 0, 1, value
            )
        )
        let pending = try await pendingStore.prepare(
            IOSPendingRecordingPreparation(
                attemptID: attemptID,
                sourceArtifact: AudioRecordingArtifact(
                    fileURL: URL(
                        fileURLWithPath: "/runtime/\(value).m4a"
                    ),
                    duration: 1.25,
                    byteCount: 32
                ),
                initialState: .readyForTranscription,
                outputIntent: outputIntent,
                transcriptionConfiguration: TranscriptionConfiguration(
                    model: "gpt-4o-transcribe",
                    language: .english
                )
            )
        )
        let handoff = try await pendingStore.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: pending),
            transcriptionID: transcriptionID
        )
        _ = try await handoff.execute(using: executor)
        let postProcessing = try await pendingStore.markPostProcessing(
            expected: IOSPendingRecordingCASExpectation(
                recording: try #require(
                    pendingJournal.recording
                )
            )
        )
        return try await pendingStore.markOutputDelivery(
            expected: IOSPendingRecordingCASExpectation(
                recording: postProcessing
            )
        )
    }

    func preparation(
        for pending: IOSPendingRecording,
        acceptedText: String = "accepted"
    ) throws -> IOSForegroundVoiceAcceptedOutputPreparation {
        try makeForegroundPreparation(
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: pending.attemptID,
            transcriptID: try #require(pending.transcriptionID),
            rawAcceptedText: acceptedText,
            outputIntent: pending.outputIntent
        )
    }

    func capturedPreparation(
        for pending: IOSPendingRecording,
        historyEnabled: Bool,
        transcriptionModel: String? = nil
    ) async throws -> IOSForegroundVoiceAcceptedOutputPreparation {
        let state = try IOSHistoryPolicyState(
            revision: 1,
            historyEnabled: historyEnabled,
            policyGeneration: 1
        )
        let receipt = try await IOSHistoryPolicyStore(
            journal: AcceptedDeliveryPolicyFakeJournal(state: state),
            capabilityOwnerIdentity: ownerIdentity
        ).confirm(expected: IOSHistoryPolicyExpectation(state: state))
        let historyWrite: IOSAcceptedOutputHistoryWrite? = if historyEnabled {
            try IOSAcceptedOutputHistoryWrite(
                policyGeneration: state.policyGeneration,
                transcriptionModel:
                    transcriptionModel ?? pending.transcriptionModel,
                transcriptionLanguageCode:
                    pending.transcriptionLanguageCode,
                durationMilliseconds: pending.durationMilliseconds
            )
        } else {
            nil
        }
        let capture = IOSAcceptedOutputHistoryCapture(
            testingPolicyReceipt: receipt,
            historyWrite: historyWrite
        )
        return try IOSForegroundVoiceAcceptedOutputPreparation(
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: pending.attemptID,
            transcriptID: try #require(pending.transcriptionID),
            rawAcceptedText: "captured accepted text",
            outputIntent: pending.outputIntent,
            keepLatestResult: true,
            historyMode: .captured(capture)
        )
    }

    func makeAdditionalFacade() -> IOSForegroundVoicePersistence {
        IOSForegroundVoicePersistence(
            operationGate: operationGate,
            pendingRecordingStore: pendingStore,
            deliveryStore: deliveryStore,
            state: state
        )
    }

    func makeRelaunchedFacade() -> IOSForegroundVoicePersistence {
        IOSForegroundVoicePersistence(
            operationGate: operationGate,
            pendingRecordingStore: pendingStore,
            deliveryStore: deliveryStore,
            state: IOSForegroundVoicePersistenceOperationState()
        )
    }

    func makeFreshDeliveryStoreFacade() -> IOSForegroundVoicePersistence {
        let freshDeliveryStore = IOSAcceptedOutputDeliveryStore(
            journal: deliveryJournal,
            now: { [clock] in clock.date },
            monotonicNowNanoseconds: { 0 },
            capabilityOwnerIdentity: ownerIdentity,
            operationGateIdentity: operationGate.identity
        )
        return IOSForegroundVoicePersistence(
            operationGate: operationGate,
            pendingRecordingStore: pendingStore,
            deliveryStore: freshDeliveryStore,
            state: IOSForegroundVoicePersistenceOperationState()
        )
    }
}

private final class ForegroundVoiceClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedDate: Date

    init(date: Date) {
        storedDate = date
    }

    var date: Date {
        get { lock.withLock { storedDate } }
        set { lock.withLock { storedDate = newValue } }
    }
}

private final class ForegroundVoiceExecutor:
    IOSPendingTranscriptionExecutor,
    @unchecked Sendable {
    private let lock = NSLock()
    private var storedCallCount = 0

    var callCount: Int { lock.withLock { storedCallCount } }

    func transcribe(
        recording: IOSPendingRecording,
        audio: IOSPendingTranscriptionAudio
    ) async throws -> String {
        _ = recording
        _ = audio
        lock.withLock { storedCallCount += 1 }
        return "provider result"
    }
}

private final class ForegroundVoiceCapturedHistoryClient:
    @unchecked Sendable {
    private let lock = NSLock()
    private var storedCallCount = 0

    var callCount: Int { lock.withLock { storedCallCount } }

    func accept(
        _ preparation: IOSAcceptedOutputDeliveryPreparation,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSAcceptedHistoryAcceptanceResult {
        lock.withLock { storedCallCount += 1 }
        let acceptance = try await deliveryStore.acceptForHistoryCoordinator(
            preparation,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
        return IOSAcceptedHistoryAcceptanceResult(
            deliveryRecord: acceptance.record,
            resolution: preparation.historyWrite == nil
                ? .notRequested
                : .pendingLocalRecovery
        )
    }
}

private final class ForegroundVoicePendingJournal:
    IOSPendingRecordingJournalStoring,
    @unchecked Sendable {
    private struct Failure {
        let error: IOSPendingRecordingError
        let commits: Bool
    }

    private let lock = NSLock()
    private var storedRecording: IOSPendingRecording?
    private var revision: UInt64 = 1
    private var nextReplaceFailure: Failure?
    private var nextRemoveFailure: Failure?
    private var nextAbsenceProofFailure: IOSPendingRecordingError?
    private var storedRemoveCallCount = 0
    private var storedOnSuccessfulMetadataRemoval:
        (@Sendable () -> Void)?

    var recording: IOSPendingRecording? {
        lock.withLock { storedRecording }
    }
    var removeCallCount: Int { lock.withLock { storedRemoveCallCount } }
    var onSuccessfulMetadataRemoval: (@Sendable () -> Void)? {
        get { lock.withLock { storedOnSuccessfulMetadataRemoval } }
        set { lock.withLock { storedOnSuccessfulMetadataRemoval = newValue } }
    }

    func failNextReplace(
        _ error: IOSPendingRecordingError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            nextReplaceFailure = Failure(
                error: error,
                commits: commitBeforeThrowing
            )
        }
    }

    func failNextRemove(
        _ error: IOSPendingRecordingError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            nextRemoveFailure = Failure(
                error: error,
                commits: commitBeforeThrowing
            )
        }
    }

    func failNextAbsenceProof(_ error: IOSPendingRecordingError) {
        lock.withLock { nextAbsenceProofFailure = error }
    }

    func seed(_ recording: IOSPendingRecording?) {
        lock.withLock {
            storedRecording = recording
            revision &+= 1
        }
    }

    func load() throws -> IOSPendingRecording? {
        lock.withLock { storedRecording }
    }

    func loadMetadataSnapshot(
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataSnapshot? {
        _ = authorization
        return lock.withLock {
            storedRecording.map {
                IOSPendingRecordingJournalMetadataSnapshot(
                    testingRecording: $0,
                    testingRevision: revision
                )
            }
        }
    }

    func create(_ recording: IOSPendingRecording) throws {
        try lock.withLock {
            guard storedRecording == nil else {
                throw IOSPendingRecordingError.pendingSlotOccupied
            }
            storedRecording = recording
            revision &+= 1
        }
    }

    func replace(
        _ recording: IOSPendingRecording,
        expected: IOSPendingRecording
    ) throws {
        try lock.withLock {
            guard storedRecording == expected else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
            if let failure = nextReplaceFailure {
                nextReplaceFailure = nil
                if failure.commits {
                    storedRecording = recording
                    revision &+= 1
                }
                throw failure.error
            }
            storedRecording = recording
            revision &+= 1
        }
    }

    func remove(expected: IOSPendingRecording) throws -> Bool {
        try lock.withLock {
            storedRemoveCallCount += 1
            guard let storedRecording else { return false }
            guard storedRecording == expected else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
            if let failure = nextRemoveFailure {
                nextRemoveFailure = nil
                if failure.commits {
                    self.storedRecording = nil
                    revision &+= 1
                }
                throw failure.error
            }
            self.storedRecording = nil
            revision &+= 1
            return true
        }
    }

    func removeMetadata(
        expected: IOSPendingRecordingJournalMetadataSnapshot,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence {
        _ = authorization
        let result: (
            IOSPendingRecordingJournalMetadataAbsenceEvidence,
            (@Sendable () -> Void)?
        ) = try lock.withLock {
            storedRemoveCallCount += 1
            guard let storedRecording else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
            let current = IOSPendingRecordingJournalMetadataSnapshot(
                testingRecording: storedRecording,
                testingRevision: revision
            )
            guard current == expected else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
            if let failure = nextRemoveFailure {
                nextRemoveFailure = nil
                if failure.commits {
                    self.storedRecording = nil
                    revision &+= 1
                }
                throw failure.error
            }
            self.storedRecording = nil
            revision &+= 1
            let callback = storedOnSuccessfulMetadataRemoval
            storedOnSuccessfulMetadataRemoval = nil
            return (
                IOSPendingRecordingJournalMetadataAbsenceEvidence(
                    testingRemoved: expected,
                    repositoryRoot: expectedRepositoryRoot
                        ?? IOSPersistenceRepositoryRootIdentity(
                            device: 1,
                            inode: 1
                        )
                ),
                callback
            )
        }
        result.1?()
        return result.0
    }

    func proveMetadataAbsent(
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence {
        _ = authorization
        return try lock.withLock {
            guard storedRecording == nil else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
            if let failure = nextAbsenceProofFailure {
                nextAbsenceProofFailure = nil
                throw failure
            }
            return IOSPendingRecordingJournalMetadataAbsenceEvidence(
                testingAlreadyAbsentRepositoryRoot: expectedRepositoryRoot
                    ?? IOSPersistenceRepositoryRootIdentity(
                        device: 1,
                        inode: 1
                    )
            )
        }
    }
}

private final class ForegroundVoiceAudioFileSystem:
    IOSPendingRecordingAudioFileSystem,
    @unchecked Sendable {
    private let lock = NSLock()
    private var present = false
    private var relativeIdentifier: String?
    private var byteCount: Int64 = 0
    private var durationMilliseconds: Int64 = 0
    private var storedFailNextRemove:
        IOSPendingRecordingAudioFileSystemError?

    var isPresent: Bool { lock.withLock { present } }
    var failNextRemove: IOSPendingRecordingAudioFileSystemError? {
        get { lock.withLock { storedFailNextRemove } }
        set { lock.withLock { storedFailNextRemove = newValue } }
    }

    func requireEmptyNamespace() async throws {
        guard !isPresent else {
            throw IOSPendingRecordingAudioFileSystemError.namespaceNotEmpty
        }
    }

    func validateProtectedAudioNamespace(
        _ inventory: IOSProtectedAudioNamespaceInventory
    ) async throws {
        _ = inventory
    }

    func reconcileProtectedAudioCleanup(
        using authorization:
            IOSPendingRecordingProtectedAudioCleanupAuthorization
    ) async throws -> IOSPendingRecordingProtectedAudioCleanupEvidence {
        IOSPendingRecordingProtectedAudioCleanupEvidence(
            testingAlreadyAbsent: authorization.cleanupAuthorization
        )
    }

    func reconcileAcceptedOutputAudioRemoval(
        using authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization
    ) async throws
        -> IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence {
        let removed = try await removePublishedAudioIfPresent(
            relativeIdentifier: authorization.audioRelativeIdentifier,
            attemptID: authorization.attemptID,
            expectedByteCount: authorization.byteCount
        )
        return IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence(
            testing: authorization,
            removed: removed
        )
    }

    func publishProtectedCopy(
        from source: AudioRecordingArtifact,
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat,
        durationMilliseconds: Int64
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        let identifier = IOSPendingRecordingStorageLocation
            .relativeAudioIdentifier(for: attemptID, format: format)
        lock.withLock {
            present = true
            relativeIdentifier = identifier
            byteCount = source.byteCount
            self.durationMilliseconds = durationMilliseconds
        }
        return ForegroundVoiceAudioLease(
            relativeIdentifier: identifier,
            durationMilliseconds: durationMilliseconds,
            byteCount: source.byteCount
        )
    }

    func publishProtectedCopy(
        from source: AudioRecordingArtifact,
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat,
        durationMilliseconds: Int64,
        inventory: IOSProtectedAudioNamespaceInventory
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        _ = inventory
        return try await publishProtectedCopy(
            from: source,
            attemptID: attemptID,
            format: format,
            durationMilliseconds: durationMilliseconds
        )
    }

    func validatePublishedAudio(
        relativeIdentifier: String,
        attemptID: UUID,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) async throws -> AudioRecordingArtifact {
        _ = attemptID
        let valid = lock.withLock {
            present
                && self.relativeIdentifier == relativeIdentifier
                && self.byteCount == byteCount
                && self.durationMilliseconds == durationMilliseconds
        }
        guard valid else {
            throw IOSPendingRecordingAudioFileSystemError
                .protectedAudioMissing
        }
        return AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/protected/audio.m4a"),
            duration: TimeInterval(durationMilliseconds) / 1_000,
            byteCount: byteCount
        )
    }

    func acquireValidatedPublishedAudio(
        relativeIdentifier: String,
        attemptID: UUID,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        _ = try await validatePublishedAudio(
            relativeIdentifier: relativeIdentifier,
            attemptID: attemptID,
            durationMilliseconds: durationMilliseconds,
            byteCount: byteCount
        )
        return ForegroundVoiceAudioLease(
            relativeIdentifier: relativeIdentifier,
            durationMilliseconds: durationMilliseconds,
            byteCount: byteCount
        )
    }

    func removePublishedAudioIfPresent(
        relativeIdentifier: String,
        attemptID: UUID,
        expectedByteCount: Int64
    ) async throws -> Bool {
        _ = attemptID
        return try lock.withLock {
            if let error = storedFailNextRemove {
                storedFailNextRemove = nil
                throw error
            }
            guard present else { return false }
            guard self.relativeIdentifier == relativeIdentifier,
                  byteCount == expectedByteCount else {
                throw IOSPendingRecordingAudioFileSystemError.sourceChanged
            }
            present = false
            return true
        }
    }
}

private final class ForegroundVoiceAudioLease:
    IOSPendingRecordingPublishedAudioLease,
    @unchecked Sendable {
    let relativeIdentifier: String
    let audioArtifact: AudioRecordingArtifact
    let durationMilliseconds: Int64

    init(
        relativeIdentifier: String,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) {
        self.relativeIdentifier = relativeIdentifier
        self.durationMilliseconds = durationMilliseconds
        audioArtifact = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/protected/audio.m4a"),
            duration: TimeInterval(durationMilliseconds) / 1_000,
            byteCount: byteCount
        )
    }

    func revalidate() async throws -> AudioRecordingArtifact {
        audioArtifact
    }

    func read(
        atOffset offset: Int64,
        maximumByteCount: Int
    ) async throws -> Data {
        let count = min(
            maximumByteCount,
            max(0, Int(audioArtifact.byteCount - offset))
        )
        return Data(repeating: 0x41, count: count)
    }

    func release() {}
}

private final class ForegroundVoiceDeliveryJournal:
    IOSAcceptedOutputDeliveryJournalStoring,
    @unchecked Sendable {
    private struct Failure {
        let error: IOSAcceptedOutputDeliveryError
        let commits: Bool
    }

    private let lock = NSLock()
    private var snapshot: IOSAcceptedOutputDeliveryJournalSnapshot?
    private var revision: UInt64 = 1
    private var nextCreateFailure: Failure?
    private var nextReplacementFailure: Failure?
    private var nextLoadFailure: IOSAcceptedOutputDeliveryError?
    private var storedCreateCallCount = 0
    private var storedReplacementRecords:
        [IOSAcceptedOutputDeliveryRecord] = []

    var removeError: IOSAcceptedOutputDeliveryError?
    var removeCommitsBeforeThrowing = false
    var confirmAbsenceError: IOSAcceptedOutputDeliveryError?
    var record: IOSAcceptedOutputDeliveryRecord? {
        lock.withLock { snapshot?.record }
    }
    var createCallCount: Int { lock.withLock { storedCreateCallCount } }
    var replacementCallCount: Int {
        lock.withLock { storedReplacementRecords.count }
    }
    var replacedWithDiscardedBeforeLatest: Bool {
        lock.withLock {
            guard storedReplacementRecords.count > 1 else { return false }
            return storedReplacementRecords.dropLast().contains(where: {
                $0.deliveryState == .discarded
            })
        }
    }

    func failNextCreate(
        _ error: IOSAcceptedOutputDeliveryError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            nextCreateFailure = Failure(
                error: error,
                commits: commitBeforeThrowing
            )
        }
    }

    func failNextReplace(
        _ error: IOSAcceptedOutputDeliveryError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            nextReplacementFailure = Failure(
                error: error,
                commits: commitBeforeThrowing
            )
        }
    }

    func failNextLoad(_ error: IOSAcceptedOutputDeliveryError) {
        lock.withLock { nextLoadFailure = error }
    }

    func removeCurrentRecordForTesting() {
        lock.withLock { snapshot = nil }
    }

    func installCurrentForTesting(
        _ record: IOSAcceptedOutputDeliveryRecord
    ) {
        lock.withLock { snapshot = makeSnapshot(record) }
    }

    func replaceCurrentForTesting(
        historyState: IOSAcceptedOutputHistoryWriteState? = nil,
        acceptedText replacementAcceptedText: String? = nil,
        attemptID replacementAttemptID: UUID? = nil,
        transcriptID replacementTranscriptID: UUID? = nil
    ) throws -> IOSAcceptedOutputDeliveryRecord {
        try lock.withLock {
            guard let current = snapshot?.record else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            let historyWrite: IOSAcceptedOutputHistoryWrite?
            if let historyState {
                guard let marker = current.historyWrite else {
                    throw IOSAcceptedOutputDeliveryError.invalidTransition
                }
                historyWrite = try marker.replacingState(historyState)
            } else {
                historyWrite = current.historyWrite
            }
            let replacement = try IOSAcceptedOutputDeliveryRecord(
                revision: current.revision + 1,
                deliveryID: current.deliveryID,
                sessionID: current.sessionID,
                attemptID: replacementAttemptID ?? current.attemptID,
                transcriptID:
                    replacementTranscriptID ?? current.transcriptID,
                failedRetryID: current.failedRetryID,
                acceptedText:
                    replacementAcceptedText ?? current.acceptedText,
                outputIntent: current.outputIntent,
                createdAt: current.createdAt,
                updatedAt: current.updatedAt,
                expiresAt: current.expiresAt,
                deliveryState: current.deliveryState,
                automaticInsertionPreferenceEnabled:
                    current.automaticInsertionPreferenceEnabled,
                keepLatestResult: current.keepLatestResult,
                publicationGeneration: current.publicationGeneration,
                historyWrite: historyWrite
            )
            snapshot = makeSnapshot(replacement)
            return replacement
        }
    }

    func load() throws -> IOSAcceptedOutputDeliveryJournalSnapshot? {
        try lock.withLock {
            if let nextLoadFailure {
                self.nextLoadFailure = nil
                throw nextLoadFailure
            }
            return snapshot
        }
    }

    func loadOpaque() throws -> IOSAcceptedOutputDeliveryOpaqueSnapshot? {
        lock.withLock {
            snapshot.map {
                IOSAcceptedOutputDeliveryOpaqueSnapshot(
                    fileRevision: $0.fileRevision
                )
            }
        }
    }

    func create(
        _ record: IOSAcceptedOutputDeliveryRecord
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        try lock.withLock {
            storedCreateCallCount += 1
            guard snapshot == nil else {
                throw IOSAcceptedOutputDeliveryError.slotOccupied
            }
            if let failure = nextCreateFailure {
                nextCreateFailure = nil
                if failure.commits {
                    snapshot = makeSnapshot(record)
                }
                throw failure.error
            }
            let created = makeSnapshot(record)
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
            storedReplacementRecords.append(record)
            if let failure = nextReplacementFailure {
                nextReplacementFailure = nil
                if failure.commits {
                    snapshot = makeSnapshot(record)
                }
                throw failure.error
            }
            let replacement = makeSnapshot(record)
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
            if let removeError {
                if removeCommitsBeforeThrowing {
                    snapshot = nil
                    removeCommitsBeforeThrowing = false
                }
                throw removeError
            }
            snapshot = nil
        }
    }

    func confirmCanonicalAbsence() throws {
        try lock.withLock {
            guard snapshot == nil else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            if let confirmAbsenceError {
                throw confirmAbsenceError
            }
        }
    }

    func removeOpaque(
        expected: IOSAcceptedOutputDeliveryOpaqueSnapshot
    ) throws {
        _ = expected
        lock.withLock { snapshot = nil }
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        _ = now
        return .empty
    }

    private func makeSnapshot(
        _ record: IOSAcceptedOutputDeliveryRecord
    ) -> IOSAcceptedOutputDeliveryJournalSnapshot {
        defer { revision &+= 1 }
        return IOSAcceptedOutputDeliveryJournalSnapshot(
            record: record,
            fileRevision: IOSStrictProtectedRecordFileRevision(
                testingToken: revision
            )
        )
    }
}
