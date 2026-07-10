import Darwin
import Foundation

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

nonisolated enum OpenAIMultipartScratchNamespace {
    static let directoryName = "holdtype-openai-multipart"
    static let v1Prefix = "htmp-v1-"
    static let fileExtension = ".multipart"
    static let markerName = "com.holdtype.openai.multipart-scratch"
    static let markerValue: [UInt8] = [0x76, 0x31]

    static var defaultDirectoryURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
    }

    static func v1FileName(for identifier: UUID) -> String {
        v1Prefix + identifier.uuidString.lowercased() + fileExtension
    }

    static func legacyFileName(for identifier: UUID) -> String {
        identifier.uuidString.uppercased() + fileExtension
    }

    static func identifier(inV1FileName fileName: String) -> UUID? {
        guard fileName.hasPrefix(v1Prefix),
              fileName.hasSuffix(fileExtension) else {
            return nil
        }
        let start = fileName.index(fileName.startIndex, offsetBy: v1Prefix.count)
        let end = fileName.index(fileName.endIndex, offsetBy: -fileExtension.count)
        let value = String(fileName[start..<end])
        guard let identifier = UUID(uuidString: value),
              value == identifier.uuidString.lowercased(),
              fileName == v1FileName(for: identifier) else {
            return nil
        }
        return identifier
    }

    static func identifier(inLegacyFileName fileName: String) -> UUID? {
        guard fileName.hasSuffix(fileExtension) else {
            return nil
        }
        let end = fileName.index(fileName.endIndex, offsetBy: -fileExtension.count)
        let value = String(fileName[..<end])
        guard let identifier = UUID(uuidString: value),
              value == identifier.uuidString.uppercased(),
              fileName == legacyFileName(for: identifier) else {
            return nil
        }
        return identifier
    }

    static func installMarker(on fileDescriptor: Int32) -> Bool {
        let adapter = DarwinOpenAIMultipartScratchPOSIXAdapter()
        return markerIsInstalled(
            on: fileDescriptor,
            adapter: adapter,
            shouldStartOperation: { true }
        )
    }

    static func hasExactMarker(on fileDescriptor: Int32) -> Bool {
        let adapter = DarwinOpenAIMultipartScratchPOSIXAdapter()
        return markerIsExact(
            on: fileDescriptor,
            adapter: adapter,
            shouldStartOperation: { true }
        )
    }
}

public nonisolated enum OpenAIProviderStartupMaintenance {
    private static let scheduler = OpenAIProviderStartupMaintenanceScheduler()

    public static func schedule() {
        scheduler.schedule {
            _ = OpenAIMultipartScratchScavenger().run()
        }
    }
}

nonisolated final class OpenAIProviderStartupMaintenanceScheduler:
    @unchecked Sendable {
    typealias Dispatch = @Sendable (@escaping @Sendable () -> Void) -> Void

    private let lock = NSLock()
    private let dispatch: Dispatch
    private var didSchedule = false

    init(
        dispatch: @escaping Dispatch = { operation in
            DispatchQueue.global(qos: .utility).async(execute: operation)
        }
    ) {
        self.dispatch = dispatch
    }

    @discardableResult
    func schedule(_ operation: @escaping @Sendable () -> Void) -> Bool {
        let shouldSchedule = lock.withLock { () -> Bool in
            guard !didSchedule else {
                return false
            }
            didSchedule = true
            return true
        }
        guard shouldSchedule else {
            return false
        }
        dispatch(operation)
        return true
    }
}

nonisolated struct OpenAIMultipartScratchTimestamp:
    Comparable,
    Equatable,
    Sendable {
    let seconds: Int64
    let nanoseconds: Int64

    static func < (
        lhs: OpenAIMultipartScratchTimestamp,
        rhs: OpenAIMultipartScratchTimestamp
    ) -> Bool {
        lhs.seconds < rhs.seconds
            || (lhs.seconds == rhs.seconds && lhs.nanoseconds < rhs.nanoseconds)
    }

    func isAtLeast(
        _ ageInSeconds: Int64,
        before reference: OpenAIMultipartScratchTimestamp
    ) -> Bool {
        guard self <= reference else {
            return false
        }
        let cutoff = reference.seconds.subtractingReportingOverflow(ageInSeconds)
        guard !cutoff.overflow else {
            return false
        }
        return self <= OpenAIMultipartScratchTimestamp(
            seconds: cutoff.partialValue,
            nanoseconds: reference.nanoseconds
        )
    }
}

