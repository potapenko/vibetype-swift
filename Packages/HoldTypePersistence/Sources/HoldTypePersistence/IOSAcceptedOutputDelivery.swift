import Foundation
import HoldTypeDomain

public enum IOSAcceptedOutputDeliveryState: Equatable, Sendable {
    case pending
    case confirmedInserted
    case submittedUnverified
    case discarded
}

public enum IOSAcceptedOutputHistoryWriteState: Equatable, Sendable {
    case pending
    case pendingReplacement
    case committed
    case cancelled
}

extension IOSAcceptedOutputHistoryWriteState {
    var isPendingDecision: Bool {
        self == .pending || self == .pendingReplacement
    }

    var mayReplayAbsentHistoryRow: Bool {
        self == .pendingReplacement
    }
}

public struct IOSAcceptedOutputHistoryWrite: Sendable {
    public let state: IOSAcceptedOutputHistoryWriteState
    public let policyGeneration: Int64
    public let transcriptionModel: String
    public let transcriptionLanguageCode: String?
    public let durationMilliseconds: Int64?

    init(
        state: IOSAcceptedOutputHistoryWriteState = .pending,
        policyGeneration: Int64,
        transcriptionModel: String,
        transcriptionLanguageCode: String?,
        durationMilliseconds: Int64?
    ) throws {
        guard let normalizedModel = IOSAcceptedOutputDeliveryValidation
            .normalizedMetadataText(transcriptionModel),
              policyGeneration > 0,
              normalizedModel.utf8.count
                <= IOSAcceptedOutputDeliveryValidation.maximumModelByteCount,
              IOSAcceptedOutputDeliveryValidation.isValidLanguageCode(
                  transcriptionLanguageCode
              ),
              IOSAcceptedOutputDeliveryValidation.isValidDuration(
                  durationMilliseconds
              ) else {
            throw IOSAcceptedOutputDeliveryError.invalidPreparation
        }

        self.state = state
        self.policyGeneration = policyGeneration
        self.transcriptionModel = normalizedModel
        self.transcriptionLanguageCode = transcriptionLanguageCode
        self.durationMilliseconds = durationMilliseconds
    }

    func replacingState(
        _ state: IOSAcceptedOutputHistoryWriteState
    ) throws -> Self {
        try Self(
            state: state,
            policyGeneration: policyGeneration,
            transcriptionModel: transcriptionModel,
            transcriptionLanguageCode: transcriptionLanguageCode,
            durationMilliseconds: durationMilliseconds
        )
    }

    func hasSameMetadata(as other: Self) -> Bool {
        policyGeneration == other.policyGeneration
            && IOSAcceptedOutputDeliveryValidation.bytesEqual(
                transcriptionModel,
                other.transcriptionModel
            )
            && transcriptionLanguageCode == other.transcriptionLanguageCode
            && durationMilliseconds == other.durationMilliseconds
    }
}

extension IOSAcceptedOutputHistoryWrite: Equatable {
    public static func == (
        lhs: IOSAcceptedOutputHistoryWrite,
        rhs: IOSAcceptedOutputHistoryWrite
    ) -> Bool {
        lhs.state == rhs.state && lhs.hasSameMetadata(as: rhs)
    }
}

public struct IOSAcceptedOutputDeliveryPreparation: Sendable {
    public let deliveryID: UUID
    public let sessionID: UUID
    public let attemptID: UUID
    public let transcriptID: UUID
    public let acceptedText: String
    public let outputIntent: DictationOutputIntent
    public let automaticInsertionPreferenceEnabled: Bool
    public let keepLatestResult: Bool
    public let historyWrite: IOSAcceptedOutputHistoryWrite?
    let historyCapture: IOSAcceptedOutputHistoryCapture?

