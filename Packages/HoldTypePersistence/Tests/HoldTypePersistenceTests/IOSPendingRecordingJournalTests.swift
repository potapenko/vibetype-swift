import Darwin
import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSPendingRecordingJournalTests {
    @Test func canonicalV1HasExactlyTwelveKeysAndExplicitNulls() throws {
        let recording = try fixtureRecording()

        let data = try IOSPendingRecordingJournalWireCodec.encode(recording)

        let expected =
            #"{"attemptID":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","audioRelativeIdentifier":"Recordings/Pending/recording-v1-aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee.m4a","byteCount":12345,"createdAt":"2026-07-10T09:08:07.006Z","durationMilliseconds":4321,"outputIntent":"standard","phase":"readyForTranscription","schemaVersion":1,"transcriptionID":null,"transcriptionLanguageCode":null,"transcriptionModel":"gpt-4o-mini-transcribe","updatedAt":"2026-07-10T09:08:08.007Z"}"#
        #expect(data == Data(expected.utf8))
        #expect(try IOSPendingRecordingJournalWireCodec.decode(data) == recording)

        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(Set(object.keys) == IOSPendingRecordingJournalWireCodec.fields)
        #expect(object.count == 12)
        #expect(object["transcriptionID"] is NSNull)
        #expect(object["transcriptionLanguageCode"] is NSNull)
        requireSendable(FoundationIOSPendingRecordingJournalRepository.self)
    }

    @Test func everyDurablePhaseUsesItsExactVersionedSpelling() throws {
        let transcriptionID = try #require(
            UUID(uuidString: "11111111-2222-4333-8444-555555555555")
        )
        let fixtures: [(IOSPendingRecordingPhase, UUID?, String)] = [
            (.readyForTranscription, nil, "readyForTranscription"),
            (.awaitingRecovery, nil, "awaitingRecovery"),
            (.transcribing, transcriptionID, "transcribing"),
            (.postProcessing, transcriptionID, "postProcessing"),
            (.outputDelivery, transcriptionID, "outputDelivery"),
        ]

        for (phase, identifier, rawValue) in fixtures {
            let recording = try fixtureRecording(
                phase: phase,
                transcriptionID: identifier,
                outputIntent: .translate,
                languageCode: "sr"
            )
            let data = try IOSPendingRecordingJournalWireCodec.encode(recording)
            let object = try #require(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            #expect(object["phase"] as? String == rawValue)
            #expect(object["outputIntent"] as? String == "translate")
            #expect(object["transcriptionLanguageCode"] as? String == "sr")
            #expect(try IOSPendingRecordingJournalWireCodec.decode(data) == recording)
        }
    }

    @Test func timestampCodecRoundsToCanonicalUTCMilliseconds() throws {
        let source = Date(timeIntervalSince1970: 1_700_000_000.123_6)
        let canonical = try IOSPendingRecordingTimestampCodec.canonicalDate(
            from: source
        )

        #expect(
            canonical.timeIntervalSince1970
                == Date(timeIntervalSince1970: 1_700_000_000.124)
                    .timeIntervalSince1970
        )
        let encoded = try IOSPendingRecordingTimestampCodec.string(from: source)
        #expect(encoded == "2023-11-14T22:13:20.124Z")
        #expect(
            try IOSPendingRecordingTimestampCodec.date(from: encoded)
                == canonical
        )
    }

    @Test func malformedDuplicateAndOversizedJSONStayTyped() throws {
        let valid = try IOSPendingRecordingJournalWireCodec.encode(
            fixtureRecording()
        )
        let validString = try #require(String(data: valid, encoding: .utf8))
        let duplicate = validString.replacingOccurrences(
            of: #""schemaVersion":1"#,
            with: #""schemaVersion":1,"schemaVersion":1"#
        )
        let deeplyNested = #"{"schemaVersion":1,"attacker":"#
            + String(repeating: "[", count: 65)
            + "0"
            + String(repeating: "]", count: 65)
            + "}"

        try expectDecodeError(
            Data("not-json".utf8),
            .journalMalformed
        )
        try expectDecodeError(
            Data(duplicate.utf8),
            .journalMalformed
        )
        try expectDecodeError(
            Data(deeplyNested.utf8),
            .journalMalformed
        )
        try expectDecodeError(
            Data(
                repeating: 0x20,
                count: FoundationIOSPendingRecordingJournalRepository
                    .maximumJournalByteCount + 1
            ),
            .journalTooLarge
        )
    }

    @Test func unsupportedVersionWinsBeforeV1ShapeValidation() throws {
        try expectDecodeError(
            Data(#"{"schemaVersion":2,"opaqueFutureField":[1,2,3]}"#.utf8),
            .unsupportedJournalVersion
        )
    }

    @Test func missingUnknownWrongTypeAndNoncanonicalValuesAreRejected() throws {
        let valid = try IOSPendingRecordingJournalWireCodec.encode(
            fixtureRecording()
        )
        let attemptID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        let otherAttemptID = "ffffffff-1111-4222-8333-444444444444"

        var fixtures: [Data] = []
        fixtures.append(try modifying(valid) { $0.removeValue(forKey: "byteCount") })
        fixtures.append(try modifying(valid) { $0["unknown"] = true })
        fixtures.append(try modifying(valid) { $0["transcriptionID"] = 7 })
        fixtures.append(try modifying(valid) { $0["durationMilliseconds"] = true })
        fixtures.append(try modifying(valid) { $0["durationMilliseconds"] = 0 })
        fixtures.append(try modifying(valid) { $0["durationMilliseconds"] = 300_000 })
        fixtures.append(try modifying(valid) { $0["byteCount"] = 25_000_000 })
        fixtures.append(try modifying(valid) {
            $0["attemptID"] = attemptID.uppercased()
        })
        fixtures.append(try modifying(valid) {
            $0["audioRelativeIdentifier"] =
                "Recordings/Pending/recording-v1-\(otherAttemptID).m4a"
        })
        fixtures.append(try modifying(valid) {
            $0["createdAt"] = "2026-07-10T09:08:07Z"
        })
        fixtures.append(try modifying(valid) {
            $0["updatedAt"] = "2026-07-10T11:08:08.007+02:00"
        })
        fixtures.append(try modifying(valid) {
            $0["updatedAt"] = "2026-07-10T09:08:06.007Z"
        })
        fixtures.append(try modifying(valid) { $0["phase"] = "recording" })
        fixtures.append(try modifying(valid) {
            $0["phase"] = "transcribing"
            $0["transcriptionID"] = NSNull()
        })
        fixtures.append(try modifying(valid) {
            $0["transcriptionModel"] = " model "
        })
        fixtures.append(try modifying(valid) {
            $0["transcriptionLanguageCode"] = "EN"
        })
        fixtures.append(try modifying(valid) {
            $0["outputIntent"] = "translate-and-copy"
        })

        let validString = try #require(String(data: valid, encoding: .utf8))
        fixtures.append(
            Data(
                validString.replacingOccurrences(
                    of: #""schemaVersion":1"#,
                    with: #""schemaVersion":1.0"#
                ).utf8
            )
        )
        fixtures.append(
            Data(
                validString.replacingOccurrences(
                    of: #""byteCount":12345"#,
                    with: #""byteCount":1.2345e4"#
                ).utf8
            )
        )

        for fixture in fixtures {
            try expectDecodeError(fixture, .invalidJournal)
        }
    }

    @Test func repositoryCreateLoadReplaceAndRemoveUseFileRevisionCAS() throws {
        let fileSystem = IOSPendingRecordingJournalFileSystemFake()
        let repository = FoundationIOSPendingRecordingJournalRepository(
            fileSystem: fileSystem
        )
        let initial = try fixtureRecording()

        #expect(try repository.load() == nil)
        try repository.create(initial)
        #expect(try repository.load() == initial)

        let updated = try fixtureRecording(
            phase: .awaitingRecovery,
            transcriptionID: nil,
            updatedAt: "2026-07-10T09:08:09.008Z"
        )
        try repository.replace(updated, expected: initial)
        #expect(try repository.load() == updated)
        #expect(try repository.remove(expected: updated))
        #expect(try repository.load() == nil)
        #expect(try repository.remove(expected: updated) == false)
    }

    @Test func repositoryPreservesOccupiedCorruptAndFutureSlots() throws {
        let occupiedFileSystem = IOSPendingRecordingJournalFileSystemFake()
        let occupiedRepository = FoundationIOSPendingRecordingJournalRepository(
            fileSystem: occupiedFileSystem
        )
        let recording = try fixtureRecording()
        try occupiedRepository.create(recording)
        try expectError(.pendingSlotOccupied) {
            try occupiedRepository.create(recording)
        }
        #expect(occupiedFileSystem.removeCallCount == 0)

        let corrupt = Data("not-json".utf8)
        let corruptFileSystem = IOSPendingRecordingJournalFileSystemFake(
            data: corrupt
        )
        let corruptRepository = FoundationIOSPendingRecordingJournalRepository(
            fileSystem: corruptFileSystem
        )
        try expectError(.journalMalformed) {
            _ = try corruptRepository.load()
        }
        #expect(corruptFileSystem.data == corrupt)
        #expect(corruptFileSystem.removeCallCount == 0)

        let future = Data(#"{"schemaVersion":9,"opaque":"keep"}"#.utf8)
        let futureFileSystem = IOSPendingRecordingJournalFileSystemFake(
            data: future
        )
        let futureRepository = FoundationIOSPendingRecordingJournalRepository(
            fileSystem: futureFileSystem
        )
        try expectError(.unsupportedJournalVersion) {
            _ = try futureRepository.load()
        }
        #expect(futureFileSystem.data == future)
        #expect(futureFileSystem.removeCallCount == 0)
    }

    @Test func repositoryRejectsValueAndRevisionCASMismatches() throws {
        let fileSystem = IOSPendingRecordingJournalFileSystemFake()
        let repository = FoundationIOSPendingRecordingJournalRepository(
            fileSystem: fileSystem
        )
        let current = try fixtureRecording()
        try repository.create(current)
        let replacement = try fixtureRecording(
            phase: .awaitingRecovery,
            updatedAt: "2026-07-10T09:08:09.008Z"
        )
        let wrongExpected = try fixtureRecording(
            phase: .awaitingRecovery,
            updatedAt: "2026-07-10T09:08:10.009Z"
        )

        try expectError(.compareAndSwapFailed) {
            try repository.replace(replacement, expected: wrongExpected)
        }
        #expect(try repository.load() == current)

        fileSystem.failNextReplaceAsStale()
        try expectError(.compareAndSwapFailed) {
            try repository.replace(replacement, expected: current)
        }
        #expect(try repository.load() == current)

        fileSystem.failNextRemoveAsStale()
        try expectError(.compareAndSwapFailed) {
            _ = try repository.remove(expected: current)
        }
        #expect(try repository.load() == current)
    }

    @Test func repositoryMapsProtectedDataAndKeepsErrorsRedacted() throws {
        let fileSystem = IOSPendingRecordingJournalFileSystemFake()
        fileSystem.readError = .protectedDataUnavailable
        let repository = FoundationIOSPendingRecordingJournalRepository(
            fileSystem: fileSystem
        )

        try expectError(.dataProtectionUnavailable) {
            _ = try repository.load()
        }
        #expect(
            IOSPendingRecordingError.dataProtectionUnavailable.description
                == "IOSPendingRecordingError(redacted)"
        )
    }

    @Test func repositoryPreservesVisibleCommitUncertaintyAsTypedState() throws {
        let fileSystem = IOSPendingRecordingJournalFileSystemFake()
        let repository = FoundationIOSPendingRecordingJournalRepository(
            fileSystem: fileSystem
        )
        let initial = try fixtureRecording()
        fileSystem.commitNextCreateThenThrow(.commitUncertain)
        try expectError(.journalCommitUncertain) {
            try repository.create(initial)
        }
        #expect(try repository.load() == initial)
        let replacement = try fixtureRecording(
            phase: .awaitingRecovery,
            updatedAt: "2026-07-10T09:08:09.008Z"
        )
        fileSystem.commitNextReplaceThenThrow(.commitUncertain)

        try expectError(.journalCommitUncertain) {
            try repository.replace(replacement, expected: initial)
        }

        #expect(try repository.load() == replacement)
        #expect(
            IOSPendingRecordingError.journalCommitUncertain.description
                == "IOSPendingRecordingError(redacted)"
        )
    }

    @Test func liveFileSystemRoundTripsProtectedBytesAndEnforcesRevision() throws {
        try withTemporaryJournalDirectory { directoryURL in
            let fileSystem = FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL
            )
            let initial = Data(#"{"schemaVersion":1}"#.utf8)
            let replacement = Data(#"{"schemaVersion":2}"#.utf8)

            let initialRevision = try fileSystem.createFile(with: initial)
            #expect(try fileSystem.readFileIfPresent()?.data == initial)
            let replacementRevision = try fileSystem.replaceFile(
                with: replacement,
                expected: initialRevision
            )
            #expect(try fileSystem.readFileIfPresent()?.data == replacement)
            #expect(
                throws: IOSPendingRecordingJournalFileSystemError.staleRevision
            ) {
                _ = try fileSystem.replaceFile(
                    with: initial,
                    expected: initialRevision
                )
            }
            try fileSystem.removeFile(expected: replacementRevision)
            #expect(try fileSystem.readFileIfPresent() == nil)
        }
    }

    @Test func postRenameDirectorySyncFailureKeepsNewBytesAndIsUncertain() throws {
        try withTemporaryJournalDirectory { directoryURL in
            let reader = FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL
            )
            let initial = Data(#"{"value":0}"#.utf8)
            let replacement = Data(#"{"value":1}"#.utf8)
            let initialRevision = try reader.createFile(with: initial)
            let failingWriter = FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL,
                replaceOperation: { directory, temporary, destination in
                    let result = temporary.withCString { temporary in
                        destination.withCString { destination in
                            Darwin.renameat(
                                directory,
                                temporary,
                                directory,
                                destination
                            )
                        }
                    }
                    return result == 0 ? .success(()) : .failure(errno)
                },
                directorySynchronizationOperation: { _ in .failure(EIO) }
            )

            #expect(
                throws:
                    IOSPendingRecordingJournalFileSystemError.commitUncertain
            ) {
                _ = try failingWriter.replaceFile(
                    with: replacement,
                    expected: initialRevision
                )
            }

            #expect(try reader.readFileIfPresent()?.data == replacement)
            #expect(
                throws: IOSPendingRecordingJournalFileSystemError.staleRevision
            ) {
                _ = try reader.replaceFile(
                    with: initial,
                    expected: initialRevision
                )
            }
            let journalDirectory = directoryURL.appendingPathComponent(
                IOSPendingRecordingStorageLocation.rootDirectoryName,
                isDirectory: true
            )
            #expect(
                try FileManager.default.contentsOfDirectory(
                    atPath: journalDirectory.path
                ) == [IOSPendingRecordingStorageLocation.journalFileName]
            )
        }
    }

    @Test func liveFileSystemSerializesConcurrentRevisionCommits() async throws {
        try await withTemporaryJournalDirectory { directoryURL in
            let firstFileSystem = FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL
            )
            let secondFileSystem = FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL
            )
            let initial = Data(#"{"value":0}"#.utf8)
            let firstBytes = Data(#"{"value":1}"#.utf8)
            let secondBytes = Data(#"{"value":2}"#.utf8)
            let revision = try firstFileSystem.createFile(with: initial)

            async let firstSucceeded = replaceSucceeded(
                fileSystem: firstFileSystem,
                data: firstBytes,
                expected: revision
            )
            async let secondSucceeded = replaceSucceeded(
                fileSystem: secondFileSystem,
                data: secondBytes,
                expected: revision
            )
            let outcomes = await [firstSucceeded, secondSucceeded]
            #expect(outcomes.filter { $0 }.count == 1)
            let finalData = try #require(
                firstFileSystem.readFileIfPresent()?.data
            )
            #expect(finalData == firstBytes || finalData == secondBytes)
        }
    }
}

