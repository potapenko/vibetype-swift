import Darwin
import Foundation
import HoldTypeDomain
import Testing
@_spi(HoldTypeIOSCore) @testable import HoldTypePersistence

@Suite(.serialized)
struct IOSV1ForegroundVoicePersistenceTests {
    @Test func acceptanceCommitsLatestThenHistoryThenExactCleanup()
        async throws {
        let fixture = FacadeFixture()
        let expected = try await fixture.moveToOutputDelivery()
        fixture.events.clear()

        let result = try await fixture.owner.accept(
            try fixture.acceptance(),
            expectedPending: expected
        )

        guard case .resultReady(let record, let notice) = result else {
            Issue.record("Expected a ready result")
            return
        }
        #expect(record.resultID == FacadeIDs.result)
        #expect(notice == nil)
        #expect(
            fixture.events.values == [
                "voice-write",
                "history-write",
                "audio-unlink",
                "voice-write",
            ]
        )
        let state = try await fixture.repository.load()
        #expect(state.pending == nil)
        #expect(state.latest?.text == "accepted text")
        #expect(try await fixture.history.load().entries.count == 1)
        #expect(!fixture.audio.contains(FacadeIDs.attempt))
    }

    @Test func historyFailureKeepsAcceptedCleanupUntilLifecycleRetry()
        async throws {
        let fixture = FacadeFixture()
        let expected = try await fixture.moveToOutputDelivery()
        fixture.historyMetadata.failNextWrite = true
        fixture.events.clear()

        let result = try await fixture.owner.accept(
            try fixture.acceptance(),
            expectedPending: expected
        )

        guard case .resultReady(_, let notice) = result else {
            Issue.record("Expected a ready result")
            return
        }
        #expect(notice == .historyWriteFailed)
        let deferred = try await fixture.repository.load()
        #expect(deferred.pending?.status == .acceptedCleanup(
            IOSVoiceStateAcceptedResult(
                resultID: FacadeIDs.result,
                sourceAttemptID: FacadeIDs.attempt,
                text: "accepted text",
                createdAt: FacadeDates.accepted
            )
        ))
        #expect(deferred.latest != nil)
        #expect(fixture.audio.contains(FacadeIDs.attempt))
        #expect(
            fixture.events.values == [
                "voice-write",
                "history-write",
            ]
        )

        fixture.events.clear()
        #expect(
            await fixture.owner.recoverContainingAppLifecycle(
                .foregroundOpportunity
            ) == .complete
        )
        #expect(try await fixture.repository.load().pending == nil)
        #expect(!fixture.audio.contains(FacadeIDs.attempt))
        #expect(try await fixture.history.load().entries.count == 1)
        #expect(fixture.events.values == [
            "history-write",
            "audio-unlink",
            "voice-write",
        ])
    }

    @Test func reconciliationHistoryFailureRetainsAcceptedAudio() async throws {
        let fixture = FacadeFixture()
        let expected = try await fixture.moveToOutputDelivery()
        fixture.historyMetadata.failNextWrite = true
        _ = try await fixture.owner.accept(
            try fixture.acceptance(),
            expectedPending: expected
        )
        fixture.historyMetadata.failNextWrite = true
        fixture.events.clear()

        let result = try #require(
            try await fixture.owner.reconcileAcceptance(
                matching: fixture.acceptance()
            )
        )

        guard case .resultReady(_, let notice) = result else {
            Issue.record("Expected reconciled accepted result")
            return
        }
        #expect(notice == .historyWriteFailed)
        #expect(try await fixture.repository.load().pending != nil)
        #expect(fixture.audio.contains(FacadeIDs.attempt))
        #expect(fixture.events.values == ["history-write"])
    }

    @Test func disabledHistoryIsNotAnAcceptanceFailure() async throws {
        let fixture = FacadeFixture()
        let history = try await fixture.history.load()
        _ = try await fixture.history.setEnabled(
            false,
            ifCurrent: IOSAcceptedTextHistorySnapshotToken(record: history)
        )
        let expected = try await fixture.moveToOutputDelivery()
        fixture.events.clear()

        let result = try await fixture.owner.accept(
            try fixture.acceptance(),
            expectedPending: expected
        )

        guard case .resultReady(_, let notice) = result else {
            Issue.record("Expected a ready result")
            return
        }
        #expect(notice == nil)
        #expect(
            fixture.events.values == [
                "voice-write", "audio-unlink", "voice-write",
            ]
        )
        #expect(try await fixture.history.load().isEnabled == false)
        #expect(try await fixture.history.load().entries.isEmpty)
    }

    @Test func fiveMinuteAcceptedAudioSurvivesDisabledHistoryAndCacheOff()
        async throws {
        let fixture = FacadeFixture()
        let history = try await fixture.history.load()
        _ = try await fixture.history.setEnabled(
            false,
            ifCurrent: IOSAcceptedTextHistorySnapshotToken(record: history)
        )
        let expected = try await fixture.moveToOutputDelivery(
            acceptedAudioRetention: .savedFiveMinute
        )

        let result = try await fixture.owner.accept(
            try fixture.acceptance(),
            expectedPending: expected
        )

        guard case .resultReady(let record, let notice) = result else {
            Issue.record("Expected a ready result")
            return
        }
        #expect(notice == nil)
        #expect(try await fixture.repository.load().pending == nil)
        #expect(try await fixture.repository.load().latest?.resultID
            == record.resultID)
        #expect(try await fixture.history.load().isEnabled == false)
        #expect(try await fixture.history.load().entries.isEmpty)
        #expect(!fixture.audio.contains(FacadeIDs.attempt))

        let saved = try await fixture.acceptedAudioCache.savedRecordings()
        #expect(saved.map(\.resultID) == [record.resultID])
        #expect(
            try await fixture.acceptedAudioCache.playableAudioFileURL(
                resultID: record.resultID,
                policy: .deleteImmediately
            ) != nil
        )

        let relaunchedCache = IOSAcceptedAudioCache(
            directoryURL: fixture.cacheDirectoryURL
        )
        try await relaunchedCache.reconcile(policy: .deleteImmediately)
        #expect(
            try await relaunchedCache.savedRecordings().map(\.resultID)
                == [record.resultID]
        )
    }

    @Test func failedFiveMinutePublishKeepsAcceptedCleanupAndSourceForRelaunch()
        async throws {
        let fixture = FacadeFixture()
        try Data([9]).write(to: fixture.cacheDirectoryURL)
        let expected = try await fixture.moveToOutputDelivery(
            acceptedAudioRetention: .savedFiveMinute
        )
        fixture.events.clear()

        let result = try await fixture.owner.accept(
            try fixture.acceptance(),
            expectedPending: expected
        )

        guard case .resultReady(let record, let notice) = result else {
            Issue.record("Expected accepted text with deferred local cleanup")
            return
        }
        #expect(notice == .localCleanupPending)
        let failedPublish = try await fixture.repository.load()
        #expect(failedPublish.latest?.resultID == record.resultID)
        #expect(failedPublish.pending?.acceptedAudioRetention
            == .savedFiveMinute)
        #expect(failedPublish.pending?.status == .acceptedCleanup(
            IOSVoiceStateAcceptedResult(
                resultID: record.resultID,
                sourceAttemptID: FacadeIDs.attempt,
                text: "accepted text",
                createdAt: FacadeDates.accepted
            )
        ))
        #expect(fixture.audio.contains(FacadeIDs.attempt))
        #expect(try await fixture.history.load().entries.count == 1)
        #expect(
            (try? FileManager.default.contentsOfDirectory(
                at: fixture.cacheDirectoryURL,
                includingPropertiesForKeys: nil
            )) == nil
        )

        try FileManager.default.removeItem(at: fixture.cacheDirectoryURL)
        try FileManager.default.createDirectory(
            at: fixture.cacheDirectoryURL,
            withIntermediateDirectories: true
        )
        let relaunched = fixture.makeRelaunchedOwner()
        fixture.events.clear()
        #expect(
            await relaunched.owner.recoverContainingAppLifecycle(
                .processLaunch
            )
                == .complete
        )

        #expect(try await fixture.repository.load().pending == nil)
        #expect(try await fixture.repository.load().latest?.resultID
            == record.resultID)
        #expect(!fixture.audio.contains(FacadeIDs.attempt))
        #expect(
            try await relaunched.cache.savedRecordings()
                .map(\.resultID) == [record.resultID]
        )
        #expect(
            fixture.events.values == [
                "audio-unlink", "voice-write",
            ]
        )
    }

    @Test
    func relaunchFinishesFiveMinuteCleanupFromExactSavedCopyAfterWriteFailure()
        async throws {
        let fixture = FacadeFixture()
        let expected = try await fixture.moveToOutputDelivery(
            acceptedAudioRetention: .savedFiveMinute
        )
        fixture.events.clear()
        fixture.voiceMetadata.failAfterSuccessfulWrites = 1

        let result = try await fixture.owner.accept(
            try fixture.acceptance(),
            expectedPending: expected
        )

        guard case .resultReady(let record, let notice) = result else {
            Issue.record("Expected accepted text with deferred metadata cleanup")
            return
        }
        #expect(notice == .localCleanupPending)
        #expect(!fixture.audio.contains(FacadeIDs.attempt))
        #expect(try await fixture.repository.load().pending?.status
            == .acceptedCleanup(
                IOSVoiceStateAcceptedResult(
                    resultID: record.resultID,
                    sourceAttemptID: FacadeIDs.attempt,
                    text: "accepted text",
                    createdAt: FacadeDates.accepted
                )
            ))
        let savedURL = try #require(
            try await fixture.acceptedAudioCache.playableAudioFileURL(
                resultID: record.resultID,
                policy: .deleteImmediately
            )
        )
        #expect(try Data(contentsOf: savedURL) == Data([1, 2, 3, 4]))

        let relaunched = fixture.makeRelaunchedOwner()
        fixture.events.clear()
        #expect(
            await relaunched.owner.recoverContainingAppLifecycle(
                .processLaunch
            ) == .complete
        )

        #expect(try await fixture.repository.load().pending == nil)
        #expect(!fixture.audio.contains(FacadeIDs.attempt))
        let relaunchedURL = try #require(
            try await relaunched.cache.playableAudioFileURL(
                resultID: record.resultID,
                policy: .deleteImmediately
            )
        )
        #expect(try Data(contentsOf: relaunchedURL) == Data([1, 2, 3, 4]))
        #expect(fixture.events.values == ["voice-write"])
    }

    @Test
    func cachedFiveMinuteProofReconcilesFailedPruneBeforeFinishingCleanup()
        async throws {
        let cacheFileSystem = FacadeAcceptedAudioFileSystem()
        let fixture = FacadeFixture(
            acceptedAudioFileSystem: cacheFileSystem
        )
        let olderResultIDs = (1...5).map { index in
            UUID(
                uuidString: String(
                    format: "50000000-0000-0000-0000-%012d",
                    index
                )
            )!
        }
        for (offset, resultID) in olderResultIDs.enumerated() {
            _ = try await fixture.acceptedAudioCache.retainAcceptedAudio(
                Data([UInt8(offset + 1)]),
                resultID: resultID,
                fileExtension: "m4a",
                createdAt: FacadeDates.created.addingTimeInterval(
                    Double(offset - 10)
                ),
                policy: .deleteImmediately,
                retention: .savedFiveMinute
            )
        }
        let expected = try await fixture.moveToOutputDelivery(
            acceptedAudioRetention: .savedFiveMinute
        )
        cacheFileSystem.failNextRemove = true

        let result = try await fixture.owner.accept(
            try fixture.acceptance(),
            expectedPending: expected
        )

        guard case .resultReady(let record, let notice) = result else {
            Issue.record("Expected accepted text with deferred cache pruning")
            return
        }
        #expect(notice == .localCleanupPending)
        #expect(fixture.audio.contains(FacadeIDs.attempt))
        #expect(try await fixture.repository.load().pending != nil)
        #expect(
            try await fixture.acceptedAudioCache.savedRecordings().count == 6
        )
        #expect(
            try await fixture.acceptedAudioCache.playableAudioFileURL(
                resultID: record.resultID,
                policy: .deleteImmediately
            ) != nil
        )

        let relaunched = fixture.makeRelaunchedOwner()
        fixture.events.clear()
        #expect(
            await relaunched.owner.recoverContainingAppLifecycle(
                .processLaunch
            ) == .complete
        )

        #expect(try await fixture.repository.load().pending == nil)
        #expect(!fixture.audio.contains(FacadeIDs.attempt))
        let saved = try await relaunched.cache.savedRecordings()
        #expect(saved.count == IOSAcceptedAudioCache.maximumSavedRecordingCount)
        #expect(saved.first?.resultID == record.resultID)
        #expect(
            await relaunched.cache.cachedAudioFileURLIfAvailable(
                resultID: olderResultIDs[0]
            ) == nil
        )
        #expect(
            try await relaunched.cache.playableAudioFileURL(
                resultID: record.resultID,
                policy: .deleteImmediately
            ) != nil
        )
        #expect(fixture.events.values == ["audio-unlink", "voice-write"])
    }

    @Test func cleanupFailureKeepsLatestReadyForTheUser() async throws {
        let fixture = FacadeFixture()
        let expected = try await fixture.moveToOutputDelivery()
        fixture.audio.failNextUnlink = true

        let result = try await fixture.owner.accept(
            try fixture.acceptance(),
            expectedPending: expected
        )

        guard case .resultReady(let record, let notice) = result else {
            Issue.record("Expected the durable Latest result")
            return
        }
        #expect(record.resultID == FacadeIDs.result)
        #expect(notice == .localCleanupPending)
        let state = try await fixture.repository.load()
        #expect(state.latest?.resultID == FacadeIDs.result)
        #expect(state.pending?.status == .acceptedCleanup(
            IOSVoiceStateAcceptedResult(
                resultID: FacadeIDs.result,
                sourceAttemptID: FacadeIDs.attempt,
                text: "accepted text",
                createdAt: FacadeDates.accepted
            )
        ))
        #expect(fixture.audio.contains(FacadeIDs.attempt))
    }

    @Test func foregroundOpportunityRetriesOnlyAcceptedLocalCleanup()
        async throws {
        let fixture = FacadeFixture()
        let expected = try await fixture.moveToOutputDelivery()
        fixture.audio.failNextUnlink = true
        _ = try await fixture.owner.accept(
            try fixture.acceptance(),
            expectedPending: expected
        )
        fixture.events.clear()

        #expect(
            await fixture.owner.recoverContainingAppLifecycle(
                .foregroundOpportunity
            ) == .complete
        )
        let state = try await fixture.repository.load()
        #expect(state.pending == nil)
        #expect(state.latest?.resultID == FacadeIDs.result)
        #expect(!fixture.audio.contains(FacadeIDs.attempt))
        #expect(fixture.events.values == ["audio-unlink", "voice-write"])
    }

    @Test func failedAttemptRetriesWithCurrentSettingsAndDiscardsExactly()
        async throws {
        let fixture = FacadeFixture()
        let ready = try await fixture.installReady()
        let first = try await fixture.owner.beginTranscription(
            expected: ready.expectation,
            transcriptionID: FacadeIDs.operation
        )
        let failed = try await fixture.owner.markFailed(
            expected: first.expectation
        )
        #expect(failed.phase == .failed)

        let retry = try await fixture.owner.retryTranscription(
            expected: IOSV1PendingRecordingExpectation(recording: failed),
            transcriptionID: FacadeIDs.otherOperation,
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "current-model",
                language: .russian
            )
        )
        #expect(retry.recording.transcriptionModel == "current-model")
        #expect(retry.recording.transcriptionLanguageCode == "ru")
        let retryFailed = try await fixture.owner.markFailed(
            expected: retry.expectation
        )
        fixture.events.clear()

        #expect(
            try await fixture.owner.discard(
                expected: IOSV1PendingRecordingExpectation(
                    recording: retryFailed
                )
            ) == .discarded
        )
        #expect(try await fixture.repository.load().pending == nil)
        #expect(!fixture.audio.contains(FacadeIDs.attempt))
        #expect(fixture.events.values == ["audio-unlink", "voice-write"])
    }

    @Test func ambiguousDispatchFailureBlocksRetryAcrossRelaunch()
        async throws {
        let fixture = FacadeFixture()
        let ready = try await fixture.installReady()
        let dispatch = try await fixture.owner.beginTranscription(
            expected: ready.expectation,
            transcriptionID: FacadeIDs.operation
        )
        let failed = try await fixture.owner.markFailed(
            expected: dispatch.expectation,
            transcriptionReplayBlocked: true
        )

        #expect(failed.phase == .failed)
        #expect(failed.transcriptionReplayBlocked)
        #expect(
            await fixture.owner.recoverContainingAppLifecycle(.processLaunch)
                == .complete
        )
        let relaunched = try #require(
            try await fixture.owner.load()?.recording
        )
        #expect(relaunched.transcriptionReplayBlocked)
        await #expect(
            throws: IOSV1ForegroundVoicePersistenceError.invalidTransition
        ) {
            _ = try await fixture.owner.retryTranscription(
                expected: IOSV1PendingRecordingExpectation(
                    recording: relaunched
                ),
                transcriptionID: FacadeIDs.otherOperation,
                transcriptionConfiguration: .defaults
            )
        }
    }

    @Test func fiveMinuteProviderFailureRelaunchAndExplicitRetrySaveAudioOnce()
        async throws {
        let fixture = FacadeFixture()
        let ready = try await fixture.installReady(
            durationMilliseconds: 299_900,
            acceptedAudioRetention: .savedFiveMinute
        )
        let calls = ProviderCallCounter()
        let first = try await fixture.owner.beginTranscription(
            expected: ready.expectation,
            transcriptionID: FacadeIDs.operation
        )

        await #expect(throws: ProviderCallError.failed) {
            _ = try await first.execute(
                using: CountingProviderExecutor(
                    calls: calls,
                    outcome: .failure
                )
            )
        }
        let failed = try await fixture.owner.markFailed(
            expected: first.expectation
        )
        #expect(calls.count == 1)

        #expect(
            await fixture.owner.recoverContainingAppLifecycle(.processLaunch)
                == .complete
        )
        #expect(calls.count == 1)
        let relaunched = try #require(try await fixture.owner.load()?.recording)
        #expect(relaunched.phase == .failed)
        #expect(relaunched.acceptedAudioRetention == .savedFiveMinute)

        let retry = try await fixture.owner.retryTranscription(
            expected: IOSV1PendingRecordingExpectation(recording: failed),
            transcriptionID: FacadeIDs.otherOperation,
            transcriptionConfiguration: .defaults
        )
        let text = try await retry.execute(
            using: CountingProviderExecutor(
                calls: calls,
                outcome: .success("accepted after retry")
            )
        )
        #expect(text == "accepted after retry")
        #expect(calls.count == 2)

        let post = try await fixture.owner.markPostProcessing(
            expected: retry.expectation
        )
        let output = try await fixture.owner.markOutputDelivery(
            expected: IOSV1PendingRecordingExpectation(recording: post)
        )
        let acceptance = try IOSV1ForegroundVoiceAcceptedOutputPreparation(
            deliveryID: FacadeIDs.result,
            sessionID: FacadeIDs.session,
            attemptID: FacadeIDs.attempt,
            transcriptID: FacadeIDs.otherOperation,
            rawAcceptedText: text,
            outputIntent: .standard
        )
        _ = try await fixture.owner.accept(
            acceptance,
            expectedPending: IOSV1PendingRecordingExpectation(
                recording: output
            )
        )

        #expect(try await fixture.repository.load().pending == nil)
        #expect(!fixture.audio.contains(FacadeIDs.attempt))
        #expect(
            try await fixture.acceptedAudioCache.savedRecordings()
                .map(\.resultID) == [FacadeIDs.result]
        )
        #expect(calls.count == 2)
    }

    @Test func completedCaptureReturnsCanonicalPendingForFirstDispatch()
        async throws {
        let preciseDate = Date(
            timeIntervalSince1970: 1_700_000_002.123_456
        )
        let fixture = FacadeFixture(repositoryNow: { preciseDate })
        let lease = try await fixture.owner.createCapture(
            attemptID: FacadeIDs.attempt,
            outputIntent: .standard
        )
        try await lease.beginFinalizing()
        guard case .completed(let capture) = try await lease
            .completeAfterRecorderClose() else {
            Issue.record("Expected completed capture")
            return
        }

        let pending = try await fixture.owner.prepareCompletedCapture(
            capture,
            transcriptionConfiguration: TranscriptionConfiguration()
        )
        let canonical = try #require(try await fixture.owner.load()?.recording)
        #expect(pending == canonical)
        #expect(pending.updatedAt != preciseDate)
        _ = try await fixture.owner.beginTranscription(
            expected: IOSV1PendingRecordingExpectation(recording: pending),
            transcriptionID: FacadeIDs.operation
        )
    }

    @Test
    func cachedFiveMinuteProofRejectsSameSizeDifferentMediaExtension()
        async throws {
        let fixture = FacadeFixture()
        _ = try await fixture.acceptedAudioCache.retainAcceptedAudio(
            Data([1, 2, 3, 4]),
            resultID: FacadeIDs.result,
            fileExtension: "wav",
            createdAt: FacadeDates.created,
            policy: .deleteImmediately,
            retention: .savedFiveMinute
        )
        let expected = try await fixture.moveToOutputDelivery(
            acceptedAudioRetention: .savedFiveMinute
        )

        let result = try await fixture.owner.accept(
            try fixture.acceptance(),
            expectedPending: expected
        )

        guard case .resultReady(let record, let notice) = result else {
            Issue.record("Expected accepted text with deferred local cleanup")
            return
        }
        #expect(notice == .localCleanupPending)
        #expect(fixture.audio.contains(FacadeIDs.attempt))
        #expect(try await fixture.repository.load().pending != nil)
        let cachedURL = try #require(
            try await fixture.acceptedAudioCache.playableAudioFileURL(
                resultID: record.resultID,
                policy: .deleteImmediately
            )
        )
        #expect(cachedURL.pathExtension == "wav")
        #expect(try Data(contentsOf: cachedURL) == Data([1, 2, 3, 4]))
    }

    @Test func acceptedTextCheckpointRetriesDownstreamWithoutAudioDispatch()
        async throws {
        let fixture = FacadeFixture()
        let ready = try await fixture.installReady(
            durationMilliseconds: 300_000,
            acceptedAudioRetention: .savedFiveMinute
        )
        let calls = ProviderCallCounter()
        let dispatch = try await fixture.owner.beginTranscription(
            expected: ready.expectation,
            transcriptionID: FacadeIDs.operation
        )
        let accepted = try await dispatch.execute(
            using: CountingProviderExecutor(
                calls: calls,
                outcome: .success("Accepted provider transcript")
            )
        )
        let transcriptionCheckpoint = try await fixture.owner
            .checkpointTranscription(
                expected: dispatch.expectation,
                acceptedTranscript: accepted
            )
        let outputCheckpoint = try await fixture.owner
            .checkpointPostProcessing(
                expected: IOSV1PendingRecordingExpectation(
                    recording: transcriptionCheckpoint
                ),
                stage: .outputReady,
                text: "Final retained text"
            )
        let failed = try await fixture.owner.markFailed(
            expected: IOSV1PendingRecordingExpectation(
                recording: outputCheckpoint
            )
        )

        #expect(calls.count == 1)
        #expect(failed.durationMilliseconds == 300_000)
        #expect(failed.acceptedAudioRetention == .savedFiveMinute)
        #expect(failed.acceptedTranscriptionID == FacadeIDs.operation)
        #expect(failed.acceptedTranscript == "Accepted provider transcript")
        #expect(failed.textCheckpointStage == .outputReady)
        #expect(failed.textCheckpointText == "Final retained text")
        await #expect(
            throws: IOSV1ForegroundVoicePersistenceError.invalidTransition
        ) {
            _ = try await fixture.owner.retryTranscription(
                expected: IOSV1PendingRecordingExpectation(recording: failed),
                transcriptionID: FacadeIDs.otherOperation,
                transcriptionConfiguration: .defaults
            )
        }

        let relaunched = fixture.makeRelaunchedOwner().owner
        let durable = try #require(try await relaunched.load()?.recording)
        let resumed = try await relaunched.retryPostProcessing(
            expected: IOSV1PendingRecordingExpectation(recording: durable),
            operationID: FacadeIDs.otherOperation
        )
        #expect(resumed.phase == .postProcessing)
        #expect(resumed.transcriptionID == FacadeIDs.otherOperation)
        #expect(resumed.acceptedTranscriptionID == FacadeIDs.operation)
        #expect(resumed.textCheckpointStage == .outputReady)
        #expect(resumed.textCheckpointText == "Final retained text")
        #expect(calls.count == 1)
    }

    @Test func nearBoundaryDoneCaptureCannotDowngradeSavedRetention()
        async throws {
        let fixture = FacadeFixture(
            orphanMediaValidation: .success(299_900)
        )
        let lease = try await fixture.owner.createCapture(
            attemptID: FacadeIDs.attempt,
            outputIntent: .standard
        )
        try await lease.beginFinalizing()
        guard case .completed(let capture) = try await lease
            .completeAfterRecorderClose() else {
            Issue.record("Expected near-boundary completed capture")
            return
        }

        let pending = try await fixture.owner.prepareCompletedCapture(
            capture,
            transcriptionConfiguration: .defaults,
            acceptedAudioRetention: .recordingCachePolicy
        )

        #expect(pending.durationMilliseconds == 299_900)
        #expect(pending.acceptedAudioRetention == .savedFiveMinute)
        #expect(
            try await fixture.repository.load().pending?
                .acceptedAudioRetention == .savedFiveMinute
        )
    }

    @Test func liveMonotonicFallbackSurvivesBadProbeAndExplicitRetry()
        async throws {
        let cases: [(
            Result<Int64, IOSV1VoiceCaptureError>,
            fallback: Int64,
            expectedDuration: Int64
        )] = [
            (.success(299), 30_000, 30_000),
            (.failure(.mediaValidationFailed), 30_000, 30_000),
            (.failure(.mediaValidationTimedOut), 30_000, 30_000),
            (.failure(.mediaValidationFailed), 329_000, 302_000),
            (.success(302_001), 329_000, 302_000),
        ]
        for (validation, fallback, expectedDuration) in cases {
            let fixture = FacadeFixture(
                orphanMediaValidation: validation
            )
            let lease = try await fixture.owner.createCapture(
                attemptID: FacadeIDs.attempt,
                outputIntent: .standard
            )
            try await lease.beginFinalizing()
            guard case .completed(let capture) = try await lease
                .completeAfterRecorderClose(
                    fallbackDurationMilliseconds: fallback
                ) else {
                Issue.record("Expected completed fallback capture")
                continue
            }
            #expect(capture.durationMilliseconds == expectedDuration)
            let pending = try await fixture.owner.prepareCompletedCapture(
                capture,
                transcriptionConfiguration: .defaults
            )
            #expect(
                pending.acceptedAudioRetention
                    == (expectedDuration >= 299_500
                        ? .savedFiveMinute : .recordingCachePolicy)
            )
            let calls = ProviderCallCounter()
            let first = try await fixture.owner.beginTranscription(
                expected: IOSV1PendingRecordingExpectation(
                    recording: pending
                ),
                transcriptionID: FacadeIDs.operation
            )
            await #expect(throws: ProviderCallError.failed) {
                _ = try await first.execute(
                    using: CountingProviderExecutor(
                        calls: calls,
                        outcome: .failure
                    )
                )
            }
            let failed = try await fixture.owner.markFailed(
                expected: first.expectation
            )
            let retry = try await fixture.owner.retryTranscription(
                expected: IOSV1PendingRecordingExpectation(
                    recording: failed
                ),
                transcriptionID: FacadeIDs.otherOperation,
                transcriptionConfiguration: .defaults
            )
            #expect(
                try await retry.execute(
                    using: CountingProviderExecutor(
                        calls: calls,
                        outcome: .success("retry success")
                    )
                ) == "retry success"
            )
            #expect(calls.count == 2)
            #expect(fixture.audio.contains(FacadeIDs.attempt))
        }
    }

    @Test func completedCaptureRemainsPlayableWhenPendingPromotionCannotCommit()
        async throws {
        let fixture = FacadeFixture()
        let lease = try await fixture.owner.createCapture(
            attemptID: FacadeIDs.attempt,
            outputIntent: .standard
        )
        try await lease.beginFinalizing()
        guard case .completed(let capture) = try await lease
            .completeAfterRecorderClose() else {
            Issue.record("Expected completed capture")
            return
        }

        fixture.voiceMetadata.failNextWrite = true
        await #expect(
            throws: IOSV1ForegroundVoicePersistenceError.localPersistence
        ) {
            _ = try await fixture.owner.prepareCompletedCapture(
                capture,
                transcriptionConfiguration: TranscriptionConfiguration()
            )
        }

        guard case .completedCapture(let saved)? = try await fixture.owner
            .loadSavedRecording() else {
            Issue.record("Expected completed-capture recovery")
            return
        }
        #expect(saved.attemptID == FacadeIDs.attempt)
        #expect(saved.durationMilliseconds == 1_250)
        #expect(saved.byteCount == 4)
        #expect(saved.availability == .available)

        let expected = IOSV1CompletedCaptureRecoveryExpectation(
            recording: saved
        )
        let playback = try await fixture.owner
            .prepareCompletedCapturePlaybackAudio(expected: expected)
        #expect(playback.withAudioData { $0 } == Data([1, 2, 3, 4]))

        fixture.voiceMetadata.failNextWrite = true
        await #expect(
            throws: IOSV1ForegroundVoicePersistenceError.localPersistence
        ) {
            _ = try await fixture.owner.recoverCapture(
                expected: expected,
                transcriptionConfiguration: TranscriptionConfiguration()
            )
        }
        guard case .completedCapture(let stillSaved)? =
            try await fixture.owner.loadSavedRecording() else {
            Issue.record("Expected recovery to remain visible")
            return
        }
        #expect(stillSaved == saved)
        #expect(fixture.audio.contains(FacadeIDs.attempt))

        try await fixture.owner.discardCapture(expected: expected)
        #expect(try await fixture.owner.loadSavedRecording() == nil)
        #expect(!fixture.audio.contains(FacadeIDs.attempt))
    }

    @Test func relaunchChangesProcessingToFailedWithoutExecutingProvider()
        async throws {
        let fixture = FacadeFixture()
        let ready = try await fixture.installReady()
        _ = try await fixture.owner.beginTranscription(
            expected: ready.expectation,
            transcriptionID: FacadeIDs.operation
        )
        fixture.events.clear()

        #expect(
            await fixture.owner.recoverContainingAppLifecycle(.processLaunch)
                == .complete
        )
        let observation = try await fixture.owner.load()
        #expect(observation?.recording.phase == .failed)
        #expect(fixture.events.values == ["voice-write"])
    }

    @Test func relaunchFinishesAcceptedCleanupIdempotentlyWithoutProvider()
        async throws {
        let fixture = FacadeFixture()
        _ = try await fixture.moveToOutputDelivery()
        _ = try await fixture.repository.commitAccepted(
            attemptID: FacadeIDs.attempt,
            resultID: FacadeIDs.result,
            text: "accepted text",
            createdAt: FacadeDates.accepted
        )
        fixture.events.clear()

        #expect(
            await fixture.owner.recoverContainingAppLifecycle(.processLaunch)
                == .complete
        )
        #expect(
            fixture.events.values == [
                "history-write", "audio-unlink", "voice-write",
            ]
        )
        #expect(try await fixture.repository.load().pending == nil)
        #expect(try await fixture.history.load().entries.count == 1)

        fixture.events.clear()
        #expect(
            await fixture.owner.recoverContainingAppLifecycle(.processLaunch)
                == .complete
        )
        #expect(fixture.events.values.isEmpty)
        #expect(try await fixture.history.load().entries.count == 1)
    }

    @Test func relaunchReusesCachedAcceptedAudioBeforePendingUnlink()
        async throws {
        let fixture = FacadeFixture(
            recordingCachePolicy: .keepLast(10)
        )
        let expected = try await fixture.moveToOutputDelivery()
        fixture.audio.failNextUnlink = true

        let result = try await fixture.owner.accept(
            try fixture.acceptance(),
            expectedPending: expected
        )

        guard case .resultReady(_, let notice) = result else {
            Issue.record("Expected a ready result")
            return
        }
        #expect(notice == .localCleanupPending)
        let cachedURL = try #require(
            await fixture.acceptedAudioCache
                .cachedAudioFileURLIfAvailable(resultID: FacadeIDs.result)
        )
        #expect(try Data(contentsOf: cachedURL) == Data([1, 2, 3, 4]))
        #expect(try await fixture.repository.load().pending != nil)

        #expect(
            await fixture.owner.recoverContainingAppLifecycle(.processLaunch)
                == .complete
        )
        #expect(try await fixture.repository.load().pending == nil)
        #expect(!fixture.audio.contains(FacadeIDs.attempt))
        #expect(
            await fixture.acceptedAudioCache
                .cachedAudioFileURLIfAvailable(resultID: FacadeIDs.result)
                == cachedURL
        )
    }

    @Test func optionalCacheFailureDoesNotBlockAcceptedCleanup()
        async throws {
        let fixture = FacadeFixture(
            recordingCachePolicy: .keepLast(10)
        )
        try Data([9]).write(to: fixture.cacheDirectoryURL)
        let expected = try await fixture.moveToOutputDelivery()

        let result = try await fixture.owner.accept(
            try fixture.acceptance(),
            expectedPending: expected
        )

        guard case .resultReady(_, let notice) = result else {
            Issue.record("Expected a ready result")
            return
        }
        #expect(notice == nil)
        #expect(try await fixture.repository.load().pending == nil)
        #expect(!fixture.audio.contains(FacadeIDs.attempt))
    }

    @Test func cacheOffReconcilesOldManagedFilesThenAcceptsNormally()
        async throws {
        let fixture = FacadeFixture()
        _ = try await fixture.acceptedAudioCache.retainAcceptedAudio(
            Data([8]),
            resultID: FacadeIDs.previousResult,
            fileExtension: "m4a",
            createdAt: FacadeDates.created,
            policy: .unlimited
        )
        let expected = try await fixture.moveToOutputDelivery()

        _ = try await fixture.owner.accept(
            try fixture.acceptance(),
            expectedPending: expected
        )

        #expect(
            await fixture.acceptedAudioCache
                .cachedAudioFileURLIfAvailable(
                    resultID: FacadeIDs.previousResult
                ) == nil
        )
        #expect(
            await fixture.acceptedAudioCache
                .cachedAudioFileURLIfAvailable(resultID: FacadeIDs.result)
                == nil
        )
        #expect(try await fixture.repository.load().pending == nil)
    }

    @Test func captureRelaunchOffersRecoverOrExactZeroDiscardWithoutProvider()
        async throws {
        let recoverable = FacadeFixture()
        let lease = try await recoverable.owner.createCapture(
            attemptID: FacadeIDs.attempt,
            outputIntent: .standard
        )
        try await lease.beginFinalizing()
        guard case .completed = try await lease.completeAfterRecorderClose()
        else {
            Issue.record("Expected completed capture")
            return
        }
        #expect(
            await recoverable.owner.reconcileCaptureSourcesAtLaunch()
                == .recoverable(attemptID: FacadeIDs.attempt)
        )
        let pending = try await recoverable.owner.recoverCapture(
            attemptID: FacadeIDs.attempt,
            transcriptionConfiguration: TranscriptionConfiguration()
        )
        #expect(pending.phase == .failed)

        for beginsFinalizing in [false, true] {
            let unfinished = FacadeFixture()
            let unfinishedLease = try await unfinished.owner.createCapture(
                attemptID: FacadeIDs.attempt,
                outputIntent: .standard
            )
            if beginsFinalizing {
                try await unfinishedLease.beginFinalizing()
            }
            unfinishedLease.release()

            #expect(
                await unfinished.owner.reconcileCaptureSourcesAtLaunch()
                    == .recoverable(attemptID: FacadeIDs.attempt)
            )
            let snapshot = try await unfinished.repository.load()
            #expect(snapshot.capture?.phase == .completed)
            #expect(snapshot.capture?.byteCount == 4)
            #expect(unfinished.audio.contains(FacadeIDs.attempt))
        }

        let exactZero = FacadeFixture(audioBytes: [])
        let zeroLease = try await exactZero.owner.createCapture(
            attemptID: FacadeIDs.attempt,
            outputIntent: .standard
        )
        zeroLease.release()
        #expect(
            await exactZero.owner.reconcileCaptureSourcesAtLaunch()
                == .discardOnly(attemptID: FacadeIDs.attempt)
        )
        try await exactZero.owner.discardCapture(
            attemptID: FacadeIDs.attempt
        )
        #expect(try await exactZero.repository.load().capture == nil)
        #expect(!exactZero.audio.contains(FacadeIDs.attempt))
    }

    @Test func processLaunchRepairsValidRecordingAndFinalizingOrphans()
        async throws {
        for beginsFinalizing in [false, true] {
            let fixture = FacadeFixture()
            let lease = try await fixture.owner.createCapture(
                attemptID: FacadeIDs.attempt,
                outputIntent: .standard
            )
            if beginsFinalizing { try await lease.beginFinalizing() }
            lease.release()

            #expect(
                await fixture.owner.repairOrphanedCaptureAtProcessLaunch()
                    == .recoverable(attemptID: FacadeIDs.attempt)
            )
            let snapshot = try await fixture.repository.load()
            #expect(snapshot.capture?.phase == .completed)
            #expect(snapshot.capture?.durationMilliseconds == 1_250)
            #expect(snapshot.capture?.byteCount == 4)
            #expect(snapshot.pending == nil)
            #expect(fixture.audio.contains(FacadeIDs.attempt))
        }
    }

    @Test func sameProcessRepairPublishesPositiveBytesWithoutProviderWork()
        async throws {
        for beginsFinalizing in [false, true] {
            let fixture = FacadeFixture()
            let lease = try await fixture.owner.createCapture(
                attemptID: FacadeIDs.attempt,
                outputIntent: .standard
            )
            if beginsFinalizing { try await lease.beginFinalizing() }
            // The production caller has the same obligation: release live
            // recorder ownership before asking persistence to salvage bytes.
            lease.release()

            #expect(
                await fixture.owner
                    .repairInterruptedCaptureAfterRecorderStops()
                    == .recoverable(attemptID: FacadeIDs.attempt)
            )
            let snapshot = try await fixture.repository.load()
            #expect(snapshot.capture?.phase == .completed)
            #expect(snapshot.capture?.byteCount == 4)
            #expect(snapshot.pending == nil)
            guard case .completedCapture(let saved)? = try await fixture.owner
                .loadSavedRecording() else {
                Issue.record("Expected same-process Saved Recording")
                continue
            }
            #expect(saved.attemptID == FacadeIDs.attempt)
            #expect(saved.availability == .available)

            // Reconciliation is idempotent and still provider-free when live
            // finalization had already committed the completed phase.
            #expect(
                await fixture.owner
                    .repairInterruptedCaptureAfterRecorderStops()
                    == .recoverable(attemptID: FacadeIDs.attempt)
            )
            #expect(try await fixture.repository.load().pending == nil)
        }
    }

    @Test func processLaunchKeepsSuspectNonEmptyOrphansRecoverable()
        async throws {
        let fixtures = [
            FacadeFixture(orphanMediaValidation: .success(299)),
            FacadeFixture(orphanMediaValidation: .success(302_001)),
            FacadeFixture(
                orphanMediaValidation: .failure(.mediaValidationFailed)
            ),
            FacadeFixture(
                orphanMediaValidation: .failure(.mediaValidationTimedOut)
            ),
        ]

        for fixture in fixtures {
            let lease = try await fixture.owner.createCapture(
                attemptID: FacadeIDs.attempt,
                outputIntent: .standard
            )
            lease.release()

            #expect(
                await fixture.owner.repairOrphanedCaptureAtProcessLaunch()
                    == .recoverable(attemptID: FacadeIDs.attempt)
            )
            let snapshot = try await fixture.repository.load()
            #expect(snapshot.capture?.phase == .completed)
            #expect(snapshot.capture?.durationMilliseconds == 0)
            #expect(fixture.audio.contains(FacadeIDs.attempt))

            guard case .completedCapture(let saved)? = try await fixture.owner
                .loadSavedRecording() else {
                Issue.record("Expected visible completed capture after relaunch")
                continue
            }
            #expect(saved.durationMilliseconds == 0)
            #expect(saved.availability == .available)
            let expected = IOSV1CompletedCaptureRecoveryExpectation(
                recording: saved
            )
            let playback = try await fixture.owner
                .prepareCompletedCapturePlaybackAudio(expected: expected)
            #expect(playback.withAudioData { $0 } == Data([1, 2, 3, 4]))

            let pending = try await fixture.owner.recoverCapture(
                expected: expected,
                transcriptionConfiguration: .defaults
            )
            #expect(pending.phase == .failed)
            #expect(pending.durationMilliseconds == 0)
            #expect(pending.acceptedAudioRetention == .savedFiveMinute)
            let calls = ProviderCallCounter()
            let dispatch = try await fixture.owner.retryTranscription(
                expected: IOSV1PendingRecordingExpectation(
                    recording: pending
                ),
                transcriptionID: FacadeIDs.operation,
                transcriptionConfiguration: .defaults
            )
            #expect(
                try await dispatch.execute(
                    using: CountingProviderExecutor(
                        calls: calls,
                        outcome: .success("manual unknown-duration result")
                    )
                ) == "manual unknown-duration result"
            )
            await #expect(
                throws: IOSV1ForegroundVoicePersistenceError
                    .dispatchAlreadyExecuted
            ) {
                _ = try await dispatch.execute(
                    using: CountingProviderExecutor(
                        calls: calls,
                        outcome: .success("duplicate")
                    )
                )
            }
            #expect(calls.count == 1)
            let failed = try await fixture.owner.markFailed(
                expected: dispatch.expectation
            )
            #expect(failed.phase == .failed)
            #expect(fixture.audio.contains(FacadeIDs.attempt))

            #expect(
                try await fixture.owner.discard(
                    expected: IOSV1PendingRecordingExpectation(
                        recording: failed
                    )
                ) == .discarded
            )
            #expect(!fixture.audio.contains(FacadeIDs.attempt))
        }
    }

    @Test func unknownRecoverySuccessRetainsAcceptedAudioAsSavedRecording()
        async throws {
        let fixture = FacadeFixture(
            orphanMediaValidation: .failure(.mediaValidationFailed)
        )
        let lease = try await fixture.owner.createCapture(
            attemptID: FacadeIDs.attempt,
            outputIntent: .standard
        )
        lease.release()
        #expect(
            await fixture.owner.repairOrphanedCaptureAtProcessLaunch()
                == .recoverable(attemptID: FacadeIDs.attempt)
        )
        guard case .completedCapture(let saved)? = try await fixture.owner
            .loadSavedRecording() else {
            Issue.record("Expected unknown completed recovery")
            return
        }
        let pending = try await fixture.owner.recoverCapture(
            expected: IOSV1CompletedCaptureRecoveryExpectation(
                recording: saved
            ),
            transcriptionConfiguration: .defaults
        )
        #expect(pending.acceptedAudioRetention == .savedFiveMinute)
        let dispatch = try await fixture.owner.retryTranscription(
            expected: IOSV1PendingRecordingExpectation(recording: pending),
            transcriptionID: FacadeIDs.operation,
            transcriptionConfiguration: .defaults
        )
        let text = try await dispatch.execute(
            using: CountingProviderExecutor(
                calls: ProviderCallCounter(),
                outcome: .success("accepted unknown recording")
            )
        )
        let post = try await fixture.owner.markPostProcessing(
            expected: dispatch.expectation
        )
        let output = try await fixture.owner.markOutputDelivery(
            expected: IOSV1PendingRecordingExpectation(recording: post)
        )
        let acceptance = try IOSV1ForegroundVoiceAcceptedOutputPreparation(
            deliveryID: FacadeIDs.result,
            sessionID: FacadeIDs.session,
            attemptID: FacadeIDs.attempt,
            transcriptID: FacadeIDs.operation,
            rawAcceptedText: text,
            outputIntent: .standard
        )
        _ = try await fixture.owner.accept(
            acceptance,
            expectedPending: IOSV1PendingRecordingExpectation(
                recording: output
            )
        )

        let retained = try #require(
            try await fixture.acceptedAudioCache.savedRecordings().first
        )
        #expect(retained.resultID == FacadeIDs.result)
        #expect(
            try await fixture.acceptedAudioCache.savedAudioFileURL(
                ifCurrent: retained
            ) != nil
        )
    }

    @Test func processLaunchSeparatesEmptyDiscardOnlyFromInvalidBlocked()
        async throws {
        let fixture = FacadeFixture(audioBytes: [])
        let lease = try await fixture.owner.createCapture(
            attemptID: FacadeIDs.attempt,
            outputIntent: .standard
        )
        lease.release()

        #expect(
            await fixture.owner.repairOrphanedCaptureAtProcessLaunch()
                == .discardOnly(attemptID: FacadeIDs.attempt)
        )
        #expect(try await fixture.repository.load().capture?.phase == .recording)
        #expect(fixture.audio.contains(FacadeIDs.attempt))

        let uncertain = FacadeFixture()
        let uncertainLease = try await uncertain.owner.createCapture(
            attemptID: FacadeIDs.attempt,
            outputIntent: .standard
        )
        uncertainLease.release()
        uncertain.audio.openError = .audioInvalid
        #expect(
            await uncertain.owner.repairOrphanedCaptureAtProcessLaunch()
                == .blocked
        )
        #expect(try await uncertain.repository.load().capture?.phase
            == .recording)
        #expect(uncertain.audio.contains(FacadeIDs.attempt))

        let missing = FacadeFixture()
        let missingLease = try await missing.owner.createCapture(
            attemptID: FacadeIDs.attempt,
            outputIntent: .standard
        )
        missingLease.release()
        missing.audio.store.remove(FacadeIDs.attempt)
        #expect(
            await missing.owner.repairOrphanedCaptureAtProcessLaunch()
                == .blocked
        )
        #expect(try await missing.repository.load().capture?.phase
            == .recording)
    }

    @Test func processLaunchRetriesAtomicWriteFailure()
        async throws {
        let writeFailure = FacadeFixture()
        let writeFailureLease = try await writeFailure.owner.createCapture(
            attemptID: FacadeIDs.attempt,
            outputIntent: .standard
        )
        try await writeFailureLease.beginFinalizing()
        writeFailureLease.release()
        writeFailure.voiceMetadata.failNextWrite = true
        #expect(
            await writeFailure.owner.repairOrphanedCaptureAtProcessLaunch()
                == .blocked
        )
        #expect(try await writeFailure.repository.load().capture?.phase
            == .finalizing)
        #expect(writeFailure.audio.contains(FacadeIDs.attempt))
        #expect(
            await writeFailure.owner.repairOrphanedCaptureAtProcessLaunch()
                == .recoverable(attemptID: FacadeIDs.attempt)
        )
        #expect(try await writeFailure.repository.load().capture?.phase
            == .completed)
        #expect(writeFailure.audio.contains(FacadeIDs.attempt))
    }

    @Test func dispatchReadsBoundedDescriptorAndExecutesOnlyOnce()
        async throws {
        let fixture = FacadeFixture(audioBytes: Array(0..<100))
        let ready = try await fixture.installReady(byteCount: 100)
        let dispatch = try await fixture.owner.beginTranscription(
            expected: ready.expectation,
            transcriptionID: FacadeIDs.operation
        )
        let probe = ReadProbe()
        let executor = ReadingExecutor(probe: probe)

        #expect(try await dispatch.execute(using: executor) == "transcribed")
        #expect(probe.bytes == Data([2, 3, 4, 5]))
        #expect(probe.calls == 1)
        await #expect(
            throws: IOSV1ForegroundVoicePersistenceError
                .dispatchAlreadyExecuted
        ) {
            _ = try await dispatch.execute(using: executor)
        }
    }

    @Test func pendingPlaybackReadsExactAudioWithoutChangingPhase()
        async throws {
        let fixture = FacadeFixture(audioBytes: Array(0..<100))
        let ready = try await fixture.installReady(byteCount: 100)

        let playback = try await fixture.owner
            .preparePendingPlaybackAudio(expected: ready.expectation)

        #expect(playback.format == .m4a)
        #expect(playback.durationMilliseconds == 1_250)
        #expect(playback.byteCount == 100)
        #expect(
            playback.withAudioData { $0 }
                == Data(Array(0..<100))
        )
        #expect(try await fixture.owner.load()?.recording == ready.recording)
    }

    @Test func pendingPlaybackRejectsAStaleExpectationAndPreservesAudio()
        async throws {
        let fixture = FacadeFixture()
        let ready = try await fixture.installReady()
        _ = try await fixture.owner.beginTranscription(
            expected: ready.expectation,
            transcriptionID: FacadeIDs.operation
        )

        await #expect(
            throws: IOSV1ForegroundVoicePersistenceError.stalePending
        ) {
            _ = try await fixture.owner.preparePendingPlaybackAudio(
                expected: ready.expectation
            )
        }
        #expect(fixture.audio.contains(FacadeIDs.attempt))
    }

    @Test func darwinAudioOpenRejectsSymlinkAndWrongIdentity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ios-v1-facade-\(UUID().uuidString)")
        let directory = IOSVoiceStateStorageLocation.directoryURL(in: root)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let file = IOSVoiceStateStorageLocation.audioFileURL(
            for: FacadeIDs.attempt,
            in: root
        )
        try Data([1, 2, 3, 4]).write(to: file)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: file.path
        )
        let fileSystem = IOSV1ForegroundVoiceDarwinAudioFileSystem(
            directoryURL: directory
        )
        let relative = IOSVoiceStateStorageLocation.relativeAudioIdentifier(
            for: FacadeIDs.attempt
        )
        let opened = try fileSystem.openPendingAudio(
            attemptID: FacadeIDs.attempt,
            relativeIdentifier: relative,
            expectedByteCount: 4
        )
        let handle = try #require(opened)
        #expect(
            try fileSystem.read(
                handle,
                atOffset: 1,
                maximumByteCount: 2
            ) == Data([2, 3])
        )
        fileSystem.close(handle)

        let target = root.appendingPathComponent("target")
        try Data([1, 2, 3, 4]).write(to: target)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(
            at: file,
            withDestinationURL: target
        )
        #expect(throws: IOSV1ForegroundVoicePersistenceError.audioInvalid) {
            _ = try fileSystem.openPendingAudio(
                attemptID: FacadeIDs.attempt,
                relativeIdentifier: relative,
                expectedByteCount: 4
            )
        }
    }
}

