import Darwin
import Foundation
import HoldTypeDomain

nonisolated struct OpenAITranscriptionRequestBuilder: Sendable {
    static let defaultEndpointURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    static let maximumAudioByteCountExclusive: Int64 = 25_000_000
    static let maximumMetadataByteCount: Int64 = 1_048_576
    static let maximumAudioReadByteCount = 64 * 1024

    private let endpointURL: URL
    private let boundaryProvider: @Sendable () -> String
    private let scratchDirectoryURL: URL
    private let fileSystem: any OpenAITranscriptionMultipartFileSystem

    init(
        endpointURL: URL = Self.defaultEndpointURL,
        boundary: String? = nil,
        scratchDirectoryURL: URL? = nil,
        fileSystem: any OpenAITranscriptionMultipartFileSystem =
            POSIXOpenAITranscriptionMultipartFileSystem()
    ) {
        self.endpointURL = endpointURL
        boundaryProvider = if let boundary { { boundary } } else { { "Boundary-\(UUID().uuidString)" } }
        self.scratchDirectoryURL = scratchDirectoryURL
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("holdtype-openai-multipart", isDirectory: true)
        self.fileSystem = fileSystem
    }

    func makeCleanupRegistration() -> OpenAITranscriptionMultipartCleanupRegistration {
        OpenAITranscriptionMultipartCleanupRegistration()
    }

    func makePreparation(
        _ transcriptionRequest: AudioTranscriptionRequest,
        cleanupRegistration: OpenAITranscriptionMultipartCleanupRegistration
    ) async throws -> OpenAITranscriptionMultipartPreparation {
        try Task.checkCancellation()
        guard transcriptionRequest.audioFileURL.isFileURL else {
            throw OpenAITranscriptionRequestBuilderError.missingAudioFile(
                transcriptionRequest.audioFileURL
            )
        }

        let fileExtension = transcriptionRequest.audioFileURL.pathExtension.lowercased()
        guard let supportedFile = Self.supportedAudioFiles[fileExtension] else {
            throw OpenAITranscriptionRequestBuilderError.unsupportedAudioFileType(fileExtension)
        }
        let boundary = boundaryProvider()
        guard Self.isSafeBoundary(boundary) else {
            throw OpenAITranscriptionRequestBuilderError.invalidMultipartBoundary
        }

        let source: any OpenAITranscriptionAudioSource
        do {
            source = try fileSystem.openAudioSource(at: transcriptionRequest.audioFileURL)
        } catch OpenAITranscriptionMultipartFileSystemError.missingSource {
            throw OpenAITranscriptionRequestBuilderError.missingAudioFile(
                transcriptionRequest.audioFileURL
            )
        } catch {
            throw OpenAITranscriptionRequestBuilderError.unreadableAudioFile(
                transcriptionRequest.audioFileURL
            )
        }

        var scratch: (any OpenAITranscriptionScratchFile)?
        do {
            guard source.identity.byteCount > 0 else {
                throw OpenAITranscriptionRequestBuilderError.emptyAudioFile(
                    transcriptionRequest.audioFileURL
                )
            }
            guard source.identity.byteCount < Self.maximumAudioByteCountExclusive else {
                throw OpenAITranscriptionRequestBuilderError.audioFileTooLarge(
                    byteCount: source.identity.byteCount,
                    maximumExclusive: Self.maximumAudioByteCountExclusive
                )
            }

            let sizes = try validatedSizes(
                supportedFile: supportedFile,
                transcriptionRequest: transcriptionRequest,
                boundary: boundary,
                audioByteCount: source.identity.byteCount
            )
            try Task.checkCancellation()
            let multipartStrings = makeMultipartStrings(
                supportedFile: supportedFile,
                transcriptionRequest: transcriptionRequest,
                boundary: boundary
            )

            let bodyFileURL = scratchDirectoryURL.appendingPathComponent(
                "\(UUID().uuidString).multipart",
                isDirectory: false
            )
            scratch = try fileSystem.createScratchFile(at: bodyFileURL)
            let preparation = OpenAITranscriptionMultipartPreparation(
                endpointURL: endpointURL,
                boundary: boundary,
                sourceFileURL: transcriptionRequest.audioFileURL,
                source: source,
                scratch: try required(scratch),
                prefix: Data(multipartStrings.prefix.utf8),
                suffix: Data(multipartStrings.suffix.utf8),
                expectedBodyByteCount: sizes.bodyByteCount
            )
            cleanupRegistration.install {
                preparation.cleanup()
            }
            try Task.checkCancellation()
            return preparation
        } catch is CancellationError {
            source.close()
            scratch?.close()
            scratch?.unlinkIfOwned()
            throw CancellationError()
        } catch let error as OpenAITranscriptionRequestBuilderError {
            source.close()
            scratch?.close()
            scratch?.unlinkIfOwned()
            throw error
        } catch {
            source.close()
            scratch?.close()
            scratch?.unlinkIfOwned()
            throw OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
        }
    }

    private func makeMultipartStrings(
        supportedFile: SupportedAudioFile,
        transcriptionRequest: AudioTranscriptionRequest,
        boundary: String
    ) -> (prefix: String, suffix: String) {
        var prefix = ""
        prefix.appendFormField(name: "model", value: transcriptionRequest.model, boundary: boundary)
        prefix.appendFormField(name: "response_format", value: "json", boundary: boundary)
        if let languageCode = transcriptionRequest.languageCode {
            prefix.appendFormField(name: "language", value: languageCode, boundary: boundary)
        }
        if let prompt = transcriptionRequest.promptComposition.providerPrompt {
            prefix.appendFormField(name: "prompt", value: prompt, boundary: boundary)
        }
        prefix.appendFileFieldHeader(
            name: "file",
            fileName: supportedFile.controlledFileName,
            contentType: supportedFile.contentType,
            boundary: boundary
        )
        return (prefix, "\r\n--\(boundary)--\r\n")
    }

    private func validatedSizes(
        supportedFile: SupportedAudioFile,
        transcriptionRequest: AudioTranscriptionRequest,
        boundary: String,
        audioByteCount: Int64
    ) throws -> (metadataByteCount: Int64, bodyByteCount: Int64) {
        var metadata: Int64 = 0
        try addFormFieldSize(name: "model", value: transcriptionRequest.model, boundary: boundary, to: &metadata)
        try addFormFieldSize(name: "response_format", value: "json", boundary: boundary, to: &metadata)
        if let language = transcriptionRequest.languageCode {
            try addFormFieldSize(name: "language", value: language, boundary: boundary, to: &metadata)
        }
        if let prompt = transcriptionRequest.promptComposition.providerPrompt {
            try addFormFieldSize(name: "prompt", value: prompt, boundary: boundary, to: &metadata)
        }
        for value in [
            "--", boundary,
            "\r\nContent-Disposition: form-data; name=\"file\"; filename=\"",
            supportedFile.controlledFileName,
            "\"\r\nContent-Type: ", supportedFile.contentType,
            "\r\n\r\n\r\n--", boundary, "--\r\n",
        ] {
            try addUTF8Size(value, to: &metadata)
        }
        guard metadata <= Self.maximumMetadataByteCount else {
            throw OpenAITranscriptionRequestBuilderError.multipartMetadataTooLarge(
                byteCount: metadata,
                maximum: Self.maximumMetadataByteCount
            )
        }
        let body = metadata.addingReportingOverflow(audioByteCount)
        guard !body.overflow else {
            throw OpenAITranscriptionRequestBuilderError.multipartBodyTooLarge
        }
        return (metadata, body.partialValue)
    }

    private func addFormFieldSize(
        name: String,
        value: String,
        boundary: String,
        to count: inout Int64
    ) throws {
        for part in ["--", boundary, "\r\nContent-Disposition: form-data; name=\"", name, "\"\r\n\r\n", value, "\r\n"] {
            try addUTF8Size(part, to: &count)
        }
    }

    private func addUTF8Size(_ value: String, to count: inout Int64) throws {
        guard let valueCount = Int64(exactly: value.utf8.count) else {
            throw OpenAITranscriptionRequestBuilderError.multipartBodyTooLarge
        }
        let addition = count.addingReportingOverflow(valueCount)
        guard !addition.overflow else {
            throw OpenAITranscriptionRequestBuilderError.multipartBodyTooLarge
        }
        count = addition.partialValue
    }

    private static func isSafeBoundary(_ boundary: String) -> Bool {
        guard !boundary.isEmpty, boundary.utf8.count <= 70 else { return false }
        return boundary.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45
        }
    }

    private func required<T>(_ value: T?) throws -> T {
        guard let value else { throw OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable }
        return value
    }

    private static let supportedAudioFiles = [
        "m4a": SupportedAudioFile(controlledFileName: "recording.m4a", contentType: "audio/mp4"),
        "wav": SupportedAudioFile(controlledFileName: "recording.wav", contentType: "audio/wav"),
    ]
}

