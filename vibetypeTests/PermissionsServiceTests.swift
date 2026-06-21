//
//  PermissionsServiceTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/20/26.
//

import Testing
@testable import vibetype

struct PermissionsServiceTests {

    @Test func currentStatusMapsAuthorizationStates() {
        #expect(
            MicrophonePermissionService(
                client: FakeMicrophonePermissionClient(authorizationStatus: .allowed)
            ).currentStatus() == .allowed
        )
        #expect(
            MicrophonePermissionService(
                client: FakeMicrophonePermissionClient(authorizationStatus: .denied)
            ).currentStatus() == .denied
        )
        #expect(
            MicrophonePermissionService(
                client: FakeMicrophonePermissionClient(authorizationStatus: .notDetermined)
            ).currentStatus() == .notDetermined
        )
    }

    @Test func unavailableAudioInputBlocksRecordingBeforeAuthorizationState() {
        let client = FakeMicrophonePermissionClient(
            hasAvailableAudioInput: false,
            authorizationStatus: .allowed
        )
        let service = MicrophonePermissionService(client: client)

        #expect(service.currentStatus() == .unavailable)
        #expect(service.currentStatus().canRecord == false)
    }

    @Test func requestPermissionSkipsPromptForTerminalStates() {
        let allowedClient = FakeMicrophonePermissionClient(authorizationStatus: .allowed)
        let deniedClient = FakeMicrophonePermissionClient(authorizationStatus: .denied)

        MicrophonePermissionService(client: allowedClient).requestPermission { status in
            #expect(status == .allowed)
        }
        MicrophonePermissionService(client: deniedClient).requestPermission { status in
            #expect(status == .denied)
        }

        #expect(allowedClient.requestCount == 0)
        #expect(deniedClient.requestCount == 0)
    }

    @Test func requestPermissionUsesCallbackWhenNotDetermined() {
        let client = FakeMicrophonePermissionClient(
            authorizationStatus: .notDetermined,
            requestResults: [true]
        )
        let service = MicrophonePermissionService(client: client)

        service.requestPermission { status in
            #expect(status == .allowed)
        }

        #expect(client.requestCount == 1)
    }

    @Test func unavailableAudioInputDoesNotRequestPermission() {
        let client = FakeMicrophonePermissionClient(
            hasAvailableAudioInput: false,
            authorizationStatus: .notDetermined,
            requestResults: [true]
        )
        let service = MicrophonePermissionService(client: client)

        service.requestPermission { status in
            #expect(status == .unavailable)
        }

        #expect(client.requestCount == 0)
    }

    @Test func microphoneSettingsCopyNamesStatusAndBoundedActions() {
        #expect(MicrophonePermissionStatus.allowed.settingsStatusText == "Microphone: Allowed")
        #expect(MicrophonePermissionStatus.allowed.settingsActionTitle == nil)
        #expect(MicrophonePermissionStatus.allowed.settingsDescription.contains("choose a dictation action"))

        #expect(MicrophonePermissionStatus.denied.settingsStatusText == "Microphone: Not Allowed")
        #expect(MicrophonePermissionStatus.denied.settingsActionTitle == "Open Microphone Settings")
        #expect(MicrophonePermissionStatus.denied.settingsDescription.contains("System Settings"))

        #expect(MicrophonePermissionStatus.notDetermined.settingsStatusText == "Microphone: Permission Needed")
        #expect(MicrophonePermissionStatus.notDetermined.settingsActionTitle == "Request Microphone Access")

        #expect(MicrophonePermissionStatus.unavailable.settingsStatusText == "Microphone: Unavailable")
        #expect(MicrophonePermissionStatus.unavailable.settingsActionTitle == nil)
        #expect(MicrophonePermissionStatus.unavailable.settingsDescription.contains("no microphone input"))
    }

    @Test func microphoneMenuCopyBlocksRecordingWithClearNextAction() {
        #expect(MicrophonePermissionStatus.allowed.menuStatusText == "Microphone: Allowed")
        #expect(MicrophonePermissionStatus.allowed.menuDetailText == nil)
        #expect(MicrophonePermissionStatus.allowed.canUseRecordingAction)
        #expect(MicrophonePermissionStatus.allowed.canRecord)

        #expect(MicrophonePermissionStatus.notDetermined.menuStatusText == "Microphone: Permission Needed")
        #expect(MicrophonePermissionStatus.notDetermined.menuDetailText?.contains("Allow microphone access") == true)
        #expect(MicrophonePermissionStatus.notDetermined.canUseRecordingAction)
        #expect(MicrophonePermissionStatus.notDetermined.canRecord == false)

        #expect(MicrophonePermissionStatus.denied.menuStatusText == "Microphone: Not Allowed")
        #expect(MicrophonePermissionStatus.denied.menuDetailText?.contains("Recording is blocked") == true)
        #expect(MicrophonePermissionStatus.denied.canUseRecordingAction == false)
        #expect(MicrophonePermissionStatus.denied.canRecord == false)

        #expect(MicrophonePermissionStatus.unavailable.menuStatusText == "Microphone: Unavailable")
        #expect(MicrophonePermissionStatus.unavailable.menuDetailText?.contains("no microphone input") == true)
        #expect(MicrophonePermissionStatus.unavailable.canUseRecordingAction == false)
        #expect(MicrophonePermissionStatus.unavailable.canRecord == false)
    }

    @Test func accessibilityStatusMapsTrustWithoutPrompting() {
        let trustedClient = FakeAccessibilityPermissionClient(isTrusted: true)
        let notTrustedClient = FakeAccessibilityPermissionClient(isTrusted: false)

        #expect(AccessibilityPermissionService(client: trustedClient).currentStatus() == .trusted)
        #expect(
            AccessibilityPermissionService(client: notTrustedClient).currentStatus() == .notTrusted
        )
        #expect(AccessibilityPermissionStatus.trusted.canPasteIntoActiveApp)
        #expect(AccessibilityPermissionStatus.notTrusted.canPasteIntoActiveApp == false)
        #expect(trustedClient.promptRequests == [false])
        #expect(notTrustedClient.promptRequests == [false])
    }

    @Test func accessibilitySettingsOpenerIsSeparateFromStatusCheck() {
        let client = FakeAccessibilityPermissionClient(isTrusted: false, opensSettings: true)
        let service = AccessibilityPermissionService(client: client)

        #expect(service.currentStatus() == .notTrusted)
        #expect(client.openSettingsCount == 0)
        #expect(service.openAccessibilitySettings())
        #expect(client.openSettingsCount == 1)
        #expect(client.promptRequests == [false])
    }

    @Test func accessibilitySettingsCopyNamesStatus() {
        #expect(AccessibilityPermissionStatus.trusted.settingsStatusText == "Accessibility: Allowed")
        #expect(AccessibilityPermissionStatus.trusted.settingsSystemImage == "checkmark.circle")
        #expect(AccessibilityPermissionStatus.trusted.settingsDescription.contains("control the active app"))

        #expect(AccessibilityPermissionStatus.notTrusted.settingsStatusText == "Accessibility: Not Allowed")
        #expect(AccessibilityPermissionStatus.notTrusted.settingsSystemImage == "exclamationmark.triangle")
        #expect(AccessibilityPermissionStatus.notTrusted.settingsDescription.contains("copy-only fallback"))
    }

    @Test func accessibilityMenuCopyKeepsCopyFallbackAvailable() {
        #expect(AccessibilityPermissionStatus.trusted.menuStatusText == "Accessibility: Allowed")
        #expect(AccessibilityPermissionStatus.trusted.menuDetailText == nil)
        #expect(AccessibilityPermissionStatus.trusted.canPasteIntoActiveApp)

        #expect(AccessibilityPermissionStatus.notTrusted.menuStatusText == "Accessibility: Not Allowed")
        #expect(AccessibilityPermissionStatus.notTrusted.menuDetailText?.contains("Auto-paste is unavailable") == true)
        #expect(AccessibilityPermissionStatus.notTrusted.menuDetailText?.contains("copied") == true)
        #expect(AccessibilityPermissionStatus.notTrusted.canPasteIntoActiveApp == false)
    }
}

