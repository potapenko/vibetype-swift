import Foundation

struct IOSAcceptedHistoryOutboxGuardedBaselineEvidence: Sendable {
    fileprivate init() {}
}

extension IOSAcceptedHistoryOutboxGuardedBaselineEvidence:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedHistoryOutboxGuardedBaselineEvidence(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSAcceptedHistoryOutboxJournalMutationAuthorization: Sendable {
    fileprivate init() {}
}

fileprivate struct IOSAcceptedHistoryOutboxCandidate: Equatable, Sendable {
    let delivery: IOSAcceptedOutputDeliveryAuthorization
    let entry: IOSAcceptedHistoryOutboxEntry

    init(delivery: IOSAcceptedOutputDeliveryAuthorization) throws {
        let record = delivery.record
        guard let marker = record.historyWrite,
              marker.state == .pending,
              let acceptedText = record.acceptedText else {
            throw IOSAcceptedHistoryOutboxError.stalePolicyGeneration
        }
        self.delivery = delivery
        entry = try Self.makeEntry(
            record: record,
            marker: marker,
            acceptedText: acceptedText
        )
    }

    static func entry(
        from delivery: IOSAcceptedOutputDeliveryAuthorization
    ) throws -> IOSAcceptedHistoryOutboxEntry {
        let record = delivery.record
        guard let marker = record.historyWrite,
              marker.state == .pending,
              let acceptedText = record.acceptedText else {
            throw IOSAcceptedHistoryOutboxError.stalePolicyGeneration
        }
        return try makeEntry(
            record: record,
            marker: marker,
            acceptedText: acceptedText
        )
    }

    private static func makeEntry(
        record: IOSAcceptedOutputDeliveryRecord,
        marker: IOSAcceptedOutputHistoryWrite,
        acceptedText: String
    ) throws -> IOSAcceptedHistoryOutboxEntry {
        try IOSAcceptedHistoryOutboxEntry(
            deliveryID: record.deliveryID,
            transcriptID: record.transcriptID,
            acceptedText: acceptedText,
            outputIntent: record.outputIntent,
            createdAt: record.createdAt,
            expiresAt: record.expiresAt,
            policyGeneration: marker.policyGeneration,
            transcriptionModel: marker.transcriptionModel,
            transcriptionLanguageCode: marker.transcriptionLanguageCode,
            durationMilliseconds: marker.durationMilliseconds
        )
    }
}

extension IOSAcceptedHistoryOutboxCandidate: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedHistoryOutboxCandidate(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

fileprivate enum IOSAcceptedHistoryOutboxReceiptOrigin: Equatable, Sendable {
    case delivery(IOSAcceptedOutputDeliveryAuthorization)
    case observation(IOSAcceptedHistoryOutboxObservation)
}

struct IOSAcceptedHistoryOutboxReceipt: Equatable, Sendable {
    fileprivate let origin: IOSAcceptedHistoryOutboxReceiptOrigin
    fileprivate let entry: IOSAcceptedHistoryOutboxEntry
    fileprivate let snapshot: IOSAcceptedHistoryOutboxJournalSnapshot

    func provesMembershipForDeliveryRemoval(
        for delivery: IOSAcceptedOutputDeliveryAuthorization
    ) -> Bool {
        guard case .delivery(let originatingDelivery) = origin,
              originatingDelivery == delivery else {
            return false
        }
        return confirmedEntryForAcceptedDecision() != nil
    }

    func provesMembership(
        for observation: IOSAcceptedHistoryOutboxObservation
    ) -> Bool {
        guard case .observation(let originatingObservation) = origin,
              originatingObservation == observation else {
            return false
        }
        return confirmedEntryForAcceptedDecision() != nil
    }

    func confirmedEntryForAcceptedDecision()
        -> IOSAcceptedHistoryOutboxEntry? {
        let originatingEntry: IOSAcceptedHistoryOutboxEntry
        switch origin {
        case .delivery(let delivery):
            guard let expected = try? IOSAcceptedHistoryOutboxCandidate.entry(
                from: delivery
            ) else {
                return nil
            }
            originatingEntry = expected
        case .observation(let observation):
            originatingEntry = observation.entry
        }
        guard entry.hasSameImmutableBytes(as: originatingEntry),
              snapshot.envelope.entries.contains(where: {
                  $0.hasSameImmutableBytes(as: entry)
              }) else {
            return nil
        }
        return entry
    }
}

extension IOSAcceptedHistoryOutboxReceipt: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSAcceptedHistoryOutboxReceipt(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSAcceptedHistoryOutboxObservation: Equatable, Sendable {
    let entry: IOSAcceptedHistoryOutboxEntry
    fileprivate let snapshot: IOSAcceptedHistoryOutboxJournalSnapshot

    fileprivate init(
        entry: IOSAcceptedHistoryOutboxEntry,
        snapshot: IOSAcceptedHistoryOutboxJournalSnapshot
    ) {
        self.entry = entry
        self.snapshot = snapshot
    }
}

extension IOSAcceptedHistoryOutboxObservation: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedHistoryOutboxObservation(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Internal ownership primitive. The coordinator supplies confirmed delivery
/// and policy capabilities and later consumes the exact membership receipt.
actor IOSAcceptedHistoryOutboxStore {
    private enum Source: Equatable, Sendable {
        case missing
        case existing(IOSAcceptedHistoryOutboxJournalSnapshot)
    }

    private struct Outcome: Equatable, Sendable {
        let envelope: IOSAcceptedHistoryOutboxEnvelope
    }

    private enum Operation: Equatable, Sendable {
        case transfer(IOSAcceptedHistoryOutboxCandidate)
        case deliveryConfirmation(IOSAcceptedHistoryOutboxCandidate)
        case observationConfirmation(IOSAcceptedHistoryOutboxObservation)
        case processedRetirement(
            IOSAcceptedHistoryOutboxReceipt,
            IOSAcceptedHistoryRowReceipt
        )
        case invalidatedRetirement(
            IOSAcceptedHistoryOutboxReceipt,
            IOSHistoryPolicyReceipt
        )
        case expiredRetirement(IOSAcceptedHistoryOutboxReceipt)

        var entry: IOSAcceptedHistoryOutboxEntry {
            switch self {
            case .transfer(let candidate): candidate.entry
            case .deliveryConfirmation(let candidate): candidate.entry
            case .observationConfirmation(let observation):
                observation.entry
            case .processedRetirement(let membership, _),
                 .invalidatedRetirement(let membership, _),
                 .expiredRetirement(let membership):
                membership.entry
            }
        }

        var receiptOrigin: IOSAcceptedHistoryOutboxReceiptOrigin {
            switch self {
            case .transfer(let candidate),
                 .deliveryConfirmation(let candidate):
                .delivery(candidate.delivery)
            case .observationConfirmation(let observation):
                .observation(observation)
            case .processedRetirement, .invalidatedRetirement,
                 .expiredRetirement:
                preconditionFailure(
                    "Retirement operations never issue membership receipts"
                )
            }
        }

        var isRetirement: Bool {
            switch self {
            case .transfer, .deliveryConfirmation,
                 .observationConfirmation:
                false
            case .processedRetirement, .invalidatedRetirement,
                 .expiredRetirement:
                true
            }
        }

        var retirementMembership: IOSAcceptedHistoryOutboxReceipt {
            switch self {
            case .processedRetirement(let membership, _),
                 .invalidatedRetirement(let membership, _),
                 .expiredRetirement(let membership):
                membership
            case .transfer, .deliveryConfirmation,
                 .observationConfirmation:
                preconditionFailure(
                    "Membership operations never retire outbox entries"
                )
            }
        }
    }

    private struct UncertainIntent: Equatable, Sendable {
        let source: Source
        let operation: Operation
        let outcome: Outcome
    }

    private let journal: any IOSAcceptedHistoryOutboxJournalStoring
    private let now: @Sendable () -> Date
    private var uncertainIntent: UncertainIntent?

    init(applicationSupportDirectoryURL: URL) {
        journal = FoundationIOSAcceptedHistoryOutboxJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        now = { Date() }
    }

    init(
        journal: any IOSAcceptedHistoryOutboxJournalStoring,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.journal = journal
        self.now = now
    }

    func load() throws -> IOSAcceptedHistoryOutboxEnvelope? {
        guard uncertainIntent?.operation.isRetirement != true else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        return try journal.load()?.envelope
    }

    func proveGuardedBaseline()
        throws -> IOSAcceptedHistoryOutboxGuardedBaselineEvidence {
        guard uncertainIntent == nil else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        guard try journal.load()?.envelope.entries.isEmpty != false else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        return IOSAcceptedHistoryOutboxGuardedBaselineEvidence()
    }

    func observe() throws -> [IOSAcceptedHistoryOutboxObservation]? {
        guard uncertainIntent == nil else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        guard let snapshot = try journal.load() else { return nil }
        return snapshot.envelope.entries.map {
            IOSAcceptedHistoryOutboxObservation(
                entry: $0,
                snapshot: snapshot
            )
        }
    }

    func transfer(
        delivery: IOSAcceptedOutputDeliveryAuthorization,
        policy: IOSHistoryPolicyReceipt
    ) throws -> IOSAcceptedHistoryOutboxReceipt {
        guard uncertainIntent?.operation.isRetirement != true else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        let candidate = try IOSAcceptedHistoryOutboxCandidate(
            delivery: delivery
        )
        guard policy.state.historyEnabled,
              candidate.entry.policyGeneration
                == policy.state.policyGeneration else {
            throw IOSAcceptedHistoryOutboxError.stalePolicyGeneration
        }
        let current = try journal.load()

        if let uncertainIntent {
            return try reconcileTransfer(
                uncertainIntent,
                candidate: candidate,
                current: current
            )
        }

        let temporalSnapshot = try currentTime()
        try requireLive(candidate.entry, at: temporalSnapshot)

        if let current {
            let outcome = try outcome(
                candidate,
                from: current.envelope,
                policyGeneration: policy.state.policyGeneration,
                now: temporalSnapshot
            )
            return try publish(
                outcome,
                source: .existing(current),
                operation: .transfer(candidate)
            )
        }

        let initial = try initialOutcome(candidate)
        do {
            return try publish(
                initial,
                source: .missing,
                operation: .transfer(candidate)
            )
        } catch IOSAcceptedHistoryOutboxError.slotOccupied {
            guard let raced = try journal.load() else {
                throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
            }
            return try publish(
                outcome(
                    candidate,
                    from: raced.envelope,
                    policyGeneration: policy.state.policyGeneration,
                    now: temporalSnapshot
                ),
                source: .existing(raced),
                operation: .transfer(candidate)
            )
        }
    }

    func confirmMembership(
        delivery: IOSAcceptedOutputDeliveryAuthorization
    ) throws -> IOSAcceptedHistoryOutboxReceipt {
        guard uncertainIntent?.operation.isRetirement != true else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        let candidate = try IOSAcceptedHistoryOutboxCandidate(
            delivery: delivery
        )
        let current = try journal.load()

        if let uncertainIntent {
            guard !uncertainIntent.operation.isRetirement else {
                throw IOSAcceptedHistoryOutboxError.commitUncertain
            }
            return try reconcileConfirmation(
                uncertainIntent,
                entry: candidate.entry,
                current: current
            )
        }

        guard let current else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        _ = try exactMembership(of: candidate, in: current.envelope)
        return try publish(
            Outcome(envelope: current.envelope),
            source: .existing(current),
            operation: .deliveryConfirmation(candidate)
        )
    }

    func confirmMembership(
        observation: IOSAcceptedHistoryOutboxObservation
    ) throws -> IOSAcceptedHistoryOutboxReceipt {
        guard uncertainIntent?.operation.isRetirement != true else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        let current = try journal.load()

        if let uncertainIntent {
            switch uncertainIntent.operation {
            case .observationConfirmation(let intendedObservation):
                guard observation == intendedObservation else {
                    throw IOSAcceptedHistoryOutboxError.commitUncertain
                }
            case .transfer, .deliveryConfirmation:
                guard current == observation.snapshot else {
                    throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
                }
            case .processedRetirement, .invalidatedRetirement,
                 .expiredRetirement:
                throw IOSAcceptedHistoryOutboxError.commitUncertain
            }
            return try reconcileConfirmation(
                uncertainIntent,
                entry: observation.entry,
                current: current
            )
        }

        guard let current,
              current == observation.snapshot else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        guard current.envelope.entries.contains(where: {
            $0.hasSameImmutableBytes(as: observation.entry)
        }) else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        return try publish(
            Outcome(envelope: current.envelope),
            source: .existing(current),
            operation: .observationConfirmation(observation)
        )
    }

    func retireProcessed(
        membership: IOSAcceptedHistoryOutboxReceipt,
        decision: IOSAcceptedHistoryRowReceipt
    ) throws {
        try retire(
            operation: .processedRetirement(membership, decision)
        )
    }

    func retireInvalidated(
        membership: IOSAcceptedHistoryOutboxReceipt,
        policy: IOSHistoryPolicyReceipt
    ) throws {
        try retire(
            operation: .invalidatedRetirement(membership, policy)
        )
    }

    func retireExpired(
        membership: IOSAcceptedHistoryOutboxReceipt
    ) throws {
        try retire(operation: .expiredRetirement(membership))
    }

    @discardableResult
    func performStagingMaintenance()
        throws -> IOSAcceptedHistoryOutboxMaintenanceReport {
        guard uncertainIntent?.operation.isRetirement != true else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        return IOSAcceptedHistoryOutboxMaintenanceReport(
            try journal.performStagingMaintenance(now: now())
        )
    }
}

private extension IOSAcceptedHistoryOutboxStore {
    private func retire(operation: Operation) throws {
        precondition(operation.isRetirement)
        if let uncertainIntent,
           (uncertainIntent.operation != operation
            || !uncertainIntent.operation.isRetirement) {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        let current = try journal.load()

        if let uncertainIntent {
            return try reconcileRetirement(
                uncertainIntent,
                operation: operation,
                current: current
            )
        }

        guard let current else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        let entry = try requireRetirementMembership(
            operation.retirementMembership,
            current: current
        )
        try validateRetirementAuthority(operation, entry: entry)
        let outcome = try retirementOutcome(
            removing: entry,
            from: current.envelope
        )
        try publishRetirement(
            outcome,
            source: current,
            operation: operation
        )
    }

    private func requireRetirementMembership(
        _ membership: IOSAcceptedHistoryOutboxReceipt,
        current: IOSAcceptedHistoryOutboxJournalSnapshot
    ) throws -> IOSAcceptedHistoryOutboxEntry {
        guard current == membership.snapshot,
              let confirmed = membership
                .confirmedEntryForAcceptedDecision() else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        return confirmed
    }

    private func validateRetirementAuthority(
        _ operation: Operation,
        entry: IOSAcceptedHistoryOutboxEntry
    ) throws {
        switch operation {
        case .processedRetirement(let membership, let decision):
            guard decision.provesDecision(for: membership) else {
                throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
            }
        case .invalidatedRetirement(_, let policy):
            guard policy.state.policyGeneration > entry.policyGeneration else {
                throw IOSAcceptedHistoryOutboxError.stalePolicyGeneration
            }
        case .expiredRetirement:
            switch entry.temporalState(at: try currentTime()) {
            case .expired:
                return
            case .live:
                throw IOSAcceptedHistoryOutboxError.invalidTransition
            case .clockRollbackAmbiguous:
                throw IOSAcceptedHistoryOutboxError.clockRollbackAmbiguous
            }
        case .transfer, .deliveryConfirmation,
             .observationConfirmation:
            preconditionFailure("Expected a retirement operation")
        }
    }

    private func retirementOutcome(
        removing entry: IOSAcceptedHistoryOutboxEntry,
        from source: IOSAcceptedHistoryOutboxEnvelope
    ) throws -> Outcome {
        guard let index = source.entries.firstIndex(where: {
            $0.hasSameImmutableBytes(as: entry)
        }) else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        let nextRevision = source.revision.addingReportingOverflow(1)
        guard !nextRevision.overflow else {
            throw IOSAcceptedHistoryOutboxError.revisionOverflow
        }
        var entries = source.entries
        entries.remove(at: index)
        return Outcome(
            envelope: try IOSAcceptedHistoryOutboxEnvelope(
                revision: nextRevision.partialValue,
                entries: entries
            )
        )
    }

    private func publishRetirement(
        _ outcome: Outcome,
        source: IOSAcceptedHistoryOutboxJournalSnapshot,
        operation: Operation
    ) throws {
        let intent = UncertainIntent(
            source: .existing(source),
            operation: operation,
            outcome: outcome
        )
        do {
            _ = try journal.replace(
                outcome.envelope,
                expected: source,
                authorization:
                    IOSAcceptedHistoryOutboxJournalMutationAuthorization()
            )
            uncertainIntent = nil
        } catch IOSAcceptedHistoryOutboxError.commitUncertain {
            uncertainIntent = intent
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
    }

    private func reconcileRetirement(
        _ intent: UncertainIntent,
        operation: Operation,
        current: IOSAcceptedHistoryOutboxJournalSnapshot?
    ) throws {
        guard intent.operation == operation,
              intent.operation.isRetirement else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }

        if let current,
           current.envelope == intent.outcome.envelope {
            return try publishRetirement(
                intent.outcome,
                source: current,
                operation: operation
            )
        }

        guard case .existing(let source) = intent.source,
              let current,
              current == source else {
            uncertainIntent = nil
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        let entry = try requireRetirementMembership(
            operation.retirementMembership,
            current: current
        )
        try validateRetirementAuthority(operation, entry: entry)
        return try publishRetirement(
            intent.outcome,
            source: current,
            operation: operation
        )
    }

    private func initialOutcome(
        _ candidate: IOSAcceptedHistoryOutboxCandidate
    ) throws -> Outcome {
        let envelope = try IOSAcceptedHistoryOutboxEnvelope(
            revision: 1,
            entries: [candidate.entry]
        )
        guard try IOSAcceptedHistoryOutboxWireCodec
            .isWithinEncodedLimit(envelope) else {
            throw IOSAcceptedHistoryOutboxError.capacityExceeded
        }
        return Outcome(envelope: envelope)
    }

    private func outcome(
        _ candidate: IOSAcceptedHistoryOutboxCandidate,
        from current: IOSAcceptedHistoryOutboxEnvelope,
        policyGeneration: Int64,
        now: Date
    ) throws -> Outcome {
        let duplicate = try collisionResult(
            candidate,
            in: current
        )
        try requireNoRollback(in: current, at: now)
        guard current.entries.allSatisfy({
            $0.policyGeneration <= policyGeneration
        }) else {
            throw IOSAcceptedHistoryOutboxError.stalePolicyGeneration
        }
        if duplicate != nil {
            return Outcome(envelope: current)
        }

        guard current.revision < Int64.max else {
            throw IOSAcceptedHistoryOutboxError.revisionOverflow
        }

        var entries = current.entries.filter { entry in
            entry.policyGeneration == policyGeneration
                && entry.temporalState(at: now) == .live
        }
        entries.append(candidate.entry)
        entries = IOSAcceptedHistoryOutboxValidation.sorted(entries)
        guard entries.count
                <= IOSAcceptedHistoryOutboxValidation.maximumEntryCount else {
            throw IOSAcceptedHistoryOutboxError.capacityExceeded
        }
        let envelope = try IOSAcceptedHistoryOutboxEnvelope(
            revision: current.revision + 1,
            entries: entries
        )
        guard try IOSAcceptedHistoryOutboxWireCodec
            .isWithinEncodedLimit(envelope) else {
            throw IOSAcceptedHistoryOutboxError.capacityExceeded
        }
        return Outcome(envelope: envelope)
    }

    private func collisionResult(
        _ candidate: IOSAcceptedHistoryOutboxCandidate,
        in envelope: IOSAcceptedHistoryOutboxEnvelope
    ) throws -> IOSAcceptedHistoryOutboxEntry? {
        if let existing = envelope.entries.first(where: {
            $0.deliveryID == candidate.entry.deliveryID
        }) {
            guard existing.hasSameImmutableBytes(as: candidate.entry) else {
                throw IOSAcceptedHistoryOutboxError.collision
            }
            return existing
        }
        guard !envelope.entries.contains(where: {
            $0.transcriptID == candidate.entry.transcriptID
        }) else {
            throw IOSAcceptedHistoryOutboxError.collision
        }
        return nil
    }

    private func exactMembership(
        of candidate: IOSAcceptedHistoryOutboxCandidate,
        in envelope: IOSAcceptedHistoryOutboxEnvelope
    ) throws -> IOSAcceptedHistoryOutboxEntry {
        if let existing = envelope.entries.first(where: {
            $0.deliveryID == candidate.entry.deliveryID
        }) {
            guard existing.hasSameImmutableBytes(as: candidate.entry) else {
                throw IOSAcceptedHistoryOutboxError.collision
            }
            return existing
        }
        if envelope.entries.contains(where: {
            $0.transcriptID == candidate.entry.transcriptID
        }) {
            throw IOSAcceptedHistoryOutboxError.collision
        }
        throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
    }

    private func currentTime() throws -> Date {
        do {
            return try IOSAcceptedOutputDeliveryTimestampCodec.canonicalDate(
                from: now()
            )
        } catch {
            throw IOSAcceptedHistoryOutboxError.clockRollbackAmbiguous
        }
    }

    private func requireLive(
        _ entry: IOSAcceptedHistoryOutboxEntry,
        at now: Date
    ) throws {
        switch entry.temporalState(at: now) {
        case .live:
            return
        case .expired:
            throw IOSAcceptedHistoryOutboxError.expired
        case .clockRollbackAmbiguous:
            throw IOSAcceptedHistoryOutboxError.clockRollbackAmbiguous
        }
    }

    private func requireNoRollback(
        in envelope: IOSAcceptedHistoryOutboxEnvelope,
        at now: Date
    ) throws {
        guard !envelope.entries.contains(where: {
            $0.temporalState(at: now) == .clockRollbackAmbiguous
        }) else {
            throw IOSAcceptedHistoryOutboxError.clockRollbackAmbiguous
        }
    }

    private func publish(
        _ outcome: Outcome,
        source: Source,
        operation: Operation
    ) throws -> IOSAcceptedHistoryOutboxReceipt {
        let intent = UncertainIntent(
            source: source,
            operation: operation,
            outcome: outcome
        )
        do {
            let snapshot: IOSAcceptedHistoryOutboxJournalSnapshot =
                switch source {
                case .missing:
                    try journal.create(
                        outcome.envelope,
                        authorization:
                            IOSAcceptedHistoryOutboxJournalMutationAuthorization()
                    )
                case .existing(let current):
                    try journal.replace(
                        outcome.envelope,
                        expected: current,
                        authorization:
                            IOSAcceptedHistoryOutboxJournalMutationAuthorization()
                    )
                }
            uncertainIntent = nil
            return IOSAcceptedHistoryOutboxReceipt(
                origin: operation.receiptOrigin,
                entry: operation.entry,
                snapshot: snapshot
            )
        } catch IOSAcceptedHistoryOutboxError.commitUncertain {
            uncertainIntent = intent
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
    }

    private func reconcileTransfer(
        _ intent: UncertainIntent,
        candidate: IOSAcceptedHistoryOutboxCandidate,
        current: IOSAcceptedHistoryOutboxJournalSnapshot?
    ) throws -> IOSAcceptedHistoryOutboxReceipt {
        guard case .transfer(let intendedCandidate) = intent.operation,
              candidate == intendedCandidate else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }

        if let current,
           current.envelope == intent.outcome.envelope {
            return try publish(
                intent.outcome,
                source: .existing(current),
                operation: intent.operation
            )
        }

        let sourceStillCurrent: Bool = switch (intent.source, current) {
        case (.missing, .none): true
        case (.existing(let source), .some(let current)): source == current
        default: false
        }
        guard sourceStillCurrent else {
            uncertainIntent = nil
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }

        let temporalSnapshot = try currentTime()
        do {
            try requireLive(candidate.entry, at: temporalSnapshot)
            if let current {
                try requireNoRollback(
                    in: current.envelope,
                    at: temporalSnapshot
                )
            }
        } catch IOSAcceptedHistoryOutboxError.expired {
            uncertainIntent = nil
            throw IOSAcceptedHistoryOutboxError.expired
        }

        switch intent.source {
        case .missing:
            return try publish(
                intent.outcome,
                source: .missing,
                operation: intent.operation
            )
        case .existing:
            guard let current else {
                uncertainIntent = nil
                throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
            }
            return try publish(
                intent.outcome,
                source: .existing(current),
                operation: intent.operation
            )
        }
    }

    private func reconcileConfirmation(
        _ intent: UncertainIntent,
        entry: IOSAcceptedHistoryOutboxEntry,
        current: IOSAcceptedHistoryOutboxJournalSnapshot?
    ) throws -> IOSAcceptedHistoryOutboxReceipt {
        guard intent.operation.entry.hasSameImmutableBytes(as: entry) else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        if let current,
           current.envelope == intent.outcome.envelope,
           current.envelope.entries.contains(where: {
               $0.hasSameImmutableBytes(as: entry)
           }) {
            return try publish(
                intent.outcome,
                source: .existing(current),
                operation: intent.operation
            )
        }

        let sourceStillCurrent: Bool = switch (intent.source, current) {
        case (.missing, .none): true
        case (.existing(let source), .some(let current)): source == current
        default: false
        }
        if sourceStillCurrent {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }

        if current?.envelope != intent.outcome.envelope {
            uncertainIntent = nil
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        throw IOSAcceptedHistoryOutboxError.commitUncertain
    }
}
