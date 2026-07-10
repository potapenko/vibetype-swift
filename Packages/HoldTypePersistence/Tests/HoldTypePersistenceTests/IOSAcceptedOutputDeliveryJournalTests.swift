import Darwin
import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSAcceptedOutputDeliveryJournalTests {
    @Test func canonicalV1HasExactRootAndHistoryKeysAndRoundTrips() throws {
        let history = try IOSAcceptedOutputHistoryWrite(
            policyGeneration: 4,
            transcriptionModel: "whisper-1",
            transcriptionLanguageCode: "fr",
            durationMilliseconds: 12_345
        )
        let record = try journalRecord(historyWrite: history)

        let data = try IOSAcceptedOutputDeliveryWireCodec.encode(record)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(Set(object.keys) == IOSAcceptedOutputDeliveryWireCodec.fields)
        let historyObject = try #require(
            object["historyWrite"] as? [String: Any]
        )
        #expect(
            Set(historyObject.keys)
                == IOSAcceptedOutputDeliveryWireCodec.historyFields
        )
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["deliveryID"] as? String == record.deliveryID.uuidString.lowercased())
        #expect(object["publicationGeneration"] as? Int == 0)
        #expect(historyObject["state"] as? String == "pending")
        #expect(try IOSAcceptedOutputDeliveryWireCodec.decode(data) == record)
    }

    @Test func everyHistoryStateAndExplicitNullRoundTrips() throws {
        for state in [
            IOSAcceptedOutputHistoryWriteState.pending,
            .committed,
            .cancelled,
        ] {
            let history = try IOSAcceptedOutputHistoryWrite(
                state: state,
                policyGeneration: 1,
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
            let record = try journalRecord(historyWrite: history)
            let decoded = try IOSAcceptedOutputDeliveryWireCodec.decode(
                IOSAcceptedOutputDeliveryWireCodec.encode(record)
            )
            #expect(decoded.historyWrite == history)
        }

        let noHistory = try journalRecord(historyWrite: nil)
        let object = try #require(
            JSONSerialization.jsonObject(
                with: IOSAcceptedOutputDeliveryWireCodec.encode(noHistory)
            ) as? [String: Any]
        )
        #expect(object["historyWrite"] is NSNull)
    }

    @Test func schemaVersionPrecedesV1AllowlistAndShapeValidation() throws {
        let data = try IOSAcceptedOutputDeliveryWireCodec.encode(journalRecord())
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["schemaVersion"] = 2
        object["futureField"] = "future"
        object.removeValue(forKey: "acceptedText")

        #expect(
            throws: IOSAcceptedOutputDeliveryError.unsupportedSchemaVersion
        ) {
            try IOSAcceptedOutputDeliveryWireCodec.decode(
                JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    @Test func futureSchemaWithSeventeenthRootFieldRemainsUnsupported() throws {
        let data = try IOSAcceptedOutputDeliveryWireCodec.encode(journalRecord())
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["schemaVersion"] = 2
        object["futureField"] = "future"
        #expect(object.count == 17)

        #expect(
            throws: IOSAcceptedOutputDeliveryError.unsupportedSchemaVersion
        ) {
            try IOSAcceptedOutputDeliveryWireCodec.decode(
                JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    @Test func duplicateUnknownMissingAndWrongTypedMembersAreRejected() throws {
        let canonical = try IOSAcceptedOutputDeliveryWireCodec.encode(
            journalRecord()
        )
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
        #expect(throws: IOSAcceptedOutputDeliveryError.malformedData) {
            try IOSAcceptedOutputDeliveryWireCodec.decode(duplicate)
        }

        var object = try #require(
            JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        )
        object["unknown"] = true
        #expect(throws: IOSAcceptedOutputDeliveryError.invalidRecord) {
            try IOSAcceptedOutputDeliveryWireCodec.decode(
                JSONSerialization.data(withJSONObject: object)
            )
        }
        object.removeValue(forKey: "unknown")
        object.removeValue(forKey: "acceptedText")
        #expect(throws: IOSAcceptedOutputDeliveryError.invalidRecord) {
            try IOSAcceptedOutputDeliveryWireCodec.decode(
                JSONSerialization.data(withJSONObject: object)
            )
        }
        object["acceptedText"] = "accepted"
        object["automaticInsertionPreferenceEnabled"] = 1
        #expect(throws: IOSAcceptedOutputDeliveryError.invalidRecord) {
            try IOSAcceptedOutputDeliveryWireCodec.decode(
                JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    @Test func canonicalUUIDDateEnumsAndGenerationAreStrict() throws {
        let canonical = try IOSAcceptedOutputDeliveryWireCodec.encode(
            journalRecord()
        )
        let base = try #require(
            JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        )
        let mutations: [(String, Any)] = [
            ("deliveryID", (base["deliveryID"] as! String).uppercased()),
            ("createdAt", "2027-01-15T08:00:00Z"),
            ("outputIntent", "unknown"),
            ("deliveryState", "unknown"),
            ("publicationGeneration", 2),
        ]
        for (key, value) in mutations {
            var object = base
            object[key] = value
            #expect(throws: IOSAcceptedOutputDeliveryError.invalidRecord) {
                try IOSAcceptedOutputDeliveryWireCodec.decode(
                    JSONSerialization.data(withJSONObject: object)
                )
            }
        }
    }

    @Test func wireDecodeNeverSilentlyTrimsHistoryMetadata() throws {
        let history = try IOSAcceptedOutputHistoryWrite(
            policyGeneration: 1,
            transcriptionModel: "model",
            transcriptionLanguageCode: nil,
            durationMilliseconds: nil
        )
        let data = try IOSAcceptedOutputDeliveryWireCodec.encode(
            journalRecord(historyWrite: history)
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var historyObject = try #require(
            object["historyWrite"] as? [String: Any]
        )
        historyObject["transcriptionModel"] = " model "
        object["historyWrite"] = historyObject

        #expect(throws: IOSAcceptedOutputDeliveryError.invalidRecord) {
            try IOSAcceptedOutputDeliveryWireCodec.decode(
                JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    @Test func malformedUTF8DepthArraysAndSourceLimitFailBeforeMaterialization() throws {
        #expect(throws: IOSAcceptedOutputDeliveryError.malformedData) {
            try IOSAcceptedOutputDeliveryWireCodec.decode(Data([0x7B, 0xFF, 0x7D]))
        }
        let canonical = try IOSAcceptedOutputDeliveryWireCodec.encode(
            journalRecord()
        )
        #expect(throws: IOSAcceptedOutputDeliveryError.malformedData) {
            try IOSAcceptedOutputDeliveryWireCodec.decode(
                Data([0xEF, 0xBB, 0xBF]) + canonical
            )
        }
        #expect(throws: IOSAcceptedOutputDeliveryError.malformedData) {
            try IOSAcceptedOutputDeliveryWireCodec.decode(
                Data("{\"schemaVersion\":1,\"a\":{\"b\":{\"c\":1}}}".utf8)
            )
        }
        #expect(throws: IOSAcceptedOutputDeliveryError.invalidRecord) {
            try IOSAcceptedOutputDeliveryWireCodec.decode(
                Data("{\"schemaVersion\":1,\"a\":[]}".utf8)
            )
        }
        #expect(throws: IOSAcceptedOutputDeliveryError.sourceTooLarge) {
            try IOSAcceptedOutputDeliveryWireCodec.decode(
                Data(
                    repeating: 0x20,
                    count: IOSAcceptedOutputDeliveryJournal.maximumByteCount + 1
                )
            )
        }
        #expect(throws: IOSAcceptedOutputDeliveryError.malformedData) {
            try IOSAcceptedOutputDeliveryWireCodec.decode(
                Data(
                    repeating: 0x20,
                    count: IOSAcceptedOutputDeliveryJournal.maximumByteCount
                )
            )
        }
    }

    @Test func acceptedTextExactLimitRoundTripsWithoutUnicodeMutation() throws {
        let payload = String(
            repeating: "a",
            count: IOSAcceptedOutputDeliveryValidation.maximumAcceptedTextByteCount
        )
        let preparation = try journalPreparation(rawAcceptedText: payload)
        let record = try journalRecord(preparation: preparation)
        let decoded = try IOSAcceptedOutputDeliveryWireCodec.decode(
            IOSAcceptedOutputDeliveryWireCodec.encode(record)
        )
        #expect(decoded.acceptedText?.utf8.elementsEqual(payload.utf8) == true)
    }

    @Test func escapedAcceptedTextLimitIsEnforcedBeforeMaterialization() throws {
        let canonical = try IOSAcceptedOutputDeliveryWireCodec.encode(
            journalRecord()
        )
        let canonicalString = try #require(
            String(data: canonical, encoding: .utf8)
        )
        let originalMember = #""acceptedText":"accepted""#
        let escapeUnit = #"\u0061"#
        let exactEscapedValue = String(
            repeating: escapeUnit,
            count: IOSAcceptedOutputDeliveryValidation
                .maximumAcceptedTextByteCount
        )
        let exactData = Data(
            canonicalString.replacingOccurrences(
                of: originalMember,
                with: "\"acceptedText\":\"\(exactEscapedValue)\""
            ).utf8
        )
        #expect(exactData.count < IOSAcceptedOutputDeliveryJournal.maximumByteCount)
        let exactRecord = try IOSAcceptedOutputDeliveryWireCodec.decode(exactData)
        #expect(
            exactRecord.acceptedText?.utf8.count
                == IOSAcceptedOutputDeliveryValidation
                    .maximumAcceptedTextByteCount
        )

        let oversizedData = Data(
            canonicalString.replacingOccurrences(
                of: originalMember,
                with: "\"acceptedText\":\"\(exactEscapedValue)\(escapeUnit)\""
            ).utf8
        )
        #expect(
            oversizedData.count
                < IOSAcceptedOutputDeliveryJournal.maximumByteCount
        )
        #expect(throws: IOSAcceptedOutputDeliveryError.malformedData) {
            try IOSAcceptedOutputDeliveryWireCodec.decode(oversizedData)
        }
    }

    @Test func repositoryUsesFileRevisionCASAndTypedUncertainty() throws {
        let fileSystem = AcceptedDeliveryFakeFileSystem()
        let repository = FoundationIOSAcceptedOutputDeliveryJournalRepository(
            fileSystem: fileSystem
        )
        let initial = try journalRecord()
        let created = try repository.create(initial)
        #expect(try repository.load() == created)

        let replacement = try journalRecord(
            preparation: journalPreparation(
                deliveryID: initial.deliveryID,
                sessionID: initial.sessionID,
                attemptID: initial.attemptID,
                transcriptID: initial.transcriptID
            ),
            revision: 2
        )
        let replaced = try repository.replace(replacement, expected: created)
        #expect(replaced.record == replacement)
        #expect(throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed) {
            try repository.replace(initial, expected: created)
        }

        fileSystem.replaceError = .commitUncertain
        #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            try repository.replace(initial, expected: replaced)
        }
    }

    @Test func opaqueReadBypassesCodecAndMarkerButRemovalPinsRevision() throws {
        let fileSystem = AcceptedDeliveryFakeFileSystem()
        fileSystem.file = IOSStrictProtectedRecordFile(
            data: Data("corrupt".utf8),
            revision: IOSStrictProtectedRecordFileRevision(testingToken: 1)
        )
        fileSystem.readError = .invalidFile
        fileSystem.opaqueRevision = IOSStrictProtectedRecordFileRevision(
            testingToken: 1
        )
        let repository = FoundationIOSAcceptedOutputDeliveryJournalRepository(
            fileSystem: fileSystem
        )

        #expect(throws: IOSAcceptedOutputDeliveryError.readFailed) {
            try repository.load()
        }
        let pinned = try #require(try repository.loadOpaque())
        fileSystem.opaqueRevision = IOSStrictProtectedRecordFileRevision(
            testingToken: 2
        )
        #expect(throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed) {
            try repository.removeOpaque(expected: pinned)
        }
        let current = try #require(try repository.loadOpaque())
        try repository.removeOpaque(expected: current)
        #expect(fileSystem.removeCount == 1)
    }

    @Test func storageLocationPolicyAndMaintenanceMappingAreExact() throws {
        let base = URL(fileURLWithPath: "/private/app-support", isDirectory: true)
        #expect(
            IOSAcceptedOutputDeliveryStorageLocation.fileURL(in: base).path
                == "/private/app-support/HoldType/ios-accepted-output-delivery.json"
        )
        #expect(IOSStrictProtectedRecordConfiguration.acceptedOutputDelivery.rootDirectoryName == "HoldType")
        #expect(IOSStrictProtectedRecordConfiguration.acceptedOutputDelivery.fileName == "ios-accepted-output-delivery.json")
        #expect(IOSStrictProtectedRecordConfiguration.acceptedOutputDelivery.maximumByteCount == 1_048_576)
        #expect(IOSStrictProtectedRecordConfiguration.acceptedOutputDelivery.marker?.name == "com.holdtype.ios.accepted-output-delivery")
        #expect(IOSStrictProtectedRecordConfiguration.acceptedOutputDelivery.marker?.value == Array("v1".utf8))

        let fileSystem = AcceptedDeliveryFakeFileSystem()
        let expected = IOSStrictProtectedRecordMaintenanceReport(
            inspectedEntryCount: 3,
            inspectedByteCount: 40,
            removedFileCount: 1,
            removedByteCount: 10,
            reachedLimit: false
        )
        let repository = FoundationIOSAcceptedOutputDeliveryJournalRepository(
            fileSystem: fileSystem,
            stagingMaintenance: { _ in expected }
        )
        #expect(
            try repository.performStagingMaintenance(
                now: Date(timeIntervalSince1970: 1_800_000_000)
            ) == expected
        )
    }

    @Test func liveRepositoryUsesExactPrivatePathModeAndMarker() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "accepted-output-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: base) }
        let repository = FoundationIOSAcceptedOutputDeliveryJournalRepository(
            applicationSupportDirectoryURL: base
        )
        let record = try journalRecord()

        let created = try repository.create(record)
        #expect(try repository.load() == created)

        let fileURL = IOSAcceptedOutputDeliveryStorageLocation.fileURL(in: base)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let descriptor = Darwin.open(fileURL.path, O_RDONLY | O_CLOEXEC)
        let validDescriptor = try #require(descriptor >= 0 ? descriptor : nil)
        defer { Darwin.close(validDescriptor) }
        let marker = try #require(
            IOSStrictProtectedRecordConfiguration.acceptedOutputDelivery.marker
        )
        var markerBytes = [UInt8](repeating: 0, count: marker.value.count + 1)
        let byteCount = marker.name.withCString { name in
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
        #expect(byteCount == marker.value.count)
        #expect(Array(markerBytes.prefix(marker.value.count)) == marker.value)
    }
}

