import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSPendingRecordingStoreTests {
    @Test func preparePublishesAndRevalidatesAudioAroundJournalCommit() async throws {
        let fixture = StoreFixture()

        let recording = try await fixture.store.prepare(fixture.preparation())

        #expect(recording.phase == .readyForTranscription)
        #expect(recording.transcriptionID == nil)
        #expect(fixture.journal.recording == recording)
        #expect(
            fixture.events.values == [
                "audio.namespace.empty",
                "audio.publish",
                "audio.lease.revalidate",
                "journal.create",
                "audio.lease.revalidate",
                "audio.lease.release",
            ]
        )
        #expect(fixture.audio.published)
    }

    @Test func journalFailurePreservesPublishedAudioAndReleasesItsCreatorLock() async {
        let fixture = StoreFixture()
        fixture.journal.createError = .journalWriteFailed

        await #expect(throws: IOSPendingRecordingError.journalWriteFailed) {
            _ = try await fixture.store.prepare(fixture.preparation())
        }

        #expect(fixture.audio.published)
        #expect(fixture.audio.leaseReleaseCount == 1)
        #expect(fixture.journal.recording == nil)
        #expect(!fixture.events.values.contains("audio.remove"))
    }

    @Test func uncertainBeginCommitCannotMintProviderAuthority() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        fixture.events.reset()
        fixture.journal.replaceError = .journalCommitUncertain
        fixture.journal.replaceCommitsBeforeError = true
        let transcriptionID = UUID()

        await #expect(
            throws: IOSPendingRecordingError.journalCommitUncertain
        ) {
            _ = try await fixture.store.beginTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: prepared),
                transcriptionID: transcriptionID
            )
        }

        let visibleCommit = try #require(fixture.journal.recording)
        #expect(visibleCommit.phase == .transcribing)
        #expect(visibleCommit.transcriptionID == transcriptionID)
        #expect(
            fixture.events.values == [
                "audio.validate",
                "journal.replace",
            ]
        )

        fixture.journal.replaceError = nil
        fixture.journal.replaceCommitsBeforeError = false
        let recovered = try await fixture.makeStore(
            destinationInspector: FakePendingDestinationInspector()
        ).recoverAfterProcessLoss(
            expected: IOSPendingRecordingCASExpectation(recording: visibleCommit)
        )
        #expect(recovered.phase == .awaitingRecovery)
        #expect(recovered.transcriptionID == nil)
    }

    @Test func beginCommitsUUIDBeforeReturningOneOneShotAuthorization() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        fixture.events.reset()
        let transcriptionID = UUID()

        let handoff = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: transcriptionID
        )

        let committed = try #require(fixture.journal.recording)
        #expect(committed.phase == .transcribing)
        #expect(committed.transcriptionID == transcriptionID)
        #expect(
            fixture.events.values == [
                "audio.validate",
                "journal.replace",
                "audio.validate",
            ]
        )
        let executor = CapturingPendingTranscriptionExecutor()
        #expect(try await handoff.execute(using: executor) == "transcript")
        #expect(executor.recording == committed)
        await #expect(
            throws: IOSPendingRecordingError.dispatchAlreadyCommitted
        ) {
            _ = try await handoff.execute(using: executor)
        }

        await #expect(throws: IOSPendingRecordingError.dispatchAlreadyCommitted) {
            _ = try await fixture.store.beginTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: committed),
                transcriptionID: transcriptionID
            )
        }
    }

    @Test func explicitRetryUsesFreshCompactConfigurationAndKeepsAttemptOwnership() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(
            fixture.preparation(initialState: .awaitingRecovery)
        )
        let transcriptionID = UUID()

        let handoff = try await fixture.store.retryTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: transcriptionID,
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "retry-model",
                language: .japanese,
                freeformPrompt: "not durable"
            )
        )

        let executor = CapturingPendingTranscriptionExecutor()
        _ = try await handoff.execute(using: executor)
        let recording = try #require(executor.recording)
        #expect(recording.attemptID == prepared.attemptID)
        #expect(recording.createdAt == prepared.createdAt)
        #expect(recording.outputIntent == prepared.outputIntent)
        #expect(recording.durationMilliseconds == prepared.durationMilliseconds)
        #expect(recording.byteCount == prepared.byteCount)
        #expect(recording.transcriptionID == transcriptionID)
        #expect(recording.transcriptionModel == "retry-model")
        #expect(recording.transcriptionLanguageCode == "ja")
    }

    @Test func postcommitHandoffFailureClearsDispatchIdentityBeforeReturning() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        fixture.events.reset()
        fixture.audio.validateError = .protectedAudioInvalid
        fixture.audio.validateErrorCallNumber = 2

        await #expect(throws: IOSPendingRecordingError.linkedAudioInvalid) {
            _ = try await fixture.store.beginTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: prepared),
                transcriptionID: UUID()
            )
        }

        let recovered = try #require(fixture.journal.recording)
        #expect(recovered.phase == .awaitingRecovery)
        #expect(recovered.transcriptionID == nil)
        #expect(
            fixture.events.values == [
                "audio.validate",
                "journal.replace",
                "audio.validate",
                "journal.replace",
            ]
        )
    }

    @Test func retryRejectsRetiredIdentityAndInvalidCurrentConfiguration() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let retiredID = UUID()
        _ = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: retiredID
        )
        let transcribing = try #require(fixture.journal.recording)
        let recovery = try await fixture.store.markAwaitingRecovery(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )

        await #expect(throws: IOSPendingRecordingError.invalidTransition) {
            _ = try await fixture.store.retryTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: recovery),
                transcriptionID: retiredID,
                transcriptionConfiguration: .defaults
            )
        }
        await #expect(
            throws: IOSPendingRecordingError.invalidTranscriptionConfiguration
        ) {
            _ = try await fixture.store.retryTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: recovery),
                transcriptionID: UUID(),
                transcriptionConfiguration: TranscriptionConfiguration(
                    language: .custom,
                    customLanguageCode: "invalid-language"
                )
            )
        }
        #expect(fixture.journal.recording == recovery)

        let freshID = UUID()
        let handoff = try await fixture.store.retryTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: recovery),
            transcriptionID: freshID,
            transcriptionConfiguration: .defaults
        )
        let executor = CapturingPendingTranscriptionExecutor()
        _ = try await handoff.execute(using: executor)
        #expect(executor.recording?.transcriptionID == freshID)
    }

    @Test func failedPostcommitCompensationKeepsAuthorityBlockedUntilRecovery() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        fixture.audio.validateError = .protectedAudioInvalid
        fixture.audio.validateErrorCallNumber = 2
        fixture.journal.replaceError = .journalWriteFailed
        fixture.journal.replaceErrorCallNumber = 2

        await #expect(throws: IOSPendingRecordingError.journalWriteFailed) {
            _ = try await fixture.store.beginTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: prepared),
                transcriptionID: UUID()
            )
        }

        let stranded = try #require(fixture.journal.recording)
        #expect(stranded.phase == .transcribing)
        #expect(stranded.transcriptionID != nil)
        fixture.journal.replaceError = nil
        let recovered = try await fixture.store.markAwaitingRecovery(
            expected: IOSPendingRecordingCASExpectation(recording: stranded)
        )
        #expect(recovered.phase == .awaitingRecovery)
        #expect(recovered.transcriptionID == nil)
    }

    @Test func transitionsUseExactCASAndClearLateResultIdentityBeforeRecovery() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let transcriptionID = UUID()
        _ = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: transcriptionID
        )
        let transcribing = try #require(fixture.journal.recording)

        let postProcessing = try await fixture.store.markPostProcessing(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )
        await #expect(throws: IOSPendingRecordingError.compareAndSwapFailed) {
            _ = try await fixture.store.markOutputDelivery(
                expected: IOSPendingRecordingCASExpectation(recording: transcribing)
            )
        }

        let recovery = try await fixture.store.markAwaitingRecovery(
            expected: IOSPendingRecordingCASExpectation(recording: postProcessing)
        )
        #expect(recovery.phase == .awaitingRecovery)
        #expect(recovery.transcriptionID == nil)
        await #expect(throws: IOSPendingRecordingError.compareAndSwapFailed) {
            _ = try await fixture.store.markOutputDelivery(
                expected: IOSPendingRecordingCASExpectation(recording: postProcessing)
            )
        }
    }

    @Test func recoveryRevokesAnUnconsumedHandoffBeforeRetry() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let handoff = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)

        let recovery = try await fixture.store.markAwaitingRecovery(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )

        await #expect(
            throws: IOSPendingRecordingError.dispatchAlreadyCommitted
        ) {
            _ = try await handoff.execute(
                using: CapturingPendingTranscriptionExecutor()
            )
        }
        let retryHandoff = try await fixture.store.retryTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: recovery),
            transcriptionID: UUID(),
            transcriptionConfiguration: .defaults
        )
        #expect(
            try await retryHandoff.execute(
                using: CapturingPendingTranscriptionExecutor()
            ) == "transcript"
        )
    }

    @Test func processingCancellationCancelsRegisteredExecutionBeforeRecovery() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let handoff = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)
        let probe = PendingExecutionProbe()
        let executor = CancellablePendingTranscriptionExecutor(probe: probe)
        let execution = Task {
            try await handoff.execute(using: executor)
        }
        #expect(probe.waitUntilStarted())

        let recovery = try await fixture.store.markAwaitingRecovery(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )

        #expect(recovery.phase == .awaitingRecovery)
        #expect(probe.waitUntilCancelled())
        switch await execution.result {
        case .success:
            Issue.record("Expected registered execution cancellation")
        case .failure(let error):
            #expect(error is CancellationError)
        }
        await #expect(
            throws: IOSPendingRecordingError.dispatchAlreadyCommitted
        ) {
            _ = try await handoff.execute(using: executor)
        }
    }

    @Test func cancelledNoncooperativeLateSuccessIsRejected() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let handoff = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)
        let executor = NoncooperativePendingTranscriptionExecutor()
        let execution = Task {
            try await handoff.execute(using: executor)
        }
        #expect(executor.waitUntilStarted())
        defer { executor.release() }

        _ = try await fixture.store.markAwaitingRecovery(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )
        executor.release()

        switch await execution.result {
        case .success:
            Issue.record("Cancelled late provider success must not escape")
        case .failure(let error):
            #expect(error is CancellationError)
        }
    }

    @Test func failedRecoveryWriteStillPermanentlyRevokesOldHandoff() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let handoff = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)
        fixture.journal.replaceError = .journalWriteFailed

        await #expect(throws: IOSPendingRecordingError.journalWriteFailed) {
            _ = try await fixture.store.markAwaitingRecovery(
                expected: IOSPendingRecordingCASExpectation(
                    recording: transcribing
                )
            )
        }

        #expect(fixture.journal.recording == transcribing)
        await #expect(
            throws: IOSPendingRecordingError.dispatchAlreadyCommitted
        ) {
            _ = try await handoff.execute(
                using: CapturingPendingTranscriptionExecutor()
            )
        }
        fixture.journal.replaceError = nil
        #expect(
            try await fixture.store.markAwaitingRecovery(
                expected: IOSPendingRecordingCASExpectation(
                    recording: transcribing
                )
            ).phase == .awaitingRecovery
        )
    }

    @Test func samePhaseAdvanceAlwaysConfirmsDurabilityAcrossStoreActors() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        _ = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)
        fixture.journal.replaceError = .journalCommitUncertain
        fixture.journal.replaceCommitsBeforeError = true

        await #expect(
            throws: IOSPendingRecordingError.journalCommitUncertain
        ) {
            _ = try await fixture.store.markPostProcessing(
                expected: IOSPendingRecordingCASExpectation(
                    recording: transcribing
                )
            )
        }
        let visibleCommit = try #require(fixture.journal.recording)
        #expect(visibleCommit.phase == .postProcessing)

        fixture.journal.replaceError = nil
        fixture.events.reset()
        let secondStore = fixture.makeStore(
            destinationInspector: FakePendingDestinationInspector()
        )
        #expect(
            try await secondStore.markPostProcessing(
                expected: IOSPendingRecordingCASExpectation(
                    recording: visibleCommit
                )
            ) == visibleCommit
        )
        #expect(fixture.events.values == ["journal.replace"])

        fixture.events.reset()
        _ = try await fixture.store.markPostProcessing(
            expected: IOSPendingRecordingCASExpectation(recording: visibleCommit)
        )
        #expect(fixture.events.values == ["journal.replace"])
    }

    @Test func uncertainProcessRecoveryRetiresOldIdentityBeforeRetry() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let oldID = UUID()
        _ = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: oldID
        )
        let transcribing = try #require(fixture.journal.recording)
        let recoveringStore = fixture.makeStore(
            destinationInspector: FakePendingDestinationInspector()
        )
        fixture.journal.replaceError = .journalCommitUncertain
        fixture.journal.replaceCommitsBeforeError = true

        await #expect(
            throws: IOSPendingRecordingError.journalCommitUncertain
        ) {
            _ = try await recoveringStore.recoverAfterProcessLoss(
                expected: IOSPendingRecordingCASExpectation(
                    recording: transcribing
                )
            )
        }
        let visibleRecovery = try #require(fixture.journal.recording)
        #expect(visibleRecovery.phase == .awaitingRecovery)
        fixture.journal.replaceError = nil

        await #expect(throws: IOSPendingRecordingError.invalidTransition) {
            _ = try await recoveringStore.retryTranscription(
                expected: IOSPendingRecordingCASExpectation(
                    recording: visibleRecovery
                ),
                transcriptionID: oldID,
                transcriptionConfiguration: .defaults
            )
        }
        let freshID = UUID()
        let handoff = try await recoveringStore.retryTranscription(
            expected: IOSPendingRecordingCASExpectation(
                recording: visibleRecovery
            ),
            transcriptionID: freshID,
            transcriptionConfiguration: .defaults
        )
        let executor = CapturingPendingTranscriptionExecutor()
        _ = try await handoff.execute(using: executor)
        #expect(executor.recording?.transcriptionID == freshID)
    }

    @Test func freshStoreRequiresDestinationAbsenceBeforeProcessLossRecovery() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let transcriptionID = UUID()
        _ = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: transcriptionID
        )
        let transcribing = try #require(fixture.journal.recording)

        await #expect(throws: IOSPendingRecordingError.invalidTransition) {
            _ = try await fixture.store.recoverAfterProcessLoss(
                expected: IOSPendingRecordingCASExpectation(recording: transcribing)
            )
        }

        let destination = FakePendingDestinationInspector()
        let freshStore = fixture.makeStore(destinationInspector: destination)
        let recovered = try await freshStore.recoverAfterProcessLoss(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )
        #expect(recovered.phase == .awaitingRecovery)
        #expect(recovered.transcriptionID == nil)

        fixture.journal.recording = transcribing
        destination.hasDestination = true
        let blockedStore = fixture.makeStore(destinationInspector: destination)
        await #expect(throws: IOSPendingRecordingError.invalidTransition) {
            _ = try await blockedStore.recoverAfterProcessLoss(
                expected: IOSPendingRecordingCASExpectation(recording: transcribing)
            )
        }

        fixture.journal.recording = transcribing
        destination.hasDestination = false
        destination.error = .journalUnreadable
        let failingStore = fixture.makeStore(destinationInspector: destination)
        await #expect(
            throws: IOSPendingRecordingError.destinationInspectionFailed
        ) {
            _ = try await failingStore.recoverAfterProcessLoss(
                expected: IOSPendingRecordingCASExpectation(recording: transcribing)
            )
        }
    }

    @Test func outputDeliveryHappyPathIsIdempotentAndRecoverableAfterRelaunch() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        _ = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)
        let postProcessing = try await fixture.store.markPostProcessing(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )
        let outputDelivery = try await fixture.store.markOutputDelivery(
            expected: IOSPendingRecordingCASExpectation(recording: postProcessing)
        )
        #expect(outputDelivery.phase == .outputDelivery)
        #expect(
            try await fixture.store.markOutputDelivery(
                expected: IOSPendingRecordingCASExpectation(recording: outputDelivery)
            ) == outputDelivery
        )

        let destination = FakePendingDestinationInspector()
        let relaunchedStore = fixture.makeStore(destinationInspector: destination)
        let recovered = try await relaunchedStore.recoverAfterProcessLoss(
            expected: IOSPendingRecordingCASExpectation(recording: outputDelivery)
        )
        #expect(recovered.phase == .awaitingRecovery)
        #expect(recovered.transcriptionID == nil)
    }

    @Test func publicDestinationProofReceivesExactDurableIdentity() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-pending-store-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let attemptID = UUID()
        let transcriptionID = UUID()
        let timestamp = try IOSPendingRecordingTimestampCodec.canonicalDate(
            from: Date()
        )
        let recording = try IOSPendingRecording(
            attemptID: attemptID,
            audioRelativeIdentifier: IOSPendingRecordingStorageLocation
                .relativeAudioIdentifier(for: attemptID, format: .wav),
            createdAt: timestamp,
            updatedAt: timestamp,
            phase: .outputDelivery,
            outputIntent: .standard,
            transcriptionID: transcriptionID,
            transcriptionModel: TranscriptionConfiguration.defaultModel,
            transcriptionLanguageCode: nil,
            durationMilliseconds: 1_000,
            byteCount: 1_000
        )
        try FoundationIOSPendingRecordingJournalRepository(
            applicationSupportDirectoryURL: directoryURL
        ).create(recording)
        let capture = PublicDestinationProofCapture()
        let store = IOSPendingRecordingStore(
            applicationSupportDirectoryURL: directoryURL,
            canonicalDestinationExists: { attemptID, transcriptionID in
                capture.record(
                    attemptID: attemptID,
                    transcriptionID: transcriptionID
                )
                return false
            }
        )

        let recovered = try await store.recoverAfterProcessLoss(
            expected: IOSPendingRecordingCASExpectation(recording: recording)
        )

        #expect(recovered.phase == .awaitingRecovery)
        #expect(capture.attemptID == attemptID)
        #expect(capture.transcriptionID == transcriptionID)
    }

    @Test func loadNeverExposesAudioURLAndDistinguishesOrphanAndAvailability() async throws {
        let empty = StoreFixture()
        #expect(try await empty.store.load() == nil)

        empty.audio.requireEmptyError = .namespaceNotEmpty
        await #expect(throws: IOSPendingRecordingError.orphanedAudio) {
            _ = try await empty.store.load()
        }

        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        fixture.audio.validateError = .protectedAudioMissing
        let observation = try #require(try await fixture.store.load())
        #expect(observation.recording == prepared)
        #expect(observation.availability == .missing)
        #expect(!String(describing: observation).contains("protected"))
    }

    @Test func sharedLiveOwnerRegistryBlocksRecoveryUntilProcessLoss() async throws {
        let fixture = StoreFixture()
        let registry = IOSPendingRecordingLiveOwnerRegistry()
        let destination = FakePendingDestinationInspector()
        let owner = IOSPendingRecordingStore(
            journal: fixture.journal,
            audioFileSystem: fixture.audio,
            liveOwnerRegistry: registry,
            now: { fixture.clockDate }
        )
        let secondStore = IOSPendingRecordingStore(
            journal: fixture.journal,
            audioFileSystem: fixture.audio,
            destinationInspector: destination,
            liveOwnerRegistry: registry,
            now: { fixture.clockDate }
        )
        let prepared = try await owner.prepare(fixture.preparation())
        _ = try await owner.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)

        await #expect(throws: IOSPendingRecordingError.invalidTransition) {
            _ = try await secondStore.recoverAfterProcessLoss(
                expected: IOSPendingRecordingCASExpectation(recording: transcribing)
            )
        }

        let relaunchedStore = IOSPendingRecordingStore(
            journal: fixture.journal,
            audioFileSystem: fixture.audio,
            destinationInspector: destination,
            liveOwnerRegistry: IOSPendingRecordingLiveOwnerRegistry(),
            now: { fixture.clockDate }
        )
        let recovered = try await relaunchedStore.recoverAfterProcessLoss(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )
        #expect(recovered.phase == .awaitingRecovery)
    }

    @Test func retiredIdentityIsRejectedAcrossStoresInTheSameProcess() async throws {
        let fixture = StoreFixture()
        let registry = IOSPendingRecordingLiveOwnerRegistry()
        let owner = IOSPendingRecordingStore(
            journal: fixture.journal,
            audioFileSystem: fixture.audio,
            liveOwnerRegistry: registry,
            now: { fixture.clockDate }
        )
        let secondStore = IOSPendingRecordingStore(
            journal: fixture.journal,
            audioFileSystem: fixture.audio,
            liveOwnerRegistry: registry,
            now: { fixture.clockDate }
        )
        let prepared = try await owner.prepare(fixture.preparation())
        let retiredID = UUID()
        _ = try await owner.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: retiredID
        )
        let transcribing = try #require(fixture.journal.recording)
        let recovery = try await owner.markAwaitingRecovery(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )

        await #expect(throws: IOSPendingRecordingError.invalidTransition) {
            _ = try await secondStore.retryTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: recovery),
                transcriptionID: retiredID,
                transcriptionConfiguration: .defaults
            )
        }
    }

    @Test func discardRemovesAudioBeforeJournalAndKeepsJournalOnAudioFailure() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(
            fixture.preparation(initialState: .awaitingRecovery)
        )
        fixture.events.reset()

        #expect(
            try await fixture.store.discard(
                expected: IOSPendingRecordingCASExpectation(recording: prepared)
            ) == .discarded
        )
        #expect(fixture.events.values == ["audio.remove", "journal.remove"])
        #expect(fixture.journal.recording == nil)
        #expect(
            try await fixture.store.discard(
                expected: IOSPendingRecordingCASExpectation(recording: prepared)
            ) == .alreadyAbsent
        )

        let failing = StoreFixture()
        let retained = try await failing.store.prepare(
            failing.preparation(initialState: .awaitingRecovery)
        )
        failing.audio.removeError = .removeFailed
        await #expect(throws: IOSPendingRecordingError.audioRemoveFailed) {
            _ = try await failing.store.discard(
                expected: IOSPendingRecordingCASExpectation(recording: retained)
            )
        }
        #expect(failing.journal.recording == retained)
        #expect(!failing.events.values.contains("journal.remove"))
    }

    @Test func processGatePreventsTwoStoresFromPublishingTheSameSlot() async {
        let fixture = StoreFixture()
        let publishBarrier = PendingStorePublishBarrier()
        let gateProbe = PendingStoreGateProbe()
        let sharedGate = IOSPendingRecordingOperationGate { event in
            gateProbe.record(event)
        }
        fixture.audio.blockNextPublish(with: publishBarrier)
        let firstStore = IOSPendingRecordingStore(
            journal: fixture.journal,
            audioFileSystem: fixture.audio,
            operationGate: sharedGate,
            now: { fixture.clockDate }
        )
        let secondStore = IOSPendingRecordingStore(
            journal: fixture.journal,
            audioFileSystem: fixture.audio,
            operationGate: sharedGate,
            now: { fixture.clockDate }
        )
        let firstPreparation = fixture.preparation(attemptID: UUID())
        let secondPreparation = fixture.preparation(attemptID: UUID())

        let firstTask = Task { try? await firstStore.prepare(firstPreparation) }
        #expect(publishBarrier.waitUntilBlocked())
        let secondTask = Task { try? await secondStore.prepare(secondPreparation) }
        #expect(gateProbe.waitUntilEnqueued())
        publishBarrier.release()
        let results = await [firstTask.value, secondTask.value]

        #expect(results.compactMap { $0 }.count == 1)
        #expect(fixture.audio.publishCallCount == 1)
        #expect(fixture.journal.recording != nil)
    }

    @Test func discardResumesAfterAudioFirstCrashWithoutGuessingOrphans() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(
            fixture.preparation(initialState: .awaitingRecovery)
        )
        fixture.journal.removeError = .journalRemoveFailed

        await #expect(throws: IOSPendingRecordingError.journalRemoveFailed) {
            _ = try await fixture.store.discard(
                expected: IOSPendingRecordingCASExpectation(recording: prepared)
            )
        }
        #expect(!fixture.audio.published)
        #expect(fixture.journal.recording == prepared)

        fixture.journal.removeError = nil
        #expect(
            try await fixture.store.discard(
                expected: IOSPendingRecordingCASExpectation(recording: prepared)
            ) == .discarded
        )
        #expect(fixture.journal.recording == nil)

        let orphan = StoreFixture()
        _ = try await orphan.store.prepare(
            orphan.preparation(initialState: .awaitingRecovery)
        )
        orphan.journal.recording = nil
        orphan.events.reset()
        #expect(
            try await orphan.store.discard(
                expected: IOSPendingRecordingCASExpectation(recording: prepared)
            ) == .alreadyAbsent
        )
        #expect(orphan.events.values.isEmpty)
        #expect(orphan.audio.published)
    }
}

