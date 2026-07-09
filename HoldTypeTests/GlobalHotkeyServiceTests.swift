//
//  GlobalHotkeyServiceTests.swift
//  HoldTypeTests
//
//  Created by Codex on 6/20/26.
//

import Carbon.HIToolbox
import CoreGraphics
import HoldTypeDomain
import Testing
@testable import HoldType

struct GlobalHotkeyServiceTests {

    @Test func defaultShortcutIsVisibleAsDisplayData() {
        let configuration = GlobalHotkeyConfiguration.defaultDictation

        #expect(configuration.shortcut == .defaultDictation)
        #expect(configuration.shortcut.displayText == "Right Command")
        #expect(configuration.activationMode == .holdToRecord)
        #expect(configuration.stopsRecordingOnKeyUp)
        #expect(configuration.displayText == "Right Command - Hold to record")
    }

    @Test func fallbackShortcutUsesGlobeFn() {
        let configuration = GlobalHotkeyConfiguration.fallbackDictation

        #expect(configuration.shortcut == .fallbackDictation)
        #expect(configuration.shortcut.displayText == "Globe/Fn")
        #expect(configuration.stopsRecordingOnKeyUp)
        #expect(configuration.displayText == "Globe/Fn - Hold to record")
    }

    @Test func appClipboardPasteShortcutUsesControlCommandV() {
        let shortcut = GlobalHotkeyShortcut.appClipboardPaste

        #expect(shortcut.modifiers == [.control, .command])
        #expect(shortcut.key == "V")
        #expect(shortcut.displayText == "Control+Command+V")
        #expect(shortcut.menuKeyEquivalentText == "⌃⌘V")
    }

    @Test func translationShortcutUsesOptionRightCommand() {
        let shortcut = GlobalHotkeyShortcut.translationDictation

        #expect(shortcut.modifiers == [.option])
        #expect(shortcut.key == "Right Command")
        #expect(shortcut.displayText == "Option+Right Command")
        #expect(shortcut.menuHoldText == "Hold Right ⌘ + Right ⌥")
    }

    @Test func dictationShortcutUsesCompactMenuHoldText() {
        let shortcut = GlobalHotkeyShortcut.defaultDictation

        #expect(shortcut.menuHoldText == "Hold Right ⌘")
    }

