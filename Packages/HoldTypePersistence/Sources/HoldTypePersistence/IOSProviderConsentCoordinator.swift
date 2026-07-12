import Darwin
import Foundation

/// The containing process's single owner for provider-consent observation,
/// compare-and-swap mutation, and short-lived provider authority.
public final class IOSProviderConsentCoordinator: @unchecked Sendable {
    public static let currentDisclosureVersion: Int64 = 1

    private let owner: IOSProviderConsentOwner
    private let gate: IOSProviderConsentAuthorizationGate
    private let repositoryGuard:
        IOSAcceptedHistoryCoordinatorRepositoryGuard?
    private let expectedRepositoryRootIdentity:
        IOSPersistenceRepositoryRootIdentity?

    public convenience init() {
        self.init(
            bootstrappingApplicationSupportDirectoryURL:
                Self.canonicalApplicationSupportDirectoryURL,
            registry: .shared
        )
    }

    convenience init(
        bootstrappingApplicationSupportDirectoryURL: URL,
        registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry,
        beforeRegistryPin: @escaping @Sendable () -> Void = {}
    ) {
        let bootstrapIdentity = Self.bootstrapApplicationSupportDirectory(
            at: bootstrappingApplicationSupportDirectoryURL
        )
        beforeRegistryPin()
        self.init(
            applicationSupportDirectoryURL:
                bootstrappingApplicationSupportDirectoryURL,
            registry: registry
        )
        let guardIdentity: IOSPersistenceRepositoryRootIdentity?
        do {
            guardIdentity = try repositoryGuard?.revalidate()
                .physicalRootIdentity
        } catch {
            guardIdentity = nil
        }
        let finalIdentity = Self.verifiedApplicationSupportDirectoryIdentity(
            at: bootstrappingApplicationSupportDirectoryURL
        )
        if bootstrapIdentity == nil
            || expectedRepositoryRootIdentity != bootstrapIdentity
            || guardIdentity != bootstrapIdentity
            || finalIdentity != bootstrapIdentity {
            repositoryGuard?.invalidate()
            gate.close()
        }
    }

    init(
        applicationSupportDirectoryURL: URL,
        registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry = .shared
    ) {
        let context = registry.context(for: applicationSupportDirectoryURL)
        owner = context.providerConsentOwner
        gate = context.providerConsentAuthorizationGate
        repositoryGuard = context.repositoryGuard
        expectedRepositoryRootIdentity =
            context.repositoryBinding.physicalRootIdentity
    }

    init(
        journal: any IOSProviderConsentJournalStoring,
        currentDisclosureVersion: Int64 =
            IOSProviderConsentCoordinator.currentDisclosureVersion,
        makeEpochID: @escaping @Sendable () -> UUID = { UUID() },
        expectedRepositoryRootIdentity:
            IOSPersistenceRepositoryRootIdentity? = nil,
        repositoryAdmissionRevalidation:
            @escaping @Sendable () throws
                -> IOSPersistenceRepositoryRootIdentity? = { nil },
        providerAdmissionInterposition:
            @escaping @Sendable () -> Void = {}
    ) {
        owner = IOSProviderConsentOwner(
            journal: journal,
            currentDisclosureVersion: currentDisclosureVersion,
            makeEpochID: makeEpochID,
            expectedRepositoryRootIdentity:
                expectedRepositoryRootIdentity,
            repositoryAdmissionRevalidation:
                repositoryAdmissionRevalidation,
            providerAdmissionInterposition:
                providerAdmissionInterposition
        )
        gate = IOSProviderConsentAuthorizationGate()
        repositoryGuard = nil
        self.expectedRepositoryRootIdentity =
            expectedRepositoryRootIdentity
    }

    /// Passive observation; no authorization is returned or implicitly dispatched.
    public func observe() async -> IOSProviderConsentObservation {
        let fence = gate.currentFence()
        let observation = await owner.observe()
        guard revalidateRepositoryOrCloseGate() else {
            return observation.repositoryUnavailable(
                at: gate.currentFence()
            )
        }
        let observationFence = gate.adoptPassively(
            binding: authorizationBinding(for: observation),
            ifFenceIs: fence
        )
        return observation.observed(at: observationFence)
    }

    @discardableResult
    public func accept(
        using observation: IOSProviderConsentObservation,
        decisionAt: Date = Date()
    ) async throws -> IOSProviderConsentObservation {
        guard revalidateRepositoryOrCloseGate() else {
            throw IOSProviderConsentError.localDataUnavailable
        }
        guard let observationFence = observation.gateFence,
              let fence = gate.currentFence(
                  matching: observationFence
              ) else {
            throw IOSProviderConsentError.staleObservation
        }
        do {
            let saved = try await owner.accept(
                using: observation,
                decisionAt: decisionAt,
                observedAt: fence,
                gate: gate
            )
            guard revalidateRepositoryOrCloseGate() else {
                throw IOSProviderConsentError.localDataUnavailable
            }
            guard let resultingFence = gate.adoptAfterExplicitAcceptance(
                binding: authorizationBinding(for: saved),
                ifFenceIs: fence
            ) else {
                throw IOSProviderConsentError.staleObservation
            }
            return saved.observed(at: resultingFence)
        } catch {
            gate.close(ifFenceIs: fence)
            throw error
        }
    }

    /// Closes provider authority synchronously before repository ownership can suspend.
    @discardableResult
    public func withdraw(
        using observation: IOSProviderConsentObservation,
        decisionAt: Date = Date()
    ) async throws -> IOSProviderConsentObservation {
        guard revalidateRepositoryOrCloseGate() else {
            throw IOSProviderConsentError.localDataUnavailable
        }
        guard let observationFence = observation.gateFence,
              let closedFence = gate.close(observedAt: observationFence) else {
            throw IOSProviderConsentError.staleObservation
        }
        let saved = try await owner.withdraw(
            using: observation,
            decisionAt: decisionAt
        )
        guard revalidateRepositoryOrCloseGate() else {
            throw IOSProviderConsentError.localDataUnavailable
        }
        let resultingFence = gate.adoptPassively(
            binding: authorizationBinding(for: saved),
            ifFenceIs: closedFence
        )
        return saved.observed(at: resultingFence)
    }

    /// Deletes only the exact unreadable physical revision in the observation.
    @discardableResult
    public func resetUnreadableConsentData(
        using observation: IOSProviderConsentObservation
    ) async throws -> IOSProviderConsentObservation {
        guard revalidateRepositoryOrCloseGate() else {
            throw IOSProviderConsentError.localDataUnavailable
        }
        guard let observationFence = observation.gateFence,
              let closedFence = gate.close(observedAt: observationFence) else {
            throw IOSProviderConsentError.staleObservation
        }
        let saved = try await owner.resetUnreadable(using: observation)
        guard revalidateRepositoryOrCloseGate() else {
            throw IOSProviderConsentError.localDataUnavailable
        }
        let resultingFence = gate.adoptPassively(
            binding: authorizationBinding(for: saved),
            ifFenceIs: closedFence
        )
        return saved.observed(at: resultingFence)
    }