private final class AcceptedDeliveryFakeFileSystem:
    IOSStrictProtectedRecordFileSystem,
    @unchecked Sendable {
    var file: IOSStrictProtectedRecordFile?
    var opaqueRevision: IOSStrictProtectedRecordFileRevision?
    var readError: IOSStrictProtectedRecordFileSystemError?
    var replaceError: IOSStrictProtectedRecordFileSystemError?
    var removeCount = 0
    private var nextToken: UInt64 = 1

    func readFileIfPresent() throws -> IOSStrictProtectedRecordFile? {
        if let readError { throw readError }
        return file
    }

    func readOpaqueFileRevisionIfPresent() throws
        -> IOSStrictProtectedRecordFileRevision? {
        opaqueRevision ?? file?.revision
    }

    func createFile(
        with data: Data
    ) throws -> IOSStrictProtectedRecordFileRevision {
        guard file == nil else {
            throw IOSStrictProtectedRecordFileSystemError.destinationConflict
        }
        let revision = makeRevision()
        file = IOSStrictProtectedRecordFile(data: data, revision: revision)
        opaqueRevision = revision
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
        opaqueRevision = revision
        return revision
    }

    func removeFile(
        expected: IOSStrictProtectedRecordFileRevision
    ) throws {
        let current = opaqueRevision ?? file?.revision
        guard current == expected else {
            throw IOSStrictProtectedRecordFileSystemError.staleRevision
        }
        file = nil
        opaqueRevision = nil
        removeCount += 1
    }

    private func makeRevision() -> IOSStrictProtectedRecordFileRevision {
        defer { nextToken += 1 }
        return IOSStrictProtectedRecordFileRevision(testingToken: nextToken)
    }
}

