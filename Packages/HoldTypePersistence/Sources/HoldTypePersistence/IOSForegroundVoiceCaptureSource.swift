import Darwin
import Foundation
import HoldTypeDomain

@_spi(HoldTypeIOSCore)
public enum IOSForegroundVoiceCaptureSourceError: Error, Equatable, Sendable {
    case invalidCreationTime
    case captureAlreadyExists
    case namespaceUnavailable
    case namespaceInvalid
    case sourceConflict
    case sourceChanged
    case invalidLeaseState
    case dataProtectionUnavailable
    case synchronizationFailed
    case mediaValidationFailed
    case mediaValidationTimedOut
    case cleanupUncertain
}

@_spi(HoldTypeIOSCore)
public enum IOSForegroundVoiceCaptureInvalidReason: Equatable, Sendable {
    case empty
    case tooShort
    case maximumDurationReached
    case invalidMedia
}

@_spi(HoldTypeIOSCore)
public enum IOSForegroundVoiceCaptureFinalizationResult: Sendable {
    case completed(IOSForegroundVoiceCompletedCapture)
    case discarded(IOSForegroundVoiceCaptureInvalidReason)
}

@_spi(HoldTypeIOSCore)
public enum IOSForegroundVoiceCaptureRecoveryStatus: Equatable, Sendable {
    case empty
    case recordingInProgress
    case activeNeedsRecovery
    case emptyActiveNeedsDiscard
    case finalizingNeedsRecovery
    case completedNeedsPendingHandoff
    case preparingPendingNeedsRecovery
    case cleanupPerformed
    case blockedUnknown
}

@_spi(HoldTypeIOSCore)
public struct IOSForegroundVoiceCaptureRecoveryObservation: Equatable, Sendable {
    public let status: IOSForegroundVoiceCaptureRecoveryStatus
    public let examinedEntryCount: Int
    public let removedEntryCount: Int
    public let removedLogicalByteCount: Int64

    init(
        status: IOSForegroundVoiceCaptureRecoveryStatus,
        examinedEntryCount: Int,
        removedEntryCount: Int,
        removedLogicalByteCount: Int64
    ) {
        self.status = status
        self.examinedEntryCount = examinedEntryCount
        self.removedEntryCount = removedEntryCount
        self.removedLogicalByteCount = removedLogicalByteCount
    }
}

@_spi(HoldTypeIOSCore)
public actor IOSForegroundVoiceCaptureSourceOwner {
    private let fileSystem: IOSForegroundVoiceCaptureSourceFileSystem
    private weak var liveLease: IOSForegroundVoiceCaptureSourceLease?

    init(
        applicationSupportDirectoryURL: URL,
        mediaValidationWorkerGate: AudioToolboxMediaValidationWorkerGate
    ) {
        fileSystem = IOSForegroundVoiceCaptureSourceFileSystem(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            adapter: DarwinIOSPendingRecordingPOSIXAdapter(),
            mediaValidator: AudioToolboxIOSPendingRecordingMediaValidator(
                workerGate: mediaValidationWorkerGate
            ),
            now: { Date() },
            monotonicClock: { captureSourceMonotonicNanoseconds() },
            queue: DispatchQueue(
                label: "app.holdtype.foreground-capture-source",
                qos: .userInitiated
            )
        )
    }

    init(
        applicationSupportDirectoryURL: URL,
        adapter: any IOSPendingRecordingPOSIXAdapter,
        mediaValidator: any IOSPendingRecordingMediaValidating,
        now: @escaping @Sendable () -> Date,
        monotonicClock: @escaping @Sendable () -> UInt64?,
        queue: DispatchQueue = DispatchQueue(
            label: "app.holdtype.foreground-capture-source.tests"
        )
    ) {
        fileSystem = IOSForegroundVoiceCaptureSourceFileSystem(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            adapter: adapter,
            mediaValidator: mediaValidator,
            now: now,
            monotonicClock: monotonicClock,
            queue: queue
        )
    }

    public func createCapture(
        attemptID: UUID,
        outputIntent: DictationOutputIntent
    ) async throws -> IOSForegroundVoiceCaptureSourceLease {
        try await createCapture(
            attemptID: attemptID,
            outputIntent: outputIntent,
            format: .m4a
        )
    }

    func createCapture(
        attemptID: UUID,
        outputIntent: DictationOutputIntent,
        format: IOSPendingRecordingAudioFormat
    ) async throws -> IOSForegroundVoiceCaptureSourceLease {
        if let liveLease, liveLease.isOpen {
            throw IOSForegroundVoiceCaptureSourceError.captureAlreadyExists
        }
        let lease = try await fileSystem.createCapture(
            attemptID: attemptID,
            outputIntent: outputIntent,
            format: format
        )
        liveLease = lease
        return lease
    }

    public func reconcileCaptureSourcesAtLaunch() async
        -> IOSForegroundVoiceCaptureRecoveryObservation {
        if let liveLease, liveLease.isOpen {
            return IOSForegroundVoiceCaptureRecoveryObservation(
                status: .recordingInProgress,
                examinedEntryCount: 0,
                removedEntryCount: 0,
                removedLogicalByteCount: 0
            )
        }
        return await fileSystem.reconcileAtLaunch()
    }
}

@_spi(HoldTypeIOSCore)
public final class IOSForegroundVoiceCaptureSourceLease: @unchecked Sendable {
    private struct State {
        var phase = IOSForegroundVoiceCaptureSourcePhase.active
        var activeOperationCount = 0
        var releaseRequested = false
        var directoryDescriptor: Int32?
        var fileDescriptor: Int32?
    }

    struct BorrowedHandles: Sendable {
        let directoryDescriptor: Int32
        let fileDescriptor: Int32
    }

    private let lock = NSLock()
    private let fileSystem: IOSForegroundVoiceCaptureSourceFileSystem
    private let recordingURL: URL
    fileprivate let identity: IOSForegroundVoiceCaptureIdentity
    fileprivate let finalName: String
    private var state: State

    fileprivate init(
        fileSystem: IOSForegroundVoiceCaptureSourceFileSystem,
        recordingURL: URL,
        identity: IOSForegroundVoiceCaptureIdentity,
        finalName: String,
        directoryDescriptor: Int32,
        fileDescriptor: Int32
    ) {
        self.fileSystem = fileSystem
        self.recordingURL = recordingURL
        self.identity = identity
        self.finalName = finalName
        state = State(
            directoryDescriptor: directoryDescriptor,
            fileDescriptor: fileDescriptor
        )
    }

    fileprivate var isOpen: Bool {
        lock.withLock {
            !state.releaseRequested && state.fileDescriptor != nil
        }
    }

    public func withTransientRecordingURL(
        _ body: (URL) throws -> Void
    ) throws {
        let handles = try beginOperation(allowedPhases: [.active])
        defer { finishOperation() }
        try fileSystem.revalidateTransientURLExposure(
            handles: handles,
            identity: identity,
            finalName: finalName
        )
        try body(recordingURL)
    }

    public func revalidateRecorderCheckpoint() async throws {
        let handles = try beginOperation(allowedPhases: [.active])
        defer { finishOperation() }
        try await fileSystem.revalidateRecorderCheckpoint(
            handles: handles,
            identity: identity,
            finalName: finalName
        )
    }

    public func beginFinalizing() async throws {
        let handles = try beginOperation(allowedPhases: [.active])
        defer { finishOperation() }
        try await fileSystem.beginFinalizing(
            handles: handles,
            identity: identity,
            finalName: finalName
        )
        lock.withLock { state.phase = .finalizing }
    }

