import Darwin
import Foundation
import Testing
@testable import HoldTypePersistence

struct IOSProviderConsentJournalTests {
    @Test func missingFileIsPassiveAndDoesNotCreateDefaults() throws {
        let fileSystem = IOSProviderConsentStrictFileSystemFake()
        let journal = makeJournal(fileSystem: fileSystem)

        #expect(try journal.load() == nil)
        #expect(fileSystem.createCallCount == 0)
        #expect(fileSystem.replaceCallCount == 0)
        #expect(fileSystem.removeCallCount == 0)
    }

    @Test func readableFileRetainsItsPhysicalRevision() throws {
        let record = try fixtureRecord()
        let data = try IOSProviderConsentWireCodec.encode(record)
        let fileSystem = IOSProviderConsentStrictFileSystemFake(
            file: IOSStrictProtectedRecordFile(
                data: data,
                revision: IOSStrictProtectedRecordFileRevision(testingToken: 41)
            )
        )
        let journal = makeJournal(fileSystem: fileSystem)

        let loadedValue = try journal.load()
        let loaded = try #require(loadedValue)

        #expect(loaded.content == .readable(record))
        #expect(
            loaded.fileRevision ==
                IOSStrictProtectedRecordFileRevision(testingToken: 41)
        )
    }

    @Test func malformedAndFutureBytesStayUnchangedAndResettable() throws {
        let fixtures = [
            Data("not-json".utf8),
            Data(
                #"{"decisionAt":"2026-07-12T16:05:04.321Z","disclosureVersion":1,"epochID":"01234567-89ab-cdef-8123-456789abcdef","revision":7,"schemaVersion":2,"state":"accepted"}"#.utf8
            ),
        ]

        for fixture in fixtures {
            let revision = IOSStrictProtectedRecordFileRevision(testingToken: 8)
            let fileSystem = IOSProviderConsentStrictFileSystemFake(
                file: IOSStrictProtectedRecordFile(
                    data: fixture,
                    revision: revision
                )
            )
            let journal = makeJournal(fileSystem: fileSystem)

            let loadedValue = try journal.load()
            let loaded = try #require(loadedValue)

            #expect(loaded.content == .unreadable)
            #expect(fileSystem.file?.data == fixture)
            #expect(fileSystem.replaceCallCount == 0)

            try journal.removeUnreadable(expected: loaded)
            #expect(fileSystem.removeCallCount == 1)
            #expect(fileSystem.file == nil)
        }
    }

    @Test func oversizedOrMisconfiguredRegularFileUsesOpaqueRevision() throws {
        for error in [
            IOSStrictProtectedRecordFileSystemError.sourceTooLarge,
            .invalidFile,
        ] {
            let revision = IOSStrictProtectedRecordFileRevision(testingToken: 17)
            let fileSystem = IOSProviderConsentStrictFileSystemFake()
            fileSystem.readError = error
            fileSystem.opaqueRevision = revision
            let journal = makeJournal(fileSystem: fileSystem)

            let loadedValue = try journal.load()
            let loaded = try #require(loadedValue)

            #expect(loaded.content == .unreadable)
            #expect(loaded.fileRevision == revision)
        }
    }

    @Test func createAndReplaceUseStrictCanonicalBytesAndPhysicalCAS() throws {
        let fileSystem = IOSProviderConsentStrictFileSystemFake()
        let journal = makeJournal(fileSystem: fileSystem)
        let accepted = try fixtureRecord()

        let created = try journal.create(accepted)
        let createdBytes = try #require(fileSystem.file?.data)
        #expect(try IOSProviderConsentWireCodec.decode(createdBytes) == accepted)
        #expect(created.content == .readable(accepted))

        let withdrawn = IOSProviderConsentRecord(
            epochID: accepted.epochID,
            revision: 2,
            disclosureVersion: 1,
            state: .withdrawn,
            decisionAt: accepted.decisionAt.addingTimeInterval(1)
        )
        let replaced = try journal.replace(withdrawn, expected: created)

        #expect(fileSystem.replaceCallCount == 1)
        #expect(try IOSProviderConsentWireCodec.decode(
            try #require(fileSystem.file?.data)
        ) == withdrawn)
        #expect(replaced.content == .readable(withdrawn))

        #expect(throws: IOSProviderConsentJournalError.staleRevision) {
            _ = try journal.replace(accepted, expected: created)
        }
    }

    @Test func strictFileSystemFailuresMapWithoutRawDetails() throws {
        let record = try fixtureRecord()
        let cases: [(IOSStrictProtectedRecordFileSystemError, IOSProviderConsentJournalError)] = [
            (.destinationConflict, .staleRevision),
            (.protectedDataUnavailable, .localDataUnavailable),
            (.repositoryIdentityConflict, .localDataUnavailable),
            (.commitUncertain, .commitUncertain),
            (.synchronizationFailed, .commitUncertain),
            (.writeFailed, .mutationNotSaved),
        ]

        for (sourceError, expectedError) in cases {
            let fileSystem = IOSProviderConsentStrictFileSystemFake()
            fileSystem.createError = sourceError
            let journal = makeJournal(fileSystem: fileSystem)

            #expect(throws: expectedError) {
                _ = try journal.create(record)
            }
        }
    }

    @Test func requiredReconciliationBarrierIsObservableAndFailureIsUncertain() {
        let fileSystem = IOSProviderConsentStrictFileSystemFake()
        let calls = LockedCounter()
        let journal = FoundationIOSProviderConsentJournalRepository(
            fileSystem: fileSystem,
            directorySynchronization: {
                calls.increment()
            }
        )

        #expect(throws: Never.self) {
            try journal.synchronizeDirectory()
        }
        #expect(calls.value == 1)

        let failing = FoundationIOSProviderConsentJournalRepository(
            fileSystem: fileSystem,
            directorySynchronization: {
                throw IOSStrictProtectedRecordFileSystemError.synchronizationFailed
            }
        )
        #expect(throws: IOSProviderConsentJournalError.commitUncertain) {
            try failing.synchronizeDirectory()
        }
    }

    @Test func consentAdapterEnforcesBackupEligibilityInsteadOfExclusion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("consent")
        #expect(FileManager.default.createFile(atPath: fileURL.path, contents: Data()))
        let descriptor = Darwin.open(fileURL.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        #expect(descriptor >= 0)
        defer { Darwin.close(descriptor) }

        let name = "com.apple.metadata:com_apple_backup_excludeItem"
        let marker: [UInt8] = [1]
        let setResult = name.withCString { name in
            marker.withUnsafeBytes {
                Darwin.fsetxattr(
                    descriptor,
                    name,
                    $0.baseAddress,
                    $0.count,
                    0,
                    0
                )
            }
        }
        #expect(setResult == 0)

        let adapter = IOSProviderConsentBackupEligiblePOSIXAdapter()
        switch adapter.setExtendedAttribute(
            fileDescriptor: descriptor,
            name: name,
            value: marker,
            flags: 0
        ) {
        case .success:
            break
        case .failure:
            Issue.record("Expected backup-exclusion removal to succeed")
        }

        var byte: UInt8 = 0
        let readResult = name.withCString {
            Darwin.fgetxattr(descriptor, $0, &byte, 1, 0, 0)
        }
        #expect(readResult == -1)
        #expect(errno == ENOATTR)

        switch adapter.extendedAttribute(
            fileDescriptor: descriptor,
            name: name,
            maximumByteCount: 1_024
        ) {
        case .success(let value):
            #expect(!value.isEmpty)
        case .failure:
            Issue.record("Expected strict validation to recognize eligible backup policy")
        }
    }

    private func makeJournal(
        fileSystem: IOSProviderConsentStrictFileSystemFake
    ) -> FoundationIOSProviderConsentJournalRepository {
        FoundationIOSProviderConsentJournalRepository(
            fileSystem: fileSystem,
            directorySynchronization: {}
        )
    }

    private func fixtureRecord() throws -> IOSProviderConsentRecord {
        IOSProviderConsentRecord(
            epochID: UUID(uuidString: "01234567-89AB-CDEF-8123-456789ABCDEF")!,
            revision: 1,
            disclosureVersion: 1,
            state: .accepted,
            decisionAt: try IOSProviderConsentWireCodec.canonicalDate(
                Date(timeIntervalSince1970: 1_752_336_304.321)
            )
        )
    }
}

