//
//  DictationRuntimeTests.swift
//  HoldTypeTests
//
//  Created by Codex on 7/6/26.
//

import Foundation
import HoldTypeDomain
import Security
import Testing
@testable import HoldType

@MainActor
struct DictationRuntimeTests {
    @Test func startHotkeyListeningRegistersServiceAndPublishesStatus() {
        let hotkeyService = FakeGlobalHotkeyService()
        let runtime = DictationRuntime(hotkeyService: hotkeyService)

        runtime.startHotkeyListening()

        #expect(hotkeyService.startListeningCount == 1)
        #expect(runtime.preferredHotkeyConfiguration == .defaultDictation)
        #expect(runtime.hotkeyRegistrationStatus == .registered(.defaultDictation))
    }

    @Test func startHotkeyListeningPublishesRegistrationFailure() {
        let hotkeyService = FakeGlobalHotkeyService(
            startListeningResult: .failure(
                .registrationUnavailable(message: "Input Monitoring unavailable.")
            )
        )
        let runtime = DictationRuntime(hotkeyService: hotkeyService)

        runtime.startHotkeyListening()

        #expect(hotkeyService.startListeningCount == 1)
        #expect(
            runtime.hotkeyRegistrationStatus == .unavailable(
                message: "Input Monitoring unavailable."
            )
        )
    }

    @Test func stopHotkeyListeningUnregistersServiceAndPublishesNotRegistered() {
        let hotkeyService = FakeGlobalHotkeyService()
        let runtime = DictationRuntime(hotkeyService: hotkeyService)

        runtime.startHotkeyListening()
        runtime.stopHotkeyListening()

        #expect(hotkeyService.stopListeningCount == 1)
        #expect(runtime.hotkeyRegistrationStatus == .notRegistered)
    }

    @Test func firstTimeMicrophoneDenialOpensSettingsAfterSystemPrompt() async {
        let settingsPresenter = SpyRuntimeSettingsPresenter()
        let microphoneClient = FakeRuntimeMicrophonePermissionClient(
            status: .notDetermined,
            requestResults: [false]
        )
        let runtime = DictationRuntime(
            appSettingsStore: AppSettingsStore(userDefaults: makeTestUserDefaults()),
            recordingSetupPreflight: RecordingSetupPreflight(
                setupStatusProvider: makeSetupStatusProvider(
                    microphoneClient: microphoneClient,
                    accessibilityTrusted: false,
                    inputMonitoringAuthorizationStatus: .allowed
                ),
                apiKeyStorage: FakeRuntimeAPIKeyStorage(availability: .saved)
            ),
            settingsPresenter: settingsPresenter,
            hotkeyService: FakeGlobalHotkeyService()
        )

        await runtime.performRecordingAction()

        #expect(microphoneClient.requestCount == 1)
        #expect(settingsPresenter.systemPromptFocusedItems == [.permissions])
        #expect(settingsPresenter.menuDismissalFocusedItems.isEmpty)
    }

    @Test func firstTimeMicrophoneGrantContinuesToOpenAIKeyPreflight() async {
        let settingsPresenter = SpyRuntimeSettingsPresenter()
        let microphoneClient = FakeRuntimeMicrophonePermissionClient(
            status: .notDetermined,
            requestResults: [true]
        )
        let runtime = DictationRuntime(
            appSettingsStore: AppSettingsStore(userDefaults: makeTestUserDefaults()),
            recordingSetupPreflight: RecordingSetupPreflight(
                setupStatusProvider: makeSetupStatusProvider(
                    microphoneClient: microphoneClient,
                    accessibilityTrusted: true,
                    inputMonitoringAuthorizationStatus: .allowed
                ),
                apiKeyStorage: FakeRuntimeAPIKeyStorage(availability: .missing)
            ),
            settingsPresenter: settingsPresenter,
            hotkeyService: FakeGlobalHotkeyService()
        )

        await runtime.performRecordingAction()

        #expect(microphoneClient.requestCount == 1)
        #expect(settingsPresenter.menuDismissalFocusedItems == [.openAI])
        #expect(settingsPresenter.systemPromptFocusedItems.isEmpty)
    }

    @Test func deniedMicrophonePreflightOpensSettingsWithoutPromptRequest() async {
        let settingsPresenter = SpyRuntimeSettingsPresenter()
        let microphoneClient = FakeRuntimeMicrophonePermissionClient(
            status: .denied,
            requestResults: [true]
        )
        let runtime = DictationRuntime(
            appSettingsStore: AppSettingsStore(userDefaults: makeTestUserDefaults()),
            recordingSetupPreflight: RecordingSetupPreflight(
                setupStatusProvider: makeSetupStatusProvider(
                    microphoneClient: microphoneClient,
                    accessibilityTrusted: true,
                    inputMonitoringAuthorizationStatus: .allowed
                ),
                apiKeyStorage: FakeRuntimeAPIKeyStorage(availability: .saved)
            ),
            settingsPresenter: settingsPresenter,
            hotkeyService: FakeGlobalHotkeyService()
        )

        await runtime.performRecordingAction()

        #expect(microphoneClient.requestCount == 0)
        #expect(settingsPresenter.menuDismissalFocusedItems == [.permissions])
        #expect(settingsPresenter.systemPromptFocusedItems.isEmpty)
    }

    @Test func openAIKeyPreflightOpensSettingsOpenAIAfterMenuDismissal() async {
        let settingsPresenter = SpyRuntimeSettingsPresenter()
        let runtime = DictationRuntime(
            appSettingsStore: AppSettingsStore(userDefaults: makeTestUserDefaults()),
            recordingSetupPreflight: RecordingSetupPreflight(
                setupStatusProvider: makeSetupStatusProvider(
                    microphoneAuthorizationStatus: .allowed,
                    accessibilityTrusted: true,
                    inputMonitoringAuthorizationStatus: .allowed
                ),
                apiKeyStorage: FakeRuntimeAPIKeyStorage(availability: .missing)
            ),
            settingsPresenter: settingsPresenter,
            hotkeyService: FakeGlobalHotkeyService()
        )

        await runtime.performRecordingAction()

        #expect(settingsPresenter.menuDismissalFocusedItems == [.openAI])
    }

    @Test func missingTranslationTargetOpensTranslationSettingsBeforeCredentialRecovery() async {
        let settingsPresenter = SpyRuntimeSettingsPresenter()
        let runtime = DictationRuntime(
            appSettingsStore: AppSettingsStore(userDefaults: makeTestUserDefaults()),
            recordingSetupPreflight: RecordingSetupPreflight(
                setupStatusProvider: makeSetupStatusProvider(
                    microphoneAuthorizationStatus: .allowed,
                    accessibilityTrusted: true,
                    inputMonitoringAuthorizationStatus: .allowed
                ),
                apiKeyStorage: FakeRuntimeAPIKeyStorage(availability: .missing)
            ),
            settingsPresenter: settingsPresenter,
            hotkeyService: FakeGlobalHotkeyService()
        )

        await runtime.performRecordingAction(intent: .translate)

        #expect(settingsPresenter.menuDismissalFocusedItems == [.translation])
        #expect(runtime.status == .failure(message: "Choose a target language in Translation settings."))
        #expect(runtime.failurePresentation?.title == "Translation settings need attention")
        #expect(runtime.failurePresentation?.settingsTarget == .translation)
    }

    @Test func dismissFailurePresentationClearsPreflightFailureStatus() async {
        let runtime = DictationRuntime(
            appSettingsStore: AppSettingsStore(userDefaults: makeTestUserDefaults()),
            recordingSetupPreflight: RecordingSetupPreflight(
                setupStatusProvider: makeSetupStatusProvider(
                    microphoneAuthorizationStatus: .allowed,
                    accessibilityTrusted: true,
                    inputMonitoringAuthorizationStatus: .allowed
                ),
                apiKeyStorage: FakeRuntimeAPIKeyStorage(availability: .missing)
            ),
            settingsPresenter: SpyRuntimeSettingsPresenter(),
            hotkeyService: FakeGlobalHotkeyService()
        )

        await runtime.performRecordingAction()
        runtime.dismissFailurePresentation()

        #expect(runtime.status == .idle)
        #expect(runtime.failurePresentation == nil)
    }

    @Test func inaccessibleAPIKeyPreflightOpensSettingsOpenAIWithoutRecording() async {
        let settingsPresenter = SpyRuntimeSettingsPresenter()
        let message = KeychainService.inaccessibleAPIKeyMessage
        let runtime = DictationRuntime(
            appSettingsStore: AppSettingsStore(userDefaults: makeTestUserDefaults()),
            recordingSetupPreflight: RecordingSetupPreflight(
                setupStatusProvider: makeSetupStatusProvider(
                    microphoneAuthorizationStatus: .allowed,
                    accessibilityTrusted: true,
                    inputMonitoringAuthorizationStatus: .allowed
                ),
                apiKeyStorage: FakeRuntimeAPIKeyStorage(
                    availability: .unavailable(message)
                )
            ),
            settingsPresenter: settingsPresenter,
            hotkeyService: FakeGlobalHotkeyService()
        )

        await runtime.performRecordingAction()

        #expect(settingsPresenter.menuDismissalFocusedItems == [.openAI])
        #expect(runtime.status == .failure(message: message))
    }

    @Test func pasteLastResultUsesStoredResultWhenSettingIsEnabled() async {
        let transcriptClipboardStore = FakeRuntimeTranscriptClipboardStore(initialText: "stored result")
        let textEventPoster = FakeRuntimeTextEventPoster()
        let pasteService = SpecialClipboardPasteService(
            transcriptClipboardStore: transcriptClipboardStore,
            accessibilityPermissionService: AccessibilityPermissionService(
                client: FakeRuntimeAccessibilityPermissionClient(isTrusted: true)
            ),
            textEventPoster: textEventPoster
        )
        let runtime = DictationRuntime(
            appSettingsStore: AppSettingsStore(userDefaults: makeTestUserDefaults()),
            hotkeyService: FakeGlobalHotkeyService(),
            pasteLastResultService: pasteService,
            transcriptClipboardStore: transcriptClipboardStore
        )

        await yieldUntil { runtime.isLastResultPasteAvailable }
        await runtime.pasteLastResult()

        #expect(runtime.isLastResultPasteAvailable)
        #expect(runtime.outputStatusText == "Inserted last result.")
        #expect(await textEventPoster.postedTexts() == ["stored result"])
    }

    @Test func retryCredentialFailureShowsRecoveryPromptWithoutOpeningSettings() async throws {
        let failedAttemptID = try #require(UUID(uuidString: "742C5C58-5C7F-4780-A21C-CC2AC3D03D4E"))
        let settingsPresenter = SpyRuntimeSettingsPresenter()
        let runtime = DictationRuntime(
            credentialResolver: FakeRuntimeCredentialResolver(result: .failure(.missingAPIKey)),
            settingsPresenter: settingsPresenter,
            hotkeyService: FakeGlobalHotkeyService()
        )

        await runtime.retryFailedTranscription(id: failedAttemptID)

        #expect(settingsPresenter.menuDismissalFocusedItems.isEmpty)
        #expect(runtime.status == .failure(message: "Enter an OpenAI API key before transcribing."))
        #expect(runtime.failurePresentation?.settingsTarget == .openAI)
        #expect(runtime.failurePresentation?.failedAttemptID == failedAttemptID)
        #expect(runtime.failurePresentation?.canRetry == true)
    }

    private func makeTestUserDefaults() -> UserDefaults {
        let userDefaults = UserDefaults(
            suiteName: "holdtype.DictationRuntimeTests.\(UUID().uuidString)"
        )
        #expect(userDefaults != nil)
        return userDefaults!
    }

    private func yieldUntil(_ condition: @escaping @MainActor () async -> Bool) async {
        for _ in 0..<20 {
            if await condition() {
                return
            }

            await Task.yield()
        }
    }

    private func makeSetupStatusProvider(
        microphoneAuthorizationStatus: MicrophoneAuthorizationStatus,
        accessibilityTrusted: Bool,
        inputMonitoringAuthorizationStatus: InputMonitoringAuthorizationStatus
    ) -> AppSetupStatusProvider {
        makeSetupStatusProvider(
            microphoneClient: FakeRuntimeMicrophonePermissionClient(
                status: microphoneAuthorizationStatus
            ),
            accessibilityTrusted: accessibilityTrusted,
            inputMonitoringAuthorizationStatus: inputMonitoringAuthorizationStatus
        )
    }

    private func makeSetupStatusProvider(
        microphoneClient: any MicrophonePermissionClient,
        accessibilityTrusted: Bool,
        inputMonitoringAuthorizationStatus: InputMonitoringAuthorizationStatus
    ) -> AppSetupStatusProvider {
        AppSetupStatusProvider(
            microphonePermissionService: MicrophonePermissionService(
                client: microphoneClient
            ),
            accessibilityPermissionService: AccessibilityPermissionService(
                client: FakeRuntimeAccessibilityPermissionClient(
                    isTrusted: accessibilityTrusted
                )
            ),
            inputMonitoringPermissionService: InputMonitoringPermissionService(
                client: FakeRuntimeInputMonitoringPermissionClient(
                    status: inputMonitoringAuthorizationStatus
                )
            )
        )
    }
}