nonisolated enum OpenAIMultipartScratchKind: Equatable, Sendable {
    case markedV1
    case legacy

    var minimumAgeInSeconds: Int64 {
        switch self {
        case .markedV1:
            60 * 60
        case .legacy:
            24 * 60 * 60
        }
    }
}

nonisolated enum OpenAIMultipartScratchDirectoryEntry: Equatable, Sendable {
    case name(String)
    case invalidName
}

nonisolated struct OpenAIMultipartScratchDeletionSnapshot: Equatable, Sendable {
    let identity: OpenAITranscriptionFileIdentity
    let referenceTime: OpenAIMultipartScratchTimestamp
    let minimumAgeInSeconds: Int64
}

nonisolated protocol OpenAIMultipartScratchCandidate: AnyObject {
    func makeDeletionSnapshot(
        referenceTime: OpenAIMultipartScratchTimestamp,
        minimumAgeInSeconds: Int64,
        shouldStartOperation: () -> Bool
    ) -> OpenAIMultipartScratchDeletionSnapshot?
    func removeIfUnchanged(
        _ snapshot: OpenAIMultipartScratchDeletionSnapshot,
        shouldStartOperation: () -> Bool
    ) -> Bool
    func close()
}

nonisolated protocol OpenAIMultipartScratchDirectory: AnyObject {
    func nextEntry(
        shouldStartOperation: () -> Bool
    ) throws -> OpenAIMultipartScratchDirectoryEntry?
    func openCandidate(
        named fileName: String,
        kind: OpenAIMultipartScratchKind,
        shouldStartOperation: () -> Bool
    ) throws -> (any OpenAIMultipartScratchCandidate)?
    func close()
}

nonisolated protocol OpenAIMultipartScratchFileSystem {
    func openNamespace(
        at directoryURL: URL,
        shouldStartOperation: () -> Bool
    ) throws -> (any OpenAIMultipartScratchDirectory)?
}

nonisolated struct OpenAIMultipartScratchScavengeSummary:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    enum StopReason: Equatable, Sendable {
        case complete
        case namespaceUnavailable
        case directoryFailure
        case entryLimit
        case removalLimit
        case byteLimit
        case timeLimit
        case clockFailure
    }

    let inspectedEntryCount: Int
    let removedFileCount: Int
    let accountedByteCount: Int64
    let stopReason: StopReason

    var description: String {
        "OpenAIMultipartScratchScavengeSummary(<redacted>)"
    }

    var debugDescription: String { description }

    var customMirror: Mirror {
        Mirror(
            self,
            children: [(label: String?, value: Any)](),
            displayStyle: .struct
        )
    }
}