private final class StoreFixture: @unchecked Sendable {
    let events = PendingStoreEventLog()
    let journal: FakePendingRecordingJournal
    let audio: FakePendingRecordingAudioFileSystem
    let clockDate = Date(timeIntervalSince1970: 1_752_150_896.789)
    let store: IOSPendingRecordingStore

    init() {
        let events = events
        journal = FakePendingRecordingJournal(events: events)
        audio = FakePendingRecordingAudioFileSystem(events: events)
        store = IOSPendingRecordingStore(
            journal: journal,
            audioFileSystem: audio,
            now: { Date(timeIntervalSince1970: 1_752_150_896.789) }
        )
    }

    func makeStore(
        destinationInspector: any IOSPendingRecordingDestinationInspecting
    ) -> IOSPendingRecordingStore {
        IOSPendingRecordingStore(
            journal: journal,
            audioFileSystem: audio,
            destinationInspector: destinationInspector,
            now: { self.clockDate }
        )
    }

    func preparation(
        attemptID: UUID = UUID(
            uuidString: "01234567-89AB-CDEF-8123-456789ABCDEF"
        )!,
        initialState: IOSPendingRecordingInitialState = .readyForTranscription
    ) -> IOSPendingRecordingPreparation {
        try! IOSPendingRecordingPreparation(
            attemptID: attemptID,
            sourceArtifact: AudioRecordingArtifact(
                fileURL: URL(fileURLWithPath: "/runtime/source.m4a"),
                duration: 1.5,
                byteCount: 12
            ),
            initialState: initialState,
            outputIntent: .translate,
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "initial-model",
                language: .english,
                freeformPrompt: "not durable"
            )
        )
    }
}

