import AVFoundation
import Darwin
import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSPendingRecordingAudioFileSystemTests {
    private let attemptID = UUID(
        uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF"
    )!

    @Test func mismatchedOpenedRepositoryRootCannotPublishDestinationBytes()
        async {
        let bytes = [UInt8](repeating: 0x5A, count: 64)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(
            sourceBytes: bytes
        )
        let fileSystem = makeFileSystem(adapter: adapter)

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError
                .repositoryIdentityConflict
        ) {
            _ = try await fileSystem.publishProtectedCopy(
                from: artifact(byteCount: bytes.count),
                attemptID: attemptID,
                format: .m4a,
                durationMilliseconds: 1_500,
                expectedRepositoryRoot:
                    IOSPersistenceRepositoryRootIdentity(
                        device: dev_t.max,
                        inode: ino_t.max
                    )
            )
        }

        #expect(adapter.publishedBytes == nil)
        #expect(!adapter.events.contains(where: { $0.hasPrefix("mkdir:") }))
        #expect(!adapter.events.contains("publish-exclusive"))
    }

    @Test func publishConfiguresBeforeWritingStreamsAndKeepsCreatorLease() async throws {
        let bytes = [UInt8](repeating: 0x5A, count: 131_073)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        let media = FakePendingRecordingMediaValidator(durations: [1_500])
        let fileSystem = makeFileSystem(adapter: adapter, media: media)

        let lease = try await fileSystem.publishProtectedCopy(
            from: artifact(byteCount: bytes.count),
            attemptID: attemptID,
            format: .m4a,
            durationMilliseconds: 1_500
        )

        #expect(
            lease.relativeIdentifier ==
                "Recordings/Pending/recording-v1-01234567-89ab-cdef-0123-456789abcdef.m4a"
        )
        #expect(lease.audioArtifact.byteCount == Int64(bytes.count))
        #expect(adapter.publishedBytes == bytes)
        #expect(adapter.sourceBytes == bytes)
        #expect(adapter.maximumReadRequest <= 64 * 1_024)
        #expect(adapter.maximumWriteRequest <= 64 * 1_024)
        #expect(adapter.sourceOpenFlags & O_NOFOLLOW != 0)
        #expect(media.requestedTimeouts == [2_000_000_000])

        let events = adapter.events
        let firstWrite = try #require(events.firstIndex(where: { $0.hasPrefix("write:") }))
        let marker = try #require(
            events.firstIndex(of: "setxattr:com.holdtype.ios.pending-recording-audio")
        )
        let protection = try #require(events.firstIndex(of: "setprotection:1"))
        let backup = try #require(
            events.firstIndex(
                of: "setxattr:com.apple.metadata:com_apple_backup_excludeItem"
            )
        )
        #expect(marker < firstWrite)
        #expect(protection < firstWrite)
        #expect(backup < firstWrite)
        #expect(events.contains("publish-exclusive"))
        #expect(events.contains("fsync:file"))
        #expect(events.contains("fsync:directory"))
        #expect(
            events[..<firstWrite].filter { $0 == "fsync:directory" }.count == 6
        )
        #expect(events.filter { $0 == "fsync:directory" }.count == 7)

        await #expect(throws: IOSPendingRecordingAudioFileSystemError.removeFailed) {
            _ = try await fileSystem.removePublishedAudioIfPresent(
                relativeIdentifier: lease.relativeIdentifier,
                attemptID: attemptID,
                expectedByteCount: Int64(bytes.count)
            )
        }
        #expect(adapter.publishedBytes == bytes)

        lease.release()
        #expect(
            try await fileSystem.removePublishedAudioIfPresent(
                relativeIdentifier: lease.relativeIdentifier,
                attemptID: attemptID,
                expectedByteCount: Int64(bytes.count)
            )
        )
        #expect(adapter.publishedBytes == nil)
        #expect(adapter.sourceBytes == bytes)
        #expect(
            try await fileSystem.removePublishedAudioIfPresent(
                relativeIdentifier: lease.relativeIdentifier,
                attemptID: attemptID,
                expectedByteCount: Int64(bytes.count)
            ) == false
        )
    }

    @Test func sourceContractIsRejectedBeforeFilesystemMutation() async {
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: [1])
        let fileSystem = makeFileSystem(adapter: adapter)
        let invalid = AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/source.M4A"),
            duration: 1.5,
            byteCount: 1
        )

        await #expect(throws: IOSPendingRecordingAudioFileSystemError.invalidSource) {
            _ = try await fileSystem.publishProtectedCopy(
                from: invalid,
                attemptID: attemptID,
                format: .m4a,
                durationMilliseconds: 1_500
            )
        }
        #expect(!adapter.events.contains(where: { $0.hasPrefix("mkdir:") }))
        #expect(!adapter.events.contains(where: { $0.hasPrefix("write:") }))
        #expect(adapter.sourceBytes == [1])
    }

    @Test func ninthConsecutiveEINTRFailsAndCleansOnlyOwnedStaging() async {
        let bytes = [UInt8](repeating: 0x33, count: 16)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        adapter.failNext("read", errors: Array(repeating: EINTR, count: 9))
        let fileSystem = makeFileSystem(adapter: adapter)

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError.sourceUnavailable
        ) {
            _ = try await fileSystem.publishProtectedCopy(
                from: artifact(byteCount: bytes.count),
                attemptID: attemptID,
                format: .m4a,
                durationMilliseconds: 1_500
            )
        }

        #expect(adapter.readCallCount == 9)
        #expect(adapter.pendingNames.isEmpty)
        #expect(adapter.sourceBytes == bytes)
    }

    @Test func eightEINTRRetriesAndPartialReadsAndWritesStillPublish() async throws {
        let bytes = Array(UInt8(0)..<UInt8(40))
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        adapter.failNext("read", errors: Array(repeating: EINTR, count: 8))
        adapter.failNext("write", errors: Array(repeating: EINTR, count: 8))
        adapter.setTransferLimits(read: 7, write: 3)
        let fileSystem = makeFileSystem(adapter: adapter)

        let lease = try await fileSystem.publishProtectedCopy(
            from: artifact(byteCount: bytes.count),
            attemptID: attemptID,
            format: .m4a,
            durationMilliseconds: 1_500
        )

        #expect(adapter.publishedBytes == bytes)
        #expect(adapter.maximumReadResult <= 7)
        #expect(adapter.maximumWriteResult <= 3)
        lease.release()
    }

    @Test func protectionMustBeAppliedBeforeTheFirstContentByte() async {
        let bytes = [UInt8](repeating: 0x7A, count: 16)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        adapter.failNext("setProtection", errors: [EPERM])
        let fileSystem = makeFileSystem(adapter: adapter)

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        ) {
            _ = try await fileSystem.publishProtectedCopy(
                from: artifact(byteCount: bytes.count),
                attemptID: attemptID,
                format: .m4a,
                durationMilliseconds: 1_500
            )
        }

        #expect(!adapter.events.contains(where: { $0.hasPrefix("write:") }))
        #expect(adapter.pendingNames.isEmpty)
        #expect(adapter.sourceBytes == bytes)
    }

    @Test func monotonicDeadlineStopsBeforeAQueuedSyscall() async {
        let bytes = [UInt8](repeating: 0x44, count: 16)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        let clock = StepPendingRecordingClock(stepNanoseconds: 2_000_000_000)
        let fileSystem = makeFileSystem(
            adapter: adapter,
            clock: { clock.now() }
        )

        await #expect(throws: IOSPendingRecordingAudioFileSystemError.operationTimedOut) {
            _ = try await fileSystem.publishProtectedCopy(
                from: artifact(byteCount: bytes.count),
                attemptID: attemptID,
                format: .m4a,
                durationMilliseconds: 1_500
            )
        }

        #expect(adapter.publishedBytes == nil)
        #expect(adapter.sourceBytes == bytes)
    }

    @Test func mediaFailurePreventsPublicationAndPreservesSource() async {
        let bytes = [UInt8](repeating: 0x55, count: 24)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        let media = FakePendingRecordingMediaValidator(durations: [1_751])
        let fileSystem = makeFileSystem(adapter: adapter, media: media)

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError.mediaValidationFailed
        ) {
            _ = try await fileSystem.publishProtectedCopy(
                from: artifact(byteCount: bytes.count),
                attemptID: attemptID,
                format: .m4a,
                durationMilliseconds: 1_500
            )
        }

        #expect(!adapter.events.contains("publish-exclusive"))
        #expect(adapter.pendingNames.isEmpty)
        #expect(adapter.sourceBytes == bytes)
    }

    @Test func directorySynchronizationFailurePreservesPublishedRecoveryAudio() async {
        let bytes = [UInt8](repeating: 0x59, count: 24)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        adapter.createEmptyPendingNamespace()
        adapter.failNext("fsyncDirectory", errors: [EIO])
        let fileSystem = makeFileSystem(adapter: adapter)

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError.synchronizationFailed
        ) {
            _ = try await fileSystem.publishProtectedCopy(
                from: artifact(byteCount: bytes.count),
                attemptID: attemptID,
                format: .m4a,
                durationMilliseconds: 1_500
            )
        }

        #expect(adapter.events.contains("publish-exclusive"))
        #expect(adapter.publishedBytes == bytes)
        #expect(adapter.pendingNames == [finalName])
        #expect(adapter.sourceBytes == bytes)
    }

    @Test func newDirectorySynchronizationFailureStopsBeforeAudioWrite() async {
        let bytes = [UInt8](repeating: 0x58, count: 24)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        adapter.failNext("fsyncDirectory", errors: [EIO])
        let fileSystem = makeFileSystem(adapter: adapter)

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError.synchronizationFailed
        ) {
            _ = try await fileSystem.publishProtectedCopy(
                from: artifact(byteCount: bytes.count),
                attemptID: attemptID,
                format: .m4a,
                durationMilliseconds: 1_500
            )
        }

        #expect(!adapter.events.contains(where: { $0.hasPrefix("write:") }))
        #expect(!adapter.events.contains("publish-exclusive"))
        #expect(adapter.sourceBytes == bytes)
    }

    @Test func sourcePathReplacementAfterCopyCannotPublish() async {
        let bytes = [UInt8](repeating: 0x66, count: 32)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        adapter.replaceSourcePathAtEndOfFile = true
        let fileSystem = makeFileSystem(adapter: adapter)

        await #expect(throws: IOSPendingRecordingAudioFileSystemError.sourceChanged) {
            _ = try await fileSystem.publishProtectedCopy(
                from: artifact(byteCount: bytes.count),
                attemptID: attemptID,
                format: .m4a,
                durationMilliseconds: 1_500
            )
        }

        #expect(adapter.publishedBytes == nil)
        #expect(!adapter.events.contains("publish-exclusive"))
    }

    @Test func validationRepeatsMediaAndIdentityChecksAtEveryHandoff() async throws {
        let bytes = [UInt8](repeating: 0x77, count: 40)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        let media = FakePendingRecordingMediaValidator(durations: [1_500, 1_500])
        let fileSystem = makeFileSystem(adapter: adapter, media: media)
        let lease = try await fileSystem.publishProtectedCopy(
            from: artifact(byteCount: bytes.count),
            attemptID: attemptID,
            format: .m4a,
            durationMilliseconds: 1_500
        )
        lease.release()

        let validated = try await fileSystem.validatePublishedAudio(
            relativeIdentifier: lease.relativeIdentifier,
            attemptID: attemptID,
            durationMilliseconds: 1_500,
            byteCount: Int64(bytes.count)
        )

        #expect(validated.fileURL == lease.audioArtifact.fileURL)
        #expect(validated.byteCount == Int64(bytes.count))
        #expect(media.requestedTimeouts == [2_000_000_000, 2_000_000_000])
        #expect(adapter.markerReadCount >= 4)
    }

    @Test func handoffRejectsMutatedOwnerOnlyModeWithoutRemovingAudio() async throws {
        let bytes = [UInt8](repeating: 0x78, count: 40)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        let fileSystem = makeFileSystem(adapter: adapter)
        let lease = try await fileSystem.publishProtectedCopy(
            from: artifact(byteCount: bytes.count),
            attemptID: attemptID,
            format: .m4a,
            durationMilliseconds: 1_500
        )
        lease.release()
        adapter.setPublishedMode(mode_t(0o640))

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        ) {
            _ = try await fileSystem.validatePublishedAudio(
                relativeIdentifier: lease.relativeIdentifier,
                attemptID: attemptID,
                durationMilliseconds: 1_500,
                byteCount: Int64(bytes.count)
            )
        }

        #expect(adapter.publishedBytes == bytes)
        #expect(adapter.sourceBytes == bytes)
    }

    @Test func transcriptionAudioReadsPinnedDescriptorAcrossTransientPathSwap()
        async throws {
        let bytes = Array(UInt8(0)..<UInt8(40))
        let replacementBytes = [UInt8](repeating: 0xEE, count: bytes.count)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        let media = FakePendingRecordingMediaValidator(
            durations: [1_500, 1_500]
        )
        let fileSystem = makeFileSystem(adapter: adapter, media: media)
        let creatorLease = try await fileSystem.publishProtectedCopy(
            from: artifact(byteCount: bytes.count),
            attemptID: attemptID,
            format: .m4a,
            durationMilliseconds: 1_500
        )
        creatorLease.release()
        let providerLease = try await fileSystem.acquireValidatedPublishedAudio(
            relativeIdentifier: creatorLease.relativeIdentifier,
            attemptID: attemptID,
            durationMilliseconds: 1_500,
            byteCount: Int64(bytes.count)
        )
        let audio = IOSPendingTranscriptionAudio(lease: providerLease)
        adapter.transientlyReplacePublishedPathDuringNextPread(
            with: replacementBytes
        )

        let readBytes = try await audio.read(
            atOffset: 0,
            maximumByteCount: bytes.count
        )

        #expect(Array(readBytes) == bytes)
        #expect(Array(readBytes) != replacementBytes)
        #expect(adapter.didUseTransientPreadReplacement)
        #expect(audio.format == .m4a)
        #expect(audio.byteCount == Int64(bytes.count))
        #expect(audio.durationMilliseconds == 1_500)
        #expect(String(describing: audio).contains("redacted"))

        audio.invalidate()
        await #expect(
            throws: IOSPendingRecordingError.dispatchAlreadyCommitted
        ) {
            _ = try await audio.read(atOffset: 0, maximumByteCount: 1)
        }
    }

    @Test func wrongProtectionPolicyIsPersistentInvalidityNotDeviceLock() async throws {
        let bytes = [UInt8](repeating: 0x79, count: 40)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        let fileSystem = makeFileSystem(adapter: adapter)
        let lease = try await fileSystem.publishProtectedCopy(
            from: artifact(byteCount: bytes.count),
            attemptID: attemptID,
            format: .m4a,
            durationMilliseconds: 1_500
        )
        lease.release()
        adapter.setPublishedProtectionClass(2)

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        ) {
            _ = try await fileSystem.validatePublishedAudio(
                relativeIdentifier: lease.relativeIdentifier,
                attemptID: attemptID,
                durationMilliseconds: 1_500,
                byteCount: Int64(bytes.count)
            )
        }
        #expect(adapter.publishedBytes == bytes)
    }

    @Test func finalNameConflictNeverOverwritesExistingAudio() async throws {
        let bytes = [UInt8](repeating: 0x21, count: 8)
        let sentinel = [UInt8](repeating: 0xF0, count: bytes.count)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        adapter.installFinalAudio(
            named: finalName,
            bytes: sentinel,
            configured: true
        )
        let fileSystem = makeFileSystem(adapter: adapter)

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError.destinationConflict
        ) {
            _ = try await fileSystem.publishProtectedCopy(
                from: artifact(byteCount: bytes.count),
                attemptID: attemptID,
                format: .m4a,
                durationMilliseconds: 1_500
            )
        }

        #expect(adapter.publishedBytes == sentinel)
        #expect(adapter.pendingNames == [finalName])
        #expect(adapter.sourceBytes == bytes)
    }

    @Test func releaseWaitsForAnInFlightLeaseRevalidation() async throws {
        let bytes = [UInt8](repeating: 0x71, count: 24)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        let media = BlockingSecondPendingRecordingMediaValidator()
        let fileSystem = FoundationIOSPendingRecordingAudioFileSystem(
            applicationSupportDirectoryURL: URL(
                fileURLWithPath: "/ApplicationSupport",
                isDirectory: true
            ),
            adapter: adapter,
            mediaValidator: media,
            monotonicClock: { 1 },
            queue: DispatchQueue(label: "pending-recording-lease-race-test")
        )
        let lease = try await fileSystem.publishProtectedCopy(
            from: artifact(byteCount: bytes.count),
            attemptID: attemptID,
            format: .m4a,
            durationMilliseconds: 1_500
        )
        let validation = Task { try await lease.revalidate() }
        #expect(media.waitUntilSecondValidationStarts())
        let closeCountBeforeRelease = adapter.events.filter { $0 == "close" }.count

        validation.cancel()
        lease.release()

        #expect(adapter.events.filter { $0 == "close" }.count == closeCountBeforeRelease)
        media.resumeSecondValidation()
        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError.operationCancelled
        ) {
            _ = try await validation.value
        }
        #expect(adapter.waitUntilCloseCount(closeCountBeforeRelease + 2))
        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        ) {
            _ = try await lease.revalidate()
        }
    }

    @Test func protectedDataWriteFailureRemainsTemporarilyUnavailable() async {
        let bytes = [UInt8](repeating: 0x72, count: 24)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        adapter.createEmptyPendingNamespace()
        adapter.failNext("write", errors: [EACCES])
        let fileSystem = makeFileSystem(adapter: adapter)

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable
        ) {
            _ = try await fileSystem.publishProtectedCopy(
                from: artifact(byteCount: bytes.count),
                attemptID: attemptID,
                format: .m4a,
                durationMilliseconds: 1_500
            )
        }

        #expect(!adapter.events.contains("publish-exclusive"))
        #expect(adapter.sourceBytes == bytes)
    }

    @Test func emptyNamespaceCheckRejectsEveryUnresolvedEntry() async throws {
        let bytes = [UInt8](repeating: 0x31, count: 8)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(sourceBytes: bytes)
        let fileSystem = makeFileSystem(adapter: adapter)
        try await fileSystem.requireEmptyNamespace()
        adapter.installFinalAudio(named: "unresolved.tmp", bytes: [1], configured: false)

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError.namespaceNotEmpty
        ) {
            try await fileSystem.requireEmptyNamespace()
        }
    }

    @Test func sealedInventoryValidatesRowsAndSkipsTombstoneMediaDecode()
        async throws {
        let media = FakePendingRecordingMediaValidator(durations: [1_500])
        let fixture = try makeInventoryFixture(media: media)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let rowBytes = [UInt8](repeating: 0x41, count: 40)
        let tombstoneBytes = [UInt8](repeating: 0x42, count: 24)
        let tombstoneID = UUID(
            uuidString: "11111111-2222-3333-4444-555555555555"
        )!
        let rowRelative = relativeIdentifier(for: attemptID, format: .m4a)
        let tombstoneRelative = relativeIdentifier(
            for: tombstoneID,
            format: .wav
        )
        fixture.adapter.installFinalAudio(
            named: URL(fileURLWithPath: rowRelative).lastPathComponent,
            bytes: rowBytes,
            configured: true
        )
        fixture.adapter.installFinalAudio(
            named: URL(fileURLWithPath: tombstoneRelative).lastPathComponent,
            bytes: tombstoneBytes,
            configured: true
        )

        try await fixture.context.operationGate.perform { authorization in
            let inventory = IOSProtectedAudioNamespaceInventory(
                testingRepositoryBinding: fixture.context.repositoryBinding,
                operationLeaseAuthorization: authorization,
                artifacts: [
                    .row(
                        attemptID: attemptID,
                        relativeIdentifier: rowRelative,
                        durationMilliseconds: 1_500,
                        byteCount: Int64(rowBytes.count)
                    ),
                    .tombstone(
                        attemptID: tombstoneID,
                        relativeIdentifier: tombstoneRelative,
                        byteCount: Int64(tombstoneBytes.count)
                    ),
                ]
            )
            try await fixture.fileSystem.validateProtectedAudioNamespace(
                inventory
            )
        }

        #expect(media.requestedTimeouts == [2_000_000_000])
        #expect(fixture.adapter.events.filter { $0 == "flock" }.count == 2)
        #expect(Set(fixture.adapter.pendingNames) == [
            URL(fileURLWithPath: rowRelative).lastPathComponent,
            URL(fileURLWithPath: tombstoneRelative).lastPathComponent,
        ])
    }

    @Test func sealedInventoryRejectsUnknownStagingAndMissingExpectedFiles()
        async throws {
        let fixture = try makeInventoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        fixture.adapter.installFinalAudio(
            named: ".recording-staging-v1-foreign.m4a",
            bytes: [1],
            configured: false
        )

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError.namespaceNotEmpty
        ) {
            try await fixture.context.operationGate.perform { authorization in
                let inventory = IOSProtectedAudioNamespaceInventory(
                    testingRepositoryBinding:
                        fixture.context.repositoryBinding,
                    operationLeaseAuthorization: authorization,
                    artifacts: []
                )
                try await fixture.fileSystem.validateProtectedAudioNamespace(
                    inventory
                )
            }
        }
        #expect(!fixture.adapter.events.contains("unlink"))

        let missingFixture = try makeInventoryFixture()
        defer { try? FileManager.default.removeItem(at: missingFixture.rootURL) }
        let missingRelative = relativeIdentifier(
            for: attemptID,
            format: .m4a
        )
        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError
                .protectedAudioMissing
        ) {
            try await missingFixture.context.operationGate.perform {
                authorization in
                let inventory = IOSProtectedAudioNamespaceInventory(
                    testingRepositoryBinding:
                        missingFixture.context.repositoryBinding,
                    operationLeaseAuthorization: authorization,
                    artifacts: [
                        .row(
                            attemptID: attemptID,
                            relativeIdentifier: missingRelative,
                            durationMilliseconds: 1_500,
                            byteCount: 24
                        ),
                    ]
                )
                try await missingFixture.fileSystem
                    .validateProtectedAudioNamespace(inventory)
            }
        }
    }

    @Test func sealedInventoryStopsAtTheOverflowSentinel() async throws {
        let fixture = try makeInventoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        for index in 0..<12 {
            fixture.adapter.installFinalAudio(
                named: "foreign-\(index).tmp",
                bytes: [UInt8(index)],
                configured: false
            )
        }

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError.namespaceNotEmpty
        ) {
            try await fixture.context.operationGate.perform { authorization in
                let inventory = IOSProtectedAudioNamespaceInventory(
                    testingRepositoryBinding:
                        fixture.context.repositoryBinding,
                    operationLeaseAuthorization: authorization,
                    artifacts: []
                )
                try await fixture.fileSystem.validateProtectedAudioNamespace(
                    inventory
                )
            }
        }

        // Dot entries plus eleven accepted finals and one overflow sentinel.
        #expect(
            fixture.adapter.events.filter { $0 == "readdir" }.count == 14
        )
        #expect(fixture.adapter.pendingNames.count == 12)
    }

    @Test func inventoryPublicationScansBeforeAndAfterOneHeldPublish()
        async throws {
        let sourceBytes = [UInt8](repeating: 0x63, count: 64)
        let media = FakePendingRecordingMediaValidator(
            durations: [1_500, 1_500]
        )
        let fixture = try makeInventoryFixture(
            sourceBytes: sourceBytes,
            media: media
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let tombstoneID = UUID(
            uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )!
        let tombstoneRelative = relativeIdentifier(
            for: tombstoneID,
            format: .wav
        )
        let tombstoneBytes = [UInt8](repeating: 0x64, count: 20)
        fixture.adapter.installFinalAudio(
            named: URL(fileURLWithPath: tombstoneRelative).lastPathComponent,
            bytes: tombstoneBytes,
            configured: true
        )

        let lease = try await fixture.context.operationGate.perform {
            authorization in
            let inventory = IOSProtectedAudioNamespaceInventory(
                testingRepositoryBinding: fixture.context.repositoryBinding,
                operationLeaseAuthorization: authorization,
                artifacts: [
                    .tombstone(
                        attemptID: tombstoneID,
                        relativeIdentifier: tombstoneRelative,
                        byteCount: Int64(tombstoneBytes.count)
                    ),
                ]
            )
            return try await fixture.fileSystem.publishProtectedCopy(
                from: artifact(byteCount: sourceBytes.count),
                attemptID: attemptID,
                format: .m4a,
                durationMilliseconds: 1_500,
                inventory: inventory
            )
        }
        defer { lease.release() }

        #expect(Set(fixture.adapter.pendingNames) == [
            finalName,
            URL(fileURLWithPath: tombstoneRelative).lastPathComponent,
        ])
        #expect(media.requestedTimeouts == [
            2_000_000_000,
            2_000_000_000,
        ])
        let events = fixture.adapter.events
        let firstScan = try #require(events.firstIndex(of: "readdir"))
        let stagingCreate = try #require(events.firstIndex(where: {
            $0.hasPrefix("openat:.recording-staging-v1-")
        }))
        let publish = try #require(events.firstIndex(of: "publish-exclusive"))
        let lastScan = try #require(events.lastIndex(of: "readdir"))
        #expect(firstScan < stagingCreate)
        #expect(publish < lastScan)
    }

    @Test func expiredInventoryLeaseFailsBeforeNamespaceMutation() async throws {
        let fixture = try makeInventoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let inventory = try await fixture.context.operationGate.perform {
            authorization in
            IOSProtectedAudioNamespaceInventory(
                testingRepositoryBinding: fixture.context.repositoryBinding,
                operationLeaseAuthorization: authorization,
                artifacts: []
            )
        }

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError.namespaceUnavailable
        ) {
            try await fixture.fileSystem.validateProtectedAudioNamespace(
                inventory
            )
        }
        #expect(!fixture.adapter.events.contains(where: {
            $0.hasPrefix("mkdir:")
        }))
    }

    @Test func compositeInventoryRejectsDuplicateOwnershipBeforeIO()
        async throws {
        let fixture = try makeInventoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let m4aRelative = relativeIdentifier(for: attemptID, format: .m4a)
        let wavRelative = relativeIdentifier(for: attemptID, format: .wav)

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError
                .protectedAudioInvalid
        ) {
            try await fixture.context.operationGate.perform { authorization in
                let inventory = IOSProtectedAudioNamespaceInventory(
                    testingRepositoryBinding:
                        fixture.context.repositoryBinding,
                    operationLeaseAuthorization: authorization,
                    artifacts: [
                        .row(
                            attemptID: attemptID,
                            relativeIdentifier: m4aRelative,
                            durationMilliseconds: 1_500,
                            byteCount: 24
                        ),
                        .row(
                            attemptID: attemptID,
                            relativeIdentifier: wavRelative,
                            durationMilliseconds: 1_500,
                            byteCount: 24
                        ),
                    ]
                )
                try await fixture.fileSystem.validateProtectedAudioNamespace(
                    inventory
                )
            }
        }
        #expect(fixture.adapter.events.isEmpty)
    }

    @Test func compositeInventoryRejectsMismatchedPhysicalRootBeforeMutation()
        async throws {
        let fixture = try makeInventoryFixture(rootIdentityMismatch: true)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        await #expect(
            throws: IOSPendingRecordingAudioFileSystemError
                .repositoryIdentityConflict
        ) {
            try await fixture.context.operationGate.perform { authorization in
                let inventory = IOSProtectedAudioNamespaceInventory(
                    testingRepositoryBinding:
                        fixture.context.repositoryBinding,
                    operationLeaseAuthorization: authorization,
                    artifacts: []
                )
                try await fixture.fileSystem.validateProtectedAudioNamespace(
                    inventory
                )
            }
        }
        #expect(!fixture.adapter.events.contains(where: {
            $0.hasPrefix("mkdir:") || $0 == "publish-exclusive"
        }))
    }

    @Test func liveDarwinAndAudioToolboxRoundTripAValidWAV() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-pending-audio-\(UUID().uuidString)",
                isDirectory: true
            )
        let applicationSupportURL = rootURL.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        )
        let sourceURL = rootURL.appendingPathComponent("source.wav")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
        let sourceData = makeOneSecondPCM16WAV()
        try sourceData.write(to: sourceURL, options: .withoutOverwriting)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: sourceURL.path
        )

        let fileSystem = FoundationIOSPendingRecordingAudioFileSystem(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        let liveAttemptID = UUID()
        let lease = try await fileSystem.publishProtectedCopy(
            from: AudioRecordingArtifact(
                fileURL: sourceURL,
                duration: 1,
                byteCount: Int64(sourceData.count)
            ),
            attemptID: liveAttemptID,
            format: .wav,
            durationMilliseconds: 1_000
        )

        let validated = try await lease.revalidate()
        #expect(validated.byteCount == Int64(sourceData.count))
        #expect(validated.duration == 1)
        lease.release()
        #expect(
            try await fileSystem.removePublishedAudioIfPresent(
                relativeIdentifier: lease.relativeIdentifier,
                attemptID: liveAttemptID,
                expectedByteCount: Int64(sourceData.count)
            )
        )
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test func audioToolboxValidatorReadsUnlinkedDescriptorNotReplacementPath()
        throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pending-media-descriptor-\(UUID().uuidString)",
            isDirectory: true
        )
        let fileURL = root.appendingPathComponent("recording.wav")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let original = makeOneSecondPCM16WAV()
        try original.write(to: fileURL)
        let descriptor = fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC)
        }
        #expect(descriptor >= 0)
        defer { if descriptor >= 0 { Darwin.close(descriptor) } }
        try FileManager.default.removeItem(at: fileURL)
        try Data(repeating: 0xEE, count: original.count).write(to: fileURL)
        let validator = AudioToolboxIOSPendingRecordingMediaValidator()

        #expect(
            try validator.durationMilliseconds(
                forFileDescriptor: descriptor,
                byteCount: Int64(original.count),
                format: .wav,
                timeoutNanoseconds: 2_000_000_000
            ) == 1_000
        )
        #expect(
            throws: IOSPendingRecordingAudioFileSystemError
                .mediaValidationFailed
        ) {
            _ = try validator.durationMilliseconds(
                forFileDescriptor: descriptor,
                byteCount: Int64(original.count),
                format: .m4a,
                timeoutNanoseconds: 2_000_000_000
            )
        }
        #expect(
            throws: IOSPendingRecordingAudioFileSystemError
                .mediaValidationFailed
        ) {
            _ = try validator.durationMilliseconds(
                forFileDescriptor: descriptor,
                byteCount: Int64(original.count - 1),
                format: .wav,
                timeoutNanoseconds: 2_000_000_000
            )
        }
    }

    @Test func audioToolboxValidatorRoundTripsARealAACM4A() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pending-media-m4a-\(UUID().uuidString)",
            isDirectory: true
        )
        let fileURL = root.appendingPathComponent("recording.m4a")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let byteCount = try writeOneSecondAACM4A(to: fileURL)
        let descriptor = fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC)
        }
        #expect(descriptor >= 0)
        defer { if descriptor >= 0 { Darwin.close(descriptor) } }

        let duration = try AudioToolboxIOSPendingRecordingMediaValidator()
            .durationMilliseconds(
                forFileDescriptor: descriptor,
                byteCount: byteCount,
                format: .m4a,
                timeoutNanoseconds: 2_000_000_000
            )

        #expect(duration > 0)
        #expect(abs(duration - 1_000) <= 250)
    }

    @Test func timedOutMediaWorkerBlocksDuplicateWorkUntilItReleasesFD()
        throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pending-media-timeout-\(UUID().uuidString)",
            isDirectory: true
        )
        let fileURL = root.appendingPathComponent("recording.wav")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let wav = makeOneSecondPCM16WAV()
        try wav.write(to: fileURL)
        let descriptor = fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC)
        }
        #expect(descriptor >= 0)
        defer { if descriptor >= 0 { Darwin.close(descriptor) } }
        let gate = AudioToolboxMediaValidationWorkerGate()
        let barrier = PendingMediaLoadBarrier()
        let closeCounter = PendingMediaCloseCounter()
        let validator = AudioToolboxIOSPendingRecordingMediaValidator(
            workerGate: gate,
            beforeDurationLoad: { barrier.blockFirstLoad() },
            onDuplicatedDescriptorClosed: { closeCounter.increment() }
        )

        #expect(
            throws: IOSPendingRecordingAudioFileSystemError
                .mediaValidationTimedOut
        ) {
            _ = try validator.durationMilliseconds(
                forFileDescriptor: descriptor,
                byteCount: Int64(wav.count),
                format: .wav,
                timeoutNanoseconds: 1_000_000
            )
        }
        #expect(barrier.waitUntilBlocked())
        #expect(closeCounter.value == 0)
        #expect(
            throws: IOSPendingRecordingAudioFileSystemError
                .mediaValidationTimedOut
        ) {
            _ = try validator.durationMilliseconds(
                forFileDescriptor: descriptor,
                byteCount: Int64(wav.count),
                format: .wav,
                timeoutNanoseconds: 2_000_000_000
            )
        }
        #expect(closeCounter.value == 0)

        barrier.resume()
        #expect(closeCounter.wait(until: 1))
        #expect(
            try validator.durationMilliseconds(
                forFileDescriptor: descriptor,
                byteCount: Int64(wav.count),
                format: .wav,
                timeoutNanoseconds: 2_000_000_000
            ) == 1_000
        )
        #expect(closeCounter.wait(until: 2))
    }

    private var finalName: String {
        "recording-v1-01234567-89ab-cdef-0123-456789abcdef.m4a"
    }

    private func artifact(byteCount: Int) -> AudioRecordingArtifact {
        AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/source.m4a"),
            duration: 1.5,
            byteCount: Int64(byteCount)
        )
    }

    private func makeFileSystem(
        adapter: SimulatedPendingRecordingPOSIXAdapter,
        media: FakePendingRecordingMediaValidator =
            FakePendingRecordingMediaValidator(durations: [1_500]),
        clock: @escaping @Sendable () -> UInt64? = { 1 }
    ) -> FoundationIOSPendingRecordingAudioFileSystem {
        FoundationIOSPendingRecordingAudioFileSystem(
            applicationSupportDirectoryURL: URL(
                fileURLWithPath: "/ApplicationSupport",
                isDirectory: true
            ),
            adapter: adapter,
            mediaValidator: media,
            monotonicClock: clock,
            queue: DispatchQueue(label: "pending-recording-audio-tests")
        )
    }

    private struct InventoryFixture {
        let rootURL: URL
        let context: IOSAcceptedHistoryCoordinatorProcessContext
        let adapter: SimulatedPendingRecordingPOSIXAdapter
        let fileSystem: FoundationIOSPendingRecordingAudioFileSystem
    }

    private func makeInventoryFixture(
        sourceBytes: [UInt8] = [UInt8](repeating: 0x61, count: 64),
        media: FakePendingRecordingMediaValidator =
            FakePendingRecordingMediaValidator(durations: [1_500]),
        rootIdentityMismatch: Bool = false
    ) throws -> InventoryFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-inventory-audio-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        var rootStatus = stat()
        let didReadRoot = rootURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return Darwin.lstat(path, &rootStatus) == 0
        }
        guard didReadRoot else {
            try? FileManager.default.removeItem(at: rootURL)
            throw CocoaError(.fileReadUnknown)
        }
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let context = registry.context(for: rootURL)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(
            sourceBytes: sourceBytes,
            applicationSupportPath: rootURL.path,
            applicationSupportDevice: rootIdentityMismatch
                ? rootStatus.st_dev &+ 1
                : rootStatus.st_dev,
            applicationSupportInode: rootStatus.st_ino
        )
        let fileSystem = FoundationIOSPendingRecordingAudioFileSystem(
            applicationSupportDirectoryURL: rootURL,
            adapter: adapter,
            mediaValidator: media,
            monotonicClock: { 1 },
            expectedRepositoryRoot:
                context.repositoryBinding.physicalRootIdentity,
            queue: DispatchQueue(
                label: "pending-recording-inventory-audio-tests"
            )
        )
        return InventoryFixture(
            rootURL: rootURL,
            context: context,
            adapter: adapter,
            fileSystem: fileSystem
        )
    }

    private func relativeIdentifier(
        for attemptID: UUID,
        format: IOSPendingRecordingAudioFormat
    ) -> String {
        IOSPendingRecordingStorageLocation.relativeAudioIdentifier(
            for: attemptID,
            format: format
        )
    }
}

