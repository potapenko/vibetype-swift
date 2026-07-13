import Foundation
import Observation
import HoldTypePersistence

nonisolated struct IOSProviderConsentPrivacySnapshot: Equatable, Sendable {
    let status: IOSProviderConsentStatus
    let decisionAt: Date?
    let canResetUnreadableData: Bool
    let requiresExplicitAcceptance: Bool
}

nonisolated enum IOSProviderConsentPrivacyState: Equatable, Sendable {
    case notLoaded
    case loading
    case ready(IOSProviderConsentPrivacySnapshot)
}

nonisolated enum IOSProviderConsentPresentationOperation:
    Equatable,
    Sendable {
    case idle
    case acceptingVoice
    case decliningVoice
    case acceptingPrivacy
    case withdrawingPrivacy
    case resettingUnreadableData
}

nonisolated enum IOSProviderConsentPresentationNotice: Equatable, Sendable {
    case accepted
    case withdrawn
    case unreadableDataReset
}

nonisolated enum IOSProviderConsentPresentationFailure: Equatable, Sendable {
    case statusChanged
    case localDataUnavailable
    case decisionNotSaved
    case operationFailed
}

nonisolated struct IOSProviderConsentPromptID: Equatable, Hashable, Sendable {
    fileprivate let value: UUID
}

nonisolated enum IOSProviderConsentVoicePromptPhase: Equatable, Sendable {
    case review
    case accepting
    case declining
}

nonisolated struct IOSProviderConsentVoicePromptPresentation:
    Equatable,
    Sendable {
    let id: IOSProviderConsentPromptID
    let phase: IOSProviderConsentVoicePromptPhase
}

nonisolated enum IOSProviderConsentPrivacyAction: Equatable, Sendable {
    case acceptCurrentDisclosure
    case withdraw
    case resetUnreadableData
}

nonisolated struct IOSProviderConsentConfirmationToken:
    Equatable,
    Hashable,
    Sendable {
    fileprivate let value: UUID
}

nonisolated enum IOSProviderConsentConfirmationAdmission:
    Equatable,
    Sendable {
    case accepted
    case stale
    case unavailable
}

nonisolated struct IOSProviderConsentPresentationClient: Sendable {
    typealias Observe = @Sendable () async -> IOSProviderConsentObservation
    typealias Accept = @Sendable (
        IOSProviderConsentObservation,
        Date
    ) async throws -> IOSProviderConsentObservation
    typealias Withdraw = @Sendable (
        IOSProviderConsentObservation,
        Date,
        @escaping @Sendable () async -> Void
    ) async throws -> IOSProviderConsentObservation
    typealias Reset = @Sendable (
        IOSProviderConsentObservation,
        @escaping @Sendable () async -> Void
    ) async throws -> IOSProviderConsentObservation
    typealias IsAuthorizationReady = @Sendable (
        IOSProviderConsentObservation
    ) -> Bool
    typealias HasSameObservationAuthority = @Sendable (
        IOSProviderConsentObservation,
        IOSProviderConsentObservation
    ) -> Bool

    let observe: Observe
    let accept: Accept
    let withdraw: Withdraw
    let resetUnreadableData: Reset
    let isAuthorizationReady: IsAuthorizationReady
    let hasSameObservationAuthority: HasSameObservationAuthority

    init(
        observe: @escaping Observe,
        accept: @escaping Accept,
        withdraw: @escaping Withdraw,
        resetUnreadableData: @escaping Reset,
        isAuthorizationReady: @escaping IsAuthorizationReady,
        hasSameObservationAuthority:
            @escaping HasSameObservationAuthority
    ) {
        self.observe = observe
        self.accept = accept
        self.withdraw = withdraw
        self.resetUnreadableData = resetUnreadableData
        self.isAuthorizationReady = isAuthorizationReady
        self.hasSameObservationAuthority = hasSameObservationAuthority
    }

    init(coordinator: IOSProviderConsentCoordinator) {
        self.init(
            observe: {
                await coordinator.observe()
            },
            accept: { observation, decisionAt in
                try await coordinator.accept(
                    using: observation,
                    decisionAt: decisionAt
                )
            },
            withdraw: {
                observation,
                decisionAt,
                authorizationDidClose in
                try await coordinator.withdraw(
                    using: observation,
                    decisionAt: decisionAt,
                    authorizationDidClose: authorizationDidClose
                )
            },
            resetUnreadableData: {
                observation,
                authorizationDidClose in
                try await coordinator.resetUnreadableConsentData(
                    using: observation,
                    authorizationDidClose: authorizationDidClose
                )
            },
            isAuthorizationReady: { observation in
                coordinator.isAuthorizationReady(for: observation)
            },
            hasSameObservationAuthority: { candidate, current in
                coordinator.hasSameObservationAuthority(
                    candidate,
                    as: current
                )
            }
        )
    }
}