private final class FakePendingRecordingJournal:
    IOSPendingRecordingJournalStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private let events: PendingStoreEventLog
    private var storedRecording: IOSPendingRecording?
    private var storedCreateError: IOSPendingRecordingError?
    private var storedReplaceError: IOSPendingRecordingError?
    private var storedReplaceErrorCallNumber: Int?
    private var storedReplaceCommitsBeforeError = false
    private var storedReplaceCallCount = 0
    private var storedRemoveError: IOSPendingRecordingError?

    var recording: IOSPendingRecording? {
        get { lock.withLock { storedRecording } }
        set { lock.withLock { storedRecording = newValue } }
    }

    var createError: IOSPendingRecordingError? {
        get { lock.withLock { storedCreateError } }
        set { lock.withLock { storedCreateError = newValue } }
    }
    var replaceError: IOSPendingRecordingError? {
        get { lock.withLock { storedReplaceError } }
        set { lock.withLock { storedReplaceError = newValue } }
    }
    var replaceErrorCallNumber: Int? {
        get { lock.withLock { storedReplaceErrorCallNumber } }
        set { lock.withLock { storedReplaceErrorCallNumber = newValue } }
    }
    var replaceCommitsBeforeError: Bool {
        get { lock.withLock { storedReplaceCommitsBeforeError } }
        set { lock.withLock { storedReplaceCommitsBeforeError = newValue } }
    }
    var removeError: IOSPendingRecordingError? {
        get { lock.withLock { storedRemoveError } }
        set { lock.withLock { storedRemoveError = newValue } }
    }

    init(events: PendingStoreEventLog) {
        self.events = events
    }

    func load() throws -> IOSPendingRecording? {
        lock.withLock { storedRecording }
    }

    func create(_ recording: IOSPendingRecording) throws {
        events.append("journal.create")
        try lock.withLock {
            if let storedCreateError {
                throw storedCreateError
            }
            guard storedRecording == nil else {
                throw IOSPendingRecordingError.pendingSlotOccupied
            }
            storedRecording = recording
        }
    }

    func replace(
        _ recording: IOSPendingRecording,
        expected: IOSPendingRecording
    ) throws {
        events.append("journal.replace")
        try lock.withLock {
            storedReplaceCallCount += 1
            guard storedRecording == expected else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
            if let storedReplaceError,
               storedReplaceErrorCallNumber == nil
                || storedReplaceErrorCallNumber == storedReplaceCallCount {
                if storedReplaceCommitsBeforeError {
                    storedRecording = recording
                }
                throw storedReplaceError
            }
            storedRecording = recording
        }
    }

    func remove(expected: IOSPendingRecording) throws -> Bool {
        events.append("journal.remove")
        return try lock.withLock {
            if let storedRemoveError {
                throw storedRemoveError
            }
            guard let storedRecording else {
                return false
            }
            guard storedRecording == expected else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
            self.storedRecording = nil
            return true
        }
    }
}

