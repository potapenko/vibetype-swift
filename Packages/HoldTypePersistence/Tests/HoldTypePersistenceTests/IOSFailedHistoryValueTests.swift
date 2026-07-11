import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSFailedHistoryValueTests {
    @Test func validValuesAreSendableAndDiagnosticsAreRedacted() throws {
        let operation = try failedHistoryTestRetryOperation()
        let entry = try failedHistoryTestEntry(
            retryCount: 1,
            retryOperation: operation
        )
        let cleanup = try failedHistoryTestAudioCleanup()
        let envelope = try IOSFailedHistoryEnvelope(
            revision: 1,
            entries: [entry],
            audioCleanup: [cleanup]
        )
        let report = IOSFailedHistoryMaintenanceReport(.empty)

        #expect(String(describing: entry) == "IOSFailedHistoryEntry(redacted)")
        #expect(
            String(reflecting: operation)
                == "IOSFailedHistoryRetryOperation(redacted)"
        )
        #expect(
            String(describing: cleanup)
                == "IOSFailedHistoryAudioCleanup(redacted)"
        )
        #expect(
            String(reflecting: envelope)
                == "IOSFailedHistoryEnvelope(redacted)"
        )
        #expect(
            String(describing: IOSFailedHistoryError.commitUncertain)
                == "IOSFailedHistoryError(redacted)"
        )
        #expect(report.customMirror.children.isEmpty)
        #expect(entry.customMirror.children.isEmpty)
        #expect(envelope.customMirror.children.isEmpty)

        requireFailedHistorySendable(IOSFailedHistoryEntry.self)
        requireFailedHistorySendable(IOSFailedHistoryEnvelope.self)
        requireFailedHistorySendable(IOSFailedHistoryAudioCleanup.self)
        requireFailedHistorySendable(IOSFailedHistoryRetryOperation.self)
        requireFailedHistorySendable(IOSFailedHistoryError.self)
    }

    @Test func stableEnumSpellingsAreExactAndComplete() {
        #expect(IOSFailedHistoryFailureCategory.allCases.map(\.rawValue) == [
            "credentialRejected",
            "networkUnavailable",
            "networkFailure",
            "timedOut",
            "rateLimited",
            "providerUnavailable",
            "providerRejected",
            "invalidResponse",
            "emptyResult",
            "echoRejected",
        ])
        #expect(IOSFailedHistoryPipelineStage.allCases.map(\.rawValue) == [
            "transcription",
            "translation",
        ])
        #expect(IOSFailedHistoryOwnershipState.allCases.map(\.rawValue) == [
            "pendingJournalRetirement",
            "ready",
        ])
        #expect(
            IOSFailedHistoryRetryOperationState.allCases.map(\.rawValue) == [
                "reserved",
                "providerDispatched",
                "acceptingOutput",
            ]
        )
    }

    @Test func entryRejectsInvalidMetadataAudioAndStateRelations() throws {
        for model in [
            "",
            " model",
            "model ",
            "model\u{0001}",
            String(
                repeating: "m",
                count: IOSPendingRecordingValidation.maximumModelByteCount + 1
            ),
        ] {
            #expect(throws: IOSFailedHistoryError.invalidEntry) {
                _ = try failedHistoryTestEntry(transcriptionModel: model)
            }
        }
        for language in ["E", "EN", "engl", "e1"] {
            #expect(throws: IOSFailedHistoryError.invalidEntry) {
                _ = try failedHistoryTestEntry(
                    transcriptionLanguageCode: language
                )
            }
        }
        for duration in [0, 300_000, -1] as [Int64] {
            #expect(throws: IOSFailedHistoryError.invalidEntry) {
                _ = try failedHistoryTestEntry(
                    durationMilliseconds: duration
                )
            }
        }
        for byteCount in [0, 25_000_000, -1] as [Int64] {
            #expect(throws: IOSFailedHistoryError.invalidEntry) {
                _ = try failedHistoryTestEntry(byteCount: byteCount)
            }
        }
        #expect(throws: IOSFailedHistoryError.invalidEntry) {
            _ = try failedHistoryTestEntry(policyGeneration: 0)
        }
        #expect(throws: IOSFailedHistoryError.invalidEntry) {
            _ = try failedHistoryTestEntry(retryCount: -1)
        }
        #expect(throws: IOSFailedHistoryError.invalidEntry) {
            _ = try failedHistoryTestEntry(
                createdAt: try failedHistoryTestDate()
                    .addingTimeInterval(0.0005)
            )
        }
        #expect(throws: IOSFailedHistoryError.invalidEntry) {
            let foreignAttempt = failedHistoryTestUUID(
                namespace: 0x01,
                index: 2
            )
            _ = try failedHistoryTestEntry(
                audioRelativeIdentifier:
                    IOSPendingRecordingStorageLocation.relativeAudioIdentifier(
                        for: foreignAttempt,
                        format: .m4a
                    )
            )
        }
        #expect(throws: IOSFailedHistoryError.invalidEntry) {
            _ = try failedHistoryTestEntry(
                pipelineStage: .translation,
                outputIntent: .standard
            )
        }

        let operation = try failedHistoryTestRetryOperation()
        #expect(throws: IOSFailedHistoryError.invalidEntry) {
            _ = try failedHistoryTestEntry(
                retryCount: 0,
                retryOperation: operation
            )
        }
        #expect(throws: IOSFailedHistoryError.invalidEntry) {
            _ = try failedHistoryTestEntry(
                retryCount: 1,
                ownershipState: .pendingJournalRetirement,
                retryOperation: operation
            )
        }
        #expect(throws: IOSFailedHistoryError.invalidEntry) {
            _ = try failedHistoryTestEntry(
                retryCount: 1,
                ownershipState: .pendingJournalRetirement
            )
        }
    }

    @Test func retryOperationRejectsDuplicateIdentityAndNoncanonicalTime() throws {
        let identifier = failedHistoryTestUUID(namespace: 0x20, index: 1)
        #expect(throws: IOSFailedHistoryError.invalidEntry) {
            _ = try IOSFailedHistoryRetryOperation(
                retryID: identifier,
                createdAt: try failedHistoryTestDate(),
                transcriptionID: identifier,
                deliveryID: failedHistoryTestUUID(namespace: 0x21, index: 1),
                sessionID: failedHistoryTestUUID(namespace: 0x22, index: 1),
                transcriptID: failedHistoryTestUUID(namespace: 0x23, index: 1),
                state: .reserved
            )
        }
        #expect(throws: IOSFailedHistoryError.invalidEntry) {
            _ = try failedHistoryTestRetryOperation(
                createdAt: try failedHistoryTestDate()
                    .addingTimeInterval(0.0005)
            )
        }
    }

    @Test func envelopeEnforcesOrderCapacityUniquenessAndOneRetry() throws {
        let older = try failedHistoryTestEntry(index: 1)
        let newer = try failedHistoryTestEntry(index: 2)
        _ = try IOSFailedHistoryEnvelope(
            revision: 1,
            entries: [newer, older],
            audioCleanup: []
        )
        #expect(throws: IOSFailedHistoryError.invalidRecord) {
            _ = try IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [older, newer],
                audioCleanup: []
            )
        }

        let tiedAt = try failedHistoryTestDate(offsetMilliseconds: 500)
        let lowerTie = try failedHistoryTestEntry(
            index: 1,
            createdAt: tiedAt,
            updatedAt: tiedAt
        )
        let higherTie = try failedHistoryTestEntry(
            index: 2,
            createdAt: tiedAt,
            updatedAt: tiedAt
        )
        _ = try IOSFailedHistoryEnvelope(
            revision: 1,
            entries: [lowerTie, higherTie],
            audioCleanup: []
        )
        #expect(throws: IOSFailedHistoryError.invalidRecord) {
            _ = try IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [higherTie, lowerTie],
                audioCleanup: []
            )
        }

        let earlierCleanup = try failedHistoryTestAudioCleanup(index: 1)
        let laterCleanup = try failedHistoryTestAudioCleanup(index: 2)
        _ = try IOSFailedHistoryEnvelope(
            revision: 1,
            entries: [],
            audioCleanup: [earlierCleanup, laterCleanup]
        )
        #expect(throws: IOSFailedHistoryError.invalidRecord) {
            _ = try IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [],
                audioCleanup: [laterCleanup, earlierCleanup]
            )
        }

        let lowerCleanupTie = try failedHistoryTestAudioCleanup(
            index: 1,
            queuedAt: tiedAt
        )
        let higherCleanupTie = try failedHistoryTestAudioCleanup(
            index: 2,
            queuedAt: tiedAt
        )
        _ = try IOSFailedHistoryEnvelope(
            revision: 1,
            entries: [],
            audioCleanup: [lowerCleanupTie, higherCleanupTie]
        )
        #expect(throws: IOSFailedHistoryError.invalidRecord) {
            _ = try IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [],
                audioCleanup: [higherCleanupTie, lowerCleanupTie]
            )
        }
        #expect(throws: IOSFailedHistoryError.invalidRecord) {
            _ = try IOSFailedHistoryEnvelope(
                revision: 0,
                entries: [],
                audioCleanup: []
            )
        }

        let sixEntries = try (1...6).reversed().map {
            try failedHistoryTestEntry(index: $0)
        }
        #expect(throws: IOSFailedHistoryError.invalidRecord) {
            _ = try IOSFailedHistoryEnvelope(
                revision: 1,
                entries: sixEntries,
                audioCleanup: []
            )
        }
        let sixCleanup = try (1...6).map {
            try failedHistoryTestAudioCleanup(index: $0)
        }
        #expect(throws: IOSFailedHistoryError.invalidRecord) {
            _ = try IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [],
                audioCleanup: sixCleanup
            )
        }

        let duplicateCleanup = try failedHistoryTestAudioCleanup(
            index: 10,
            attemptID: older.attemptID,
            audioRelativeIdentifier: older.audioRelativeIdentifier
        )
        #expect(throws: IOSFailedHistoryError.invalidRecord) {
            _ = try IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [older],
                audioCleanup: [duplicateCleanup]
            )
        }

        let firstRetry = try failedHistoryTestEntry(
            index: 1,
            retryCount: 1,
            retryOperation: failedHistoryTestRetryOperation(index: 1)
        )
        let secondRetry = try failedHistoryTestEntry(
            index: 2,
            retryCount: 1,
            retryOperation: failedHistoryTestRetryOperation(index: 2)
        )
        #expect(throws: IOSFailedHistoryError.invalidRecord) {
            _ = try IOSFailedHistoryEnvelope(
                revision: 1,
                entries: [secondRetry, firstRetry],
                audioCleanup: []
            )
        }
    }

    @Test func entryEqualityUsesExactModelBytes() throws {
        let composed = "é"
        let decomposed = "e\u{301}"
        #expect(composed == decomposed)

        let lhs = try failedHistoryTestEntry(transcriptionModel: composed)
        let rhs = try failedHistoryTestEntry(transcriptionModel: decomposed)
        #expect(lhs != rhs)
    }

    @Test func timestampBoundsFailWithoutTrapping() throws {
        #expect(throws: IOSFailedHistoryError.invalidRecord) {
            _ = try IOSFailedHistoryTimestampCodec.date(from: Int64.max)
        }
        let upperBoundary = Date(
            timeIntervalSince1970:
                9_223_372_036_854_775_808.0 / 1_000.0
        )
        #expect(throws: IOSFailedHistoryError.invalidRecord) {
            _ = try IOSFailedHistoryTimestampCodec.canonicalDate(
                from: upperBoundary
            )
        }
    }

    @Test func pendingModelBoundIsSharedAndExplicit() throws {
        let maximum = String(
            repeating: "m",
            count: IOSPendingRecordingValidation.maximumModelByteCount
        )
        #expect(IOSPendingRecordingValidation.isValidModel(maximum))
        #expect(
            !IOSPendingRecordingValidation.isValidModel(maximum + "m")
        )
        for invalid in [" model", "model ", "model\u{0001}"] {
            #expect(!IOSPendingRecordingValidation.isValidModel(invalid))
            #expect(throws: IOSFailedHistoryError.invalidEntry) {
                _ = try failedHistoryTestEntry(transcriptionModel: invalid)
            }
        }
        _ = try failedHistoryTestEntry(transcriptionModel: maximum)
    }

    @Test func storageLocationAndStrictConfigurationAreExact() {
        let base = URL(fileURLWithPath: "/private/app-support", isDirectory: true)
        #expect(
            IOSFailedHistoryStorageLocation.fileURL(in: base).path
                == "/private/app-support/HoldType/ios-failed-history.json"
        )
        let configuration = IOSStrictProtectedRecordConfiguration.failedHistory
        #expect(configuration.rootDirectoryName == "HoldType")
        #expect(configuration.fileName == "ios-failed-history.json")
        #expect(configuration.maximumByteCount == 1_048_576)
        #expect(
            configuration.marker?.name
                == "com.holdtype.ios.failed-history"
        )
        #expect(configuration.marker?.value == Array("v1".utf8))
    }
}
