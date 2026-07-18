import Darwin

nonisolated enum OpenAIMultipartScratchPOSIXCallResult<Value> {
    case success(Value)
    case failure(Int32)
}

nonisolated protocol OpenAIMultipartScratchPOSIXAdapter {
    func openFile(atPath path: String, flags: Int32)
        -> OpenAIMultipartScratchPOSIXCallResult<Int32>
    func fileStatus(for fileDescriptor: Int32)
        -> OpenAIMultipartScratchPOSIXCallResult<stat>
    func effectiveUserID() -> OpenAIMultipartScratchPOSIXCallResult<uid_t>
    func openDirectoryStream(for fileDescriptor: Int32)
        -> OpenAIMultipartScratchPOSIXCallResult<UnsafeMutablePointer<DIR>>
    func nextDirectoryEntry(in stream: UnsafeMutablePointer<DIR>)
        -> OpenAIMultipartScratchPOSIXCallResult<OpenAIMultipartScratchDirectoryEntry?>
    func directoryDescriptor(for stream: UnsafeMutablePointer<DIR>)
        -> OpenAIMultipartScratchPOSIXCallResult<Int32>
    func openFile(
        relativeTo directoryDescriptor: Int32,
        named fileName: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Int32>
    func extendedAttribute(
        named name: String,
        on fileDescriptor: Int32,
        maximumByteCount: Int
    ) -> OpenAIMultipartScratchPOSIXCallResult<[UInt8]>
    func setExtendedAttribute(
        named name: String,
        value: [UInt8],
        on fileDescriptor: Int32,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Void>
    func lock(fileDescriptor: Int32, operation: Int32)
        -> OpenAIMultipartScratchPOSIXCallResult<Void>
    func pathStatus(
        relativeTo directoryDescriptor: Int32,
        named fileName: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<stat>
    func unlink(
        relativeTo directoryDescriptor: Int32,
        named fileName: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Void>
    func closeFile(_ fileDescriptor: Int32)
    func closeDirectoryStream(_ stream: UnsafeMutablePointer<DIR>)
}

nonisolated struct DarwinOpenAIMultipartScratchPOSIXAdapter:
    OpenAIMultipartScratchPOSIXAdapter {
    func openFile(
        atPath path: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Int32> {
        let result = path.withCString { Darwin.open($0, flags) }
        return result >= 0 ? .success(result) : .failure(errno)
    }

    func fileStatus(
        for fileDescriptor: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<stat> {
        var status = stat()
        return Darwin.fstat(fileDescriptor, &status) == 0
            ? .success(status)
            : .failure(errno)
    }

    func effectiveUserID() -> OpenAIMultipartScratchPOSIXCallResult<uid_t> {
        .success(Darwin.geteuid())
    }

    func openDirectoryStream(
        for fileDescriptor: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<UnsafeMutablePointer<DIR>> {
        guard let stream = Darwin.fdopendir(fileDescriptor) else {
            return .failure(errno)
        }
        return .success(stream)
    }

    func nextDirectoryEntry(
        in stream: UnsafeMutablePointer<DIR>
    ) -> OpenAIMultipartScratchPOSIXCallResult<OpenAIMultipartScratchDirectoryEntry?> {
        errno = 0
        guard let entry = Darwin.readdir(stream) else {
            return errno == 0 ? .success(nil) : .failure(errno)
        }
        let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: Int(entry.pointee.d_namlen) + 1
            ) { String(validatingCString: $0) }
        }
        return .success(name.map(OpenAIMultipartScratchDirectoryEntry.name) ?? .invalidName)
    }

    func directoryDescriptor(
        for stream: UnsafeMutablePointer<DIR>
    ) -> OpenAIMultipartScratchPOSIXCallResult<Int32> {
        let result = Darwin.dirfd(stream)
        return result >= 0 ? .success(result) : .failure(errno)
    }

    func openFile(
        relativeTo directoryDescriptor: Int32,
        named fileName: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Int32> {
        let result = fileName.withCString {
            Darwin.openat(directoryDescriptor, $0, flags)
        }
        return result >= 0 ? .success(result) : .failure(errno)
    }

    func extendedAttribute(
        named name: String,
        on fileDescriptor: Int32,
        maximumByteCount: Int
    ) -> OpenAIMultipartScratchPOSIXCallResult<[UInt8]> {
        var bytes = [UInt8](repeating: 0, count: maximumByteCount)
        let result = name.withCString { attributeName in
            bytes.withUnsafeMutableBytes { buffer in
                Darwin.fgetxattr(
                    fileDescriptor,
                    attributeName,
                    buffer.baseAddress,
                    buffer.count,
                    0,
                    0
                )
            }
        }
        guard result >= 0 else {
            return .failure(errno)
        }
        return .success(Array(bytes.prefix(result)))
    }

    func setExtendedAttribute(
        named name: String,
        value: [UInt8],
        on fileDescriptor: Int32,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Void> {
        let result = name.withCString { attributeName in
            value.withUnsafeBytes { bytes in
                Darwin.fsetxattr(
                    fileDescriptor,
                    attributeName,
                    bytes.baseAddress,
                    bytes.count,
                    0,
                    flags
                )
            }
        }
        return result == 0 ? .success(()) : .failure(errno)
    }

    func lock(
        fileDescriptor: Int32,
        operation: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Void> {
        flock(fileDescriptor, operation) == 0 ? .success(()) : .failure(errno)
    }

    func pathStatus(
        relativeTo directoryDescriptor: Int32,
        named fileName: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<stat> {
        var status = stat()
        let result = fileName.withCString {
            Darwin.fstatat(directoryDescriptor, $0, &status, flags)
        }
        return result == 0 ? .success(status) : .failure(errno)
    }

    func unlink(
        relativeTo directoryDescriptor: Int32,
        named fileName: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Void> {
        let result = fileName.withCString {
            Darwin.unlinkat(directoryDescriptor, $0, flags)
        }
        return result == 0 ? .success(()) : .failure(errno)
    }

    func closeFile(_ fileDescriptor: Int32) {
        Darwin.close(fileDescriptor)
    }

    func closeDirectoryStream(_ stream: UnsafeMutablePointer<DIR>) {
        Darwin.closedir(stream)
    }
}
