import Foundation
import UIKit

typealias KeyboardLatestExpiryScheduler = (
    Date,
    @escaping @MainActor () -> Void
) -> Timer?

typealias KeyboardListeningCountdownScheduler = (
    @escaping @MainActor () -> Void
) -> Timer?

typealias KeyboardDocumentIdentifierRetryScheduler = (
    @escaping @MainActor () -> Void
) -> Timer?

typealias KeyboardDeliveryObservationScheduler = (
    @escaping @MainActor () -> Void
) -> Timer?

typealias KeyboardContainingAppOpener = (
    URL,
    @escaping (Bool) -> Void
) -> Void

@MainActor
struct KeyboardViewControllerDependencies {
    let loadSnapshot: () throws -> KeyboardBridgeSnapshot?
    let loadDictationState: () throws -> KeyboardDictationStateRecord?
    let loadConsumedHandoffIntent: () throws -> KeyboardHandoffIntentRecord?
    let saveDictationCommand: (KeyboardDictationCommandRecord) throws -> Void
    let saveHandoffIntent: (KeyboardHandoffIntentRecord) throws -> Void
    let observeDictationState: (
        @escaping @MainActor () -> Void
    ) -> KeyboardDictationBridgeObserver?
    let now: () -> Date
    let makeRequestID: () -> UUID
    let makeAttemptID: () -> UUID
    let makeDeliveryClaimID: () -> UUID
    let documentProxyOverride: (any UITextDocumentProxy)?
    let documentProxyProviderOverride: (() -> any UITextDocumentProxy)?
    let loadDocumentIdentifier: (any UITextDocumentProxy) -> UUID?
    let inputModeSwitchKeyOverride: Bool?
    let fullAccessOverride: Bool?
    let scheduleLatestExpiry: KeyboardLatestExpiryScheduler
    let scheduleListeningCountdown: KeyboardListeningCountdownScheduler
    let scheduleDocumentIdentifierRetry:
        KeyboardDocumentIdentifierRetryScheduler
    let scheduleDeliveryObservation: KeyboardDeliveryObservationScheduler
    let openContainingAppOverride: KeyboardContainingAppOpener?
    let recordDiagnostic: (IOSRuntimeDiagnosticEvent) -> Void

    static let live = KeyboardViewControllerDependencies(
        loadSnapshot: {
            let store = try KeyboardBridgeStore.appGroup()
            return try store.load()
        },
        loadDictationState: {
            let store = try KeyboardDictationBridgeStore.appGroup()
            return try store.loadState()
        },
        loadConsumedHandoffIntent: {
            let store = try KeyboardHandoffIntentStore.appGroup()
            return try store.loadConsumed()
        },
        saveDictationCommand: { command in
            let store = try KeyboardDictationBridgeStore.appGroup()
            try store.saveCommand(command)
            KeyboardDictationBridgeSignal.postCommandChanged()
        },
        saveHandoffIntent: { intent in
            let store = try KeyboardHandoffIntentStore.appGroup()
            try store.save(intent)
        },
        observeDictationState: { action in
            KeyboardDictationBridgeObserver(
                name: KeyboardDictationBridgeConfiguration.stateNotification,
                action: action
            )
        },
        now: { Date() },
        makeRequestID: { UUID() },
        makeAttemptID: { UUID() },
        makeDeliveryClaimID: { UUID() },
        documentProxyOverride: nil,
        documentProxyProviderOverride: nil,
        loadDocumentIdentifier: { documentProxy in
            KeyboardDocumentIdentifierAdapter.load(from: documentProxy)
        },
        inputModeSwitchKeyOverride: nil,
        fullAccessOverride: nil,
        scheduleLatestExpiry: { fireDate, action in
            let timer = Timer(
                fire: fireDate,
                interval: 0,
                repeats: false
            ) { _ in
                Task { @MainActor in
                    action()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            return timer
        },
        scheduleListeningCountdown: { action in
            let timer = Timer(
                timeInterval: 1,
                repeats: true
            ) { _ in
                Task { @MainActor in
                    action()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            return timer
        },
        scheduleDocumentIdentifierRetry: { action in
            let timer = Timer(
                timeInterval: 0.1,
                repeats: false
            ) { _ in
                Task { @MainActor in
                    action()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            return timer
        },
        scheduleDeliveryObservation: { action in
            let timer = Timer(
                timeInterval: 0.5,
                repeats: false
            ) { _ in
                Task { @MainActor in
                    action()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            return timer
        },
        openContainingAppOverride: nil,
        recordDiagnostic: { event in
            IOSRuntimeDiagnosticsStore.keyboard.record(event)
        }
    )
}