private final class FakePendingRecordingAudioFileSystem:
    IOSPendingRecordingAudioFileSystem,
    @unchecked Sendable {
    private let lock = NSLock()
    private let events: PendingStoreEventLog
    private var storedPublished = false
    private var storedPublishCallCount = 0
    private var storedLeaseReleaseCount = 0
    private var storedRequireEmptyError: IOSPendingRecordingAudioFileSystemError?
    private var storedValidateError: IOSPendingRecordingAudioFileSystemError?
    private var storedValidateErrorCallNumber: Int?
    private var storedValidateCallCount = 0
    private var storedRemoveError: IOSPendingRecordingAudioFileSystemError?
    private var storedPublishBarrier: PendingStorePublishBarrier?

    var published: Bool { lock.withLock { storedPublished } }
    var publishCallCount: Int { lock.withLock { storedPublishCallCount } }
    var leaseReleaseCount: Int { lock.withLock { storedLeaseReleaseCount } }
    var requireEmptyError: IOSPendingRecordingAudioFileSystemError? {
        get { lock.withLock { storedRequireEmptyError } }
        set { lock.withLock { storedRequireEmptyError = newValue } }
    }
    var validateError: IOSPendingRecordingAudioFileSystemError? {
        get { lock.withLock { storedValidateError } }
        set { lock.withLock { storedValidateError = newValue } }
    }
    var validateErrorCallNumber: Int? {
        get { lock.withLock { storedValidateErrorCallNumber } }
        set { lock.withLock { storedValidateErrorCallNumber = newValue } }
    }
    var removeError: IOSPendingRecordingAudioFileSystemError? {
        get { lock.withLock { storedRemoveError } }
        set { lock.withLock { storedRemoveError = newValue } }
    }

    func blockNextPublish(with barrier: PendingStorePublishBarrier) {
        lock.withLock { storedPublishBarrier = barrier }
    }

    init(events: PendingStoreEventLog) {
        self.events = events
    }

    func requireEmptyNamespace() async throws {
        events.append("audio.namespace.empty")
        if let error = lock.withLock({ storedRequireEmptyError }) {
            throw error
        }
    }

    func publishProtectedCopy(
        from source: AudioRecordingArtifact,
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat,
        durationMilliseconds: Int64
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        events.append("audio.publish")
        let barrier = lock.withLock { () -> PendingStorePublishBarrier? in
            defer { storedPublishBarrier = nil }
            return storedPublishBarrier
        }
        barrier?.block()
        lock.withLock {
            storedPublished = true
            storedPublishCallCount += 1
        }
        let relative = IOSPendingRecordingStorageLocation.relativeAudioIdentifier(
            for: attemptID,
            format: format
        )
        return FakePendingRecordingAudioLease(
            relativeIdentifier: relative,
            artifact: AudioRecordingArtifact(
                fileURL: URL(fileURLWithPath: "/protected/recording.m4a"),
                duration: TimeInterval(durationMilliseconds) / 1_000,
                byteCount: source.byteCount
            ),
            durationMilliseconds: durationMilliseconds,
            events: events,
            onRelease: { [weak self] in
                guard let self else {
                    return
                }
                self.lock.withLock { self.storedLeaseReleaseCount += 1 }
            }
        )
    }

    func validatePublishedAudio(
        relativeIdentifier: String,
        attemptID: UUID,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) async throws -> AudioRecordingArtifact {
        events.append("audio.validate")
        let error = lock.withLock { () -> IOSPendingRecordingAudioFileSystemError? in
            storedValidateCallCount += 1
            guard storedValidateErrorCallNumber == nil
                    || storedValidateErrorCallNumber == storedValidateCallCount else {
                return nil
            }
            return storedValidateError
        }
        if let error {
            throw error
        }
        return AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/protected/recording.m4a"),
            duration: TimeInterval(durationMilliseconds) / 1_000,
            byteCount: byteCount
        )
    }

    func removePublishedAudioIfPresent(
        relativeIdentifier: String,
        attemptID: UUID,
        expectedByteCount: Int64
    ) async throws -> Bool {
        events.append("audio.remove")
        if let error = lock.withLock({ storedRemoveError }) {
            throw error
        }
        return lock.withLock {
            defer { storedPublished = false }
            return storedPublished
        }
    }
}

