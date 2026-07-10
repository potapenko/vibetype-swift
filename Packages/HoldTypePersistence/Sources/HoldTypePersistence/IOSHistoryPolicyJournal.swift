import CoreFoundation
import Darwin
import Foundation

struct IOSHistoryPolicyJournalSnapshot: Equatable, Sendable {
    let state: IOSHistoryPolicyState
    let fileRevision: IOSStrictProtectedRecordFileRevision
}

protocol IOSHistoryPolicyJournalStoring: Sendable {
    func load() throws -> IOSHistoryPolicyJournalSnapshot?
    func replace(
        _ state: IOSHistoryPolicyState,
        expected: IOSHistoryPolicyJournalSnapshot
    ) throws -> IOSHistoryPolicyJournalSnapshot
    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport
}

enum IOSHistoryPolicyJournal {
    static let maximumByteCount = 16_384
}

struct FoundationIOSHistoryPolicyJournalRepository:
    IOSHistoryPolicyJournalStoring,
    Sendable {
    private let fileSystem: any IOSStrictProtectedRecordFileSystem
    private let stagingMaintenance: @Sendable (Date) throws
        -> IOSStrictProtectedRecordMaintenanceReport

    init(applicationSupportDirectoryURL: URL) {
        let fileSystem = FoundationIOSStrictProtectedRecordFileSystem(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            configuration: .historyPolicy,
            adapter: IOSHistoryPolicyMarkerPOSIXAdapter()
        )
        self.fileSystem = fileSystem
        stagingMaintenance = { now in
            try fileSystem.removeAbandonedTemporaryFiles(now: now)
        }
    }

    init(
        fileSystem: any IOSStrictProtectedRecordFileSystem,
        stagingMaintenance: @escaping @Sendable (Date) throws
            -> IOSStrictProtectedRecordMaintenanceReport = { _ in .empty }
    ) {
        self.fileSystem = fileSystem
        self.stagingMaintenance = stagingMaintenance
    }

    func load() throws -> IOSHistoryPolicyJournalSnapshot? {
        guard let file = try readFile() else { return nil }
        return IOSHistoryPolicyJournalSnapshot(
            state: try IOSHistoryPolicyWireCodec.decode(file.data),
            fileRevision: file.revision
        )
    }

    func replace(
        _ state: IOSHistoryPolicyState,
        expected: IOSHistoryPolicyJournalSnapshot
    ) throws -> IOSHistoryPolicyJournalSnapshot {
        let data = try IOSHistoryPolicyWireCodec.encode(state)
        do {
            let revision = try fileSystem.replaceFile(
                with: data,
                expected: expected.fileRevision
            )
            return IOSHistoryPolicyJournalSnapshot(
                state: state,
                fileRevision: revision
            )
        } catch IOSStrictProtectedRecordFileSystemError.staleRevision,
                IOSStrictProtectedRecordFileSystemError.missing {
            throw IOSHistoryPolicyError.compareAndSwapFailed
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable {
            throw IOSHistoryPolicyError.dataProtectionUnavailable
        } catch IOSStrictProtectedRecordFileSystemError.commitUncertain {
            throw IOSHistoryPolicyError.commitUncertain
        } catch {
            throw IOSHistoryPolicyError.writeFailed
        }
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        do {
            return try stagingMaintenance(now)
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable {
            throw IOSHistoryPolicyError.dataProtectionUnavailable
        } catch {
            throw IOSHistoryPolicyError.maintenanceFailed
        }
    }

    private func readFile() throws -> IOSStrictProtectedRecordFile? {
        do {
            return try fileSystem.readFileIfPresent()
        } catch IOSStrictProtectedRecordFileSystemError.sourceTooLarge {
            throw IOSHistoryPolicyError.sourceTooLarge
        } catch IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable {
            throw IOSHistoryPolicyError.dataProtectionUnavailable
        } catch {
            throw IOSHistoryPolicyError.readFailed
        }
    }
}

enum IOSHistoryPolicyWireCodec {
    private static let supportedSchemaVersion: Int64 = 1
    private static let fields: Set<String> = [
        "schemaVersion", "revision", "historyEnabled", "policyGeneration",
    ]

    static func encode(_ state: IOSHistoryPolicyState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(IOSHistoryPolicyWireV1(state: state))
            guard data.count <= IOSHistoryPolicyJournal.maximumByteCount else {
                throw IOSHistoryPolicyError.writeFailed
            }
            return data
        } catch let error as IOSHistoryPolicyError {
            throw error
        } catch {
            throw IOSHistoryPolicyError.writeFailed
        }
    }

    static func decode(_ data: Data) throws -> IOSHistoryPolicyState {
        do {
            try BoundedJSONMemberValidator.validate(
                data,
                limits: BoundedJSONMemberValidationLimits(
                    maximumInputByteCount:
                        IOSHistoryPolicyJournal.maximumByteCount,
                    maximumNestingDepth: 1,
                    maximumMembersPerObject: 16,
                    maximumTotalObjectMembers: 16,
                    maximumElementsPerArray: 0,
                    maximumTotalValues: 17,
                    maximumDecodedKeyByteCount: 64,
                    maximumDecodedValueStringByteCount: 256,
                    maximumNumberTokenByteCount: 20
                )
            )
        } catch BoundedJSONMemberValidationError.inputTooLarge {
            throw IOSHistoryPolicyError.sourceTooLarge
        } catch {
            throw IOSHistoryPolicyError.malformedData
        }

        let root: Any
        do {
            root = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw IOSHistoryPolicyError.malformedData
        }
        guard let object = root as? [String: Any] else {
            throw IOSHistoryPolicyError.invalidRecord
        }
        let reader = IOSHistoryPolicyObjectReader(object: object)
        guard try reader.integer64("schemaVersion")
                == supportedSchemaVersion else {
            throw IOSHistoryPolicyError.unsupportedSchemaVersion
        }
        guard Set(object.keys) == fields else {
            throw IOSHistoryPolicyError.invalidRecord
        }
        return try IOSHistoryPolicyState(
            revision: reader.integer64("revision"),
            historyEnabled: reader.boolean("historyEnabled"),
            policyGeneration: reader.integer64("policyGeneration")
        )
    }
}

private struct IOSHistoryPolicyObjectReader {
    let object: [String: Any]

    func boolean(_ key: String) throws -> Bool {
        guard let value = object[key] as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw IOSHistoryPolicyError.invalidRecord
        }
        return value.boolValue
    }

    func integer64(_ key: String) throws -> Int64 {
        guard let value = object[key] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              !Self.isFloatingPoint(value),
              let integer = Int64(value.stringValue) else {
            throw IOSHistoryPolicyError.invalidRecord
        }
        return integer
    }

    private static func isFloatingPoint(_ number: NSNumber) -> Bool {
        let type = String(cString: number.objCType)
        return type == "f" || type == "d"
    }
}