nonisolated struct OpenAIMultipartScratchScavenger {
    static let maximumInspectedEntryCount = 256
    static let maximumRemovedFileCount = 32
    static let maximumAccountedByteCount: Int64 = 512 * 1_024 * 1_024
    static let maximumElapsedNanoseconds: UInt64 = 1_000_000_000

    private let namespaceURL: URL
    private let fileSystem: any OpenAIMultipartScratchFileSystem
    private let wallClock: @Sendable () -> OpenAIMultipartScratchTimestamp?
    private let monotonicClock: @Sendable () -> UInt64?

    init(
        namespaceURL: URL = OpenAIMultipartScratchNamespace.defaultDirectoryURL,
        fileSystem: any OpenAIMultipartScratchFileSystem =
            POSIXOpenAIMultipartScratchFileSystem(),
        wallClock: @escaping @Sendable () -> OpenAIMultipartScratchTimestamp? = {
            systemScratchTimestamp(clock: CLOCK_REALTIME)
        },
        monotonicClock: @escaping @Sendable () -> UInt64? = {
            systemScratchNanoseconds(clock: CLOCK_MONOTONIC)
        }
    ) {
        self.namespaceURL = namespaceURL
        self.fileSystem = fileSystem
        self.wallClock = wallClock
        self.monotonicClock = monotonicClock
    }

    func run() -> OpenAIMultipartScratchScavengeSummary {
        guard let referenceTime = wallClock(),
              let startTime = monotonicClock() else {
            return summary(stopReason: .clockFailure)
        }

        let directory: (any OpenAIMultipartScratchDirectory)?
        do {
            directory = try fileSystem.openNamespace(
                at: namespaceURL,
                shouldStartOperation: {
                    withinTimeBudget(startTime: startTime)
                }
            )
        } catch {
            return summary(stopReason: .namespaceUnavailable)
        }
        guard withinTimeBudget(startTime: startTime) else {
            directory?.close()
            return summary(stopReason: .timeLimit)
        }
        guard let directory else {
            return summary(stopReason: .complete)
        }
        defer { directory.close() }

        var inspectedEntryCount = 0
        var removedFileCount = 0
        var accountedByteCount: Int64 = 0

        while true {
            guard withinTimeBudget(startTime: startTime) else {
                return summary(
                    inspected: inspectedEntryCount,
                    removed: removedFileCount,
                    bytes: accountedByteCount,
                    stopReason: .timeLimit
                )
            }
            guard inspectedEntryCount < Self.maximumInspectedEntryCount else {
                return summary(
                    inspected: inspectedEntryCount,
                    removed: removedFileCount,
                    bytes: accountedByteCount,
                    stopReason: .entryLimit
                )
            }

            let entry: OpenAIMultipartScratchDirectoryEntry?
            do {
                entry = try directory.nextEntry(
                    shouldStartOperation: {
                        withinTimeBudget(startTime: startTime)
                    }
                )
            } catch {
                return summary(
                    inspected: inspectedEntryCount,
                    removed: removedFileCount,
                    bytes: accountedByteCount,
                    stopReason: .directoryFailure
                )
            }
            guard withinTimeBudget(startTime: startTime) else {
                return summary(
                    inspected: inspectedEntryCount,
                    removed: removedFileCount,
                    bytes: accountedByteCount,
                    stopReason: .timeLimit
                )
            }
            guard let entry else {
                return summary(
                    inspected: inspectedEntryCount,
                    removed: removedFileCount,
                    bytes: accountedByteCount,
                    stopReason: .complete
                )
            }

            if case .name(let name) = entry, name == "." || name == ".." {
                continue
            }
            inspectedEntryCount += 1

            guard case .name(let fileName) = entry,
                  let kind = kind(for: fileName) else {
                continue
            }
            guard withinTimeBudget(startTime: startTime) else {
                return summary(
                    inspected: inspectedEntryCount,
                    removed: removedFileCount,
                    bytes: accountedByteCount,
                    stopReason: .timeLimit
                )
            }

            let candidate: (any OpenAIMultipartScratchCandidate)?
            do {
                candidate = try directory.openCandidate(
                    named: fileName,
                    kind: kind,
                    shouldStartOperation: {
                        withinTimeBudget(startTime: startTime)
                    }
                )
            } catch {
                continue
            }
            guard let candidate else {
                continue
            }

            guard withinTimeBudget(startTime: startTime) else {
                candidate.close()
                return summary(
                    inspected: inspectedEntryCount,
                    removed: removedFileCount,
                    bytes: accountedByteCount,
                    stopReason: .timeLimit
                )
            }
            guard let deletionSnapshot = candidate.makeDeletionSnapshot(
                referenceTime: referenceTime,
                minimumAgeInSeconds: kind.minimumAgeInSeconds,
                shouldStartOperation: {
                    withinTimeBudget(startTime: startTime)
                }
            ) else {
                candidate.close()
                continue
            }

            let byteCount = deletionSnapshot.identity.byteCount
            let addition = accountedByteCount.addingReportingOverflow(byteCount)
            guard !addition.overflow,
                  addition.partialValue <= Self.maximumAccountedByteCount else {
                candidate.close()
                return summary(
                    inspected: inspectedEntryCount,
                    removed: removedFileCount,
                    bytes: accountedByteCount,
                    stopReason: .byteLimit
                )
            }
            accountedByteCount = addition.partialValue
            guard withinTimeBudget(startTime: startTime) else {
                candidate.close()
                return summary(
                    inspected: inspectedEntryCount,
                    removed: removedFileCount,
                    bytes: accountedByteCount,
                    stopReason: .timeLimit
                )
            }

            if candidate.removeIfUnchanged(
                deletionSnapshot,
                shouldStartOperation: {
                    withinTimeBudget(startTime: startTime)
                }
            ) {
                removedFileCount += 1
            }
            candidate.close()
            guard removedFileCount < Self.maximumRemovedFileCount else {
                return summary(
                    inspected: inspectedEntryCount,
                    removed: removedFileCount,
                    bytes: accountedByteCount,
                    stopReason: .removalLimit
                )
            }
        }
    }

    private func kind(for fileName: String) -> OpenAIMultipartScratchKind? {
        if OpenAIMultipartScratchNamespace.identifier(inV1FileName: fileName) != nil {
            return .markedV1
        }
        if OpenAIMultipartScratchNamespace.identifier(inLegacyFileName: fileName) != nil {
            return .legacy
        }
        return nil
    }

    private func withinTimeBudget(startTime: UInt64) -> Bool {
        guard let currentTime = monotonicClock(), currentTime >= startTime else {
            return false
        }
        return currentTime - startTime < Self.maximumElapsedNanoseconds
    }

    private func summary(
        inspected: Int = 0,
        removed: Int = 0,
        bytes: Int64 = 0,
        stopReason: OpenAIMultipartScratchScavengeSummary.StopReason
    ) -> OpenAIMultipartScratchScavengeSummary {
        OpenAIMultipartScratchScavengeSummary(
            inspectedEntryCount: inspected,
            removedFileCount: removed,
            accountedByteCount: bytes,
            stopReason: stopReason
        )
    }
}