nonisolated private final class PendingStorePublishBarrier: @unchecked Sendable {
    private let blocked = DispatchSemaphore(value: 0)
    private let releaseSignal = DispatchSemaphore(value: 0)

    func block() {
        blocked.signal()
        _ = releaseSignal.wait(timeout: .now() + 10)
    }

    func waitUntilBlocked() -> Bool {
        blocked.wait(timeout: .now() + 10) == .success
    }

    func release() {
        releaseSignal.signal()
    }
}

nonisolated private final class PendingStoreGateProbe: @unchecked Sendable {
    private let enqueued = DispatchSemaphore(value: 0)

    func record(_ event: IOSPendingRecordingOperationGate.Event) {
        if case .enqueued = event {
            enqueued.signal()
        }
    }

    func waitUntilEnqueued() -> Bool {
        enqueued.wait(timeout: .now() + 10) == .success
    }
}

nonisolated private final class PendingExecutionProbe: @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let cancelled = DispatchSemaphore(value: 0)

    func markStarted() {
        started.signal()
    }

    func markCancelled() {
        cancelled.signal()
    }

    func waitUntilStarted() -> Bool {
        started.wait(timeout: .now() + 10) == .success
    }

    func waitUntilCancelled() -> Bool {
        cancelled.wait(timeout: .now() + 10) == .success
    }
}