private final class FacadeFixture: @unchecked Sendable {
    let events = FacadeEventLog()
    let voiceMetadata: FacadeMetadataFileSystem
    let historyMetadata: FacadeMetadataFileSystem
    let repository: IOSVoiceStateRepository
    let history: IOSAcceptedTextHistoryRepository
    let audio: FacadeAudioFileSystem
    let acceptedAudioCache: IOSAcceptedAudioCache
    let acceptedAudioFileSystem: any ProtectedAtomicMetadataFileSystem
    let owner: IOSV1ForegroundVoicePersistenceOwner
    let cacheDirectoryURL: URL

    init(
        audioBytes: [UInt8] = [1, 2, 3, 4],
        orphanMediaValidation:
            Result<Int64, IOSV1VoiceCaptureError> = .success(1_250),
        recordingCachePolicy: RecordingCachePolicy = .deleteImmediately,
        acceptedAudioFileSystem: any ProtectedAtomicMetadataFileSystem =
            FoundationProtectedAtomicMetadataFileSystem(),
        now: @escaping @Sendable () -> Date = { FacadeDates.accepted },
        repositoryNow: @escaping @Sendable () -> Date = {
            FacadeDates.updated
        }
    ) {
        voiceMetadata = FacadeMetadataFileSystem(
            event: "voice-write",
            events: events
        )
        historyMetadata = FacadeMetadataFileSystem(
            event: "history-write",
            events: events
        )
        let root = URL(fileURLWithPath: "/tmp/ios-v1-facade-tests")
        repository = IOSVoiceStateRepository(
            fileURL: root.appendingPathComponent("voice.json"),
            fileSystem: voiceMetadata,
            now: repositoryNow
        )
        history = IOSAcceptedTextHistoryRepository(
            fileURL: root.appendingPathComponent("history.json"),
            fileSystem: historyMetadata
        )
        let audioStore = FacadeAudioStore(
            initial: [FacadeIDs.attempt: Data(audioBytes)]
        )
        audio = FacadeAudioFileSystem(store: audioStore, events: events)
        cacheDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ios-accepted-audio-cache-\(UUID().uuidString)",
                isDirectory: true
            )
        self.acceptedAudioFileSystem = acceptedAudioFileSystem
        acceptedAudioCache = IOSAcceptedAudioCache(
            directoryURL: cacheDirectoryURL,
            fileSystem: acceptedAudioFileSystem
        )
        let captureOwner = IOSV1VoiceCaptureOwner(
            repository: repository,
            directoryURL: root,
            fileSystem: FacadeCaptureFileSystem(store: audioStore),
            mediaValidator: FacadeMediaValidator(
                result: orphanMediaValidation
            )
        )
        owner = IOSV1ForegroundVoicePersistenceOwner(
            repository: repository,
            captureOwner: captureOwner,
            historyRepository: history,
            acceptedAudioCache: acceptedAudioCache,
            audioFileSystem: audio,
            captureMediaValidator: FacadeMediaValidator(
                result: orphanMediaValidation
            ),
            recordingCachePolicy: { recordingCachePolicy },
            now: now
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: cacheDirectoryURL)
    }

    func installReady(
        byteCount: Int64 = 4,
        durationMilliseconds: Int64 = 1_250,
        acceptedAudioRetention: IOSAcceptedAudioRetention =
            .recordingCachePolicy
    ) async throws
        -> IOSV1PendingRecordingObservation {
        let pending = try IOSVoiceStatePending(
            attemptID: FacadeIDs.attempt,
            audioRelativeIdentifier:
                IOSVoiceStateStorageLocation.relativeAudioIdentifier(
                    for: FacadeIDs.attempt
                ),
            createdAt: FacadeDates.created,
            updatedAt: FacadeDates.created,
            outputIntent: .standard,
            transcriptionModel: "whisper-1",
            transcriptionLanguageCode: nil,
            durationMilliseconds: durationMilliseconds,
            byteCount: byteCount,
            acceptedAudioRetention: acceptedAudioRetention,
            status: .ready
        )
        _ = try await repository.installPending(pending)
        return try #require(try await owner.load())
    }

    func moveToOutputDelivery(
        acceptedAudioRetention: IOSAcceptedAudioRetention =
            .recordingCachePolicy
    ) async throws
        -> IOSV1PendingRecordingExpectation {
        let ready = try await installReady(
            acceptedAudioRetention: acceptedAudioRetention
        )
        let dispatch = try await owner.beginTranscription(
            expected: ready.expectation,
            transcriptionID: FacadeIDs.operation
        )
        let post = try await owner.markPostProcessing(
            expected: dispatch.expectation
        )
        let output = try await owner.markOutputDelivery(
            expected: IOSV1PendingRecordingExpectation(recording: post)
        )
        return IOSV1PendingRecordingExpectation(recording: output)
    }

    func acceptance() throws
        -> IOSV1ForegroundVoiceAcceptedOutputPreparation {
        try IOSV1ForegroundVoiceAcceptedOutputPreparation(
            deliveryID: FacadeIDs.result,
            sessionID: FacadeIDs.session,
            attemptID: FacadeIDs.attempt,
            transcriptID: FacadeIDs.operation,
            rawAcceptedText: "accepted text",
            outputIntent: .standard
        )
    }

    func makeRelaunchedOwner() -> (
        owner: IOSV1ForegroundVoicePersistenceOwner,
        cache: IOSAcceptedAudioCache
    ) {
        let freshDirectoryURL = URL(
            fileURLWithPath: cacheDirectoryURL.path,
            isDirectory: true
        )
        let cache = IOSAcceptedAudioCache(
            directoryURL: freshDirectoryURL,
            fileSystem: acceptedAudioFileSystem
        )
        let captureOwner = IOSV1VoiceCaptureOwner(
            repository: repository,
            directoryURL: URL(
                fileURLWithPath: "/tmp/ios-v1-facade-tests",
                isDirectory: true
            ),
            fileSystem: FacadeCaptureFileSystem(store: audio.store),
            mediaValidator: FacadeMediaValidator()
        )
        let owner = IOSV1ForegroundVoicePersistenceOwner(
            repository: repository,
            captureOwner: captureOwner,
            historyRepository: history,
            acceptedAudioCache: cache,
            audioFileSystem: audio,
            captureMediaValidator: FacadeMediaValidator(),
            recordingCachePolicy: { .deleteImmediately },
            now: { FacadeDates.accepted }
        )
        return (owner, cache)
    }
}

