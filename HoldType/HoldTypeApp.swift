//
//  HoldTypeApp.swift
//  HoldType
//
//  Created by Eugene Potapenko on 6/20/26.
//

import AppKit
import Darwin
import HoldTypeOpenAI
import SwiftUI

@main
struct HoldTypeApp: App {
    @NSApplicationDelegateAdaptor(HoldTypeAppDelegate.self) private var appDelegate

    init() {
        let launchEnvironment = ProcessInfo.processInfo.environment
        let isInputMonitoringRecoveryLaunch = InputMonitoringPermissionLaunchRecovery.shouldRequest(
            environment: launchEnvironment
        )
        #if DEBUG
        let isDebugTranscriptionFailureLaunch = DebugTranscriptionFailurePromptLaunch.shouldRequest(
            environment: launchEnvironment
        )
        #else
        let isDebugTranscriptionFailureLaunch = false
        #endif

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            InputMonitoringPermissionLaunchRecovery.requestIfNeeded(environment: launchEnvironment)
        }

        if !isInputMonitoringRecoveryLaunch && !isDebugTranscriptionFailureLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(700)) {
                AppSetupController().presentSetupIfNeededForLaunch()
            }
        }

        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            DebugAccessibilityPermissionRecovery.requestIfNeeded()
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(HoldTypeMenuBarIdentity.iconAssetName)
                .renderingMode(.template)
                .accessibilityLabel(HoldTypeMenuBarIdentity.title)
                .help(HoldTypeMenuBarIdentity.helpText)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
enum InputMonitoringPermissionLaunchRecovery {
    static let requestEnvironmentKey = "HOLDTYPE_REQUEST_INPUT_MONITORING_ON_LAUNCH"
    static let openSettingsEnvironmentKey = "HOLDTYPE_OPEN_INPUT_MONITORING_SETTINGS_ON_LAUNCH"
    static let exitAfterRequestEnvironmentKey = "HOLDTYPE_EXIT_AFTER_INPUT_MONITORING_REQUEST"
    static let requestDelayAfterActivation: DispatchTimeInterval = .milliseconds(500)

    static func shouldRequest(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[requestEnvironmentKey] == "1"
    }

    static func requestIfNeeded(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        permissionService: InputMonitoringPermissionService = InputMonitoringPermissionService(),
        activateApp: () -> Void = {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        },
        scheduleRequestAfterActivation: @escaping (@escaping @MainActor () -> Void) -> Void = { request in
            DispatchQueue.main.asyncAfter(deadline: .now() + requestDelayAfterActivation) {
                Task { @MainActor in
                    request()
                }
            }
        },
        terminateProcess: @escaping () -> Void = {
            Darwin.exit(0)
        }
    ) {
        guard shouldRequest(environment: environment) else {
            return
        }

        activateApp()
        scheduleRequestAfterActivation {
            let status = permissionService.requestPermission()
            if status != .allowed || environment[openSettingsEnvironmentKey] == "1" {
                permissionService.openInputMonitoringSettings()
            }

            if environment[exitAfterRequestEnvironmentKey] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                    terminateProcess()
                }
            }
        }
    }

    static func launchFreshRequest(
        bundleURL: URL = Bundle.main.bundleURL,
        openSettings: Bool = true
    ) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-n",
            bundleURL.path,
            "--env",
            "\(requestEnvironmentKey)=1",
            "--env",
            "\(openSettingsEnvironmentKey)=\(openSettings ? "1" : "0")",
            "--env",
            "\(exitAfterRequestEnvironmentKey)=1"
        ]

        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}

#if DEBUG
@MainActor
enum DebugAccessibilityPermissionRecovery {
    static let environmentKey = "HOLDTYPE_DEBUG_REQUEST_ACCESSIBILITY"