nonisolated final class OpenAITranscriptionMultipartCleanupRegistration: @unchecked Sendable {
    private let lock = NSLock()
    private var cleanup: (@Sendable () -> Void)?
    private var cleanupRequested = false
    private var cleanupScheduled = false
    private var cleanupCompleted = false

    func install(_ cleanup: @escaping @Sendable () -> Void) {
        let action = lock.withLock { () -> (@Sendable () -> Void)? in
            guard !cleanupCompleted, !cleanupScheduled else {
                return nil
            }
            self.cleanup = cleanup
            return takeCleanupIfReady()
        }
        if let action {
            schedule(action)
        }
    }

    func requestCleanup() {
        let action = lock.withLock { () -> (@Sendable () -> Void)? in
            cleanupRequested = true
            return takeCleanupIfReady()
        }
        if let action {
            schedule(action)
        }
    }

    var isCleanupCompleted: Bool {
        lock.withLock { cleanupCompleted }
    }

    private func takeCleanupIfReady() -> (@Sendable () -> Void)? {
        guard cleanupRequested,
              !cleanupScheduled,
              let cleanup else {
            return nil
        }
        self.cleanup = nil
        cleanupScheduled = true
        return cleanup
    }

    private func schedule(_ cleanup: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .utility).async { [self] in
            cleanup()
            lock.withLock {
                cleanupCompleted = true
            }
        }
    }
}