    init(
        deliveryID: UUID,
        sessionID: UUID,
        attemptID: UUID,
        transcriptID: UUID,
        rawAcceptedText: String,
        outputIntent: DictationOutputIntent,
        automaticInsertionPreferenceEnabled: Bool,
        keepLatestResult: Bool,
        historyWrite: IOSAcceptedOutputHistoryWrite?
    ) throws {
        guard let acceptedText = IOSAcceptedOutputDeliveryValidation
            .normalizedAcceptedText(rawAcceptedText),
              historyWrite?.state == .pending || historyWrite == nil else {
            throw IOSAcceptedOutputDeliveryError.invalidPreparation
        }

        self.deliveryID = deliveryID
        self.sessionID = sessionID
        self.attemptID = attemptID
        self.transcriptID = transcriptID
        self.acceptedText = acceptedText
        self.outputIntent = outputIntent
        self.automaticInsertionPreferenceEnabled =
            automaticInsertionPreferenceEnabled
        self.keepLatestResult = keepLatestResult
        self.historyWrite = historyWrite
        historyCapture = nil
    }

    public init(
        deliveryID: UUID,
        sessionID: UUID,
        attemptID: UUID,
        transcriptID: UUID,
        rawAcceptedText: String,
        outputIntent: DictationOutputIntent,
        automaticInsertionPreferenceEnabled: Bool,
        keepLatestResult: Bool,
        historyCapture: IOSAcceptedOutputHistoryCapture
    ) throws {
        guard let acceptedText = IOSAcceptedOutputDeliveryValidation
            .normalizedAcceptedText(rawAcceptedText),
              historyCapture.historyWrite?.state == .pending
                || historyCapture.historyWrite == nil else {
            throw IOSAcceptedOutputDeliveryError.invalidPreparation
        }

        self.deliveryID = deliveryID
        self.sessionID = sessionID
        self.attemptID = attemptID
        self.transcriptID = transcriptID
        self.acceptedText = acceptedText
        self.outputIntent = outputIntent
        self.automaticInsertionPreferenceEnabled =
            automaticInsertionPreferenceEnabled
        self.keepLatestResult = keepLatestResult
        historyWrite = historyCapture.historyWrite
        self.historyCapture = historyCapture
    }
}

extension IOSAcceptedOutputDeliveryPreparation: Equatable {
    public static func == (
        lhs: IOSAcceptedOutputDeliveryPreparation,
        rhs: IOSAcceptedOutputDeliveryPreparation
    ) -> Bool {
        lhs.deliveryID == rhs.deliveryID
            && lhs.sessionID == rhs.sessionID
            && lhs.attemptID == rhs.attemptID
            && lhs.transcriptID == rhs.transcriptID
            && IOSAcceptedOutputDeliveryValidation.bytesEqual(
                lhs.acceptedText,
                rhs.acceptedText
            )
            && lhs.outputIntent == rhs.outputIntent
            && lhs.automaticInsertionPreferenceEnabled
                == rhs.automaticInsertionPreferenceEnabled
            && lhs.keepLatestResult == rhs.keepLatestResult
            && lhs.historyWrite == rhs.historyWrite
            && lhs.historyCapture == rhs.historyCapture
    }
}

public struct IOSAcceptedOutputDeliveryRecord: Sendable {
    public let revision: Int64
    public let deliveryID: UUID
    public let sessionID: UUID
    public let attemptID: UUID
    public let transcriptID: UUID
    public let acceptedText: String?
    public let outputIntent: DictationOutputIntent
    public let createdAt: Date
    public let updatedAt: Date
    public let expiresAt: Date
    public let deliveryState: IOSAcceptedOutputDeliveryState
    public let automaticInsertionPreferenceEnabled: Bool
    public let keepLatestResult: Bool
    public let publicationGeneration: Int64
    public let historyWrite: IOSAcceptedOutputHistoryWrite?

