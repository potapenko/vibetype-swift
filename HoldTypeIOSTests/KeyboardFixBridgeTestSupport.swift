import Foundation

enum KeyboardFixBridgeTestSupportError: Error {
    case invalidFixture
}

struct KeyboardFixBridgeTestFixture {
    let directory: URL
    let store: KeyboardFixBridgeStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-keyboard-fix-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        store = KeyboardFixBridgeStore(directoryURL: directory)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename, isDirectory: false)
    }
}

func makeKeyboardFixMetadataActions(
    customCount: Int = 1
) throws -> [KeyboardFixMetadataAction] {
    guard let translate = KeyboardFixMetadataAction(
        identifier: KeyboardFixBridgeConfiguration.translateIdentifier,
        kind: .translate,
        title: "Translate",
        icon: .translate,
        order: 0,
        isEnabled: true
    ),
    let fix = KeyboardFixMetadataAction(
        identifier: KeyboardFixBridgeConfiguration.fixIdentifier,
        kind: .fix,
        title: "Fix",
        icon: .fix,
        order: 1,
        isEnabled: true
    ) else {
        throw KeyboardFixBridgeTestSupportError.invalidFixture
    }

    let custom = try (0..<customCount).map { index in
        guard let action = KeyboardFixMetadataAction(
            identifier: "user.action.\(index)",
            kind: .customPrompt,
            title: "Custom \(index)",
            icon: .custom,
            order: index + 2,
            isEnabled: index.isMultiple(of: 2)
        ) else {
            throw KeyboardFixBridgeTestSupportError.invalidFixture
        }
        return action
    }
    return [translate, fix] + custom
}

func makeKeyboardFixMetadataSnapshot(
    revision: UInt64 = 1,
    publishedAt: Date = Date(timeIntervalSince1970: 1_750_000_000),
    customCount: Int = 1
) throws -> KeyboardFixMetadataSnapshot {
    guard let snapshot = KeyboardFixMetadataSnapshot(
        revision: revision,
        publishedAt: publishedAt,
        actions: try makeKeyboardFixMetadataActions(customCount: customCount)
    ) else {
        throw KeyboardFixBridgeTestSupportError.invalidFixture
    }
    return snapshot
}

func makeKeyboardFixRequest(
    revision: UInt64 = 7,
    requestID: UUID = UUID(),
    actionIdentifier: String = "user.action.0",
    sourceText: String = "  Selected source\n",
    documentIdentifier: String = "document-identity",
    sourceFingerprint: String = "source-fingerprint",
    issuedAt: Date = Date(timeIntervalSince1970: 1_750_000_000),
    expiresAt: Date? = nil
) throws -> KeyboardFixRequestRecord {
    guard let request = KeyboardFixRequestRecord(
        revision: revision,
        requestID: requestID,
        actionIdentifier: actionIdentifier,
        sourceText: sourceText,
        documentIdentifier: documentIdentifier,
        sourceFingerprint: sourceFingerprint,
        issuedAt: issuedAt,
        expiresAt: expiresAt
            ?? issuedAt.addingTimeInterval(
                KeyboardFixBridgeConfiguration.recordLifetime
            )
    ) else {
        throw KeyboardFixBridgeTestSupportError.invalidFixture
    }
    return request
}

func makeKeyboardFixResult(
    request: KeyboardFixRequestRecord,
    phase: KeyboardFixResultPhase = .succeeded,
    outputText: String? = "  Exact output\n",
    failureCode: KeyboardFixFailureCode? = nil,
    publishedAt: Date? = nil
) throws -> KeyboardFixResultRecord {
    guard let result = KeyboardFixResultRecord(
        identity: request.identity,
        phase: phase,
        outputText: phase == .succeeded ? outputText : nil,
        failureCode: phase == .failed ? (failureCode ?? .providerFailed) : nil,
        requestIssuedAt: request.issuedAt,
        publishedAt: publishedAt ?? request.issuedAt.addingTimeInterval(1),
        expiresAt: request.expiresAt
    ) else {
        throw KeyboardFixBridgeTestSupportError.invalidFixture
    }
    return result
}