private final class FacadeEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] { lock.withLock { storage } }
    func append(_ value: String) { lock.withLock { storage.append(value) } }
    func clear() { lock.withLock { storage.removeAll() } }
}

private final class FacadeMetadataFileSystem:
    ProtectedAtomicMetadataFileSystem,
    @unchecked Sendable {
    private let lock = NSLock()
    private let event: String
    private let events: FacadeEventLog
    private var bytes: Data?
    var failNextWrite = false
    var failAfterSuccessfulWrites: Int?

    init(event: String, events: FacadeEventLog) {
        self.event = event
        self.events = events
    }

    func readFileIfPresent(
        at _: URL,
        policy: ProtectedAtomicMetadataFilePolicy
    ) throws -> Data? {
        try lock.withLock {
            if let bytes, bytes.count > policy.maximumByteCount {
                throw ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded
            }
            return bytes
        }
    }

    func replaceFileAtomically(
        at _: URL,
        with data: Data,
        policy: ProtectedAtomicMetadataFilePolicy
    ) throws {
        events.append(event)
        try lock.withLock {
            if failNextWrite {
                failNextWrite = false
                throw ProtectedAtomicMetadataFileSystemError.writeFailed
            }
            if let remaining = failAfterSuccessfulWrites {
                if remaining == 0 {
                    failAfterSuccessfulWrites = nil
                    throw ProtectedAtomicMetadataFileSystemError.writeFailed
                }
                failAfterSuccessfulWrites = remaining - 1
            }
            guard data.count <= policy.maximumByteCount else {
                throw ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded
            }
            bytes = data
        }
    }

    func removeFileIfPresent(at _: URL) throws {
        lock.withLock { bytes = nil }
    }
}

