import CoreFoundation
import Darwin
import Foundation
import HoldTypeDomain

protocol IOSPendingRecordingJournalStoring: Sendable {
    func load() throws -> IOSPendingRecording?
    func loadMetadataSnapshot(
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws
        -> IOSPendingRecordingJournalMetadataSnapshot?
    func create(_ recording: IOSPendingRecording) throws
    func create(
        _ recording: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws
    func replace(
        _ recording: IOSPendingRecording,
        expected: IOSPendingRecording
    ) throws
    func replace(
        _ recording: IOSPendingRecording,
        expected: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws
    func remove(expected: IOSPendingRecording) throws -> Bool
    func remove(
        expected: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> Bool
    func removeMetadata(
        expected: IOSPendingRecordingJournalMetadataSnapshot,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence
    func proveMetadataAbsent(
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence
}

extension IOSPendingRecordingJournalStoring {
    func loadMetadataSnapshot(
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws
        -> IOSPendingRecordingJournalMetadataSnapshot? {
        _ = authorization
        throw IOSPendingRecordingError.journalUnreadable
    }

    func create(
        _ recording: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws {
        _ = expectedRepositoryRoot
        try create(recording)
    }

    func replace(
        _ recording: IOSPendingRecording,
        expected: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws {
        _ = expectedRepositoryRoot
        try replace(recording, expected: expected)
    }

    func remove(
        expected: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> Bool {
        _ = expectedRepositoryRoot
        return try remove(expected: expected)
    }

    func removeMetadata(
        expected: IOSPendingRecordingJournalMetadataSnapshot,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence {
        _ = expected
        _ = expectedRepositoryRoot
        _ = authorization
        throw IOSPendingRecordingError.journalRemoveFailed
    }

    func proveMetadataAbsent(
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence {
        _ = expectedRepositoryRoot
        _ = authorization
        throw IOSPendingRecordingError.journalRemoveFailed
    }
}

/// Canonicalizes runtime dates to the journal's UTC millisecond precision.
enum IOSPendingRecordingTimestampCodec {
    private static let millisecondsPerSecond = 1_000.0

    static func canonicalDate(from date: Date) throws -> Date {
        let seconds = date.timeIntervalSince1970
        let scaled = seconds * millisecondsPerSecond
        guard seconds.isFinite,
              scaled.isFinite,
              scaled >= Double(Int64.min),
              scaled <= Double(Int64.max) else {
            throw IOSPendingRecordingError.invalidJournal
        }

        let milliseconds = Int64(
            scaled.rounded(.toNearestOrAwayFromZero)
        )
        let canonical = Date(
            timeIntervalSince1970: Double(milliseconds) / millisecondsPerSecond
        )
        guard canonical.timeIntervalSinceReferenceDate.isFinite else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return canonical
    }

    static func string(from date: Date) throws -> String {
        let canonical = try canonicalDate(from: date)
        let formatter = makeFormatter()
        let value = formatter.string(from: canonical)
        guard value.utf8.count == 24,
              value.hasSuffix("Z"),
              formatter.date(from: value) == canonical else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return value
    }

    static func date(from value: String) throws -> Date {
        guard value.utf8.count == 24,
              value.hasSuffix("Z") else {
            throw IOSPendingRecordingError.invalidJournal
        }
        let formatter = makeFormatter()
        guard let parsed = formatter.date(from: value),
              formatter.string(from: parsed) == value,
              try canonicalDate(from: parsed) == parsed else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return parsed
    }

    private static func makeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

enum IOSPendingRecordingJournalFileSystemError: Error, Equatable, Sendable {
    case invalidLocation
    case repositoryIdentityConflict
    case sourceTooLarge
    case missing
    case destinationConflict
    case staleRevision
    case protectedDataUnavailable
    case invalidFile
    case readFailed
    case writeFailed
    case synchronizationFailed
    case commitUncertain
    case removeFailed
}

struct IOSPendingRecordingJournalFileRevision: Equatable, Sendable {
    fileprivate let snapshot: IOSPendingRecordingJournalFileSnapshot?
    private let testingToken: UInt64?

    fileprivate init(snapshot: IOSPendingRecordingJournalFileSnapshot) {
        self.snapshot = snapshot
        testingToken = nil
    }

    /// Narrow seam for repository tests; live commits always use a stat snapshot.
    init(testingToken: UInt64) {
        snapshot = nil
        self.testingToken = testingToken
    }
}

struct IOSPendingRecordingJournalFile: Equatable, Sendable {
    let data: Data
    let revision: IOSPendingRecordingJournalFileRevision
}

/// Opaque identity for the one canonical PendingRecording metadata path and
/// strict-record policy. It deliberately carries no caller-provided strings.
struct IOSPendingRecordingJournalCanonicalPathIdentity:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    private let value: UInt8

    fileprivate static let pendingRecording = Self(value: 1)

    private init(value: UInt8) {
        self.value = value
    }

    var description: String {
        "IOSPendingRecordingJournalCanonicalPathIdentity(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSPendingRecordingJournalMetadataFile:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    let file: IOSPendingRecordingJournalFile
    let pathIdentity: IOSPendingRecordingJournalCanonicalPathIdentity

    var description: String {
        "IOSPendingRecordingJournalMetadataFile(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Sealed metadata observation used only by the failed-History ownership
/// transfer. It retains the decoded value and the exact physical file revision.
struct IOSPendingRecordingJournalMetadataSnapshot:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    let recording: IOSPendingRecording
    fileprivate let fileRevision: IOSPendingRecordingJournalFileRevision

    var description: String {
        "IOSPendingRecordingJournalMetadataSnapshot(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    fileprivate init(
        recording: IOSPendingRecording,
        fileRevision: IOSPendingRecordingJournalFileRevision
    ) {
        self.recording = recording
        self.fileRevision = fileRevision
    }

    #if DEBUG
    init(
        testingRecording: IOSPendingRecording,
        testingRevision: UInt64
    ) {
        recording = testingRecording
        fileRevision = IOSPendingRecordingJournalFileRevision(
            testingToken: testingRevision
        )
    }
    #endif
}

struct IOSPendingRecordingJournalDirectoryIdentity:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    let device: dev_t
    let inode: ino_t

    var description: String {
        "IOSPendingRecordingJournalDirectoryIdentity(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    fileprivate init(_ status: stat) {
        device = status.st_dev
        inode = status.st_ino
    }

    fileprivate init(device: dev_t, inode: ino_t) {
        self.device = device
        self.inode = inode
    }
}

/// Proof that the one PendingRecording metadata path was absent on both sides
/// of a successful directory durability barrier. The already-absent case has
/// no source revision to invent.
enum IOSPendingRecordingJournalMetadataAbsenceEvidence:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    struct Binding:
        Equatable,
        Sendable,
        CustomStringConvertible,
        CustomDebugStringConvertible,
        CustomReflectable {
        let repositoryRoot: IOSPersistenceRepositoryRootIdentity
        let journalDirectory: IOSPendingRecordingJournalDirectoryIdentity
        let pathIdentity: IOSPendingRecordingJournalCanonicalPathIdentity

        var description: String {
            "IOSPendingRecordingJournalMetadataAbsenceEvidence.Binding(redacted)"
        }
        var debugDescription: String { description }
        var customMirror: Mirror { Mirror(self, children: [:]) }

        fileprivate init(
            repositoryRoot: IOSPersistenceRepositoryRootIdentity,
            journalDirectory: IOSPendingRecordingJournalDirectoryIdentity,
            pathIdentity: IOSPendingRecordingJournalCanonicalPathIdentity
        ) {
            self.repositoryRoot = repositoryRoot
            self.journalDirectory = journalDirectory
            self.pathIdentity = pathIdentity
        }
    }

    struct Removed:
        Equatable,
        Sendable,
        CustomStringConvertible,
        CustomDebugStringConvertible,
        CustomReflectable {
        fileprivate let sourceRevision: IOSPendingRecordingJournalFileRevision
        let binding: Binding

        var description: String {
            "IOSPendingRecordingJournalMetadataAbsenceEvidence.Removed(redacted)"
        }
        var debugDescription: String { description }
        var customMirror: Mirror { Mirror(self, children: [:]) }

        fileprivate init(
            sourceRevision: IOSPendingRecordingJournalFileRevision,
            binding: Binding
        ) {
            self.sourceRevision = sourceRevision
            self.binding = binding
        }
    }

    struct AlreadyAbsent:
        Equatable,
        Sendable,
        CustomStringConvertible,
        CustomDebugStringConvertible,
        CustomReflectable {
        let binding: Binding

        var description: String {
            "IOSPendingRecordingJournalMetadataAbsenceEvidence.AlreadyAbsent(redacted)"
        }
        var debugDescription: String { description }
        var customMirror: Mirror { Mirror(self, children: [:]) }

        fileprivate init(binding: Binding) {
            self.binding = binding
        }
    }

    case removed(Removed)
    case alreadyAbsent(AlreadyAbsent)

    var description: String {
        "IOSPendingRecordingJournalMetadataAbsenceEvidence(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    var binding: Binding {
        switch self {
        case .removed(let evidence): evidence.binding
        case .alreadyAbsent(let evidence): evidence.binding
        }
    }

    func provesRemoval(
        of snapshot: IOSPendingRecordingJournalMetadataSnapshot
    ) -> Bool {
        guard case .removed(let evidence) = self else { return false }
        return evidence.sourceRevision == snapshot.fileRevision
    }

    var provesPreexistingAbsence: Bool {
        if case .alreadyAbsent = self { return true }
        return false
    }

    var provesCanonicalPendingRecordingPath: Bool {
        binding.pathIdentity == .pendingRecording
    }

    #if DEBUG
    init(
        testingRemoved source:
            IOSPendingRecordingJournalMetadataSnapshot,
        repositoryRoot: IOSPersistenceRepositoryRootIdentity =
            IOSPersistenceRepositoryRootIdentity(device: 1, inode: 1)
    ) {
        self = .removed(
            Removed(
                sourceRevision: source.fileRevision,
                binding: Binding(
                    repositoryRoot: repositoryRoot,
                    journalDirectory:
                        IOSPendingRecordingJournalDirectoryIdentity(
                            device: 1,
                            inode: 2
                        ),
                    pathIdentity: .pendingRecording
                )
            )
        )
    }

    init(
        testingAlreadyAbsentRepositoryRoot repositoryRoot:
            IOSPersistenceRepositoryRootIdentity =
                IOSPersistenceRepositoryRootIdentity(device: 1, inode: 1)
    ) {
        self = .alreadyAbsent(
            AlreadyAbsent(
                binding: Binding(
                    repositoryRoot: repositoryRoot,
                    journalDirectory:
                        IOSPendingRecordingJournalDirectoryIdentity(
                            device: 1,
                            inode: 2
                        ),
                    pathIdentity: .pendingRecording
                )
            )
        )
    }
    #endif
}

/// Descriptor-derived identity durably attached to the exact Pending journal
/// before an audio unlink. It contains no transcript or provider payload.
struct IOSPendingRecordingAudioRemovalPhysicalSnapshot: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let byteCount: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
    let statusChangeSeconds: Int64
    let statusChangeNanoseconds: Int64

    init(_ value: stat) {
        device = UInt64(truncatingIfNeeded: value.st_dev)
        inode = UInt64(truncatingIfNeeded: value.st_ino)
        byteCount = Int64(value.st_size)
        modificationSeconds = Int64(value.st_mtimespec.tv_sec)
        modificationNanoseconds = Int64(value.st_mtimespec.tv_nsec)
        statusChangeSeconds = Int64(value.st_ctimespec.tv_sec)
        statusChangeNanoseconds = Int64(value.st_ctimespec.tv_nsec)
    }

    init?(
        device: UInt64,
        inode: UInt64,
        byteCount: Int64,
        modificationSeconds: Int64,
        modificationNanoseconds: Int64,
        statusChangeSeconds: Int64,
        statusChangeNanoseconds: Int64
    ) {
        guard inode > 0,
              byteCount > 0,
              modificationNanoseconds >= 0,
              modificationNanoseconds < 1_000_000_000,
              statusChangeNanoseconds >= 0,
              statusChangeNanoseconds < 1_000_000_000 else {
            return nil
        }
        self.device = device
        self.inode = inode
        self.byteCount = byteCount
        self.modificationSeconds = modificationSeconds
        self.modificationNanoseconds = modificationNanoseconds
        self.statusChangeSeconds = statusChangeSeconds
        self.statusChangeNanoseconds = statusChangeNanoseconds
    }
}

struct IOSPendingRecordingAudioRemovalIntent: Equatable, Sendable {
    static let extendedAttributeName =
        "com.holdtype.ios.pending-audio-removal"
    static let encodedByteCount = 50

    let purpose: IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization.Purpose
    let recording: IOSPendingRecording
    let physicalSnapshot: IOSPendingRecordingAudioRemovalPhysicalSnapshot

    init?(
        purpose: IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization.Purpose,
        recording: IOSPendingRecording,
        physicalSnapshot: IOSPendingRecordingAudioRemovalPhysicalSnapshot
    ) {
        let phaseIsEligible = switch purpose {
        case .acceptedOutput:
            recording.phase == .outputDelivery
        case .discard:
            recording.phase == .readyForTranscription
                || recording.phase == .awaitingRecovery
        }
        guard phaseIsEligible,
              physicalSnapshot.byteCount == recording.byteCount else {
            return nil
        }
        self.purpose = purpose
        self.recording = recording
        self.physicalSnapshot = physicalSnapshot
    }
}

extension IOSPendingRecordingAudioRemovalIntent:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSPendingRecordingAudioRemovalIntent(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSPendingRecordingAudioRemovalIntentSnapshot: Equatable, Sendable {
    let intent: IOSPendingRecordingAudioRemovalIntent
    let journalRevision: IOSPendingRecordingJournalFileRevision
}

struct IOSPendingRecordingAudioRemovalIntentAuthorization:
    Equatable,
    Sendable {
    fileprivate init() {}

    #if DEBUG
    init(testingToken: Void) {}
    #endif
}

protocol IOSPendingRecordingAudioRemovalIntentStoring: Sendable {
    func load(
        expected recording: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingAudioRemovalIntentSnapshot?
    func commit(
        _ intent: IOSPendingRecordingAudioRemovalIntent,
        expected recording: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingAudioRemovalIntentSnapshot
}

/// Generic proof that one configured strict-record path was absent on both
/// sides of a successful directory durability barrier. It is intentionally
/// content-free so a record-specific journal can bind it to its own opaque
/// cleanup capability without decoding unavailable or tombstoned bytes.
struct IOSStrictProtectedRecordAbsenceEvidence: Equatable, Sendable {
    let repositoryRoot: IOSPersistenceRepositoryRootIdentity
    let recordDirectory: IOSPendingRecordingJournalDirectoryIdentity
    let configuration: IOSStrictProtectedRecordConfiguration

    init(
        repositoryRoot: IOSPersistenceRepositoryRootIdentity,
        recordDirectory: IOSPendingRecordingJournalDirectoryIdentity,
        configuration: IOSStrictProtectedRecordConfiguration
    ) {
        self.repositoryRoot = repositoryRoot
        self.recordDirectory = recordDirectory
        self.configuration = configuration
    }

    #if DEBUG
    init(testingConfiguration configuration: IOSStrictProtectedRecordConfiguration) {
        repositoryRoot = IOSPersistenceRepositoryRootIdentity(
            device: 1,
            inode: 1
        )
        recordDirectory = IOSPendingRecordingJournalDirectoryIdentity(
            device: 1,
            inode: 2
        )
        self.configuration = configuration
    }
    #endif
}

extension IOSStrictProtectedRecordAbsenceEvidence:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSStrictProtectedRecordAbsenceEvidence(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

protocol IOSPendingRecordingJournalFileSystem: Sendable {
    func readFileIfPresent() throws -> IOSPendingRecordingJournalFile?
    func readMetadataFileIfPresent(
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataFile?
    func readOpaqueFileRevisionIfPresent() throws
        -> IOSPendingRecordingJournalFileRevision?
    func createFile(with data: Data) throws -> IOSPendingRecordingJournalFileRevision
    func createFile(
        with data: Data,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingJournalFileRevision
    func replaceFile(
        with data: Data,
        expected: IOSPendingRecordingJournalFileRevision
    ) throws -> IOSPendingRecordingJournalFileRevision
    func replaceFile(
        with data: Data,
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingJournalFileRevision
    func removeFile(
        expected: IOSPendingRecordingJournalFileRevision
    ) throws
    func removeFile(
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws
    func removeOpaqueFile(
        expected: IOSPendingRecordingJournalFileRevision
    ) throws
    func removeMetadataFile(
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence
    func proveMetadataFileAbsent(
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence
    func proveCanonicalFileAbsent(
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSStrictProtectedRecordAbsenceEvidence
    func readAudioRemovalIntent(
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingAudioRemovalIntentAuthorization
    ) throws -> Data?
    func writeAudioRemovalIntent(
        _ data: Data,
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        createOnly: Bool,
        authorization: IOSPendingRecordingAudioRemovalIntentAuthorization
    ) throws -> IOSPendingRecordingJournalFileRevision
}

extension IOSPendingRecordingJournalFileSystem {
    func readMetadataFileIfPresent(
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataFile? {
        _ = authorization
        throw IOSPendingRecordingJournalFileSystemError.invalidLocation
    }

    func createFile(
        with data: Data,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingJournalFileRevision {
        _ = expectedRepositoryRoot
        return try createFile(with: data)
    }

    func replaceFile(
        with data: Data,
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingJournalFileRevision {
        _ = expectedRepositoryRoot
        return try replaceFile(with: data, expected: expected)
    }

    func removeFile(
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws {
        _ = expectedRepositoryRoot
        try removeFile(expected: expected)
    }

    func readOpaqueFileRevisionIfPresent() throws
        -> IOSPendingRecordingJournalFileRevision? {
        try readFileIfPresent()?.revision
    }

    func removeOpaqueFile(
        expected: IOSPendingRecordingJournalFileRevision
    ) throws {
        try removeFile(expected: expected)
    }

    func removeMetadataFile(
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence {
        _ = expected
        _ = expectedRepositoryRoot
        _ = authorization
        throw IOSPendingRecordingJournalFileSystemError.invalidLocation
    }

    func proveMetadataFileAbsent(
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence {
        _ = expectedRepositoryRoot
        _ = authorization
        throw IOSPendingRecordingJournalFileSystemError.invalidLocation
    }

    func proveCanonicalFileAbsent(
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSStrictProtectedRecordAbsenceEvidence {
        _ = expectedRepositoryRoot
        throw IOSPendingRecordingJournalFileSystemError.invalidLocation
    }

    func readAudioRemovalIntent(
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingAudioRemovalIntentAuthorization
    ) throws -> Data? {
        _ = expected
        _ = expectedRepositoryRoot
        _ = authorization
        throw IOSPendingRecordingJournalFileSystemError.invalidLocation
    }

    func writeAudioRemovalIntent(
        _ data: Data,
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        createOnly: Bool,
        authorization: IOSPendingRecordingAudioRemovalIntentAuthorization
    ) throws -> IOSPendingRecordingJournalFileRevision {
        _ = data
        _ = expected
        _ = expectedRepositoryRoot
        _ = createOnly
        _ = authorization
        throw IOSPendingRecordingJournalFileSystemError.invalidLocation
    }
}

typealias IOSStrictProtectedRecordFileSystemError =
    IOSPendingRecordingJournalFileSystemError
typealias IOSStrictProtectedRecordFileRevision =
    IOSPendingRecordingJournalFileRevision
typealias IOSStrictProtectedRecordFile = IOSPendingRecordingJournalFile
typealias IOSStrictProtectedRecordFileSystem =
    IOSPendingRecordingJournalFileSystem

/// Physical policy for one crash-safe protected record in the app-private
/// HoldType directory. The legacy journal file system is parameterized by this
/// value so mandatory records can share its strict durability boundary without
/// using the best-effort metadata writer.
struct IOSStrictProtectedRecordConfiguration: Equatable, Sendable {
    struct Marker: Equatable, Sendable {
        let name: String
        let value: [UInt8]
    }

    static let pendingRecording = Self(
        rootDirectoryName: IOSPendingRecordingStorageLocation.rootDirectoryName,
        fileName: IOSPendingRecordingStorageLocation.journalFileName,
        maximumByteCount:
            FoundationIOSPendingRecordingJournalRepository.maximumJournalByteCount,
        marker: nil
    )

    let rootDirectoryName: String
    let fileName: String
    let maximumByteCount: Int
    let marker: Marker?
}

struct IOSStrictProtectedRecordMaintenanceReport: Equatable, Sendable {
    let inspectedEntryCount: Int
    let inspectedByteCount: Int64
    let removedFileCount: Int
    let removedByteCount: Int64
    let reachedLimit: Bool

    static let empty = Self(
        inspectedEntryCount: 0,
        inspectedByteCount: 0,
        removedFileCount: 0,
        removedByteCount: 0,
        reachedLimit: false
    )
}

/// Strict journal repository. All compare-and-swap decisions are made from the
/// same bounded read whose descriptor revision is supplied to the file commit.
struct FoundationIOSPendingRecordingJournalRepository:
    IOSPendingRecordingJournalStoring,
    Sendable {
    static let maximumJournalByteCount = 64 * 1_024

    private let fileSystem: any IOSPendingRecordingJournalFileSystem

    init(
        applicationSupportDirectoryURL: URL,
        repositoryGuard:
            IOSAcceptedHistoryCoordinatorRepositoryGuard? = nil
    ) {
        fileSystem = FoundationIOSPendingRecordingJournalFileSystem(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            expectedRepositoryRoot:
                repositoryGuard?.expectedPhysicalRootIdentity,
            onRepositoryIdentityMismatch: {
                repositoryGuard?.invalidate()
            }
        )
    }

    init(fileSystem: any IOSPendingRecordingJournalFileSystem) {
        self.fileSystem = fileSystem
    }

    func load() throws -> IOSPendingRecording? {
        guard let file = try readFile() else {
            return nil
        }
        return try IOSPendingRecordingJournalWireCodec.decode(file.data)
    }

    func loadMetadataSnapshot(
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws
        -> IOSPendingRecordingJournalMetadataSnapshot? {
        let metadataFile: IOSPendingRecordingJournalMetadataFile?
        do {
            metadataFile = try fileSystem.readMetadataFileIfPresent(
                authorization: authorization
            )
        } catch IOSPendingRecordingJournalFileSystemError.sourceTooLarge {
            throw IOSPendingRecordingError.journalTooLarge
        } catch IOSPendingRecordingJournalFileSystemError.protectedDataUnavailable {
            throw IOSPendingRecordingError.dataProtectionUnavailable
        } catch IOSPendingRecordingJournalFileSystemError.repositoryIdentityConflict {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        } catch {
            throw IOSPendingRecordingError.journalUnreadable
        }
        guard let metadataFile else { return nil }
        guard metadataFile.pathIdentity == .pendingRecording else {
            throw IOSPendingRecordingError.journalUnreadable
        }
        let file = metadataFile.file
        return IOSPendingRecordingJournalMetadataSnapshot(
            recording: try IOSPendingRecordingJournalWireCodec.decode(file.data),
            fileRevision: file.revision
        )
    }

    func create(_ recording: IOSPendingRecording) throws {
        try create(recording, expectedRepositoryRoot: nil)
    }

    func create(
        _ recording: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws {
        let data = try IOSPendingRecordingJournalWireCodec.encode(recording)
        do {
            _ = try fileSystem.createFile(
                with: data,
                expectedRepositoryRoot: expectedRepositoryRoot
            )
        } catch let error as IOSPendingRecordingJournalFileSystemError {
            throw mapCreateError(error)
        } catch {
            throw IOSPendingRecordingError.journalWriteFailed
        }
    }

    func replace(
        _ recording: IOSPendingRecording,
        expected: IOSPendingRecording
    ) throws {
        try replace(
            recording,
            expected: expected,
            expectedRepositoryRoot: nil
        )
    }

    func replace(
        _ recording: IOSPendingRecording,
        expected: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws {
        guard let currentFile = try readFile() else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }
        let current = try IOSPendingRecordingJournalWireCodec.decode(
            currentFile.data
        )
        guard current == expected else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }

        let data = try IOSPendingRecordingJournalWireCodec.encode(recording)
        do {
            _ = try fileSystem.replaceFile(
                with: data,
                expected: currentFile.revision,
                expectedRepositoryRoot: expectedRepositoryRoot
            )
        } catch IOSPendingRecordingJournalFileSystemError.staleRevision,
                IOSPendingRecordingJournalFileSystemError.missing {
            throw IOSPendingRecordingError.compareAndSwapFailed
        } catch IOSPendingRecordingJournalFileSystemError.protectedDataUnavailable {
            throw IOSPendingRecordingError.dataProtectionUnavailable
        } catch IOSPendingRecordingJournalFileSystemError.repositoryIdentityConflict {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        } catch IOSPendingRecordingJournalFileSystemError.commitUncertain {
            throw IOSPendingRecordingError.journalCommitUncertain
        } catch {
            throw IOSPendingRecordingError.journalWriteFailed
        }
    }

    func remove(
        expected: IOSPendingRecording
    ) throws -> Bool {
        try remove(expected: expected, expectedRepositoryRoot: nil)
    }

    func remove(
        expected: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> Bool {
        guard let currentFile = try readFile() else {
            return false
        }
        let current = try IOSPendingRecordingJournalWireCodec.decode(
            currentFile.data
        )
        guard current == expected else {
            throw IOSPendingRecordingError.compareAndSwapFailed
        }

        do {
            try fileSystem.removeFile(
                expected: currentFile.revision,
                expectedRepositoryRoot: expectedRepositoryRoot
            )
            return true
        } catch IOSPendingRecordingJournalFileSystemError.staleRevision,
                IOSPendingRecordingJournalFileSystemError.missing {
            throw IOSPendingRecordingError.compareAndSwapFailed
        } catch IOSPendingRecordingJournalFileSystemError.protectedDataUnavailable {
            throw IOSPendingRecordingError.dataProtectionUnavailable
        } catch IOSPendingRecordingJournalFileSystemError.repositoryIdentityConflict {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        } catch {
            throw IOSPendingRecordingError.journalRemoveFailed
        }
    }

    func removeMetadata(
        expected: IOSPendingRecordingJournalMetadataSnapshot,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence {
        do {
            let evidence = try fileSystem.removeMetadataFile(
                expected: expected.fileRevision,
                expectedRepositoryRoot: expectedRepositoryRoot,
                authorization: authorization
            )
            guard evidence.provesRemoval(of: expected),
                  evidence.binding.pathIdentity == .pendingRecording else {
                throw IOSPendingRecordingError.journalCommitUncertain
            }
            return evidence
        } catch let error as IOSPendingRecordingError {
            throw error
        } catch let error as IOSPendingRecordingJournalFileSystemError {
            throw mapMetadataRetirementError(error)
        } catch {
            throw IOSPendingRecordingError.journalRemoveFailed
        }
    }

    func proveMetadataAbsent(
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence {
        do {
            let evidence = try fileSystem.proveMetadataFileAbsent(
                expectedRepositoryRoot: expectedRepositoryRoot,
                authorization: authorization
            )
            guard evidence.provesPreexistingAbsence,
                  evidence.binding.pathIdentity == .pendingRecording else {
                throw IOSPendingRecordingError.journalCommitUncertain
            }
            return evidence
        } catch let error as IOSPendingRecordingError {
            throw error
        } catch let error as IOSPendingRecordingJournalFileSystemError {
            throw mapMetadataRetirementError(error)
        } catch {
            throw IOSPendingRecordingError.journalRemoveFailed
        }
    }

    private func readFile() throws -> IOSPendingRecordingJournalFile? {
        do {
            return try fileSystem.readFileIfPresent()
        } catch IOSPendingRecordingJournalFileSystemError.sourceTooLarge {
            throw IOSPendingRecordingError.journalTooLarge
        } catch IOSPendingRecordingJournalFileSystemError.protectedDataUnavailable {
            throw IOSPendingRecordingError.dataProtectionUnavailable
        } catch IOSPendingRecordingJournalFileSystemError.repositoryIdentityConflict {
            throw IOSPendingRecordingError.repositoryIdentityConflict
        } catch {
            throw IOSPendingRecordingError.journalUnreadable
        }
    }

    private func mapCreateError(
        _ error: IOSPendingRecordingJournalFileSystemError
    ) -> IOSPendingRecordingError {
        switch error {
        case .destinationConflict:
            .pendingSlotOccupied
        case .sourceTooLarge:
            .journalTooLarge
        case .protectedDataUnavailable:
            .dataProtectionUnavailable
        case .repositoryIdentityConflict:
            .repositoryIdentityConflict
        case .commitUncertain:
            .journalCommitUncertain
        default:
            .journalWriteFailed
        }
    }

    private func mapMetadataRetirementError(
        _ error: IOSPendingRecordingJournalFileSystemError
    ) -> IOSPendingRecordingError {
        switch error {
        case .staleRevision, .missing, .invalidFile, .destinationConflict:
            .compareAndSwapFailed
        case .protectedDataUnavailable:
            .dataProtectionUnavailable
        case .repositoryIdentityConflict:
            .repositoryIdentityConflict
        case .commitUncertain:
            .journalCommitUncertain
        default:
            .journalRemoveFailed
        }
    }

}

typealias IOSPendingRecordingJournalRepository =
    FoundationIOSPendingRecordingJournalRepository

struct FoundationIOSPendingRecordingAudioRemovalIntentRepository:
    IOSPendingRecordingAudioRemovalIntentStoring,
    Sendable {
    private let fileSystem: any IOSPendingRecordingJournalFileSystem

    init(
        applicationSupportDirectoryURL: URL,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        onRepositoryIdentityMismatch: @escaping @Sendable () -> Void
    ) {
        fileSystem = FoundationIOSPendingRecordingJournalFileSystem(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            expectedRepositoryRoot: expectedRepositoryRoot,
            onRepositoryIdentityMismatch: onRepositoryIdentityMismatch
        )
    }

    init(fileSystem: any IOSPendingRecordingJournalFileSystem) {
        self.fileSystem = fileSystem
    }

    func load(
        expected recording: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingAudioRemovalIntentSnapshot? {
        let current = try requireCurrent(
            recording,
            expectedRepositoryRoot: expectedRepositoryRoot
        )
        let data: Data?
        do {
            data = try fileSystem.readAudioRemovalIntent(
                expected: current.revision,
                expectedRepositoryRoot: expectedRepositoryRoot,
                authorization:
                    IOSPendingRecordingAudioRemovalIntentAuthorization()
            )
        } catch let error as IOSPendingRecordingJournalFileSystemError {
            throw map(error)
        } catch {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        guard let data else { return nil }
        return IOSPendingRecordingAudioRemovalIntentSnapshot(
            intent: try IOSPendingRecordingAudioRemovalIntentCodec.decode(
                data,
                recording: recording
            ),
            journalRevision: current.revision
        )
    }

    func commit(
        _ intent: IOSPendingRecordingAudioRemovalIntent,
        expected recording: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingAudioRemovalIntentSnapshot {
        guard intent.recording == recording else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        let current = try requireCurrent(
            recording,
            expectedRepositoryRoot: expectedRepositoryRoot
        )
        let existingData: Data?
        do {
            existingData = try fileSystem.readAudioRemovalIntent(
                expected: current.revision,
                expectedRepositoryRoot: expectedRepositoryRoot,
                authorization:
                    IOSPendingRecordingAudioRemovalIntentAuthorization()
            )
        } catch let error as IOSPendingRecordingJournalFileSystemError {
            throw map(error)
        } catch {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        if let existingData {
            let existing = try IOSPendingRecordingAudioRemovalIntentCodec
                .decode(existingData, recording: recording)
            guard existing == intent else {
                throw IOSPendingRecordingAudioFileSystemError.removeFailed
            }
        }
        let data = IOSPendingRecordingAudioRemovalIntentCodec.encode(intent)
        let revision: IOSPendingRecordingJournalFileRevision
        do {
            revision = try fileSystem.writeAudioRemovalIntent(
                data,
                expected: current.revision,
                expectedRepositoryRoot: expectedRepositoryRoot,
                createOnly: existingData == nil,
                authorization:
                    IOSPendingRecordingAudioRemovalIntentAuthorization()
            )
        } catch let error as IOSPendingRecordingJournalFileSystemError {
            throw map(error)
        } catch {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        return IOSPendingRecordingAudioRemovalIntentSnapshot(
            intent: intent,
            journalRevision: revision
        )
    }

    private func requireCurrent(
        _ recording: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingJournalFile {
        let file: IOSPendingRecordingJournalFile
        do {
            guard let current = try fileSystem.readFileIfPresent() else {
                throw IOSPendingRecordingAudioFileSystemError.removeFailed
            }
            file = current
        } catch let error as IOSPendingRecordingAudioFileSystemError {
            throw error
        } catch let error as IOSPendingRecordingJournalFileSystemError {
            throw map(error)
        } catch {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        guard try IOSPendingRecordingJournalWireCodec.decode(file.data)
                == recording else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        _ = expectedRepositoryRoot
        return file
    }

    private func map(
        _ error: IOSPendingRecordingJournalFileSystemError
    ) -> IOSPendingRecordingAudioFileSystemError {
        switch error {
        case .protectedDataUnavailable:
            .dataProtectionUnavailable
        case .repositoryIdentityConflict:
            .repositoryIdentityConflict
        case .commitUncertain, .synchronizationFailed:
            .synchronizationFailed
        default:
            .removeFailed
        }
    }
}

enum IOSPendingRecordingAudioRemovalIntentCodec {
    private static let schemaVersion: UInt8 = 1

    static func encode(
        _ intent: IOSPendingRecordingAudioRemovalIntent
    ) -> Data {
        var data = Data()
        data.reserveCapacity(IOSPendingRecordingAudioRemovalIntent.encodedByteCount)
        data.append(schemaVersion)
        data.append(intent.purpose.rawValue)
        append(intent.physicalSnapshot.device, to: &data)
        append(intent.physicalSnapshot.inode, to: &data)
        append(UInt64(bitPattern: intent.physicalSnapshot.byteCount), to: &data)
        append(
            UInt64(bitPattern: intent.physicalSnapshot.modificationSeconds),
            to: &data
        )
        append(
            UInt32(intent.physicalSnapshot.modificationNanoseconds),
            to: &data
        )
        append(
            UInt64(bitPattern: intent.physicalSnapshot.statusChangeSeconds),
            to: &data
        )
        append(
            UInt32(intent.physicalSnapshot.statusChangeNanoseconds),
            to: &data
        )
        return data
    }

    static func decode(
        _ data: Data,
        recording: IOSPendingRecording
    ) throws -> IOSPendingRecordingAudioRemovalIntent {
        guard data.count == IOSPendingRecordingAudioRemovalIntent.encodedByteCount,
              data[0] == schemaVersion,
              let purpose =
                IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization.Purpose(
                    rawValue: data[1]
                ) else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        var offset = 2
        let device = readUInt64(data, offset: &offset)
        let inode = readUInt64(data, offset: &offset)
        let byteCount = Int64(bitPattern: readUInt64(data, offset: &offset))
        let modificationSeconds = Int64(
            bitPattern: readUInt64(data, offset: &offset)
        )
        let modificationNanoseconds = Int64(readUInt32(data, offset: &offset))
        let statusChangeSeconds = Int64(
            bitPattern: readUInt64(data, offset: &offset)
        )
        let statusChangeNanoseconds = Int64(readUInt32(data, offset: &offset))
        guard offset == data.count,
              let physicalSnapshot =
                IOSPendingRecordingAudioRemovalPhysicalSnapshot(
                    device: device,
                    inode: inode,
                    byteCount: byteCount,
                    modificationSeconds: modificationSeconds,
                    modificationNanoseconds: modificationNanoseconds,
                    statusChangeSeconds: statusChangeSeconds,
                    statusChangeNanoseconds: statusChangeNanoseconds
                ),
              let intent = IOSPendingRecordingAudioRemovalIntent(
                  purpose: purpose,
                  recording: recording,
                  physicalSnapshot: physicalSnapshot
              ) else {
            throw IOSPendingRecordingAudioFileSystemError.removeFailed
        }
        return intent
    }

    private static func append<T: FixedWidthInteger>(
        _ value: T,
        to data: inout Data
    ) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func readUInt64(
        _ data: Data,
        offset: inout Int
    ) -> UInt64 {
        var value: UInt64 = 0
        for _ in 0..<8 {
            value = (value << 8) | UInt64(data[offset])
            offset += 1
        }
        return value
    }

    private static func readUInt32(
        _ data: Data,
        offset: inout Int
    ) -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            value = (value << 8) | UInt32(data[offset])
            offset += 1
        }
        return value
    }
}

enum IOSPendingRecordingJournalWireCodec {
    static let supportedSchemaVersion = 1
    static let fields: Set<String> = [
        "schemaVersion",
        "attemptID",
        "audioRelativeIdentifier",
        "createdAt",
        "updatedAt",
        "phase",
        "outputIntent",
        "transcriptionID",
        "transcriptionModel",
        "transcriptionLanguageCode",
        "durationMilliseconds",
        "byteCount",
    ]

    static func encode(_ recording: IOSPendingRecording) throws -> Data {
        let wire = try IOSPendingRecordingJournalWireV1(recording: recording)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let data: Data
        do {
            data = try encoder.encode(wire)
        } catch {
            throw IOSPendingRecordingError.invalidJournal
        }
        guard data.count <= FoundationIOSPendingRecordingJournalRepository
            .maximumJournalByteCount else {
            throw IOSPendingRecordingError.journalTooLarge
        }
        return data
    }

    static func decode(_ data: Data) throws -> IOSPendingRecording {
        do {
            try BoundedJSONMemberValidator.validate(
                data,
                limits: .metadataFile(
                    maximumInputByteCount:
                        FoundationIOSPendingRecordingJournalRepository
                            .maximumJournalByteCount
                )
            )
        } catch BoundedJSONMemberValidationError.inputTooLarge {
            throw IOSPendingRecordingError.journalTooLarge
        } catch {
            throw IOSPendingRecordingError.journalMalformed
        }

        let rootValue: Any
        do {
            rootValue = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw IOSPendingRecordingError.journalMalformed
        }
        guard let object = rootValue as? [String: Any] else {
            throw IOSPendingRecordingError.invalidJournal
        }

        let reader = IOSPendingRecordingJournalObjectReader(object: object)
        let schemaVersion = try reader.integer64("schemaVersion")
        guard schemaVersion == Int64(supportedSchemaVersion) else {
            throw IOSPendingRecordingError.unsupportedJournalVersion
        }
        guard Set(object.keys) == fields else {
            throw IOSPendingRecordingError.invalidJournal
        }

        let attemptID = try canonicalUUID(
            from: reader.string("attemptID")
        )
        let transcriptionIDValue = try reader.nullableString(
            "transcriptionID"
        )
        let transcriptionID = try transcriptionIDValue.map {
            try canonicalUUID(from: $0)
        }
        let phase = try decodePhase(reader.string("phase"))
        let outputIntent = try decodeOutputIntent(
            reader.string("outputIntent")
        )

        do {
            return try IOSPendingRecording(
                attemptID: attemptID,
                audioRelativeIdentifier: reader.string(
                    "audioRelativeIdentifier"
                ),
                createdAt: IOSPendingRecordingTimestampCodec.date(
                    from: reader.string("createdAt")
                ),
                updatedAt: IOSPendingRecordingTimestampCodec.date(
                    from: reader.string("updatedAt")
                ),
                phase: phase,
                outputIntent: outputIntent,
                transcriptionID: transcriptionID,
                transcriptionModel: reader.string("transcriptionModel"),
                transcriptionLanguageCode: reader.nullableString(
                    "transcriptionLanguageCode"
                ),
                durationMilliseconds: reader.integer64(
                    "durationMilliseconds"
                ),
                byteCount: reader.integer64("byteCount")
            )
        } catch {
            throw IOSPendingRecordingError.invalidJournal
        }
    }

    private static func canonicalUUID(from value: String) throws -> UUID {
        guard let identifier = UUID(uuidString: value),
              value == identifier.uuidString.lowercased() else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return identifier
    }

    private static func decodePhase(
        _ value: String
    ) throws -> IOSPendingRecordingPhase {
        switch value {
        case "readyForTranscription": .readyForTranscription
        case "awaitingRecovery": .awaitingRecovery
        case "transcribing": .transcribing
        case "postProcessing": .postProcessing
        case "outputDelivery": .outputDelivery
        default: throw IOSPendingRecordingError.invalidJournal
        }
    }

    private static func decodeOutputIntent(
        _ value: String
    ) throws -> DictationOutputIntent {
        guard let intent = DictationOutputIntent(rawValue: value) else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return intent
    }
}

private struct IOSPendingRecordingJournalObjectReader {
    let object: [String: Any]

    func string(_ key: String) throws -> String {
        guard let value = object[key] as? String else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return value
    }

    func nullableString(_ key: String) throws -> String? {
        guard let value = object[key] else {
            throw IOSPendingRecordingError.invalidJournal
        }
        if value is NSNull {
            return nil
        }
        guard let string = value as? String else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return string
    }

    func integer64(_ key: String) throws -> Int64 {
        guard let value = object[key],
              let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !Self.isFloatingPoint(number),
              let integer = Int64(number.stringValue) else {
            throw IOSPendingRecordingError.invalidJournal
        }
        return integer
    }

    private static func isFloatingPoint(_ number: NSNumber) -> Bool {
        let type = String(cString: number.objCType)
        return type == "f" || type == "d"
    }
}

private struct IOSPendingRecordingJournalWireV1: Encodable {
    let schemaVersion = 1
    let attemptID: String
    let audioRelativeIdentifier: String
    let createdAt: String
    let updatedAt: String
    let phase: String
    let outputIntent: String
    let transcriptionID: String?
    let transcriptionModel: String
    let transcriptionLanguageCode: String?
    let durationMilliseconds: Int64
    let byteCount: Int64

    init(recording: IOSPendingRecording) throws {
        attemptID = recording.attemptID.uuidString.lowercased()
        audioRelativeIdentifier = recording.audioRelativeIdentifier
        createdAt = try IOSPendingRecordingTimestampCodec.string(
            from: recording.createdAt
        )
        updatedAt = try IOSPendingRecordingTimestampCodec.string(
            from: recording.updatedAt
        )
        phase = Self.phaseValue(recording.phase)
        outputIntent = recording.outputIntent.rawValue
        transcriptionID = recording.transcriptionID?.uuidString.lowercased()
        transcriptionModel = recording.transcriptionModel
        transcriptionLanguageCode = recording.transcriptionLanguageCode
        durationMilliseconds = recording.durationMilliseconds
        byteCount = recording.byteCount
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(attemptID, forKey: .attemptID)
        try container.encode(
            audioRelativeIdentifier,
            forKey: .audioRelativeIdentifier
        )
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(phase, forKey: .phase)
        try container.encode(outputIntent, forKey: .outputIntent)
        if let transcriptionID {
            try container.encode(transcriptionID, forKey: .transcriptionID)
        } else {
            try container.encodeNil(forKey: .transcriptionID)
        }
        try container.encode(
            transcriptionModel,
            forKey: .transcriptionModel
        )
        if let transcriptionLanguageCode {
            try container.encode(
                transcriptionLanguageCode,
                forKey: .transcriptionLanguageCode
            )
        } else {
            try container.encodeNil(forKey: .transcriptionLanguageCode)
        }
        try container.encode(
            durationMilliseconds,
            forKey: .durationMilliseconds
        )
        try container.encode(byteCount, forKey: .byteCount)
    }

    private static func phaseValue(
        _ phase: IOSPendingRecordingPhase
    ) -> String {
        switch phase {
        case .readyForTranscription: "readyForTranscription"
        case .awaitingRecovery: "awaitingRecovery"
        case .transcribing: "transcribing"
        case .postProcessing: "postProcessing"
        case .outputDelivery: "outputDelivery"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case attemptID
        case audioRelativeIdentifier
        case createdAt
        case updatedAt
        case phase
        case outputIntent
        case transcriptionID
        case transcriptionModel
        case transcriptionLanguageCode
        case durationMilliseconds
        case byteCount
    }
}

private struct IOSPendingRecordingJournalFileSnapshot: Equatable, Sendable {
    let device: dev_t
    let inode: ino_t
    let byteCount: off_t
    let modificationSeconds: time_t
    let modificationNanoseconds: Int
    let statusChangeSeconds: time_t
    let statusChangeNanoseconds: Int

    init(_ status: stat) {
        device = status.st_dev
        inode = status.st_ino
        byteCount = status.st_size
        modificationSeconds = status.st_mtimespec.tv_sec
        modificationNanoseconds = status.st_mtimespec.tv_nsec
        statusChangeSeconds = status.st_ctimespec.tv_sec
        statusChangeNanoseconds = status.st_ctimespec.tv_nsec
    }
}

/// Descriptor-relative live boundary for the single protected journal file.
/// The destination is never opened through a followed path component.
struct FoundationIOSPendingRecordingJournalFileSystem:
    IOSPendingRecordingJournalFileSystem,
    Sendable {
    private final class MaintenanceEnumerationCursor: @unchecked Sendable {
        private let adapter: any IOSPendingRecordingPOSIXAdapter
        private let lock = NSLock()
        private var directoryIdentity: FileIdentity?
        private var stream: UnsafeMutablePointer<DIR>?

        init(adapter: any IOSPendingRecordingPOSIXAdapter) {
            self.adapter = adapter
        }

        deinit {
            reset()
        }

        func stream(
            matching directoryIdentity: FileIdentity,
            opening: () throws -> UnsafeMutablePointer<DIR>
        ) throws -> UnsafeMutablePointer<DIR> {
            lock.lock()
            defer { lock.unlock() }

            if self.directoryIdentity != directoryIdentity {
                closeStreamIfPresent()
            }
            if let stream {
                return stream
            }

            let stream = try opening()
            self.directoryIdentity = directoryIdentity
            self.stream = stream
            return stream
        }

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            closeStreamIfPresent()
        }

        private func closeStreamIfPresent() {
            if let stream {
                adapter.closeDirectoryStream(stream)
            }
            stream = nil
            directoryIdentity = nil
        }
    }

    private static let processMutationLock = NSLock()
    private static let transferChunkByteCount = 64 * 1_024
    private static let maximumInterruptedRetryCount = 8
    private static let maintenanceMaximumDirectoryEntryCount = 256
    private static let maintenanceMaximumCandidateCount = 32
    private static let maintenanceMaximumByteCount: Int64 = 4 * 1_024 * 1_024
    private static let maintenanceMaximumElapsedNanoseconds: UInt64 =
        100_000_000
    private static let maintenanceMinimumAge: TimeInterval = 24 * 60 * 60
    private static let completeProtectionClass: Int32 = 1
    private static let backupExclusionAttributeName =
        "com.apple.metadata:com_apple_backup_excludeItem"
    private static let backupExclusionAttributeValue: [UInt8] = [
        0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30,
        0x5F, 0x10, 0x11, 0x63, 0x6F, 0x6D, 0x2E, 0x61,
        0x70, 0x70, 0x6C, 0x65, 0x2E, 0x62, 0x61, 0x63,
        0x6B, 0x75, 0x70, 0x64, 0x08, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x1C,
    ]

    typealias ReplaceOperation = @Sendable (
        _ directoryDescriptor: Int32,
        _ temporaryName: String,
        _ destinationName: String
    ) -> IOSPendingRecordingPOSIXResult<Void>
    typealias DirectorySynchronizationOperation = @Sendable (
        _ directoryDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void>
    typealias BeforeMetadataAbsenceFinalCheck = @Sendable () -> Void

    private let applicationSupportDirectoryURL: URL
    private let configuration: IOSStrictProtectedRecordConfiguration
    private let adapter: any IOSPendingRecordingPOSIXAdapter
    private let replaceOperation: ReplaceOperation
    private let directorySynchronizationOperation:
        DirectorySynchronizationOperation?
    private let beforeMetadataAbsenceFinalCheck:
        BeforeMetadataAbsenceFinalCheck
    private let monotonicNowNanoseconds: @Sendable () -> UInt64
    private let beforeRepositoryRootOpen: @Sendable () throws -> Void
    private let configuredExpectedRepositoryRoot:
        IOSPersistenceRepositoryRootIdentity?
    private let onRepositoryIdentityMismatch: @Sendable () -> Void
    private let maintenanceEnumerationCursor: MaintenanceEnumerationCursor

    init(
        applicationSupportDirectoryURL: URL,
        configuration: IOSStrictProtectedRecordConfiguration = .pendingRecording,
        adapter: any IOSPendingRecordingPOSIXAdapter =
            DarwinIOSPendingRecordingPOSIXAdapter(),
        replaceOperation: @escaping ReplaceOperation = {
            directoryDescriptor,
            temporaryName,
            destinationName in
            liveIOSPendingRecordingJournalReplace(
                directoryDescriptor: directoryDescriptor,
                temporaryName: temporaryName,
                destinationName: destinationName
            )
        },
        directorySynchronizationOperation:
            DirectorySynchronizationOperation? = nil,
        beforeMetadataAbsenceFinalCheck:
            @escaping BeforeMetadataAbsenceFinalCheck = {},
        beforeRepositoryRootOpen:
            @escaping @Sendable () throws -> Void = {},
        expectedRepositoryRoot:
            IOSPersistenceRepositoryRootIdentity? = nil,
        onRepositoryIdentityMismatch:
            @escaping @Sendable () -> Void = {},
        monotonicNowNanoseconds: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        }
    ) {
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
        self.configuration = configuration
        self.adapter = adapter
        self.replaceOperation = replaceOperation
        self.directorySynchronizationOperation =
            directorySynchronizationOperation
        self.beforeMetadataAbsenceFinalCheck =
            beforeMetadataAbsenceFinalCheck
        self.beforeRepositoryRootOpen = beforeRepositoryRootOpen
        configuredExpectedRepositoryRoot = expectedRepositoryRoot
        self.onRepositoryIdentityMismatch =
            onRepositoryIdentityMismatch
        self.monotonicNowNanoseconds = monotonicNowNanoseconds
        maintenanceEnumerationCursor = MaintenanceEnumerationCursor(
            adapter: adapter
        )
    }

    func readFileIfPresent() throws -> IOSPendingRecordingJournalFile? {
        guard let directory = try openJournalDirectory(createIfMissing: false) else {
            return nil
        }
        defer { close(directory) }
        try validateDirectoryIdentity(directory)

        guard let pathStatus = try statusIfPresent(
            named: configuration.fileName,
            directory: directory,
            failure: .readFailed
        ) else {
            return nil
        }
        try validateJournalStatus(
            pathStatus,
            effectiveUserID: directory.effectiveUserID
        )
        guard pathStatus.st_size >= 0,
              pathStatus.st_size <= off_t(configuration.maximumByteCount) else {
            throw IOSPendingRecordingJournalFileSystemError.sourceTooLarge
        }

        let descriptor = try openJournalForReading(directory: directory)
        defer { adapter.closeFile(descriptor) }
        let openedStatus = try status(
            descriptor: descriptor,
            failure: .readFailed
        )
        try validateJournalStatus(
            openedStatus,
            effectiveUserID: directory.effectiveUserID
        )
        guard IOSPendingRecordingJournalFileSnapshot(pathStatus)
                == IOSPendingRecordingJournalFileSnapshot(openedStatus) else {
            throw IOSPendingRecordingJournalFileSystemError.readFailed
        }
        try validateExactConfiguration(descriptor: descriptor)

        let data = try readBoundedData(from: descriptor)
        let finalStatus = try status(
            descriptor: descriptor,
            failure: .readFailed
        )
        try validateJournalStatus(
            finalStatus,
            effectiveUserID: directory.effectiveUserID
        )
        let snapshot = IOSPendingRecordingJournalFileSnapshot(finalStatus)
        guard snapshot == IOSPendingRecordingJournalFileSnapshot(openedStatus),
              finalStatus.st_size == off_t(data.count) else {
            throw IOSPendingRecordingJournalFileSystemError.readFailed
        }
        try validatePathIdentity(
            named: configuration.fileName,
            descriptorStatus: finalStatus,
            directory: directory,
            failure: .readFailed
        )
        try validateDirectoryIdentity(directory)

        return IOSPendingRecordingJournalFile(
            data: data,
            revision: IOSPendingRecordingJournalFileRevision(
                snapshot: snapshot
            )
        )
    }

    func readMetadataFileIfPresent(
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataFile? {
        _ = authorization
        try requirePendingRecordingMetadataConfiguration()
        return try readFileIfPresent().map {
            IOSPendingRecordingJournalMetadataFile(
                file: $0,
                pathIdentity: .pendingRecording
            )
        }
    }

    func readOpaqueFileRevisionIfPresent() throws
        -> IOSPendingRecordingJournalFileRevision? {
        guard let directory = try openJournalDirectory(createIfMissing: false) else {
            return nil
        }
        defer { close(directory) }
        try validateDirectoryIdentity(directory)

        guard let pathStatus = try statusIfPresent(
            named: configuration.fileName,
            directory: directory,
            failure: .readFailed
        ) else {
            return nil
        }
        try validateJournalStatus(
            pathStatus,
            effectiveUserID: directory.effectiveUserID
        )

        let descriptor = try openJournalForReading(directory: directory)
        defer { adapter.closeFile(descriptor) }
        let openedStatus = try status(
            descriptor: descriptor,
            failure: .readFailed
        )
        try validateJournalStatus(
            openedStatus,
            effectiveUserID: directory.effectiveUserID
        )
        guard IOSPendingRecordingJournalFileSnapshot(pathStatus)
                == IOSPendingRecordingJournalFileSnapshot(openedStatus) else {
            throw IOSPendingRecordingJournalFileSystemError.readFailed
        }
        try validatePathIdentity(
            named: configuration.fileName,
            descriptorStatus: openedStatus,
            directory: directory,
            failure: .readFailed
        )
        try validateDirectoryIdentity(directory)
        return IOSPendingRecordingJournalFileRevision(
            snapshot: IOSPendingRecordingJournalFileSnapshot(openedStatus)
        )
    }

    func createFile(
        with data: Data
    ) throws -> IOSPendingRecordingJournalFileRevision {
        try createFile(with: data, expectedRepositoryRoot: nil)
    }

    func createFile(
        with data: Data,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingJournalFileRevision {
        try validateWriteData(data)
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        try beforeRepositoryRootOpen()
        guard let directory = try openJournalDirectory(
            createIfMissing: true,
            expectedRepositoryRoot: expectedRepositoryRoot
        ) else {
            throw IOSPendingRecordingJournalFileSystemError.writeFailed
        }
        defer { close(directory) }
        try validateDirectoryIdentity(directory)
        try lockDirectoryForMutation(directory)
        try validateDirectoryIdentity(directory)

        if try statusIfPresent(
            named: configuration.fileName,
            directory: directory,
            failure: .writeFailed
        ) != nil {
            throw IOSPendingRecordingJournalFileSystemError.destinationConflict
        }

        return try commitTemporaryFile(
            data: data,
            directory: directory,
            expected: nil,
            createOnly: true
        )
    }

    func replaceFile(
        with data: Data,
        expected: IOSPendingRecordingJournalFileRevision
    ) throws -> IOSPendingRecordingJournalFileRevision {
        try replaceFile(
            with: data,
            expected: expected,
            expectedRepositoryRoot: nil
        )
    }

    func replaceFile(
        with data: Data,
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingJournalFileRevision {
        try validateWriteData(data)
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        try beforeRepositoryRootOpen()
        guard let directory = try openJournalDirectory(
            createIfMissing: false,
            expectedRepositoryRoot: expectedRepositoryRoot
        ) else {
            throw IOSPendingRecordingJournalFileSystemError.missing
        }
        defer { close(directory) }
        try validateDirectoryIdentity(directory)
        try lockDirectoryForMutation(directory)
        try validateDirectoryIdentity(directory)
        try validateCurrentFile(directory: directory, expected: expected)
        try requireNoAudioRemovalIntent(directory: directory)

        return try commitTemporaryFile(
            data: data,
            directory: directory,
            expected: expected,
            createOnly: false
        )
    }

    func removeFile(
        expected: IOSPendingRecordingJournalFileRevision
    ) throws {
        try removeFile(
            expected: expected,
            expectedRepositoryRoot: nil
        )
    }

    func removeFile(
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws {
        try removeFile(
            expected: expected,
            expectedRepositoryRoot: expectedRepositoryRoot,
            requiresExactConfiguration: true
        )
    }

    func removeOpaqueFile(
        expected: IOSPendingRecordingJournalFileRevision
    ) throws {
        try removeFile(
            expected: expected,
            expectedRepositoryRoot: nil,
            requiresExactConfiguration: false
        )
    }

    func removeMetadataFile(
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence {
        _ = authorization
        try requirePendingRecordingMetadataConfiguration()
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        try beforeRepositoryRootOpen()
        guard let directory = try openJournalDirectory(
            createIfMissing: false,
            expectedRepositoryRoot: expectedRepositoryRoot
        ) else {
            throw IOSPendingRecordingJournalFileSystemError.missing
        }
        defer { close(directory) }
        try validateDirectoryIdentity(directory)
        try lockDirectoryForMutation(directory)
        try validateDirectoryIdentity(directory)
        try validateCurrentFile(directory: directory, expected: expected)
        try validateDirectoryIdentity(directory)

        let result = retryInterrupted {
            adapter.unlinkAt(
                directoryDescriptor: directory.descriptor,
                name: configuration.fileName
            )
        }
        switch result {
        case .success:
            break
        case .failure(ENOENT):
            throw IOSPendingRecordingJournalFileSystemError.commitUncertain
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.removeFailed
        }

        return try confirmMetadataAbsenceAfterRemoval(
            sourceRevision: expected,
            directory: directory
        )
    }

    func proveMetadataFileAbsent(
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence {
        _ = authorization
        try requirePendingRecordingMetadataConfiguration()
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        try beforeRepositoryRootOpen()
        guard let directory = try openJournalDirectory(
            createIfMissing: false,
            expectedRepositoryRoot: expectedRepositoryRoot
        ) else {
            throw IOSPendingRecordingJournalFileSystemError.missing
        }
        defer { close(directory) }
        try validateDirectoryIdentity(directory)
        try lockDirectoryForMutation(directory)
        try validateDirectoryIdentity(directory)

        guard try statusIfPresent(
            named: configuration.fileName,
            directory: directory,
            failure: .readFailed
        ) == nil else {
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        }
        try validateDirectoryIdentity(directory)
        try synchronizeDirectory(directory.descriptor)
        beforeMetadataAbsenceFinalCheck()
        guard try statusIfPresent(
            named: configuration.fileName,
            directory: directory,
            failure: .readFailed
        ) == nil else {
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        }
        try validateDirectoryIdentity(directory)

        return .alreadyAbsent(
            IOSPendingRecordingJournalMetadataAbsenceEvidence.AlreadyAbsent(
                binding: metadataAbsenceBinding(directory: directory)
            )
        )
    }

    func proveCanonicalFileAbsent(
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSStrictProtectedRecordAbsenceEvidence {
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        try beforeRepositoryRootOpen()
        guard let directory = try openJournalDirectory(
            createIfMissing: false,
            expectedRepositoryRoot: expectedRepositoryRoot
        ) else {
            throw IOSPendingRecordingJournalFileSystemError.missing
        }
        defer { close(directory) }
        try validateDirectoryIdentity(directory)
        try lockDirectoryForMutation(directory)
        try validateDirectoryIdentity(directory)

        guard try statusIfPresent(
            named: configuration.fileName,
            directory: directory,
            failure: .readFailed
        ) == nil else {
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        }
        try validateDirectoryIdentity(directory)
        try synchronizeDirectory(directory.descriptor)
        beforeMetadataAbsenceFinalCheck()
        guard try statusIfPresent(
            named: configuration.fileName,
            directory: directory,
            failure: .readFailed
        ) == nil else {
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        }
        try validateDirectoryIdentity(directory)

        return IOSStrictProtectedRecordAbsenceEvidence(
            repositoryRoot: directory.repositoryRootIdentity,
            recordDirectory: IOSPendingRecordingJournalDirectoryIdentity(
                device: directory.identity.device,
                inode: directory.identity.inode
            ),
            configuration: configuration
        )
    }

    func readAudioRemovalIntent(
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingAudioRemovalIntentAuthorization
    ) throws -> Data? {
        _ = authorization
        try requirePendingRecordingMetadataConfiguration()
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        try beforeRepositoryRootOpen()
        guard let directory = try openJournalDirectory(
            createIfMissing: false,
            expectedRepositoryRoot: expectedRepositoryRoot
        ) else {
            throw IOSPendingRecordingJournalFileSystemError.missing
        }
        defer { close(directory) }
        try validateDirectoryIdentity(directory)
        try lockDirectoryForMutation(directory)
        try validateDirectoryIdentity(directory)
        try validateCurrentFile(directory: directory, expected: expected)

        let descriptor = try openJournalForReading(directory: directory)
        defer { adapter.closeFile(descriptor) }
        let openedStatus = try status(
            descriptor: descriptor,
            failure: .readFailed
        )
        guard let expectedSnapshot = expected.snapshot,
              IOSPendingRecordingJournalFileSnapshot(openedStatus)
                == expectedSnapshot else {
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        }
        try validateJournalStatus(
            openedStatus,
            effectiveUserID: directory.effectiveUserID
        )
        try validateExactConfiguration(descriptor: descriptor)
        try validatePathIdentity(
            named: configuration.fileName,
            descriptorStatus: openedStatus,
            directory: directory,
            failure: .readFailed
        )
        let result = retryInterrupted {
            adapter.extendedAttribute(
                fileDescriptor: descriptor,
                name: IOSPendingRecordingAudioRemovalIntent
                    .extendedAttributeName,
                maximumByteCount:
                    IOSPendingRecordingAudioRemovalIntent.encodedByteCount + 1
            )
        }
        let data: Data?
        switch result {
        case .success(let bytes):
            guard bytes.count
                    == IOSPendingRecordingAudioRemovalIntent.encodedByteCount
            else {
                throw IOSPendingRecordingJournalFileSystemError.invalidFile
            }
            data = Data(bytes)
        case .failure(ENOATTR):
            data = nil
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.invalidFile
        }
        let finalStatus = try status(
            descriptor: descriptor,
            failure: .readFailed
        )
        guard IOSPendingRecordingJournalFileSnapshot(finalStatus)
                == expectedSnapshot else {
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        }
        try validatePathIdentity(
            named: configuration.fileName,
            descriptorStatus: finalStatus,
            directory: directory,
            failure: .readFailed
        )
        try validateDirectoryIdentity(directory)
        return data
    }

    func writeAudioRemovalIntent(
        _ data: Data,
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        createOnly: Bool,
        authorization: IOSPendingRecordingAudioRemovalIntentAuthorization
    ) throws -> IOSPendingRecordingJournalFileRevision {
        _ = authorization
        guard data.count
                == IOSPendingRecordingAudioRemovalIntent.encodedByteCount else {
            throw IOSPendingRecordingJournalFileSystemError.invalidFile
        }
        try requirePendingRecordingMetadataConfiguration()
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        try beforeRepositoryRootOpen()
        guard let directory = try openJournalDirectory(
            createIfMissing: false,
            expectedRepositoryRoot: expectedRepositoryRoot
        ) else {
            throw IOSPendingRecordingJournalFileSystemError.missing
        }
        defer { close(directory) }
        try validateDirectoryIdentity(directory)
        try lockDirectoryForMutation(directory)
        try validateDirectoryIdentity(directory)
        try validateCurrentFile(directory: directory, expected: expected)

        let descriptor = try openJournalForMutation(directory: directory)
        defer { adapter.closeFile(descriptor) }
        let beforeStatus = try status(
            descriptor: descriptor,
            failure: .writeFailed
        )
        guard let expectedSnapshot = expected.snapshot,
              IOSPendingRecordingJournalFileSnapshot(beforeStatus)
                == expectedSnapshot else {
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        }
        try validateExactConfiguration(descriptor: descriptor)
        try validatePathIdentity(
            named: configuration.fileName,
            descriptorStatus: beforeStatus,
            directory: directory,
            failure: .writeFailed
        )

        let setResult = adapter.setExtendedAttribute(
            fileDescriptor: descriptor,
            name: IOSPendingRecordingAudioRemovalIntent.extendedAttributeName,
            value: Array(data),
            flags: createOnly ? XATTR_CREATE : XATTR_REPLACE
        )
        switch setResult {
        case .success:
            break
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure(EEXIST), .failure(ENOATTR):
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.commitUncertain
        }

        do {
            try synchronizeFile(descriptor)
            let committedStatus = try status(
                descriptor: descriptor,
                failure: .writeFailed
            )
            try validateJournalStatus(
                committedStatus,
                effectiveUserID: directory.effectiveUserID
            )
            try validateExactConfiguration(descriptor: descriptor)
            try validatePathIdentity(
                named: configuration.fileName,
                descriptorStatus: committedStatus,
                directory: directory,
                failure: .writeFailed
            )
            try validateDirectoryIdentity(directory)
            try synchronizeDirectory(directory.descriptor)
            let finalStatus = try status(
                descriptor: descriptor,
                failure: .writeFailed
            )
            guard IOSPendingRecordingJournalFileSnapshot(finalStatus)
                    == IOSPendingRecordingJournalFileSnapshot(committedStatus)
            else {
                throw IOSPendingRecordingJournalFileSystemError.commitUncertain
            }
            try validatePathIdentity(
                named: configuration.fileName,
                descriptorStatus: finalStatus,
                directory: directory,
                failure: .writeFailed
            )
            let persisted = retryInterrupted {
                adapter.extendedAttribute(
                    fileDescriptor: descriptor,
                    name: IOSPendingRecordingAudioRemovalIntent
                        .extendedAttributeName,
                    maximumByteCount: data.count + 1
                )
            }
            guard case .success(Array(data)) = persisted else {
                throw IOSPendingRecordingJournalFileSystemError.commitUncertain
            }
            try validateDirectoryIdentity(directory)
            return IOSPendingRecordingJournalFileRevision(
                snapshot: IOSPendingRecordingJournalFileSnapshot(finalStatus)
            )
        } catch IOSPendingRecordingJournalFileSystemError
            .protectedDataUnavailable {
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        } catch {
            throw IOSPendingRecordingJournalFileSystemError.commitUncertain
        }
    }

    private func removeFile(
        expected: IOSPendingRecordingJournalFileRevision,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        requiresExactConfiguration: Bool
    ) throws {
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        try beforeRepositoryRootOpen()
        guard let directory = try openJournalDirectory(
            createIfMissing: false,
            expectedRepositoryRoot: expectedRepositoryRoot
        ) else {
            throw IOSPendingRecordingJournalFileSystemError.missing
        }
        defer { close(directory) }
        try validateDirectoryIdentity(directory)
        try lockDirectoryForMutation(directory)
        try validateDirectoryIdentity(directory)
        try validateCurrentFile(
            directory: directory,
            expected: expected,
            requiresExactConfiguration: requiresExactConfiguration
        )
        try requireNoAudioRemovalIntent(directory: directory)
        try validateDirectoryIdentity(directory)

        let result = retryInterrupted {
            adapter.unlinkAt(
                directoryDescriptor: directory.descriptor,
                name: configuration.fileName
            )
        }
        switch result {
        case .success:
            break
        case .failure(ENOENT):
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.removeFailed
        }

        try synchronizeDirectory(directory.descriptor)
    }

    func removeAbandonedTemporaryFiles(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        try removeAbandonedTemporaryFiles(
            now: now,
            expectedRepositoryRoot: nil
        )
    }

    func removeAbandonedTemporaryFiles(
        now: Date,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        guard now.timeIntervalSince1970.isFinite else {
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        try beforeRepositoryRootOpen()
        guard let directory = try openJournalDirectory(
            createIfMissing: false,
            expectedRepositoryRoot: expectedRepositoryRoot
        ) else {
            maintenanceEnumerationCursor.reset()
            return .empty
        }
        defer { close(directory) }
        try validateDirectoryIdentity(directory)
        try lockDirectoryForMutation(directory)
        try validateDirectoryIdentity(directory)

        let stream = try maintenanceEnumerationCursor.stream(
            matching: directory.identity
        ) {
            try openDirectoryStream(directory: directory)
        }
        let startedAt = monotonicNowNanoseconds()
        var inspectedEntryCount = 0
        var inspectedByteCount: Int64 = 0
        var removedFileCount = 0
        var removedByteCount: Int64 = 0
        var reachedLimit = false

        do {
            var enumeratedEntryCount = 0
            var candidateNames: [String] = []
            var reachedEndOfDirectory = false
            while true {
                guard enumeratedEntryCount
                        < Self.maintenanceMaximumDirectoryEntryCount,
                      elapsedNanoseconds(since: startedAt)
                        < Self.maintenanceMaximumElapsedNanoseconds else {
                    reachedLimit = true
                    break
                }

                let entry: IOSPendingRecordingDirectoryEntry?
                switch retryInterrupted({
                    adapter.nextDirectoryEntry(stream: stream)
                }) {
                case .success(let value):
                    entry = value
                case .failure(let code) where isProtectedDataError(code):
                    maintenanceEnumerationCursor.reset()
                    throw IOSPendingRecordingJournalFileSystemError
                        .protectedDataUnavailable
                case .failure:
                    maintenanceEnumerationCursor.reset()
                    throw IOSPendingRecordingJournalFileSystemError.readFailed
                }
                guard let entry else {
                    reachedEndOfDirectory = true
                    break
                }
                enumeratedEntryCount += 1
                guard case .name(let name) = entry,
                      name != ".",
                      name != "..",
                      isTemporaryFileName(name) else {
                    continue
                }
                candidateNames.append(name)
            }
            if reachedEndOfDirectory {
                maintenanceEnumerationCursor.reset()
            }

            let candidateCount = min(
                candidateNames.count,
                Self.maintenanceMaximumCandidateCount
            )
            if candidateNames.count > candidateCount {
                reachedLimit = true
            }
            let startIndex = maintenanceStartIndex(
                now: now,
                candidateCount: candidateNames.count
            )

            for offset in 0..<candidateCount {
                guard elapsedNanoseconds(since: startedAt)
                        < Self.maintenanceMaximumElapsedNanoseconds else {
                    reachedLimit = true
                    break
                }
                let name = candidateNames[
                    (startIndex + offset) % candidateNames.count
                ]
                inspectedEntryCount += 1
                guard let pathStatus = try statusIfPresent(
                    named: name,
                    directory: directory,
                    failure: .readFailed
                ) else {
                    continue
                }
                guard pathStatus.st_size >= 0 else { continue }
                let byteCount = Int64(pathStatus.st_size)
                guard byteCount <= Self.maintenanceMaximumByteCount,
                      inspectedByteCount
                        <= Self.maintenanceMaximumByteCount - byteCount else {
                    reachedLimit = true
                    continue
                }
                inspectedByteCount += byteCount
                guard isOldEnoughForMaintenance(pathStatus, now: now) else {
                    continue
                }

                do {
                    let descriptor = try openTemporaryForMaintenance(
                        named: name,
                        directory: directory
                    )
                    defer { adapter.closeFile(descriptor) }
                    let descriptorStatus = try status(
                        descriptor: descriptor,
                        failure: .readFailed
                    )
                    try validateJournalStatus(
                        descriptorStatus,
                        effectiveUserID: directory.effectiveUserID
                    )
                    guard IOSPendingRecordingJournalFileSnapshot(descriptorStatus)
                            == IOSPendingRecordingJournalFileSnapshot(pathStatus)
                    else {
                        continue
                    }
                    if descriptorStatus.st_size != 0 {
                        guard configuration.marker != nil else { continue }
                        do {
                            try validateExactConfiguration(
                                descriptor: descriptor
                            )
                        } catch IOSPendingRecordingJournalFileSystemError
                            .invalidFile {
                            continue
                        }
                    }
                    try validatePathIdentity(
                        named: name,
                        descriptorStatus: descriptorStatus,
                        directory: directory,
                        failure: .readFailed
                    )
                    guard elapsedNanoseconds(since: startedAt)
                            < Self.maintenanceMaximumElapsedNanoseconds else {
                        reachedLimit = true
                        break
                    }

                    switch retryInterrupted({
                        adapter.unlinkAt(
                            directoryDescriptor: directory.descriptor,
                            name: name
                        )
                    }) {
                    case .success:
                        removedFileCount += 1
                        removedByteCount += byteCount
                    case .failure(ENOENT):
                        continue
                    case .failure(let code) where isProtectedDataError(code):
                        throw IOSPendingRecordingJournalFileSystemError
                            .protectedDataUnavailable
                    case .failure:
                        throw IOSPendingRecordingJournalFileSystemError
                            .removeFailed
                    }
                } catch IOSPendingRecordingJournalFileSystemError.missing,
                        IOSPendingRecordingJournalFileSystemError.invalidFile,
                        IOSPendingRecordingJournalFileSystemError.readFailed {
                    continue
                }
            }
        } catch {
            if removedFileCount > 0 {
                try synchronizeDirectory(directory.descriptor)
            }
            throw error
        }

        if removedFileCount > 0 {
            try synchronizeDirectory(directory.descriptor)
        }
        return IOSStrictProtectedRecordMaintenanceReport(
            inspectedEntryCount: inspectedEntryCount,
            inspectedByteCount: inspectedByteCount,
            removedFileCount: removedFileCount,
            removedByteCount: removedByteCount,
            reachedLimit: reachedLimit
        )
    }
}

private extension FoundationIOSPendingRecordingJournalFileSystem {
    struct DirectoryHandle {
        let parentDescriptor: Int32
        let descriptor: Int32
        let repositoryRootIdentity: IOSPersistenceRepositoryRootIdentity
        let identity: FileIdentity
        let effectiveUserID: uid_t
    }

    struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t

        init(_ status: stat) {
            device = status.st_dev
            inode = status.st_ino
        }
    }

    struct TemporaryFile {
        let name: String
        let descriptor: Int32
        let identity: FileIdentity
    }

    func openDirectoryStream(
        directory: DirectoryHandle
    ) throws -> UnsafeMutablePointer<DIR> {
        let descriptorResult = retryInterrupted {
            adapter.openAt(
                directoryDescriptor: directory.parentDescriptor,
                name: configuration.rootDirectoryName,
                flags: O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW,
                mode: nil
            )
        }
        let descriptor: Int32
        switch descriptorResult {
        case .success(let value):
            descriptor = value
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.readFailed
        }

        do {
            let status = try status(
                descriptor: descriptor,
                failure: .readFailed
            )
            guard isDirectory(status),
                  status.st_uid == directory.effectiveUserID,
                  status.st_mode & mode_t(0o7777) == mode_t(0o700),
                  FileIdentity(status) == directory.identity else {
                throw IOSPendingRecordingJournalFileSystemError.readFailed
            }
        } catch {
            adapter.closeFile(descriptor)
            throw error
        }

        switch retryInterrupted({
            adapter.openDirectoryStream(fileDescriptor: descriptor)
        }) {
        case .success(let stream):
            return stream
        case .failure(let code) where isProtectedDataError(code):
            adapter.closeFile(descriptor)
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            adapter.closeFile(descriptor)
            throw IOSPendingRecordingJournalFileSystemError.readFailed
        }
    }

    func isTemporaryFileName(_ name: String) -> Bool {
        let prefix = ".\(configuration.fileName)."
        let suffix = ".tmp"
        guard name.hasPrefix(prefix),
              name.hasSuffix(suffix),
              name.count == prefix.count + 36 + suffix.count else {
            return false
        }
        let identifierStart = name.index(
            name.startIndex,
            offsetBy: prefix.count
        )
        let identifierEnd = name.index(identifierStart, offsetBy: 36)
        let value = String(name[identifierStart..<identifierEnd])
        guard let identifier = UUID(uuidString: value) else { return false }
        return value == identifier.uuidString.lowercased()
    }

    func elapsedNanoseconds(since startedAt: UInt64) -> UInt64 {
        let current = monotonicNowNanoseconds()
        return current >= startedAt ? current - startedAt : UInt64.max
    }

    func maintenanceStartIndex(
        now: Date,
        candidateCount: Int
    ) -> Int {
        guard candidateCount > 0 else { return 0 }
        let minute = (now.timeIntervalSince1970 / 60).rounded(.towardZero)
        let remainder = minute.truncatingRemainder(
            dividingBy: Double(candidateCount)
        )
        let normalized = remainder >= 0
            ? remainder
            : remainder + Double(candidateCount)
        return Int(normalized)
    }

    func isOldEnoughForMaintenance(
        _ status: stat,
        now: Date
    ) -> Bool {
        let modificationTime = Double(status.st_mtimespec.tv_sec)
            + Double(status.st_mtimespec.tv_nsec) / 1_000_000_000
        let age = now.timeIntervalSince1970 - modificationTime
        return modificationTime.isFinite
            && age.isFinite
            && age >= Self.maintenanceMinimumAge
    }

    func openTemporaryForMaintenance(
        named name: String,
        directory: DirectoryHandle
    ) throws -> Int32 {
        switch retryInterrupted({
            adapter.openAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
                mode: nil
            )
        }) {
        case .success(let descriptor):
            return descriptor
        case .failure(ENOENT):
            throw IOSPendingRecordingJournalFileSystemError.missing
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.readFailed
        }
    }

    func openJournalDirectory(
        createIfMissing: Bool,
        expectedRepositoryRoot:
            IOSPersistenceRepositoryRootIdentity? = nil
    ) throws -> DirectoryHandle? {
        let requiredRepositoryRoot = try requiredRepositoryRoot(
            operationExpectedRoot: expectedRepositoryRoot
        )
        guard applicationSupportDirectoryURL.isFileURL,
              !applicationSupportDirectoryURL.path.isEmpty,
              !applicationSupportDirectoryURL.path.utf8.contains(0),
              isValidPathComponent(configuration.rootDirectoryName),
              isValidPathComponent(configuration.fileName),
              configuration.maximumByteCount > 0,
              configuration.maximumByteCount < Int.max,
              configuration.marker.map({
                  !$0.name.isEmpty
                      && !$0.name.utf8.contains(0)
                      && !$0.value.isEmpty
              }) ?? true else {
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }

        let effectiveUserID: uid_t
        switch retryInterrupted({ adapter.effectiveUserID() }) {
        case .success(let value):
            effectiveUserID = value
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }

        let parentResult = retryInterrupted {
            adapter.openPath(
                applicationSupportDirectoryURL.path,
                flags: O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW,
                mode: nil
            )
        }
        let parentDescriptor: Int32
        switch parentResult {
        case .success(let value):
            parentDescriptor = value
        case .failure(ENOENT) where !createIfMissing:
            if requiredRepositoryRoot != nil {
                onRepositoryIdentityMismatch()
                throw IOSPendingRecordingJournalFileSystemError
                    .repositoryIdentityConflict
            }
            return nil
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure(let code):
            if requiredRepositoryRoot != nil,
               code == ENOENT || code == ELOOP || code == ENOTDIR {
                onRepositoryIdentityMismatch()
                throw IOSPendingRecordingJournalFileSystemError
                    .repositoryIdentityConflict
            }
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }

        var shouldCloseParent = true
        defer {
            if shouldCloseParent {
                adapter.closeFile(parentDescriptor)
            }
        }
        let parentStatus = try status(
            descriptor: parentDescriptor,
            failure: .invalidLocation
        )
        guard isDirectory(parentStatus),
              parentStatus.st_uid == effectiveUserID,
              requiredRepositoryRoot?.matches(parentStatus) ?? true else {
            if requiredRepositoryRoot != nil {
                onRepositoryIdentityMismatch()
                throw IOSPendingRecordingJournalFileSystemError
                    .repositoryIdentityConflict
            }
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }

        let rootName = configuration.rootDirectoryName
        var createdDirectory = false
        var rootStatus = try directoryStatusIfPresent(
            named: rootName,
            parentDescriptor: parentDescriptor,
            failure: .invalidLocation
        )
        if rootStatus == nil {
            guard createIfMissing else { return nil }
            switch retryInterrupted({
                adapter.makeDirectoryAt(
                    directoryDescriptor: parentDescriptor,
                    name: rootName,
                    mode: 0o700
                )
            }) {
            case .success:
                createdDirectory = true
            case .failure(EEXIST):
                break
            case .failure(let code) where isProtectedDataError(code):
                throw IOSPendingRecordingJournalFileSystemError
                    .protectedDataUnavailable
            case .failure:
                throw IOSPendingRecordingJournalFileSystemError.writeFailed
            }
            rootStatus = try directoryStatusIfPresent(
                named: rootName,
                parentDescriptor: parentDescriptor,
                failure: .invalidLocation
            )
        }

        guard let rootStatus,
              isDirectory(rootStatus),
              rootStatus.st_uid == effectiveUserID else {
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }

        let rootResult = retryInterrupted {
            adapter.openAt(
                directoryDescriptor: parentDescriptor,
                name: rootName,
                flags: O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW,
                mode: nil
            )
        }
        let rootDescriptor: Int32
        switch rootResult {
        case .success(let value):
            rootDescriptor = value
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }
        var shouldCloseRoot = true
        defer {
            if shouldCloseRoot {
                adapter.closeFile(rootDescriptor)
            }
        }

        let rootModeNeedsTightening =
            rootStatus.st_mode & mode_t(0o7777) != mode_t(0o700)
        if createdDirectory || rootModeNeedsTightening {
            try requireSuccess(
                retryInterrupted {
                    adapter.changeMode(
                        fileDescriptor: rootDescriptor,
                        mode: 0o700
                    )
                },
                failure: .writeFailed
            )
        }

        let openedStatus = try status(
            descriptor: rootDescriptor,
            failure: .invalidLocation
        )
        guard isDirectory(openedStatus),
              openedStatus.st_uid == effectiveUserID,
              openedStatus.st_mode & mode_t(0o7777) == mode_t(0o700),
              FileIdentity(openedStatus) == FileIdentity(rootStatus) else {
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }

        if createdDirectory || rootModeNeedsTightening {
            try synchronizeDirectory(rootDescriptor)
            try synchronizeDirectory(parentDescriptor)
        }

        shouldCloseParent = false
        shouldCloseRoot = false
        return DirectoryHandle(
            parentDescriptor: parentDescriptor,
            descriptor: rootDescriptor,
            repositoryRootIdentity: IOSPersistenceRepositoryRootIdentity(
                device: parentStatus.st_dev,
                inode: parentStatus.st_ino
            ),
            identity: FileIdentity(openedStatus),
            effectiveUserID: effectiveUserID
        )
    }

    func close(_ directory: DirectoryHandle) {
        adapter.closeFile(directory.descriptor)
        adapter.closeFile(directory.parentDescriptor)
    }

    func lockDirectoryForMutation(_ directory: DirectoryHandle) throws {
        switch retryInterrupted({
            adapter.lock(
                fileDescriptor: directory.descriptor,
                operation: LOCK_EX | LOCK_NB
            )
        }) {
        case .success:
            return
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        }
    }

    func validateDirectoryIdentity(_ directory: DirectoryHandle) throws {
        let descriptorStatus = try status(
            descriptor: directory.descriptor,
            failure: .invalidLocation
        )
        guard isDirectory(descriptorStatus),
              descriptorStatus.st_uid == directory.effectiveUserID,
              descriptorStatus.st_mode & mode_t(0o7777) == mode_t(0o700),
              FileIdentity(descriptorStatus) == directory.identity,
              let pathStatus = try directoryStatusIfPresent(
                  named: configuration.rootDirectoryName,
                  parentDescriptor: directory.parentDescriptor,
                  failure: .invalidLocation
              ),
              isDirectory(pathStatus),
              pathStatus.st_uid == directory.effectiveUserID,
              pathStatus.st_mode & mode_t(0o7777) == mode_t(0o700),
              FileIdentity(pathStatus) == directory.identity else {
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }
    }

    func confirmMetadataAbsenceAfterRemoval(
        sourceRevision: IOSPendingRecordingJournalFileRevision,
        directory: DirectoryHandle
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence {
        var removalIsUncertain = false

        // The unlink boundary has already been crossed. Keep attempting the
        // durability barrier and the second path observation even if the first
        // post-unlink observation fails; no later failure may be reported as a
        // plain remove failure.
        do {
            guard try statusIfPresent(
                named: configuration.fileName,
                directory: directory,
                failure: .readFailed
            ) == nil else {
                throw IOSPendingRecordingJournalFileSystemError.staleRevision
            }
            try validateDirectoryIdentity(directory)
        } catch {
            removalIsUncertain = true
        }

        do {
            try synchronizeDirectory(directory.descriptor)
        } catch {
            removalIsUncertain = true
        }

        beforeMetadataAbsenceFinalCheck()

        do {
            guard try statusIfPresent(
                named: configuration.fileName,
                directory: directory,
                failure: .readFailed
            ) == nil else {
                throw IOSPendingRecordingJournalFileSystemError.staleRevision
            }
            try validateDirectoryIdentity(directory)
        } catch {
            removalIsUncertain = true
        }

        guard !removalIsUncertain else {
            throw IOSPendingRecordingJournalFileSystemError.commitUncertain
        }
        return .removed(
            IOSPendingRecordingJournalMetadataAbsenceEvidence.Removed(
                sourceRevision: sourceRevision,
                binding: metadataAbsenceBinding(directory: directory)
            )
        )
    }

    func metadataAbsenceBinding(
        directory: DirectoryHandle
    ) -> IOSPendingRecordingJournalMetadataAbsenceEvidence.Binding {
        IOSPendingRecordingJournalMetadataAbsenceEvidence.Binding(
            repositoryRoot: directory.repositoryRootIdentity,
            journalDirectory: IOSPendingRecordingJournalDirectoryIdentity(
                device: directory.identity.device,
                inode: directory.identity.inode
            ),
            pathIdentity: .pendingRecording
        )
    }

    func requirePendingRecordingMetadataConfiguration() throws {
        guard configuration == .pendingRecording else {
            throw IOSPendingRecordingJournalFileSystemError.invalidLocation
        }
    }

    func commitTemporaryFile(
        data: Data,
        directory: DirectoryHandle,
        expected: IOSPendingRecordingJournalFileRevision?,
        createOnly: Bool
    ) throws -> IOSPendingRecordingJournalFileRevision {
        let temporary = try createTemporaryFile(directory: directory)
        var shouldRemoveTemporary = true
        defer {
            adapter.closeFile(temporary.descriptor)
            if shouldRemoveTemporary {
                removeTemporaryIfOwned(temporary, directory: directory)
            }
        }

        try validateDirectoryIdentity(directory)
        try configureTemporaryFile(
            temporary,
            directory: directory
        )
        try write(data, to: temporary.descriptor)
        try synchronizeFile(temporary.descriptor)
        try validateOwnedTemporaryFile(
            temporary,
            directory: directory,
            expectedByteCount: data.count
        )
        try validateExactConfiguration(descriptor: temporary.descriptor)
        try validateDirectoryIdentity(directory)

        if let expected {
            try validateCurrentFile(directory: directory, expected: expected)
        } else if try statusIfPresent(
            named: configuration.fileName,
            directory: directory,
            failure: .writeFailed
        ) != nil {
            throw IOSPendingRecordingJournalFileSystemError.destinationConflict
        }

        let prepublishStatus = try status(
            descriptor: temporary.descriptor,
            failure: .writeFailed
        )
        try validateJournalStatus(
            prepublishStatus,
            effectiveUserID: directory.effectiveUserID
        )
        guard prepublishStatus.st_size == off_t(data.count),
              FileIdentity(prepublishStatus) == temporary.identity else {
            throw IOSPendingRecordingJournalFileSystemError.writeFailed
        }

        let publishResult: IOSPendingRecordingPOSIXResult<Void>
        if createOnly {
            publishResult = retryInterrupted {
                adapter.publishExclusively(
                    directoryDescriptor: directory.descriptor,
                    temporaryName: temporary.name,
                    finalName: configuration.fileName
                )
            }
        } else {
            publishResult = retryInterrupted {
                replaceOperation(
                    directory.descriptor,
                    temporary.name,
                    configuration.fileName
                )
            }
        }
        switch publishResult {
        case .success:
            shouldRemoveTemporary = false
        case .failure(EEXIST) where createOnly:
            if finalPathMayReferenceTemporary(
                temporary,
                directory: directory
            ) != false {
                throw IOSPendingRecordingJournalFileSystemError.commitUncertain
            }
            throw IOSPendingRecordingJournalFileSystemError.destinationConflict
        case .failure(ENOENT) where !createOnly:
            if finalPathMayReferenceTemporary(
                temporary,
                directory: directory
            ) != false {
                throw IOSPendingRecordingJournalFileSystemError.commitUncertain
            }
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        case .failure where finalPathMayReferenceTemporary(
            temporary,
            directory: directory
        ) != false:
            throw IOSPendingRecordingJournalFileSystemError.commitUncertain
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.writeFailed
        }

        // Rename makes the new bytes visible. It is not a confirmed durable
        // commit until descriptor/path policy and the containing directory are
        // revalidated and the directory entry is synchronized. Never roll back
        // or clean the visible journal if one of these post-commit steps fails.
        var publishedStatus: stat?
        var postCommitFailed = false
        do {
            let preconfigurationStatus = try status(
                descriptor: temporary.descriptor,
                failure: .writeFailed
            )
            try validateJournalStatus(
                preconfigurationStatus,
                effectiveUserID: directory.effectiveUserID
            )
            guard preconfigurationStatus.st_size == off_t(data.count),
                  FileIdentity(preconfigurationStatus) == temporary.identity else {
                throw IOSPendingRecordingJournalFileSystemError.writeFailed
            }
            try validatePathIdentity(
                named: configuration.fileName,
                descriptorStatus: preconfigurationStatus,
                directory: directory,
                failure: .writeFailed
            )
            try requireConfigurationSuccess(
                retryInterrupted {
                    adapter.setExtendedAttribute(
                        fileDescriptor: temporary.descriptor,
                        name: Self.backupExclusionAttributeName,
                        value: Self.backupExclusionAttributeValue,
                        flags: 0
                    )
                }
            )
            try synchronizeFile(temporary.descriptor)
            try validateExactConfiguration(descriptor: temporary.descriptor)
            let finalStatus = try status(
                descriptor: temporary.descriptor,
                failure: .writeFailed
            )
            try validateJournalStatus(
                finalStatus,
                effectiveUserID: directory.effectiveUserID
            )
            guard finalStatus.st_size == off_t(data.count),
                  FileIdentity(finalStatus) == temporary.identity else {
                throw IOSPendingRecordingJournalFileSystemError.writeFailed
            }
            try validatePathIdentity(
                named: configuration.fileName,
                descriptorStatus: finalStatus,
                directory: directory,
                failure: .writeFailed
            )
            try validateDirectoryIdentity(directory)
            publishedStatus = finalStatus
        } catch {
            postCommitFailed = true
        }

        // Attempt the durability barrier even when an earlier post-rename
        // policy check failed; both outcomes remain commit-uncertain.
        do {
            try synchronizeDirectory(directory.descriptor)
        } catch {
            postCommitFailed = true
        }

        guard !postCommitFailed, let publishedStatus else {
            throw IOSPendingRecordingJournalFileSystemError.commitUncertain
        }
        return IOSPendingRecordingJournalFileRevision(
            snapshot: IOSPendingRecordingJournalFileSnapshot(publishedStatus)
        )
    }

    func finalPathMayReferenceTemporary(
        _ temporary: TemporaryFile,
        directory: DirectoryHandle
    ) -> Bool? {
        do {
            guard let finalStatus = try statusIfPresent(
                named: configuration.fileName,
                directory: directory,
                failure: .writeFailed
            ) else {
                return false
            }
            return FileIdentity(finalStatus) == temporary.identity
        } catch {
            return nil
        }
    }

    func createTemporaryFile(
        directory: DirectoryHandle
    ) throws -> TemporaryFile {
        let name = ".\(configuration.fileName)."
            + UUID().uuidString.lowercased()
            + ".tmp"
        let result = retryInterrupted {
            adapter.openAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode: 0o600
            )
        }
        let descriptor: Int32
        switch result {
        case .success(let value):
            descriptor = value
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.writeFailed
        }

        let initialStatus: stat
        do {
            initialStatus = try status(
                descriptor: descriptor,
                failure: .writeFailed
            )
            guard isRegularFile(initialStatus),
                  initialStatus.st_uid == directory.effectiveUserID,
                  initialStatus.st_nlink == 1,
                  initialStatus.st_size == 0 else {
                throw IOSPendingRecordingJournalFileSystemError.writeFailed
            }
        } catch {
            adapter.closeFile(descriptor)
            throw error
        }

        let temporary = TemporaryFile(
            name: name,
            descriptor: descriptor,
            identity: FileIdentity(initialStatus)
        )
        do {
            try requireSuccess(
                retryInterrupted {
                    adapter.changeMode(
                        fileDescriptor: descriptor,
                        mode: 0o600
                    )
                },
                failure: .writeFailed
            )
            let status = try status(
                descriptor: descriptor,
                failure: .writeFailed
            )
            try validateJournalStatus(
                status,
                effectiveUserID: directory.effectiveUserID
            )
            guard status.st_size == 0 else {
                throw IOSPendingRecordingJournalFileSystemError.writeFailed
            }
            guard FileIdentity(status) == temporary.identity else {
                throw IOSPendingRecordingJournalFileSystemError.writeFailed
            }
            return temporary
        } catch {
            adapter.closeFile(descriptor)
            removeTemporaryIfOwned(temporary, directory: directory)
            throw error
        }
    }

    func configureTemporaryFile(
        _ temporary: TemporaryFile,
        directory: DirectoryHandle
    ) throws {
        try validateOwnedTemporaryFile(
            temporary,
            directory: directory,
            expectedByteCount: 0
        )
        try requireConfigurationSuccess(
            retryInterrupted {
                adapter.setProtectionClass(
                    fileDescriptor: temporary.descriptor,
                    protectionClass: Self.completeProtectionClass
                )
            }
        )
        try requireConfigurationSuccess(
            retryInterrupted {
                adapter.setExtendedAttribute(
                    fileDescriptor: temporary.descriptor,
                    name: Self.backupExclusionAttributeName,
                    value: Self.backupExclusionAttributeValue,
                    flags: XATTR_CREATE
                )
            }
        )
        if let marker = configuration.marker {
            try requireConfigurationSuccess(
                retryInterrupted {
                    adapter.setExtendedAttribute(
                        fileDescriptor: temporary.descriptor,
                        name: marker.name,
                        value: marker.value,
                        flags: XATTR_CREATE
                    )
                }
            )
        }
        try validateExactConfiguration(descriptor: temporary.descriptor)
        try validateOwnedTemporaryFile(
            temporary,
            directory: directory,
            expectedByteCount: 0
        )
    }

    func validateExactConfiguration(descriptor: Int32) throws {
        let protectionResult = retryInterrupted {
            adapter.protectionClass(fileDescriptor: descriptor)
        }
        switch protectionResult {
        case .success(Self.completeProtectionClass):
            break
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        default:
            throw IOSPendingRecordingJournalFileSystemError.invalidFile
        }

        let backupResult = retryInterrupted {
            adapter.extendedAttribute(
                fileDescriptor: descriptor,
                name: Self.backupExclusionAttributeName,
                maximumByteCount: Self.backupExclusionAttributeValue.count + 1
            )
        }
        switch backupResult {
        case .success(Self.backupExclusionAttributeValue):
            break
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        default:
            throw IOSPendingRecordingJournalFileSystemError.invalidFile
        }

        if let marker = configuration.marker {
            let markerResult = retryInterrupted {
                adapter.extendedAttribute(
                    fileDescriptor: descriptor,
                    name: marker.name,
                    maximumByteCount: marker.value.count + 1
                )
            }
            switch markerResult {
            case .success(marker.value):
                break
            case .failure(let code) where isProtectedDataError(code):
                throw IOSPendingRecordingJournalFileSystemError
                    .protectedDataUnavailable
            default:
                throw IOSPendingRecordingJournalFileSystemError.invalidFile
            }
        }
    }

    func validateCurrentFile(
        directory: DirectoryHandle,
        expected: IOSPendingRecordingJournalFileRevision,
        requiresExactConfiguration: Bool = true
    ) throws {
        guard let pathStatus = try statusIfPresent(
            named: configuration.fileName,
            directory: directory,
            failure: .writeFailed
        ) else {
            throw IOSPendingRecordingJournalFileSystemError.missing
        }
        try validateJournalStatus(
            pathStatus,
            effectiveUserID: directory.effectiveUserID
        )
        guard let expectedSnapshot = expected.snapshot,
              IOSPendingRecordingJournalFileSnapshot(pathStatus)
                == expectedSnapshot else {
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        }

        let descriptor = try openJournalForReading(directory: directory)
        defer { adapter.closeFile(descriptor) }
        let descriptorStatus = try status(
            descriptor: descriptor,
            failure: .writeFailed
        )
        try validateJournalStatus(
            descriptorStatus,
            effectiveUserID: directory.effectiveUserID
        )
        guard IOSPendingRecordingJournalFileSnapshot(descriptorStatus)
                == expectedSnapshot else {
            throw IOSPendingRecordingJournalFileSystemError.staleRevision
        }
        if requiresExactConfiguration {
            try validateExactConfiguration(descriptor: descriptor)
        }
        try validatePathIdentity(
            named: configuration.fileName,
            descriptorStatus: descriptorStatus,
            directory: directory,
            failure: .writeFailed
        )
    }

    func openJournalForReading(
        directory: DirectoryHandle
    ) throws -> Int32 {
        let result = retryInterrupted {
            adapter.openAt(
                directoryDescriptor: directory.descriptor,
                name: configuration.fileName,
                flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
                mode: nil
            )
        }
        switch result {
        case .success(let descriptor):
            return descriptor
        case .failure(ENOENT):
            throw IOSPendingRecordingJournalFileSystemError.missing
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.readFailed
        }
    }

    func openJournalForMutation(
        directory: DirectoryHandle
    ) throws -> Int32 {
        let result = retryInterrupted {
            adapter.openAt(
                directoryDescriptor: directory.descriptor,
                name: configuration.fileName,
                flags: O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
                mode: nil
            )
        }
        switch result {
        case .success(let descriptor):
            return descriptor
        case .failure(ENOENT):
            throw IOSPendingRecordingJournalFileSystemError.missing
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.writeFailed
        }
    }

    /// A Pending journal carrying an audio-removal intent owns the exact audio
    /// retirement recovery. Generic replacement/removal must not erase that
    /// cross-process authority; only descriptor-bound metadata retirement may
    /// unlink the journal after audio absence has been proven.
    func requireNoAudioRemovalIntent(
        directory: DirectoryHandle
    ) throws {
        guard configuration == .pendingRecording else { return }
        let descriptor = try openJournalForReading(directory: directory)
        defer { adapter.closeFile(descriptor) }
        let result = retryInterrupted {
            adapter.extendedAttribute(
                fileDescriptor: descriptor,
                name: IOSPendingRecordingAudioRemovalIntent
                    .extendedAttributeName,
                maximumByteCount:
                    IOSPendingRecordingAudioRemovalIntent.encodedByteCount + 1
            )
        }
        switch result {
        case .failure(ENOATTR):
            return
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .success:
            throw IOSPendingRecordingJournalFileSystemError.commitUncertain
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.invalidFile
        }
    }

    func validateOwnedTemporaryFile(
        _ temporary: TemporaryFile,
        directory: DirectoryHandle,
        expectedByteCount: Int
    ) throws {
        let descriptorStatus = try status(
            descriptor: temporary.descriptor,
            failure: .writeFailed
        )
        try validateJournalStatus(
            descriptorStatus,
            effectiveUserID: directory.effectiveUserID
        )
        guard FileIdentity(descriptorStatus) == temporary.identity,
              descriptorStatus.st_size == off_t(expectedByteCount) else {
            throw IOSPendingRecordingJournalFileSystemError.writeFailed
        }
        try validatePathIdentity(
            named: temporary.name,
            descriptorStatus: descriptorStatus,
            directory: directory,
            failure: .writeFailed
        )
    }

    func validatePathIdentity(
        named name: String,
        descriptorStatus: stat,
        directory: DirectoryHandle,
        failure: IOSPendingRecordingJournalFileSystemError
    ) throws {
        guard let pathStatus = try statusIfPresent(
            named: name,
            directory: directory,
            failure: failure
        ) else {
            throw failure
        }
        try validateJournalStatus(
            pathStatus,
            effectiveUserID: directory.effectiveUserID
        )
        guard IOSPendingRecordingJournalFileSnapshot(pathStatus)
                == IOSPendingRecordingJournalFileSnapshot(descriptorStatus) else {
            throw failure
        }
    }

    func validateJournalStatus(
        _ status: stat,
        effectiveUserID: uid_t
    ) throws {
        guard isRegularFile(status),
              status.st_uid == effectiveUserID,
              status.st_nlink == 1,
              status.st_mode & mode_t(0o7777) == mode_t(0o600) else {
            throw IOSPendingRecordingJournalFileSystemError.invalidFile
        }
    }

    func readBoundedData(from descriptor: Int32) throws -> Data {
        let maximumByteCount = configuration.maximumByteCount
        var data = Data()
        var buffer = [UInt8](
            repeating: 0,
            count: Self.transferChunkByteCount
        )

        while true {
            let remaining = maximumByteCount - data.count
            let requestCount = min(buffer.count, remaining + 1)
            let result = buffer.withUnsafeMutableBytes { bytes in
                retryInterrupted {
                    adapter.read(
                        fileDescriptor: descriptor,
                        buffer: bytes.baseAddress!,
                        byteCount: requestCount
                    )
                }
            }
            switch result {
            case .success(0):
                return data
            case .success(let count) where count > 0 && count <= remaining:
                data.append(contentsOf: buffer.prefix(count))
            case .success:
                throw IOSPendingRecordingJournalFileSystemError.sourceTooLarge
            case .failure(let code) where isProtectedDataError(code):
                throw IOSPendingRecordingJournalFileSystemError
                    .protectedDataUnavailable
            case .failure:
                throw IOSPendingRecordingJournalFileSystemError.readFailed
            }
        }
    }

    func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = min(
                    Self.transferChunkByteCount,
                    bytes.count - offset
                )
                let pointer = bytes.baseAddress!.advanced(by: offset)
                let result = retryInterrupted {
                    adapter.write(
                        fileDescriptor: descriptor,
                        buffer: pointer,
                        byteCount: count
                    )
                }
                switch result {
                case .success(let written) where written > 0 && written <= count:
                    offset += written
                case .failure(let code) where isProtectedDataError(code):
                    throw IOSPendingRecordingJournalFileSystemError
                        .protectedDataUnavailable
                default:
                    throw IOSPendingRecordingJournalFileSystemError.writeFailed
                }
            }
        }
    }

    func validateWriteData(_ data: Data) throws {
        guard !data.isEmpty else {
            throw IOSPendingRecordingJournalFileSystemError.writeFailed
        }
        guard data.count <= configuration.maximumByteCount else {
            throw IOSPendingRecordingJournalFileSystemError.sourceTooLarge
        }
    }

    func synchronizeFile(_ descriptor: Int32) throws {
        let result = retryInterrupted {
            adapter.synchronize(fileDescriptor: descriptor)
        }
        switch result {
        case .success:
            return
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError
                .synchronizationFailed
        }
    }

    func synchronizeDirectory(_ descriptor: Int32) throws {
        switch retryInterrupted({
            if let directorySynchronizationOperation {
                directorySynchronizationOperation(descriptor)
            } else {
                adapter.synchronize(fileDescriptor: descriptor)
            }
        }) {
        case .success:
            return
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError
                .synchronizationFailed
        }
    }

    func status(
        descriptor: Int32,
        failure: IOSPendingRecordingJournalFileSystemError
    ) throws -> stat {
        switch retryInterrupted({ adapter.status(of: descriptor) }) {
        case .success(let value):
            return value
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw failure
        }
    }

    func statusIfPresent(
        named name: String,
        directory: DirectoryHandle,
        failure: IOSPendingRecordingJournalFileSystemError
    ) throws -> stat? {
        switch retryInterrupted({
            adapter.statusAt(
                directoryDescriptor: directory.descriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }) {
        case .success(let value):
            return value
        case .failure(ENOENT):
            return nil
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw failure
        }
    }

    func directoryStatusIfPresent(
        named name: String,
        parentDescriptor: Int32,
        failure: IOSPendingRecordingJournalFileSystemError
    ) throws -> stat? {
        switch retryInterrupted({
            adapter.statusAt(
                directoryDescriptor: parentDescriptor,
                name: name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }) {
        case .success(let value):
            return value
        case .failure(ENOENT):
            return nil
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw failure
        }
    }

    func removeTemporaryIfOwned(
        _ temporary: TemporaryFile,
        directory: DirectoryHandle
    ) {
        guard case .success(let pathStatus) = retryInterrupted({
            adapter.statusAt(
                directoryDescriptor: directory.descriptor,
                name: temporary.name,
                flags: AT_SYMLINK_NOFOLLOW
            )
        }),
        FileIdentity(pathStatus) == temporary.identity else {
            return
        }
        _ = retryInterrupted {
            adapter.unlinkAt(
                directoryDescriptor: directory.descriptor,
                name: temporary.name
            )
        }
    }

    func requireSuccess<Value>(
        _ result: IOSPendingRecordingPOSIXResult<Value>,
        failure: IOSPendingRecordingJournalFileSystemError
    ) throws {
        switch result {
        case .success:
            return
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw failure
        }
    }

    func requireConfigurationSuccess<Value>(
        _ result: IOSPendingRecordingPOSIXResult<Value>
    ) throws {
        switch result {
        case .success:
            return
        case .failure(let code) where isProtectedDataError(code):
            throw IOSPendingRecordingJournalFileSystemError
                .protectedDataUnavailable
        case .failure:
            throw IOSPendingRecordingJournalFileSystemError.invalidFile
        }
    }

    func retryInterrupted<Value>(
        _ operation: () -> IOSPendingRecordingPOSIXResult<Value>
    ) -> IOSPendingRecordingPOSIXResult<Value> {
        var interruptionCount = 0
        while true {
            let result = operation()
            guard case .failure(EINTR) = result,
                  interruptionCount < Self.maximumInterruptedRetryCount else {
                return result
            }
            interruptionCount += 1
        }
    }

    func isRegularFile(_ status: stat) -> Bool {
        status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
    }

    func isDirectory(_ status: stat) -> Bool {
        status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
    }

    func isProtectedDataError(_ code: Int32) -> Bool {
        code == EACCES || code == EPERM
    }

    func isValidPathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.utf8.contains(0)
    }

    func requiredRepositoryRoot(
        operationExpectedRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPersistenceRepositoryRootIdentity? {
        if let operationExpectedRoot,
           let configuredExpectedRepositoryRoot,
           operationExpectedRoot != configuredExpectedRepositoryRoot {
            onRepositoryIdentityMismatch()
            throw IOSPendingRecordingJournalFileSystemError
                .repositoryIdentityConflict
        }
        return operationExpectedRoot ?? configuredExpectedRepositoryRoot
    }
}

private func liveIOSPendingRecordingJournalReplace(
    directoryDescriptor: Int32,
    temporaryName: String,
    destinationName: String
) -> IOSPendingRecordingPOSIXResult<Void> {
    let result = temporaryName.withCString { temporaryName in
        destinationName.withCString { destinationName in
            Darwin.renameat(
                directoryDescriptor,
                temporaryName,
                directoryDescriptor,
                destinationName
            )
        }
    }
    return result == 0 ? .success(()) : .failure(errno)
}

typealias FoundationIOSStrictProtectedRecordFileSystem =
    FoundationIOSPendingRecordingJournalFileSystem
