//
//  SettingsPermissionsViewModel.swift
//  HoldType
//
//  Created by Codex on 7/6/26.
//

import Combine
import Foundation
import OSLog

@MainActor
final class SettingsPermissionsViewModel: ObservableObject {
    static let inputMonitoringManualFallbackWarningThreshold = 2

    @Published private(set) var microphonePermissionStatus: MicrophonePermissionStatus
    @Published private(set) var accessibilityPermissionStatus: AccessibilityPermissionStatus
    @Published private(set) var inputMonitoringPermissionStatus: InputMonitoringPermissionStatus
    @Published private(set) var showsInputMonitoringManualFallbackWarning = false

    private let microphonePermissionService: MicrophonePermissionService
    private let accessibilityPermissionService: AccessibilityPermissionService
    private let inputMonitoringPermissionService: InputMonitoringPermissionService
    private let inputMonitoringRecoveryLauncher: @MainActor () -> Bool
    private let visiblePollingIntervalNanoseconds: UInt64
    private var visiblePollingTask: Task<Void, Never>?
    private var lastDebugSnapshot: PermissionDebugSnapshot?
    private var failedInputMonitoringActionCount = 0

    init(
        microphonePermissionService: MicrophonePermissionService,
        accessibilityPermissionService: AccessibilityPermissionService,
        inputMonitoringPermissionService: InputMonitoringPermissionService,
        inputMonitoringRecoveryLauncher: @escaping @MainActor () -> Bool = {
            InputMonitoringPermissionLaunchRecovery.launchFreshRequest()
        },
        visiblePollingIntervalNanoseconds: UInt64
    ) {
        self.microphonePermissionService = microphonePermissionService
        self.accessibilityPermissionService = accessibilityPermissionService
        self.inputMonitoringPermissionService = inputMonitoringPermissionService
        self.inputMonitoringRecoveryLauncher = inputMonitoringRecoveryLauncher
        self.visiblePollingIntervalNanoseconds = visiblePollingIntervalNanoseconds
        self.microphonePermissionStatus = microphonePermissionService.currentStatus()
        self.inputMonitoringPermissionStatus = inputMonitoringPermissionService.currentStatus()
        self.accessibilityPermissionStatus = accessibilityPermissionService.currentStatus()
    }

    func refreshOnAppearOrFocus() {
        refreshSystemPermissionStatuses()
        recordDebugSnapshot(reason: "appear-or-focus", includesSecureStorage: false)
    }

    func refreshAfterSettingsChange() {
        refreshSystemPermissionStatuses()
        recordDebugSnapshot(reason: "settings-change", includesSecureStorage: false)
    }