private final class FacadeAcceptedAudioFileSystem:
    ProtectedAtomicMetadataFileSystem,
    @unchecked Sendable {
    private let lock = NSLock()
    private let base = FoundationProtectedAtomicMetadataFileSystem()
    var failNextRemove = false

    func readFileIfPresent(
        at fileURL: URL,
        policy: ProtectedAtomicMetadataFilePolicy
    ) throws -> Data? {
        try base.readFileIfPresent(at: fileURL, policy: policy)
    }

    func replaceFileAtomically(
        at fileURL: URL,
        with data: Data,
        policy: ProtectedAtomicMetadataFilePolicy
    ) throws {
        try base.replaceFileAtomically(
            at: fileURL,
            with: data,
            policy: policy
        )
    }

    func removeFileIfPresent(at fileURL: URL) throws {
        try lock.withLock {
            if failNextRemove {
                failNextRemove = false
                throw ProtectedAtomicMetadataFileSystemError.removeFailed
            }
        }
        try base.removeFileIfPresent(at: fileURL)
    }
}

private final class FacadeAudioStore: @unchecked Sendable {
    private let lock = NSLock()
    private var files: [UUID: Data]

    init(initial: [UUID: Data]) { files = initial }
    func data(_ id: UUID) -> Data? { lock.withLock { files[id] } }
    func install(_ id: UUID, data: Data) { lock.withLock { files[id] = data } }
    func remove(_ id: UUID) { lock.withLock { files[id] = nil } }
    func contains(_ id: UUID) -> Bool { lock.withLock { files[id] != nil } }
}

