import AVFAudio
import Foundation

nonisolated struct IOSAudioSessionAttemptToken: Equatable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated struct IOSAudioSessionObservationGeneration:
    Equatable,
    Hashable,
    Sendable
{
    fileprivate let rawValue: UInt64
}

nonisolated enum IOSAudioSessionCategory: Equatable, Sendable {
    case playAndRecord
}

nonisolated enum IOSAudioSessionMode: Equatable, Sendable {
    case `default`
}

nonisolated struct IOSAudioSessionCategoryOptions:
    OptionSet,
    Equatable,
    Sendable
{
    let rawValue: UInt8

    static let allowBluetoothHFP = Self(rawValue: 1 << 0)
    static let defaultToSpeaker = Self(rawValue: 1 << 1)
}

nonisolated struct IOSAudioSessionConfiguration: Equatable, Sendable {
    let category: IOSAudioSessionCategory
    let mode: IOSAudioSessionMode
    let options: IOSAudioSessionCategoryOptions

    static let foregroundRecording = Self(
        category: .playAndRecord,
        mode: .default,
        options: [.allowBluetoothHFP, .defaultToSpeaker]
    )
}

nonisolated enum IOSAudioSessionActivationRequest: Equatable, Sendable {
    case activate
    case deactivateAndNotifyOthers
}

nonisolated struct IOSAudioSessionInputPort: Equatable, Sendable {
    let uid: String
    let portType: String
    let selectedDataSourceID: Int?
}

nonisolated struct IOSAudioSessionCurrentState: Equatable, Sendable {
    let inputPorts: [IOSAudioSessionInputPort]
    let isInputAvailable: Bool
    let isInputMuted: Bool
    let sampleRate: Double
    let inputNumberOfChannels: Int
}

nonisolated struct IOSAudioSessionFrozenInput: Equatable, Sendable {
    let uid: String
    let portType: String
    let selectedDataSourceID: Int?
    let sampleRate: Double
    let inputNumberOfChannels: Int
}

nonisolated enum IOSAudioRouteChangeReason: Equatable, Sendable {
    case unknown
    case newDeviceAvailable
    case oldDeviceUnavailable
    case categoryChange
    case override
    case wakeFromSleep
    case noSuitableRouteForCategory
    case routeConfigurationChange
}

nonisolated enum IOSAudioSessionSystemEvent: Equatable, Sendable {
    case interruptionBegan
    case interruptionEnded
    case routeChanged(IOSAudioRouteChangeReason)
    case inputMuteChanged
    case mediaServicesLost
    case mediaServicesReset
}

nonisolated enum IOSAudioSessionEvent: Equatable, Sendable {
    case interruptionBegan
    case interruptionEnded
    case routeChanged(
        reason: IOSAudioRouteChangeReason,
        currentState: IOSAudioSessionCurrentState
    )
    case inputMuteChanged(currentState: IOSAudioSessionCurrentState)
    case mediaServicesLost
    case mediaServicesReset
}

nonisolated struct IOSAudioSessionEventEnvelope: Equatable, Sendable {
    let attemptToken: IOSAudioSessionAttemptToken
    let generation: IOSAudioSessionObservationGeneration
    let event: IOSAudioSessionEvent
}

nonisolated enum IOSAudioSessionAdapterError: Error, Equatable, Sendable {
    case attemptAlreadyActive
    case staleAttempt
    case categoryConfigurationFailed
    case hapticsConfigurationFailed
    case activationFailed
    case deactivationFailed
    case inputUnavailable
    case ambiguousInput
    case invalidInputIdentity
    case invalidInputFormat
}

nonisolated enum IOSAudioSessionDiagnostic: String, Equatable, Sendable {
    case categoryConfigured = "audio category configured"
    case hapticsDisabled = "recording haptics disabled"
    case sessionActivated = "audio session activated"
    case sessionDeactivated = "audio session deactivated"
    case observationInstalled = "audio observation installed"
    case observationRemoved = "audio observation removed"
    case staleCallbackIgnored = "stale audio callback ignored"
    case eventDelivered = "audio event delivered"
    case inputFrozen = "audio input frozen"
    case operationFailed = "audio operation failed"
}

@MainActor
protocol IOSAudioSessionSystemObservation: AnyObject {
    func cancel()
}

@MainActor
protocol IOSAudioSessionSystem: AnyObject {
    func setCategory(_ configuration: IOSAudioSessionConfiguration) throws
    func setAllowsHapticsAndSystemSoundsDuringRecording(_ allowed: Bool) throws
    func setActive(_ request: IOSAudioSessionActivationRequest) throws
    func currentState() -> IOSAudioSessionCurrentState
    func installEventObserver(
        _ receive: @escaping @MainActor @Sendable (
            IOSAudioSessionSystemEvent
        ) -> Void
    ) -> any IOSAudioSessionSystemObservation
}

