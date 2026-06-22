//
//  GlobalHotkeyServiceTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/20/26.
//

import Testing
@testable import vibetype

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

        try service.startListening { action in
            receivedActions.append(action)
        }
        service.trigger(.keyDown)
        service.trigger(.keyUp)

        #expect(service.startListeningCount == 1)
        #expect(service.currentRegistrationStatus == .registered(.defaultDictation))
        #expect(service.triggeredActions == [.keyDown, .keyUp])
        #expect(receivedActions == [.keyDown, .keyUp])
    }

    @Test func fakeHotkeyCanSimulateFallbackRegistration() throws {
        let service = FakeGlobalHotkeyService(
            preferredConfiguration: .defaultDictation,
            startListeningResult: .success(.fallbackRegistered(.fallbackDictation))
        )
        var receivedActions: [GlobalHotkeyAction] = []

        try service.startListening { action in
            receivedActions.append(action)
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
            try service.startListening { action in
                receivedActions.append(action)
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

        try service.startListening { action in
            receivedActions.append(action)
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
        try service.startListening { [weak self] action in
            self?.receivedActions.append(action)
        }
    }
}
