import Foundation
import Testing

struct KeyboardDictationBridgeTests {
    @Test func twoCurrentRecordsRoundTripAndExpire() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KeyboardDictationBridgeStore(directoryURL: directory)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let sessionID = UUID()
        let attemptID = UUID()
        let requestID = UUID()
        let command = try #require(
            KeyboardDictationCommandRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: requestID,
                sourceDocumentID: nil,
                kind: .start,
                action: .translateAndImprove,
                issuedAt: now,
                expiresAt: now.addingTimeInterval(5)
            )
        )
        let state = try #require(
            KeyboardDictationStateRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: requestID,
                sourceDocumentID: nil,
                phase: .listening,
                translationAvailable: true,
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            )
        )

        try store.saveCommand(command)
        try store.saveState(state)

        #expect(try store.loadCommand(at: now) == command)
        #expect(try store.loadState(at: now) == state)
        #expect(command.action == .translateAndImprove)
        #expect(command.action.translates)
        #expect(command.action.corrects)
        #expect(command.action.selectedAutomaticModeCount == 2)
        #expect(state.sessionID == command.sessionID)
        #expect(state.attemptID == command.attemptID)
        #expect(state.requestID == command.requestID)
        #expect(state.translationAvailable)
        #expect(
            try store.loadCommand(at: now.addingTimeInterval(5)) == nil
        )
        #expect(
            try store.loadState(at: now.addingTimeInterval(60)) == nil
        )
        #expect(
            try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent).sorted() == [
                KeyboardDictationBridgeConfiguration.commandFilename,
                KeyboardDictationBridgeConfiguration.stateFilename,
            ].sorted()
        )
    }

    @Test func automaticModeTogglesCoverEveryCombination() {
        #expect(
            KeyboardVoiceAction.standard.togglingTranslation() == .translate
        )
        #expect(
            KeyboardVoiceAction.translate.togglingCorrection()
                == .translateAndImprove
        )
        #expect(
            KeyboardVoiceAction.translateAndImprove.togglingTranslation()
                == .improve
        )
        #expect(
            KeyboardVoiceAction.improve.togglingCorrection() == .standard
        )
    }

    @Test func resultIsBoundedAndOnlyAllowedForResultReady() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let sessionID = UUID()
        let attemptID = UUID()
        let requestID = UUID()

        #expect(
            KeyboardDictationStateRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: requestID,
                phase: .ready,
                result: "unexpected",
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            ) == nil
        )
        #expect(
            KeyboardDictationStateRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: requestID,
                phase: .resultReady,
                result: nil,
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            ) == nil
        )
        #expect(
            KeyboardDictationStateRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: requestID,
                phase: .resultReady,
                result: String(repeating: "x", count: 3_073),
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            ) == nil
        )
        #expect(
            KeyboardDictationStateRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: requestID,
                phase: .resultReady,
                result: "Processed keyboard text",
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            ) != nil
        )
    }

    @Test func attemptIdentityIsCompleteAndDocumentMatchingIsExact() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let sessionID = UUID()
        let attemptID = UUID()
        let requestID = UUID()
        let documentID = UUID()
        let state = KeyboardDictationStateRecord(
            sessionID: sessionID,
            attemptID: attemptID,
            requestID: requestID,
            sourceDocumentID: documentID,
            phase: .listening,
            publishedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )

        #expect(state?.hasActiveAttempt == true)
        #expect(state?.belongsToDocument(documentID) == true)
        #expect(state?.belongsToDocument(UUID()) == false)
        #expect(state?.belongsToDocument(nil) == false)
        #expect(
            KeyboardDictationStateRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: nil,
                phase: .listening,
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            ) == nil
        )
    }

    @Test func deliveryClaimIsBoundToTerminalAttemptRecords() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let sessionID = UUID()
        let attemptID = UUID()
        let requestID = UUID()
        let claimID = UUID()

        #expect(
            KeyboardDictationCommandRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: requestID,
                sourceDocumentID: UUID(),
                kind: .claimDelivery,
                issuedAt: now,
                expiresAt: now.addingTimeInterval(5)
            ) == nil
        )
        #expect(
            KeyboardDictationCommandRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: requestID,
                sourceDocumentID: UUID(),
                deliveryClaimID: claimID,
                kind: .start,
                issuedAt: now,
                expiresAt: now.addingTimeInterval(5)
            ) == nil
        )
        #expect(
            KeyboardDictationCommandRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: requestID,
                sourceDocumentID: UUID(),
                deliveryClaimID: claimID,
                kind: .claimDelivery,
                issuedAt: now,
                expiresAt: now.addingTimeInterval(5)
            ) != nil
        )
        #expect(
            KeyboardDictationStateRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: requestID,
                deliveryClaimID: claimID,
                phase: .processing,
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            ) == nil
        )
        #expect(
            KeyboardDictationStateRecord(
                sessionID: sessionID,
                attemptID: attemptID,
                requestID: requestID,
                deliveryClaimID: claimID,
                phase: .resultReady,
                result: "Claimed once",
                publishedAt: now,
                expiresAt: now.addingTimeInterval(60)
            ) != nil
        )
    }
}