private final class FacadeAudioFileSystem:
    IOSV1ForegroundVoiceAudioFileSystem,
    @unchecked Sendable {
    let store: FacadeAudioStore
    let events: FacadeEventLog
    private let lock = NSLock()
    var failNextUnlink = false
    var openError: IOSV1ForegroundVoicePersistenceError?

    init(store: FacadeAudioStore, events: FacadeEventLog) {
        self.store = store
        self.events = events
    }

    func contains(_ id: UUID) -> Bool { store.contains(id) }

    func openPendingAudio(
        attemptID: UUID,
        relativeIdentifier: String,
        expectedByteCount: Int64?
    ) throws -> IOSV1ForegroundVoiceAudioHandle? {
        if let openError { throw openError }
        guard relativeIdentifier == IOSVoiceStateStorageLocation
            .relativeAudioIdentifier(for: attemptID) else {
            throw IOSV1ForegroundVoicePersistenceError.audioInvalid
        }
        guard let data = store.data(attemptID) else { return nil }
        guard expectedByteCount.map({ Int64(data.count) == $0 }) != false else {
            throw IOSV1ForegroundVoicePersistenceError.audioInvalid
        }
        return IOSV1ForegroundVoiceAudioHandle(
            attemptID: attemptID,
            directoryDescriptor: 40,
            fileDescriptor: 41,
            fileName: "pending.m4a",
            directoryDevice: 1,
            directoryInode: 2,
            fileDevice: 3,
            fileInode: 4,
            byteCount: Int64(data.count)
        )
    }

    func read(
        _ handle: IOSV1ForegroundVoiceAudioHandle,
        atOffset offset: Int64,
        maximumByteCount: Int
    ) throws -> Data {
        guard let data = store.data(handle.attemptID) else {
            throw IOSV1ForegroundVoicePersistenceError.audioMissing
        }
        let start = Int(offset)
        let end = min(data.count, start + maximumByteCount)
        return data.subdata(in: start..<end)
    }

    func unlink(_ handle: IOSV1ForegroundVoiceAudioHandle) throws {
        try lock.withLock {
            if failNextUnlink {
                failNextUnlink = false
                throw IOSV1ForegroundVoicePersistenceError.cleanupUncertain
            }
        }
        guard store.contains(handle.attemptID) else { return }
        events.append("audio-unlink")
        store.remove(handle.attemptID)
    }

    func close(_: IOSV1ForegroundVoiceAudioHandle) {}
}