@MainActor
final class IOSAudioSessionEventSubscription {
    let attemptToken: IOSAudioSessionAttemptToken
    let generation: IOSAudioSessionObservationGeneration

    private var cancelAction: (@MainActor () -> Void)?

    init(
        attemptToken: IOSAudioSessionAttemptToken,
        generation: IOSAudioSessionObservationGeneration,
        cancelAction: @escaping @MainActor () -> Void
    ) {
        self.attemptToken = attemptToken
        self.generation = generation
        self.cancelAction = cancelAction
    }

    func cancel() {
        let action = cancelAction
        cancelAction = nil
        action?()
    }
}

/// Owns the process-level iOS recording session boundary without owning a
/// recorder. All system callbacks are normalized before they reach the voice
/// owner, and carry only the attempt token and observation generation.
@MainActor
final class IOSAudioSessionAdapter {
    typealias EventHandler = @MainActor @Sendable (
        IOSAudioSessionEventEnvelope
    ) -> Void
    typealias DiagnosticHandler = @MainActor @Sendable (
        IOSAudioSessionDiagnostic
    ) -> Void

    private struct ObservationBinding: Equatable {
        let attemptToken: IOSAudioSessionAttemptToken
        let generation: IOSAudioSessionObservationGeneration
    }

    private let system: any IOSAudioSessionSystem
    private let diagnose: DiagnosticHandler
    private var activeAttemptToken: IOSAudioSessionAttemptToken?
    private var observationBinding: ObservationBinding?
    private var systemObservation: (any IOSAudioSessionSystemObservation)?
    private var nextObservationGeneration: UInt64 = 0

    init(
        system: any IOSAudioSessionSystem,
        diagnose: @escaping DiagnosticHandler = { _ in }
    ) {
        self.system = system
        self.diagnose = diagnose
    }

    convenience init(
        diagnose: @escaping DiagnosticHandler = { _ in }
    ) {
        self.init(
            system: IOSAVAudioSessionSystem(),
            diagnose: diagnose
        )
    }

    func configureAndActivate(
        for attemptToken: IOSAudioSessionAttemptToken
    ) throws {
        guard activeAttemptToken == nil else {
            throw IOSAudioSessionAdapterError.attemptAlreadyActive
        }

        do {
            try system.setCategory(.foregroundRecording)
            diagnose(.categoryConfigured)
        } catch {
            diagnose(.operationFailed)
            throw IOSAudioSessionAdapterError.categoryConfigurationFailed
        }

        do {
            try system.setAllowsHapticsAndSystemSoundsDuringRecording(false)
            diagnose(.hapticsDisabled)
        } catch {
            diagnose(.operationFailed)
            throw IOSAudioSessionAdapterError.hapticsConfigurationFailed
        }

        do {
            try system.setActive(.activate)
            activeAttemptToken = attemptToken
            diagnose(.sessionActivated)
        } catch {
            diagnose(.operationFailed)
            throw IOSAudioSessionAdapterError.activationFailed
        }
    }

    func deactivate(
        for attemptToken: IOSAudioSessionAttemptToken
    ) throws {
        guard activeAttemptToken == attemptToken else {
            throw IOSAudioSessionAdapterError.staleAttempt
        }

        do {
            try system.setActive(.deactivateAndNotifyOthers)
            activeAttemptToken = nil
            diagnose(.sessionDeactivated)
        } catch {
            diagnose(.operationFailed)
            throw IOSAudioSessionAdapterError.deactivationFailed
        }
    }

    func freezeCurrentInput(
        for attemptToken: IOSAudioSessionAttemptToken
    ) throws -> IOSAudioSessionFrozenInput {
        guard activeAttemptToken == attemptToken else {
            throw IOSAudioSessionAdapterError.staleAttempt
        }

        let state = system.currentState()
        guard state.isInputAvailable, !state.isInputMuted else {
            throw IOSAudioSessionAdapterError.inputUnavailable
        }
        guard state.inputPorts.count == 1,
              let input = state.inputPorts.first else {
            throw IOSAudioSessionAdapterError.ambiguousInput
        }
        guard !input.uid.isEmpty, !input.portType.isEmpty else {
            throw IOSAudioSessionAdapterError.invalidInputIdentity
        }
        guard state.sampleRate.isFinite,
              state.sampleRate > 0,
              state.inputNumberOfChannels > 0 else {
            throw IOSAudioSessionAdapterError.invalidInputFormat
        }

        let frozen = IOSAudioSessionFrozenInput(
            uid: input.uid,
            portType: input.portType,
            selectedDataSourceID: input.selectedDataSourceID,
            sampleRate: state.sampleRate,
            inputNumberOfChannels: state.inputNumberOfChannels
        )
        diagnose(.inputFrozen)
        return frozen
    }

