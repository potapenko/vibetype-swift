import Foundation

/// The containing process's single owner for provider-consent observation,
/// compare-and-swap mutation, and short-lived provider authority.
public final class IOSProviderConsentCoordinator: @unchecked Sendable {
    public static let currentDisclosureVersion: Int64 = 1

    private let owner: IOSProviderConsentOwner
    private let gate = IOSProviderConsentAuthorizationGate()

    public init(
        applicationSupportDirectoryURL: URL,
        currentDisclosureVersion: Int64 =
            IOSProviderConsentCoordinator.currentDisclosureVersion
    ) {
        owner = IOSProviderConsentOwner(
            journal: FoundationIOSProviderConsentJournalRepository(
                applicationSupportDirectoryURL: applicationSupportDirectoryURL
            ),
            currentDisclosureVersion: currentDisclosureVersion
        )
    }

    init(
        journal: any IOSProviderConsentJournalStoring,
        currentDisclosureVersion: Int64 =
            IOSProviderConsentCoordinator.currentDisclosureVersion,
        makeEpochID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        owner = IOSProviderConsentOwner(
            journal: journal,
            currentDisclosureVersion: currentDisclosureVersion,
            makeEpochID: makeEpochID
        )
    }

    /// Passive observation; no authorization is returned or implicitly dispatched.
    public func observe() async -> IOSProviderConsentObservation {
        let fence = gate.currentFence()
        let observation = await owner.observe()
        gate.adoptPassively(
            binding: observation.authorizationBinding,
            ifFenceIs: fence
        )
        return observation
    }

    @discardableResult
    public func accept(
        using observation: IOSProviderConsentObservation,
        decisionAt: Date = Date()
    ) async throws -> IOSProviderConsentObservation {
        let fence = gate.currentFence()
        do {
            let saved = try await owner.accept(
                using: observation,
                decisionAt: decisionAt
            )
            gate.adoptAfterExplicitAcceptance(
                binding: saved.authorizationBinding,
                ifFenceIs: fence
            )
            return saved
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
        gate.close()
        return try await owner.withdraw(
            using: observation,
            decisionAt: decisionAt
        )
    }

    /// Deletes only the exact unreadable physical revision in the observation.
    @discardableResult
    public func resetUnreadableConsentData(
        using observation: IOSProviderConsentObservation
    ) async throws -> IOSProviderConsentObservation {
        gate.close()
        return try await owner.resetUnreadable(using: observation)
    }

    public func makeAuthorization(
        from observation: IOSProviderConsentObservation
    ) -> IOSProviderConsentAuthorization? {
        guard let binding = observation.authorizationBinding else {
            return nil
        }
        return gate.makeAuthorization(for: binding)
    }

    public func validate(
        _ authorization: IOSProviderConsentAuthorization,
        for stage: IOSProviderConsentProviderStage
    ) -> Bool {
        _ = stage
        return gate.validate(authorization)
    }

    public func revalidateAfterProviderResponse(
        _ authorization: IOSProviderConsentAuthorization,
        for stage: IOSProviderConsentProviderStage
    ) -> Bool {
        validate(authorization, for: stage)
    }

    /// Retires every dispatch and response token without mutating durable consent.
    public func invalidateProviderAuthorizations() {
        gate.close()
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

private actor IOSProviderConsentOwner {
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
    private let identity = IOSProviderConsentOwnerIdentity()
    private var uncertainIntent: UncertainIntent?

    init(
        journal: any IOSProviderConsentJournalStoring,
        currentDisclosureVersion: Int64,
        makeEpochID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.journal = journal
        self.currentDisclosureVersion = currentDisclosureVersion
        self.makeEpochID = makeEpochID
    }

    func observe() -> IOSProviderConsentObservation {
        guard currentDisclosureVersion > 0 else {
            return unavailableObservation()
        }
        do {
            if let uncertainIntent {
                return try resolveUncertainObservation(uncertainIntent)
            }
            return observation(for: try journal.load())
        } catch {
            return unavailableObservation()
        }
    }

    func accept(
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
            return self.observation(for: current)
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
            return self.observation(for: nil)
        } catch IOSProviderConsentJournalError.commitUncertain {
            uncertainIntent = .reset(source: expected)
            return try reconcileReset(source: expected)
        } catch {
            throw map(error)
        }
    }
}

private extension IOSProviderConsentOwner {
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
            return observation(for: try journal.create(intended))
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
            return observation(
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
        return observation(for: confirmed)
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
                return observation(for: current)
            }
            guard case .readable(let record)? = current?.content,
                  record == intended,
                  let current else {
                throw IOSProviderConsentError.commitUncertain
            }
            let confirmed = try confirmDirectoryDurability(of: current)
            uncertainIntent = nil
            return observation(for: confirmed)
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
            return observation(for: nil)
        }
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
            disclosureVersion: record.disclosureVersion
        )
    }
}

final class IOSProviderConsentAuthorizationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var fence = UUID()
    private var generation = UUID()
    private var binding: IOSProviderConsentAuthorizationBinding?
    private var requiresExplicitAcceptance = false

    func currentFence() -> UUID {
        lock.withLock { fence }
    }

    func adoptPassively(
        binding newBinding: IOSProviderConsentAuthorizationBinding?,
        ifFenceIs expectedFence: UUID
    ) {
        lock.withLock {
            guard fence == expectedFence else { return }
            if requiresExplicitAcceptance, newBinding != nil {
                return
            }
            if binding != newBinding {
                generation = UUID()
            }
            binding = newBinding
        }
    }

    func adoptAfterExplicitAcceptance(
        binding newBinding: IOSProviderConsentAuthorizationBinding?,
        ifFenceIs expectedFence: UUID
    ) {
        lock.withLock {
            guard fence == expectedFence,
                  let newBinding else { return }
            if binding != newBinding {
                generation = UUID()
            }
            binding = newBinding
            requiresExplicitAcceptance = false
        }
    }

    func close(ifFenceIs expectedFence: UUID) {
        lock.withLock {
            guard fence == expectedFence else { return }
            closeLocked()
        }
    }

    func close() {
        lock.withLock {
            closeLocked()
        }
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

    func validate(_ authorization: IOSProviderConsentAuthorization) -> Bool {
        lock.withLock {
            binding == authorization.binding
                && generation == authorization.gateGeneration
        }
    }

    private func closeLocked() {
        binding = nil
        generation = UUID()
        fence = UUID()
        requiresExplicitAcceptance = true
    }
}
