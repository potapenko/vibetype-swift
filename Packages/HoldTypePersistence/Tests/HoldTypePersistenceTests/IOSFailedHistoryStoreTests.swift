import Darwin
import Foundation
import Testing
@testable import HoldTypePersistence

struct IOSFailedHistoryStoreTests {
    @Test func missingLoadIsNilAndDoesNotCreateStorage() async throws {
        let fixture = FailedHistoryStoreFixture()
        #expect(try await fixture.store.load() == nil)
        #expect(fixture.fileSystem.file == nil)
        #expect(fixture.fileSystem.events == ["load"])
    }

    @Test func guardedBaselineRequiresProvenMissingOrEmptyState() async throws {
        let missing = FailedHistoryStoreFixture()
        let missingEvidence = try await missing.store.proveGuardedBaseline()
        #expect(
            missingEvidence.capabilityOwnerIdentity == missing.ownerIdentity
        )
        #expect(
            String(describing: missingEvidence)
                == "IOSFailedHistoryGuardedBaselineEvidence(redacted)"
        )
        #expect(missingEvidence.customMirror.children.isEmpty)

        let empty = FailedHistoryStoreFixture()
        try empty.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [],
                audioCleanup: []
            )
        )
        _ = try await empty.store.proveGuardedBaseline()

        let row = FailedHistoryStoreFixture()
        try row.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [try failedHistoryTestEntry()],
                audioCleanup: []
            )
        )
        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try await row.store.proveGuardedBaseline()
        }

        let cleanup = FailedHistoryStoreFixture()
        try cleanup.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [],
                audioCleanup: [try failedHistoryTestAudioCleanup()]
            )
        )
        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try await cleanup.store.proveGuardedBaseline()
        }
    }

    @Test func rawLoadPreservesAllInternalStateForCoordinatorRecovery()
        async throws {
        let fixture = FailedHistoryStoreFixture()
        let envelope = try IOSFailedHistoryEnvelope(
            revision: 9,
            entries: [try failedHistoryTestEntry(policyGeneration: 7)],
            audioCleanup: [
                try failedHistoryTestAudioCleanup(policyGeneration: 3),
            ]
        )
        try fixture.install(envelope)
        #expect(try await fixture.store.load() == envelope)
    }

    @Test func typedReadFailuresPropagateWithoutMutation() async throws {
        let fixture = FailedHistoryStoreFixture()
        try fixture.install(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [],
                audioCleanup: []
            )
        )
        let original = fixture.fileSystem.file?.data

        for (fileError, expected) in [
            (IOSStrictProtectedRecordFileSystemError.sourceTooLarge,
             IOSFailedHistoryError.sourceTooLarge),
            (.protectedDataUnavailable, .dataProtectionUnavailable),
            (.readFailed, .readFailed),
        ] {
            fixture.fileSystem.readError = fileError
            await #expect(throws: expected) {
                _ = try await fixture.store.load()
            }
        }
        #expect(fixture.fileSystem.file?.data == original)
    }

    @Test func stagingMaintenanceUsesInjectedClockAndRedactedReport()
        async throws {
        let fixture = FailedHistoryStoreFixture()
        fixture.fileSystem.maintenanceReport =
            IOSStrictProtectedRecordMaintenanceReport(
                inspectedEntryCount: 2,
                inspectedByteCount: 30,
                removedFileCount: 1,
                removedByteCount: 10,
                reachedLimit: false
            )
        let report = try await fixture.store.performStagingMaintenance()

        #expect(report.inspectedEntryCount == 2)
        #expect(report.removedFileCount == 1)
        #expect(
            String(describing: report)
                == "IOSFailedHistoryMaintenanceReport(redacted)"
        )
        #expect(fixture.fileSystem.events == ["maintenance"])
    }

    @Test func liveRepositoryUsesExactPrivateProtectionAndMarker() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "failed-history-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: base) }

        let ownerIdentity = IOSAcceptedHistoryCapabilityOwnerIdentity()
        let repository = FoundationIOSFailedHistoryJournalRepository(
            applicationSupportDirectoryURL: base
        )
        let store = IOSFailedHistoryStore(
            journal: repository,
            capabilityOwnerIdentity: ownerIdentity
        )
        let envelope = try IOSFailedHistoryEnvelope(
            revision: 1,
            entries: [try failedHistoryTestEntry()],
            audioCleanup: []
        )
        _ = try repository.create(
            envelope,
            authorization: IOSFailedHistoryJournalMutationAuthorization(
                testingToken: ()
            )
        )
        #expect(try await store.load() == envelope)

        let rootURL = base.appendingPathComponent("HoldType", isDirectory: true)
        let fileURL = IOSFailedHistoryStorageLocation.fileURL(in: base)
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
            IOSStrictProtectedRecordConfiguration.failedHistory.marker
        )
        var markerBytes = [UInt8](repeating: 0, count: marker.value.count + 1)
        let markerByteCount = marker.name.withCString { name in
            markerBytes.withUnsafeMutableBytes {
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
        #expect(markerByteCount == marker.value.count)
        #expect(Array(markerBytes.prefix(marker.value.count)) == marker.value)

        let preserved = try Data(contentsOf: fileURL)
        #expect(
            marker.name.withCString {
                Darwin.fremovexattr(validDescriptor, $0, 0)
            } == 0
        )
        await #expect(throws: IOSFailedHistoryError.readFailed) {
            _ = try await store.load()
        }
        #expect(try Data(contentsOf: fileURL) == preserved)

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
        await #expect(throws: IOSFailedHistoryError.readFailed) {
            _ = try await store.load()
        }
        #expect(try Data(contentsOf: fileURL) == preserved)
    }
}

private final class FailedHistoryStoreFixture: @unchecked Sendable {
    let ownerIdentity = IOSAcceptedHistoryCapabilityOwnerIdentity()
    let fileSystem = FailedHistoryFakeFileSystem()
    let repository: FoundationIOSFailedHistoryJournalRepository
    let store: IOSFailedHistoryStore

    init() {
        repository = FoundationIOSFailedHistoryJournalRepository(
            fileSystem: fileSystem,
            stagingMaintenance: { [fileSystem] now in
                try fileSystem.removeAbandonedTemporaryFiles(now: now)
            }
        )
        store = IOSFailedHistoryStore(
            journal: repository,
            capabilityOwnerIdentity: ownerIdentity,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    func install(_ envelope: IOSFailedHistoryEnvelope) throws {
        fileSystem.install(try IOSFailedHistoryWireCodec.encode(envelope))
        fileSystem.resetEvents()
    }
}
