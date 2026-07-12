import Darwin
import Foundation
import HoldTypeDomain
import Testing
@_spi(HoldTypeIOSCore) @testable import HoldTypePersistence

struct IOSForegroundVoiceCaptureSourceWireCodecTests {
    private let attemptID = UUID(
        uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF"
    )!

    @Test func exactWireValuesRoundTripWithoutAlternateLengths() throws {
        let intent = IOSForegroundVoiceCaptureCreationIntent(
            attemptID: attemptID,
            outputIntent: .translate,
            format: .wav,
            creationMilliseconds: 1_750_000_000_123
        )
        let identity = IOSForegroundVoiceCaptureIdentity(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .m4a,
            creationMilliseconds: 1_750_000_000_123,
            device: 0x0102_0304_0506_0708,
            inode: 0x1112_1314_1516_1718,
            generation: 0x2122_2324
        )
        let completion = IOSForegroundVoiceCaptureCompletion(
            durationMilliseconds: 1_500,
            byteCount: 65_537,
            modificationSeconds: -2,
            modificationNanoseconds: 999_999_999
        )

        let intentBytes = IOSForegroundVoiceCaptureSourceWireCodec
            .creationIntent(intent)
        let identityBytes = IOSForegroundVoiceCaptureSourceWireCodec
            .identity(identity)
        let completionBytes = IOSForegroundVoiceCaptureSourceWireCodec
            .completion(completion)

        #expect(intentBytes.count == 27)
        #expect(identityBytes.count == 47)
        #expect(completionBytes.count == 25)
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeCreationIntent(intentBytes) == intent
        )
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeIdentity(identityBytes) == identity
        )
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeCompletion(completionBytes) == completion
        )

        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeCreationIntent(intentBytes + [0]) == nil
        )
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeIdentity(identityBytes + [0]) == nil
        )
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeCompletion(completionBytes + [0]) == nil
        )
    }

    @Test func reservedValuesFutureSchemaAndInvalidTimesAreRejected() {
        let intent = IOSForegroundVoiceCaptureCreationIntent(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .m4a,
            creationMilliseconds: 1
        )
        var bytes = IOSForegroundVoiceCaptureSourceWireCodec.creationIntent(intent)
        bytes[0] = 2
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeCreationIntent(bytes) == nil
        )
        bytes = IOSForegroundVoiceCaptureSourceWireCodec.creationIntent(intent)
        bytes[17] = 0
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeCreationIntent(bytes) == nil
        )
        bytes = IOSForegroundVoiceCaptureSourceWireCodec.creationIntent(intent)
        bytes.replaceSubrange(19..<27, with: repeatElement(0xFF, count: 8))
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeCreationIntent(bytes) == nil
        )

        var completion = IOSForegroundVoiceCaptureSourceWireCodec.completion(
            IOSForegroundVoiceCaptureCompletion(
                durationMilliseconds: 1_000,
                byteCount: 10,
                modificationSeconds: 1,
                modificationNanoseconds: 0
            )
        )
        completion.replaceSubrange(21..<25, with: [0x3B, 0x9A, 0xCA, 0x00])
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeCompletion(completion) == nil
        )
    }

    @Test func canonicalNamesRejectUppercaseAndUnknownExtensions() {
        let finalName = IOSForegroundVoiceCaptureSourceWireCodec.finalName(
            attemptID: attemptID,
            format: .m4a
        )
        #expect(
            finalName
                == "capture-v1-01234567-89ab-cdef-0123-456789abcdef.m4a"
        )
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec.parseFinalName(finalName)?
                .attemptID == attemptID
        )
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec.parseFinalName(
                finalName.uppercased()
            ) == nil
        )
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec.parseFinalName(
                finalName.replacingOccurrences(of: ".m4a", with: ".caf")
            ) == nil
        )
    }
}

