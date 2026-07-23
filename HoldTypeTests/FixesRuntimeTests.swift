import CoreGraphics
import Foundation
import HoldTypeDomain
import HoldTypeOpenAI
import Testing
@testable import HoldType

@MainActor
struct FixesRuntimeTests {
    @Test func captureHappensSynchronouslyBeforePalettePreparation() async throws {
        let fixture = try makeFixture()

        fixture.runtime.showPalette()

        #expect(fixture.targetClient.focusedElementCallCount == 1)
        #expect(fixture.panel.model == nil)

        try await waitUntil {
            fixture.panel.model != nil
        }
        #expect(fixture.panel.anchorRect == fixture.targetClient.state?.anchorRect)
    }

    @Test func selectedActionTransformsAndReplacesTheFrozenSource() async throws {
        let fixture = try makeFixture()
        fixture.execution.output = "\nFixed\n"
        fixture.runtime.showPalette()
        try await waitUntil {
            fixture.panel.model != nil
        }
        let model = try #require(fixture.panel.model)

        model.selectAction(id: "default.improve-writing")
        model.activateSelection()

        try await waitUntil {
            fixture.replacement.calls.count == 1
        }
        let executionCall = try #require(fixture.execution.calls.first)
        #expect(executionCall.sourceText == "selected")
        #expect(executionCall.actionID == "default.improve-writing")
        let replacementCall = try #require(fixture.replacement.calls.first)
        #expect(replacementCall.output == "\nFixed\n")
        #expect(replacementCall.snapshot.sourceText == "selected")
        #expect(fixture.panel.hideCount >= 1)
        #expect(!fixture.runtime.isPaletteVisible)
    }

    @Test func changedTextBeforeActivationFailsClosed() async throws {
        let fixture = try makeFixture()
        fixture.runtime.showPalette()
        try await waitUntil {
            fixture.panel.model != nil
        }
        let model = try #require(fixture.panel.model)
        fixture.targetClient.replaceText("prefix changed suffix")

        model.activateSelection()

        #expect(fixture.execution.calls.isEmpty)
        #expect(fixture.replacement.calls.isEmpty)
        guard case .staleTarget = model.status else {
            Issue.record("Expected stale-target presentation")
            return
        }
    }

    @Test func providerFailureAllowsRetryOnlyWhileSnapshotIsValid() async throws {
        let fixture = try makeFixture()
        fixture.execution.error = FixesRuntimeTestError.provider
        fixture.runtime.showPalette()
        try await waitUntil {
            fixture.panel.model != nil
        }
        let model = try #require(fixture.panel.model)

        model.activateSelection()

        try await waitUntil {
            if case .failure = model.status {
                return true
            }
            return false
        }
        guard case .failure(let message, let allowsRetry) = model.status else {
            Issue.record("Expected failure presentation")
            return
        }
        #expect(message == "Provider failed for this Fix.")
        #expect(allowsRetry)
        #expect(fixture.replacement.calls.isEmpty)
    }

    @Test func dismissalCancelsProviderAndLeavesSourceUntouched() async throws {
        let fixture = try makeFixture()
        fixture.execution.delay = .seconds(30)
        fixture.runtime.showPalette()
        try await waitUntil {
            fixture.panel.model != nil
        }
        let model = try #require(fixture.panel.model)
        model.activateSelection()
        try await waitUntil {
            fixture.execution.calls.count == 1
        }

        fixture.runtime.dismissPalette()

        #expect(fixture.execution.cancelCount == 1)
        #expect(fixture.replacement.calls.isEmpty)
        #expect(!fixture.runtime.isPaletteVisible)
    }