    static func requestIfNeeded(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        permissionService: AccessibilityPermissionService = AccessibilityPermissionService()
    ) {
        guard environment[environmentKey] == "1" else {
            return
        }

        let status = permissionService.requestPermission()
        if status != .trusted {
            permissionService.openAccessibilitySettings()
        }
    }
}

@MainActor
enum DebugTranscriptionFailurePromptLaunch {
    static let environmentKey = "HOLDTYPE_DEBUG_TRANSCRIPTION_FAILURE"
    static let presentationDelay: DispatchTimeInterval = .milliseconds(500)

    static func shouldRequest(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        reason(from: environment[environmentKey]) != nil
    }

    static func requestIfNeeded(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        presentFailure: @escaping @MainActor (FailedTranscriptionReason) -> Void = { reason in
            DictationRuntime.shared.presentDebugTranscriptionFailure(reason: reason)
        },
        schedulePresentation: @escaping (@escaping @MainActor () -> Void) -> Void = { presentation in
            DispatchQueue.main.asyncAfter(deadline: .now() + presentationDelay) {
                Task { @MainActor in
                    presentation()
                }
            }
        }
    ) {
        guard let reason = reason(from: environment[environmentKey]) else {
            return
        }

        schedulePresentation {
            presentFailure(reason)
        }
    }

    static func reason(from rawValue: String?) -> FailedTranscriptionReason? {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "timeout", "timed-out", "timed_out":
            return .timedOut
        case "network", "network-unavailable", "network_unavailable":
            return .networkUnavailable
        case "network-failure", "network_failure":
            return .networkFailure
        case "invalid-api-key", "invalid_api_key", "api-key", "api_key":
            return .invalidAPIKey
        case "transcription-settings", "settings", "bad-request", "bad_request":
            return .badRequest
        default:
            return nil
        }
    }
}
#endif

@MainActor
final class HoldTypeAppDelegate: NSObject, NSApplicationDelegate {
    private let specialClipboardHotkeyCoordinator = SpecialClipboardHotkeyCoordinator()
    private let dictationRuntime = DictationRuntime.shared
    private let fixesRuntime = FixesRuntime.shared
    private let floatingIndicatorCoordinator = FloatingIndicatorCoordinator.shared
    private let quitConfirmationPresenter: any QuitConfirmationPresenting
    private let transcriptionFailurePromptCoordinator: (any TranscriptionFailurePromptCoordinating)?
    private let launchEnvironment: [String: String]
    private let clearTranscriptHistoryOverride: (@MainActor () -> Void)?
    private let startRuntimeComponentsOverride: (@MainActor () -> Void)?
    private let stopRuntimeComponentsOverride: (@MainActor () -> Void)?
    private let scheduleProviderStartupMaintenance: @MainActor () -> Void
    private let isUpdaterRelaunchInProgress: @MainActor () -> Bool
    private let repairInterruptedRecordings: @MainActor () -> Void
    private let prepareForTermination: @MainActor () async -> Void
    private let replyToTerminationRequest: @MainActor (NSApplication, Bool) -> Void
    private let terminationTimeoutNanoseconds: UInt64
    private var terminationPreparationTask: Task<Void, Never>?
    private var terminationDeadlineTask: Task<Void, Never>?
    private var isTerminationPreparationPending = false
    private var isTerminationPreparationComplete = false

    override init() {
        quitConfirmationPresenter = NativeQuitConfirmationPresenter()
        transcriptionFailurePromptCoordinator = TranscriptionFailurePromptCoordinator(
            dictationRuntime: dictationRuntime
        )
        launchEnvironment = ProcessInfo.processInfo.environment
        clearTranscriptHistoryOverride = nil
        startRuntimeComponentsOverride = nil
        stopRuntimeComponentsOverride = nil
        scheduleProviderStartupMaintenance = {
            OpenAIProviderStartupMaintenance.schedule()
        }
        isUpdaterRelaunchInProgress = {
            SoftwareUpdateRelaunchState.isUpdaterRelaunchInProgress
        }
        repairInterruptedRecordings = {
            DictationRuntime.shared.repairInterruptedRecordings()
        }
        prepareForTermination = {
            await DictationRuntime.shared.prepareForTermination()
        }
        replyToTerminationRequest = { application, shouldTerminate in
            application.reply(toApplicationShouldTerminate: shouldTerminate)
        }
        terminationTimeoutNanoseconds = 2_500_000_000
        super.init()
    }

