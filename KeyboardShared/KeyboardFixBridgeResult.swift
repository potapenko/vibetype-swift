import Foundation

nonisolated enum KeyboardFixResultPhase: String, Codable, Sendable {
    case processing
    case succeeded
    case failed
}

nonisolated enum KeyboardFixFailureCode: String, Codable, CaseIterable, Sendable {
    case actionUnavailable = "action_unavailable"
    case consentRequired = "consent_required"
    case credentialUnavailable = "credential_unavailable"
    case translationUnavailable = "translation_unavailable"
    case providerFailed = "provider_failed"
    case timedOut = "timed_out"
    case cancelled
    case invalidOutput = "invalid_output"
    case requestInvalid = "request_invalid"
    case sourceTooLarge = "source_too_large"
    case persistenceFailed = "persistence_failed"
}

/// One app-written state/result for an exact keyboard Fix target.
nonisolated struct KeyboardFixResultRecord:
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
    let sourceKind: KeyboardFixSourceKind
    let documentIdentifier: String
    let sourceFingerprint: String
    let phase: KeyboardFixResultPhase
    let outputText: String?
    let failureCode: KeyboardFixFailureCode?
    let requestIssuedAt: Date
    let publishedAt: Date
    let expiresAt: Date

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case revision
        case requestID
        case actionIdentifier
        case sourceKind
        case documentIdentifier
        case sourceFingerprint
        case phase
        case outputText
        case failureCode
        case requestIssuedAt
        case publishedAt
        case expiresAt
    }

    init?(
        identity: KeyboardFixRequestIdentity,
        phase: KeyboardFixResultPhase,
        outputText: String? = nil,
        failureCode: KeyboardFixFailureCode? = nil,
        requestIssuedAt: Date,
        publishedAt: Date,
        expiresAt: Date
    ) {
        guard identity.revision > 0,
              KeyboardFixBridgeValidation.isValidIdentifier(
                identity.actionIdentifier
              ),
              KeyboardFixBridgeValidation.isValidDocumentIdentifier(
                identity.documentIdentifier
              ),
              KeyboardFixBridgeValidation.isValidFingerprint(
                identity.sourceFingerprint
              ),
              Self.hasValidPayload(
                phase: phase,
                outputText: outputText,
                failureCode: failureCode
              ),
              KeyboardFixBridgeValidation.hasValidLifetime(
                issuedAt: requestIssuedAt,
                publishedAt: publishedAt,
                expiresAt: expiresAt
              )
        else {
            return nil
        }
        schemaVersion = Self.schemaVersion
        revision = identity.revision
        requestID = identity.requestID
        actionIdentifier = identity.actionIdentifier
        sourceKind = identity.sourceKind
        documentIdentifier = identity.documentIdentifier
        sourceFingerprint = identity.sourceFingerprint
        self.phase = phase
        self.outputText = outputText
        self.failureCode = failureCode
        self.requestIssuedAt = requestIssuedAt
        self.publishedAt = publishedAt
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

    var isTerminal: Bool {
        phase != .processing
    }

    func matches(_ expectedIdentity: KeyboardFixRequestIdentity) -> Bool {
        identity == expectedIdentity
    }

    func isValid(at date: Date) -> Bool {
        schemaVersion == Self.schemaVersion
            && publishedAt <= date
            && expiresAt > date
            && KeyboardFixBridgeValidation.hasValidLifetime(
                issuedAt: requestIssuedAt,
                publishedAt: publishedAt,
                expiresAt: expiresAt
            )
    }

    var description: String {
        """
        KeyboardFixResultRecord(requestID: \(requestID), revision: \(revision), \
        phase: \(phase.rawValue), outputText: <redacted>, \
        documentIdentifier: <redacted>, sourceFingerprint: <redacted>)
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
                "sourceKind": sourceKind.rawValue,
                "documentIdentifier": "<redacted>",
                "sourceFingerprint": "<redacted>",
                "phase": phase.rawValue,
                "outputText": "<redacted>",
                "failureCode": failureCode?.rawValue as Any,
                "requestIssuedAt": requestIssuedAt,
                "publishedAt": publishedAt,
                "expiresAt": expiresAt,
            ]
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(revision, forKey: .revision)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(actionIdentifier, forKey: .actionIdentifier)
        try container.encode(sourceKind, forKey: .sourceKind)
        try container.encode(documentIdentifier, forKey: .documentIdentifier)
        try container.encode(sourceFingerprint, forKey: .sourceFingerprint)
        try container.encode(phase, forKey: .phase)
        if let outputText {
            try container.encode(outputText, forKey: .outputText)
        } else {
            try container.encodeNil(forKey: .outputText)
        }
        if let failureCode {
            try container.encode(failureCode, forKey: .failureCode)
        } else {
            try container.encodeNil(forKey: .failureCode)
        }
        try container.encode(requestIssuedAt, forKey: .requestIssuedAt)
        try container.encode(publishedAt, forKey: .publishedAt)
        try container.encode(expiresAt, forKey: .expiresAt)
    }

    init(from decoder: Decoder) throws {
        try KeyboardFixBridgeStrictDecoding.requireExactKeys(
            Set(CodingKeys.allCases.map(\.stringValue)),
            from: decoder
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let identity = KeyboardFixRequestIdentity(
            revision: try container.decode(UInt64.self, forKey: .revision),
            requestID: try container.decode(UUID.self, forKey: .requestID),
            actionIdentifier: try container.decode(
                String.self,
                forKey: .actionIdentifier
            ),
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
            )
        )
        guard schemaVersion == Self.schemaVersion,
              let record = Self(
                identity: identity,
                phase: try container.decode(
                    KeyboardFixResultPhase.self,
                    forKey: .phase
                ),
                outputText: try container.decodeIfPresent(
                    String.self,
                    forKey: .outputText
                ),
                failureCode: try container.decodeIfPresent(
                    KeyboardFixFailureCode.self,
                    forKey: .failureCode
                ),
                requestIssuedAt: try container.decode(
                    Date.self,
                    forKey: .requestIssuedAt
                ),
                publishedAt: try container.decode(Date.self, forKey: .publishedAt),
                expiresAt: try container.decode(Date.self, forKey: .expiresAt)
              )
        else {
            throw KeyboardFixBridgeStrictDecoding.invalidRecord(from: decoder)
        }
        self = record
    }

    private static func hasValidPayload(
        phase: KeyboardFixResultPhase,
        outputText: String?,
        failureCode: KeyboardFixFailureCode?
    ) -> Bool {
        let hasValidOutput = outputText.map {
            KeyboardFixBridgeValidation.containsVisibleContent($0)
                && $0.utf8.count
                    <= KeyboardFixBridgeConfiguration.maximumOutputUTF8Bytes
        } ?? false
        let hasValidFailure = failureCode.map {
            $0.rawValue.utf8.count
                <= KeyboardFixBridgeConfiguration.maximumErrorCodeUTF8Bytes
        } ?? false

        return switch phase {
        case .processing:
            outputText == nil && failureCode == nil
        case .succeeded:
            hasValidOutput && failureCode == nil
        case .failed:
            outputText == nil && hasValidFailure
        }
    }
}