    @Test func optionJCoordinatorStartsTriggersCaptureAndStops() async throws {
        let fixture = try makeFixture()

        fixture.runtime.startHotkeyListening()
        #expect(fixture.runtime.hotkeyRegistrationStatus == .registered)
        fixture.hotkey.trigger()

        #expect(fixture.targetClient.focusedElementCallCount == 1)
        try await waitUntil {
            fixture.panel.model != nil
        }

        fixture.runtime.stopHotkeyListening()
        #expect(!fixture.hotkey.isListening)
        #expect(
            fixture.runtime.hotkeyRegistrationStatus == .notRegistered
        )
    }

    private func makeFixture() throws -> FixesRuntimeFixture {
        let token = FocusedTextElementToken()
        let state = FocusedTextElementState(
            token: token,
            processIdentifier: 101,
            text: "prefix selected suffix",
            selectedRange: NSRange(location: 7, length: 8),
            anchorRect: CGRect(x: 20, y: 40, width: 60, height: 18),
            isSecure: false
        )
        let targetClient = FixesRuntimeTargetClient(state: state)
        let targetService = FocusedTextTargetService(
            accessibilityPermissionService: AccessibilityPermissionService(
                client: FixesRuntimePermissionClient()
            ),
            client: targetClient,
            holdTypeProcessIdentifier: 999
        )
        let catalogStore = FixesRuntimeCatalogStore(catalog: .defaults)
        let replacement = FixesRuntimeReplacementService()
        let execution = FixesRuntimeExecutionService()
        let panel = FixesRuntimePanelPresenter()
        let hotkeyService = FixesRuntimeHotkeyService()
        let runtime = FixesRuntime(
            catalogStore: catalogStore,
            targetService: targetService,
            replacementService: replacement,
            executionService: execution,
            credentialResolver: FixesRuntimeCredentialResolver(),
            settingsProvider: {
                var settings = AppSettings.defaults
                settings.translationTargetLanguage = .english
                return settings
            },
            panelPresenter: panel,
            hotkeyCoordinator: FixesHotkeyCoordinator(
                hotkeyService: hotkeyService
            )
        )
        return FixesRuntimeFixture(
            runtime: runtime,
            targetClient: targetClient,
            replacement: replacement,
            execution: execution,
            panel: panel,
            hotkey: hotkeyService
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<200 {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Timed out waiting for asynchronous Fixes state")
    }
}

@MainActor
private struct FixesRuntimeFixture {
    let runtime: FixesRuntime
    let targetClient: FixesRuntimeTargetClient
    let replacement: FixesRuntimeReplacementService
    let execution: FixesRuntimeExecutionService
    let panel: FixesRuntimePanelPresenter
    let hotkey: FixesRuntimeHotkeyService
}

private actor FixesRuntimeCatalogStore: MacOSTextFixCatalogStoring {
    let catalog: TextFixCatalog

    init(catalog: TextFixCatalog) {
        self.catalog = catalog
    }

    func load() async throws -> TextFixCatalog {
        catalog
    }

    func save(_ catalog: TextFixCatalog) async throws -> TextFixCatalog {
        catalog
    }
}

@MainActor
private final class FixesRuntimeTargetClient: FocusedTextTargetClient {
    var state: FocusedTextElementState?
    private(set) var focusedElementCallCount = 0

    init(state: FocusedTextElementState) {
        self.state = state
    }

    func focusedElement() -> FocusedTextElementState? {
        focusedElementCallCount += 1
        return state
    }

    func currentState(
        for token: FocusedTextElementToken
    ) -> FocusedTextElementState? {
        state?.token == token ? state : nil
    }

    func focus(_ token: FocusedTextElementToken) -> Bool {
        state?.token == token
    }

    func setSelectedRange(
        _ range: NSRange,
        for token: FocusedTextElementToken
    ) -> Bool {
        state?.token == token
    }

    func isFocused(_ token: FocusedTextElementToken) -> Bool {
        state?.token == token
    }

    func replaceText(_ text: String) {
        guard let state else {
            return
        }
        self.state = FocusedTextElementState(
            token: state.token,
            processIdentifier: state.processIdentifier,
            text: text,
            selectedRange: state.selectedRange,
            anchorRect: state.anchorRect,
            isSecure: state.isSecure
        )
    }
}

private final class FixesRuntimePermissionClient:
    AccessibilityPermissionClient {
    func isProcessTrusted(promptIfNeeded: Bool) -> Bool {
        true
    }

    func openAccessibilitySettings() -> Bool {
        false
    }
}

@MainActor
private final class FixesRuntimeReplacementService: FocusedTextReplacing {
    struct Call {
        let snapshot: FocusedTextTargetSnapshot
        let output: String
    }

    private(set) var calls: [Call] = []

    func replace(
        snapshot: FocusedTextTargetSnapshot,
        with output: String
    ) async throws {
        calls.append(Call(snapshot: snapshot, output: output))
    }
}

@MainActor
private final class FixesRuntimeExecutionService: TextFixExecuting {
    struct Call {
        let actionID: String
        let sourceText: String
    }

    var output = "Fixed"
    var error: Error?
    var delay: Duration?
    private(set) var calls: [Call] = []
    private(set) var cancelCount = 0

    func execute(
        action: TextFixAction,
        sourceText: String,
        settings: AppSettings,
        credential: OpenAICredential
    ) async throws -> String {
        calls.append(Call(actionID: action.id, sourceText: sourceText))
        if let delay {
            try await Task.sleep(for: delay)
        }
        if let error {
            throw error
        }
        return output
    }

    func cancelActiveExecution() {
        cancelCount += 1
    }
}

@MainActor
private final class FixesRuntimePanelPresenter:
    FixesPalettePanelPresenting {
    private(set) var model: FixesPaletteModel?
    private(set) var anchorRect: CGRect?
    private(set) var hideCount = 0

    func show(
        model: FixesPaletteModel,
        accessibilityAnchorRect: CGRect?
    ) {
        self.model = model
        anchorRect = accessibilityAnchorRect
    }

    func hide() {
        hideCount += 1
        model = nil
    }
}

private struct FixesRuntimeCredentialResolver:
    OpenAICredentialResolving {
    func resolveOpenAICredential() throws -> OpenAICredential {
        try OpenAICredential(apiKey: "test-key")
    }
}

private final class FixesRuntimeHotkeyService: FixesHotkeyListening {
    private(set) var isListening = false
    private var handler: (() -> Void)?

    func start(handler: @escaping () -> Void) throws {
        self.handler = handler
        isListening = true
    }

    func stop() {
        handler = nil
        isListening = false
    }

    func trigger() {
        handler?()
    }
}

private enum FixesRuntimeTestError: Error, LocalizedError {
    case provider

    var errorDescription: String? {
        "Provider failed for this Fix."
    }
}
