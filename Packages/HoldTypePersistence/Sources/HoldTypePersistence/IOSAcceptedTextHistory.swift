import Foundation
import HoldTypeDomain

public enum IOSAcceptedTextHistoryEntryError: Error, Equatable, Sendable {
    case invalidText
    case invalidCreationDate
}

public struct IOSAcceptedTextHistoryEntry: Equatable, Identifiable, Sendable {
    public let resultID: UUID
    public let text: String
    public let createdAt: Date

    public var id: UUID { resultID }

    public init(
        resultID: UUID,
        text: String,
        createdAt: Date
    ) throws {
        guard IOSAcceptedTextHistoryValidation.isStoredText(text) else {
            throw IOSAcceptedTextHistoryEntryError.invalidText
        }

        let canonicalDate: Date
        do {
            canonicalDate = try IOSAcceptedTextHistoryTimestampCodec
                .canonicalDate(from: createdAt)
        } catch {
            throw IOSAcceptedTextHistoryEntryError.invalidCreationDate
        }

        self.resultID = resultID
        self.text = text
        self.createdAt = canonicalDate
    }

    public static func == (
        lhs: IOSAcceptedTextHistoryEntry,
        rhs: IOSAcceptedTextHistoryEntry
    ) -> Bool {
        lhs.resultID == rhs.resultID
            && IOSAcceptedTextHistoryValidation.bytesEqual(lhs.text, rhs.text)
            && lhs.createdAt == rhs.createdAt
    }
}

enum IOSAcceptedTextHistoryValidation {
    static let maximumTextByteCount = 131_072

    static func isStoredText(_ value: String) -> Bool {
        guard hasAllowedControls(value),
              value.utf8.count <= maximumTextByteCount,
              let accepted = try? AcceptedTranscript(rawText: value) else {
            return false
        }
        return bytesEqual(accepted.text, value)
    }

    static func bytesEqual(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }

    private static func hasAllowedControls(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x00...0x1F:
                scalar.value == 0x09
                    || scalar.value == 0x0A
                    || scalar.value == 0x0D
            case 0x7F...0x9F:
                false
            default:
                true
            }
        }
    }
}

enum IOSAcceptedTextHistoryTimestampCodec {
    static func canonicalDate(from date: Date) throws -> Date {
        let milliseconds = try self.milliseconds(
            from: date,
            requireCanonical: false
        )
        return Date(
            timeIntervalSince1970: Double(milliseconds) / 1_000
        )
    }

    static func milliseconds(from date: Date) throws -> Int64 {
        try milliseconds(from: date, requireCanonical: true)
    }

    private static func milliseconds(
        from date: Date,
        requireCanonical: Bool
    ) throws -> Int64 {
        let scaled = date.timeIntervalSince1970 * 1_000
        guard scaled.isFinite,
              scaled >= Double(Int64.min),
              scaled <= Double(Int64.max) else {
            throw IOSAcceptedTextHistoryEntryError.invalidCreationDate
        }
        let value = Int64(scaled.rounded(.toNearestOrAwayFromZero))
        if requireCanonical {
            let canonical = Date(
                timeIntervalSince1970: Double(value) / 1_000
            )
            guard canonical == date else {
                throw IOSAcceptedTextHistoryEntryError.invalidCreationDate
            }
        }
        return value
    }
}

public struct IOSAcceptedTextHistoryRecord: Equatable, Sendable {
    public static let maximumEntryCount = 20
    public static let enabledEmpty = Self(isEnabled: true, entries: [])

    public let isEnabled: Bool
    public let entries: [IOSAcceptedTextHistoryEntry]

    init(isEnabled: Bool, entries: [IOSAcceptedTextHistoryEntry]) {
        self.isEnabled = isEnabled
        self.entries = entries
    }
}

public struct IOSAcceptedTextHistorySnapshotToken: Equatable, Sendable {
    private let isEnabled: Bool
    private let resultIDs: [UUID]

    public init(record: IOSAcceptedTextHistoryRecord) {
        isEnabled = record.isEnabled
        resultIDs = record.entries.map(\.resultID)
    }
}

public enum IOSAcceptedTextHistoryAppendResult: Equatable, Sendable {
    case inserted
    case duplicate
    case disabled
    case outsideRetentionWindow
}

public enum IOSAcceptedTextHistoryMutationResult: Equatable, Sendable {
    case confirmed(IOSAcceptedTextHistoryRecord)
    case stale(IOSAcceptedTextHistoryRecord)
}

extension IOSAcceptedTextHistoryEntry: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSAcceptedTextHistoryEntry(redacted)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSAcceptedTextHistoryRecord: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSAcceptedTextHistoryRecord(redacted)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