    init(
        quitConfirmationPresenter: any QuitConfirmationPresenting,
        transcriptionFailurePromptCoordinator: (any TranscriptionFailurePromptCoordinating)? = nil,
        launchEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        clearTranscriptHistory: (@MainActor () -> Void)? = nil,
        startRuntimeComponents: (@MainActor () -> Void)? = nil,
        stopRuntimeComponents: (@MainActor () -> Void)? = nil,
        scheduleProviderStartupMaintenance: @escaping @MainActor () -> Void = {},
        isUpdaterRelaunchInProgress: @escaping @MainActor () -> Bool = {
            SoftwareUpdateRelaunchState.isUpdaterRelaunchInProgress
        },
        repairInterruptedRecordings: @escaping @MainActor () -> Void = {},
        prepareForTermination: @escaping @MainActor () async -> Void = {},
        replyToTerminationRequest: @escaping @MainActor (NSApplication, Bool) -> Void = { _, _ in },
        terminationTimeoutNanoseconds: UInt64 = 2_500_000_000
    ) {
        self.quitConfirmationPresenter = quitConfirmationPresenter
        self.transcriptionFailurePromptCoordinator = transcriptionFailurePromptCoordinator
        self.launchEnvironment = launchEnvironment
        clearTranscriptHistoryOverride = clearTranscriptHistory
        startRuntimeComponentsOverride = startRuntimeComponents
        stopRuntimeComponentsOverride = stopRuntimeComponents
        self.scheduleProviderStartupMaintenance = scheduleProviderStartupMaintenance
        self.isUpdaterRelaunchInProgress = isUpdaterRelaunchInProgress
        self.repairInterruptedRecordings = repairInterruptedRecordings
        self.prepareForTermination = prepareForTermination
        self.replyToTerminationRequest = replyToTerminationRequest
        self.terminationTimeoutNanoseconds = terminationTimeoutNanoseconds
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isInputMonitoringRecoveryLaunch else {
            return
        }

        scheduleProviderStartupMaintenance()
        repairInterruptedRecordings()
        transcriptionFailurePromptCoordinator?.start()

        if let startRuntimeComponentsOverride {
            startRuntimeComponentsOverride()
        } else {
            floatingIndicatorCoordinator.start()
            specialClipboardHotkeyCoordinator.start()
            dictationRuntime.startHotkeyListening()
            fixesRuntime.startHotkeyListening()
        }

        #if DEBUG
        DebugTranscriptionFailurePromptLaunch.requestIfNeeded(environment: launchEnvironment)
        #endif
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isTerminationPreparationComplete {
            return .terminateNow
        }
        if isTerminationPreparationPending {
            return .terminateLater
        }

        if !isUpdaterRelaunchInProgress(),
           quitConfirmationPresenter.requestQuitConfirmation() == .cancel {
            return .terminateCancel
        }

        beginTerminationPreparation(for: sender)
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !isInputMonitoringRecoveryLaunch else {
            return
        }

        if let clearTranscriptHistoryOverride {
            clearTranscriptHistoryOverride()
        } else {
            TranscriptRecoveryHistoryStore.shared.clear()
        }

        if let stopRuntimeComponentsOverride {
            stopRuntimeComponentsOverride()
        } else {
            floatingIndicatorCoordinator.stop()
            fixesRuntime.stopHotkeyListening()
            dictationRuntime.stopHotkeyListening()
            specialClipboardHotkeyCoordinator.stop()
        }

        transcriptionFailurePromptCoordinator?.stop()
    }

