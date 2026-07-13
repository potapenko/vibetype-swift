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

    @Test func historyFailureWarnsButStillFinishesAcceptedCleanup()
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
        #expect(try await fixture.repository.load().pending == nil)
        #expect(try await fixture.repository.load().latest != nil)
        #expect(!fixture.audio.contains(FacadeIDs.attempt))
        #expect(
            fixture.events.values == [
                "voice-write",
                "history-write",
                "audio-unlink",
                "voice-write",
            ]
        )
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

    @Test func captureRelaunchOffersRecoverOrDiscardWithoutProvider()
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

        let discardOnly = FacadeFixture()
        let unfinished = try await discardOnly.owner.createCapture(
            attemptID: FacadeIDs.attempt,
            outputIntent: .standard
        )
        #expect(
            await discardOnly.owner.reconcileCaptureSourcesAtLaunch()
                == .discardOnly(attemptID: FacadeIDs.attempt)
        )
        try await discardOnly.owner.discardCapture(
            attemptID: FacadeIDs.attempt
        )
        #expect(try await discardOnly.repository.load().capture == nil)
        #expect(!discardOnly.audio.contains(FacadeIDs.attempt))
        unfinished.release()
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
    let owner: IOSV1ForegroundVoicePersistenceOwner

    init(audioBytes: [UInt8] = [1, 2, 3, 4]) {
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
            now: { FacadeDates.updated }
        )
        history = IOSAcceptedTextHistoryRepository(
            fileURL: root.appendingPathComponent("history.json"),
            fileSystem: historyMetadata
        )
        let audioStore = FacadeAudioStore(
            initial: [FacadeIDs.attempt: Data(audioBytes)]
        )
        audio = FacadeAudioFileSystem(store: audioStore, events: events)
        let captureOwner = IOSV1VoiceCaptureOwner(
            repository: repository,
            directoryURL: root,
            fileSystem: FacadeCaptureFileSystem(store: audioStore),
            mediaValidator: FacadeMediaValidator()
        )
        owner = IOSV1ForegroundVoicePersistenceOwner(
            repository: repository,
            captureOwner: captureOwner,
            historyRepository: history,
            audioFileSystem: audio,
            now: { FacadeDates.accepted }
        )
    }

    func installReady(byteCount: Int64 = 4) async throws
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
            durationMilliseconds: 1_250,
            byteCount: byteCount,
            status: .ready
        )
        _ = try await repository.installPending(pending)
        return try #require(try await owner.load())
    }

    func moveToOutputDelivery() async throws
        -> IOSV1PendingRecordingExpectation {
        let ready = try await installReady()
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

private final class FacadeAudioStore: @unchecked Sendable {
    private let lock = NSLock()
    private var files: [UUID: Data]

    init(initial: [UUID: Data]) { files = initial }
    func data(_ id: UUID) -> Data? { lock.withLock { files[id] } }
    func install(_ id: UUID, data: Data) { lock.withLock { files[id] = data } }
    func remove(_ id: UUID) { lock.withLock { files[id] = nil } }
    func contains(_ id: UUID) -> Bool { lock.withLock { files[id] != nil } }
}

private struct FacadeAudioFileSystem:
    IOSV1ForegroundVoiceAudioFileSystem,
    Sendable {
    let store: FacadeAudioStore
    let events: FacadeEventLog

    func contains(_ id: UUID) -> Bool { store.contains(id) }

    func openPendingAudio(
        attemptID: UUID,
        relativeIdentifier: String,
        expectedByteCount: Int64?
    ) throws -> IOSV1ForegroundVoiceAudioHandle? {
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
        store.install(attemptID, data: Data([1, 2, 3, 4]))
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
    func durationMilliseconds(
        fileDescriptor _: Int32,
        byteCount _: Int64,
        timeoutNanoseconds _: UInt64
    ) throws -> Int64 { 1_250 }
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
    static let session = UUID(
        uuidString: "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE"
    )!
}

private enum FacadeDates {
    static let created = Date(timeIntervalSince1970: 1_700_000_000)
    static let updated = Date(timeIntervalSince1970: 1_700_000_001)
    static let accepted = Date(timeIntervalSince1970: 1_700_000_002)
}
