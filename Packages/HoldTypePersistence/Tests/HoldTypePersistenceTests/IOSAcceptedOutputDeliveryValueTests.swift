import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSAcceptedOutputDeliveryValueTests {
    @Test func preparationUsesFrozenTrimAndPreservesAcceptedUTF8Exactly() throws {
        let edgeScalars = [
            "\u{0009}", "\u{000A}", "\u{000D}", "\u{0020}", "\u{00A0}",
            "\u{1680}", "\u{2000}", "\u{200A}", "\u{2028}", "\u{2029}",
            "\u{202F}", "\u{205F}", "\u{3000}",
        ]
        let payload = "👩🏽‍💻 e\u{301} \u{2067}RTL\u{2069}\r\n\tinside"

        for edge in edgeScalars {
            let preparation = try makePreparation(
                rawAcceptedText: edge + payload + edge
            )
            #expect(preparation.acceptedText.utf8.elementsEqual(payload.utf8))
        }
    }

    @Test func preparationRejectsForbiddenControlsWhitespaceAndOversize() {
        for value in ["", " \n\t\u{3000}", "a\u{0000}b", "a\u{007F}b", "a\u{0085}b"] {
            #expect(throws: IOSAcceptedOutputDeliveryError.invalidPreparation) {
                try makePreparation(rawAcceptedText: value)
            }
        }
        #expect(throws: IOSAcceptedOutputDeliveryError.invalidPreparation) {
            try makePreparation(
                rawAcceptedText: String(
                    repeating: "a",
                    count: IOSAcceptedOutputDeliveryValidation
                        .maximumAcceptedTextByteCount + 1
                )
            )
        }
    }

    @Test func acceptedTranscriptMayNotSilentlyApplyAdditionalFoundationTrim() {
        #expect(throws: IOSAcceptedOutputDeliveryError.invalidPreparation) {
            try makePreparation(rawAcceptedText: "\u{200B}payload\u{200B}")
        }
    }

    @Test func payloadIdentityUsesUTF8RatherThanCanonicalStringEquality() throws {
        let decomposed = try makePreparation(rawAcceptedText: "e\u{301}")
        let composed = try makePreparation(
            deliveryID: decomposed.deliveryID,
            attemptID: decomposed.attemptID,
            transcriptID: decomposed.transcriptID,
            rawAcceptedText: "é"
        )
        #expect(decomposed.acceptedText == composed.acceptedText)
        #expect(decomposed != composed)

        let record = try makeRecord(from: decomposed)
        #expect(record.collides(with: composed))
        #expect(!record.hasSameAcceptance(as: composed))
    }

    @Test func historyMetadataIsStrictAndPreparationRequiresPendingState() throws {
        let history = try IOSAcceptedOutputHistoryWrite(
            policyGeneration: 1,
            transcriptionModel: "  gpt-4o-mini-transcribe  ",
            transcriptionLanguageCode: "en",
            durationMilliseconds: 299_999
        )
        #expect(history.state == .pending)
        #expect(history.transcriptionModel == "gpt-4o-mini-transcribe")

        for generation in [Int64.min, -1, 0] {
            #expect(throws: IOSAcceptedOutputDeliveryError.invalidPreparation) {
                try IOSAcceptedOutputHistoryWrite(
                    policyGeneration: generation,
                    transcriptionModel: "model",
                    transcriptionLanguageCode: nil,
                    durationMilliseconds: nil
                )
            }
        }
        for language in ["EN", "e", "engl", "e1"] {
            #expect(throws: IOSAcceptedOutputDeliveryError.invalidPreparation) {
                try IOSAcceptedOutputHistoryWrite(
                    policyGeneration: 1,
                    transcriptionModel: "model",
                    transcriptionLanguageCode: language,
                    durationMilliseconds: nil
                )
            }
        }
        for duration in [Int64.min, 0, 300_000] {
            #expect(throws: IOSAcceptedOutputDeliveryError.invalidPreparation) {
                try IOSAcceptedOutputHistoryWrite(
                    policyGeneration: 1,
                    transcriptionModel: "model",
                    transcriptionLanguageCode: nil,
                    durationMilliseconds: duration
                )
            }
        }
        #expect(throws: IOSAcceptedOutputDeliveryError.invalidPreparation) {
            try IOSAcceptedOutputHistoryWrite(
                policyGeneration: 1,
                transcriptionModel: String(repeating: "x", count: 257),
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }

        let committed = try history.replacingState(.committed)
        #expect(throws: IOSAcceptedOutputDeliveryError.invalidPreparation) {
            try makePreparation(historyWrite: committed)
        }
    }

    @Test func duplicateAcceptanceIgnoresOnlyDocumentedMutableFields() throws {
        let pending = try IOSAcceptedOutputHistoryWrite(
            policyGeneration: 7,
            transcriptionModel: "model",
            transcriptionLanguageCode: "en",
            durationMilliseconds: 42
        )
        let preparation = try makePreparation(
            keepLatestResult: true,
            historyWrite: pending
        )
        let advanced = try makeRecord(
            from: preparation,
            keepLatestResult: false,
            historyWrite: pending.replacingState(.committed)
        )
        #expect(advanced.hasSameAcceptance(as: preparation))

        let changedMetadata = try makePreparation(
            deliveryID: preparation.deliveryID,
            attemptID: preparation.attemptID,
            transcriptID: preparation.transcriptID,
            historyWrite: IOSAcceptedOutputHistoryWrite(
                policyGeneration: 8,
                transcriptionModel: "model",
                transcriptionLanguageCode: "en",
                durationMilliseconds: 42
            )
        )
        #expect(!advanced.hasSameAcceptance(as: changedMetadata))
    }

    @Test func recordRejectsImpossibleStateGenerationAndTombstoneCombinations() throws {
        let preparation = try makePreparation()

        for generation in [Int64.min, -1, 2, Int64.max] {
            #expect(throws: IOSAcceptedOutputDeliveryError.invalidRecord) {
                try makeRecord(
                    from: preparation,
                    publicationGeneration: generation
                )
            }
        }
        for state in [
            IOSAcceptedOutputDeliveryState.confirmedInserted,
            .submittedUnverified,
        ] {
            #expect(throws: IOSAcceptedOutputDeliveryError.invalidRecord) {
                try makeRecord(
                    from: preparation,
                    deliveryState: state,
                    publicationGeneration: 0
                )
            }
            _ = try makeRecord(
                from: preparation,
                deliveryState: state,
                publicationGeneration: 1
            )
        }
        #expect(throws: IOSAcceptedOutputDeliveryError.invalidRecord) {
            try makeRecord(
                from: preparation,
                acceptedText: nil,
                deliveryState: .discarded,
                automaticInsertionPreferenceEnabled: true
            )
        }
        let tombstone = try makeRecord(
            from: preparation,
            acceptedText: nil,
            deliveryState: .discarded,
            automaticInsertionPreferenceEnabled: false,
            historyWrite: nil
        )
        #expect(tombstone.deliveryState == .discarded)
    }

    @Test func recordRevisionTimestampAndTTLBoundsAreExact() throws {
        let preparation = try makePreparation()
        #expect(throws: IOSAcceptedOutputDeliveryError.invalidRecord) {
            try makeRecord(from: preparation, revision: 0)
        }
        _ = try makeRecord(from: preparation, revision: Int64.max)

        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(throws: IOSAcceptedOutputDeliveryError.invalidRecord) {
            try makeRecord(
                from: preparation,
                createdAt: createdAt,
                updatedAt: createdAt,
                expiresAt: createdAt.addingTimeInterval(86_399.999)
            )
        }
        #expect(throws: IOSAcceptedOutputDeliveryError.invalidRecord) {
            try makeRecord(
                from: preparation,
                createdAt: createdAt,
                updatedAt: createdAt.addingTimeInterval(-0.001),
                expiresAt: createdAt.addingTimeInterval(86_400)
            )
        }
    }

    @Test func publicValuesErrorsAndReflectionRedactCanaries() throws {
        let canary = "TOP-SECRET-TRANSCRIPT"
        let history = try IOSAcceptedOutputHistoryWrite(
            policyGeneration: 1,
            transcriptionModel: "SECRET-MODEL",
            transcriptionLanguageCode: "en",
            durationMilliseconds: 1
        )
        let preparation = try makePreparation(
            rawAcceptedText: canary,
            historyWrite: history
        )
        let record = try makeRecord(from: preparation, historyWrite: history)
        let values: [Any] = [
            history,
            preparation,
            record,
            IOSAcceptedOutputDeliveryExpectation(record: record),
            IOSAcceptedOutputDeliveryObservation.active(record),
            IOSAcceptedOutputDeliveryError.writeFailed,
        ]

        for value in values {
            let rendered = String(describing: value)
                + String(reflecting: value)
                + String(describing: Mirror(reflecting: value))
            #expect(!rendered.contains(canary))
            #expect(!rendered.contains("SECRET-MODEL"))
        }
    }
}

