import Darwin
import Foundation
import Testing
@testable import HoldTypePersistence

struct IOSHistoryPolicyJournalTests {
    @Test func canonicalV1HasExactlyFourFieldsAndRoundTrips() throws {
        let state = try policyState(
            revision: 7,
            historyEnabled: false
        )
        let data = try IOSHistoryPolicyWireCodec.encode(state)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(Set(object.keys) == [
            "schemaVersion", "revision", "historyEnabled", "policyGeneration",
        ])
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["revision"] as? Int == 7)
        #expect(object["historyEnabled"] as? Bool == false)
        #expect(object["policyGeneration"] as? Int == 7)
        #expect(try IOSHistoryPolicyWireCodec.decode(data) == state)
    }

    @Test func schemaDispatchPrecedesTheV1Allowlist() throws {
        var object = try canonicalObject()
        object["schemaVersion"] = 2
        object["futureField"] = "future"

        #expect(throws: IOSHistoryPolicyError.unsupportedSchemaVersion) {
            try IOSHistoryPolicyWireCodec.decode(
                JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    @Test func duplicateUnknownMissingAndNumericAliasesAreRejected() throws {
        let canonical = try IOSHistoryPolicyWireCodec.encode(.baseline)
        let canonicalString = try #require(
            String(data: canonical, encoding: .utf8)
        )
        let duplicate = Data(
            canonicalString.replacingOccurrences(
                of: "{",
                with: "{\"revision\":1,",
                options: [],
                range: canonicalString.startIndex..<canonicalString.index(
                    after: canonicalString.startIndex
                )
            ).utf8
        )
        #expect(throws: IOSHistoryPolicyError.malformedData) {
            try IOSHistoryPolicyWireCodec.decode(duplicate)
        }

        var object = try canonicalObject()
        object["unknown"] = true
        #expect(throws: IOSHistoryPolicyError.invalidRecord) {
            try IOSHistoryPolicyWireCodec.decode(
                JSONSerialization.data(withJSONObject: object)
            )
        }
        object.removeValue(forKey: "unknown")
        object.removeValue(forKey: "historyEnabled")
        #expect(throws: IOSHistoryPolicyError.invalidRecord) {
            try IOSHistoryPolicyWireCodec.decode(
                JSONSerialization.data(withJSONObject: object)
            )
        }

        #expect(throws: IOSHistoryPolicyError.invalidRecord) {
            try IOSHistoryPolicyWireCodec.decode(
                Data(
                    #"{"historyEnabled":true,"policyGeneration":1,"revision":1.0,"schemaVersion":1}"#.utf8
                )
            )
        }
        #expect(throws: IOSHistoryPolicyError.invalidRecord) {
            try IOSHistoryPolicyWireCodec.decode(
                Data(
                    #"{"historyEnabled":1,"policyGeneration":1,"revision":1,"schemaVersion":1}"#.utf8
                )
            )
        }
    }

    @Test func malformedDepthAndSourceLimitsFailBeforeMaterialization() {
        #expect(throws: IOSHistoryPolicyError.malformedData) {
            try IOSHistoryPolicyWireCodec.decode(Data([0x7B, 0xFF, 0x7D]))
        }
        #expect(throws: IOSHistoryPolicyError.malformedData) {
            try IOSHistoryPolicyWireCodec.decode(
                Data("{\"schemaVersion\":1,\"nested\":{}}".utf8)
            )
        }
        #expect(throws: IOSHistoryPolicyError.sourceTooLarge) {
            try IOSHistoryPolicyWireCodec.decode(
                Data(
                    repeating: 0x20,
                    count: IOSHistoryPolicyJournal.maximumByteCount + 1
                )
            )
        }
    }

    @Test func repositoryUsesPhysicalRevisionCASAndTypedUncertainty() throws {
        let fileSystem = HistoryPolicyFakeFileSystem()
        let repository = FoundationIOSHistoryPolicyJournalRepository(
            fileSystem: fileSystem
        )
        fileSystem.install(try IOSHistoryPolicyWireCodec.encode(.baseline))
        let loaded = try repository.load()
        let created = try #require(loaded)
        #expect(try repository.load() == created)

        let successor = try policyState(revision: 2, historyEnabled: false)
        let replaced = try repository.replace(successor, expected: created)
        #expect(replaced.state == successor)
        #expect(throws: IOSHistoryPolicyError.compareAndSwapFailed) {
            try repository.replace(.baseline, expected: created)
        }

        fileSystem.replaceError = .commitUncertain
        #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            try repository.replace(successor, expected: replaced)
        }
    }

    @Test func repositoryPreservesCorruptFutureAndProtectedSlots() throws {
        let fileSystem = HistoryPolicyFakeFileSystem()
        let repository = FoundationIOSHistoryPolicyJournalRepository(
            fileSystem: fileSystem
        )
        fileSystem.install(Data("corrupt".utf8))
        #expect(throws: IOSHistoryPolicyError.malformedData) {
            try repository.load()
        }
        let preserved = fileSystem.file?.data

        fileSystem.readError = .protectedDataUnavailable
        #expect(throws: IOSHistoryPolicyError.dataProtectionUnavailable) {
            try repository.load()
        }
        #expect(fileSystem.file?.data == preserved)
    }

    @Test func maintenanceMappingIsContentFree() throws {
        let expected = IOSStrictProtectedRecordMaintenanceReport(
            inspectedEntryCount: 4,
            inspectedByteCount: 80,
            removedFileCount: 1,
            removedByteCount: 20,
            reachedLimit: false
        )
        let repository = FoundationIOSHistoryPolicyJournalRepository(
            fileSystem: HistoryPolicyFakeFileSystem(),
            stagingMaintenance: { _ in expected }
        )
        #expect(
            try repository.performStagingMaintenance(
                now: Date(timeIntervalSince1970: 1_800_000_000)
            ) == expected
        )
    }

    @Test func liveRepositoryUsesExactProtectionModeBackupPolicyAndMarker() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "history-policy-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: base) }
        let repository = FoundationIOSHistoryPolicyJournalRepository(
            applicationSupportDirectoryURL: base
        )
        let fileSystem = FoundationIOSStrictProtectedRecordFileSystem(
            applicationSupportDirectoryURL: base,
            configuration: .historyPolicy
        )
        _ = try fileSystem.createFile(
            with: IOSHistoryPolicyWireCodec.encode(.baseline)
        )

        let rootURL = fileURLRoot(in: base)
        let fileURL = IOSHistoryPolicyStorageLocation.fileURL(in: base)
        let rootAttributes = try FileManager.default.attributesOfItem(
            atPath: rootURL.path
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )
        #expect(
            (rootAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700
        )
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(
            try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true
        )
        #if os(iOS) && !targetEnvironment(simulator)
        #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
        #else
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            #expect(protection == .complete)
        }
        #endif

        let descriptor = Darwin.open(fileURL.path, O_RDWR | O_CLOEXEC)
        let validDescriptor = try #require(descriptor >= 0 ? descriptor : nil)
        defer { Darwin.close(validDescriptor) }
        let marker = try #require(
            IOSStrictProtectedRecordConfiguration.historyPolicy.marker
        )
        var bytes = [UInt8](repeating: 0, count: marker.value.count + 1)
        let byteCount = marker.name.withCString { name in
            bytes.withUnsafeMutableBytes {
                Darwin.fgetxattr(
                    validDescriptor,
                    name,
                    $0.baseAddress,
                    $0.count,
                    0,
                    0
                )
            }
        }
        #expect(byteCount == marker.value.count)
        #expect(Array(bytes.prefix(marker.value.count)) == marker.value)

        let preservedData = try Data(contentsOf: fileURL)
        let removeResult = marker.name.withCString {
            Darwin.fremovexattr(validDescriptor, $0, 0)
        }
        #expect(removeResult == 0)
        #expect(throws: IOSHistoryPolicyError.readFailed) {
            _ = try repository.load()
        }
        #expect(try Data(contentsOf: fileURL) == preservedData)

        let wrongMarker = Array("v2".utf8)
        let setResult = marker.name.withCString { name in
            wrongMarker.withUnsafeBytes {
                Darwin.fsetxattr(
                    validDescriptor,
                    name,
                    $0.baseAddress,
                    $0.count,
                    0,
                    Int32(XATTR_CREATE)
                )
            }
        }
        #expect(setResult == 0)
        #expect(throws: IOSHistoryPolicyError.readFailed) {
            _ = try repository.load()
        }
        #expect(try Data(contentsOf: fileURL) == preservedData)
    }
}

