import Darwin
import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSCaptureTransferWireCodecTests {
    private let attemptID = UUID(
        uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF"
    )!

    @Test func exactTransferBindingRoundTripsAsFiftyOneBytes() {
        let binding = IOSForegroundVoiceCaptureTransferBinding(
            attemptID: attemptID,
            sourceDevice: 0x0102_0304_0506_0708,
            sourceInode: 0x1112_1314_1516_1718,
            sourceGeneration: 0x2122_2324,
            outputIntent: .translate,
            format: .wav,
            durationMilliseconds: 1_500,
            byteCount: 65_537
        )

        let bytes = IOSForegroundVoiceCaptureSourceWireCodec
            .transferBinding(binding)

        #expect(bytes.count == 51)
        #expect(bytes[0] == 1)
        #expect(Array(bytes[17..<25]) == [
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        ])
        #expect(Array(bytes[25..<33]) == [
            0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
        ])
        #expect(Array(bytes[33..<37]) == [0x21, 0x22, 0x23, 0x24])
        #expect(bytes[37] == 2)
        #expect(bytes[38] == 2)
        #expect(Array(bytes[39..<43]) == [0x00, 0x00, 0x05, 0xDC])
        #expect(Array(bytes[43..<51]) == [
            0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01,
        ])
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeTransferBinding(bytes) == binding
        )
    }

    @Test func transferBindingRejectsAlternateAndInvalidWireValues() {
        let binding = IOSForegroundVoiceCaptureTransferBinding(
            attemptID: attemptID,
            sourceDevice: 1,
            sourceInode: 2,
            sourceGeneration: 3,
            outputIntent: .standard,
            format: .m4a,
            durationMilliseconds: 300,
            byteCount: 1
        )
        let canonical = IOSForegroundVoiceCaptureSourceWireCodec
            .transferBinding(binding)

        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeTransferBinding(Array(canonical.dropLast())) == nil
        )
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeTransferBinding(canonical + [0]) == nil
        )

        var futureSchema = canonical
        futureSchema[0] = 2
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeTransferBinding(futureSchema) == nil
        )

        var reservedIntent = canonical
        reservedIntent[37] = 0
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeTransferBinding(reservedIntent) == nil
        )

        var reservedFormat = canonical
        reservedFormat[38] = 3
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeTransferBinding(reservedFormat) == nil
        )

        var tooShort = canonical
        tooShort.replaceSubrange(39..<43, with: [0x00, 0x00, 0x01, 0x2B])
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeTransferBinding(tooShort) == nil
        )

        var maximumDuration = canonical
        maximumDuration.replaceSubrange(
            39..<43,
            with: [0x00, 0x04, 0x93, 0xE0]
        )
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeTransferBinding(maximumDuration) == nil
        )

        var empty = canonical
        empty.replaceSubrange(43..<51, with: repeatElement(0, count: 8))
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeTransferBinding(empty) == nil
        )

        var maximumBytes = canonical
        maximumBytes.replaceSubrange(
            43..<51,
            with: [0x00, 0x00, 0x00, 0x00, 0x01, 0x7D, 0x78, 0x40]
        )
        #expect(
            IOSForegroundVoiceCaptureSourceWireCodec
                .decodeTransferBinding(maximumBytes) == nil
        )
    }
}

struct IOSCaptureTransferAudioFileSystemTests {
    private let attemptID = UUID(
        uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF"
    )!
    private let audioBytes = [UInt8](repeating: 0x5A, count: 96)

