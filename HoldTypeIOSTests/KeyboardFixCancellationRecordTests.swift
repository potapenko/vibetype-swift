import Foundation
import Testing
@testable import HoldTypeIOS

private typealias AppCancellationRecord =
    HoldTypeIOS.KeyboardFixCancellationRecord

struct KeyboardFixCancellationRecordTests {
    @Test func requestedAndAcknowledgedRecordsStrictlyRoundTrip() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let requested = try #require(
            AppCancellationRecord(
                requestID: UUID(),
                issuedAt: issuedAt,
                expiresAt: issuedAt.addingTimeInterval(60)
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let requestedData = try encoder.encode(requested)
        let requestedObject = try #require(
            JSONSerialization.jsonObject(with: requestedData)
                as? [String: Any]
        )
        #expect(
            Set(requestedObject.keys) == [
                "schemaVersion",
                "requestID",
                "issuedAt",
                "expiresAt",
                "phase",
                "acknowledgedAt",
            ]
        )
        #expect(requestedObject["acknowledgedAt"] is NSNull)
        #expect(
            try decoder.decode(
                AppCancellationRecord.self,
                from: requestedData
            ) == requested
        )

        let acknowledged = try #require(
            requested.acknowledging(
                at: issuedAt.addingTimeInterval(1)
            )
        )
        let acknowledgedData = try encoder.encode(acknowledged)
        #expect(
            try decoder.decode(
                AppCancellationRecord.self,
                from: acknowledgedData
            ) == acknowledged
        )
    }

    @Test func unexpectedFieldsAndInvalidPhasePayloadFailClosed() throws {
        let requestID = UUID().uuidString.lowercased()
        let requestedWithUnexpectedField = """
        {
          "schemaVersion": 1,
          "requestID": "\(requestID)",
          "issuedAt": 1750000000000,
          "expiresAt": 1750000060000,
          "phase": "requested",
          "acknowledgedAt": null,
          "source": "must-not-exist"
        }
        """
        let requestedWithAcknowledgement = """
        {
          "schemaVersion": 1,
          "requestID": "\(requestID)",
          "issuedAt": 1750000000000,
          "expiresAt": 1750000060000,
          "phase": "requested",
          "acknowledgedAt": 1750000001000
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        #expect(throws: (any Error).self) {
            try decoder.decode(
                AppCancellationRecord.self,
                from: Data(requestedWithUnexpectedField.utf8)
            )
        }
        #expect(throws: (any Error).self) {
            try decoder.decode(
                AppCancellationRecord.self,
                from: Data(requestedWithAcknowledgement.utf8)
            )
        }
    }
}
