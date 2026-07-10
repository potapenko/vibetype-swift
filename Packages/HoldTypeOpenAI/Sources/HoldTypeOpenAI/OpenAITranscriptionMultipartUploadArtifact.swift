import Darwin
import Foundation

nonisolated protocol OpenAIFileUploadBody: Sendable {
    var byteCount: Int64 { get }

    func makeInputStream(
        startingAtOffset: Int64,
        failureHandler: @escaping @Sendable (OpenAITranscriptionRequestBuilderError) -> Void
    ) throws -> InputStream
}

nonisolated extension OpenAIFileUploadBody {
    func makeInputStream(
        failureHandler: @escaping @Sendable (OpenAITranscriptionRequestBuilderError) -> Void
    ) throws -> InputStream {
        try makeInputStream(startingAtOffset: 0, failureHandler: failureHandler)
    }
}

/// Owns the read descriptor for one finalized multipart body after its pathname has been removed.
nonisolated final class OpenAITranscriptionMultipartUploadArtifact:
    OpenAIFileUploadBody,
    @unchecked Sendable {
    static let maximumReadByteCount = 64 * 1024

    let byteCount: Int64

    private let fileDescriptor: Int32
    private let identity: OpenAITranscriptionFileIdentity
    private let calls: any OpenAITranscriptionPOSIXCalling

    init(
        fileDescriptor: Int32,
        identity: OpenAITranscriptionFileIdentity,
        calls: any OpenAITranscriptionPOSIXCalling
    ) {
        self.fileDescriptor = fileDescriptor
        self.identity = identity
        byteCount = identity.byteCount
        self.calls = calls
    }

    func makeInputStream(
        startingAtOffset: Int64,
        failureHandler: @escaping @Sendable (OpenAITranscriptionRequestBuilderError) -> Void
    ) throws -> InputStream {
        guard startingAtOffset >= 0, startingAtOffset <= byteCount else {
            throw OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
        }
        try validatePinnedDescriptor()

        return OpenAITranscriptionMultipartInputStream(
            artifact: self,
            startingAtOffset: startingAtOffset,
            failureHandler: failureHandler
        )
    }

    fileprivate func read(
        into buffer: UnsafeMutableRawPointer,
        maximumCount: Int,
        offset: Int64
    ) throws -> Int {
        guard maximumCount > 0,
              offset >= 0,
              offset < byteCount else {
            return 0
        }

        let remaining = byteCount - offset
        let requestedCount = min(
            maximumCount,
            Self.maximumReadByteCount,
            Int(remaining)
        )
        try validatePinnedDescriptor()
        while true {
            let result = calls.pread(fileDescriptor, buffer, requestedCount, offset)
            if result < 0, errno == EINTR {
                continue
            }
            guard result > 0, result <= requestedCount else {
                throw OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
            }
            try validatePinnedDescriptor()
            return result
        }
    }

    private func validatePinnedDescriptor() throws {
        var descriptorStatus = stat()
        guard Darwin.fstat(fileDescriptor, &descriptorStatus) == 0 else {
            throw OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
        }
        let currentIdentity = fileIdentity(descriptorStatus)
        guard currentIdentity == identity,
              isRegular(descriptorStatus),
              descriptorStatus.st_uid == geteuid(),
              descriptorStatus.st_mode & mode_t(0o777) == mode_t(0o600),
              descriptorStatus.st_nlink == 0 else {
            throw OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
        }
    }

    deinit {
        Darwin.close(fileDescriptor)
    }
}