struct IOSForegroundVoiceCaptureSourceTests {
    private let attemptID = UUID(
        uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF"
    )!
    private let timestamp = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func creationPublishesStrictSourceAndClearsDurableIntent() async throws {
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let owner = makeOwner(adapter: adapter)

        let lease = try await owner.createCapture(
            attemptID: attemptID,
            outputIntent: .translate,
            format: .wav
        )
        var exposedURL: URL?
        try lease.withTransientRecordingURL { exposedURL = $0 }

        #expect(
            exposedURL?.path
                == "/ApplicationSupport/HoldType/Recordings/Capture/"
                + "capture-v1-01234567-89ab-cdef-0123-456789abcdef.wav"
        )
        #expect(adapter.captureCreationIntent == nil)
        #expect(adapter.captureNames.count == 1)
        #expect(adapter.capturePhase == Array("active-v1".utf8))
        #expect(
            adapter.captureAttribute(
                named: "com.holdtype.ios.capture-source-audio"
            ) == Array("v1".utf8)
        )
        #expect(
            adapter.captureAttribute(
                named: "com.holdtype.ios.capture-source-identity"
            )?.count == 47
        )
        let intentIndex = try #require(
            adapter.events.firstIndex(
                of: "setxattr:com.holdtype.ios.capture-source-creation-intent"
            )
        )
        let createIndex = try #require(
            adapter.events.firstIndex(where: {
                $0.hasPrefix("openat:.capture-source-creating-v1-")
            })
        )
        let removeIndex = try #require(
            adapter.events.firstIndex(
                of: "removexattr:com.holdtype.ios.capture-source-creation-intent"
            )
        )
        #expect(intentIndex < createIndex)
        #expect(createIndex < removeIndex)
        lease.release()
    }

    @Test func liveLeaseRejectsSecondCaptureBeforeFilesystemMutation() async throws {
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let owner = makeOwner(adapter: adapter)
        let lease = try await owner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        let eventCount = adapter.events.count

        await #expect(
            throws: IOSForegroundVoiceCaptureSourceError.captureAlreadyExists
        ) {
            _ = try await owner.createCapture(
                attemptID: UUID(),
                outputIntent: .standard,
                format: .wav
            )
        }

        #expect(adapter.events.count == eventCount)
        lease.release()
    }

    @Test func newProcessOwnerCannotCreateOverExistingUnlockedSource()
        async throws {
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let firstOwner = makeOwner(adapter: adapter)
        let lease = try await firstOwner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        adapter.writeCaptureBytes([1])
        lease.release()
        let secondOwner = makeOwner(adapter: adapter)

        await #expect(
            throws: IOSForegroundVoiceCaptureSourceError.captureAlreadyExists
        ) {
            _ = try await secondOwner.createCapture(
                attemptID: UUID(),
                outputIntent: .standard,
                format: .wav
            )
        }

        #expect(adapter.captureNames.count == 1)
        #expect(adapter.captureCreationIntent == nil)
    }

    @Test func recorderCheckpointsRejectPathReplacementAndModeWeakening()
        async throws {
        let replacementAdapter = SimulatedPendingRecordingPOSIXAdapter(
            sourceBytes: []
        )
        let replacementOwner = makeOwner(adapter: replacementAdapter)
        let replacementLease = try await replacementOwner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        replacementAdapter.replaceCapturePath(with: [1, 2, 3])
        await #expect(
            throws: IOSForegroundVoiceCaptureSourceError.sourceChanged
        ) {
            try await replacementLease.revalidateRecorderCheckpoint()
        }
        replacementLease.release()

        let modeAdapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let modeOwner = makeOwner(adapter: modeAdapter)
        let modeLease = try await modeOwner.createCapture(
            attemptID: UUID(),
            outputIntent: .standard,
            format: .wav
        )
        modeAdapter.setCaptureMode(0o644)
        await #expect(
            throws: IOSForegroundVoiceCaptureSourceError.sourceChanged
        ) {
            try await modeLease.revalidateRecorderCheckpoint()
        }
        modeLease.release()

        let specialModeAdapter = SimulatedPendingRecordingPOSIXAdapter(
            sourceBytes: []
        )
        let specialModeOwner = makeOwner(adapter: specialModeAdapter)
        let specialModeLease = try await specialModeOwner.createCapture(
            attemptID: UUID(),
            outputIntent: .standard,
            format: .wav
        )
        specialModeAdapter.setCaptureMode(0o4600)
        await #expect(
            throws: IOSForegroundVoiceCaptureSourceError.sourceChanged
        ) {
            try await specialModeLease.revalidateRecorderCheckpoint()
        }
        specialModeLease.release()
    }

    @Test func namespacePathReplacementBlocksURLExposureAndMutation()
        async throws {
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let owner = makeOwner(adapter: adapter)
        let lease = try await owner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        adapter.replaceCaptureNamespace()
        var exposed = false

        #expect(
            throws: IOSForegroundVoiceCaptureSourceError.namespaceInvalid
        ) {
            try lease.withTransientRecordingURL { _ in exposed = true }
        }
        await #expect(
            throws: IOSForegroundVoiceCaptureSourceError.namespaceInvalid
        ) {
            try await lease.beginFinalizing()
        }

        #expect(!exposed)
        lease.release()
    }

    @Test func leaseRejectsConcurrentPhaseChangeDuringURLClosure() async throws {
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let owner = makeOwner(adapter: adapter)
        let lease = try await owner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        let entered = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let urlTask = Task.detached {
            try lease.withTransientRecordingURL { _ in
                entered.signal()
                _ = resume.wait(timeout: .now() + 2)
            }
        }
        let didEnter = await Task.detached {
            waitForCaptureSemaphore(entered)
        }.value
        #expect(didEnter)

        await #expect(
            throws: IOSForegroundVoiceCaptureSourceError.invalidLeaseState
        ) {
            try await lease.beginFinalizing()
        }

        resume.signal()
        try await urlTask.value
        lease.release()
    }

    @Test func validCloseCommitsCompletionThenCompletedPhase() async throws {
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let owner = makeOwner(adapter: adapter, durationMilliseconds: 1_500)
        let lease = try await owner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        adapter.writeCaptureBytes([UInt8](repeating: 0x5A, count: 128))

        try await lease.beginFinalizing()
        #expect(adapter.capturePhase == Array("finalizing-v1".utf8))
        let result = try await lease.completeAfterRecorderClose()

        switch result {
        case let .completed(capability):
            #expect(capability.durationMilliseconds == 1_500)
            #expect(capability.byteCount == 128)
            #expect(
                adapter.captureAttribute(
                    named: "com.holdtype.ios.capture-source-completion"
                )?.count == 25
            )
            #expect(adapter.capturePhase == Array("completed-v1".utf8))
            capability.release()
        case .discarded:
            Issue.record("Valid capture was discarded")
        }
        let completionIndex = try #require(
            adapter.events.firstIndex(
                of: "setxattr:com.holdtype.ios.capture-source-completion"
            )
        )
        let completedIndex = try #require(
            adapter.events.lastIndex(
                of: "setxattr:com.holdtype.ios.capture-source-phase"
            )
        )
        #expect(completionIndex < completedIndex)
        #expect(
            adapter.events[(completionIndex + 1)..<completedIndex]
                .contains("fsync:file")
        )
    }

    @Test(arguments: [
        (duration: Int64(0), reason: IOSForegroundVoiceCaptureInvalidReason.tooShort),
        (duration: Int64(299), reason: .tooShort),
        (duration: Int64(300_000), reason: .maximumDurationReached),
    ])
    func invalidDurationIsDurablyDiscarded(
        duration: Int64,
        reason: IOSForegroundVoiceCaptureInvalidReason
    ) async throws {
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let owner = makeOwner(
            adapter: adapter,
            durationMilliseconds: duration
        )
        let lease = try await owner.createCapture(
            attemptID: UUID(),
            outputIntent: .standard,
            format: .wav
        )
        adapter.writeCaptureBytes([1, 2, 3])
        try await lease.beginFinalizing()

        let result = try await lease.completeAfterRecorderClose()

        switch result {
        case let .discarded(actualReason):
            #expect(actualReason == reason)
        case .completed:
            Issue.record("Invalid duration was completed")
        }
        #expect(adapter.captureNames.isEmpty)
        let discardIndex = try #require(
            adapter.events.lastIndex(
                of: "setxattr:com.holdtype.ios.capture-source-phase"
            )
        )
        let unlinkIndex = try #require(
            adapter.events.lastIndex(where: { $0.hasPrefix("unlink:capture-v1-") })
        )
        #expect(discardIndex < unlinkIndex)
        #expect(
            adapter.events[(discardIndex + 1)..<unlinkIndex].contains("fsync:file")
        )
    }

    @Test func emptyCloseDoesNotInvokeMediaAndIsRemoved() async throws {
        let validator = CaptureMediaValidator(result: .success(1_500))
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let owner = makeOwner(adapter: adapter, validator: validator)
        let lease = try await owner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        try await lease.beginFinalizing()

        let result = try await lease.completeAfterRecorderClose()

        switch result {
        case let .discarded(reason): #expect(reason == .empty)
        case .completed: Issue.record("Empty capture was completed")
        }
        #expect(validator.callCount == 0)
        #expect(adapter.captureNames.isEmpty)
    }

    @Test func maximumByteBoundDiscardsBeforeMediaValidation() async throws {
        let validator = CaptureMediaValidator(result: .success(1_500))
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let owner = makeOwner(adapter: adapter, validator: validator)
        let lease = try await owner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        adapter.writeCaptureBytes(
            [UInt8](repeating: 0x5A, count: 25_000_000)
        )
        try await lease.beginFinalizing()

        let result = try await lease.completeAfterRecorderClose()

        guard case let .discarded(reason) = result else {
            Issue.record("Oversized capture was completed")
            return
        }
        #expect(reason == .invalidMedia)
        #expect(validator.callCount == 0)
        #expect(adapter.captureNames.isEmpty)
    }

    @Test func validationTimeoutPreservesFinalizingSource() async throws {
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let validator = CaptureMediaValidator(
            result: .failure(
                IOSPendingRecordingAudioFileSystemError.mediaValidationTimedOut
            )
        )
        let owner = makeOwner(adapter: adapter, validator: validator)
        let lease = try await owner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        adapter.writeCaptureBytes([1, 2, 3])
        try await lease.beginFinalizing()

        await #expect(
            throws: IOSForegroundVoiceCaptureSourceError.mediaValidationTimedOut
        ) {
            _ = try await lease.completeAfterRecorderClose()
        }

        #expect(adapter.captureNames.count == 1)
        #expect(adapter.capturePhase == Array("finalizing-v1".utf8))
        lease.release()
    }

    @Test func protectedDataFailurePreservesSourceWhileCorruptMediaDiscards()
        async throws {
        let protectedAdapter = SimulatedPendingRecordingPOSIXAdapter(
            sourceBytes: []
        )
        let protectedValidator = CaptureMediaValidator(
            result: .failure(
                IOSPendingRecordingAudioFileSystemError
                    .dataProtectionUnavailable
            )
        )
        let protectedOwner = makeOwner(
            adapter: protectedAdapter,
            validator: protectedValidator
        )
        let protectedLease = try await protectedOwner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        protectedAdapter.writeCaptureBytes([1, 2, 3])
        try await protectedLease.beginFinalizing()
        await #expect(
            throws: IOSForegroundVoiceCaptureSourceError
                .dataProtectionUnavailable
        ) {
            _ = try await protectedLease.completeAfterRecorderClose()
        }
        #expect(protectedAdapter.captureNames.count == 1)
        #expect(protectedAdapter.capturePhase == Array("finalizing-v1".utf8))
        protectedLease.release()

        let corruptAdapter = SimulatedPendingRecordingPOSIXAdapter(
            sourceBytes: []
        )
        let corruptValidator = CaptureMediaValidator(
            result: .failure(
                IOSPendingRecordingAudioFileSystemError.mediaValidationFailed
            )
        )
        let corruptOwner = makeOwner(
            adapter: corruptAdapter,
            validator: corruptValidator
        )
        let corruptLease = try await corruptOwner.createCapture(
            attemptID: UUID(),
            outputIntent: .standard,
            format: .wav
        )
        corruptAdapter.writeCaptureBytes([1, 2, 3])
        try await corruptLease.beginFinalizing()
        let result = try await corruptLease.completeAfterRecorderClose()
        guard case let .discarded(reason) = result else {
            Issue.record("Corrupt media was completed")
            return
        }
        #expect(reason == .invalidMedia)
        #expect(corruptAdapter.captureNames.isEmpty)
    }

    @Test func cancelSynchronizesDiscardingBeforeIdentityPinnedUnlink()
        async throws {
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let owner = makeOwner(adapter: adapter)
        let lease = try await owner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        adapter.writeCaptureBytes([1, 2, 3])

        try await lease.beginDiscardingBeforeRecorderStop()
        #expect(adapter.captureNames.count == 1)
        try await lease.finishDiscardAfterRecorderStop()

        #expect(adapter.captureNames.isEmpty)
        let phaseIndex = try #require(
            adapter.events.lastIndex(
                of: "setxattr:com.holdtype.ios.capture-source-phase"
            )
        )
        let unlinkIndex = try #require(
            adapter.events.lastIndex(where: { $0.hasPrefix("unlink:capture-v1-") })
        )
        #expect(phaseIndex < unlinkIndex)
        #expect(adapter.events[(phaseIndex + 1)..<unlinkIndex].contains("fsync:file"))
    }

    @Test func uncertainDirectorySyncAfterUnlinkNeverReportsSuccess()
        async throws {
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let owner = makeOwner(adapter: adapter)
        let lease = try await owner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        adapter.failNext("fsyncDirectory", errors: [EIO])

        await #expect(
            throws: IOSForegroundVoiceCaptureSourceError.cleanupUncertain
        ) {
            try await lease.beginDiscardingBeforeRecorderStop()
            try await lease.finishDiscardAfterRecorderStop()
        }

        #expect(adapter.captureNames.isEmpty)
        adapter.installRecreatedCapturePath(
            attemptID: attemptID,
            format: .wav,
            bytes: [9, 9, 9]
        )
        try await lease.finishDiscardAfterRecorderStop()
        #expect(adapter.captureBytes == [9, 9, 9])
    }

    @Test func committedUnlinkErrorIsConfirmedFromHeldDescriptor()
        async throws {
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let owner = makeOwner(adapter: adapter)
        let lease = try await owner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        try await lease.beginDiscardingBeforeRecorderStop()
        adapter.failNextUnlinkAfterCommit(with: EIO)

        try await lease.finishDiscardAfterRecorderStop()

        #expect(adapter.captureNames.isEmpty)
    }

    @Test func relaunchClassifiesPositiveActiveFinalizingAndCompleted()
        async throws {
        let activeAdapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let activeOwner = makeOwner(adapter: activeAdapter)
        let activeLease = try await activeOwner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        activeAdapter.writeCaptureBytes([1, 2, 3])
        activeLease.release()
        #expect(
            await activeOwner.reconcileCaptureSourcesAtLaunch().status
                == .activeNeedsRecovery
        )

        let finalizingAdapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let finalizingOwner = makeOwner(adapter: finalizingAdapter)
        let finalizingLease = try await finalizingOwner.createCapture(
            attemptID: UUID(),
            outputIntent: .standard,
            format: .wav
        )
        finalizingAdapter.writeCaptureBytes([1, 2, 3])
        try await finalizingLease.beginFinalizing()
        finalizingLease.release()
        #expect(
            await finalizingOwner.reconcileCaptureSourcesAtLaunch().status
                == .finalizingNeedsRecovery
        )

        let completedAdapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let completedOwner = makeOwner(adapter: completedAdapter)
        let completedLease = try await completedOwner.createCapture(
            attemptID: UUID(),
            outputIntent: .standard,
            format: .wav
        )
        completedAdapter.writeCaptureBytes([1, 2, 3])
        try await completedLease.beginFinalizing()
        let result = try await completedLease.completeAfterRecorderClose()
        guard case let .completed(capability) = result else {
            Issue.record("Expected completed capture")
            return
        }
        capability.release()
        #expect(
            await completedOwner.reconcileCaptureSourcesAtLaunch().status
                == .completedNeedsPendingHandoff
        )
    }

    @Test func relaunchPreservesMalformedSourceAndReportsRedactedValues()
        async throws {
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let owner = makeOwner(adapter: adapter)
        let lease = try await owner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        adapter.setCaptureAttribute(
            named: "com.holdtype.ios.capture-source-phase",
            value: Array("future-v2".utf8)
        )
        lease.release()

        let observation = await owner.reconcileCaptureSourcesAtLaunch()

        #expect(observation.status == .blockedUnknown)
        #expect(adapter.captureNames.count == 1)
        #expect(String(describing: observation).contains("redacted"))
        #expect(String(describing: lease).contains("redacted"))
        #expect(
            String(
                describing: IOSForegroundVoiceCaptureSourceError.sourceChanged
            ).contains("redacted")
        )
    }

    @Test func exactOldZeroByteActiveSourceIsAbandonedButYoungOneIsNot()
        async throws {
        let clock = CaptureWallClock(
            Date(timeIntervalSince1970: 2)
        )
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let owner = makeOwner(adapter: adapter, wallClock: clock)
        let lease = try await owner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        lease.release()

        #expect(
            await owner.reconcileCaptureSourcesAtLaunch().status
                == .emptyActiveNeedsDiscard
        )
        #expect(adapter.captureNames.count == 1)

        clock.value = Date(timeIntervalSince1970: 3_603)
        let observation = await owner.reconcileCaptureSourcesAtLaunch()
        #expect(observation.status == .cleanupPerformed)
        #expect(observation.removedEntryCount == 1)
        #expect(adapter.captureNames.isEmpty)
    }

    @Test func relaunchReconcilesOnlyExactCreationIntentCrashWindows()
        async throws {
        let intent = IOSForegroundVoiceCaptureCreationIntent(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav,
            creationMilliseconds: UInt64(
                timestamp.timeIntervalSince1970 * 1_000
            )
        )
        let intentBytes = IOSForegroundVoiceCaptureSourceWireCodec
            .creationIntent(intent)

        let publishedAdapter = SimulatedPendingRecordingPOSIXAdapter(
            sourceBytes: []
        )
        let publishedOwner = makeOwner(adapter: publishedAdapter)
        let publishedLease = try await publishedOwner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        publishedAdapter.writeCaptureBytes([1])
        publishedAdapter.setCaptureNamespaceAttribute(
            named: IOSForegroundVoiceCaptureSourceFileSystem.creationIntentName,
            value: intentBytes
        )
        publishedLease.release()
        let publishedObservation = await publishedOwner
            .reconcileCaptureSourcesAtLaunch()
        #expect(publishedObservation.status == .activeNeedsRecovery)
        #expect(publishedAdapter.captureCreationIntent == nil)
        #expect(publishedAdapter.captureNames.count == 1)

        let hiddenAdapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let hiddenOwner = makeOwner(adapter: hiddenAdapter)
        let hiddenLease = try await hiddenOwner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        hiddenLease.release()
        hiddenAdapter.movePublishedCaptureToHiddenName(
            attemptID: attemptID,
            format: .wav
        )
        hiddenAdapter.setCaptureNamespaceAttribute(
            named: IOSForegroundVoiceCaptureSourceFileSystem.creationIntentName,
            value: intentBytes
        )
        let hiddenObservation = await hiddenOwner
            .reconcileCaptureSourcesAtLaunch()
        #expect(hiddenObservation.status == .cleanupPerformed)
        #expect(hiddenObservation.removedEntryCount == 1)
        #expect(hiddenAdapter.captureCreationIntent == nil)
        #expect(hiddenAdapter.captureNames.isEmpty)
    }

    @Test func passiveMissingNamespaceIsNoOpAndNeverCreatesDirectories() async {
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let owner = makeOwner(
            adapter: adapter,
            monotonicClock: { nil }
        )

        let observation = await owner.reconcileCaptureSourcesAtLaunch()

        #expect(observation.status == .empty)
        #expect(!adapter.events.contains(where: { $0.hasPrefix("mkdir:") }))
    }

    @Test func relaunchRejectsExactOversizedCompletedManifest() async throws {
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let owner = makeOwner(adapter: adapter)
        let lease = try await owner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        adapter.writeCaptureBytes([1, 2, 3])
        try await lease.beginFinalizing()
        let result = try await lease.completeAfterRecorderClose()
        guard case let .completed(capability) = result else {
            Issue.record("Fixture capture did not complete")
            return
        }
        capability.release()
        adapter.writeCaptureBytes(
            [UInt8](repeating: 0x5A, count: 25_000_000)
        )
        let modificationSeconds = try #require(
            adapter.captureModificationSeconds
        )
        adapter.setCaptureAttribute(
            named: IOSForegroundVoiceCaptureSourceFileSystem.completionName,
            value: IOSForegroundVoiceCaptureSourceWireCodec.completion(
                IOSForegroundVoiceCaptureCompletion(
                    durationMilliseconds: 1_500,
                    byteCount: 25_000_000,
                    modificationSeconds: modificationSeconds,
                    modificationNanoseconds: 0
                )
            )
        )

        let observation = await owner.reconcileCaptureSourcesAtLaunch()

        #expect(observation.status == .blockedUnknown)
        #expect(adapter.captureNames.count == 1)
    }

    @Test func relaunchDeadlineExpiryAfterValidationPreservesOldSource()
        async throws {
        let wallClock = CaptureWallClock(Date(timeIntervalSince1970: 2))
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [])
        let creationOwner = makeOwner(
            adapter: adapter,
            wallClock: wallClock
        )
        let lease = try await creationOwner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        lease.release()
        wallClock.value = Date(timeIntervalSince1970: 3_603)
        adapter.resetEvents()
        let reconciliationOwner = makeOwner(
            adapter: adapter,
            wallClock: wallClock,
            monotonicClock: {
                adapter.events.contains(
                    "getxattr:com.holdtype.ios.capture-source-phase"
                ) ? 600_000_000 : 0
            }
        )

        let observation = await reconciliationOwner
            .reconcileCaptureSourcesAtLaunch()

        #expect(observation.status == .blockedUnknown)
        #expect(adapter.capturePhase == Array("active-v1".utf8))
        #expect(adapter.captureNames.count == 1)
    }

    @Test func liveFilesystemKeepsDescriptorIdentityAcrossRecorderStyleTruncate()
        async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-capture-live-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        _ = chmod(root.path, mode_t(0o700))
        let adapter = LiveCapturePOSIXAdapter()
        let owner = IOSForegroundVoiceCaptureSourceOwner(
            applicationSupportDirectoryURL: root,
            adapter: adapter,
            mediaValidator: CaptureMediaValidator(result: .success(1_500)),
            now: { self.timestamp },
            monotonicClock: { 1_000_000 }
        )
        let lease = try await owner.createCapture(
            attemptID: attemptID,
            outputIntent: .standard,
            format: .wav
        )
        try lease.withTransientRecordingURL { URL in
            let descriptor = URL.path.withCString {
                Darwin.open($0, O_WRONLY | O_TRUNC | O_NOFOLLOW | O_CLOEXEC)
            }
            #expect(descriptor >= 0)
            guard descriptor >= 0 else { return }
            defer { Darwin.close(descriptor) }
            let bytes = [UInt8](repeating: 0x5A, count: 256)
            let count = bytes.withUnsafeBytes {
                Darwin.write(descriptor, $0.baseAddress, $0.count)
            }
            #expect(count == bytes.count)
            #expect(Darwin.fsync(descriptor) == 0)
        }

        try await lease.revalidateRecorderCheckpoint()
        try await lease.beginFinalizing()
        let result = try await lease.completeAfterRecorderClose()
        guard case let .completed(capability) = result else {
            Issue.record("Live descriptor-backed source did not complete")
            return
        }
        #expect(capability.byteCount == 256)
        capability.release()
        #expect(
            await owner.reconcileCaptureSourcesAtLaunch().status
                == .completedNeedsPendingHandoff
        )
    }

    private func makeOwner(
        adapter: SimulatedPendingRecordingPOSIXAdapter,
        durationMilliseconds: Int64 = 1_500,
        validator: CaptureMediaValidator? = nil,
        wallClock: CaptureWallClock? = nil,
        monotonicClock: @escaping @Sendable () -> UInt64? = { 1_000_000 }
    ) -> IOSForegroundVoiceCaptureSourceOwner {
        let wallClock = wallClock ?? CaptureWallClock(timestamp)
        return IOSForegroundVoiceCaptureSourceOwner(
            applicationSupportDirectoryURL: URL(
                fileURLWithPath: "/ApplicationSupport",
                isDirectory: true
            ),
            adapter: adapter,
            mediaValidator: validator ?? CaptureMediaValidator(
                result: .success(durationMilliseconds)
            ),
            now: { wallClock.value },
            monotonicClock: monotonicClock
        )
    }
}