private func makeOneSecondPCM16WAV() -> Data {
    let sampleRate: UInt32 = 8_000
    let channelCount: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let sampleCount = Int(sampleRate)
    let dataByteCount = UInt32(sampleCount * Int(bitsPerSample / 8))
    let byteRate = sampleRate * UInt32(channelCount) * UInt32(bitsPerSample / 8)
    let blockAlign = channelCount * (bitsPerSample / 8)

    var data = Data()
    data.append(contentsOf: "RIFF".utf8)
    data.appendLittleEndian(UInt32(36) + dataByteCount)
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    data.appendLittleEndian(UInt32(16))
    data.appendLittleEndian(UInt16(1))
    data.appendLittleEndian(channelCount)
    data.appendLittleEndian(sampleRate)
    data.appendLittleEndian(byteRate)
    data.appendLittleEndian(blockAlign)
    data.appendLittleEndian(bitsPerSample)
    data.append(contentsOf: "data".utf8)
    data.appendLittleEndian(dataByteCount)
    data.append(Data(repeating: 0, count: Int(dataByteCount)))
    return data
}

private func writeOneSecondAACM4A(to fileURL: URL) throws -> Int64 {
    do {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
        ]
        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let frameCount = AVAudioFrameCount(file.processingFormat.sampleRate)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ),
        let channel = buffer.floatChannelData?[0] else {
            throw CocoaError(.fileWriteUnknown)
        }
        channel.initialize(repeating: 0, count: Int(frameCount))
        buffer.frameLength = frameCount
        try file.write(from: buffer)
    }
    let attributes = try FileManager.default.attributesOfItem(
        atPath: fileURL.path
    )
    guard let size = attributes[.size] as? NSNumber else {
        throw CocoaError(.fileReadUnknown)
    }
    return size.int64Value
}