nonisolated struct OpenAITranscriptionPreparedMultipartUpload: Sendable {
    let request: URLRequest
    let body: any OpenAIFileUploadBody
}

nonisolated struct OpenAITranscriptionMultipartPreparation: Sendable {
    let bodyFileURL: URL
    private let endpointURL: URL
    private let boundary: String
    private let sourceFileURL: URL
    private let source: any OpenAITranscriptionAudioSource
    private let scratch: any OpenAITranscriptionScratchFile
    private let prefix: Data
    private let suffix: Data
    private let expectedBodyByteCount: Int64

    init(
        endpointURL: URL,
        boundary: String,
        sourceFileURL: URL,
        source: any OpenAITranscriptionAudioSource,
        scratch: any OpenAITranscriptionScratchFile,
        prefix: Data,
        suffix: Data,
        expectedBodyByteCount: Int64
    ) {
        self.endpointURL = endpointURL
        self.boundary = boundary
        self.sourceFileURL = sourceFileURL
        self.source = source
        self.scratch = scratch
        bodyFileURL = scratch.fileURL
        self.prefix = prefix
        self.suffix = suffix
        self.expectedBodyByteCount = expectedBodyByteCount
    }

    func prepareRequest() async throws -> OpenAITranscriptionPreparedMultipartUpload {
        do {
            try Task.checkCancellation()
            try scratch.writeAll(prefix)
            try Task.checkCancellation()
            var audioCount: Int64 = 0
            while audioCount < source.identity.byteCount {
                try Task.checkCancellation()
                let remaining = source.identity.byteCount - audioCount
                let requested = min(
                    OpenAITranscriptionRequestBuilder.maximumAudioReadByteCount,
                    Int(remaining)
                )
                let chunk = try source.read(upToCount: requested)
                try Task.checkCancellation()
                guard !chunk.isEmpty else {
                    throw OpenAITranscriptionMultipartFileSystemError.sourceChanged
                }
                let addition = audioCount.addingReportingOverflow(Int64(chunk.count))
                guard !addition.overflow, addition.partialValue <= source.identity.byteCount else {
                    throw OpenAITranscriptionMultipartFileSystemError.sourceChanged
                }
                audioCount = addition.partialValue
                try scratch.writeAll(chunk)
                try Task.checkCancellation()
                await Task.yield()
            }
            let trailingByte = try source.read(upToCount: 1)
            try Task.checkCancellation()
            guard trailingByte.isEmpty else {
                throw OpenAITranscriptionMultipartFileSystemError.sourceChanged
            }
            try source.validateUnchanged()
            try Task.checkCancellation()
            try scratch.writeAll(suffix)
            try Task.checkCancellation()
            try scratch.synchronizeAndValidate(expectedByteCount: expectedBodyByteCount)
            try Task.checkCancellation()
            try source.validateUnchanged()
            try Task.checkCancellation()
            let uploadBody = try scratch.pinFinalizedUploadArtifact(
                expectedByteCount: expectedBodyByteCount
            )
            try Task.checkCancellation()
            source.close()
            scratch.close()

            var request = URLRequest(url: endpointURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(
                "multipart/form-data; boundary=\(boundary)",
                forHTTPHeaderField: "Content-Type"
            )
            request.setValue(String(expectedBodyByteCount), forHTTPHeaderField: "Content-Length")
            try Task.checkCancellation()
            return OpenAITranscriptionPreparedMultipartUpload(
                request: request,
                body: uploadBody
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch OpenAITranscriptionMultipartFileSystemError.sourceChanged {
            throw OpenAITranscriptionRequestBuilderError.audioFileChanged(sourceFileURL)
        } catch OpenAITranscriptionMultipartFileSystemError.sourceReadFailed {
            throw OpenAITranscriptionRequestBuilderError.unreadableAudioFile(sourceFileURL)
        } catch let error as OpenAITranscriptionRequestBuilderError {
            throw error
        } catch {
            throw OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
        }
    }

    func cleanup() {
        source.close()
        scratch.close()
        scratch.unlinkIfOwned()
    }
}

nonisolated extension OpenAITranscriptionMultipartPreparation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "OpenAITranscriptionMultipartPreparation(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror {
        Mirror(
            self,
            children: [(label: String?, value: Any)](),
            displayStyle: .struct
        )
    }
}

public nonisolated enum OpenAITranscriptionRequestBuilderError:
    Error,
    Equatable,
    LocalizedError,
    Sendable {
    case missingAudioFile(URL)
    case emptyAudioFile(URL)
    case unsupportedAudioFileType(String)
    case unreadableAudioFile(URL)
    case audioFileChanged(URL)
    case audioFileTooLarge(byteCount: Int64, maximumExclusive: Int64)
    case multipartMetadataTooLarge(byteCount: Int64, maximum: Int64)
    case multipartBodyTooLarge
    case multipartBodyUnavailable
    case invalidMultipartBoundary
    case invalidCustomLanguageCode(String)

    public var errorDescription: String? {
        switch self {
        case .missingAudioFile: "The recording file is missing."
        case .emptyAudioFile: "The recording file is empty."
        case .unsupportedAudioFileType: "The recording format is not supported."
        case .unreadableAudioFile: "The recording file could not be read."
        case .audioFileChanged: "The recording changed while the request was being prepared."
        case .audioFileTooLarge: "The recording is too large to send."
        case .multipartMetadataTooLarge: "The transcription request settings are too large."
        case .multipartBodyTooLarge, .multipartBodyUnavailable, .invalidMultipartBoundary:
            "The transcription request could not be prepared."
        case .invalidCustomLanguageCode: "Use a two- or three-letter custom language code."
        }
    }
}

nonisolated extension OpenAITranscriptionRequestBuilderError:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { "OpenAITranscriptionRequestBuilderError(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [(label: String?, value: Any)](),
            displayStyle: .enum
        )
    }
}