    @Test func rightCommandMapperEmitsHoldEvents() {
        var mapper = RightCommandHotkeyEventMapper()

        let keyDown = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightCommand),
            flags: [.maskCommand]
        )
        let keyUp = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightCommand),
            flags: []
        )

        #expect(keyDown == .keyDown())
        #expect(keyUp == .keyUp())
        #expect(mapper.isRightCommandPressed == false)
    }

    @Test func rightCommandMapperCarriesOptionAsTranslationIntentOnKeyDown() {
        var mapper = RightCommandHotkeyEventMapper()

        let keyDown = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightCommand),
            flags: [.maskCommand, .maskAlternate]
        )
        let keyUp = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightCommand),
            flags: [.maskAlternate]
        )

        #expect(keyDown == .keyDown(outputIntent: .translate))
        #expect(keyUp == .keyUp())
    }

    @Test func rightCommandMapperPromotesTranslationWhenOptionIsPressedAfterRightCommand() {
        var mapper = RightCommandHotkeyEventMapper()

        let keyDown = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightCommand),
            flags: [.maskCommand]
        )
        let optionDown = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightOption),
            flags: [.maskCommand, .maskAlternate]
        )
        let keyUp = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightCommand),
            flags: [.maskAlternate]
        )

        #expect(keyDown == .keyDown())
        #expect(optionDown == .outputIntentChanged(to: .translate))
        #expect(keyUp == .keyUp())
    }

    @Test func rightCommandMapperIgnoresOptionAloneBeforeTranslationKeyDown() {
        var mapper = RightCommandHotkeyEventMapper()

        let optionDown = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightOption),
            flags: [.maskAlternate]
        )
        let keyDown = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightCommand),
            flags: [.maskCommand, .maskAlternate]
        )
        let keyUp = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightCommand),
            flags: [.maskAlternate]
        )

        #expect(optionDown == nil)
        #expect(keyDown == .keyDown(outputIntent: .translate))
        #expect(keyUp == .keyUp())
    }

    @Test func rightCommandMapperKeepsTranslationIntentAfterOptionRelease() {
        var mapper = RightCommandHotkeyEventMapper()

        let keyDown = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightCommand),
            flags: [.maskCommand]
        )
        let optionDown = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightOption),
            flags: [.maskCommand, .maskAlternate]
        )
        let optionUp = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightOption),
            flags: [.maskCommand]
        )
        let keyUp = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightCommand),
            flags: []
        )

        #expect(keyDown == .keyDown())
        #expect(optionDown == .outputIntentChanged(to: .translate))
        #expect(optionUp == nil)
        #expect(keyUp == .keyUp())
    }

    @Test func rightCommandMapperIgnoresLeftCommandAndRepeatedFlags() {
        var mapper = RightCommandHotkeyEventMapper()

        let leftCommand = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_Command),
            flags: [.maskCommand]
        )
        let firstRightCommand = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightCommand),
            flags: [.maskCommand]
        )
        let repeatedRightCommand = mapper.event(
            type: .flagsChanged,
            keyCode: Int64(kVK_RightCommand),
            flags: [.maskCommand]
        )
        let unrelatedKeyDown = mapper.event(
            type: .keyDown,
            keyCode: Int64(kVK_RightCommand),
            flags: [.maskCommand]
        )

        #expect(leftCommand == nil)
        #expect(firstRightCommand == .keyDown())
        #expect(repeatedRightCommand == nil)
        #expect(unrelatedKeyDown == nil)
    }

    @Test func holdToRecordStartsOnKeyDownAndStopsOnMatchingKeyUp() {
        let configuration = GlobalHotkeyConfiguration.defaultDictation

        #expect(
            configuration.recordingCommand(
                for: .keyDown,
                isRecording: false,
                isShortcutPressed: false
            ) == .startRecording
        )
        #expect(
            configuration.recordingCommand(
                for: .keyDown,
                isRecording: true,
                isShortcutPressed: true
            ) == nil
        )
        #expect(
            configuration.recordingCommand(
                for: .keyUp,
                isRecording: true,
                isShortcutPressed: true
            ) == .stopRecording
        )
        #expect(
            configuration.recordingCommand(
                for: .keyUp,
                isRecording: true,
                isShortcutPressed: false
            ) == nil
        )
    }

    @Test func toggleModeUsesKeyDownOnlyAndIgnoresKeyUp() {
        let configuration = GlobalHotkeyConfiguration(
            shortcut: .defaultDictation,
            activationMode: .toggle
        )

        #expect(configuration.stopsRecordingOnKeyUp == false)
        #expect(configuration.displayText == "Right Command - Toggle")
        #expect(
            configuration.recordingCommand(
                for: .keyDown,
                isRecording: false,
                isShortcutPressed: false
            ) == .startRecording
        )
        #expect(
            configuration.recordingCommand(
                for: .keyUp,
                isRecording: true,
                isShortcutPressed: true
            ) == nil
        )
        #expect(
            configuration.recordingCommand(
                for: .keyDown,
                isRecording: true,
                isShortcutPressed: true
            ) == nil
        )
        #expect(
            configuration.recordingCommand(
                for: .keyDown,
                isRecording: true,
                isShortcutPressed: false
            ) == .stopRecording
        )
    }

    @Test func registrationStatusExposesActiveConfiguration() {
        let configuration = GlobalHotkeyConfiguration.defaultDictation

        #expect(
            GlobalHotkeyRegistrationStatus.registered(configuration).activeConfiguration
                == configuration
        )
        #expect(GlobalHotkeyRegistrationStatus.registered(configuration).isRegistered)
        #expect(GlobalHotkeyRegistrationStatus.notRegistered.isRegistered == false)
        #expect(
            GlobalHotkeyRegistrationStatus.unavailable(message: "Already in use").displayText
                == "Global hotkey unavailable"
        )
    }

    @Test func fakeHotkeyDeliversSubscribedActions() throws {
        let service = FakeGlobalHotkeyService()
        var receivedActions: [GlobalHotkeyAction] = []

        try service.startListening { event in
            receivedActions.append(event.action)
        }
        service.trigger(.keyDown)
        service.trigger(.keyUp)

        #expect(service.startListeningCount == 1)
        #expect(service.currentRegistrationStatus == .registered(.defaultDictation))
        #expect(service.triggeredActions == [.keyDown, .keyUp])
        #expect(service.triggeredEvents == [.keyDown(), .keyUp()])
        #expect(receivedActions == [.keyDown, .keyUp])
    }

    @Test func fakeHotkeyDeliversOutputIntentEvents() throws {
        let service = FakeGlobalHotkeyService()
        var receivedEvents: [GlobalHotkeyEvent] = []

        try service.startListening { event in
            receivedEvents.append(event)
        }
        service.trigger(.keyDown(outputIntent: .translate))

        #expect(
            service.triggeredEvents == [
                .keyDown(outputIntent: .translate)
            ]
        )
        #expect(receivedEvents == service.triggeredEvents)
    }

    @Test func fakeHotkeyCanSimulateFallbackRegistration() throws {
        let service = FakeGlobalHotkeyService(
            preferredConfiguration: .defaultDictation,
            startListeningResult: .success(.fallbackRegistered(.fallbackDictation))
        )
        var receivedActions: [GlobalHotkeyAction] = []

        try service.startListening { event in
            receivedActions.append(event.action)
        }
        service.trigger(.keyDown)

        #expect(service.preferredConfiguration == .defaultDictation)
        #expect(service.currentRegistrationStatus == .fallbackRegistered(.fallbackDictation))
        #expect(service.currentRegistrationStatus.activeConfiguration == .fallbackDictation)
        #expect(receivedActions == [.keyDown])
    }

    @Test func fakeHotkeyCanSimulateRegistrationFailure() {
        let service = FakeGlobalHotkeyService(
            startListeningResult: .failure(
                .registrationUnavailable(message: "Right Command is already in use.")
            )
        )
        var receivedActions: [GlobalHotkeyAction] = []

        do {
            try service.startListening { event in
                receivedActions.append(event.action)
            }
            Issue.record("Expected startListening to throw")
        } catch let error as GlobalHotkeyServiceError {
            #expect(
                error == .registrationUnavailable(
                    message: "Right Command is already in use."
                )
            )
        } catch {
            Issue.record("Expected GlobalHotkeyServiceError, got \(error)")
        }

        service.trigger(.keyDown)

        #expect(service.startListeningCount == 1)
        #expect(
            service.currentRegistrationStatus == .unavailable(
                message: "Right Command is already in use."
            )
        )
        #expect(service.triggeredActions == [.keyDown])
        #expect(receivedActions.isEmpty)
    }

    @Test func stopListeningClearsSubscribedHandler() throws {
        let service = FakeGlobalHotkeyService()
        var receivedActions: [GlobalHotkeyAction] = []

        try service.startListening { event in
            receivedActions.append(event.action)
        }
        service.stopListening()
        service.trigger(.keyDown)

        #expect(service.stopListeningCount == 1)
        #expect(service.currentRegistrationStatus == .notRegistered)
        #expect(receivedActions.isEmpty)
    }

    @Test func appCodeCanDependOnHotkeyProtocol() throws {
        let service = FakeGlobalHotkeyService()
        let consumer = HotkeyConsumer(service: service)

        try consumer.connect()
        service.trigger(.keyDown)

        #expect(consumer.receivedActions == [.keyDown])
        #expect(service.currentRegistrationStatus == .registered(.defaultDictation))
    }
}

private final class HotkeyConsumer {
    private let service: any GlobalHotkeyService
    private(set) var receivedActions: [GlobalHotkeyAction] = []

    init(service: any GlobalHotkeyService) {
        self.service = service
    }

    func connect() throws {
        try service.startListening { [weak self] event in
            self?.receivedActions.append(event.action)
        }
    }
}