private func replaceSucceeded(
    fileSystem: FoundationIOSPendingRecordingJournalFileSystem,
    data: Data,
    expected: IOSPendingRecordingJournalFileRevision
) -> Bool {
    do {
        _ = try fileSystem.replaceFile(with: data, expected: expected)
        return true
    } catch IOSPendingRecordingJournalFileSystemError.staleRevision {
        return false
    } catch {
        return false
    }
}

private func withTemporaryJournalDirectory<Result>(
    _ operation: (URL) throws -> Result
) throws -> Result {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    return try operation(directoryURL)
}

private func withTemporaryJournalDirectory<Result>(
    _ operation: (URL) async throws -> Result
) async throws -> Result {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    return try await operation(directoryURL)
}

private func fixtureRecording(
    phase: IOSPendingRecordingPhase = .readyForTranscription,
    transcriptionID: UUID? = nil,
    outputIntent: DictationOutputIntent = .standard,
    languageCode: String? = nil,
    updatedAt: String = "2026-07-10T09:08:08.007Z"
) throws -> IOSPendingRecording {
    let attemptID = try #require(
        UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
    )
    return try IOSPendingRecording(
        attemptID: attemptID,
        audioRelativeIdentifier: IOSPendingRecordingStorageLocation
            .relativeAudioIdentifier(for: attemptID, format: .m4a),
        createdAt: IOSPendingRecordingTimestampCodec.date(
            from: "2026-07-10T09:08:07.006Z"
        ),
        updatedAt: IOSPendingRecordingTimestampCodec.date(from: updatedAt),
        phase: phase,
        outputIntent: outputIntent,
        transcriptionID: transcriptionID,
        transcriptionModel: "gpt-4o-mini-transcribe",
        transcriptionLanguageCode: languageCode,
        durationMilliseconds: 4_321,
        byteCount: 12_345
    )
}

