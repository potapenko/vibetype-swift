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

    @Test func maximumValidModelFitsTheCompleteJournalWireRecord() throws {
        let model = String(
            repeating: "m",
            count: IOSPendingRecordingValidation.maximumModelByteCount
        )
        #expect(
            IOSPendingRecordingValidation.maximumModelByteCount
                == IOSAcceptedOutputDeliveryValidation.maximumModelByteCount
        )

        let recording = try fixtureRecording(transcriptionModel: model)
        let encoded = try IOSPendingRecordingJournalWireCodec.encode(recording)

        #expect(
            encoded.count
                <= FoundationIOSPendingRecordingJournalRepository
                    .maximumJournalByteCount
        )
        #expect(
            try IOSPendingRecordingJournalWireCodec.decode(encoded) == recording
        )
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

    @Test func metadataRetirementReturnsRootBoundDurableAbsenceEvidence() throws {
        try withTemporaryJournalDirectory { directoryURL in
            let repository = FoundationIOSPendingRecordingJournalRepository(
                applicationSupportDirectoryURL: directoryURL
            )
            let recording = try fixtureRecording()
            try repository.create(recording)
            let snapshot = try #require(
                try repository.loadMetadataSnapshot(
                    authorization: journalMetadataAuthorization()
                )
            )

            let removed = try repository.removeMetadata(
                expected: snapshot,
                expectedRepositoryRoot: nil,
                authorization: journalMetadataAuthorization()
            )

            #expect(snapshot.recording == recording)
            #expect(removed.provesRemoval(of: snapshot))
            #expect(!removed.provesPreexistingAbsence)
            #expect(
                try repository.loadMetadataSnapshot(
                    authorization: journalMetadataAuthorization()
                ) == nil
            )
            #expect(
                snapshot.description
                    == "IOSPendingRecordingJournalMetadataSnapshot(redacted)"
            )
            #expect(snapshot.debugDescription == snapshot.description)
            #expect(snapshot.customMirror.children.isEmpty)
            #expect(
                removed.description
                    == "IOSPendingRecordingJournalMetadataAbsenceEvidence(redacted)"
            )
            #expect(removed.debugDescription == removed.description)
            #expect(removed.customMirror.children.isEmpty)
            switch removed {
            case .removed(let details):
                #expect(
                    details.description
                        == "IOSPendingRecordingJournalMetadataAbsenceEvidence.Removed(redacted)"
                )
                #expect(details.debugDescription == details.description)
                #expect(details.customMirror.children.isEmpty)
            case .alreadyAbsent:
                Issue.record("Expected removed metadata evidence")
            }

            let alreadyAbsent = try repository.proveMetadataAbsent(
                expectedRepositoryRoot: nil,
                authorization: journalMetadataAuthorization()
            )

            #expect(alreadyAbsent.provesPreexistingAbsence)
            #expect(!alreadyAbsent.provesRemoval(of: snapshot))
            #expect(alreadyAbsent.binding == removed.binding)
            #expect(
                alreadyAbsent.description
                    == "IOSPendingRecordingJournalMetadataAbsenceEvidence(redacted)"
            )
            #expect(alreadyAbsent.debugDescription == alreadyAbsent.description)
            #expect(alreadyAbsent.customMirror.children.isEmpty)
            switch alreadyAbsent {
            case .removed:
                Issue.record("Expected already-absent metadata evidence")
            case .alreadyAbsent(let details):
                #expect(
                    details.description
                        == "IOSPendingRecordingJournalMetadataAbsenceEvidence.AlreadyAbsent(redacted)"
                )
                #expect(details.debugDescription == details.description)
                #expect(details.customMirror.children.isEmpty)
            }
            #expect(
                removed.binding.description
                    == "IOSPendingRecordingJournalMetadataAbsenceEvidence.Binding(redacted)"
            )
            #expect(
                removed.binding.debugDescription
                    == removed.binding.description
            )
            #expect(removed.binding.customMirror.children.isEmpty)
            #expect(
                removed.binding.pathIdentity.description
                    == "IOSPendingRecordingJournalCanonicalPathIdentity(redacted)"
            )
            #expect(
                removed.binding.pathIdentity.customMirror.children.isEmpty
            )
            #expect(
                removed.binding.journalDirectory.description
                    == "IOSPendingRecordingJournalDirectoryIdentity(redacted)"
            )
            #expect(
                removed.binding.journalDirectory.debugDescription
                    == removed.binding.journalDirectory.description
            )
            #expect(
                removed.binding.journalDirectory.customMirror.children.isEmpty
            )
            let applicationSupportIdentity = try #require(
                journalTestFileIdentity(directoryURL)
            )
            let journalDirectoryIdentity = try #require(
                journalTestFileIdentity(
                    directoryURL.appendingPathComponent(
                        IOSPendingRecordingStorageLocation.rootDirectoryName,
                        isDirectory: true
                    )
                )
            )
            #expect(
                removed.binding.repositoryRoot.device
                    == applicationSupportIdentity.device
            )
            #expect(
                removed.binding.repositoryRoot.inode
                    == applicationSupportIdentity.inode
            )
            #expect(
                removed.binding.journalDirectory.device
                    == journalDirectoryIdentity.device
            )
            #expect(
                removed.binding.journalDirectory.inode
                    == journalDirectoryIdentity.inode
            )
        }
    }

    @Test func metadataRetirementRejectsChangedRevisionWithSameBytes() throws {
        try withTemporaryJournalDirectory { directoryURL in
            let fileSystem = FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL
            )
            let repository = FoundationIOSPendingRecordingJournalRepository(
                fileSystem: fileSystem
            )
            let recording = try fixtureRecording()
            try repository.create(recording)
            let snapshot = try #require(
                try repository.loadMetadataSnapshot(
                    authorization: journalMetadataAuthorization()
                )
            )
            let originalFile = try #require(
                try fileSystem.readFileIfPresent()
            )
            _ = try fileSystem.replaceFile(
                with: originalFile.data,
                expected: originalFile.revision
            )

            try expectError(.compareAndSwapFailed) {
                _ = try repository.removeMetadata(
                    expected: snapshot,
                    expectedRepositoryRoot: nil,
                    authorization: journalMetadataAuthorization()
                )
            }

            #expect(
                try repository.loadMetadataSnapshot(
                    authorization: journalMetadataAuthorization()
                )?.recording == recording
            )
        }
    }

    @Test func metadataUnlinkThenSyncFailureIsCommitUncertain() throws {
        try withTemporaryJournalDirectory { directoryURL in
            let writer = FoundationIOSPendingRecordingJournalRepository(
                applicationSupportDirectoryURL: directoryURL
            )
            let recording = try fixtureRecording()
            try writer.create(recording)
            let snapshot = try #require(
                try writer.loadMetadataSnapshot(
                    authorization: journalMetadataAuthorization()
                )
            )
            let journalURL = journalTestFileURL(directoryURL)
            let failingRepository = FoundationIOSPendingRecordingJournalRepository(
                fileSystem: FoundationIOSPendingRecordingJournalFileSystem(
                    applicationSupportDirectoryURL: directoryURL,
                    directorySynchronizationOperation: { _ in .failure(EIO) }
                )
            )

            try expectError(.journalCommitUncertain) {
                _ = try failingRepository.removeMetadata(
                    expected: snapshot,
                    expectedRepositoryRoot: nil,
                    authorization: journalMetadataAuthorization()
                )
            }

            #expect(!FileManager.default.fileExists(atPath: journalURL.path))
        }
    }

    @Test func metadataRecreatedAfterUnlinkCannotMintRemovalProof() throws {
        try withTemporaryJournalDirectory { directoryURL in
            let writer = FoundationIOSPendingRecordingJournalRepository(
                applicationSupportDirectoryURL: directoryURL
            )
            let recording = try fixtureRecording()
            let bytes = try IOSPendingRecordingJournalWireCodec.encode(recording)
            try writer.create(recording)
            let snapshot = try #require(
                try writer.loadMetadataSnapshot(
                    authorization: journalMetadataAuthorization()
                )
            )
            let journalURL = journalTestFileURL(directoryURL)
            let recreatingRepository =
                FoundationIOSPendingRecordingJournalRepository(
                    fileSystem:
                        FoundationIOSPendingRecordingJournalFileSystem(
                            applicationSupportDirectoryURL: directoryURL,
                            beforeMetadataAbsenceFinalCheck: {
                                _ = FileManager.default.createFile(
                                    atPath: journalURL.path,
                                    contents: bytes,
                                    attributes: [.posixPermissions: 0o600]
                                )
                            }
                        )
                )

            try expectError(.journalCommitUncertain) {
                _ = try recreatingRepository.removeMetadata(
                    expected: snapshot,
                    expectedRepositoryRoot: nil,
                    authorization: journalMetadataAuthorization()
                )
            }

            #expect(FileManager.default.fileExists(atPath: journalURL.path))
        }
    }

    @Test func metadataRecreatedDuringAbsenceProofFailsClosed() throws {
        try withTemporaryJournalDirectory { directoryURL in
            let writer = FoundationIOSPendingRecordingJournalRepository(
                applicationSupportDirectoryURL: directoryURL
            )
            let recording = try fixtureRecording()
            try writer.create(recording)
            let snapshot = try #require(
                try writer.loadMetadataSnapshot(
                    authorization: journalMetadataAuthorization()
                )
            )
            _ = try writer.removeMetadata(
                expected: snapshot,
                expectedRepositoryRoot: nil,
                authorization: journalMetadataAuthorization()
            )
            let journalURL = journalTestFileURL(directoryURL)
            let corruptBytes = Data("recreated".utf8)
            let provingRepository = FoundationIOSPendingRecordingJournalRepository(
                fileSystem: FoundationIOSPendingRecordingJournalFileSystem(
                    applicationSupportDirectoryURL: directoryURL,
                    beforeMetadataAbsenceFinalCheck: {
                        _ = FileManager.default.createFile(
                            atPath: journalURL.path,
                            contents: corruptBytes,
                            attributes: [.posixPermissions: 0o600]
                        )
                    }
                )
            )

            try expectError(.compareAndSwapFailed) {
                _ = try provingRepository.proveMetadataAbsent(
                    expectedRepositoryRoot: nil,
                    authorization: journalMetadataAuthorization()
                )
            }

            #expect(try Data(contentsOf: journalURL) == corruptBytes)
        }
    }

    @Test func metadataRetirementMapsProtectedDataAndRootMismatch() throws {
        try withTemporaryJournalDirectory { directoryURL in
            let writer = FoundationIOSPendingRecordingJournalRepository(
                applicationSupportDirectoryURL: directoryURL
            )
            let recording = try fixtureRecording()
            try writer.create(recording)
            let snapshot = try #require(
                try writer.loadMetadataSnapshot(
                    authorization: journalMetadataAuthorization()
                )
            )
            let protectedRepository =
                FoundationIOSPendingRecordingJournalRepository(
                    fileSystem:
                        FoundationIOSPendingRecordingJournalFileSystem(
                            applicationSupportDirectoryURL: directoryURL,
                            beforeRepositoryRootOpen: {
                                throw IOSPendingRecordingJournalFileSystemError
                                    .protectedDataUnavailable
                            }
                        )
                )
            try expectError(.dataProtectionUnavailable) {
                _ = try protectedRepository.removeMetadata(
                    expected: snapshot,
                    expectedRepositoryRoot: nil,
                    authorization: journalMetadataAuthorization()
                )
            }

            let physicalRoot = try #require(
                journalTestFileIdentity(directoryURL)
            )
            let wrongRoot = IOSPersistenceRepositoryRootIdentity(
                device: physicalRoot.device,
                inode: physicalRoot.inode ^ ino_t(1)
            )
            try expectError(.repositoryIdentityConflict) {
                _ = try writer.removeMetadata(
                    expected: snapshot,
                    expectedRepositoryRoot: wrongRoot,
                    authorization: journalMetadataAuthorization()
                )
            }

            _ = try writer.removeMetadata(
                expected: snapshot,
                expectedRepositoryRoot: nil,
                authorization: journalMetadataAuthorization()
            )
            try expectError(.dataProtectionUnavailable) {
                _ = try protectedRepository.proveMetadataAbsent(
                    expectedRepositoryRoot: nil,
                    authorization: journalMetadataAuthorization()
                )
            }
            try expectError(.repositoryIdentityConflict) {
                _ = try writer.proveMetadataAbsent(
                    expectedRepositoryRoot: wrongRoot,
                    authorization: journalMetadataAuthorization()
                )
            }
        }
    }

    @Test func corruptMetadataCannotBeReportedAsAlreadyAbsent() throws {
        try withTemporaryJournalDirectory { directoryURL in
            let fileSystem = FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL
            )
            let corruptBytes = Data("not-json".utf8)
            _ = try fileSystem.createFile(with: corruptBytes)
            let repository = FoundationIOSPendingRecordingJournalRepository(
                fileSystem: fileSystem
            )

            try expectError(.compareAndSwapFailed) {
                _ = try repository.proveMetadataAbsent(
                    expectedRepositoryRoot: nil,
                    authorization: journalMetadataAuthorization()
                )
            }
            try expectError(.journalMalformed) {
                _ = try repository.loadMetadataSnapshot(
                    authorization: journalMetadataAuthorization()
                )
            }
            #expect(try fileSystem.readFileIfPresent()?.data == corruptBytes)
        }
    }

    @Test func metadataAuthorityRejectsForeignStrictRecordConfiguration()
        throws {
        try withTemporaryJournalDirectory { directoryURL in
            let configuration = IOSStrictProtectedRecordConfiguration(
                rootDirectoryName:
                    IOSPendingRecordingStorageLocation.rootDirectoryName,
                fileName: "foreign-record.json",
                maximumByteCount:
                    FoundationIOSPendingRecordingJournalRepository
                        .maximumJournalByteCount,
                marker: nil
            )
            let fileSystem = FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL,
                configuration: configuration
            )
            let bytes = Data("foreign".utf8)
            let revision = try fileSystem.createFile(with: bytes)
            let authorization = journalMetadataAuthorization()

            #expect(
                throws:
                    IOSPendingRecordingJournalFileSystemError.invalidLocation
            ) {
                _ = try fileSystem.readMetadataFileIfPresent(
                    authorization: authorization
                )
            }
            #expect(
                throws:
                    IOSPendingRecordingJournalFileSystemError.invalidLocation
            ) {
                _ = try fileSystem.removeMetadataFile(
                    expected: revision,
                    expectedRepositoryRoot: nil,
                    authorization: authorization
                )
            }
            #expect(
                throws:
                    IOSPendingRecordingJournalFileSystemError.invalidLocation
            ) {
                _ = try fileSystem.proveMetadataFileAbsent(
                    expectedRepositoryRoot: nil,
                    authorization: authorization
                )
            }
            #expect(try fileSystem.readFileIfPresent()?.data == bytes)
            #expect(authorization.customMirror.children.isEmpty)
            #expect(
                authorization.description
                    == "IOSPendingRecordingMetadataRetirementAuthorization(redacted)"
            )
        }
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

    @Test func liveFileSystemTightensAnExistingOwnedRootDirectory() throws {
        try withTemporaryJournalDirectory { directoryURL in
            let rootURL = directoryURL.appendingPathComponent(
                IOSPendingRecordingStorageLocation.rootDirectoryName,
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: false
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: rootURL.path
            )
            let fileSystem = FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL
            )

            _ = try fileSystem.createFile(with: Data("strict".utf8))

            let attributes = try FileManager.default.attributesOfItem(
                atPath: rootURL.path
            )
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        }
    }

    @Test func liveFileSystemAppliesCustomNameLimitAndMarker() throws {
        try withTemporaryJournalDirectory { directoryURL in
            let marker = IOSStrictProtectedRecordConfiguration.Marker(
                name: "com.holdtype.tests.strict-record",
                value: Array("v1".utf8)
            )
            let fileSystem = FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL,
                configuration: IOSStrictProtectedRecordConfiguration(
                    rootDirectoryName:
                        IOSPendingRecordingStorageLocation.rootDirectoryName,
                    fileName: "strict-test-record.json",
                    maximumByteCount: 16,
                    marker: marker
                )
            )
            let exactLimit = Data(repeating: 0x61, count: 16)

            _ = try fileSystem.createFile(with: exactLimit)

            #expect(try fileSystem.readFileIfPresent()?.data == exactLimit)
            let fileURL = directoryURL
                .appendingPathComponent(
                    IOSPendingRecordingStorageLocation.rootDirectoryName,
                    isDirectory: true
                )
                .appendingPathComponent("strict-test-record.json")
            let rawDescriptor = Darwin.open(fileURL.path, O_RDONLY | O_CLOEXEC)
            let descriptor = try #require(
                rawDescriptor >= 0 ? rawDescriptor : nil
            )
            defer { Darwin.close(descriptor) }
            var markerBytes = [UInt8](repeating: 0, count: 3)
            let markerByteCount = marker.name.withCString { name in
                markerBytes.withUnsafeMutableBytes {
                    Darwin.fgetxattr(
                        descriptor,
                        name,
                        $0.baseAddress,
                        $0.count,
                        0,
                        0
                    )
                }
            }
            #expect(markerByteCount == 2)
            #expect(Array(markerBytes.prefix(2)) == Array("v1".utf8))
            #expect(
                throws: IOSPendingRecordingJournalFileSystemError.sourceTooLarge
            ) {
                _ = try FoundationIOSPendingRecordingJournalFileSystem(
                    applicationSupportDirectoryURL: directoryURL,
                    configuration: IOSStrictProtectedRecordConfiguration(
                        rootDirectoryName:
                            IOSPendingRecordingStorageLocation.rootDirectoryName,
                        fileName: "strict-too-large.json",
                        maximumByteCount: 16,
                        marker: marker
                    )
                ).createFile(with: Data(repeating: 0x61, count: 17))
            }
        }
    }

    @Test func opaqueRevisionCanRemoveAFileWithMissingCustomMarker() throws {
        try withTemporaryJournalDirectory { directoryURL in
            let marker = IOSStrictProtectedRecordConfiguration.Marker(
                name: "com.holdtype.tests.opaque-record",
                value: Array("v1".utf8)
            )
            let configuration = IOSStrictProtectedRecordConfiguration(
                rootDirectoryName:
                    IOSPendingRecordingStorageLocation.rootDirectoryName,
                fileName: "opaque-test-record.json",
                maximumByteCount: 1_024,
                marker: marker
            )
            let fileSystem = FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL,
                configuration: configuration
            )
            _ = try fileSystem.createFile(with: Data("opaque".utf8))
            let fileURL = directoryURL
                .appendingPathComponent(
                    configuration.rootDirectoryName,
                    isDirectory: true
                )
                .appendingPathComponent(configuration.fileName)
            let rawDescriptor = Darwin.open(fileURL.path, O_RDWR | O_CLOEXEC)
            let descriptor = try #require(
                rawDescriptor >= 0 ? rawDescriptor : nil
            )
            let removeMarkerResult = marker.name.withCString {
                Darwin.fremovexattr(descriptor, $0, 0)
            }
            Darwin.close(descriptor)
            #expect(removeMarkerResult == 0)

            #expect(
                throws: IOSPendingRecordingJournalFileSystemError.invalidFile
            ) {
                _ = try fileSystem.readFileIfPresent()
            }
            let revision = try #require(
                try fileSystem.readOpaqueFileRevisionIfPresent()
            )

            try fileSystem.removeOpaqueFile(expected: revision)

            #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    @Test func maintenanceRemovesOnlyOldOwnedMarkedOrZeroByteStaging() throws {
        try withTemporaryJournalDirectory { directoryURL in
            let fileName = "ios-accepted-output-delivery.json"
            let marker = IOSStrictProtectedRecordConfiguration.Marker(
                name: "com.holdtype.tests.delivery-maintenance",
                value: Array("v1".utf8)
            )
            let rootURL = directoryURL.appendingPathComponent(
                IOSPendingRecordingStorageLocation.rootDirectoryName,
                isDirectory: true
            )
            let oldMarkedName = ".\(fileName)."
                + "11111111-2222-4333-8444-555555555555.tmp"
            let freshMarkedName = ".\(fileName)."
                + "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee.tmp"
            let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
            let now = oldDate.addingTimeInterval(24 * 60 * 60 + 1)

            for name in [oldMarkedName, freshMarkedName] {
                _ = try FoundationIOSPendingRecordingJournalFileSystem(
                    applicationSupportDirectoryURL: directoryURL,
                    configuration: IOSStrictProtectedRecordConfiguration(
                        rootDirectoryName:
                            IOSPendingRecordingStorageLocation.rootDirectoryName,
                        fileName: name,
                        maximumByteCount: 1_024,
                        marker: marker
                    )
                ).createFile(with: Data("marked".utf8))
            }
            try FileManager.default.setAttributes(
                [.modificationDate: oldDate],
                ofItemAtPath: rootURL.appendingPathComponent(oldMarkedName).path
            )

            let oldZeroName = ".\(fileName)."
                + "99999999-8888-4777-8666-555555555555.tmp"
            let oldZeroURL = rootURL.appendingPathComponent(oldZeroName)
            #expect(
                FileManager.default.createFile(
                    atPath: oldZeroURL.path,
                    contents: Data(),
                    attributes: [.posixPermissions: 0o600]
                )
            )
            try FileManager.default.setAttributes(
                [.modificationDate: oldDate],
                ofItemAtPath: oldZeroURL.path
            )

            let unknownURL = rootURL.appendingPathComponent(
                ".\(fileName).not-a-canonical-uuid.tmp"
            )
            #expect(
                FileManager.default.createFile(
                    atPath: unknownURL.path,
                    contents: Data(),
                    attributes: [.posixPermissions: 0o600]
                )
            )
            try FileManager.default.setAttributes(
                [.modificationDate: oldDate],
                ofItemAtPath: unknownURL.path
            )

            let maintenance = FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL,
                configuration: IOSStrictProtectedRecordConfiguration(
                    rootDirectoryName:
                        IOSPendingRecordingStorageLocation.rootDirectoryName,
                    fileName: fileName,
                    maximumByteCount: 1_024,
                    marker: marker
                ),
                monotonicNowNanoseconds: { 0 }
            )
            let report = try maintenance.removeAbandonedTemporaryFiles(now: now)

            #expect(report.removedFileCount == 2)
            #expect(report.removedByteCount == Int64(Data("marked".utf8).count))
            #expect(!FileManager.default.fileExists(
                atPath: rootURL.appendingPathComponent(oldMarkedName).path
            ))
            #expect(!FileManager.default.fileExists(atPath: oldZeroURL.path))
            #expect(FileManager.default.fileExists(
                atPath: rootURL.appendingPathComponent(freshMarkedName).path
            ))
            #expect(FileManager.default.fileExists(atPath: unknownURL.path))
        }
    }

    @Test func maintenanceAdvancesPastFirst256StableForeignNames() throws {
        try withTemporaryJournalDirectory { directoryURL in
            let fileName = "ios-accepted-output-delivery.json"
            let marker = IOSStrictProtectedRecordConfiguration.Marker(
                name: "com.holdtype.tests.delivery-maintenance-window",
                value: Array("v1".utf8)
            )
            let configuration = IOSStrictProtectedRecordConfiguration(
                rootDirectoryName:
                    IOSPendingRecordingStorageLocation.rootDirectoryName,
                fileName: fileName,
                maximumByteCount: 1_024,
                marker: marker
            )
            let targetName = ".\(fileName)."
                + "11111111-2222-4333-8444-555555555555.tmp"
            let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
            let now = oldDate.addingTimeInterval(24 * 60 * 60 + 1)
            let targetURL = directoryURL
                .appendingPathComponent(
                    configuration.rootDirectoryName,
                    isDirectory: true
                )
                .appendingPathComponent(targetName)

            _ = try FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL,
                configuration: IOSStrictProtectedRecordConfiguration(
                    rootDirectoryName: configuration.rootDirectoryName,
                    fileName: targetName,
                    maximumByteCount: configuration.maximumByteCount,
                    marker: marker
                )
            ).createFile(with: Data("stale".utf8))
            try FileManager.default.setAttributes(
                [.modificationDate: oldDate],
                ofItemAtPath: targetURL.path
            )

            let foreignNames = (0..<300).map { "foreign-\($0)" }
            let adapter = DeterministicMaintenancePOSIXAdapter(
                directoryEntries: [".", ".."] + foreignNames + [targetName]
            )
            let maintenance = FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL,
                configuration: configuration,
                adapter: adapter,
                monotonicNowNanoseconds: { 0 }
            )

            let firstReport = try maintenance
                .removeAbandonedTemporaryFiles(now: now)

            #expect(firstReport.reachedLimit)
            #expect(firstReport.removedFileCount == 0)
            #expect(FileManager.default.fileExists(atPath: targetURL.path))
            #expect(adapter.openedDirectoryStreamCount == 1)
            #expect(adapter.directoryEntryReadCount == 256)

            let secondReport = try maintenance
                .removeAbandonedTemporaryFiles(now: now)

            #expect(secondReport.removedFileCount == 1)
            #expect(!FileManager.default.fileExists(atPath: targetURL.path))
            #expect(adapter.openedDirectoryStreamCount == 1)
        }
    }

    @Test func maintenanceSkipsUnsafeAndOversizedCanonicalCandidates() throws {
        try withTemporaryJournalDirectory { directoryURL in
            let fileName = "ios-accepted-output-delivery.json"
            let marker = IOSStrictProtectedRecordConfiguration.Marker(
                name: "com.holdtype.tests.delivery-maintenance",
                value: Array("v1".utf8)
            )
            let rootURL = directoryURL.appendingPathComponent(
                IOSPendingRecordingStorageLocation.rootDirectoryName,
                isDirectory: true
            )
            let validName = ".\(fileName)."
                + "11111111-2222-4333-8444-555555555555.tmp"
            _ = try FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL,
                configuration: IOSStrictProtectedRecordConfiguration(
                    rootDirectoryName:
                        IOSPendingRecordingStorageLocation.rootDirectoryName,
                    fileName: validName,
                    maximumByteCount: 1_024,
                    marker: marker
                )
            ).createFile(with: Data("valid".utf8))

            let invalidNames = [
                ".\(fileName).22222222-3333-4444-8555-666666666666.tmp",
                ".\(fileName).33333333-4444-4555-8666-777777777777.tmp",
                ".\(fileName).44444444-5555-4666-8777-888888888888.tmp",
                ".\(fileName).55555555-6666-4777-8888-999999999999.tmp",
                ".\(fileName).66666666-7777-4888-8999-aaaaaaaaaaaa.tmp",
            ]
            let wrongModeURL = rootURL.appendingPathComponent(invalidNames[0])
            #expect(FileManager.default.createFile(
                atPath: wrongModeURL.path,
                contents: Data(),
                attributes: [.posixPermissions: 0o644]
            ))
            try FileManager.default.createDirectory(
                at: rootURL.appendingPathComponent(invalidNames[1]),
                withIntermediateDirectories: false
            )
            try FileManager.default.createSymbolicLink(
                at: rootURL.appendingPathComponent(invalidNames[2]),
                withDestinationURL: wrongModeURL
            )
            let hardLinkSourceURL = rootURL.appendingPathComponent("hard-link-source")
            #expect(FileManager.default.createFile(
                atPath: hardLinkSourceURL.path,
                contents: Data(),
                attributes: [.posixPermissions: 0o600]
            ))
            try FileManager.default.linkItem(
                at: hardLinkSourceURL,
                to: rootURL.appendingPathComponent(invalidNames[3])
            )
            let oversizedURL = rootURL.appendingPathComponent(invalidNames[4])
            #expect(FileManager.default.createFile(
                atPath: oversizedURL.path,
                contents: Data(),
                attributes: [.posixPermissions: 0o600]
            ))
            let truncateResult = oversizedURL.path.withCString {
                Darwin.truncate($0, off_t(4 * 1_024 * 1_024 + 1))
            }
            #expect(truncateResult == 0)

            let maintenance = FoundationIOSPendingRecordingJournalFileSystem(
                applicationSupportDirectoryURL: directoryURL,
                configuration: IOSStrictProtectedRecordConfiguration(
                    rootDirectoryName:
                        IOSPendingRecordingStorageLocation.rootDirectoryName,
                    fileName: fileName,
                    maximumByteCount: 1_024,
                    marker: marker
                ),
                monotonicNowNanoseconds: { 0 }
            )
            let report = try maintenance.removeAbandonedTemporaryFiles(
                now: Date().addingTimeInterval(2 * 24 * 60 * 60)
            )

            #expect(report.removedFileCount == 1)
            #expect(!FileManager.default.fileExists(
                atPath: rootURL.appendingPathComponent(validName).path
            ))
            for name in invalidNames {
                #expect(FileManager.default.fileExists(
                    atPath: rootURL.appendingPathComponent(name).path
                ))
            }
        }
    }
}