nonisolated struct OpenAITranscriptionFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let byteCount: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
    let changeSeconds: Int64
    let changeNanoseconds: Int64
}

nonisolated enum OpenAITranscriptionMultipartFileSystemError: Error, Equatable, Sendable {
    case missingSource
    case invalidSource
    case sourceReadFailed
    case sourceChanged
    case scratchUnavailable
    case scratchWriteFailed
}

nonisolated protocol OpenAITranscriptionAudioSource: Sendable {
    var identity: OpenAITranscriptionFileIdentity { get }
    func read(upToCount count: Int) throws -> Data
    func validateUnchanged() throws
    func close()
}

nonisolated protocol OpenAITranscriptionScratchFile: Sendable {
    var fileURL: URL { get }
    func writeAll(_ data: Data) throws
    func synchronizeAndValidate(expectedByteCount: Int64) throws
    func pinFinalizedUploadArtifact(
        expectedByteCount: Int64
    ) throws -> any OpenAIFileUploadBody
    func close()
    func unlinkIfOwned()
}

nonisolated protocol OpenAITranscriptionMultipartFileSystem: Sendable {
    func openAudioSource(at fileURL: URL) throws -> any OpenAITranscriptionAudioSource
    func createScratchFile(at fileURL: URL) throws -> any OpenAITranscriptionScratchFile
}

