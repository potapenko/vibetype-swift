import Foundation

/// One extension-written selected-text request. It contains no prompt,
/// credential, model, surrounding text, or durable app state.
nonisolated struct KeyboardFixRequestRecord:
    Codable,
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    static let schemaVersion = 1

    let schemaVersion: Int
    let revision: UInt64
    let requestID: UUID
    let actionIdentifier: String
    let sourceText: String
    let sourceKind: KeyboardFixSourceKind
    let documentIdentifier: String
    let sourceFingerprint: String
    let issuedAt: Date
    let expiresAt: Date

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case revision
        case requestID
        case actionIdentifier
        case sourceText
        case sourceKind
        case documentIdentifier
        case sourceFingerprint
        case issuedAt
        case expiresAt
    }

    init?(
        revision: UInt64,
        requestID: UUID,
        actionIdentifier: String,
        sourceText: String,
        sourceKind: KeyboardFixSourceKind = .selection,
        documentIdentifier: String,
        sourceFingerprint: String,
        issuedAt: Date,
        expiresAt: Date
    ) {
        guard revision > 0,
              KeyboardFixBridgeValidation.isValidIdentifier(actionIdentifier),
              KeyboardFixBridgeValidation.containsVisibleContent(sourceText),
              sourceText.utf8.count
                <= KeyboardFixBridgeConfiguration.maximumSourceUTF8Bytes,
              KeyboardFixBridgeValidation.isValidDocumentIdentifier(
                documentIdentifier
              ),
              KeyboardFixBridgeValidation.isValidFingerprint(sourceFingerprint),
              KeyboardFixBridgeValidation.hasValidLifetime(
                issuedAt: issuedAt,
                expiresAt: expiresAt
              )
        else {
            return nil
        }
        schemaVersion = Self.schemaVersion
        self.revision = revision
        self.requestID = requestID
        self.actionIdentifier = actionIdentifier
        self.sourceText = sourceText
        self.sourceKind = sourceKind
        self.documentIdentifier = documentIdentifier
        self.sourceFingerprint = sourceFingerprint
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    var identity: KeyboardFixRequestIdentity {
        KeyboardFixRequestIdentity(
            revision: revision,
            requestID: requestID,
            actionIdentifier: actionIdentifier,
            sourceKind: sourceKind,
            documentIdentifier: documentIdentifier,
            sourceFingerprint: sourceFingerprint
        )
    }

    func isValid(at date: Date) -> Bool {
        schemaVersion == Self.schemaVersion
            && issuedAt <= date
            && expiresAt > date
            && KeyboardFixBridgeValidation.hasValidLifetime(
                issuedAt: issuedAt,
                expiresAt: expiresAt
            )
    }

    var description: String {
        """
        KeyboardFixRequestRecord(requestID: \(requestID), revision: \(revision), \
        sourceText: <redacted>, documentIdentifier: <redacted>, \
        sourceFingerprint: <redacted>)
        """
    }

    var debugDescription: String {
        description
    }

    var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "schemaVersion": schemaVersion,
                "revision": revision,
                "requestID": requestID,
                "actionIdentifier": actionIdentifier,
                "sourceText": "<redacted>",
                "sourceKind": sourceKind.rawValue,
                "documentIdentifier": "<redacted>",
                "sourceFingerprint": "<redacted>",
                "issuedAt": issuedAt,
                "expiresAt": expiresAt,
            ]
        )
    }

    init(from decoder: Decoder) throws {
        try KeyboardFixBridgeStrictDecoding.requireExactKeys(
            Set(CodingKeys.allCases.map(\.stringValue)),
            from: decoder
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.schemaVersion,
              let record = Self(
                revision: try container.decode(UInt64.self, forKey: .revision),
                requestID: try container.decode(UUID.self, forKey: .requestID),
                actionIdentifier: try container.decode(
                    String.self,
                    forKey: .actionIdentifier
                ),
                sourceText: try container.decode(String.self, forKey: .sourceText),
                sourceKind: try container.decode(
                    KeyboardFixSourceKind.self,
                    forKey: .sourceKind
                ),
                documentIdentifier: try container.decode(
                    String.self,
                    forKey: .documentIdentifier
                ),
                sourceFingerprint: try container.decode(
                    String.self,
                    forKey: .sourceFingerprint
                ),
                issuedAt: try container.decode(Date.self, forKey: .issuedAt),
                expiresAt: try container.decode(Date.self, forKey: .expiresAt)
              )
        else {
            throw KeyboardFixBridgeStrictDecoding.invalidRecord(from: decoder)
        }
        self = record
    }
}