nonisolated struct POSIXOpenAIMultipartScratchFileSystem:
    OpenAIMultipartScratchFileSystem {
    private let adapter: any OpenAIMultipartScratchPOSIXAdapter

    init(
        adapter: any OpenAIMultipartScratchPOSIXAdapter =
            DarwinOpenAIMultipartScratchPOSIXAdapter()
    ) {
        self.adapter = adapter
    }

    func openNamespace(
        at directoryURL: URL,
        shouldStartOperation: () -> Bool
    ) throws -> (any OpenAIMultipartScratchDirectory)? {
        let openResult = retryingScratchPOSIXCall(
            shouldStartOperation: shouldStartOperation
        ) {
            adapter.openFile(
                atPath: directoryURL.path,
                flags: O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
            )
        }
        guard case .some(.success(let descriptor)) = openResult else {
            return nil
        }

        let statusResult = retryingScratchPOSIXCall(
            shouldStartOperation: shouldStartOperation
        ) {
            adapter.fileStatus(for: descriptor)
        }
        let userResult = retryingScratchPOSIXCall(
            shouldStartOperation: shouldStartOperation
        ) {
            adapter.effectiveUserID()
        }
        guard case .some(.success(let status)) = statusResult,
              case .some(.success(let effectiveUserID)) = userResult,
              status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == effectiveUserID,
              status.st_mode & mode_t(0o777) == mode_t(0o700) else {
            adapter.closeFile(descriptor)
            return nil
        }

        let streamResult = retryingScratchPOSIXCall(
            shouldStartOperation: shouldStartOperation
        ) {
            adapter.openDirectoryStream(for: descriptor)
        }
        guard case .some(.success(let stream)) = streamResult else {
            adapter.closeFile(descriptor)
            return nil
        }
        return POSIXOpenAIMultipartScratchDirectory(
            stream: stream,
            effectiveUserID: effectiveUserID,
            adapter: adapter
        )
    }
}