nonisolated protocol OpenAITranscriptionPOSIXCalling: Sendable {
    func read(_ fileDescriptor: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int
    func write(_ fileDescriptor: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int
    func synchronize(_ fileDescriptor: Int32) -> Int32
    func pread(
        _ fileDescriptor: Int32,
        _ buffer: UnsafeMutableRawPointer,
        _ count: Int,
        _ offset: Int64
    ) -> Int
}

nonisolated extension OpenAITranscriptionPOSIXCalling {
    func pread(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int, _ offset: Int64) -> Int {
        Darwin.pread(fd, buffer, count, off_t(offset))
    }
}

nonisolated struct DarwinOpenAITranscriptionPOSIXCalls: OpenAITranscriptionPOSIXCalling {
    func read(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int { Darwin.read(fd, buffer, count) }
    func write(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int { Darwin.write(fd, buffer, count) }
    func synchronize(_ fd: Int32) -> Int32 { Darwin.fsync(fd) }
    func pread(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int, _ offset: Int64) -> Int {
        Darwin.pread(fd, buffer, count, off_t(offset))
    }
}

nonisolated struct POSIXOpenAITranscriptionMultipartFileSystem: OpenAITranscriptionMultipartFileSystem {
    private let calls: any OpenAITranscriptionPOSIXCalling

    init(calls: any OpenAITranscriptionPOSIXCalling = DarwinOpenAITranscriptionPOSIXCalls()) {
        self.calls = calls
    }

    func openAudioSource(at fileURL: URL) throws -> any OpenAITranscriptionAudioSource {
        try fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw OpenAITranscriptionMultipartFileSystemError.invalidSource }
            var pathStatus = stat()
            guard Darwin.lstat(path, &pathStatus) == 0 else {
                if errno == ENOENT { throw OpenAITranscriptionMultipartFileSystemError.missingSource }
                throw OpenAITranscriptionMultipartFileSystemError.invalidSource
            }
            guard isRegular(pathStatus), !isSymbolicLink(pathStatus) else {
                throw OpenAITranscriptionMultipartFileSystemError.invalidSource
            }
            let fd = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
            guard fd >= 0 else {
                if errno == ENOENT { throw OpenAITranscriptionMultipartFileSystemError.missingSource }
                throw OpenAITranscriptionMultipartFileSystemError.invalidSource
            }
            var descriptorStatus = stat()
            guard Darwin.fstat(fd, &descriptorStatus) == 0,
                  isRegular(descriptorStatus),
                  fileIdentity(pathStatus) == fileIdentity(descriptorStatus) else {
                Darwin.close(fd)
                throw OpenAITranscriptionMultipartFileSystemError.invalidSource
            }
            return POSIXOpenAITranscriptionAudioSource(
                fileURL: fileURL,
                fileDescriptor: fd,
                identity: fileIdentity(descriptorStatus),
                calls: calls
            )
        }
    }

    func createScratchFile(at fileURL: URL) throws -> any OpenAITranscriptionScratchFile {
        let directoryURL = fileURL.deletingLastPathComponent()
        try ensurePrivateDirectory(directoryURL)
        return try fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable }
            let fd = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable }
            var createdStatus = stat()
            guard Darwin.fstat(fd, &createdStatus) == 0,
                  isRegular(createdStatus),
                  createdStatus.st_uid == geteuid(),
                  createdStatus.st_nlink == 1,
                  createdStatus.st_size == 0 else {
                Darwin.close(fd)
                throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
            }
            let createdIdentity = fileIdentity(createdStatus)
            guard Darwin.fchmod(fd, 0o600) == 0 else {
                Darwin.close(fd)
                unlinkScratchIfMatching(fileURL, identity: createdIdentity)
                throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
            }
            var status = stat()
            guard Darwin.fstat(fd, &status) == 0,
                  isRegular(status),
                  status.st_uid == geteuid(),
                  status.st_mode & mode_t(0o777) == mode_t(0o600),
                  status.st_nlink == 1,
                  status.st_dev == createdStatus.st_dev,
                  status.st_ino == createdStatus.st_ino else {
                Darwin.close(fd)
                unlinkScratchIfMatching(fileURL, identity: createdIdentity)
                throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
            }
            do {
                try applyPrivateResourceValues(fileURL)
                var descriptorStatus = stat()
                var pathStatus = stat()
                guard Darwin.fstat(fd, &descriptorStatus) == 0,
                      Darwin.lstat(path, &pathStatus) == 0,
                      isPrivateScratch(descriptorStatus),
                      isPrivateScratch(pathStatus),
                      fileIdentity(pathStatus) == fileIdentity(descriptorStatus) else {
                    throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
                }
                return POSIXOpenAITranscriptionScratchFile(
                    fileURL: fileURL,
                    fileDescriptor: fd,
                    identity: fileIdentity(descriptorStatus),
                    calls: calls
                )
            } catch {
                Darwin.close(fd)
                unlinkScratchIfMatching(fileURL, identity: createdIdentity)
                throw error
            }
        }
    }

    private func ensurePrivateDirectory(_ directoryURL: URL) throws {
        try directoryURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable }
            if Darwin.mkdir(path, 0o700) != 0, errno != EEXIST {
                throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
            }
            var status = stat()
            guard Darwin.lstat(path, &status) == 0,
                  status.st_mode & S_IFMT == S_IFDIR,
                  status.st_uid == geteuid() else {
                throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
            }
            guard Darwin.chmod(path, 0o700) == 0 else {
                throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
            }
            try applyPrivateResourceValues(directoryURL)
            var protectedStatus = stat()
            guard Darwin.lstat(path, &protectedStatus) == 0,
                  protectedStatus.st_mode & S_IFMT == S_IFDIR,
                  protectedStatus.st_uid == geteuid(),
                  protectedStatus.st_mode & mode_t(0o777) == mode_t(0o700) else {
                throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
            }
        }
    }

    private func applyPrivateResourceValues(_ fileURL: URL) throws {
#if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path
        )
#endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = fileURL
        try mutableURL.setResourceValues(values)
    }

    private func unlinkScratchIfMatching(
        _ fileURL: URL,
        identity: OpenAITranscriptionFileIdentity
    ) {
        fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            var status = stat()
            guard Darwin.lstat(path, &status) == 0,
                  isRegular(status),
                  status.st_uid == geteuid(),
                  UInt64(status.st_dev) == identity.device,
                  UInt64(status.st_ino) == identity.inode else {
                return
            }
            var result: Int32
            repeat {
                result = Darwin.unlink(path)
            } while result != 0 && errno == EINTR
        }
    }
}

nonisolated private final class POSIXOpenAITranscriptionAudioSource:
    OpenAITranscriptionAudioSource,
    @unchecked Sendable {
    private struct State {
        var fileDescriptor: Int32?
        var activeOperationCount = 0
        var closeRequested = false
    }

    let identity: OpenAITranscriptionFileIdentity
    private let fileURL: URL
    private let calls: any OpenAITranscriptionPOSIXCalling
    private let lock = NSLock()
    private var state: State

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

    func read(upToCount count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        let fd = try beginDescriptorUse(
            failure: OpenAITranscriptionMultipartFileSystemError.sourceReadFailed
        )
        defer { finishDescriptorUse() }

        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { bytes -> Int in
            guard let base = bytes.baseAddress else { return 0 }
            while true {
                let result = calls.read(fd, base, count)
                if result < 0, errno == EINTR { continue }
                return result
            }
        }
        guard result >= 0, result <= count else {
            throw OpenAITranscriptionMultipartFileSystemError.sourceReadFailed
        }
        data.count = result
        return data
    }

    func validateUnchanged() throws {
        let fd = try beginDescriptorUse(
            failure: OpenAITranscriptionMultipartFileSystemError.sourceChanged
        )
        defer { finishDescriptorUse() }

        var descriptorStatus = stat()
        guard Darwin.fstat(fd, &descriptorStatus) == 0,
              fileIdentity(descriptorStatus) == identity else {
            throw OpenAITranscriptionMultipartFileSystemError.sourceChanged
        }
        try fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw OpenAITranscriptionMultipartFileSystemError.sourceChanged }
            var pathStatus = stat()
            guard Darwin.lstat(path, &pathStatus) == 0,
                  fileIdentity(pathStatus) == identity else {
                throw OpenAITranscriptionMultipartFileSystemError.sourceChanged
            }
        }
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

    private func beginDescriptorUse(failure: Error) throws -> Int32 {
        try lock.withLock {
            guard !state.closeRequested, let descriptor = state.fileDescriptor else {
                throw failure
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

    deinit { close() }
}

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
        close()
        unlinkIfOwned()
    }
}

