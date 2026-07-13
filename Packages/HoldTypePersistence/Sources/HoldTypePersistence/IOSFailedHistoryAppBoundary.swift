import Foundation
import HoldTypeDomain

/// Opaque app-only identity for one failed History row.
public struct IOSFailedHistoryRowID: Equatable, Hashable, Sendable {
    fileprivate let rawValue: UUID

    fileprivate init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public enum IOSFailedHistoryAudioAvailability: Equatable, Sendable {
    case available
    case temporarilyUnavailable
}

/// Bounded presentation data for the containing app's History surface.
public struct IOSFailedHistoryItem: Equatable, Identifiable, Sendable {
    public let id: IOSFailedHistoryRowID
    public let failureCategory: IOSFailedHistoryFailureCategory
    public let pipelineStage: IOSFailedHistoryPipelineStage
    public let retryCount: Int32
    public let outputIntent: DictationOutputIntent
    public let transcriptionModel: String
    public let transcriptionLanguageCode: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let durationMilliseconds: Int64
    public let audioAvailability: IOSFailedHistoryAudioAvailability

    fileprivate init(entry: IOSFailedHistoryEntry) {
        id = IOSFailedHistoryRowID(rawValue: entry.attemptID)
        failureCategory = entry.failureCategory
        pipelineStage = entry.pipelineStage
        retryCount = entry.retryCount
        outputIntent = entry.outputIntent
        transcriptionModel = entry.transcriptionModel
        transcriptionLanguageCode = entry.transcriptionLanguageCode
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
        durationMilliseconds = entry.durationMilliseconds
        audioAvailability = .available
    }
}

public enum IOSFailedHistoryLoadDisposition: Equatable, Sendable {
    case available([IOSFailedHistoryItem])
    case pendingLocalRecovery
}

public enum IOSFailedHistoryMutationDisposition: Equatable, Sendable {
    case complete
    case pendingLocalRecovery
}

/// Frozen non-secret settings for one explicit Retry provider session.
@_spi(HoldTypeIOSCore)
public struct IOSFailedHistoryRetryConfiguration: Equatable, Sendable {
    public let transcriptionConfiguration: TranscriptionConfiguration
    public let transcriptionPromptComposition: TranscriptionPromptComposition
    public let textCorrectionConfiguration: TextCorrectionConfiguration
    public let postProcessingConfiguration:
        TranscriptPostProcessingConfiguration
    public let translationConfiguration: TranslationConfiguration?
    public let keepLatestResult: Bool

    public init?(
        transcriptionConfiguration: TranscriptionConfiguration,
        transcriptionPromptComposition: TranscriptionPromptComposition,
        textCorrectionConfiguration: TextCorrectionConfiguration,
        postProcessingConfiguration:
            TranscriptPostProcessingConfiguration,
        translationConfiguration: TranslationConfiguration?,
        keepLatestResult: Bool
    ) {
        guard !transcriptionConfiguration.customLanguageCodeValidation
                .isInvalid,
              IOSPendingRecordingValidation.isValidModel(
                  transcriptionConfiguration.resolvedModel
              ),
              IOSPendingRecordingValidation.isValidLanguageCode(
                  transcriptionConfiguration.resolvedLanguageCode
              ),
              transcriptionPromptComposition.contextEchoGuardText == nil,
              (!textCorrectionConfiguration.isEnabled
                  || IOSPendingRecordingValidation.isValidModel(
                      textCorrectionConfiguration.resolvedModel
                  )),
              translationConfiguration.map({ configuration in
                  configuration.canRunAction
                      && IOSPendingRecordingValidation.isValidModel(
                          configuration.resolvedModel
                      )
              }) ?? true else {
            return nil
        }
        self.transcriptionConfiguration = transcriptionConfiguration
        self.transcriptionPromptComposition =
            transcriptionPromptComposition
        self.textCorrectionConfiguration = textCorrectionConfiguration
        self.postProcessingConfiguration = postProcessingConfiguration
        self.translationConfiguration = translationConfiguration
        self.keepLatestResult = keepLatestResult
    }

