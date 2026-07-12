import Foundation

public enum IOSContainingAppRecoveryOpportunity: Equatable, Sendable {
    case processLaunch
    case foreground
}

public enum IOSContainingAppRecoveryDisposition: Equatable, Sendable {
    case complete
    case pendingLocalRecovery
}

public extension IOSAcceptedHistoryCoordinator {
    /// Runs one ordered, provider-free containing-app recovery opportunity.
    /// A later lifecycle event owns any remaining work; this method never
    /// loops or schedules itself.
    func recoverContainingAppLifecycle(
        _ opportunity: IOSContainingAppRecoveryOpportunity
    ) async -> IOSContainingAppRecoveryDisposition {
        guard !Task.isCancelled else {
            return .pendingLocalRecovery
        }
        guard await foregroundVoicePersistenceState.current() == nil else {
            return .pendingLocalRecovery
        }

        do {
            if opportunity == .processLaunch {
                let hasRetainedPolicyCutover =
                    await policyCutoverState.current() != nil
                if !hasRetainedPolicyCutover {
                    guard try await recoverInterruptedFailedHistoryRetry()
                        == .noWork else {
                        return .pendingLocalRecovery
                    }
                }
            }

            let historyCleanup = if opportunity == .processLaunch {
                try await recoverHistoryPolicyCleanupForContainingAppLaunch()
            } else {
                try await recoverHistoryPolicyCleanup()
            }
            guard historyCleanup == .complete else {
                return .pendingLocalRecovery
            }

            if try await recoverAcceptedHistory() == .pendingLocalRecovery {
                return .pendingLocalRecovery
            }

            guard opportunity == .processLaunch else {
                return .complete
            }
            guard let pendingRecordingStore else {
                return .pendingLocalRecovery
            }
            guard let observation = try await pendingRecordingStore.load()
            else {
                return .complete
            }
            switch observation.recording.phase {
            case .readyForTranscription, .awaitingRecovery:
                return observation.availability == .available
                    ? .complete
                    : .pendingLocalRecovery
            case .transcribing, .postProcessing, .outputDelivery:
                _ = try await pendingRecordingStore
                    .recoverContainingAppAfterProcessLoss(
                        expected: observation.expectation
                    )
                return .complete
            }
        } catch {
            return .pendingLocalRecovery
        }
    }
}

extension IOSContainingAppRecoveryOpportunity: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSContainingAppRecoveryOpportunity(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSContainingAppRecoveryDisposition: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSContainingAppRecoveryDisposition(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