private struct IOSHistoryPolicyWireV1: Encodable {
    let schemaVersion = 1
    let revision: Int64
    let historyEnabled: Bool
    let policyGeneration: Int64

    init(state: IOSHistoryPolicyState) {
        revision = state.revision
        historyEnabled = state.historyEnabled
        policyGeneration = state.policyGeneration
    }
}

private struct IOSHistoryPolicyMarkerPOSIXAdapter:
    IOSPendingRecordingPOSIXAdapter,
    Sendable {
    private let base = DarwinIOSPendingRecordingPOSIXAdapter()

    func effectiveUserID() -> IOSPendingRecordingPOSIXResult<uid_t> {
        base.effectiveUserID()
    }

    func openPath(
        _ path: String,
        flags: Int32,
        mode: mode_t?
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        base.openPath(path, flags: flags, mode: mode)
    }

    func openAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32,
        mode: mode_t?
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        base.openAt(
            directoryDescriptor: directoryDescriptor,
            name: name,
            flags: flags,
            mode: mode
        )
    }

    func makeDirectoryAt(
        directoryDescriptor: Int32,
        name: String,
        mode: mode_t
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.makeDirectoryAt(
            directoryDescriptor: directoryDescriptor,
            name: name,
            mode: mode
        )
    }

    func status(
        of fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<stat> {
        base.status(of: fileDescriptor)
    }

    func statusAtPath(
        _ path: String
    ) -> IOSPendingRecordingPOSIXResult<stat> {
        base.statusAtPath(path)
    }

    func statusAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<stat> {
        base.statusAt(
            directoryDescriptor: directoryDescriptor,
            name: name,
            flags: flags
        )
    }

    func read(
        fileDescriptor: Int32,
        buffer: UnsafeMutableRawPointer,
        byteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        base.read(
            fileDescriptor: fileDescriptor,
            buffer: buffer,
            byteCount: byteCount
        )
    }

    func write(
        fileDescriptor: Int32,
        buffer: UnsafeRawPointer,
        byteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<Int> {
        base.write(
            fileDescriptor: fileDescriptor,
            buffer: buffer,
            byteCount: byteCount
        )
    }

    func synchronize(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.synchronize(fileDescriptor: fileDescriptor)
    }

    func changeMode(
        fileDescriptor: Int32,
        mode: mode_t
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.changeMode(fileDescriptor: fileDescriptor, mode: mode)
    }

    func lock(
        fileDescriptor: Int32,
        operation: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.lock(fileDescriptor: fileDescriptor, operation: operation)
    }

    func setExtendedAttribute(
        fileDescriptor: Int32,
        name: String,
        value: [UInt8],
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        let markerName = IOSStrictProtectedRecordConfiguration
            .historyPolicy.marker?.name
        return base.setExtendedAttribute(
            fileDescriptor: fileDescriptor,
            name: name,
            value: value,
            flags: name == markerName ? Int32(XATTR_CREATE) : flags
        )
    }

    func extendedAttribute(
        fileDescriptor: Int32,
        name: String,
        maximumByteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<[UInt8]> {
        base.extendedAttribute(
            fileDescriptor: fileDescriptor,
            name: name,
            maximumByteCount: maximumByteCount
        )
    }

    func setProtectionClass(
        fileDescriptor: Int32,
        protectionClass: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.setProtectionClass(
            fileDescriptor: fileDescriptor,
            protectionClass: protectionClass
        )
    }

    func protectionClass(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        base.protectionClass(fileDescriptor: fileDescriptor)
    }

    func publishExclusively(
        directoryDescriptor: Int32,
        temporaryName: String,
        finalName: String
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.publishExclusively(
            directoryDescriptor: directoryDescriptor,
            temporaryName: temporaryName,
            finalName: finalName
        )
    }

    func unlinkAt(
        directoryDescriptor: Int32,
        name: String
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        base.unlinkAt(
            directoryDescriptor: directoryDescriptor,
            name: name
        )
    }

    func openDirectoryStream(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<UnsafeMutablePointer<DIR>> {
        base.openDirectoryStream(fileDescriptor: fileDescriptor)
    }

    func nextDirectoryEntry(
        stream: UnsafeMutablePointer<DIR>
    ) -> IOSPendingRecordingPOSIXResult<IOSPendingRecordingDirectoryEntry?> {
        base.nextDirectoryEntry(stream: stream)
    }

    func closeFile(_ fileDescriptor: Int32) {
        base.closeFile(fileDescriptor)
    }

    func closeDirectoryStream(_ stream: UnsafeMutablePointer<DIR>) {
        base.closeDirectoryStream(stream)
    }
}