nonisolated final class OpenAITranscriptionMultipartInputStream:
    InputStream,
    StreamDelegate,
    @unchecked Sendable {
    private struct State {
        var status: Stream.Status = .notOpen
        var error: Error?
        var offset: Int64 = 0
        var didReportFailure = false
    }

    private enum ReadCommit {
        case committed(Stream.Event)
        case closed
        case failed
    }

    private let artifact: OpenAITranscriptionMultipartUploadArtifact
    private let startingAtOffset: Int64
    private let failureHandler: @Sendable (OpenAITranscriptionRequestBuilderError) -> Void
    private let lock = NSLock()
    private let readLock = NSLock()
    private var state = State()
    private weak var storedDelegate: (any StreamDelegate)?

    init(
        artifact: OpenAITranscriptionMultipartUploadArtifact,
        startingAtOffset: Int64,
        failureHandler: @escaping @Sendable (OpenAITranscriptionRequestBuilderError) -> Void
    ) {
        self.artifact = artifact
        self.startingAtOffset = startingAtOffset
        self.failureHandler = failureHandler
        super.init(data: Data())
        state.offset = startingAtOffset
    }

    override var delegate: (any StreamDelegate)? {
        get { lock.withLock { storedDelegate ?? self } }
        set { lock.withLock { storedDelegate = newValue } }
    }

    override func open() {
        let events = lock.withLock { () -> [Stream.Event] in
            guard state.status == .notOpen else {
                return []
            }
            state.status = startingAtOffset == artifact.byteCount ? .atEnd : .open
            return startingAtOffset == artifact.byteCount
                ? [.openCompleted, .endEncountered]
                : [.openCompleted, .hasBytesAvailable]
        }
        emit(events)
    }

    override func close() {
        lock.withLock {
            state.status = .closed
        }
    }

    override func read(
        _ buffer: UnsafeMutablePointer<UInt8>,
        maxLength len: Int
    ) -> Int {
        readLock.withLock {
            readSerially(buffer, maxLength: len)
        }
    }

    private func readSerially(
        _ buffer: UnsafeMutablePointer<UInt8>,
        maxLength len: Int
    ) -> Int {
        guard len > 0 else {
            return 0
        }

        let offset = lock.withLock { () -> Int64? in
            guard state.status == .open else {
                return nil
            }
            return state.offset
        }
        guard let offset else {
            return streamStatus == .atEnd ? 0 : -1
        }

        do {
            let count = try artifact.read(
                into: buffer,
                maximumCount: len,
                offset: offset
            )
            let commit = lock.withLock { () -> ReadCommit in
                guard state.status == .open, state.offset == offset else {
                    return state.status == .error ? .failed : .closed
                }
                state.offset += Int64(count)
                if state.offset == artifact.byteCount {
                    state.status = .atEnd
                    return .committed(.endEncountered)
                }
                return .committed(.hasBytesAvailable)
            }
            switch commit {
            case .committed(let event):
                emit([event])
                return count
            case .closed:
                return 0
            case .failed:
                return -1
            }
        } catch {
            return reportFailure(.multipartBodyUnavailable, expectedOffset: offset)
                ? -1
                : 0
        }
    }

    override func getBuffer(
        _ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
        length len: UnsafeMutablePointer<Int>
    ) -> Bool {
        buffer.pointee = nil
        len.pointee = 0
        return false
    }

    override var hasBytesAvailable: Bool {
        lock.withLock {
            state.status == .open && state.offset < artifact.byteCount
        }
    }

    override var streamStatus: Stream.Status {
        lock.withLock { state.status }
    }

    override var streamError: (any Error)? {
        lock.withLock { state.error }
    }

    override func property(forKey key: Stream.PropertyKey) -> Any? {
        nil
    }

    override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
        false
    }

    override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}

    override func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {}

    private func reportFailure(
        _ error: OpenAITranscriptionRequestBuilderError,
        expectedOffset: Int64
    ) -> Bool {
        let shouldReport = lock.withLock { () -> Bool in
            guard state.status == .open, state.offset == expectedOffset else {
                return false
            }
            state.status = .error
            state.error = error
            guard !state.didReportFailure else {
                return false
            }
            state.didReportFailure = true
            return true
        }
        if shouldReport {
            failureHandler(error)
            emit([.errorOccurred])
        }
        return shouldReport
    }

    private func emit(_ events: [Stream.Event]) {
        guard !events.isEmpty else {
            return
        }
        let delegate = self.delegate
        for event in events {
            delegate?.stream?(self, handle: event)
        }
    }
}