private final class FakeMicrophonePermissionClient: MicrophonePermissionClient {
    private(set) var requestCount = 0
    private var requestResults: [Bool]

    var hasAvailableAudioInput: Bool
    var currentAuthorizationStatus: MicrophoneAuthorizationStatus

    init(
        hasAvailableAudioInput: Bool = true,
        authorizationStatus: MicrophoneAuthorizationStatus,
        requestResults: [Bool] = []
    ) {
        self.hasAvailableAudioInput = hasAvailableAudioInput
        self.currentAuthorizationStatus = authorizationStatus
        self.requestResults = requestResults
    }

    func authorizationStatus() -> MicrophoneAuthorizationStatus {
        currentAuthorizationStatus
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        requestCount += 1
        completion(requestResults.first ?? false)
        if !requestResults.isEmpty {
            requestResults.removeFirst()
        }
    }
}

private final class FakeAccessibilityPermissionClient: AccessibilityPermissionClient {
    private(set) var openSettingsCount = 0
    private(set) var promptRequests: [Bool] = []

    var isTrusted: Bool
    var opensSettings: Bool

    init(isTrusted: Bool, opensSettings: Bool = false) {
        self.isTrusted = isTrusted
        self.opensSettings = opensSettings
    }

    func isProcessTrusted(promptIfNeeded: Bool) -> Bool {
        promptRequests.append(promptIfNeeded)
        return isTrusted
    }

    func openAccessibilitySettings() -> Bool {
        openSettingsCount += 1
        return opensSettings
    }
}