private nonisolated struct IOSProviderConsentPresentedObservation: Sendable {
    let observation: IOSProviderConsentObservation
    let isAuthorizationReady: Bool
}

private nonisolated struct IOSProviderConsentOperationCompletion<
    Value: Sendable
>: Sendable {
    let sequence: UInt64
    let value: Value
}

/// Process-owned presentation authority for provider-consent review and
/// mutations. Durable observations and exact scene leases remain private;
/// observable state contains only content-free UI projections.
@MainActor
@Observable
final class IOSProviderConsentPresentationOwner {
    typealias ReadMicrophoneStatus = @MainActor @Sendable () ->
        IOSMicrophonePermissionStatus
    typealias BeforePublication = @MainActor @Sendable (UInt64) async -> Void

    private final class VoiceRequest {
        let id: IOSProviderConsentPromptID
        let lease: IOSVoiceSceneStartLease
        let observation: IOSProviderConsentObservation
        var continuation: CheckedContinuation<
            IOSProviderConsentObservation?,
            Never
        >?

        init(
            id: IOSProviderConsentPromptID,
            lease: IOSVoiceSceneStartLease,
            observation: IOSProviderConsentObservation,
            continuation: CheckedContinuation<
                IOSProviderConsentObservation?,
                Never
            >
        ) {
            self.id = id
            self.lease = lease
            self.observation = observation
            self.continuation = continuation
        }
    }

    private struct PendingConfirmation {
        let token: IOSProviderConsentConfirmationToken
        let action: IOSProviderConsentPrivacyAction
        let observation: IOSProviderConsentObservation
    }

    private(set) var privacyState = IOSProviderConsentPrivacyState.notLoaded
    private(set) var microphoneStatus = IOSMicrophonePermissionStatus.unavailable
    private(set) var operation = IOSProviderConsentPresentationOperation.idle
    private(set) var notice: IOSProviderConsentPresentationNotice?
    private(set) var failure: IOSProviderConsentPresentationFailure?
    private(set) var voicePrompt: IOSProviderConsentVoicePromptPresentation?
    private(set) var confirmationRevision: UInt64 = 0

    @ObservationIgnored
    private let client: IOSProviderConsentPresentationClient
    @ObservationIgnored
    private let sceneRegistry: IOSVoiceSceneRegistry
    @ObservationIgnored
    private let readMicrophoneStatus: ReadMicrophoneStatus
    @ObservationIgnored
    private let now: @Sendable () -> Date
    @ObservationIgnored
    private let beforePublication: BeforePublication
    @ObservationIgnored
    private let invalidationRelay =
        IOSProviderConsentVoiceInvalidationRelay()
    @ObservationIgnored
    private let operationGate = IOSProviderConsentPresentationOperationGate()
    @ObservationIgnored
    private var privacyObservation: IOSProviderConsentObservation?
    @ObservationIgnored
    private var privacyAuthorizationIsReady = false
    @ObservationIgnored
    private var pendingConfirmation: PendingConfirmation?
    @ObservationIgnored
    private var voiceRequest: VoiceRequest?
    @ObservationIgnored
    private var voiceSceneSubscription: IOSVoiceSceneEventSubscription?
    @ObservationIgnored
    private var mutationTask: Task<Void, Never>?
    @ObservationIgnored
    private var activeMutationID: UUID?
    @ObservationIgnored
    private var activePrivacyLoadID: UUID?
    @ObservationIgnored
    private var lastPublishedSequence: UInt64 = 0

