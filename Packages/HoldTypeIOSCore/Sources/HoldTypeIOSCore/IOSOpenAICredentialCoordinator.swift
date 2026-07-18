import Foundation
import HoldTypeOpenAI
import HoldTypePersistence

/// App-only orchestration for Keychain truth, the transient credential cache,
/// and the non-secret last-known marker.
///
/// The production composition root must create exactly one instance for the
/// app process and route every credential operation through it. Creating a
/// coordinator per scene or using its Keychain and marker adapters directly
/// would bypass this instance's transaction gate and runtime truth.
public actor IOSOpenAICredentialCoordinator {
    private enum RuntimeCache {
        case unresolved
        case available(IOSResolvedOpenAICredential)
        case knownAbsent
        case unavailableWhileLocked
    }

    private enum MarkerObservation {
        case readable(CredentialPresenceMarker?)
        case unreadable
    }

    private enum ActualPresence {
        case present
        case absent
    }

    private let keychainStorage: any OpenAIAPIKeyStoring
    private let markerStore: any IOSCredentialPresenceMarkerStoring
    private let now: @Sendable () -> Date
    private let operationGate: CredentialOperationGate

    private var runtimeCache = RuntimeCache.unresolved
    private var rejectedGeneration: IOSOpenAICredentialGeneration?
    private var unresolvedMarkerIssue:
        IOSOpenAICredentialLocalMarkerIssue?
    private var statusRevision: UInt64 = 0
    private var statusUpdateContinuations: [
        UUID: AsyncStream<IOSOpenAICredentialStatusUpdate>.Continuation
    ] = [:]

    public init(
        applicationSupportDirectoryURL: URL,
        applicationIdentifierAccessGroup: String,
        keychainAccessMode: OpenAIAPIKeyKeychainAccessMode =
            .currentProcessDefault()
    ) throws {
        keychainStorage = try OpenAIAPIKeyKeychainStorage(
            applicationIdentifierAccessGroup:
                applicationIdentifierAccessGroup,
            accessMode: keychainAccessMode
        )
        markerStore = RepositoryCredentialPresenceMarkerStore(
            repository: CredentialPresenceMarkerRepository(
                fileURL: IOSCredentialPresenceMarkerStorageLocation.fileURL(
                    in: applicationSupportDirectoryURL
                )
            )
        )
        now = { Date() }
        operationGate = CredentialOperationGate()
    }

    init(
        keychainStorage: any OpenAIAPIKeyStoring,
        markerStore: any IOSCredentialPresenceMarkerStoring,
        now: @escaping @Sendable () -> Date = { Date() },
        operationGate: CredentialOperationGate = CredentialOperationGate()
    ) {
        self.keychainStorage = keychainStorage
        self.markerStore = markerStore
        self.now = now
        self.operationGate = operationGate
    }

    /// Reads the same marker-only status plus its process-local ordering token.
    public func credentialStatusUpdate()
        -> IOSOpenAICredentialStatusUpdate {
        IOSOpenAICredentialStatusUpdate(
            revision: statusRevision,
            status: status(for: loadMarkerObservation())
        )
    }

    /// Observes payload-free process truth. Subscription reads only the local
    /// non-secret marker for its initial value; later values are event-driven
    /// and never contain a credential or generation.
    public func statusUpdates()
        -> AsyncStream<IOSOpenAICredentialStatusUpdate> {
        let identifier = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: IOSOpenAICredentialStatusUpdate.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        statusUpdateContinuations[identifier] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task {
                await self?.removeStatusUpdateContinuation(identifier)
            }
        }
        continuation.yield(credentialStatusUpdate())
        return stream
    }

    public func saveOrReplace(
        _ candidate: String
    ) async throws -> IOSOpenAICredentialMutationOutcome {
        let credential: OpenAICredential
        do {
            credential = try OpenAICredential(apiKey: candidate)
        } catch OpenAICredential.ValidationError.missingAPIKey {
            throw IOSOpenAICredentialCoordinatorError.emptyAPIKey
        } catch {
            throw IOSOpenAICredentialCoordinatorError.emptyAPIKey
        }

        return try await performExclusiveOperation { [self] in
            try await performSaveOrReplace(credential)
        }
    }

    private func performSaveOrReplace(
        _ credential: OpenAICredential
    ) async throws -> IOSOpenAICredentialMutationOutcome {
        defer { publishStatusUpdate() }
        let priorMarker = try loadReadableMarkerForMutation()
        try saveMarker(
            state: .mutationInProgress,
            mutationKind: .saveOrReplace
        )

        do {
            try await keychainStorage.saveOrReplaceAPIKey(credential.apiKey)
        } catch {
            let exactMarkerRestored = restorePriorMarker(priorMarker)
            if error is CancellationError {
                guard !exactMarkerRestored else {
                    throw CancellationError()
                }
                throw IOSOpenAICredentialCoordinatorError
                    .operationCancelledStatusNeedsRefresh
            }
            throw mappedAccessError(
                error,
                markerRestorationFailed: !exactMarkerRestored
            )
        }

        runtimeCache = .available(makeHandle(for: credential))
        rejectedGeneration = nil

        do {
            try saveMarker(state: .present)
            unresolvedMarkerIssue = nil
            return .applied
        } catch {
            return .appliedStatusNeedsRefresh
        }
    }

    public func remove() async throws -> IOSOpenAICredentialMutationOutcome {
        try await performExclusiveOperation { [self] in
            try await performRemove()
        }
    }

    private func performRemove() async throws -> IOSOpenAICredentialMutationOutcome {
        defer { publishStatusUpdate() }
        let priorMarker = try loadReadableMarkerForMutation()
        try saveMarker(
            state: .mutationInProgress,
            mutationKind: .remove
        )

        do {
            try await keychainStorage.removeAPIKey()
        } catch {
            let exactMarkerRestored = restorePriorMarker(priorMarker)
            if error is CancellationError {
                guard !exactMarkerRestored else {
                    throw CancellationError()
                }
                throw IOSOpenAICredentialCoordinatorError
                    .operationCancelledStatusNeedsRefresh
            }
            throw mappedAccessError(
                error,
                markerRestorationFailed: !exactMarkerRestored
            )
        }

        runtimeCache = .knownAbsent
        rejectedGeneration = nil

        do {
            try saveMarker(state: .absent)
            unresolvedMarkerIssue = nil
            return .applied
        } catch {
            return .appliedStatusNeedsRefresh
        }
    }

    public func resolve(
        for purpose: IOSOpenAICredentialResolutionPurpose
    ) async throws -> IOSOpenAICredentialResolutionOutcome {
        try await performExclusiveOperation { [self] in
            try await performResolve(for: purpose)
        }
    }

    private func performResolve(
        for purpose: IOSOpenAICredentialResolutionPurpose
    ) async throws -> IOSOpenAICredentialResolutionOutcome {
        do {
            let outcome = try await resolveWithoutPublishing(
                for: purpose
            )
            let statusUpdate = publishStatusUpdate(
                status: outcome.status
            ) ?? IOSOpenAICredentialStatusUpdate(
                revision: statusRevision,
                status: outcome.status
            )
            return IOSOpenAICredentialResolutionOutcome(
                resolution: outcome.resolution,
                statusUpdate: statusUpdate
            )
        } catch {
            publishStatusUpdate()
            throw error
        }
    }

    private func resolveWithoutPublishing(
        for purpose: IOSOpenAICredentialResolutionPurpose
    ) async throws -> IOSOpenAICredentialResolutionOutcome {
        let markerObservation = loadMarkerObservation()
        if purpose == .voicePreflight {
            switch runtimeCache {
            case .available(let handle):
                let markerIssue = reconcileMarker(
                    to: .present,
                    from: markerObservation
                )
                if rejectedGeneration == handle.generation {
                    throw IOSOpenAICredentialCoordinatorError.providerRejected
                }
                return makeResolutionOutcome(
                    .available(handle),
                    markerIssue: markerIssue
                )
            case .knownAbsent:
                return makeResolutionOutcome(
                    .notConfigured,
                    markerIssue: reconcileMarker(
                        to: .absent,
                        from: markerObservation
                    )
                )
            case .unresolved, .unavailableWhileLocked:
                break
            }
        }

        return try await resolveFromKeychain(markerObservation: markerObservation)
    }

    /// Records only process-local presentation state for the exact credential
    /// generation that produced the provider rejection.
    public func recordProviderRejection(
        for generation: IOSOpenAICredentialGeneration
    ) {
        guard case .available(let handle) = runtimeCache,
              handle.generation == generation else {
            return
        }

        rejectedGeneration = generation
        publishStatusUpdate()
    }

    @discardableResult
    private func publishStatusUpdate(
        status: IOSOpenAICredentialStatus? = nil
    ) -> IOSOpenAICredentialStatusUpdate? {
        guard !statusUpdateContinuations.isEmpty else {
            guard let status else { return nil }
            return IOSOpenAICredentialStatusUpdate(
                revision: statusRevision,
                status: status
            )
        }
        let resolvedStatus = status ?? credentialStatusUpdate().status
        statusRevision &+= 1
        let update = IOSOpenAICredentialStatusUpdate(
            revision: statusRevision,
            status: resolvedStatus
        )
        for continuation in statusUpdateContinuations.values {
            continuation.yield(update)
        }
        return update
    }

    private func removeStatusUpdateContinuation(_ identifier: UUID) {
        statusUpdateContinuations.removeValue(forKey: identifier)
    }

    private func resolveFromKeychain(
        markerObservation: MarkerObservation
    ) async throws -> IOSOpenAICredentialResolutionOutcome {
        let storedAPIKey: String?
        do {
            storedAPIKey = try await keychainStorage.loadAPIKey()
        } catch {
            if error is CancellationError {
                throw error
            }
            let failure = mappedAccessFailure(error)
            updateRuntimeCache(after: failure)
            throw IOSOpenAICredentialCoordinatorError.credentialAccessFailed(
                failure,
                markerRestorationFailed: false
            )
        }

        guard let storedAPIKey else {
            runtimeCache = .knownAbsent
            rejectedGeneration = nil
            return makeResolutionOutcome(
                .notConfigured,
                markerIssue: reconcileMarker(
                    to: .absent,
                    from: markerObservation
                )
            )
        }

        let credential: OpenAICredential
        do {
            credential = try OpenAICredential(apiKey: storedAPIKey)
        } catch {
            updateRuntimeCache(after: .invalidStoredCredential)
            throw IOSOpenAICredentialCoordinatorError.credentialAccessFailed(
                .invalidStoredCredential,
                markerRestorationFailed: false
            )
        }

        let handle: IOSResolvedOpenAICredential
        if case .available(let currentHandle) = runtimeCache,
           currentHandle.credential == credential {
            handle = currentHandle
        } else {
            handle = makeHandle(for: credential)
            rejectedGeneration = nil
        }
        runtimeCache = .available(handle)

        return makeResolutionOutcome(
            .available(handle),
            markerIssue: reconcileMarker(
                to: .present,
                from: markerObservation
            )
        )
    }

    private func makeResolutionOutcome(
        _ resolution: IOSOpenAICredentialResolution,
        markerIssue: IOSOpenAICredentialLocalMarkerIssue?
    ) -> IOSOpenAICredentialResolutionOutcome {
        let currentStatus = status(for: loadMarkerObservation())
        let outcomeStatus = IOSOpenAICredentialStatus(
            primary: currentStatus.primary,
            statusNeedsRefresh: currentStatus.statusNeedsRefresh,
            localMarkerIssue: markerIssue ?? currentStatus.localMarkerIssue
        )
        return IOSOpenAICredentialResolutionOutcome(
            resolution: resolution,
            status: outcomeStatus
        )
    }

    private func loadReadableMarkerForMutation() throws -> CredentialPresenceMarker? {
        do {
            return try markerStore.load()
        } catch {
            throw IOSOpenAICredentialCoordinatorError.markerUnavailable
        }
    }

    private func loadMarkerObservation() -> MarkerObservation {
        do {
            return .readable(try markerStore.load())
        } catch {
            return .unreadable
        }
    }

    private func saveMarker(
        state: CredentialPresenceMarker.State,
        mutationKind: CredentialPresenceMarker.MutationKind? = nil
    ) throws {
        let marker: CredentialPresenceMarker
        do {
            marker = try CredentialPresenceMarker(
                state: state,
                updatedAt: now(),
                mutationKind: mutationKind
            )
        } catch {
            throw IOSOpenAICredentialCoordinatorError.markerUnavailable
        }

        do {
            try markerStore.save(marker)
        } catch {
            throw IOSOpenAICredentialCoordinatorError.markerUnavailable
        }
    }

    private func restorePriorMarker(
        _ priorMarker: CredentialPresenceMarker?
    ) -> Bool {
        do {
            if let priorMarker {
                try markerStore.save(priorMarker)
            } else {
                try markerStore.removeIfPresent()
            }
            return true
        } catch {
            do {
                try saveMarker(state: .unknown)
            } catch {
                // The durable mutation marker remains fail-closed.
            }
            return false
        }
    }

    private func reconcileMarker(
        to actualPresence: ActualPresence,
        from observation: MarkerObservation
    ) -> IOSOpenAICredentialLocalMarkerIssue? {
        guard case .readable(let marker) = observation else {
            unresolvedMarkerIssue = .unavailable
            return .unavailable
        }

        let finalState: CredentialPresenceMarker.State = switch actualPresence {
        case .present:
            .present
        case .absent:
            .absent
        }

        if marker?.state == finalState {
            unresolvedMarkerIssue = nil
            return nil
        }

        switch marker?.state {
        case .unknown, .mutationInProgress:
            break
        case .present, .absent, .none:
            try? saveMarker(state: .unknown)
        }

        do {
            try saveMarker(state: finalState)
            unresolvedMarkerIssue = nil
            return nil
        } catch {
            unresolvedMarkerIssue = .unavailable
            return .unavailable
        }
    }

    private func status(
        for markerObservation: MarkerObservation
    ) -> IOSOpenAICredentialStatus {
        let marker: CredentialPresenceMarker?
        let observedMarkerIssue: IOSOpenAICredentialLocalMarkerIssue?
        switch markerObservation {
        case .readable(let readableMarker):
            marker = readableMarker
            observedMarkerIssue = nil
        case .unreadable:
            marker = nil
            observedMarkerIssue = .unavailable
        }

        let primary: IOSOpenAICredentialPrimaryStatus = switch runtimeCache {
        case .available(let handle):
            rejectedGeneration == handle.generation
                ? .providerRejected
                : .availableInThisProcess
        case .knownAbsent:
            .notConfigured
        case .unavailableWhileLocked:
            .unavailableWhileLocked
        case .unresolved:
            switch marker?.state {
            case .present:
                .savedLastKnown
            case .absent:
                .notConfigured
            case .unknown, .mutationInProgress, .none:
                .notCheckedInThisProcess
            }
        }

        let statusNeedsRefresh = switch marker?.state {
        case .unknown, .mutationInProgress:
            true
        case .present, .absent, .none:
            false
        }

        return IOSOpenAICredentialStatus(
            primary: primary,
            statusNeedsRefresh: statusNeedsRefresh,
            localMarkerIssue:
                observedMarkerIssue ?? unresolvedMarkerIssue
        )
    }

    private func makeHandle(
        for credential: OpenAICredential
    ) -> IOSResolvedOpenAICredential {
        IOSResolvedOpenAICredential(
            credential: credential,
            generation: IOSOpenAICredentialGeneration(rawValue: UUID())
        )
    }

    private func mappedAccessError(
        _ error: Error,
        markerRestorationFailed: Bool
    ) -> IOSOpenAICredentialCoordinatorError {
        .credentialAccessFailed(
            mappedAccessFailure(error),
            markerRestorationFailed: markerRestorationFailed
        )
    }

    private func mappedAccessFailure(
        _ error: Error
    ) -> IOSOpenAICredentialAccessFailure {
        guard let error = error as? OpenAIAPIKeyKeychainStorageError else {
            return .keychainFailure
        }

        switch error {
        case .unavailableWhileLocked:
            return .unavailableWhileLocked
        case .invalidResult, .invalidStoredAPIKey, .emptyAPIKey:
            return .invalidStoredCredential
        case .invalidApplicationIdentifierAccessGroup, .keychainFailure:
            return .keychainFailure
        }
    }

    private func updateRuntimeCache(
        after failure: IOSOpenAICredentialAccessFailure
    ) {
        switch (runtimeCache, failure) {
        case (.unresolved, .unavailableWhileLocked):
            runtimeCache = .unavailableWhileLocked
        case (.unavailableWhileLocked, .invalidStoredCredential),
             (.unavailableWhileLocked, .keychainFailure):
            runtimeCache = .unresolved
        case (.unresolved, .invalidStoredCredential),
             (.unresolved, .keychainFailure),
             (.available, _),
             (.knownAbsent, _),
             (.unavailableWhileLocked, .unavailableWhileLocked):
            break
        }
    }

    private func performExclusiveOperation<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            return try await operationGate.perform(operation)
        } catch CredentialOperationGate.AcquisitionError.cancelledBeforeLease {
            throw IOSOpenAICredentialCoordinatorError.operationCancelledBeforeStart
        }
    }
}

protocol IOSCredentialPresenceMarkerStoring: Sendable {
    func load() throws -> CredentialPresenceMarker?
    func save(_ marker: CredentialPresenceMarker) throws
    func removeIfPresent() throws
}

private struct RepositoryCredentialPresenceMarkerStore:
    IOSCredentialPresenceMarkerStoring
{
    let repository: CredentialPresenceMarkerRepository

    func load() throws -> CredentialPresenceMarker? {
        try repository.load()
    }

    func save(_ marker: CredentialPresenceMarker) throws {
        try repository.save(marker)
    }

    func removeIfPresent() throws {
        try repository.removeIfPresent()
    }
}

extension IOSOpenAICredentialCoordinator:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    public nonisolated var description: String {
        "IOSOpenAICredentialCoordinator(<redacted>)"
    }

    public nonisolated var debugDescription: String { description }
    public nonisolated var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}