    fileprivate func supports(_ outputIntent: DictationOutputIntent) -> Bool {
        switch outputIntent {
        case .standard:
            translationConfiguration == nil
        case .translate:
            translationConfiguration?.canRunAction == true
        }
    }

    fileprivate var internalSnapshot: IOSFailedHistoryRetrySetupSnapshot? {
        try? IOSFailedHistoryRetrySetupSnapshot(
            credentialEligibility: .available,
            transcriptionConfiguration: transcriptionConfiguration,
            transcriptionPromptComposition: transcriptionPromptComposition,
            textCorrectionConfiguration: textCorrectionConfiguration,
            postProcessingConfiguration: postProcessingConfiguration,
            translationConfiguration: translationConfiguration,
            keepLatestResult: keepLatestResult
        )
    }
}

/// One fresh, credential-bound provider session. The credential remains owned
/// by the provider implementation and never enters Persistence storage.
@_spi(HoldTypeIOSCore)
public struct IOSFailedHistoryRetrySession: Sendable {
    public let configuration: IOSFailedHistoryRetryConfiguration
    fileprivate let provider: any IOSFailedHistoryRetryProviderExecuting

    public init(
        configuration: IOSFailedHistoryRetryConfiguration,
        provider: any IOSFailedHistoryRetryProviderExecuting
    ) {
        self.configuration = configuration
        self.provider = provider
    }
}

@_spi(HoldTypeIOSCore)
public enum IOSFailedHistoryRetrySessionResolution: Sendable {
    case ready(IOSFailedHistoryRetrySession)
    case setupRequired(RecoveryDestination)
    case temporarilyUnavailable
    case cancelled
}

/// Process-owned containing-app factory that resolves current setup and
/// credentials for every explicit Retry request.
@_spi(HoldTypeIOSCore)
public protocol IOSFailedHistoryRetrySessionProviding: Sendable {
    func makeFailedHistoryRetrySession(
        for outputIntent: DictationOutputIntent
    ) async -> IOSFailedHistoryRetrySessionResolution
}

public enum IOSFailedHistoryRetryDisposition: Equatable, Sendable {
    case accepted
    case recoverableFailure
    case cancelled
    case setupRequired(RecoveryDestination)
    case unavailable
    case pendingLocalRecovery
}

/// App-facing failed-History facade. Durable capabilities and provider text
/// stay behind this actor and never enter the keyboard or App Group.
@_spi(HoldTypeIOSCore)
public actor IOSFailedHistoryAppBoundary {
    private let coordinator: IOSAcceptedHistoryCoordinator
    private let retrySessionProvider:
        any IOSFailedHistoryRetrySessionProviding
    private let usageRecorder: any IOSFailedHistoryRetryUsageRecording

    public init(
        applicationSupportDirectoryURL: URL,
        retrySessionProvider:
            any IOSFailedHistoryRetrySessionProviding,
        usageRecordingClient: IOSTranscriptionUsageRecordingClient
    ) {
        coordinator = IOSAcceptedHistoryCoordinator(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        self.retrySessionProvider = retrySessionProvider
        usageRecorder = usageRecordingClient
    }

    init(
        coordinator: IOSAcceptedHistoryCoordinator,
        retrySessionProvider:
            any IOSFailedHistoryRetrySessionProviding,
        usageRecorder: any IOSFailedHistoryRetryUsageRecording
    ) {
        self.coordinator = coordinator
        self.retrySessionProvider = retrySessionProvider
        self.usageRecorder = usageRecorder
    }

    public func loadFailedHistory() async -> IOSFailedHistoryLoadDisposition {
        do {
            return .available(
                try await coordinator.loadFailedHistoryItemsForContainingApp()
            )
        } catch {
            return .pendingLocalRecovery
        }
    }

    public func deleteFailedHistory(
        _ id: IOSFailedHistoryRowID
    ) async -> IOSFailedHistoryMutationDisposition {
        guard case .available(let items) = await loadFailedHistory() else {
            return .pendingLocalRecovery
        }
        guard items.contains(where: { $0.id == id }) else {
            return .complete
        }

        do {
            _ = try await coordinator.deleteFailedHistoryEntry(
                attemptID: id.rawValue
            )
            return .complete
        } catch {
            guard case .available(let refreshed) = await loadFailedHistory()
            else {
                return .pendingLocalRecovery
            }
            return refreshed.contains(where: { $0.id == id })
                ? .pendingLocalRecovery
                : .complete
        }
    }

    public func retryFailedHistory(
        _ id: IOSFailedHistoryRowID
    ) async -> IOSFailedHistoryRetryDisposition {
        let items: [IOSFailedHistoryItem]
        do {
            try Task.checkCancellation()
            items = try await coordinator.loadFailedHistoryItemsForContainingApp()
            try Task.checkCancellation()
        } catch is CancellationError {
            return .cancelled
        } catch {
            return Task.isCancelled ? .cancelled : .pendingLocalRecovery
        }
        guard let item = items.first(where: { $0.id == id }) else {
            return .unavailable
        }

        guard !Task.isCancelled else { return .cancelled }
        let sessionResolution = await retrySessionProvider
            .makeFailedHistoryRetrySession(for: item.outputIntent)
        guard !Task.isCancelled else { return .cancelled }
        let session: IOSFailedHistoryRetrySession
        switch sessionResolution {
        case .ready(let ready):
            session = ready
        case .setupRequired(let destination):
            return .setupRequired(destination)
        case .temporarilyUnavailable:
            return .unavailable
        case .cancelled:
            return .cancelled
        }

        guard session.configuration.supports(item.outputIntent),
              let setup = session.configuration.internalSnapshot else {
            return item.outputIntent == .translate
                ? .setupRequired(.translation)
                : .setupRequired(.transcription)
        }

        do {
            try Task.checkCancellation()
            let handoff = try await coordinator.prepareFailedHistoryRetry(
                attemptID: id.rawValue,
                setup: setup
            )
            let execution = try await handoff.executePipeline(
                IOSFailedHistoryRetryPipeline(
                    provider: session.provider,
                    usageRecorder: usageRecorder
                )
            )
            switch execution {
            case .failed:
                return .recoverableFailure
            case .authorizationUnavailable:
                return .setupRequired(.microphoneAndPrivacy)
            case .accepted(let output):
                switch try await output.accept() {
                case .committed, .cancelled, .notRequested:
                    return .accepted
                case .pendingLocalRecovery:
                    return .pendingLocalRecovery
                }
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
            if Task.isCancelled {
                return .cancelled
            }
            guard case .available(let refreshed) = await loadFailedHistory()
            else {
                return .pendingLocalRecovery
            }
            return refreshed.contains(where: { $0.id == id })
                ? .pendingLocalRecovery
                : .unavailable
        }
    }
}

private extension IOSAcceptedHistoryCoordinator {
    func loadFailedHistoryItemsForContainingApp()
        async throws -> [IOSFailedHistoryItem] {
        guard let pendingRecordingStore else {
            throw IOSAcceptedHistoryCoordinatorError.localRecoveryPending
        }
        let policyStore = policyStore
        let failedHistoryStore = failedHistoryStore
        let baselineRecoveryState = baselineRecoveryState
        let acceptanceState = acceptanceState
        let pendingReplacementState = pendingReplacementState
        let outboxWorkerState = outboxWorkerState
        let policyCutoverState = policyCutoverState
        let failedHistoryTransferState = failedHistoryTransferState
        let failedHistoryAudioCleanupState = failedHistoryAudioCleanupState
        let failedHistoryRetryState = failedHistoryRetryState
        let foregroundVoicePersistenceState =
            foregroundVoicePersistenceState
        let failedHistoryMutationInterlock = failedHistoryMutationInterlock
        let deliveryStore = deliveryStore
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration

        do {
            return try await operationGate.perform { authorization in
                guard await foregroundVoicePersistenceState.current() == nil
                else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                let repositoryBinding = repositoryRegistration?.revalidate()
                guard !repositoryIdentityState.isConflicted,
                      await baselineRecoveryState.value() == false else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                guard let policy = try await policyStore.load() else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                let policyReceipt = try await policyStore.confirm(
                    expected: IOSHistoryPolicyExpectation(state: policy)
                )
                let entries = try await failedHistoryStore
                    .loadPolicyFilteredEntries(
                        using: policyReceipt,
                        operationLeaseAuthorization: authorization,
                        requiringSettledRowOwnership: true
                    )
                let retainedCutover = await policyCutoverState.current()
                if entries.isEmpty,
                   Self.isCommittedLogicalEmptyRead(
                       retainedCutover,
                       matching: policyReceipt
                   ) {
                    if let repositoryBinding {
                        _ = repositoryRegistration?.revalidate(
                            expectedBinding: repositoryBinding
                        )
                    }
                    guard !repositoryIdentityState.isConflicted else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .repositoryIdentityConflict
                    }
                    return []
                }
                guard await acceptanceState.current() == nil,
                      await pendingReplacementState.current() == nil,
                      await outboxWorkerState.current() == nil,
                      retainedCutover == nil,
                      await failedHistoryTransferState.current() == nil,
                      await failedHistoryAudioCleanupState.current() == nil,
                      await failedHistoryRetryState.hasLiveOwner() == false,
                      !failedHistoryMutationInterlock.isBlocked,
                      await deliveryStore
                        .hasUncertainAcceptanceForHistoryCoordinator() == false,
                      await deliveryStore
                        .hasRetainedHistoryWorkForPolicyCutover() == false else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                let pendingObservation = try await pendingRecordingStore
                    .loadForContainingAppBoundary(
                        operationLeaseAuthorization: authorization
                    )
                guard pendingObservation?.availability != .temporarilyUnavailable,
                      pendingObservation?.availability != .missing,
                      pendingObservation?.availability != .invalid else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                guard entries.allSatisfy({
                    $0.ownershipState == .ready
                        && $0.retryOperation == nil
                }) else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                if let repositoryBinding {
                    _ = repositoryRegistration?.revalidate(
                        expectedBinding: repositoryBinding
                    )
                }
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                return entries.map(IOSFailedHistoryItem.init(entry:))
            }
        } catch IOSPersistenceOperationGate.AcquisitionError
            .cancelledBeforeLease {
            throw IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError
            .reentrantOperation {
            throw IOSAcceptedHistoryCoordinatorError.reentrantOperation
        }
    }

    static func isCommittedLogicalEmptyRead(
        _ work: IOSHistoryPolicyCutoverWork?,
        matching policy: IOSHistoryPolicyReceipt
    ) -> Bool {
        guard let work,
              work.ownerIdentity == policy.capabilityOwnerIdentity,
              work.command != nil,
              work.phase.crossedLogicalBoundary,
              let retainedPolicy = work.phase.committedPolicyReceipt else {
            return false
        }
        return retainedPolicy.capabilityOwnerIdentity
                == policy.capabilityOwnerIdentity
            && retainedPolicy.state == policy.state
    }
}

extension IOSFailedHistoryRowID: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { "IOSFailedHistoryRowID(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryAudioAvailability: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSFailedHistoryAudioAvailability(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryItem: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { "IOSFailedHistoryItem(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryLoadDisposition: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSFailedHistoryLoadDisposition(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryMutationDisposition: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSFailedHistoryMutationDisposition(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryConfiguration: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSFailedHistoryRetryConfiguration(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetrySession: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSFailedHistoryRetrySession(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetrySessionResolution:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSFailedHistoryRetrySessionResolution(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryDisposition: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSFailedHistoryRetryDisposition(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