    public func makeAuthorization(
        from observation: IOSProviderConsentObservation
    ) -> IOSProviderConsentAuthorization? {
        guard revalidateRepositoryOrCloseGate(),
              let observationFence = observation.gateFence,
              let binding = authorizationBinding(for: observation) else {
            return nil
        }
        return gate.makeAuthorization(
            for: binding,
            observedAt: observationFence
        )
    }

    /// Registers cancellation before a provider task is allowed to launch.
    public func registerProviderDispatch(
        _ authorization: IOSProviderConsentAuthorization,
        for stage: IOSProviderConsentProviderStage,
        onCancellation: @escaping @Sendable () -> Void
    ) async -> IOSProviderConsentDispatchRegistration? {
        await owner.registerProviderDispatch(
            authorization,
            stage: stage,
            onCancellation: onCancellation,
            gate: gate
        )
    }

    /// Atomically linearizes a synchronous provider-task launch against
    /// withdrawal. The closure must only start an already prepared task and
    /// must not suspend. Synchronous cancellation or invalidation requested
    /// through this coordinator is deferred until the callback returns.
    @discardableResult
    public func launchProviderDispatch(
        _ registration: IOSProviderConsentDispatchRegistration,
        launch: @Sendable () -> Void
    ) async -> Bool {
        guard await owner.prepareProviderDispatchLaunch(
            registration,
            gate: gate
        ) else {
            return false
        }
        gate.performPreparedDispatchLaunch(launch)
        return true
    }

    public func cancelProviderDispatch(
        _ registration: IOSProviderConsentDispatchRegistration
    ) {
        guard revalidateRepositoryOrCloseGate() else { return }
        gate.cancelDispatch(registration)
    }

    /// Converts a completed, still-authorized provider dispatch into one
    /// result capability. Withdrawal cancels either side of this handoff.
    public func finishProviderDispatch(
        _ registration: IOSProviderConsentDispatchRegistration,
        onResultCancellation: @escaping @Sendable () -> Void
    ) async -> IOSProviderConsentResultAuthorization? {
        await owner.finishProviderDispatch(
            registration,
            onResultCancellation: onResultCancellation,
            gate: gate
        )
    }

    /// Runs one non-suspending local result commit while holding the consent
    /// fence. Returning successfully consumes the capability; a thrown local
    /// error leaves it available for an idempotent retry.
    public func consumeProviderResult<T: Sendable>(
        _ authorization: IOSProviderConsentResultAuthorization,
        perform operation: @Sendable () throws -> T
    ) async rethrows -> T? {
        guard await owner.prepareProviderResultConsumption(
            authorization,
            gate: gate
        ) else {
            return nil
        }
        return try gate.performPreparedResultConsumption(
            authorization,
            operation: operation
        )
    }

    public func abandonProviderResult(
        _ authorization: IOSProviderConsentResultAuthorization
    ) {
        guard revalidateRepositoryOrCloseGate() else { return }
        gate.abandonResult(authorization)
    }

    /// Retires every dispatch and response token without mutating durable consent.
    public func invalidateProviderAuthorizations() {
        gate.close()
    }

#if DEBUG
    func testingCurrentGateFence() -> IOSProviderConsentObservationFence {
        gate.currentFence()
    }
#endif

    static var canonicalApplicationSupportDirectoryURL: URL {
        URL.applicationSupportDirectory
    }

