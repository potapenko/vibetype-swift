import Foundation

public enum IOSVoiceDraftSegmentError: Error, Equatable, Sendable {
    case invalidText
}

public enum IOSVoiceDraftRecordError: Error, Equatable, Sendable {
    case invalidText
    case tooManyAcceptedResults
}

public enum IOSVoiceDraftInsertionMode: String, Equatable, Sendable {
    case replace
    case append
}

public struct IOSVoiceDraftSegment: Equatable, Identifiable, Sendable {
    public let resultID: UUID
    public let text: String

    public var id: UUID { resultID }

    public init(resultID: UUID, text: String) throws {
        guard IOSAcceptedTextHistoryValidation.isStoredText(text) else {
            throw IOSVoiceDraftSegmentError.invalidText
        }
        self.resultID = resultID
        self.text = text
    }
}

public struct IOSVoiceDraftRecord: Equatable, Sendable {
    public static let maximumSegmentCount = 100
    public static let empty = Self(text: "", segments: [])

    public let text: String
    public let segments: [IOSVoiceDraftSegment]

    public var isEmpty: Bool { text.isEmpty && segments.isEmpty }
    /// Whether the Draft contains text that is useful to present or restore.
    public var hasMeaningfulText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public var isFull: Bool { segments.count >= Self.maximumSegmentCount }

    @_spi(HoldTypeIOSCore)
    public init(segments: [IOSVoiceDraftSegment]) {
        text = segments.map(\.text).joined(separator: "\n\n")
        self.segments = segments
    }

    @_spi(HoldTypeIOSCore)
    public init(
        text: String,
        segments: [IOSVoiceDraftSegment]
    ) {
        self.text = text
        self.segments = segments
    }

    @_spi(HoldTypeIOSCore)
    public func replacingText(_ updatedText: String) throws -> Self {
        guard Self.isValidEditableText(updatedText) else {
            throw IOSVoiceDraftRecordError.invalidText
        }
        guard segments.count <= Self.maximumSegmentCount else {
            throw IOSVoiceDraftRecordError.tooManyAcceptedResults
        }
        if updatedText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            return .empty
        }
        return Self(text: updatedText, segments: segments)
    }

    static func isValidEditableText(_ value: String) -> Bool {
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

public struct IOSVoiceDraftSnapshotToken: Equatable, Sendable {
    private let text: String
    private let segments: [IOSVoiceDraftSegment]

    public init(record: IOSVoiceDraftRecord) {
        text = record.text
        segments = record.segments
    }
}

public enum IOSVoiceDraftAppendResult: Equatable, Sendable {
    case inserted(IOSVoiceDraftRecord)
    case duplicate(IOSVoiceDraftRecord)
    case full(IOSVoiceDraftRecord)
}

public enum IOSVoiceDraftMutationResult: Equatable, Sendable {
    case confirmed(IOSVoiceDraftRecord)
    case stale(IOSVoiceDraftRecord)
}

extension IOSVoiceDraftSegment: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSVoiceDraftSegment(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSVoiceDraftRecord: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSVoiceDraftRecord(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSVoiceDraftSnapshotToken: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSVoiceDraftSnapshotToken(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