private extension Data {
    mutating func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

private final class FakePendingRecordingMediaValidator:
    IOSPendingRecordingMediaValidating,
    @unchecked Sendable {
    private let lock = NSLock()
    private var durations: [Int64]
    private var timeouts: [UInt64] = []

    init(durations: [Int64]) {
        self.durations = durations
    }

    var requestedTimeouts: [UInt64] {
        lock.withLock { timeouts }
    }

    func durationMilliseconds(
        forFileDescriptor fileDescriptor: Int32,
        byteCount: Int64,
        format: IOSPendingRecordingAudioFormat,
        timeoutNanoseconds: UInt64
    ) throws -> Int64 {
        _ = fileDescriptor
        _ = byteCount
        _ = format
        return lock.withLock {
            timeouts.append(timeoutNanoseconds)
            return durations.isEmpty ? 1_500 : durations.removeFirst()
        }
    }
}

private final class StepPendingRecordingClock: @unchecked Sendable {
    private let lock = NSLock()
    private let stepNanoseconds: UInt64
    private var value: UInt64 = 0

    init(stepNanoseconds: UInt64) {
        self.stepNanoseconds = stepNanoseconds
    }

    func now() -> UInt64? {
        lock.withLock {
            defer { value += stepNanoseconds }
            return value
        }
    }
}

private final class PendingMediaLoadBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private let blocked = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private var callCount = 0