    init(
        revision: Int64,
        deliveryID: UUID,
        sessionID: UUID,
        attemptID: UUID,
        transcriptID: UUID,
        acceptedText: String?,
        outputIntent: DictationOutputIntent,
        createdAt: Date,
        updatedAt: Date,
        expiresAt: Date,
        deliveryState: IOSAcceptedOutputDeliveryState,
        automaticInsertionPreferenceEnabled: Bool,
        keepLatestResult: Bool,
        publicationGeneration: Int64,
        historyWrite: IOSAcceptedOutputHistoryWrite?
    ) throws {
        let createdMilliseconds = try IOSAcceptedOutputDeliveryTimestampCodec
            .milliseconds(from: createdAt)
        let updatedMilliseconds = try IOSAcceptedOutputDeliveryTimestampCodec
            .milliseconds(from: updatedAt)
        let expiresMilliseconds = try IOSAcceptedOutputDeliveryTimestampCodec
            .milliseconds(from: expiresAt)
        let expectedExpiry = createdMilliseconds.addingReportingOverflow(
            IOSAcceptedOutputDeliveryValidation.lifetimeMilliseconds
        )

        guard revision >= 1,
              publicationGeneration == 0 || publicationGeneration == 1,
              !expectedExpiry.overflow,
              expectedExpiry.partialValue == expiresMilliseconds,
              createdMilliseconds <= updatedMilliseconds,
              updatedMilliseconds <= expiresMilliseconds else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }

        switch deliveryState {
        case .discarded:
            guard acceptedText == nil,
                  !automaticInsertionPreferenceEnabled,
                  historyWrite == nil else {
                throw IOSAcceptedOutputDeliveryError.invalidRecord
            }
        case .pending:
            guard let acceptedText,
                  IOSAcceptedOutputDeliveryValidation.isStoredAcceptedText(
                      acceptedText
                  ) else {
                throw IOSAcceptedOutputDeliveryError.invalidRecord
            }
        case .confirmedInserted, .submittedUnverified:
            guard publicationGeneration == 1,
                  let acceptedText,
                  IOSAcceptedOutputDeliveryValidation.isStoredAcceptedText(
                      acceptedText
                  ) else {
                throw IOSAcceptedOutputDeliveryError.invalidRecord
            }
        }

        self.revision = revision
        self.deliveryID = deliveryID
        self.sessionID = sessionID
        self.attemptID = attemptID
        self.transcriptID = transcriptID
        self.acceptedText = acceptedText
        self.outputIntent = outputIntent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.deliveryState = deliveryState
        self.automaticInsertionPreferenceEnabled =
            automaticInsertionPreferenceEnabled
        self.keepLatestResult = keepLatestResult
        self.publicationGeneration = publicationGeneration
        self.historyWrite = historyWrite
    }

    func hasSameAcceptance(
        as preparation: IOSAcceptedOutputDeliveryPreparation
    ) -> Bool {
        guard deliveryState != .discarded,
              deliveryID == preparation.deliveryID,
              sessionID == preparation.sessionID,
              attemptID == preparation.attemptID,
              transcriptID == preparation.transcriptID,
              acceptedText.map({
                  IOSAcceptedOutputDeliveryValidation.bytesEqual(
                      $0,
                      preparation.acceptedText
                  )
              }) == true,
              outputIntent == preparation.outputIntent,
              automaticInsertionPreferenceEnabled
                == preparation.automaticInsertionPreferenceEnabled else {
            return false
        }
        switch (historyWrite, preparation.historyWrite) {
        case (.none, .none):
            return true
        case (.some(let current), .some(let prepared)):
            return current.hasSameMetadata(as: prepared)
        case (.none, .some), (.some, .none):
            return false
        }
    }

    func collides(with preparation: IOSAcceptedOutputDeliveryPreparation) -> Bool {
        deliveryID == preparation.deliveryID
            || (attemptID == preparation.attemptID
                && transcriptID == preparation.transcriptID)
    }
}

