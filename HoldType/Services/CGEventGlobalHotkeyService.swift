//
//  CGEventGlobalHotkeyService.swift
//  HoldType
//
//  Created by Codex on 7/6/26.
//

import Carbon.HIToolbox
import CoreGraphics
import Foundation
import HoldTypeDomain
import OSLog

enum RightCommandPhysicalState: Equatable {
    case pressed
    case released
}

private enum RightCommandHotkeyRecoveryReason: String {
    case eventTapDisabledByTimeout = "tap_disabled_timeout"
    case eventTapDisabledByUserInput = "tap_disabled_user_input"
    case listenerStopped = "listener_stopped"
    case physicalStateReconciliation = "physical_state_reconciliation"
}

struct RightCommandHotkeyEventMapper {
    static let requiredReleasedObservationCount = 2

    private(set) var isRightCommandPressed = false
    private var activeOutputIntent: DictationOutputIntent = .standard
    private var consecutiveReleasedObservationCount = 0

    mutating func event(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        rightCommandPhysicalState: RightCommandPhysicalState
    ) -> GlobalHotkeyEvent? {
        guard type == .flagsChanged else {
            return nil
        }

        guard keyCode == Int64(kVK_RightCommand) else {
            guard isRightCommandPressed else {
                return nil
            }

            return outputIntentChangeEventIfNeeded(for: flags)
        }

        // The event flags are the authoritative edge for the normal path. A
        // separately queried key-state snapshot may still describe the state
        // before this event while the event tap callback is running.
        let eventHasCommand = flags.contains(.maskCommand)
        if eventHasCommand, !isRightCommandPressed {
            isRightCommandPressed = true
            consecutiveReleasedObservationCount = 0
            activeOutputIntent = outputIntent(for: flags)
            return .keyDown(outputIntent: activeOutputIntent)
        }

        if !eventHasCommand, isRightCommandPressed {
            return releaseIfPressed()
        }

        // maskCommand is aggregate and stays set when Left Command remains
        // held. Treat the callback-time HID value as the first reconciliation
        // sample instead of trusting one potentially stale read.
        if rightCommandPhysicalState == .released, isRightCommandPressed {
            return reconcilePhysicalState(.released)
        }

        return outputIntentChangeEventIfNeeded(for: flags)
    }

    mutating func reconcilePhysicalState(
        _ physicalState: RightCommandPhysicalState
    ) -> GlobalHotkeyEvent? {
        guard isRightCommandPressed else {
            consecutiveReleasedObservationCount = 0
            return nil
        }

        guard physicalState == .released else {
            consecutiveReleasedObservationCount = 0
            return nil
        }

        // A second sample avoids stopping on a transient system-state read.
        consecutiveReleasedObservationCount += 1
        guard consecutiveReleasedObservationCount >= Self.requiredReleasedObservationCount else {
            return nil
        }

        return releaseIfPressed()
    }

    mutating func releaseIfPressed() -> GlobalHotkeyEvent? {
        guard isRightCommandPressed else {
            return nil
        }

        isRightCommandPressed = false
        consecutiveReleasedObservationCount = 0
        activeOutputIntent = .standard
        return .keyUp()
    }

    mutating func reset() {
        isRightCommandPressed = false
        consecutiveReleasedObservationCount = 0
        activeOutputIntent = .standard
    }

    private func outputIntent(for flags: CGEventFlags) -> DictationOutputIntent {
        flags.contains(.maskAlternate) ? .translate : .standard
    }

    private mutating func outputIntentChangeEventIfNeeded(for flags: CGEventFlags) -> GlobalHotkeyEvent? {
        let updatedOutputIntent = activeOutputIntent.merged(with: outputIntent(for: flags))
        guard updatedOutputIntent != activeOutputIntent else {
            return nil
        }

        activeOutputIntent = updatedOutputIntent
        return .outputIntentChanged(to: updatedOutputIntent)
    }
}

final class CGEventGlobalHotkeyService: GlobalHotkeyService {
    typealias RightCommandPhysicalStateProvider = () -> RightCommandPhysicalState

