import Foundation
import HoldTypeDomain

struct IOSAcceptedHistoryGuardedBaselineEvidence: Sendable {
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity

    fileprivate init(
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    ) {
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
    }
}

extension IOSAcceptedHistoryGuardedBaselineEvidence: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedHistoryGuardedBaselineEvidence(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSAcceptedHistoryJournalMutationAuthorization: Sendable {
    fileprivate init() {}
}

fileprivate enum IOSAcceptedHistoryCandidateOrigin: Equatable, Sendable {
    case delivery(IOSAcceptedOutputDeliveryAuthorization)
    case outbox(IOSAcceptedHistoryOutboxReceipt)
}

fileprivate struct IOSAcceptedHistoryCandidate: Equatable, Sendable {
    let origin: IOSAcceptedHistoryCandidateOrigin
    let entry: IOSAcceptedHistoryEntry
    let expiresAt: Date
    let permitsExpiredRetryRecovery: Bool

    init(
        delivery: IOSAcceptedOutputDeliveryAuthorization,
        policy: IOSHistoryPolicyReceipt,
        permitsExpiredRetryRecovery: Bool = false
    ) throws {
        let record = delivery.record
        guard let marker = record.historyWrite,
              marker.state.isPendingDecision,
              policy.state.historyEnabled,
              marker.policyGeneration == policy.state.policyGeneration,
              let acceptedText = record.acceptedText else {
            throw IOSAcceptedHistoryError.stalePolicyGeneration
        }
        origin = .delivery(delivery)
        entry = try Self.entry(
            deliveryID: record.deliveryID,
            transcriptID: record.transcriptID,
            acceptedText: acceptedText,
            outputIntent: record.outputIntent,
            createdAt: record.createdAt,
            policyGeneration: marker.policyGeneration,
            transcriptionModel: marker.transcriptionModel,
            transcriptionLanguageCode: marker.transcriptionLanguageCode,
            durationMilliseconds: marker.durationMilliseconds
        )
        expiresAt = record.expiresAt
        self.permitsExpiredRetryRecovery = permitsExpiredRetryRecovery
    }

    init(
        outbox: IOSAcceptedHistoryOutboxReceipt,
        policy: IOSHistoryPolicyReceipt
    ) throws {
        guard let confirmed = outbox.confirmedEntryForAcceptedDecision() else {
            throw IOSAcceptedHistoryError.compareAndSwapFailed
        }
        guard policy.state.historyEnabled,
              confirmed.policyGeneration == policy.state.policyGeneration else {
            throw IOSAcceptedHistoryError.stalePolicyGeneration
        }
        origin = .outbox(outbox)
        entry = try Self.entry(from: confirmed)
        expiresAt = confirmed.expiresAt
        permitsExpiredRetryRecovery = false
    }

    func matches(
        delivery: IOSAcceptedOutputDeliveryAuthorization
    ) -> Bool {
        switch origin {
        case .delivery(let originatingDelivery):
            return originatingDelivery == delivery
        case .outbox:
            guard let other = try? Self.entry(from: delivery) else {
                return false
            }
            return entry.hasSameImmutableBytes(as: other)
        }
    }

    func matches(outbox: IOSAcceptedHistoryOutboxReceipt) -> Bool {
        switch origin {
        case .delivery:
            guard let confirmed = outbox.confirmedEntryForAcceptedDecision(),
                  let other = try? Self.entry(from: confirmed) else {
                return false
            }
            return entry.hasSameImmutableBytes(as: other)
        case .outbox(let originatingOutbox):
            return originatingOutbox == outbox
        }
    }

    private static func entry(
        from delivery: IOSAcceptedOutputDeliveryAuthorization
    ) throws -> IOSAcceptedHistoryEntry {
        let record = delivery.record
        guard let marker = record.historyWrite,
              marker.state.isPendingDecision,
              let acceptedText = record.acceptedText else {
            throw IOSAcceptedHistoryError.stalePolicyGeneration
        }
        return try entry(
            deliveryID: record.deliveryID,
            transcriptID: record.transcriptID,
            acceptedText: acceptedText,
            outputIntent: record.outputIntent,
            createdAt: record.createdAt,
            policyGeneration: marker.policyGeneration,
            transcriptionModel: marker.transcriptionModel,
            transcriptionLanguageCode: marker.transcriptionLanguageCode,
            durationMilliseconds: marker.durationMilliseconds
        )
    }

    private static func entry(
        from outbox: IOSAcceptedHistoryOutboxEntry
    ) throws -> IOSAcceptedHistoryEntry {
        try entry(
            deliveryID: outbox.deliveryID,
            transcriptID: outbox.transcriptID,
            acceptedText: outbox.acceptedText,
            outputIntent: outbox.outputIntent,
            createdAt: outbox.createdAt,
            policyGeneration: outbox.policyGeneration,
            transcriptionModel: outbox.transcriptionModel,
            transcriptionLanguageCode: outbox.transcriptionLanguageCode,
            durationMilliseconds: outbox.durationMilliseconds
        )
    }

    private static func entry(
        deliveryID: UUID,
        transcriptID: UUID,
        acceptedText: String,
        outputIntent: HoldTypeDomain.DictationOutputIntent,
        createdAt: Date,
        policyGeneration: Int64,
        transcriptionModel: String,
        transcriptionLanguageCode: String?,
        durationMilliseconds: Int64?
    ) throws -> IOSAcceptedHistoryEntry {
        try IOSAcceptedHistoryEntry(
            deliveryID: deliveryID,
            transcriptID: transcriptID,
            acceptedText: acceptedText,
            outputIntent: outputIntent,
            createdAt: createdAt,
            policyGeneration: policyGeneration,
            transcriptionModel: transcriptionModel,
            transcriptionLanguageCode: transcriptionLanguageCode,
            durationMilliseconds: durationMilliseconds,
            cachedAudioRelativeIdentifier: nil
        )
    }
}

extension IOSAcceptedHistoryCandidate: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSAcceptedHistoryCandidate(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSAcceptedHistoryRetentionDecision: Equatable, Sendable {
    case retained
    case notRetained
}

fileprivate enum IOSAcceptedHistoryReceiptOutcome: Equatable, Sendable {
    case retained(IOSAcceptedHistoryEntry)
    case notRetained
    case preparedNotRetained
}

struct IOSAcceptedHistoryRowReceipt: Equatable, Sendable {
    fileprivate let candidate: IOSAcceptedHistoryCandidate
    fileprivate let snapshot: IOSAcceptedHistoryJournalSnapshot
    fileprivate let outcome: IOSAcceptedHistoryReceiptOutcome
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity

    var decision: IOSAcceptedHistoryRetentionDecision {
        switch outcome {
        case .retained: .retained
        case .notRetained, .preparedNotRetained: .notRetained
        }
    }

    func provesDecision(
        for delivery: IOSAcceptedOutputDeliveryAuthorization
    ) -> Bool {
        guard capabilityOwnerIdentity == delivery.capabilityOwnerIdentity,
              snapshotMatchesOutcome,
              candidate.matches(delivery: delivery) else {
            return false
        }
        if case .preparedNotRetained = outcome {
            return delivery.record.historyWrite?.state
                == .pendingReplacement
        }
        return true
    }

    func provesDecision(
        for outbox: IOSAcceptedHistoryOutboxReceipt
    ) -> Bool {
        guard case .preparedNotRetained = outcome else {
            return capabilityOwnerIdentity == outbox.capabilityOwnerIdentity
            && snapshotMatchesOutcome
            && candidate.matches(outbox: outbox)
        }
        return false
    }

    func provesMembership(
        for delivery: IOSAcceptedOutputDeliveryAuthorization
    ) -> Bool {
        guard case .retained = outcome else { return false }
        return provesDecision(for: delivery)
    }

    func provesMembership(
        for outbox: IOSAcceptedHistoryOutboxReceipt
    ) -> Bool {
        guard case .retained = outcome else { return false }
        return provesDecision(for: outbox)
    }

    fileprivate var snapshotMatchesOutcome: Bool {
        let deliveryMatches = snapshot.envelope.entries.filter {
            $0.deliveryID == candidate.entry.deliveryID
        }
        let transcriptMatches = snapshot.envelope.entries.filter {
            $0.transcriptID == candidate.entry.transcriptID
        }

        switch outcome {
        case .retained(let retained):
            return retained.hasSameImmutableBytes(as: candidate.entry)
                && deliveryMatches == [retained]
                && transcriptMatches == [retained]
        case .notRetained, .preparedNotRetained:
            return deliveryMatches.isEmpty && transcriptMatches.isEmpty
        }
    }
}

extension IOSAcceptedHistoryRowReceipt: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSAcceptedHistoryRowReceipt(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Internal persistence primitive. The containing-app coordinator supplies
/// confirmed delivery and policy capabilities; raw generations are never an
/// input to this boundary.
actor IOSAcceptedHistoryStore {
    nonisolated let capabilityOwnerIdentity:
        IOSAcceptedHistoryCapabilityOwnerIdentity
    private enum Source: Equatable, Sendable {
        case missing
        case existing(IOSAcceptedHistoryJournalSnapshot)
    }

    private struct Outcome: Equatable, Sendable {
        let envelope: IOSAcceptedHistoryEnvelope
        let retainedEntry: IOSAcceptedHistoryEntry?
        let requiresLiveSource: Bool
    }

    private enum ReceiptMode: Equatable, Sendable {
        case durableDecision
        case preparedNotRetained
    }

    private struct UncertainIntent: Equatable, Sendable {
        let source: Source
        let candidate: IOSAcceptedHistoryCandidate
        let outcome: Outcome
        let receiptMode: ReceiptMode
    }

    private struct UncertainPruneIntent: Equatable, Sendable {
        let source: IOSAcceptedHistoryJournalSnapshot
        let policy: IOSHistoryPolicyReceipt
        let outcome: IOSAcceptedHistoryEnvelope
    }

    private let journal: any IOSAcceptedHistoryJournalStoring
    private let now: @Sendable () -> Date
    private var uncertainIntent: UncertainIntent?
    private var uncertainPruneIntent: UncertainPruneIntent?

    init(
        applicationSupportDirectoryURL: URL,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
            IOSAcceptedHistoryCapabilityOwnerIdentity(),
        repositoryGuard:
            IOSAcceptedHistoryCoordinatorRepositoryGuard? = nil
    ) {
        journal = FoundationIOSAcceptedHistoryJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            repositoryGuard: repositoryGuard
        )
        now = { Date() }
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
    }

    init(
        journal: any IOSAcceptedHistoryJournalStoring,
        now: @escaping @Sendable () -> Date = { Date() },
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
            IOSAcceptedHistoryCapabilityOwnerIdentity()
    ) {
        self.journal = journal
        self.now = now
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
    }

    /// Raw state is coordinator-only because stale generations remain on disk
    /// after a committed policy cutover until lifecycle reconciliation.
    func load() throws -> IOSAcceptedHistoryEnvelope? {
        guard uncertainPruneIntent == nil else {
            throw IOSAcceptedHistoryError.commitUncertain
        }
        return try journal.load()?.envelope
    }

    func proveGuardedBaseline()
        throws -> IOSAcceptedHistoryGuardedBaselineEvidence {
        guard uncertainIntent == nil,
              uncertainPruneIntent == nil else {
            throw IOSAcceptedHistoryError.commitUncertain
        }
        guard try journal.load()?.envelope.entries.isEmpty != false else {
            throw IOSAcceptedHistoryError.compareAndSwapFailed
        }
        return IOSAcceptedHistoryGuardedBaselineEvidence(
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
    }

    func decideUpsert(
        delivery: IOSAcceptedOutputDeliveryAuthorization,
        policy: IOSHistoryPolicyReceipt
    ) throws -> IOSAcceptedHistoryRowReceipt {
        try requireOwners(delivery, policy)
        try requireNoPruneUncertainty()
        let candidate = try IOSAcceptedHistoryCandidate(
            delivery: delivery,
            policy: policy
        )
        return try decideUpsert(candidate)
    }

    /// Retry-only absent-row provenance. Ordinary `.pending` delivery recovery
    /// remains confirmation-only; this path is available solely while the
    /// exact failed `acceptingOutput` relation and lease are still valid.
    func decideFailedRetryReplay(
        delivery: IOSAcceptedOutputDeliveryAuthorization,
        policy: IOSHistoryPolicyReceipt,
        deliveryPermit: IOSFailedHistoryRetryDeliveryPermit
    ) throws -> IOSAcceptedHistoryRowReceipt {
        try requireOwners(delivery, policy)
        let acceptingOutputReceipt = deliveryPermit.acceptingOutputReceipt
        let preparation = acceptingOutputReceipt.frozenSlotProof.preparation
        guard deliveryPermit.provesActiveRelation(),
              acceptingOutputReceipt.ownerIdentity
                == capabilityOwnerIdentity,
              acceptingOutputReceipt.repositoryBinding.physicalRootIdentity
                != nil,
              delivery.storeIdentity
                == acceptingOutputReceipt.deliveryStoreIdentity,
              delivery.record.hasExactFailedRetryAcceptance(
                as: preparation,
                retryID: acceptingOutputReceipt.retryOperation.retryID
              ),
              delivery.record.historyWrite?.state == .pending,
              policy.state
                == preparation.historyCapture?.policyReceipt.state else {
            throw IOSAcceptedHistoryError.compareAndSwapFailed
        }
        try requireNoPruneUncertainty()
        let candidate = try IOSAcceptedHistoryCandidate(
            delivery: delivery,
            policy: policy,
            permitsExpiredRetryRecovery: true
        )
        return try decideUpsert(candidate)
    }

    /// For store-minted replacement replay, an absent capacity loser is not a
    /// standalone durable History mutation. Its sealed receipt becomes durable
    /// only with the matching delivery-marker CAS, eliminating a crash gap in
    /// which a later capacity change could reinterpret an earlier decision.
    func decideReplayableReplacement(
        delivery: IOSAcceptedOutputDeliveryAuthorization,
        policy: IOSHistoryPolicyReceipt
    ) throws -> IOSAcceptedHistoryRowReceipt {
        try requireOwners(delivery, policy)
        guard delivery.record.historyWrite?.state
                == .pendingReplacement else {
            throw IOSAcceptedHistoryError.compareAndSwapFailed
        }
        try requireNoPruneUncertainty()
        let candidate = try IOSAcceptedHistoryCandidate(
            delivery: delivery,
            policy: policy
        )
        return try decideReplayableReplacement(candidate)
    }

    func decideUpsert(
        outbox: IOSAcceptedHistoryOutboxReceipt,
        policy: IOSHistoryPolicyReceipt
    ) throws -> IOSAcceptedHistoryRowReceipt {
        try requireOwners(outbox, policy)
        try requireNoPruneUncertainty()
        let candidate = try IOSAcceptedHistoryCandidate(
            outbox: outbox,
            policy: policy
        )
        return try decideUpsert(candidate)
    }

    /// Relaunch recovery never inserts an absent row. Exact immutable
    /// membership is identically rewritten before a new receipt is issued.
    func confirmMembership(
        delivery: IOSAcceptedOutputDeliveryAuthorization,
        policy: IOSHistoryPolicyReceipt
    ) throws -> IOSAcceptedHistoryRowReceipt {
        try requireOwners(delivery, policy)
        try requireNoPruneUncertainty()
        let candidate = try IOSAcceptedHistoryCandidate(
            delivery: delivery,
            policy: policy
        )
        return try confirmMembership(candidate)
    }

    func confirmMembership(
        outbox: IOSAcceptedHistoryOutboxReceipt,
        policy: IOSHistoryPolicyReceipt
    ) throws -> IOSAcceptedHistoryRowReceipt {
        try requireOwners(outbox, policy)
        try requireNoPruneUncertainty()
        let candidate = try IOSAcceptedHistoryCandidate(
            outbox: outbox,
            policy: policy
        )
        return try confirmMembership(candidate)
    }

    func pruneInvalidatedRows(
        using policy: IOSHistoryPolicyReceipt
    ) throws {
        guard policy.capabilityOwnerIdentity == capabilityOwnerIdentity else {
            throw IOSAcceptedHistoryError.compareAndSwapFailed
        }
        if let uncertainPruneIntent {
            guard policy == uncertainPruneIntent.policy else {
                throw IOSAcceptedHistoryError.commitUncertain
            }
            return try reconcilePrune(
                uncertainPruneIntent,
                current: try journal.load()
            )
        }
        guard uncertainIntent == nil else {
            throw IOSAcceptedHistoryError.commitUncertain
        }
        guard let current = try journal.load() else { return }
        let outcome = try pruneOutcome(
            current.envelope,
            policyGeneration: policy.state.policyGeneration
        )
        try publishPrune(
            outcome,
            source: current,
            policy: policy
        )
    }

    @discardableResult
    func performStagingMaintenance()
        throws -> IOSAcceptedHistoryMaintenanceReport {
        try requireNoPruneUncertainty()
        return IOSAcceptedHistoryMaintenanceReport(
            try journal.performStagingMaintenance(now: now())
        )
    }
}

private extension IOSAcceptedHistoryStore {
    private enum TemporalState: Equatable {
        case live
        case expired
        case clockRollbackAmbiguous
    }

    func requireOwners(
        _ delivery: IOSAcceptedOutputDeliveryAuthorization,
        _ policy: IOSHistoryPolicyReceipt
    ) throws {
        guard delivery.capabilityOwnerIdentity == capabilityOwnerIdentity,
              policy.capabilityOwnerIdentity == capabilityOwnerIdentity else {
            throw IOSAcceptedHistoryError.compareAndSwapFailed
        }
    }

    func requireOwners(
        _ outbox: IOSAcceptedHistoryOutboxReceipt,
        _ policy: IOSHistoryPolicyReceipt
    ) throws {
        guard outbox.capabilityOwnerIdentity == capabilityOwnerIdentity,
              policy.capabilityOwnerIdentity == capabilityOwnerIdentity else {
            throw IOSAcceptedHistoryError.compareAndSwapFailed
        }
    }

    private func requireNoPruneUncertainty() throws {
        guard uncertainPruneIntent == nil else {
            throw IOSAcceptedHistoryError.commitUncertain
        }
    }

    private func pruneOutcome(
        _ source: IOSAcceptedHistoryEnvelope,
        policyGeneration: Int64
    ) throws -> IOSAcceptedHistoryEnvelope {
        guard source.entries.allSatisfy({
            $0.policyGeneration <= policyGeneration
        }) else {
            throw IOSAcceptedHistoryError.stalePolicyGeneration
        }
        let entries = source.entries.filter {
            $0.policyGeneration == policyGeneration
        }
        guard entries != source.entries else { return source }
        let nextRevision = source.revision.addingReportingOverflow(1)
        guard !nextRevision.overflow else {
            throw IOSAcceptedHistoryError.revisionOverflow
        }
        return try IOSAcceptedHistoryEnvelope(
            revision: nextRevision.partialValue,
            entries: entries
        )
    }

    private func publishPrune(
        _ outcome: IOSAcceptedHistoryEnvelope,
        source: IOSAcceptedHistoryJournalSnapshot,
        policy: IOSHistoryPolicyReceipt
    ) throws {
        let intent = UncertainPruneIntent(
            source: source,
            policy: policy,
            outcome: outcome
        )
        do {
            let snapshot = try journal.replace(
                outcome,
                expected: source,
                authorization: IOSAcceptedHistoryJournalMutationAuthorization()
            )
            guard snapshot.envelope == outcome else {
                uncertainPruneIntent = intent
                throw IOSAcceptedHistoryError.commitUncertain
            }
            uncertainPruneIntent = nil
        } catch IOSAcceptedHistoryError.commitUncertain {
            uncertainPruneIntent = intent
            throw IOSAcceptedHistoryError.commitUncertain
        }
    }

    private func reconcilePrune(
        _ intent: UncertainPruneIntent,
        current: IOSAcceptedHistoryJournalSnapshot?
    ) throws {
        let sourceStillCurrent = current == intent.source
        if let current,
           current.envelope == intent.outcome,
           !sourceStillCurrent {
            return try publishPrune(
                intent.outcome,
                source: current,
                policy: intent.policy
            )
        }
        guard let current, sourceStillCurrent else {
            uncertainPruneIntent = nil
            throw IOSAcceptedHistoryError.compareAndSwapFailed
        }
        let revalidated = try pruneOutcome(
            current.envelope,
            policyGeneration: intent.policy.state.policyGeneration
        )
        guard revalidated == intent.outcome else {
            uncertainPruneIntent = nil
            throw IOSAcceptedHistoryError.compareAndSwapFailed
        }
        return try publishPrune(
            intent.outcome,
            source: current,
            policy: intent.policy
        )
    }

    private func decideUpsert(
        _ candidate: IOSAcceptedHistoryCandidate
    ) throws -> IOSAcceptedHistoryRowReceipt {
        let current = try journal.load()

        if let uncertainIntent {
            return try reconcileDecision(
                uncertainIntent,
                candidate: candidate,
                current: current
            )
        }

        if let current {
            let next = try outcome(candidate, from: current.envelope)
            try requireLiveSourceIfNeeded(next, candidate: candidate)
            return try publish(
                next,
                source: .existing(current),
                candidate: candidate
            )
        }

        let initial = try initialOutcome(candidate)
        try requireLiveSourceIfNeeded(initial, candidate: candidate)
        do {
            return try publish(
                initial,
                source: .missing,
                candidate: candidate
            )
        } catch IOSAcceptedHistoryError.slotOccupied {
            guard let raced = try journal.load() else {
                throw IOSAcceptedHistoryError.compareAndSwapFailed
            }
            let next = try outcome(candidate, from: raced.envelope)
            try requireLiveSourceIfNeeded(next, candidate: candidate)
            return try publish(
                next,
                source: .existing(raced),
                candidate: candidate
            )
        }
    }

    private func decideReplayableReplacement(
        _ candidate: IOSAcceptedHistoryCandidate
    ) throws -> IOSAcceptedHistoryRowReceipt {
        let current = try journal.load()

        if let uncertainIntent {
            return try reconcileDecision(
                uncertainIntent,
                candidate: candidate,
                current: current
            )
        }

        if let current {
            let next = try outcome(candidate, from: current.envelope)
            try requireLiveSourceIfNeeded(next, candidate: candidate)
            if next.retainedEntry == nil {
                return try preparedNotRetainedReceipt(
                    candidate: candidate,
                    snapshot: current,
                    outcome: next
                )
            }
            return try publish(
                next,
                source: .existing(current),
                candidate: candidate
            )
        }

        let initial = try initialOutcome(candidate)
        try requireLiveSourceIfNeeded(initial, candidate: candidate)
        do {
            return try publish(
                initial,
                source: .missing,
                candidate: candidate
            )
        } catch IOSAcceptedHistoryError.slotOccupied {
            guard let raced = try journal.load() else {
                throw IOSAcceptedHistoryError.compareAndSwapFailed
            }
            let next = try outcome(candidate, from: raced.envelope)
            try requireLiveSourceIfNeeded(next, candidate: candidate)
            if next.retainedEntry == nil {
                return try preparedNotRetainedReceipt(
                    candidate: candidate,
                    snapshot: raced,
                    outcome: next
                )
            }
            return try publish(
                next,
                source: .existing(raced),
                candidate: candidate
            )
        }
    }

    private func preparedNotRetainedReceipt(
        candidate: IOSAcceptedHistoryCandidate,
        snapshot: IOSAcceptedHistoryJournalSnapshot,
        outcome: Outcome
    ) throws -> IOSAcceptedHistoryRowReceipt {
        let identicalSourceConfirmation = Outcome(
            envelope: snapshot.envelope,
            retainedEntry: nil,
            requiresLiveSource: outcome.requiresLiveSource
        )
        return try publish(
            identicalSourceConfirmation,
            source: .existing(snapshot),
            candidate: candidate,
            receiptMode: .preparedNotRetained
        )
    }

    private func confirmMembership(
        _ candidate: IOSAcceptedHistoryCandidate
    ) throws -> IOSAcceptedHistoryRowReceipt {
        let current = try journal.load()

        if let uncertainIntent {
            return try reconcileMembershipConfirmation(
                uncertainIntent,
                candidate: candidate,
                current: current
            )
        }

        guard let current else {
            throw IOSAcceptedHistoryError.compareAndSwapFailed
        }
        let retained = try exactMembership(
            of: candidate,
            in: current.envelope
        )
        try requireNoFuturePolicyGeneration(
            in: current.envelope,
            candidate: candidate
        )
        return try publish(
            Outcome(
                envelope: current.envelope,
                retainedEntry: retained,
                requiresLiveSource: false
            ),
            source: .existing(current),
            candidate: candidate
        )
    }

    private func initialOutcome(
        _ candidate: IOSAcceptedHistoryCandidate
    ) throws -> Outcome {
        let entries = try trimToEncodedLimit(
            [candidate.entry],
            revision: 1
        )
        let envelope = try IOSAcceptedHistoryEnvelope(
            revision: 1,
            entries: entries
        )
        return Outcome(
            envelope: envelope,
            retainedEntry: retainedEntry(candidate, in: entries),
            requiresLiveSource: true
        )
    }

    private func outcome(
        _ candidate: IOSAcceptedHistoryCandidate,
        from current: IOSAcceptedHistoryEnvelope
    ) throws -> Outcome {
        let duplicate = current.entries.first(where: {
            $0.deliveryID == candidate.entry.deliveryID
        })
        if let duplicate {
            guard duplicate.hasSameImmutableBytes(as: candidate.entry) else {
                throw IOSAcceptedHistoryError.collision
            }
        } else {
            guard !current.entries.contains(where: {
                $0.transcriptID == candidate.entry.transcriptID
            }) else {
                throw IOSAcceptedHistoryError.collision
            }
        }
        try requireNoFuturePolicyGeneration(
            in: current,
            candidate: candidate
        )
        if let duplicate {
            return Outcome(
                envelope: current,
                retainedEntry: duplicate,
                requiresLiveSource: false
            )
        }

        var entries = current.entries.filter {
            $0.policyGeneration == candidate.entry.policyGeneration
        }
        entries.append(candidate.entry)
        entries = IOSAcceptedHistoryValidation.sorted(entries)
        if entries.count > IOSAcceptedHistoryValidation.maximumEntryCount {
            entries.removeLast(
                entries.count - IOSAcceptedHistoryValidation.maximumEntryCount
            )
        }

        let provisionalRevision: Int64
        if current.revision == Int64.max {
            provisionalRevision = current.revision
        } else {
            provisionalRevision = current.revision + 1
        }
        entries = try trimMutationToEncodedLimit(
            entries,
            provisionalRevision: provisionalRevision,
            current: current
        )

        let revision: Int64
        if entries == current.entries {
            revision = current.revision
        } else {
            let next = current.revision.addingReportingOverflow(1)
            guard !next.overflow else {
                throw IOSAcceptedHistoryError.revisionOverflow
            }
            revision = next.partialValue
        }
        let envelope = try IOSAcceptedHistoryEnvelope(
            revision: revision,
            entries: entries
        )
        return Outcome(
            envelope: envelope,
            retainedEntry: retainedEntry(candidate, in: entries),
            requiresLiveSource: true
        )
    }

    private func trimToEncodedLimit(
        _ source: [IOSAcceptedHistoryEntry],
        revision: Int64
    ) throws -> [IOSAcceptedHistoryEntry] {
        var entries = source
        while true {
            let envelope = try IOSAcceptedHistoryEnvelope(
                revision: revision,
                entries: entries
            )
            if try IOSAcceptedHistoryWireCodec.isWithinEncodedLimit(envelope) {
                return entries
            }
            guard !entries.isEmpty else {
                throw IOSAcceptedHistoryError.writeFailed
            }
            entries.removeLast()
        }
    }

    private func trimMutationToEncodedLimit(
        _ source: [IOSAcceptedHistoryEntry],
        provisionalRevision: Int64,
        current: IOSAcceptedHistoryEnvelope
    ) throws -> [IOSAcceptedHistoryEntry] {
        var entries = source
        while true {
            if entries == current.entries {
                guard try IOSAcceptedHistoryWireCodec
                    .isWithinEncodedLimit(current) else {
                    throw IOSAcceptedHistoryError.invalidRecord
                }
                return entries
            }
            let envelope = try IOSAcceptedHistoryEnvelope(
                revision: provisionalRevision,
                entries: entries
            )
            if try IOSAcceptedHistoryWireCodec.isWithinEncodedLimit(envelope) {
                return entries
            }
            guard !entries.isEmpty else {
                throw IOSAcceptedHistoryError.writeFailed
            }
            entries.removeLast()
        }
    }

    private func exactMembership(
        of candidate: IOSAcceptedHistoryCandidate,
        in envelope: IOSAcceptedHistoryEnvelope
    ) throws -> IOSAcceptedHistoryEntry {
        if let row = envelope.entries.first(where: {
            $0.deliveryID == candidate.entry.deliveryID
        }) {
            guard row.hasSameImmutableBytes(as: candidate.entry) else {
                throw IOSAcceptedHistoryError.collision
            }
            return row
        }
        if envelope.entries.contains(where: {
            $0.transcriptID == candidate.entry.transcriptID
        }) {
            throw IOSAcceptedHistoryError.collision
        }
        throw IOSAcceptedHistoryError.compareAndSwapFailed
    }

    private func retainedEntry(
        _ candidate: IOSAcceptedHistoryCandidate,
        in entries: [IOSAcceptedHistoryEntry]
    ) -> IOSAcceptedHistoryEntry? {
        entries.first {
            $0.deliveryID == candidate.entry.deliveryID
                && $0.hasSameImmutableBytes(as: candidate.entry)
        }
    }

    private func requireNoFuturePolicyGeneration(
        in envelope: IOSAcceptedHistoryEnvelope,
        candidate: IOSAcceptedHistoryCandidate
    ) throws {
        guard envelope.entries.allSatisfy({
            $0.policyGeneration <= candidate.entry.policyGeneration
        }) else {
            throw IOSAcceptedHistoryError.stalePolicyGeneration
        }
    }

    private func publish(
        _ outcome: Outcome,
        source: Source,
        candidate: IOSAcceptedHistoryCandidate,
        receiptMode: ReceiptMode = .durableDecision
    ) throws -> IOSAcceptedHistoryRowReceipt {
        let intent = UncertainIntent(
            source: source,
            candidate: candidate,
            outcome: outcome,
            receiptMode: receiptMode
        )
        do {
            let snapshot: IOSAcceptedHistoryJournalSnapshot = switch source {
            case .missing:
                try journal.create(
                    outcome.envelope,
                    authorization:
                        IOSAcceptedHistoryJournalMutationAuthorization()
                )
            case .existing(let current):
                try journal.replace(
                    outcome.envelope,
                    expected: current,
                    authorization:
                        IOSAcceptedHistoryJournalMutationAuthorization()
                )
            }
            guard snapshot.envelope == outcome.envelope else {
                uncertainIntent = intent
                throw IOSAcceptedHistoryError.commitUncertain
            }
            let receiptOutcome: IOSAcceptedHistoryReceiptOutcome =
                if let retained = outcome.retainedEntry {
                    .retained(retained)
                } else {
                    switch receiptMode {
                    case .durableDecision: .notRetained
                    case .preparedNotRetained: .preparedNotRetained
                    }
                }
            let receipt = IOSAcceptedHistoryRowReceipt(
                candidate: candidate,
                snapshot: snapshot,
                outcome: receiptOutcome,
                capabilityOwnerIdentity: capabilityOwnerIdentity
            )
            guard receipt.snapshotMatchesOutcome else {
                uncertainIntent = intent
                throw IOSAcceptedHistoryError.commitUncertain
            }
            uncertainIntent = nil
            return receipt
        } catch IOSAcceptedHistoryError.commitUncertain {
            uncertainIntent = intent
            throw IOSAcceptedHistoryError.commitUncertain
        }
    }

    private func reconcileDecision(
        _ intent: UncertainIntent,
        candidate: IOSAcceptedHistoryCandidate,
        current: IOSAcceptedHistoryJournalSnapshot?
    ) throws -> IOSAcceptedHistoryRowReceipt {
        guard candidate == intent.candidate else {
            throw IOSAcceptedHistoryError.commitUncertain
        }

        let sourceStillCurrent: Bool = switch (intent.source, current) {
        case (.missing, .none): true
        case (.existing(let source), .some(let current)): source == current
        default: false
        }

        if let current,
           current.envelope == intent.outcome.envelope,
           !sourceStillCurrent {
            return try publish(
                intent.outcome,
                source: .existing(current),
                candidate: candidate,
                receiptMode: intent.receiptMode
            )
        }

        guard sourceStillCurrent else {
            uncertainIntent = nil
            throw IOSAcceptedHistoryError.compareAndSwapFailed
        }

        do {
            try requireLiveSourceIfNeeded(
                intent.outcome,
                candidate: candidate
            )
        } catch IOSAcceptedHistoryError.expired {
            uncertainIntent = nil
            throw IOSAcceptedHistoryError.expired
        }

        switch intent.source {
        case .missing:
            return try publish(
                intent.outcome,
                source: .missing,
                candidate: candidate,
                receiptMode: intent.receiptMode
            )
        case .existing:
            guard let current else {
                uncertainIntent = nil
                throw IOSAcceptedHistoryError.compareAndSwapFailed
            }
            return try publish(
                intent.outcome,
                source: .existing(current),
                candidate: candidate,
                receiptMode: intent.receiptMode
            )
        }
    }

    private func reconcileMembershipConfirmation(
        _ intent: UncertainIntent,
        candidate: IOSAcceptedHistoryCandidate,
        current: IOSAcceptedHistoryJournalSnapshot?
    ) throws -> IOSAcceptedHistoryRowReceipt {
        guard candidate == intent.candidate else {
            throw IOSAcceptedHistoryError.commitUncertain
        }
        guard let current else {
            throw IOSAcceptedHistoryError.commitUncertain
        }
        guard current.envelope == intent.outcome.envelope else {
            let sourceStillCurrent: Bool = switch intent.source {
            case .missing: false
            case .existing(let source): source == current
            }
            if sourceStillCurrent {
                throw IOSAcceptedHistoryError.commitUncertain
            }
            uncertainIntent = nil
            throw IOSAcceptedHistoryError.compareAndSwapFailed
        }
        guard intent.outcome.retainedEntry != nil else {
            _ = try publish(
                intent.outcome,
                source: .existing(current),
                candidate: candidate,
                receiptMode: intent.receiptMode
            )
            throw IOSAcceptedHistoryError.compareAndSwapFailed
        }
        return try publish(
            intent.outcome,
            source: .existing(current),
            candidate: candidate,
            receiptMode: intent.receiptMode
        )
    }

    private func requireLiveSourceIfNeeded(
        _ outcome: Outcome,
        candidate: IOSAcceptedHistoryCandidate
    ) throws {
        guard outcome.requiresLiveSource else { return }
        switch temporalState(of: candidate, at: try currentTime()) {
        case .live:
            return
        case .expired:
            guard candidate.permitsExpiredRetryRecovery else {
                throw IOSAcceptedHistoryError.expired
            }
        case .clockRollbackAmbiguous:
            throw IOSAcceptedHistoryError.clockRollbackAmbiguous
        }
    }

    private func currentTime() throws -> Date {
        do {
            return try IOSAcceptedOutputDeliveryTimestampCodec.canonicalDate(
                from: now()
            )
        } catch {
            throw IOSAcceptedHistoryError.clockRollbackAmbiguous
        }
    }

    private func temporalState(
        of candidate: IOSAcceptedHistoryCandidate,
        at now: Date
    ) -> TemporalState {
        if now < candidate.entry.createdAt {
            return .clockRollbackAmbiguous
        }
        if now >= candidate.expiresAt {
            return .expired
        }
        return .live
    }
}