nonisolated private struct SupportedAudioFile: Sendable { let controlledFileName: String; let contentType: String }

nonisolated private extension String {
    mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
    }
    mutating func appendFileFieldHeader(name: String, fileName: String, contentType: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
    }
}

nonisolated func isRegular(_ status: stat) -> Bool { status.st_mode & S_IFMT == S_IFREG }
nonisolated private func isSymbolicLink(_ status: stat) -> Bool { status.st_mode & S_IFMT == S_IFLNK }
nonisolated private func isPrivateScratch(_ status: stat) -> Bool {
    isRegular(status)
        && status.st_uid == geteuid()
        && status.st_mode & mode_t(0o777) == mode_t(0o600)
        && status.st_size == 0
        && status.st_nlink == 1
}
nonisolated func fileIdentity(_ status: stat) -> OpenAITranscriptionFileIdentity {
    OpenAITranscriptionFileIdentity(
        device: UInt64(status.st_dev),
        inode: UInt64(status.st_ino),
        byteCount: Int64(status.st_size),
        modificationSeconds: Int64(status.st_mtimespec.tv_sec),
        modificationNanoseconds: Int64(status.st_mtimespec.tv_nsec),
        changeSeconds: Int64(status.st_ctimespec.tv_sec),
        changeNanoseconds: Int64(status.st_ctimespec.tv_nsec)
    )
}