private func journalPreparation(
    deliveryID: UUID = UUID(),
    sessionID: UUID = UUID(),
    attemptID: UUID = UUID(),
    transcriptID: UUID = UUID(),
    rawAcceptedText: String = "accepted"
) throws -> IOSAcceptedOutputDeliveryPreparation {
    try IOSAcceptedOutputDeliveryPreparation(
        deliveryID: deliveryID,
        sessionID: sessionID,
        attemptID: attemptID,
        transcriptID: transcriptID,
        rawAcceptedText: rawAcceptedText,
        outputIntent: .translate,
        automaticInsertionPreferenceEnabled: true,
        keepLatestResult: true,
        historyWrite: nil
    )
}

private func journalRecord(
    preparation: IOSAcceptedOutputDeliveryPreparation? = nil,
    revision: Int64 = 1,
    publicationGeneration: Int64 = 0,
    historyWrite: IOSAcceptedOutputHistoryWrite? = nil
) throws -> IOSAcceptedOutputDeliveryRecord {
    let preparation = try preparation ?? journalPreparation()
    let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    return try IOSAcceptedOutputDeliveryRecord(
        revision: revision,
        deliveryID: preparation.deliveryID,
        sessionID: preparation.sessionID,
        attemptID: preparation.attemptID,
        transcriptID: preparation.transcriptID,
        acceptedText: preparation.acceptedText,
        outputIntent: preparation.outputIntent,
        createdAt: createdAt,
        updatedAt: createdAt,
        expiresAt: createdAt.addingTimeInterval(86_400),
        deliveryState: .pending,
        automaticInsertionPreferenceEnabled: true,
        keepLatestResult: true,
        publicationGeneration: publicationGeneration,
        historyWrite: historyWrite
    )
}
