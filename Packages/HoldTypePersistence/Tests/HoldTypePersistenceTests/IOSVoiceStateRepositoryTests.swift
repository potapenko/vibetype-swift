import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

@Suite(.serialized)
struct IOSVoiceStateRepositoryTests {
    @Test func missingRecordIsAnEmptySnapshot() async throws {
        let fileSystem = VoiceStateFileSystem()
        let repository = makeRepository(fileSystem: fileSystem)

        #expect(try await repository.load() == .empty)
        #expect(fileSystem.bytes == nil)
    }

    @Test func pendingAndLatestRoundTripThroughStrictWireRecord() async throws {
        let fileSystem = VoiceStateFileSystem()
        let repository = makeRepository(fileSystem: fileSystem)
        let pending = try makePending()

        _ = try await repository.installPending(pending)
        let processing = try await repository.beginProcessing(
            attemptID: pending.attemptID,
            operationID: IDs.operation,
            allowFailed: false
        )
        _ = try await repository.advanceProcessing(
            attemptID: pending.attemptID,
            operationID: IDs.operation,
            to: .postProcessing
        )
        _ = try await repository.advanceProcessing(
            attemptID: pending.attemptID,
            operationID: IDs.operation,
            to: .outputDelivery
        )
        let accepted = try await repository.commitAccepted(
            attemptID: pending.attemptID,
            resultID: IDs.result,
            text: "accepted text",
            createdAt: Dates.accepted
        )

        #expect(processing.attemptID == pending.attemptID)
        #expect(accepted.resultID == IDs.result)
        let relaunched = makeRepository(fileSystem: fileSystem)
        let snapshot = try await relaunched.load()
        #expect(
            snapshot.latest == (try IOSVoiceStateLatest(
                resultID: IDs.result,
                sourceAttemptID: IDs.attempt,
                text: "accepted text",
                createdAt: Dates.accepted
            ))
        )
        #expect(snapshot.pending?.status == .acceptedCleanup(accepted))
    }

    @Test func finalizedDurationIsStoredWithoutFiveMinuteClamping()
        async throws {
        for duration in [Int64(300_000), 302_000, 302_001] {
            let fileSystem = VoiceStateFileSystem()
            let repository = makeRepository(fileSystem: fileSystem)
            let pending = try makePending(durationMilliseconds: duration)

            _ = try await repository.installPending(pending)

            #expect(try await repository.load().pending?.durationMilliseconds
                == duration)
        }
    }

    @Test func unknownFinalizedDurationRoundTripsAndPromotesWithoutDataLoss()
        async throws {
        let fileSystem = VoiceStateFileSystem()
        let repository = makeRepository(fileSystem: fileSystem)
        let capture = try makeCapture()
        _ = try await repository.installCapture(capture)
        _ = try await repository.transitionCapture(
            attemptID: capture.attemptID,
            to: .finalizing
        )

        let completed = try await repository.completeCapture(
            attemptID: capture.attemptID,
            durationMilliseconds: 0,
            byteCount: 4_096
        )
        #expect(completed.durationMilliseconds == 0)
        #expect(
            try await makeRepository(fileSystem: fileSystem).load().capture?
                .durationMilliseconds == 0
        )

        let pending = try await repository.promoteCapture(
            attemptID: capture.attemptID,
            transcriptionConfiguration: .defaults,
            initialStatus: .failed
        )
        #expect(pending.durationMilliseconds == 0)
        #expect(pending.status == .failed)
        #expect(
            try await makeRepository(fileSystem: fileSystem).load().pending?
                .durationMilliseconds == 0
        )
    }

    @Test func sessionModesRoundTripFromCaptureThroughPending() async throws {
        let fileSystem = VoiceStateFileSystem()
        let repository = makeRepository(fileSystem: fileSystem)
        let capture = try makeCapture(
            draftInsertionMode: .append,
            forcesTextCorrection: true
        )
        _ = try await repository.installCapture(capture)
        _ = try await repository.transitionCapture(
            attemptID: capture.attemptID,
            to: .finalizing
        )
        _ = try await repository.completeCapture(
            attemptID: capture.attemptID,
            durationMilliseconds: 1_250,
            byteCount: 4_096
        )

        let pending = try await repository.promoteCapture(
            attemptID: capture.attemptID,
            transcriptionConfiguration: .defaults
        )

        #expect(pending.draftInsertionMode == .append)
        #expect(pending.forcesTextCorrection)
        let relaunched = try await makeRepository(
            fileSystem: fileSystem
        ).load()
        #expect(relaunched.pending?.draftInsertionMode == .append)
        #expect(relaunched.pending?.forcesTextCorrection == true)
    }

    @Test func savedFiveMinuteRetentionRoundTripsWithPending() async throws {
        let fileSystem = VoiceStateFileSystem()
        let repository = makeRepository(fileSystem: fileSystem)
        let capture = try makeCapture()
        _ = try await repository.installCapture(capture)
        _ = try await repository.transitionCapture(
            attemptID: capture.attemptID,
            to: .finalizing
        )
        _ = try await repository.completeCapture(
            attemptID: capture.attemptID,
            durationMilliseconds: 300_000,
            byteCount: 4_096
        )

        let pending = try await repository.promoteCapture(
            attemptID: capture.attemptID,
            transcriptionConfiguration: .defaults,
            acceptedAudioRetention: .savedFiveMinute
        )

        #expect(pending.acceptedAudioRetention == .savedFiveMinute)
        #expect(
            try await makeRepository(fileSystem: fileSystem).load().pending?
                .acceptedAudioRetention == .savedFiveMinute
        )
    }

    @Test func versionOnePendingMigratesWithLegacyAppendSemantics() async throws {
        let bytes = Data(
            """
            {"capture":null,"latest":null,"pending":{"attemptID":"AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA","audioRelativeIdentifier":"VoiceState/pending-v1-aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.m4a","createdAtMilliseconds":1700000000000,"updatedAtMilliseconds":1700000000000,"outputIntent":"standard","transcriptionModel":"gpt-4o-transcribe","transcriptionLanguageCode":"en","durationMilliseconds":1250,"byteCount":4096,"status":{"kind":"ready","stage":null,"operationID":null,"accepted":null}},"schemaVersion":1}
            """.utf8
        )
        let snapshot = try await makeRepository(
            fileSystem: VoiceStateFileSystem(bytes: bytes)
        ).load()

        #expect(snapshot.pending?.draftInsertionMode == .append)
        #expect(snapshot.pending?.forcesTextCorrection == false)
        #expect(
            snapshot.pending?.acceptedAudioRetention
                == .recordingCachePolicy
        )
    }

    @Test func versionTwoPendingMigratesToPolicyManagedAcceptedAudio()
        async throws {
        let bytes = Data(
            """
            {"capture":null,"latest":null,"pending":{"attemptID":"AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA","audioRelativeIdentifier":"VoiceState/pending-v1-aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.m4a","createdAtMilliseconds":1700000000000,"updatedAtMilliseconds":1700000000000,"outputIntent":"standard","draftInsertionMode":"replace","forcesTextCorrection":true,"transcriptionModel":"gpt-4o-transcribe","transcriptionLanguageCode":"en","durationMilliseconds":1250,"byteCount":4096,"status":{"kind":"ready","stage":null,"operationID":null,"accepted":null}},"schemaVersion":2}
            """.utf8
        )
        let snapshot = try await makeRepository(
            fileSystem: VoiceStateFileSystem(bytes: bytes)
        ).load()

        #expect(snapshot.pending?.draftInsertionMode == .replace)
        #expect(snapshot.pending?.forcesTextCorrection == true)
        #expect(
            snapshot.pending?.acceptedAudioRetention
                == .recordingCachePolicy
        )
    }

    @Test func onlyOnePendingSlotMayBeInstalled() async throws {
        let repository = makeRepository()
        _ = try await repository.installPending(try makePending())

        await #expect(
            throws: IOSVoiceStateRepositoryError.pendingSlotOccupied
        ) {
            _ = try await repository.installPending(
                try makePending(attemptID: IDs.otherAttempt)
            )
        }
    }

    @Test func captureRoundTripsAndExcludesThePendingSlot() async throws {
        let fileSystem = VoiceStateFileSystem()
        let repository = makeRepository(fileSystem: fileSystem)
        let capture = try makeCapture()

        _ = try await repository.installCapture(capture)

        #expect(try await makeRepository(fileSystem: fileSystem).load().capture == capture)
        await #expect(
            throws: IOSVoiceStateRepositoryError.pendingSlotOccupied
        ) {
            _ = try await repository.installPending(try makePending())
        }
        await #expect(
            throws: IOSVoiceStateRepositoryError.pendingSlotOccupied
        ) {
            _ = try await repository.installCapture(
                try makeCapture(attemptID: IDs.otherAttempt)
            )
        }
    }

    @Test func captureRoundTripsItsFrozenRecordingDurationLimit() async throws {
        for minutes in [1, 15] {
            let fileSystem = VoiceStateFileSystem()
            let repository = makeRepository(fileSystem: fileSystem)
            let capture = try makeCapture(
                recordingDurationLimit: RecordingDurationLimit(minutes: minutes)
            )

            _ = try await repository.installCapture(capture)

            let relaunched = try await makeRepository(
                fileSystem: fileSystem
            ).load()
            #expect(relaunched.capture?.recordingDurationLimit.minutes == minutes)
        }
    }

    @Test func versionFourCaptureMigratesToTheFiveMinuteDefault() async throws {
        let bytes = Data(
            """
            {"capture":{"attemptID":"AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA","audioRelativeIdentifier":"VoiceState/pending-v1-aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.m4a","createdAtMilliseconds":1700000000000,"outputIntent":"standard","draftInsertionMode":"replace","forcesTextCorrection":false,"phase":"recording","durationMilliseconds":null,"byteCount":null},"latest":null,"pending":null,"schemaVersion":4}
            """.utf8
        )

        let snapshot = try await makeRepository(
            fileSystem: VoiceStateFileSystem(bytes: bytes)
        ).load()

        #expect(snapshot.capture?.recordingDurationLimit == .default)
    }

    @Test func currentCaptureSchemaRejectsAnInvalidRecordingDurationLimit()
        async {
        let bytes = Data(
            """
            {"capture":{"attemptID":"AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA","audioRelativeIdentifier":"VoiceState/pending-v1-aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.m4a","createdAtMilliseconds":1700000000000,"outputIntent":"standard","draftInsertionMode":"replace","forcesTextCorrection":false,"recordingDurationLimitMinutes":16,"phase":"recording","durationMilliseconds":null,"byteCount":null},"latest":null,"pending":null,"schemaVersion":5}
            """.utf8
        )

        await #expect(throws: IOSVoiceStateRepositoryError.invalidRecord) {
            _ = try await makeRepository(
                fileSystem: VoiceStateFileSystem(bytes: bytes)
            ).load()
        }
    }

    @Test func completedCapturePromotesAtomicallyWithoutChangingAudioIdentity() async throws {
        let fileSystem = VoiceStateFileSystem()
        let repository = makeRepository(fileSystem: fileSystem)
        let capture = try makeCapture()
        _ = try await repository.installCapture(capture)
        _ = try await repository.transitionCapture(
            attemptID: capture.attemptID,
            to: .finalizing
        )
        let completed = try await repository.completeCapture(
            attemptID: capture.attemptID,
            durationMilliseconds: 1_250,
            byteCount: 4_096
        )
        let writesBeforePromotion = fileSystem.writeCount

        let pending = try await repository.promoteCapture(
            attemptID: capture.attemptID,
            transcriptionConfiguration: TranscriptionConfiguration(
                language: .english
            )
        )

        #expect(completed.phase == .completed)
        #expect(fileSystem.writeCount == writesBeforePromotion + 1)
        #expect(pending.audioRelativeIdentifier == capture.audioRelativeIdentifier)
        #expect(pending.transcriptionLanguageCode == "en")
        #expect(pending.status == .ready)
        let snapshot = try await repository.load()
        #expect(snapshot.capture == nil)
        #expect(snapshot.pending == pending)
    }

    @Test func captureTransitionsRejectStaleAndIncompletePromotion() async throws {
        let repository = makeRepository()
        let capture = try makeCapture()
        _ = try await repository.installCapture(capture)

        await #expect(throws: IOSVoiceStateRepositoryError.stalePending) {
            _ = try await repository.transitionCapture(
                attemptID: IDs.otherAttempt,
                to: .finalizing
            )
        }
        await #expect(throws: IOSVoiceStateRepositoryError.invalidTransition) {
            _ = try await repository.promoteCapture(
                attemptID: capture.attemptID,
                transcriptionConfiguration: .defaults
            )
        }
        _ = try await repository.transitionCapture(
            attemptID: capture.attemptID,
            to: .finalizing
        )
        await #expect(throws: IOSVoiceStateRepositoryError.invalidTransition) {
            _ = try await repository.transitionCapture(
                attemptID: capture.attemptID,
                to: .recording
            )
        }
    }

    @Test func invalidPromotionLeavesCompletedCaptureUnchanged() async throws {
        let fileSystem = VoiceStateFileSystem()
        let repository = makeRepository(fileSystem: fileSystem)
        let capture = try makeCapture()
        _ = try await repository.installCapture(capture)
        _ = try await repository.transitionCapture(
            attemptID: capture.attemptID,
            to: .finalizing
        )
        _ = try await repository.completeCapture(
            attemptID: capture.attemptID,
            durationMilliseconds: 1_250,
            byteCount: 4_096
        )
        let bytes = fileSystem.bytes

        await #expect(throws: IOSVoiceStateRepositoryError.invalidTransition) {
            _ = try await repository.promoteCapture(
                attemptID: capture.attemptID,
                transcriptionConfiguration: TranscriptionConfiguration(
                    language: .custom,
                    customLanguageCode: "invalid-code"
                )
            )
        }

        #expect(fileSystem.bytes == bytes)
        #expect(try await repository.load().capture?.phase == .completed)
        #expect(try await repository.load().pending == nil)
    }

    @Test func initialAndRetryProcessingHaveDistinctAdmission() async throws {
        let repository = makeRepository()
        let pending = try makePending()
        _ = try await repository.installPending(pending)

        await #expect(throws: IOSVoiceStateRepositoryError.invalidTransition) {
            _ = try await repository.beginProcessing(
                attemptID: pending.attemptID,
                operationID: IDs.operation,
                allowFailed: true
            )
        }
        _ = try await repository.beginProcessing(
            attemptID: pending.attemptID,
            operationID: IDs.operation,
            allowFailed: false
        )
        _ = try await repository.markFailed(attemptID: pending.attemptID)
        await #expect(throws: IOSVoiceStateRepositoryError.invalidTransition) {
            _ = try await repository.beginProcessing(
                attemptID: pending.attemptID,
                operationID: IDs.otherOperation,
                allowFailed: false
            )
        }
        let retry = try await repository.beginProcessing(
            attemptID: pending.attemptID,
            operationID: IDs.otherOperation,
            allowFailed: true
        )
        #expect(
            retry.status == .processing(
                .transcription,
                operationID: IDs.otherOperation
            )
        )
    }

    @Test func retryAtomicallyUsesCurrentTranscriptionSettings() async throws {
        let repository = makeRepository()
        let pending = try makePending()
        _ = try await repository.installPending(pending)
        _ = try await repository.markFailed(attemptID: pending.attemptID)

        let retry = try await repository.beginRetry(
            attemptID: pending.attemptID,
            operationID: IDs.otherOperation,
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "new-model",
                language: .russian
            )
        )

        #expect(retry.transcriptionModel == "new-model")
        #expect(retry.transcriptionLanguageCode == "ru")
        #expect(
            retry.status == .processing(
                .transcription,
                operationID: IDs.otherOperation
            )
        )
    }

    @Test func acceptedTranscriptCheckpointSurvivesRelaunchAndBlocksAudioRetry()
        async throws {
        let fileSystem = VoiceStateFileSystem()
        let repository = makeRepository(fileSystem: fileSystem)
        let pending = try makePending(
            durationMilliseconds: 300_000,
            acceptedAudioRetention: .savedFiveMinute
        )
        _ = try await repository.installPending(pending)
        _ = try await repository.beginProcessing(
            attemptID: pending.attemptID,
            operationID: IDs.operation,
            allowFailed: false
        )

        let checkpointed = try await repository.checkpointTranscription(
            attemptID: pending.attemptID,
            operationID: IDs.operation,
            text: "Accepted provider transcript"
        )

        #expect(
            checkpointed.status == .processing(
                .postProcessing,
                operationID: IDs.operation
            )
        )
        #expect(
            checkpointed.transcriptionCheckpoint
                == (try IOSVoiceStateTranscriptionCheckpoint(
                    operationID: IDs.operation,
                    acceptedTranscript: "Accepted provider transcript"
                ))
        )
        #expect(checkpointed.durationMilliseconds == 300_000)
        #expect(checkpointed.acceptedAudioRetention == .savedFiveMinute)

        let relaunched = makeRepository(fileSystem: fileSystem)
        guard let failed = try await relaunched.reconcileAfterLaunch().pending
        else {
            Issue.record("Expected durable failed Pending after relaunch.")
            return
        }
        #expect(failed.status == .failed)
        #expect(failed.transcriptionCheckpoint
            == checkpointed.transcriptionCheckpoint)
        await #expect(throws: IOSVoiceStateRepositoryError.invalidTransition) {
            _ = try await relaunched.beginRetry(
                attemptID: pending.attemptID,
                operationID: IDs.otherOperation,
                transcriptionConfiguration: .defaults
            )
        }

        let resumed = try await relaunched.beginPostProcessingRetry(
            attemptID: pending.attemptID,
            operationID: IDs.otherOperation
        )
        #expect(
            resumed.status == .processing(
                .postProcessing,
                operationID: IDs.otherOperation
            )
        )
        #expect(resumed.transcriptionCheckpoint
            == checkpointed.transcriptionCheckpoint)
        #expect(resumed.durationMilliseconds == 300_000)
        #expect(resumed.acceptedAudioRetention == .savedFiveMinute)
    }

    @Test func acceptedCommitAtomicallyPublishesLatestAndCleanupOwner() async throws {
        let fileSystem = VoiceStateFileSystem()
        let repository = makeRepository(fileSystem: fileSystem)
        try await moveToOutputDelivery(repository)
        let writesBeforeCommit = fileSystem.writeCount

        let accepted = try await repository.commitAccepted(
            attemptID: IDs.attempt,
            resultID: IDs.result,
            text: "accepted text",
            createdAt: Dates.accepted
        )

        #expect(fileSystem.writeCount == writesBeforeCommit + 1)
        let snapshot = try await repository.load()
        #expect(snapshot.latest?.resultID == IDs.result)
        #expect(snapshot.pending?.status == .acceptedCleanup(accepted))

        let duplicate = try await repository.commitAccepted(
            attemptID: IDs.attempt,
            resultID: IDs.result,
            text: "accepted text",
            createdAt: Dates.accepted
        )
        #expect(duplicate == accepted)
        #expect(fileSystem.writeCount == writesBeforeCommit + 1)
    }

    @Test func failedAcceptedCommitPreservesThePriorConfirmedState() async throws {
        let fileSystem = VoiceStateFileSystem()
        let repository = makeRepository(fileSystem: fileSystem)
        try await moveToOutputDelivery(repository)
        let priorBytes = fileSystem.bytes
        fileSystem.failNextWrite = true

        await #expect(throws: IOSVoiceStateRepositoryError.writeFailed) {
            _ = try await repository.commitAccepted(
                attemptID: IDs.attempt,
                resultID: IDs.result,
                text: "accepted text",
                createdAt: Dates.accepted
            )
        }

        #expect(fileSystem.bytes == priorBytes)
        let snapshot = try await repository.load()
        #expect(snapshot.latest == nil)
        #expect(
            snapshot.pending?.status == .processing(
                .outputDelivery,
                operationID: IDs.operation
            )
        )
    }

    @Test func exactCleanupAndDiscardNeverChangeLatest() async throws {
        let repository = makeRepository()
        try await moveToOutputDelivery(repository)
        _ = try await repository.commitAccepted(
            attemptID: IDs.attempt,
            resultID: IDs.result,
            text: "accepted text",
            createdAt: Dates.accepted
        )

        await #expect(throws: IOSVoiceStateRepositoryError.stalePending) {
            _ = try await repository.finishAcceptedCleanup(
                attemptID: IDs.otherAttempt,
                resultID: IDs.result
            )
        }
        _ = try await repository.finishAcceptedCleanup(
            attemptID: IDs.attempt,
            resultID: IDs.result
        )
        let afterCleanup = try await repository.load()
        #expect(afterCleanup.pending == nil)
        #expect(afterCleanup.latest?.resultID == IDs.result)

        _ = try await repository.installPending(
            try makePending(attemptID: IDs.otherAttempt)
        )
        _ = try await repository.discardPending(
            attemptID: IDs.otherAttempt
        )
        let afterDiscard = try await repository.load()
        #expect(afterDiscard.pending == nil)
        #expect(afterDiscard.latest?.resultID == IDs.result)
    }

    @Test func relaunchBlocksReplayForLostTranscribingDispatch() async throws {
        let fileSystem = VoiceStateFileSystem()
        let repository = makeRepository(fileSystem: fileSystem)
        _ = try await repository.installPending(try makePending())
        _ = try await repository.beginProcessing(
            attemptID: IDs.attempt,
            operationID: IDs.operation,
            allowFailed: false
        )
        let writesBeforeRelaunch = fileSystem.writeCount

        let relaunched = makeRepository(fileSystem: fileSystem)
        let reconciled = try await relaunched.reconcileAfterLaunch()

        #expect(reconciled.pending?.status == .failed)
        #expect(reconciled.pending?.transcriptionReplayBlocked == true)
        #expect(reconciled.pending?.transcriptionCheckpoint == nil)
        #expect(reconciled.latest == nil)
        #expect(fileSystem.writeCount == writesBeforeRelaunch + 1)
        #expect(try await relaunched.reconcileAfterLaunch() == reconciled)
        await #expect(throws: IOSVoiceStateRepositoryError.invalidTransition) {
            _ = try await relaunched.beginRetry(
                attemptID: IDs.attempt,
                operationID: IDs.otherOperation,
                transcriptionConfiguration: .defaults
            )
        }
    }

    @Test func acceptedCleanupSurvivesRelaunchWithoutBeingDowngraded() async throws {
        let fileSystem = VoiceStateFileSystem()
        let repository = makeRepository(fileSystem: fileSystem)
        try await moveToOutputDelivery(repository)
        _ = try await repository.commitAccepted(
            attemptID: IDs.attempt,
            resultID: IDs.result,
            text: "accepted text",
            createdAt: Dates.accepted
        )
        let bytes = fileSystem.bytes

        let relaunched = makeRepository(fileSystem: fileSystem)
        let snapshot = try await relaunched.reconcileAfterLaunch()

        #expect(snapshot.latest?.resultID == IDs.result)
        #expect(fileSystem.bytes == bytes)
    }

    @Test func corruptFutureOversizedAndUnavailableDataFailClosed() async throws {
        for (bytes, error) in [
            (Data("not-json".utf8), IOSVoiceStateRepositoryError.malformedData),
            (
                Data(
                    "{\"capture\":null,\"latest\":null,\"pending\":null,\"schemaVersion\":6}"
                        .utf8
                ),
                IOSVoiceStateRepositoryError.unsupportedSchemaVersion
            ),
            (
                Data(
                    "{\"capture\":null,\"extra\":1,\"latest\":null,\"pending\":null,\"schemaVersion\":1}"
                        .utf8
                ),
                IOSVoiceStateRepositoryError.invalidRecord
            ),
        ] {
            let fileSystem = VoiceStateFileSystem(bytes: bytes)
            let repository = makeRepository(fileSystem: fileSystem)
            await #expect(throws: error) {
                _ = try await repository.load()
            }
            #expect(fileSystem.bytes == bytes)
        }

        let oversized = VoiceStateFileSystem(
            bytes: Data(repeating: 0, count: IOSVoiceStateRepository.maximumByteCount + 1)
        )
        await #expect(throws: IOSVoiceStateRepositoryError.sourceTooLarge) {
            _ = try await makeRepository(fileSystem: oversized).load()
        }

        let unavailable = VoiceStateFileSystem()
        unavailable.failReads = true
        await #expect(throws: IOSVoiceStateRepositoryError.readFailed) {
            _ = try await makeRepository(fileSystem: unavailable).load()
        }
    }

    @Test func concurrentInstallSerializesToOneWinner() async throws {
        let repository = makeRepository()
        let results = await withTaskGroup(
            of: Result<UUID, IOSVoiceStateRepositoryError>.self
        ) { group in
            for identifier in [IDs.attempt, IDs.otherAttempt] {
                group.addTask {
                    do {
                        _ = try await repository.installPending(
                            try makePending(attemptID: identifier)
                        )
                        return .success(identifier)
                    } catch let error as IOSVoiceStateRepositoryError {
                        return .failure(error)
                    } catch {
                        return .failure(.writeFailed)
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        #expect(results.filter { if case .success = $0 { true } else { false } }.count == 1)
        #expect(
            results.contains {
                if case .failure(.pendingSlotOccupied) = $0 { true }
                else { false }
            }
        )
    }

    private func makeRepository(
        fileSystem: VoiceStateFileSystem = VoiceStateFileSystem()
    ) -> IOSVoiceStateRepository {
        IOSVoiceStateRepository(
            fileURL: URL(fileURLWithPath: "/tmp/ios-v1-voice-state.json"),
            fileSystem: fileSystem,
            now: { Dates.updated }
        )
    }

    private func moveToOutputDelivery(
        _ repository: IOSVoiceStateRepository
    ) async throws {
        _ = try await repository.installPending(try makePending())
        _ = try await repository.beginProcessing(
            attemptID: IDs.attempt,
            operationID: IDs.operation,
            allowFailed: false
        )
        _ = try await repository.advanceProcessing(
            attemptID: IDs.attempt,
            operationID: IDs.operation,
            to: .postProcessing
        )
        _ = try await repository.advanceProcessing(
            attemptID: IDs.attempt,
            operationID: IDs.operation,
            to: .outputDelivery
        )
    }
}

private func makeCapture(
    attemptID: UUID = IDs.attempt,
    draftInsertionMode: IOSVoiceDraftInsertionMode = .replace,
    forcesTextCorrection: Bool = false,
    recordingDurationLimit: RecordingDurationLimit = .default
) throws -> IOSVoiceStateCapture {
    try IOSVoiceStateCapture(
        attemptID: attemptID,
        audioRelativeIdentifier:
            IOSVoiceStateStorageLocation.relativeAudioIdentifier(
                for: attemptID
            ),
        createdAt: Dates.created,
        outputIntent: .standard,
        draftInsertionMode: draftInsertionMode,
        forcesTextCorrection: forcesTextCorrection,
        recordingDurationLimit: recordingDurationLimit,
        phase: .recording
    )
}

private func makePending(
    attemptID: UUID = IDs.attempt,
    durationMilliseconds: Int64 = 1_250,
    acceptedAudioRetention: IOSAcceptedAudioRetention = .recordingCachePolicy
) throws -> IOSVoiceStatePending {
    try IOSVoiceStatePending(
        attemptID: attemptID,
        audioRelativeIdentifier:
            IOSVoiceStateStorageLocation.relativeAudioIdentifier(
                for: attemptID
            ),
        createdAt: Dates.created,
        updatedAt: Dates.created,
        outputIntent: .standard,
        transcriptionModel: "gpt-4o-transcribe",
        transcriptionLanguageCode: "en",
        durationMilliseconds: durationMilliseconds,
        byteCount: 4_096,
        acceptedAudioRetention: acceptedAudioRetention,
        status: .ready
    )
}

private enum IDs {
    static let attempt = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
    static let otherAttempt = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
    static let operation = UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!
    static let otherOperation = UUID(uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!
    static let result = UUID(uuidString: "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE")!
    static let otherResult = UUID(uuidString: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF")!
}

private enum Dates {
    static let created = Date(timeIntervalSince1970: 1_700_000_000)
    static let updated = Date(timeIntervalSince1970: 1_700_000_001)
    static let accepted = Date(timeIntervalSince1970: 1_700_000_002)
}

private final class VoiceStateFileSystem:
    ProtectedAtomicMetadataFileSystem,
    @unchecked Sendable {
    private let lock = NSLock()
    private var storedBytes: Data?
    private var storedWriteCount = 0
    var failReads = false
    var failNextWrite = false

    init(bytes: Data? = nil) {
        storedBytes = bytes
    }

    var bytes: Data? { lock.withLock { storedBytes } }
    var writeCount: Int { lock.withLock { storedWriteCount } }

    func readFileIfPresent(
        at _: URL,
        policy: ProtectedAtomicMetadataFilePolicy
    ) throws -> Data? {
        try lock.withLock {
            if failReads {
                throw ProtectedAtomicMetadataFileSystemError.readFailed
            }
            if let storedBytes, storedBytes.count > policy.maximumByteCount {
                throw ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded
            }
            return storedBytes
        }
    }

    func replaceFileAtomically(
        at _: URL,
        with data: Data,
        policy: ProtectedAtomicMetadataFilePolicy
    ) throws {
        try lock.withLock {
            if failNextWrite {
                failNextWrite = false
                throw ProtectedAtomicMetadataFileSystemError.writeFailed
            }
            guard data.count <= policy.maximumByteCount else {
                throw ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded
            }
            storedBytes = data
            storedWriteCount += 1
        }
    }

    func removeFileIfPresent(at _: URL) throws {
        lock.withLock { storedBytes = nil }
    }
}