@MainActor
private final class SpyRuntimeSettingsPresenter: SetupSettingsPresenting {
    private(set) var showFocusedItems: [SettingsNavigationItem?] = []
    private(set) var menuDismissalFocusedItems: [SettingsNavigationItem?] = []
    private(set) var systemPromptFocusedItems: [SettingsNavigationItem?] = []

    func show(focusing item: SettingsNavigationItem?) {
        showFocusedItems.append(item)
    }

    func showAfterMenuDismissal(focusing item: SettingsNavigationItem?) {
        menuDismissalFocusedItems.append(item)
    }

    func showAfterSystemPermissionPrompt(focusing item: SettingsNavigationItem?) {
        systemPromptFocusedItems.append(item)
    }
}

private struct FakeRuntimeAPIKeyStorage: APIKeyStorage {
    let availability: APIKeyAvailability

    func saveAPIKey(_ apiKey: String) throws {}

    func loadAPIKey() throws -> String? {
        if case .unavailable = availability {
            throw KeychainServiceError.unhandledKeychainStatus(errSecInteractionNotAllowed)
        }

        return availability.allowsTranscription ? "sk-test" : nil
    }

    func deleteAPIKey() throws {}

    func apiKeyAvailability() throws -> APIKeyAvailability {
        availability
    }
}