nonisolated final class POSIXOpenAIMultipartScratchDirectory:
    OpenAIMultipartScratchDirectory {
    private var stream: UnsafeMutablePointer<DIR>?
    private let effectiveUserID: uid_t
    private let adapter: any OpenAIMultipartScratchPOSIXAdapter

    init(
        stream: UnsafeMutablePointer<DIR>,
        effectiveUserID: uid_t,
        adapter: any OpenAIMultipartScratchPOSIXAdapter
    ) {
        self.stream = stream
        self.effectiveUserID = effectiveUserID
        self.adapter = adapter
    }

    func nextEntry(
        shouldStartOperation: () -> Bool
    ) throws -> OpenAIMultipartScratchDirectoryEntry? {
        guard let stream else {
            return nil
        }
        let result = retryingScratchPOSIXCall(
            shouldStartOperation: shouldStartOperation
        ) {
            adapter.nextDirectoryEntry(in: stream)
        }
        guard let result else {
            return nil
        }
        switch result {
        case .success(let entry):
            return entry
        case .failure:
            throw POSIXOpenAIMultipartScratchError.directoryReadFailed
        }
    }

    func openCandidate(
        named fileName: String,
        kind: OpenAIMultipartScratchKind,
        shouldStartOperation: () -> Bool
    ) throws -> (any OpenAIMultipartScratchCandidate)? {
        guard let stream else {
            return nil
        }
        let directoryResult = retryingScratchPOSIXCall(
            shouldStartOperation: shouldStartOperation
        ) {
            adapter.directoryDescriptor(for: stream)
        }
        guard case .some(.success(let directoryDescriptor)) = directoryResult else {
            return nil
        }

        let openResult = retryingScratchPOSIXCall(
            shouldStartOperation: shouldStartOperation
        ) {
            adapter.openFile(
                relativeTo: directoryDescriptor,
                named: fileName,
                flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
            )
        }
        guard case .some(.success(let descriptor)) = openResult else {
            return nil
        }

        let statusResult = retryingScratchPOSIXCall(
            shouldStartOperation: shouldStartOperation
        ) {
            adapter.fileStatus(for: descriptor)
        }
        guard case .some(.success(let status)) = statusResult,
              isEligibleScratchStatus(status, effectiveUserID: effectiveUserID),
              (kind != .markedV1
                || markerIsExact(
                    on: descriptor,
                    adapter: adapter,
                    shouldStartOperation: shouldStartOperation
                )),
              case .some(.success) = retryingScratchPOSIXCall(
                shouldStartOperation: shouldStartOperation,
                operation: {
                    adapter.lock(
                        fileDescriptor: descriptor,
                        operation: LOCK_EX | LOCK_NB
                    )
                }
              ) else {
            adapter.closeFile(descriptor)
            return nil
        }
        return POSIXOpenAIMultipartScratchCandidate(
            directoryDescriptor: directoryDescriptor,
            fileDescriptor: descriptor,
            fileName: fileName,
            kind: kind,
            identity: fileIdentity(status),
            effectiveUserID: effectiveUserID,
            adapter: adapter
        )
    }

    func close() {
        guard let stream else {
            return
        }
        self.stream = nil
        adapter.closeDirectoryStream(stream)
    }

    deinit {
        close()
    }
}

