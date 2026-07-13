import Foundation
import Observation

/// Thread-safe exact-once storage for a MainActor scene-unregistration action.
/// Explicit retirement is synchronous. If a scene host is released from
/// another executor, deinitialization uses a supported MainActor hop.
private nonisolated final class IOSForegroundVoiceSceneHostCleanupToken:
    @unchecked Sendable {
    typealias Action = @MainActor @Sendable () -> Bool

    private let lock = NSLock()
    private var action: Action?

    init(_ action: @escaping Action) {
        self.action = action
    }

    @MainActor
    func cancel() -> Bool {
        take()?() ?? false
    }

    private func take() -> Action? {
        lock.lock()
        defer { lock.unlock() }
        let pendingAction = action
        action = nil
        return pendingAction
    }

    deinit {
        guard let action = take() else { return }
        Task { @MainActor in
            _ = action()
        }
    }
}

/// Scene-local ownership for the process-shared foreground Voice graph.
/// Construction is passive; a SwiftUI lifecycle hook must explicitly register
/// the scene before activity updates or Voice actions are admitted.
@MainActor
@Observable
final class IOSForegroundVoiceSceneHostOwner:
    CustomDebugStringConvertible,
    CustomReflectable,
    CustomStringConvertible {
    @ObservationIgnored
    private let controller: IOSForegroundVoiceController
    @ObservationIgnored
    private let sceneRegistry: IOSVoiceSceneRegistry
    private var sceneFacade: IOSVoiceSceneFacade?
    @ObservationIgnored
    private var cleanupToken: IOSForegroundVoiceSceneHostCleanupToken?
    private var isRetired = false

    init(
        controller: IOSForegroundVoiceController,
        sceneRegistry: IOSVoiceSceneRegistry
    ) {
        precondition(
            controller.sceneRegistry === sceneRegistry,
            "Scene host requires the controller's process scene registry."
        )
        self.controller = controller
        self.sceneRegistry = sceneRegistry
    }

    convenience init(runtime: IOSForegroundVoiceRuntime) {
        self.init(
            controller: runtime.controller,
            sceneRegistry: runtime.sceneRegistry
        )
    }

    var description: String { "IOSForegroundVoiceSceneHostOwner" }
    var debugDescription: String { description }

    var customMirror: Mirror {
        Mirror(self, children: ["sceneHost": "content-free"])
    }

    var isRegistered: Bool {
        sceneFacade != nil && !isRetired
    }

    var promptPresentation: IOSVoiceScenePromptPresentation {
        guard !isRetired, let sceneFacade else { return .unavailable }
        return sceneFacade.promptPresentation
    }

    var presentation: IOSForegroundVoicePresentation {
        controller.presentation
    }

    var actionCommands: [IOSForegroundVoiceActionCommand] {
        controller.actionCommands
    }

    /// Creates this host's one and only opaque scene facade. Once unregistered,
    /// the owner is permanently retired and cannot manufacture a new identity.
    @discardableResult
    func register(
        initialActivity: IOSVoiceSceneActivity = .background
    ) -> IOSVoiceSceneRegistrationMutation {
        guard !isRetired else { return .stale }
        guard sceneFacade == nil else { return .unchanged }

        let sceneFacade = sceneRegistry.registerScene(
            initialActivity: initialActivity
        )
        self.sceneFacade = sceneFacade
        cleanupToken = IOSForegroundVoiceSceneHostCleanupToken {
            sceneFacade.unregister() == .accepted
        }
        return .accepted
    }

    /// Registers on the first explicit scene lifecycle observation and updates
    /// the same opaque facade on every later observation.
    @discardableResult
    func registerOrUpdateActivity(
        _ activity: IOSVoiceSceneActivity
    ) -> IOSVoiceSceneRegistrationMutation {
        guard !isRetired else { return .stale }
        guard sceneFacade != nil else {
            return register(initialActivity: activity)
        }
        return updateActivity(activity)
    }

    @discardableResult
    func updateActivity(
        _ activity: IOSVoiceSceneActivity
    ) -> IOSVoiceSceneRegistrationMutation {
        guard !isRetired, let sceneFacade else { return .stale }
        return sceneFacade.updateActivity(activity)
    }

    /// Synchronously unregisters the exact facade at most once and permanently
    /// rejects all later lifecycle and Voice mutations from this scene host.
    @discardableResult
    func unregister() -> IOSVoiceSceneRegistrationMutation {
        guard !isRetired, sceneFacade != nil else { return .stale }
        isRetired = true
        sceneFacade = nil

        let didUnregister = cleanupToken?.cancel() ?? false
        cleanupToken = nil
        return didUnregister ? .accepted : .stale
    }

    /// All actions, including process-wide recovery actions, pass through the
    /// exact facade owned by this host. A passive or retired host cannot submit.
    @discardableResult
    func submit(
        _ command: IOSForegroundVoiceActionCommand
    ) -> IOSForegroundVoiceActionAdmission {
        guard !isRetired, let sceneFacade else { return .unavailable }
        return controller.submit(command, from: sceneFacade)
    }
}