    init(
        client: IOSProviderConsentPresentationClient,
        sceneRegistry: IOSVoiceSceneRegistry,
        readMicrophoneStatus: @escaping ReadMicrophoneStatus,
        now: @escaping @Sendable () -> Date = { Date() },
        beforePublication: @escaping BeforePublication = { _ in }
    ) {
        self.client = client
        self.sceneRegistry = sceneRegistry
        self.readMicrophoneStatus = readMicrophoneStatus
        self.now = now
        self.beforePublication = beforePublication
    }

    convenience init(
        coordinator: IOSProviderConsentCoordinator,
        sceneRegistry: IOSVoiceSceneRegistry,
        permissionAdapter: IOSMicrophonePermissionAdapter
    ) {
        self.init(
            client: IOSProviderConsentPresentationClient(
                coordinator: coordinator
            ),
            sceneRegistry: sceneRegistry,
            readMicrophoneStatus: {
                permissionAdapter.currentStatus()
            }
        )
    }

    deinit {
        mutationTask?.cancel()
    }

    var isBusy: Bool { operation != .idle }

    func waitUntilIdle() async {
        await mutationTask?.value
    }

    func bindVoiceInvalidation(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) {
        invalidationRelay.bind(action)
    }

    /// Passive Privacy load. It reads only consent metadata and the public
    /// microphone authorization status supplied by the process adapter.
    func activatePrivacy() async {
        microphoneStatus = readMicrophoneStatus()
        if let mutationTask {
            await mutationTask.value
            return
        }
        let loadID = UUID()
        activePrivacyLoadID = loadID
        privacyState = .loading

        let client = client
        let completion = await operationGate.perform {
            let observation = await client.observe()
            return IOSProviderConsentPresentedObservation(
                observation: observation,
                isAuthorizationReady:
                    client.isAuthorizationReady(observation)
            )
        }
        guard activePrivacyLoadID == loadID,
              activeMutationID == nil else {
            return
        }
        activePrivacyLoadID = nil
        await publish(completion)
    }

    /// Voice preflight reads through this same process owner so Privacy and
    /// every scene converge on one exact observation sequence.
    func observeForVoicePreflight() async -> IOSProviderConsentObservation {
        if let mutationTask { await mutationTask.value }
        let client = client
        let completion = await operationGate.perform {
            let observation = await client.observe()
            return IOSProviderConsentPresentedObservation(
                observation: observation,
                isAuthorizationReady:
                    client.isAuthorizationReady(observation)
            )
        }
        await publish(completion)
        return completion.value.observation
    }

