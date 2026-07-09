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

struct RightCommandHotkeyEventMapper {
    private(set) var isRightCommandPressed = false
    private var activeOutputIntent: DictationOutputIntent = .standard

    mutating func event(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags
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

        let isPressed = flags.contains(.maskCommand)

        if isPressed, !isRightCommandPressed {
            isRightCommandPressed = true
            activeOutputIntent = outputIntent(for: flags)
            return .keyDown(outputIntent: activeOutputIntent)
        }

        if !isPressed, isRightCommandPressed {
            isRightCommandPressed = false
            activeOutputIntent = .standard
            return .keyUp()
        }

        return outputIntentChangeEventIfNeeded(for: flags)
    }

    mutating func reset() {
        isRightCommandPressed = false
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
    let preferredConfiguration = GlobalHotkeyConfiguration.defaultDictation

    private(set) var currentRegistrationStatus: GlobalHotkeyRegistrationStatus = .notRegistered

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var actionHandler: GlobalHotkeyActionHandler?
    private var eventMapper = RightCommandHotkeyEventMapper()

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
        currentRegistrationStatus = .registered(preferredConfiguration)
    }

    func stopListening() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        self.runLoopSource = nil
        self.eventTap = nil
        actionHandler = nil
        eventMapper.reset()
        currentRegistrationStatus = .notRegistered
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let hotkeyEvent = eventMapper.event(
            type: type,
            keyCode: keyCode,
            flags: event.flags
        )

        if let hotkeyEvent {
            actionHandler?(hotkeyEvent)
        }

        return Unmanaged.passUnretained(event)
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