extension IOSAcceptedOutputDeliveryRecord: Equatable {
    public static func == (
        lhs: IOSAcceptedOutputDeliveryRecord,
        rhs: IOSAcceptedOutputDeliveryRecord
    ) -> Bool {
        lhs.revision == rhs.revision
            && lhs.deliveryID == rhs.deliveryID
            && lhs.sessionID == rhs.sessionID
            && lhs.attemptID == rhs.attemptID
            && lhs.transcriptID == rhs.transcriptID
            && IOSAcceptedOutputDeliveryValidation.optionalBytesEqual(
                lhs.acceptedText,
                rhs.acceptedText
            )
            && lhs.outputIntent == rhs.outputIntent
            && lhs.createdAt == rhs.createdAt
            && lhs.updatedAt == rhs.updatedAt
            && lhs.expiresAt == rhs.expiresAt
            && lhs.deliveryState == rhs.deliveryState
            && lhs.automaticInsertionPreferenceEnabled
                == rhs.automaticInsertionPreferenceEnabled
            && lhs.keepLatestResult == rhs.keepLatestResult
            && lhs.publicationGeneration == rhs.publicationGeneration
            && lhs.historyWrite == rhs.historyWrite
    }
}

public struct IOSAcceptedOutputDeliveryExpectation: Equatable, Sendable {
    public let deliveryID: UUID
    public let sessionID: UUID
    public let attemptID: UUID
    public let transcriptID: UUID
    public let revision: Int64

    public init(record: IOSAcceptedOutputDeliveryRecord) {
        deliveryID = record.deliveryID
        sessionID = record.sessionID
        attemptID = record.attemptID
        transcriptID = record.transcriptID
        revision = record.revision
    }

    func matches(_ record: IOSAcceptedOutputDeliveryRecord) -> Bool {
        self == IOSAcceptedOutputDeliveryExpectation(record: record)
    }

    func matchesIdentity(_ record: IOSAcceptedOutputDeliveryRecord) -> Bool {
        deliveryID == record.deliveryID
            && sessionID == record.sessionID
            && attemptID == record.attemptID
            && transcriptID == record.transcriptID
    }
}

public enum IOSAcceptedOutputDeliveryObservation: Equatable, Sendable {
    case active(IOSAcceptedOutputDeliveryRecord)
    case expired(IOSAcceptedOutputDeliveryExpectation)
    case clockRollbackAmbiguous(IOSAcceptedOutputDeliveryExpectation)
}

public struct IOSAcceptedOutputDeliveryAuthorization: Sendable {
    public let record: IOSAcceptedOutputDeliveryRecord
    let snapshot: IOSAcceptedOutputDeliveryJournalSnapshot
    let storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity

    init(
        snapshot: IOSAcceptedOutputDeliveryJournalSnapshot,
        storeIdentity: IOSAcceptedOutputDeliveryStoreIdentity,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    ) {
        record = snapshot.record
        self.snapshot = snapshot
        self.storeIdentity = storeIdentity
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
    }
}

extension IOSAcceptedOutputDeliveryAuthorization: Equatable {
    public static func == (
        lhs: IOSAcceptedOutputDeliveryAuthorization,
        rhs: IOSAcceptedOutputDeliveryAuthorization
    ) -> Bool {
        lhs.snapshot == rhs.snapshot
            && lhs.storeIdentity == rhs.storeIdentity
            && lhs.capabilityOwnerIdentity == rhs.capabilityOwnerIdentity
    }
}

struct IOSAcceptedOutputHistoryOwnershipProof: Equatable, Sendable {
    private enum Evidence: Equatable, Sendable {
        case retainedRow(IOSAcceptedHistoryRowReceipt)
        case outbox(IOSAcceptedHistoryOutboxReceipt)
    }

    private let evidence: Evidence

    var capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity {
        switch evidence {
        case .retainedRow(let receipt): receipt.capabilityOwnerIdentity
        case .outbox(let receipt): receipt.capabilityOwnerIdentity
        }
    }

    var outboxStoreIdentity: IOSAcceptedHistoryOutboxStoreIdentity? {
        guard case .outbox(let receipt) = evidence else { return nil }
        return receipt.storeIdentity
    }

    init(retainedRowReceipt: IOSAcceptedHistoryRowReceipt) {
        evidence = .retainedRow(retainedRowReceipt)
    }

    init(outboxReceipt: IOSAcceptedHistoryOutboxReceipt) {
        evidence = .outbox(outboxReceipt)
    }

