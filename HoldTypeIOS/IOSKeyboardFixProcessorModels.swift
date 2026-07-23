import Foundation
import HoldTypeDomain

/// App-private input for one selected-text Fix. The action may contain a
/// custom prompt, so every diagnostic projection deliberately redacts it.
nonisolated struct IOSKeyboardFixExecutionInput: Sendable {
    let action: TextFixAction
    let sourceText: String
}

nonisolated extension IOSKeyboardFixExecutionInput:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        """
        IOSKeyboardFixExecutionInput(actionIdentifier: \(action.id), \
        sourceText: <redacted>, prompt: <redacted>)
        """
    }

    nonisolated var debugDescription: String { description }

    nonisolated var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "actionIdentifier": action.id,
                "sourceText": "<redacted>",
                "prompt": "<redacted>",
            ]
        )
    }
}

/// Failures that the injected typed/custom executor may return. Each case maps
/// to one closed bridge code; arbitrary provider errors remain providerFailed.
nonisolated enum IOSKeyboardFixExecutionFailure:
    Error,
    Equatable,
    Sendable {
    case actionUnavailable
    case consentRequired
    case credentialUnavailable
    case translationUnavailable
    case providerFailed
    case timedOut
    case cancelled
    case invalidOutput
    case persistenceFailed

    var bridgeCode: KeyboardFixFailureCode {
        switch self {
        case .actionUnavailable:
            .actionUnavailable
        case .consentRequired:
            .consentRequired
        case .credentialUnavailable:
            .credentialUnavailable
        case .translationUnavailable:
            .translationUnavailable
        case .providerFailed:
            .providerFailed
        case .timedOut:
            .timedOut
        case .cancelled:
            .cancelled
        case .invalidOutput:
            .invalidOutput
        case .persistenceFailed:
            .persistenceFailed
        }
    }
}

nonisolated enum IOSKeyboardFixSettingsReadiness: Equatable, Sendable {
    case ready
    case translationUnavailable
    case actionUnavailable
}

nonisolated struct IOSKeyboardFixBridgeClient: Sendable {
    typealias ConsumeRequest = @Sendable (Date) throws ->
        KeyboardFixRequestRecord?
    typealias ConsumeCancellation = @Sendable (Date) throws ->
        KeyboardFixCancellationRecord?
    typealias PublishResult = @Sendable (KeyboardFixResultRecord) throws -> Void
    typealias PublishCancellationAcknowledgement = @Sendable (
        KeyboardFixCancellationRecord
    ) throws -> Bool
    typealias RetireRequest = @Sendable (UUID) throws -> Void

    let consumeRequest: ConsumeRequest
    let consumeCancellation: ConsumeCancellation
    let publishResult: PublishResult
    let publishCancellationAcknowledgement:
        PublishCancellationAcknowledgement
    let retireRequest: RetireRequest

    init(
        consumeRequest: @escaping ConsumeRequest,
        consumeCancellation: @escaping ConsumeCancellation = { _ in nil },
        publishResult: @escaping PublishResult,
        publishCancellationAcknowledgement:
            @escaping PublishCancellationAcknowledgement = { _ in false },
        retireRequest: @escaping RetireRequest = { _ in }
    ) {
        self.consumeRequest = consumeRequest
        self.consumeCancellation = consumeCancellation
        self.publishResult = publishResult
        self.publishCancellationAcknowledgement =
            publishCancellationAcknowledgement
        self.retireRequest = retireRequest
    }

    init(store: KeyboardFixBridgeStore) {
        let box = IOSKeyboardFixBridgeStoreBox(store: store)
        self.init(
            consumeRequest: { date in
                try box.store.consumeRequest(at: date)
            },
            consumeCancellation: { date in
                try box.store.consumeCancellationRequest(at: date)
            },
            publishResult: { result in
                try box.store.publishResult(result)
            },
            publishCancellationAcknowledgement: { acknowledgement in
                try box.store.publishCancellationAcknowledgement(
                    acknowledgement
                )
            },
            retireRequest: { requestID in
                try box.store.cancelRequest(requestID: requestID)
            }
        )
    }
}

/// File access is serialized by IOSKeyboardFixProcessor. This box only lets
/// Sendable dependency closures retain the Foundation-backed value adapter.
private nonisolated final class IOSKeyboardFixBridgeStoreBox:
    @unchecked Sendable {
    let store: KeyboardFixBridgeStore

    init(store: KeyboardFixBridgeStore) {
        self.store = store
    }
}

