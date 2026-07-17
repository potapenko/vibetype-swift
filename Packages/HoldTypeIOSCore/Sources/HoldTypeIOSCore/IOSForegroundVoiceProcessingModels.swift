import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypePersistence

@_spi(HoldTypeIOSCore)
public enum IOSForegroundVoiceProcessingMode: Equatable, Sendable {
    case initial
    case retry
}

/// One exact provider chain's explicit user-cancellation signal. Generic task
/// cancellation deliberately does not set this bit: only an admitted
/// `Cancel Processing` action may revoke late-result authority. Dispatch
/// evidence still decides whether the retained audio is ordinarily retryable.
@_spi(HoldTypeIOSCore)
public final class IOSForegroundVoiceProcessingCancellationAuthority:
    @unchecked Sendable {
    private let lock = NSLock()
    private var explicitlyCancelled = false

    public init() {}

    public var isExplicitlyCancelled: Bool {
        lock.withLock { explicitlyCancelled }
    }

    public func cancelExplicitly() {
        lock.withLock { explicitlyCancelled = true }
    }
}

/// One frozen provider-processing input assembled by the process-owned voice
/// preflight. It is runtime-only and deliberately redacts its credential,
/// Library content, Pending owner, and consent observation.
@_spi(HoldTypeIOSCore)
public struct IOSForegroundVoiceProcessingRequest: Sendable {
    let sessionID: UUID
    let pendingRecording: IOSV1PendingRecording
    let mode: IOSForegroundVoiceProcessingMode
    let settings: IOSAppSettings
    let library: IOSLibraryContent
    let credential: IOSResolvedOpenAICredential?
    let consentObservation: IOSV1ProviderConsentObservation?
    let forcesTextCorrection: Bool
    let cancellationAuthority:
        IOSForegroundVoiceProcessingCancellationAuthority

    public init(
        sessionID: UUID,
        pendingRecording: IOSV1PendingRecording,
        mode: IOSForegroundVoiceProcessingMode,
        settings: IOSAppSettings,
        library: IOSLibraryContent,
        credential: IOSResolvedOpenAICredential?,
        consentObservation: IOSV1ProviderConsentObservation?,
        forcesTextCorrection: Bool = false,
        cancellationAuthority:
            IOSForegroundVoiceProcessingCancellationAuthority = .init()
    ) {
        self.sessionID = sessionID
        self.pendingRecording = pendingRecording
        self.mode = mode
        self.settings = settings
        self.library = library
        self.credential = credential
        self.consentObservation = consentObservation
        self.forcesTextCorrection = forcesTextCorrection
        self.cancellationAuthority = cancellationAuthority
    }
}

@_spi(HoldTypeIOSCore)
public enum IOSForegroundVoiceProcessingFailure: Equatable, Sendable {
    case invalidConfiguration
    case providerConsentUnavailable
    case credentialRejected
    case networkUnavailable
    case networkFailure
    case timedOut
    case providerUnavailable
    case invalidRecording
    case invalidResponse
    case cancelled
    case localPersistence
}

/// Ordered, payload-free foreground progress. The callback always runs on the
/// main actor so UI owners can consume it without introducing another hop.
@_spi(HoldTypeIOSCore)
public typealias IOSForegroundVoiceProcessingProgressHandler =
    @MainActor @Sendable (VoiceAttemptStage) -> Void

/// Redacted orchestration result. Provider text and credentials never cross
/// this boundary; accepted text appears only through Latest Result.
@_spi(HoldTypeIOSCore)
public enum IOSForegroundVoiceProcessingResolution: Equatable, Sendable {
    case notStarted(IOSForegroundVoiceProcessingFailure)
    case acceptance(IOSV1ForegroundVoiceAcceptanceResult)
    case retryAvailable(
        IOSV1PendingRecording,
        failure: IOSForegroundVoiceProcessingFailure,
        stage: VoiceAttemptStage
    )
    case busy
}

extension IOSForegroundVoiceProcessingMode:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSForegroundVoiceProcessingMode(redacted)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceProcessingRequest:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSForegroundVoiceProcessingRequest(redacted)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceProcessingFailure:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSForegroundVoiceProcessingFailure(redacted)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceProcessingResolution:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSForegroundVoiceProcessingResolution(redacted)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
