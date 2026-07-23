import Foundation

nonisolated enum KeyboardFixBridgeConfiguration {
    static let metadataFilename = "keyboard-fix-metadata-v1.json"
    static let requestFilename = "keyboard-fix-request-v1.json"
    static let requestClaimFilename = "keyboard-fix-request-claim-v1.json"
    static let resultFilename = "keyboard-fix-result-v1.json"
    static let resultClaimFilename = "keyboard-fix-result-claim-v1.json"

    static let maximumMetadataBytes = 64 * 1_024
    static let maximumRequestBytes = 40 * 1_024
    static let maximumResultBytes = 72 * 1_024
    static let maximumActionCount = 100
    static let maximumIdentifierUTF8Bytes = 128
    static let maximumTitleCharacterCount = 80
    static let maximumIconUTF8Bytes = 128
    static let maximumSourceUTF8Bytes = 32 * 1_024
    static let maximumFingerprintUTF8Bytes = 128
    static let maximumOutputUTF8Bytes = 64 * 1_024
    static let maximumErrorCodeUTF8Bytes = 256
    static let recordLifetime: TimeInterval = 60

    static let translateIdentifier = "builtin.translate"
    static let fixIdentifier = "builtin.fix"
}

nonisolated enum KeyboardFixActionKind: String, Codable, CaseIterable, Sendable {
    case translate
    case fix
    case customPrompt
}

nonisolated enum KeyboardFixIconToken: String, Codable, CaseIterable, Sendable {
    case translate
    case fix
    case improveWriting = "improve-writing"
    case makeShorter = "make-shorter"
    case summarize
    case bulletPoints = "bullet-points"
    case casual
    case markdown
    case formal
    case expand
    case rewrite
    case custom
}

nonisolated enum KeyboardFixSourceKind: String, Codable, Sendable {
    case selection
}

nonisolated struct KeyboardFixRequestIdentity: Equatable, Sendable {
    let revision: UInt64
    let requestID: UUID
    let actionIdentifier: String
    let sourceKind: KeyboardFixSourceKind
    let documentIdentifier: String
    let sourceFingerprint: String
}

nonisolated enum KeyboardFixBridgeValidation {
    static func isValidIdentifier(_ value: String) -> Bool {
        containsVisibleContent(value)
            && value.utf8.count
                <= KeyboardFixBridgeConfiguration.maximumIdentifierUTF8Bytes
    }

    static func isValidTitle(_ value: String) -> Bool {
        containsVisibleContent(value)
            && value.count
                <= KeyboardFixBridgeConfiguration.maximumTitleCharacterCount
    }

    static func isValidDocumentIdentifier(_ value: String) -> Bool {
        isValidIdentifier(value)
    }

    static func isValidFingerprint(_ value: String) -> Bool {
        containsVisibleContent(value)
            && value.utf8.count
                <= KeyboardFixBridgeConfiguration.maximumFingerprintUTF8Bytes
    }

    static func containsVisibleContent(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    static func hasValidLifetime(
        issuedAt: Date,
        publishedAt: Date? = nil,
        expiresAt: Date
    ) -> Bool {
        guard issuedAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt > issuedAt,
              expiresAt.timeIntervalSince(issuedAt)
                <= KeyboardFixBridgeConfiguration.recordLifetime
        else {
            return false
        }
        guard let publishedAt else {
            return true
        }
        return publishedAt.timeIntervalSinceReferenceDate.isFinite
            && publishedAt >= issuedAt
            && publishedAt < expiresAt
    }
}

nonisolated enum KeyboardFixBridgeStrictDecoding {
    static func requireExactKeys(
        _ expectedKeys: Set<String>,
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: KeyboardFixBridgeDynamicCodingKey.self
        )
        let actualKeys = Set(container.allKeys.map(\.stringValue))
        guard actualKeys == expectedKeys else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Keyboard Fix record has an invalid closed schema."
                )
            )
        }
    }

    static func invalidRecord(from decoder: Decoder) -> DecodingError {
        DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "Keyboard Fix record failed validation."
            )
        )
    }
}

private struct KeyboardFixBridgeDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
