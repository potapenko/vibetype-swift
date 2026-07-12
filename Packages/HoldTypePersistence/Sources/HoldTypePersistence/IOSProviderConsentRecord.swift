import Foundation

/// Provider-processing consent state exposed without storage authority details.
public enum IOSProviderConsentStatus: Equatable, Sendable {
    case notReviewed
    case reviewRequired
    case acceptedCurrentDisclosure
    case withdrawn
    case localDataUnavailable
    case mutationNotSaved
}

extension IOSProviderConsentStatus:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { "IOSProviderConsentStatus(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// One passive, content-free observation from the process-owned consent coordinator.
public struct IOSProviderConsentObservation: Equatable, Sendable {
    public let status: IOSProviderConsentStatus
    public let decisionAt: Date?
    public let canResetUnreadableData: Bool

    let ownerIdentity: IOSProviderConsentOwnerIdentity
    let source: IOSProviderConsentObservationSource

    init(
        status: IOSProviderConsentStatus,
        decisionAt: Date?,
        canResetUnreadableData: Bool,
        ownerIdentity: IOSProviderConsentOwnerIdentity,
        source: IOSProviderConsentObservationSource
    ) {
        self.status = status
        self.decisionAt = decisionAt
        self.canResetUnreadableData = canResetUnreadableData
        self.ownerIdentity = ownerIdentity
        self.source = source
    }
}

extension IOSProviderConsentObservation:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { "IOSProviderConsentObservation(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Opaque proof bound to one exact accepted epoch, revision, and disclosure.
public struct IOSProviderConsentAuthorization: Equatable, Sendable {
    let binding: IOSProviderConsentAuthorizationBinding
    let gateGeneration: UUID
}

extension IOSProviderConsentAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { "IOSProviderConsentAuthorization(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Remote stages that independently require the same live provider authority.
public enum IOSProviderConsentProviderStage: CaseIterable, Sendable {
    case transcription
    case correction
    case translation
}

extension IOSProviderConsentProviderStage:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { "IOSProviderConsentProviderStage(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

public enum IOSProviderConsentError: Error, Equatable, Sendable {
    case invalidDisclosureVersion
    case staleObservation
    case unreadableDataRequiresReset
    case resetRequiresUnreadableObservation
    case revisionOverflow
    case localDataUnavailable
    case mutationNotSaved
    case commitUncertain

    public var publicStatus: IOSProviderConsentStatus {
        switch self {
        case .localDataUnavailable, .commitUncertain:
            .localDataUnavailable
        case .invalidDisclosureVersion,
             .staleObservation,
             .unreadableDataRequiresReset,
             .resetRequiresUnreadableObservation,
             .revisionOverflow,
             .mutationNotSaved:
            .mutationNotSaved
        }
    }
}

extension IOSProviderConsentError:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { "IOSProviderConsentError(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSProviderConsentDecisionState: String, Equatable, Sendable {
    case accepted
    case withdrawn
}

struct IOSProviderConsentRecord: Equatable, Sendable {
    let epochID: UUID
    let revision: Int64
    let disclosureVersion: Int64
    let state: IOSProviderConsentDecisionState
    let decisionAt: Date
}

extension IOSProviderConsentRecord:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSProviderConsentRecord(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSProviderConsentOwnerIdentity: Equatable, Sendable {
    private let value = UUID()
}

extension IOSProviderConsentOwnerIdentity:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSProviderConsentOwnerIdentity(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSProviderConsentAuthorizationBinding: Equatable, Sendable {
    let ownerIdentity: IOSProviderConsentOwnerIdentity
    let epochID: UUID
    let revision: Int64
    let disclosureVersion: Int64
}

extension IOSProviderConsentAuthorizationBinding:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSProviderConsentAuthorizationBinding(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSProviderConsentObservationSource: Equatable, Sendable {
    case absent
    case snapshot(IOSProviderConsentJournalSnapshot)
    case unavailable
    case mutationNotSaved
}

extension IOSProviderConsentObservationSource:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSProviderConsentObservationSource(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