    /// Suspends one explicit Start until the exact initiating scene decides.
    /// The continuation is never transferred to another scene.
    func continueVoiceStart(
        lease: IOSVoiceSceneStartLease,
        observation: IOSProviderConsentObservation
    ) async -> IOSProviderConsentObservation? {
        guard operation == .idle,
              voiceRequest == nil,
              privacyObservation.map({ current in
                  client.hasSameObservationAuthority(
                      observation,
                      current
                  )
              }) == true,
              Self.canOfferReview(
                  for: observation,
                  isAuthorizationReady: privacyAuthorizationIsReady
              ),
              sceneRegistry.validateContinuation(lease) == .ready,
              !Task.isCancelled else {
            return nil
        }

        let id = IOSProviderConsentPromptID(value: UUID())
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled,
                      operation == .idle,
                      voiceRequest == nil,
                      sceneRegistry.validateContinuation(lease) == .ready else {
                    continuation.resume(returning: nil)
                    return
                }
                voiceRequest = VoiceRequest(
                    id: id,
                    lease: lease,
                    observation: observation,
                    continuation: continuation
                )
                voiceSceneSubscription = sceneRegistry.observeEvents {
                    [weak self] event in
                    self?.receiveSceneEvent(event)
                }
                voicePrompt = IOSProviderConsentVoicePromptPresentation(
                    id: id,
                    phase: .review
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishVoiceRequest(id: id, result: nil)
            }
        }
    }

    func isVoicePrompt(
        _ id: IOSProviderConsentPromptID,
        ownedBy sceneHost: IOSForegroundVoiceSceneHostOwner
    ) -> Bool {
        voicePrompt?.id == id
            && sceneHost.promptPresentation == .ownedByThisScene
    }

    func acceptVoicePrompt(
        _ id: IOSProviderConsentPromptID,
        from capability: IOSVoiceScenePromptDecisionCapability
    ) {
        guard operation == .idle,
              let request = voiceRequest,
              request.id == id,
              sceneRegistry.validatePromptDecision(
                  capability,
                  for: request.lease
              ),
              sceneRegistry.validateContinuation(request.lease) == .ready else {
            return
        }
        beginMutation(.acceptingVoice) { [weak self] mutationID in
            guard let self else { return }
            if self.voiceRequest === request {
                self.voicePrompt = IOSProviderConsentVoicePromptPresentation(
                    id: id,
                    phase: .accepting
                )
            }
            do {
                let client = self.client
                let decisionAt = self.now()
                let observation = request.observation
                let completion = try await self.operationGate.perform {
                    let accepted = try await client.accept(
                        observation,
                        decisionAt
                    )
                    return IOSProviderConsentPresentedObservation(
                        observation: accepted,
                        isAuthorizationReady:
                            client.isAuthorizationReady(accepted)
                    )
                }
                await self.completeVoiceMutation(
                    mutationID: mutationID,
                    request: request,
                    result: completion,
                    notice: .accepted
                )
            } catch {
                await self.failVoiceMutation(
                    mutationID: mutationID,
                    request: request,
                    error: error
                )
            }
        }
    }

    func acceptVoicePrompt(
        _ id: IOSProviderConsentPromptID,
        from sceneHost: IOSForegroundVoiceSceneHostOwner
    ) {
        guard let capability = sceneHost.promptDecisionCapability() else {
            return
        }
        acceptVoicePrompt(id, from: capability)
    }

    func declineVoicePrompt(
        _ id: IOSProviderConsentPromptID,
        from capability: IOSVoiceScenePromptDecisionCapability
    ) {
        guard operation == .idle,
              let request = voiceRequest,
              request.id == id,
              sceneRegistry.validatePromptDecision(
                  capability,
                  for: request.lease
              ),
              sceneRegistry.validateContinuation(request.lease) == .ready else {
            return
        }
        beginMutation(.decliningVoice) { [weak self] mutationID in
            guard let self else { return }
            if self.voiceRequest === request {
                self.voicePrompt = IOSProviderConsentVoicePromptPresentation(
                    id: id,
                    phase: .declining
                )
            }
            do {
                let client = self.client
                let decisionAt = self.now()
                let observation = request.observation
                let relay = self.invalidationRelay
                let completion = try await self.operationGate.perform {
                    let withdrawn = try await client.withdraw(
                        observation,
                        decisionAt,
                        relay.signal
                    )
                    return IOSProviderConsentPresentedObservation(
                        observation: withdrawn,
                        isAuthorizationReady:
                            client.isAuthorizationReady(withdrawn)
                    )
                }
                await self.completeVoiceMutation(
                    mutationID: mutationID,
                    request: request,
                    result: nil,
                    publishedObservation: completion,
                    notice: .withdrawn
                )
            } catch {
                await self.failVoiceMutation(
                    mutationID: mutationID,
                    request: request,
                    error: error
                )
            }
        }
    }

    func declineVoicePrompt(
        _ id: IOSProviderConsentPromptID,
        from sceneHost: IOSForegroundVoiceSceneHostOwner
    ) {
        guard let capability = sceneHost.promptDecisionCapability() else {
            return
        }
        declineVoicePrompt(id, from: capability)
    }

    func dismissVoicePrompt(
        _ id: IOSProviderConsentPromptID,
        from capability: IOSVoiceScenePromptDecisionCapability
    ) {
        guard operation == .idle,
              let request = voiceRequest,
              request.id == id,
              sceneRegistry.validatePromptDecision(
                  capability,
                  for: request.lease
              ) else {
            return
        }
        finishVoiceRequest(id: id, result: nil)
    }

    func dismissVoicePrompt(
        _ id: IOSProviderConsentPromptID,
        from sceneHost: IOSForegroundVoiceSceneHostOwner
    ) {
        guard let capability = sceneHost.promptDecisionCapability() else {
            return
        }
        dismissVoicePrompt(id, from: capability)
    }

    func makePrivacyConfirmation(
        for action: IOSProviderConsentPrivacyAction
    ) -> IOSProviderConsentConfirmationToken? {
        guard operation == .idle,
              let observation = privacyObservation,
              Self.canPerform(
                  action,
                  using: observation,
                  isAuthorizationReady: privacyAuthorizationIsReady
              ) else {
            return nil
        }
        let token = IOSProviderConsentConfirmationToken(value: UUID())
        replacePendingConfirmation(PendingConfirmation(
            token: token,
            action: action,
            observation: observation
        ))
        return token
    }

    func isPrivacyConfirmationCurrent(
        _ token: IOSProviderConsentConfirmationToken
    ) -> Bool {
        _ = confirmationRevision
        return operation == .idle
            && pendingConfirmation?.token == token
    }

    @discardableResult
    func confirmPrivacyAction(
        _ token: IOSProviderConsentConfirmationToken
    ) -> IOSProviderConsentConfirmationAdmission {
        guard operation == .idle else { return .unavailable }
        guard let confirmation = pendingConfirmation,
              confirmation.token == token else {
            return .stale
        }
        replacePendingConfirmation(nil)
        finishVoiceRequest(result: nil)

        let nextOperation: IOSProviderConsentPresentationOperation = switch
            confirmation.action {
        case .acceptCurrentDisclosure:
            .acceptingPrivacy
        case .withdraw:
            .withdrawingPrivacy
        case .resetUnreadableData:
            .resettingUnreadableData
        }
        beginMutation(nextOperation) { [weak self] mutationID in
            guard let self else { return }
            do {
                let result: IOSProviderConsentOperationCompletion<
                    IOSProviderConsentPresentedObservation
                >
                let notice: IOSProviderConsentPresentationNotice
                let client = self.client
                let decisionAt = self.now()
                let observation = confirmation.observation
                let relay = self.invalidationRelay
                switch confirmation.action {
                case .acceptCurrentDisclosure:
                    result = try await self.operationGate.perform {
                        let accepted = try await client.accept(
                            observation,
                            decisionAt
                        )
                        return IOSProviderConsentPresentedObservation(
                            observation: accepted,
                            isAuthorizationReady:
                                client.isAuthorizationReady(accepted)
                        )
                    }
                    notice = .accepted
                case .withdraw:
                    result = try await self.operationGate.perform {
                        let withdrawn = try await client.withdraw(
                            observation,
                            decisionAt,
                            relay.signal
                        )
                        return IOSProviderConsentPresentedObservation(
                            observation: withdrawn,
                            isAuthorizationReady:
                                client.isAuthorizationReady(withdrawn)
                        )
                    }
                    notice = .withdrawn
                case .resetUnreadableData:
                    result = try await self.operationGate.perform {
                        let reset = try await client.resetUnreadableData(
                            observation,
                            relay.signal
                        )
                        return IOSProviderConsentPresentedObservation(
                            observation: reset,
                            isAuthorizationReady:
                                client.isAuthorizationReady(reset)
                        )
                    }
                    notice = .unreadableDataReset
                }
                await self.completePrivacyMutation(
                    mutationID: mutationID,
                    result: result,
                    notice: notice
                )
            } catch {
                await self.failPrivacyMutation(
                    mutationID: mutationID,
                    error: error
                )
            }
        }
        return .accepted
    }

    private func beginMutation(
        _ nextOperation: IOSProviderConsentPresentationOperation,
        operation body: @escaping @MainActor @Sendable (UUID) async -> Void
    ) {
        guard operation == .idle, mutationTask == nil else { return }
        activePrivacyLoadID = nil
        replacePendingConfirmation(nil)
        notice = nil
        failure = nil
        operation = nextOperation
        let mutationID = UUID()
        activeMutationID = mutationID
        mutationTask = Task { @MainActor in
            await body(mutationID)
        }
    }

    private func completeVoiceMutation(
        mutationID: UUID,
        request: VoiceRequest,
        result: IOSProviderConsentOperationCompletion<
            IOSProviderConsentPresentedObservation
        >?,
        publishedObservation: IOSProviderConsentOperationCompletion<
            IOSProviderConsentPresentedObservation
        >? = nil,
        notice: IOSProviderConsentPresentationNotice
    ) async {
        guard activeMutationID == mutationID else { return }
        if let publication = publishedObservation ?? result {
            await publish(publication)
        }
        self.notice = notice
        finishMutation(mutationID)

        let continuationResult: IOSProviderConsentObservation?
        if let result,
           voiceRequest === request,
           sceneRegistry.validateContinuation(request.lease) == .ready {
            continuationResult = result.value.observation
        } else {
            continuationResult = nil
        }
        finishVoiceRequest(id: request.id, result: continuationResult)
    }

    private func failVoiceMutation(
        mutationID: UUID,
        request: VoiceRequest,
        error: Error
    ) async {
        let client = client
        let refreshed = await operationGate.perform {
            let observation = await client.observe()
            return IOSProviderConsentPresentedObservation(
                observation: observation,
                isAuthorizationReady:
                    client.isAuthorizationReady(observation)
            )
        }
        guard activeMutationID == mutationID else { return }
        await publish(refreshed)
        failure = Self.map(error)
        finishMutation(mutationID)
        finishVoiceRequest(id: request.id, result: nil)
    }

    private func completePrivacyMutation(
        mutationID: UUID,
        result: IOSProviderConsentOperationCompletion<
            IOSProviderConsentPresentedObservation
        >,
        notice: IOSProviderConsentPresentationNotice
    ) async {
        guard activeMutationID == mutationID else { return }
        await publish(result)
        self.notice = notice
        finishMutation(mutationID)
    }

    private func failPrivacyMutation(
        mutationID: UUID,
        error: Error
    ) async {
        let client = client
        let refreshed = await operationGate.perform {
            let observation = await client.observe()
            return IOSProviderConsentPresentedObservation(
                observation: observation,
                isAuthorizationReady:
                    client.isAuthorizationReady(observation)
            )
        }
        guard activeMutationID == mutationID else { return }
        await publish(refreshed)
        failure = Self.map(error)
        finishMutation(mutationID)
    }

    private func finishMutation(_ mutationID: UUID) {
        guard activeMutationID == mutationID else { return }
        activeMutationID = nil
        mutationTask = nil
        operation = .idle
    }

    private func publish(
        _ completion: IOSProviderConsentOperationCompletion<
            IOSProviderConsentPresentedObservation
        >
    ) async {
        await beforePublication(completion.sequence)
        guard completion.sequence > lastPublishedSequence else { return }
        lastPublishedSequence = completion.sequence
        publish(completion.value)
    }

    private func publish(_ presented: IOSProviderConsentPresentedObservation) {
        let observation = presented.observation
        privacyObservation = observation
        privacyAuthorizationIsReady = presented.isAuthorizationReady
        replacePendingConfirmation(nil)
        privacyState = .ready(
            IOSProviderConsentPrivacySnapshot(
                status: observation.status,
                decisionAt: observation.decisionAt,
                canResetUnreadableData:
                    observation.canResetUnreadableData,
                requiresExplicitAcceptance:
                    observation.status == .acceptedCurrentDisclosure
                        && !presented.isAuthorizationReady
            )
        )
    }

    private func replacePendingConfirmation(
        _ next: PendingConfirmation?
    ) {
        pendingConfirmation = next
        confirmationRevision &+= 1
    }

    private func receiveSceneEvent(_ event: IOSVoiceSceneRegistryEvent) {
        guard sceneRegistry.validate(event) else { return }
        if case .initiatingSceneBecameUnavailable = event.kind {
            finishVoiceRequest(result: nil)
        }
    }

    private func finishVoiceRequest(
        id: IOSProviderConsentPromptID? = nil,
        result: IOSProviderConsentObservation?
    ) {
        guard let request = voiceRequest,
              id == nil || request.id == id else {
            return
        }
        voiceRequest = nil
        voicePrompt = nil
        voiceSceneSubscription?.cancel()
        voiceSceneSubscription = nil
        let continuation = request.continuation
        request.continuation = nil
        continuation?.resume(returning: result)
    }

    private static func canOfferReview(
        for observation: IOSProviderConsentObservation,
        isAuthorizationReady: Bool
    ) -> Bool {
        switch observation.status {
        case .notReviewed, .reviewRequired, .withdrawn:
            true
        case .acceptedCurrentDisclosure:
            !isAuthorizationReady
        case .localDataUnavailable, .mutationNotSaved:
            false
        }
    }

    private static func canPerform(
        _ action: IOSProviderConsentPrivacyAction,
        using observation: IOSProviderConsentObservation,
        isAuthorizationReady: Bool
    ) -> Bool {
        switch action {
        case .acceptCurrentDisclosure:
            return canOfferReview(
                for: observation,
                isAuthorizationReady: isAuthorizationReady
            )
        case .withdraw:
            return observation.status == .acceptedCurrentDisclosure
        case .resetUnreadableData:
            return observation.canResetUnreadableData
        }
    }

    private static func map(_ error: Error)
        -> IOSProviderConsentPresentationFailure {
        guard let error = error as? IOSProviderConsentError else {
            return .operationFailed
        }
        return switch error {
        case .staleObservation:
            .statusChanged
        case .localDataUnavailable, .commitUncertain:
            .localDataUnavailable
        case .mutationNotSaved, .unreadableDataRequiresReset,
             .resetRequiresUnreadableObservation, .revisionOverflow,
             .invalidDisclosureVersion:
            .decisionNotSaved
        }
    }
}