private func journalMetadataAuthorization()
    -> IOSPendingRecordingMetadataRetirementAuthorization {
    IOSPendingRecordingMetadataRetirementAuthorization(testingToken: 1)
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

private struct JournalTestFileIdentity {
    let device: dev_t
    let inode: ino_t
}

private func journalTestFileIdentity(_ url: URL) -> JournalTestFileIdentity? {
    var status = stat()
    let didRead = url.withUnsafeFileSystemRepresentation { path in
        guard let path else { return false }
        return Darwin.lstat(path, &status) == 0
    }
    guard didRead else { return nil }
    return JournalTestFileIdentity(
        device: status.st_dev,
        inode: status.st_ino
    )
}

private func journalTestFileURL(_ applicationSupportDirectoryURL: URL) -> URL {
    applicationSupportDirectoryURL
        .appendingPathComponent(
            IOSPendingRecordingStorageLocation.rootDirectoryName,
            isDirectory: true
        )
        .appendingPathComponent(
            IOSPendingRecordingStorageLocation.journalFileName,
            isDirectory: false
        )
}

private func fixtureRecording(
    phase: IOSPendingRecordingPhase = .readyForTranscription,
    transcriptionID: UUID? = nil,
    outputIntent: DictationOutputIntent = .standard,
    languageCode: String? = nil,
    transcriptionModel: String = "gpt-4o-mini-transcribe",
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
        transcriptionModel: transcriptionModel,
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

private final class DeterministicMaintenancePOSIXAdapter:
    IOSPendingRecordingPOSIXAdapter,
    @unchecked Sendable {
    private let live = DarwinIOSPendingRecordingPOSIXAdapter()
    private let directoryEntries: [String]
    private let lock = NSLock()
    private var streamIndexes: [Int: Int] = [:]
    private var openedStreamCount = 0
    private var entryReadCount = 0

    init(directoryEntries: [String]) {
        self.directoryEntries = directoryEntries
    }

    var openedDirectoryStreamCount: Int {
        lock.withLock { openedStreamCount }
    }

    var directoryEntryReadCount: Int {
        lock.withLock { entryReadCount }
    }

    func effectiveUserID() -> IOSPendingRecordingPOSIXResult<uid_t> {
        live.effectiveUserID()
    }

    func openPath(
        _ path: String,
        flags: Int32,
        mode: mode_t?
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        live.openPath(path, flags: flags, mode: mode)
    }

    func openAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32,
        mode: mode_t?
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        live.openAt(
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
        live.makeDirectoryAt(
            directoryDescriptor: directoryDescriptor,
            name: name,
            mode: mode
        )
    }

    func status(
        of fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<stat> {
        live.status(of: fileDescriptor)
    }

    func statusAtPath(
        _ path: String
    ) -> IOSPendingRecordingPOSIXResult<stat> {
        live.statusAtPath(path)
    }

    func statusAt(
        directoryDescriptor: Int32,
        name: String,
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<stat> {
        live.statusAt(
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
        live.read(
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
        live.write(
            fileDescriptor: fileDescriptor,
            buffer: buffer,
            byteCount: byteCount
        )
    }

    func synchronize(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        live.synchronize(fileDescriptor: fileDescriptor)
    }

    func changeMode(
        fileDescriptor: Int32,
        mode: mode_t
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        live.changeMode(fileDescriptor: fileDescriptor, mode: mode)
    }

    func lock(
        fileDescriptor: Int32,
        operation: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        live.lock(fileDescriptor: fileDescriptor, operation: operation)
    }

    func setExtendedAttribute(
        fileDescriptor: Int32,
        name: String,
        value: [UInt8],
        flags: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        live.setExtendedAttribute(
            fileDescriptor: fileDescriptor,
            name: name,
            value: value,
            flags: flags
        )
    }

    func extendedAttribute(
        fileDescriptor: Int32,
        name: String,
        maximumByteCount: Int
    ) -> IOSPendingRecordingPOSIXResult<[UInt8]> {
        live.extendedAttribute(
            fileDescriptor: fileDescriptor,
            name: name,
            maximumByteCount: maximumByteCount
        )
    }

    func setProtectionClass(
        fileDescriptor: Int32,
        protectionClass: Int32
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        live.setProtectionClass(
            fileDescriptor: fileDescriptor,
            protectionClass: protectionClass
        )
    }

    func protectionClass(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<Int32> {
        live.protectionClass(fileDescriptor: fileDescriptor)
    }

    func publishExclusively(
        directoryDescriptor: Int32,
        temporaryName: String,
        finalName: String
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        live.publishExclusively(
            directoryDescriptor: directoryDescriptor,
            temporaryName: temporaryName,
            finalName: finalName
        )
    }

    func unlinkAt(
        directoryDescriptor: Int32,
        name: String
    ) -> IOSPendingRecordingPOSIXResult<Void> {
        live.unlinkAt(
            directoryDescriptor: directoryDescriptor,
            name: name
        )
    }

    func openDirectoryStream(
        fileDescriptor: Int32
    ) -> IOSPendingRecordingPOSIXResult<UnsafeMutablePointer<DIR>> {
        live.closeFile(fileDescriptor)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        let stream = raw.assumingMemoryBound(to: DIR.self)
        lock.withLock {
            openedStreamCount += 1
            streamIndexes[Int(bitPattern: raw)] = 0
        }
        return .success(stream)
    }

    func nextDirectoryEntry(
        stream: UnsafeMutablePointer<DIR>
    ) -> IOSPendingRecordingPOSIXResult<IOSPendingRecordingDirectoryEntry?> {
        lock.withLock {
            entryReadCount += 1
            let key = Int(bitPattern: UnsafeMutableRawPointer(stream))
            guard let index = streamIndexes[key] else {
                return .failure(EBADF)
            }
            guard index < directoryEntries.count else {
                return .success(nil)
            }
            streamIndexes[key] = index + 1
            return .success(.name(directoryEntries[index]))
        }
    }

    func closeFile(_ fileDescriptor: Int32) {
        live.closeFile(fileDescriptor)
    }

    func closeDirectoryStream(_ stream: UnsafeMutablePointer<DIR>) {
        let raw = UnsafeMutableRawPointer(stream)
        let shouldDeallocate = lock.withLock {
            streamIndexes.removeValue(forKey: Int(bitPattern: raw)) != nil
        }
        if shouldDeallocate {
            raw.deallocate()
        }
    }
}

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