    static let physicalStateReconciliationInterval: TimeInterval = 0.15

    let preferredConfiguration = GlobalHotkeyConfiguration.defaultDictation

    private(set) var currentRegistrationStatus: GlobalHotkeyRegistrationStatus = .notRegistered

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.holdtype.HoldType",
        category: "Hotkey"
    )

    private let rightCommandPhysicalStateProvider: RightCommandPhysicalStateProvider
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var physicalStateReconciliationTimer: Timer?
    private var actionHandler: GlobalHotkeyActionHandler?
    private var eventMapper = RightCommandHotkeyEventMapper()

    init(
        rightCommandPhysicalStateProvider: @escaping RightCommandPhysicalStateProvider = {
            CGEventSource.keyState(
                .hidSystemState,
                key: CGKeyCode(kVK_RightCommand)
            ) ? .pressed : .released
        }
    ) {
        self.rightCommandPhysicalStateProvider = rightCommandPhysicalStateProvider
    }

    func startListening(actionHandler: @escaping GlobalHotkeyActionHandler) throws {
        stopListening()

        self.actionHandler = actionHandler

        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let newEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: dictationHotkeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            let message = "Input Monitoring is required for Right Command dictation shortcuts."
            currentRegistrationStatus = .unavailable(message: message)
            self.actionHandler = nil
            throw GlobalHotkeyServiceError.registrationUnavailable(message: message)
        }

        guard let newRunLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            newEventTap,
            0
        ) else {
            CFMachPortInvalidate(newEventTap)
            let message = "Could not start Right Command dictation shortcut listener."
            currentRegistrationStatus = .unavailable(message: message)
            self.actionHandler = nil
            throw GlobalHotkeyServiceError.registrationUnavailable(message: message)
        }

        eventTap = newEventTap
        runLoopSource = newRunLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newEventTap, enable: true)
        startPhysicalStateReconciliation()
        currentRegistrationStatus = .registered(preferredConfiguration)
    }

    func stopListening() {
        physicalStateReconciliationTimer?.invalidate()
        physicalStateReconciliationTimer = nil

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        self.runLoopSource = nil
        self.eventTap = nil

        if let keyUp = eventMapper.releaseIfPressed() {
            logRecoveredRelease(reason: .listenerStopped)
            actionHandler?(keyUp)
        }

        actionHandler = nil
        eventMapper.reset()
        currentRegistrationStatus = .notRegistered
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

            let reason: RightCommandHotkeyRecoveryReason = type == .tapDisabledByTimeout
                ? .eventTapDisabledByTimeout
                : .eventTapDisabledByUserInput
            Self.logger.info("Hotkey listener recovered: \(reason.rawValue, privacy: .public)")
            reconcilePhysicalState()

            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let hotkeyEvent = eventMapper.event(
            type: type,
            keyCode: keyCode,
            flags: event.flags,
            rightCommandPhysicalState: rightCommandPhysicalStateProvider()
        )

        if let hotkeyEvent {
            actionHandler?(hotkeyEvent)
        }

        return Unmanaged.passUnretained(event)
    }

    private func startPhysicalStateReconciliation() {
        let timer = Timer(
            timeInterval: Self.physicalStateReconciliationInterval,
            repeats: true
        ) { [weak self] _ in
            self?.reconcilePhysicalState()
        }
        physicalStateReconciliationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func reconcilePhysicalState() {
        guard let keyUp = eventMapper.reconcilePhysicalState(
            rightCommandPhysicalStateProvider()
        ) else {
            return
        }

        logRecoveredRelease(reason: .physicalStateReconciliation)
        actionHandler?(keyUp)
    }

    private func logRecoveredRelease(reason: RightCommandHotkeyRecoveryReason) {
        Self.logger.info("Hotkey release recovered: \(reason.rawValue, privacy: .public)")
    }

    deinit {
        stopListening()
    }
}

private func dictationHotkeyEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let service = Unmanaged<CGEventGlobalHotkeyService>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return service.handle(type: type, event: event)
}