    func blockFirstLoad() {
        let shouldBlock = lock.withLock {
            callCount += 1
            return callCount == 1
        }
        guard shouldBlock else { return }
        blocked.signal()
        _ = release.wait(timeout: .now() + 10)
    }

    func waitUntilBlocked() -> Bool {
        blocked.wait(timeout: .now() + 10) == .success
    }

    func resume() {
        release.signal()
    }
}

private final class PendingMediaCloseCounter: @unchecked Sendable {
    private let condition = NSCondition()
    private var storedValue = 0

    var value: Int { condition.withLock { storedValue } }

    func increment() {
        condition.withLock {
            storedValue += 1
            condition.broadcast()
        }
    }

    func wait(until expectedValue: Int) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(10)
        while storedValue < expectedValue {
            guard condition.wait(until: deadline) else { return false }
        }
        return true
    }
}

private final class BlockingSecondPendingRecordingMediaValidator:
    IOSPendingRecordingMediaValidating,
    @unchecked Sendable {
    private let lock = NSLock()
    private let secondValidationStarted = DispatchSemaphore(value: 0)
    private let allowSecondValidation = DispatchSemaphore(value: 0)
    private var callCount = 0

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
        let shouldBlock = lock.withLock { () -> Bool in
            callCount += 1
            return callCount == 2
        }
        if shouldBlock {
            secondValidationStarted.signal()
            guard allowSecondValidation.wait(timeout: .now() + 10) == .success else {
                throw IOSPendingRecordingAudioFileSystemError.mediaValidationTimedOut
            }
        }
        return 1_500
    }

    func waitUntilSecondValidationStarts() -> Bool {
        secondValidationStarted.wait(timeout: .now() + 10) == .success
    }

    func resumeSecondValidation() {
        allowSecondValidation.signal()
    }
}