    public func completeAfterRecorderClose() async throws
        -> IOSForegroundVoiceCaptureFinalizationResult {
        let handles = try beginOperation(allowedPhases: [.finalizing])
        defer { finishOperation() }
        let result = try await fileSystem.completeAfterRecorderClose(
            handles: handles,
            identity: identity,
            finalName: finalName
        )
        switch result {
        case let .completed(completion):
            lock.withLock { state.phase = .completed }
            return .completed(
                IOSForegroundVoiceCompletedCapture(
                    lease: self,
                    completion: completion
                )
            )
        case let .discarded(reason):
            lock.withLock {
                state.phase = .discarding
                state.releaseRequested = true
            }
            return .discarded(reason)
        }
    }

    public func beginDiscardingBeforeRecorderStop() async throws {
        let handles = try beginOperation(allowedPhases: [.active, .finalizing])
        defer { finishOperation() }
        try await fileSystem.beginDiscarding(
            handles: handles,
            identity: identity,
            finalName: finalName,
            expectedPhases: [.active, .finalizing]
        )
        lock.withLock { state.phase = .discarding }
    }

    public func finishDiscardAfterRecorderStop() async throws {
        let handles = try beginOperation(allowedPhases: [.discarding])
        defer { finishOperation() }
        try await fileSystem.removeDiscarding(
            handles: handles,
            identity: identity,
            finalName: finalName
        )
        lock.withLock {
            state.releaseRequested = true
        }
    }

    public func release() {
        let descriptors = lock.withLock { () -> (Int32?, Int32?) in
            state.releaseRequested = true
            guard state.activeOperationCount == 0 else { return (nil, nil) }
            return takeDescriptorsForClose()
        }
        close(descriptors)
    }

    private func beginOperation(
        allowedPhases: Set<IOSForegroundVoiceCaptureSourcePhase>
    ) throws -> BorrowedHandles {
        try lock.withLock {
            guard !state.releaseRequested,
                  state.activeOperationCount == 0,
                  allowedPhases.contains(state.phase),
                  let directoryDescriptor = state.directoryDescriptor,
                  let fileDescriptor = state.fileDescriptor else {
                throw IOSForegroundVoiceCaptureSourceError.invalidLeaseState
            }
            state.activeOperationCount += 1
            return BorrowedHandles(
                directoryDescriptor: directoryDescriptor,
                fileDescriptor: fileDescriptor
            )
        }
    }

    private func finishOperation() {
        let descriptors = lock.withLock { () -> (Int32?, Int32?) in
            precondition(state.activeOperationCount > 0)
            state.activeOperationCount -= 1
            guard state.activeOperationCount == 0,
                  state.releaseRequested else {
                return (nil, nil)
            }
            return takeDescriptorsForClose()
        }
        close(descriptors)
    }

    private func takeDescriptorsForClose() -> (Int32?, Int32?) {
        let descriptors = (state.directoryDescriptor, state.fileDescriptor)
        state.directoryDescriptor = nil
        state.fileDescriptor = nil
        return descriptors
    }

    private func close(_ descriptors: (Int32?, Int32?)) {
        if let fileDescriptor = descriptors.1 {
            fileSystem.adapter.closeFile(fileDescriptor)
        }
        if let directoryDescriptor = descriptors.0 {
            fileSystem.adapter.closeFile(directoryDescriptor)
        }
    }

    deinit { release() }
}

@_spi(HoldTypeIOSCore)
public final class IOSForegroundVoiceCompletedCapture: @unchecked Sendable {
    private let lease: IOSForegroundVoiceCaptureSourceLease
    fileprivate let completion: IOSForegroundVoiceCaptureCompletion

    public var durationMilliseconds: Int64 {
        Int64(completion.durationMilliseconds)
    }

    public var byteCount: Int64 {
        Int64(completion.byteCount)
    }

    fileprivate init(
        lease: IOSForegroundVoiceCaptureSourceLease,
        completion: IOSForegroundVoiceCaptureCompletion
    ) {
        self.lease = lease
        self.completion = completion
    }

    public func release() { lease.release() }
}

extension IOSForegroundVoiceCaptureSourceError: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSForegroundVoiceCaptureSourceError(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceCaptureRecoveryObservation: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "IOSForegroundVoiceCaptureRecoveryObservation(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceCaptureSourceLease: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSForegroundVoiceCaptureSourceLease(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceCompletedCapture: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSForegroundVoiceCompletedCapture(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum CaptureSourceFinalizationFileSystemResult: Sendable {
    case completed(IOSForegroundVoiceCaptureCompletion)
    case discarded(IOSForegroundVoiceCaptureInvalidReason)
}

private struct CaptureSourceDirectoryHandle: Sendable {
    let descriptor: Int32
    let URL: Foundation.URL
}

private struct CaptureSourceValidatedFile: Sendable {
    let status: stat
    let identity: IOSForegroundVoiceCaptureIdentity
    let phase: IOSForegroundVoiceCaptureSourcePhase
    let completion: IOSForegroundVoiceCaptureCompletion?
}

final class IOSForegroundVoiceCaptureSourceFileSystem: @unchecked Sendable {
    static let namespaceMarkerName = "com.holdtype.ios.capture-source-namespace"
    static let creationIntentName = "com.holdtype.ios.capture-source-creation-intent"
    static let sourceMarkerName = "com.holdtype.ios.capture-source-audio"
    static let identityName = "com.holdtype.ios.capture-source-identity"
    static let completionName = "com.holdtype.ios.capture-source-completion"
    static let phaseName = "com.holdtype.ios.capture-source-phase"
    static let markerValue = Array("v1".utf8)
    static let maximumEntryCount = 128
    static let maximumRemovalCount = 16
    static let maximumRemovalByteCount: Int64 = 200_000_000
    static let reconciliationDeadlineNanoseconds: UInt64 = 500_000_000
    static let mediaValidationDeadlineNanoseconds: UInt64 = 2_000_000_000

    let adapter: any IOSPendingRecordingPOSIXAdapter
    private let applicationSupportDirectoryURL: URL
    private let mediaValidator: any IOSPendingRecordingMediaValidating
    private let now: @Sendable () -> Date
    private let monotonicClock: @Sendable () -> UInt64?
    private let queue: DispatchQueue