private final class CaptureMediaValidator:
    IOSPendingRecordingMediaValidating,
    @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<Int64, Error>
    private var storedCallCount = 0

    init(result: Result<Int64, Error>) {
        self.result = result
    }

    var callCount: Int { lock.withLock { storedCallCount } }

    func durationMilliseconds(
        forFileDescriptor fileDescriptor: Int32,
        byteCount: Int64,
        format: IOSPendingRecordingAudioFormat,
        timeoutNanoseconds: UInt64
    ) throws -> Int64 {
        _ = fileDescriptor
        _ = byteCount
        _ = format
        _ = timeoutNanoseconds
        lock.withLock { storedCallCount += 1 }
        return try result.get()
    }
}

private final class CaptureWallClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date

    init(_ value: Date) { storedValue = value }

    var value: Date {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private func waitForCaptureSemaphore(_ semaphore: DispatchSemaphore) -> Bool {
    semaphore.wait(timeout: .now() + 2) == .success
}

private final class LiveCapturePOSIXAdapter:
    IOSPendingRecordingPOSIXAdapter,
    @unchecked Sendable {
    private struct PhysicalIdentity: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    private let lock = NSLock()
    private let base = DarwinIOSPendingRecordingPOSIXAdapter()
    private var protectionClasses: [PhysicalIdentity: Int32] = [:]

    func effectiveUserID() -> IOSPendingRecordingPOSIXResult<uid_t> {
        base.effectiveUserID()
    }

    func openPath(
        _ path: String,
        flags: Int32,
        mode: mode_t?
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        base.openPath(path, flags: flags, mode: mode)
    }

    func openAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32,
        mode: mode_t?
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        base.openAt(
            directoryDescriptor: directoryDescriptor,
            name: name,
            flags: flags,
            mode: mode
        )
    }

    func makeDirectoryAt(
        directoryDescriptor: Int32,
        name: String,
        mode: mode_t
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.makeDirectoryAt(
            directoryDescriptor: directoryDescriptor,
            name: name,
            mode: mode
        )
    }

    func status(of fileDescriptor: Int32) -> IOSPendingRecordingPOSIXResult<stat> {
        base.status(of: fileDescriptor)
    }

    func statusAtPath(_ path: String) -> IOSPendingRecordingPOSIXResult<stat> {
        base.statusAtPath(path)
    }

    func statusAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<stat> {
        base.statusAt(
            directoryDescriptor: directoryDescriptor,
            name: name,
            flags: flags
        )
    }

    func read(
        fileDescriptor: Int32,
        buffer: UnsafeMutableRawPointer,
        byteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        base.read(
            fileDescriptor: fileDescriptor,
            buffer: buffer,
            byteCount: byteCount
        )
    }

    func readAt(
        fileDescriptor: Int32,
        buffer: UnsafeMutableRawPointer,
        byteCount: Int,
        offset: Int64
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        base.readAt(
            fileDescriptor: fileDescriptor,
            buffer: buffer,
            byteCount: byteCount,
            offset: offset
        )
    }

    func write(
        fileDescriptor: Int32,
        buffer: UnsafeRawPointer,
        byteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        base.write(
            fileDescriptor: fileDescriptor,
            buffer: buffer,
            byteCount: byteCount
        )
    }

    func synchronize(fileDescriptor: Int32) -> IOSPendingRecordingPOSIXResult<Void> {
        base.synchronize(fileDescriptor: fileDescriptor)
    }

    func changeMode(
        fileDescriptor: Int32,
        mode: mode_t
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.changeMode(fileDescriptor: fileDescriptor, mode: mode)
    }

    func lock(
        fileDescriptor: Int32,
        operation: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.lock(fileDescriptor: fileDescriptor, operation: operation)
    }

    func setExtendedAttribute(
        fileDescriptor: Int32,
        name: String,
        value: [UInt8],
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.setExtendedAttribute(
            fileDescriptor: fileDescriptor,
            name: name,
            value: value,
            flags: flags
        )
    }

    func extendedAttribute(
        fileDescriptor: Int32,
        name: String,
        maximumByteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<[UInt8]> {
        base.extendedAttribute(
            fileDescriptor: fileDescriptor,
            name: name,
            maximumByteCount: maximumByteCount
        )
    }

    func removeExtendedAttribute(
        fileDescriptor: Int32,
        name: String
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.removeExtendedAttribute(fileDescriptor: fileDescriptor, name: name)
    }

    func setProtectionClass(
        fileDescriptor: Int32,
        protectionClass: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        guard let identity = identity(fileDescriptor) else { return .failure(EBADF) }
        lock.withLock { protectionClasses[identity] = protectionClass }
        return .success(())
    }

    func protectionClass(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        guard let identity = identity(fileDescriptor) else { return .failure(EBADF) }
        guard let value = lock.withLock({ protectionClasses[identity] }) else {
            return .failure(ENOATTR)
        }
        return .success(value)
    }

    func publishExclusively(
        directoryDescriptor: Int32,
        temporaryName: String,
        finalName: String
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.publishExclusively(
            directoryDescriptor: directoryDescriptor,
            temporaryName: temporaryName,
            finalName: finalName
        )
    }

    func unlinkAt(
        directoryDescriptor: Int32,
        name: String
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.unlinkAt(directoryDescriptor: directoryDescriptor, name: name)
    }

    func openDirectoryStream(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<UnsafeMutablePointer<DIR>> {
        base.openDirectoryStream(fileDescriptor: fileDescriptor)
    }

    func nextDirectoryEntry(
        stream: UnsafeMutablePointer<DIR>
    ) -> IOSPendingRecordingPOSIXResult<IOSPendingRecordingDirectoryEntry?> {
        base.nextDirectoryEntry(stream: stream)
    }

    func closeFile(_ fileDescriptor: Int32) {
        base.closeFile(fileDescriptor)
    }

    func closeDirectoryStream(_ stream: UnsafeMutablePointer<DIR>) {
        base.closeDirectoryStream(stream)
    }

    private func identity(_ descriptor: Int32) -> PhysicalIdentity? {
        guard case let .success(status) = base.status(of: descriptor) else {
            return nil
        }
        return PhysicalIdentity(device: status.st_dev, inode: status.st_ino)
    }
}