    func inspectCurrentState() -> IOSAudioSessionCurrentState {
        system.currentState()
    }

    func observeEvents(
        for attemptToken: IOSAudioSessionAttemptToken,
        receive: @escaping EventHandler
    ) -> IOSAudioSessionEventSubscription {
        removeCurrentObservation()

        nextObservationGeneration &+= 1
        if nextObservationGeneration == 0 {
            nextObservationGeneration = 1
        }
        let generation = IOSAudioSessionObservationGeneration(
            rawValue: nextObservationGeneration
        )
        let binding = ObservationBinding(
            attemptToken: attemptToken,
            generation: generation
        )
        observationBinding = binding
        systemObservation = system.installEventObserver {
            [weak self] event in
            self?.handle(
                event,
                binding: binding,
                receive: receive
            )
        }
        diagnose(.observationInstalled)

        return IOSAudioSessionEventSubscription(
            attemptToken: attemptToken,
            generation: generation
        ) { [weak self] in
            self?.removeObservation(matching: binding)
        }
    }

    private func handle(
        _ systemEvent: IOSAudioSessionSystemEvent,
        binding: ObservationBinding,
        receive: EventHandler
    ) {
        guard observationBinding == binding else {
            diagnose(.staleCallbackIgnored)
            return
        }

        let event: IOSAudioSessionEvent
        switch systemEvent {
        case .interruptionBegan:
            event = .interruptionBegan
        case .interruptionEnded:
            // The resume suggestion is deliberately absent from the seam.
            // Only a later explicit Start may reactivate the audio session.
            event = .interruptionEnded
        case let .routeChanged(reason):
            event = .routeChanged(
                reason: reason,
                currentState: system.currentState()
            )
        case .inputMuteChanged:
            event = .inputMuteChanged(
                currentState: system.currentState()
            )
        case .mediaServicesLost:
            event = .mediaServicesLost
        case .mediaServicesReset:
            event = .mediaServicesReset
        }

        receive(
            IOSAudioSessionEventEnvelope(
                attemptToken: binding.attemptToken,
                generation: binding.generation,
                event: event
            )
        )
        diagnose(.eventDelivered)
    }

    private func removeObservation(matching binding: ObservationBinding) {
        guard observationBinding == binding else { return }
        removeCurrentObservation()
    }

    private func removeCurrentObservation() {
        guard observationBinding != nil || systemObservation != nil else {
            return
        }
        observationBinding = nil
        systemObservation?.cancel()
        systemObservation = nil
        diagnose(.observationRemoved)
    }
}

@MainActor
final class IOSAVAudioSessionSystem: IOSAudioSessionSystem {
    private struct UnsupportedConfiguration: Error {}

    private let session: AVAudioSession
    private let application: AVAudioApplication
    private let notificationCenter: NotificationCenter

    init(
        session: AVAudioSession = .sharedInstance(),
        application: AVAudioApplication = .shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.session = session
        self.application = application
        self.notificationCenter = notificationCenter
    }

    func setCategory(_ configuration: IOSAudioSessionConfiguration) throws {
        guard configuration == .foregroundRecording else {
            throw UnsupportedConfiguration()
        }
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
    }

    func setAllowsHapticsAndSystemSoundsDuringRecording(
        _ allowed: Bool
    ) throws {
        try session.setAllowHapticsAndSystemSoundsDuringRecording(allowed)
    }

    func setActive(_ request: IOSAudioSessionActivationRequest) throws {
        switch request {
        case .activate:
            try session.setActive(true, options: [])
        case .deactivateAndNotifyOthers:
            try session.setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        }
    }

    func currentState() -> IOSAudioSessionCurrentState {
        IOSAudioSessionCurrentState(
            inputPorts: session.currentRoute.inputs.map { input in
                IOSAudioSessionInputPort(
                    uid: input.uid,
                    portType: input.portType.rawValue,
                    selectedDataSourceID: input.selectedDataSource.map {
                        Int(truncating: $0.dataSourceID)
                    }
                )
            },
            isInputAvailable: session.isInputAvailable,
            isInputMuted: application.isInputMuted,
            sampleRate: session.sampleRate,
            inputNumberOfChannels: session.inputNumberOfChannels
        )
    }