private struct FacadeCaptureFileSystem:
    IOSV1VoiceCaptureFileSystem,
    Sendable {
    let store: FacadeAudioStore

    func create(
        attemptID: UUID,
        directoryURL: URL,
        fileName: String
    ) throws -> IOSV1VoiceCaptureFileHandle {
        if !store.contains(attemptID) {
            store.install(attemptID, data: Data([1, 2, 3, 4]))
        }
        return IOSV1VoiceCaptureFileHandle(
            attemptID: attemptID,
            directoryDescriptor: 50,
            fileDescriptor: 51,
            directoryURL: directoryURL,
            fileName: fileName,
            directoryIdentity: IOSV1VoiceCaptureFileIdentity(
                device: 1,
                inode: 2
            ),
            identity: IOSV1VoiceCaptureFileIdentity(device: 3, inode: 4)
        )
    }

    func validate(
        _ handle: IOSV1VoiceCaptureFileHandle
    ) throws -> IOSV1VoiceCaptureFileFacts {
        guard let data = store.data(handle.attemptID) else {
            throw IOSV1VoiceCaptureError.sourceChanged
        }
        return IOSV1VoiceCaptureFileFacts(
            identity: handle.identity,
            byteCount: Int64(data.count),
            modificationSeconds: 1_700_000_000,
            modificationNanoseconds: 0
        )
    }

    func synchronize(_: IOSV1VoiceCaptureFileHandle) throws {}
    func remove(_ handle: IOSV1VoiceCaptureFileHandle) throws {
        store.remove(handle.attemptID)
    }
    func close(_: IOSV1VoiceCaptureFileHandle) {}
}