    func provesOwnership(
        for delivery: IOSAcceptedOutputDeliveryAuthorization
    ) -> Bool {
        switch evidence {
        case .retainedRow(let receipt):
            receipt.provesMembership(for: delivery)
        case .outbox(let receipt):
            receipt.provesMembershipForDeliveryRemoval(for: delivery)
        }
    }

    func provesOwnership(
        for delivery: IOSAcceptedOutputDeliveryAuthorization,
        under reservation:
            IOSAcceptedOutputPendingHistoryTransferReservation
    ) -> Bool {
        switch evidence {
        case .retainedRow(let receipt):
            return receipt.provesMembership(for: delivery)
                && reservation.permitsOwnershipProof(
                    from: nil
                )
        case .outbox(let receipt):
            return receipt.provesMembershipForDeliveryRemoval(for: delivery)
                && reservation.permitsOwnershipProof(
                    from: receipt.storeIdentity
                )
        }
    }
}

public enum IOSAcceptedOutputDeliveryRemovalResult: Equatable, Sendable {
    case removed
    case alreadyAbsent
}

public enum IOSAcceptedOutputDeliveryError: Error, Equatable, Sendable {
    case invalidPreparation
    case invalidRecord
    case sourceTooLarge
    case malformedData
    case unsupportedSchemaVersion
    case readFailed
    case writeFailed
    case dataProtectionUnavailable
    case slotOccupied
    case compareAndSwapFailed
    case identityCollision
    case invalidTransition
    case revisionOverflow
    case commitUncertain
    case removeFailed
    case removalCommitUncertain
    case expired
    case clockRollbackAmbiguous
    case historyTransferRequired
    case bridgeRevocationRequired
}

extension IOSAcceptedOutputDeliveryError: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSAcceptedOutputDeliveryError(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        IOSAcceptedOutputDeliveryRedaction.mirror(of: self)
    }
}

extension IOSAcceptedOutputHistoryWrite: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSAcceptedOutputHistoryWrite(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        IOSAcceptedOutputDeliveryRedaction.mirror(of: self)
    }
}

extension IOSAcceptedOutputDeliveryPreparation: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "IOSAcceptedOutputDeliveryPreparation(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        IOSAcceptedOutputDeliveryRedaction.mirror(of: self)
    }
}

extension IOSAcceptedOutputDeliveryRecord: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSAcceptedOutputDeliveryRecord(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        IOSAcceptedOutputDeliveryRedaction.mirror(of: self)
    }
}

extension IOSAcceptedOutputDeliveryExpectation: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "IOSAcceptedOutputDeliveryExpectation(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        IOSAcceptedOutputDeliveryRedaction.mirror(of: self)
    }
}

extension IOSAcceptedOutputDeliveryObservation: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "IOSAcceptedOutputDeliveryObservation(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        IOSAcceptedOutputDeliveryRedaction.mirror(of: self)
    }
}

extension IOSAcceptedOutputDeliveryAuthorization: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "IOSAcceptedOutputDeliveryAuthorization(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        IOSAcceptedOutputDeliveryRedaction.mirror(of: self)
    }
}