nonisolated private final class CapturingPendingTranscriptionExecutor:
    IOSPendingTranscriptionExecutor,
    @unchecked Sendable {
    private let lock = NSLock()
    private var storedRecording: IOSPendingRecording?
    private var storedAudioArtifact: AudioRecordingArtifact?

    var recording: IOSPendingRecording? {
        lock.withLock { storedRecording }
    }

    var audioArtifact: AudioRecordingArtifact? {
        lock.withLock { storedAudioArtifact }
    }

    func transcribe(
        recording: IOSPendingRecording,
        audioArtifact: AudioRecordingArtifact
    ) async throws -> String {
        lock.withLock {
            storedRecording = recording
            storedAudioArtifact = audioArtifact
        }
        return "transcript"
    }
}

nonisolated private final class CancellablePendingTranscriptionExecutor:
    IOSPendingTranscriptionExecutor,
    @unchecked Sendable {
    private let probe: PendingExecutionProbe

    init(probe: PendingExecutionProbe) {
        self.probe = probe
    }

    func transcribe(
        recording: IOSPendingRecording,
        audioArtifact: AudioRecordingArtifact
    ) async throws -> String {
        probe.markStarted()
        do {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            return "late transcript"
        } catch {
            probe.markCancelled()
            throw error
        }
    }
}