    private var captureNamespaceURL: URL {
        applicationSupportDirectoryURL
            .appendingPathComponent("HoldType", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent("Capture", isDirectory: true)
    }

    init(
        applicationSupportDirectoryURL: URL,
        adapter: any IOSPendingRecordingPOSIXAdapter,
        mediaValidator: any IOSPendingRecordingMediaValidating,
        now: @escaping @Sendable () -> Date,
        monotonicClock: @escaping @Sendable () -> UInt64?,
        queue: DispatchQueue
    ) {
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
        self.adapter = adapter
        self.mediaValidator = mediaValidator
        self.now = now
        self.monotonicClock = monotonicClock
        self.queue = queue
    }

    func createCapture(
        attemptID: UUID,
        outputIntent: DictationOutputIntent,
        format: IOSPendingRecordingAudioFormat
    ) async throws -> IOSForegroundVoiceCaptureSourceLease {
        try await perform {
            try self.performCreateCapture(
                attemptID: attemptID,
                outputIntent: outputIntent,
                format: format
            )
        }
    }

    func revalidateTransientURLExposure(
        handles: IOSForegroundVoiceCaptureSourceLease.BorrowedHandles,
        identity: IOSForegroundVoiceCaptureIdentity,
        finalName: String
    ) throws {
        _ = try validateSource(
            handles: handles,
            expectedIdentity: identity,
            finalName: finalName,
            allowedPhases: [.active]
        )
    }

    func revalidateRecorderCheckpoint(
        handles: IOSForegroundVoiceCaptureSourceLease.BorrowedHandles,
        identity: IOSForegroundVoiceCaptureIdentity,
        finalName: String
    ) async throws {
        try await perform {
            _ = try self.validateSource(
                handles: handles,
                expectedIdentity: identity,
                finalName: finalName,
                allowedPhases: [.active]
            )
        }
    }

    func beginFinalizing(
        handles: IOSForegroundVoiceCaptureSourceLease.BorrowedHandles,
        identity: IOSForegroundVoiceCaptureIdentity,
        finalName: String
    ) async throws {
        try await perform {
            _ = try self.validateSource(
                handles: handles,
                expectedIdentity: identity,
                finalName: finalName,
                allowedPhases: [.active]
            )
            try self.replacePhase(
                .finalizing,
                fileDescriptor: handles.fileDescriptor
            )
        }
    }

    func completeAfterRecorderClose(
        handles: IOSForegroundVoiceCaptureSourceLease.BorrowedHandles,
        identity: IOSForegroundVoiceCaptureIdentity,
        finalName: String
    ) async throws -> CaptureSourceFinalizationFileSystemResult {
        try await perform {
            try self.performCompleteAfterRecorderClose(
                handles: handles,
                identity: identity,
                finalName: finalName
            )
        }
    }

    func beginDiscarding(
        handles: IOSForegroundVoiceCaptureSourceLease.BorrowedHandles,
        identity: IOSForegroundVoiceCaptureIdentity,
        finalName: String,
        expectedPhases: Set<IOSForegroundVoiceCaptureSourcePhase>
    ) async throws {
        try await perform {
            _ = try self.validateSource(
                handles: handles,
                expectedIdentity: identity,
                finalName: finalName,
                allowedPhases: expectedPhases
            )
            try self.replacePhase(
                .discarding,
                fileDescriptor: handles.fileDescriptor
            )
        }
    }

    func removeDiscarding(
        handles: IOSForegroundVoiceCaptureSourceLease.BorrowedHandles,
        identity: IOSForegroundVoiceCaptureIdentity,
        finalName: String
    ) async throws {
        try await perform {
            let status = try self.require(
                self.adapter.status(of: handles.fileDescriptor),
                error: .cleanupUncertain
            )
            if status.st_nlink != 0 {
                _ = try self.validateSource(
                    handles: handles,
                    expectedIdentity: identity,
                    finalName: finalName,
                    allowedPhases: [.discarding]
                )
            }
            try self.removePinnedSource(
                handles: handles,
                finalName: finalName
            )
        }
    }

    func reconcileAtLaunch() async -> IOSForegroundVoiceCaptureRecoveryObservation {
        do {
            return try await perform { try self.performReconcileAtLaunch() }
        } catch {
            return IOSForegroundVoiceCaptureRecoveryObservation(
                status: .blockedUnknown,
                examinedEntryCount: 0,
                removedEntryCount: 0,
                removedLogicalByteCount: 0
            )
        }
    }

    private func perform<Value: Sendable>(
        _ body: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try body() })
            }
        }
    }

    private func performCreateCapture(
        attemptID: UUID,
        outputIntent: DictationOutputIntent,
        format: IOSPendingRecordingAudioFormat
    ) throws -> IOSForegroundVoiceCaptureSourceLease {
        let creationMilliseconds = try currentCreationMilliseconds()
        let namespace = try openCaptureNamespace(createIfMissing: true)
        var namespaceTransferred = false
        defer {
            if !namespaceTransferred {
                adapter.closeFile(namespace.descriptor)
            }
        }
        let creatorDescriptor = try require(
            adapter.openAt(
                directoryDescriptor: namespace.descriptor,
                name: ".",
                flags: O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC,
                mode: nil
            ),
            error: .namespaceUnavailable
        )
        defer { adapter.closeFile(creatorDescriptor) }
        try requireVoid(
            adapter.lock(
                fileDescriptor: creatorDescriptor,
                operation: LOCK_EX | LOCK_NB
            ),
            error: .captureAlreadyExists
        )
        guard let scanStart = monotonicClock() else {
            throw IOSForegroundVoiceCaptureSourceError.namespaceUnavailable
        }
        guard try directoryNames(
            descriptor: namespace.descriptor,
            startNanoseconds: scanStart
        ).isEmpty else {
            throw IOSForegroundVoiceCaptureSourceError.captureAlreadyExists
        }

        let intent = IOSForegroundVoiceCaptureCreationIntent(
            attemptID: attemptID,
            outputIntent: outputIntent,
            format: format,
            creationMilliseconds: creationMilliseconds
        )
        try requireVoid(
            adapter.setExtendedAttribute(
                fileDescriptor: namespace.descriptor,
                name: Self.creationIntentName,
                value: IOSForegroundVoiceCaptureSourceWireCodec.creationIntent(intent),
                flags: XATTR_CREATE
            ),
            error: .sourceConflict
        )
        try synchronize(namespace.descriptor)

        let hiddenName = IOSForegroundVoiceCaptureSourceWireCodec.hiddenName(
            attemptID: attemptID,
            format: format
        )
        let finalName = IOSForegroundVoiceCaptureSourceWireCodec.finalName(
            attemptID: attemptID,
            format: format
        )
        let fileDescriptor = try require(
            adapter.openAt(
                directoryDescriptor: namespace.descriptor,
                name: hiddenName,
                flags: O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode: mode_t(0o600)
            ),
            error: .sourceConflict
        )
        var fileTransferred = false
        defer {
            if !fileTransferred { adapter.closeFile(fileDescriptor) }
        }
        try requireVoid(
            adapter.lock(
                fileDescriptor: fileDescriptor,
                operation: LOCK_EX | LOCK_NB
            ),
            error: .sourceConflict
        )
        try configureProtectedFile(fileDescriptor)
        let status = try require(
            adapter.status(of: fileDescriptor),
            error: .sourceChanged
        )
        let identity = try makeIdentity(
            intent: intent,
            status: status
        )
        try validatePinnedFileStatus(status, expectedIdentity: identity)
        try setCreatedAttribute(
            fileDescriptor: fileDescriptor,
            name: Self.sourceMarkerName,
            value: Self.markerValue
        )
        try setCreatedAttribute(
            fileDescriptor: fileDescriptor,
            name: Self.identityName,
            value: IOSForegroundVoiceCaptureSourceWireCodec.identity(identity)
        )
        try setCreatedAttribute(
            fileDescriptor: fileDescriptor,
            name: Self.phaseName,
            value: IOSForegroundVoiceCaptureSourceWireCodec.phase(.active)
        )
        try synchronize(fileDescriptor)
        try requireVoid(
            adapter.publishExclusively(
                directoryDescriptor: namespace.descriptor,
                temporaryName: hiddenName,
                finalName: finalName
            ),
            error: .sourceConflict
        )
        try synchronize(namespace.descriptor)
        let handles = IOSForegroundVoiceCaptureSourceLease.BorrowedHandles(
            directoryDescriptor: namespace.descriptor,
            fileDescriptor: fileDescriptor
        )
        _ = try validateSource(
            handles: handles,
            expectedIdentity: identity,
            finalName: finalName,
            allowedPhases: [.active]
        )
        try requireVoid(
            adapter.removeExtendedAttribute(
                fileDescriptor: namespace.descriptor,
                name: Self.creationIntentName
            ),
            error: .synchronizationFailed
        )
        try synchronize(namespace.descriptor)

        fileTransferred = true
        namespaceTransferred = true
        return IOSForegroundVoiceCaptureSourceLease(
            fileSystem: self,
            recordingURL: namespace.URL.appendingPathComponent(
                finalName,
                isDirectory: false
            ),
            identity: identity,
            finalName: finalName,
            directoryDescriptor: namespace.descriptor,
            fileDescriptor: fileDescriptor
        )
    }

    private func performCompleteAfterRecorderClose(
        handles: IOSForegroundVoiceCaptureSourceLease.BorrowedHandles,
        identity: IOSForegroundVoiceCaptureIdentity,
        finalName: String
    ) throws -> CaptureSourceFinalizationFileSystemResult {
        let validated = try validateSource(
            handles: handles,
            expectedIdentity: identity,
            finalName: finalName,
            allowedPhases: [.finalizing]
        )
        guard validated.completion == nil else {
            throw IOSForegroundVoiceCaptureSourceError.sourceChanged
        }
        let statusBefore = validated.status
        guard statusBefore.st_size > 0 else {
            try transitionToDiscardingAndRemove(
                handles: handles,
                identity: identity,
                finalName: finalName
            )
            return .discarded(.empty)
        }
        let byteCount = Int64(statusBefore.st_size)
        guard byteCount
            < FoundationIOSPendingRecordingAudioFileSystem.maximumAudioByteCount else {
            try transitionToDiscardingAndRemove(
                handles: handles,
                identity: identity,
                finalName: finalName
            )
            return .discarded(.invalidMedia)
        }
        let duration: Int64
        do {
            duration = try mediaValidator.durationMilliseconds(
                forFileDescriptor: handles.fileDescriptor,
                byteCount: byteCount,
                format: identity.format,
                timeoutNanoseconds: Self.mediaValidationDeadlineNanoseconds
            )
        } catch IOSPendingRecordingAudioFileSystemError.mediaValidationTimedOut {
            throw IOSForegroundVoiceCaptureSourceError.mediaValidationTimedOut
        } catch IOSPendingRecordingAudioFileSystemError.operationTimedOut {
            throw IOSForegroundVoiceCaptureSourceError.mediaValidationTimedOut
        } catch IOSPendingRecordingAudioFileSystemError.dataProtectionUnavailable {
            throw IOSForegroundVoiceCaptureSourceError.dataProtectionUnavailable
        } catch IOSPendingRecordingAudioFileSystemError.mediaValidationFailed {
            try transitionToDiscardingAndRemove(
                handles: handles,
                identity: identity,
                finalName: finalName
            )
            return .discarded(.invalidMedia)
        } catch {
            throw IOSForegroundVoiceCaptureSourceError.mediaValidationFailed
        }
        let statusAfter = try require(
            adapter.status(of: handles.fileDescriptor),
            error: .sourceChanged
        )
        guard sameStableContent(statusBefore, statusAfter) else {
            throw IOSForegroundVoiceCaptureSourceError.sourceChanged
        }
        if duration < 300 {
            try transitionToDiscardingAndRemove(
                handles: handles,
                identity: identity,
                finalName: finalName
            )
            return .discarded(.tooShort)
        }
        if duration >= 300_000 {
            try transitionToDiscardingAndRemove(
                handles: handles,
                identity: identity,
                finalName: finalName
            )
            return .discarded(.maximumDurationReached)
        }
        guard duration <= Int64(UInt32.max),
              statusAfter.st_mtimespec.tv_nsec >= 0,
              statusAfter.st_mtimespec.tv_nsec < 1_000_000_000 else {
            throw IOSForegroundVoiceCaptureSourceError.mediaValidationFailed
        }
        let completion = IOSForegroundVoiceCaptureCompletion(
            durationMilliseconds: UInt32(duration),
            byteCount: UInt64(byteCount),
            modificationSeconds: Int64(statusAfter.st_mtimespec.tv_sec),
            modificationNanoseconds: UInt32(statusAfter.st_mtimespec.tv_nsec)
        )
        try setCreatedAttribute(
            fileDescriptor: handles.fileDescriptor,
            name: Self.completionName,
            value: IOSForegroundVoiceCaptureSourceWireCodec.completion(completion)
        )
        try synchronize(handles.fileDescriptor)
        try replacePhase(.completed, fileDescriptor: handles.fileDescriptor)
        _ = try validateSource(
            handles: handles,
            expectedIdentity: identity,
            finalName: finalName,
            allowedPhases: [.completed]
        )
        return .completed(completion)
    }

    private func transitionToDiscardingAndRemove(
        handles: IOSForegroundVoiceCaptureSourceLease.BorrowedHandles,
        identity: IOSForegroundVoiceCaptureIdentity,
        finalName: String
    ) throws {
        try replacePhase(.discarding, fileDescriptor: handles.fileDescriptor)
        _ = try validateSource(
            handles: handles,
            expectedIdentity: identity,
            finalName: finalName,
            allowedPhases: [.discarding]
        )
        try removePinnedSource(handles: handles, finalName: finalName)
    }

    private func removePinnedSource(
        handles: IOSForegroundVoiceCaptureSourceLease.BorrowedHandles,
        finalName: String,
        reconciliationStart: UInt64? = nil
    ) throws {
        try validateNamespaceDescriptorPath(handles.directoryDescriptor)
        let statusBefore = try require(
            adapter.status(of: handles.fileDescriptor),
            error: .cleanupUncertain
        )
        if statusBefore.st_nlink == 0 {
            if let reconciliationStart {
                try checkReconciliationDeadline(reconciliationStart)
            }
            do {
                try synchronize(handles.directoryDescriptor)
            } catch {
                throw IOSForegroundVoiceCaptureSourceError.cleanupUncertain
            }
            return
        }
        guard statusBefore.st_nlink == 1 else {
            throw IOSForegroundVoiceCaptureSourceError.cleanupUncertain
        }
        let pathStatus = try require(
            adapter.statusAt(
                directoryDescriptor: handles.directoryDescriptor,
                name: finalName,
                flags: AT_SYMLINK_NOFOLLOW
            ),
            error: .cleanupUncertain
        )
        guard samePhysicalIdentity(statusBefore, pathStatus) else {
            throw IOSForegroundVoiceCaptureSourceError.cleanupUncertain
        }
        if let reconciliationStart {
            try checkReconciliationDeadline(reconciliationStart)
        }
        let unlinkResult = adapter.unlinkAt(
            directoryDescriptor: handles.directoryDescriptor,
            name: finalName
        )
        let postUnlinkStatus = try require(
            adapter.status(of: handles.fileDescriptor),
            error: .cleanupUncertain
        )
        guard postUnlinkStatus.st_nlink == 0 else {
            _ = unlinkResult
            throw IOSForegroundVoiceCaptureSourceError.cleanupUncertain
        }
        do {
            try synchronize(handles.directoryDescriptor)
        } catch {
            throw IOSForegroundVoiceCaptureSourceError.cleanupUncertain
        }
    }

    private func validateSource(
        handles: IOSForegroundVoiceCaptureSourceLease.BorrowedHandles,
        expectedIdentity: IOSForegroundVoiceCaptureIdentity,
        finalName: String,
        allowedPhases: Set<IOSForegroundVoiceCaptureSourcePhase>
    ) throws -> CaptureSourceValidatedFile {
        try validateNamespaceDescriptorPath(handles.directoryDescriptor)
        let descriptorStatus = try require(
            adapter.status(of: handles.fileDescriptor),
            error: .sourceChanged
        )
        let pathStatus = try require(
            adapter.statusAt(
                directoryDescriptor: handles.directoryDescriptor,
                name: finalName,
                flags: AT_SYMLINK_NOFOLLOW
            ),
            error: .sourceChanged
        )
        try validatePinnedFileStatus(
            descriptorStatus,
            expectedIdentity: expectedIdentity
        )
        guard samePhysicalIdentity(descriptorStatus, pathStatus) else {
            throw IOSForegroundVoiceCaptureSourceError.sourceChanged
        }
        try validateProtectedAttributes(handles.fileDescriptor)
        guard try exactAttribute(
            handles.fileDescriptor,
            name: Self.sourceMarkerName,
            expected: Self.markerValue
        ) else {
            throw IOSForegroundVoiceCaptureSourceError.sourceChanged
        }
        let identityBytes = try attribute(
            handles.fileDescriptor,
            name: Self.identityName,
            maximumByteCount: 48
        )
        guard let identity = IOSForegroundVoiceCaptureSourceWireCodec
            .decodeIdentity(identityBytes),
              identity == expectedIdentity,
              IOSForegroundVoiceCaptureSourceWireCodec.finalName(
                attemptID: identity.attemptID,
                format: identity.format
              ) == finalName else {
            throw IOSForegroundVoiceCaptureSourceError.sourceChanged
        }
        let phaseBytes = try attribute(
            handles.fileDescriptor,
            name: Self.phaseName,
            maximumByteCount: 32
        )
        guard let phase = IOSForegroundVoiceCaptureSourceWireCodec
            .decodePhase(phaseBytes),
              allowedPhases.contains(phase) else {
            throw IOSForegroundVoiceCaptureSourceError.sourceChanged
        }
        let completion = try optionalCompletion(
            fileDescriptor: handles.fileDescriptor
        )
        switch phase {
        case .active:
            guard completion == nil else {
                throw IOSForegroundVoiceCaptureSourceError.sourceChanged
            }
        case .finalizing, .discarding:
            if let completion,
               !completionMatches(completion, status: descriptorStatus) {
                throw IOSForegroundVoiceCaptureSourceError.sourceChanged
            }
        case .completed, .preparingPending, .transferred:
            guard let completion,
                  completionMatches(completion, status: descriptorStatus) else {
                throw IOSForegroundVoiceCaptureSourceError.sourceChanged
            }
        }
        return CaptureSourceValidatedFile(
            status: descriptorStatus,
            identity: identity,
            phase: phase,
            completion: completion
        )
    }

    private func performReconcileAtLaunch() throws
        -> IOSForegroundVoiceCaptureRecoveryObservation {
        let namespace: CaptureSourceDirectoryHandle
        do {
            namespace = try openCaptureNamespace(createIfMissing: false)
        } catch CaptureNamespaceOpenResult.absent {
            return observation(.empty)
        }
        defer { adapter.closeFile(namespace.descriptor) }
        guard let start = monotonicClock() else {
            throw IOSForegroundVoiceCaptureSourceError.namespaceUnavailable
        }
        try checkReconciliationDeadline(start)
        let creatorDescriptor = try require(
            adapter.openAt(
                directoryDescriptor: namespace.descriptor,
                name: ".",
                flags: O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC,
                mode: nil
            ),
            error: .namespaceUnavailable
        )
        defer { adapter.closeFile(creatorDescriptor) }
        try checkReconciliationDeadline(start)
        switch adapter.lock(
            fileDescriptor: creatorDescriptor,
            operation: LOCK_EX | LOCK_NB
        ) {
        case .success:
            break
        case let .failure(errorCode) where errorCode == EWOULDBLOCK:
            return observation(.blockedUnknown)
        case .failure:
            return observation(.blockedUnknown)
        }
        try checkReconciliationDeadline(start)
        var names = try directoryNames(
            descriptor: namespace.descriptor,
            startNanoseconds: start
        )
        let examinedCount = names.count
        try checkReconciliationDeadline(start)
        if let intentBytes = try optionalAttribute(
            namespace.descriptor,
            name: Self.creationIntentName,
            maximumByteCount: 28
        ) {
            try checkReconciliationDeadline(start)
            guard let intent = IOSForegroundVoiceCaptureSourceWireCodec
                .decodeCreationIntent(intentBytes) else {
                return observation(.blockedUnknown, examined: examinedCount)
            }
            let hiddenName = IOSForegroundVoiceCaptureSourceWireCodec.hiddenName(
                attemptID: intent.attemptID,
                format: intent.format
            )
            let finalName = IOSForegroundVoiceCaptureSourceWireCodec.finalName(
                attemptID: intent.attemptID,
                format: intent.format
            )
            if names.isEmpty {
                try checkReconciliationDeadline(start)
                try removeCreationIntent(
                    namespace.descriptor,
                    reconciliationStart: start
                )
                return observation(.cleanupPerformed)
            }
            if names == [hiddenName] {
                try checkReconciliationDeadline(start)
                let size = try removeExactEmptyCreationResidue(
                    namespaceDescriptor: namespace.descriptor,
                    name: hiddenName,
                    reconciliationStart: start
                )
                try checkReconciliationDeadline(start)
                try removeCreationIntent(
                    namespace.descriptor,
                    reconciliationStart: start
                )
                return observation(
                    .cleanupPerformed,
                    examined: examinedCount,
                    removed: 1,
                    bytes: size
                )
            }
            if names == [finalName] {
                try checkReconciliationDeadline(start)
                let descriptor = try openLockedSource(
                    namespaceDescriptor: namespace.descriptor,
                    name: finalName
                )
                guard let descriptor else {
                    return observation(.blockedUnknown, examined: examinedCount)
                }
                defer { adapter.closeFile(descriptor) }
                try checkReconciliationDeadline(start)
                let expectedIdentity = try expectedIdentity(
                    descriptor: descriptor,
                    attemptID: intent.attemptID,
                    outputIntent: intent.outputIntent,
                    format: intent.format,
                    creationMilliseconds: intent.creationMilliseconds
                )
                _ = try validateSource(
                    handles: .init(
                        directoryDescriptor: namespace.descriptor,
                        fileDescriptor: descriptor
                    ),
                    expectedIdentity: expectedIdentity,
                    finalName: finalName,
                    allowedPhases: [.active]
                )
                try checkReconciliationDeadline(start)
                try removeCreationIntent(
                    namespace.descriptor,
                    reconciliationStart: start
                )
                names = [finalName]
            } else {
                return observation(.blockedUnknown, examined: examinedCount)
            }
        }
        guard names.count == 1,
              let parsed = IOSForegroundVoiceCaptureSourceWireCodec.parseFinalName(
                names[0]
              ) else {
            return names.isEmpty
                ? observation(.empty, examined: examinedCount)
                : observation(.blockedUnknown, examined: examinedCount)
        }
        try checkReconciliationDeadline(start)
        let descriptor = try openLockedSource(
            namespaceDescriptor: namespace.descriptor,
            name: names[0]
        )
        guard let descriptor else {
            return observation(.blockedUnknown, examined: examinedCount)
        }
        defer { adapter.closeFile(descriptor) }
        try checkReconciliationDeadline(start)
        let identityBytes = try attribute(
            descriptor,
            name: Self.identityName,
            maximumByteCount: 48
        )
        guard let identity = IOSForegroundVoiceCaptureSourceWireCodec
            .decodeIdentity(identityBytes),
              identity.attemptID == parsed.attemptID,
              identity.format == parsed.format else {
            return observation(.blockedUnknown, examined: examinedCount)
        }
        try checkReconciliationDeadline(start)
        let validated: CaptureSourceValidatedFile
        do {
            validated = try validateSource(
                handles: .init(
                    directoryDescriptor: namespace.descriptor,
                    fileDescriptor: descriptor
                ),
                expectedIdentity: identity,
                finalName: names[0],
                allowedPhases: Set(IOSForegroundVoiceCaptureSourcePhase.allCases)
            )
        } catch {
            return observation(.blockedUnknown, examined: examinedCount)
        }
        try checkReconciliationDeadline(start)
        switch validated.phase {
        case .active:
            if validated.status.st_size > 0 {
                return observation(.activeNeedsRecovery, examined: examinedCount)
            }
            if isAbandonedZeroByteSource(validated) {
                try checkReconciliationDeadline(start)
                try replacePhase(.discarding, fileDescriptor: descriptor)
                try checkReconciliationDeadline(start)
                try removeReconciledSource(
                    namespaceDescriptor: namespace.descriptor,
                    fileDescriptor: descriptor,
                    name: names[0],
                    reconciliationStart: start
                )
                return observation(
                    .cleanupPerformed,
                    examined: examinedCount,
                    removed: 1,
                    bytes: 0
                )
            }
            return observation(.emptyActiveNeedsDiscard, examined: examinedCount)
        case .finalizing:
            return observation(.finalizingNeedsRecovery, examined: examinedCount)
        case .completed:
            return observation(.completedNeedsPendingHandoff, examined: examinedCount)
        case .preparingPending:
            return observation(.preparingPendingNeedsRecovery, examined: examinedCount)
        case .discarding, .transferred:
            let byteCount = max(0, Int64(validated.status.st_size))
            guard byteCount <= Self.maximumRemovalByteCount else {
                return observation(.blockedUnknown, examined: examinedCount)
            }
            try checkReconciliationDeadline(start)
            try removeReconciledSource(
                namespaceDescriptor: namespace.descriptor,
                fileDescriptor: descriptor,
                name: names[0],
                reconciliationStart: start
            )
            return observation(
                .cleanupPerformed,
                examined: examinedCount,
                removed: 1,
                bytes: byteCount
            )
        }
    }

    private func openCaptureNamespace(
        createIfMissing: Bool
    ) throws -> CaptureSourceDirectoryHandle {
        guard applicationSupportDirectoryURL.isFileURL,
              !applicationSupportDirectoryURL.path.isEmpty,
              !applicationSupportDirectoryURL.path.utf8.contains(0) else {
            throw IOSForegroundVoiceCaptureSourceError.namespaceUnavailable
        }
        let rootDescriptor: Int32
        switch adapter.openPath(
            applicationSupportDirectoryURL.path,
            flags: O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC,
            mode: nil
        ) {
        case let .success(value):
            rootDescriptor = value
        case let .failure(errorCode)
            where !createIfMissing && errorCode == ENOENT:
            throw CaptureNamespaceOpenResult.absent
        case .failure:
            throw IOSForegroundVoiceCaptureSourceError.namespaceUnavailable
        }
        var currentDescriptor = rootDescriptor
        var currentURL = applicationSupportDirectoryURL
        var ownsCurrent = true
        defer {
            if ownsCurrent { adapter.closeFile(currentDescriptor) }
        }
        try validateDirectory(currentDescriptor, requireMode: false)
        for name in ["HoldType", "Recordings", "Capture"] {
            let isCapture = name == "Capture"
            let opened: (descriptor: Int32, created: Bool)
            do {
                opened = try openChildDirectory(
                    parentDescriptor: currentDescriptor,
                    name: name,
                    createIfMissing: createIfMissing
                )
            } catch CaptureNamespaceOpenResult.absent {
                throw CaptureNamespaceOpenResult.absent
            }
            adapter.closeFile(currentDescriptor)
            currentDescriptor = opened.descriptor
            currentURL.appendPathComponent(name, isDirectory: true)
            try validateDirectory(currentDescriptor, requireMode: true)
            if isCapture {
                if opened.created {
                    try configureCaptureNamespace(currentDescriptor)
                } else {
                    try validateCaptureNamespace(currentDescriptor)
                }
            }
        }
        try validateNamespaceDescriptorPath(currentDescriptor)
        ownsCurrent = false
        return CaptureSourceDirectoryHandle(
            descriptor: currentDescriptor,
            URL: currentURL
        )
    }

    private func openChildDirectory(
        parentDescriptor: Int32,
        name: String,
        createIfMissing: Bool
    ) throws -> (descriptor: Int32, created: Bool) {
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        switch adapter.openAt(
            directoryDescriptor: parentDescriptor,
            name: name,
            flags: flags,
            mode: nil
        ) {
        case let .success(descriptor):
            return (descriptor, false)
        case let .failure(errorCode) where errorCode == ENOENT && createIfMissing:
            var created = true
            switch adapter.makeDirectoryAt(
                directoryDescriptor: parentDescriptor,
                name: name,
                mode: mode_t(0o700)
            ) {
            case .success:
                try synchronize(parentDescriptor)
            case let .failure(mkdirError) where mkdirError == EEXIST:
                created = false
                break
            case .failure:
                throw IOSForegroundVoiceCaptureSourceError.namespaceUnavailable
            }
            let descriptor = try require(
                adapter.openAt(
                    directoryDescriptor: parentDescriptor,
                    name: name,
                    flags: flags,
                    mode: nil
                ),
                error: .namespaceUnavailable
            )
            return (descriptor, created)
        case let .failure(errorCode) where errorCode == ENOENT:
            throw CaptureNamespaceOpenResult.absent
        case .failure:
            throw IOSForegroundVoiceCaptureSourceError.namespaceUnavailable
        }
    }

    private func configureCaptureNamespace(_ descriptor: Int32) throws {
        try requireVoid(
            adapter.changeMode(fileDescriptor: descriptor, mode: mode_t(0o700)),
            error: .namespaceInvalid
        )
        try configureProtectedAttributes(descriptor)
        try setCreatedAttribute(
            fileDescriptor: descriptor,
            name: Self.namespaceMarkerName,
            value: Self.markerValue
        )
        try synchronize(descriptor)
        try validateCaptureNamespace(descriptor)
    }

    private func validateCaptureNamespace(_ descriptor: Int32) throws {
        try validateDirectory(descriptor, requireMode: true)
        try validateProtectedAttributes(descriptor)
        guard try exactAttribute(
            descriptor,
            name: Self.namespaceMarkerName,
            expected: Self.markerValue
        ) else {
            throw IOSForegroundVoiceCaptureSourceError.namespaceInvalid
        }
    }

    private func configureProtectedFile(_ descriptor: Int32) throws {
        try requireVoid(
            adapter.changeMode(fileDescriptor: descriptor, mode: mode_t(0o600)),
            error: .sourceChanged
        )
        try configureProtectedAttributes(descriptor)
        try validateProtectedAttributes(descriptor)
    }

    private func configureProtectedAttributes(_ descriptor: Int32) throws {
        try requireVoid(
            adapter.setProtectionClass(
                fileDescriptor: descriptor,
                protectionClass: FoundationIOSPendingRecordingAudioFileSystem
                    .completeProtectionClass
            ),
            error: .dataProtectionUnavailable
        )
        try setCreatedAttribute(
            fileDescriptor: descriptor,
            name: FoundationIOSPendingRecordingAudioFileSystem
                .backupExclusionAttributeName,
            value: FoundationIOSPendingRecordingAudioFileSystem
                .backupExclusionAttributeValue
        )
    }

    private func validateProtectedAttributes(_ descriptor: Int32) throws {
        let protection = try require(
            adapter.protectionClass(fileDescriptor: descriptor),
            error: .dataProtectionUnavailable
        )
        guard protection == FoundationIOSPendingRecordingAudioFileSystem
            .completeProtectionClass,
              try exactAttribute(
                descriptor,
                name: FoundationIOSPendingRecordingAudioFileSystem
                    .backupExclusionAttributeName,
                expected: FoundationIOSPendingRecordingAudioFileSystem
                    .backupExclusionAttributeValue
              ) else {
            throw IOSForegroundVoiceCaptureSourceError.dataProtectionUnavailable
        }
    }

    private func validateDirectory(
        _ descriptor: Int32,
        requireMode: Bool
    ) throws {
        let status = try require(
            adapter.status(of: descriptor),
            error: .namespaceInvalid
        )
        let userID = try require(
            adapter.effectiveUserID(),
            error: .namespaceInvalid
        )
        guard status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == userID,
              !requireMode || status.st_mode & mode_t(0o7777) == mode_t(0o700) else {
            throw IOSForegroundVoiceCaptureSourceError.namespaceInvalid
        }
    }

    private func validatePinnedFileStatus(
        _ status: stat,
        expectedIdentity: IOSForegroundVoiceCaptureIdentity
    ) throws {
        let userID = try require(
            adapter.effectiveUserID(),
            error: .sourceChanged
        )
        guard let physicalIdentity = statusIdentity(status),
              status.st_mode & S_IFMT == S_IFREG,
              status.st_mode & mode_t(0o7777) == mode_t(0o600),
              status.st_uid == userID,
              status.st_nlink == 1,
              physicalIdentity.0 == expectedIdentity.device,
              physicalIdentity.1 == expectedIdentity.inode,
              physicalIdentity.2 == expectedIdentity.generation else {
            throw IOSForegroundVoiceCaptureSourceError.sourceChanged
        }
    }

    private func makeIdentity(
        intent: IOSForegroundVoiceCaptureCreationIntent,
        status: stat
    ) throws -> IOSForegroundVoiceCaptureIdentity {
        guard let device = UInt64(exactly: status.st_dev),
              let inode = UInt64(exactly: status.st_ino) else {
            throw IOSForegroundVoiceCaptureSourceError.sourceChanged
        }
        return IOSForegroundVoiceCaptureIdentity(
            attemptID: intent.attemptID,
            outputIntent: intent.outputIntent,
            format: intent.format,
            creationMilliseconds: intent.creationMilliseconds,
            device: device,
            inode: inode,
            generation: UInt32(status.st_gen)
        )
    }

    private func expectedIdentity(
        descriptor: Int32,
        attemptID: UUID,
        outputIntent: DictationOutputIntent,
        format: IOSPendingRecordingAudioFormat,
        creationMilliseconds: UInt64
    ) throws -> IOSForegroundVoiceCaptureIdentity {
        let status = try require(
            adapter.status(of: descriptor),
            error: .sourceChanged
        )
        return try makeIdentity(
            intent: IOSForegroundVoiceCaptureCreationIntent(
                attemptID: attemptID,
                outputIntent: outputIntent,
                format: format,
                creationMilliseconds: creationMilliseconds
            ),
            status: status
        )
    }

    private func replacePhase(
        _ phase: IOSForegroundVoiceCaptureSourcePhase,
        fileDescriptor: Int32
    ) throws {
        try requireVoid(
            adapter.setExtendedAttribute(
                fileDescriptor: fileDescriptor,
                name: Self.phaseName,
                value: IOSForegroundVoiceCaptureSourceWireCodec.phase(phase),
                flags: XATTR_REPLACE
            ),
            error: .sourceChanged
        )
        try synchronize(fileDescriptor)
    }

    private func optionalCompletion(
        fileDescriptor: Int32
    ) throws -> IOSForegroundVoiceCaptureCompletion? {
        guard let bytes = try optionalAttribute(
            fileDescriptor,
            name: Self.completionName,
            maximumByteCount: 26
        ) else {
            return nil
        }
        guard let completion = IOSForegroundVoiceCaptureSourceWireCodec
            .decodeCompletion(bytes) else {
            throw IOSForegroundVoiceCaptureSourceError.sourceChanged
        }
        return completion
    }

    private func attribute(
        _ descriptor: Int32,
        name: String,
        maximumByteCount: Int
    ) throws -> [UInt8] {
        try require(
            adapter.extendedAttribute(
                fileDescriptor: descriptor,
                name: name,
                maximumByteCount: maximumByteCount
            ),
            error: .sourceChanged
        )
    }

    private func optionalAttribute(
        _ descriptor: Int32,
        name: String,
        maximumByteCount: Int
    ) throws -> [UInt8]? {
        switch adapter.extendedAttribute(
            fileDescriptor: descriptor,
            name: name,
            maximumByteCount: maximumByteCount
        ) {
        case let .success(value):
            return value
        case let .failure(errorCode) where errorCode == ENOATTR:
            return nil
        case .failure:
            throw IOSForegroundVoiceCaptureSourceError.sourceChanged
        }
    }

    private func exactAttribute(
        _ descriptor: Int32,
        name: String,
        expected: [UInt8]
    ) throws -> Bool {
        try attribute(
            descriptor,
            name: name,
            maximumByteCount: expected.count + 1
        ) == expected
    }

    private func setCreatedAttribute(
        fileDescriptor: Int32,
        name: String,
        value: [UInt8]
    ) throws {
        try requireVoid(
            adapter.setExtendedAttribute(
                fileDescriptor: fileDescriptor,
                name: name,
                value: value,
                flags: XATTR_CREATE
            ),
            error: .sourceChanged
        )
    }

    private func synchronize(_ descriptor: Int32) throws {
        try requireVoid(
            adapter.synchronize(fileDescriptor: descriptor),
            error: .synchronizationFailed
        )
    }

    private func currentCreationMilliseconds() throws -> UInt64 {
        let milliseconds = now().timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite,
              milliseconds >= 0,
              milliseconds <= Double(
                IOSForegroundVoiceCaptureSourceWireCodec.latestCreationMilliseconds
              ) else {
            throw IOSForegroundVoiceCaptureSourceError.invalidCreationTime
        }
        let value = UInt64(milliseconds.rounded(.towardZero))
        guard value <= IOSForegroundVoiceCaptureSourceWireCodec
            .latestCreationMilliseconds else {
            throw IOSForegroundVoiceCaptureSourceError.invalidCreationTime
        }
        return value
    }

    private func directoryNames(
        descriptor: Int32,
        startNanoseconds: UInt64
    ) throws -> [String] {
        let streamDescriptor = try require(
            adapter.openAt(
                directoryDescriptor: descriptor,
                name: ".",
                flags: O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC,
                mode: nil
            ),
            error: .namespaceUnavailable
        )
        let stream: UnsafeMutablePointer<DIR>
        switch adapter.openDirectoryStream(fileDescriptor: streamDescriptor) {
        case let .success(value):
            stream = value
        case .failure:
            adapter.closeFile(streamDescriptor)
            throw IOSForegroundVoiceCaptureSourceError.namespaceUnavailable
        }
        defer { adapter.closeDirectoryStream(stream) }
        var names: [String] = []
        var interruptedCount = 0
        while names.count < Self.maximumEntryCount {
            try checkReconciliationDeadline(startNanoseconds)
            switch adapter.nextDirectoryEntry(stream: stream) {
            case let .success(.name(name)?):
                interruptedCount = 0
                if name != ".", name != ".." { names.append(name) }
            case .success(.invalidName?):
                throw IOSForegroundVoiceCaptureSourceError.namespaceInvalid
            case .success(nil):
                return names.sorted()
            case let .failure(errorCode) where errorCode == EINTR:
                interruptedCount += 1
                guard interruptedCount <= 8 else {
                    throw IOSForegroundVoiceCaptureSourceError.namespaceUnavailable
                }
            case .failure:
                throw IOSForegroundVoiceCaptureSourceError.namespaceUnavailable
            }
        }
        return names.sorted()
    }

    private func checkReconciliationDeadline(_ start: UInt64) throws {
        guard let current = monotonicClock(),
              current >= start,
              current - start < Self.reconciliationDeadlineNanoseconds else {
            throw IOSForegroundVoiceCaptureSourceError.namespaceUnavailable
        }
    }

    private func removeCreationIntent(
        _ descriptor: Int32,
        reconciliationStart: UInt64? = nil
    ) throws {
        try validateNamespaceDescriptorPath(descriptor)
        if let reconciliationStart {
            try checkReconciliationDeadline(reconciliationStart)
        }
        try requireVoid(
            adapter.removeExtendedAttribute(
                fileDescriptor: descriptor,
                name: Self.creationIntentName
            ),
            error: .synchronizationFailed
        )
        try synchronize(descriptor)
    }

    private func removeExactEmptyCreationResidue(
        namespaceDescriptor: Int32,
        name: String,
        reconciliationStart: UInt64? = nil
    ) throws -> Int64 {
        try validateNamespaceDescriptorPath(namespaceDescriptor)
        let descriptor = try require(
            adapter.openAt(
                directoryDescriptor: namespaceDescriptor,
                name: name,
                flags: O_RDWR | O_NOFOLLOW | O_CLOEXEC,
                mode: nil
            ),
            error: .sourceChanged
        )
        defer { adapter.closeFile(descriptor) }
        try requireVoid(
            adapter.lock(fileDescriptor: descriptor, operation: LOCK_EX | LOCK_NB),
            error: .sourceChanged
        )
        let status = try require(adapter.status(of: descriptor), error: .sourceChanged)
        let userID = try require(adapter.effectiveUserID(), error: .sourceChanged)
        guard status.st_mode & S_IFMT == S_IFREG,
              status.st_mode & mode_t(0o7777) == mode_t(0o600),
              status.st_uid == userID,
              status.st_nlink == 1,
              status.st_size == 0 else {
            throw IOSForegroundVoiceCaptureSourceError.sourceChanged
        }
        let pathStatus = try require(
            adapter.statusAt(
                directoryDescriptor: namespaceDescriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            ),
            error: .sourceChanged
        )
        guard samePhysicalIdentity(status, pathStatus) else {
            throw IOSForegroundVoiceCaptureSourceError.sourceChanged
        }
        try removePinnedSource(
            handles: .init(
                directoryDescriptor: namespaceDescriptor,
                fileDescriptor: descriptor
            ),
            finalName: name,
            reconciliationStart: reconciliationStart
        )
        return 0
    }

    private func openLockedSource(
        namespaceDescriptor: Int32,
        name: String
    ) throws -> Int32? {
        let descriptor = try require(
            adapter.openAt(
                directoryDescriptor: namespaceDescriptor,
                name: name,
                flags: O_RDWR | O_NOFOLLOW | O_CLOEXEC,
                mode: nil
            ),
            error: .sourceChanged
        )
        switch adapter.lock(
            fileDescriptor: descriptor,
            operation: LOCK_EX | LOCK_NB
        ) {
        case .success:
            return descriptor
        case let .failure(errorCode) where errorCode == EWOULDBLOCK:
            adapter.closeFile(descriptor)
            return nil
        case .failure:
            adapter.closeFile(descriptor)
            throw IOSForegroundVoiceCaptureSourceError.sourceChanged
        }
    }

    private func validateNamespaceDescriptorPath(_ descriptor: Int32) throws {
        try validateDirectory(descriptor, requireMode: true)
        try validateProtectedAttributes(descriptor)
        guard try exactAttribute(
            descriptor,
            name: Self.namespaceMarkerName,
            expected: Self.markerValue
        ) else {
            throw IOSForegroundVoiceCaptureSourceError.namespaceInvalid
        }
        let descriptorStatus = try require(
            adapter.status(of: descriptor),
            error: .namespaceInvalid
        )
        let pathStatus = try require(
            adapter.statusAtPath(captureNamespaceURL.path),
            error: .namespaceInvalid
        )
        guard samePhysicalIdentity(descriptorStatus, pathStatus),
              pathStatus.st_mode & S_IFMT == S_IFDIR else {
            throw IOSForegroundVoiceCaptureSourceError.namespaceInvalid
        }
    }

    private func removeReconciledSource(
        namespaceDescriptor: Int32,
        fileDescriptor: Int32,
        name: String,
        reconciliationStart: UInt64
    ) throws {
        try removePinnedSource(
            handles: .init(
                directoryDescriptor: namespaceDescriptor,
                fileDescriptor: fileDescriptor
            ),
            finalName: name,
            reconciliationStart: reconciliationStart
        )
    }

    private func isAbandonedZeroByteSource(
        _ source: CaptureSourceValidatedFile
    ) -> Bool {
        guard source.status.st_size == 0,
              source.status.st_mtimespec.tv_sec >= 0,
              source.status.st_mtimespec.tv_nsec >= 0,
              source.status.st_mtimespec.tv_nsec < 1_000_000_000 else {
            return false
        }
        let nowMilliseconds = now().timeIntervalSince1970 * 1_000
        guard nowMilliseconds.isFinite,
              nowMilliseconds >= 3_600_000,
              nowMilliseconds <= Double(
                IOSForegroundVoiceCaptureSourceWireCodec.latestCreationMilliseconds
              ) else {
            return false
        }
        let current = UInt64(nowMilliseconds.rounded(.towardZero))
        guard current <= IOSForegroundVoiceCaptureSourceWireCodec
            .latestCreationMilliseconds else {
            return false
        }
        let modificationSeconds = UInt64(source.status.st_mtimespec.tv_sec)
        let secondsProduct = modificationSeconds.multipliedReportingOverflow(by: 1_000)
        guard !secondsProduct.overflow else { return false }
        let nanosecondMilliseconds = UInt64(
            max(0, source.status.st_mtimespec.tv_nsec)
        ) / 1_000_000
        let modification = secondsProduct.partialValue.addingReportingOverflow(
            nanosecondMilliseconds
        )
        guard !modification.overflow,
              current >= source.identity.creationMilliseconds,
              current - source.identity.creationMilliseconds >= 3_600_000,
              current >= modification.partialValue,
              current - modification.partialValue >= 3_600_000 else {
            return false
        }
        return true
    }

    private func sameStableContent(_ lhs: stat, _ rhs: stat) -> Bool {
        samePhysicalIdentity(lhs, rhs)
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
    }

    private func samePhysicalIdentity(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_gen == rhs.st_gen
    }

    private func statusIdentity(_ value: stat) -> (UInt64, UInt64, UInt32)? {
        guard let device = UInt64(exactly: value.st_dev),
              let inode = UInt64(exactly: value.st_ino) else {
            return nil
        }
        return (device, inode, UInt32(value.st_gen))
    }

    private func completionMatches(
        _ completion: IOSForegroundVoiceCaptureCompletion,
        status: stat
    ) -> Bool {
        status.st_size >= 0
            && status.st_mtimespec.tv_nsec >= 0
            && status.st_mtimespec.tv_nsec < 1_000_000_000
            && completion.byteCount > 0
            && completion.byteCount < UInt64(
                FoundationIOSPendingRecordingAudioFileSystem.maximumAudioByteCount
            )
            && completion.byteCount == UInt64(status.st_size)
            && completion.modificationSeconds == Int64(status.st_mtimespec.tv_sec)
            && completion.modificationNanoseconds == UInt32(
                status.st_mtimespec.tv_nsec
            )
            && completion.durationMilliseconds >= 300
            && completion.durationMilliseconds < 300_000
    }

    private func observation(
        _ status: IOSForegroundVoiceCaptureRecoveryStatus,
        examined: Int = 0,
        removed: Int = 0,
        bytes: Int64 = 0
    ) -> IOSForegroundVoiceCaptureRecoveryObservation {
        IOSForegroundVoiceCaptureRecoveryObservation(
            status: status,
            examinedEntryCount: examined,
            removedEntryCount: min(removed, Self.maximumRemovalCount),
            removedLogicalByteCount: min(bytes, Self.maximumRemovalByteCount)
        )
    }

    private func require<Value>(
        _ result: IOSPendingRecordingPOSIXResult<Value>,
        error: IOSForegroundVoiceCaptureSourceError
    ) throws -> Value {
        switch result {
        case let .success(value): return value
        case .failure: throw error
        }
    }

    private func requireVoid(
        _ result: IOSPendingRecordingPOSIXResult<Void>,
        error: IOSForegroundVoiceCaptureSourceError
    ) throws {
        _ = try require(result, error: error)
    }
}

private enum CaptureNamespaceOpenResult: Error {
    case absent
}

private func captureSourceMonotonicNanoseconds() -> UInt64? {
    var value = timespec()
    guard Darwin.clock_gettime(CLOCK_MONOTONIC, &value) == 0,
          value.tv_sec >= 0,
          value.tv_nsec >= 0 else {
        return nil
    }
    let seconds = UInt64(value.tv_sec).multipliedReportingOverflow(
        by: 1_000_000_000
    )
    guard !seconds.overflow else { return nil }
    let total = seconds.partialValue.addingReportingOverflow(UInt64(value.tv_nsec))
    return total.overflow ? nil : total.partialValue
}
