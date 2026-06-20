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