private actor IOSProviderConsentPresentationOperationGate {
    private var isOwned = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var completionSequence: UInt64 = 0

    func perform<Result: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Result
    ) async rethrows -> IOSProviderConsentOperationCompletion<Result> {
        await acquire()
        defer { release() }
        let value = try await operation()
        completionSequence += 1
        return IOSProviderConsentOperationCompletion(
            sequence: completionSequence,
            value: value
        )
    }

    private func acquire() async {
        guard isOwned else {
            isOwned = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isOwned = false
            return
        }
        waiters.removeFirst().resume()
    }
}

private nonisolated final class IOSProviderConsentVoiceInvalidationRelay:
    @unchecked Sendable {
    private let lock = NSLock()
    private var action: (@MainActor @Sendable () -> Void)?

    func bind(_ action: @escaping @MainActor @Sendable () -> Void) {
        lock.withLock { self.action = action }
    }

    func signal() async {
        let action: (@MainActor @Sendable () -> Void)? = lock.withLock {
            self.action
        }
        guard let action else { return }
        await action()
    }
}

extension IOSProviderConsentPresentationOwner:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSProviderConsentPresentationOwner(<redacted>)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSProviderConsentPrivacySnapshot:
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    nonisolated var description: String { Self.redactedDescription }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
    private nonisolated static let redactedDescription =
        "IOSProviderConsentPrivacySnapshot(<redacted>)"
}

