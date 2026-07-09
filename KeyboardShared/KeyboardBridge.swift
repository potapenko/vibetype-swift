//
//  KeyboardBridge.swift
//  HoldType
//
//  Created by Codex on 7/9/26.
//

import Foundation

enum KeyboardBridgeConfiguration {
    static let appGroupIdentifier = "group.app.holdtype.HoldType.shared"
    static let snapshotFilename = "keyboard-bridge-v1.json"
}

enum KeyboardBridgePhase: String, Codable, Equatable, Sendable {
    case idle
    case listening
    case transcribing
    case transcriptReady
    case failed
}

struct KeyboardBridgeTranscript: Codable, Equatable, Identifiable, Sendable {
    enum ValidationError: Error, Equatable {
        case emptyText
    }

    let id: UUID
    let text: String
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case createdAt
    }

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) throws {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw ValidationError.emptyText
        }

        self.id = id
        self.text = normalizedText
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let text = try container.decode(String.self, forKey: .text)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)

        do {
            try self.init(id: id, text: text, createdAt: createdAt)
        } catch ValidationError.emptyText {
            throw DecodingError.dataCorruptedError(
                forKey: .text,
                in: container,
                debugDescription: "Accepted transcript text must not be empty."
            )
        }
    }
}

struct KeyboardBridgeSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let revision: UInt64
    let sessionID: UUID?
    let phase: KeyboardBridgePhase
    let sourceDocumentIdentifier: UUID?
    let updatedAt: Date
    let expiresAt: Date
    let acceptedTranscript: KeyboardBridgeTranscript?

    init(
        schemaVersion: Int = currentSchemaVersion,
        revision: UInt64,
        sessionID: UUID? = nil,
        phase: KeyboardBridgePhase,
        sourceDocumentIdentifier: UUID? = nil,
        updatedAt: Date = Date(),
        expiresAt: Date,
        acceptedTranscript: KeyboardBridgeTranscript? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.sessionID = sessionID
        self.phase = phase
        self.sourceDocumentIdentifier = sourceDocumentIdentifier
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.acceptedTranscript = acceptedTranscript
    }

    func transcriptForInsertion(at date: Date = Date()) -> KeyboardBridgeTranscript? {
        guard schemaVersion == Self.currentSchemaVersion,
              expiresAt > date,
              phase == .transcriptReady else {
            return nil
        }

        return acceptedTranscript
    }
}

enum KeyboardBridgeStoreError: Error, LocalizedError, Equatable {
    case appGroupContainerUnavailable(String)
    case nonIncreasingRevision(current: UInt64, proposed: UInt64)
    case revisionExhausted

    var errorDescription: String? {
        switch self {
        case .appGroupContainerUnavailable:
            return "The HoldType App Group container is unavailable."
        case .nonIncreasingRevision:
            return "The keyboard bridge revision must increase."
        case .revisionExhausted:
            return "The keyboard bridge revision cannot increase further."
        }
    }
}

struct KeyboardBridgeStore {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let writingOptions: Data.WritingOptions

    init(
        directoryURL: URL,
        fileManager: FileManager = .default,
        writingOptions: Data.WritingOptions = [
            .atomic,
            .completeFileProtectionUntilFirstUserAuthentication,
        ]
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.writingOptions = writingOptions
    }

    static func appGroup(
        identifier: String = KeyboardBridgeConfiguration.appGroupIdentifier,
        fileManager: FileManager = .default
    ) throws -> KeyboardBridgeStore {
        guard let directoryURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            throw KeyboardBridgeStoreError.appGroupContainerUnavailable(identifier)
        }

        return KeyboardBridgeStore(directoryURL: directoryURL, fileManager: fileManager)
    }

    func load(at date: Date = Date()) throws -> KeyboardBridgeSnapshot? {
        guard let snapshot = try storedSnapshot() else {
            return nil
        }

        guard snapshot.schemaVersion == KeyboardBridgeSnapshot.currentSchemaVersion,
              snapshot.expiresAt > date else {
            return nil
        }

        return snapshot
    }

    func nextRevision() throws -> UInt64 {
        guard let currentRevision = try storedSnapshot()?.revision else {
            return 1
        }

        guard currentRevision < UInt64.max else {
            throw KeyboardBridgeStoreError.revisionExhausted
        }

        return currentRevision + 1
    }

    func save(_ snapshot: KeyboardBridgeSnapshot) throws {
        if let currentRevision = try storedSnapshot()?.revision,
           snapshot.revision <= currentRevision {
            throw KeyboardBridgeStoreError.nonIncreasingRevision(
                current: currentRevision,
                proposed: snapshot.revision
            )
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(snapshot)
        try data.write(to: snapshotURL, options: writingOptions)
    }

    private func storedSnapshot() throws -> KeyboardBridgeSnapshot? {
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: snapshotURL)
        return try decoder.decode(KeyboardBridgeSnapshot.self, from: data)
    }

    private var snapshotURL: URL {
        directoryURL.appendingPathComponent(
            KeyboardBridgeConfiguration.snapshotFilename,
            isDirectory: false
        )
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