private struct FacadeMediaValidator: IOSV1VoiceCaptureMediaValidating {
    let result: Result<Int64, IOSV1VoiceCaptureError>

    init(
        result: Result<Int64, IOSV1VoiceCaptureError> = .success(1_250)
    ) {
        self.result = result
    }

    func durationMilliseconds(
        fileDescriptor _: Int32,
        byteCount _: Int64,
        timeoutNanoseconds _: UInt64
    ) throws -> Int64 { try result.get() }
}

private final class ReadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedBytes = Data()
    private var storedCalls = 0

    var bytes: Data { lock.withLock { storedBytes } }
    var calls: Int { lock.withLock { storedCalls } }
    func record(_ bytes: Data) {
        lock.withLock {
            storedBytes = bytes
            storedCalls += 1
        }
    }
}

private struct ReadingExecutor: IOSV1PendingTranscriptionExecutor {
    let probe: ReadProbe

    func transcribe(
        recording _: IOSV1PendingRecording,
        audio: IOSV1PendingTranscriptionAudio
    ) async throws -> String {
        probe.record(
            try await audio.read(atOffset: 2, maximumByteCount: 4)
        )
        return "transcribed"
    }
}

private enum ProviderCallError: Error, Equatable {
    case failed
}

private final class ProviderCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }

    func increment() {
        lock.withLock { value += 1 }
    }
}

private struct CountingProviderExecutor: IOSV1PendingTranscriptionExecutor {
    enum Outcome: Sendable {
        case failure
        case success(String)
    }

    let calls: ProviderCallCounter
    let outcome: Outcome

    func transcribe(
        recording _: IOSV1PendingRecording,
        audio _: IOSV1PendingTranscriptionAudio
    ) async throws -> String {
        calls.increment()
        switch outcome {
        case .failure:
            throw ProviderCallError.failed
        case .success(let text):
            return text
        }
    }
}

private enum FacadeIDs {
    static let attempt = UUID(
        uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
    )!
    static let operation = UUID(
        uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
    )!
    static let otherOperation = UUID(
        uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC"
    )!
    static let result = UUID(
        uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD"
    )!
    static let previousResult = UUID(
        uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDC"
    )!
    static let session = UUID(
        uuidString: "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE"
    )!
}

private enum FacadeDates {
    static let created = Date(timeIntervalSince1970: 1_700_000_000)
    static let updated = Date(timeIntervalSince1970: 1_700_000_001)
    static let accepted = Date(timeIntervalSince1970: 1_700_000_002)
}