nonisolated private final class NoncooperativePendingTranscriptionExecutor:
    IOSPendingTranscriptionExecutor,
    @unchecked Sendable {
    private enum ReleaseState {
        case waiting
        case suspended(CheckedContinuation<Void, Never>)
        case released
    }

    private let lock = NSLock()
    private let started = DispatchSemaphore(value: 0)
    private var releaseState = ReleaseState.waiting

    func transcribe(
        recording: IOSPendingRecording,
        audioArtifact: AudioRecordingArtifact
    ) async throws -> String {
        started.signal()
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                switch releaseState {
                case .waiting:
                    releaseState = .suspended(continuation)
                    return false
                case .suspended:
                    preconditionFailure("Executor has one invocation")
                case .released:
                    return true
                }
            }
            if shouldResume {
                continuation.resume()
            }
        }
        return "late transcript"
    }

    func waitUntilStarted() -> Bool {
        started.wait(timeout: .now() + 10) == .success
    }

    func release() {
        let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
            switch releaseState {
            case .waiting:
                releaseState = .released
                return nil
            case .suspended(let continuation):
                releaseState = .released
                return continuation
            case .released:
                return nil
            }
        }
        continuation?.resume()
    }
}

private final class FakePendingRecordingAudioLease:
    IOSPendingRecordingPublishedAudioLease,
    @unchecked Sendable {
    let relativeIdentifier: String
    let audioArtifact: AudioRecordingArtifact
    let durationMilliseconds: Int64

    private let events: PendingStoreEventLog
    private let onRelease: @Sendable () -> Void

    init(
        relativeIdentifier: String,
        artifact: AudioRecordingArtifact,
        durationMilliseconds: Int64,
        events: PendingStoreEventLog,
        onRelease: @escaping @Sendable () -> Void
    ) {
        self.relativeIdentifier = relativeIdentifier
        audioArtifact = artifact
        self.durationMilliseconds = durationMilliseconds
        self.events = events
        self.onRelease = onRelease
    }

    func revalidate() async throws -> AudioRecordingArtifact {
        events.append("audio.lease.revalidate")
        return audioArtifact
    }

    func release() {
        events.append("audio.lease.release")
        onRelease()
    }
}

