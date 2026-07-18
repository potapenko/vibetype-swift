import Foundation
import HoldTypeOpenAI

public enum IOSOpenAICredentialResolutionPurpose: Equatable, Sendable {
    case openAISettingsRefresh
    case voicePreflight
}

public enum IOSOpenAICredentialPrimaryStatus: Equatable, Sendable {
    case notConfigured
    case notCheckedInThisProcess
    case savedLastKnown
    case availableInThisProcess
    case unavailableWhileLocked
    case providerRejected
}

public enum IOSOpenAICredentialLocalMarkerIssue: Error, Equatable, Sendable {
    case unavailable
}

public struct IOSOpenAICredentialStatus: Equatable, Sendable {
    public let primary: IOSOpenAICredentialPrimaryStatus
    public let statusNeedsRefresh: Bool
    public let localMarkerIssue: IOSOpenAICredentialLocalMarkerIssue?

    public init(
        primary: IOSOpenAICredentialPrimaryStatus,
        statusNeedsRefresh: Bool,
        localMarkerIssue: IOSOpenAICredentialLocalMarkerIssue?
    ) {
        self.primary = primary
        self.statusNeedsRefresh = statusNeedsRefresh
        self.localMarkerIssue = localMarkerIssue
    }
}

/// Monotonic process-local ordering for payload-free credential presentation.
/// The revision carries no credential identity or generation.
public struct IOSOpenAICredentialStatusUpdate: Equatable, Sendable {
    public let revision: UInt64
    public let status: IOSOpenAICredentialStatus

    public init(
        revision: UInt64,
        status: IOSOpenAICredentialStatus
    ) {
        self.revision = revision
        self.status = status
    }
}

public enum IOSOpenAICredentialMutationOutcome: Equatable, Sendable {
    case applied
    case appliedStatusNeedsRefresh
}

public struct IOSOpenAICredentialGeneration: Equatable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct IOSResolvedOpenAICredential: Equatable, Sendable {
    public let credential: OpenAICredential
    public let generation: IOSOpenAICredentialGeneration

    init(
        credential: OpenAICredential,
        generation: IOSOpenAICredentialGeneration
    ) {
        self.credential = credential
        self.generation = generation
    }
}

public enum IOSOpenAICredentialResolution: Equatable, Sendable {
    case available(IOSResolvedOpenAICredential)
    case notConfigured
}

public struct IOSOpenAICredentialResolutionOutcome: Equatable, Sendable {
    public let resolution: IOSOpenAICredentialResolution
    public let statusUpdate: IOSOpenAICredentialStatusUpdate

    public var status: IOSOpenAICredentialStatus {
        statusUpdate.status
    }

    public init(
        resolution: IOSOpenAICredentialResolution,
        status: IOSOpenAICredentialStatus
    ) {
        self.resolution = resolution
        statusUpdate = IOSOpenAICredentialStatusUpdate(
            revision: 0,
            status: status
        )
    }

    public init(
        resolution: IOSOpenAICredentialResolution,
        statusUpdate: IOSOpenAICredentialStatusUpdate
    ) {
        self.resolution = resolution
        self.statusUpdate = statusUpdate
    }
}

public enum IOSOpenAICredentialAccessFailure: Equatable, Sendable {
    case unavailableWhileLocked
    case invalidStoredCredential
    case keychainFailure
}

public enum IOSOpenAICredentialCoordinatorError: Error, Equatable, Sendable {
    case emptyAPIKey
    case markerUnavailable
    case credentialAccessFailed(
        IOSOpenAICredentialAccessFailure,
        markerRestorationFailed: Bool
    )
    case providerRejected
    case operationCancelledBeforeStart
    case operationCancelledStatusNeedsRefresh
}

extension IOSOpenAICredentialLocalMarkerIssue:
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    public var errorDescription: String? { description }
    public var description: String { "OpenAI credential status could not be updated locally." }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Self.redactedMirror(for: self) }
}

extension IOSOpenAICredentialCoordinatorError:
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .emptyAPIKey:
            "Enter an OpenAI API key."
        case .markerUnavailable:
            "OpenAI credential status is unavailable. The saved key was not changed."
        case .credentialAccessFailed(let failure, let markerRestorationFailed):
            failure.message(statusNeedsRefresh: markerRestorationFailed)
        case .providerRejected:
            "OpenAI rejected the current API key. Replace it in HoldType Settings."
        case .operationCancelledBeforeStart:
            "The OpenAI credential operation was cancelled before it started."
        case .operationCancelledStatusNeedsRefresh:
            "The OpenAI credential operation was cancelled and status needs refresh."
        }
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { Self.redactedMirror(for: self) }
}

extension IOSOpenAICredentialStatus:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    public var description: String { "IOSOpenAICredentialStatus(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Self.redactedMirror(for: self) }
}

extension IOSOpenAICredentialStatusUpdate:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    public var description: String {
        "IOSOpenAICredentialStatusUpdate(<redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { Self.redactedMirror(for: self) }
}

extension IOSOpenAICredentialMutationOutcome:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    public var description: String { "IOSOpenAICredentialMutationOutcome(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Self.redactedMirror(for: self) }
}

extension IOSOpenAICredentialGeneration:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    public var description: String { "IOSOpenAICredentialGeneration(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Self.redactedMirror(for: self) }
}

extension IOSResolvedOpenAICredential:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    public var description: String { "IOSResolvedOpenAICredential(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Self.redactedMirror(for: self) }
}

extension IOSOpenAICredentialResolution:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    public var description: String { "IOSOpenAICredentialResolution(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Self.redactedMirror(for: self) }
}

extension IOSOpenAICredentialResolutionOutcome:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    public var description: String { "IOSOpenAICredentialResolutionOutcome(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Self.redactedMirror(for: self) }
}

private extension IOSOpenAICredentialAccessFailure {
    func message(statusNeedsRefresh: Bool) -> String {
        let base = switch self {
        case .unavailableWhileLocked:
            "The saved OpenAI API key is unavailable while this device is locked."
        case .invalidStoredCredential:
            "The saved OpenAI API key could not be read."
        case .keychainFailure:
            "The OpenAI API key could not be accessed in Keychain."
        }

        guard statusNeedsRefresh else {
            return base
        }
        return "\(base) Credential status also needs refresh."
    }
}

private extension CustomReflectable {
    static func redactedMirror(for value: Any) -> Mirror {
        Mirror(
            value,
            children: [(label: String?, value: Any)]()
        )
    }
}