private func makePreparation(
    deliveryID: UUID = UUID(),
    sessionID: UUID = UUID(),
    attemptID: UUID = UUID(),
    transcriptID: UUID = UUID(),
    rawAcceptedText: String = "accepted text",
    automaticInsertionPreferenceEnabled: Bool = true,
    keepLatestResult: Bool = true,
    historyWrite: IOSAcceptedOutputHistoryWrite? = nil
) throws -> IOSAcceptedOutputDeliveryPreparation {
    try IOSAcceptedOutputDeliveryPreparation(
        deliveryID: deliveryID,
        sessionID: sessionID,
        attemptID: attemptID,
        transcriptID: transcriptID,
        rawAcceptedText: rawAcceptedText,
        outputIntent: .standard,
        automaticInsertionPreferenceEnabled:
            automaticInsertionPreferenceEnabled,
        keepLatestResult: keepLatestResult,
        historyWrite: historyWrite
    )
}

private func makeRecord(
    from preparation: IOSAcceptedOutputDeliveryPreparation,
    revision: Int64 = 1,
    createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
    updatedAt: Date? = nil,
    expiresAt: Date? = nil,
    acceptedText: String? = "accepted text",
    deliveryState: IOSAcceptedOutputDeliveryState = .pending,
    automaticInsertionPreferenceEnabled: Bool? = nil,
    keepLatestResult: Bool? = nil,
    publicationGeneration: Int64 = 0,
    historyWrite: IOSAcceptedOutputHistoryWrite?? = nil
) throws -> IOSAcceptedOutputDeliveryRecord {
    try IOSAcceptedOutputDeliveryRecord(
        revision: revision,
        deliveryID: preparation.deliveryID,
        sessionID: preparation.sessionID,
        attemptID: preparation.attemptID,
        transcriptID: preparation.transcriptID,
        acceptedText: acceptedText == "accepted text"
            ? preparation.acceptedText
            : acceptedText,
        outputIntent: preparation.outputIntent,
        createdAt: createdAt,
        updatedAt: updatedAt ?? createdAt,
        expiresAt: expiresAt ?? createdAt.addingTimeInterval(86_400),
        deliveryState: deliveryState,
        automaticInsertionPreferenceEnabled:
            automaticInsertionPreferenceEnabled
                ?? preparation.automaticInsertionPreferenceEnabled,
        keepLatestResult: keepLatestResult ?? preparation.keepLatestResult,
        publicationGeneration: publicationGeneration,
        historyWrite: historyWrite ?? preparation.historyWrite
    )
}
