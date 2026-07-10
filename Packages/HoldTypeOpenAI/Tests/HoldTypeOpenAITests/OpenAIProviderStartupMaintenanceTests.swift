import Darwin
import Foundation
import Testing
@testable import HoldTypeOpenAI

@MainActor
struct OpenAIProviderStartupMaintenanceTests {
    @Test func rawNameGrammarAndNanosecondAgeBoundariesAreExact() {
        let identifier = UUID(uuidString: "01234567-89AB-CDEF-8123-456789ABCDEF")!
        let v1 = "htmp-v1-01234567-89ab-cdef-8123-456789abcdef.multipart"
        let legacy = "01234567-89AB-CDEF-8123-456789ABCDEF.multipart"

        #expect(OpenAIMultipartScratchNamespace.v1FileName(for: identifier) == v1)
        #expect(OpenAIMultipartScratchNamespace.legacyFileName(for: identifier) == legacy)
        #expect(OpenAIMultipartScratchNamespace.identifier(inV1FileName: v1) == identifier)
        #expect(OpenAIMultipartScratchNamespace.identifier(inLegacyFileName: legacy) == identifier)
        #expect(
            OpenAIMultipartScratchNamespace.identifier(
                inV1FileName: "htmp-v1-01234567-89AB-CDEF-8123-456789ABCDEF.multipart"
            ) == nil
        )
        #expect(
            OpenAIMultipartScratchNamespace.identifier(
                inLegacyFileName: "01234567-89ab-cdef-8123-456789abcdef.multipart"
            ) == nil
        )
        #expect(OpenAIMultipartScratchNamespace.identifier(inV1FileName: v1 + ".old") == nil)
        #expect(OpenAIMultipartScratchNamespace.identifier(inLegacyFileName: "recording.m4a") == nil)

        let reference = OpenAIMultipartScratchTimestamp(seconds: 100_000, nanoseconds: 400)
        #expect(
            OpenAIMultipartScratchTimestamp(seconds: 96_400, nanoseconds: 400)
                .isAtLeast(3_600, before: reference)
        )
        #expect(
            !OpenAIMultipartScratchTimestamp(seconds: 96_400, nanoseconds: 401)
                .isAtLeast(3_600, before: reference)
        )
        #expect(
            OpenAIMultipartScratchTimestamp(seconds: 13_600, nanoseconds: 400)
                .isAtLeast(86_400, before: reference)
        )
        #expect(
            !OpenAIMultipartScratchTimestamp(seconds: 100_000, nanoseconds: 401)
                .isAtLeast(0, before: reference)
        )
    }

    @Test func scannerUsesExactOneHourAndTwentyFourHourThresholds() {
        let reference = OpenAIMultipartScratchTimestamp(seconds: 200_000, nanoseconds: 700)
        let v1AtThreshold = fakeCandidate(
            inode: 1,
            timestamp: .init(seconds: 196_400, nanoseconds: 700)
        )
        let v1OneNanosecondYoung = fakeCandidate(
            inode: 2,
            timestamp: .init(seconds: 196_400, nanoseconds: 701)
        )
        let legacyAtThreshold = fakeCandidate(
            inode: 3,
            timestamp: .init(seconds: 113_600, nanoseconds: 700)
        )
        let legacyOneNanosecondYoung = fakeCandidate(
            inode: 4,
            timestamp: .init(seconds: 113_600, nanoseconds: 701)
        )
        let validV1 = OpenAIMultipartScratchNamespace.v1FileName(for: UUID())
        let youngV1 = OpenAIMultipartScratchNamespace.v1FileName(for: UUID())
        let validLegacy = OpenAIMultipartScratchNamespace.legacyFileName(for: UUID())
        let youngLegacy = OpenAIMultipartScratchNamespace.legacyFileName(for: UUID())
        let malformed = validV1.uppercased()
        let directory = FakeScratchDirectory(
            entries: [validV1, youngV1, validLegacy, youngLegacy, malformed, "recording.m4a"],
            candidates: [
                validV1: v1AtThreshold,
                youngV1: v1OneNanosecondYoung,
                validLegacy: legacyAtThreshold,
                youngLegacy: legacyOneNanosecondYoung,
            ]
        )

        let summary = fakeScanner(directory: directory, reference: reference).run()

        #expect(summary.stopReason == .complete)
        #expect(summary.inspectedEntryCount == 6)
        #expect(summary.removedFileCount == 2)
        #expect(v1AtThreshold.wasRemoved)
        #expect(!v1OneNanosecondYoung.wasRemoved)
        #expect(legacyAtThreshold.wasRemoved)
        #expect(!legacyOneNanosecondYoung.wasRemoved)
        #expect(directory.openedNames.count == 4)
    }

    @Test func scannerHonorsExactEntryRemovalAndByteBoundaries() {
        let reference = OpenAIMultipartScratchTimestamp(seconds: 300_000, nanoseconds: 0)

        let entriesAtLimit = (0..<256).map { "unrelated-\($0)" }
        let exactEntryDirectory = FakeScratchDirectory(
            entries: entriesAtLimit,
            candidates: [:]
        )
        let entrySummary = fakeScanner(
            directory: exactEntryDirectory,
            reference: reference
        ).run()
        #expect(entrySummary.inspectedEntryCount == 256)
        #expect(entrySummary.stopReason == .entryLimit)

        var removalEntries: [String] = []
        var removalCandidates: [String: FakeScratchCandidate] = [:]
        for inode in 1...33 {
            let name = OpenAIMultipartScratchNamespace.legacyFileName(for: UUID())
            removalEntries.append(name)
            removalCandidates[name] = fakeCandidate(
                inode: UInt64(inode),
                byteCount: 0,
                timestamp: .init(seconds: 0, nanoseconds: 0)
            )
        }
        let removalSummary = fakeScanner(
            directory: FakeScratchDirectory(
                entries: removalEntries,
                candidates: removalCandidates
            ),
            reference: reference
        ).run()
        #expect(removalSummary.removedFileCount == 32)
        #expect(removalSummary.stopReason == .removalLimit)

        let exactByteName = OpenAIMultipartScratchNamespace.v1FileName(for: UUID())
        let overByteName = OpenAIMultipartScratchNamespace.v1FileName(for: UUID())
        let exactByteCandidate = fakeCandidate(
            inode: 100,
            byteCount: OpenAIMultipartScratchScavenger.maximumAccountedByteCount,
            timestamp: .init(seconds: 0, nanoseconds: 0)
        )
        let overByteCandidate = fakeCandidate(
            inode: 101,
            byteCount: 1,
            timestamp: .init(seconds: 0, nanoseconds: 0)
        )
        let byteSummary = fakeScanner(
            directory: FakeScratchDirectory(
                entries: [exactByteName, overByteName],
                candidates: [
                    exactByteName: exactByteCandidate,
                    overByteName: overByteCandidate,
                ]
            ),
            reference: reference
        ).run()
        #expect(byteSummary.stopReason == .byteLimit)
        #expect(
            byteSummary.accountedByteCount
                == OpenAIMultipartScratchScavenger.maximumAccountedByteCount
        )
        #expect(exactByteCandidate.wasRemoved)
        #expect(!overByteCandidate.wasRemoved)
    }

    @Test func elapsedOneSecondStopsBeforeNewWorkButOneNanosecondLessIsAllowed() {
        let reference = OpenAIMultipartScratchTimestamp(seconds: 1, nanoseconds: 0)
        let unavailable = FakeScratchFileSystem(directory: nil)
        let atBoundaryClock = ScriptedScratchClock(
            first: 0,
            remaining: OpenAIMultipartScratchScavenger.maximumElapsedNanoseconds
        )
        let atBoundary = OpenAIMultipartScratchScavenger(
            namespaceURL: URL(fileURLWithPath: "/unused"),
            fileSystem: unavailable,
            wallClock: { reference },
            monotonicClock: { atBoundaryClock.next() }
        ).run()
        #expect(atBoundary.stopReason == .timeLimit)

        let belowBoundaryClock = ScriptedScratchClock(
            first: 0,
            remaining: OpenAIMultipartScratchScavenger.maximumElapsedNanoseconds - 1
        )
        let belowBoundary = OpenAIMultipartScratchScavenger(
            namespaceURL: URL(fileURLWithPath: "/unused"),
            fileSystem: unavailable,
            wallClock: { reference },
            monotonicClock: { belowBoundaryClock.next() }
        ).run()
        #expect(belowBoundary.stopReason == .complete)
    }

    @Test func finalRacePreservesCandidateAndSummaryDoesNotExposeContent() {
        let name = OpenAIMultipartScratchNamespace.v1FileName(for: UUID())
        let raced = fakeCandidate(
            inode: 1,
            timestamp: .init(seconds: 0, nanoseconds: 0),
            allowFinalRemoval: false
        )
        let summary = fakeScanner(
            directory: FakeScratchDirectory(
                entries: [name],
                candidates: [name: raced]
            ),
            reference: .init(seconds: 10_000, nanoseconds: 0)
        ).run()

        #expect(summary.removedFileCount == 0)
        #expect(!raced.wasRemoved)
        let values = [String(describing: summary), String(reflecting: summary)]
        for value in values {
            #expect(!value.contains(name))
            #expect(!value.contains("10_000"))
            #expect(value.contains("redacted"))
        }
    }

    @Test func schedulerDispatchesOnlyOncePerProcessInstance() {
        let dispatch = CapturingScratchDispatch()
        let scheduler = OpenAIProviderStartupMaintenanceScheduler(
            dispatch: { operation in dispatch.append(operation) }
        )

        #expect(scheduler.schedule {})
        #expect(!scheduler.schedule {})
        #expect(dispatch.operationCount == 1)
    }

    @Test func missingOrSymlinkNamespaceIsNotCreatedOrRepaired() throws {
        let root = scratchTemporaryDirectory("maintenance-namespace")
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("missing", isDirectory: true)
        let missingSummary = OpenAIMultipartScratchScavenger(
            namespaceURL: missing,
            wallClock: { .init(seconds: 1, nanoseconds: 0) },
            monotonicClock: { 0 }
        ).run()
        #expect(missingSummary.stopReason == .complete)
        #expect(!FileManager.default.fileExists(atPath: missing.path))

        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        #expect(Darwin.chmod(target.path, 0o700) == 0)
        let symlink = root.appendingPathComponent("namespace-link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        _ = OpenAIMultipartScratchScavenger(
            namespaceURL: symlink,
            wallClock: { .init(seconds: 1, nanoseconds: 0) },
            monotonicClock: { 0 }
        ).run()
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func posixScannerDeletesOnlyEligibleOrphansAndHonorsCreatorLock() throws {
        let namespace = scratchTemporaryDirectory("maintenance-posix")
        defer { try? FileManager.default.removeItem(at: namespace) }
        #expect(Darwin.chmod(namespace.path, 0o700) == 0)

        let markedV1 = try makePOSIXScratch(
            in: namespace,
            name: OpenAIMultipartScratchNamespace.v1FileName(for: UUID()),
            marker: .exact
        )
        let legacy = try makePOSIXScratch(
            in: namespace,
            name: OpenAIMultipartScratchNamespace.legacyFileName(for: UUID())
        )
        let unmarkedV1 = try makePOSIXScratch(
            in: namespace,
            name: OpenAIMultipartScratchNamespace.v1FileName(for: UUID())
        )
        let wronglyMarkedV1 = try makePOSIXScratch(
            in: namespace,
            name: OpenAIMultipartScratchNamespace.v1FileName(for: UUID()),
            marker: .wrong
        )
        let hardLinkedV1 = try makePOSIXScratch(
            in: namespace,
            name: OpenAIMultipartScratchNamespace.v1FileName(for: UUID()),
            marker: .exact
        )
        let hardLinkPeer = namespace.appendingPathComponent("hard-link-peer")
        try FileManager.default.linkItem(at: hardLinkedV1, to: hardLinkPeer)

        let sourceM4A = try makePOSIXScratch(in: namespace, name: "recording.m4a")
        let sourceWAV = try makePOSIXScratch(in: namespace, name: "recording.wav")
        let symlinkName = OpenAIMultipartScratchNamespace.v1FileName(for: UUID())
        let symlink = namespace.appendingPathComponent(symlinkName)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: sourceM4A)

        let nested = namespace.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        let nestedScratch = try makePOSIXScratch(
            in: nested,
            name: OpenAIMultipartScratchNamespace.legacyFileName(for: UUID())
        )
        let exactDirectory = namespace.appendingPathComponent(
            OpenAIMultipartScratchNamespace.legacyFileName(for: UUID()),
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: exactDirectory,
            withIntermediateDirectories: false
        )

        let active = try makePOSIXScratch(
            in: namespace,
            name: OpenAIMultipartScratchNamespace.v1FileName(for: UUID()),
            marker: .exact
        )
        let activeDescriptor = Darwin.open(active.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        #expect(activeDescriptor >= 0)
        #expect(flock(activeDescriptor, LOCK_EX | LOCK_NB) == 0)

        var now = timespec()
        #expect(Darwin.clock_gettime(CLOCK_REALTIME, &now) == 0)
        let futureReference = OpenAIMultipartScratchTimestamp(
            seconds: Int64(now.tv_sec) + (48 * 60 * 60),
            nanoseconds: Int64(now.tv_nsec)
        )
        let scanner = OpenAIMultipartScratchScavenger(
            namespaceURL: namespace,
            wallClock: { futureReference },
            monotonicClock: { 0 }
        )

        let first = scanner.run()
        #expect(first.removedFileCount == 2)
        #expect(!FileManager.default.fileExists(atPath: markedV1.path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        for retained in [
            unmarkedV1, wronglyMarkedV1, hardLinkedV1, hardLinkPeer,
            sourceM4A, sourceWAV, symlink, nestedScratch, exactDirectory, active,
        ] {
            #expect(FileManager.default.fileExists(atPath: retained.path))
        }

        if activeDescriptor >= 0 {
            #expect(flock(activeDescriptor, LOCK_UN) == 0)
            Darwin.close(activeDescriptor)
        }
        let second = scanner.run()
        #expect(second.removedFileCount == 1)
        #expect(!FileManager.default.fileExists(atPath: active.path))
        let third = scanner.run()
        #expect(third.removedFileCount == 0)
    }

    @Test func posixFinalRecheckPreservesModeLinkAndAgeMutations() throws {
        for mutation in POSIXFinalScratchMutation.allCases {
            try verifyPOSIXFinalMutationIsPreserved(mutation)
        }
    }

    @Test func injectedAdapterRejectsFinalMarkerMutationAfterStableIdentity() {
        let adapter = FinalMutationScratchPOSIXAdapter(scenario: .marker)

        let summary = scanner(using: adapter).run()

        #expect(summary.removedFileCount == 0)
        #expect(adapter.markerReadCallCount == 3)
        #expect(adapter.finalDescriptorStatusWasRequested)
        #expect(adapter.unlinkCallCount == 0)
    }

    @Test func injectedAdapterRejectsFinalPathReplacementAfterStableDescriptor() {
        let adapter = FinalMutationScratchPOSIXAdapter(scenario: .pathIdentity)

        let summary = scanner(using: adapter).run()

        #expect(summary.removedFileCount == 0)
        #expect(adapter.finalDescriptorStatusWasRequested)
        #expect(adapter.pathStatusCallCount == 2)
        #expect(adapter.unlinkCallCount == 0)
    }

    @Test func injectedAdapterRejectsPostSnapshotGrowthBeyondByteBudget() {
        let adapter = FinalMutationScratchPOSIXAdapter(scenario: .sizeBeyondBudget)

        let summary = scanner(using: adapter).run()

        #expect(
            summary.accountedByteCount
                == OpenAIMultipartScratchScavenger.maximumAccountedByteCount
        )
        #expect(summary.removedFileCount == 0)
        #expect(adapter.finalDescriptorStatusWasRequested)
        #expect(adapter.pathStatusCallCount == 2)
        #expect(adapter.unlinkCallCount == 0)
    }

    @Test func lowLevelAdapterStopsBeforeDeadlineAndBeforeEINTRRetry() {
        let adapter = DeadlineScratchPOSIXAdapter(
            openResults: [.failure(EINTR), .success(10)]
        )
        let scanner = OpenAIMultipartScratchScavenger(
            namespaceURL: URL(fileURLWithPath: "/unused"),
            fileSystem: POSIXOpenAIMultipartScratchFileSystem(adapter: adapter),
            wallClock: { .init(seconds: 1, nanoseconds: 0) },
            monotonicClock: {
                adapter.openCallCount == 0
                    ? 0
                    : OpenAIMultipartScratchScavenger.maximumElapsedNanoseconds
            }
        )

        let summary = scanner.run()

        #expect(summary.stopReason == .timeLimit)
        #expect(adapter.openCallCount == 1)
        #expect(adapter.nonCleanupCallCount == 1)
    }

    @Test func lowLevelAdapterStopsWhenDeadlineCrossesBeforeFinalUnlink() throws {
        let namespace = scratchTemporaryDirectory("maintenance-unlink-deadline")
        defer { try? FileManager.default.removeItem(at: namespace) }
        #expect(Darwin.chmod(namespace.path, 0o700) == 0)
        let file = try makePOSIXScratch(
            in: namespace,
            name: OpenAIMultipartScratchNamespace.legacyFileName(for: UUID())
        )
        var now = timespec()
        #expect(Darwin.clock_gettime(CLOCK_REALTIME, &now) == 0)
        let reference = OpenAIMultipartScratchTimestamp(
            seconds: Int64(now.tv_sec) + (48 * 60 * 60),
            nanoseconds: Int64(now.tv_nsec)
        )
        let adapter = FinalUnlinkDeadlineScratchPOSIXAdapter()
        let scanner = OpenAIMultipartScratchScavenger(
            namespaceURL: namespace,
            fileSystem: POSIXOpenAIMultipartScratchFileSystem(adapter: adapter),
            wallClock: { reference },
            monotonicClock: {
                adapter.didCompleteFinalPathStatus
                    ? OpenAIMultipartScratchScavenger.maximumElapsedNanoseconds
                    : 0
            }
        )

        let summary = scanner.run()

        #expect(summary.stopReason == .timeLimit)
        #expect(adapter.unlinkCallCount == 0)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}

nonisolated private final class FakeScratchFileSystem: OpenAIMultipartScratchFileSystem {
    private let directory: FakeScratchDirectory?

    init(directory: FakeScratchDirectory?) {
        self.directory = directory
    }

    func openNamespace(
        at directoryURL: URL,
        shouldStartOperation: () -> Bool
    ) throws -> (any OpenAIMultipartScratchDirectory)? {
        guard shouldStartOperation() else {
            return nil
        }
        return directory
    }
}

nonisolated private final class FakeScratchDirectory: OpenAIMultipartScratchDirectory {
    private let lock = NSLock()
    private let entries: [String]
    private let candidates: [String: FakeScratchCandidate]
    private var index = 0
    private var storedOpenedNames: [String] = []

    var openedNames: [String] {
        lock.withLock { storedOpenedNames }
    }

    init(entries: [String], candidates: [String: FakeScratchCandidate]) {
        self.entries = entries
        self.candidates = candidates
    }

    func nextEntry(
        shouldStartOperation: () -> Bool
    ) throws -> OpenAIMultipartScratchDirectoryEntry? {
        guard shouldStartOperation() else {
            return nil
        }
        return lock.withLock {
            guard index < entries.count else {
                return nil
            }
            defer { index += 1 }
            return .name(entries[index])
        }
    }

    func openCandidate(
        named fileName: String,
        kind: OpenAIMultipartScratchKind,
        shouldStartOperation: () -> Bool
    ) throws -> (any OpenAIMultipartScratchCandidate)? {
        guard shouldStartOperation() else {
            return nil
        }
        lock.withLock { storedOpenedNames.append(fileName) }
        return candidates[fileName]
    }

    func close() {}
}

nonisolated private final class FakeScratchCandidate: OpenAIMultipartScratchCandidate {
    private let lock = NSLock()
    private let identity: OpenAITranscriptionFileIdentity
    private let allowFinalRemoval: Bool
    private var removed = false

    var wasRemoved: Bool {
        lock.withLock { removed }
    }

    init(identity: OpenAITranscriptionFileIdentity, allowFinalRemoval: Bool) {
        self.identity = identity
        self.allowFinalRemoval = allowFinalRemoval
    }

    func makeDeletionSnapshot(
        referenceTime: OpenAIMultipartScratchTimestamp,
        minimumAgeInSeconds: Int64,
        shouldStartOperation: () -> Bool
    ) -> OpenAIMultipartScratchDeletionSnapshot? {
        guard shouldStartOperation() else {
            return nil
        }
        let newest = max(
            OpenAIMultipartScratchTimestamp(
                seconds: identity.modificationSeconds,
                nanoseconds: identity.modificationNanoseconds
            ),
            OpenAIMultipartScratchTimestamp(
                seconds: identity.changeSeconds,
                nanoseconds: identity.changeNanoseconds
            )
        )
        guard newest.isAtLeast(minimumAgeInSeconds, before: referenceTime) else {
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
        guard shouldStartOperation(), allowFinalRemoval, snapshot.identity == identity else {
            return false
        }
        lock.withLock { removed = true }
        return true
    }

    func close() {}
}

nonisolated private final class ScriptedScratchClock: @unchecked Sendable {
    private let lock = NSLock()
    private let first: UInt64
    private let remaining: UInt64
    private var didReturnFirst = false

    init(first: UInt64, remaining: UInt64) {
        self.first = first
        self.remaining = remaining
    }

    func next() -> UInt64 {
        lock.withLock {
            guard didReturnFirst else {
                didReturnFirst = true
                return first
            }
            return remaining
        }
    }
}

nonisolated private final class CapturingScratchDispatch: @unchecked Sendable {
    private let lock = NSLock()
    private var operations: [@Sendable () -> Void] = []

    var operationCount: Int {
        lock.withLock { operations.count }
    }

    func append(_ operation: @escaping @Sendable () -> Void) {
        lock.withLock { operations.append(operation) }
    }
}

nonisolated private enum POSIXFinalScratchMutation: CaseIterable {
    case mode
    case linkCount
    case age
}

nonisolated private func verifyPOSIXFinalMutationIsPreserved(
    _ mutation: POSIXFinalScratchMutation
) throws {
    let namespace = scratchTemporaryDirectory("maintenance-final-\(mutation)")
    defer { try? FileManager.default.removeItem(at: namespace) }
    guard Darwin.chmod(namespace.path, 0o700) == 0 else {
        throw CocoaError(.fileWriteNoPermission)
    }

    let kind = OpenAIMultipartScratchKind.legacy
    let name = OpenAIMultipartScratchNamespace.legacyFileName(for: UUID())
    let file = try makePOSIXScratch(
        in: namespace,
        name: name
    )

    var now = timespec()
    guard Darwin.clock_gettime(CLOCK_REALTIME, &now) == 0 else {
        throw CocoaError(.fileReadUnknown)
    }
    let reference = OpenAIMultipartScratchTimestamp(
        seconds: Int64(now.tv_sec) + (48 * 60 * 60),
        nanoseconds: Int64(now.tv_nsec)
    )
    let fileSystem = POSIXOpenAIMultipartScratchFileSystem()
    guard let directory = try fileSystem.openNamespace(
        at: namespace,
        shouldStartOperation: { true }
    ) else {
        throw CocoaError(.fileReadNoPermission)
    }
    defer { directory.close() }
    guard let candidate = try directory.openCandidate(
        named: name,
        kind: kind,
        shouldStartOperation: { true }
    ) else {
        throw CocoaError(.fileReadNoPermission)
    }
    defer { candidate.close() }
    guard var snapshot = candidate.makeDeletionSnapshot(
        referenceTime: reference,
        minimumAgeInSeconds: kind.minimumAgeInSeconds,
        shouldStartOperation: { true }
    ) else {
        throw CocoaError(.fileReadUnknown)
    }

    switch mutation {
    case .mode:
        guard Darwin.chmod(file.path, 0o640) == 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
    case .linkCount:
        try FileManager.default.linkItem(
            at: file,
            to: namespace.appendingPathComponent("link-peer")
        )
    case .age:
        let futureDate = Date(timeIntervalSince1970: TimeInterval(reference.seconds + 1))
        try FileManager.default.setAttributes(
            [.modificationDate: futureDate],
            ofItemAtPath: file.path
        )
        var status = stat()
        guard Darwin.lstat(file.path, &status) == 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        snapshot = OpenAIMultipartScratchDeletionSnapshot(
            identity: fileIdentity(status),
            referenceTime: reference,
            minimumAgeInSeconds: kind.minimumAgeInSeconds
        )
    }

    let wasRemoved = candidate.removeIfUnchanged(
        snapshot,
        shouldStartOperation: { true }
    )

    #expect(!wasRemoved, "Mutation must be rejected: \(mutation)")
    #expect(
        FileManager.default.fileExists(atPath: file.path),
        "The candidate pathname must survive: \(mutation)"
    )
}

nonisolated private enum FinalMutationScratchScenario: Equatable {
    case marker
    case pathIdentity
    case sizeBeyondBudget

    var fileName: String {
        switch self {
        case .marker:
            "htmp-v1-01234567-89ab-cdef-8123-456789abcdef.multipart"
        case .pathIdentity, .sizeBeyondBudget:
            "01234567-89AB-CDEF-8123-456789ABCDEF.multipart"
        }
    }

    var snapshotByteCount: Int64 {
        switch self {
        case .marker, .pathIdentity:
            1
        case .sizeBeyondBudget:
            OpenAIMultipartScratchScavenger.maximumAccountedByteCount
        }
    }
}

nonisolated private func scanner(
    using adapter: FinalMutationScratchPOSIXAdapter
) -> OpenAIMultipartScratchScavenger {
    OpenAIMultipartScratchScavenger(
        namespaceURL: URL(fileURLWithPath: "/unused"),
        fileSystem: POSIXOpenAIMultipartScratchFileSystem(adapter: adapter),
        wallClock: { .init(seconds: 200_000, nanoseconds: 0) },
        monotonicClock: { 0 }
    )
}

nonisolated private final class FinalMutationScratchPOSIXAdapter:
    OpenAIMultipartScratchPOSIXAdapter,
    @unchecked Sendable {
    private static let namespaceDescriptor: Int32 = 10
    private static let directoryDescriptor: Int32 = 11
    private static let candidateDescriptor: Int32 = 20
    private static let effectiveUserID = uid_t(501)

    private let lock = NSLock()
    private let scenario: FinalMutationScratchScenario
    private var didReturnEntry = false
    private var descriptorStatusCalls = 0
    private var storedPathStatusCallCount = 0
    private var storedMarkerReadCallCount = 0
    private var storedUnlinkCallCount = 0

    init(scenario: FinalMutationScratchScenario) {
        self.scenario = scenario
    }

    var finalDescriptorStatusWasRequested: Bool {
        lock.withLock { descriptorStatusCalls >= 3 }
    }

    var pathStatusCallCount: Int {
        lock.withLock { storedPathStatusCallCount }
    }

    var markerReadCallCount: Int {
        lock.withLock { storedMarkerReadCallCount }
    }

    var unlinkCallCount: Int {
        lock.withLock { storedUnlinkCallCount }
    }

    func openFile(
        atPath path: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Int32> {
        .success(Self.namespaceDescriptor)
    }

    func fileStatus(
        for fileDescriptor: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<stat> {
        guard fileDescriptor == Self.candidateDescriptor else {
            return .success(scriptedScratchNamespaceStatus())
        }
        return lock.withLock {
            descriptorStatusCalls += 1
            return .success(
                scriptedScratchCandidateStatus(
                    inode: 100,
                    byteCount: scenario.snapshotByteCount
                )
            )
        }
    }

    func effectiveUserID() -> OpenAIMultipartScratchPOSIXCallResult<uid_t> {
        .success(Self.effectiveUserID)
    }

    func openDirectoryStream(
        for fileDescriptor: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<UnsafeMutablePointer<DIR>> {
        .success(UnsafeMutablePointer<DIR>(bitPattern: 1)!)
    }

    func nextDirectoryEntry(
        in stream: UnsafeMutablePointer<DIR>
    ) -> OpenAIMultipartScratchPOSIXCallResult<OpenAIMultipartScratchDirectoryEntry?> {
        lock.withLock {
            guard !didReturnEntry else {
                return .success(nil)
            }
            didReturnEntry = true
            return .success(.name(scenario.fileName))
        }
    }

    func directoryDescriptor(
        for stream: UnsafeMutablePointer<DIR>
    ) -> OpenAIMultipartScratchPOSIXCallResult<Int32> {
        .success(Self.directoryDescriptor)
    }

    func openFile(
        relativeTo directoryDescriptor: Int32,
        named fileName: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Int32> {
        .success(Self.candidateDescriptor)
    }

    func extendedAttribute(
        named name: String,
        on fileDescriptor: Int32,
        maximumByteCount: Int
    ) -> OpenAIMultipartScratchPOSIXCallResult<[UInt8]> {
        lock.withLock {
            storedMarkerReadCallCount += 1
            if scenario == .marker && storedMarkerReadCallCount >= 3 {
                return .success([])
            }
            return .success(OpenAIMultipartScratchNamespace.markerValue)
        }
    }

    func setExtendedAttribute(
        named name: String,
        value: [UInt8],
        on fileDescriptor: Int32,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Void> {
        .failure(EIO)
    }

    func lock(
        fileDescriptor: Int32,
        operation: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Void> {
        .success(())
    }

    func pathStatus(
        relativeTo directoryDescriptor: Int32,
        named fileName: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<stat> {
        lock.withLock {
            storedPathStatusCallCount += 1
            let inode: ino_t = scenario == .pathIdentity
                && storedPathStatusCallCount >= 2 ? 101 : 100
            let byteCount = scenario == .sizeBeyondBudget
                && storedPathStatusCallCount >= 2
                ? scenario.snapshotByteCount + 1
                : scenario.snapshotByteCount
            return .success(
                scriptedScratchCandidateStatus(
                    inode: inode,
                    byteCount: byteCount
                )
            )
        }
    }

    func unlink(
        relativeTo directoryDescriptor: Int32,
        named fileName: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Void> {
        lock.withLock { storedUnlinkCallCount += 1 }
        return .success(())
    }

    func closeFile(_ fileDescriptor: Int32) {}

    func closeDirectoryStream(_ stream: UnsafeMutablePointer<DIR>) {}

    private func scriptedScratchNamespaceStatus() -> stat {
        var status = stat()
        status.st_mode = S_IFDIR | mode_t(0o700)
        status.st_uid = Self.effectiveUserID
        return status
    }

    private func scriptedScratchCandidateStatus(
        inode: ino_t,
        byteCount: Int64
    ) -> stat {
        var status = stat()
        status.st_dev = 1
        status.st_ino = inode
        status.st_mode = S_IFREG | mode_t(0o600)
        status.st_nlink = 1
        status.st_uid = Self.effectiveUserID
        status.st_size = off_t(byteCount)
        status.st_mtimespec = timespec(tv_sec: 0, tv_nsec: 0)
        status.st_ctimespec = timespec(tv_sec: 0, tv_nsec: 0)
        return status
    }
}

nonisolated private final class DeadlineScratchPOSIXAdapter:
    OpenAIMultipartScratchPOSIXAdapter,
    @unchecked Sendable {
    private let lock = NSLock()
    private var openResults: [OpenAIMultipartScratchPOSIXCallResult<Int32>]
    private var storedOpenCallCount = 0
    private var storedNonCleanupCallCount = 0

    init(openResults: [OpenAIMultipartScratchPOSIXCallResult<Int32>]) {
        self.openResults = openResults
    }

    var openCallCount: Int {
        lock.withLock { storedOpenCallCount }
    }

    var nonCleanupCallCount: Int {
        lock.withLock { storedNonCleanupCallCount }
    }

    func openFile(
        atPath path: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Int32> {
        lock.withLock {
            storedOpenCallCount += 1
            storedNonCleanupCallCount += 1
            guard !openResults.isEmpty else {
                return .failure(EIO)
            }
            return openResults.removeFirst()
        }
    }

    func fileStatus(
        for fileDescriptor: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<stat> {
        unexpectedCall()
    }

    func effectiveUserID() -> OpenAIMultipartScratchPOSIXCallResult<uid_t> {
        unexpectedCall()
    }

    func openDirectoryStream(
        for fileDescriptor: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<UnsafeMutablePointer<DIR>> {
        unexpectedCall()
    }

    func nextDirectoryEntry(
        in stream: UnsafeMutablePointer<DIR>
    ) -> OpenAIMultipartScratchPOSIXCallResult<OpenAIMultipartScratchDirectoryEntry?> {
        unexpectedCall()
    }

    func directoryDescriptor(
        for stream: UnsafeMutablePointer<DIR>
    ) -> OpenAIMultipartScratchPOSIXCallResult<Int32> {
        unexpectedCall()
    }

    func openFile(
        relativeTo directoryDescriptor: Int32,
        named fileName: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Int32> {
        unexpectedCall()
    }

    func extendedAttribute(
        named name: String,
        on fileDescriptor: Int32,
        maximumByteCount: Int
    ) -> OpenAIMultipartScratchPOSIXCallResult<[UInt8]> {
        unexpectedCall()
    }

    func setExtendedAttribute(
        named name: String,
        value: [UInt8],
        on fileDescriptor: Int32,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Void> {
        unexpectedCall()
    }

    func lock(
        fileDescriptor: Int32,
        operation: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Void> {
        unexpectedCall()
    }

    func pathStatus(
        relativeTo directoryDescriptor: Int32,
        named fileName: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<stat> {
        unexpectedCall()
    }

    func unlink(
        relativeTo directoryDescriptor: Int32,
        named fileName: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Void> {
        unexpectedCall()
    }

    func closeFile(_ fileDescriptor: Int32) {}

    func closeDirectoryStream(_ stream: UnsafeMutablePointer<DIR>) {}

    private func unexpectedCall<Value>() -> OpenAIMultipartScratchPOSIXCallResult<Value> {
        lock.withLock { storedNonCleanupCallCount += 1 }
        return .failure(EIO)
    }
}

nonisolated private final class FinalUnlinkDeadlineScratchPOSIXAdapter:
    OpenAIMultipartScratchPOSIXAdapter,
    @unchecked Sendable {
    private let lock = NSLock()
    private let base = DarwinOpenAIMultipartScratchPOSIXAdapter()
    private var pathStatusCallCount = 0
    private var storedUnlinkCallCount = 0

    var didCompleteFinalPathStatus: Bool {
        lock.withLock { pathStatusCallCount >= 2 }
    }

    var unlinkCallCount: Int {
        lock.withLock { storedUnlinkCallCount }
    }

    func openFile(
        atPath path: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Int32> {
        base.openFile(atPath: path, flags: flags)
    }

    func fileStatus(
        for fileDescriptor: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<stat> {
        base.fileStatus(for: fileDescriptor)
    }

    func effectiveUserID() -> OpenAIMultipartScratchPOSIXCallResult<uid_t> {
        base.effectiveUserID()
    }

    func openDirectoryStream(
        for fileDescriptor: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<UnsafeMutablePointer<DIR>> {
        base.openDirectoryStream(for: fileDescriptor)
    }

    func nextDirectoryEntry(
        in stream: UnsafeMutablePointer<DIR>
    ) -> OpenAIMultipartScratchPOSIXCallResult<OpenAIMultipartScratchDirectoryEntry?> {
        base.nextDirectoryEntry(in: stream)
    }

    func directoryDescriptor(
        for stream: UnsafeMutablePointer<DIR>
    ) -> OpenAIMultipartScratchPOSIXCallResult<Int32> {
        base.directoryDescriptor(for: stream)
    }

    func openFile(
        relativeTo directoryDescriptor: Int32,
        named fileName: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Int32> {
        base.openFile(
            relativeTo: directoryDescriptor,
            named: fileName,
            flags: flags
        )
    }

    func extendedAttribute(
        named name: String,
        on fileDescriptor: Int32,
        maximumByteCount: Int
    ) -> OpenAIMultipartScratchPOSIXCallResult<[UInt8]> {
        base.extendedAttribute(
            named: name,
            on: fileDescriptor,
            maximumByteCount: maximumByteCount
        )
    }

    func setExtendedAttribute(
        named name: String,
        value: [UInt8],
        on fileDescriptor: Int32,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Void> {
        base.setExtendedAttribute(
            named: name,
            value: value,
            on: fileDescriptor,
            flags: flags
        )
    }

    func lock(
        fileDescriptor: Int32,
        operation: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Void> {
        base.lock(fileDescriptor: fileDescriptor, operation: operation)
    }

    func pathStatus(
        relativeTo directoryDescriptor: Int32,
        named fileName: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<stat> {
        let result = base.pathStatus(
            relativeTo: directoryDescriptor,
            named: fileName,
            flags: flags
        )
        lock.withLock { pathStatusCallCount += 1 }
        return result
    }

    func unlink(
        relativeTo directoryDescriptor: Int32,
        named fileName: String,
        flags: Int32
    ) -> OpenAIMultipartScratchPOSIXCallResult<Void> {
        lock.withLock { storedUnlinkCallCount += 1 }
        return base.unlink(
            relativeTo: directoryDescriptor,
            named: fileName,
            flags: flags
        )
    }

    func closeFile(_ fileDescriptor: Int32) {
        base.closeFile(fileDescriptor)
    }

    func closeDirectoryStream(_ stream: UnsafeMutablePointer<DIR>) {
        base.closeDirectoryStream(stream)
    }
}

nonisolated private enum POSIXScratchMarker {
    case none
    case exact
    case wrong
}

nonisolated private func fakeScanner(
    directory: FakeScratchDirectory,
    reference: OpenAIMultipartScratchTimestamp
) -> OpenAIMultipartScratchScavenger {
    OpenAIMultipartScratchScavenger(
        namespaceURL: URL(fileURLWithPath: "/unused"),
        fileSystem: FakeScratchFileSystem(directory: directory),
        wallClock: { reference },
        monotonicClock: { 0 }
    )
}

nonisolated private func fakeCandidate(
    inode: UInt64,
    byteCount: Int64 = 1,
    timestamp: OpenAIMultipartScratchTimestamp,
    allowFinalRemoval: Bool = true
) -> FakeScratchCandidate {
    FakeScratchCandidate(
        identity: OpenAITranscriptionFileIdentity(
            device: 1,
            inode: inode,
            byteCount: byteCount,
            modificationSeconds: timestamp.seconds,
            modificationNanoseconds: timestamp.nanoseconds,
            changeSeconds: timestamp.seconds,
            changeNanoseconds: timestamp.nanoseconds
        ),
        allowFinalRemoval: allowFinalRemoval
    )
}

nonisolated private func scratchTemporaryDirectory(_ prefix: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "\(prefix)-\(UUID().uuidString)",
        isDirectory: true
    )
    try! FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: false
    )
    return url
}

nonisolated private func makePOSIXScratch(
    in directory: URL,
    name: String,
    marker: POSIXScratchMarker = .none
) throws -> URL {
    let url = directory.appendingPathComponent(name, isDirectory: false)
    #expect(FileManager.default.createFile(atPath: url.path, contents: Data([1])))
    #expect(Darwin.chmod(url.path, 0o600) == 0)
    guard marker != .none else {
        return url
    }
    let descriptor = Darwin.open(url.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
    guard descriptor >= 0 else {
        throw CocoaError(.fileReadNoPermission)
    }
    defer { Darwin.close(descriptor) }
    switch marker {
    case .none:
        break
    case .exact:
        #expect(OpenAIMultipartScratchNamespace.installMarker(on: descriptor))
    case .wrong:
        let wrong = Array("v2".utf8)
        let result = OpenAIMultipartScratchNamespace.markerName.withCString { name in
            wrong.withUnsafeBytes { bytes in
                Darwin.fsetxattr(
                    descriptor,
                    name,
                    bytes.baseAddress,
                    bytes.count,
                    0,
                    XATTR_CREATE
                )
            }
        }
        #expect(result == 0)
    }
    return url
}