extension IOSAcceptedOutputHistoryOwnershipProof: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedOutputHistoryOwnershipProof(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSAcceptedOutputDeliveryValidation {
    static let maximumAcceptedTextByteCount = 131_072
    static let maximumModelByteCount = 256
    static let lifetimeMilliseconds: Int64 = 86_400_000

    static func normalizedAcceptedText(_ rawValue: String) -> String? {
        guard hasAllowedControls(rawValue),
              let trimmed = frozenTrim(rawValue),
              !trimmed.isEmpty,
              trimmed.utf8.count <= maximumAcceptedTextByteCount,
              let accepted = try? AcceptedTranscript(rawText: trimmed),
              bytesEqual(accepted.text, trimmed) else {
            return nil
        }
        return accepted.text
    }

    static func normalizedMetadataText(_ rawValue: String) -> String? {
        guard hasAllowedControls(rawValue) else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func isStoredAcceptedText(_ value: String) -> Bool {
        guard let normalized = normalizedAcceptedText(value) else {
            return false
        }
        return bytesEqual(normalized, value)
    }

    static func hasAllowedControls(_ value: String) -> Bool {
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

    static func isValidLanguageCode(_ value: String?) -> Bool {
        guard let value else { return true }
        guard value.utf8.count == 2 || value.utf8.count == 3 else {
            return false
        }
        return value.utf8.allSatisfy { (97...122).contains($0) }
    }

    static func isValidDuration(_ value: Int64?) -> Bool {
        guard let value else { return true }
        return value > 0 && value < 300_000
    }

    static func bytesEqual(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }

    static func optionalBytesEqual(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case (.some(let lhs), .some(let rhs)): bytesEqual(lhs, rhs)
        case (.none, .some), (.some, .none): false
        }
    }

    private static func frozenTrim(_ value: String) -> String? {
        let scalars = value.unicodeScalars
        var lower = scalars.startIndex
        var upper = scalars.endIndex
        while lower < upper, isFrozenEdgeScalar(scalars[lower]) {
            lower = scalars.index(after: lower)
        }
        while lower < upper {
            let candidate = scalars.index(before: upper)
            guard isFrozenEdgeScalar(scalars[candidate]) else { break }
            upper = candidate
        }
        var trimmed = String.UnicodeScalarView()
        trimmed.append(contentsOf: scalars[lower..<upper])
        return String(trimmed)
    }

    private static func isFrozenEdgeScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0009, 0x000A, 0x000D, 0x0020, 0x00A0, 0x1680,
             0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            true
        default:
            false
        }
    }
}

enum IOSAcceptedOutputDeliveryTimestampCodec {
    private static let millisecondsPerSecond = 1_000.0

    static func canonicalDate(from date: Date) throws -> Date {
        let milliseconds = try milliseconds(from: date, requireCanonical: false)
        let canonical = Date(
            timeIntervalSince1970:
                Double(milliseconds) / millisecondsPerSecond
        )
        guard canonical.timeIntervalSinceReferenceDate.isFinite,
              try string(fromCanonical: canonical).utf8.count == 24 else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        return canonical
    }

    static func milliseconds(from date: Date) throws -> Int64 {
        try milliseconds(from: date, requireCanonical: true)
    }

    static func string(from date: Date) throws -> String {
        let canonical = try canonicalDate(from: date)
        guard canonical == date else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        return try string(fromCanonical: canonical)
    }

    static func date(from value: String) throws -> Date {
        guard value.utf8.count == 24,
              value.unicodeScalars.allSatisfy(\.isASCII),
              value.hasSuffix("Z") else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        let formatter = makeFormatter()
        guard let date = formatter.date(from: value),
              try string(fromCanonical: date) == value,
              try canonicalDate(from: date) == date else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        return date
    }

    private static func milliseconds(
        from date: Date,
        requireCanonical: Bool
    ) throws -> Int64 {
        let seconds = date.timeIntervalSince1970
        let scaled = seconds * millisecondsPerSecond
        guard seconds.isFinite,
              scaled.isFinite,
              scaled >= Double(Int64.min),
              scaled <= Double(Int64.max) else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        let rounded = Int64(scaled.rounded(.toNearestOrAwayFromZero))
        if requireCanonical {
            let canonical = Date(
                timeIntervalSince1970:
                    Double(rounded) / millisecondsPerSecond
            )
            guard canonical == date else {
                throw IOSAcceptedOutputDeliveryError.invalidRecord
            }
        }
        return rounded
    }

    private static func string(fromCanonical date: Date) throws -> String {
        let value = makeFormatter().string(from: date)
        guard value.utf8.count == 24 else {
            throw IOSAcceptedOutputDeliveryError.invalidRecord
        }
        return value
    }

    private static func makeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

private enum IOSAcceptedOutputDeliveryRedaction {
    static func mirror(of value: Any) -> Mirror {
        Mirror(value, children: ["state": "redacted"])
    }
}