    static func bootstrapApplicationSupportDirectory(
        at applicationSupportDirectoryURL: URL
    ) -> IOSPersistenceRepositoryRootIdentity? {
        let root = applicationSupportDirectoryURL.absoluteURL
            .standardizedFileURL
        let name = root.lastPathComponent
        guard root.isFileURL,
              !root.path.isEmpty,
              name != ".",
              name != "..",
              !name.isEmpty,
              !name.contains("/"),
              !name.utf8.contains(0) else {
            return nil
        }
        let parentURL = root.deletingLastPathComponent()
        let parent = parentURL.path.withCString {
            Darwin.open(
                $0,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard parent >= 0 else { return nil }
        defer { Darwin.close(parent) }

        var parentStatus = stat()
        guard Darwin.fstat(parent, &parentStatus) == 0,
              parentStatus.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              parentStatus.st_uid == Darwin.geteuid(),
              parentStatus.st_mode & mode_t(0o022) == 0 else {
            return nil
        }

        let creation = createDirectoryIfMissing(
            named: name,
            parent: parent
        )
        guard creation != .failed else { return nil }
        let descriptor = name.withCString {
            Darwin.openat(
                parent,
                $0,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        if creation == .created,
           Darwin.fchmod(descriptor, mode_t(0o700)) != 0 {
            return nil
        }
        guard let identity = validatedBootstrapDirectoryIdentity(
            descriptor: descriptor,
            requiresOwnerOnlyMode: creation == .created
        ), pathMatchesBootstrapDirectory(
            named: name,
            parent: parent,
            identity: identity
        ) else {
            return nil
        }

        if creation == .created {
            guard synchronizeBootstrapDirectory(descriptor),
                  synchronizeBootstrapDirectory(parent),
                  pathMatchesBootstrapDirectory(
                      named: name,
                      parent: parent,
                      identity: identity
                  ) else {
                return nil
            }
        }
        return identity
    }

    private enum BootstrapDirectoryCreation {
        case created
        case existing
        case failed
    }

    private static func createDirectoryIfMissing(
        named name: String,
        parent: Int32
    ) -> BootstrapDirectoryCreation {
        var interruptedCount = 0
        while true {
            let result = name.withCString {
                Darwin.mkdirat(parent, $0, mode_t(0o700))
            }
            if result == 0 { return .created }
            if errno == EEXIST { return .existing }
            if errno == EINTR, interruptedCount < 8 {
                interruptedCount += 1
                continue
            }
            return .failed
        }
    }

    private static func validatedBootstrapDirectoryIdentity(
        descriptor: Int32,
        requiresOwnerOnlyMode: Bool
    ) -> IOSPersistenceRepositoryRootIdentity? {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              status.st_uid == Darwin.geteuid(),
              status.st_mode & mode_t(0o022) == 0,
              !requiresOwnerOnlyMode
                || status.st_mode & mode_t(0o7777) == mode_t(0o700) else {
            return nil
        }
        return IOSPersistenceRepositoryRootIdentity(
            device: status.st_dev,
            inode: status.st_ino
        )
    }

    private static func pathMatchesBootstrapDirectory(
        named name: String,
        parent: Int32,
        identity: IOSPersistenceRepositoryRootIdentity
    ) -> Bool {
        var status = stat()
        let result = name.withCString {
            Darwin.fstatat(parent, $0, &status, AT_SYMLINK_NOFOLLOW)
        }
        return result == 0
            && status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
            && status.st_uid == Darwin.geteuid()
            && IOSPersistenceRepositoryRootIdentity(
                device: status.st_dev,
                inode: status.st_ino
            ) == identity
    }

    private static func verifiedApplicationSupportDirectoryIdentity(
        at applicationSupportDirectoryURL: URL
    ) -> IOSPersistenceRepositoryRootIdentity? {
        let root = applicationSupportDirectoryURL.absoluteURL
            .standardizedFileURL
        let name = root.lastPathComponent
        guard root.isFileURL,
              !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.utf8.contains(0) else {
            return nil
        }
        let parentURL = root.deletingLastPathComponent()
        let parent = parentURL.path.withCString {
            Darwin.open(
                $0,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard parent >= 0 else { return nil }
        defer { Darwin.close(parent) }
        var parentStatus = stat()
        guard Darwin.fstat(parent, &parentStatus) == 0,
              parentStatus.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              parentStatus.st_uid == Darwin.geteuid(),
              parentStatus.st_mode & mode_t(0o022) == 0 else {
            return nil
        }
        let descriptor = name.withCString {
            Darwin.openat(
                parent,
                $0,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        guard let identity = validatedBootstrapDirectoryIdentity(
            descriptor: descriptor,
            requiresOwnerOnlyMode: false
        ), pathMatchesBootstrapDirectory(
            named: name,
            parent: parent,
            identity: identity
        ) else {
            return nil
        }
        return identity
    }

    private static func synchronizeBootstrapDirectory(
        _ descriptor: Int32
    ) -> Bool {
        var interruptedCount = 0
        while true {
            if Darwin.fsync(descriptor) == 0 { return true }
            if errno == EINTR, interruptedCount < 8 {
                interruptedCount += 1
                continue
            }
            return false
        }
    }

    private func authorizationBinding(
        for observation: IOSProviderConsentObservation
    ) -> IOSProviderConsentAuthorizationBinding? {
        observation.authorizationBinding?.bound(
            to: expectedRepositoryRootIdentity
        )
    }

    @discardableResult
    private func revalidateRepositoryOrCloseGate() -> Bool {
        guard let repositoryGuard else { return true }
        do {
            _ = try repositoryGuard.revalidate()
            return true
        } catch {
            gate.close()
            return false
        }
    }
}

extension IOSProviderConsentCoordinator:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { "IOSProviderConsentCoordinator(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

actor IOSProviderConsentOwner {
    private enum UncertainIntent: Equatable, Sendable {
        case mutation(
            source: IOSProviderConsentJournalSnapshot?,
            intended: IOSProviderConsentRecord
        )
        case reset(source: IOSProviderConsentJournalSnapshot)
    }

    private let journal: any IOSProviderConsentJournalStoring
    private let currentDisclosureVersion: Int64
    private let makeEpochID: @Sendable () -> UUID
    private let expectedRepositoryRootIdentity:
        IOSPersistenceRepositoryRootIdentity?
    private let repositoryAdmissionRevalidation:
        @Sendable () throws -> IOSPersistenceRepositoryRootIdentity?
    private let providerAdmissionInterposition: @Sendable () -> Void
    private let identity = IOSProviderConsentOwnerIdentity()
    private var uncertainIntent: UncertainIntent?
    private var authorizationConfirmedSnapshot:
        IOSProviderConsentJournalSnapshot?

    init(
        journal: any IOSProviderConsentJournalStoring,
        currentDisclosureVersion: Int64,
        makeEpochID: @escaping @Sendable () -> UUID = { UUID() },
        expectedRepositoryRootIdentity:
            IOSPersistenceRepositoryRootIdentity? = nil,
        repositoryAdmissionRevalidation:
            @escaping @Sendable () throws
                -> IOSPersistenceRepositoryRootIdentity? = { nil },
        providerAdmissionInterposition:
            @escaping @Sendable () -> Void = {}
    ) {
        self.journal = journal
        self.currentDisclosureVersion = currentDisclosureVersion
        self.makeEpochID = makeEpochID
        self.expectedRepositoryRootIdentity =
            expectedRepositoryRootIdentity
        self.repositoryAdmissionRevalidation =
            repositoryAdmissionRevalidation
        self.providerAdmissionInterposition =
            providerAdmissionInterposition
    }

    func observe() -> IOSProviderConsentObservation {
        guard currentDisclosureVersion > 0 else {
            return unavailableObservation()
        }
        do {
            if let uncertainIntent {
                return try resolveUncertainObservation(uncertainIntent)
            }
            return try observationAfterDurabilityConfirmation(
                for: journal.load()
            )
        } catch {
            return unavailableObservation()
        }
    }

    func accept(
        using observation: IOSProviderConsentObservation,
        decisionAt: Date,
        observedAt gateFence: IOSProviderConsentObservationFence,
        gate: IOSProviderConsentAuthorizationGate
    ) throws -> IOSProviderConsentObservation {
        let saved = try gate.withSealedMutation(
            observedAt: gateFence
        ) {
            try acceptWithoutMutationFence(
                using: observation,
                decisionAt: decisionAt
            )
        }
        guard let saved else {
            throw IOSProviderConsentError.staleObservation
        }
        return saved
    }

    private func acceptWithoutMutationFence(
        using observation: IOSProviderConsentObservation,
        decisionAt: Date
    ) throws -> IOSProviderConsentObservation {
        try requireValidDisclosureVersion()
        let current = try currentSnapshot(matching: observation)

        switch current?.content {
        case .unreadable:
            throw IOSProviderConsentError.unreadableDataRequiresReset
        case .readable(let record)
            where record.state == .accepted
                && record.disclosureVersion == currentDisclosureVersion:
            return try observationAfterDurabilityConfirmation(for: current)
        case .readable(let record):
            let intended = try successor(
                of: record,
                state: .accepted,
                decisionAt: decisionAt
            )
            return try replace(
                intended,
                source: try requireSnapshot(current)
            )
        case nil:
            let intended = try firstRecord(
                state: .accepted,
                decisionAt: decisionAt
            )
            return try create(intended)
        }
    }

    func withdraw(
        using observation: IOSProviderConsentObservation,
        decisionAt: Date
    ) throws -> IOSProviderConsentObservation {
        try requireValidDisclosureVersion()
        let current = try currentSnapshot(matching: observation)

        switch current?.content {
        case .unreadable:
            throw IOSProviderConsentError.unreadableDataRequiresReset
        case .readable(let record) where record.state == .withdrawn:
            return self.observation(for: current)
        case .readable(let record):
            let intended = try successor(
                of: record,
                state: .withdrawn,
                decisionAt: decisionAt
            )
            return try replace(
                intended,
                source: try requireSnapshot(current)
            )
        case nil:
            let intended = try firstRecord(
                state: .withdrawn,
                decisionAt: decisionAt
            )
            return try create(intended)
        }
    }

    func resetUnreadable(
        using observation: IOSProviderConsentObservation
    ) throws -> IOSProviderConsentObservation {
        try requireOwned(observation)
        guard uncertainIntent == nil else {
            throw IOSProviderConsentError.commitUncertain
        }
        guard case .snapshot(let expected) = observation.source,
              expected.content == .unreadable else {
            throw IOSProviderConsentError.resetRequiresUnreadableObservation
        }

        let current = try loadOrMapError()
        guard current == expected else {
            throw IOSProviderConsentError.staleObservation
        }
        do {
            try journal.removeUnreadable(expected: expected)
            authorizationConfirmedSnapshot = nil
            return self.observation(for: nil)
        } catch IOSProviderConsentJournalError.commitUncertain {
            uncertainIntent = .reset(source: expected)
            return try reconcileReset(source: expected)
        } catch {
            throw map(error)
        }
    }

    func registerProviderDispatch(
        _ authorization: IOSProviderConsentAuthorization,
        stage: IOSProviderConsentProviderStage,
        onCancellation: @escaping @Sendable () -> Void,
        gate: IOSProviderConsentAuthorizationGate
    ) -> IOSProviderConsentDispatchRegistration? {
        let outcome = gate.withSealedAdmission(authorization) {
            durableAdmissionDecision(for: authorization.binding) {
                gate.registerDispatch(
                    authorization,
                    stage: stage,
                    onCancellation: onCancellation
                )
            }
        }
        guard case .value(let registration) = outcome else {
            return nil
        }
        return registration
    }

    func prepareProviderDispatchLaunch(
        _ registration: IOSProviderConsentDispatchRegistration,
        gate: IOSProviderConsentAuthorizationGate
    ) -> Bool {
        let outcome = gate.withSealedAdmission(registration) {
            durableAdmissionDecision(for: registration.binding) {
                gate.prepareDispatchLaunch(registration)
            }
        }
        guard case .value(let didPrepare) = outcome else {
            return false
        }
        return didPrepare
    }

    func finishProviderDispatch(
        _ registration: IOSProviderConsentDispatchRegistration,
        onResultCancellation: @escaping @Sendable () -> Void,
        gate: IOSProviderConsentAuthorizationGate
    ) -> IOSProviderConsentResultAuthorization? {
        let outcome = gate.withSealedAdmission(registration) {
            durableAdmissionDecision(for: registration.binding) {
                gate.finishDispatch(
                    registration,
                    onResultCancellation: onResultCancellation
                )
            }
        }
        guard case .value(let authorization) = outcome else {
            return nil
        }
        return authorization
    }

    func prepareProviderResultConsumption(
        _ authorization: IOSProviderConsentResultAuthorization,
        gate: IOSProviderConsentAuthorizationGate
    ) -> Bool {
        let outcome = gate.withSealedAdmission(authorization) {
            durableAdmissionDecision(for: authorization.binding) {
                gate.prepareResultConsumption(authorization)
            }
        }
        guard case .value(let didPrepare) = outcome else {
            return false
        }
        return didPrepare
    }
}

private extension IOSProviderConsentOwner {
    func durableAdmissionDecision<Value>(
        for binding: IOSProviderConsentAuthorizationBinding,
        transition: () -> Value
    ) -> IOSProviderConsentSealedAdmissionDecision<Value> {
        do {
            return try journal.withProviderAdmissionLease { snapshot in
                guard validatesDurableAdmission(
                    for: binding,
                    snapshot: snapshot
                ) else {
                    return .durableAdmissionInvalid
                }
                let rootAfterRead = try repositoryAdmissionRevalidation()
                guard rootAfterRead == expectedRepositoryRootIdentity else {
                    authorizationConfirmedSnapshot = nil
                    return .durableAdmissionInvalid
                }
                let rootAtTransition = try repositoryAdmissionRevalidation()
                guard rootAtTransition == rootAfterRead,
                      rootAtTransition == expectedRepositoryRootIdentity else {
                    authorizationConfirmedSnapshot = nil
                    return .durableAdmissionInvalid
                }
                // The test interposition sits at the last validation boundary.
                // Production supplies an empty hook; a test substitution is
                // revalidated while the repository admission lease is still
                // held and before gate state can change.
                providerAdmissionInterposition()
                let rootAfterInterposition =
                    try repositoryAdmissionRevalidation()
                guard rootAfterInterposition == rootAtTransition,
                      rootAfterInterposition
                        == expectedRepositoryRootIdentity else {
                    authorizationConfirmedSnapshot = nil
                    return .durableAdmissionInvalid
                }
                return .value(transition())
            }
        } catch {
            authorizationConfirmedSnapshot = nil
            return .durableAdmissionInvalid
        }
    }

    func validatesDurableAdmission(
        for binding: IOSProviderConsentAuthorizationBinding,
        snapshot: IOSProviderConsentJournalSnapshot?
    ) -> Bool {
        guard binding.ownerIdentity == identity,
              binding.disclosureVersion == currentDisclosureVersion,
              binding.repositoryRootIdentity
                == expectedRepositoryRootIdentity,
              let expectedFileRevision = binding.fileRevision,
              let snapshot,
              snapshot.fileRevision == expectedFileRevision,
              snapshot == authorizationConfirmedSnapshot,
              case .readable(let record) = snapshot.content,
              record.state == .accepted,
              record.epochID == binding.epochID,
              record.revision == binding.revision,
              record.disclosureVersion == binding.disclosureVersion else {
            authorizationConfirmedSnapshot = nil
            return false
        }
        return true
    }

    func requireValidDisclosureVersion() throws {
        guard currentDisclosureVersion > 0 else {
            throw IOSProviderConsentError.invalidDisclosureVersion
        }
    }

    func requireOwned(_ observation: IOSProviderConsentObservation) throws {
        guard observation.ownerIdentity == identity else {
            throw IOSProviderConsentError.staleObservation
        }
    }

    func currentSnapshot(
        matching observation: IOSProviderConsentObservation
    ) throws -> IOSProviderConsentJournalSnapshot? {
        try requireOwned(observation)
        guard uncertainIntent == nil else {
            throw IOSProviderConsentError.commitUncertain
        }
        let current = try loadOrMapError()
        switch observation.source {
        case .absent where current == nil:
            return nil
        case .snapshot(let expected) where current == expected:
            return current
        case .unavailable, .mutationNotSaved, .absent, .snapshot:
            throw IOSProviderConsentError.staleObservation
        }
    }

    func requireSnapshot(
        _ snapshot: IOSProviderConsentJournalSnapshot?
    ) throws -> IOSProviderConsentJournalSnapshot {
        guard let snapshot else {
            throw IOSProviderConsentError.staleObservation
        }
        return snapshot
    }

    func successor(
        of record: IOSProviderConsentRecord,
        state: IOSProviderConsentDecisionState,
        decisionAt: Date
    ) throws -> IOSProviderConsentRecord {
        guard record.revision < Int64.max else {
            throw IOSProviderConsentError.revisionOverflow
        }
        do {
            return IOSProviderConsentRecord(
                epochID: record.epochID,
                revision: record.revision + 1,
                disclosureVersion: currentDisclosureVersion,
                state: state,
                decisionAt: try IOSProviderConsentWireCodec.canonicalDate(decisionAt)
            )
        } catch {
            throw IOSProviderConsentError.mutationNotSaved
        }
    }

    func firstRecord(
        state: IOSProviderConsentDecisionState,
        decisionAt: Date
    ) throws -> IOSProviderConsentRecord {
        do {
            return IOSProviderConsentRecord(
                epochID: makeEpochID(),
                revision: 1,
                disclosureVersion: currentDisclosureVersion,
                state: state,
                decisionAt: try IOSProviderConsentWireCodec.canonicalDate(decisionAt)
            )
        } catch {
            throw IOSProviderConsentError.mutationNotSaved
        }
    }

    func create(
        _ intended: IOSProviderConsentRecord
    ) throws -> IOSProviderConsentObservation {
        do {
            return confirmedMutationObservation(
                for: try journal.create(intended)
            )
        } catch IOSProviderConsentJournalError.commitUncertain {
            uncertainIntent = .mutation(source: nil, intended: intended)
            return try reconcileMutation(source: nil, intended: intended)
        } catch {
            throw map(error)
        }
    }

    func replace(
        _ intended: IOSProviderConsentRecord,
        source: IOSProviderConsentJournalSnapshot
    ) throws -> IOSProviderConsentObservation {
        do {
            return confirmedMutationObservation(
                for: try journal.replace(intended, expected: source)
            )
        } catch IOSProviderConsentJournalError.commitUncertain {
            uncertainIntent = .mutation(source: source, intended: intended)
            return try reconcileMutation(source: source, intended: intended)
        } catch {
            throw map(error)
        }
    }

    func reconcileMutation(
        source: IOSProviderConsentJournalSnapshot?,
        intended: IOSProviderConsentRecord
    ) throws -> IOSProviderConsentObservation {
        let current = try loadOrCommitUncertain()
        if current == source {
            uncertainIntent = nil
            throw IOSProviderConsentError.mutationNotSaved
        }
        guard case .readable(let record)? = current?.content,
              record == intended,
              let current else {
            throw IOSProviderConsentError.commitUncertain
        }
        let confirmed = try confirmDirectoryDurability(of: current)
        uncertainIntent = nil
        return confirmedMutationObservation(for: confirmed)
    }

    func reconcileReset(
        source: IOSProviderConsentJournalSnapshot
    ) throws -> IOSProviderConsentObservation {
        let current = try loadOrCommitUncertain()
        if current == source {
            uncertainIntent = nil
            throw IOSProviderConsentError.mutationNotSaved
        }
        guard current == nil else {
            throw IOSProviderConsentError.commitUncertain
        }
        try confirmAbsentDirectoryDurability()
        uncertainIntent = nil
        authorizationConfirmedSnapshot = nil
        return observation(for: nil)
    }

    private func resolveUncertainObservation(
        _ intent: UncertainIntent
    ) throws -> IOSProviderConsentObservation {
        switch intent {
        case .mutation(let source, let intended):
            let current = try loadOrCommitUncertain()
            if current == source {
                uncertainIntent = nil
                return try observationAfterDurabilityConfirmation(for: current)
            }
            guard case .readable(let record)? = current?.content,
                  record == intended,
                  let current else {
                throw IOSProviderConsentError.commitUncertain
            }
            let confirmed = try confirmDirectoryDurability(of: current)
            uncertainIntent = nil
            return confirmedMutationObservation(for: confirmed)
        case .reset(let source):
            let current = try loadOrCommitUncertain()
            if current == source {
                uncertainIntent = nil
                return observation(for: current)
            }
            guard current == nil else {
                throw IOSProviderConsentError.commitUncertain
            }
            try confirmAbsentDirectoryDurability()
            uncertainIntent = nil
            authorizationConfirmedSnapshot = nil
            return observation(for: nil)
        }
    }

    func observationAfterDurabilityConfirmation(
        for snapshot: IOSProviderConsentJournalSnapshot?
    ) throws -> IOSProviderConsentObservation {
        guard let snapshot,
              case .readable(let record) = snapshot.content,
              record.state == .accepted,
              record.disclosureVersion == currentDisclosureVersion else {
            authorizationConfirmedSnapshot = nil
            return observation(for: snapshot)
        }
        if authorizationConfirmedSnapshot == snapshot {
            return observation(for: snapshot)
        }
        let confirmed = try confirmDirectoryDurability(of: snapshot)
        authorizationConfirmedSnapshot = confirmed
        return observation(for: confirmed)
    }

    func confirmedMutationObservation(
        for snapshot: IOSProviderConsentJournalSnapshot
    ) -> IOSProviderConsentObservation {
        if case .readable(let record) = snapshot.content,
           record.state == .accepted,
           record.disclosureVersion == currentDisclosureVersion {
            authorizationConfirmedSnapshot = snapshot
        } else {
            authorizationConfirmedSnapshot = nil
        }
        return observation(for: snapshot)
    }

    func confirmDirectoryDurability(
        of snapshot: IOSProviderConsentJournalSnapshot
    ) throws -> IOSProviderConsentJournalSnapshot {
        do {
            try journal.synchronizeDirectory()
            guard try journal.load() == snapshot else {
                throw IOSProviderConsentError.commitUncertain
            }
            return snapshot
        } catch let error as IOSProviderConsentError {
            throw error
        } catch {
            throw IOSProviderConsentError.commitUncertain
        }
    }

    func confirmAbsentDirectoryDurability() throws {
        do {
            try journal.synchronizeDirectory()
            guard try journal.load() == nil else {
                throw IOSProviderConsentError.commitUncertain
            }
        } catch let error as IOSProviderConsentError {
            throw error
        } catch {
            throw IOSProviderConsentError.commitUncertain
        }
    }

    func loadOrMapError() throws -> IOSProviderConsentJournalSnapshot? {
        do {
            return try journal.load()
        } catch {
            throw map(error)
        }
    }

    func loadOrCommitUncertain() throws -> IOSProviderConsentJournalSnapshot? {
        do {
            return try journal.load()
        } catch {
            throw IOSProviderConsentError.commitUncertain
        }
    }

    func map(_ error: Error) -> IOSProviderConsentError {
        switch error as? IOSProviderConsentJournalError {
        case .staleRevision:
            .staleObservation
        case .localDataUnavailable:
            .localDataUnavailable
        case .mutationNotSaved:
            .mutationNotSaved
        case .commitUncertain:
            .commitUncertain
        case nil:
            .mutationNotSaved
        }
    }

    func unavailableObservation() -> IOSProviderConsentObservation {
        IOSProviderConsentObservation(
            status: .localDataUnavailable,
            decisionAt: nil,
            canResetUnreadableData: false,
            ownerIdentity: identity,
            source: .unavailable
        )
    }

    func observation(
        for snapshot: IOSProviderConsentJournalSnapshot?
    ) -> IOSProviderConsentObservation {
        guard let snapshot else {
            return IOSProviderConsentObservation(
                status: .notReviewed,
                decisionAt: nil,
                canResetUnreadableData: false,
                ownerIdentity: identity,
                source: .absent
            )
        }

        switch snapshot.content {
        case .unreadable:
            return IOSProviderConsentObservation(
                status: .reviewRequired,
                decisionAt: nil,
                canResetUnreadableData: true,
                ownerIdentity: identity,
                source: .snapshot(snapshot)
            )
        case .readable(let record):
            let status: IOSProviderConsentStatus
            if record.state == .withdrawn {
                status = .withdrawn
            } else if record.disclosureVersion == currentDisclosureVersion {
                status = .acceptedCurrentDisclosure
            } else {
                status = .reviewRequired
            }
            return IOSProviderConsentObservation(
                status: status,
                decisionAt: record.decisionAt,
                canResetUnreadableData: false,
                ownerIdentity: identity,
                source: .snapshot(snapshot)
            )
        }
    }
}

private extension IOSProviderConsentObservation {
    func observed(
        at fence: IOSProviderConsentObservationFence?
    ) -> IOSProviderConsentObservation {
        IOSProviderConsentObservation(
            status: status,
            decisionAt: decisionAt,
            canResetUnreadableData: canResetUnreadableData,
            ownerIdentity: ownerIdentity,
            source: source,
            gateFence: fence
        )
    }

    func repositoryUnavailable(
        at fence: IOSProviderConsentObservationFence
    ) -> IOSProviderConsentObservation {
        IOSProviderConsentObservation(
            status: .localDataUnavailable,
            decisionAt: nil,
            canResetUnreadableData: false,
            ownerIdentity: ownerIdentity,
            source: .unavailable,
            gateFence: fence
        )
    }

    var authorizationBinding: IOSProviderConsentAuthorizationBinding? {
        guard status == .acceptedCurrentDisclosure,
              case .snapshot(let snapshot) = source,
              case .readable(let record) = snapshot.content,
              record.state == .accepted else {
            return nil
        }
        return IOSProviderConsentAuthorizationBinding(
            ownerIdentity: ownerIdentity,
            epochID: record.epochID,
            revision: record.revision,
            disclosureVersion: record.disclosureVersion,
            fileRevision: snapshot.fileRevision
        )
    }
}

enum IOSProviderConsentSealedAdmissionDecision<Value> {
    case durableAdmissionInvalid
    case value(Value)
}

enum IOSProviderConsentSealedAdmissionOutcome<Value> {
    case rejected
    case value(Value)
}

final class IOSProviderConsentAuthorizationGate: @unchecked Sendable {
    private struct DispatchState {
        let registration: IOSProviderConsentDispatchRegistration
        let onCancellation: @Sendable () -> Void
        var isLaunched: Bool
    }

    private struct ResultState {
        let authorization: IOSProviderConsentResultAuthorization
        let onCancellation: @Sendable () -> Void
        var isBeingConsumed: Bool
    }

    private let operationLock = NSRecursiveLock()
    private let lock = NSLock()
    private let identity = IOSProviderConsentAuthorizationGateIdentity()
    private var fence = IOSProviderConsentObservationFence()
    private var generation = UUID()
    private var binding: IOSProviderConsentAuthorizationBinding?
    private var requiresExplicitAcceptance = false
    private var dispatches: [UUID: DispatchState] = [:]
    private var results: [UUID: ResultState] = [:]
    private var callbackDepth = 0
    private var deferredClose = false
    private var deferredDispatchCancellations: Set<UUID> = []
    private var deferredResultAbandons: Set<UUID> = []

    func currentFence() -> IOSProviderConsentObservationFence {
        lock.withLock { fence }
    }

    func currentFence(
        matching observationFence: IOSProviderConsentObservationFence
    ) -> IOSProviderConsentObservationFence? {
        lock.withLock {
            fence == observationFence ? fence : nil
        }
    }

    func adoptPassively(
        binding newBinding: IOSProviderConsentAuthorizationBinding?,
        ifFenceIs expectedFence: IOSProviderConsentObservationFence
    ) -> IOSProviderConsentObservationFence? {
        operationLock.lock()
        let adoption: (
            IOSProviderConsentObservationFence?,
            [@Sendable () -> Void]
        ) = lock.withLock {
            guard fence == expectedFence else { return (nil, []) }
            if requiresExplicitAcceptance, newBinding != nil {
                return (fence, [])
            }
            if binding != newBinding {
                let cancellations = retireProviderWorkLocked()
                generation = UUID()
                binding = newBinding
                fence = IOSProviderConsentObservationFence()
                return (fence, cancellations)
            }
            binding = newBinding
            return (fence, [])
        }
        operationLock.unlock()
        adoption.1.forEach { $0() }
        return adoption.0
    }

    func adoptAfterExplicitAcceptance(
        binding newBinding: IOSProviderConsentAuthorizationBinding?,
        ifFenceIs expectedFence: IOSProviderConsentObservationFence
    ) -> IOSProviderConsentObservationFence? {
        operationLock.lock()
        let adoption: (
            IOSProviderConsentObservationFence?,
            [@Sendable () -> Void]
        ) = lock.withLock {
            guard fence == expectedFence,
                  let newBinding else { return (nil, []) }
            var cancellations: [@Sendable () -> Void] = []
            if binding != newBinding {
                cancellations = retireProviderWorkLocked()
                generation = UUID()
            }
            binding = newBinding
            requiresExplicitAcceptance = false
            // A successful explicit decision supersedes every older async
            // completion that captured the prior fence.
            fence = IOSProviderConsentObservationFence()
            return (fence, cancellations)
        }
        operationLock.unlock()
        adoption.1.forEach { $0() }
        return adoption.0
    }

    func close(ifFenceIs expectedFence: IOSProviderConsentObservationFence) {
        operationLock.lock()
        let cancellations: [@Sendable () -> Void]? = lock.withLock {
            guard fence == expectedFence else { return nil }
            guard callbackDepth == 0 else {
                _ = beginDeferredCloseLocked()
                return []
            }
            return closeLocked()
        }
        operationLock.unlock()
        cancellations?.forEach { $0() }
    }

    func close(
        observedAt observationFence: IOSProviderConsentObservationFence
    ) -> IOSProviderConsentObservationFence? {
        operationLock.lock()
        let closure: (
            IOSProviderConsentObservationFence?,
            [@Sendable () -> Void]
        ) = lock.withLock {
            guard fence == observationFence else { return (nil, []) }
            guard callbackDepth == 0 else {
                return (beginDeferredCloseLocked(), [])
            }
            let cancellations = closeLocked()
            return (fence, cancellations)
        }
        operationLock.unlock()
        closure.1.forEach { $0() }
        return closure.0
    }

    func close() {
        operationLock.lock()
        let cancellations: [@Sendable () -> Void] = lock.withLock {
            guard callbackDepth == 0 else {
                _ = beginDeferredCloseLocked()
                return []
            }
            return closeLocked()
        }
        operationLock.unlock()
        cancellations.forEach { $0() }
    }

    func withSealedMutation<Value>(
        observedAt observationFence: IOSProviderConsentObservationFence,
        perform operation: () throws -> Value
    ) rethrows -> Value? {
        operationLock.lock()
        guard lock.withLock({
            callbackDepth == 0 && fence == observationFence
        }) else {
            operationLock.unlock()
            return nil
        }
        do {
            let value = try operation()
            operationLock.unlock()
            return value
        } catch {
            operationLock.unlock()
            throw error
        }
    }

    func withSealedAdmission<Value>(
        _ authorization: IOSProviderConsentAuthorization,
        perform operation: () throws
            -> IOSProviderConsentSealedAdmissionDecision<Value>
    ) rethrows -> IOSProviderConsentSealedAdmissionOutcome<Value> {
        try withSealedAdmission(
            capabilityIsCurrent: { self.isCurrent(authorization) },
            perform: operation
        )
    }

    func withSealedAdmission<Value>(
        _ registration: IOSProviderConsentDispatchRegistration,
        perform operation: () throws
            -> IOSProviderConsentSealedAdmissionDecision<Value>
    ) rethrows -> IOSProviderConsentSealedAdmissionOutcome<Value> {
        try withSealedAdmission(
            capabilityIsCurrent: { self.isCurrent(registration) },
            perform: operation
        )
    }

    func withSealedAdmission<Value>(
        _ authorization: IOSProviderConsentResultAuthorization,
        perform operation: () throws
            -> IOSProviderConsentSealedAdmissionDecision<Value>
    ) rethrows -> IOSProviderConsentSealedAdmissionOutcome<Value> {
        try withSealedAdmission(
            capabilityIsCurrent: { self.isCurrent(authorization) },
            perform: operation
        )
    }

    func makeAuthorization(
        for requestedBinding: IOSProviderConsentAuthorizationBinding
    ) -> IOSProviderConsentAuthorization? {
        lock.withLock {
            guard binding == requestedBinding else { return nil }
            return IOSProviderConsentAuthorization(
                binding: requestedBinding,
                gateGeneration: generation
            )
        }
    }

    func makeAuthorization(
        for requestedBinding: IOSProviderConsentAuthorizationBinding,
        observedAt observationFence: IOSProviderConsentObservationFence
    ) -> IOSProviderConsentAuthorization? {
        lock.withLock {
            guard fence == observationFence,
                  binding == requestedBinding else {
                return nil
            }
            return IOSProviderConsentAuthorization(
                binding: requestedBinding,
                gateGeneration: generation
            )
        }
    }

    func isCurrent(
        _ authorization: IOSProviderConsentAuthorization
    ) -> Bool {
        lock.withLock {
            binding == authorization.binding
                && generation == authorization.gateGeneration
        }
    }

    func isCurrent(
        _ registration: IOSProviderConsentDispatchRegistration
    ) -> Bool {
        lock.withLock {
            guard registration.gateIdentity == identity,
                  binding == registration.binding,
                  generation == registration.gateGeneration,
                  let state = dispatches[registration.registrationID] else {
                return false
            }
            return state.registration == registration
        }
    }

    func isCurrent(
        _ authorization: IOSProviderConsentResultAuthorization
    ) -> Bool {
        lock.withLock {
            guard authorization.gateIdentity == identity,
                  binding == authorization.binding,
                  generation == authorization.gateGeneration,
                  let state = results[authorization.resultID] else {
                return false
            }
            return state.authorization == authorization
        }
    }

    func registerDispatch(
        _ authorization: IOSProviderConsentAuthorization,
        stage: IOSProviderConsentProviderStage,
        onCancellation: @escaping @Sendable () -> Void
    ) -> IOSProviderConsentDispatchRegistration? {
        operationLock.lock()
        let registration: IOSProviderConsentDispatchRegistration? = lock.withLock {
            guard binding == authorization.binding,
                  generation == authorization.gateGeneration else {
                return nil
            }
            let registration = IOSProviderConsentDispatchRegistration(
                gateIdentity: identity,
                registrationID: UUID(),
                binding: authorization.binding,
                gateGeneration: authorization.gateGeneration,
                stage: stage
            )
            dispatches[registration.registrationID] = DispatchState(
                registration: registration,
                onCancellation: onCancellation,
                isLaunched: false
            )
            return registration
        }
        operationLock.unlock()
        return registration
    }

    func launchDispatch(
        _ registration: IOSProviderConsentDispatchRegistration,
        launch: @Sendable () -> Void
    ) -> Bool {
        operationLock.lock()
        let didPrepare = prepareDispatchLaunch(registration)
        operationLock.unlock()
        guard didPrepare else {
            return false
        }
        performPreparedDispatchLaunch(launch)
        return true
    }

    func prepareDispatchLaunch(
        _ registration: IOSProviderConsentDispatchRegistration
    ) -> Bool {
        lock.withLock {
            guard registration.gateIdentity == identity,
                  binding == registration.binding,
                  generation == registration.gateGeneration,
                  var state = dispatches[registration.registrationID],
                  state.registration == registration,
                  !state.isLaunched else {
                return false
            }
            state.isLaunched = true
            dispatches[registration.registrationID] = state
            callbackDepth += 1
            return true
        }
    }

    func performPreparedDispatchLaunch(
        _ launch: @Sendable () -> Void
    ) {
        launch()
        let cancellations = finishCallbackBoundary()
        cancellations.forEach { $0() }
    }

    func cancelDispatch(
        _ registration: IOSProviderConsentDispatchRegistration
    ) {
        operationLock.lock()
        let cancellation = lock.withLock { () -> (@Sendable () -> Void)? in
            if callbackDepth > 0 {
                deferredDispatchCancellations.insert(
                    registration.registrationID
                )
                return nil
            }
            guard registration.gateIdentity == identity,
                  let state = dispatches[registration.registrationID],
                  state.registration == registration else {
                return nil
            }
            dispatches.removeValue(forKey: registration.registrationID)
            return state.onCancellation
        }
        operationLock.unlock()
        cancellation?()
    }

    func finishDispatch(
        _ registration: IOSProviderConsentDispatchRegistration,
        onResultCancellation: @escaping @Sendable () -> Void
    ) -> IOSProviderConsentResultAuthorization? {
        operationLock.lock()
        let authorization: IOSProviderConsentResultAuthorization? = lock.withLock {
            guard registration.gateIdentity == identity,
                  binding == registration.binding,
                  generation == registration.gateGeneration,
                  let state = dispatches[registration.registrationID],
                  state.registration == registration,
                  state.isLaunched else {
                return nil
            }
            dispatches.removeValue(forKey: registration.registrationID)
            let authorization = IOSProviderConsentResultAuthorization(
                gateIdentity: identity,
                resultID: UUID(),
                binding: registration.binding,
                gateGeneration: registration.gateGeneration,
                stage: registration.stage
            )
            results[authorization.resultID] = ResultState(
                authorization: authorization,
                onCancellation: onResultCancellation,
                isBeingConsumed: false
            )
            return authorization
        }
        operationLock.unlock()
        return authorization
    }

    func consumeResult<T>(
        _ authorization: IOSProviderConsentResultAuthorization,
        perform operation: @Sendable () throws -> T
    ) rethrows -> T? {
        operationLock.lock()
        let didPrepare = prepareResultConsumption(authorization)
        operationLock.unlock()
        guard didPrepare else {
            return nil
        }
        return try performPreparedResultConsumption(
            authorization,
            operation: operation
        )
    }

    func prepareResultConsumption(
        _ authorization: IOSProviderConsentResultAuthorization
    ) -> Bool {
        lock.withLock {
            guard authorization.gateIdentity == identity,
                  binding == authorization.binding,
                  generation == authorization.gateGeneration,
                  var state = results[authorization.resultID],
                  state.authorization == authorization,
                  !state.isBeingConsumed else {
                return false
            }
            state.isBeingConsumed = true
            results[authorization.resultID] = state
            callbackDepth += 1
            return true
        }
    }

    func performPreparedResultConsumption<T>(
        _ authorization: IOSProviderConsentResultAuthorization,
        operation: @Sendable () throws -> T
    ) rethrows -> T {
        do {
            let value = try operation()
            lock.withLock {
                if results[authorization.resultID]?.authorization
                    == authorization {
                    results.removeValue(forKey: authorization.resultID)
                }
            }
            let cancellations = finishCallbackBoundary()
            cancellations.forEach { $0() }
            return value
        } catch {
            lock.withLock {
                guard var state = results[authorization.resultID],
                      state.authorization == authorization else { return }
                state.isBeingConsumed = false
                results[authorization.resultID] = state
            }
            let cancellations = finishCallbackBoundary()
            cancellations.forEach { $0() }
            throw error
        }
    }

    func abandonResult(
        _ authorization: IOSProviderConsentResultAuthorization
    ) {
        operationLock.lock()
        let cancellation = lock.withLock { () -> (@Sendable () -> Void)? in
            if callbackDepth > 0 {
                deferredResultAbandons.insert(authorization.resultID)
                return nil
            }
            guard authorization.gateIdentity == identity,
                  let state = results[authorization.resultID],
                  state.authorization == authorization else {
                return nil
            }
            results.removeValue(forKey: authorization.resultID)
            return state.onCancellation
        }
        operationLock.unlock()
        cancellation?()
    }

    private func finishCallbackBoundary() -> [@Sendable () -> Void] {
        return lock.withLock {
            callbackDepth -= 1
            guard callbackDepth == 0 else { return [] }

            let shouldClose = deferredClose
            let dispatchIDs = deferredDispatchCancellations
            let resultIDs = deferredResultAbandons
            deferredClose = false
            deferredDispatchCancellations.removeAll(
                keepingCapacity: false
            )
            deferredResultAbandons.removeAll(keepingCapacity: false)

            if shouldClose {
                return retireProviderWorkLocked()
            }
            var cancellations: [@Sendable () -> Void] = []
            for registrationID in dispatchIDs {
                if let state = dispatches.removeValue(
                    forKey: registrationID
                ) {
                    cancellations.append(state.onCancellation)
                }
            }
            for resultID in resultIDs {
                if let state = results.removeValue(forKey: resultID) {
                    cancellations.append(state.onCancellation)
                }
            }
            return cancellations
        }
    }

    private func withSealedAdmission<Value>(
        capabilityIsCurrent: () -> Bool,
        perform operation: () throws
            -> IOSProviderConsentSealedAdmissionDecision<Value>
    ) rethrows -> IOSProviderConsentSealedAdmissionOutcome<Value> {
        operationLock.lock()
        guard lock.withLock({ callbackDepth == 0 }),
              capabilityIsCurrent() else {
            operationLock.unlock()
            return .rejected
        }
        do {
            switch try operation() {
            case .durableAdmissionInvalid:
                let cancellations = lock.withLock { closeLocked() }
                operationLock.unlock()
                cancellations.forEach { $0() }
                return .rejected
            case .value(let value):
                operationLock.unlock()
                return .value(value)
            }
        } catch {
            operationLock.unlock()
            throw error
        }
    }

    private func closeLocked() -> [@Sendable () -> Void] {
        let cancellations = retireProviderWorkLocked()
        binding = nil
        generation = UUID()
        fence = IOSProviderConsentObservationFence()
        requiresExplicitAcceptance = true
        return cancellations
    }

    private func beginDeferredCloseLocked()
        -> IOSProviderConsentObservationFence {
        guard !deferredClose else { return fence }
        deferredClose = true
        binding = nil
        generation = UUID()
        fence = IOSProviderConsentObservationFence()
        requiresExplicitAcceptance = true
        return fence
    }

    private func retireProviderWorkLocked() -> [@Sendable () -> Void] {
        let cancellations = dispatches.values.map(\.onCancellation)
            + results.values.map(\.onCancellation)
        dispatches.removeAll(keepingCapacity: false)
        results.removeAll(keepingCapacity: false)
        return cancellations
    }
}