nonisolated final class POSIXOpenAIMultipartScratchCandidate:
    OpenAIMultipartScratchCandidate {
    private let directoryDescriptor: Int32
    private var fileDescriptor: Int32?
    private let fileName: String
    private let kind: OpenAIMultipartScratchKind
    private let identity: OpenAITranscriptionFileIdentity
    private let effectiveUserID: uid_t
    private let adapter: any OpenAIMultipartScratchPOSIXAdapter

    init(
        directoryDescriptor: Int32,
        fileDescriptor: Int32,
        fileName: String,
        kind: OpenAIMultipartScratchKind,
        identity: OpenAITranscriptionFileIdentity,
        effectiveUserID: uid_t,
        adapter: any OpenAIMultipartScratchPOSIXAdapter
    ) {
        self.directoryDescriptor = directoryDescriptor
        self.fileDescriptor = fileDescriptor
        self.fileName = fileName
        self.kind = kind
        self.identity = identity
        self.effectiveUserID = effectiveUserID
        self.adapter = adapter
    }

    func makeDeletionSnapshot(
        referenceTime: OpenAIMultipartScratchTimestamp,
        minimumAgeInSeconds: Int64,
        shouldStartOperation: () -> Bool
    ) -> OpenAIMultipartScratchDeletionSnapshot? {
        guard let fileDescriptor else {
            return nil
        }
        let descriptorResult = retryingScratchPOSIXCall(
            shouldStartOperation: shouldStartOperation
        ) {
            adapter.fileStatus(for: fileDescriptor)
        }
        guard case .some(.success(let descriptorStatus)) = descriptorResult,
              isEligibleScratchStatus(
                descriptorStatus,
                effectiveUserID: effectiveUserID
              ),
              fileIdentity(descriptorStatus) == identity,
              (kind != .markedV1
                || markerIsExact(
                    on: fileDescriptor,
                    adapter: adapter,
                    shouldStartOperation: shouldStartOperation
                )) else {
            return nil
        }

        let pathResult = retryingScratchPOSIXCall(
            shouldStartOperation: shouldStartOperation
        ) {
            adapter.pathStatus(
                relativeTo: directoryDescriptor,
                named: fileName,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }
        guard case .some(.success(let pathStatus)) = pathResult,
              isEligibleScratchStatus(
                pathStatus,
                effectiveUserID: effectiveUserID
              ),
              fileIdentity(pathStatus) == identity,
              newestTimestamp(for: descriptorStatus).isAtLeast(
                  minimumAgeInSeconds,
                  before: referenceTime
              ) else {
            return nil
        }
        return OpenAIMultipartScratchDeletionSnapshot(
            identity: identity,
            referenceTime: referenceTime,
            minimumAgeInSeconds: minimumAgeInSeconds
        )
    }

    func removeIfUnchanged(
        _ snapshot: OpenAIMultipartScratchDeletionSnapshot,
        shouldStartOperation: () -> Bool
    ) -> Bool {
        guard let fileDescriptor else {
            return false
        }
        let descriptorResult = retryingScratchPOSIXCall(
            shouldStartOperation: shouldStartOperation
        ) {
            adapter.fileStatus(for: fileDescriptor)
        }
        guard case .some(.success(let descriptorStatus)) = descriptorResult,
              isEligibleScratchStatus(
                descriptorStatus,
                effectiveUserID: effectiveUserID
              ),
              fileIdentity(descriptorStatus) == snapshot.identity,
              newestTimestamp(for: descriptorStatus).isAtLeast(
                  snapshot.minimumAgeInSeconds,
                  before: snapshot.referenceTime
              ),
              (kind != .markedV1
                || markerIsExact(
                    on: fileDescriptor,
                    adapter: adapter,
                    shouldStartOperation: shouldStartOperation
                )),
              case .some(.success) = retryingScratchPOSIXCall(
                shouldStartOperation: shouldStartOperation,
                operation: {
                    adapter.lock(
                        fileDescriptor: fileDescriptor,
                        operation: LOCK_EX | LOCK_NB
                    )
                }
              ) else {
            return false
        }

        let pathResult = retryingScratchPOSIXCall(
            shouldStartOperation: shouldStartOperation
        ) {
            adapter.pathStatus(
                relativeTo: directoryDescriptor,
                named: fileName,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }
        guard case .some(.success(let pathStatus)) = pathResult,
              isEligibleScratchStatus(
                pathStatus,
                effectiveUserID: effectiveUserID
              ),
              fileIdentity(pathStatus) == snapshot.identity,
              newestTimestamp(for: pathStatus).isAtLeast(
                  snapshot.minimumAgeInSeconds,
                  before: snapshot.referenceTime
              ) else {
            return false
        }

        let unlinkResult = retryingScratchPOSIXCall(
            shouldStartOperation: shouldStartOperation
        ) {
            adapter.unlink(
                relativeTo: directoryDescriptor,
                named: fileName,
                flags: 0
            )
        }
        guard case .some(.success) = unlinkResult else {
            return false
        }
        return true
    }

    func close() {
        guard let fileDescriptor else {
            return
        }
        self.fileDescriptor = nil
        adapter.closeFile(fileDescriptor)
    }

    deinit {
        close()
    }
}

nonisolated private enum POSIXOpenAIMultipartScratchError: Error {
    case directoryReadFailed
}

nonisolated private func retryingScratchPOSIXCall<Value>(
    shouldStartOperation: () -> Bool,
    operation: () -> OpenAIMultipartScratchPOSIXCallResult<Value>
) -> OpenAIMultipartScratchPOSIXCallResult<Value>? {
    while shouldStartOperation() {
        let result = operation()
        if case .failure(EINTR) = result {
            continue
        }
        return result
    }
    return nil
}

nonisolated private func markerIsInstalled(
    on fileDescriptor: Int32,
    adapter: any OpenAIMultipartScratchPOSIXAdapter,
    shouldStartOperation: () -> Bool
) -> Bool {
    let result = retryingScratchPOSIXCall(
        shouldStartOperation: shouldStartOperation
    ) {
        adapter.setExtendedAttribute(
            named: OpenAIMultipartScratchNamespace.markerName,
            value: OpenAIMultipartScratchNamespace.markerValue,
            on: fileDescriptor,
            flags: XATTR_CREATE
        )
    }
    guard case .some(.success) = result else {
        return false
    }
    return true
}

nonisolated private func markerIsExact(
    on fileDescriptor: Int32,
    adapter: any OpenAIMultipartScratchPOSIXAdapter,
    shouldStartOperation: () -> Bool
) -> Bool {
    let result = retryingScratchPOSIXCall(
        shouldStartOperation: shouldStartOperation
    ) {
        adapter.extendedAttribute(
            named: OpenAIMultipartScratchNamespace.markerName,
            on: fileDescriptor,
            maximumByteCount: OpenAIMultipartScratchNamespace.markerValue.count + 1
        )
    }
    guard case .some(.success(let bytes)) = result else {
        return false
    }
    return bytes == OpenAIMultipartScratchNamespace.markerValue
}

nonisolated private func isEligibleScratchStatus(
    _ status: stat,
    effectiveUserID: uid_t
) -> Bool {
    status.st_mode & S_IFMT == S_IFREG
        && status.st_uid == effectiveUserID
        && status.st_mode & mode_t(0o777) == mode_t(0o600)
        && status.st_nlink == 1
        && status.st_size >= 0
}

nonisolated private func newestTimestamp(
    for identity: OpenAITranscriptionFileIdentity
) -> OpenAIMultipartScratchTimestamp {
    max(
        OpenAIMultipartScratchTimestamp(
            seconds: identity.modificationSeconds,
            nanoseconds: identity.modificationNanoseconds
        ),
        OpenAIMultipartScratchTimestamp(
            seconds: identity.changeSeconds,
            nanoseconds: identity.changeNanoseconds
        )
    )
}

nonisolated private func newestTimestamp(
    for status: stat
) -> OpenAIMultipartScratchTimestamp {
    newestTimestamp(for: fileIdentity(status))
}

nonisolated private func systemScratchTimestamp(
    clock: clockid_t
) -> OpenAIMultipartScratchTimestamp? {
    var value = timespec()
    guard Darwin.clock_gettime(clock, &value) == 0 else {
        return nil
    }
    return OpenAIMultipartScratchTimestamp(
        seconds: Int64(value.tv_sec),
        nanoseconds: Int64(value.tv_nsec)
    )
}

nonisolated private func systemScratchNanoseconds(clock: clockid_t) -> UInt64? {
    guard let value = systemScratchTimestamp(clock: clock),
          value.seconds >= 0,
          value.nanoseconds >= 0 else {
        return nil
    }
    let seconds = UInt64(value.seconds).multipliedReportingOverflow(
        by: 1_000_000_000
    )
    guard !seconds.overflow else {
        return nil
    }
    let total = seconds.partialValue.addingReportingOverflow(
        UInt64(value.nanoseconds)
    )
    return total.overflow ? nil : total.partialValue
}