    @Test func descriptorSourcePublishesTransferBoundPendingAudio()
        async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        try await fixture.context.operationGate.perform { lease in
            let inventory = IOSProtectedAudioNamespaceInventory(
                testingRepositoryBinding: fixture.context.repositoryBinding,
                operationLeaseAuthorization: lease,
                artifacts: []
            )
            let startEventIndex = fixture.adapter.events.count

            let published = try await fixture.fileSystem
                .publishOrRecoverCaptureTransfer(
                    from: fixture.source,
                    inventory: inventory
                )
            defer { published.release() }

            #expect(
                published.relativeIdentifier
                    == "Recordings/Pending/"
                        + "recording-v1-01234567-89ab-cdef-0123-456789abcdef.wav"
            )
            #expect(published.durationMilliseconds == 1_500)
            #expect(published.audioArtifact.byteCount == Int64(audioBytes.count))
            #expect(fixture.adapter.publishedBytes == audioBytes)
            #expect(
                fixture.adapter.pendingNames
                    == [
                        "recording-v1-01234567-89ab-cdef-0123-456789abcdef.wav",
                    ]
            )

            let bindingBytes = try readPublishedAttribute(
                fixture: fixture,
                name: "com.holdtype.ios.capture-source-transfer"
            )
            #expect(bindingBytes.count == 51)
            #expect(
                IOSForegroundVoiceCaptureSourceWireCodec
                    .decodeTransferBinding(bindingBytes)
                    == fixture.source.transferBinding
            )
            #expect(
                try readPublishedAttribute(
                    fixture: fixture,
                    name: "com.holdtype.ios.pending-recording-audio"
                ) == Array("v1".utf8)
            )

            let events = Array(fixture.adapter.events[startEventIndex...])
            let bindingIndex = try #require(
                events.firstIndex(
                    of: "setxattr:com.holdtype.ios.capture-source-transfer"
                )
            )
            let firstWriteIndex = try #require(
                events.firstIndex(where: { $0.hasPrefix("write:") })
            )
            #expect(bindingIndex < firstWriteIndex)
            #expect(
                events[(bindingIndex + 1)..<firstWriteIndex]
                    .contains("fsync:file")
            )
            #expect(events.contains(where: { $0.hasPrefix("pread:") }))
            #expect(!events.contains(where: { $0.hasPrefix("read:") }))
            _ = try await published.revalidate()
        }

        #expect(fixture.operationFinished.value == 1)
    }

    @Test func malformedPublishedTransferBindingIsRejectedAndPreserved()
        async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        try await fixture.context.operationGate.perform { lease in
            let inventory = IOSProtectedAudioNamespaceInventory(
                testingRepositoryBinding: fixture.context.repositoryBinding,
                operationLeaseAuthorization: lease,
                artifacts: []
            )
            let initial = try await fixture.fileSystem
                .publishOrRecoverCaptureTransfer(
                    from: fixture.source,
                    inventory: inventory
                )
            initial.release()
            try replacePublishedTransferBinding(
                fixture: fixture,
                value: [UInt8](repeating: 0xA5, count: 50)
            )

            await #expect(
                throws: IOSPendingRecordingAudioFileSystemError
                    .protectedAudioInvalid
            ) {
                _ = try await fixture.fileSystem
                    .publishOrRecoverCaptureTransfer(
                        from: fixture.source,
                        inventory: inventory
                    )
            }

            #expect(fixture.adapter.publishedBytes == audioBytes)
            #expect(fixture.adapter.pendingNames.count == 1)
        }

        #expect(fixture.operationFinished.value == 2)
    }

    @Test func mismatchedPublishedTransferBindingIsRejectedAndPreserved()
        async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        try await fixture.context.operationGate.perform { lease in
            let inventory = IOSProtectedAudioNamespaceInventory(
                testingRepositoryBinding: fixture.context.repositoryBinding,
                operationLeaseAuthorization: lease,
                artifacts: []
            )
            let initial = try await fixture.fileSystem
                .publishOrRecoverCaptureTransfer(
                    from: fixture.source,
                    inventory: inventory
                )
            initial.release()
            let binding = try #require(fixture.source.transferBinding)
            let mismatched = IOSForegroundVoiceCaptureTransferBinding(
                attemptID: binding.attemptID,
                sourceDevice: binding.sourceDevice,
                sourceInode: binding.sourceInode &+ 1,
                sourceGeneration: binding.sourceGeneration,
                outputIntent: binding.outputIntent,
                format: binding.format,
                durationMilliseconds: binding.durationMilliseconds,
                byteCount: binding.byteCount
            )
            try replacePublishedTransferBinding(
                fixture: fixture,
                value: IOSForegroundVoiceCaptureSourceWireCodec
                    .transferBinding(mismatched)
            )

            await #expect(
                throws: IOSPendingRecordingAudioFileSystemError
                    .protectedAudioInvalid
            ) {
                _ = try await fixture.fileSystem
                    .publishOrRecoverCaptureTransfer(
                        from: fixture.source,
                        inventory: inventory
                    )
            }

            #expect(fixture.adapter.publishedBytes == audioBytes)
            #expect(fixture.adapter.pendingNames.count == 1)
        }

        #expect(fixture.operationFinished.value == 2)
    }

    private func makeFixture() throws -> CaptureTransferFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-capture-transfer-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: false
        )
        var rootStatus = stat()
        let didReadRoot = rootURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return Darwin.lstat(path, &rootStatus) == 0
        }
        guard didReadRoot else {
            try? FileManager.default.removeItem(at: rootURL)
            throw CaptureTransferTestError.fixtureSetup
        }

        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let context = registry.context(for: rootURL)
        let adapter = SimulatedPendingRecordingPOSIXAdapter(
            sourceBytes: audioBytes,
            applicationSupportPath: rootURL.path,
            applicationSupportDevice: rootStatus.st_dev,
            applicationSupportInode: rootStatus.st_ino
        )
        let sourceDescriptor = try requireSuccess(
            adapter.openPath(
                "/source.m4a",
                flags: O_RDWR | O_CLOEXEC | O_NOFOLLOW,
                mode: nil
            )
        )
        do {
            let sourceStatus = try requireSuccess(
                adapter.status(of: sourceDescriptor)
            )
            let device = try #require(UInt64(exactly: sourceStatus.st_dev))
            let inode = try #require(UInt64(exactly: sourceStatus.st_ino))
            let creationMilliseconds: UInt64 = 1_750_000_000_123
            let identity = IOSForegroundVoiceCaptureIdentity(
                attemptID: attemptID,
                outputIntent: .translate,
                format: .wav,
                creationMilliseconds: creationMilliseconds,
                device: device,
                inode: inode,
                generation: UInt32(sourceStatus.st_gen)
            )
            let completion = IOSForegroundVoiceCaptureCompletion(
                durationMilliseconds: 1_500,
                byteCount: UInt64(audioBytes.count),
                modificationSeconds: Int64(sourceStatus.st_mtimespec.tv_sec),
                modificationNanoseconds: UInt32(
                    sourceStatus.st_mtimespec.tv_nsec
                )
            )
            try requireVoid(
                adapter.setProtectionClass(
                    fileDescriptor: sourceDescriptor,
                    protectionClass: FoundationIOSPendingRecordingAudioFileSystem
                        .completeProtectionClass
                )
            )
            try setCreatedAttribute(
                adapter: adapter,
                descriptor: sourceDescriptor,
                name: IOSForegroundVoiceCaptureSourceFileSystem.sourceMarkerName,
                value: IOSForegroundVoiceCaptureSourceFileSystem.markerValue
            )
            try setCreatedAttribute(
                adapter: adapter,
                descriptor: sourceDescriptor,
                name: IOSForegroundVoiceCaptureSourceFileSystem.identityName,
                value: IOSForegroundVoiceCaptureSourceWireCodec.identity(identity)
            )
            try setCreatedAttribute(
                adapter: adapter,
                descriptor: sourceDescriptor,
                name: IOSForegroundVoiceCaptureSourceFileSystem.completionName,
                value: IOSForegroundVoiceCaptureSourceWireCodec
                    .completion(completion)
            )
            try setCreatedAttribute(
                adapter: adapter,
                descriptor: sourceDescriptor,
                name: IOSForegroundVoiceCaptureSourceFileSystem.phaseName,
                value: IOSForegroundVoiceCaptureSourceWireCodec
                    .phase(.preparingPending)
            )
            try setCreatedAttribute(
                adapter: adapter,
                descriptor: sourceDescriptor,
                name: FoundationIOSPendingRecordingAudioFileSystem
                    .backupExclusionAttributeName,
                value: FoundationIOSPendingRecordingAudioFileSystem
                    .backupExclusionAttributeValue
            )

            let operationFinished = LockedInteger()
            let source = IOSPendingRecordingCaptureTransferSource(
                fileDescriptor: sourceDescriptor,
                attemptID: attemptID,
                outputIntent: .translate,
                format: .wav,
                creationMilliseconds: creationMilliseconds,
                device: device,
                inode: inode,
                generation: UInt32(sourceStatus.st_gen),
                durationMilliseconds: 1_500,
                byteCount: Int64(audioBytes.count),
                modificationSeconds: Int64(sourceStatus.st_mtimespec.tv_sec),
                modificationNanoseconds: UInt32(
                    sourceStatus.st_mtimespec.tv_nsec
                ),
                onOperationFinished: { operationFinished.increment() }
            )
            let fileSystem = FoundationIOSPendingRecordingAudioFileSystem(
                applicationSupportDirectoryURL: rootURL,
                adapter: adapter,
                mediaValidator: ConstantCaptureTransferMediaValidator(
                    durationMilliseconds: 1_500
                ),
                monotonicClock: { 1 },
                expectedRepositoryRoot:
                    context.repositoryBinding.physicalRootIdentity,
                queue: DispatchQueue(
                    label: "capture-transfer-foundation-tests"
                )
            )
            return CaptureTransferFixture(
                rootURL: rootURL,
                context: context,
                adapter: adapter,
                fileSystem: fileSystem,
                sourceDescriptor: sourceDescriptor,
                source: source,
                operationFinished: operationFinished
            )
        } catch {
            adapter.closeFile(sourceDescriptor)
            try? FileManager.default.removeItem(at: rootURL)
            throw error
        }
    }

    private func readPublishedAttribute(
        fixture: CaptureTransferFixture,
        name: String
    ) throws -> [UInt8] {
        let descriptor = try openPublishedDescriptor(fixture: fixture)
        defer { fixture.adapter.closeFile(descriptor) }
        return try requireSuccess(
            fixture.adapter.extendedAttribute(
                fileDescriptor: descriptor,
                name: name,
                maximumByteCount: 128
            )
        )
    }

    private func replacePublishedTransferBinding(
        fixture: CaptureTransferFixture,
        value: [UInt8]
    ) throws {
        let descriptor = try openPublishedDescriptor(fixture: fixture)
        defer { fixture.adapter.closeFile(descriptor) }
        try requireVoid(
            fixture.adapter.setExtendedAttribute(
                fileDescriptor: descriptor,
                name: "com.holdtype.ios.capture-source-transfer",
                value: value,
                flags: XATTR_REPLACE
            )
        )
    }

    private func openPublishedDescriptor(
        fixture: CaptureTransferFixture
    ) throws -> Int32 {
        let root = try requireSuccess(
            fixture.adapter.openPath(
                fixture.rootURL.path,
                flags: O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW,
                mode: nil
            )
        )
        var current = root
        do {
            for name in ["HoldType", "Recordings", "Pending"] {
                let next = try requireSuccess(
                    fixture.adapter.openAt(
                        directoryDescriptor: current,
                        name: name,
                        flags: O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW,
                        mode: nil
                    )
                )
                fixture.adapter.closeFile(current)
                current = next
            }
            let finalName = try #require(fixture.adapter.pendingNames.first)
            let file = try requireSuccess(
                fixture.adapter.openAt(
                    directoryDescriptor: current,
                    name: finalName,
                    flags: O_RDWR | O_CLOEXEC | O_NOFOLLOW,
                    mode: nil
                )
            )
            fixture.adapter.closeFile(current)
            return file
        } catch {
            fixture.adapter.closeFile(current)
            throw error
        }
    }

    private func setCreatedAttribute(
        adapter: SimulatedPendingRecordingPOSIXAdapter,
        descriptor: Int32,
        name: String,
        value: [UInt8]
    ) throws {
        try requireVoid(
            adapter.setExtendedAttribute(
                fileDescriptor: descriptor,
                name: name,
                value: value,
                flags: XATTR_CREATE
            )
        )
    }

    private func requireSuccess<Value>(
        _ result: IOSPendingRecordingPOSIXResult<Value>
    ) throws -> Value {
        guard case let .success(value) = result else {
            throw CaptureTransferTestError.posixFailure
        }
        return value
    }

    private func requireVoid(
        _ result: IOSPendingRecordingPOSIXResult<Void>
    ) throws {
        _ = try requireSuccess(result)
    }
}

private struct CaptureTransferFixture {
    let rootURL: URL
    let context: IOSAcceptedHistoryCoordinatorProcessContext
    let adapter: SimulatedPendingRecordingPOSIXAdapter
    let fileSystem: FoundationIOSPendingRecordingAudioFileSystem
    let sourceDescriptor: Int32
    let source: IOSPendingRecordingCaptureTransferSource
    let operationFinished: LockedInteger

    func close() {
        adapter.closeFile(sourceDescriptor)
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private final class ConstantCaptureTransferMediaValidator:
    IOSPendingRecordingMediaValidating,
    @unchecked Sendable {
    private let durationMilliseconds: Int64

    init(durationMilliseconds: Int64) {
        self.durationMilliseconds = durationMilliseconds
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
        _ = timeoutNanoseconds
        return durationMilliseconds
    }
}

private final class LockedInteger: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int { lock.withLock { storedValue } }

    func increment() {
        lock.withLock { storedValue += 1 }
    }
}

private enum CaptureTransferTestError: Error {
    case fixtureSetup
    case posixFailure
}