private struct FakeRuntimeCredentialResolver: OpenAICredentialResolving {
    let result: Result<String, OpenAICredentialResolutionError>

    func resolveOpenAICredential() throws -> OpenAICredential {
        try OpenAICredential(apiKey: result.get())
    }
}

private final class FakeRuntimeMicrophonePermissionClient: MicrophonePermissionClient {
    var hasAvailableAudioInput = true
    private(set) var requestCount = 0
    private var requestResults: [Bool]
    var status: MicrophoneAuthorizationStatus

    init(status: MicrophoneAuthorizationStatus, requestResults: [Bool] = []) {
        self.status = status
        self.requestResults = requestResults
    }

    func authorizationStatus() -> MicrophoneAuthorizationStatus {
        status
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        requestCount += 1
        let result = requestResults.isEmpty ? status == .allowed : requestResults.removeFirst()
        status = result ? .allowed : .denied
        completion(result)
    }
}

private struct FakeRuntimeAccessibilityPermissionClient: AccessibilityPermissionClient {
    let isTrusted: Bool

    func isProcessTrusted(promptIfNeeded: Bool) -> Bool {
        isTrusted
    }

    func openAccessibilitySettings() -> Bool {
        true
    }
}

private struct FakeRuntimeInputMonitoringPermissionClient: InputMonitoringPermissionClient {
    let status: InputMonitoringAuthorizationStatus

    func authorizationStatus() -> InputMonitoringAuthorizationStatus {
        status
    }

    func requestAccess() -> Bool {
        status == .allowed
    }

    func openInputMonitoringSettings() -> Bool {
        true
    }
}

private actor FakeRuntimeTranscriptClipboardStore: TranscriptClipboardStoring {
    private var text: String?

    init(initialText: String? = nil) {
        self.text = initialText
    }

    func save(_ text: String) async throws {
        self.text = text
    }

    func clear() async {
        text = nil
    }

    func currentText() async -> String? {
        text
    }
}

private actor FakeRuntimeTextEventPoster: TextEventPosting {
    private var texts: [String] = []

    func postText(_ text: String) async throws {
        texts.append(text)
    }

    func postedTexts() -> [String] {
        texts
    }
}
