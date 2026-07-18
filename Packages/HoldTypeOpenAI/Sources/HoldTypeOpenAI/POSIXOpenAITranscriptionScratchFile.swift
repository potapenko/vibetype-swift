import Darwin
import Foundation

nonisolated private final class POSIXOpenAITranscriptionScratchFile:
    OpenAITranscriptionScratchFile,
    @unchecked Sendable {
    private struct State {
        var fileDescriptor: Int32?
        var activeOperationCount = 0
        var closeRequested = false
    }

    private enum UnlinkState: Equatable {
        case available
        case inProgress
        case complete
    }

    let fileURL: URL
    private let identity: OpenAITranscriptionFileIdentity
    private let calls: any OpenAITranscriptionPOSIXCalling
    private let lock = NSLock()
    private var state: State
    private var unlinkState = UnlinkState.available

    init(
        fileURL: URL,
        fileDescriptor: Int32,
        identity: OpenAITranscriptionFileIdentity,
        calls: any OpenAITranscriptionPOSIXCalling
    ) {
        self.fileURL = fileURL
        self.identity = identity
        self.calls = calls
        state = State(fileDescriptor: fileDescriptor)
    }

    func writeAll(_ data: Data) throws {
        let fd = try beginDescriptorUse()
        defer { finishDescriptorUse() }

        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = calls.write(fd, base.advanced(by: offset), bytes.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0, written <= bytes.count - offset else {
                    throw OpenAITranscriptionMultipartFileSystemError.scratchWriteFailed
                }
                offset += written
            }
        }
    }

    func synchronizeAndValidate(expectedByteCount: Int64) throws {
        let fd = try beginDescriptorUse()
        defer { finishDescriptorUse() }

        while calls.synchronize(fd) != 0 {
            if errno == EINTR { continue }
            throw OpenAITranscriptionMultipartFileSystemError.scratchWriteFailed
        }
        try Task.checkCancellation()
        try validateWriterAndPath(fd: fd, expectedByteCount: expectedByteCount)
        try Task.checkCancellation()
    }

    func pinFinalizedUploadArtifact(
        expectedByteCount: Int64
    ) throws -> any OpenAIFileUploadBody {
        guard claimUnlink() else {
            throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
        }

        var shouldRestoreUnlink = true
        var readDescriptor: Int32 = -1
        defer {
            if readDescriptor >= 0 { Darwin.close(readDescriptor) }
            if shouldRestoreUnlink { finishUnlink(completed: false) }
        }

        let writerDescriptor = try beginDescriptorUse()
        defer { finishDescriptorUse() }
        try Task.checkCancellation()
        try validateWriterAndPath(
            fd: writerDescriptor,
            expectedByteCount: expectedByteCount
        )
        try Task.checkCancellation()

        readDescriptor = try fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
            }
            let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
            guard descriptor >= 0 else {
                throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
            }
            return descriptor
        }
        try Task.checkCancellation()

        var writerStatus = stat()
        var readerStatus = stat()
        guard Darwin.fstat(writerDescriptor, &writerStatus) == 0,
              Darwin.fstat(readDescriptor, &readerStatus) == 0,
              matchesOwnedScratch(writerStatus, expectedByteCount: expectedByteCount),
              matchesOwnedScratch(readerStatus, expectedByteCount: expectedByteCount),
              sameFile(writerStatus, readerStatus) else {
            throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
        }
        try Task.checkCancellation()

        try fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
            }
            var pathStatus = stat()
            guard Darwin.lstat(path, &pathStatus) == 0,
                  matchesOwnedScratch(pathStatus, expectedByteCount: expectedByteCount),
                  sameFile(writerStatus, pathStatus),
                  sameFile(readerStatus, pathStatus) else {
                throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
            }
            try Task.checkCancellation()

            var unlinkResult: Int32
            repeat {
                unlinkResult = Darwin.unlink(path)
            } while unlinkResult != 0 && errno == EINTR
            guard unlinkResult == 0 else {
                throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
            }
        }

        finishUnlink(completed: true)
        shouldRestoreUnlink = false
        try Task.checkCancellation()

        var pinnedStatus = stat()
        guard Darwin.fstat(readDescriptor, &pinnedStatus) == 0,
              matchesOwnedScratch(
                  pinnedStatus,
                  expectedByteCount: expectedByteCount,
                  expectedLinkCount: 0
              ),
              sameFile(readerStatus, pinnedStatus) else {
            throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
        }
        try Task.checkCancellation()

        let artifact = OpenAITranscriptionMultipartUploadArtifact(
            fileDescriptor: readDescriptor,
            identity: fileIdentity(pinnedStatus),
            calls: calls
        )
        readDescriptor = -1
        return artifact
    }

    func close() {
        let descriptor = lock.withLock { () -> Int32? in
            state.closeRequested = true
            guard state.activeOperationCount == 0 else { return nil }
            let descriptor = state.fileDescriptor
            state.fileDescriptor = nil
            return descriptor
        }
        if let descriptor { Darwin.close(descriptor) }
    }

    func unlinkIfOwned() {
        guard claimUnlink() else { return }
        var completed = false
        fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            var status = stat()
            var statusResult: Int32
            repeat {
                statusResult = Darwin.lstat(path, &status)
            } while statusResult != 0 && errno == EINTR
            guard statusResult == 0 else {
                completed = errno == ENOENT
                return
            }
            guard isRegular(status),
                  UInt64(status.st_dev) == identity.device,
                  UInt64(status.st_ino) == identity.inode else {
                completed = true
                return
            }
            var unlinkResult: Int32
            repeat {
                unlinkResult = Darwin.unlink(path)
            } while unlinkResult != 0 && errno == EINTR
            completed = unlinkResult == 0 || errno == ENOENT
        }
        finishUnlink(completed: completed)
    }

    private func beginDescriptorUse() throws -> Int32 {
        try lock.withLock {
            guard !state.closeRequested, let descriptor = state.fileDescriptor else {
                throw OpenAITranscriptionMultipartFileSystemError.scratchWriteFailed
            }
            state.activeOperationCount += 1
            return descriptor
        }
    }

    private func finishDescriptorUse() {
        let descriptor = lock.withLock { () -> Int32? in
            state.activeOperationCount -= 1
            guard state.activeOperationCount == 0, state.closeRequested else { return nil }
            let descriptor = state.fileDescriptor
            state.fileDescriptor = nil
            return descriptor
        }
        if let descriptor { Darwin.close(descriptor) }
    }

    private func validateWriterAndPath(
        fd: Int32,
        expectedByteCount: Int64
    ) throws {
        var descriptorStatus = stat()
        guard Darwin.fstat(fd, &descriptorStatus) == 0,
              matchesOwnedScratch(descriptorStatus, expectedByteCount: expectedByteCount) else {
            throw OpenAITranscriptionMultipartFileSystemError.scratchWriteFailed
        }
        try fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                throw OpenAITranscriptionMultipartFileSystemError.scratchWriteFailed
            }
            var pathStatus = stat()
            guard Darwin.lstat(path, &pathStatus) == 0,
                  matchesOwnedScratch(pathStatus, expectedByteCount: expectedByteCount),
                  sameFile(descriptorStatus, pathStatus) else {
                throw OpenAITranscriptionMultipartFileSystemError.scratchWriteFailed
            }
        }
    }

    private func claimUnlink() -> Bool {
        lock.withLock {
            guard unlinkState == .available else { return false }
            unlinkState = .inProgress
            return true
        }
    }

    private func finishUnlink(completed: Bool) {
        lock.withLock {
            unlinkState = completed ? .complete : .available
        }
    }

    private func matchesOwnedScratch(
        _ status: stat,
        expectedByteCount: Int64,
        expectedLinkCount: UInt16 = 1
    ) -> Bool {
        isRegular(status)
            && status.st_uid == geteuid()
            && status.st_mode & mode_t(0o777) == mode_t(0o600)
            && Int64(status.st_size) == expectedByteCount
            && status.st_nlink == expectedLinkCount
    }

    private func sameFile(_ left: stat, _ right: stat) -> Bool {
        left.st_dev == right.st_dev && left.st_ino == right.st_ino
    }

    deinit {
        unlinkIfOwned()
        close()
    }
}

nonisolated func makePOSIXOpenAITranscriptionScratchFile(
    fileURL: URL,
    fileDescriptor: Int32,
    identity: OpenAITranscriptionFileIdentity,
    calls: any OpenAITranscriptionPOSIXCalling
) -> any OpenAITranscriptionScratchFile {
    POSIXOpenAITranscriptionScratchFile(
        fileURL: fileURL,
        fileDescriptor: fileDescriptor,
        identity: identity,
        calls: calls
    )
}