private final class IOSProviderConsentStrictFileSystemFake:
    IOSStrictProtectedRecordFileSystem,
    @unchecked Sendable {
    var file: IOSStrictProtectedRecordFile?
    var opaqueRevision: IOSStrictProtectedRecordFileRevision?
    var readError: IOSStrictProtectedRecordFileSystemError?
    var createError: IOSStrictProtectedRecordFileSystemError?
    var replaceError: IOSStrictProtectedRecordFileSystemError?
    var removeError: IOSStrictProtectedRecordFileSystemError?
    private(set) var createCallCount = 0
    private(set) var replaceCallCount = 0
    private(set) var removeCallCount = 0
    private var nextRevision: UInt64 = 100

    init(file: IOSStrictProtectedRecordFile? = nil) {
        self.file = file
        opaqueRevision = file?.revision
    }

    func readFileIfPresent() throws -> IOSStrictProtectedRecordFile? {
        if let readError { throw readError }
        return file
    }

    func readOpaqueFileRevisionIfPresent() throws
        -> IOSStrictProtectedRecordFileRevision? {
        opaqueRevision ?? file?.revision
    }

    func createFile(with data: Data) throws
        -> IOSStrictProtectedRecordFileRevision {
        createCallCount += 1
        if let createError { throw createError }
        guard file == nil else {
            throw IOSStrictProtectedRecordFileSystemError.destinationConflict
        }
        let revision = mintRevision()
        file = IOSStrictProtectedRecordFile(data: data, revision: revision)
        opaqueRevision = revision
        return revision
    }

    func replaceFile(
        with data: Data,
        expected: IOSStrictProtectedRecordFileRevision
    ) throws -> IOSStrictProtectedRecordFileRevision {
        replaceCallCount += 1
        if let replaceError { throw replaceError }
        guard file?.revision == expected else {
            throw IOSStrictProtectedRecordFileSystemError.staleRevision
        }
        let revision = mintRevision()
        file = IOSStrictProtectedRecordFile(data: data, revision: revision)
        opaqueRevision = revision
        return revision
    }

    func removeFile(
        expected: IOSStrictProtectedRecordFileRevision
    ) throws {
        try removeOpaqueFile(expected: expected)
    }

    func removeOpaqueFile(
        expected: IOSStrictProtectedRecordFileRevision
    ) throws {
        removeCallCount += 1
        if let removeError { throw removeError }
        guard opaqueRevision == expected || file?.revision == expected else {
            throw IOSStrictProtectedRecordFileSystemError.staleRevision
        }
        file = nil
        opaqueRevision = nil
    }

    private func mintRevision() -> IOSStrictProtectedRecordFileRevision {
        defer { nextRevision += 1 }
        return IOSStrictProtectedRecordFileRevision(testingToken: nextRevision)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int { lock.withLock { storedValue } }

    func increment() {
        lock.withLock {
            storedValue += 1
        }
    }
}
