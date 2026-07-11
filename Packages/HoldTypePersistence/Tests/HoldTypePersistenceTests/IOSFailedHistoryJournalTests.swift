import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSFailedHistoryJournalTests {
    @Test func canonicalV1HasExactNestedShapesAndExplicitNulls() throws {
        let operation = try failedHistoryTestRetryOperation(
            state: .acceptingOutput
        )
        let entry = try failedHistoryTestEntry(
            retryCount: 1,
            transcriptionLanguageCode: "en",
            retryOperation: operation
        )
        let cleanup = try failedHistoryTestAudioCleanup()
        let envelope = try IOSFailedHistoryEnvelope(
            revision: 7,
            entries: [entry],
            audioCleanup: [cleanup]
        )
        let data = try IOSFailedHistoryWireCodec.encode(envelope)
        let root = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(Set(root.keys) == [
            "schemaVersion", "revision", "entries", "audioCleanup",
        ])
        #expect(root["schemaVersion"] as? Int == 1)
        #expect(root["revision"] as? Int == 7)

        let rows = try #require(root["entries"] as? [[String: Any]])
        let row = try #require(rows.first)
        #expect(Set(row.keys) == [
            "attemptID",
            "createdAt",
            "updatedAt",
            "policyGeneration",
            "failureCategory",
            "pipelineStage",
            "retryCount",
            "outputIntent",
            "transcriptionModel",
            "transcriptionLanguageCode",
            "durationMilliseconds",
            "byteCount",
            "audioRelativeIdentifier",
            "ownershipState",
            "retryOperation",
        ])
        #expect(
            row["attemptID"] as? String
                == entry.attemptID.uuidString.lowercased()
        )
        #expect(row["createdAt"] as? Int64 == 1_800_000_000_010)
        #expect(row["failureCategory"] as? String == "networkFailure")
        #expect(row["pipelineStage"] as? String == "transcription")
        #expect(row["ownershipState"] as? String == "ready")

        let retry = try #require(row["retryOperation"] as? [String: Any])
        #expect(Set(retry.keys) == [
            "retryID",
            "createdAt",
            "transcriptionID",
            "deliveryID",
            "sessionID",
            "transcriptID",
            "state",
        ])
        #expect(retry["state"] as? String == "acceptingOutput")

        let tombstones = try #require(
            root["audioCleanup"] as? [[String: Any]]
        )
        let tombstone = try #require(tombstones.first)
        #expect(Set(tombstone.keys) == [
            "attemptID",
            "policyGeneration",
            "queuedAt",
            "audioRelativeIdentifier",
            "byteCount",
        ])

        #expect(try IOSFailedHistoryWireCodec.decode(data) == envelope)

        let nullEntry = try failedHistoryTestEntry(
            transcriptionLanguageCode: nil
        )
        let nullData = try IOSFailedHistoryWireCodec.encode(
            IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [nullEntry],
                audioCleanup: []
            )
        )
        let nullRoot = try #require(
            JSONSerialization.jsonObject(with: nullData) as? [String: Any]
        )
        let nullRows = try #require(
            nullRoot["entries"] as? [[String: Any]]
        )
        let nullRow = try #require(nullRows.first)
        #expect(nullRow["transcriptionLanguageCode"] is NSNull)
        #expect(nullRow["retryOperation"] is NSNull)
    }

    @Test func allStableWireEnumValuesRoundTrip() throws {
        for (index, category) in IOSFailedHistoryFailureCategory.allCases
            .enumerated() {
            let entry = try failedHistoryTestEntry(
                index: index + 1,
                failureCategory: category
            )
            let envelope = try IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [entry],
                audioCleanup: []
            )
            #expect(
                try IOSFailedHistoryWireCodec.decode(
                    IOSFailedHistoryWireCodec.encode(envelope)
                ) == envelope
            )
        }

        for (index, stage) in IOSFailedHistoryPipelineStage.allCases
            .enumerated() {
            let item = index + 1
            let entry = try failedHistoryTestEntry(
                index: item,
                pipelineStage: stage,
                outputIntent: stage == .translation ? .translate : .standard
            )
            let envelope = try IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [entry],
                audioCleanup: []
            )
            #expect(
                try IOSFailedHistoryWireCodec.decode(
                    IOSFailedHistoryWireCodec.encode(envelope)
                ) == envelope
            )
        }

        for (index, ownership) in IOSFailedHistoryOwnershipState.allCases
            .enumerated() {
            let entry = try failedHistoryTestEntry(
                index: index + 1,
                ownershipState: ownership
            )
            let envelope = try IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [entry],
                audioCleanup: []
            )
            #expect(
                try IOSFailedHistoryWireCodec.decode(
                    IOSFailedHistoryWireCodec.encode(envelope)
                ) == envelope
            )
        }

        for (index, intent) in [
            DictationOutputIntent.standard,
            .translate,
        ].enumerated() {
            let entry = try failedHistoryTestEntry(
                index: index + 1,
                pipelineStage: intent == .translate
                    ? .translation
                    : .transcription,
                outputIntent: intent
            )
            let envelope = try IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [entry],
                audioCleanup: []
            )
            #expect(
                try IOSFailedHistoryWireCodec.decode(
                    IOSFailedHistoryWireCodec.encode(envelope)
                ) == envelope
            )
        }

        for (index, state) in IOSFailedHistoryRetryOperationState.allCases
            .enumerated() {
            let item = index + 1
            let entry = try failedHistoryTestEntry(
                index: item,
                retryCount: 1,
                retryOperation: failedHistoryTestRetryOperation(
                    index: item,
                    state: state
                )
            )
            let envelope = try IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [entry],
                audioCleanup: []
            )
            #expect(
                try IOSFailedHistoryWireCodec.decode(
                    IOSFailedHistoryWireCodec.encode(envelope)
                ) == envelope
            )
        }
    }

    @Test func wireUUIDsNullsAndRetryCountBoundariesAreStrict() throws {
        for retryCount in [Int32.zero, Int32.max] {
            let entry = try failedHistoryTestEntry(retryCount: retryCount)
            let envelope = try IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [entry],
                audioCleanup: []
            )
            #expect(
                try IOSFailedHistoryWireCodec.decode(
                    IOSFailedHistoryWireCodec.encode(envelope)
                ) == envelope
            )
        }

        let operation = try IOSFailedHistoryRetryOperation(
            retryID: UUID(
                uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1"
            )!,
            createdAt: try failedHistoryTestDate(offsetMilliseconds: 11),
            transcriptionID: UUID(
                uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2"
            )!,
            deliveryID: UUID(
                uuidString: "cccccccc-cccc-4ccc-8ccc-ccccccccccc3"
            )!,
            sessionID: UUID(
                uuidString: "dddddddd-dddd-4ddd-8ddd-ddddddddddd4"
            )!,
            transcriptID: UUID(
                uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5"
            )!,
            state: .reserved
        )
        let rowAttemptID = UUID(
            uuidString: "f1111111-1111-4111-8111-111111111111"
        )!
        let entry = try failedHistoryTestEntry(
            attemptID: rowAttemptID,
            retryCount: 1,
            retryOperation: operation
        )
        let cleanupAttemptID = UUID(
            uuidString: "f2222222-2222-4222-8222-222222222222"
        )!
        let cleanup = try failedHistoryTestAudioCleanup(
            attemptID: cleanupAttemptID
        )
        let canonical = String(
            decoding: try IOSFailedHistoryWireCodec.encode(
                IOSFailedHistoryEnvelope(
                    revision: 1,
                    entries: [entry],
                    audioCleanup: [cleanup]
                )
            ),
            as: UTF8.self
        )
        let rowID = entry.attemptID.uuidString.lowercased()
        let retryID = operation.retryID.uuidString.lowercased()
        let cleanupID = cleanup.attemptID.uuidString.lowercased()
        let strictMutations = [
            canonical.replacingOccurrences(
                of: "\"attemptID\":\"\(rowID)\"",
                with: "\"attemptID\":\"\(rowID.uppercased())\""
            ),
            canonical.replacingOccurrences(
                of: "\"retryID\":\"\(retryID)\"",
                with: "\"retryID\":\"\(retryID.uppercased())\""
            ),
            canonical.replacingOccurrences(
                of: "\"attemptID\":\"\(cleanupID)\"",
                with: "\"attemptID\":\"\(cleanupID.uppercased())\""
            ),
            canonical.replacingOccurrences(
                of: "\"retryCount\":1",
                with: "\"retryCount\":2147483648"
            ),
            canonical.replacingOccurrences(
                of: "\"retryID\":\"\(retryID)\"",
                with:
                    "\"retryID\":\"\(retryID)\",\"retry\\u0049D\":\"\(retryID)\""
            ),
        ]
        for source in strictMutations {
            #expect(throws: (any Error).self) {
                _ = try IOSFailedHistoryWireCodec.decode(Data(source.utf8))
            }
        }

        let nullEntry = try failedHistoryTestEntry(
            transcriptionLanguageCode: nil
        )
        let nullCanonical = String(
            decoding: try IOSFailedHistoryWireCodec.encode(
                IOSFailedHistoryEnvelope(
                    revision: 1,
                    entries: [nullEntry],
                    audioCleanup: []
                )
            ),
            as: UTF8.self
        )
        for source in [
            nullCanonical.replacingOccurrences(
                of: "\"retryOperation\":null,",
                with: ""
            ),
            nullCanonical.replacingOccurrences(
                of: "\"transcriptionLanguageCode\":null,",
                with: ""
            ),
        ] {
            #expect(throws: IOSFailedHistoryError.invalidRecord) {
                _ = try IOSFailedHistoryWireCodec.decode(Data(source.utf8))
            }
        }
    }

    @Test func maximumShapeRoundTripsAndUnsortedWireIsRejected() throws {
        var entries = try (1...5).reversed().map {
            try failedHistoryTestEntry(index: $0)
        }
        entries[0] = try failedHistoryTestEntry(
            index: 5,
            retryCount: 1,
            retryOperation: failedHistoryTestRetryOperation(index: 5)
        )
        let cleanup = try (1...5).map {
            try failedHistoryTestAudioCleanup(index: $0)
        }
        let envelope = try IOSFailedHistoryEnvelope(
            revision: 1,
            entries: entries,
            audioCleanup: cleanup
        )
        let encoded = try IOSFailedHistoryWireCodec.encode(envelope)
        #expect(try IOSFailedHistoryWireCodec.decode(encoded) == envelope)

        var root = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        root["entries"] = try #require(root["entries"] as? [Any]).reversed()
            .map { $0 }
        let reversedEntries = try JSONSerialization.data(
            withJSONObject: root,
            options: [.sortedKeys]
        )
        #expect(throws: IOSFailedHistoryError.invalidRecord) {
            _ = try IOSFailedHistoryWireCodec.decode(reversedEntries)
        }

        root = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        root["audioCleanup"] = try #require(
            root["audioCleanup"] as? [Any]
        ).reversed().map { $0 }
        let reversedCleanup = try JSONSerialization.data(
            withJSONObject: root,
            options: [.sortedKeys]
        )
        #expect(throws: IOSFailedHistoryError.invalidRecord) {
            _ = try IOSFailedHistoryWireCodec.decode(reversedCleanup)
        }
    }

    @Test func schemaDispatchPrecedesV1Allowlists() {
        let future = Data(
            """
            {"schemaVersion":2,"revision":1,"entries":[],"audioCleanup":[],"future":true}
            """.utf8
        )
        #expect(throws: IOSFailedHistoryError.unsupportedSchemaVersion) {
            _ = try IOSFailedHistoryWireCodec.decode(future)
        }
        #expect(throws: IOSFailedHistoryError.invalidRecord) {
            _ = try IOSFailedHistoryWireCodec.decode(
                Data(
                    """
                    {"schemaVersion":1,"revision":1,"entries":[],"audioCleanup":[],"future":true}
                    """.utf8
                )
            )
        }
    }

    @Test func duplicateMissingUnknownAndNumericAliasesAreRejected() {
        let sources = [
            #"{"schemaVersion":1,"schema\u0056ersion":1,"revision":1,"entries":[],"audioCleanup":[]}"#,
            """
            {"schemaVersion":1,"revision":1.0,"entries":[],"audioCleanup":[]}
            """,
            """
            {"schemaVersion":1,"revision":1e0,"entries":[],"audioCleanup":[]}
            """,
            """
            {"schemaVersion":true,"revision":1,"entries":[],"audioCleanup":[]}
            """,
            """
            {"schemaVersion":1,"revision":1,"entries":[]}
            """,
            """
            {"schemaVersion":1,"revision":1,"entries":[null],"audioCleanup":[]}
            """,
        ]
        for source in sources {
            #expect(throws: (any Error).self) {
                _ = try IOSFailedHistoryWireCodec.decode(Data(source.utf8))
            }
        }
    }

    @Test func rowRetryAndTombstoneShapesAreStrict() throws {
        let operation = try failedHistoryTestRetryOperation()
        let envelope = try IOSFailedHistoryEnvelope(
            revision: 1,
            entries: [
                try failedHistoryTestEntry(
                    retryCount: 1,
                    retryOperation: operation
                ),
            ],
            audioCleanup: [try failedHistoryTestAudioCleanup()]
        )
        let canonical = String(
            decoding: try IOSFailedHistoryWireCodec.encode(envelope),
            as: UTF8.self
        )
        let mutations = [
            canonical.replacingOccurrences(
                of: "\"networkFailure\"",
                with: "\"unknown\""
            ),
            canonical.replacingOccurrences(
                of: "\"transcription\"",
                with: "\"recording\""
            ),
            canonical.replacingOccurrences(
                of: "\"ready\"",
                with: "\"unknown\""
            ),
            canonical.replacingOccurrences(
                of: "\"reserved\"",
                with: "\"unknown\""
            ),
            canonical.replacingOccurrences(
                of: "\"transcriptionLanguageCode\":\"en\"",
                with: "\"transcriptionLanguageCode\":1"
            ),
            canonical.replacingOccurrences(
                of: "\"retryOperation\":{",
                with: "\"retryOperation\":{\"future\":1,"
            ),
            canonical.replacingOccurrences(
                of: "\"retryCount\":1",
                with: "\"retryCount\":true"
            ),
            canonical.replacingOccurrences(
                of: "\"audioCleanup\":[{",
                with: "\"audioCleanup\":[{\"future\":1,"
            ),
        ]
        for (index, source) in mutations.enumerated() {
            do {
                _ = try IOSFailedHistoryWireCodec.decode(Data(source.utf8))
                Issue.record("Mutation \(index) unexpectedly decoded")
            } catch let error as IOSFailedHistoryError {
                #expect(error == .invalidRecord)
            } catch {
                Issue.record("Mutation \(index) returned an untyped error")
            }
        }
    }

    @Test func malformedDepthAndSourceLimitsFailBeforeMaterialization() throws {
        #expect(throws: IOSFailedHistoryError.malformedData) {
            _ = try IOSFailedHistoryWireCodec.decode(Data([0x7B, 0xFF, 0x7D]))
        }
        #expect(throws: IOSFailedHistoryError.malformedData) {
            _ = try IOSFailedHistoryWireCodec.decode(
                Data([0xEF, 0xBB, 0xBF] + Array("{}".utf8))
            )
        }
        #expect(throws: IOSFailedHistoryError.malformedData) {
            _ = try IOSFailedHistoryWireCodec.decode(
                Data(
                    """
                    {"schemaVersion":1,"revision":1,"entries":[{"retryOperation":{"nested":[[[[]]]]}}],"audioCleanup":[]}
                    """.utf8
                )
            )
        }
        #expect(throws: IOSFailedHistoryError.sourceTooLarge) {
            _ = try IOSFailedHistoryWireCodec.decode(
                Data(
                    repeating: 0x20,
                    count: IOSFailedHistoryJournal.maximumByteCount + 1
                )
            )
        }

        let empty = try IOSFailedHistoryEnvelope(
            revision: 1,
            entries: [],
            audioCleanup: []
        )
        let canonical = try IOSFailedHistoryWireCodec.encode(empty)
        var exactLimit = canonical
        exactLimit.append(
            Data(
                repeating: 0x20,
                count: IOSFailedHistoryJournal.maximumByteCount
                    - canonical.count
            )
        )
        #expect(try IOSFailedHistoryWireCodec.decode(exactLimit) == empty)
        exactLimit.append(0x20)
        #expect(throws: IOSFailedHistoryError.sourceTooLarge) {
            _ = try IOSFailedHistoryWireCodec.decode(exactLimit)
        }
    }

    @Test func repositoryCreateReplaceAndPhysicalCASAreExact() throws {
        let fileSystem = FailedHistoryFakeFileSystem()
        let repository = FoundationIOSFailedHistoryJournalRepository(
            fileSystem: fileSystem
        )
        let initial = try IOSFailedHistoryEnvelope(
            revision: 1,
            entries: [],
            audioCleanup: []
        )
        let created = try repository.create(
            initial,
            authorization: IOSFailedHistoryJournalMutationAuthorization(
                testingToken: ()
            )
        )
        #expect(created.envelope == initial)
        #expect(try repository.load() == created)
        #expect(throws: IOSFailedHistoryError.slotOccupied) {
            _ = try repository.create(
                initial,
                authorization: IOSFailedHistoryJournalMutationAuthorization(
                    testingToken: ()
                )
            )
        }

        let replacement = try IOSFailedHistoryEnvelope(
            revision: 2,
            entries: [try failedHistoryTestEntry()],
            audioCleanup: []
        )
        let replaced = try repository.replace(
            replacement,
            expected: created,
            authorization: IOSFailedHistoryJournalMutationAuthorization(
                testingToken: ()
            )
        )
        #expect(replaced.envelope == replacement)
        #expect(replaced.fileRevision != created.fileRevision)

        fileSystem.install(fileSystem.file!.data)
        #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try repository.replace(
                initial,
                expected: replaced,
                authorization: IOSFailedHistoryJournalMutationAuthorization(
                    testingToken: ()
                )
            )
        }
    }

    @Test func repositoryMapsTypedFailuresAndPreservesPublishedBytes() throws {
        let fileSystem = FailedHistoryFakeFileSystem()
        let repository = FoundationIOSFailedHistoryJournalRepository(
            fileSystem: fileSystem
        )
        let envelope = try IOSFailedHistoryEnvelope(
            revision: 1,
            entries: [],
            audioCleanup: []
        )

        fileSystem.createFailure = .init(
            error: .commitUncertain,
            commitBeforeThrowing: false
        )
        #expect(throws: IOSFailedHistoryError.commitUncertain) {
            _ = try repository.create(
                envelope,
                authorization: IOSFailedHistoryJournalMutationAuthorization(
                    testingToken: ()
                )
            )
        }
        #expect(fileSystem.file == nil)

        fileSystem.createFailure = .init(
            error: .commitUncertain,
            commitBeforeThrowing: true
        )
        #expect(throws: IOSFailedHistoryError.commitUncertain) {
            _ = try repository.create(
                envelope,
                authorization: IOSFailedHistoryJournalMutationAuthorization(
                    testingToken: ()
                )
            )
        }
        let committedBytes = try #require(fileSystem.file?.data)
        #expect(try IOSFailedHistoryWireCodec.decode(committedBytes) == envelope)

        let committed = try #require(try repository.load())
        let replacement = try IOSFailedHistoryEnvelope(
            revision: 2,
            entries: [try failedHistoryTestEntry()],
            audioCleanup: []
        )
        fileSystem.replaceFailure = .init(
            error: .commitUncertain,
            commitBeforeThrowing: false
        )
        #expect(throws: IOSFailedHistoryError.commitUncertain) {
            _ = try repository.replace(
                replacement,
                expected: committed,
                authorization: IOSFailedHistoryJournalMutationAuthorization(
                    testingToken: ()
                )
            )
        }
        #expect(fileSystem.file?.data == committedBytes)

        fileSystem.replaceFailure = .init(
            error: .commitUncertain,
            commitBeforeThrowing: true
        )
        #expect(throws: IOSFailedHistoryError.commitUncertain) {
            _ = try repository.replace(
                replacement,
                expected: committed,
                authorization: IOSFailedHistoryJournalMutationAuthorization(
                    testingToken: ()
                )
            )
        }
        let replacementBytes = try #require(fileSystem.file?.data)
        #expect(
            try IOSFailedHistoryWireCodec.decode(replacementBytes)
                == replacement
        )

        let replaced = try #require(try repository.load())
        for (fileError, expected) in [
            (IOSStrictProtectedRecordFileSystemError.protectedDataUnavailable,
             IOSFailedHistoryError.dataProtectionUnavailable),
            (.writeFailed, .writeFailed),
        ] {
            fileSystem.replaceFailure = .init(
                error: fileError,
                commitBeforeThrowing: false
            )
            #expect(throws: expected) {
                _ = try repository.replace(
                    replacement,
                    expected: replaced,
                    authorization:
                        IOSFailedHistoryJournalMutationAuthorization(
                            testingToken: ()
                        )
                )
            }
            #expect(fileSystem.file?.data == replacementBytes)
        }

        for (fileError, expected) in [
            (IOSStrictProtectedRecordFileSystemError.sourceTooLarge,
             IOSFailedHistoryError.sourceTooLarge),
            (.protectedDataUnavailable, .dataProtectionUnavailable),
            (.readFailed, .readFailed),
        ] {
            fileSystem.readError = fileError
            #expect(throws: expected) {
                _ = try repository.load()
            }
        }
        #expect(fileSystem.file?.data == replacementBytes)
    }

    @Test func corruptAndFutureSourcesRemainUntouched() throws {
        let fileSystem = FailedHistoryFakeFileSystem()
        let repository = FoundationIOSFailedHistoryJournalRepository(
            fileSystem: fileSystem
        )

        for (data, expected) in [
            (Data("corrupt".utf8), IOSFailedHistoryError.malformedData),
            (Data(
                """
                {"schemaVersion":2,"revision":1,"entries":[],"audioCleanup":[]}
                """.utf8
            ), .unsupportedSchemaVersion),
        ] {
            fileSystem.install(data)
            #expect(throws: expected) {
                _ = try repository.load()
            }
            #expect(fileSystem.file?.data == data)
        }
    }

    @Test func maintenanceMappingIsContentFree() throws {
        let expected = IOSStrictProtectedRecordMaintenanceReport(
            inspectedEntryCount: 4,
            inspectedByteCount: 80,
            removedFileCount: 1,
            removedByteCount: 20,
            reachedLimit: false
        )
        let repository = FoundationIOSFailedHistoryJournalRepository(
            fileSystem: FailedHistoryFakeFileSystem(),
            stagingMaintenance: { _ in expected }
        )
        #expect(
            try repository.performStagingMaintenance(
                now: try failedHistoryTestDate()
            ) == expected
        )
    }
}