private final class SimulatedPendingRecordingPOSIXAdapter:
    IOSPendingRecordingPOSIXAdapter,
    @unchecked Sendable {
    private final class Node {
        enum Kind: Equatable { case directory, file }

        let kind: Kind
        let device: dev_t
        let inode: ino_t
        var mode: mode_t
        var owner: uid_t
        var linkCount: nlink_t = 1
        var bytes: [UInt8]
        var children: [String: Node]
        var extendedAttributes: [String: [UInt8]] = [:]
        var protectionClass: Int32?
        var lockedByDescriptor: Int32?
        var version: time_t = 1

        init(
            kind: Kind,
            device: dev_t,
            inode: ino_t,
            mode: mode_t,
            owner: uid_t,
            bytes: [UInt8] = []
        ) {
            self.kind = kind
            self.device = device
            self.inode = inode
            self.mode = mode
            self.owner = owner
            self.bytes = bytes
            children = [:]
        }
    }

    private final class Descriptor {
        let node: Node
        var offset = 0

        init(node: Node) {
            self.node = node
        }
    }

    private struct DirectoryStreamState {
        var entries: [String]
        var index = 0
    }

    private final class State {
        let effectiveUserID: uid_t = 501
        let device: dev_t
        let applicationSupportPath: String
        var nextDescriptor: Int32 = 10
        var nextInode: ino_t = 100
        var descriptors: [Int32: Descriptor] = [:]
        var streams: [Int: DirectoryStreamState] = [:]
        var events: [String] = []
        var failures: [String: [Int32]] = [:]
        var sourcePathNode: Node
        let applicationSupportNode: Node
        var replaceSourcePathAtEndOfFile = false
        var didReplaceSourcePath = false
        var readCallCount = 0
        var maximumReadRequest = 0
        var maximumWriteRequest = 0
        var maximumReadResult = 0
        var maximumWriteResult = 0
        var readLimit: Int?
        var writeLimit: Int?
        var sourceOpenFlags: Int32 = 0
        var transientPreadReplacementBytes: [UInt8]?
        var didUseTransientPreadReplacement = false

        init(
            sourceBytes: [UInt8],
            applicationSupportPath: String,
            applicationSupportDevice: dev_t,
            applicationSupportInode: ino_t
        ) {
            let owner = uid_t(501)
            device = applicationSupportDevice
            self.applicationSupportPath = applicationSupportPath
            sourcePathNode = Node(
                kind: .file,
                device: applicationSupportDevice,
                inode: 1,
                mode: S_IFREG | mode_t(0o600),
                owner: owner,
                bytes: sourceBytes
            )
            applicationSupportNode = Node(
                kind: .directory,
                device: applicationSupportDevice,
                inode: applicationSupportInode,
                mode: S_IFDIR | mode_t(0o700),
                owner: owner
            )
        }

        func makeNode(
            kind: Node.Kind,
            mode: mode_t,
            bytes: [UInt8] = []
        ) -> Node {
            defer { nextInode += 1 }
            return Node(
                kind: kind,
                device: device,
                inode: nextInode,
                mode: mode,
                owner: effectiveUserID,
                bytes: bytes
            )
        }

        func descriptor(for node: Node) -> Int32 {
            let value = nextDescriptor
            nextDescriptor += 1
            descriptors[value] = Descriptor(node: node)
            return value
        }

        func pendingDirectory(create: Bool) -> Node? {
            var node = applicationSupportNode
            for name in ["HoldType", "Recordings", "Pending"] {
                if let child = node.children[name] {
                    node = child
                } else if create {
                    let child = makeNode(
                        kind: .directory,
                        mode: S_IFDIR | mode_t(0o700)
                    )
                    node.children[name] = child
                    node = child
                } else {
                    return nil
                }
            }
            return node
        }

        func popFailure(_ operation: String) -> Int32? {
            guard var values = failures[operation], !values.isEmpty else {
                return nil
            }
            let value = values.removeFirst()
            failures[operation] = values
            return value
        }
    }

    private let lock = NSCondition()
    private let state: State

    init(
        sourceBytes: [UInt8],
        applicationSupportPath: String = "/ApplicationSupport",
        applicationSupportDevice: dev_t = 1,
        applicationSupportInode: ino_t = 2
    ) {
        state = State(
            sourceBytes: sourceBytes,
            applicationSupportPath: applicationSupportPath,
            applicationSupportDevice: applicationSupportDevice,
            applicationSupportInode: applicationSupportInode
        )
    }

    var events: [String] { lock.withLock { state.events } }
    var sourceBytes: [UInt8] { lock.withLock { state.sourcePathNode.bytes } }
    var readCallCount: Int { lock.withLock { state.readCallCount } }
    var maximumReadRequest: Int { lock.withLock { state.maximumReadRequest } }
    var maximumWriteRequest: Int { lock.withLock { state.maximumWriteRequest } }
    var maximumReadResult: Int { lock.withLock { state.maximumReadResult } }
    var maximumWriteResult: Int { lock.withLock { state.maximumWriteResult } }
    var sourceOpenFlags: Int32 { lock.withLock { state.sourceOpenFlags } }
    func waitUntilCloseCount(_ expectedCount: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let deadline = Date().addingTimeInterval(2)
        while state.events.filter({ $0 == "close" }).count < expectedCount {
            guard lock.wait(until: deadline) else {
                return false
            }
        }
        return true
    }
    var markerReadCount: Int {
        lock.withLock {
            state.events.filter {
                $0 == "getxattr:com.holdtype.ios.pending-recording-audio"
            }.count
        }
    }
    var pendingNames: [String] {
        lock.withLock {
            state.pendingDirectory(create: false)?.children.keys.sorted() ?? []
        }
    }
    var publishedBytes: [UInt8]? {
        lock.withLock {
            guard let pending = state.pendingDirectory(create: false) else { return nil }
            return pending.children.first(where: {
                $0.key.hasPrefix("recording-v1-")
                    && ($0.key.hasSuffix(".m4a") || $0.key.hasSuffix(".wav"))
            })?.value.bytes
        }
    }
    var replaceSourcePathAtEndOfFile: Bool {
        get { lock.withLock { state.replaceSourcePathAtEndOfFile } }
        set { lock.withLock { state.replaceSourcePathAtEndOfFile = newValue } }
    }
    var didUseTransientPreadReplacement: Bool {
        lock.withLock { state.didUseTransientPreadReplacement }
    }

    func transientlyReplacePublishedPathDuringNextPread(
        with bytes: [UInt8]
    ) {
        lock.withLock { state.transientPreadReplacementBytes = bytes }
    }

    func failNext(_ operation: String, errors: [Int32]) {
        lock.withLock { state.failures[operation] = errors }
    }

    func createEmptyPendingNamespace() {
        lock.withLock {
            _ = state.pendingDirectory(create: true)
        }
    }

    func setTransferLimits(read: Int?, write: Int?) {
        lock.withLock {
            state.readLimit = read
            state.writeLimit = write
        }
    }

    func setPublishedMode(_ mode: mode_t) {
        lock.withLock {
            guard let pending = state.pendingDirectory(create: false),
                  let node = pending.children.first(where: {
                      $0.key.hasPrefix("recording-v1-")
                  })?.value else {
                return
            }
            node.mode = S_IFREG | mode
            node.version += 1
        }
    }

    func setPublishedProtectionClass(_ protectionClass: Int32) {
        lock.withLock {
            guard let pending = state.pendingDirectory(create: false),
                  let node = pending.children.first(where: {
                      $0.key.hasPrefix("recording-v1-")
                  })?.value else {
                return
            }
            node.protectionClass = protectionClass
            node.version += 1
        }
    }

    func installFinalAudio(named name: String, bytes: [UInt8], configured: Bool) {
        lock.withLock {
            let pending = state.pendingDirectory(create: true)!
            let node = state.makeNode(
                kind: .file,
                mode: S_IFREG | mode_t(0o600),
                bytes: bytes
            )
            if configured {
                node.extendedAttributes[
                    "com.holdtype.ios.pending-recording-audio"
                ] = Array("v1".utf8)
                node.extendedAttributes[
                    "com.apple.metadata:com_apple_backup_excludeItem"
                ] = Self.backupExclusionValue
                node.protectionClass = 1
            }
            pending.children[name] = node
        }
    }

    func effectiveUserID() -> IOSPendingRecordingPOSIXResult<uid_t> {
        lock.withLock {
            state.events.append("geteuid")
            return .success(state.effectiveUserID)
        }
    }

    func openPath(
        _ path: String,
        flags: Int32,
        mode: mode_t?
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        lock.withLock {
            state.events.append("open-path")
            if let failure = state.popFailure("openPath") { return .failure(failure) }
            let node: Node
            switch path {
            case "/source.m4a":
                state.sourceOpenFlags = flags
                node = state.sourcePathNode
            case state.applicationSupportPath:
                node = state.applicationSupportNode
            default:
                return .failure(ENOENT)
            }
            if flags & O_DIRECTORY != 0, node.kind != .directory {
                return .failure(ENOTDIR)
            }
            return .success(state.descriptor(for: node))
        }
    }

    func openAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32,
        mode: mode_t?
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        lock.withLock {
            state.events.append("openat:\(name)")
            if let failure = state.popFailure("openAt") { return .failure(failure) }
            guard let directory = state.descriptors[directoryDescriptor]?.node,
                  directory.kind == .directory else {
                return .failure(EBADF)
            }
            if name == "." {
                return .success(state.descriptor(for: directory))
            }
            if flags & O_CREAT != 0 {
                guard directory.children[name] == nil else { return .failure(EEXIST) }
                let node = state.makeNode(
                    kind: .file,
                    mode: S_IFREG | (mode ?? mode_t(0o600))
                )
                directory.children[name] = node
                return .success(state.descriptor(for: node))
            }
            guard let node = directory.children[name] else { return .failure(ENOENT) }
            if flags & O_DIRECTORY != 0, node.kind != .directory {
                return .failure(ENOTDIR)
            }
            return .success(state.descriptor(for: node))
        }
    }

    func makeDirectoryAt(
        directoryDescriptor: Int32,
        name: String,
        mode: mode_t
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        lock.withLock {
            state.events.append("mkdir:\(name)")
            if let failure = state.popFailure("mkdir") { return .failure(failure) }
            guard let directory = state.descriptors[directoryDescriptor]?.node,
                  directory.kind == .directory else {
                return .failure(EBADF)
            }
            guard directory.children[name] == nil else { return .failure(EEXIST) }
            directory.children[name] = state.makeNode(
                kind: .directory,
                mode: S_IFDIR | mode
            )
            return .success(())
        }
    }

    func status(of fileDescriptor: Int32) -> IOSPendingRecordingPOSIXResult<stat> {
        lock.withLock {
            state.events.append("fstat")
            if let failure = state.popFailure("fstat") { return .failure(failure) }
            guard let node = state.descriptors[fileDescriptor]?.node else {
                return .failure(EBADF)
            }
            return .success(Self.makeStatus(node))
        }
    }

    func statusAtPath(_ path: String) -> IOSPendingRecordingPOSIXResult<stat> {
        lock.withLock {
            state.events.append("lstat-path")
            if let failure = state.popFailure("lstat") { return .failure(failure) }
            switch path {
            case "/source.m4a":
                return .success(Self.makeStatus(state.sourcePathNode))
            case state.applicationSupportPath:
                return .success(Self.makeStatus(state.applicationSupportNode))
            case state.applicationSupportPath
                + "/HoldType/Recordings/Pending":
                guard let pending = state.pendingDirectory(create: false) else {
                    return .failure(ENOENT)
                }
                return .success(Self.makeStatus(pending))
            default:
                return .failure(ENOENT)
            }
        }
    }

    func statusAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<stat> {
        lock.withLock {
            state.events.append("fstatat:\(name)")
            if let failure = state.popFailure("fstatAt") { return .failure(failure) }
            guard let directory = state.descriptors[directoryDescriptor]?.node,
                  let node = directory.children[name] else {
                return .failure(ENOENT)
            }
            return .success(Self.makeStatus(node))
        }
    }

    func read(
        fileDescriptor: Int32,
        buffer: UnsafeMutableRawPointer,
        byteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        lock.withLock {
            state.events.append("read:\(byteCount)")
            state.readCallCount += 1
            state.maximumReadRequest = max(state.maximumReadRequest, byteCount)
            if let failure = state.popFailure("read") { return .failure(failure) }
            guard let descriptor = state.descriptors[fileDescriptor],
                  descriptor.node.kind == .file else {
                return .failure(EBADF)
            }
            let available = descriptor.node.bytes.count - descriptor.offset
            let count = max(
                0,
                min(min(byteCount, available), state.readLimit ?? Int.max)
            )
            state.maximumReadResult = max(state.maximumReadResult, count)
            if count > 0 {
                descriptor.node.bytes.withUnsafeBytes { source in
                    _ = Darwin.memcpy(
                        buffer,
                        source.baseAddress!.advanced(by: descriptor.offset),
                        count
                    )
                }
                descriptor.offset += count
            } else if state.replaceSourcePathAtEndOfFile,
                      !state.didReplaceSourcePath,
                      descriptor.node === state.sourcePathNode {
                state.didReplaceSourcePath = true
                state.sourcePathNode = state.makeNode(
                    kind: .file,
                    mode: S_IFREG | mode_t(0o600),
                    bytes: descriptor.node.bytes
                )
            }
            return .success(count)
        }
    }

    func readAt(
        fileDescriptor: Int32,
        buffer: UnsafeMutableRawPointer,
        byteCount: Int,
        offset: Int64
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        lock.withLock {
            state.events.append("pread:\(byteCount):\(offset)")
            guard offset >= 0,
                  offset <= Int64(Int.max),
                  let descriptor = state.descriptors[fileDescriptor],
                  descriptor.node.kind == .file else {
                return .failure(EINVAL)
            }
            if let failure = state.popFailure("pread") {
                return .failure(failure)
            }
            var restoredPath: (Node, String, Node)?
            if let replacementBytes = state.transientPreadReplacementBytes,
               let pending = state.pendingDirectory(create: false),
               let published = pending.children.first(where: {
                   $0.value === descriptor.node
               }) {
                let replacement = state.makeNode(
                    kind: .file,
                    mode: published.value.mode,
                    bytes: replacementBytes
                )
                pending.children[published.key] = replacement
                restoredPath = (pending, published.key, published.value)
                state.transientPreadReplacementBytes = nil
                state.didUseTransientPreadReplacement = true
            }
            defer {
                if let restoredPath {
                    restoredPath.0.children[restoredPath.1] = restoredPath.2
                }
            }
            let start = Int(offset)
            let available = max(0, descriptor.node.bytes.count - start)
            let count = min(byteCount, available)
            if count > 0 {
                descriptor.node.bytes.withUnsafeBytes { source in
                    _ = Darwin.memcpy(
                        buffer,
                        source.baseAddress!.advanced(by: start),
                        count
                    )
                }
            }
            return .success(count)
        }
    }

    func write(
        fileDescriptor: Int32,
        buffer: UnsafeRawPointer,
        byteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        lock.withLock {
            state.events.append("write:\(byteCount)")
            state.maximumWriteRequest = max(state.maximumWriteRequest, byteCount)
            if let failure = state.popFailure("write") { return .failure(failure) }
            guard let descriptor = state.descriptors[fileDescriptor],
                  descriptor.node.kind == .file else {
                return .failure(EBADF)
            }
            let count = min(byteCount, state.writeLimit ?? Int.max)
            state.maximumWriteResult = max(state.maximumWriteResult, count)
            let source = UnsafeRawBufferPointer(start: buffer, count: count)
            let endOffset = descriptor.offset + count
            if descriptor.node.bytes.count < endOffset {
                descriptor.node.bytes.append(
                    contentsOf: repeatElement(
                        0,
                        count: endOffset - descriptor.node.bytes.count
                    )
                )
            }
            descriptor.node.bytes.replaceSubrange(
                descriptor.offset..<endOffset,
                with: source
            )
            descriptor.offset = endOffset
            descriptor.node.version += 1
            return .success(count)
        }
    }

    func synchronize(fileDescriptor: Int32) -> IOSPendingRecordingPOSIXResult<Void> {
        lock.withLock {
            guard let node = state.descriptors[fileDescriptor]?.node else {
                return .failure(EBADF)
            }
            state.events.append(
                node.kind == .directory ? "fsync:directory" : "fsync:file"
            )
            if node.kind == .directory,
               let failure = state.popFailure("fsyncDirectory") {
                return .failure(failure)
            }
            if let failure = state.popFailure("fsync") { return .failure(failure) }
            return .success(())
        }
    }

    func changeMode(
        fileDescriptor: Int32,
        mode: mode_t
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        lock.withLock {
            state.events.append("chmod:\(String(mode, radix: 8))")
            guard let node = state.descriptors[fileDescriptor]?.node else {
                return .failure(EBADF)
            }
            node.mode = (node.mode & S_IFMT) | mode
            return .success(())
        }
    }

    func lock(
        fileDescriptor: Int32,
        operation: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        lock.withLock {
            state.events.append("flock")
            if let failure = state.popFailure("flock") { return .failure(failure) }
            guard let node = state.descriptors[fileDescriptor]?.node else {
                return .failure(EBADF)
            }
            guard node.lockedByDescriptor == nil
                    || node.lockedByDescriptor == fileDescriptor else {
                return .failure(EWOULDBLOCK)
            }
            node.lockedByDescriptor = fileDescriptor
            return .success(())
        }
    }

    func setExtendedAttribute(
        fileDescriptor: Int32,
        name: String,
        value: [UInt8],
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        lock.withLock {
            state.events.append("setxattr:\(name)")
            if let failure = state.popFailure("setXattr") {
                return .failure(failure)
            }
            guard let node = state.descriptors[fileDescriptor]?.node else {
                return .failure(EBADF)
            }
            if flags & XATTR_CREATE != 0, node.extendedAttributes[name] != nil {
                return .failure(EEXIST)
            }
            node.extendedAttributes[name] = value
            return .success(())
        }
    }

    func extendedAttribute(
        fileDescriptor: Int32,
        name: String,
        maximumByteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<[UInt8]> {
        lock.withLock {
            state.events.append("getxattr:\(name)")
            guard let node = state.descriptors[fileDescriptor]?.node,
                  let value = node.extendedAttributes[name] else {
                return .failure(ENOATTR)
            }
            guard value.count <= maximumByteCount else { return .failure(ERANGE) }
            return .success(value)
        }
    }

    func setProtectionClass(
        fileDescriptor: Int32,
        protectionClass: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        lock.withLock {
            state.events.append("setprotection:\(protectionClass)")
            if let failure = state.popFailure("setProtection") {
                return .failure(failure)
            }
            guard let node = state.descriptors[fileDescriptor]?.node else {
                return .failure(EBADF)
            }
            node.protectionClass = protectionClass
            return .success(())
        }
    }

    func protectionClass(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        lock.withLock {
            state.events.append("getprotection")
            guard let value = state.descriptors[fileDescriptor]?.node
                .protectionClass else {
                return .failure(ENOATTR)
            }
            return .success(value)
        }
    }

    func publishExclusively(
        directoryDescriptor: Int32,
        temporaryName: String,
        finalName: String
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        lock.withLock {
            state.events.append("publish-exclusive")
            if let failure = state.popFailure("publish") { return .failure(failure) }
            guard let directory = state.descriptors[directoryDescriptor]?.node,
                  directory.children[finalName] == nil,
                  let node = directory.children.removeValue(forKey: temporaryName) else {
                return .failure(EEXIST)
            }
            directory.children[finalName] = node
            directory.version += 1
            return .success(())
        }
    }

    func unlinkAt(
        directoryDescriptor: Int32,
        name: String
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        lock.withLock {
            state.events.append("unlink:\(name)")
            if let failure = state.popFailure("unlink") { return .failure(failure) }
            guard let directory = state.descriptors[directoryDescriptor]?.node,
                  let node = directory.children.removeValue(forKey: name) else {
                return .failure(ENOENT)
            }
            node.linkCount = 0
            directory.version += 1
            return .success(())
        }
    }

    func openDirectoryStream(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<UnsafeMutablePointer<DIR>> {
        lock.withLock {
            state.events.append("fdopendir")
            guard let directory = state.descriptors.removeValue(
                forKey: fileDescriptor
            )?.node, directory.kind == .directory else {
                return .failure(EBADF)
            }
            let raw = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
            let stream = raw.assumingMemoryBound(to: DIR.self)
            state.streams[Int(bitPattern: raw)] = DirectoryStreamState(
                entries: [".", ".."] + directory.children.keys.sorted()
            )
            return .success(stream)
        }
    }

    func nextDirectoryEntry(
        stream: UnsafeMutablePointer<DIR>
    ) -> IOSPendingRecordingPOSIXResult<IOSPendingRecordingDirectoryEntry?> {
        lock.withLock {
            state.events.append("readdir")
            let key = Int(bitPattern: UnsafeMutableRawPointer(stream))
            guard var value = state.streams[key] else { return .failure(EBADF) }
            guard value.index < value.entries.count else { return .success(nil) }
            let name = value.entries[value.index]
            value.index += 1
            state.streams[key] = value
            return .success(.name(name))
        }
    }

    func closeFile(_ fileDescriptor: Int32) {
        lock.withLock {
            state.events.append("close")
            guard let descriptor = state.descriptors.removeValue(
                forKey: fileDescriptor
            ) else { return }
            if descriptor.node.lockedByDescriptor == fileDescriptor {
                descriptor.node.lockedByDescriptor = nil
            }
            lock.broadcast()
        }
    }

    func closeDirectoryStream(_ stream: UnsafeMutablePointer<DIR>) {
        lock.withLock {
            let raw = UnsafeMutableRawPointer(stream)
            state.streams.removeValue(forKey: Int(bitPattern: raw))
            raw.deallocate()
        }
    }

    private static func makeStatus(_ node: Node) -> stat {
        var value = stat()
        value.st_dev = node.device
        value.st_ino = node.inode
        value.st_mode = node.mode
        value.st_nlink = node.linkCount
        value.st_uid = node.owner
        value.st_size = off_t(node.bytes.count)
        value.st_mtimespec = timespec(tv_sec: node.version, tv_nsec: 0)
        value.st_ctimespec = timespec(tv_sec: node.version, tv_nsec: 0)
        return value
    }

    private static let backupExclusionValue: [UInt8] = [
        0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30,
        0x5F, 0x10, 0x11, 0x63, 0x6F, 0x6D, 0x2E, 0x61,
        0x70, 0x70, 0x6C, 0x65, 0x2E, 0x62, 0x61, 0x63,
        0x6B, 0x75, 0x70, 0x64, 0x08, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x1C,
    ]
}
