import Darwin
import Foundation

struct IOSV1ForegroundVoiceAudioHandle: Sendable {
    let attemptID: UUID
    let directoryDescriptor: Int32
    let fileDescriptor: Int32
    let fileName: String
    let directoryDevice: UInt64
    let directoryInode: UInt64
    let fileDevice: UInt64
    let fileInode: UInt64
    let byteCount: Int64
}

protocol IOSV1ForegroundVoiceAudioFileSystem: Sendable {
    func openPendingAudio(
        attemptID: UUID,
        relativeIdentifier: String,
        expectedByteCount: Int64?
    ) throws -> IOSV1ForegroundVoiceAudioHandle?
    func read(
        _ handle: IOSV1ForegroundVoiceAudioHandle,
        atOffset offset: Int64,
        maximumByteCount: Int
    ) throws -> Data
    func unlink(_ handle: IOSV1ForegroundVoiceAudioHandle) throws
    func close(_ handle: IOSV1ForegroundVoiceAudioHandle)
}

struct IOSV1ForegroundVoiceDarwinAudioFileSystem:
    IOSV1ForegroundVoiceAudioFileSystem {
    let directoryURL: URL

    func openPendingAudio(
        attemptID: UUID,
        relativeIdentifier: String,
        expectedByteCount: Int64?
    ) throws -> IOSV1ForegroundVoiceAudioHandle? {
        let m4a = IOSVoiceStateStorageLocation.relativeAudioIdentifier(
            for: attemptID
        )
        let wav = IOSVoiceStateStorageLocation.relativeAudioIdentifier(
            for: attemptID,
            extension: "wav"
        )
        guard relativeIdentifier == m4a || relativeIdentifier == wav,
              expectedByteCount.map({ $0 > 0 }) != false else {
            throw IOSV1ForegroundVoicePersistenceError.audioInvalid
        }
        let fileName = String(relativeIdentifier.split(separator: "/").last!)
        let directory = Darwin.open(
            directoryURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard directory >= 0 else {
            if errno == ENOENT { return nil }
            throw openError(errno)
        }
        let file = fileName.withCString {
            Darwin.openat(
                directory,
                $0,
                O_RDONLY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard file >= 0 else {
            let code = errno
            Darwin.close(directory)
            if code == ENOENT { return nil }
            throw openError(code)
        }
        do {
            let handle = try makeHandle(
                attemptID: attemptID,
                directory: directory,
                file: file,
                fileName: fileName,
                expectedByteCount: expectedByteCount
            )
            try validate(handle)
            return handle
        } catch {
            Darwin.close(file)
            Darwin.close(directory)
            throw error
        }
    }

    func read(
        _ handle: IOSV1ForegroundVoiceAudioHandle,
        atOffset offset: Int64,
        maximumByteCount: Int
    ) throws -> Data {
        try validate(handle)
        let requested = min(
            Int64(maximumByteCount),
            handle.byteCount - offset
        )
        guard requested > 0 else { return Data() }
        var data = Data(count: Int(requested))
        var result: Int = -1
        for retry in 0...8 {
            result = data.withUnsafeMutableBytes { buffer in
                Darwin.pread(
                    handle.fileDescriptor,
                    buffer.baseAddress,
                    buffer.count,
                    off_t(offset)
                )
            }
            if result >= 0 { break }
            if errno != EINTR || retry == 8 { break }
        }
        guard result >= 0 else {
            throw IOSV1ForegroundVoicePersistenceError.audioInvalid
        }
        data.removeSubrange(result..<data.count)
        return data
    }

    func unlink(_ handle: IOSV1ForegroundVoiceAudioHandle) throws {
        try validate(handle)
        let result = handle.fileName.withCString {
            Darwin.unlinkat(handle.directoryDescriptor, $0, 0)
        }
        guard result == 0 else {
            throw IOSV1ForegroundVoicePersistenceError.cleanupUncertain
        }
        var status = stat()
        guard Darwin.fstat(handle.fileDescriptor, &status) == 0,
              status.st_nlink == 0,
              Darwin.fsync(handle.directoryDescriptor) == 0 else {
            throw IOSV1ForegroundVoicePersistenceError.cleanupUncertain
        }
    }

    func close(_ handle: IOSV1ForegroundVoiceAudioHandle) {
        Darwin.close(handle.fileDescriptor)
        Darwin.close(handle.directoryDescriptor)
    }

    private func makeHandle(
        attemptID: UUID,
        directory: Int32,
        file: Int32,
        fileName: String,
        expectedByteCount: Int64?
    ) throws -> IOSV1ForegroundVoiceAudioHandle {
        var directoryStatus = stat()
        var fileStatus = stat()
        guard Darwin.fstat(directory, &directoryStatus) == 0,
              Darwin.fstat(file, &fileStatus) == 0,
              directoryStatus.st_mode & S_IFMT == S_IFDIR,
              fileStatus.st_mode & S_IFMT == S_IFREG,
              fileStatus.st_mode & mode_t(0o777) == mode_t(0o600),
              fileStatus.st_nlink == 1,
              expectedByteCount.map({
                  Int64(fileStatus.st_size) == $0
              }) != false else {
            throw IOSV1ForegroundVoicePersistenceError.audioInvalid
        }
        return IOSV1ForegroundVoiceAudioHandle(
            attemptID: attemptID,
            directoryDescriptor: directory,
            fileDescriptor: file,
            fileName: fileName,
            directoryDevice: UInt64(directoryStatus.st_dev),
            directoryInode: UInt64(directoryStatus.st_ino),
            fileDevice: UInt64(fileStatus.st_dev),
            fileInode: UInt64(fileStatus.st_ino),
            byteCount: Int64(fileStatus.st_size)
        )
    }

    private func validate(
        _ handle: IOSV1ForegroundVoiceAudioHandle
    ) throws {
        var directoryStatus = stat()
        var directoryPathStatus = stat()
        var fileStatus = stat()
        var pathStatus = stat()
        guard Darwin.fstat(
                  handle.directoryDescriptor,
                  &directoryStatus
              ) == 0,
              Darwin.lstat(directoryURL.path, &directoryPathStatus) == 0,
              directoryStatus.st_mode & S_IFMT == S_IFDIR,
              UInt64(directoryStatus.st_dev) == handle.directoryDevice,
              UInt64(directoryStatus.st_ino) == handle.directoryInode,
              directoryStatus.st_dev == directoryPathStatus.st_dev,
              directoryStatus.st_ino == directoryPathStatus.st_ino,
              Darwin.fstat(handle.fileDescriptor, &fileStatus) == 0,
              handle.fileName.withCString({
                  Darwin.fstatat(
                      handle.directoryDescriptor,
                      $0,
                      &pathStatus,
                      AT_SYMLINK_NOFOLLOW
                  )
              }) == 0,
              fileStatus.st_mode & S_IFMT == S_IFREG,
              fileStatus.st_mode & mode_t(0o777) == mode_t(0o600),
              fileStatus.st_nlink == 1,
              UInt64(fileStatus.st_dev) == handle.fileDevice,
              UInt64(fileStatus.st_ino) == handle.fileInode,
              fileStatus.st_dev == pathStatus.st_dev,
              fileStatus.st_ino == pathStatus.st_ino,
              Int64(fileStatus.st_size) == handle.byteCount else {
            throw IOSV1ForegroundVoicePersistenceError.audioInvalid
        }
    }

    private func openError(_ code: Int32) -> Error {
        if code == EACCES || code == EPERM {
            return IOSV1ForegroundVoicePersistenceError
                .audioTemporarilyUnavailable
        }
        return IOSV1ForegroundVoicePersistenceError.audioInvalid
    }
}