private func modifying(
    _ data: Data,
    _ mutation: (inout [String: Any]) -> Void
) throws -> Data {
    var object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    mutation(&object)
    return try JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys]
    )
}

private func expectDecodeError(
    _ data: Data,
    _ expected: IOSPendingRecordingError
) throws {
    do {
        _ = try IOSPendingRecordingJournalWireCodec.decode(data)
        Issue.record("Expected journal decode to fail")
    } catch let error as IOSPendingRecordingError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected error type")
    }
}

private func expectError(
    _ expected: IOSPendingRecordingError,
    operation: () throws -> Void
) throws {
    do {
        try operation()
        Issue.record("Expected operation to fail")
    } catch let error as IOSPendingRecordingError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected error type")
    }
}

private func requireSendable<Value: Sendable>(_ type: Value.Type) {}

private final class IOSPendingRecordingJournalFileSystemFake:
    IOSPendingRecordingJournalFileSystem,
    @unchecked Sendable {
    private struct State {
        var data: Data?
        var revision: UInt64
        var readError: IOSPendingRecordingJournalFileSystemError? = nil
        var nextCreateError: IOSPendingRecordingJournalFileSystemError? = nil
        var commitBeforeNextCreateError = false
        var nextReplaceError: IOSPendingRecordingJournalFileSystemError? = nil
        var commitBeforeNextReplaceError = false
        var staleNextReplace = false
        var staleNextRemove = false
        var removeCallCount = 0
    }

    private let lock = NSLock()
    private var state: State

    init(data: Data? = nil) {
        state = State(data: data, revision: data == nil ? 0 : 1)
    }

    var data: Data? {
        lock.withLock { state.data }
    }

    var removeCallCount: Int {
        lock.withLock { state.removeCallCount }
    }

    var readError: IOSPendingRecordingJournalFileSystemError? {
        get { lock.withLock { state.readError } }
        set { lock.withLock { state.readError = newValue } }
    }

    func failNextReplaceAsStale() {
        lock.withLock { state.staleNextReplace = true }
    }

    func commitNextCreateThenThrow(
        _ error: IOSPendingRecordingJournalFileSystemError
    ) {
        lock.withLock {
            state.nextCreateError = error
            state.commitBeforeNextCreateError = true
        }
    }

    func commitNextReplaceThenThrow(
        _ error: IOSPendingRecordingJournalFileSystemError
    ) {
        lock.withLock {
            state.nextReplaceError = error
            state.commitBeforeNextReplaceError = true
        }
    }

    func failNextRemoveAsStale() {
        lock.withLock { state.staleNextRemove = true }
    }

    func readFileIfPresent() throws -> IOSPendingRecordingJournalFile? {
        try lock.withLock {
            if let readError = state.readError {
                throw readError
            }
            guard let data = state.data else { return nil }
            return IOSPendingRecordingJournalFile(
                data: data,
                revision: IOSPendingRecordingJournalFileRevision(
                    testingToken: state.revision
                )
            )
        }
    }

    func createFile(
        with data: Data
    ) throws -> IOSPendingRecordingJournalFileRevision {
        try lock.withLock {
            guard state.data == nil else {
                throw IOSPendingRecordingJournalFileSystemError
                    .destinationConflict
            }
            if let error = state.nextCreateError {
                state.nextCreateError = nil
                if state.commitBeforeNextCreateError {
                    state.commitBeforeNextCreateError = false
                    state.revision += 1
                    state.data = data
                }
                throw error
            }
            state.revision += 1
            state.data = data
            return IOSPendingRecordingJournalFileRevision(
                testingToken: state.revision
            )
        }
    }

    func replaceFile(
        with data: Data,
        expected: IOSPendingRecordingJournalFileRevision
    ) throws -> IOSPendingRecordingJournalFileRevision {
        try lock.withLock {
            if state.staleNextReplace {
                state.staleNextReplace = false
                throw IOSPendingRecordingJournalFileSystemError.staleRevision
            }
            guard state.data != nil,
                  expected == IOSPendingRecordingJournalFileRevision(
                      testingToken: state.revision
                  ) else {
                throw IOSPendingRecordingJournalFileSystemError.staleRevision
            }
            if let error = state.nextReplaceError {
                state.nextReplaceError = nil
                if state.commitBeforeNextReplaceError {
                    state.commitBeforeNextReplaceError = false
                    state.revision += 1
                    state.data = data
                }
                throw error
            }
            state.revision += 1
            state.data = data
            return IOSPendingRecordingJournalFileRevision(
                testingToken: state.revision
            )
        }
    }

    func removeFile(
        expected: IOSPendingRecordingJournalFileRevision
    ) throws {
        try lock.withLock {
            state.removeCallCount += 1
            if state.staleNextRemove {
                state.staleNextRemove = false
                throw IOSPendingRecordingJournalFileSystemError.staleRevision
            }
            guard state.data != nil,
                  expected == IOSPendingRecordingJournalFileRevision(
                      testingToken: state.revision
                  ) else {
                throw IOSPendingRecordingJournalFileSystemError.staleRevision
            }
            state.revision += 1
            state.data = nil
        }
    }
}