private func fileURLRoot(in base: URL) -> URL {
    base.appendingPathComponent(
        IOSStrictProtectedRecordConfiguration.historyPolicy.rootDirectoryName,
        isDirectory: true
    )
}

private final class HistoryPolicyFakeFileSystem:
    IOSStrictProtectedRecordFileSystem,
    @unchecked Sendable {
    var file: IOSStrictProtectedRecordFile?
    var readError: IOSStrictProtectedRecordFileSystemError?
    var replaceError: IOSStrictProtectedRecordFileSystemError?
    private var nextToken: UInt64 = 1

    func install(_ data: Data) {
        file = IOSStrictProtectedRecordFile(
            data: data,
            revision: makeRevision()
        )
    }

    func readFileIfPresent() throws -> IOSStrictProtectedRecordFile? {
        if let readError { throw readError }
        return file
    }

    func createFile(
        with data: Data
    ) throws -> IOSStrictProtectedRecordFileRevision {
        guard file == nil else {
            throw IOSStrictProtectedRecordFileSystemError.destinationConflict
        }
        let revision = makeRevision()
        file = IOSStrictProtectedRecordFile(data: data, revision: revision)
        return revision
    }

    func replaceFile(
        with data: Data,
        expected: IOSStrictProtectedRecordFileRevision
    ) throws -> IOSStrictProtectedRecordFileRevision {
        guard file?.revision == expected else {
            throw IOSStrictProtectedRecordFileSystemError.staleRevision
        }
        if let replaceError { throw replaceError }
        let revision = makeRevision()
        file = IOSStrictProtectedRecordFile(data: data, revision: revision)
        return revision
    }

    func removeFile(
        expected: IOSStrictProtectedRecordFileRevision
    ) throws {
        guard file?.revision == expected else {
            throw IOSStrictProtectedRecordFileSystemError.staleRevision
        }
        file = nil
    }

    private func makeRevision() -> IOSStrictProtectedRecordFileRevision {
        defer { nextToken += 1 }
        return IOSStrictProtectedRecordFileRevision(testingToken: nextToken)
    }
}

private func policyState(
    revision: Int64,
    historyEnabled: Bool
) throws -> IOSHistoryPolicyState {
    try IOSHistoryPolicyState(
        revision: revision,
        historyEnabled: historyEnabled,
        policyGeneration: revision
    )
}

private func canonicalObject() throws -> [String: Any] {
    try #require(
        JSONSerialization.jsonObject(
            with: IOSHistoryPolicyWireCodec.encode(.baseline)
        ) as? [String: Any]
    )
}