    func installEventObserver(
        _ receive: @escaping @MainActor @Sendable (
            IOSAudioSessionSystemEvent
        ) -> Void
    ) -> any IOSAudioSessionSystemObservation {
        let bridge = IOSAudioSessionNotificationBridge(receive: receive)
        let registrations = [
            NotificationRegistration(
                name: AVAudioSession.interruptionNotification,
                object: session
            ),
            NotificationRegistration(
                name: AVAudioSession.routeChangeNotification,
                object: session
            ),
            NotificationRegistration(
                name: AVAudioApplication.inputMuteStateChangeNotification,
                object: application
            ),
            NotificationRegistration(
                name: AVAudioSession.mediaServicesWereLostNotification,
                object: session
            ),
            NotificationRegistration(
                name: AVAudioSession.mediaServicesWereResetNotification,
                object: session
            ),
        ]
        let observers = registrations.map { registration in
            notificationCenter.addObserver(
                forName: registration.name,
                object: registration.object,
                queue: nil
            ) { notification in
                guard let event = Self.systemEvent(from: notification) else {
                    return
                }
                bridge.send(event)
            }
        }
        return IOSAVAudioSessionNotificationObservation(
            notificationCenter: notificationCenter,
            observers: observers
        )
    }

    nonisolated static func systemEvent(
        from notification: Notification
    ) -> IOSAudioSessionSystemEvent? {
        switch notification.name {
        case AVAudioSession.interruptionNotification:
            guard let number = notification.userInfo?[
                AVAudioSessionInterruptionTypeKey
            ] as? NSNumber,
            let type = AVAudioSession.InterruptionType(
                rawValue: number.uintValue
            ) else {
                return nil
            }
            switch type {
            case .began:
                return .interruptionBegan
            case .ended:
                return .interruptionEnded
            @unknown default:
                return nil
            }
        case AVAudioSession.routeChangeNotification:
            let rawValue = (
                notification.userInfo?[AVAudioSessionRouteChangeReasonKey]
                    as? NSNumber
            )?.uintValue
            let reason = rawValue.flatMap(
                AVAudioSession.RouteChangeReason.init(rawValue:)
            )
            return .routeChanged(normalize(reason))
        case AVAudioApplication.inputMuteStateChangeNotification:
            return .inputMuteChanged
        case AVAudioSession.mediaServicesWereLostNotification:
            return .mediaServicesLost
        case AVAudioSession.mediaServicesWereResetNotification:
            return .mediaServicesReset
        default:
            return nil
        }
    }

    nonisolated private static func normalize(
        _ reason: AVAudioSession.RouteChangeReason?
    ) -> IOSAudioRouteChangeReason {
        guard let reason else { return .unknown }
        switch reason {
        case .unknown:
            return .unknown
        case .newDeviceAvailable:
            return .newDeviceAvailable
        case .oldDeviceUnavailable:
            return .oldDeviceUnavailable
        case .categoryChange:
            return .categoryChange
        case .override:
            return .override
        case .wakeFromSleep:
            return .wakeFromSleep
        case .noSuitableRouteForCategory:
            return .noSuitableRouteForCategory
        case .routeConfigurationChange:
            return .routeConfigurationChange
        @unknown default:
            return .unknown
        }
    }
}

private struct NotificationRegistration {
    let name: Notification.Name
    let object: AnyObject
}

nonisolated final class IOSAudioSessionNotificationBridge: @unchecked Sendable {
    private let receive: @MainActor @Sendable (
        IOSAudioSessionSystemEvent
    ) -> Void
    private let lock = NSLock()
    private var pendingEvents: [IOSAudioSessionSystemEvent] = []
    private var drainIsScheduled = false

    init(
        receive: @escaping @MainActor @Sendable (
            IOSAudioSessionSystemEvent
        ) -> Void
    ) {
        self.receive = receive
    }

    func send(_ event: IOSAudioSessionSystemEvent) {
        let shouldScheduleDrain = lock.withLock {
            pendingEvents.append(event)
            guard !drainIsScheduled else { return false }
            drainIsScheduled = true
            return true
        }
        guard shouldScheduleDrain else { return }

        Task { @MainActor [self] in
            drainPendingEvents()
        }
    }

    @MainActor
    private func drainPendingEvents() {
        while let event = takeNextEvent() {
            receive(event)
        }
    }

    private func takeNextEvent() -> IOSAudioSessionSystemEvent? {
        lock.withLock {
            guard !pendingEvents.isEmpty else {
                drainIsScheduled = false
                return nil
            }
            return pendingEvents.removeFirst()
        }
    }
}

@MainActor
private final class IOSAVAudioSessionNotificationObservation:
    IOSAudioSessionSystemObservation
{
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol]

    init(
        notificationCenter: NotificationCenter,
        observers: [NSObjectProtocol]
    ) {
        self.notificationCenter = notificationCenter
        self.observers = observers
    }

    func cancel() {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }
}