private final class FakePendingDestinationInspector:
    IOSPendingRecordingDestinationInspecting,
    @unchecked Sendable {
    private let lock = NSLock()
    private var storedHasDestination = false
    private var storedError: IOSPendingRecordingError?

    var hasDestination: Bool {
        get { lock.withLock { storedHasDestination } }
        set { lock.withLock { storedHasDestination = newValue } }
    }

    var error: IOSPendingRecordingError? {
        get { lock.withLock { storedError } }
        set { lock.withLock { storedError = newValue } }
    }

    func hasCanonicalDestination(
        attemptID: UUID,
        transcriptionID: UUID
    ) throws -> Bool {
        if let error = lock.withLock({ storedError }) {
            throw error
        }
        return hasDestination
    }
}

private final class PendingStoreEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] {
        lock.withLock { storedValues }
    }

    func append(_ value: String) {
        lock.withLock { storedValues.append(value) }
    }

    func reset() {
        lock.withLock { storedValues.removeAll() }
    }
}

private final class PublicDestinationProofCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedAttemptID: UUID?
    private var storedTranscriptionID: UUID?

    var attemptID: UUID? { lock.withLock { storedAttemptID } }
    var transcriptionID: UUID? { lock.withLock { storedTranscriptionID } }

    func record(attemptID: UUID, transcriptionID: UUID) {
        lock.withLock {
            storedAttemptID = attemptID
            storedTranscriptionID = transcriptionID
        }
    }
}