    private func beginTerminationPreparation(for application: NSApplication) {
        isTerminationPreparationPending = true
        terminationPreparationTask = Task { @MainActor [weak self, weak application] in
            guard let self, let application else {
                return
            }
            await self.prepareForTermination()
            self.completeTerminationPreparation(for: application)
        }
        terminationDeadlineTask = Task { @MainActor [weak self, weak application] in
            guard let self, let application else {
                return
            }
            do {
                try await Task.sleep(nanoseconds: self.terminationTimeoutNanoseconds)
            } catch {
                return
            }
            self.completeTerminationPreparation(for: application)
        }
    }

    private func completeTerminationPreparation(for application: NSApplication) {
        guard isTerminationPreparationPending else {
            return
        }

        isTerminationPreparationPending = false
        isTerminationPreparationComplete = true
        terminationPreparationTask?.cancel()
        terminationDeadlineTask?.cancel()
        terminationPreparationTask = nil
        terminationDeadlineTask = nil
        replyToTerminationRequest(application, true)
    }

    private var isInputMonitoringRecoveryLaunch: Bool {
        InputMonitoringPermissionLaunchRecovery.shouldRequest(environment: launchEnvironment)
    }
}

enum QuitConfirmationDecision: Equatable {
    case cancel
    case quit
}

enum QuitConfirmationCopy {
    static func informativeText(launchAtLoginStatus: LaunchAtLoginStatus) -> String {
        var text = """
        \(HoldTypeMenuBarIdentity.title) will stop listening for dictation shortcuts and menu bar actions until you reopen it.
        """

        if !launchAtLoginStatus.isEnabled {
            text += "\n\nRight Command dictation will not be available after restart until \(HoldTypeMenuBarIdentity.title) is opened again."
        }

        return text
    }
}

@MainActor
protocol QuitConfirmationPresenting {
    func requestQuitConfirmation() -> QuitConfirmationDecision
}

@MainActor
struct NativeQuitConfirmationPresenter: QuitConfirmationPresenting {
    private let launchAtLoginStatusProvider: @MainActor () -> LaunchAtLoginStatus

    init(
        launchAtLoginStatusProvider: @escaping @MainActor () -> LaunchAtLoginStatus = {
            LaunchAtLoginService().currentStatus()
        }
    ) {
        self.launchAtLoginStatusProvider = launchAtLoginStatusProvider
    }

    func requestQuitConfirmation() -> QuitConfirmationDecision {
        let shouldRestoreAccessoryAfterCancel = !hasVisibleAppWindow

        AppWindowActivation.showRegularApp()

        let launchAtLoginStatus = launchAtLoginStatusProvider()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quit \(HoldTypeMenuBarIdentity.title)?"
        alert.informativeText = QuitConfirmationCopy.informativeText(
            launchAtLoginStatus: launchAtLoginStatus
        )
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit \(HoldTypeMenuBarIdentity.title)")

        bringAlertToFront(alert)
        let decision: QuitConfirmationDecision = alert.runModal() == .alertSecondButtonReturn
            ? .quit
            : .cancel

        if decision == .cancel, shouldRestoreAccessoryAfterCancel {
            NSApplication.shared.setActivationPolicy(.accessory)
        }

        return decision
    }

    private func bringAlertToFront(_ alert: NSAlert) {
        let alertWindow = alert.window
        alertWindow.level = .modalPanel
        alertWindow.collectionBehavior = alertWindow.collectionBehavior.union(.moveToActiveSpace)
        alertWindow.makeKeyAndOrderFront(nil)
        alertWindow.orderFrontRegardless()
    }

    private var hasVisibleAppWindow: Bool {
        NSApplication.shared.windows.contains { window in
            window.isVisible
                && !window.isMiniaturized
                && window.canBecomeKey
        }
    }
}
