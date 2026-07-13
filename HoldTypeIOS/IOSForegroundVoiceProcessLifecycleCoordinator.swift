import Foundation
@_spi(HoldTypeIOSCore) import HoldTypePersistence

nonisolated struct IOSForegroundVoiceLifecycleRefresh: Sendable {
    let observation: IOSForegroundVoiceObservation
    let disposition: IOSV1ContainingAppRecoveryDisposition
}

/// The single process owner that binds lifecycle recovery to controller
/// publication. Construction is passive; only an explicit scheduler signal
/// starts work.
@MainActor
final class IOSForegroundVoiceProcessLifecycleCoordinator {
    typealias Refresh = @MainActor @Sendable (
        IOSV1ContainingAppRecoveryOpportunity
    ) async -> IOSForegroundVoiceLifecycleRefresh

    private let controller: IOSForegroundVoiceController
    private let refresh: Refresh

    init(
        workflow: IOSForegroundVoiceWorkflow,
        controller: IOSForegroundVoiceController
    ) {
        self.controller = controller
        refresh = { [workflow] opportunity in
            await workflow.recoverLifecycle(opportunity)
        }
    }

    init(
        controller: IOSForegroundVoiceController,
        refresh: @escaping Refresh
    ) {
        self.controller = controller
        self.refresh = refresh
    }

    func recover(
        _ opportunity: IOSV1ContainingAppRecoveryOpportunity
    ) async -> IOSV1ContainingAppRecoveryDisposition {
        await controller.performLifecycleRefresh {
            [refresh] in
            await refresh(opportunity)
        }
    }

    var schedulerRecovery: IOSContainingAppLifecycleScheduler.Recovery {
        { [weak self] opportunity in
            guard let self else { return .pendingLocalRecovery }
            return await self.recover(opportunity)
        }
    }
}

extension IOSForegroundVoiceProcessLifecycleCoordinator:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSForegroundVoiceProcessLifecycleCoordinator(<redacted>)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceLifecycleRefresh:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSForegroundVoiceLifecycleRefresh(<redacted>)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