nonisolated struct IOSKeyboardFixCatalogClient: Sendable {
    typealias Load = @Sendable () async throws -> TextFixCatalog

    let load: Load

    init(load: @escaping Load) {
        self.load = load
    }
}

/// Reads current app-private settings and projects only execution readiness.
/// Models, prompts, and other configuration stay inside the containing app.
nonisolated struct IOSKeyboardFixSettingsClient: Sendable {
    typealias Readiness = @Sendable (TextFixAction) async throws ->
        IOSKeyboardFixSettingsReadiness

    let readiness: Readiness

    init(readiness: @escaping Readiness) {
        self.readiness = readiness
    }
}

/// Version-specific consent gate. The implementation must return true only
/// for an accepted current disclosure (version 4 for this feature contract).
nonisolated struct IOSKeyboardFixConsentV4Client: Sendable {
    typealias IsAccepted = @Sendable () async throws -> Bool

    let isAccepted: IsAccepted

    init(isAccepted: @escaping IsAccepted) {
        self.isAccepted = isAccepted
    }
}

/// Credential presence gate. The credential itself never crosses this seam.
nonisolated struct IOSKeyboardFixCredentialClient: Sendable {
    typealias IsAvailable = @Sendable () async throws -> Bool

    let isAvailable: IsAvailable

    init(isAvailable: @escaping IsAvailable) {
        self.isAvailable = isAvailable
    }
}

/// One injected executor covers Translate, Fix, and custom prompts. Production
/// composition can adapt the existing Voice Draft executor here.
nonisolated struct IOSKeyboardFixExecutionClient: Sendable {
    typealias Execute = @Sendable (
        IOSKeyboardFixExecutionInput
    ) async throws -> String

    let execute: Execute

    init(execute: @escaping Execute) {
        self.execute = execute
    }
}

nonisolated struct IOSKeyboardFixBackgroundTaskToken:
    Equatable,
    Hashable,
    Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Lifecycle adapter for one bounded provider attempt. The expiration handler
/// must be invoked when iOS revokes background time; ending is idempotent.
nonisolated struct IOSKeyboardFixBackgroundTaskClient: Sendable {
    typealias Begin = @Sendable (
        @escaping @Sendable () -> Void
    ) async -> IOSKeyboardFixBackgroundTaskToken
    typealias End = @Sendable (IOSKeyboardFixBackgroundTaskToken) async -> Void

    let begin: Begin
    let end: End

    init(begin: @escaping Begin, end: @escaping End) {
        self.begin = begin
        self.end = end
    }

    static var foregroundOnly: IOSKeyboardFixBackgroundTaskClient {
        IOSKeyboardFixBackgroundTaskClient(
            begin: { _ in IOSKeyboardFixBackgroundTaskToken() },
            end: { _ in }
        )
    }
}

nonisolated struct IOSKeyboardFixProcessorClock: Sendable {
    let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date) {
        self.now = now
    }

    static var live: IOSKeyboardFixProcessorClock {
        IOSKeyboardFixProcessorClock(now: Date.init)
    }
}

nonisolated enum IOSKeyboardFixProcessorSignal: Equatable, Sendable {
    case processing(requestID: UUID, actionIdentifier: String)
    case terminal(
        requestID: UUID,
        actionIdentifier: String,
        outcome: IOSKeyboardFixTerminalOutcome
    )
    case expired(requestID: UUID, actionIdentifier: String)
    case bridgeUnavailable
    case rejectedWhileBusy
    case cancellationAcknowledged(requestID: UUID)
}

nonisolated extension IOSKeyboardFixProcessorSignal:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSKeyboardFixProcessorSignal(redacted)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

nonisolated struct IOSKeyboardFixSignalClient: Sendable {
    let emit: @Sendable (IOSKeyboardFixProcessorSignal) -> Void

    init(
        emit: @escaping @Sendable (IOSKeyboardFixProcessorSignal) -> Void
    ) {
        self.emit = emit
    }

    static var silent: IOSKeyboardFixSignalClient {
        IOSKeyboardFixSignalClient(emit: { _ in })
    }
}

nonisolated enum IOSKeyboardFixTerminalOutcome: Equatable, Sendable {
    case succeeded
    case failed(KeyboardFixFailureCode)
}

nonisolated enum IOSKeyboardFixProcessorOutcome: Equatable, Sendable {
    case noRequest
    case busy
    case completed(IOSKeyboardFixTerminalOutcome)
    case expired
    case bridgeUnavailable
}

nonisolated extension IOSKeyboardFixProcessorOutcome:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSKeyboardFixProcessorOutcome(redacted)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}