extension IOSProviderConsentPrivacyState:
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    nonisolated var description: String {
        "IOSProviderConsentPrivacyState(<redacted>)"
    }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSProviderConsentPresentationOperation:
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    nonisolated var description: String {
        "IOSProviderConsentPresentationOperation(<redacted>)"
    }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSProviderConsentPresentationNotice:
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    nonisolated var description: String {
        "IOSProviderConsentPresentationNotice(<redacted>)"
    }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSProviderConsentPresentationFailure:
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    nonisolated var description: String {
        "IOSProviderConsentPresentationFailure(<redacted>)"
    }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSProviderConsentPromptID:
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    nonisolated var description: String {
        "IOSProviderConsentPromptID(<redacted>)"
    }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSProviderConsentVoicePromptPhase:
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    nonisolated var description: String {
        "IOSProviderConsentVoicePromptPhase(<redacted>)"
    }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSProviderConsentVoicePromptPresentation:
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    nonisolated var description: String {
        "IOSProviderConsentVoicePromptPresentation(<redacted>)"
    }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSProviderConsentPrivacyAction:
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    nonisolated var description: String {
        "IOSProviderConsentPrivacyAction(<redacted>)"
    }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSProviderConsentConfirmationToken:
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    nonisolated var description: String {
        "IOSProviderConsentConfirmationToken(<redacted>)"
    }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSProviderConsentPresentationClient:
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    nonisolated var description: String {
        "IOSProviderConsentPresentationClient(<redacted>)"
    }
    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}