    func startVisiblePermissionsPolling() {
        visiblePollingTask?.cancel()
        refreshSystemPermissionStatuses()
        recordDebugSnapshot(reason: "poll-start", includesSecureStorage: false)

        let intervalNanoseconds = visiblePollingIntervalNanoseconds
        visiblePollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if intervalNanoseconds == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: intervalNanoseconds)
                }

                guard !Task.isCancelled else {
                    return
                }

                self?.refreshSystemPermissionStatuses()
                self?.recordDebugSnapshot(reason: "poll", includesSecureStorage: false)
            }
        }
    }

    func stopVisiblePermissionsPolling() {
        visiblePollingTask?.cancel()
        visiblePollingTask = nil
    }

    func handleMicrophonePermissionAction(afterPrompt: @escaping @MainActor () -> Void) {
        switch microphonePermissionStatus {
        case .allowed, .unavailable:
            refreshMicrophonePermissionStatus()
        case .denied:
            microphonePermissionService.openMicrophoneSettings()
            refreshMicrophonePermissionStatus()
        case .notDetermined:
            microphonePermissionService.requestPermission { newStatus in
                Task { @MainActor in
                    self.microphonePermissionStatus = newStatus
                    afterPrompt()
                }
            }
        }
    }

    func handleAccessibilityPermissionAction() {
        accessibilityPermissionStatus = accessibilityPermissionService.requestPermission()

        if accessibilityPermissionStatus != .trusted {
            accessibilityPermissionService.openAccessibilitySettings()
        }

        startVisiblePermissionsPolling()
    }

    func handleInputMonitoringPermissionAction() {
        switch inputMonitoringPermissionStatus {
        case .allowed:
            refreshInputMonitoringPermissionStatus()
        case .denied, .notDetermined:
            inputMonitoringPermissionStatus = inputMonitoringPermissionService.requestPermission()

            if inputMonitoringPermissionStatus != .allowed {
                failedInputMonitoringActionCount += 1
                showsInputMonitoringManualFallbackWarning = failedInputMonitoringActionCount
                    >= Self.inputMonitoringManualFallbackWarningThreshold
                _ = inputMonitoringRecoveryLauncher()
                inputMonitoringPermissionService.openInputMonitoringSettings()
            } else {
                resetInputMonitoringManualFallbackWarning()
            }

            startVisiblePermissionsPolling()
        }
    }

    private func refreshSystemPermissionStatuses() {
        refreshMicrophonePermissionStatus()
        refreshInputMonitoringPermissionStatus()
        refreshAccessibilityPermissionStatus()
    }

    private func refreshMicrophonePermissionStatus() {
        microphonePermissionStatus = microphonePermissionService.currentStatus()
    }

    private func refreshAccessibilityPermissionStatus() {
        accessibilityPermissionStatus = accessibilityPermissionService.currentStatus()
    }

    private func refreshInputMonitoringPermissionStatus() {
        inputMonitoringPermissionStatus = inputMonitoringPermissionService.currentStatus()
        if inputMonitoringPermissionStatus == .allowed {
            resetInputMonitoringManualFallbackWarning()
        }
    }

    private func resetInputMonitoringManualFallbackWarning() {
        failedInputMonitoringActionCount = 0
        showsInputMonitoringManualFallbackWarning = false
    }

    private func recordDebugSnapshot(reason: String, includesSecureStorage: Bool) {
        let snapshot = PermissionDebugSnapshot(
            microphone: microphonePermissionStatus.settingsStatusText,
            accessibility: accessibilityPermissionStatus.settingsStatusText,
            inputMonitoring: inputMonitoringPermissionStatus.settingsStatusText,
            secureStorage: includesSecureStorage ? "not-applicable" : nil
        )

        guard SettingsPermissionsDebugLogger.shouldRecord(
            snapshot: snapshot,
            previousSnapshot: lastDebugSnapshot,
            reason: reason
        ) else {
            return
        }

        lastDebugSnapshot = snapshot
        SettingsPermissionsDebugLogger.record(snapshot: snapshot, reason: reason)
    }

    deinit {
        visiblePollingTask?.cancel()
    }
}

private struct PermissionDebugSnapshot: Equatable {
    let microphone: String
    let accessibility: String
    let inputMonitoring: String
    let secureStorage: String?
}

private enum SettingsPermissionsDebugLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.holdtype.HoldType",
        category: "Permissions"
    )

    static func shouldRecord(
        snapshot: PermissionDebugSnapshot,
        previousSnapshot: PermissionDebugSnapshot?,
        reason: String
    ) -> Bool {
        guard isEnabled else {
            return false
        }

        return snapshot != previousSnapshot || reason != "poll"
    }

    static func record(snapshot: PermissionDebugSnapshot, reason: String) {
        let secureStorage = snapshot.secureStorage ?? "not-refreshed"
        logger.info(
            """
            Permission refresh: reason=\(reason, privacy: .public), \
            \(snapshot.microphone, privacy: .public), \
            \(snapshot.accessibility, privacy: .public), \
            \(snapshot.inputMonitoring, privacy: .public), \
            \(secureStorage, privacy: .public)
            """
        )
    }

    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["HOLDTYPE_DEBUG_PERMISSIONS"] == "1"
    }
}
